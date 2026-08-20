# Roadmap

## Phase 0 — Foundations (design ✔ / decisions)
- [x] Validate DelphiLSP capabilities end-to-end (see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md))
- [x] Architecture (see [ARCHITECTURE.md](ARCHITECTURE.md))
- [ ] Decide MCP plumbing: adopt an existing Delphi MCP framework vs. minimal own implementation
- [ ] CI-less build script (`BuildWithParams`-style) and test project fixtures

## Phase 1 — LSP core (console, no MCP yet) ✔
- [x] `Lsp.Transport.Process`: spawn DelphiLSP, Content-Length framing, reader thread, clean shutdown
- [x] `Lsp.Client`: initialize, didChangeConfiguration(settingsFile), didOpen (encoding-safe), request/response correlation, retry on `-32800`
- [x] Console harness reproducing the validation battery (5/5 PASS on a real-world project)

## Phase 2 — MCP stdio minimum ✔
- [x] Tools: `delphi_definition`, `delphi_hover`, `delphi_symbols`, `delphi_completion`
- [x] Auto-didOpen with per-document cache; warm per-project LSP clients
- [x] Verified against Claude Code (registered; CLI health check: Connected)

## Phase 3 — Config Fabricator ✔
- [x] RAD Studio discovery via registry (multi-version, pick highest)
- [x] Use project `.delphilsp.json` when fresh; detect staleness (dead project path, other compiler generation)
- [x] Fabricate settings from `.dproj` (search paths, defines, platform, namespaces) into a `%LOCALAPPDATA%` cache — user projects are never written to. Verified end-to-end: 5/5 battery and MCP hover on a project with no settings at all

## Phase 4 — The value tools ✔
- [x] `delphi_diagnostics` (linter mode; per-file on-demand lint via didChange re-lint)
- [x] `delphi_references` (hybrid: candidate text scan → `definition` validation → compiler-grade result; homonyms rejected, bounded work with explicit unverified leftovers)
- [x] `delphi_build` (MSBuild via registry-located `rsvars.bat`, structured errors/warnings + output tail)

## Phase 4.5 — Safe editing (`delphi_edit` + `delphi_read`) ✔
Port of an internally battle-tested safe-edit tool (30+ measured test rounds with several
LLMs), so that ANY model — large or small — can modify Delphi sources through the MCP
without corrupting them:
- [x] Single-full-line unique anchors (line-number hints on mismatch/repeats, atline tie-break), never whole-file rewrites
- [x] Strict encoding handling (CP1252/UTF-8±BOM detection with strict UTF-8 validation; characters that don't fit REJECT with the native Pascal literal alternative; mojibake-signature warnings)
- [x] Atomic writes + global edit lock; post-write audit re-read from disk (high-byte accounting, alien EOLs, corruption marks, `end.` structure, insert-inside-method heuristic)
- [x] Automatic pre-edit backups (`__delphi-patch/<day>/`, 15-day retention) with 2-step restore (loss preview first)
- [x] Hard rejection of binary designer files (TPF0), `__history/`/`__recovery/` artifacts
- [x] Semantic INSERT: `rutina-global` (tool picks the legal boundary) and `metodo` (tool writes BOTH halves: class declaration + qualified implementation)
- [x] `createunit`: standard IDE skeleton, never overwrites
- [x] `delphi_read`: encoding-correct numbered reads (the anchor source of truth)
- [x] Battery: 30/30 checks green over real MCP stdio, byte-level verification (tests/test_delphi_edit.py)

## Phase 5 — Resident service + GUI (the remote-work host)
Primary use case: the Windows machine (with RAD Studio) stays on as a server; agents connect
over MCP Streamable HTTP from anywhere — including Linux clients that have no access to the
Windows filesystem.
- [ ] Workspace Manager: multi-workspace, warm instances, request queue, LRU, idle shutdown, hang kill+respawn
- [x] Streamable HTTP transport (`--http [port]`) with **Bearer token auth** (DELPHI_MCP_TOKEN env var or settings.ini [Security] AuthToken; 5/5 battery: tests/test_http_auth.py). Recommended exposure: VPN only
- [x] Remote file toolset so a remote agent needs no share: `delphi_read` (encoding-aware), `delphi_search` (skips `__history/`, build dirs), `delphi_list` (12/12 battery: tests/test_workspace_tools.py)
- [x] `delphi_git`: whitelisted git operations (status, diff, log, show, branch, add, commit) with shell-metacharacter rejection — remote agents version their work without shell access
- [x] Hosts: ONE executable with three modes — Windows Service (`-install`/`-uninstall`, the switch baked into the registered ImagePath), terminal (stdio or `--http`) and VCL tray (starts minimized; the icon is the "it is running" indicator; menu: log, copy URL, exit). Wiring shared in `Lsp.Host`; verified install→start→serve→tool call→stop→uninstall

## Phase 6 — Publication
- [ ] English docs pass, config examples (Claude Code / Claude Desktop), demo project
- [ ] License note: requires user's own licensed RAD Studio (DelphiLSP.exe is not redistributed)
- [ ] GitHub release

## Research track (parallel)
- [ ] LSIF: how RAD Studio 13 generates indexes, whether they contain references, feasibility as a references backend
