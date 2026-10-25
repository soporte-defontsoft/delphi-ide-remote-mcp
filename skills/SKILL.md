---
name: delphi-mcp
description: Work a remote RAD Studio (Delphi IDE) machine through the Delphi IDE Remote MCP Server (delphi_* / vault_* tools). Load when connected to an MCP server exposing delphi_workspace, delphi_build, delphi_edit and friends - it teaches the path model, the safe-editing contract, the build/deploy chains (Windows, Linux via PAServer, Android via adb, the desktop of any PAServer target - Linux or Windows, this server included - via delphi_desktop) and how to move files and logs the right way.
---

# Delphi IDE Remote MCP - field guide for agents

You are talking to a Windows machine that has RAD Studio installed. The
projects, the compiler, the devices and the files all live THERE. You
build, edit, deploy and drive apps through tools; you never need Delphi
on your side.

## First contact (always, in this order)

**Before the first call: identify yourself.** Your `clientInfo.name` in the
MCP handshake is your identity here: the mailbox, the trash purge and the
sessions list use it. Set it to your agent id (e.g. `hermes`). If your client
cannot set it (it says `mcp` or a generic name), pass `agent=<your id>` in
`delphi_report` and `delphi_messages` on EVERY call: `agent=` wins over the
handshake.

1. `delphi_workspace` - your allowed roots, your access level, WHICH
   Delphi you are working with (`activeDelphiName` "RAD Studio 13",
   `activeDelphiPersonality` "Delphi 13", edition and build - use those
   words when you search the web for anything version-specific) and the
   path model. **Server paths use virtual drive units**: `srvd:\...`,
   `srvc:\...`. They only exist inside this MCP. Always send paths in
   that form; never invent local-looking paths of your own.
   One server is ONE Delphi: another version is another MCP server the
   operator gives you, never a parameter. The name of an MCP entry is only
   the operator's label - the same version may run on several machines.
   What a server IS: `activeDelphiName`, `activeDelphiBuild`,
   `delphiUpdate` (13.1 and 13.2 are both "RAD Studio 13": the operator
   declares which, when it matters) and `server.host`, the machine.
2. `delphi_components` - what the server's RAD Studio has installed to
   program with (design packages, any install channel). Check BEFORE
   writing uses clauses for third-party libraries. Base RTL/VCL/FMX are
   always available and not listed. `filter=` narrows (e.g. `filter=FMX`).
3. If a vault is announced in the instructions, `vault_read` its index -
   it holds the operator's conventions and project context.

## Reading files and logs

- `delphi_read` pages at 400 lines per call - read in RANGES.
- `delphi_search` / `delphi_list` to locate; never read whole trees.
- A `READ-007`, `READ-008` or `READ-009` note on a read (bytes that do not
  fit the file's encoding; a UTF-8 source - or a text form - without a BOM,
  which the compiler and the IDE read as ANSI: the note shows both readings)
  says what to do: follow it, and never write U+FFFD back. Converting a
  file's encoding is the operator's decision, never a side effect of an edit.
- A folder name the engine cannot carry in a URI - a character beyond
  U+FFFF (an emoji) or half a character, anywhere in a project's tree -
  makes DelphiLSP lose folders or lint nothing: the answer says so
  (`LSP-043`, `LSP-044`, `LSP-045`) and the fix is the folder's name
  (`delphi_move`), not another call.
- **An API you do not know** (what a class or routine is for, how it is
  used): `delphi_docs search query=<it>` and then `read id=<a result>` -
  the RAD Studio help installed on the server, in small pieces. Do not
  guess and do not read a whole RTL unit for it; for the exact signature,
  the installed sources win: `delphi_hover` / `delphi_definition`.
- Big dumps (logcat, long outputs) have a file mode (`out=`): use it,
  then read the file in ranges or download it.
- **Getting a file onto YOUR machine** (an installer, an .apk, a
  screenshot PNG, a long unit to grep locally): call `delphi_fetch` once
  and use the `download` field it returns - a `GET /files?path=...` on
  the same host:port as `/mcp`, with the same `Authorization: Bearer`
  header:
  `curl -H "Authorization: Bearer $TOKEN" -o file "http://host:port/files?path=..."`.
  Verify with `sha256sum` against the `X-File-SHA256` header. This is the
  standard way for any size; files over 1 MB answer with the link only.
  Inline base64 chunks (`maxbytes<=1048576`, loop `offset` until `eof`)
  are for clients without a shell.

