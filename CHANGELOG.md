# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

## [1.24.0] - 2026-10-31

A minor version around the form designer, and the renderer inside its own
container. `delphi_create` makes inherited forms and frames, `delphi_designer
insert` takes a frame of the project, and `layout` measures FMX forms and gives
a VCL form the rectangles the VCL really resolved, an inline frame and what it
holds included. The form renderer now always runs inside an AppContainer with
no capabilities and no network: the design code of the installed packages no
longer runs with the service's account, and no answer says whether a file
exists on the server. A form whose ancestor or frame lives in another folder
of the project is drawn and judged whole, a copy beside a form no longer takes
its place, and a package disabled in the IDE is no longer loaded. `delphi_adb
stop` stops an app, and a device adb lists with a number can be named.
Validated before the release through Hermes on a second machine by Qwen3.8
Flash Next (a full test of every tool, directed tests of what changed and three
rounds over what those found).

### Added

- **`delphi_create` makes inherited forms and frames.** `ancestor` takes the class of a
  form or frame of the project: the new form says `inherited`, its class descends from
  that one and its `uses` gets that unit. An ancestor the project does not list answers
  `CREATE-038`, and a frame as the ancestor of a form or the reverse, `CREATE-039`.
- **`delphi_designer insert` takes a frame of the project.** It was refused because the
  class table only knows the library (`DSGN-015`), and by hand it took three more calls.
  Now it writes the `inline` block as the IDE does, with its field and its unit in the
  `uses`.

- **`delphi_adb stop` stops an app.** Only `key=back` existed, which does not close a hung
  app. It force-stops what `run` can start, a Delphi FMX app, by the activity the device
  says it launches; any other package is refused (`ADB-033`) and left running.
- **`delphi_designer layout` measures FMX forms.** It refused them (`DSGN-027`). Now the
  renderer lays the form out and says where each control ends up, those inside a `TTabControl`,
  a `TVertScrollBox` or a `TExpander` too: `boxes`, what has a zero side and what sticks out of
  where it lives. What overlaps is listed and does not take `clean`
  away, because in FMX one control over another is how a form is composed. Without the
  renderer it still refuses, never `clean: true`.

### Changed

- **`delphi_designer layout` of a VCL form gives the real rectangles.** `boxes` come from
  what the VCL resolved (`boxesFrom: renderer`), so a page of a `TPageControl` leaves out the
  tab band; without the renderer, or if it takes over 30 s, they come from the text and
  `boxesNote` says why (`boxesFrom: text`). What it reports as a problem is still judged from
  the text. It now takes what a `preview` takes.
- **A form whose ancestor or frame lives in another folder of the project is drawn and
  judged whole.** It came out partial (`RENDER-010`), the frame substituted, and the
  order judge refused it (`DSGN-143`). When the renderer says a class is missing and the
  project that lists the form's unit has it, the server brings that form along, judged
  like a sibling, literals included. With no project listing the unit, the form stays
  partial and says so; if what it brings makes the renderer fail, the partial form is the
  answer and `DSGN-181` names it. A lone copy beside the form that its `uses` does not name
  is not taken for the original. Each folder crossed costs one more run of the renderer.

### Fixed

- **`delphi_adb` can name a device adb lists with a number.** Over wireless debugging adb can
  list `adb-X (2)._adb-tls-connect._tcp`, and it accepts only that whole name. The gate refused
  the space and the parentheses (`ADB-018`), so that device could not be named at all, though
  `ADB-018` itself says to use what `devices` lists. It now goes as listed, and
  `AdbAllowedDevices` recognizes it by the name without the number.
