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
- `READ-007` on a read: some bytes do not fit the file's encoding (a mixed
  or damaged file). They show as U+FFFD and no writer writes the file back
  (`EDIT-038`): fix it in its editor, or restore a good copy. `READ-008`: a
  source in UTF-8 without a BOM, which the compiler reads as ANSI, so its
  accents reach the program as mojibake - the way out is the IDE's (open and
  save it: UTF-8 with a BOM). Leave its bytes as they are.
- **An API you do not know** (what a class or routine is for, how it is
  used, which framework has it): `delphi_docs search query=<it>` and then
  `read id=<a result>` - the RAD Studio help installed on the server, in
  small pieces: a long page gives its introduction and sections first, a
  class its member lists in `related`. Do not guess and do not read a whole
  RTL unit for it. For the exact signature, the installed sources win:
  `delphi_hover` / `delphi_definition`. It works in any workspace: it
  opens only the help files the IDE registers.
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
  an anchor (the rest of the line does, to its end), and `occurrence`
  counts the matching lines of the file as it was before the batch; when an
  anchor that carries indentation picks a line indented otherwise, the
  batch is refused (`EDIT-121`) with each line as `line N = occurrence K`.
- **Fragment mode, for a long line**: `fragment` + `atline` (mandatory) +
  `new` changes just that piece of ONE line - no need to paste a
  600-character README paragraph to turn "68" into "69". The fragment must
  appear EXACTLY ONCE in that line, case-sensitive; zero or several is a
  refusal that shows you the real line. No line breaks, and it does not
  combine with `old`, `delete`, `toline` or another mode (`insert`,
  `createunit`, `restore`, `create`). Same
  rule in `delphi_edit`, `delphi_textedit`, batches (`edits`, key
  `fragment`) and `delphi_changeset` stage (resolved when you stage).
- Pascal traps: a method signature exists TWICE (interface +
  implementation); there are TWO uses clauses; one single `end.` at the
  file end. Half an edit is not an edit.
- `.fmx`/`.dfm` are DATA, not code. The compiler only checks their text
  grammar - a wrong property name or enum value compiles fine and then
  **crashes the form at load time on the target, silently**. The server
  lints designer edits against tables generated from the framework's own
  metadata: an `DESIGNER WARNING` warning in the edit result is measured
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
  one is read through ANSI, and a character ANSI cannot hold is refused.
- Prefer `Align`/anchors over absolute Position/Size in forms: absolute
  coordinates designed on a desktop form overflow phone screens.

## Tests: does it WORK, not just compile

- `delphi_test command=discover path=<folder>` finds the test projects;
  `command=run project=<the test .dproj>` builds and runs one and answers
  `total`/`passed`/`failed` with the failing lines. That is your red-green
  loop: edit -> diagnostics -> build -> **test** -> commit.
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
  silently.
- If `applicable=true`, repeat the same call with `mode=apply`: the tool
  writes it through the changeset engine (all files or none, a backup of
  each) and answers with the commit. Then `delphi_build`. If false, the
  blockers say exactly why - fix them or leave the name alone; apply
  writes nothing in that case.

## Forms (.dfm/.fmx)

- Never guess what a class publishes: `delphi_designer info classname=TButton`
  (add `framework=fmx` for FMX) lists the REAL published properties and
  events; `prop classname=TPanel prop=Align` gives the legal enum members.
- `tree path=<form>` shows the component tree; `get component=<Name>` one
  block. After editing a form with `delphi_edit`, run `delphi_designer lint
  path=<form>`: a property the class does not publish, or a value its type
  does not take (an enum value that does not exist, a `Color = 'hola'`),
  will not stream, and nobody tells you at build time - lint judges values
  with the same checks as `set`.
- To ADD a component: `delphi_designer command=insert path=<form>
  classname=TButton component=BtnOk` (`component` names it, its text too
  when the class shows its Name, so no `set prop=Name` afterwards - without
  it, the first free Button1, Button2... as the IDE; `parent=Panel1` puts it
  inside a container, the form by default). Do not write a visual control's
  block by hand: insert places it at 10,10, among its siblings where the
  IDE keeps it, with the minimum the IDE writes (its Name as text when its
  class does that, its TabOrder), adds its published field to the form's
  class and its unit to the uses, and answers the numbered block. In VCL a
  parent is the form or a control whose class accepts controls (a TPanel, a
  TGroupBox, a TTabSheet - not its TPageControl, not a TButton; never a data
  module); in FMX any control. What insert cannot place - a non-visual
  component such as a TTimer, a class or a parent the tables do not have -
  goes by hand, and the refusal says how: its block, its published field,
  its unit in the uses, then `check-binding`. A name with letters outside
  ASCII needs the form saved as UTF-8 with BOM, and the unit with a BOM or in
  ANSI: the IDE and the compiler read a file without BOM as ANSI, so
  insert and a rename refuse it in a file that has an encoding to keep
  (`DSGN-111`) rather than change it; a unit that is still pure ASCII has
  none, and the name chooses ANSI (or UTF-8 with a BOM when ANSI cannot hold
  it), as the IDE does when it saves. In an inherited form the names of the
  ancestors count, although their components are not written in the derived
  file: insert never picks one, and a name that one of them has is refused,
  naming the ancestor.
