# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- **The id of a changeset can no longer be predicted from another one.** The
  id is a capability - whoever knows it can commit or roll back that batch,
  and `status` shows every open one without its secret tail - and the tail
  came from `Random`, a 32-bit linear congruential generator: from one id an
  agent could rebuild its state and compute the tail of the next changeset
  another session opened (measured on 2026-10-23: predicted exactly; found by
  Claude Opus 5.5 in its review of the 1.22.0 code). The tail now comes from a
  Windows GUID, in the same form (`tests/test_contratos_1222.py`).
- **`delphi_move` names what the build still reads where the moved folder used
  to be.** Its description promises that what it could not re-point is named,
  and it was silent about a search path that reaches the folder through a
  property of the project (`<My-Path>lib</My-Path>` used as `$(My-Path)` in
  `DCC_UnitSearchPath`) or that is written absolute: after moving `lib` the
  build failed with `F2613` and nothing pointed at the cause (Claude Opus 5.5
  through Hermes, measured on 2026-10-22). Such a value is not rewritten - a
  property can hold anything - but the answer now names it (`MOVE-021`): the
  project, the property as written, where it led and where that is now. Each
  value is expanded as msbuild reads it, by the same expander as the build
  read gate, in every build the project declares (`tests/test_contratos_1222.py`).
- **`delphi_config set-property` says when a `$(X)` in the value will be read
  empty.** A value changed in its place can end up above the definition of the
  property it uses, and msbuild reads a `.dproj` top to bottom: `X` is still
  empty there (measured on 2026-10-22: `DCC_UnitSearchPath=$(My-Path)` above
  `My-Path` gave `F2613`). `CFG-136` now says so and how to write the value
  below it (`tests/test_contratos_1222.py`).
- **Editing a file through a path with other capitals no longer renames it.**
  The atomic writer replaced the file by renaming a temporary over the name it
  was given, so a `delphi_edit` that named `Mcp.Tools.Adb.pas` as
  `Mcp.Tools.ADB.pas` renamed it on disk - git, which ignores case on
  Windows, did not show it (measured on 2026-10-23 on this repository, and
  on the production server with `UCaso.pas` edited as `UCASO.PAS`). Every
  writer that replaces a file now keeps the name as it is on disk
  (`tests/test_contratos_1222.py`).
- **`delphi_designer` takes a component of an inline frame by its path.**
  `preview` named `Frame11.Edit1` as the loader does, and `get`, `set` and
  `delete` answered that it did not exist; `DSGN-078` listed none of them and
  sent the agent to the frame's own file, while the IDE changes them in the
  form, in their `inherited` block. `get` and `set` now take the path,
  `DSGN-078` lists what the form overrides by its path, and a delete or a
  rename of one is refused as part of the frame (`DSGN-083`), not as
  inherited from an ancestor form. A bare name is the form's own, as the
  form's `FindComponent` reads it: with an `Edit1` in the form and another in
  a frame, `get Edit1` gave the frame's and `set Edit1` changed the form's
  (Claude Opus 5.5 through Hermes, 2026-10-23); a bare name that is only
  inside a frame is now refused with its path (`DSGN-017`, `DSGN-078`), and
  `get` heads a frame's component with its path. Those refusals speak of
  inline frames only in a form that has them (`tests/test_contratos_1222.py`).
- **`delphi_designer insert` adds a page to a `TPageControl`.** A
  `TTabSheet` with a page control as its parent was refused (`DSGN-080`: a
  page control takes no controls), so there was no way to add a page but
  writing it by hand; and a `TTabSheet` on the form itself was written,
  though its loader takes its page control from the parent that loads it and
  leaves it without one (measured on 2026-10-23). A page now goes in a page
  control, and only there (`DSGN-168` for any other parent, in `insert` and
  in `set parent=`). Its note no longer says that it lands at 10,10 - a page
  keeps no position of its own (`DSGN-169`), and neither does a control
  that `props` places - and it says which page opens:
  the page control's `ActivePage`, which the IDE saves as the page selected
  when it saves and a program usually sets in code (measured in the IDE on
  2026-10-23) (`tests/test_contratos_1222.py`).
