# DelphiLSP MCP Service

A Model Context Protocol (MCP) server that gives AI agents **real semantic understanding of Delphi code**, powered by Embarcadero's official `DelphiLSP.exe` — the same engine behind Code Insight in the RAD Studio IDE.

Runs as a **resident Windows service (or GUI app)** that keeps language-server indexes warm across agent sessions, serving multiple AI clients (Claude Code, Claude Desktop, or any MCP client) over Streamable HTTP — with a classic stdio mode as well.

> **Status: design phase.** Architecture validated end-to-end against DelphiLSP 37.0 (RAD Studio 13). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DELPHILSP-NOTES.md](docs/DELPHILSP-NOTES.md) for the measured research this project is built on.

## Why

AI agents working on Delphi codebases are usually limited to text search (grep). This server lets them ask the *real* compiler front-end instead:

- *What is this symbol?* → `delphi_hover`
- *Where is it defined / implemented?* → `delphi_definition`
- *What is the structure of this unit?* → `delphi_symbols`
- *Does this code have errors right now?* → `delphi_diagnostics` (Error Insight via LSP linter mode — no build needed)
- *Who uses this method?* → `delphi_references` (hybrid grep + definition-validation, since DelphiLSP does not implement LSP `references`)
- *Build it for real* → `delphi_build` (MSBuild)

## Key design points

- **Zero hardcoded paths** — RAD Studio installation (11/12/13+) is discovered via the Windows registry.
- **Project config made automatic** — uses the IDE-generated `.delphilsp.json` when fresh, and can **fabricate one from the `.dproj`** when absent or stale (validated experimentally).
- **Warm indexes** — one supervised `DelphiLSP` (controller + agents) per workspace, kept alive between agent sessions. LRU eviction and idle shutdown are configurable.
- **Correct source encoding** — BOM detection with configurable ANSI fallback; legacy CP1252 sources are not corrupted.
- **Dual host** — same core runs as a Windows service (headless) or as a VCL GUI app (live log, workspace monitor).

## Requirements

- Windows
- A **licensed installation of RAD Studio / Delphi 11+** (`DelphiLSP.exe` ships with it and is **not redistributable** — this project does not include or replace it)

## License

MIT — see [LICENSE](LICENSE).
