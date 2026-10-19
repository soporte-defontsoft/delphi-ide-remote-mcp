# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

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
  for 1.21. `test_estilos_derivados_1182` S15 measures the container on its
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

## [1.20.1] - 2026-10-17

What Hermes (Qwen3.8 Flash Next) found in the targeted rounds of 1.20.0 and of these fixes,
each fix checked again with three rounds on Delphi 13.2 before
publishing. `delphi_config` reads and edits a `.dproj` with one parse -
the one the build uses -, checked against MSXML: `set-output` sets every
group, `set-version` works on a project the IDE made and takes
`include=true` for the IDE's "Include version information", and a
project `delphi_create` makes is born with the version information the
IDE writes. `delphi_styles` asks FMX itself what it would ignore when it
loads a style: `set` does not write it, `lint` and `build` name it.
`delphi_designer preview state=` follows a dotted path, `prop` says what
an integer with named constants takes, `removeuses` takes a library unit
out of a `.dpr`, and several answers now say what happened instead of
something else: the elements of a set, the style a form carries, the file
of an inline image, why a unit has no boundary for `insert`, and
`delphi_config` for a `.dproj` given to the edit tools.

### Fixed

- **`delphi_designer preview state=` follows a dotted path, as `prop` and
  `set` do.** `Label1.Font.Size=14`, `Label1.TextSettings.FontColor=claRed`
  or `FrameF1.RectF.Fill.Color=claRed` were refused with `RENDER-012 ...
  does not publish Font.Size`: the renderer looked the whole path up as ONE
  property of the component. It now walks it the way the RTL reads a form
  (`TReader`): each segment but the last is an object of the component's
  own (a `TFont`, a `TTextSettings`, a `TBrush`) and the last one is set on
  it. A segment the object does not publish names that object's class
  (`TFont does not publish Sise`); a segment that holds a value ends the
  path (`RENDER-020`); one that holds a reference to another component is
  not walked through (`RENDER-021`): in a form file that component is
  written by its Name, so its properties are set by its own Name - the same
  rule `set` applies. Measured by Hermes (Qwen3.8 Flash Next) in the
  targeted rounds of 1.20.0: two refusals for one task.
- **The note of an inline image says what happened to THAT file.** It was
  one sentence for every case - "Its temp file was consumed" - also when
  the agent had named `out=` and its file stayed; Hermes read it as "the
  image is lost" and fetched it again with a download and curl, several
  turns for an image it already had. The note of `delphi_designer
  preview` (`DSGN-071`) and of `delphi_desktop` / `delphi_adb` captures
  (`CAPT-001`) now ends with `CAPT-016` (only the server's temporary file
  was consumed: the image is already yours, in this answer) or `CAPT-017`
  (the file you named in `out=` stays where `screenshot` says). One place
  composes it for the three tools.
- **A value that is not an element of a set lists the elements, as one
  that is not a value of an enumeration already did.** `delphi_designer
  set Font.Style=[Underline]` answered `"Underline" is not an element of
  TFontStyles` and nothing more, so an agent had to know `fsUnderline`;
  it now ends with `valid: fsBold, fsItalic, fsUnderline, fsStrikeOut`,
  for a set of the framework and for one a class of yours publishes.
  Measured with Hermes (Qwen3.8 Flash Next) replicating a form from an image.
- **`delphi_build target=Deploy` answers `"target": "Deploy"`.** It
  answered `"Build;Deploy"` - the targets the server hands msbuild, since a
  Deploy always builds first - and that value is refused as input
  (`BUILD-004`): Hermes copied it from our own answer into its next call
  and we refused it. The answer now says what was asked; msbuild still
  runs `Build;Deploy`, and a battery now checks that a Deploy builds first
  (a bare `/t:Deploy` re-ships the previous binary).