- **`delphi_config add-deployfile` writes what the IDE's Deployment Manager
  writes.** It wrote only the `.deployproj`, which the IDE regenerates from
  the project's Deployment section when it deploys: a file added by the
  server was lost the first time the IDE deployed the project. And it wrote
  Debug and Release, absolute outside the project folder, in a new group on
  each call (measured in the IDE with David on 2026-10-23). It now writes
  the entry in the `.dproj` as the Deployment Manager does - relative to the
  project, `..\` included, absolute only from another drive; ONE
  configuration, the active one or `config=`; class `File`, its platform,
  `RemoteName`, and `.\sub\` for a `remotedir` - and the same entry in the
  `.deployproj` msbuild deploys from, where the IDE would generate it (the
  root and class folder the project declares), both or neither - a
  `.deployproj` generated for it, and its `<Import>`, included.
  `remove-deployfile` takes it out of both (`config=` narrows it) and leaves a
  platform group it empties as the IDE writes it, `<ItemGroup .../>`, and
  `view section=deploy` reads the project, with the files added only to the
  `.deployproj` apart (`CFG-144`: msbuild deploys them, the IDE drops them)
  (`tests/test_contratos_1222.py`).
- **One judge of a configuration for `delphi_build`, `delphi_test` and
  `delphi_config`.** There were two: on a project that declares no
  configuration (one from before platforms) `delphi_build config=Debug`
  built while `delphi_config add-deployfile config=Debug` was refused with
  `CFG-116` "(none)", and `add-deployfile` without `config=` took the selected
  one without judging it (Claude Fable 5.1 through Hermes, 2026-10-23). Now
  every command picks the configuration the same way - the one given or the
  selected one, its name checked, not `Base`, one the project declares (any
  valid name when it declares none, as msbuild) - and a configuration the
  project does not declare is `CFG-107` everywhere; `CFG-116` is gone
  (`tests/test_contratos_1222.py`).
- **What runs on a target is what the operator allowed, and only that.**
  Claude Fable 5.1 measured through Hermes (2026-10-23) that a project the
  agent created with the name of an allowed one ran the binary the allowed
  one had deployed, and read in the code that the deploy did not ask the
  list at all, so a homonym could replace the allowed project's files on the
  target. Now `delphi_build target=Deploy` through a profile asks the same
  `RemoteRunProjects` as `remote-run` (`RUN-007`); `kill` and `output` touch
  only a job this server started for that project and profile (`RUN-021`;
  any id of the right shape was taken); and `exe=` runs only the project
  binary or a file its `.deployproj` lists for that platform (`PAS-063`;
  it was any file of the deploy folder) (`tests/test_remoterun.py`).
- **`RemoteRunProjects` names projects by their path.** A bare name matched
  any project with that name in any folder, so a homonym could deploy over
  the allowed project and run on its target; and the agent's own
  `McpDesktopNode.dproj` passed by the name that grants the desktop node.
  Now an entry is the path of a `.dproj` - its `.dpr`, or no extension, is
  the same project, which the example promised while the path was compared
  exactly - or the wildcard; a bare name authorizes nothing and `RUN-022`
  says which path to write. `McpDesktopNode` keeps its name: it is this
  server's own node, asked by its own question. `settings.example.ini` no
  longer names internal projects (`tests/test_remoterun.py`).
- **`delphi_paserver reseat` no longer invents a platform.** A `.profile`
  that names no platform was seated in the IDE as Linux64, a fact the file
  does not state, while `remove-sdk` already refuses what has no readable
  platform; one without a host was skipped without a word. Both are now left
  unseated and listed in `skipped`, as `reseat-sdk` does. The platform of the
  SDKs this server brings (Linux64) is written once, for its six checks and
  two messages (`tests/test_paserver.py`).
- **`delphi_projects` gives a repository's branch as git does.** It read
  `.git\HEAD` by hand: a branch `fix/x` came out as `x`, and a linked
  worktree - whose `.git` is a file, the kind `delphi_git worktree add`
  makes - had no branch at all. The branch is now git's answer, asked once
  per repository and only when the repository, its git folder and the
  common one can be read. `delphi_git clone` into a worktree is "already a
  repository" (`GIT-032`), as into a folder with a `.git` folder: it only looked
  for the folder. One check of "this folder has its .git" for the three
  places (`tests/test_listas_1150.py`).
- **`delphi_build` names an Android binary as the compiler writes it.** On
  Android the compiler puts `lib` before what the build composes:
  `lib<project>.so`, and with a declared `OutputExt` `lib<project>.<ext>`
  (measured). The server tried `lib` only in front of a `.so`, so a build
  with `OutputExt` succeeded with no `output`, and two places wrote
  `lib<project>.so` by hand. Now one namer gives the file the build leaves
  and another the name the `.apk` loads it by (`lib<project>.so`, as the
  targets say); an iOS build is looked for without extension, as its
  targets compose it (`tests/test_deploy_adb.py`).
- **Rules that lived twice now live once** (`tests/test_bloque3_1230.py`):
  - `delphi_designer get` of a component that is not in the form answers
    `DSGN-078`, with the form's names, as `set`, `delete` and the other
    commands that write; it had its own `DSGN-017`, without them.
  - Every capture is announced by the one deliverer: `screenshot` (only the
    agent's own `out=`) and `screenshotBytes` - `delphi_adb screenshot`
    called its size `size`. And the `path` of `delphi_read` says it reads any
    text file, as it does (it said "the Delphi file").
  - `delphi_create` of a form refuses a form name that is a reserved word:
    `formname=Begin` wrote `Begin: TBegin`, which does not compile
    (`CREATE-026`, the rule of every other new name).
  - A help page id with an empty segment (`system:a//x.htm`) is refused as
    not an id (`DOCS-013`), as the help store already refused it, instead of
    "no such page".
  - The value of an enumeration or a set is judged by one judge, for a type
    of the form tables and for one a user class publishes; the hint for a
    set written without brackets was the value in one and the first member
    in the other.
  - A project property that msbuild reads as a boolean (`UsePackages`,
    `DCC_DebugDCUs`, `VerInfo_IncludeVerInfo`) is true when msbuild says so -
    `yes`, `on`, `!false` - not only when it says `true`: `set-version`
    told a project with `VerInfo_IncludeVerInfo=yes` that it did not carry
    its version.
  - `none`, `default` and `reset` mean "back to the default" in `set-sdk`,
    `set-profile` and `set-output` alike: `set-output output=none` wrote a
    folder called `none`.
- **An anchor line matches by one rule in both edit tools, in blocks and in
  batches.** `delphi_edit` compared a one-line anchor with the end of its line
  exact - `foo := 1;` did not match `  foo := 1;  ` (`EDIT-093` with the
  `EDIT-094` note) - while `delphi_textedit` and every block anchor trimmed
  both ends: the same line matched in a block and not alone, and
  `occurrence` counted it in one tool and not in the other. The blanks at
  either end no longer count anywhere - one-line and block anchors,
  `occurrence` and the preview of `delphi_changeset` - and `EDIT-094` is gone
  with the case it described. An anchor carrying U+FFFD was refused before
  any search, and only by `delphi_edit` (`EDIT-061`, and `EDIT-005` for a
  `fragment`): a line that really holds that character could not be edited,
  and `delphi_textedit` said nothing about a broken read. U+FFFD is now the
  note of an anchor or a fragment that matches nothing, in both tools.
  `delphi_textedit` gave two facts of an anchor codes of its own (`TEXT-009`
  repeated, `TEXT-002` an `atline` that is none of them): both tools say
  `EDIT-077` and `EDIT-062`. And in a batch, an entry with no tie-break whose
  anchor appeared more than once in the file as it was before the batch -
  where `occurrence` counts - was applied wherever it had become unique by
  its turn, answering `APPLIED`: with `x := 1;` on lines 4 and 6, entry 1
  changed line 6 by `occurrence` and entry 2 landed on line 4 (measured on
  2026-10-23). From the second entry on it is refused now, with the lines
  (`EDIT-130`) (`tests/test_ancla_1230.py`).
- **`delphi_config` writes for a platform only when the project has it, and
  a name that is no platform gets one answer.** `add-searchpath`, `set-sdk`,
  `set-profile`, `add-deployfile` and `set-property` wrote groups for a
  platform the project does not declare - an Android64 search path in a
  project that is only Windows - and `set-sdk` answered "The project will
  compile Linux64 with SDK ..." while `delphi_build` refuses that platform
  (`BUILD-046`; measured on 2026-10-23). They now refuse it with the build's
  own text; a platform the project declares and keeps disabled can still be
  configured, as `remove-platform` leaves it, and removing what was written
  is never refused. And "not a valid Delphi platform" came with five codes,
  four in `delphi_config` (`CFG-007`, `CFG-024`, `CFG-078`, `CFG-082`, only
  two of them with the valid names) and one in `delphi_build`: it is
  `BUILD-003` everywhere now, with the valid names
  (`tests/test_plataforma_comando_1230.py`).
