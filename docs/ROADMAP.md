# Roadmap

Status page as of 2026-10-06 (current release v1.15.0; 42 tools).

## Delivered

- Foundations (former phases 0-5): DelphiLSP validated end-to-end (see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md)), architecture (see [ARCHITECTURE.md](ARCHITECTURE.md)), LSP core, MCP stdio + Streamable HTTP with Bearer auth, Config Fabricator, `delphi_diagnostics` / `delphi_references` / `delphi_build`, remote file toolset, one executable as service / terminal / tray
- Safe editing (`delphi_edit`, `delphi_read`), `delphi_changeset` and fragment mode (0.4x–1.0.15)
- Designer: read, lint, check-binding, layout (0.5x)
- Styles (0.5x)
- `delphi_test` (0.58)
- `delphi_git` switch / merge / stash (0.57); the whitelist now covers status, diff, log, show, branch, switch, merge, stash, add, commit, init, push, tag, config, clone, pull, fetch, worktree, restore (1.7.6, always --staged)
- PAServer chain, get-sdk per distro, remote-run + kill (0.5x–1.0.16)
- adb, including display and tapScale (1.0.17)
- One desktop tool through PAServer (`delphi_desktop profile=`), Linux + Windows node, PrintWindow fallback, region / window crops (1.0.16)
- Native run-job launcher (`node/McpRunJob`), no shell; the on-target runner was removed in 0.98 (1.0.16)
- Vault, messages, reports
- Auth model: workspace-or-nothing (0.91) and nothing-global (0.98)
- Jail floor at the gate (1.0.14); `__delphi-temp` inside the jail (1.0.12)
- `DelphiVersion` per workspace and the named Delphi (1.0.17) - superseded: one server, one Delphi, `[Server] DelphiVersion` (written by the server at its first start)
- `rename_symbol mode=apply` (1.0.17)
- HTTP session TTL (1.0.17)
- Bounded per-client notification queue (200)
- Dead keys and key modifiers on the desktop node; the `delphi_adb_linux` alias retired; unit rename follows into every unit and qualified reference; DUnitX failures listed; the engine's warm-up told apart from "not a symbol" (1.1.0)
- Designer binary `.dfm` read on the fly, and `to-text` / `to-binary` conversion (1.1.2)
- `delphi_create kind=project-test` and the engine's own DUnitX suite (1.2.0)
- Reference projects: `[Workspace.<name>] ReadOnlyRoots=` (1.3.0)
- `delphi_git worktree` (1.4.0)
- `delphi_paserver command=output` for a `remote-run` job (1.5.0)
- `delphi_move` re-points relative paths across the border; `delphi_config` on a `.groupproj` (`add-project` / `remove-project`); `fix-references`; standalone sources in `delphi_create` (1.6.0)
- Every message tagged with its outcome from one catalog, the server in English, and ten review rounds of all or nothing, the jail and the contract (1.7.0)
- The changeset preview rehearses with the engines; a unit move whose project cannot be re-pointed is all or nothing (`MOVE-019`); `docs/TOOLS.md` contract blocks generated from `tools/list`; one access table that the gate consults and `tools/list` announces (`annotations.readOnlyHint`, `_meta.access`); `clean` for domain verdicts; long paths refused honestly (1.7.1-1.7.3)

- The life of the engines: asked to `shutdown` before their input is closed and launched so that no child can open an error dialog (1.7.10); stopped when nobody uses them for `[Server] EngineIdleMinutes`, and stopped and replaced when they hang (1.8.0)
- `delphi_docs`: the RAD Studio help installed with Delphi, searched and read in pieces - the list of help files is the IDE's own (1.10.0)
- One lexicon for Pascal text (`Lsp.Pascal`): what is code, a string, a comment or a directive, asked by every tool that reads Pascal instead of a dozen readers with a piece of the rule each (1.10.0)
- The designer tables read from the source of each installed Delphi - its own preprocessor and declarations reader, generated in the background and cached per version - instead of tables of one RAD Studio compiled into the exe (1.12.0)
- A cap on warm DelphiLSP engines: `[Server] MaxEngines`, the least recently used one that is not working makes room (1.13.0)
- One reader for Pascal classes, one composer for the citation of a line, the agent's regular expressions through PCRE, `delphi_git ls-remote`; a jail where Git never recurses into submodules and no tool names what lies behind a junction (1.13.0)
- Answers that say whose fix it is: a root whose drive is not connected (`WS-022`, `unavailableRoots`, `PROJ-005`), Git's dubious ownership (`GIT-057`), the download link above 1 MB (1.13.1)
- One server, one Delphi (`[Server] DelphiVersion`, and `DelphiUpdate` to check the installed update); tool descriptions about 11% shorter, each change measured against a small local model; `tools/list` without the tools the caller cannot use - the vault's where there is none or it is read-only, the write tools for a read-only credential (1.14.0)
- File lists that name each folder once (about 40% fewer tokens over ten list calls, measured); one convention for line numbers in every answer (`line` 1-based, `line0`/`character0` for the engine tools); `delphi_list` and `vault_search` by pages; a lint with no project settings answers at once (`LSP-035`) (1.15.0)

## Open

- Next: designer `insert` and `set`, for small models - a visual component with the IDE's minimum (position, caption, the published field and its unit, a parent it may live in), and one property changed or added, checked against the tables before it is written
- KDE and other non-GNOME Linux desktops on the desktop node
- The two-Delphi-versions case, measured on a machine that has them
- Completion prefix filter
- Progress and cancellation for long builds; `POST /files` upload
- LSIF as a references backend (measured feasible, see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md))

## Parked (the operator keeps them on the list, not now)

- The designer beyond `insert` / `set` (events, collections, non-visual components), and the defaults a component's constructor sets, read from its source
- Reading the newest MCP spec and noting the differences

## Declined by the operator (do not re-propose)

- Interpreters: running arbitrary interpreters on the server (`delphi_run` itself was retired on 2026-09-23)
- `[URGENTE]`-style priority messages in the mailbox
- GetIt / package installation from the MCP
- GUI control of Linux from the MCP outside the PAServer node
