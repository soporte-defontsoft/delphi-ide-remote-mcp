# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [0.3.0] - 2026-08-19

First complete release: total control of Delphi and its projects from a
remote machine. Built and validated in a single day against DelphiLSP 37.0
(RAD Studio 13 "Florence").

### Added
- **16 MCP tools**: `delphi_symbols`, `delphi_definition`, `delphi_hover`,
  `delphi_completion` (official DelphiLSP engine); `delphi_diagnostics`
  (Error Insight on demand, no build); `delphi_references` (hybrid text scan
  + compiler validation, homonyms rejected); `delphi_read` / `delphi_edit`
  (safe editing: one-line anchors, byte-exact encoding preservation, atomic
  writes, backups + 2-step restore, semantic INSERT, TPF0 hard-reject);
  `delphi_create` (scaffold console/VCL/FMX projects and VCL/FMX forms,
  buildable immediately); `delphi_build` (real MSBuild); `delphi_run`
  (jailed execution with output capture); `delphi_fetch` (chunked artifact
  download with SHA-256); `delphi_search`, `delphi_list` (files and
  explorer-style dirs), `delphi_projects` (locator), `delphi_git`
  (whitelisted operations).
- **Three hosts**: stdio (local MCP clients), console `--http [port]`
  (Streamable HTTP), and `DelphiLspMcpTray` (starts minimized to tray).
- **Security**: Bearer token auth (`[Security] AuthToken` /
  `DELPHI_MCP_TOKEN`) and workspace jail (`[Workspace] Roots` /
  `DELPHI_MCP_ROOTS`) enforced on every disk-touching tool, with
  canonicalized paths (no `..\` escapes, no prefix cousins).
- **Config Fabricator**: project settings generated from the `.dproj` when
  no fresh `.delphilsp.json` exists (stale ones detected and ignored);
  RAD Studio located via the Windows registry (11/12/13+, no hardcoded paths).
- **Tests**: five end-to-end batteries speaking real MCP over stdio/HTTP,
  86 checks total, including byte-level encoding verification and building
  freshly scaffolded projects for real.

### Notes
- Requires a licensed RAD Studio / Delphi 11+ installation on the server
  machine (`DelphiLSP.exe` is not redistributed).
- MCP plumbing vendored from gdksoftware/delphi-mcp-server (MIT) with two
  documented local changes (see `vendor/gdk-mcp-server/VENDOR.md`).
