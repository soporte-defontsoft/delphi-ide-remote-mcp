# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

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
  `Cfg_N` and their flags, `ProjectGuid`, `ProjectVersion`, `MainSource`) is
  refused with `CFG-132`, a build event or a free compiler option - text this
  server never passes to a program - with `CFG-133`; the value is not judged
  when written but when that build reads it, like any value of the `.dproj`
  (`BUILD-050`). `get-property` is a read, allowed in read-only mode.
  (`tests/test_config_property_1220.py`, with msbuild as the judge of where
  the property landed; `LspTests.Dproj`.)

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
