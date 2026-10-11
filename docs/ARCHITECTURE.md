# Architecture

## Overview

```
                     ┌───────────────────────────────────┐
  Claude Code ───────┤  HTTP (MCP Streamable)            │
  Claude Desktop ────┤                                   │
  other MCP client ──┤   Delphi IDE Remote MCP Server    │
                     │  ┌─────────────────────────────┐  │
   (no switch =      │  │ MCP layer (tools, routing)  │  │
    stdio, for       │  ├─────────────────────────────┤  │
    per-session      │  │ Workspace Manager           │  │  one supervised DelphiLSP
    clients)         │  │  spawn / warm / queue       │  │  per workspace, kept alive
                     │  ├─────────────────────────────┤  │  between agent sessions
                     │  │ Config Fabricator           │  │  .dproj → LSP settings when
                     │  │                             │  │  no fresh .delphilsp.json
                     │  ├─────────────────────────────┤  │
                     │  │ LSP Client                  │  │  JSON-RPC framing, retries,
                     │  │                             │  │  encoding-safe didOpen
                     │  └─────────────────────────────┘  │
                     │  Host: service / terminal / tray  │
                     └───────────────┬───────────────────┘
                                     │ stdio (LSP JSON-RPC)
                             ┌───────▼────────┐
                             │ DelphiLSP.exe  │  controller + agent + linter
                             │ (RAD Studio)   │  (same topology the IDE uses)
                             └────────────────┘
```

## Layers

| Layer | Responsibility |
|---|---|
| **MCP layer** | Tool registration/dispatch, MCP handshake, Streamable HTTP + stdio transports |
| **Workspace Manager** | Lifecycle of one DelphiLSP per workspace: spawn on first request, keep warm, request queue (the LSP agent is single-request). An engine nobody uses for `[Server] EngineIdleMinutes` is stopped, and one that hangs - something in flight, no message, no CPU and no I/O for 20 s, and no answer when asked - is stopped and replaced at the next request (1.8.0). With `[Server] MaxEngines`, an engine past the cap stops the least recently used one that is not working (1.13.0) |
| **Config Fabricator** | Locate RAD Studio via registry (newest with DelphiLSP unless the server pins `[Server] DelphiVersion` - one server, one Delphi); use project's `.delphilsp.json` if fresh; otherwise generate settings from the `.dproj` (search paths, defines, platform, namespaces) |
| **LSP Client** | `Content-Length` framing over child stdio, request/response correlation, retry with escalating delays (indexing returns `-32800 Request removed`), document sync (`didOpen` with correct encoding) |
| **Host** | ONE executable, three modes of the same core: Windows Service (headless, `-install`), terminal (stdio, or `--http`) and VCL tray (live log). All three share `Lsp.Host`, which builds the managers, the single access gate and its outbound filter — never copied per mode. **The service must log on as the user who owns the IDE** — RAD Studio's configuration lives in `HKEY_CURRENT_USER`, so under `LocalSystem` the server starts and answers with no Library Search Path and no registered packages. See the README and `settings.example.ini`. |

## Why a resident service (and not per-session stdio)

Measured on a real ~12k-line unit: DelphiLSP takes seconds to index after `didOpen` and holds ~550 MB per agent. A per-session stdio MCP pays that cost on **every** agent session. A resident service:

- keeps indexes **warm across sessions** and across multiple concurrent AI clients;
- keeps the engine's copy of every open document in step with the disk: DelphiLSP reads a unit from disk only while nobody has it open, and never re-reads one it has open (measured 2026-09-30), so before every question the server sends `didChange` for each open document whose disk stamp moved — the one asked about and the others alike — and `didClose` for one whose file is gone or that nobody has asked about for `[Server] EngineIdleMinutes` (30 by default), so the open set, and what each request pays to keep it in step, stays bounded (`TSessionClient.Refresh`);
- stops an engine that may be working the way the protocol asks — `shutdown`, its answer, then its input closed — because one whose input is just closed under a request in flight dies of an access violation (measured 2026-09-30; an engine that was never handed out has its input just closed, which measured clean), and writes to its own log how an engine ended when it was not clean or did not answer;
- sets the no-dialog error mode on each child it launches — engines, builds, git, test executables, adb, and through its launcher the program a remote run starts on a Windows target — because a crashed child's dialog would wait for nobody;
- keeps the engines' life with a sweeper thread: the ones nobody uses are stopped, and the hung ones - asked first: a healthy engine answers nothing to a request it cannot parse - are stopped and replaced (1.8.0). A cap on warm engines is `[Server] MaxEngines`: past it, the least recently used one stops (1.13.0).

