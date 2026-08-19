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

## Phase 4 — The value tools
- [ ] `delphi_diagnostics` (linter mode; per-file on-demand lint)
- [ ] `delphi_references` (hybrid: candidate text scan → `definition` validation → compiler-grade result)
- [ ] `delphi_build` (MSBuild via registry-located `rsvars.bat`, structured output)

## Phase 4.5 — Safe editing (`delphi_patch`)
Port of an internally battle-tested safe-edit tool (30+ measured test rounds with several
LLMs), so that ANY model — large or small — can modify Delphi sources through the MCP
without corrupting them:
- [ ] Single-full-line unique anchors (with real-line hint on mismatch), never whole-file rewrites
- [ ] Strict encoding validation (CP1252/UTF-8 BOM detection, mojibake rejection, byte-level round-trip)
- [ ] Atomic writes + per-file operation queue (anti-race)
- [ ] Automatic pre-edit backups with 2-step restore
- [ ] Hard rejection of binary designer files (TPF0), `__history/`/`__recovery/` artifacts

## Phase 5 — Resident service + GUI
- [ ] Workspace Manager: multi-workspace, warm instances, request queue, LRU, idle shutdown, hang kill+respawn
- [ ] Streamable HTTP transport (localhost by default)
- [ ] Dual host: Windows service + VCL GUI monitor (log, workspaces, memory, manual reload)

## Phase 6 — Publication
- [ ] English docs pass, config examples (Claude Code / Claude Desktop), demo project
- [ ] License note: requires user's own licensed RAD Studio (DelphiLSP.exe is not redistributed)
- [ ] GitHub release

## Research track (parallel)
- [ ] LSIF: how RAD Studio 13 generates indexes, whether they contain references, feasibility as a references backend