- To CHANGE one property: `set component=Button1 prop=Caption value=OK`. It
  is checked against the class BEFORE writing: a property the class does
  not publish (the answer suggests the close one), an enum value that does
  not exist (the answer lists the legal ones), a value its type does not
  take (read from the Delphi source: a whole number or one of its named
  constants such as clRed, a number, a character, a string), a component
  of another class (a DBGrid's DataSource takes a TDataSource: the answer
  lists the ones that fit), a list such as Memo1.Lines (edit it with
  `delphi_edit`) - nothing is written. `value=nil` clears a reference. A
  string may go without quotes, and a number as you would type it (130,
  0.7): set writes it the way the IDE does (an accent as #243, a long string
  in pieces). A reference to a component inside an inline frame is written
  `Frame1.Name` (one of another form, `Form2.Name`) and goes as given: the
  form loader resolves it, set does not read the other file; the frame's
  own components are edited in the frame's file. The
  form's own size (`component=<the form>
  prop=ClientWidth`) and an inline frame's Width/Height go through set too.
  A path through a reference to another component (`PopupMenu.AutoPopup` on
  a button) is refused (`DSGN-119`): the form loader reads it before the
  reference exists - set it on that component (`component=PopupMenu1
  prop=AutoPopup`); a sub-component such as `EditLabel.Caption` is written
  as before. In FMX a control's place is `Position.X`/`Position.Y`, and
  `Left`/`Top` are refused (`DSGN-118`).
  `set component=X
  parent=Panel1` (alone) moves X with its children; `prop=Name` renames it,
  its field and the form lines that name it (its methods keep their names,
  and `usesInCode` lists the code that still says the old one).
- To REMOVE one: `delete component=X`. It is REFUSED while a method of its
  own - a handler it is bound to, or one named after it - has code, and the
  answer lists each with its line: clean them first (move what they do, or
  empty them) and repeat. Empty handlers, its field and the references to
  it in the form go with it; a method something else also uses stays.
  `usesInCode` lists the lines of the unit that still name it: the compiler
  stops there. insert, delete and a rename write the form and its unit
  together, all or nothing.
- A binary `.dfm` reads (and previews) on the fly; editing it needs `to-text` first (see
  above). `.fmx` is always text.
- SEE the form instead of imagining it: `delphi_designer command=preview
  path=<form>` returns a PNG of what the IDE designer shows, in the same
  answer. The loop is insert/set (or `delphi_edit` for the rest) -> `lint`
  -> `preview` -> fix. Several properties at once go in `props`
  (`Caption=Save;Left=24`, insert and set, all or none); `set before=`,
  `after=` or `index=` reorders a component among its siblings, only where
  the IDE's own writer keeps it (a refusal gives the order it would save;
  the file order is the z-order, TabOrder the keyboard order).
  To place something, measure on the image and convert with its `frame`
  (image pixels to form units; `Left`/`Top` in the file - `Position.X`/
  `Position.Y` in FMX - are relative to the parent, whose rectangle
  `component=<parent>` gives as `componentRect`).
  `state=PageControl1.ActivePage=TabSheet2` shows another page without
  touching the file (inside an inline frame, `Frame1.Edit1.Text=x`); and
  `component=Frame1.Edit1` crops to a frame's child;
  `nonVisual` lists the non-visual components even when
  they are not drawn (`nonvisual=true` draws them). `ignored` lists each
  property the form loader could not read - component, property, reason
  and its line in the file -: the rest is drawn, but the form will not open
  until you fix them with `set`. From a service the
  answer says `fidelity=print`: controls that paint their own way come out
  native-looking, the layout is the real one.
  `style=` draws it with another look, never written to the file: in FMX the
  form's own StyleBook by default, `none` for the Windows default, a `.style`
  file, or a platform of the designer's Style list (`android`, `ios`,
  `win11`...); in VCL a `.vsf` file (then out of design mode: VCL styles
  never apply to designed controls) or `none`, the default.

## FMX styles

- A project's look lives in text `.style` files (one master per theme, or a
  master plus a tokens `.ini`). Treat them BY NAME with `delphi_styles`,
  never by line: `view` lists the StyleNames a `StyleLookup` can use, `get`
  shows one, `set style=cardstyle child=background prop=Fill.Color
  value=xFF112233` changes one property (value exactly as the file writes
  it), `clone style=cardstyle name=cardstyle_alt` adds a variant and
  `delete style=cardstyle_alt` removes one. The way back is the
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
  `delphi_messages command=read agent=<your id>` before going on: the
  operator answered a report of yours or changed the plan. Messages are
  delivered once; act on them and, when an answer is due, reply with
  `delphi_report`. Use the same `agent` id in both tools. If your client
  cannot set `clientInfo.name` to your id (it introduces itself as `mcp` or
  some generic name), `agent=` is not optional: without it the mailbox looks
  empty while mail waits under your name.

## Running on the target (not on this server)

- `delphi_build target=Deploy` ships the binary to the host of its PAServer
  profile (the call's `profile`, else the project's `set-profile`), which
  has to be in `RemoteHosts`; to RUN it there use
  `delphi_paserver command=remote-run profile=<profile> project=<the .dproj>
  args=... timeoutms=...`. It returns `exitCode` and the program's output.
  You never give a remote path: the server runs what THAT project deployed
  and nothing else on that machine (a script in the same folder is refused
  too - only native binaries).
- Nothing has to be installed on the target (v0.98): PAServer itself runs
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
or this very server when a PAServer runs in its user session. ALWAYS through
a PAServer listening on that machine, Windows included: without one there
is no desktop to reach, whatever the network says. The machine is
the `profile` parameter, never a different tool. No `project` needed: the
node bundled with the server deploys and UPDATES itself on the target on
first use (a `node.ver` stamp), the right binary for that system - nothing
is compiled or installed by hand.

**One step, no arithmetic (1.3.1):** a `screenshot` comes back IN the
same answer as an image (scaled to `maxwidth`, 1280 by default) together
with a `frame` token; nothing to download, and its temp file is gone.
To press what you see, measure x,y ON THAT IMAGE and call `tap` (or
`type`) with those x,y and `frame=<the token, copied as it is>`: the
server converts scale, crop origin and (Android) display for you. Never
divide by a scale or add an origin yourself. `inline=false` gives the
old file + `download` link (still with a `frame`).

Flow: `screenshot` brings the WHOLE desktop here as a PNG -> LOOK at it and
measure the pixel -> `tap x= y=` presses exactly there (the node converts
the screen scale itself; always measure ON the screenshot it returned) ->
`type text=` writes (with `x`,`y` it presses there first: one trip). On
Linux it types with the DESKTOP'S OWN keymap, so accents, `@`, capitals and
punctuation arrive whatever the layout is, and the echo names the keyboard
it used; a character that layout has no key for is a refusal, not a silent
drop. On Windows it types Unicode. The text is typed, never run: shell
metacharacters are just characters ->
`key code=` presses one key: on a Linux target by evdev code (Escape 1,
Tab 15, Enter 28), on a Windows target by NAME (escape, enter, tab, super,
f1..f12) - the tool reads the profile's platform and refuses the other
kind, because a number on Windows is a different key; `modifiers=ctrl`
(or shift, alt, super, comma separated) holds them while the key goes down:
Ctrl+K on Linux is `code=37 modifiers=ctrl`, Alt+Tab `code=15
modifiers=alt`. `type` on Linux composes accented letters through the
layout's dead keys ("í" = dead acute + i), so Spanish text arrives whole ->
every capture comes with a `windows` list (title + rectangle in capture
pixels; on Linux the X11/Xwayland windows, i.e. every FMX app - native
Wayland windows are not listed); `overview` brings them all into view to
reach a covered one (Linux: the Super overview - tap one or Escape) ->
`screenshot region="x,y,w,h"` (or `window="<title>"`) brings back just that
piece of the same capture at full resolution, with an `origin` (pass its `frame` to tap and the server adds it; without frame, ADD it to
what you measure on it) - use it to read a small dialog, and go back to the
whole desktop whenever something may have opened elsewhere -> `status` says whether
the desktop is reachable and what to ask for. Every answer carries
`graphicalEnv`: the session the node ran in.

It runs under the SAME workspace switches as remote-run: `AllowRemoteRun`,
`McpDesktopNode` (or the wildcard `all`) in `RemoteRunProjects`, and the
profile's host inside `RemoteHosts` (the server's own desktop is the
profile whose host is 127.0.0.1). The target needs a graphical session open
for the user PAServer runs as. On Linux, PAServer may run as a service: the
server completes DISPLAY and friends from the session. On Windows, PAServer
must run INSIDE the user's session (a Windows service lives in session 0,
which has no desktop) and the session must be unlocked - a locked Windows
answers "Access denied" to any capture, and the tool says so in `hint`. (An
unlocked one may refuse the screen copy now and then; the node then composes
the desktop from the windows themselves and `nodeOutput` carries a
`FALLBACK:` line: same coordinates, no cursor, no taskbar.) On
GNOME the screen-capture permission must have been granted once - a mute
screenshot timeout means exactly that permission.

Coordinates are REAL pixels on both systems and the Windows node is
DPI-aware: measure on the screenshot or on `windows`, and never mix in
coordinates from a tool that is not DPI-aware (on a 125% display the same
window sits 250 px away). **When the profile is someone's own machine, its
screen and mouse are theirs**: whatever they have open is in frame. Do the
gesture you came for and nothing else.

## Projects and builds

- `delphi_create` scaffolds console/VCL/FMX projects, runtime packages
  and DUnitX test projects (`project-test`: runner + first fixture, green
  at birth; `delphi_test` runs it), and inside a
  project: `form-vcl`/`form-fmx`, `frame-vcl`/`frame-fmx`, `datamodule`
  and `unit` (a plain .pas). Everything compiles at birth and is already
  registered in the `.dpr` and the `.dproj`. Then `delphi_config
  command=add-platform` for extra targets.
- **The folder layout is yours**: inside a project, `dir=` is a SUBFOLDER
  of the project (relative, as deep as you like - no drive, no `..`); the
  unit is born there and registered with its relative path. Moving or
  deleting a whole FOLDER with `delphi_move` / `delphi_delete` re-points
  or removes the units inside it in the `.dpr`/`.dproj`.
- **Project membership is the server's job, never a hand edit of the
  `.dpr`/`.dproj`**: an existing `.pas` joins with `delphi_config
  command=add-unit path=<.pas>` (forms get their `CreateForm`, frames do
  not), `remove-unit` drops it from the project and keeps the file,
  `delphi_delete` on a unit trashes its designer pair and updates the
  projects that list it, `delphi_move` renames/moves a unit with its pair,
  header and project entries; with `copy=true` it copies instead (header and pair too, no project re-pointed: `add-unit` when you want it in one). `view` lists the project's `units`.
- `delphi_build` runs MSBuild. The result declares the real `output`
  path - trust it, do not guess. `target=Deploy` on Android builds the
  full `.apk` (the server generates the deployment manifest if missing).
- **A build is what the IDE would build**: only a platform the project
  declares and has enabled (another is refused with `BUILD-046`:
  `delphi_config command=add-platform` declares it, as the IDE does), and
  without `platform` the project's own default. What you build, the
  operator builds the same in the IDE without reconfiguring anything.
- **"Unit 'X' not found" on a platform you just added** (and only
  there): the unit belongs to an installed component whose folder is in
  the IDE's library path for the other platforms only. The failed build
  already says where: `missingUnits[].sourceFolders` - run the
  `delphi_config command=add-searchpath platform=<the one> path=<folder>`
  it names and build again (one round per library, not two). Before the
  first build on a new platform, `delphi_components platform=<the one>`
  lists the components registered elsewhere and not there. An empty
  `sourceFolders` means no source for that platform: `delphi_report`.
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
-> `test-connection` -> `get-sdk` once (pulls the sysroot; minutes -
re-running it is safe and incremental: `already up to date` is success) ->
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
  NONE since v0.98): always name your `device=` explicitly.
- `logcat`: default 300 lines, inline answers carry the newest 400.
  For the full dump pass `out=srvd:\...\dump.txt`, then read it in
  ranges or download it. Validate app behaviour by logging from your app
  and filtering on your own tag: `filter=MyTag`.
- `screenshot` returns the device screen **in the same answer** (with
  `inline=false`, a file on the server and its download link). If you
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

A workspace may also declare `ReadOnlyRoots`: reference projects outside your roots that you can read, search and navigate to learn how things are done in this house, never write (bring a unit or a folder in with `delphi_move copy=true`; a whole project stays where it is) - `delphi_workspace` lists them and `delphi_projects` flags them `readOnly`. A read-only credential can read, search, navigate, diagnose, list
components, fetch files and file reports (a screenshot writes a capture
file, so `delphi_adb screenshot` and `delphi_desktop` are refused too) -
`tools/list` announces what each tool allows in this mode
(`annotations.readOnlyHint`, `_meta.access`, `readOnlyCommands`) - but every
mutating tool (edit/create/build/run/install/tap...) is refused at the
gate. If you are read-only and need a change, report it; do not fish
for bypasses (there are none).

Since v0.98 you always work inside ONE workspace: what its declaration
grants is ALL there is (an absent switch is off, an absent list is empty -
hosts, projects, devices, vault). A refusal naming `RemoteHosts`,
`RemoteRunProjects` or `AdbAllowedDevices` is your workspace's declared
reach, not a server bug: `delphi_report` it if you need more.

<!-- contract reviewed: v1.18.0 -->
