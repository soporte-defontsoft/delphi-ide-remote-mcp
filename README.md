# Delphi IDE Remote MCP Server

**An MCP server that remote-controls a full RAD Studio (Delphi IDE) installation — language server, build system, deploy chain — so you can develop in Delphi from any platform.**

The Windows machine holds RAD Studio and the projects. You work from wherever you actually want to be: a Linux laptop, a Mac, a cloud agent, a CI runner. Understand the code, edit it safely, scaffold, build, run, package, fetch the binaries, commit — the whole cycle over MCP, with Delphi installed on **neither** the client nor the agent.

It is not a language-server bridge. Semantic understanding is one capability of many, and it is the one that is genuinely hard, so it runs on Embarcadero's official `DelphiLSP.exe` — the same engine behind Code Insight in the RAD Studio IDE. But the language server backs **7 of the 29 tools**; the other 22 are the working day: the safe editing engine, MSBuild, git, the file tools, the project scaffolder, the deploy chain (PAServer, adb), the knowledge vault. See [What each tool actually runs on](#what-each-tool-actually-runs-on) for the exact split.

Runs as a **Windows Service**, a terminal process or a tray app — one executable, three modes — keeping language-server processes warm across agent sessions and serving multiple AI clients (Claude Code, Claude Desktop, or any MCP client) over Streamable HTTP, with a classic stdio mode as well.

> **Status: BETA.** Functional and covered by over 540 end-to-end checks against DelphiLSP 37.0 (RAD Studio 13), but young: expect rough edges and breaking changes between minor versions. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DELPHILSP-NOTES.md](docs/DELPHILSP-NOTES.md) for the measured research this project is built on, and [CHANGELOG.md](CHANGELOG.md) for versions.

## Why

AI agents working on Delphi codebases are usually limited to text search (grep). This server gives them **total control of Delphi and its projects from a remote machine** — understand, edit safely, verify and build, through the real compiler front-end.

**The core idea: centralize Delphi, work from anywhere.** One Windows PC or VM holds the RAD Studio installation and the projects; this server runs there. Everything else — your laptop, a Linux box, a CI runner, an agent in the cloud — connects over MCP HTTP and gets the full development cycle (locate a project, read, edit, scaffold, build, run, download the binaries, commit) **without installing Delphi, or anything at all, on the client side**.

## Use cases

Two credential levels — a full read-write token, and a read-only one (or anonymous read-only for tokenless clients) — let very different agents share the same live codebase safely. The read-only level can read, search, navigate symbols, get diagnostics, follow definitions into RTL/VCL and installed components, download files and run query-only git; it can touch **nothing** on the server. That opens up a range of setups:

- **Move your daily work to another OS.** The Windows box with RAD Studio becomes a remote build server; you drive it from a Linux laptop, a Mac, or a cloud agent. Full read-write token, VPN/LAN only. Edit, scaffold, build, run, fetch the binaries, commit — Delphi never leaves the server.
- **A documentation / wiki / RAG agent that cross-checks the real source.** Give it the read-only token. It maintains the wiki or answers questions from a RAG index, and whenever it needs to be sure, it confirms the claim against the actual code — "does `TOrderService.Post` really validate the tax id?" — instead of trusting a possibly-stale document. Grounded answers, zero write risk.
- **A code-review / audit agent on every branch.** Read-only. It reads diffs, walks symbols with compiler-grade accuracy, follows calls cross-unit and into VCL, runs on-demand diagnostics (real E/W/H codes, no build) — and cannot alter the tree it is reviewing.
- **An onboarding / Q&A assistant for the team.** Read-only, pointed at the whole `Roots`. New developers ask "where is X handled, what calls Y, what's the type of Z" and get answers from the live sources, not a wiki that drifts.
- **The programming agent + the reviewing agent, side by side.** One holds the read-write token and does the work; another holds the read-only token and independently checks it — two agents, one codebase, only one able to write.
- **A CI / release runner.** Read-write on a locked-down VM: pull, build Release, package the deploy, upload/fetch artifacts, tag — all over MCP, no interactive IDE.

