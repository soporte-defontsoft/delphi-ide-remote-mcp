# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [0.16.0-beta] - 2026-08-19

### Added
- **`delphi_delete` (tool 26)**: remove a file or folder inside the workspace
  — NOT a hard delete: the target is moved to a recoverable trash
  (`__delphi-patch\<date>\deleted\` next to it), so a mistake can be undone.
  Refuses to delete the trash folder itself. Jailed, read-write only. Cleans
  up stray files and build leftovers.
- **`delphi_move` (tool 27)**: move or rename a file/folder inside the
  workspace; the source is copied to the trash first, destination parents are
  created, an existing destination is never overwritten. Jailed, read-write.
- **`[Server] BindIP`** (env `DELPHI_MCP_BIND_IP`): bind the HTTP listener to
  one interface (e.g. a LAN/VPN address) instead of all interfaces — which
  also removes the duplicate IPv4+IPv6 firewall prompt.

## [0.15.0-beta] - 2026-08-19

Cross-platform groundwork: see and manage a project's build configurations,
and discover the Platform Assistant so an agent can target Linux/macOS.

### Added
- **`delphi_config` (tool 24)**: see and manage a project's build
  configurations and target platforms. `view` (read-only) reports the
  framework, the configurations (Debug/Release/custom) and every platform
  with whether it is enabled, whether the project **can** target it, and
  whether it needs a remote profile. `add-platform` (read-write) enables a
  platform in the `.dproj` — a **curated** edit of the `<Platforms>` block
  only. It refuses a platform the framework cannot target: **VCL is Windows
  only** (`Vcl.Forms` does not exist on Linux/macOS/mobile); FMX and console
  cross platforms.
- **`delphi_paserver` (tool 25, read-only)**: the bridge for building on
  other platforms via the Platform Assistant. `platforms` lists what this
  server can target and each platform's profile/SDK status; `packages` lists
  the PAServer installers that ship with each Delphi install (download with
  `delphi_fetch`, run on the Linux/Mac target); `profiles` lists the
  registered connection profiles and SDKs. The write/network half (create a
  profile against the target, deploy+run remotely) builds on this once a live
  PAServer target exists.
- **`Lsp.Dproj`**: the single tolerant `.dproj` parser, now shared by the LSP
  config fabricator and these tools — no second parser (house rule).
- `delphi_build` accepts any declared platform, not just Win32/Win64.

## [0.14.0-beta] - 2026-08-19

The library read zone finally covers what it always promised, plus the
fourth field round's findings.

### Fixed
- **The read zone was missing most of the machine's Delphi material**, a gap
  in a feature shipped back in 0.6.0:
  - it walked only `Win32`/`Win64`, while an install registers a Library
    Search Path for **every** platform (13 here: Linux64, OSX64, OSXARM64,
    Android ×2, iOS ×4, Win64x, WinARM64EC…);
  - it expanded a hardcoded handful of macros, so every entry using
    `$(BDSCatalogRepository…)` was silently dropped — i.e. **every GetIt
    package** (FmxLinux, LockBox…) and the Android SDKs.
  Macros are now expanded against the IDE's own authoritative table
  (`HKCU\…\BDS\<ver>\Environment Variables`), all registered platforms are
  walked, the catalog repositories are included whole (the search path points
  at compiled `Lib\`, while the useful material is the sibling `source\`),
  and it is done **per installation** — each Delphi owns its packages.
- **`delphi_list` aborted entirely on one unreadable subdirectory**
  (`TDirectory.GetFiles` recursive is all-or-nothing) and again when asking
  size/date of a file whose path exceeds the classic length limit. Measured
  on the Android NDK, which killed a whole listing; it now walks tolerantly
  and lists 19,436 files there.
- **R4-A**: `delphi_fetch` returned the server's real path. The byte-fidelity
  exemption was wrong for it: its payload is base64, an alphabet with neither
  `:` nor `%`, so masking cannot corrupt it. Only `delphi_read` stays exempt
  (its payload is file text an edit anchor must match).
- **R4-C**: `delphi_list` echoed `..\` segments back in every returned path;
  the root is canonicalized first.
- Paths whose last segment is `.` or `..` are no longer refused as
  "name ending in a dot": they are ordinary navigation, and the jail already
  canonicalizes before deciding (escape attempts through `..` remain caught —
  verified in the field round).

### Added
- **R4-B**: `delphi_workspace` publishes `readableExtra` — the read-only
  library zone (installations, library paths, catalog repositories), so the
  agent knows what it may read besides the roots instead of being told
  "anything outside is refused".

## [0.13.0-beta] - 2026-08-19

Read-only becomes airtight, a feedback channel for the agents that use the
server, and the third field round's findings.

### Added
- **`delphi_report` (tool 23)**: agents report bugs, limitations or
  suggestions **directly to the server**, which stores each one as its own
  timestamped markdown file (version, date, kind, origin, message) in a
  `reports/` folder next to the executable — a history that can be read and
  worked through later. Deliberately **available at every access level,
  read-only included**: the restricted agents are the ones most likely to hit
  a wall. Safe by construction — the client never supplies a path: the folder
  is fixed and the file name is generated server-side.
- **`Lsp.Texts`**: every model-facing text (tool/parameter descriptions,
  rejections, notices) and the version string now live in ONE unit. These
  texts are the server's real user interface; scattered they drift and
  contradict each other. Pure ASCII by convention — the encoding rule that
  produced the mojibake bug is now a property of the file.

### Security
- **Read-only is now airtight** (found by an internal audit that ran the
  server anonymously and tried to escape):
  - `delphi_git diff|show --output=<path>` let ANY client — including
    anonymous/read-only — write files anywhere on disk, **outside the
    workspace roots included** (an absolute `--output` ignores `-C <repo>`).
    Dangerous git options (`--output`, `--no-index`, `--exec`,
    `--upload-pack`, `--receive-pack`, `--ext-diff`, `--textconv`,
    `--config-env`, `-c`, `-o`) are now refused **at the single gate**, so the
    rule applies to every git call at BOTH access levels.
  - `delphi_git tag` with a `message` (annotated tag = a write) passed the
    read-only gate when `args` was empty: the gate only looked at `args`.
- Verified in the same audit and left unchanged (they were already correct):
  401 for a missing token when one is configured, and the per-request
  read-only flag being re-set on every request (no leakage between pooled
  Indy threads).

### Fixed
- **C1-bis**: `insert:"metodo"` with `visibility:"published"` placed the
  declaration right after the class header — i.e. BEFORE the component
  fields, which is E2169 ("field definition not allowed after methods").
  It now lands after the last member of the implicit published section.
- **B5** (root cause found by measuring the live JSON): `definition` answers a
  bare Location **object**, not an array, so the chaining added in 0.12.0
  never triggered and `kind=declaration` still returned the enclosing scope.
  The parser now accepts object/array/LocationLink and aims the second lookup
  at the routine's identifier column.
- **R3-1**: LSP tools leaked the real drive in their URIs
  (`file:///D%3A/...`) because the percent-encoded colon dodged the mask.
  Virtual drive units now cover that form too.
- `delphi_git log` regression test no longer asserts on a specific old commit
  message (it scrolled out of the 20-line window).

## [0.12.0-beta] - 2026-08-19

Virtual drive units — server paths stop looking like the client's own disks —
plus every finding from the second field round (the "Agenda" end-to-end run:
2 projects, 7 commits, 16/16 tests, ~86 MCP calls).

### Added
- **Virtual drive units (`srvd:`, `srvc:`, ...)**: the server's real drive
  letters never travel to the client. One generic prefix rule at the single
  dispatch gate handles both directions — arguments are expanded on the way
  in (`srvd:\x` → `D:\x`; real paths still accepted), and every textual
  result is masked on the way out, INCLUDING compiler/git/LSP output and 8.3
  short forms (`D:\PROYEC~1`). Byte-fidelity exemption: successful
  `delphi_read`/`delphi_fetch` content travels verbatim (an edit anchor
  built from masked text would not match the disk); their rejections are
  masked like everything else. Measured origin: remote agents mistaking
  server paths for their own local disks.
- **`delphi_edit delete:true`**: removes the anchored line ENTIRELY
  (`new:""` only blanks it — and now says so: `BLANQUEADA la linea N ...
  para eliminarla del todo usa delete:true`).
- **IDE settings read at runtime** (`IdeConfigValue`, generic HKCU reader —
  the building block for future Android/macOS/SDK configuration): new
  units/forms/projects are created with the encoding the IDE is configured
  to use (`Editor\DefaultFileFilter`: UTF-8 → utf8-bom, ANSI → cp1252), and
  BOM-less pure-ASCII files get their first accents written in that same
  standard.

### Fixed
- **B3 (blocker): `insert:"rutina-global"` in a `.dpr`** placed the routine
  before `end.` — legal in a unit, E2070 + 2×E2029 in a program. In a `.dpr`
  the routine now lands between the `uses` clause and the main `begin`;
  `insert:"metodo"` on a `.dpr` is refused with guidance.
- **C1: `insert:"metodo"` with `visibility:"published"`** now works on form
  classes with no explicit section keyword: the declaration lands in the
  implicit published section right after the class header — the event
  handler case, the most common VCL edit.
- **B1: `delphi_git commit`/`tag` messages** now reach git via `-F <file>`
  (byte-exact): embedding them in the command line turned every `"` into
  `''`.
- **B5: `delphi_definition kind=declaration` on a call site** returned the
  declaration of the ENCLOSING method; the tool now chains
  definition→declaration at the target's own position, so it answers the
  callee.
- **B2: `acentos=` counted the UTF-8 BOM** as 3 phantom high bytes.
- **B4: mojibake in `delphi_create form-vcl` response messages**: a handful
  of message literals carried non-ASCII bytes that the compiler mangles when
  the IDE's default encoding disagrees with the file; all server messages
  are now pure ASCII by construction.
- Scaffolded `.gitignore` no longer carries a UTF-8 BOM (git does not strip
  it, which silently broke the first ignore rule).

### Security
- **`[Workspace] Roots` parsing fails CLOSED**: quotes around a root are
  tolerated and stripped (paths with spaces need no quoting — the separator
  is `;`), and if Roots is configured but NO root parses valid, every path
  is refused instead of silently running unrestricted.

## [0.11.0-beta] - 2026-08-19

The transfer batch, plus the addendum findings from the replication run.
Bringing a repository in no longer means recreating it file by file.

### Added
- **`delphi_git clone` / `pull` / `fetch`**: a whole repository onto the
  server in ONE call, jailed to the workspace roots (URL in `message`,
  destination in `repo`; only http/https/git/ssh URLs; refuses to clone
  over an existing repo). Measured: the full public repo cloned in 1.2 s
  versus ~200 MCP calls to recreate it.
- **`delphi_upload` (tool 22)**: the mirror of `delphi_fetch` — chunked
  base64 upload with whole-file SHA-256 verification, for material that
  cannot be recreated by editing (`.res`, icons, binary designer files).
  Jailed, creates parent directories, refuses out-of-order offsets.
- **Create-with-content**: `delphi_edit createunit` accepts `content` (the
  whole unit in one call instead of create + N anchored patches — the
  measured friction #1: 6 calls per file down to 1), both it and
  `delphi_textedit` accept `eol` (`crlf` default / `lf`), because the JSON
  channel usually delivers LF-only text.

### Security
- **Windows name-normalization bypass closed** (found in the field): a path
  ending in a dot or space ("X.pas.") passes any literal extension check
  while Windows creates "X.pas" — it defeated the `.pas` guard of
  `delphi_textedit`. Alternate Data Streams ("X.pas::$DATA") did the same.
  Both are now refused at the single write gate, so the fix covers EVERY
  writing tool, not just the one where it was found.
- `delphi_upload` validates the base64 alphabet itself: Delphi's decoder
  skips invalid characters instead of failing, which would have written a
  silently corrupt file.

### Fixed
- `delphi_textedit` create reported `encoding=utf8` for pure-ASCII content
  that a later `delphi_read` detects as cp1252; it now says what detection
  will say.

## [0.10.0-beta] - 2026-08-19

More field-test findings from the full-repo replication run. Two were real
bugs (one an outright blocker), one a new tool, one a security hardening.

### Fixed
- **Dotted unit names** (blocker): `delphi_edit createunit` and scaffolded
  form units rejected names like `Lsp.BuildRunner` — the tool could not
  create the very units of the project it is part of. Namespaced names
  (`Ident(.Ident)*`) are now accepted.
- **Access Violation on `delphi_edit` with `new=""`**: blanking a line
  crashed the handler (indexing an empty split). Empty replacement now
  blanks the line cleanly.

### Added
- **`delphi_workspace` (tool 21)**: the server's lay of the land — the
  configured workspace roots (made explicit so a remote agent never
  confuses SERVER paths with its own local disk), the access level
  (read-write / read-only) and the active Delphi. Read-only; call it first.

### Security
- Every `delphi_run` (arbitrary execution by design) and `delphi_build`
  (can run pre/post-build steps from the .dproj) now writes an audit line
  to the log — for run, the executed binary's SHA-256. (Build and run
  remain refused under a read-only credential.) OS-level sandboxing of the
  spawned process is tracked as future work.

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