Running with no switch (stdio) remains available for clients that cannot speak HTTP; it simply hosts the same core with session lifetime.

## DelphiLSP operating modes (per Embarcadero docs, verified)

- `agent` — single process, language features, **no diagnostics**. Default.
- `linter` — single process, **only** diagnostics (`publishDiagnostics`).
- `controller` + `agentCount=2` — spawns 1 agent + 1 linter and **supervises/replaces them if they die**. Same topology as the IDE. **This is the mode the Workspace Manager uses** — process babysitting comes for free.

## The `references` gap

DelphiLSP does **not** implement `textDocument/references` nor `workspace/symbol` (verified: `-32601 Method not found`). The `delphi_references` tool is therefore a hybrid:

1. Text-scan the workspace for candidate identifier occurrences (respecting Delphi case-insensitivity, skipping IDE artifacts like `__history/`).
2. For each candidate, ask DelphiLSP `definition` at that exact position.
3. Keep only candidates whose definition resolves to the target symbol's location — homonyms are eliminated by the compiler engine itself.

Result quality is compiler-grade; cost is one `definition` round-trip per candidate (batched, cached). A future LSIF-based path (RAD Studio 13 added LSIF generation to the LSP engine) may replace the scan.

## Encoding rules

Legacy Delphi sources are frequently Windows-1252 while LSP mandates UTF-8 JSON. `didOpen` reads: BOM → honor it; no BOM → UTF-8 when the bytes are valid UTF-8, else the machine's ANSI code page (as the IDE and the compiler read it). The LSP client never writes sources back; the editing tools do, through their own engine.

## Build tool

`delphi_build` shells out to MSBuild (`rsvars.bat` located via the same registry discovery) and returns structured compiler output. Compilation is intentionally **not** attempted through the LSP: the protocol has no build operation.

## Design points

The README lists them in one line each; here they are with their measurements and their history.