- **A project `delphi_create` makes for FMX no longer carries the VCL unit
  scopes.** One template gave every project
  `Winapi;...;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell` in its Base
  group, so in an FMX project an unqualified `uses Dialogs` compiled
  against `Vcl.Dialogs` on Win32 - and failed on Linux64. The scopes are
  now laid out as the IDE lays them out (measured on the 37.0 samples):
  the common ones in Base, the Windows ones (`Winapi`, `System.Win`...) in
  `Base_Win32` and `Base_Win64`, and the VCL ones never in an FMX project.
  VCL, console and package projects resolve exactly as before on Windows.
- **`delphi_designer preview` says what style the form itself carries.**
  A StyleBook whose only item is empty was described as `the form's own
  StyleBook StyleBook1 (1 items)`, and a `style=` file or platform said
  nothing about the form: Hermes took two previews drawn with `style=` for
  the look of the app, and its StyleBook was empty. `style` now says
  `EMPTY` (the platform default is drawn, and the app runs with it too
  unless its code loads a style), and with `style=` it ends with `for this
  image only: the form itself carries ...` - its StyleBook with N styles,
  an empty one, or none. The parameter's description says the same.
- **`get-sdk` is said to be once per target machine, not per project, and
  the texts name the call that says whether it is already done.** The
  descriptions of `delphi_paserver` and of `delphi_build`'s `platform`,
  and the skill, gave the step ("get-sdk once") without saying how to know
  it was done: Hermes pulled an SDK it already had, and later proposed it
  again for a new project. They now say that `command=platforms` tells
  when it is already pulled (`ready (SDK present)`).
- **Three answers that read as something else.** `delphi_list dirs=true`
  on a folder with files and no subfolders answered `total: 0` and nothing
  more, which reads as an empty folder: it now says how many files there
  are and how to list them (`LIST-014`). `WS-008` said "Directory not
  found" also when `delphi_search` was given a FILE that does not exist,
  and Hermes concluded that `root` takes no files: it now says the path
  does not exist, as neither folder nor file. `maxwidth` was described as
  "the width the image is scaled to"; it is the most width it travels at -
  a narrower capture is never enlarged.
- **`delphi_config set-output` sets the folder in EVERY configuration and
  platform.** It rewrote only the first `DCC_ExeOutput` and
  `DCC_DcuOutput` of the `.dproj`: a project whose Debug configuration sets
  its own folder kept it, and the Debug build landed there while the answer
  said `Compiled` (measured in the 1.20.0 audit; of the 296 `.dproj` of the
  37.0 samples, 192 set it and 5 in more than one group). Every group that
  sets it is now rewritten, the base group gets it when it lacks it, and
  `CFG-081` says what each group had. The writer is the inverse of the
  reader the build uses to find its outputs, with the same parse.
- **`delphi_config set-version` works on a project the IDE made.** It asked
  for `VerInfo_MajorVer`, which the IDE writes only once the version is no
  longer 1.0.0.0, so it refused every new project of the IDE - and 284 of
  the 296 `.dproj` of the 37.0 samples that include the version - with
  `CFG-003` ("This project has no VERSIONINFO"). The build takes the
  binary's version from the `FileVersion` key of `VerInfo_Keys` (measured:
  with the numbers at 2.3.4.5 and the key at 9.8.7.6, the exe says
  9.8.7.6), and that key is what it now needs. A project without the
  numbers gets the four in each group that holds the key, right before its
  `VerInfo_Keys`, as the IDE leaves them. `CFG-003` says what is missing,
  and the answer says when the project does not include the version in its
  binaries (no `VerInfo_IncludeVerInfo`), instead of reporting a version
  the binary does not carry. Found by Hermes (Qwen3.8 Flash Next) in the targeted test
  of 1.20.1; a battery builds the IDE's own templates and reads the version
  of the binary. And `include=true` makes the binaries carry it: it writes
  `VerInfo_IncludeVerInfo=true` in each group that holds the version keys,
  what the IDE's "Include version information" checkbox writes. No tool
  could check that box, so on a console - born unchecked, as the IDE makes
  it - an agent could set the version and never get it into the exe. Found
  by Hermes (Qwen3.8 Flash Next) in the three rounds of the targeted test
  that checked these fixes.
