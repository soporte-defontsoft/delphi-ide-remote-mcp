# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

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
  one - and say so when it is the sum of that chunk alone
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