- **`delphi_designer layout` knows an FMX data module in a `.dfm`.** A data
  module of an FMX project lives in a `.dfm` whose unit names the FMX class
  group, as the IDE writes it, and the server already took it for FMX
  everywhere but in `layout` and in the outside-the-parent note of `insert`
  and `set`: those asked the extension, so `layout` measured it as a VCL
  window (measured on 2026-10-23). They ask the same judge now, and
  `layout` answers that it does not measure FMX
  (`tests/test_es_vcl_1230.py`).
- **A unit is served by the same project in every tool, however deep it
  lives.** The project of a unit is looked for in the folders above it. The
  language tools climbed eight folders and `delphi_delete`, `delphi_move`
  and the move's search twelve, so a unit ten folders below its `.dproj`
  belonged to it for a delete and to none for `delphi_diagnostics`, which
  answered `LSP-035` (measured on 2026-10-23). The climb itself was written
  by hand in eleven places, each with its own stop at the root, some by a
  rule that climbs from `\\host\share` to `\\host`. Now there is one climb,
  up to twelve folders when nothing else stops it first, and each search
  stops where its own judge says (`tests/test_subida_1230.py`).
- **`delphi_test` says a run was cut by its timeout only when it cut it.**
  When the deadline passed while the output of a test program that had
  already ended on its own was still being read, the answer was
  `result: timeout` with the `exitCode` 0 of a run that had ended well
  (measured on 2026-10-23: 10 of 10 with `timeoutms=1` and a test program
  that takes 54 ms). Every program the server runs is waited for the same
  way, and now a timeout means it was killed: what ended on its own is
  answered as it ended, with all it printed, and a deadline shorter than
  the 50 ms the wait used to sleep is kept (`tests/test_test_timeout_1182.py`,
  whose own cut depended on that race and failed now and then in a full
  run).
- **A path written with forward slashes is judged as the same path.**
  Windows opens `C:/x` as it opens `C:\x`, but a check that reads the text
  does not: a file in the IDE's `__history` or `__recovery` was not taken for
  one of its dead copies when its path came with `/`, and `//host/share` was
  not a network path (measured on 2026-10-23). A complete path an agent
  passes was already given Windows' separator at the server's door; a path
  read from a file, from git or from the IDE was turned by hand in 42
  places, each deciding on its own whether to. Now one function gives a path
  Windows' separators and its inverse gives it `/`, and every place that
  judges, compares or keys a path by its text asks them (`LspUnitTests`,
  `tests/test_paisaje.py`).
- **A missing unit's folder is suggested also when it is called `Backup...`
  or lives under a `Release` folder.** When a build fails with `F2613`,
  `BUILD-042` says where the unit's source is. It skipped every folder whose
  path held `\backup`, a rule of its own that the IDE does not follow (its
  dead copies live in `__history` and `__recovery`) and that also skipped a
  source folder such as `\BackupService\`; and it judged build output by the
  whole path, so a root that hangs from a folder named `Release` gave no
  candidate at all (measured on 2026-10-23). Build output and the IDE's dead
  copies are now judged below each root, as the listings do. The IDE's two
  folder names are written once, and the second check of `delphi_edit` on a
  dead copy asks the write gate's question and answers with its code:
  `EDIT-033` and `EDIT-065` said what `GUARD-005` and `GUARD-004` say, and
  are gone (`tests/test_copias_y_artefactos_1230.py`).
- **A path read from a file is resolved as the program that reads it does.**
  A path written in a `.dproj`, a group, a `.rc` or a form can be half
  rooted: `\x`, the root of the current drive of whoever reads it, or `C:x`,
  the current folder of that drive. The server took both as complete and
  resolved them against its own process - its drive and its folder, which
  nobody named - while msbuild runs in the project's folder and the helper
  that renders a form in the form's. With the server on another drive than
  the projects (as a Windows service it runs in `C:\Windows\system32`), the
  judge that refuses a form value naming a file outside the roots looked for
  it on one drive while the helper resolves it on the other, so a caption
  `\private\x.txt` naming such a file passed; and the finders missed what
  the build reads - the
  `compilesAgainst` of `delphi_projects`, the projects of a group in
  `delphi_config view`, the files of a `.rc` in `delphi_styles lint`; and
  the build gate refused a search path, an output folder, a `{$I}` or an
  `<Import>` that msbuild reads inside the roots (`BUILD-050`, `BUILD-029`,
  `BUILD-028`, `BUILD-017`), judging another file than the one msbuild
  opens (measured on 2026-10-23). One resolver now applies Windows' own
  rule from the folder of whoever reads the path - msbuild and the compiler
  run in the project's folder, and a `{$I}` relative to its source is read
  from the source's - and what it cannot resolve, a drive-relative path on
  another drive, is refused by a judge (`BUILD-051`, and `BUILD-057` for a
  directive) and skipped by a finder. It was written by hand in a dozen
  places (`tests/test_rutas_a_medias_1230.py`).
- **What the second review found (Claude Fable 5.1 through Hermes,
  2026-10-23).** `delphi_test` on a package whose source names `DUnitX.`
  (a package of test helpers) took it for a test, built it and tried to run
  its `.bpl`: a test is a program, and a package now gets `TEST-018` before
  anything is built. With the access table closed, a read-only credential
  that called a tool that does not exist got `READ-002` "writes or acts":
  a name that is no tool is now answered as such. `TEST-001` and `CFG-118`
  said "Win32 and Win64" by hand; they now list what really runs on this
  machine (Win64x too, and WinARM64EC on an ARM). `delphi_config view` of a
  bare `.dpk` with no `.dproj` reads its units, as for a bare `.dpr`,
  instead of reading the `.dpk` as a `.dproj`. The description of
  `delphi_projects` says that a repository rooted above your roots is not
  listed, and the docs list the `include` kind of `delphi_create`
  (`tests/test_delphi_test.py`, `tests/test_http_auth.py`).
- **A connection profile goes on by the name the IDE gives it.**
  `delphi_paserver` and `delphi_desktop` took the profile as typed:
  `Zorin-Desktop` passed (the file system does not mind the case) and went
  on as `Zorin-Desktop` to PAServer, while `delphi_build` deploys with the
  IDE's `zorin-desktop`; and the desktop took a different lock for each
  spelling of the same machine. Every command now picks the profile from the
  IDE's list and goes on with its name; `remove-profile`, `test-connection`
  and `get-sdk` ask that list instead of the disk (`tests/test_remoterun.py`).
- **What the review of these changes found (Claude Fable 5.1 through Hermes,
  2026-10-23).** The access table that decides what a read-only credential
  may call, what the `reader` profile lists and what `tools/list` announces
  took a tool missing from it as one that only reads: a new tool that writes,
  whose author forgot its row, was open to a read-only credential. The table
  now names every tool, what it does not name writes, and
  `tests/test_paisaje.py` asks for a row per registered tool.
  `RemoteRunProjects` compared paths without their extension, so a sibling
  `X.txt` passed as the allowed `X.dproj` (the same binary ran): what it
  authorizes is a project (`CFG-033`). `delphi_projects` no longer names a
  repository whose root lies above the roots. `delphi_config set-active`
  in a `.dproj` that declares no configuration no longer writes the one you
  type (`CFG-145`). `reseat` says why it skips a `.profile` it cannot read,
  the `.sdk` that `get-sdk` writes takes its platform from the same constant
  as the checks that read it, and `settings.example.ini` tells the wildcard
  of the four lists (`tests/test_remoterun.py`,
  `tests/test_contratos_1222.py`, `tests/test_listas_1150.py`).
- **A package is a project for every tool.** What a tool takes as a project
  - its `.dproj`, `.dpr` or `.dpk` - was written by hand in six places, and
  `delphi_test` left the `.dpk` out: it answered `CFG-033` "is not a project
  (.dproj, .dpr or .dpk)", the message that names it valid. It now goes on
  to `TEST-018`, which says a test is a program. The LSP settings of a
  package whose `.dproj` names no main source point at its `.dpk`, not at a
  `.dpr` that is not there. One predicate for "project or its main source"
  and one for "its main source", next to the pair that goes from one to the
  other (`tests/test_delphi_test.py`).
- **The wildcard works in every allowlist of `settings.ini`.** `RemoteHosts`
  took `*` or `0.0.0.0`, `RemoteRunProjects` took `all` or `*`, and
  `GitRemotes` and `AdbAllowedDevices` took none, so `GitRemotes=*` refused
  every host (Claude Fable 5.1 through Hermes, 2026-10-23). Now an entry
  `*`, `all` or `0.0.0.0` means "anything" in all four, and
  `docs/CONFIGURATION.md` says so (`tests/test_contratos_1222.py`).
- **The `reader` profile lists every tool that only reads.** `[Tools]
  Profile=reader` advertised a list of twenty names of its own, written next
  to the access table five days after `delphi_components` existed, and it
  left that tool out: an agent with the profile did not see the tool that
  says what is installed to program with. The profile is now the table's
  read-only tools - what `tools/list` announces as `_meta.access` read-only -
  so the next tool that only reads joins it without another list
  (`tests/test_round20.py`).
- **`delphi_components` with `filter` finds a library that has no package.**
  It searched only the packages registered in the IDE, so a library that is
  just folders of the Library Search Path - units to put in a `uses`,
  nothing in the palette, like `superobject` on the reference machine - got
  `COMP-005` "no registered package contains", and an agent took it for
  missing while a build found it (David, 2026-10-23). The filter now also
  searches the Library Search Path of every platform, and `COMP-012` lists
  the matching folders with the platforms that register each one; `COMP-005`
  is left for what is in neither, and the listing without `filter` says where
  such a library lives. The view of one platform lists its candidate roots
  in a stable order (`tests/test_missing_units.py`).
- **`delete: true` follows one rule in `delphi_edit`, `delphi_textedit` and
  every entry of a batch.** Both descriptions say `delete` takes no `new`, and
  only `delphi_edit` refused it: `delphi_textedit` with `old`, `new` and
  `delete: true` deleted the line and dropped `new`, answering OK; and in a
  batch, an entry whose `old` is a block did not read `delete` at all, so the
  block became `new` (Claude Fable 5.1 through Hermes, 2026-10-23). Now
  `delete` with `new` is `EDIT-057` everywhere and nothing is written, and a
  block with `delete` and no `new` is removed whole. A `delete` with neither
  `old` nor `atline` is `EDIT-056` in both tools (`TEXT-003`, the same fact
  with another code, is gone) (`tests/test_contratos_1222.py`).
- **`delphi_hover` gives a symbol's file as a path the other tools take.**
  The engine's link (`file:///C%3A/.../System.SysUtils.pas#8766`) came out as
  `file:///srvc%3A/...`, which `delphi_read` refused; it is now the path and
  the line (`System.SysUtils.pas:8766 (srvc:\...\System.SysUtils.pas, line
  8766)`). `delphi_definition` puts the column of a routine's body on its name,
  as `declaration` does, instead of the engine's column 0
  (`tests/test_contratos_1222.py`).
