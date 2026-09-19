# `src/` — the server and its two Windows companions

Three Delphi projects share these sources (all in [`MCP-delphi.groupproj`](../MCP-delphi.groupproj)):

| Project | What it is |
|---|---|
| **`DelphiLspMcp.dproj`** | **The server itself** — the Delphi IDE Remote MCP Server: 42 tools over stdio, HTTP (`--http`) or tray (`-gui`), LSP core included. What ships in every release. |
| `DelphiStyleConvert.dproj` | Companion CLI that converts VCL⇄FMX style files; `delphi_styles` runs it. Ships next to the server. |
| `LspCoreTest.dproj` | Console **diagnostic harness for the LSP core** (`Lsp.Transport.Process`, `Lsp.Client`, `Lsp.Discovery`, `Lsp.ConfigFabricator`): drives a real `DelphiLSP.exe` with no MCP layer on top — `LspCoreTest hover --file X --line N`. Nobody links it; it exists so a broken LSP conversation can be probed in isolation. |

Build the server with **`BuildMcp.bat`** (defaults: `quiet Win64 make Debug`; the
shipping exe is `BuildMcp.bat quiet Win64 build Release`) and the harness with
`BuildWithParams.bat`. Binaries land under `Compiled\<Platform>\<Config>` and
never enter git.

The full picture — tools, security model, configuration — lives in the
[root README](../README.md) and [`docs/`](../docs).
