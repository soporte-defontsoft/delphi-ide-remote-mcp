# DelphiLSP MCP Service

A Model Context Protocol (MCP) server that gives AI agents **real semantic understanding of Delphi code**, powered by Embarcadero's official `DelphiLSP.exe` — the same engine behind Code Insight in the RAD Studio IDE.

Runs as a **resident Windows service (or GUI app)** that keeps language-server indexes warm across agent sessions, serving multiple AI clients (Claude Code, Claude Desktop, or any MCP client) over Streamable HTTP — with a classic stdio mode as well.

> **Status: design phase.** Architecture validated end-to-end against DelphiLSP 37.0 (RAD Studio 13). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DELPHILSP-NOTES.md](docs/DELPHILSP-NOTES.md) for the measured research this project is built on.

## Why

AI agents working on Delphi codebases are usually limited to text search (grep). This server gives them **total control of Delphi and its projects from a remote machine** — understand, edit safely, verify and build, through the real compiler front-end.

## The tools

| Tool | What it does |
|---|---|
| `delphi_symbols` | Document symbol tree of a unit (classes, methods, sections) |
| `delphi_definition` | Compiler-grade go-to-definition, cross-unit, into RTL/VCL sources |
| `delphi_hover` | Type/signature of an identifier usage |
| `delphi_completion` | Code completion candidates |
| `delphi_references` | Find references (hybrid: text scan + per-candidate `definition` validation — homonyms rejected by the compiler engine) |
| `delphi_diagnostics` | Error Insight on demand: real compiler codes (E/W/H) with exact positions, no build |
| `delphi_read` | Encoding-correct numbered reads (CP1252 / UTF-8±BOM detected for real) |
| `delphi_edit` | **Safe editing**: one-line anchors, encoding preserved byte-for-byte, atomic writes, automatic backups + 2-step restore, semantic INSERT (global routine / method with both halves), TPF0 hard-reject, post-write audit |
| `delphi_create` | Scaffold NEW projects (console/VCL/FMX) and NEW forms (VCL/FMX) with IDE-equivalent skeletons — buildable immediately |
| `delphi_build` | Real MSBuild builds with structured errors/warnings |
| `delphi_run` | Run a built executable on the server and capture its output (jailed to the roots, no shell, hard timeout) |
| `delphi_fetch` | Download files from the server in base64 chunks with whole-file SHA-256 — "get the deploy" to run GUI apps on the client machine |
| `delphi_search` | Recursive literal search, IDE artifacts skipped |
| `delphi_list` | Recursive file listing with size/mtime; `dirs=true` browses subdirectories explorer-style |
| `delphi_projects` | Locate projects (.dproj/.groupproj) by name under a root or under the configured workspace roots (`settings.ini [Workspace] Roots=D:\Projects;E:\More`) |
| `delphi_git` | Whitelisted git operations (status/diff/log/show/branch/add/commit) |

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

### Security (`settings.ini` next to the exe, or environment variables)

```ini
[Security]
AuthToken=your-long-random-token        ; or DELPHI_MCP_TOKEN env var

[Workspace]
Roots=D:\Projects;E:\MoreProjects       ; or DELPHI_MCP_ROOTS env var
```

- **AuthToken**: every HTTP request must carry `Authorization: Bearer <token>` or gets 401.
- **Roots** are both discovery (`delphi_projects`) and a **jail**: with roots configured, every
  disk-touching tool (read/edit/create/build/lint/search/list/git/LSP) refuses paths outside
  them — including `..\` escapes and prefix cousins. No roots = unrestricted (local trusted
  mode). For remote exposure configure BOTH, and expose over VPN/LAN only.

## Tests

`tests/` contains five end-to-end batteries that talk real MCP to the built server (86 checks, byte-level verification for the editing tool): `test_delphi_patch.py`, `test_workspace_tools.py`, `test_http_auth.py`, `test_scaffold.py` (scaffolds console/VCL/FMX projects and builds them for real) and `test_guard.py` (workspace jail, including escape attempts).

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
**Programmed by Claude** (Anthropic's Claude Code, model Claude Fable 5) working as the
implementing engineer under David's direction — every commit carries its co-author tag.
The safe-editing tool ports an internally battle-tested design measured over 30+ test
rounds against several LLMs.

Related projects worth knowing: [GDK Software's Delphi MCP framework](https://github.com/gdksoftware/delphi-mcp-server)
(vendored here, MIT), the official [DelphiLSP VS Code extension](https://marketplace.visualstudio.com/items?itemName=EmbarcaderoTechnologies.delphilsp),
and [EditInVsCodeDelphiPlugin](https://github.com/csm101/EditInVsCodeDelphiPlugin).

## License

MIT — see [LICENSE](LICENSE).
