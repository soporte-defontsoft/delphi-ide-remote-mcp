# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Changed

- **`delphi_config remove-unit` / `remove-searchpath` / `remove-project` take
  the entry as the project lists it, even one that points outside.** The
  path of a `remove-*` was judged by the jail as if the tool were going to
  read it (the generic floor of `[RutaDelServidor]` and the tool itself), so
  a `<DCCReference>` or a search path pointing outside what the session can
  read answered `GUARD-002` - the very entry `BUILD-050` asks to remove
  before it builds (measured on 2026-10-21 with a real project copied to the
  NAS: 29 absolute references to the component folder of ANOTHER machine).
  Now that path is what the project SAYS (`[NombreSiComando]`, one attribute
  read by the same RTTI census as the other marks): nothing is read or
  written there, the core does not open a path outside what is readable and
  says so (`CFG-123`), the entry leaves the `.dpr` and the `.dproj`, and the
  project itself is still judged for writing. `add-unit`, `add-searchpath`
  and `add-project` still require a readable path. `BUILD-050` names the
  way out. `test_remove_fuera_1213` (R1, R3, R4 red against 1.21.2).
- **The build supplies the output folders a project leaves undeclared,
  instead of refusing it.** Until 1.21.2 a project without `DCC_DcuOutput`
  (or a package without `DCC_BplOutput`/`DCC_DcpOutput`) for the platform and
  config of the build answered `BUILD-030`, because without them dcc leaves
  every `.dcu` next to its source - a component's or a reference's inside its
  own folder, outside the workspace - and the `.bpl`/`.dcp` in the IDE's
  global folders. Measured on 2026-10-21 against a twenty-year-old real
  project copied to the NAS and opened in the IDE 13.2: the IDE compiled it
  and wrote 14 `.dcu` of a component into `Program Files`; this server
  refused it. Now the build passes those folders itself on MSBuild's command
  line, as global properties: the binary output folder of that build
  (`DCC_ExeOutput`), or `.\$(Platform)\$(Config)` - what the IDE writes for a
  new project - when there is none; per platform and configuration, judged
  by the same two judges as a declared folder (`BUILD-029`, `BUILD-031`),
  never written to the `.dproj`, and a folder the project does declare is
  always the one used. The answer says which and where (`outputSupplied`,
  `BUILD-054`). `BUILD-030` stays for the one folder the build does not
  supply, the C++ `.hpp` one. One literal for the IDE's default layout
  (`IDE_OUTPUT_DEFAULT`), shared by the gate, `set-output default` and
  `delphi_create`. `test_build_salida_suplida_1213` (S1, S3, S4, S5 and S7
  red against 1.21.2, S3 being a unit of a read-only reference compiled from
  its source with its folder left untouched); `test_escritor_guardado` O
  updated.
- **`delphi_upload` says when what it wrote is a project file.** It is the
  one channel that writes a `.dproj` raw, on purpose - `delphi_edit` and
  `delphi_textedit` refuse one (`EDIT-128`) - and the build judges it
  however it got there; an agent that found that out by trying (Hermes, deep
  test of 1.21.2) read it as a gap. The answer now carries `projectNote`
  (`UPLOAD-014`) for a `.dproj`, a `.groupproj`, a `.dpr` or a `.dpk`: the
  build judges it before compiling, and which tool is the house for editing
  it. `test_upload_nota_proyecto_1213`, red against 1.21.2.

### Fixed

- **The build gate read an `<RcItem>` as if it were a `.rc` script.** An
  `RcItem` is a resource FILE (the `.gif` or `.png` the IDE lists under
  Resources and Images and compiles as RCDATA through the `.rc` it generates
  itself); the gate of 1.21.2 ran the `.rc` reader on it, parsed its bytes as
  text and refused with `BUILD-052` quoting them. Found on a real project the
  first time it reached that gate (2026-10-21). Now only the script of an
  `RcCompile` goes through the `.rc` reader; an `RcItem` is judged by its
  path like everything else the build reads (one inside compiles, one outside
  is `BUILD-050`). `test_build_lista_blanca_1212` W10 extended, red against
  1.21.2.