An agent can also be pointed at the **library read zone** (RTL/VCL sources and installed third-party components) to reason about framework or component internals, still without any write capability.

## What each tool actually runs on

The language server is the hardest part to get right, but it is not most of the server. Of the 28 core tools, **exactly 7 are backed by DelphiLSP**; the other 21 never touch it (plus 5 optional `vault_*` tools, registered only when you configure a vault). This matters in practice: the LSP-backed tools are the only ones that need a resolvable project configuration — the rest work on any folder inside the roots.

**Backed by DelphiLSP (7):** `delphi_symbols`, `delphi_definition`, `delphi_hover`, `delphi_completion`, `delphi_signature`, `delphi_diagnostics`, and `delphi_references` (hybrid — LSP-validated, see the table).

**NOT DelphiLSP (the other 21):** `delphi_read`, `delphi_edit`, `delphi_textedit`, `delphi_create`, `delphi_build`, `delphi_run`, `delphi_list`, `delphi_search`, `delphi_projects`, `delphi_workspace`, `delphi_move`, `delphi_delete`, `delphi_fetch`, `delphi_upload`, `delphi_package`, `delphi_git`, `delphi_installs`, `delphi_config`, `delphi_paserver`, `delphi_adb`, `delphi_report` — plus the 5 `vault_*` tools. These run on MSBuild, git, the filesystem, the registry, adb, the safe-editing engine and your vault.

The table below says which engine each one uses and why it matters:

| Engine | Tools | What that means for you |
|---|---|---|
| **DelphiLSP** (official, compiler-grade) | `delphi_symbols`, `delphi_definition`, `delphi_hover`, `delphi_completion`, `delphi_signature`, `delphi_diagnostics` | Real semantic answers, not grep: resolves inheritance, `with`, overloads, and follows into RTL/VCL. Needs a `.delphilsp.json` (used when fresh, fabricated from the `.dproj` when not). |
| **DelphiLSP + disk scan** (hybrid) | `delphi_references` | The LSP has no `references`, so candidates are scanned from disk and then each one is *validated* by asking the LSP where it resolves to. Verified against the live compiler, never an index. |
| **Own safe-editing engine** | `delphi_read`, `delphi_edit`, `delphi_textedit`, `delphi_create` | Anchored edits with encoding preserved (CP1252 vs UTF-8), atomic writes, automatic backups, designer-file awareness. No LSP involved. |
| **MSBuild** (`rsvars.bat`, located via the registry) | `delphi_build` | The real compiler and linker. The LSP cannot build — it has no such operation. |
| **The filesystem, jailed** | `delphi_list`, `delphi_search`, `delphi_projects`, `delphi_workspace`, `delphi_move`, `delphi_delete`, `delphi_fetch`, `delphi_upload`, `delphi_package` | Navigation, transfer and housekeeping inside the workspace roots. |
| **`git.exe`**, arguments composed by the server | `delphi_git` | Query commands at every level; writes only read-write. Never a shell. |
| **Registry / IDE configuration** | `delphi_installs`, `delphi_config`, `delphi_paserver` | Which RAD Studio versions exist, project platforms and output paths, remote-target profiles and SDKs. |
| **The IDE's own `adb`** (found via the SDK Manager's `.sdk` files) | `delphi_adb` | The Android devices hanging off the server — discover, attach, install, run, screenshot, tap, logcat — with the exact adb the IDE itself uses. |
| **The IDE's registry** (Known Packages — what the palette loads) | `delphi_components` | The design packages installed in the server's RAD Studio, whatever the install channel — what the agent has available to program with. List only; installing stays a human decision. |
| **A separate process, sandboxed** | `delphi_run` | Off by design (`AllowRun`): this is a compile server. |
| **Your Markdown vault** | `vault_read`, `vault_search`, `vault_append`, `vault_create`, `vault_patch` | Persistent memory, isolated from the code tools (see below). |
| **A folder the server owns** | `delphi_report` | The feedback channel back to us; the one write a read-only client may perform. |

## Persistent memory for your agents (optional)