- **A `.dproj` in `delphi_edit` or `delphi_textedit` points to
  `delphi_config`.** The two refusals sent the agent to each other -
  `EDIT-032` to `delphi_textedit`, `TEXT-001` to "the IDE / delphi_create" -
  and neither named the tool that edits a project. Both now answer the same
  `EDIT-128`, which says what `delphi_config` edits. Found by Hermes
  (Qwen3.8 Flash Next) in the targeted test.
- **A project `delphi_create` makes is born with the version information
  the IDE writes.** Its `.dproj` had none - no `VerInfo_Keys`, no
  `VerInfo_IncludeVerInfo` -, so its binary carried no version and
  `set-version` refused it. It now has what the 37.0 IDE writes in a
  project it has just created (measured with one of each kind, made in the
  IDE): the keys in `Base_Win32` and `Base_Win64`, and the version included
  in the binary in every kind but a console or test project, which the IDE
  also leaves unchecked. A console `.dpr` now links its resource
  (`{$R *.res}`), as the IDE's template does: without it the resource the
  build generates - the version, the icon - never reached the exe.
- **`delphi_styles` says what FMX ignores in a text style, and `set` does
  not write it.** FMX's style reader swallows every error while it loads a
  style: a property the class does not publish (`Fill.Color` on a
  `TLayout`), a value it cannot read (`Fill.Color = red`), a class it does
  not know - with everything inside it. `set` wrote them (they pass the
  IDE's parser), `build` made a `.bin.style` without them and answered
  `ok:true`, and the app never saw them. The style converter now repeats
  that load and lists what the reader swallowed, with the RTL's own message
  (`Error reading TLayout.Fill.Color: Property Fill.Color does not exist`):
  `set` refuses a change FMX would ignore (`STYLE-050`, nothing written),
  and `lint` (`ignoredByFmx`, no longer `clean`) and `build` (`ignored` per
  file) name what is already there (`STYLE-051`). Found by Hermes (Qwen3.8 Flash Next) in
  the full test of 1.20.1, who read the binary by hand.
- **`delphi_edit insert` says why a unit has no boundary.** `EDIT-049` blamed
  only "a unit without an implementation section"; a unit that does not read
  as Pascal - a routine BODY in its interface - has none either, and Hermes
  took his empty implementation section for the cause. The message now names
  both and sends to `delphi_diagnostics`.
- **`delphi_edit removeuses` takes a library unit out of a `.dpr`, as
  `adduses` puts one in.** `adduses System.JSON` on a program worked, and
  nothing could undo it: `removeuses` answered `USES-014` and sent the
  agent to `delphi_config remove-unit`, which takes a `.pas`. A unit of the
  project - its `.pas` in the program's tree, or an entry with its `in
  '...'` path - still goes by `remove-unit`, which also removes its
  `CreateForm` and its `DCCReference` (`USES-025`, nothing written).
- **`delphi_config`, the build and a move read and edit project XML with one
  parse, checked against the parser the IDE loads.** Five units read a
  `.dproj`, `.deployproj` or `.groupproj` each in its own way, in 39
  regexes and searches for a tag and a few needles in constants - the exact
  tag with no attributes, "the last group opened before it", the group by
  its `Condition` matched letter by letter, regexes that wanted the
  attribute first and in double quotes and also read what a comment holds.
  Now one reader does it (an element with its own closing even when another
  of its name sits inside, a CDATA read as XML reads it, nothing inside a
  comment), and every tool reads and writes through it, in place. What an
  agent sees:
  - `add-searchpath`, `set-sdk` and `set-profile` find a platform group
    written by hand (`'$(Base_Linux64)' != ''`) instead of creating a second
    one and writing into it;
  - `set-sdk` and `set-profile` take out EVERY `PlatformSDK` / `Profile` of
    the group: they removed only the first, and with two the other one kept
    winning; `before` names the one that was in effect;
  - the SDK and the profile a project declares (`view`, `delphi_build`), and
    the output folders the build checks, are read as msbuild reads them: the
    last value among the groups that apply, an element's own `Condition`
    counts (5 of the 37.0 samples carry
    `<Profile Condition="'$(Platform)'=='iOSDevice64'">` in the
    unconditional group), and an empty `<X/>` leaves the value empty; a
    configuration's group no longer counts as the base;
  - the deployment view, `add-deployfile` and `remove-deployfile` see an
    entry whose `Condition` comes before its `Include` (4 entries the IDE
    wrote in a sample were invisible), an empty `<DeployFile .../>` no longer
    swallows the entry after it, and a group of a platform the server does
    not list any more (`OSX32`) shows as written;
  - `target=Deploy` and `add-deployfile` add the manifest's `<Import>` to a
    `.dproj` whose `CodeGear.Delphi.Targets` import has its `Condition`
    first: they looked for `Project` first, never found it, and the deploy
    failed with `MSB4057` (13 of the 296 samples write it that way, 8 of
    them without that import);
  - `add-platform` and `remove-platform` find a platform written in single
    quotes or with another attribute (3 samples declare
    `<Platform value="Win32" Profile="win_desktop">`: `remove-platform`
    answered that Win32 was not declared while `view` listed it enabled),
    and one inside a comment no longer counts;
  - `set-version` changes `FileVersion` and `ProductVersion` only as keys of
    `VerInfo_Keys`: it rewrote that text wherever it appeared, a build event
    included;
  - `add-unit`, moving a unit and `remove-unit` find a `DCCReference` whose
    `Include` is not the first attribute, is in single quotes or shares its
    line;
  - moving a folder re-points the paths of an attribute in any order or
    quotes, and never one inside a comment;
  - `add-project` / `remove-project` compare target names as msbuild does
    (without case): an aggregate target written `build` got a second
    `Build`.
  `tests/test_xml_familia_1201.py` measures each of these on its own
  project, and each is red against the previous binary.
  Measured against the previous binary on the 296 `.dproj` of the 37.0
  samples and their 27 `.groupproj` (view, platforms, version, deployment
  with the manifest generated from scratch, add-unit, a unit move,
  remove-unit, a folder move, group add/remove; 4,575 steps on each side):
  the same answers and the same bytes but for 24 steps, each one of the
  fixes above - the manifest's `<Import>` (8 projects for Linux64, the 13
  with the anchor written `Condition` first for Android) and
  `remove-platform` on a platform with a `Profile` (3). A move reads every
  project file under the workspace edge, so its speed was measured too: in
  a root of 316 projects, moving a folder takes 2.23 s against 2.48 s and
  moving a unit 2.33 s against 2.49 s.
  Measured against MSXML - what the IDE loads, through `Xml.XMLDoc` - element
  by element on the 4,124 project files of this machine: the same attributes
  and values, 0 discrepancies (the previous reader disagreed in 3,537 of
  the 4,084 first measured). The judge decided one detail: MSXML keeps a
  tab or a line break written inside an attribute (only CRLF becomes LF),
  though XML says they become blanks, and so does the reader. The DOM is
  not the writer: none of the three engines Delphi ships writes a project
  file back byte for byte.
  `tests/test_oraculo_xml.py` keeps the comparison (a planted file with the
  hard cases, and its mutant), and a rule of `test_paisaje` keeps project
  XML out of regexes and `Pos` of a tag anywhere else (39 copies in 5 units
  before).

### Added

- **`delphi_styles lint` names a component whose `StyleName` is the name
  of one of the styles** (`componentsNamedLikeAStyle`, `STYLE-049`).
  `StyleName` names the component itself as a style resource; it does not
  dress it - a control takes a style by `StyleLookup`. Measured with
  Hermes: three containers got the `StyleName` of a style and none was
  dressed, while `set` and `lint` said nothing. It is a hint, apart from
  the findings: it does not change `clean`.
- **`delphi_designer prop` says what an integer with named constants
  takes** (`takes`): for every type whose unit registers names for its
  values - read from the installed source (`RegisterIntegerConsts` and its
  `IdentTo`), so `TColor`, `TAlphaColor`, `TCursor` and those of installed
  components alike. A whole number, the type's own names, and what its
  reader also loads (`xFF00FF00` for a `TAlphaColor`). It is the same text
  `set` gives when it refuses a value, from one function; `prop` said only
  the type, and Hermes had to provoke a refusal to learn the forms.

## [1.20.0] - 2026-10-16

What an agent reads back, measured with Hermes on Delphi 13.2 with two
models (a mixture-of-experts Flash and a dense 27B) before publishing: a
full pass over every tool, then targeted rounds repeated three times per
model on what each fix touched. Answers cost less: a JSON answer no longer
reaches the agent twice, and a `delphi_desktop` gesture says only what it
did, with its image inside one answer. The IDE's own form reader is asked
at every door that writes or shows a form, so a form the IDE would not
load is said with the reader's words and line instead of a renderer
failure. A single `delphi_edit` / `delphi_textedit` takes a block as its
anchor; a parameter that does not go with a command says where it does
go; a property of the other framework is said as such, and a whole number
that does not fit says how the same 32 bits do. `delphi_designer prop`
follows a dotted path as `set` does, a class-typed property points to its
class, and `info filter=` looks one level inside object properties.
Two answers change meaning: `delphi_definition kind=implementation` gives
the body (what `definition` gives), and `delphi_rename_symbol` is not
applicable when the name is inside a string in ANY unit of its scope.

### Changed

- **A JSON answer no longer reaches the agent twice.** Every answer that is
  a JSON object travels as text AND as `structuredContent`, and the MCP spec
  asks the text to be the serialized `structuredContent` - the backwards-
  compatible copy - so that a client can drop one of the two. Ours never
  were equal: the server added `"ok": true` (and `code` on a refusal) to
  `structuredContent` only. Hermes 0.22.2 drops the duplicate exactly when
  the text parses to the same JSON, so it kept both, and EVERY JSON answer
  reached its model twice - measured on 2026-10-16 by running our answers
  through its own renderer: `delphi_workspace` 4,807 characters, the
  `delphi_help` page of `delphi_designer` 20,105. The text now carries what
  is added, at the end of the object, and nothing else changes: the tool's
  own text keeps its form (it is not re-serialized), prose answers still
  publish no `structuredContent`, and a refusal keeps `isError` and its
  `{text, ok, code}`. Through the same renderer: 2,502 and 10,121, half of
  every JSON answer of every tool. A client that reads the text as JSON
  sees one more field, `ok`. (A refusal whose JSON carried its own `ok`
  keeps its text as it was: it travels with `isError`, and a client then
  takes the text.)
- **`delphi_desktop`: what a gesture answers is what that gesture did.**
  Every `tap`, `key`, `type`, `screenshot` and `overview` carried the
  node's whole startup in `nodeOutput` - its libraries, the session's
  cgroup, the scale, the window list twice (it already travels in
  `windows`), the node's own console usage, and a `CAPTURE=` line with the
  node's folder on the target: about 1,300 characters on every gesture,
  measured on 2026-10-16 in Hermes' history (228 gestures and captures, 215 with that
  path). Two of those cost it steps: it called the tool with
  `command=tecla` and `escribe`, words of the node's console usage, and it
  passed the node's capture folder as `out=`. Now a gesture or a capture
  that worked keeps only what the node said about it - the action
  (`CLICK at pixel ...`, `KEY ... sent`, `WRITTEN ... (the focus is NOT
  verified ...)`) and any warning (`FALLBACK:`, a channel that never got
  ready) - and with nothing to say `nodeOutput` is left out. `status` and
  a failure keep the node's diagnostics; no answer carries the capture
  path, the window protocol lines or the console usage. The startup lines
  are named by their ids in the node's own catalog
  (`NodeProtocolo.inc`), and `test_catalogo` checks every one is a note,
  never an action or a failure.
- **A single `delphi_edit` / `delphi_textedit` takes a block as its anchor.**
  An `old` of several consecutive lines was refused (`EDIT-001`: "the anchor
  of a SINGLE edit is ONE line... send it in `edits`") while the engine
  already applied exactly that as an `edits` entry. Measured in Hermes'
  history on 2026-10-16: 14 refusals (10 with the 27B, 4 with Flash Next),
  12 of them fixed on the very next call - one call lost every time - and
  Claude hit it twice the same day. Now such an edit IS the one-entry batch:
  the block is found whole and in order and replaced (`delete:true`, or an
  empty `new`, removes it), `atline` is the line where it starts when it
  appears more than once, and `toline` with a block is refused as in `edits`
  (`EDIT-020`). An anchor of ONE line works as always.
- **A parameter that does not go with the command says where it does go.**
  The eleven tools with several modes refuse a parameter their mode does not
  take (`DSGN-047`, `EDIT-115`, `CFG-110`, `GIT-038`...) and listed what that
  mode takes. A small model that FORGOT the command read "`path` does not go
  with command=info" - info being only the default: 4 of the 10 such
  refusals in Hermes' history (measured on 2026-10-16). The answer now adds,
  from the same table, the modes that do take it: everything that was sent,
  when one mode takes all of it (`What you sent (path, maxdepth) goes with:
  tree.`), or else the parameter itself (`"code" goes with:
  insert=rutina-global, insert=metodo.`). Parameter names only, never a value.
- **`delphi_designer`: a property of the other framework is said as such,
  and "Did you mean" only proposes what exists.** Of the property refusals
  in Hermes' history that were not its own border tests, half were the
  other platform's property - `Alignment` on an FMX `TLabel` (21 warnings
  over two edits), `Caption` on an FMX `TButton`,
  `Position.X` on a VCL `TLabel` - and the near-name guess got two of three
  wrong: "Did you mean Action?" for `Caption`, `Hint.Color` for `Font.Color`
  (`Hint` is a string). The judge of a property - `set`, `insert`, `lint` and
  the warnings after an edit - now asks the table of the OTHER framework of
  the same install whether the class of the same name publishes it (`"Alignment"
  is what the VCL TLabel publishes; this form is FMX`), from the segment that
  fails (`TextSettings.Font.Color`: the VCL `TFont`'s). When that applies
  there is no near-name guess, and a guess is made only when the whole path
  exists. The first time the other framework's table is needed it is read:
  about 0.9 s and 78 MB for the VCL one, once per process. 300 such lines
  add 11 ms and 19 KB to a `lint`.
- **A whole number that does not fit says how the same 32 bits do.**
  `TextSettings.FontColor = $FF00A152` - an ARGB colour written by hand - is
  more than the form loader's signed 32 bits, and `DSGN-093` (and the `lint`
  line) said only the limit: Hermes took six calls to get out of it on
  2026-10-16 and ended up writing `-16735918`. Now the answer computes the
  way out: the same 32 bits as a signed number, and - when the type's own
  reader also takes `x` and a hexadecimal, as `TAlphaColor`'s does, read from
  its source - that form first (`xFF00A152`, the way the IDE's own forms
  write it).

### Fixed

- **An inline image always fits in one answer.** Over HTTP the whole
  answer of a tool travels as ONE server-sent event, and the MCP Python SDK
  2.x reads events with `httpx2`, which drops one over 1 MiB: the call
  ended in `SSE stream ended without a response`. A 3440-wide desktop with
  a photo as wallpaper, scaled to 1280, is a 972 KB PNG - 1.3 MB in base64
  - and Hermes lost three screenshots of its Zorin that way on 2026-10-16
  (another client without that limit got the same image). An inline image
  now weighs at most 737,280 bytes: the PNG when it fits, otherwise the
  SAME image - same width and height, so `frame`, `inlineScale` and every
  tap measured on it are unchanged - as JPEG at quality 85, 70 or 55; if
  not even that fits, it comes as a file with its link (`CAPT-014`). A
  model counts an image by its pixels, so this saves no tokens: it makes
  the image arrive. One place for every tool that captures (`delphi_desktop`,
  `delphi_adb`, `delphi_designer preview`).
- **`preview` of a form the IDE cannot load says so, with the reader's own
  words and the line.** It answered `DSGN-061 INTERNAL` - "the renderer
  could not draw" - for a file the agent had written wrong, eight times in
  Hermes' history. Now the renderer tells the server when the failure came
  from the form reader itself (the RTL's `EFilerError`/`EParserError` while
  loading) and the answer is `DSGN-153`: the file, not the renderer, with
  each thing the reader said and the line it names (`line 15: FontColor =
  -65536  ->  Error reading Edit1.FontColor: Invalid property value`). And
  the real cause no longer gets lost: a number that does not fit a published
  property (`TextSettings.FontColor = $FF00A152`) was skipped by the
  renderer's Ignore without being consumed, the reader lost its place, and
  all that came out was `Stream read error`. What the reader skipped now
  comes out on a failure too, and the first line of the answer is the
  property that broke it. `DSGN-061` stays for what is really ours: a design
  package or a component that fails while painting.
- **A value only the IDE's reader can judge is judged by it - in `lint`,
  after `delphi_edit` and the changeset, and in `delphi_upload`.** A
  property a class stores by code (`DefineProperties`: `FontColor` or
  `HorzTextAlign` on an FMX `TEdit`) has no type in the tables, so its value
  went unjudged: `designer set` already asked the IDE's reader (`DSGN-149`),
  but `delphi_edit` wrote `FontColor = -65536` without a word and `lint`
  answered `CLEAN` for a form the IDE would not open (measured in production
  on 2026-10-16). Now, when the tables find nothing wrong and leave a line
  unjudged, the form goes whole to the same reader: `lint` says `CLEAN` only
  if it loads (`DSGN-154` when it could not be asked), and a write that
  leaves a form the reader does not load gets `EDIT-127` with the reader's
  words and the line. Counted over 4,938 real forms (the IDE's samples and
  ours): nearly every form has such a line - `Explicit*`, `Left`/`Top` of a
  non-visual, `DesignerMasterStyle` - so a form write costs one load of the
  form (0.3 s on a plain form, about 1 s with 112 design packages, 5 s the
  first time), done after the server's write lock is released, never under
  it. `delphi_upload` now judges a text form like `delphi_edit` does
  (`designer` in its answer) once the file is whole - the IDE's parser reads
  it, or the chunk carries `sha256`; it judged none before. What the reader
  skips from a class that is not installed is not a warning: that is
  `DSGN-039`'s note.
- **`delphi_rename_symbol` blocks on a string with the name in ANY unit of
  its scope.** Its description promises that a hit inside a string literal
  (`FindComponent`, RTTI or `StyleLookup` by name) makes it not applicable,
  but only the strings of the files it was going to edit were looked at: a
  `'Saluda'` in another unit was a mere warning (`RENAME-007`) and the rename
  was applicable - leaving that lookup pointing to a name that no longer
  exists, with the compiler silent. Hermes found it in the pre-release
  validation of 2026-10-16. `delphi_references` now counts apart the
  mentions that fall inside a string, by the lexer, in its whole scan
  (`stringMentionsCount`), and the rename blocks on that count
  (`RENAME-020`); its own scan of the edited files is gone.
- **`delphi_definition kind=implementation` is `definition`.** It sent
  DelphiLSP's `textDocument/implementation`, which on a call site answers the
  declaration of the method that CONTAINS the call (`ShowMessage` inside
  `TFormMain.Greet` -> `Greet`), measured on 13.1 and, by Hermes, on 13.2;
  the description said it answered "like declaration", which stopped being
  true when `declaration` started chaining through `definition`. The
  implementation of a symbol is its body, which is what `definition` gives.
- **`delphi_designer prop` follows a dotted path, as `set` does.** It looked
  the property up on the first level of the class only, so
  `prop TLabel fmx TextSettings.HorzAlign` and `prop TLabel vcl Font.Size`
  answered "is not a published property" (`DSGN-016`) for what `set` writes
  without complaint. Measured in the pre-release rounds of 2026-10-16: the
  27B model guessed `TextSettings.HorzAlign` right, checked it with `prop`
  BEFORE writing - what the tool's description asks for - and was sent
  looking for a class that does not exist; the model that wrote without
  asking got there in one call. `prop` now asks the same judge as `set`: down
  a class-typed property and into the descendant its instance holds, with
  the enum's members at the leaf; what does not exist comes back in the
  judge's words, with the other framework's hint. A class-typed property
  points to its class (`DSGN-155`: `command=info classname=TTextSettings`
  lists its own), as Delphi's help links a property to its type - never an
  equivalence between frameworks. And the list of what a class publishes in
  a "does not exist" (`DSGN-087`, the lint), which comes cut from the table,
  ends with the way to the whole one: `info classname=... framework=...`.
  `info` with `filter` now also looks one level inside the object properties
  (`filter=Horz` on an FMX `TLabel` finds `TextSettings.HorzAlign`, dotted as
  `set` writes it): it said "the class simply has no such member" (`DSGN-048`),
  and a hand-written coda ("an FMX text control keeps its font in
  TextSettings") stood in for the table in one case - it is gone. On a class
  that publishes nothing itself (`TTextSettings`, where `DSGN-155` leads),
  the filter searches what its descendants publish: it said "no such member"
  next to a `descendantsPublish` that listed `FontColor`. A property
  that holds a REFERENCE to a component (`PopupMenu`) is not opened and gets no
  `DSGN-155`: whether a class-typed property is an object of its own or a
  reference is one rule (`EsObjetoPropio`), the one `set` already used, now
  asked by `prop` and the filter too - and `test_paisaje` watches that it is
  not written again by hand.
- **Three descriptions said what the tools do not do.** `delphi_diagnostics`
  spoke of the settings of `"project"` - a field of its answer - and Hermes
  read it as a parameter (`SYS-015`); `delphi_hover` promised `null` on a
  declaration, while the implementation header answers on 13.1 and both do
  on 13.2; and `delphi_help`'s refusals `HELP-007` and `HELP-002` listed the
  whole registry as "the ones there are" - `vault_*` included in a
  workspace whose `tools/list` has no vault. They now list what `tools/list`
  announces to that session.
- **`delphi_upload` of a form the IDE's parser cannot read says so.** A
  text form uploaded without `sha256` is judged only when the parser reads it
  whole, because a first chunk is not a form yet - and when it did not, the
  answer was `ok: true` and nothing else. Hermes uploaded a whole form with
  its BOM mistyped and found out two calls later with `read` and `lint`. Now
  such an upload carries `designerNote` (`UPLOAD-013`): not judged yet, what
  the parser said and on which line, and that it is expected only if more
  chunks follow.
- **`delphi_upload` no longer invites what it refuses.** Its description
  listed "binary designer files" among what to upload, and the tool refuses
  them (`UPLOAD-002`) - whose text said this server does not read binary
  designers, which stopped being true in 1.1.2. The description no longer
  lists them, and the refusal gives the real reason: upload writes designers
  as text, the shape `delphi_edit` and `delphi_designer` edit; convert first
  (`delphi_designer to-text`) or upload the text form.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
