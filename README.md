# DelphiLSP MCP Service

A Model Context Protocol (MCP) server that gives AI agents **real semantic understanding of Delphi code**, powered by Embarcadero's official `DelphiLSP.exe` — the same engine behind Code Insight in the RAD Studio IDE.

Runs as a **resident Windows service (or GUI app)** that keeps language-server indexes warm across agent sessions, serving multiple AI clients (Claude Code, Claude Desktop, or any MCP client) over Streamable HTTP — with a classic stdio mode as well.

> **Status: BETA.** Functional and covered by 100+ end-to-end checks against DelphiLSP 37.0 (RAD Studio 13), but young: expect rough edges and breaking changes between minor versions. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DELPHILSP-NOTES.md](docs/DELPHILSP-NOTES.md) for the measured research this project is built on, and [CHANGELOG.md](CHANGELOG.md) for versions.

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
| `delphi_build` | Real MSBuild builds with structured errors/warnings |
| `delphi_run` | Run a built executable on the server and capture its output (jailed to the roots, no shell, hard timeout) |
| `delphi_fetch` | Download files from the server in base64 chunks with whole-file SHA-256 — "get the deploy" to run GUI apps on the client machine |
| `delphi_upload` | The mirror of fetch: send files TO the server in chunks, SHA-256 verified — for binaries you cannot recreate by editing |
| `delphi_search` | Recursive literal search, IDE artifacts skipped |
| `delphi_list` | Recursive file listing with size/mtime; `dirs=true` browses subdirectories explorer-style |
| `delphi_projects` | Locate projects (.dproj/.groupproj) by name under a root or under the configured workspace roots (`settings.ini [Workspace] Roots=D:\Projects;E:\More`) |
| `delphi_installs` | List every RAD Studio/Delphi installation discovered on the machine (side-by-side versions), flagging which one is active for the LSP engine |
| `delphi_workspace` | The lay of the land on the server: the configured workspace roots (your allowed universe), the access level, and the active Delphi. Server paths travel with **virtual drive units** (`srvd:`, `srvc:` — they only exist inside this MCP, never on your local disk). Call it first |
| `delphi_git` | Whitelisted git operations — including **`clone`/`pull`** (bring a whole repo onto the server in one call, jailed) plus status/diff/log/show/branch/add/commit/init/push/tag/config. Options that write files or read outside the repo (`--output`, `--no-index`, `-c`…) are refused at the gate |
| `delphi_report` | **Feedback channel**: the agent reports a bug, limitation or suggestion and the server files it as its own dated markdown in `reports/` next to the executable. Works at **every** access level, read-only included |

## Quickstart

**Local (stdio)** — register in Claude Code on the Windows machine:

```bash
claude mcp add delphi -- C:/path/to/DelphiLspMcp.exe
```

**Remote (Streamable HTTP)** — run on the Windows machine that owns RAD Studio (console `DelphiLspMcp --http 3000`, or the tray app `DelphiLspMcpTray`, which starts minimized to the tray), set a token, and register from any client machine (Linux included):

```bash
claude mcp add --transport http delphi http://WINDOWS-HOST:3000/mcp --header "Authorization: Bearer YOUR_TOKEN"
```

Per-client configuration snippets (Claude Code, Claude Desktop, OpenCode, custom agents): see [docs/CLIENTS.md](docs/CLIENTS.md).

### Configuration (`settings.ini` next to the exe, or environment variables)

```ini
[Server]
Port=3000                               ; HTTP listen port (default 3000)

[Security]
AuthToken=your-long-random-token        ; full read-write  (or DELPHI_MCP_TOKEN)
ReadOnlyToken=another-random-token      ; read-only access (or DELPHI_MCP_READONLY_TOKEN)
AnonymousReadOnly=0                     ; 1 = no token -> read-only access

[Workspace]
Roots=D:\Projects;E:\MoreProjects       ; or DELPHI_MCP_ROOTS env var
```

- **Port**: used by both the console `--http` mode and the tray app. A port given on the
  command line (`DelphiLspMcp --http 3900`) overrides the ini for that run.
- **AuthToken**: full access. Every HTTP request must carry `Authorization: Bearer <token>`
  or gets 401 (when any token is configured).
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
  accept the RAD Studio installation and the IDE Library Search Path directories — so an
  agent can follow a definition into `System.SysUtils.pas` or read an installed component's
  source. Writing tools can never touch that zone. The Config Fabricator also merges the IDE
  Library Search Path, so symbols of installed (third-party) components resolve.

## Tests

`tests/` contains six end-to-end batteries that talk real MCP to the built server (221 checks, byte-level verification for the editing tool): `test_delphi_patch.py`, `test_workspace_tools.py`, `test_http_auth.py` (auth, configurable port, read-only access level), `test_scaffold.py` (scaffolds console/VCL/FMX projects and builds them for real), `test_guard.py` (workspace jail, including escape attempts) and `test_v012.py` (virtual drive units round trip, delete/blank modes, `.dpr` inserts, implicit published, git messages via `-F`, Roots fail-closed parsing).

## Key design points

- **Zero hardcoded paths** — RAD Studio installation (11/12/13+) is discovered via the Windows registry.
- **Project config made automatic** — uses the IDE-generated `.delphilsp.json` when fresh, and can **fabricate one from the `.dproj`** when absent or stale (validated experimentally).
- **Warm indexes** — one supervised `DelphiLSP` (controller + agents) per workspace, kept alive between agent sessions. LRU eviction and idle shutdown are configurable.
- **Correct source encoding** — BOM detection with configurable ANSI fallback; legacy CP1252 sources are not corrupted.
- **Dual host** — same core runs as a Windows service (headless) or as a VCL GUI app (live log, workspace monitor).

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
