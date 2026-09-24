# `src/Server/` — the server itself

`DelphiLspMcp.dproj` is the Delphi IDE Remote MCP Server: 41 tools over stdio, HTTP
(`--http`) or tray (`-gui`), LSP core included. What ships in every release. Its
`Lsp.*` units (the engine: encoding detector, safe editing, designer, build runner,
remote run...) and `Mcp.Tools.*` units (one per tool) live here, and the other
projects of the group link them from this folder.

Since 2026-09-24 every project of the repo has its own folder under `src/`:

| Folder | Project |
|---|---|
| `Server/` | the server (this folder) |
| `StyleConvert/` | `DelphiStyleConvert`, the VCL/FMX style converter `delphi_styles` drives |
| `UnitTests/` | `LspUnitTests`, the DUnitX suite of the engine, run by `delphi_test` |
| `DesktopNode/` | `McpDesktopNode`, the desktop node for Linux and Windows targets |
| `RunJob/` | `McpRunJob`, the native launcher PAServer starts for every remote job |
| `DesignerMetaDump/` | the two generators of `Lsp.DesignerMeta.Vcl/Fmx.pas` (run again on a new RAD Studio) |

Build the server alone with **`BuildMcp.bat`** here (defaults: `quiet Win64 make Debug`;
the shipping exe is `BuildMcp.bat quiet Win64 build Release`), or the whole group
with [`BuildGroup.bat`](../../BuildGroup.bat) at the root. Binaries land under
`Compiled\<Platform>\<Config>` and never enter git.

The full picture — tools, security model, configuration — lives in the
[root README](../../README.md) and [`docs/`](../../docs).
