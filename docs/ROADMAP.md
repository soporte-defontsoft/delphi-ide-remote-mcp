# Roadmap

## Phase 0 — Foundations (design ✔ / decisions)
- [x] Validate DelphiLSP capabilities end-to-end (see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md))
- [x] Architecture (see [ARCHITECTURE.md](ARCHITECTURE.md))
- [ ] Decide MCP plumbing: adopt an existing Delphi MCP framework vs. minimal own implementation
- [ ] CI-less build script (`BuildWithParams`-style) and test project fixtures

## Phase 1 — LSP core (console, no MCP yet)
- [ ] `Lsp.Transport.Process`: spawn DelphiLSP, Content-Length framing, reader thread, clean shutdown
- [ ] `Lsp.Client`: initialize (controller+2), didChangeConfiguration(settingsFile), didOpen (encoding-safe), request/response correlation, retry on `-32800`
- [ ] Console harness reproducing the validation battery (hover, definition intra/cross-unit, documentSymbol, diagnostics)

## Phase 2 — MCP stdio minimum
- [ ] Tools: `delphi_definition`, `delphi_hover`, `delphi_symbols`, `delphi_completion`
- [ ] Auto-didOpen with per-document cache
- [ ] Verified against Claude Code (stdio MCP registration)

## Phase 3 — Config Fabricator
- [ ] RAD Studio discovery via registry (multi-version, pick highest / configurable)
- [ ] Use project `.delphilsp.json` when fresh; detect staleness (paths, dll version)
- [ ] Fabricate settings from `.dproj` (search paths, defines, platform, namespaces)

## Phase 4 — The value tools
- [ ] `delphi_diagnostics` (linter mode; per-file on-demand lint)
- [ ] `delphi_references` (hybrid: candidate text scan → `definition` validation → compiler-grade result)
- [ ] `delphi_build` (MSBuild via registry-located `rsvars.bat`, structured output)

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