- **Several answers said what they did not mean.** `delphi_move` of a file to a folder
  that exists answered `LSP-016`, which sends you to `delphi_list`; now `MOVE-026` gives
  the final path to use. `MOVE-025` says parent folders are created, and `EDIT-019` says
  plainly what to give back. `delphi_designer lint` of a frame or a form with a StyleBook
  it cannot read now says its `StyleLookup` values were not judged (`DSGN-178`), and
  `delphi_styles lint` that it looked at no form (`STYLE-064`), where `lookupsUsed: 0` read
  as good news. `delphi_styles set` of a color without its `x` names the format (`STYLE-063`),
  `VAULT-041` says prompts come from the workspace's vault, `delphi_installs` says
  `requestedUpdate` appears only if declared, and the long audit line names what
  `corruption` counts. In `edits` on a form, each entry's report names the object it landed
  in: a repeated block could land in another component with only a line number to tell. The
  same report now says when it cut a long line (`...`). `delphi_signature` with nothing to
  answer gives its own causes (`LSP-052`): the shared note asked for a position inside an
  identifier, the opposite of what it needs. The TCP probe of `delphi_paserver` says the host
  passed because `RemoteHosts` allows it.
- **`delphi_designer layout` of a VCL form lists an inline frame and what is inside it.**
  With the renderer (`boxesFrom: renderer`) the boxes were the text's list with the real
  rectangles put in, and the text of a form never lists what a frame holds: a form made of
  frames answered `boxes: []` and `clean: true`. Found by the directed test of this version
  on the 13.2 machine. Now what the renderer measures and the text does not list is added,
  with the line of its block (0 inside a frame); it is listed, not judged, and
  `howMeasured` says so.
- **`delphi_designer insert` of a frame of the project no longer says the renderer could not
  load it.** The IDE's writer was asked with the form proposed but the unit as it is on
  disk, whose `uses` does not name the frame's unit yet - and since this version a lone
  copy the `uses` does not name is not taken (`RENDER-025`): every frame went in as the
  last child with `DSGN-145` and a `DSGN-140` that blamed a missing package or folder.
  Found by the directed test of this version. The judge now sees the unit as the insert
  will leave it, and what it reads of that proposal does not count as a reading of the
  disk.
- **`LSP-002` and `LSP-025` name the case that never warms up.** They said the engine was
  warming up the unit and to repeat in a few seconds; a method whose body is only `;` is
  one DelphiLSP never indexes as a definition (measured on 13.1 and 13.2: hover answers,
  definition does not, and the same call failed for two minutes in the complete review of
  this version), and a rename from its declaration lists its header as unverified
  (`RENAME-018`) for the same reason. The messages now say so and what to do.