- **Several answers now say what really happened.** `delphi_git` on a folder
  with no repository is `GIT-082 NOT_FOUND` (it was a generic `GIT-036
  DENIED`), and its description no longer says that stash never drops (`pop`
  drops the entry once it applies cleanly; git keeps it on a conflict). A
  connection profile that does not exist is `PAS-053 NOT_FOUND`. `delphi_read`
  past the end of a file is `READ-010` and names `fromline` (it was `EDIT-100`
  and `from`). `delphi_create` of a form, frame or data module without
  `project` says so (`CREATE-036`; it was the generic `GUARD-018`), and
  `CREATE-011` names `include` and says that a unit or an include can be
  created on its own. `BUILD-050` quotes a path also as it is written in the
  project when the build reads it otherwise (an escaped `%2E%2E`), which is
  the entry `remove-searchpath` takes. A build answers with its `durationMs`,
  as `delphi_test` and `remote-run` do. A `delphi_docs` search whose results
  all fit gives them as its `total` (it counted the candidates: total 5 with
  4 results and nothing more to see). `delphi_list` with its root inside a
  trash folder counts every entry as a trash copy (`LIST-008` called the day
  copies live files). `delphi_config remove-unit` reads a relative path as
  the project lists it, from its `.dpr`: it was judged from the server's own
  folder, and `CFG-125` said that a unit inside the project lay outside what
  the session can read. `CREATE-035` names the kinds a parameter goes with
  (`form-vcl`, ... `datamodule`), not `form`, which is no kind (Claude Opus
  5.5 through Hermes, 2026-10-23) (`tests/test_contratos_1222.py`).
- **The folder summary of `delphi_symbols` lists a unit's constants and
  variables.** The summary of each unit's interface left out a constant
  written on the line of `const` itself (`const X = 1;`), typed constants
  (`B: Integer = 2;`) and variables (Claude Opus 5.5 through Hermes,
  2026-10-22) (`tests/test_contratos_1222.py`).
- **`GUARD-002` names the places you can work in, the read-only ones
  included.** A path outside the roots was refused with a list of the roots
  that named one the server could not reach and left out the read-only roots,
  which can be read (Hermes, 2026-10-22: three refusals before finding the
  root to read). It now lists the roots and read-only roots the server
  reaches, these marked `(read-only)` - the same list as `WS-022`, and now
  also that of a relative path (`GUARD-021`) and of a `<server>` name
  (`GUARD-039`), which listed every root as written (Claude Fable 5.1 through
  Hermes, 2026-10-23) (`tests/test_contratos_1222.py`).
