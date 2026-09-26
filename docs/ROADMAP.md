# Roadmap

Status page as of 2026-09-25 (current release v1.3.4; 41 tools - `delphi_run` retired).

## Delivered

- Foundations (former phases 0-5): DelphiLSP validated end-to-end (see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md)), architecture (see [ARCHITECTURE.md](ARCHITECTURE.md)), LSP core, MCP stdio + Streamable HTTP with Bearer auth, Config Fabricator, `delphi_diagnostics` / `delphi_references` / `delphi_build`, remote file toolset, one executable as service / terminal / tray
- Safe editing (`delphi_edit`, `delphi_read`), `delphi_changeset` and fragment mode (0.4x–1.0.15)
- Designer: read, lint, check-binding, layout (0.5x)
- Styles (0.5x)
- `delphi_test` (0.58)
- `delphi_git` switch / merge / stash (0.57); the whitelist now covers status, diff, log, show, branch, switch, merge, stash, add, commit, init, push, tag, config, clone, pull, fetch
- PAServer chain, get-sdk per distro, remote-run + kill (0.5x–1.0.16)
- adb, including display and tapScale (1.0.17)
- One desktop tool through PAServer (`delphi_desktop profile=`), Linux + Windows node, PrintWindow fallback, region / window crops (1.0.16)
- Native run-job launcher (`node/McpRunJob`), no shell; the on-target runner was removed in 0.98 (1.0.16)
- Vault, messages, reports
- Auth model: workspace-or-nothing (0.91) and nothing-global (0.98)
- Jail floor at the gate (1.0.14); `__delphi-temp` inside the jail (1.0.12)
- `DelphiVersion` per workspace and the named Delphi (1.0.17)
- `rename_symbol mode=apply` (1.0.17)
- HTTP session TTL (1.0.17)
- Bounded per-client notification queue (200)
- Dead keys and key modifiers on the desktop node; the `delphi_adb_linux` alias retired; unit rename follows into every unit and qualified reference; DUnitX failures listed; the engine's warm-up told apart from "not a symbol" (1.1.0)

## Open

- Workspace Manager: LRU / idle shutdown of warm DelphiLSP clients, and kill+respawn on hang
- KDE and other non-GNOME Linux desktops on the desktop node
- The two-Delphi-versions case, measured on a machine that has them
- Completion prefix filter
- Progress and cancellation for long builds; `POST /files` upload
- LSIF as a references backend (measured feasible, see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md))

## Parked (the operator keeps them on the list, not now)

- Designer phase 2: structural `.dfm` edits validated by RTTI
- `convert.exe` binary → text designer conversion
- Reading the newest MCP spec and noting the differences

## Declined by the operator (do not re-propose)

- Interpreters: running arbitrary interpreters on the server (`delphi_run` itself was retired on 2026-09-23)
- `[URGENTE]`-style priority messages in the mailbox
- GetIt / package installation from the MCP
- GUI control of Linux from the MCP outside the PAServer node