## Editing safely (`delphi_edit`)

- Anchor edits: `old` must be copied EXACTLY from a fresh `delphi_read`,
  as small and unique as possible. An edit error is a diagnosis - re-read
  and fix the anchor; do not retry blindly. Indentation does not count in
  an anchor (the rest of the line does, to its end). `old` may be one line
  or several consecutive ones, in a single edit as in an `edits` entry.
- **Fragment mode, for a long line**: `fragment` + `atline` + `new`
  changes just that piece of ONE line - no need to paste a 600-character
  README paragraph to turn "68" into "69". The same in `delphi_edit`,
  `delphi_textedit`, batches (`edits`) and `delphi_changeset` stage.
- Pascal traps: a method signature exists TWICE (interface +
  implementation); there are TWO uses clauses; one single `end.` at the
  file end. Half an edit is not an edit.
- A NEW routine or method goes in with `insert` (`rutina-global`, or
  `metodo` + `inclass`): ONE routine per call - a `code` with two is
  refused (`EDIT-129`) naming them, and nothing is written.
- `.fmx`/`.dfm` are DATA, not code. The compiler only checks their text
  grammar - a wrong property name or enum value compiles fine and then
  **crashes the form at load time on the target, silently**. The server
  lints designer edits against tables generated from the framework's own
  metadata: a `DESIGNER WARNING` in the edit result is measured
  truth - fix it before building. FMX property spelling is not VCL:
  `Size.Width` (not `Size.X`), `TextSettings.Font.Size` (not
  `Font.Size`), `TextSettings.HorzAlign = Center` (not `taCenter`).
- A binary `.dfm` (TPF0 stream or `$FF` resource wrapper, the legacy shape)
  is READ on the fly everywhere - `delphi_read`, `delphi_search`,
  `delphi_designer tree/get/lint/check-binding/layout/preview` - and the answer says
  so. To EDIT it: `delphi_designer command=to-text` (the IDE's own
  conversion, backup first), edit as text, then `lint` and `check-binding`
  (what the IDE reports when it reopens the form); `to-binary` is the way
  back. Editing the binary directly is refused. `.fmx` is always text.
  Accents in a text `.dfm` go as `#NNN` outside the quotes
  (`'Configuraci'#243'n'`), the way the IDE and `to-text` write them; a raw
  one is read the way the IDE's parser reads the file: through the machine's
  ANSI code page when it has no BOM (there, a character ANSI cannot hold is
  refused when written), as Unicode when it has one - `to-binary` included.
- Prefer `Align`/anchors over absolute Position/Size in forms: absolute
  coordinates designed on a desktop form overflow phone screens.

## Tests: does it WORK, not just compile

- `delphi_test command=discover path=<folder>` finds the test projects;
  `command=run project=<the test .dproj>` builds and runs one and answers
  `total`/`passed`/`failed` with the failing lines. That is your red-green
  loop: edit -> diagnostics -> build -> **test** -> commit. `filter` takes
  what DUnitX matches - a fixture by its full name or the start of it
  (`Unit.TFixture`), a test by its full name (`Unit.TFixture.Method`) - and
  no wildcards; one that ran nothing says so (`filterNote`).
- `delphi_diagnostics` is the quick check and `delphi_build` the real one.
  The answer names the project it linted with (`project`); of a unit in a
  folder BELOW that project's folder the engine gives the errors only,
  never warnings or hints (`LSP-046` says so) - the build gives them.
- It needs `AllowTests=1` declared in YOUR workspace on the server. Without
  it `discover` works and `run` says so - that is a switch, not a bug.
- The test runs in a Windows container on a COPY of its output folder: it
  sees that folder and, besides it, only what Windows gives every container
  (its own temp, the system files), and has no network. Write tests of
  LOGIC; a data file a test reads goes in the output folder, a project
  built with runtime packages is refused (build it whole), and what the test
  writes there comes back in `files`. A test that needs a database or the
  network belongs on a
  target machine (`delphi_paserver remote-run`).

## Renaming a symbol

