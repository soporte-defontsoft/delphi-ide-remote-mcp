# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [0.9.1-beta] - 2026-08-19

### Fixed
- **Mojibake in delphi_git output** (second field-test round): git emits
  UTF-8 but captured console output was decoded as ANSI ("AÃ±ade" for
  "Añade"). The capture now runs a strict UTF-8 scan over the bytes:
  well-formed UTF-8 with high bytes decodes as UTF-8, everything else keeps
  the ANSI fallback (compilers and console programs emit ANSI/OEM). Applies
  to delphi_git, delphi_run and delphi_build alike. 142 checks.

## [0.9.0-beta] - 2026-08-19

Everything in this release comes from the first real remote field test: a
Claude Desktop agent on another machine drove the full cycle over HTTP and
its report exposed four issues. All four are fixed and test-locked.

### Fixed
- **Stale LSP buffer** (the big one): the language server saw each file as
  it was when first opened; edits made afterwards (delphi_edit, scaffolding,
  external editors) were invisible to completion/signature/definition. Now
  every acquire compares a disk fingerprint (mtime+size) and refreshes the
  buffer via didChange - the LSP always answers about the CURRENT source.
- **BOM false positive in the delphi_edit audit**: on UTF-8+BOM files the
  high-byte accounting smuggled 3 phantom bytes (the BOM) into the "leaving"
  side, producing "ACENTOS FUERA DE CUADRO: esperaba 0 y hay 3" on perfectly
  healthy writes (and scaring agents into restoring). Text fragments are now
  encoded BOM-less for accounting.

### Changed
- **delphi_git `message`**: normal punctuation is welcome (the message never
  goes through a shell - git is spawned with a direct command line); only
  line breaks are refused. Shell-metacharacter screening stays on `args`.
- **delphi_git `config`** added to the whitelist, restricted to `user.name`
  / `user.email` (value in `message`), so a remote agent can commit on a
  fresh repo/machine. Refused in read-only mode like every write.
- **delphi_create** ships a basic `.gitignore` with every new project
  (build artifacts, tool backups, `.delphilsp.json`); the agent may edit it
  later with delphi_textedit.

### Tests
- 141 checks across the 5 batteries (stale-buffer refresh, BOM accounting
  on utf8-bom, git config identity + free punctuation, scaffold .gitignore).

## [0.8.0-beta] - 2026-08-19

Closes the gap found by the full capability inventory of DelphiLSP 37.0
(docs/DELPHILSP-NOTES.md): the engine announced signatureHelp and
declaration/implementation providers that no tool exposed.

### Added
- **`delphi_signature` (tool 20)**: signature help for the call under a
  position — routine signatures with parameter names/types, the IDE's
  Ctrl+Shift+Space. Position must be inside the call parentheses.
- **`delphi_definition` `kind` parameter**: `definition` (default) = the
  body in the implementation section; `declaration` = the interface
  declaration — the two halves of a Delphi unit. (`implementation` is
  accepted but the engine answers it like declaration — measured.)

### Docs
- DELPHILSP-NOTES: measured navigation semantics (definition=body,
  declaration=interface, implementation≡declaration), LSIF conditions and
  kill-switch, `$Y` requirement, DelphiLSPLog registry logging.

## [0.7.0-beta] - 2026-08-19

### Added
- **`delphi_installs` (tool 19)**: list every RAD Studio/Delphi installation
  discovered on the machine (side-by-side versions are common), with root
  directory, DelphiLSP/msbuild availability, and which one is ACTIVE for the
  LSP engine (the newest shipping DelphiLSP.exe). Installs without DelphiLSP
  are listed too: they still build via msbuild.

### Fixed
- **No composed branding paths**: `$(BDSUSERDIR)`/`$(BDSCOMMONDIR)` are now
  resolved from the authoritative `rsvars.bat` written by the installer
  (Embarcadero renames its Documents folder between eras — e.g. "RAD
  Studio" vs "Embarcadero\Studio"), never composed by hand. Entries that
  cannot be resolved are dropped instead of guessed.

## [0.6.0-beta] - 2026-08-19

Born from a dogfooding audit: "could this MCP have built its own project?"
The Delphi cycle could; docs, tests and release engineering could not. Now
they can.

### Added
- **`delphi_textedit` (tool 18)**: safe editing of plain-text NON-Delphi
  files (.md .html .js .css .sql .py .bat .ini .json ... any plain text,
  denylist not whitelist) with the same discipline as `delphi_edit` —
  one-full-line unique anchor with hints and atline tie-break, encoding and
  EOL preserved, automatic backup, atomic write, no whole-file rewrites —
  plus a CREATE mode that never overwrites. Delphi sources/designers/.dproj
  and binaries are refused.
- **`delphi_git`: `init`, `push`, `tag`** added to the whitelist (push uses
  the credentials/remotes stored on the server — consistent with the
  centralized model; tag is annotated when "message" is given). In read-only
  mode `tag`/`branch` without arguments (pure listing) pass; everything else
  that writes stays refused.
- **Library read zone**: with a jail configured, READING tools (read /
  search / list / fetch / LSP navigation) also accept the RAD Studio
  installation and the IDE Library Search Path directories, so agents can
  follow definitions into RTL/VCL sources and read installed components'
  code. Writing tools can never touch that zone.
- **Config Fabricator**: merges the IDE's global Library Search Path
  (registry) into fabricated settings, so symbols of installed third-party
  components resolve without the project repeating their paths.

### Tests
- 124 checks across the same five batteries (textedit lifecycle including
  .html, git init/tag/push against a throwaway repo, library-zone
  read-vs-write, read-only classification of the new tools).

## [0.5.0-beta] - 2026-08-19

### Added
- **Read-only access level**, enforced at a single gate in front of every
  `tools/call`: `[Security] ReadOnlyToken` (second Bearer credential),
  `AnonymousReadOnly=1` (tokenless requests get read-only), and a
  `--readonly` flag (whole process read-only, any transport). Read-only
  clients can read, search, navigate symbols, get diagnostics, download and
  run query git commands; `delphi_edit`, `delphi_create`, `delphi_build`,
  `delphi_run`, `delphi_package` and git write commands are refused. Made
  for reviewer agents (e.g. a wiki agent cross-checking the sources).
- `settings.example.ini` configuration template.

### Changed
- Documented that the HTTP listen port is configurable via
  `settings.ini [Server] Port` (default 3000; `--http <port>` overrides),
  and locked the behavior with a test.
- Token/credential reading centralized in one unit (was duplicated in the
  console and tray hosts).

## [0.4.0-beta] - 2026-08-19

The project is now explicitly labeled **beta**: functional and test-covered,
but young — expect rough edges and breaking changes between minor versions.

### Added
- `delphi_package` (tool 17): zip a build-output directory on the server
  into a single deploy artifact (recursive, `.dcu` intermediates excluded),
  ready to download with one `delphi_fetch`. The standard route to run GUI
  apps on the client machine: `delphi_build` → `delphi_package` →
  `delphi_fetch`.

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
