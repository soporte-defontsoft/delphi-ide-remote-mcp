# `src/` — seven projects, one per folder

Everything Delphi in this repository lives here, **one project per folder** (the two
form renderers share theirs), and all seven are in
[`MCP-delphi.groupproj`](../MCP-delphi.groupproj), so a
*Build All* in the IDE or `BuildGroup.bat` at the root compiles every one of
them. What each is for, whether it ships, and when it runs:

| Folder | Project | What it is for | Ships in the release zip? | When it runs |
|---|---|---|---|---|
| [`Server/`](Server) | **`DelphiLspMcp`** | **The product**: the Delphi IDE Remote MCP Server, 42 tools over stdio, HTTP or tray. Its `Lsp.*` units are the engine (encoding detector, safe editing, designer, build runner, remote run, jail) and its `Mcp.Tools.*` units are one per tool. The other projects link the engine from this folder. | **Yes**, as `DelphiLspMcp.exe` | Always: it is the server. |
| [`StyleConvert/`](StyleConvert) | `DelphiStyleConvert` | Companion CLI that converts VCL/FMX style files between text and binary. `delphi_styles build` runs it; the server looks for it next to its own exe. | **Yes**, next to the server | Whenever an agent builds a style. |
| [`Render/`](Render) | `DelphiFormRenderVcl`, `DelphiFormRenderFmx` | The two **form renderers**: a `.dfm` / `.fmx` to a PNG of what the IDE designer shows, with the IDE's design packages loaded into THEM, never into the server. Win32. `delphi_designer preview` runs them; the server looks for them next to its own exe. `Render/Pruebas/` holds their manual DUnitX battery (it launches the exes, so it runs from the user's session, not in `delphi_test`'s container). | **Yes**, next to the server | Every `delphi_designer preview`. |
| [`DesktopNode/`](DesktopNode) | `McpDesktopNode` | The **desktop node**: the server's eyes and hands on a target machine (screenshot, tap, type, key, window list). One source, two binaries: Linux64 (GNOME, portal + libei) and Win64 (GDI + SendInput). | **Yes**, both binaries under `node/` | The server pushes it to each target on first use and runs it for every `delphi_desktop` gesture. |
| [`RunJob/`](RunJob) | `McpRunJob` | The **run-job launcher**: what PAServer starts on a target for every remote execution and every desktop gesture. It reads a job file, starts the native binary unattended with its arguments and leaves a watcher that writes the exit code. No shell anywhere. | **Yes**, both binaries under `node/` | Every `remote-run` and every desktop gesture on a PAServer target. |
| [`UnitTests/`](UnitTests) | `LspUnitTests` | The engine's **DUnitX suite**: unit tests of the encoding detector and its inverses, the designer binary shape and the RTL round trip, and the `.dproj` hazard scan. The step below the black-box Python batteries in `tests/`. | No | `tests/test_engine_dunitx.py` runs it through `delphi_test` in every regression; you can run it with `delphi_test command=run`. |

Two things ship that are **not** projects: `settings.example.ini` (the
configuration template) and `docs/`. The Python batteries in `tests/` are the
harness, not a client, and the vendored MCP plumbing in `vendor/` is frozen.

## Building

- The whole group: **`BuildGroup.bat quiet build Release`** at the root. It also
  builds the node and the launcher for Linux64 against the project's SDK and
  copies the four binaries to `node/`, which is what the release packs. Those
  four are build output and are not versioned; `tests/release_check.py` refuses
  to package one that is missing or older than its sources.
- One project: `delphi_build` from an agent, or the IDE, or `Server/BuildMcp.bat`
  for the server alone. Binaries land under each folder's
  `Compiled\<Platform>\<Config>` (or `<Platform>\<Config>`: `Win32\Release` for the
  renderers) and never enter git.

Each folder carries its own README with the detail.