- `delphi_rename_symbol path=<unit> line=<0-based> character=<0-based>
  newname=<NewName>` (a hit's `line0` and `character0`: its `line` is the
  1-based one `delphi_read` shows) previews a semantic rename: every occurrence
  re-confirmed, and `applicable` tells you if it is safe. NEVER rename by
  search-and-replace: the preview exists precisely because designers,
  string literals (FindComponent/RTTI/StyleLookup) and homonyms break
  silently: a name inside a string, in ANY unit of the scope, leaves it
  not applicable (`RENAME-020`). A namesake in another unit (a second
  `TFoo`) or an overload is
  never taken for yours: `via: "override"` in `delphi_references` is the
  inheritance family as the engine resolves it, and a namesake leaves the
  rename not applicable (`RENAME-017`) instead of being renamed with it.
  `delphi_references` lists the lines of the form files that name it as
  well (`designer`) - the ones a rename blocks on (`RENAME-019`); a
  component of the form is renamed with `delphi_designer command=set
  prop=Name`.
- If `applicable=true`, repeat the same call with `mode=apply`: the tool
  writes it through the changeset engine (all files or none, a backup of
  each) and answers with the commit. Then `delphi_build`. If false, the
  blockers say exactly why - fix them or leave the name alone; apply
  writes nothing in that case.

## Forms (.dfm/.fmx)

- Never guess what a class publishes: `delphi_designer info classname=TButton`
  (add `framework=fmx` for FMX) lists the REAL published properties and
  events; `prop classname=TPanel prop=Align` gives the legal enum members,
  and takes a dotted path as `set` does (`TextSettings.HorzAlign`). A
  property of kind class whose type is not a component is an object: `info
  classname=<its type>` lists its own, and `filter=` on `info` looks one
  level inside them.
  `tree path=<form>` shows the component tree; `get component=<Name>` one
  block.
- Edit a form with the designer commands, not by hand: `insert` adds a
  visual control (its block, its published field and its unit in the uses,
  where the IDE keeps it), `set` changes a property (several with `props`,
  all or none) after checking it against the class (on the form itself, a
  property your own base class publishes is judged by the type it
  declares), `delete` removes one
  with its empty handlers. The properties go in as the IDE's own writer
  stores them - its order, the size a control's constructor gives, the
  companions it adds (`Size.PlatformDefault`, `ParentFont`) - and the answer
  says when that is not the value you gave: `notStored` (the class already
  gives it), `storedAs` (the component turns it into another when it loads)
  or `storedIn` (its class keeps it in other properties: in FMX, `Width` and
  `Height` go in `Size`). Each writes the form and its unit together, all
  or nothing, and a refusal says exactly what to do instead - including how
  to add by hand what insert cannot place (a non-visual component such as
  a TTimer: its block, its published field, its unit in the uses, then
  `check-binding`).
- After a form edit made with `delphi_edit`, run `delphi_designer lint
  path=<form>`: a property the class does not publish, or a value its type
  does not take, will not stream, and nobody tells you at build time.
- SEE the form instead of imagining it: `delphi_designer command=preview
  path=<form>` returns a PNG of what the IDE designer shows. The loop is
  insert/set -> `lint` -> `preview` -> fix. To place something, measure on
  the image and convert with its `frame` (image pixels to form units;
  `Left`/`Top` - `Position.X`/`Position.Y` in FMX - are relative to the
  parent, whose rectangle `component=<parent>` gives as `componentRect`).
  `ignored` in the answer lists each property the form loader could not
  read: the rest is drawn, but the form will not open until you fix them -
  except those your own classes publish, which the renderer cannot load and
  the real form reads (`ignoredUserNote` names them).

## FMX styles