Every session, your agent starts from zero. It can read your code, but it does
not know *why* that unit is built the way it is, which conventions your team
follows, what was already tried and rejected, or where a project stands today.
So you explain it again. And the next session, again.

Point `[Vault] Path` at a folder of Markdown notes — an Obsidian vault, or just
a folder — and that stops. The agent gets **`vault_read` and `vault_search`**:
a memory it consults before touching the code. Optionally (`ReadOnly=0`) it also
gets **`vault_append`, `vault_create` and `vault_patch`**, so it records what it
learned for the next session — and for the next agent.

This matters most in the remote setup this server exists for: an agent on Linux
has no filesystem access to the Windows machine at all, so without this its
memory is whatever fits in one conversation.

It works by itself. On connect the agent is told there is a vault and to start
with `vault_read` (no path); that one call returns the vault's **rules** and its
**index**, and from the index descriptions it loads only the notes that apply —
lazy loading, so a memory that grows for years still fits in a context window.

Two design choices worth knowing before you enable it:

- **The doctrine lives in the vault, not in this server.** Your rules are a file
  *inside* your vault (`AGENTS-VAULT.md`), so two people can point this at two
  different vaults and each gets their own conventions, in their own language.
  Nothing about your way of working is hardcoded here.
- **What can be enforced by code is enforced by the server**, not left to the
  model to remember: the original of any note is backed up before it changes,
  the rules and index files are never writable, and there is no rewrite, delete
  or move — only append, create and anchored replace. A confused model cannot
  destroy accumulated knowledge.

Off unless you configure it. Point it at an empty folder and the server creates
a working starter vault for you; there is also a ready-made one in
[`examples/vault/`](examples/vault/). **Full explanation: [docs/VAULT.md](docs/VAULT.md).**

## The tools