- **`DSGN-115` says why a literal under Windows or Program Files is refused.** It said "a
  path outside the allowed read locations" of a folder the session could read: since this
  version the renderer's container reads those folders on its own, so such a literal is
  refused by its text, exists or not, and the message now says so, and where to keep the
  files (the form's folder or below it).
- **The renderer's packages box is moved into place with the retries a file write has, and
  `DSGN-177` names the step of the box that failed.** The server fills the box beside its
  final name and renames the folder into place; a reader of an instant holding any of the
  hundred copies it has just made (a scanner opens files as they are born) makes that rename
  fail with access denied - measured: a folder with a file open inside is refused even when
  the reader shares reading, writing and deletion - and the first preview of that server
  answered `DSGN-177` with a bare `System Error. Code: 5`. Seen once in the suite, with the
  IDE starting on the same machine; the log of that run was not kept, so the step is not
  known. The rename now retries for half a second as `AtomicWrite` does (one helper for both),
  and the refusal says which step of the box failed: its folder, the containers' access, the
  copies, the COM classes or the move.
- **The form renderer now always runs inside its own container, and its answer no
  longer says whether a file exists.** `delphi_designer` preview, lint and the check
  of what the IDE would save run the design code of the installed packages. That code
  reads and writes whatever a form asks it to, and it ran with the service's account.
  Before drawing, the server looked up each file a form names and refused the ones
  outside the session's reach, so the refusal told an agent which files exist on the
  server. Now each call gets an AppContainer with no capabilities and its Job Object,
  and if that cannot be prepared nothing is drawn (`DSGN-177`). From there, nothing of
  the roots, the server's folder, the user's profile or a mapped drive can be opened,
  and there is no network. Windows and the Program Files folders stay readable to any
  container, so a form literal naming something there is refused by its text
  (`DSGN-115`), exists or not. What the renderer needs travels to it: the form, its
  sibling forms and units and what its literals name below its folder are copied to a
  folder of the call, and the packages to a read-only box shared by all calls. The
  renderers no longer read the registry: the server tells them where the IDE is and
  which packages they may load. The ADO classes, which Windows keeps under a registry
  key no container may read, are declared in the manifest of the box's copy of the
  renderers, so a form with a `TADOQuery` still loads whole and can still be judged.
  Measured over 876 forms, the 292 that could differ repeated with the ADO classes in
  place: components and reader messages match the previous version; time on forms with ADO is 3 % more, and
  the first call after a change of packages takes about a second more to make the box.
  What changes on purpose, because it is what the container is for:
  - A form no longer shows live data from outside: a `TFileListBox` lists the call's
    folder, a dataset that opens its database at design time comes out empty, and a
    component that needs a blocked dialog says so (`RENDER-022`).
  - A form literal under Windows or Program Files stops the drawing even if that file
    does not exist on this machine: an image path of an older RAD Studio does it, as
    in two forms of the RAD Studio samples.
  - A component that opens a file by its full path fails as with a missing file, even
    inside the roots.
  - The language of the RTL's messages is Windows's: the per-program override in the
    IDE's registry does not reach the container.
  - If asking for those COM classes fails when the box is made, that box goes without
    them until the next one: the server logs it, and the components that need them
    come out in `ignored`.
  Not yet measured on an installation with other third-party packages.
- **A copy of a form next to the original no longer takes its place.** To draw or
  judge a form, the renderers look for its ancestors and frames by root class among
  the forms of the folder, and took the first one listed. With `UBase - copia.dfm`
  next to `UBase.dfm` (what copying a form in Explorer leaves), `delphi_designer`
  drew the copy while the program links `UBase`. Now the `uses` of the `.pas` that
  names the class decides, by file name; when it does not, `RENDER-025` says which
  one was read.
- **A reparse point is a link only when its tag says so.** Any reparse point counted
  as a link, so a OneDrive placeholder or a deduplicated file was skipped when
  listing, walking or purging a folder, and a form's sibling held that way was not
  read. Now only a tag with the name-surrogate bit (junction, symlink) is a link, and
  one whose tag cannot be read still counts as one. Measured here with the app aliases
  of `WindowsApps`; there is no OneDrive on the test machine, so a real placeholder
  has not been tried.
- **The device names Windows documents are all refused in a path.** `GUARD-027`
  missed `COM0`, `LPT0`, `COM` and `LPT` with a superscript 1-3, `CONIN$` and
  `CONOUT$`: a file with one of those names could be created here and then not open
  on another Windows. Like `COM1` before them, an existing file with one of those names
  cannot be read, renamed or deleted through the tools either: that goes by hand.
- **The places a server protects no longer depend on its environment.** The Windows folder,
  `Program Files` and the user's profile were read from `WINDIR`, `ProgramFiles` and
  `USERPROFILE`: launched by a client that does not pass them, the protection was simply not
  there, and with no `LOCALAPPDATA` the server's cache fell in the launcher's folder. Windows
  answers now; `LOCALAPPDATA` and `APPDATA` still win when they hold an absolute path.
- **Two agents named `a.b` and `a-b` no longer share a mailbox.** A name with a `.` or a `_`
  now has its own folder for messages, reports and captures; what such an agent had pending
  stays in the old folder.
- **A package disabled in the IDE is no longer loaded to draw or judge a form.**
  `delphi_designer` preview, lint and the check of what the IDE would save loaded
  every package in the IDE's Known Packages, without looking at Disabled Packages:
  a class of a disabled package was drawn as if it were available, and a package
  disabled because it misbehaves still ran. Now the server gives the renderers only
  the enabled ones, so such a class comes out substituted and `packages` counts only
  those (`DSGN-068` says it may be disabled). `$(BDSCOMMONDIR)` comes from the
  server's reader of `rsvars.bat` instead of being composed by hand.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