- A project's look lives in text `.style` files (one master per theme, or a
  master plus a tokens `.ini`). Treat them BY NAME with `delphi_styles`,
  never by line: `view` lists the StyleNames a `StyleLookup` can use, `get`
  shows one, `set style=cardstyle child=background prop=Fill.Color
  value=xFF112233` changes one property (value exactly as the file writes
  it), `clone style=cardstyle name=cardstyle_alt` adds a variant and
  `delete style=cardstyle_alt` removes one. `set` refuses a change FMX
  would ignore when it loads the style (`STYLE-050`: a property the class
  does not publish, a value it cannot read - `delphi_designer command=prop`
  says what the class publishes) or with which it could not load the style
  at all (`STYLE-053`: a color goes as `xAARRGGBB`, never `$AARRGGBB`), and
  `lint`/`build` list what FMX ignores in a file already written
  (`ignoredByFmx`) and what it cannot load (`fmxCannotLoad`). The way back is the
  `__delphi-patch\<day>\` copy, which is the file BEFORE ITS FIRST CHANGE
  TODAY: putting it back (`delphi_delete` the file, then `delphi_move` the
  copy to its name - `delphi_move` never overwrites) undoes the day's other
  changes too; to undo only one, read its lines in that copy and put them
  back with `delphi_textedit`.
- Before and after touching a `.fmx`: `delphi_styles command=lint
  path=<Styles folder> project=<.dproj>` - a `StyleLookup` that no style
  defines renders with the default look and nobody tells you.
- After editing styles: `command=build path=<Styles folder>` (text ->
  `.bin.style` -> `.res`), then `delphi_build target=Build`: the app embeds
  the binary form; the text form loads but does not resolve `StyleLookup`.
- `delphi_search pattern=*.style` (or `*.ini`, `*.md`) searches files
  outside the Delphi set.

## Mail from the operator

- Any tool answer may end with `PENDING MESSAGES: N`. When it does, call
  `delphi_messages command=read` before going on (with `agent=<your id>`
  if your client cannot set its name - see First contact): the operator
  answered a report of yours or changed the plan. Messages are delivered
  once; act on them and, when an answer is due, reply with
  `delphi_report`.

## Running on the target (not on this server)

- `delphi_build target=Deploy` ships the binary to the host of its PAServer
  profile (the call's `profile`, else the project's `set-profile`), which
  has to be in `RemoteHosts`; to RUN it there use
  `delphi_paserver command=remote-run profile=<profile> project=<the .dproj>
  args=... timeoutms=...`. It returns `exitCode` and the program's output.
  You never give a remote path: the server runs what THAT project deployed
  and nothing else on that machine (a script in the same folder is refused
  too - only native binaries).
- Nothing has to be installed on the target: PAServer itself runs
  what this server sends. If the program has not finished when the timeout
  expires it is NOT killed - you get `stillRunning: true` and its partial
  output; a GUI app stays up, ready to be driven with delphi_desktop. If a
  job is stuck or no longer wanted, the same answer's `killNote` gives the
  call: `delphi_paserver command=kill profile= project= job=<jobId>` - it
  stops only that job, on that machine.
- Only the NATIVE binary that project deployed can run (the native
  launcher, McpRunJob, verifies the file signature). Remember
  `target=Deploy` REWRITES that folder: copy state you need before
  redeploying.

## The desktop of a target (`delphi_desktop`) - eyes and hands

The same idea as adb, for the machine behind a PAServer profile: a Linux
(**GNOME only today**, Zorin and Fedora measured), a Windows with PAServer,
or this very server when a PAServer runs in its user session. ALWAYS
through a PAServer listening on that machine, Windows included: without one
there is no desktop to reach, whatever the network says. The machine is the
`profile` parameter; leave `project` empty - the node bundled with the
server deploys and updates itself on the target, nothing is compiled or
installed by hand.

**One step, no arithmetic:** `screenshot` comes back IN the answer as an
image with a `frame` token. Measure x,y ON THAT IMAGE and call `tap` (or
`type`, which presses there first: one trip) with those x,y and
`frame=<the token, copied as it is>`: the server converts scale and crop
origin for you - never divide by a scale or add an origin yourself. Every
capture lists `windows` (title + rectangle); `overview` brings a covered
one into view (Linux: the Super overview); `screenshot region="x,y,w,h"`
or `window="<title>"` brings a piece at full resolution to read a small
dialog - go back to the whole desktop whenever something may have opened
elsewhere. `key` takes an evdev code on Linux and a key NAME on Windows
(the tool reads the profile's platform); `modifiers=ctrl` holds keys while
it goes down. `type` on Linux uses the desktop's own keymap, accents
included; the text is typed, never run.

It runs under the SAME workspace switches as remote-run (`AllowRemoteRun`,
`McpDesktopNode` or `all` in `RemoteRunProjects`, the profile's host in
`RemoteHosts`; the server's own desktop is the profile whose host is
127.0.0.1). The target needs a graphical session open for the user PAServer
runs as: on Linux PAServer may run as a service (the server completes
DISPLAY from the session); on Windows PAServer must run INSIDE the user's
session - a service lives in session 0, which has no desktop - and the
session must be unlocked. On Linux the node names a locked session, or a
desktop with no monitor (a remote desktop that disconnected), instead of
failing in the portal; `command=status` says what to ask the operator for.
On GNOME the screen-capture permission must have been granted once: a
mute screenshot timeout means exactly that.

Coordinates are REAL pixels on both systems and the Windows node is
DPI-aware: never mix in coordinates from a tool that is not (on a 125%
display the same window sits 250 px away). **When the profile is someone's
own machine, its screen and mouse are theirs**: whatever they have open is
in frame. Do the gesture you came for and nothing else.

## Projects and builds

- `delphi_create` scaffolds console/VCL/FMX projects, runtime packages
  and DUnitX test projects (`project-test`: runner + first fixture, green
  at birth; `delphi_test` runs it), and inside a
  project: `form-vcl`/`form-fmx`, `frame-vcl`/`frame-fmx`, `datamodule`
  and `unit` (a plain .pas; with no project and an absolute `dir`,
  standalone), plus `include` (a .inc for `{$I}`, never registered).
  Everything compiles at birth and is already
  registered in the `.dpr` and the `.dproj`. Then `delphi_config
  command=add-platform` for extra targets. A new project carries the
  version information the IDE writes: `delphi_config command=set-version
  version=1.2.3` keeps the numbers and the keys together, and
  `include=true` makes the binaries carry it (a console is born, as in the
  IDE, without it - the answer says so).
- **The folder layout is yours**: inside a project, `dir=` is a SUBFOLDER
  of the project (relative, as deep as you like - no drive, no `..`); the
  unit is born there and registered with its relative path.
- **Project membership is the server's job, never a hand edit of the
  `.dpr`/`.dproj`**: an existing `.pas` joins with `delphi_config
  command=add-unit path=<.pas>` (forms get their `CreateForm`, frames do
  not), `remove-unit` drops it from the project and keeps the file (even an entry whose file is gone or lies outside what you can read: the way out of a `BUILD-050` on a `<DCCReference>`),
  `delphi_move`, `delphi_delete` and a `delphi_changeset` move, copy and
  delete files as an operator does: what you name goes (`Form1.*` takes a
  unit and its form), and NO project, header or path is rewritten - the
  answer names each file that still points across (`MOVE-023`, `FILE-046`)
  and a pair split in two (`FILE-051`). Then re-point it yourself:
  `add-unit` / `remove-unit`, or `fix-references` for a whole project.
  `view` lists the project's `units`.
- `delphi_build` runs MSBuild. The result declares the real `output`
  path - trust it, do not guess. `target=Deploy` on Android builds the
  full `.apk` (the server generates the deployment manifest if missing).
  It is compile-only and its gate is a whitelist: an element a build does
  not understand, a task, free compiler options or a foreign `<Import>`
  is refused by name (`BUILD-017`), and what the build reads through the
  project - the icon, the manifest, the search paths, a `.rc` - has to
  lie inside what you can read (`BUILD-050`); the refusal names the
  element and the value, so fix the `.dproj`, do not retry. An output
  folder the project does not declare (the `.dcu`, `.bpl` or `.dcp` one)
  is supplied inside the project for that build (`outputSupplied` says
  where; `BUILD-054`), never written to the `.dproj`: a project that
  compiles in the IDE with its `.dcu` next to the sources compiles here
  the same, with them in its binary output folder.
- **A build is what the IDE would build**: only a platform the project
  declares and has enabled (another is refused with `BUILD-046`:
  `delphi_config command=add-platform` declares it, as the IDE does; a `.dproj` whose `<Project>` never closes - an upload cut short - is `BUILD-055`, which says how to put it back, not `BUILD-046`), and
  without `platform` or `config` the ones the project has selected
  (`delphi_config view`: `defaultPlatform`, `defaultConfig`; `set-active`
  changes them, as *Activate* in the IDE). What you build, the
  operator builds the same in the IDE without reconfiguring anything.
- **"Unit 'X' not found" on a platform you just added** (and only
  there): the unit belongs to an installed component whose folder is in
  the IDE's library path for the other platforms only. The failed build
  already says where: `missingUnits[].sourceFolders` - run the
  `delphi_config command=add-searchpath platform=<the one> path=<folder>` (several folders at once: `paths=[...]`, all or nothing, one write)
  it names and build again (one round per library, not two). Before the
  first build on a new platform, `delphi_components platform=<the one>`
  lists the components registered elsewhere and not there. An empty
  `sourceFolders` means no source for that platform: `delphi_report`.
  A unit that only exists under a scope (`Dialogs`: `FMX.Dialogs`,
  `Vcl.Dialogs`) comes back in `qualified`: write it qualified in the
  uses (`BUILD-049`) - there is no folder to add.
- **A project option no other command covers** (an Android keystore, a
  define, a version key, a search path of one configuration):
  `delphi_config command=set-property name=<property> value=<text>
  platform=<the one> config=<the one>` writes it in the group the IDE
  would use for that build (neither: the base group, inherited by every
  build); `get-property` says what that build reads and every group that
  sets it; `remove-property` drops it. The value is judged when that
  build reads it, like the rest of the `.dproj`: a keystore outside your
  roots refuses the Android build with `BUILD-050` - re-point it to one
  inside or remove it. The structure of the `.dproj` (`Config`,
  `Platform`, `Base`, `Cfg_N`), the build events and the free compiler
  options are refused (`CFG-132`, `CFG-133`).
- **A component that loads a native library at runtime** (a `.so` on
  Linux, `.dylib` on macOS, `.dll` on Windows - OBR's `libzbar`, for
  instance) needs that file shipped with the binary:
  `delphi_config command=add-deployfile platform=<one> path=<the .so>`
  (found under the component's `Library\<platform>\` folder), then
  `delphi_build target=Deploy`. The file lands next to the binary on the
  target; `view` lists the deployment entries. If you run the binary by
  hand instead, put the library next to it (`LD_LIBRARY_PATH=.`).

## Linux (PAServer)

`delphi_paserver` end to end: `packages` (the PAServer installer ships
with the IDE - `delphi_fetch` its path and `curl` the `download` link, it
is ~70 MB) -> install and start it on the target, from a terminal INSIDE
its graphical session (a GUI launched later through an out-of-session
PAServer aborts with no DISPLAY - measured) -> `add-profile` (an existing
name is refused, never overwritten. It also writes the seat the IDE
reads for its own list - the IDE picks it up at its NEXT start, so do
not expect it to appear in a running IDE. If a profile is on disk but
missing from the IDE, `command=reseat` writes the missing seats
from the files themselves, no PAServer and no passwords needed)
-> `test-connection` -> `get-sdk` ONCE PER TARGET MACHINE, not per
project (pulls the sysroot; minutes. Look first: `command=platforms`
says `ready (SDK present)` when it is already there - then skip it;
re-running is safe and incremental: `already up to date` is success) ->
`delphi_config command=add-platform platform=Linux64` (once per project)
-> `delphi_build platform=Linux64` -> `delphi_package` -> `delphi_fetch`
(`download` link, sha256) to run the ELF on YOUR machine - or run it ON
the target with `command=remote-run` and drive its window with
`delphi_desktop`.

One PAServer per Delphi version: a machine can run several, each on its
own port, and a profile has to point to the one of THIS server's Delphi
(`delphi_paserver packages` gives its installer; 13.1 and 13.2 both say
37.0, so the version number does not tell them apart). Another Delphi's
PAServer refuses paclient, and the answer says so (`PAS-056`).

## Windows (PAServer too)

A Windows target - another PC, or this server's own desktop - is set up
the same way, and without PAServer there is nothing to talk to. On that
machine, once: start `paserver.exe` (it ships with RAD Studio under
`C:\Program Files (x86)\Embarcadero\PAServer\37.0\`; `packages` names the
installer for a machine without the IDE) from a terminal INSIDE the user's
session - never as a service, session 0 has no desktop - and open its port
in that machine's firewall, Windows' or the antivirus suite's (measured:
ESET's was the one blocking). From here: `test-connection host= port=`
(no profile) is the probe - unreachable with the machine answering a ping is
a firewall - then `add-profile ... platform=Win64`, `test-connection
profile=`, and `delphi_desktop profile=` deploys the node on its first gesture.

## Android (`delphi_adb`) - eyes and hands

Flow: `discover` (mDNS) -> `connect address=ip:port` -> `devices` ->
`delphi_build target=Deploy` -> `install` -> `run` -> `logcat` ->
`screenshot` -> `tap`/`key`.

- Devices are allowlisted PER WORKSPACE (`AdbAllowedDevices`; absent =
  none): always name your `device=` explicitly.
- `logcat`: default 300 lines, inline answers carry the newest 400.
  For the full dump pass `out=srvd:\...\dump.txt`, then read it in
  ranges or download it. Validate app behaviour by logging from your app
  and filtering on your own tag: `filter=MyTag`.
- `screenshot` returns the device screen **in the same answer** (with
  `inline=false`, a download link that works once; over stdio there is
  none - pass `out=` to keep the file). If you
  cannot view images,
  do not guess from pixel heuristics - a nearly-empty FMX form is a
  uniform (238,238,238) gray that looks like a launcher. Prefer logcat
  evidence.
- `tap` coordinates are PHYSICAL pixels as measured on the screenshot -
  not your .fmx logical coordinates. Phones scale (a 360-logical-wide
  form is 720 physical at scale 2.0). If your taps land nowhere, your
  layout probably overflowed the screen: fix the form with `Align`.
- A wifi-adb device can drop its connection by itself. An
  `[ADB-007 DENIED] NO CONNECTION TO THE DEVICE` answer tells you the
  recovery path; reconnecting may need a human hand
  on the device - say so instead of looping.

## After the server is updated

Your client caches the tool schemas when it connects. If a refusal asks
for a parameter your schema does not have (e.g. `Missing "path"`), the
server was updated after you connected: reconnect the MCP session (or
restart your client) and fetch the tools again. `initialize` tells you
the server version. A NEW optional parameter your cached schema does not
list (e.g. `fragment`) still travels if you send it; the contract you can
trust is `delphi_help command=tool name=<tool>`. A 404 on your session id
also happens when the session expired by inactivity (`[Server]
SessionTimeoutMinutes`, default 720): re-initialize, it is not a failure.

## When you hit a wall

Every refusal or failure starts with its tag, `[AREA-NNN OUTCOME]`, and
the OUTCOME says what to do (rule 11 of `delphi_help command=conventions`):
`INVALID_PARAM` - fix the call and repeat; `NOT_FOUND` - find the right
name and repeat; `DENIED` - the same call will fail again: do what the
reason says, or change course; `INTERNAL` - the server broke: report it.

`delphi_report` files your report (bug / limitation / suggestion /
question) on the server for the operator - it works at EVERY access
level and it is the correct move on an `INTERNAL`, when something looks
broken, when a `DENIED` stops work you need (a feature the operator
turned off), or when a package you need is missing. One honest report
beats twenty blind retries. `command=list` shows the reports of your
workspace (yours and its other agents') and `command=read name=<dir>\<name>`
one whole - before filing, look whether it was already reported.

## Access levels

A read-only credential can read, search, navigate, diagnose, list
components, fetch files and file reports (a capture writes a file, so
`delphi_adb screenshot`, `delphi_desktop` and `delphi_designer preview`
are refused too) - `tools/list` announces what each tool allows in this
mode (`annotations.readOnlyHint`, `_meta.access`, `readOnlyCommands`) - but
every mutating tool (edit/create/build/run/install/tap...) is refused at
the gate. If you are read-only and need a change, report it; do not fish
for bypasses (there are none).

A workspace may also declare `ReadOnlyRoots`: reference projects outside
your roots that you can read, search and navigate to learn how things are
done in this house, never write (bring a unit, a folder or a whole project
in with `delphi_move copy=true`; a repository with its git, when its git is inside) -
`delphi_workspace` lists them and `delphi_projects` flags them `readOnly`.

You always work inside ONE workspace: what its declaration grants is ALL
there is (an absent switch is off, an absent list is empty - hosts,
projects, devices, vault). A refusal naming `RemoteHosts`,
`RemoteRunProjects` or `AdbAllowedDevices` is your workspace's declared
reach, not a server bug: `delphi_report` it if you need more. A `403` with
`SYS-034` on the handshake means your token is right and its workspace is
closed (declared with no roots): the operator's side, not yours.

<!-- contract reviewed: v1.22.1 -->