- **`delphi_styles set` rewrote a property FMX already ignored and said CHANGED.**
  The judge of `set` (STYLE-050, what FMX's own reader ignores) compared the
  ignored list before and after the change and refused only what the change
  added: a property the class does not publish that was already in the object
  (a `Fill.Color` on a TButton, set the day before) was rewritten with
  CHANGED, and the value never reached the app nor the `.bin.style` - lint and
  build said so, `set` did not. Found by Hermes (Qwen3.8 Flash Next) in its
  deep test of 1.21.2. Now what FMX ignores that names the property this
  `set` writes is refused even if it was already ignored; a valid property on
  the same object, or the same property on a class that publishes it, still
  builds. `test_styles_set_ignorado_1213`, red against 1.21.2.

## [1.21.2] - 2026-10-20

A patch of 1.21.1 that turns the build gate into a whitelist and judges what
the build reads, after the lesson of 1.20.1 (a resource script and a manifest
from outside the workspace ended up inside the binary); validated by Hermes
(Qwen3.8 Flash Next) on Delphi 13.2 before publishing. The server also cleans
what any child that died without finalizing left in Windows' atom table, and
the FMX application window no longer flashes in the taskbar.

### Security

- **The build gate is a whitelist.** `delphi_build` refused a project by a
  list of 21 MSBuild task names (`<Exec>`, `<Copy>`...); whatever the list
  did not know, built. Now a project builds only when every element is one
  a compile-only build understands - under `<Project>`: PropertyGroup,
  ItemGroup, Import, ProjectExtensions and Target; inside a `<Target>`:
  Message, Warning, Error, CallTarget, OnError, PropertyGroup and ItemGroup;
  inside a task, only Output - and anything else is refused by its name and
  its parent's (the known tasks keep their own wording). XML the scanner
  cannot follow is refused too. The list stays as a second barrier.
- **What the build reads is judged by the read gate.** Every value of every
  property and every `Include` of every item of the `.dproj` and what it
  imports - the icon, the manifest, the search paths, the `.rc` files, the
  deployment files, a keystore - is expanded as msbuild expands it and has
  to lie where this session may read (the workspace, the IDE and its library
  zone), whether it exists or not; measured in 1.20.1, an `RcCompile` and a
  `Manifest_File` from outside ended up inside the `.res` and the exe. The
  `.rc` of each `RcCompile` is read with the same judge as `delphi_styles
  build`. Free text handed to the compiler's command line
  (`DCC_AdditionalSwitches`, `BRCC_UserSuppliedOptions`,
  `BRCC_ResponseFilename`) is refused without `AllowBuildScripts`. And a
  file in the project's tree that is a hard link to one outside what the
  session may read is refused: the compiler would read it through that
  name. BUILD-050 to BUILD-053; `test_build_lista_blanca_1212`, red against
  1.21.1. Census on the 122 projects of the production roots: nothing
  legitimate is refused.

### Fixed

- **A child that died on its own left its atoms in Windows' global table.**
  The server cleaned the RTL atoms (`Delphi<pid>`, `ControlOfs...`,
  `WndProcPtr...`, `FIREMONKEY...`) only of the children it killed itself,
  by their deadline; a renderer that died without finalizing on its own -
  its Job kills it on an unhandled exception, a design package crashes
  inside it - left them for good, and when it was the judge of a `set`,
  which tolerates that failure, nobody saw it. Measured on 20-oct-2026:
  6 VCL renderers in one release gate (18 atoms), 2 in an instrumented pass,
  intermittent. `RunCore`, the one launcher, now cleans what any ended child
  left (cheap for the ones that finalized: without their process atom
  nothing is scanned) and logs it with the exit code, so the next death
  says why. `test_hijo_sin_finalizar_1212`, red against 1.21.1.
- **The FMX application window flashed in the taskbar for an instant.** The
  renderer's CBT hook changed the `CREATESTRUCT`'s extended style when
  `TFMAppClass` was created, and Windows ignores that (measured with a
  probe): the window was born with `WS_EX_APPWINDOW` and stayed visible
  until the renderer hid it - 3 samples of 4,043 in the designer corpus, the
  "2 samples with no cause" of 19-oct. The hook now sets the style on the
  window itself, which Windows honours. Same battery, red against 1.21.1
  (caught in 1 of 3 renders).

## [1.21.1] - 2026-10-20

A patch of 1.21.0 with what agents and our own measurements found once it
was out, checked by Hermes (Qwen3.8 Flash Next) on Delphi 13.2 before
publishing - a targeted pass, the full test, and rounds on what they
found - and, this once, by a full review of Claude Sonnet 5 and GPT-5.6
Luna. Three holes through hard links are closed: reading one whose other
name is outside the roots (`GUARD-041`), also through the copies the
server makes on its own; `delphi_upload` writing through one into the file
outside (`GUARD-043`); and purging a folder that held one, which changed
the attributes of the file outside. A project the IDE
has just created builds, a configuration of the project's own deploys,
and a path written with forward slashes is written as it is read. And
the tools say what they used to keep quiet: a parameter of another
command (`DESK-025`, `HELP-009`, `DOCS-017`, `REPORT-013`), a completion
trigger the engine ignores, the project `references` and `rename`
resolved with and the uses in the form files, a unit that only exists
qualified (`BUILD-049`), and two routines in one `insert` (`EDIT-129`);
`delphi_git config` reads the identity it sets.

### Fixed

- **Purging a folder that held a hard link changed the attributes of a file
  OUTSIDE the workspace.** The deleter of trees cleared the attributes of
  every file before deleting it, and the attributes of a hard link ARE those
  of the file - the same file, with its other name outside the roots.
  Measured on 11-oct-2026 and again on 20-oct against 1.21.0: a folder with a
  hard link to a read-only, hidden file outside, sent to the trash and
  purged, left that file without both attributes (its bytes untouched). A
  name is now deleted without touching the file's attributes - Windows'
  `FileDispositionInfoEx` with "ignore read-only", which deletes a read-only
  name as it is - and where the file system does not know it, the read-only
  attribute of a file with more than one name is never cleared (deleting it
  fails and says so). `test_enlace_duro_1182`, red against 1.21.0.
- **A project just created in the IDE did not build through the server.**
  Its `.dproj` imports `$(MSBuildProjectName).deployproj` with
  `Condition="Exists('$(MSBuildProjectName).deployproj')"`, and that file
  does not exist until the first deployment; the build gate refused every
  `<Import>` of a missing file - `BUILD-017`, in the words of a security
  refusal - although MSBuild, the judge, simply does not import it. The same
  wall stopped a `delphi_git worktree` of a repository that ignores its
  `.deployproj` (an agent on Hermes, 19-oct-2026). That exact form - a
  condition that is `Exists()` of the import's own path - is now let through
  when the file is missing; any other condition is still not evaluated by
  the server, and a file that IS there is read and scanned as before. The
  scan and MSBuild run under the same write lock, so the file cannot appear
  in between through the server. Measured live: the VCL and FMX projects the
  IDE created build. `test_build_imports`, red against 1.21.0.
- **Deploying a configuration other than Debug or Release shipped nothing
  and said it had succeeded.** The deployment manifest the server generates
  had groups for 'Debug' and 'Release' only, written by hand; with a
  configuration of the project's own (`Prod`) msbuild cleaned the target's
  folder, found no file for that configuration and reported success
  (measured on 20-oct-2026 against the Zorin: nothing arrived). The groups
  are now those of the configurations the project builds - the ones it
  declares except Base, the same list that `delphi_build` and `set-active`
  accept, now read by one helper. Measured live: the `Prod` binary arrives
  and runs. `test_deploy_adb`, red against 1.21.0.
- **`delphi_desktop` took the parameters of a gesture it was not doing
  without a word.** A call with `code`, `x`, `y` or `text` and no
  `command` is a screenshot - the default - and the server answered with
  one: an agent on Hermes (Claude Sonnet 5) that put `command` outside the
  tool's arguments sent Escape, Super, four taps and a `type` that were
  seven screenshots, and reported that GNOME's overview took no input
  (19-oct-2026; its calls, read back in Hermes's log, showed it). The tool
  now judges what goes with each command like the other tools with several
  commands (`delphi_adb` among them): `DESK-025`, nothing done, with what
  that command takes, which commands the parameter goes with and - when
  `command` did not arrive - that the call was a screenshot.
- **`delphi_help`, `delphi_docs` and `delphi_report` took a parameter of
  another command without a word too** - the last tools with several
  commands that did not judge them: `name` with `help conventions`,
  `offset` with `docs search`, `title` with `report list` were ignored
  (measured live on 20-oct-2026). They are refused now like everywhere
  else (`HELP-009`, `DOCS-017`, `REPORT-013`), with what the command takes
  and which commands the parameter goes with. Two exceptions, kept on
  purpose: `docs` without `command` and with an `id` still tolerates a
  `query` beside it (its description promises so), and `report` takes
  `agent` with every command (rule 12 of `delphi_help` asks for it on every
  call).
- **`RENAME-019` did not name the way that exists for a component of the
  form.** It said a published member breaks the form's binding and that the
  IDE "only repairs it interactively"; `delphi_designer command=set
  prop=Name` renames a component as the IDE does - the component, its field
  and the form lines that name it - and an agent did not find it (on
  Hermes, 19-oct-2026). The refusal names it now.
- **The form renderers printed their usage line as `%s --path ...`** with
  "(No argument for format)" behind it: the line has two forms, each with the
  program's name, and only one name was passed. Measured on 20-oct-2026 with
  the production renderers; nobody reads it but an operator, who now gets
  the name.
- **`delphi_git command=config` could not read the identity it sets.**
  Without `message` it answered `GIT-033` ("config needs the value"), so an
  agent had no way to know which name and e-mail its commits would carry
  short of committing and reading the log. Now `config name=user.name` (or
  `user.email`) without `message` reads the value a commit here would use -
  the repository's, or the global one of the server's account - and a key
  that no config has is said as such (`GIT-079`, not an error) with how to
  set it. Reading is a query: it takes no write lock and works in a
  read-only root, where setting is still refused. Any other key is still
  refused, to read or to write (`GIT-024`). `test_git_config_lee_1211`,
  red against 1.21.0.
- **`delphi_references` and `delphi_rename_symbol` said where they looked
  but not with which project.** Both answered `scope` (the folders searched)
  and not whose settings the engine resolved with; with two copies of the
  same project in the workspace - the usual case - an agent could not tell
  which one its uses came from. Both now name it in `project`, as
  `delphi_diagnostics` already did, read by one helper for the three
  (`ProyectoDeLosAjustes`). `test_refs_proyecto_1211`, red against 1.21.0.
- **`delphi_completion` ignored a `trigger` the engine does not complete
  on, without a word.** A letter (`S`, `Z`) changes nothing - the answer is
  the one without it, measured - and an agent read it as a bug twice (on
  Hermes). The answer now says so in `triggerNote` (`LSP-047`) with the
  characters the engine announces; the judge is the engine itself, the
  `triggerCharacters` of its `initialize` answer (`. ( < [` for the 37.0
  agent), not a list of ours. `test_completion_trigger_1211`, red against
  1.21.0.
- **A unit missing under its bare name sent the agent to add-searchpath
  when it only had to be qualified.** `uses Dialogs` in a project whose unit
  scope names do not include FMX or Vcl fails with F2613, and `BUILD-042`
  found no folder with a `Dialogs.pas` and said "add the folder, or the
  component is not installed" (an agent on Hermes). When a missing unit has
  no source under its own name, the build now lists in `qualified` the
  scoped names that do exist - `FMX.Dialogs`, `Vcl.Dialogs` - and the note
  says to write it qualified (`BUILD-049`). The judge is what is on disk
  (the `<scope>.<unit>.pas` of the session's roots and of the library zone),
  not a list of scopes; one behind a link that leaves the roots is not
  offered. `test_build_cualifica_1211`, red against 1.21.0.
- **A hard link inside the roots read a file outside them.** A hard link is
  the same file under another name, and the jail judged the name - and its
  real path, which for a hard link is its own. Measured on 20-oct-2026
  against 1.21.0 with a hard link to a file outside every root:
  `delphi_read` and `delphi_search` read it, and `delphi_styles build`
  baked it into the `.res`. The read gate now asks Windows for the other names
  of a file that has more than one (`FindFirstFileNameW`) and refuses it
  when one of them is outside what the session can read (`GUARD-041`), or
  when they cannot be listed (`GUARD-042`); a hard link whose names are all
  inside - the roots or a reference - is read as before. It judges READING
  (read, search, fetch, copy, the edits that read first, the files a build
  includes - `{$I}`, `{$R}` - or a style names): deleting or moving that
  name does not touch the other one and is still allowed. A file with one
  name costs one open that reads nothing. `test_enlace_duro_lectura_1211`,
  red against 1.21.0.
- **The copies the server makes on its own read a hard link, and
  `delphi_upload` wrote through one.** Measured on 20-oct-2026 with a hard
  link in the roots to a file outside them: `delphi_upload` over it wrote
  the uploaded bytes INTO the file outside - upload writes into the file,
  with any offset, where every other writer puts a new file in place with a
  rename - and the copies the server keeps before replacing or moving a file
  (upload's sealed copy, the trash copy of `delphi_move`, the `.res` that
  `delphi_styles build` replaces) and `copy=true` of a folder took that
  file's bytes into the roots, where the read gate refused them. Upload now
  refuses a file with more than one name (`GUARD-043`: delete this name
  first). The copies ask the read gate's question about the other names: a
  move takes the name without a copy, as it does with a symlink; a folder
  copy leaves it out and lists it (`FILE-032`); a styles build over it is
  refused before anything runs, and anything else that would replace it
  keeping a copy, before it is touched (`GUARD-041`, `GUARD-042`).
  Deleting such a name was already safe: the trash keeps the name, not a
  copy. `test_enlace_duro_copias_1211`, red against 1.21.0.
- **`delphi_edit` INSERT with two routines in `code` wrote the second as it
  came and said both halves were done.** With `insert=metodo`, only the
  first routine was declared in the class and qualified; the second went in
  as a global routine nobody declared (E2003 at the next build). With
  `insert=rutina-global visible=true`, only the first reached the
  interface. Found by Hermes in the validation of 1.21.1 and measured in
  production. `code` is one routine, as its description says: a block with
  more is refused now (`EDIT-129`) naming them, and nothing is written.
  The routines are counted by the house reader (`Lsp.PascalDecl`), so a
  local routine nested inside one does not count. `test_insert_una_rutina_1211`,
  red against 1.21.0.
- **A path written with forward slashes could be read but not written.**
  `delphi_edit` and `delphi_textedit` of `D:/dir/file.pas` (or `srvd:/...`)
  were refused with `GUARD-037` - "some part of the path is a LINK" - when
  there was no link, right after `delphi_read` had read the same path (Hermes,
  in the validation of 1.21.1; measured in production). Windows takes `/`,
  but the functions that cut a path into folder and name only see `\`, so
  the writer's real folder came out as the drive itself. The entrance now
  gives every absolute server path (`[RutaDelServidor]`) one form, with
  `\`, for every tool at once - where it already turned 8.3 names into long
  ones; a path outside the roots is still refused as outside.
  `test_rutas_con_barra_1211`, red against 1.21.0.
- **`delphi_references` did not list the uses in the form files, which its
  sibling `delphi_rename_symbol` sees and blocks on.** For an event handler,
  references answered the two lines of the `.pas` and nothing about
  `OnClick = Button1Click` in the `.dfm`, while rename at the same position
  refused with `RENAME-019` because of that line (Sonnet, in the validation
  of 1.21.1; measured with its exact calls). An agent measuring the impact of
  a change with references counted fewer places than there are. References
  now lists them in `designer`, grouped by folder and file like the others,
  with their line, and says what they are (`LSP-048`). Both tools walk the
  form files with one helper (`UsosEnDisenadores`): rename counts and
  blocks, references lists. `test_rename`, red against 1.21.0.

## [1.21.0] - 2026-10-19

Measured on real projects and on the Samples, and checked by Hermes
(Qwen3.8 Flash Next) on Delphi 13.2 before publishing: a targeted pass,
the full test, and three rounds on what they found. A new capability:
`delphi_config set-active`, the configuration and platform a project
builds by default (the IDE's *Activate*); `delphi_build` and
`delphi_test` without `config=` build the one the project has selected.
The engine runs with the settings of that configuration and platform, a
project `delphi_create` makes is born with the configurations the IDE
writes, and the IDE's form reader judges what a form says - its lines,
its numbers, in the language of Windows - so the designer reads the
Samples without a false warning. A `.rc` is read by tokens and everything
it names stays inside its styles folder; `delphi_git push` never forces.
What the server kills, it cleans: no process left behind fills Windows'
global atom table (it took a whole machine down while testing), and the
form renderers put nothing on the desktop - no taskbar window, no dialog,
no focus taken; a component that opens a dialog at design time answers
`RENDER-022` in a second. From Hermes's full test: `delphi_styles`
refuses what FMX could not load, `preview state=` names the form's own
class, `delphi_test filter` says what DUnitX matches, and `LSP-005` gives
the line in both counts.

### Fixed

- **The server's machine could stop starting processes at all: what we
  kill, we clean.** Measured 18-oct-2026, 23:33: the release gate ran the
  237 batteries and 195 of them died at once with 0xC0000142
  (STATUS_DLL_INIT_FAILED), the desktop full of "Delphiformrenderfmx"
  windows, and the whole machine needed a reboot. The global atom table of
  the session (16384 entries, shared by every process) was at 16320. A VCL
  or FMX process registers atoms when it starts (`Vcl.Controls`:
  `Delphi<pid>` and `ControlOfs<HInstance><tid>`; `Vcl.Dialogs`:
  `WndProcPtr<HInstance><tid>`; `FMX.Platform.Win`: `FIREMONKEY<pid>_<tid>`;
  and one more per runtime package it loads) and only its finalization
  deletes them: a process killed with `TerminateProcess` leaves them until
  Windows restarts. 3,894 of them were server copies of the batteries (the
  exe carries VCL for the tray) killed by the harness with `proc.kill()`;
  about 1,000 were renderers that had loaded the IDE's design packages and
  ended NORMALLY: the units of a package loaded with `LoadPackage` only
  finalize with `UnloadPackage` (and unloading the design packages outside
  the IDE crashes), so the copies of VCL and FMX inside `vcl370.bpl` and
  `fmx370.bpl` left their six atoms on every render with packages (measured
  by hand: +6 with packages, 0 without). Now:
  - `Lsp.AtomosRtl` is the one house of that form (there is no judge to ask:
    Windows does not know whose an atom is; `test_paisaje` watches it). After
    every kill of ours - the deadline of `RunCapturedIn`, the Job of a
    `delphi_test`, the stop of the engine, the renderer's watchdog before it
    kills itself - the atoms of the dead process (its pid, its main thread)
    are deleted, and never those of a pid or a thread that has not
    terminated (existing is not enough: a dead process exists while anybody
    holds a handle, and its id is not reused meanwhile). And the renderers
    delete their own atoms as the very last thing before `ExitProcess`,
    after every finalization: what is still there with their pid is the
    packages' copies', which nobody else will ever delete.
  - The harness stops its servers instead of killing them: `lanza_http`
    returns a process whose `kill()` is CTRL_BREAK (the server's console
    handler stops the HTTP server and finalizes), the real kill only after
    15 s; the 81 `proc.kill()` of the batteries need no change. `run_all`
    counts the atoms of dead processes before and after the suite and fails
    if the batteries left any; `test_atomos_1202` measures the watchdog, the
    stop of a server, and a control that does leak.
- **The FMX renderer put a window on the taskbar.** With the IDE's design
  packages loaded (a form with installed components) FMX created its
  application window (`TFMAppClass`, `WS_EX_APPWINDOW`, visible) as soon as
  a package asked for `Application.Handle`: the "Delphiformrenderfmx" entry
  seen seven times at once during the corpus (its eight threads). Measured
  with `EnumWindows` and the window's module: the renderer has TWO copies of
  FMX - the one linked into the exe and the one the design packages bring in
  (`fmx370.bpl`) - and the window was the second copy's, created inside the
  initialization of `dclfmxstd370.bpl`, which installs the IDE's own handle
  hook (it answers 0 outside the IDE). Both renderers (the VCL one loads
  those packages too) now hand both copies a hidden window of their own
  through the hook the IDE uses for the designer
  (`RegisterApplicationHWNDProc`; the package's export is found by the name
  of the routine, not by its decorated name), re-apply it around every
  package, and a window guard on the main thread (a CBT hook) makes any
  `TFMAppClass` still created be born as a tool window, without
  `WS_EX_APPWINDOW` and without activating. Measured at 5 ms: no visible
  application window of a renderer, ever, and no focus taken.
- **A component's dialog hung the renderer and reached the desktop.** Half
  of the FireDAC demos in the Samples keep a connection `Connected` (or a
  dataset `Active`) against a definition the machine's ini does not have; at
  design time FireDAC raised and showed a MODAL message box - one per lint,
  on the desktop, taking the focus - and the renderer waited behind it until
  its deadline (RENDER-007, 60 s). The same window guard refuses every
  dialog window (`#32770`: MessageBox, TaskDialog, the common dialogs; and
  the VCL's `TMessageForm`) and every activation: the code that opened it
  goes on as if it had been accepted, the render ends in a second, and the
  answer carries `[RENDER-022]` naming the dialog. The corpus battery now
  watches the desktop while it runs (application windows, dialogs and focus
  of the renderers: all zero), which no battery did before - only a person
  at the screen could see it.
- **`delphi_styles set` wrote a value FMX cannot load at all, and `lint`
  called the folder clean.** The judge since 1.20.1 is FMX's own reader (the
  converter's `check`), and it reported what FMX skips; when the reader
  RAISED instead - `TextSettings.FontColor = $FFFF0000`, `EReadError:
  Invalid property value` - the converter exited with its error and the
  server took that, the strongest verdict, for "could not ask": `set` wrote
  it, `lint` said clean, and only `build` refused the style (Hermes, the
  full test of 1.21.0). Now `set` refuses such a change with FMX's error
  (`STYLE-053`, nothing written) when the file loaded without it, and
  `lint` lists the styles FMX cannot load in `fmxCannotLoad` and is no
  longer clean (`STYLE-054`). A text that does not even parse stays with the
  IDE's parser and its line (`DSGN-124`). And `STYLE-019` gave
  `$FF2A2A2A` as the example of a color - one of the values that breaks the
  load: the example is the form the file writes, `xFF2A2A2A`.
- **`delphi_designer preview state=` named the renderer's own class.**
  `[RENDER-012] state: TFormOculta does not publish AnchoTotal` - the
  renderer builds the root of a form as a class of its own, and the three
  `state` refusals that name a class took it from the object. They name the
  class the FILE writes now: the root's from its header, a substituted
  component's or an inline frame's as the reader found it, and the real one
  for the rest (`TFont`). Hermes spent four calls looking for a
  `TFormOculta` in its project (the full test of 1.21.0).
- **`delphi_test` with a `filter` DUnitX does not match said only "no
  tests".** DUnitX matches the start of a fixture's full name or a test's
  full name - its `TNameFilter`, no wildcards - and with nothing matched it
  runs zero tests and exits with 0. Hermes tried `*WritesFile` and
  `WritesFile` before the full name. The `filter` parameter says what it
  matches, and a run with a `filter` that ran nothing adds `filterNote`
  (`TEST-035`).
- **The column refusal of the position tools gave the line in one count
  only.** `LSP-005` said "line 16" in the 0-based count the tools take and
  showed that line's text, which is line 17 of `delphi_read`: it says both
  now ("line 16 (line 17 in delphi_read)").
- **`delphi_git push` could FORCE the remote.** Since 1.19.0 the `ref` of a
  push was judged only by git - the name of a branch or tag that exists
  here -, and `check-ref-format` accepts `+main`: after `delphi_git tag
  name="+main"` (git and the tool accept that name), `push ref="+main"`
  sent `git push origin "+main"`, which git reads as "force main", and the
  history of the remote was rewritten (measured: `+ d9d8cb9...765a884 main ->
  main (forced update)`). A `ref` that starts with `+` (force) or `:`
  (delete) is refused by its form before git is asked, in the judge of push
  and again in its second barrier. The three batteries that claimed to watch
  it passed only because no ref was called `+main`; one now creates it,
  with the history diverged, and checks the remote. Push adds to the
  remote, never overwrites or deletes.
- **The engine runs with OUR settings, made for the configuration and
  platform the project has selected (Win32 for one that is not Windows:
  Code Insight is a Windows front end), and a running engine gets them
  again when they change.** Measured on 17/18-oct-2026, four faults behind one
  door, the settings file the engine runs with (`.delphilsp.json`):
  - The IDE's own was preferred while it named a project that existed. The
    IDE rewrites it only when it reloads the project, and nobody opens the
    IDE on a server: after `delphi_config add-searchpath`, `delphi_diagnostics`
    kept answering `F2063` for a unit in the new folder and
    `delphi_definition` answered null, until somebody opened the IDE. And a
    copy of a project carried one naming the ORIGINAL: the unit of the copy
    resolved into the original's folder. It is never read now.
  - An engine already running never got new settings: they went to it once,
    when it started. `add-searchpath` was not seen, with ours either, until
    the server restarted. The settings are made again on every request,
    outside the lock that keeps their writer, written to the server's cache
    only when they change, and given again to a running engine, which
    reloads them (measured: 0.2 s the agent, 0.6 s the linter; its compiler
    too, Win64 to Win32 on the same engine); the linter lints the same text
    again with them.
  - Ours chained every `DCC_Define` of every configuration - DEBUG and
    RELEASE at once, a configuration that does not exist - and lacked the
    `FRAMEWORK_<type>` that msbuild adds (`CodeGear.Delphi.Targets`). The
    judge, msbuild, on the IDE's own VCL template: an error under
    `{$IFDEF FRAMEWORK_VCL}`, which dcc reports in every configuration, was
    invisible to `delphi_diagnostics`, and one under `{$IFDEF RELEASE}` was
    reported in Debug. The properties now come from the build's evaluator
    for the selected pair, a `$(DCC_Define)` inside a value being what the
    groups before it said (as the IDE writes the defines of each
    configuration); the unit paths are the ones the IDE gives its own engine
    and msbuild compiles with - with `DCC_DebugDCUs` the IDE's Debug DCU
    Path first, then the project's search path, then the Library Path
    (`lib\<platform>\release` first; measured against the IDE's own
    `.delphilsp.json` of six new projects) -, the macros of a project's
    search path are expanded with the IDE's table (a `$(BDSCatalogRepository)`
    there was dropped), and the navigation folders are the IDE's Browsing
    Path from the registry instead of a list of 14 folders written by hand.
  - The project of a unit was the first `.dproj` whose TEXT carried its
    name. A unit its project reaches by search path had none (`LSP-035`,
    nothing linted), and with two copies of a project side by side the
    shared unit of one was linted with the other's project. A project now
    serves a unit when its `.dpr`/`.dpk` lists it by its path (or the unit
    is its main source) - the judge `delphi_move` already used -, and one
    that only reaches the unit's folder by search path, the judge of
    `delphi_references`, serves it when no project lists it. A single
    `.dproj` in the unit's folder or above still governs it; among several,
    the one that lists it. Only what one of these judges decided is cached,
    and the cache follows everything the answer was decided on: every folder
    walked, up and down (a project that appears there changes it), and every
    `.dproj` judged with its `.dpr` - with only the chosen one's stamps, a
    second project that lists the unit, created beside the first, was not
    seen until the server restarted. (A first version put the two
    judges at one level and lost the main source: with two `.dproj` in a
    folder, `B.dpr` was linted with `A.dproj`, and a demo below that reaches
    the folder by search path won over the project above that lists the
    unit - review of 18-oct, both red before the fix.) `LSP-021`, `LSP-014`
    and `LSP-038` no longer send the agent to the IDE's json: they say what
    serves a unit, and `LSP-035` its remedy (`add-unit`, `add-searchpath`).
- **`delphi_build` and `delphi_test` without `config=` build the
  configuration the project has selected**, as the IDE and msbuild do, as
  they already did with the platform; it was Debug, written by hand. The
  answer says which one (`config`). `config=Base` is refused with its own
  `CFG-120`: Base is what the configurations inherit from, the IDE does not
  build it, and it built into `Win64\Base\` with the base settings. A
  selected configuration the project does not declare says so (`CFG-121`),
  not "does not exist" of a name the agent never sent. A `config` of blanks
  was taken as "none" by the judge and reached msbuild as `/p:Config=" "`,
  which builds with the base settings. The schemas no longer advertise
  `Debug` as the default of `config`; `delphi_test discover` says the
  `config` next to the `platform` that `run` will use, and no longer takes
  `config=Debug` / `platform=Win64` for its schema's defaults (one was
  refused, the other passed in silence).
- **A project `delphi_create` makes is born with the configurations the
  IDE writes.** Compared group by group with projects the 37.0 IDE had just
  created (VCL, FMX, console, package, DUnitX): 1.20.1 aligned only the
  version information, and a new project had no Debug or Release groups at
  all - no `DEBUG` or `RELEASE` define, none of the debug information,
  optimization, range and overflow checks of each -, no manifest, no icon
  and no per-monitor DPI. They are written now as the IDE writes them, with
  its keys (`Cfg_1` is Debug), the console target of a console, the
  Android permissions of an FMX, the DUnitX folder of a test project; and
  the console, package and test projects no longer carry the VCL unit
  scopes, which the IDE does not give them. What stays ours on purpose: the
  output folders (the build gate wants them declared), Win32 and Win64
  enabled, and neither the list of packages installed on the machine nor
  the groups of platforms the project does not enable.
- `delphi_config add-searchpath` on the base group suggested
  `delphi_build {platform:"Win64"}` whatever the project; it names the
  project's own platform now.
- The lint said an FMX **view** (`<unit>.<View>.fmx`) did not load: the
  renderer read it on its own, and every `inherited` child gave "Ancestor
  for 'X' not found" - 31 of the 78 views of the Samples, and `delphi_edit`
  after any change to a view warned that "the app dies creating the form".
  The IDE loads a view on top of its master, and declares it in the master's
  `.pas` with `{$R *.<View>.fmx ...}`: the renderer reads that directive and
  loads the master first, like the IDE (lint CLEAN, preview drawn). A form
  read WITHOUT one of its ancestors (no `.pas` next to it says which class it
  inherits from) is no longer "does not load": the lint says it
  could not be confirmed (`DSGN-154`), and preview says what was skipped may
  be what the missing ancestor brings (`DSGN-156`) instead of "it will not
  open".
- The lint (check-binding) said a component without a published field made
  the form fail to load. `TReader` does not need the field: it creates the
  component when its CLASS is the type of some published field of the class
  chain, or registered. The tables now record what each unit of the
  installation registers when it runs (`RegisterClass`, `RegisterClasses`,
  `RegisterFmxClasses` in its `initialization`; generation 14), so a
  `TMainMenu`, a `TComboEdit` or a `TListBoxGroupHeader` without a field -
  four Samples of Embarcadero - is no longer reported. Only when no field
  names its class and no unit registers it is it reported, and the warning
  says it loads only if the program registers it itself (the FMX
  control units register theirs, `Vcl.StdCtrls` does not). A Sample of
  Embarcadero with four field-less `TLabel` was reported as broken.
- What the IDE's reader skips because of an exception that is NOT a reader
  error is no longer a warning of the form. The renderer now says whose each
  skipped exception was (`IGNORED=<reader|class>|...`, the same rule as
  `NOTLOADED=`: `EFilerError` and `EParserError` are the reader's, anything
  else is a component's code in this environment - IBX without `gds32.dll`,
  a `TActionManager` without its style unit, an access violation inside a
  bpl; three Samples of Embarcadero. An exception raised by a property
  setter reaches the reader wrapped as a reader error and stays a warning:
  only what fails while a component is created or named shows its class).
  The lint answers "not confirmed"
  (`DSGN-154`) with the class and the message, and preview says so
  (`DSGN-163`) instead of "the form will fail to open". A reader error that
  names no property - "Ancestor for 'X' not found" - stays a warning. And a
  component that picks its parts by a class name this installation does not
  have (`ItemAppearanceClassName` of a `TListView`, registered by a unit of
  the project, which the reader does not load) is "not confirmed" too, with
  the property and the class, instead of a warning on every property under
  those parts, and only for the properties under those parts: a typo in
  another property of the same component is still a warning.
- The styles `lint` now asks the same judge as `delphi_styles build` about
  every `.rc` (`refused`, with the build's own refusal): a file inside the
  workspace but outside the styles folder exists and build refuses it
  (`STYLE-052`), and the lint said nothing. And `#include "x" // comment`
  is read as `x`: the comment was taken as part of the file name (`STYLE-025`
  in build, `missing` in lint).
- A VCL form with a `TCalendar`, `TMediaPlayer`, `TWebBrowser` or
  `TBindNavigator` - names FMX has too - was reported as not loading: the
  renderer registered the IDE's classes by NAME and skipped the VCL one when
  the FMX one came first, so the reader built a stand-in without its
  properties. Classes are registered as themselves now, and each renderer
  activates its framework's class group before reading
  (`ActivateClassGroup`), as the IDE's designer does: every FMX unit
  activates FMX's group when it initializes.
- The actions of FMX (`TChangeTabAction`, the photo actions), of LiveBindings
  and of data sets came out substituted: the IDE's design core clears the
  action-registration hook when it loads (`ActionEditors`), so each
  `RegisterActions` of a design package failed and cut its `Register` short.
  The renderer sets its hooks again after loading each package, as the IDE
  does.
- With the IDE packages loaded on demand, a first pass that FAILED was the
  answer: a stand-in reading a property of a class it is not (the `Size` of a
  `TStringField`) left the reader mid-stream ("Stream read error") and a form
  with FireDAC fields "did not load". It is read again with the packages, as
  a first pass that only substituted classes already was.
- A data module of an FMX project lives in a `.dfm`, and it was judged as VCL
  ("Property Source does not exist" in its `TImageList`). Its framework is the
  class group the IDE writes in its unit (`{%CLASSGROUP
  'FMX.Controls.TControl'}`, which `delphi_create` writes too): for the lint,
  the tables, `set`, `insert` and preview.
- The reader loads the root of a form into a `TForm` (or a `TFrame`), and
  what only the root's own class has - a `TQuickRep`, a `TForm3D`, a
  `TWebModule`, a data module read as FMX - was reported as not loading. It
  is "not confirmed" now (`DSGN-154`, naming the class), and preview notes it
  (`DSGN-157`) instead of "it will not open". The tables judge it: the root's
  class has the property and the class it is read into does not.
- `preview` with a `state` whose component part ends in a dot (`Label1.=x`)
  took the renderer down with an access violation; it is a shape error now
  (`RENDER-006`). Nine other places took the first piece of a text without
  checking it was there (the same access violation on an empty text); they use
  the shared helper, and `test_paisaje` keeps the bare form out.
- `DSGN-154` (the lint could not ask the IDE's form reader) put the reason in
  the middle of the sentence, and every reason ends in a full stop: the
  agent read "...read the form without it.. preview loads the form." The
  reason goes last now.
- What the root of a designer unit is for the IDE - a form, a frame or another
  module - was decided by a list of class names and, when the chain of
  ancestors left the unit, by the NAME SUFFIX of the last class seen. Measured
  against the 654 designer units of the Samples' projects, it was wrong in the
  39 whose chain leaves the unit: a data module on a user base in another unit
  lost its `DesignClass`, a frame on such a base got an `Application.CreateForm`,
  a `TWebModule` was a form, a form on a `TPanelFrame` was a frame. `add-unit`,
  a unit's rename and the reader's `--root` now ask, in order: the IDE's own
  record (the `<DesignClass>` of a `.dproj` that lists the unit), and the chain
  of ancestors - followed by the engine when it leaves the unit - up to the
  first class the designer table knows, whose category the table's hierarchy
  says. What cannot be judged is said (`CFG-122`) and registered as a form. The
  same name lists went from `check-binding` (a `TForm3D`, `TWebModule` or
  `TQuickRep` root left it partial and silent) and from the renderer (`frame`
  inside a class name made it a frame: the loaded class decides now).
- `delphi_test` answered `pass` for a run whose counts were green and whose
  runner exited with an error. Measured: a DUnitX project that passes every
  test and then raises while it closes exits with code 2, and the run was a
  pass; so was a console runner that prints PASS for each test and sets
  `ExitCode := 3`. Something failed outside the tests it counted - a
  finalization, a leak check, the runner itself. The run is `fail` now, with
  `verdictFrom: exitCode` and a note that says it (`TEST-034`).
- **The IDE's form reader speaks the language of Windows, and the server read
  it in English.** The form helpers are built with runtime packages, so their
  RTL loads `rtl370.de`, `.fr` or `.ja` - installed next to `rtl370.bpl` - on a
  German, French or Japanese Windows (or with the IDE set to that language).
  The server split the reader's message ("Error reading Edit1.FontColor:
  ...") with the English format, and measured with the reader in German
  ("Fehler beim Lesen von ..."), it named nothing:
  - `delphi_designer set` (and `insert` with `props`) of a value the class
    stores by code - the one only the reader can judge - wrote
    `FontColor = -65536` with `ok`, and the form no longer opened;
  - the lint lost the line of what the reader said, and what it skipped from
    a substituted third-party class came out as a reader warning (`EDIT-127`)
    instead of its note.

  The helper now splits the message itself, with the format that composed it
  in its own language, and sends the parts; measured in German, French and
  Japanese (whose format puts the name first). And when the reader does not
  name the value, `set` no longer writes it silently: it asks the same reader
  about the form as it was, as saving asks the form parser. If that loads,
  this change broke it (`DSGN-158`, nothing written); if it does not load
  either, or the reader could not be asked (a literal naming a file outside
  the jail), the value is written and `readerNote` says it was not judged
  (`DSGN-159`).
- A line of a form was an event when its property started with `On`. The
  events of a dataset (`AfterOpen`, `BeforePost`...) and of a web module
  (`BeforeDispatch`) do not, and the table of the framework already knew which
  property is a method. Measured with a `TFDMemTable` and `AfterOpen =
  FDMemTable1AfterOpen`: `check-binding` (and the lint after every write)
  said `clean` with no handler and with the handler in `public` - the form
  does not load: streaming only finds published methods -, `insert=metodo`
  left that handler in `public`, and `delete` of the dataset left its empty
  handler behind. The table decides now, by the class of the object the line
  belongs to (the root, by the class that judges it); the name only where the
  table cannot tell (an item of a collection, a class it does not have).
- `delphi_changeset` refused to stage an edit of a `.dpk` (`CHSET-018`: "a
  project file the IDE maintains; the commit would have refused it anyway").
  A `.dpk` is a source, and `delphi_edit` - the commit's own writer - writes
  it. The stage had its own list of project files; it asks the writer's rule
  now (`.dproj` and `.groupproj` stay refused, for `delphi_config`).
- `delphi_config add-requires` rewrote the whole `requires` clause of a
  package, one name per line, read with its directives blanked out: its
  comments and its `{$IFDEF}` went. Measured with `rtl, // la base` and
  `dbrtl{$IFDEF MSWINDOWS}, vcl{$ENDIF}`: after adding `xmlrtl`, `vcl` was
  required on every platform. The clause is read and written now by the
  reader and the writer of `contains` and `uses`, which keep comments and
  directives in place; one split in `{$IFDEF}` branches is refused, as for
  those (`USES-001`, the same message), instead of guessing the branch.
- Renaming a unit (`delphi_move` to a new name) rewrote EVERY identifier equal
  to the old unit name in the files of the project, not only the unit: a
  record field `Precio: Double` became `UPrecio: Double` when unit `Precio`
  was renamed, the build died with `E2003` and the answer said `MOVED`
  (measured). The name is the unit only in an entry of a `uses` or
  `contains` clause (its branches included) and, outside them, in front of a
  dot (`Precio.Base`); fields, variables and properties of that name stay.
- The section of a unit (`interface`, `implementation`) was found only at the
  start of a line: `adduses` refused `unit X; interface uses A;
  implementation end.` (`USES-007`, "I cannot find the implementation
  section"). The keyword is found where it is in the code now, and a clause
  `adduses` creates there goes right after it, on its line.
- The warning that a routine was inserted inside a method (`EDIT-101`) judged
  by the line above the new header: two declarations in a row in an
  `interface` (the one above ends in `);`) raised it, and a header written
  after `initialization` did not. It is decided now by the reader of the
  unit's routines: inside the body of another one (between its `begin` and
  its `end`), or after the declarations (the main block, `initialization`,
  past the final `end`); the warning says which.
- **Platforms by what they are, not by their name.** Three questions shared
  one answer, and each site spelled the platform family its own way
  (`StartsWith('Win')`, `StartsWith('Android')`, the Android ABI twice):
  - `delphi_config view` said `needsProfileForDeploy=true` for Android, with
    "Android takes no profile" next to it. It is `false` now: an Android
    deploy builds the `.apk` here and `delphi_adb` installs it.
  - `set-profile` wrote a PAServer profile into an Android platform (the
    first Deploy then failed with `E8712 AndroidManifest.xml does not
    exist`, and the next ones answered "Deployed through profile ..." with
    the `.apk` still here), and accepted a Windows profile for `Linux64`
    (`set-sdk` already checked the platform of its `.sdk`). Both are refused
    now (`CFG-123`, `CFG-124` naming the profiles that can), and so is a
    `delphi_build target=Deploy` with such a profile, before compiling and
    before its host is contacted; an Android Deploy no longer reads a
    `<Profile>` the project carries. A profile serves a platform when its
    `Profile_platform` is of the system whose PAServer deploys it (a Mac's
    serves macOS and iOS).
  - `delphi_test platform=WinARM64EC` on an x64 machine built the runner,
    ran it, crashed with `0xC0000005` and blamed the runner. "Runs here" is
    asked of Windows now (`GetMachineTypeAttributes`): `TEST-007` before
    building.
  One table in `Lsp.Dproj` says what each platform is (system, machine,
  Android ABI); the IDE's registry lists the same 13 but not that.
- **A number in a form is what the IDE's own parser reads.** A regex decided
  it, without the suffixes the IDE writes (`41488.4481893519d`, a TDate a
  class writes by code - `AccessTokenExpiryDate` of TOAuth2Authenticator -;
  `34700d` in a Variant; `1.5s`, `12.5c`): `delphi_designer set` refused such
  a value as "not a one-line form value" (`DSGN-092`) without asking the
  form reader, which loads it. The parser says it now, with the type it
  stores. A published float property (a TDate included) still takes no
  suffix - the reader reads it with `ReadFloat`, which does not take them -
  and the refusal says so.
- **A form is read by its lines only where the IDE's parser reads it the
  same way.** The designer and the style tools read and edit a form line by
  line, in the shape the IDE writes it; the IDE's parser reads tokens. A
  form the IDE loads with the `>` of a collection on a line of its own (or
  `end >`, an item and its property on one line, two properties on a line)
  was read with other lines: `lint` said CLEAN,
  `tree` lost the component's `end`, and `set Left=20` wrote a second
  `Left` above the collection and answered ok - the old one, the last, is
  the one the IDE keeps. The parser is asked now, with the line of each
  thing it reads: `tree`, `get`, `layout`, `check-binding`, `preview`,
  `set`, `insert`, `delete` and `delphi_styles` refuse such a file naming
  the line (`DSGN-160`), the `lint` of a form - also the one after
  `delphi_edit` - says it (`DSGN-161`) and the styles `lint` lists it
  (`notInTheIdeShape`); `to-binary` and then `to-text` give it the IDE's
  shape. What comes after the `end` of the root object - an extra `end`
  that closed it early, something pasted after it - the parser does not
  read and the IDE drops when it saves: the `lint` says so (`DSGN-162`),
  and the root is read as the IDE reads it. A list inside a list, as the
  IDE writes it, is now read to its last `)`, not to the inner one's.
- **A property written twice is set where it counts.** The IDE writes one
  twice when a class defines it with `DefineProperties` as well as
  publishing it (`ImageIndex` of an FMX action, `Left` and `Top` of an FMX
  form - 14 forms of the Samples); its reader reads both in order and keeps
  the last. `delphi_designer set` changed the first and answered ok with no
  effect; `set` and `delete` now change every one, and the value read
  (`previous`) is the last. The styles `lint` no longer counts an empty
  `StyleLookup` - the class's default style, which FMX picks without a
  name - as a lookup without a style.
- **A `.rc` is read the way `brcc32` reads it: by tokens.** Two line
  regexes read it - the styles `lint` (`NAME RCDATA "file"` only) and the
  second barrier of `delphi_styles build` (two words and a file) - and
  `brcc32` takes memory flags before the file (`LOGO RCDATA DISCARDABLE
  "x.png"`), the file on another line, two resources on one line,
  `RCINCLUDE`: neither saw them. One reader now (`Lsp.Styles.LeeRc`): the
  `lint` lists every resource whose file is missing, whatever its type, and
  the barrier checks every file the `.rc` names, and anything shaped like a
  path, against the jail before `brcc32` runs. `brcc32` also runs with `-x`
  in its container: the server's `INCLUDE` variable is not a place an `.rc`
  of the workspace looks in.
- **What a `.rc` directive names goes through the jail too.** The reading
  does not follow `brcc32`'s preprocessor, and a `#define F "C:\..."` used
  as a resource's file reached `brcc32` unjudged: the container kept out
  what is sensitive (the server's home, the profile, the roots), but a file
  Windows lets every app package read (`etc\hosts`) went into the `.res`.
  The second barrier now judges every path-shaped token of a directive,
  quoted or not, before `brcc32` runs. And everything a `.rc` names must
  now stay inside the styles folder (`STYLE-052`): `brcc32` compiles a copy
  of that folder alone, so nothing outside it ever worked, and a `..` that
  stayed inside the workspace seen from the `.rc`'s folder climbed out of
  that copy - measured: `etc\hosts` went into the `.res`. This is a
  stopgap until a more restricted token (LPAC) for the container, planned
  for 1.22. `test_estilos_derivados_1182` S15 measures the container on its
  own again (red with `brcc32` run outside it): the barrier now stops S13,
  S14 and S16 first. And the styles `lint` no
  longer says a resource's file is missing when that file is a macro
  (`#define F "x.bin"` / `X RCDATA F`, which `brcc32` expands): since the
  token reader above, it named `F` as the missing file.

### Added

- **`delphi_config set-active config= platform=`**: the configuration
  and/or platform the project builds by default - what *Activate* in the
  IDE's Project Manager writes, the two default lines of the `.dproj` and
  nothing else. Only ones the project declares (a configuration that is
  not `Base`; a platform it has enabled and its framework can target), all
  or nothing (`CFG-115`..`CFG-118`); the same value again writes nothing
  and makes no backup (`CFG-119`). `view` says `defaultConfig` next to
  `defaultPlatform`.

### Changed

- **One reader of the IDE's Library Search Path.** The library zone, the
  engine's settings and `delphi_components` each read it from the registry
  and expanded its macros their own way - three readers of one setting, two
  of them over a hand-written twin of the generic registry reader. They ask
  one now (`IdePlatformLibraryPaths`), with one macro table; measured to
  give the same folders on the 13 platforms of this machine. And the
  conditions of a project's property groups, its value groups and its
  default lines (`<Config Condition="'$(Config)'==''">`) are written by one
  namer each, which `delphi_create`, `add-platform`, `set-active` and the
  build's evaluator share.
- **The engine's settings are composed outside the lock that keeps their
  writer.** It was held for the whole fabrication - the registry, the jail
  for every folder of the search path, a `.dproj` on a network drive - and
  every engine request of every session waited for another's. A lint makes
  them once per request, not twice, and who only asks whether a unit HAS a
  project (the lint, references, rename, the ancestor chain) no longer makes
  them; settings of an older generation in the server's cache are purged.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
- [1.20](docs/changelog/1.20.md)
- [1.19](docs/changelog/1.19.md)
- [1.18](docs/changelog/1.18.md)
- [1.17](docs/changelog/1.17.md)
- [1.16](docs/changelog/1.16.md)
- [1.15](docs/changelog/1.15.md)
- [1.14](docs/changelog/1.14.md)
- [1.13](docs/changelog/1.13.md)
- [1.12](docs/changelog/1.12.md)
- [1.11](docs/changelog/1.11.md)
- [1.10](docs/changelog/1.10.md)
- [1.9](docs/changelog/1.9.md)
- [1.8](docs/changelog/1.8.md)
- [1.7](docs/changelog/1.7.md)
- [1.6](docs/changelog/1.6.md)
- [1.5](docs/changelog/1.5.md)
- [1.4](docs/changelog/1.4.md)
- [1.3](docs/changelog/1.3.md)
- [1.2](docs/changelog/1.2.md)
- [1.1](docs/changelog/1.1.md)
- [1.0](docs/changelog/1.0.md)
- [0.x](docs/changelog/0.x.md)