- **A parameter that does not go with the call is refused, not ignored.**
  `delphi_search` with ONE file as root and a `pattern` that does not pick it
  searched the file anyway (`SEARCH-009`); `delphi_adb` took `device` with
  `devices`, `discover`, `connect` and `disconnect`, which talk to no single
  device (`ADB-028`); and `delphi_components` with `platform` and `filter`
  answered with a note that it ignored the filter, where its siblings refuse
  (`COMP-011`) (`tests/test_contratos_1222.py`).

## [1.22.1] - 2026-10-23

What an agent reads, points at and writes is what the IDE and the compiler
see, accents included. The position tools point at the right symbol on a
line with accents - the engine counts a column in UTF-8 bytes and the agent
in UTF-16, and every column is now converted both ways -, `delphi_test` and
`delphi_git diff`/`show` return a source's accents as the file has them, and
`delphi_designer insert`/`set` write a component's properties as the IDE's
own writer stores them, saying when it stores another value, none at all, or
keeps it in other properties. The build read gate judges a search path the
way msbuild and `dcc` resolve it - the `=` and `:` shortcuts, `%XX` escapes,
`$(ProjectDir)` and the `\??\` prefix let a unit from outside the roots be
read (measured, now closed) -, a new project property lands where the IDE
writes it, every project file the server writes goes through the IDE's XML
parser, and several answers now say what the tool did. Validated before the
release by Claude Opus 5.5 and Qwen3.8 Flash Next through Hermes on a second
machine: a directed test of what is new, a full test of every tool, a free
exploration of the whole server, and three rounds over what they found and
was fixed.

### Fixed

- **The build read gate judges a search path the way the compiler resolves it,
  not by its text.** A path the build reads that looked like a key=value pair
  (an `=` before the first slash, `a=b\..\..\outside`) or a URL (a `:` with
  slashes after it, `s\a:b\..\..\outside`, or the NT device form `\??\C:\outside`)
  was skipped unjudged and `dcc` read a unit from outside the roots (measured on
  2026-10-22: each compiled). The `=` and `:` shortcuts now apply only to the
  properties the build reads as key=value, not paths (`VerInfo_Keys`,
  `DCC_UnitAlias`); every other value is resolved - `GetFullPath` collapses `..`
  exactly as Win32 and `dcc` do - and judged, and the `\??\` device prefix is
  stripped like `\\?\` (`tests/test_puerta_1221.py`).
- **The build read gate unescapes `%XX` before it judges a path, as msbuild
  does.** `%2E%2E\%2E%2E\outside` (escaped dots) and `inside%3B..\..\outside`
  (an escaped `;` that msbuild turns into a list separator) reached `dcc` as
  `..\..\outside` while the gate judged the literal, inside-looking text
  (measured on 2026-10-22: both compiled reading a unit from outside). The
  expanded value is now unescaped before it is split and judged
  (`tests/test_puerta_1221.py`).
- **`$(ProjectDir)` in a path the build reads is no longer expanded with the
  project folder.** It is not an msbuild reserved property, and msbuild reads it
  empty in the body of a `.dproj` (measured on 2026-10-22: `$(ProjectDir)\outside`
  compiled reading outside the roots while the gate judged a folder inside). The
  gate now leaves it empty, as msbuild does; `MSBuildProjectDirectory` (reserved)
  and `SanitizedProjectName` (which msbuild does set, measured) stay
  (`tests/test_puerta_1221.py`).
- **A `$(...)` whose property name has a dash is no longer refused.**
  `set-property` accepts creating `My-Path`, but the build gate denied any value
  that then said `$(My-Path)` with `BUILD-051`, because its name grammar did not
  allow `-` while msbuild does (measured on 2026-10-22: `$(My-Path)` expands).
  The gate's grammar now accepts `-` too (`tests/test_puerta_1221.py`).
- **A `$( Name )` with spaces is judged as msbuild reads it.** msbuild does not
  trim the name, so `$( A )` is the (undefined, empty) property " A ", not `A`;
  the gate trimmed it and expanded with `A`'s value (measured on 2026-10-22:
  `$( A )` let through a path msbuild read differently). The gate no longer trims
  the name, so a `$(...)` that is not a plain property name is refused as
  non-verifiable, `BUILD-051` (`tests/test_puerta_1221.py`).
- **The position tools point at the right symbol on a line with accents.**
  DelphiLSP counts a column in UTF-8 bytes of the line, both ways - measured
  with the engine alone: an `ñ` is one more, a `€` two, an emoji two more
  than UTF-16, in hover, definition, document symbols and diagnostics, with
  the unit opened or read from disk, ANSI or UTF-8, and it declares no
  `positionEncoding` whatever the client offers - while the agent,
  `delphi_read` and `delphi_search` count UTF-16. With an accent earlier on
  the line, definition, hover and signature asked about the symbol next to
  it, references confirmed nothing and rename refused, and a
  diagnostic's range came back shifted. The engine's client now converts
  every column it sends and every one it receives with the line the engine
  holds (`LspTests.Encodings`, `tests/test_columna_acentos_1221.py`).
- **`delphi_git diff` and `show` give a source in the machine's ANSI code page
  with its accents.** git writes its own text in UTF-8 and the lines of a
  file as they are, and the server read whatever was not UTF-8 in the
  console's code page: `año` came back as `a±o` (1252 read as 850), and in a
  diff with a UTF-8 source and an ANSI one, both. Each line is now read as
  UTF-8 when it is, else in the machine's ANSI code page, the one `dcc` and
  the IDE read a source without a BOM in (`tests/test_git_acentos_1193.py`).
- **`delphi_test` returns a failure message with its accents.** A Delphi
  test runner writes to a pipe in the machine's ANSI code page (its RTL uses
  the console's only for a console), and the server read it in the OEM one:
  `í ñ € Ç` came back as `Ý ± Ç Ã` (`tests/test_delphi_test.py`).
- **Every project file the server writes is now really judged by the IDE's
  XML parser.** 1.22.0 promised it, but the check lived in the editors of
  the `.dproj`, and five writers saved without it: `add-project` /
  `remove-project` of a `.groupproj`, a move that re-points a `.dproj` or a
  `.groupproj`, the `.dproj` of `delphi_create` and a `create` in a
  changeset. It now lives in the one writer underneath, by the kind of file
  (`.dproj`, `.groupproj`, `.deployproj`), and a changeset's preview says it
  too (`CFG-142`; `tests/test_xml_ide_1221.py`).
- **`delphi_designer insert` and `set` write a component's properties as the
  IDE's writer stores them.** The server asks that writer - the form loaded
  as the designer loads it and written back - and takes its lines for the
  component: an inserted VCL control carries the size its constructor gives
  (the IDE stores `Width` and `Height`, and `layout` read them as missing),
  a property set lands where the IDE writes it instead of at the top of the
  block, `Size.Width` in FMX comes with the `Size.Height` and
  `Size.PlatformDefault = False` the IDE adds, `Font.Style` with the other
  `Font.*` and `ParentFont = False`, and a value the class already gives is
  not written (`notStored`, `DSGN-165`). What the agent sets is read after the
  rest of the component, as the IDE sets it on the loaded one, so it is the
  value that stays; and a property its class declares `stored False` - `Width`
  and `Height` in FMX, which the IDE keeps in `Size` - is answered with what
  the IDE writes for it (`storedIn`, `DSGN-167`), not as a value the class
  already gives. A value the component turns into
  another when it loads is written as the IDE stores it, and the answer says
  so (`storedAs`, `DSGN-166`): a `Left` that an `Align` places, the time of a
  date picker's `Date`, the name of an alpha color given as `xAARRGGBB` - the
  answer said the value given while the IDE would save another. What its
  loader read and could not apply - an event's method (it runs no code), a
  reference to a component of another module - and what its reader skipped
  stay, in their place in the writer's order. When it cannot be asked - an
  inherited component or one of an inline frame, a class it did not load, an
  ancestor it did not read - the lines stay as composed and `ideNote` says
  why (`DSGN-164`; `tests/test_designer_ide_1221.py`).
- `adduses` followed by `removeuses` gives back the same bytes in a compact
  unit too (the section keyword with code right below it): the new clause
  takes the spacing the keyword already had, before and after it, instead of
  a blank line of its own (`tests/test_delphi_patch.py`).
- `delphi_definition kind=declaration` on the header of a routine's body
  returns its declaration - in the interface or in its class - and no longer
  the body (`tests/test_definition_implementation_120.py`).
- `delphi_desktop status` against a target whose PAServer does not answer
  says `reachable: false` with the reason, as `delphi_paserver
  test-connection` does, instead of refusing with `RUN-010`
  (`tests/test_remoterun.py`).
- `delphi_paserver platforms`: `buildsLocally` is true for a platform with
  its SDK pulled - it builds here, as `delphi_build` says - not only for the
  Windows ones (`tests/test_v012.py`).
- `remove-searchpath` names the other group that holds a folder only when
  the folder is an entry there, and names only the groups that hold it: `lib`
  matched `lib2` as text, and the hint listed every group with a search path,
  the one just said not to have it included (`CFG-022`;
  `tests/test_config_property_1220.py`, `tests/test_contratos_1221.py`).
- `delphi_list dirs=true` with a `pattern`, and `delphi_symbols` of a folder
  with `mode` or `filter`, say the parameter does not go with what was asked
  (`LIST-015`, `LSP-050`) instead of ignoring it, and `LIST-015` names the
  mode it does go with as it is asked for (`dirs=false`)
  (`tests/test_contratos_1221.py`).
- `delphi_config set-property`, `add-searchpath` and `set-output` write a new
  property where the IDE does: at the END of its group, in the order the
  properties are created (measured in the IDE's Project Options on a new
  project); a property that is already there changes in place. They put it at
  the top of the group, and set-property moved an existing one there too: since
  msbuild reads a group in document order, `DCC_UnitSearchPath=$(MyPath);...`
  set after `MyPath` landed above it and saw it empty (F2613)
  (`tests/test_orden_propiedad_1221.py`).
- `delphi_upload` says what its `sha256` is: the file as it stands at the
  end of that call - every byte from offset 0 through that chunk, the whole
  file on the last one - which is what the server always checked. The
  parameter said only "on the LAST chunk, the whole file", and an agent sent
  the whole file's sum on the first of several chunks and a chunk's own sum
  on a later one; `UPLOAD-015` and `UPLOAD-011` now say which sum goes where
  (`chunkSha256` for a chunk's own bytes). `UPLOAD-009` and `UPLOAD-015` say
  which sum the call's bytes give and which one was sent (they said "received"
  and "expected", read the other way round), `UPLOAD-011` and `UPLOAD-012` no
  longer say the file differs from the source - the sum sent may be the wrong
  one - and say so when it is the sum of that chunk alone; and once
  `UPLOAD-011` has set the file aside, the answer's `size` and `nextOffset`
  are 0, as its "resend from offset=0" says, not the size assembled
  (`tests/test_contratos_1221.py`).
- The global properties of a build are one list: the outputs the build
  supplies were copied by hand next to the fixed ones, and `test_paisaje`
  now also sees a property passed as `/p:%s`.

## [1.22.0] - 2026-10-22

A project of the IDE builds through the server the way the IDE builds it,
and its options are managed in one place. The build gate judges only what
the requested platform and configuration read, evaluating the groups of the
`.dproj` the way msbuild does, and judges a macro that expands to a list
piece by piece: a real FMX project with an Android keystore outside the
roots and the IDE's usual package list now builds for Windows and Linux
(measured on two machines). `delphi_config` gains `set-property`,
`remove-property` and `get-property` - one property of the `.dproj` by
name, in the group of the build you name, written where the IDE writes it,
the way to re-point or drop that keystore. Underneath, one reader and one
writer of a project property in `Lsp.Dproj`, the reader judging a build with
the gate's own evaluator, and the leftovers of the reviewers of the change
closed, two of them holes: a search path written with Windows'
extended-path prefix was not judged, and five ways the evaluator of the
group conditions diverged from msbuild, each one a group the gate would not
judge, and a macro inside a path the build reads that was expanded with a
value the compiler would not read. And every project file the server writes
is loaded by the IDE's own XML parser before it is saved.

### Added

- **`delphi_config set-property`, `remove-property` and `get-property`: one
  property of the `.dproj` by name, in the group of the build `platform=` and
  `config=` name.** An agent whose project kept its Android keystore outside
  its roots (`PF_KeyStoreDebug`, in the `'$(Cfg_1_Android64)'!=''` group the
  IDE writes) had no tool to drop or re-point it: the two text editors refuse
  a `.dproj` on purpose and no command wrote in the group of a configuration
  (measured on 2026-10-21). `set-property name=PF_KeyStoreDebug value=<path>
  platform=Android64 config=Debug` writes it where the IDE would - the group
  of that pair, created with its definer in the IDE's own order when the
  project lacks it -, `remove-property` takes it out with its line, and
  `get-property` answers the value that build reads (the default build
  without `platform=` / `config=`) and every group that sets it. The name
  only chooses: the structure of the `.dproj` (`Config`, `Platform`, `Base`,
  `Cfg_N` and their flags, `ProjectGuid`, `ProjectVersion`, `MainSource`, and
  the properties the IDE's own imports resolve their files through - `BDS`,
  `APPDATA`..., the list `BUILD-019` refuses a build for) is refused with
  `CFG-132`, a build event or a free compiler option - text this
  server never passes to a program - with `CFG-133`; the value is not judged
  when written but when that build reads it, like any value of the `.dproj`
  (`BUILD-050`). `get-property` is a read, allowed in read-only mode.
  (`tests/test_config_property_1220.py`, with msbuild as the judge of where
  the property landed; `LspTests.Dproj`.)
- **Every project file the server writes is loaded by the IDE's own XML
  parser before it is saved.** The editors of the `.dproj`, the `.deployproj`
  and the `.groupproj` compose their text in place with the server's scanner;
  the result now goes through MSXML 6 - the parser the IDE loads a project
  with - and a text it would not load is not written (`CFG-142`, naming the
  line and the reason; the file stays as it was). A second barrier behind the
  scanner, in the one saver every writer of a project file calls.
  (`LspTests.Dproj`.)

### Changed

- **One writer of a project property, in `Lsp.Dproj`.** `set-sdk`,
  `set-profile`, `add-searchpath` and `remove-searchpath` each chose the
  `PropertyGroup` of a platform their own way (a private writer for the first
  two, the group by its condition for the other two, and a creator of the
  platform's groups that raised), and none could write in the group of a
  configuration. They now go through `GrupoDelBuild` / `AseguraGrupoDelBuild`
  / `PonPropiedadDelBuild`, the writing twin of `EffectiveProperty`: the group
  of a build - base, platform, configuration or the pair -, created with its
  definer where the IDE puts it (measured on a `.dproj` the IDE wrote) when
  the project lacks it. A configuration without the definer group the IDE
  writes is refused (`CFG-104`, now naming the build) instead of getting a
  group msbuild would never read; `CFG-088`, `CFG-091` and `CFG-093` are
  gone with the code that answered them. `test_paisaje` watches that no unit
  outside `Lsp.Dproj` chooses or creates a build's group by hand.
- **The reader of a project property judges "this build" like the gate.**
  `EffectiveProperty` - output folders, SDK and profile, packages, the
  engine's settings, `get-property`, and the expansion of `$(X)` inside a
  value the gate judges - chose the groups by the name of the configuration
  key, the first form of the gate; it now uses the gate's own evaluator
  (`VeredictosDeElementos`: one judge of "this group applies to this build",
  for reading and for judging), so a flag planted in an unconditioned group,
  a child configuration or a renamed key read what msbuild reads. For
  reading, only what is certainly applied counts: a condition the evaluator
  cannot decide is not taken as declared (the gate judges it instead), as
  before. (`LspTests.Dproj`, with a check that five reads of a 100 KB
  `.dproj` stay under half a second.)
- **Two `PropertyGroup`s with the same `Condition`, and the order of the
  configuration keys.** msbuild applies every group whose condition holds and
  the last definition wins; the writer of a property took the first group
  with that condition and a reader could read the other. Both take the last
  group now, `set-property` removes the copies the earlier groups held of
  the property (an element with a `Condition` of its own stays, and when the
  build named by `platform=` and `config=` reads a different value than the
  one just written, the answer says so), and the keys of the configurations
  are read in the order of their definer groups, as the IDE writes them, not
  in the order of `BuildConfiguration` (Release, Base, Debug in 230 of the
  296 sample projects of the IDE), so a new group lands after its siblings.
  (`LspTests.Dproj`.)
- **A property name msbuild rejects is refused, and so is a key it rejects.**
  `set-property` accepted a name with a `.` (MSB5016 in msbuild, measured)
  and a name msbuild reserves (`MSBuildProjectName`, MSB4004); `CFG-131` and
  `CFG-132` refuse them now, by the one grammar of a tag name that also
  judges the key of a configuration before a group is named after it
  (`CFG-141`).
- **The build gate judges what the requested build reads, not every property
  group of the `.dproj`.** A keystore that only an Android64 Debug build reads
  (`PF_KeyStoreDebug`, in the `'$(Cfg_1_Android64)'!=''` group the IDE
  writes) refused a Linux64 or Win64 build with `BUILD-050`, while the IDE
  built them because it never reads that value (measured on 2026-10-21 on a
  real FMX project; an agent reported it the same day). Now the conditions
  of the groups, and of an element with a `Condition`, are evaluated the way
  msbuild evaluates them: in document order, over what the earlier groups
  left set, with `$(Config)` and `$(Platform)` as requested
  (`Lsp.Dproj.EvaluaCondicion`, one declared grammar of the forms the IDE
  writes; a condition it does not understand is judged, a flag set by
  something it does not understand makes whatever compares it judged too,
  and a name msbuild takes from outside the project - the environment,
  `rsvars.bat`, the IDE's table - is never assumed empty).
  A first form of this change decided by the name of the configuration key
  and would have skipped a group msbuild reads: a flag planted in an
  unconditioned group, a child configuration that inherits Debug, or a key
  renamed in `BuildConfiguration` (found by the reviewers of the change,
  measured red). (`tests/test_build_grupos_1215.py`, 16 checks, 5 red
  against 1.21.4; `LspTests.Dproj`.)
- **A macro that expands to a list is judged piece by piece.** The IDE closes
  the package list of every project with `$(DCC_UsePackage)`; the build gate
  expanded it to the whole list and judged that as one relative path, so any
  project with more than about twenty-five runtime packages was refused with
  `BUILD-050` naming `$(DCC_UsePackage)` (measured on 2026-10-21: 217
  characters passed, 313 did not, 1,599 without the macro passed). What a
  macro expands to is now split by `;` like the written value, and each piece
  judged on its own. The same mistake hid a hole: a search path that expanded
  to a list of folders with drive letters (`$(Path)`) looked like a text with
  a `:` and slashes after it, which the gate takes for a URL, and was not
  judged at all; now every folder of the list is judged and the ones outside
  are refused. (`tests/test_build_lista_macro_1215.py`, 10 checks, 4 red
  against 1.21.4.)
- **`delphi_config view section=searchpaths` lists the groups of a
  configuration too** (`Debug`, `Win64 Debug`), where `set-property` can now
  write a search path; it listed the base group and the platforms only.
- **One writer of a deployment `ItemGroup` and of a `DCCReference`.** Five
  places composed the `<ItemGroup Condition=...>` of a `.deployproj` by hand
  (the Android manifest, the one of the other platforms, the empty group and
  the new group of a completed manifest, `add-deployfile`) and `delphi_create`
  composed the `<DCCReference>` of a unit twice beside the writer of
  `add-unit`; `XmlGrupoDeDespliegue` (`Lsp.Dproj`) and `DccRefXml`
  (`Lsp.ProjectUnits`) are the houses now, watched by `test_paisaje`.

### Fixed

- **A search path written with Windows' extended-path prefix (`\\?\C:\...`)
  was not judged by the build gate.** The gate took "a `:` with slashes after
  it" for a URL and skipped the piece, while dcc opens such a folder: a unit
  that only existed outside the roots compiled through it (a reviewer's note,
  measured on 2026-10-21, red against 1.21.4). The prefix is now removed
  before judging, by the house that already read it (`Lsp.Rutas`), and the
  path goes through the gate like any other; a prefixed path inside the roots
  still compiles. (`tests/test_build_prefijo_1220.py`.)
- **The evaluator of the group conditions diverged from msbuild in five
  ways, each one a group the build gate would not judge.** A reviewer
  measured them against the IDE's msbuild on 2026-10-21: a `PropertyGroup`
  inside `ProjectExtensions` or inside a `Target` set a flag for the
  evaluator while msbuild ignores it there; a value was expanded late, with
  the properties it names as they stood at the comparison, while msbuild
  fixes it when defined; a global property the build passes on its line
  (`/p:Profile`, `/p:PlatformSDK`, the emptied build events...) was read from
  the document, while the global wins even when the document defines it
  later; a property set by a file the project imports was taken as empty;
  and `'1.0'=='1'`, `'yes'=='true'` or `'%31'=='1'` were false, while msbuild
  compares numbers and booleans before text and unescapes `%XX`. In each
  case the gate took the group for another build's and did not judge its
  values, so a search path to a folder outside the roots in such a group
  compiled a unit from there. The evaluator now does what was measured; the
  globals the build passes are one declared list that `test_paisaje` keeps
  in step with the msbuild line; a name another file of the project's chain
  defines is never assumed empty; and a reader of one build reads the groups
  of the root only. A `PropertyGroup` with a namespace prefix was suspected
  too: msbuild refuses it (MSB4097), nothing to close.
  (`tests/test_build_evaluador_1220.py`, 8 checks, 5 red against the
  previous build; `LspTests.Dproj`.)
- **A macro inside a path the build reads could point one way for the gate
  and another for the compiler.** The gate expanded `$(Name)` with the last
  value the project gives that property, while msbuild fixes a property's
  value where it is defined: with `<A>..</A>`, a search path
  `$(A)\..\outside` and then `<A>x</A>`, the gate judged a folder inside the
  roots and dcc read one outside, and a unit that only existed there
  compiled (measured on 2026-10-22, in 1.21.4 too). Three more shapes of the
  same cause were measured the same day: a property defined once under a
  `Condition` the gate cannot evaluate (an `Exists()`) expanded to nothing
  while msbuild applied it; a name of the IDE's table (`LANGDIR`) redefined
  by the project expanded to the table's value while msbuild took the
  project's; a macro used before its only definition expanded to that value
  while msbuild read it empty. The gate now expands every value the build
  reads with the same walk that evaluates the group conditions as msbuild
  does: a property has the value it was last given before that point in a
  group this build reads (empty until then, the project's over the
  environment's), an item's `Include` the final one, and what the document
  does not know (the IDE's and msbuild's own properties, an environment
  variable, a name nothing defines) is expanded by the gate's table
  afterwards. What the gate cannot know is refused with `BUILD-056`, naming
  the macro: a property set under a `Condition` it cannot evaluate, or a
  property the build passes on its own command line. And a `$(...)` in a value
  the build reads is approved only when what is inside is a simple property
  name (letters, digits and `_`): anything else - a property function, an
  item, a name with a dot or a dash - makes the whole value non-verifiable and
  is refused with `BUILD-051` before expanding, whether or not the path
  exists. Measured over 3,651 projects (the IDE's samples, this machine's
  roots and a NAS): none uses a macro the gate now refuses, none is refused
  that built before, and a property defined once per configuration is no
  longer refused. (`tests/test_build_macros_1220.py`, 15 checks, 5 red
  against 1.21.4, three of which compiled with a unit from outside the roots;
  `LspTests.Dproj`.)
- **The engine's search path and the IDE's Library path split the list before
  expanding macros.** A macro that expands to a list (`$(Path)`, an
  environment variable holding two folders) stayed one piece with a `;`
  inside - a folder that does not exist - so the LSP engine did not see the
  folders it named. Both now expand first and then split, with the build
  gate's own splitter. (`LspTests.Motor`: a macro of the IDE's table that
  expands to two folders gives two entries; it gave one that did not exist.
  The engine's settings expand the IDE's macro table only, not the process
  environment, so the case is measured at the unit level.)
- **The deployment manifest took the output folder of any platform.** The
  `ProjectOutput` entry of a generated or completed `.deployproj` read
  `DCC_ExeOutput` by merging every group of the `.dproj`, so a project with a
  folder of its own for another platform could ship from the wrong one; it
  now reads the value of that platform and configuration and expands its
  macros with the one expander of output folders. The old merger is gone.
- **Two refusals did not say how to go on** (an independent agent, three
  directed runs before this release). `remove-searchpath` answered `CFG-022`
  "not in the search path" for a folder that a configuration's group holds
  (as `set-property` with `config=` writes it): it now says which group has
  it and that `remove-property` with that `platform=` and `config=` takes it
  out. And `BUILD-055` (a `.dproj` cut short) told the agent to restore the
  copy in `__delphi-patch` without saying how: it now names the way -
  `delphi_delete` the broken file, then `delphi_move` the copy the upload
  named in `backup` to its name - which leaves the file byte for byte and
  builds. (`tests/test_config_property_1220.py`,
  `tests/test_build_dproj_truncado_1214.py`: one check each, red against the
  previous build.)
- **An upload whose final `sha256` did not match left the name empty.** With
  the whole file in one call (`offset=0` and its `sha256`), the server wrote
  it, moved the previous version to the trash and then set the upload aside,
  so the file that was there was no longer under its name (an independent
  agent's full review before this release). That call is now checked before
  anything is written: a mismatch is `UPLOAD-015` and the file stays as it
  was. After several chunks the check can only come at the end: `UPLOAD-011`
  now says that the first chunk kept a copy of the previous version and that
  `delphi_move` of that copy puts it back. (`tests/test_upload_corrupt_1192.py`,
  two checks red against the previous build; the batteries that measure the
  quarantine reach it in two chunks, the only way it happens now.)

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
- [1.21](docs/changelog/1.21.md)
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