- **Zero hardcoded paths** — RAD Studio installation (11/12/13+) is discovered via the Windows registry.
- **Project config made automatic** — uses the IDE-generated `.delphilsp.json` when fresh, and can **fabricate one from the `.dproj`** when absent or stale (validated experimentally).
- **Warm processes** — one `DelphiLSP` (controller + agents; DelphiLSP replaces its own dead/hung children) per workspace, kept alive between agent sessions and refreshed against disk on each use. An engine nobody uses for `[Server] EngineIdleMinutes` (30 by default) is stopped, and the next request of its project starts another; one that hangs is stopped too — whoever was waiting on it gets `LSP-033` — and replaced the same way (1.8.0). How many engines stay warm at once can be capped with `[Server] MaxEngines`: past it, the least recently used one stops (1.13.0).
- **Correct source encoding** — BOM detection, strict UTF-8, and otherwise the machine's ANSI code page, as the IDE and the compiler read a file without BOM; legacy ANSI sources are not corrupted. On a Windows set to "Beta: Use Unicode UTF-8 for worldwide language support" the ANSI page IS UTF-8 (65001): an old ANSI source without BOM is read there with U+FFFD where its accents are (READ-007) and is not edited, which is how `dcc` would read it on that machine too - save it once in its real page, or with a BOM, on a machine that reads it right.
- **What a tool answers is what the agent sees** — tools reply in prose or in JSON, and both travel in the MCP `content`. `structuredContent` is published only when the answer IS a JSON object, or when a prose call FAILED (there it carries `ok`, a machine-readable `code` — `DENIED`, `NOT_FOUND`, `INVALID_PARAM`, `INTERNAL` — and the refusal text). A prose success publishes none: a client that understands the field shows it *instead of* `content`, so a status placeholder there made the real answer invisible (measured against production and fixed in v1.0.1-beta). A refusal carried INSIDE a JSON object gets the same treatment since v1.0.4-beta: the object's `error` field decides, so `ok` is never `true` on a refusal, whatever the tool put there.
- **Every message says what it is and how it ended** (v1.7.0). Every refusal, failure and note of the server STARTS with a tag: `[CFG-058]` for a success message or a note, `[EDIT-093 NOT_FOUND]` for a refusal (a listing or a file's content carries none; a JSON answer carries it in its `error` field). The outcome — `INVALID_PARAM` (the call itself is malformed: fix it and repeat), `NOT_FOUND` (the call is right but what it names is not there), `DENIED` (a rule refuses it or something stands in the way: the same call will fail again, do what the reason says), `INTERNAL` (the server broke or misses a piece: report it) — is the same `code` that `structuredContent` carries, and it is DECLARED by the code that writes the message: the server never guesses it by reading the text, so rewording a message cannot change a result. The id stays when the wording changes, so an agent or a test recognizes a message by its id, not by its phrase. Every text lives in one catalog (`src/Server/Lsp.Texts.pas`, and `src/DesktopNode/Mld.Textos.pas` for the programs that run on the target) and goes out through one helper; the product speaks English.
- **"It isn't there" and "it isn't that kind of thing" are different answers** (v1.0.4-beta). A folder handed to `delphi_read`, a file handed to `delphi_list`, a markdown file handed to `delphi_build`: each says what the path actually is and which tool handles it, instead of reporting it missing. And the outcome follows rule 11 — a path that is simply not there is `NOT_FOUND` ("correct it and repeat"), never `DENIED` (a rule refuses it: the same call fails again); and a path of the wrong kind is `INVALID_PARAM`.
- **Byte fidelity beats the drive mask** (v1.0.4-beta). Server drive letters leave as virtual units (`D:\` → `srvd:\`) in every textual result, EXCEPT where the text is file content an agent will copy as an edit anchor: `delphi_read`, `delphi_search` hits, the vault readers, and the verification echo of `delphi_edit` / `delphi_textedit`. Those tools mask their own paths instead (since 1.15.0 the folder of a list, `dir`, is masked by the one organizer of file lists). A mask that rewrites the line you are about to anchor on guarantees the anchor cannot match. Since 1.9.0 the same goes for the lines of content of `delphi_git` `diff` / `show` / `log` (those that start with `+`, `-` or a space): a `'Z:\x'` in a string literal came out `'srv0:\x'`. The lines that are git's are masked as before. `delphi_docs` (1.10.0) is exempt for another reason: its text is the installed help, whose examples cite paths that are not this server's (`TPath.Combine('E:\somewhere', ...)` came out `'srv0:\somewhere'`, and the documentation of what Combine does with each path made no sense). What it composes itself carries no path, and the query and section it echoes are masked.
- **Pascal text is read by one lexicon** (1.10.0). What is code, a string, a comment or a directive is decided in one unit, `Lsp.Pascal`, and every tool that reads Pascal asks it - the `uses` writer, `insert`, the rename of a unit, `delphi_references`, the `delphi_symbols` digest, the designer's binding report, test discovery - in a view of the text with the same length and line breaks, so what is found in the view is in the same place in the file. Until then about a dozen readers each knew a piece of the rule, and a probe measured nine faults in four tools; two of them wrote INSIDE a comment and said the job was done. Two reviewers before the tag found the places that census had missed - the `CreateForm` of a `.dpr`, a directive behind a `uses` entry that a rename dropped, a line that ends inside a comment, the digest, the rename of a symbol - and they ask the same lexicon now. A symbol rename, like a unit rename, rewrites code only, never a comment.
- **The jail is measured on where a path really goes** (v1.0.5-beta). Not on what it is called: a junction or a symlink inside a root used to escape it for reading *and* for writing, because the check validated the path as text while the file system followed the link. A `git clone` with `core.symlinks` was enough to plant one without leaving the MCP. Boundaries are now decided on the resolved destination. Two corners of the same rule fell in v1.0.13-beta, both found by audit and both measured with real junctions: the ReadOnlyPaths pardon re-checked the path as TEXT and forgave the very refusal the link check had just produced (pardons went by the refusal's *reason* from then on; since 1.7.4 there is no pardon to get right: reading is one question, `JaulaDenegada`, and the write rules - a reference, `ReadOnlyPaths`, the confinement - are added after it in `PathDenied`), and every recursive delete - the startup purge included - followed a junction and deleted on the other side, because the RTL's recursive delete never looks at the reparse bit. There is one tree deleter now, and a link falls as an entry: its target is never looked at.
- **A batch of edits answers with what happened, not with what you asked for** (v1.0.5-beta). Every entry comes back with the resulting line re-read from disk, the same evidence a single edit has always returned — and `occurrence` inside a batch is resolved once against the ORIGINAL file and then dragged as earlier entries add or remove lines, which is what its description always promised and did not do.

The server is one executable in three modes: see the **Host** row of [Layers](#layers).

## What this document does not cover

Beyond the design points above, this document describes the LSP core only. The guard gate, the editing engine, MSBuild, the PAServer/adb chain, the desktop node, the run-job launcher and the vault are described in the README, in [CONFIGURATION.md](CONFIGURATION.md) and in [TOOLS.md](TOOLS.md).
