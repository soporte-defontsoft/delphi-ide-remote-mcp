# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- **What an answer quotes from the disk comes back as the disk has it, also
  inside a JSON answer.** The outbound filter leaves the citations a call
  composed (`N|text`, `Lsp.Mascara.CitaDeLinea`) untouched and masks the rest,
  but it recognised them line by line, and a JSON answer is one line: every
  citation inside one was masked, and a `<letter>:` in it became `srv0:`. The
  echo of `delphi_designer` insert, set and delete lied about what it had just
  written - `Caption = 'Contrase'#241'a:'` came back as
  `'Contrase'#241'srv0:'` in `block`, `value` and `previous`, with the form
  right on disk - and so did the line a `delphi_changeset` preview quotes when
  a `delete-line` names a line that is not the one in `old`. The filter now
  walks a JSON answer string by string, with the walker `EnmascaraJsonSalvo`
  already used; the values `delphi_designer` takes from the form (`value`,
  `previous`, `storedAs`, `storedIn`) are marked as content where they are
  composed (`ContenidoTalCual`, beside `CitaDeLinea`); and the changeset's
  quoted line is a citation on its own line (`line N is not the expected one;
  it is:` followed by `N|text`) instead of a quote written by hand. The
  commit and the preview of a `delete-line` now ask one rule
  (`DeleteLineDenegado`) instead of two copies of it.

## [1.23.0] - 2026-10-26

A cleanup release: one rule where there were several, and the holes they
hid. Files move, copy and delete as an operator does - only what is named,
never overwriting, merging into a folder that exists, with a wildcard in the
name (`Form1.*` takes a unit and its form) - and the answer names what
crosses the border instead of rewriting projects behind the agent's back; the
unit rename is retired. The jail compares paths the way the filesystem does:
a comparison that folded with the user's language let a sibling of a root,
named with another case of the same letter, be read and written. That hole,
and four more measured in the published 1.22.1 - a unit read from outside
through the main source's `in`, a connection profile and a move's note that
told whether something outside the roots existed, and a `.deployproj` deploy
command reaching the build - are closed. The server's house deletes a folder a
test left locked, the build's import scan reads where msbuild reads, a copy
takes a project and a whole repository, and many answers now say what really
happened. Validated before the release through Hermes on a second machine by
Claude Opus 5.5 (a full test of every tool) and Qwen3.8 Flash Next (a directed
test of what is new).

### Changed