| Tool | What it does |
|---|---|
| `delphi_symbols` | Document symbol tree of a unit (classes, methods, sections) |
| `delphi_definition` | Compiler-grade go-to-definition, cross-unit, into RTL/VCL sources; `kind=declaration` jumps to the interface declaration of the target symbol (on call sites the tool chains definition→declaration, so you get the callee) |
| `delphi_signature` | Signature help for the call under the cursor (parameter names/types) — the IDE's Ctrl+Shift+Space |
| `delphi_hover` | Type/signature of an identifier usage |
| `delphi_completion` | Code completion candidates |
| `delphi_references` | Find references (hybrid: text scan + per-candidate `definition` validation — homonyms rejected by the compiler engine) |
| `delphi_diagnostics` | Error Insight on demand: real compiler codes (E/W/H) with exact positions, no build |
| `delphi_read` | Encoding-correct numbered reads (CP1252 / UTF-8±BOM detected for real) |
| `delphi_edit` | **Safe editing**: one-line anchors, encoding preserved byte-for-byte, atomic writes, automatic backups + 2-step restore, semantic INSERT (global routine / method with both halves — also inside a `.dpr`, and into the implicit published section of forms), line DELETE mode, TPF0 hard-reject, post-write audit; new units use the encoding configured in the IDE |
| `delphi_textedit` | Safe editing of **non-Delphi text files** (.md .html .js .css .py .ini ... any plain text): same anchor/encoding/backup/atomic discipline, so an agent can maintain docs, tests and web assets too |
| `delphi_create` | Scaffold NEW projects (console/VCL/FMX) and NEW forms (VCL/FMX) with IDE-equivalent skeletons — buildable immediately |
| `delphi_build` | Real MSBuild builds with structured errors/warnings; on success it declares the artifact it produced (`output`). `target=Deploy` compiles **and ships**: to the PAServer of the `profile` param on Linux/macOS, or assembling the **Android `.apk`** — the deployment manifest, manifest template and version fallbacks are generated when the project has none (the IDE's own files always win) |
| `delphi_run` | **OFF by default** — this is a compile-only server, it does not execute programs. Download the artifact (`delphi_package` + `delphi_fetch`) and run it on your machine, or deploy to a real target (PAServer / Android). An operator can opt in with `[Security] AllowRun=1` for CI console runners; even then it is jailed, no shell, hard timeout, and Low-integrity sandboxed |
| `delphi_fetch` | Download files from the server — "get the deploy" to run GUI apps on the client machine. Every answer carries a **`download` link** (`GET /files?path=...` on the same host, same Bearer, `X-File-SHA256` header): bytes travel as HTTP — a 70 MB installer is one `curl`. Base64 chunks inline remain for small files and clients without a shell; files over 4 MB answer with the link only unless `maxbytes<=1048576` is passed explicitly |
| `delphi_upload` | The mirror of fetch: send files TO the server in chunks, SHA-256 verified — for binaries you cannot recreate by editing |
| `delphi_search` | Recursive literal search, IDE artifacts skipped |
| `delphi_list` | Recursive file listing with size/mtime; `dirs=true` browses subdirectories explorer-style; IDE artifacts are filtered relative to the root and the result says how many entries it hid |
| `delphi_projects` | Locate projects (.dproj/.groupproj) by name under a root or under the configured workspace roots (`settings.ini [Workspace] Roots=D:\Projects;E:\More`) |
| `delphi_installs` | List every RAD Studio/Delphi installation discovered on the machine (side-by-side versions), flagging which one is active for the LSP engine |
| `delphi_workspace` | The lay of the land on the server: the configured workspace roots (your allowed universe), the access level, and the active Delphi. Server paths travel with **virtual drive units** (`srvd:`, `srvc:` — they only exist inside this MCP, never on your local disk). Call it first |
| `delphi_git` | Whitelisted git operations — including **`clone`/`pull`** (bring a whole repo onto the server in one call, jailed) plus status/diff/log/show/branch/add/commit/init/push/tag/config. Options that write files or read outside the repo (`--output`, `--no-index`, `-c`…) are refused at the gate |
| `delphi_report` | **Feedback channel**: the agent reports a bug, limitation or suggestion and the server files it as its own dated markdown in `reports/` next to the executable. Works at **every** access level, read-only included |
| `delphi_config` | See and manage a project's build **configurations, target platforms, output folder and search paths**: `view` reports framework/configs/platforms with status and the search paths per platform; `add-platform`/`remove-platform` enable/disable a platform in the `.dproj` (curated edit), refusing platforms the framework can't target (VCL is Windows-only); `set-output` puts every binary under one folder (e.g. `Compiled`); `add-searchpath`/`remove-searchpath` manage a platform's unit search path - the IDE's Project Options > Search path - creating the platform's property groups as the IDE would (the usual fix for "unit not found" on a newly added platform: its third-party components' folders are registered for the other platforms only); `add-deployfile`/`remove-deployfile` ship an extra file with the build on one platform - the IDE's Deployment Manager - for the native library a component loads at runtime |
| `delphi_paserver` | The bridge for building on **Linux/macOS** via the Platform Assistant: `platforms` (what the server can target + profile status), `packages` (the PAServer installers to download and run on the target), `profiles` (registered connection profiles/SDKs), `add-profile` (register a connection profile against a live PAServer - the password is stored encrypted by `paclient` itself), `test-connection` (full handshake against a profile, or a raw TCP reachability probe with `host`+`port` and no name), `get-sdk` (pull the platform SDK/sysroot from the live PAServer and register it - after this, `delphi_build` links for the platform) |
| `delphi_adb` | **Android devices for remote development** — the phones/tablets hang off the *server*, you program from anywhere: `discover` (devices announcing wireless debugging on the server's network, via mDNS, each with its `ip:port`), `devices` (what adb has attached — the IDE's deploy-target list), `connect`/`disconnect` (attach one over the network), `install` (put a built `.apk` on a device), `run` (launch the installed app — the IDE's "Deploy and Run"), `logcat` (bounded dump of the device log, optional filter), `screenshot` (the device screen to a PNG you then fetch — your remote **eyes**) and `tap`/`key` (touch and navigation keys — your remote **hands**): enough to deploy, drive and debug the app end to end. Uses the IDE's own Android SDK `adb`, discovered per install |
| `delphi_components` | **What the server has installed to program with**: every design package registered in the IDE (the list the palette loads), whatever the install channel — GetIt, vendor installers, manual. Description + `.bpl` per entry, disabled ones marked, optional `filter`. Read-only by design — no install (that stays a human decision); a missing library is reported with `delphi_report` |
| `vault_read` · `vault_search` | **Optional persistent memory** (off unless configured): read and search a vault of Markdown notes — your decisions, conventions and project context — so a remote agent starts with more than the source tree. Lazy loading: it bootstraps with the vault's own rules + index and pulls only the notes it needs |
| `vault_append` · `vault_create` · `vault_patch` | Let the agent **record what it learned** (opt-in, read-write credential only): append a log entry, create a note, replace an anchored fragment. No rewrites, no deletes, and the server always backs the original up first. See **[docs/VAULT.md](docs/VAULT.md)** |

**→ Full parameter-by-parameter reference with types, defaults and worked workflows: [docs/TOOLS.md](docs/TOOLS.md)** (generated from the server's own `tools/list`, so it never drifts from the code).

**→ Handing this server to an AI agent?** Give it [skills/cmcpdelphiide/SKILL.md](skills/cmcpdelphiide/SKILL.md) — a field-tested agent skill (drop it into the agent's skills folder or paste it as instructions) covering the path model, the safe-editing contract, the deploy chains and how to move files and logs the right way.

## Quickstart

**Local (stdio)** — register in Claude Code on the Windows machine:

```bash
claude mcp add delphi -- C:/path/to/DelphiLspMcp.exe
```

**Remote (Streamable HTTP)** — run it on the Windows machine that owns RAD Studio, set a token, and register from any client machine (Linux included):

```bash
claude mcp add --transport http delphi http://WINDOWS-HOST:3000/mcp --header "Authorization: Bearer YOUR_TOKEN"
```

### One executable, three ways to run it

| You want | Run | Notes |
|---|---|---|
| A local client to spawn it | `DelphiLspMcp.exe` | No switch: MCP over stdio. |
| The remote server, in a terminal | `DelphiLspMcp.exe --http 3000` | Ctrl+C stops it. Good for trying things out. |
| The remote server, permanently | `DelphiLspMcp.exe -install` | **How you should actually deploy it**: a Windows Service, started by the machine, with nobody logged in. Needs an elevated prompt; `-uninstall` removes it. |
| An eye on it while you work | `DelphiLspMcp.exe -gui` | Tray app: starts iconized, double-click for the live log. |

Each switch is accepted as `/x`, `-x` or `--x`. The service reads the same `settings.ini` next to the executable as every other mode.

Per-client configuration snippets (Claude Code, Claude Desktop, OpenCode, custom agents): see [docs/CLIENTS.md](docs/CLIENTS.md).

**Getting the best out of the server from an AI agent** — a model-facing guide (prefer semantic tools over text search, virtual paths, 0-based positions, safe editing): [docs/AGENT.md](docs/AGENT.md). Paste it into your agent's `CLAUDE.md` / `AGENTS.md`.

### Configuration (`settings.ini` next to the exe, or environment variables)

```ini
[Server]
Port=3000                               ; HTTP listen port (default 3000)

[Security]
AuthToken=your-long-random-token        ; full read-write  (or DELPHI_MCP_TOKEN)
ReadOnlyToken=another-random-token      ; read-only access (or DELPHI_MCP_READONLY_TOKEN)
AnonymousReadOnly=0                     ; 1 = no token -> read-only access
AllowRun=0                              ; 1 = allow delphi_run (jailed+sandboxed); default off
AllowBuildScripts=0                     ; 1 = allow build scripts (custom <Target>/<Exec>) WITHOUT delphi_run

[Workspace]
Roots=D:\Projects;E:\MoreProjects       ; or DELPHI_MCP_ROOTS env var

[Log]
LinesPerFile=2000                       ; tray log: persist a block every N lines (min 100)
MaxFiles=10                             ; rotation: keep the newest N block files
```

- **Port**: used by the service, the terminal `--http` mode and the tray app alike. A port given on the
  command line (`DelphiLspMcp --http 3900`) overrides the ini for that run.
- **BindIP** (`[Server] BindIP` or `DELPHI_MCP_BIND_IP`): listen on a single interface (e.g.
  your LAN/VPN address) instead of all of them — which also stops the firewall prompting
  twice (IPv4 + IPv6).
- **Firewall prompts every start?** Windows keys its prompts to the exe binary, so each
  rebuild looks new. Run `scripts/firewall-allow.ps1` **once as Administrator** to install a
  single durable rule keyed to the *port* (covers every rebuild) and clear the accumulated
  per-binary duplicates: `powershell -ExecutionPolicy Bypass -File scripts\firewall-allow.ps1 -Port 3131`.
- **AuthToken**: full access. Every HTTP request must carry `Authorization: Bearer <token>`
  or gets 401 (when any token is configured). **With NO credential configured at all, the
  server binds to `127.0.0.1` only** — an unconfigured server is never silently open to the
  network; remote access requires a token (or an explicit `AnonymousReadOnly=1`).
- **ReadOnlyToken**: a second credential for reviewer agents. It can read, search, navigate
  symbols, get diagnostics, download, run query git commands and file reports — but
  `delphi_edit`, `delphi_create`, `delphi_build`, `delphi_run`, `delphi_package`,
  `delphi_upload` and git write commands are refused. `AnonymousReadOnly=1` grants the same
  read-only level to tokenless requests. The whole classification is enforced at a **single
  gate** in front of every `tools/call` — including the git argument filter, so no option can
  turn a "read" command into a write. Audited by running the server anonymously and trying to
  escape.
- `--readonly` on the command line makes the entire process read-only, whatever the
  transport (useful for a stdio-registered reviewer).
- **AllowBuildScripts**: `delphi_build` refuses a project whose `.dproj` (or an imported
  `.targets`) carries a task that *executes a program or plants/deletes files* at build
  time — the compile-only guarantee, so an uploaded `.dproj` cannot run code through a
  planted `<Exec>`. An **inert** custom `<Target>` (a `<Message>`, a property) always
  builds. For a **trusted** project that legitimately signs (Authenticode via `<Exec>`) or
  copies at build time, set `AllowBuildScripts=1` — this permits its build scripts **without**
  enabling `delphi_run`. `AllowRun=1` implies it. Both off by default.
- **`[Adb] AllowedDevices`**: an allowlist for `delphi_adb` — `AllowedDevices=192.168.1.163;SERIAL123`
  (semicolon list; an IP entry covers whatever port wifi debugging negotiates, a USB serial is
  listed as-is). When configured, devices outside the list are refused at **both** access levels,
  and every device-addressing command must name its `device` explicitly (an implicit target could
  be an unlisted device that happens to be the only one attached). Absent = unrestricted, for a
  dev machine.
- **`[Log]`** (tray mode): the live log window keeps at most `LinesPerFile` lines in memory —
  on reaching the cap the block is saved to `logs\yyyymmdd-hhnnss.log` next to the exe and the
  window restarts at zero; rotation keeps the newest `MaxFiles` files. A controlled exit
  flushes the partial block, so the tail of a session survives for post-mortems. Memory is
  bounded end to end: the producer buffer caps at 5000 lines (beyond that, lines are counted
  and reported as dropped, never accumulated).
- **Roots** are both discovery (`delphi_projects`) and a **jail**: with roots configured, every
  disk-touching tool (read/edit/create/build/lint/search/list/git/LSP) refuses paths outside
  them — including `..\` escapes and prefix cousins. Paths with spaces need no quoting (the
  separator is `;`); quotes around a root are tolerated and stripped. If Roots is configured
  but no root parses valid, the server **fails closed** (everything refused) rather than
  silently running unrestricted. No roots = unrestricted (local trusted mode). For remote
  exposure configure BOTH, and expose over VPN/LAN only.
- **Virtual drive units**: the server's real drive letters never travel to the client — paths
  leave as `srvd:\...`, `srvc:\...` and are accepted back in the same form (real paths still
  work), so an agent can never mistake server paths for its own local disks. One generic rule
  at the dispatch gate covers every tool's output, compiler/git messages and 8.3 short forms
  included. Exception: successful `delphi_read`/`delphi_fetch` content is byte-exact by
  design and travels verbatim.
- **Library read zone**: READING tools (read/search/list/fetch/LSP navigation) additionally
  accept, for **every installed Delphi**, its installation directory, the Library Search Path
  of **every registered platform** (Win, Linux64, macOS, Android, iOS…) and the **GetIt
  catalog repositories** — so an agent can follow a definition into `System.SysUtils.pas`,
  read the source of an installed component (FMXLinux, LockBox…) or inspect the Android SDK.
  Macros like `$(BDSCatalogRepositoryAllUsers)` are expanded from the IDE's own registry
  table, never hardcoded. Writing tools can never touch that zone, and `delphi_workspace`
  reports it as `readableExtra`. The Config Fabricator also merges the IDE Library Search
  Path, so symbols of installed (third-party) components resolve.

## Tests

`tests/` contains eight end-to-end batteries that talk real MCP to the built server (468 checks, byte-level verification for the editing tool): `test_delphi_patch.py`, `test_workspace_tools.py`, `test_http_auth.py` (auth, configurable port, read-only access level), `test_scaffold.py` (scaffolds console/VCL/FMX projects and builds them for real), `test_guard.py` (workspace jail, escape attempts, argument-injection vectors), `test_v012.py` (virtual drive units round trip, delete/blank modes, `.dpr` inserts, implicit published, git messages via `-F`, Roots fail-closed parsing, argument typing), `test_vault.py` (the knowledge vault, including its governance rules) and `test_r9_concurrency.py` (simultaneous vault writers).

Each security fix is paired with the vector it closes **and** with a counter-test proving it did not over-tighten — a fix that refuses too much is a bug too.

## Key design points

- **Zero hardcoded paths** — RAD Studio installation (11/12/13+) is discovered via the Windows registry.
- **Project config made automatic** — uses the IDE-generated `.delphilsp.json` when fresh, and can **fabricate one from the `.dproj`** when absent or stale (validated experimentally).
- **Warm processes** — one `DelphiLSP` (controller + agents; DelphiLSP replaces its own dead/hung children) per workspace, kept alive between agent sessions and refreshed against disk on each use. (LRU eviction and idle-shutdown of idle workspaces are roadmap, not yet implemented — processes stay warm until the host exits.)
- **Correct source encoding** — BOM detection with configurable ANSI fallback; legacy CP1252 sources are not corrupted.
- **One executable, three modes** — Windows Service, terminal (`--http`/stdio) and VCL tray app (live log) are the same binary and the same 29 tools. They cannot drift: one project, one unit list, and the server itself is built once in `Lsp.Host` for all three.

## Requirements

- Windows
- A **licensed installation of RAD Studio / Delphi 11+** (`DelphiLSP.exe` ships with it and is **not redistributable** — this project does not include or replace it)

## Credits

Designed and directed by **David Fontanet ([Defontsoft](https://www.defontsoft.com))**.
**Programmed by Claude** working as the implementing engineer under David's direction, in
Anthropic's Claude Code.

Which Claude model actually did the work was *not* the author's choice. Anthropic's systems
swap the active model mid-session on their own — in this project's experience, every time
their content classifier trips over some word in an ordinary technical conversation — so the
model kept changing under our feet, often in the middle of a task. **Claude Fable 5, Claude
Opus 5 and Claude Opus 4.8** all took part for that reason, and all three are credited; every
commit carries its co-author tag.

The safe-editing tool ports an internally battle-tested design measured over 30+ test
rounds against several LLMs.

Related projects worth knowing: [GDK Software's Delphi MCP framework](https://github.com/gdksoftware/delphi-mcp-server)
(vendored here, MIT), the official [DelphiLSP VS Code extension](https://marketplace.visualstudio.com/items?itemName=EmbarcaderoTechnologies.delphilsp),
and [EditInVsCodeDelphiPlugin](https://github.com/csm101/EditInVsCodeDelphiPlugin).

## License

MIT — see [LICENSE](LICENSE).
