# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- `delphi_delete purge` does not let one agent purge a file named like an owner marker (`*.by`) inside the copy another agent sent to the trash: it was taken for an orphan marker, and nobody asked whose copy held it. Such a file arrives by git, a copy or a zip; the trash's owner rule now covers it.
- `delphi_changeset` does not create a project file (`.dproj`, `.groupproj`), as `EDIT-128` already said and `delphi_textedit` already did: it refused only to edit one, and a `create` was staged, previewed clean and written. Moving or deleting one is still the operator's, as in `delphi_move` and `delphi_delete`.
- `delphi_build target=Deploy` that fails no longer tells you to kill a remote-run job that does not exist. `deployLockedNote` looked for `E0017` and the watcher's name anywhere in msbuild's console, so a folder with such a name was enough; it now reads the lines msbuild classifies as errors, with both on the same line.
- `RENDER-026` says which file holds the inline it left out: the form you asked for may not be the one that closes the cycle.
- What lives in another file of a form now says which file, and its line there. A property the IDE's reader skipped inside an inline frame's or an ancestor's file came out of `delphi_designer preview` without a line while `DSGN-114` promised "line says where each one is", `lint` gave no line, and a frame that could not be read named only the form. A control inside an inline frame that the form does not override came out of `layout` with `line: 0`. Now `ignored` entries, `lint` warnings and `layout` boxes carry `file` and the line in it. The renderer says which file it was reading, and where each control is written (render protocol 4). A frame that contains itself no longer counts as a property in `DSGN-114`: `RENDER-026` already names its file and what to do.
- `delphi_config view` shows the project's version (`version`, the one the build puts in the binary), whether the binaries carry it (`versionIncluded`) and, when the VERSIONINFO numbers and the FileVersion key disagree, both (`versionMismatch`). After `set-version` there was no way to read it back but to open the `.dproj`.
- `delphi_changeset` creates a file that is not Pascal as `delphi_textedit` does: in CRLF, without a final line break nobody wrote. A `.json` or a `.txt` came out with one; a source or a form still ends in its line break, as `delphi_create` writes it.
- `delphi_designer insert` and `set parent=` on an FMX form say when the control sticks out of its parent (`outsideParent`), as they did on a VCL form. FMX was skipped for a reason that no longer held: `layout` measures FMX forms since 1.24.
- A remote job is finished only when the launcher's closing line is the last one of its output, whole. A program that printed the sentinel inside a line, or an output read while the launcher was still writing it, was taken for a finished job.
- A network path with an accented letter, inside the JSON of an answer, comes back in its declared form. The JSON escapes a letter that is not ASCII, and the matching wrote it as it was, so the server's real host name showed.
- A program run on a Windows target (`remote-run`, and the desktop node) gets its arguments as Delphi reads them. The launcher composed the line by the rules of the C runtime, so a Delphi program got a final backslash doubled and a double quote turned into backslashes: `delphi_desktop type` with `di "hola"` typed `di \hola\`. The text of `type` now travels encoded and the node decodes it; an argument with a double quote for a program on a Windows target is refused before anything runs (`RUN-025`), since Delphi's `ParamStr` cannot receive one.
- Two `delphi_adb screenshot` calls on the same device at once each get their own capture. The capture on the device had one fixed name and no lock, so one call took the other's image and the other found none; each now names its own.
- `delphi_build` refuses a path the build reads that carries a device prefix with no drive or network path behind it (`\\?\GLOBALROOT\Device\...`, a volume by its GUID): `BUILD-050`, outside every root. The gate dropped the prefix and judged what was left, a relative path that fell inside the project, while the compiler opens the device.
- A search path that names one folder twice, differing only in case or in a final backslash, reaches the language server once, as the IDE's library already did; two folders that differ only in `ss` and `ß` stay two, as they are on disk.
- `delphi_designer set` no longer refuses a sound value with `DSGN-158` ("the form would not open") when the IDE's form reader was stopped for time instead of judging it: a renderer that ran out of time judged nothing, and the value is now written with `readerNote` saying it was not judged, as when the reader could not be asked.
- A conversion of a form (`to-text`, `to-binary`, reading a binary `.dfm`) stopped by the renderer's own budget says it was the converter's time, not that something in the form waits.
- `delphi_designer layout` on an FMX form gives a control of the form its own line, not the line of a control with the same name inside an inline frame that comes before it.
- The rows of a batch (`edits`) and a few other echoes no longer cut a character in two: an emoji at the cut left half of it in the answer.
- `delphi_changeset stage` takes `ops` encoded twice (a JSON string holding the list), as `edits` already did.
- `vault_append` finds an `anchor` of several lines sent with Windows line breaks; it never matched, while `vault_patch` already took them.
- A project in a folder whose name has a comma builds when the build supplies its `.dcu` folder: msbuild split the value at the comma.
- A first load of the IDE's design packages answers before an MCP client gives up, and says it was the packages. Under Microsoft Defender it can take more than a minute once (each package it has not seen is checked), and the renderer went on until its 60 s, past what many clients wait, to answer `RENDER-007`, which then said "repeat" and also "something in the form waits". Now loading the packages has a budget of its own, 50 s, and a renderer still loading them answers `RENDER-027` with how many it loaded and the one it was on, so a package that hangs while it loads is named instead of asking for one repeat after another; repeating the call goes on from there (measured on a 4-core VM, three times with new bytes: 50 s and then 17 to 20 s, against 69 s in one go). `RENDER-007` is left for a form that does not finish, and when the server itself stops a renderer it says which phase it was in (`DSGN-187` while loading packages, `DSGN-062` after).

- `delphi_test`'s `filter` reaches the DUnitX runner as a Delphi program reads its command line, and one with a double quote is refused before anything runs (`TEST-037`). The runner's line was composed by the rules of the C runtime: a double quote closed the filter and what followed it became other options of the runner, and a final backslash arrived doubled.
- Lists of folders and files no longer lose one of two names the disk tells apart. `compilesAgainst` in `delphi_projects`, the IDE's profiles and SDKs in `delphi_paserver profiles`, the projects `delphi_references` adds to its search and the PAServer installers were sorted lists compared with the user's locale, which takes `Strasse` and `Straße`, or a name with a soft hyphen, for one: the second went missing. They now compare names as NTFS does.
- A folder marked shared (`SharedFolders`) whose name has a letter that is not ASCII is shared whatever the case of that letter, as NTFS compares two names: a confined agent was refused it when the case differed.
- `delphi_workspace` names the server's account as Windows does, from the process's own identity. The domain came from `USERDOMAIN`, which whoever starts the process sets.
- `delphi_test` copies into its container a folder next to the test whose name differs from the server's temporary folder in a character the user's locale takes for the same one (a small hyphen for its hyphen). The copy compared the name with the locale, while NTFS keeps the two apart, so the test did not find that folder.
- `delphi_list` and `delphi_search` hide only the server's own trash, `__delphi-patch`. A second name, the copies folder of a tool that is not this server, was hidden as trash, while every other tool read, wrote and deleted in it as in any folder.
- A file's extension is judged as NTFS compares names. With the user's locale, a name ending in `.pa` and a modifier letter s was taken for a Pascal source (`delphi_textedit` refused it as a Delphi file) and one ending in `.dpr`, a modifier letter O and `j` for a project file (refused with `EDIT-128`); the same judge decided what `adduses`, `removeuses` and `check-binding` take as a unit and what `delphi_test` leaves out of its copy.

- The renderer's own time limit comes from the call's. `delphi_designer layout` waits 30 s for it, but the renderer was told 60 s, and 50 s for the IDE's packages, so its watcher never spoke and the server stopped it without the reason; it now gets 15 s for both, and a preview keeps 60 s and 50 s. A call that renders again with forms brought from other folders gives each new round what is left of its time, not all of it again.

- `delphi_designer layout` knows what a container does with its children by its class's ancestry, in that framework's class table, not by a list of names that mixed VCL and FMX. Two overlapping buttons inside a VCL `TTabControl`, which has one area, were not reported, because FMX's `TTabControl` has pages; the items of an FMX `TListBox` that do not fit were reported as sticking out and not visible, although they scroll (also on `insert`); a `TMemo`, `TGrid`, `TPresentedVertScrollBox`, `TGridPanelLayout` or a component derived from one was not recognized. The `Align` a VCL class does not write is the one its source redeclares with `default`: `TActionToolBar`, `TActionMainMenuBar`, `TFormTabsBar` and `TCategoryPanelGroup` were missing, and `TCoolBar` and `TControlBar`, which do not redeclare it, were taken as `alTop`.

- The style converter `delphi_styles` uses (`build`, `lint`, `set`, the platform defaults) runs inside a Windows container of its own, on a copy of the style in a folder of that call, as the form renderers do. It ran outside any container, reading the agent's file directly, and `build` ran it in the agent's folder: a converter that wrote a file there did it. Its output now carries a protocol number, like the renderers' (`STYLE-066` when a converter of another version answers; `STYLE-065` when its container cannot be prepared), and when it does not answer, the server's log says why.
- When the shared folder of the renderers' packages could not be prepared, the call that asked for it could release the folder from under another call still using it.

- `DelphiLspMcp.exe --install` (or `--uninstall`) says that the Windows service installer reads `/install` or `-install`, instead of installing nothing in silence: the server took the three spellings of a mode, but the installer only reads those two.

- The form renderer loads an IDE package registered with any of the IDE's macros: it knew `$(BDS)`, `$(BDSBIN)` and `$(BDSCOMMONDIR)` by hand, so a package under `$(BDSCatalogRepository)` or `$(BDSUSERDIR)` (GetIt's, the user's) came out as missing. An SDK's sysroot and libraries take every IDE macro too, `$(BDSPLATFORMSDKSDIR)` among them, from the same table.

- With `$(BDSLIB)` redefined in the IDE's Environment Variables, the language server's library folder and the package names `delphi_build` suggests for a package (`requiresSuggested`) come from that folder, as msbuild takes it: both were composed from the IDE's root.

### Changed

- `delphi_config`'s description says again that `add-platform` enables a platform in the `.dproj`. The second pass had dropped it, and with Qwen3.8 Flash Next the task "build Linux64 with the SDK zorin18" fell from 3 of 5 to 2 of 18; with it back, 9 of 18 (`docs/TOOL-DESCRIPTIONS.md`).
- `delphi_package` lists what it leaves out in one place, all of it: `*.dcu`, `dcu\`, the IDE's `__history` and `__recovery`, and the trash. The description and its `dir` gave two different, shorter lists.
- A project file staged in `delphi_changeset` is refused with `EDIT-128`, the message of `delphi_edit` and `delphi_textedit` for the same rule; `CHSET-018` said it with another code and a shorter list of what `delphi_config` does.
- `delphi_changeset preview` says of an edit whose anchor does not resolve what `delphi_edit` says of the same anchor: the lines where it appears when it appears more than once (`EDIT-077`) or when `atline` names another (`EDIT-062`), and, when it is not there, the similar line or the block it sits inside. It said `NOT FOUND` or `AMBIGUOUS (set atline)`, with no lines.
- Internal, nothing in a contract: one reader of a list of folders (`CarpetasDeUnaLista`), of the account's name, by Windows and no longer by the environment for a deploy's note (`NombreDeEstaCuenta`), of the X authorization on Linux (`XauthorityMasReciente`), of the process's identity (`SidDelProceso`), of the name of the server's trash and temporary folders (`EsNombreDePapelera`, `EsCarpetaDesechable`), of the `delphi_git` commands that use the network (`EsOrdenDeRed`: the remote's gate, the log, the lock and the timeout asked four lists), one writer of a new `uses` clause with its forms (`EstrenaClausula`; its two callers composed it, and the one-line unit's in its line was a third), one grammar of the conditional directives (`CondicionalDe`: the readers of a `uses` split into branches and the evaluator of the active branch each had a copy), one reader of a piece of a file (`LeeTrozoDeBytes`: `delphi_fetch` opened its own stream instead of going through the read gate), one namer of the new folder of an operation in the server's temporary folder (`CarpetaUnica`: four places composed it), one judge of whether a name is the calling agent (`EsDelAgente`, `EsDeOtroAgente`: the trash purge compared it three times and the confinement once), the words of the desktop node's protocol in its shared file (the orders the server gives it and its two desktops read, and the Windows session in the launcher's first line), the launcher's watcher line composed by the composer of the house, one composer of paclient's timeout and one probe of a PAServer profile (`PaclientPlazo`, `PaclientConecta`: test-connection and get-sdk wrote them by hand), one reader of the code view of a source the engine sees (`LoadSourceCode`: the inheritance and three places of references composed it), one name of the style converter (`NombreDelConversor`: the containers' box copied it by a literal of its own), one judge of a project file written by a text tool (`ProyectoDenegado`: the three doors wrote it by hand), the names that were still judged by the user's locale judged as NTFS compares them (the style lint's files, the owner marker, the designers a rename touches, the folders a move reports, the IDE profile or SDK chosen from its list: `IndiceDeRuta`), one key for a path in the cache of git folders (`ClaveDeRuta`), and one start, one report of what was read and one writer of a measure for the two form renderers.
- Seven tool descriptions are shorter, 891 characters in all (`delphi_config`, `delphi_changeset`, `delphi_move`, `delphi_test`, `delphi_build`, and the `new` of `delphi_edit`, `delphi_textedit` and `delphi_changeset`): no rule, limit or default went, and the one task Qwen3.8 Flash Next lost came back with the phrase of `add-platform` above (`docs/TOOL-DESCRIPTIONS.md`, the second pass).

## [1.25.1] - 2026-11-02

A patch for what measuring everything left pending after 1.25.0 found, and for what two
agents found testing that. The form designer no longer writes an edit after a client gave
up on it, which could land a control twice, and `insert` no longer closes a cycle of frames.
A frame that contains itself is told apart instead of bringing the renderer down, and
`RENDER-007` says to repeat the call: measured with Microsoft Defender's own report, the
first load of design packages after a signature update can pass the renderer's 60 s. Nothing
in a contract changes. Validated before the release through Hermes on a second machine by
Qwen3.8 Flash Next and GPT-5.6 Luna (directed tests of what changed).

### Fixed

- `delphi_designer` no longer writes an edit after a client may have given up. When judging an `insert`, `set` or a rename took 50 s or more, the client had usually stopped waiting (many give up at a minute) while the server went on and wrote: the agent repeated the call and the control landed twice. Now nothing is written and the answer says so (`DSGN-185`); repeating it works, since what was slow the first time is ready.
- A frame that contains itself, directly or through others, is told apart (`RENDER-026`, with the chain), and the rest of the form is drawn without it. The renderer fell with an access violation after about 3 s, `preview` blamed a design package (`DSGN-061`) and `lint` answered CLEAN. `lint`, and a form edit, now ask the IDE's form reader about every form that holds an inline frame, which no table can judge.
- `delphi_designer insert` no longer closes such a cycle (`DSGN-186`, nothing written). Through another frame it wrote the cycle and answered `ok`, with the two units using each other. A frame into itself got `DSGN-015`, "not in the table", with the recipe to write it by hand, which leads to the cycle.
- `delphi_designer insert` gives a VCL frame the next `TabOrder`, as the designer does when dropping it: with three controls it took 0, the one of another control.
- An `insert` or a `set parent=` that writes without being able to ask the IDE's writer for the order no longer says "Nothing was written" in its `orderNote` (`DSGN-145`), of what it had just written. Only `set before=`, `after=` and `index=`, which do refuse, say it.
- `FILE-053` no longer sends you to delete the live file when what you named is the link itself: it says the link is the operator's, and that nothing was deleted.
- `RENDER-007` says what to do, and names the cause it left out. Microsoft Defender checks each design package it has not seen under its current signatures, up to about 10 s each: on a 4-core VM with 41 third-party packages the first load after a signature update took 86 to 110 s and passed the renderer's 60 s, with nothing wrong in the form or its packages. The answer blamed them. Now it says to repeat the call, since what was checked stays checked.

## [1.25.0] - 2026-11-01

A minor version around the protocol, and around what agents kept tripping on.
The server speaks MCP 2026-07-28 next to the sessions it already had, on the
same endpoint. **One contract changes: `delphi_desktop` now has its own
permission, per host, and it needs a line in your `settings.ini`**
(`DesktopAllowedHosts` to see and act, `DesktopViewHosts` only to see; the
refusal says what to write). `delphi_search` shows the lines around a hit and
leaves files out, `delphi_git` takes six more operations, one `delphi_changeset
stage` takes several, a build lists its hints, a unit below its project's folder
gets its warnings and hints, and a local with a common name can be renamed. What
`delphi_build` and `delphi_test` report now comes from MSBuild's classification
and DUnitX's own summary, where a folder or a test that printed the right words
could turn one result into another. Validated before the release through Hermes
on a second machine by Qwen3.8 Flash Next (a full test of every tool and directed
tests of what changed).

### Added

- **The server speaks MCP 2026-07-28, next to the sessions it already had.** That revision
  removes the handshake and the sessions. `server/discover` now answers with the versions
  spoken, the capabilities and the instructions, where it answered `-32601` and the clients
  fell back. A request with that version in its `_meta` is served with no session: its
  headers and required fields are judged (`SYS-035` to `SYS-038`, with the codes and HTTP
  statuses the revision names), and its results carry `resultType`, `serverInfo` and, on the
  ones a client may keep, `ttlMs` and `cacheScope`. An `initialize` still opens a session
  that works as it did, on the same endpoint. Your identity there is the `clientInfo.name`
  of each request: with no name, or one that sanitizes to nothing, a request gets an identity
  of its own and never the operator's, so what it sends to the trash cannot be purged by
  the next one. This opens nothing new: a holder of the token could already `initialize`
  with any name, and the name is still a courtesy between honest agents, as the revision
  says too. Requests with no session do not count in `sessions` of `delphi_workspace`.
  Not done: closing a response stream does not cancel the work in course, as before.
- **`delphi_docs search` pages like every other list.** `offset` takes its `nextOffset`, and
  the answer says `shown`, `hasMore` and `nextOffset`; it was refused (`DOCS-017`), so past
  the first 25 results a page of the help could not be reached.
- **`delphi_search` shows what is around a hit and leaves files out.** `context` adds up to 10
  lines to each hit, as `before` and `after`, so a search no longer needs a `delphi_read` per
  hit. `exclude` takes masks like `pattern`, judged the same way, and `excluded` counts what
  it left out.
- **`delphi_git` takes six more operations, by fields as always.** `diff format=name-only`;
  `log grep` (the commit message, as text, ignoring case); `add action=update` (every tracked
  file that changed, or only `paths`); `commit action=amend` (with `message` or keeping the one
  it has); `fetch action=prune`; `clone branch`. Two refusals keep them from destroying
  anything: `GIT-086` when a remote already has the commit to amend, and `GIT-087` when a
  refspec writes outside `refs/remotes`, where prune would delete local branches (measured with
  plain git: it took the current branch too).
- **`delphi_build` takes `configuration` and `command` as other names of `config` and `target`**,
  what agents send without looking; each one cost a call.
- **`delphi_changeset stage` takes several operations in one call.** `ops` is a list of the
  fields one `stage` takes; all are staged or none, and each goes through the same checks as one
  sent alone. A batch of N files costs four calls instead of N+3.
- **`delphi_build` lists the compiler's hints in `hints`**, read by the same reader as `warnings`:
  they only came inside `outputTail`. Nothing in `quiet`, no key when there are none, no repeat
  in the tail, and at most 50 with `hintsTotal` saying how many there were.
- **`delphi_diagnostics` gives warnings and hints of a unit below its project's folder.** The
  engine only gave its errors, and `LSP-046` said so; measured, what decides it is the folder of
  the project named in its settings, and that file does not have to exist. Such a unit is linted
  with its own settings, per folder, and nothing is written in the workspace. Each folder costs
  an engine, inside `MaxEngines`. `LSP-046` is gone.
- **`delphi_rename_symbol` refuses when a unit it does not write would silently change target**
  (`RENAME-023`, `retargeted`). With a global of the interface, if another unit uses both and the
  renamed one comes later in its uses, a call that resolves elsewhere today would take the new
  symbol, and it compiles (measured with dcc: the last of the uses wins, those of `implementation`
  count after those of `interface`). A method, a routine only in `implementation`, a local
  declaration or a qualified call do not count.
- **`delphi_definition` says what is at the destination**: `name` and `text`, the line as written,
  so finding out what it found no longer takes a `delphi_read`.
- **A local with a common name can be renamed.** `delphi_references` and `delphi_rename_symbol`
  look for a local in its routine only, and say so (`localTo`): every `I` of the project used up the
  candidates, and those of other routines blocked the rename as homonyms. The candidates inside are
  still judged by the engine; a parameter is not a local, its header lives in two places.

### Changed

- **`delphi_desktop` has its own permission, per host: this needs a line in your `settings.ini`.** `DesktopAllowedHosts` sees and acts on the desktops of those hosts, `DesktopViewHosts` only sees them (`screenshot`, `status`), and `RemoteHosts` is still needed too. `McpDesktopNode` or `all` in `RemoteRunProjects` no longer grant it, and a workspace that relied on them gets `RUN-020`, which says what to write. That entry was a permission disguised as a project in a list of project paths, and it could not tell one target from another, or looking from typing.
- `delphi_edit` `adduses` and `removeuses` read their list like `add-requires` does: `;`, `,` or a blank separates names. `"A B"` was refused as one invalid unit name.
- The account warning of `delphi_workspace` asks the process token whether the server runs as LocalSystem (SID `S-1-5-18`), so it no longer depends on the name of the account or on `USERPROFILE`.
- An agent's mailbox and report folder are its name in lower case, so `a--b` and `a-b`, two agents for the trash, no longer read and delete each other's mail.
- Rules that were written in several places now live in one: the text a new file is born with, the empty unit skeleton, the IDE's `bin` folder, where a sysroot keeps its `libc.so.6` and whether it mixes two distros, which `delphi_adb` commands need a named device, how a disabled IDE package is matched, what msbuild sees of the server's environment, the lines the form renderers write to the server, how an answer writes a position, what a note leaves out after an edit, and which `delphi_git` commands only consult. No result changes.
- The standard unit aliases the engine gets come from the installation's `CodeGear.Common.Targets`, where they were a copy of that list. Answers of several lines use one line break, LF: some used CRLF.

### Fixed

- `delphi_changeset` refuses `delete` and `move` of a link when staging (CHSET-036): undoing a batch that failed turned a link into a plain file with its target's content, while the answer said every file was back byte for byte. `delphi_delete` and `delphi_move` handle the link itself.
- `delphi_test` with `nobuild` runs the binary of the configuration it was asked for. With a literal output folder per configuration, the newest binary won: Release ran the Debug binary and reported its results as Release's. The `output` of `delphi_build` reads the same output folder, the one of that build.
- `delphi_edit` `insert=rutina-global` in a `.dpr` whose `uses` is split in `{$IFDEF}` branches places the routine after the whole clause. It landed inside the first branch, so with the other branch active the routine did not exist.
- An Android project with no version keys gets the `minSdkVersion` and `targetSdkVersion` of the installed IDE, read from its Android package (36 on 37.0), where the server wrote a fixed 35.
- `delphi_build` takes `errors`, `warnings` and `hints` from MSBuild's own classification, in log files of the server. They were found by searching its console text: with `verbosity=normal`, a warning whose text said `: error` came back in `errors` next to `success: true`, and with `verbose` a folder named `My error Example` sent there every line that named it, and each warning came back twice.
- `delphi_designer set`, `delphi_edit` and `lint` say when a string value names a path that `preview` refuses (DSGN-183): `set` wrote it, `lint` answered CLEAN, and only `preview` refused the form, and any other form of its folder, afterwards (DSGN-115). The form stays valid and the value is written: it is a note, by the same judge as `preview`. After an edit it names only what that edit brought.
- `delphi_test` reads the DUnitX summary as its own block of whole lines, the last one in the output, and its failures only after it. A test that printed `Tests Failed : 7` turned a green suite red, one that printed `Tests Failed : 0` hid the count of a red one, a line `Failing Tests` from a test filled `failures` of a green suite, and a failure message with `Tests Failed : 0` in it could make a red suite with exit code 0 come back green.
- `delphi_build` retries a locked binary and reports it only when the compiler said F2039. A project in a folder named `F2039Demo` with any other error built five times, about 17 s, and came back with a note about a locked binary. The same goes for what it reads of the linker's `cannot find -l` and of `W1033`, which now come from MSBuild's error and warning logs.
- `delphi_rename_symbol` gives `character0` on the row of the definition too, like every other row of `changes`.
- A form renderer from another version says so (DSGN-184) instead of being misread. The renderers now state their protocol first thing and the server compares it: with a stale renderer, `preview` blamed a design package (DSGN-061), and what it skipped could turn into "not confirmed" with no notice.
- `delphi_designer prop` says that an integer property with no named constants the form reader understands takes a whole number. On `ModalResult` it said nothing, and the way to find out was to try `mrOk`, which is refused.
- The description of `delphi_delete` says what a reference project is (`ReadOnlyRoots`): an agent read it as any project with its repository, tried a delete expecting the refusal, and it went to the trash, as a folder of your roots does.
- `scripts\Enviar-Mensaje.ps1` leaves the message where the server reads it, in the workspace's folder (`-Workspace`), and refuses a folder that does not exist. Since each workspace got its own mailbox (1.18.0) it wrote to a folder nobody read, and `docs/TOOLS.md` said the same.
- An engine stopped under another agent's request ends clean: `shutdown` is now the last thing it receives. A request that had already passed the check of "is it stopped?" could be written after it, and then the engine, having answered everything, died with `0xC0000005` when its input was closed. Nobody lost an answer, but the log said so and the suite went red about one run in forty.
- **`delphi_desktop` against a PAServer that does not answer costs one wait, and only that
  profile's.** `paclient` gives up by itself (21 s against an address that does not answer,
  and its `--timeout` does not shorten that), so no `timeoutms` was added: what went away is
  ours. The first gesture on a profile tried to upload the node after being told there was no
  connection, paying the wait twice; while it waited it held a lock shared by every profile, so
  a gesture on a live target waited behind a dead one; and each attempt left a folder in the
  server's temporary area. `status` still answers `reachable: false` with the reason; a gesture
  now says `FETCH-004` instead of `RUN-010`, with what `paclient` said.
- **A routine whose header spans several lines is found again.** For a call to it the engine
  answers a line inside the header, which does not name the routine: `delphi_definition` pointed
  there, `delphi_references` took the call for a homonym and `delphi_rename_symbol` was blocked
  (`RENAME-017`). Now the answer is the header itself.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
- [1.24](docs/changelog/1.24.md)
- [1.23](docs/changelog/1.23.md)
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