- **A UNC or device/NT path is recognized through its one judge.** Whether a
  path is a UNC share or a device / NT extended-length prefix (`\\?\`, `\\.\`,
  `\??\`) is now decided by `EsUnc` / `EsPrefijoDeDispositivo` (`Lsp.Rutas`), not
  by a hand-written "starts with two backslashes" that a device prefix fools (it
  starts that way yet is not a UNC). Routed the stragglers through the judges:
  the persistent network resource read from the registry (`Lsp.NetDrives`), the
  whole-unit/resource check that forbids deleting a drive or share root
  (`BorradoDenegado`), a network-letter site (`EsSitioDeLetraDeRed`,
  `Lsp.Lugares`) and the build's refusal of an `<Import>` from a UNC path
  (`Lsp.Dproj`), which stays broad - a UNC and a device/NT-prefix import are
  refused alike, now via both judges. And the format now has its one composer:
  `ConPrefijoDeDispositivo` writes the `\\?\` extended-length prefix (its reader
  is `SinPrefijoDeDispositivo`), replacing three hand-built copies in `Lsp.Rutas`
  (`tests/test_build_imports.py`).
- **`delphi_move copy=true` copies a project, and a whole repository, like
  any folder.** A copy of a folder holding a project, or of a loose `.dproj`,
  was refused (`MOVE-004`, "a project never lives in two places"), a rule of
  how this repository is worked, not of the product; and a folder with a
  `.git` inside was refused whole. Now a project copies like any folder, and
  a repository is copied with its git when its git stays inside what is
  copied: git itself says where each repository inside keeps its metadata, its
  common directory and its working tree. A linked worktree or a submodule (its
  `.git` is a file pointing at another repository's metadata), a
  `core.worktree` outside, or a repository reached through a link the copy
  follows is refused with `MOVE-022`, saying where that git lives
  (`tests/test_ficheros_operador_1230.py`, G1-G7).
- **`delphi_move` and `delphi_delete` do what an operator does, and say what
  they saw.** Moving, renaming or deleting a unit re-pointed every project that
  listed it (`.dpr`, `.dproj`, groups, `{$I}`/`{$R}`/`{$L}`), rewrote its
  `unit X;` header and the uses of the other units, took its `.dfm`/`.fmx`
  along, and refused the whole operation when a project could not be
  rewritten (`MOVE-019`, `FILE-039`): surgery on files the agent did not name.
  Now they touch only what is named, as the system's own move, copy and delete
  do, and the answer carries a note: the files whose paths cross the border of
  what moved and now lead elsewhere, each by its full path with what it counts
  (`MOVE-023`; `FILE-046` for what still points at something deleted), what
  the build reads through a property or an absolute path that no longer leads
  where it did (`MOVE-021`, with the property to change), and the files it
  could not read to look (`MOVE-024`). Fixing is the agent's:
  `delphi_config fix-references`, `remove-unit` / `add-unit`, `delphi_edit`
  for a header. The commit of `delphi_changeset` gives the same note for what
  it moved and deleted, and its `CHSET-033` refusal is gone
  (`tests/test_mudanza.py`, `test_round50.py`, `test_contratos_1222.py`,
  `test_resultados.py`, `test_changeset_unidad_1192.py`).
- **A wildcard in the name: `UFicha.*`, `*.pas`.** `delphi_move` (moving and
  copying) and `delphi_delete` take a wildcard in the last part of `path`,
  matched in that folder as Windows matches it (`*.pas` does not match
  `b.pas2`); with a wildcard, `dest` is the folder the matches go into. All or
  nothing: one file another process holds stops the whole operation, and its
  `SYS-027` names it. A unit and its form travel by their own names -
  `form.*` takes both - and a unit that goes without its form, or the
  reverse, gets a note (`FILE-051`). The jail judges the wildcard's folder at
  the entry and every match by its own gate; a wildcard in a folder is still
  `GUARD-024`, and the new refusals say what is wrong: nothing matches
  (`FILE-047`), `dest` is a file (`FILE-048`), a wildcard in the trash or with
  `purge` (`FILE-050`) (`tests/test_ficheros_operador_1230.py`, W1-W7;
  `test_round37.py`; `test_resultados.py`, E123-E151).
- **A move into a folder that exists merges into it, and nothing is ever
  overwritten.** Before the first byte, `delphi_move` looks at everything it
  would write: a file that already exists is refused with the list of every
  clash and nothing written (`FILE-025`), the longest path it would write has
  to fit (`GUARD-028`, naming it; it failed halfway with `MOVE-012`), and the
  drive has to keep a margin free (`GUARD-044`). A folder whose destination
  exists merges into it and is undone whole if an entry fails; renaming a file
  or a folder to change only its case works (it was refused as already there)
  (`tests/test_ficheros_operador_1230.py`, C1-C5; DUnitX
  `TMudanzaDeOperadorTests`).
- **A move is a rename on its own drive, a file too.** A file moved to another
  drive was copied and deleted by the RTL, following a symlink; now it is
  refused like a folder with `MOVE-002`, which says the way: `copy=true`, then
  `delphi_delete` (`tests/test_readonly_roots.py`).
- **The task map of `delphi_help` says how to rename a file**: "delete / move
  (rename) a file", next to "rename a symbol".
- **`delphi_docs read` pages a long page like every list.** A chunk of a
  page came with `length`, `offset` and `nextOffset`, written by hand and
  without `hasMore`, so a client that walks "until `hasMore` is false", as
  `delphi_list`, `delphi_search` and `delphi_projects` say, could not walk
  it. It now answers with the page of the lists: `total` (the characters of
  the page; it was `length`), `shown` (those of this chunk), `offset`,
  `hasMore` and `nextOffset`. The note that says a list was cut is
  composed in one place for `delphi_list` (files and folders),
  `delphi_projects` and `delphi_docs` (`Lsp.Listas`, `TPagina`); the one of
  `delphi_docs` now says how many characters came, of how many
  (`tests/test_delphi_docs.py`).
- **`delphi_components` refuses an unknown platform like every other tool.**
  A name that is not a Delphi platform got its own `COMP-008` with the same
  list of valid ones that `BUILD-003` gives in the build, its gate and
  `delphi_config`; it now gets `BUILD-003`. `delphi_test` keeps its
  `TEST-001`, which lists the platforms that can RUN on this machine
  (`tests/test_missing_units.py`).

### Removed

- **The startup purge no longer touches the workspace roots.** Since 1.18.2
  nothing of the server lives in a root - the captures went to its own home -
  and emptying every `__delphi-temp` under each root only took away what
  earlier versions left there: the server deleting inside a workspace, which
  is not its home, and on a root two machines share, what the other machine's
  server had in flight (hence the one-hour cut of the network roots). Its own
  comment said to retire it in 1.19. The server's home is still emptied at
  startup, by the only live instance of the exe; whatever an earlier version
  left in a root is the operator's to delete, hidden from every listing and
  refused for writing (`tests/test_purga_temporales.py`).
- **The unit rename, and the texts only it used.** Rewriting a renamed unit's
  header, the uses of the other units and their `UnitOld.X` references had no
  caller left once a move stopped re-pointing (`fix-references` re-points by
  the same name). Retired ids: `CFG-057`, `CHSET-033`, `FILE-002` to
  `FILE-006`, `FILE-019`, `FILE-026`, `FILE-027`, `FILE-035`, `FILE-039`,
  `FILE-043`, `MOVE-005`, `MOVE-006`, `MOVE-010`, `MOVE-015` to `MOVE-019`
  (`tests/test_catalogo.py`, C11: no constant of the catalogues goes unused).

### Fixed

- **The all-or-nothing restore never writes in place through a hard link.** When
  an operation fails, `TFotoDeFicheros` puts each file back through the jail's
  atomic writer - a temp beside it and a rename, which breaks a hard link and
  never writes outside. A path too long to fit that temp (`GUARD-028`) is
  restored by a direct in-place write instead, and that write did not ask whether
  the file had other names: a hard link would change the bytes under all of them,
  and one can be outside the jail (`GUARD-043`). The direct restore now refuses a
  hard link and reports it, instead of writing in place. It is a second barrier -
  the atomic writer already refuses a long path, so no tool modifies one and a
  delete or move breaks the link; the unit test drives the snapshot directly
  (`src/UnitTests/LspTests.RestauraEnlaceDuro.pas`).
- **Paths inside the jail are compared the way the filesystem compares them,
  not the way a language does.** "Is this path inside a root?" and "is this the
  root, a protected place, the same entry?" were answered with `StartsText` and
  `SameText` (and one `MatchText`), which fold with the user's locale: they
  called two names the SAME - the German sharp s in its two cases (U+00DF and
  U+1E9E), or two forms of the "dz" digraph (U+01C5 and U+01C4) - while NTFS
  keeps them as different entries. With a root named with the lowercase sharp s,
  an outside sibling named with the uppercase one was read AND written through
  the jail - measured against production r1222ci, and against published 1.22.1
  (the hole predates it). The comparison now goes through one ordinal judge, the
  filesystem's own: `RutaDentroDe` for "inside or is" and `RutaEnLista` for a
  path against a list (`Lsp.Rutas`), both on the same engine as the RTL's
  `SameFileName` (`CompareStringOrdinal`, ignore-case), and the equality sites
  call `SameFileName`. It only ever errs toward "outside" / "different": it
  denies more, never less. The same fix lets a case-only rename of an accented
  name through, which `SameText`, folding only a-z, used to refuse as a move
  "into itself" (`EnLugar`, `CaeDentro`, `MismaEntrada`, `RootItselfDenied`,
  `RemoteRunProjectDenied`, `LugarProtegidoEn` and the root and place prefixes in
  `Lsp.Guard`; `EnLugar` in `Lsp.Rutas`; two sites in `Lsp.Lugares`). The judge
  is measured against the disk itself (`src/UnitTests/LspTests.RutasOrdinal.pas`:
  it creates the pairs and asks NTFS whether they are the same entry) and
  watched by `test_paisaje`.
- **A dangling link can be deleted and moved.** A junction whose target was
  gone answered `SYS-012` "does not exist" to `delphi_delete` and `FILE-024`
  to `delphi_move` - existence was asked by following the link - and no tool
  could remove it; only the purge of the trash knew (2y of 1.18.2). Whether an
  entry is there is now asked of the name itself, a dangling link too, in one
  place, and the link goes to the trash or to its new name as a link
  (`tests/test_purga_enlace_colgante_1182.py`, Y3-Y4).
- **`delphi_list` and `delphi_search` count the vault notes they hide.** A
  knowledge vault inside a root was skipped without a word, although the
  description says hidden entries are counted (`delphi_projects` already did):
  now `hiddenVault` and `LIST-016`, which names the tools that show them
  (`tests/test_vault.py`).
- **`delphi_package` leaves out the IDE's `__history` and `__recovery`.** Old
  versions of the sources went into the deliverable; the description now says
  so too (`tests/test_round17.py`, R7b).
- **A folder a test leaves born locked no longer stays undeletable in the
  server's house.** A test can create a folder with an empty, protected DACL in
  the `CreateDirectory` call itself (no `WRITE_DAC` needed), which denies
  everyone, the owner included: the tree walker then raises `GUARD-040`, so
  neither the startup purge nor `delphi_test`'s between-runs sweep could remove
  it and it lived on as admin-only junk in the server's own temp. The two house
  sweeps now reclaim such a folder first (`ReclamaArbol`): as its owner the
  server gives it, as ONE object and without propagating, a protected DACL with
  a single ACE for its own account - just enough to list and delete it - and
  `BorraArbol` then removes it. The write is `SetFileSecurity`, not
  `SetNamedSecurityInfo`: the latter propagates inheritance down the subtree, a
  tree walk reserved for the guard's own walkers (measured: it does not follow a
  junction inside, but the server still must not walk a tree it was not asked
  to). Only inside the server's house (`ServerTempDir`), never across a link
  (`RecorreSinEnlaces` skips them), and never in the general `BorraArbol` - the
  agent's jail still answers `GUARD-040` for a folder it cannot list
  (`tests/test_casa_ilegible_1230.py`; `LspTests.ReclamaArbol`, measured
  directly; `test_paisaje.py`, the write-security namer).
- **The note of a move never says whether something outside the roots
  exists.** An `{$I}` or a `.dproj` property leading out of the roots was
  counted (`MOVE-023`, `MOVE-021`) only when what it led to existed, telling
  an agent that cannot read it whether it is there (measured). Whether a path
  exists is now asked after the read gate, by one helper (`ExisteYSeLee`);
  it was written by hand in six places, two of them without the gate
  (`tests/test_puerta_leer.py`, L4; `test_paisaje.py`).
- **`MOVE-021` says the right thing when the project itself moved.** When
  what moved was the `.dproj` and its relative property led to what stayed,
  it said "led to X, which is now X" under a header ("the build still reads
  these where what moved used to be") that was false: it now says "which did
  not move", under a header true both ways (`tests/test_puerta_leer.py`, L4).
- **A copy no longer brings git metadata through a link.** A folder holding
  a link to a repository was copied with that repository's `.git` behind the
  link (measured against the current release), although the copy promised
  that file tools never copy git metadata, links included. What the copy will
  copy is now listed first by the copier itself, with its own rules, and a
  repository reached through a link it follows is refused (`MOVE-022`).
- **The build's import scan reads a nested `<Import>` where msbuild reads
  it.** `$(MSBuildProjectDirectory)`, `$(ProjectDir)` and
  `$(MSBuildProjectName)` were expanded from the file that writes the
  `<Import>`; msbuild fixes them to the project being compiled across the
  whole import chain (measured with msbuild; only
  `$(MSBuildThisFileDirectory)` follows the current file). A nested import
  through one of them was scanned in one folder and loaded by msbuild from
  another, so the scan could judge a harmless file while msbuild imported a
  task; both walkers now expand them from the compiled project
  (`tests/test_build_imports.py`, a39).
- **A folder move no longer copies the folder's own trash into its safety
  copy.** Before moving a folder, `delphi_move` copies it to the recoverable
  trash, and that copy took the folder's `__delphi-patch` along: a trash inside
  the trash, with every earlier copy duplicated on each move (measured). The
  folder's trash travels with it - a move is a rename - so the safety copy now
  leaves every trash inside the folder out, as `copy=true` already did
  (`tests/test_evidente_1230.py`, E4).
- **The build refuses a `.deployproj` deploy command.** A `DeployFile` in a
  deploy manifest can carry a `<LocalCommand>` (run on the build machine) or a
  `<RemoteCommand>` (run on the target through PAServer) - a free command line
  handed to an executor. The ones the server writes are empty, and
  `delphi_config add-deployfile` can only write them empty, but an agent could
  fill them another way (an edit, an upload); the compile-only gate scanned the
  imported `.deployproj` for tasks and foreign imports and did not flag these.
  Now a non-empty `<LocalCommand>` or `<RemoteCommand>` is refused at the gate,
  however the file got there, by the same rule as a build event or a free
  compiler option - an agent asks for operations, it does not hand a command to
  an executor (`tests/test_build_imports.py`).
- **The build refuses a project source that is a link leading outside the
  roots.** The build's gate walks the project folder for hard links and
  directives, but a file in the tree that is a symlink or junction whose real
  target is outside the roots was skipped by the walker (it drops links it
  cannot read), so the gate never saw it - while `dcc`, which follows the link,
  would compile that outside file into the binary (measured: a unit used by
  `uses` that was a symlink to an outside `.pas` compiled with the server's
  permissions). The `in` path of the `.dpr` is already judged; now the folder
  walk also hands such links to the gate, and a source whose real target is
  outside is refused (`BUILD-063`). A link whose target is inside the roots
  still compiles (`tests/test_build_symlink_1230.py`).
- **`delphi_styles build` compiles a resource script the server wrote, not the
  agent's.** The `.rc` that names the compiled style resources went to `brcc32`
  as the agent wrote it, and `brcc32` has a preprocessor (`#define`, `##`) that
  composes file paths the server's second-barrier reader could not see - only
  the AppContainer stopped them, and it still reads what the OS grants every
  application package (Windows, Program Files; the V5 residue). Now the `.rc`
  of `delphi_styles` must be a plain list of `NAME TYPE [flags] FILE` entries
  (the file name in quotes); anything else - a `#define`, an
  `#include`/`RCINCLUDE`, a block, `LANGUAGE`... - is refused (`STYLE-056`), and
  the server composes the script it compiles from that list
  (`Lsp.Styles.RcCompuesto`, the inverse of `LeeRc`), so its preprocessor never
  runs on the agent's text. A `.rc` that is already a list compiles as before
  and the `.res` carries the same resources; the project build still takes a
  full `.rc`, and `lint` now reports a non-list `.rc`
  (`tests/test_styles_rc_lista_1230.py`).
- **The build no longer reads a unit from outside through the main source's
  `in`.** The build's gate judged the `{$I}`/`{$R}` directives and everything
  the `.dproj` reads, but not the path of `uses X in '...'` in a `.dpr` (or
  `contains` in a `.dpk`): `uses X in 'C:\anywhere\X.pas'` compiled, with the
  server's permissions, and what the compiler reads comes back out inside
  the binary and quoted in its errors. Nor were the directives of a unit of
  the workspace that lies outside the project's folder judged - one reached
  by such an `in`, or by a search path or include path of the workspace -,
  so its `{$I}` of a file outside was read too. Each `in` path is now
  judged, whether the file exists or not (BUILD-061; one relative to the
  current folder of another drive cannot be checked, BUILD-062; an entry
  that does not read as one, USES-026), and those units' directives are
  judged like the project folder's (BUILD-028). `delphi_config remove-unit`
  takes such an entry out (`tests/test_build_in_fuera_1230.py`).
- **A connection profile is read only if the IDE lists it, and
  `delphi_desktop` checks its name at the gate.** `delphi_desktop` did not
  hold its `profile` to the name rule of `delphi_build` and
  `delphi_paserver` (letters, digits, `_`, `-`), which the parameter's
  description promises for all three, and the reader of a profile composed
  the path of its `.profile` from the name as typed: with `..` in it, it
  looked at any `.profile` on the disk, outside the workspace, and the
  refusal told whether one existed (PAS-054, "could not read") or not
  (PAS-053). The reader now opens only the file of a profile the IDE lists,
  by its name in the list, and `delphi_desktop` refuses a bad name with
  PAS-015 like its siblings (`tests/test_perfil_por_lista_1230.py`).
- **`delphi_adb run` launches a package the device lists.** The app name
  went to `am start` as typed; it is now chosen among the packages the
  device's package manager lists (`pm list packages`) - the exact name, or
  the only one that differs just in case - and what reaches the device is
  that name. A package that is not installed is refused before anything
  runs (ADB-029).
- **`delphi_adb` no longer reports a failed `connect` or `run` as done.**
  `adb` exits with 0 when `connect` does not attach ("cannot connect to
  ...") and when `am start` starts nothing ("Error: Activity class ... does
  not exist."), measured with the IDE's adb 37.0.0, and the answer came back
  as a success. Both are now judged by adb's own words: a `connect` that
  does not say "connected to" is refused with the way to attach - on
  Android 11+, pairing the device with the server once, which its operator
  does with `adb pair` (ADB-030) -, and a `run` whose activity does not
  exist says the app is not a Delphi FMX one (ADB-031). The `logcat`
  pre-check and the `screenshot` steps that had already decided a failure
  no longer turn it into a success when adb exited with 0, and a capture
  that did not arrive reports adb's real exit code. The tool description
  and the `discover` note no longer promise an authorization prompt on the
  first connect (`tests/test_deploy_adb.py`).
- **The folder digest of `delphi_symbols` sees a unit written with tabs.**
  What each unit of a folder declares is read as text, and those rules took
  only spaces between words: in a source indented and aligned with tabs,
  `class<TAB>procedure`, a constant `MAX<TAB>=<TAB>1` and a variable
  `V<TAB>:<TAB>Integer` were missing from the digest. The start of a routine
  header (an optional `class` and the routine word) is now one pattern
  (`Lsp.Pascal.PatronInicioDeRutina`), shared by the five places that wrote
  it by hand (`tests/test_lector_clases.py`).
- **A file with no BOM and no accent is labelled `ascii (utf8/ansi
  compatible)`, not `utf8`.** `delphi_read` said `encoding=utf8` of a unit
  that the IDE opens as ANSI: with nothing but ASCII, UTF-8 and the ANSI page
  read it alike, and the detector follows the IDE's preference for NEW files
  (which still decides how a source born in the same call is written). The
  label of `delphi_read`, `delphi_edit` and `delphi_textedit` now has one
  composer (`Lsp.Patch.EtiquetaDeCodificacion`); `delphi_textedit create`
  already said it this way with a rule of its own. And an edit of
  `delphi_textedit` reports the encoding of what it left on disk, not the one
  it read: the first accent of an ASCII text is written in that of a new file
  of its class. No byte changes (`tests/test_delphi_patch.py`).
- **A deployment manifest the server generates looks for the build where the
  build left it.** With an output folder of its own (`delphi_config
  set-output Compiled`), an Android build leaves everything - its
  `AndroidManifest.xml`, its resource `.xml` files and `lib<project>.so` -
  in `Compiled\Android64\Debug`, and the generated manifest looked for them
  in `Android64\Debug`: the Deploy failed with "Required local file
  Android64\Debug\AndroidManifest.xml not found" (measured). The minimal
  manifest of a PAServer platform had the same folder written by hand. The
  output folder of a build has one composer (`Lsp.Dproj.SalidaDelBinario`),
  shared by the build's own output and the three manifest generators, and the
  minimal one writes the same entry as one added to an existing manifest.
  And a project that declares no configurations - which builds any - gets
  the group of the configuration it deploys, not only Debug and Release
  (`tests/test_deploy_adb.py`).
- **A test never runs in a job without its limits.** `delphi_test` runs a
  test inside a Job Object (kill-on-close, a cap of 3 GiB per process and
  one on processes) and refuses to run it when the job cannot be created;
  but when Windows refused to SET those limits, the test still ran, in a
  job that limited nothing. A job whose limits cannot be set now counts as
  one that could not be created (TEST-032); the build and git, which run
  without a job when it cannot be had, keep doing so. The cap itself was
  measured: 3.5 GB is refused inside a test and granted outside.
- **The mojibake warning sees UTF-8 read as Latin-1 on every code page.** New
  text carrying UTF-8 read as Latin-1 or CP1252 (`Ã³` for `ó`, what an agent's
  tools make of a UTF-8 file) was warned about only where the machine's ANSI
  page is 1252: on any other, those characters have no ANSI byte and the
  detector did not read them (measured with the server running in code page
  1251). Every character from U+0080 to U+00FF now counts as the Latin-1 byte
  it comes from, as U+0080 to U+009F already did; on a 1252 machine nothing
  changes.
- **`delphi_adb` and `delphi_designer` describe only the captures they
  make.** `inline` and `maxwidth` had one text for the three tools that
  capture, naming a screenshot, a gesture's capture and a preview in all of
  them, and a frame to pass to `tap` or `type`: `delphi_adb`'s `tap` returns
  no image, and `delphi_designer` only draws in `preview`, whose frame maps
  the image to form units and is taken by no command. Each tool now puts its
  own head before the common rule, as `out` already did; `tools/list` is 209
  characters lighter.
- **The server stops at once on a busy machine.** At startup it warms the
  designer tables in a low-priority thread, and on the way out it waited up
  to 5 s for that thread: with every core busy, Windows did not give it the
  time to see that the server was closing, and every stop took the 5 s
  (measured with twelve processes burning CPU: 5.3 s, 13 times out of 13; a
  full battery run twice saw a stop go past the harness's 15 s). The thread
  is raised to normal priority before the wait: 0.1 s
  (`tests/test_atomos_1202.py`, C1).
- **An agent's `out=` is judged by one question, before anything runs.**
  `delphi_desktop` checked its `out=` with the jail alone before the gesture:
  one inside the trash passed, the tap or the typing reached the target, and
  the refusal came afterwards. `delphi_adb logcat` let its `out=` write into
  an old `__delphi-temp` left in a root, which every other writer refuses
  since 1.18.2. Both, the captures and `delphi_git worktree` now ask the one
  gate for a destination the agent names (`WriteTargetDenied`, which now
  includes the read-only mode the mixed tools added by hand), and the writer
  that places a product asks it too, so a caller that forgets cannot place
  anything in a dead folder (`tests/test_round43.py` W1c,
  `tests/test_deploy_adb.py`).
- **A new unit name is judged by the library the compiler resolves.** The
  rule against hijacking a library unit was two lists by hand (28 units, 14
  namespaces): `Generics.Collections` passed (it is
  `System.Generics.Collections` through the `System` unit scope), and so did
  the unit of any installed component (`IdHTTP`). It is now the `.dcu` and
  `.pas` files of the IDE's Search Path for Win32 and Win64, where `dcc`
  looks: a unit's exact name is refused (`CREATE-009`), and so is hanging a
  name from one of the library's namespaces, directly or through a unit
  scope (`CREATE-010`). A short name that only reaches a library unit
  through the scopes of a project the IDE creates (`SysUtils`, `Consts`) is
  created with a note that says so (`CREATE-037`): it only affects code that
  writes that name unqualified. Most of the old list (`SysUtils`, `Forms`,
  `Windows`...) was refused and now gets the note; `System`, the exact name
  of a unit, is still refused. The same rule and note serve
  `delphi_create`, `delphi_edit` creating a unit and `delphi_move` renaming
  one (`tests/test_round10.py`, B2).
- **What a writer that died leaves in the server's caches is purged.** The
  designer tables and the engine settings are rewritten through the atomic
  writer, whose intermediate is `.<name>.<8 hex>.delphi-patch-tmp`. The
  purge of the tables deleted `.tmp` files, which nothing writes since that
  writer took over, and the purge of the settings did not see them: an
  intermediate left by a process killed mid-write stayed for good. Both
  purges now ask the writer's own reader and remove the ones older than an
  hour (`tests/test_designer_tablas.py`, `tests/test_motor_fuera.py` F0).
- **The designer tables see what a unit streams or registers from an
  include.** The generator decides whether to read what a unit stores by
  code (`DefineProperties`) or registers (`RegisterComponents`...) by looking
  for those words in the raw file, without its includes, while the reading
  that follows does expand them: a `DefineProperties` or a `Register` in a
  `.inc` was never read. It now looks at the same active text, includes in
  and comments out. The tables move to generation 15 and are rebuilt once.
- **`delphi_designer set` judges `HelpContext` as the integer it is.** A
  subrange whose bound is a named constant got no base type in the designer
  tables: `THelpContext = -MaxInt..MaxInt`, the `HelpContext` of every VCL
  and FMX control, and `TWidth = ColumnHeaderWidth..MaxInt` of a list view
  column. `set HelpContext=abc` was written, and only `lint`, through the
  IDE's form reader, said the form would not load. A signed bound is now a
  number, and a named one is followed to its value in the unit that declares
  it, searched in the order the compiler uses; what cannot be followed is
  still left unjudged. The tables move to generation 16
  (`tests/test_designer_modalresult_1191.py` H1).
- **A `pattern` of `delphi_list` and `delphi_search` takes any name Windows
  takes.** Each mask was checked against a grammar of our own - letters,
  digits, spaces and `* ? . - _` - that refused real file names such as
  `Unit1 (copia)*.pas` or `O'Brien*.pas` (`WS-005`). It is now asked what
  the file walk itself asks, `TPath.HasValidFileNameChars` with wildcards:
  no folder, no drive, none of `< > | "`. Braces `{a,b}` are still refused
  (`WS-006`) (`tests/test_textos_1230.py` T4).
- **`delphi_designer preview` loads a design package with "wizard" in its
  name.** The renderer skips the IDE's experts by the name of their `.bpl`,
  and "wizard" also matched `JvWizardsDesign`, the design package of JVCL's
  `TJvWizard`: a form using it came out as pink boxes, and the note said the
  package was not installed. That pattern caught no expert the others miss,
  and is gone; the version-control experts are now matched without the
  IDE's version written in (`ide370` would have stopped matching with the
  next RAD Studio) (`tests/test_designer_preview.py` P8b, where JVCL is
  installed).
- **A unit in a folder with an apostrophe joins and leaves a project cleanly,
  and a uses clause that does not read as a list is never rewritten.**
  `add-unit` wrote `in 'David's units\UFicha.pas'` without doubling the
  quote: the `.dpr` did not compile (`E2052`) and the tool said `ADDED`.
  `remove-unit` read that path up to the quote and left its `DCCReference`
  in the `.dproj`. With a quote left open, the clause reader did not see its
  `;`, and rewriting the clause took the `begin` and the first statements of
  the program with it, while the tool said `REMOVED`. An entry is now
  written and read by one pair, with the path quoted as the compiler reads
  it; a clause where something is not an entry is refused (`USES-026`) by
  every tool that rewrites one; and a `CreateForm` split over two lines
  goes with its unit (`tests/test_dpr_entradas_1230.py`).
- **The server stops even when a connection crosses the stop.** Indy's HTTP
  server waits, with no limit, for every connection to end, and one that
  arrived just as the server stopped could be left with nothing to end it:
  the stop spun for ever (measured with a debugger on a hung server; as a
  service, a stop with a request in flight would have stayed in
  `STOP_PENDING`). The HTTP stop now has 3 s; past them it is logged and
  the service goes on closing (`tests/test_atomos_1202.py` C1).
- **A text file that was pure ASCII gets its first accent in UTF-8, as a new
  one is born.** `delphi_textedit` creates a `.md`, a `.py` or a `.json` in
  UTF-8, but editing one that held only ASCII followed the IDE's default
  encoding for sources: with that set to ANSI, a `.md` came out in the
  machine's ANSI code page, which Python, JSON readers and a Git web view
  do not read. Such a text now takes the encoding a new one of its kind
  gets (an IDE project, UTF-8 with a BOM); a source keeps its own rule, and
  a form or a text `.style`, both read by the IDE's form parser, stay as
  they are (`LspTests.Encodings`).
- **`delphi_designer lint` no longer lets any property through on seven
  classes.** What a class stores by code (`Filer.DefineProperty`) is read
  from its source. The declarations of `TReader.DefineProperty` and
  `TWriter.DefineProperty` in `System.Classes` were read as calls whose name
  could not be told, so a class whose `DefineProperties` names `TReader`
  (`THeaderStrings`, several JVCL classes) was taken to store any name. And
  a body ran on to the next routine in column 0, past a `type` section in
  between, so `TImage` (FMX) and `TCustomDSRESTServerTransport` "named" the
  `TReader` subclass declared after them. A misspelt property on any of them
  passed the lint. Bodies now come from the source reader, and a
  declaration is not a call; those classes keep the names they really store
  (designer tables, generation 17).
- **`settings.ini` has one reader.** The HTTP transport's keys (`[Server]`
  `Port`, `Host` and `Endpoint`, `[CORS]`, `[SSL]`) were read by the vendored
  settings class with a `TIniFile` of its own, which could also compose the
  file's path from the executable and create or overwrite it - the last of
  the loose readers the server's own reader took in on 2026-09-26. They are
  read now with everything else, with the same calls and defaults, and the
  class only holds the values; the vendored logger loses its file writer,
  which nobody turned on (the log is the server's own). Found when
  `tests/test_paisaje.py` started to walk the vendored units the server
  compiles, which it never did.
- **A Deploy with no profile anywhere is refused before it builds.** With no
  `profile=`, no `<Profile>` in the project and no profile the IDE keeps for
  the platform, `delphi_build target=Deploy` ran msbuild, which built and then
  stopped with its own "Missing profile name" (41 s on Linux64; on Win64 the
  same with a deployment manifest, and `MSB4057` "the target Deploy does not
  exist" without one - none of them saying that a profile is missing). It is
  now refused before anything runs (`BUILD-058`), naming the profiles that
  deploy that platform, by the rule of the IDE's own target (`_VerifyProfile`
  in `CodeGear.Profiles.Targets`): a profile for every platform but Android
  and a Windows `BT_BuildType=AppStore` package, which goes to no machine;
  `CFG-028` and `CFG-032` say so.
- **A project file with mixed line endings keeps the ones a writer did not
  touch.** The `.dproj` and `.deployproj` writers compose the whole file with
  `sLineBreak`, and the saver gave the new lines the file's ending only when
  the file had no CRLF at all: in an LF file with one CRLF line,
  `add-searchpath` left the LF line before its block in CRLF. The saver now
  follows the rule of every line editor - what was not touched stays byte for
  byte, what is new takes the file's dominant ending - finding what stayed
  with a bounded line diff and changing each stretch through the same
  composer (`CambiaLineasEnSuTexto`).
- **A build for another platform says it left the version resource empty.**
  The project's `.res` (icon, version info, manifest) is one for every
  platform that shares its folder, and `BuildVersionResource` rewrites it for
  the platform of each build - but on a Make only when the `.dproj` is newer
  (`CodeGear.Common.Targets`). Measured: a Linux64 build leaves it with no
  resources (32 bytes), a Win64 Make keeps that one and the exe ships without
  icon or version info (155,136 bytes smaller), a Build restores it. The build
  that empties it now says so once (`BUILD-059`, `resNote`), and so does a
  Windows Make that finds it empty (`BUILD-060`) (Hermes, 2026-10-22)
  (`tests/test_evidente_1230.py`).
- **A desktop node that cannot reach the session's bus says so.** Every way
  the node fails writes its reason on the line the server reads
  (`Could not capture: <reason>`), and the server passes it on - except
  `NODE-028` ("no desktop to talk to", when the session bus does not answer),
  written without that mark: the answer was `DESK-018`, "the node did not say
  why", when it had. The line now has one writer in the node (`NoPude`),
  watched by `tests/test_paisaje.py`.
- **Answers that misled about what the server or the IDE does, each measured
  first (the 1.22.2 reviews).** `delphi_designer set` of FMX
  `TextSettings.Font.Style` said the IDE does not store it (`DSGN-165`), and
  the IDE writes it as `TextSettings.Font.StyleExt`: the properties a class
  never stores by name are now read from its sub-objects too, so the answer
  says `storedIn`. `delphi_diagnostics` of a `.inc` stayed "in progress" for
  good (measured: six minutes with three lines): an include file is refused at
  once (`LSP-051`) - lint the unit that includes it. `delphi_config
  add-searchpath` judged `%2E%2E\Lib` as typed (`CFG-018`, "does not exist")
  while msbuild reads `..\Lib`: it is judged unescaped, as the build reads it -
  the jail and the characters too, so a `%3B` (a `;` that splits the list) is
  refused. `delphi_search` took one mask and `delphi_list` several separated
  by `;`: one reader for both, several masks in each and every one checked (a
  piece naming a folder was silently ignored by list). `BUILD-008` named a
  package once per unit (`vcl` twenty times). `STYLE-003` said the server
  cannot read a `.bin.style` - it is `delphi_styles` that works on the text
  one; `DESK-008` said the activities overview was open after Super, which
  closes it when it was open; `ADB-005`, given for a device the command does
  not even use, says to leave it out; the `mode` of `delphi_symbols` promised
  to say when the tree is the full one. And `delphi_designer set prop=Name`
  said the IDE keeps the names of a component's handlers (`DSGN-103`):
  measured in the IDE, renaming `Button1` to `BtnOk` renames the handlers it
  named after it (`Button1Click` -> `BtnOkClick`: declaration, header and the
  form lines that bind them), keeps one with a name of its own and leaves the
  code that calls them - and so does the server now (`methodsRenamed`), with
  those calls in `usesInCode`, as they no longer compile. And `delphi_config
  set-profile` called itself "the twin of set-sdk: in the IDE a target gets
  both": measured in the IDE, choosing a platform's profile in its Project
  Manager writes nothing in the project - the IDE keeps ONE profile per
  platform for all its projects - so the `<Profile>` set-profile writes is
  read by msbuild and not shown by the IDE (which is what lets two projects
  deploy to two machines); its texts say so, `view` shows the IDE's one as
  `profileSource: ide-default` (it said `none`), and `delphi_build
  target=Deploy` with no `profile=` and no `<Profile>` deploys, like the IDE,
  with the IDE's profile for the platform, judged by the same gates as any
  other (it stopped with "Missing profile name"; the answer's
  `profileSource` says where the one used came from)
  (`tests/test_textos_1230.py`, `tests/test_deploy_remotehost.py`).

- **An inherited component with no block in the descendant form can be read
  and changed.** The IDE writes in a descendant form only what differs from
  its ancestor (measured in the IDE on 2026-10-24: changing the form's
  `Caption` leaves `Button1` and `Button2` of its `Panel1` without a block;
  changing `Button1.Left` writes `inherited Panel1` with `inherited Button1`
  inside and only its `Left`), so a component nobody has touched has no
  lines in the file - and `delphi_designer get`, `set`, `delete` and `insert
  parent=` answered `DSGN-078` ("there is no component Button1") with no way
  forward, while `preview` found it. Now `set`, and `insert` or `set parent=`
  into such a container, first write its `inherited` block and those of its
  missing parents, each where the IDE's writer puts it among its siblings
  (`DSGN-171`, `inheritedNote`); `get` says what it is and shows it as the
  IDE's form reader loads it (`DSGN-172`); `delete` and a rename answer the
  refusal for an inherited component (`DSGN-084`). The same for a component
  of a frame placed inline, which the IDE's writer also skips when it does not
  differ from the frame - and `DSGN-083` promised its properties could be set
  here, by its path: `set Marco1.Dentro` now writes `inherited PanelF` >
  `inherited Dentro` inside `inline Marco1`, `get` names the frame it comes
  from, and `delete` answers the frame's refusal (`DSGN-083`). And `set
  before=` / `after=` takes such a sibling as its reference (it answered
  `DSGN-078` too): the IDE's writer judges the order with it where the
  ancestor creates it, and no block is written for it, as the IDE writes none
  for what does not differ (`tests/test_heredado_sin_bloque_1230.py`).
- **`get-sdk` no longer pulls on top of an SDK it did not bring, and nothing in
  the IDE's registry is changed without a copy.** Its guard against two
  distributions in one sysroot only acted when the folder had its record
  (`mcp-sdk.json`) and both distributions were known: with a folder without it
  (made by the IDE, by hand, or left by a pull that failed half-way), a target
  whose `/etc/os-release` could not be read, or a record with no distribution,
  paclient pulled on top - and an `.sdk` file or an SDK Manager seat of that
  name that `get-sdk` had not made was overwritten. Now an SDK is `get-sdk`'s
  only when its record says so, and anything else with that name is refused
  (`PAS-064`); a target whose distribution cannot be read is refused before
  anything is created (`PAS-065`), where it fell back to the profile's name;
  the record is written before the first pull, so a pull that fails is retried
  in its own folder; and the connection is checked first. `reseat-sdk` leaves
  an SDK without a record to the SDK Manager (`PAS-066`). The registry: the SDK
  and profile seats that `get-sdk`, `reseat-sdk`, `remove-sdk`, `add-profile`
  and `remove-profile` write or delete, and `Default_Linux64` with
  `active=yes`, were changed without a copy, unlike the files beside them. Now
  one door exports the key first with `reg.exe` - opening the copy puts it
  back - and leaves alone one that already says the same
  (`previousIdeSeatCopy`, `previousIdeDefaultCopy`, `removedSeatCopy`,
  `PAS-067`; `PAS-068` and `PAS-070`
  when it cannot). `add-profile` answered `ideRegistered: true` even when the
  seat was not written; now it says so (`tests/test_get_sdk_1230.py`).
- **A text form saved in UTF-16 or UTF-32 is no longer passed off as one the
  IDE opens.** The IDE's code editor lets a `.dfm` or `.fmx` be saved in
  UTF-16 or UTF-32, but its designer does not load it again ("Invalid stream
  format", measured on 2026-10-24 with UTF-16 LE, UTF-16 BE and UTF-32), and
  the compiler refuses it too (`E2161`). The RTL says so by construction:
  `TestStreamFormat` takes a leading `$FF` for a binary form and `FE FF` or
  `00 00 FE FF` for nothing it knows, and its form parser refuses any BOM but
  UTF-8's. The server converted such a form to UTF-8 or UTF-16 before asking
  that parser, so `lint` called it clean, `preview` drew it, `insert`, `set`
  and `delete` wrote it, `to-binary` converted it, and the note (`DSGN-121`)
  said "The IDE opens it". Now the parser gets the bytes as they are: those
  commands refuse the form (`DSGN-122`, with what the parser said), and the
  way out is `to-text`, which turns it into the text the IDE writes (ASCII,
  an accent as `#N`; UTF-8 with a BOM when a name needs it), backup first, its
  unit untouched (`DSGN-170`) - for a `.fmx` too, which `to-text` refused
  outright (`DSGN-013`: FireMonkey has no binary form). A half character in
  such a form is refused there (`DSGN-147`). A form whose ancestor is one of
  them is drawn without it, and
  the warning names that file (`RENDER-023`) instead of saying the ancestor
  has no file; `delphi_edit` keeps editing it as text, and its note now says
  how to fix it (`tests/test_form_ancho_1230.py`).
- **A link the server cannot follow is judged closed.** A junction inside the
  roots whose attributes the service's account may not read (a deny ACE on it
  and on its folder) cannot be opened, so its target could not be resolved -
  but Windows still goes through it. The jail kept the path as written, inside
  the roots, and let it pass: creating, editing, uploading, moving, copying,
  deleting and reading through such a link were stopped only because the RTL
  failed to create or find the folder, with an `INTERNAL` error (measured on
  2026-10-24 with the production build, on folders of the test's own). This
  covers both a link whose attributes read but that neither opens nor yields
  what it stores and one whose attributes cannot be read at all
  (`ACCESS_DENIED`, when its folder cannot be listed either - seen only on a
  volume without the inherited capability ACEs a temp folder carries). The
  real path of such a link is now outside every root, and the jail refuses it
  (`GUARD-001`, whose text now says so); a folder that cannot be opened but is
  not a link is judged as before, and a protected place keeps being compared
  by what it says (`tests/test_enlace_ilegible_1230.py`).
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
  inside a frame is now refused with its path (`DSGN-078`), and
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
- **A new file is born in one encoding, whoever creates it.** A `.dproj`
  created by a `delphi_changeset` was written in UTF-8 without a BOM, while
  `delphi_create` writes it with one, as the IDE does: there were three rules,
  one per creator. Now a source or a form takes the IDE's configured encoding,
  the IDE's own XML (a project, a group, a deployment manifest) UTF-8 with a
  BOM, and anything else UTF-8 without one, in `delphi_create`, the changeset
  and both edit tools. The `eol` a create asks for is read by one reader too
  (`tests/test_nacer_1230.py`).
- **A source is a package because it says `package`, as the compiler reads
  it.** `dcc` compiles a `.dpr` that starts with `package` into a `.bpl` and a
  `.dpk` that starts with `program` into an `.exe` (measured on 2026-10-24),
  but `delphi_config add-requires`, the `CreateForm` of a unit added to a
  project and the note about a form in a console project decided it by the
  `.dpk` extension: a package written in a `.dpr` was refused its `requires`
  (`CFG-049`), and a program written in a `.dpk` was given one - a
  `requires vcl` inside a program, which then no longer compiled. They ask the
  source's own header now (`tests/test_paquete_1230.py`).
- **`delphi_projects` given a file says it is a file.** It answered `PROJ-003`,
  "does not exist... there is nothing there", for a file that was there;
  `delphi_package` said `LIST-002` naming `delphi_list`. The three tools that
  take a folder now say `LIST-002` with their own name, and `LIST-011`, a
  second code `delphi_list` had for the same thing and never reached, is gone
  (`tests/test_hermanas_1230.py`). The README no longer promises that a more
  restricted token (LPAC) for the resource compiler of `delphi_styles build`
  closes what it reads under `C:\Windows` and `Program Files`: those folders
  grant read to restricted application packages too (measured on 2026-10-24).
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

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
- [1.22](docs/changelog/1.22.md)
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
