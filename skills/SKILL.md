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
2. `delphi_components` - what the server's RAD Studio has installed to
   program with (design packages, any install channel). Check BEFORE
   writing uses clauses for third-party libraries. Base RTL/VCL/FMX are
   always available and not listed. `filter=` narrows (e.g. `filter=FMX`).
3. If a vault is announced in the instructions, `vault_read` its index -
   it holds the operator's conventions and project context.

## Reading files and logs

- `delphi_read` pages at 400 lines per call - read in RANGES.
- `delphi_search` / `delphi_list` to locate; never read whole trees.
- Big dumps (logcat, long outputs) have a file mode (`out=`): use it,
  then read the file in ranges or download it.
- **Getting a file onto YOUR machine** (an installer, an .apk, a
  screenshot PNG, a long unit to grep locally): call `delphi_fetch` once
  and use the `download` field it returns - a `GET /files?path=...` on
  the same host:port as `/mcp`, with the same `Authorization: Bearer`
  header:
  `curl -H "Authorization: Bearer $TOKEN" -o file "http://host:port/files?path=..."`.
  Verify with `sha256sum` against the `X-File-SHA256` header. This is the
  standard way for any size; files over 4 MB answer with the link only.
  Inline base64 chunks (`maxbytes<=1048576`, loop `offset` until `eof`)
  are for clients without a shell.

## Editing safely (`delphi_edit`)

- Anchor edits: `old` must be copied EXACTLY from a fresh `delphi_read`,
  as small and unique as possible. An edit error is a diagnosis - re-read
  and fix the anchor; do not retry blindly.
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
  metadata: an `AVISO DESIGNER` warning in the edit result is measured
  truth - fix it before building. FMX property spelling is not VCL:
  `Size.Width` (not `Size.X`), `TextSettings.Font.Size` (not
  `Font.Size`), `TextSettings.HorzAlign = Center` (not `taCenter`).
- A binary `.dfm` (TPF0 stream or `$FF` resource wrapper, the legacy shape)
  is READ on the fly everywhere - `delphi_read`, `delphi_search`,
  `delphi_designer tree/get/lint/check-binding/layout` - and the answer says
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

## Renaming a symbol

- `delphi_rename_symbol path=<unit> line=<0-based> character=<0-based>
  newname=<NewName>` previews a semantic rename: every occurrence
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

- Never guess what a class publishes: `delphi_designer info class=TButton`
  (add `framework=fmx` for FMX) lists the REAL published properties and
  events; `prop class=TPanel prop=Align` gives the legal enum members.
- `tree path=<form>` shows the component tree; `get component=<Name>` one
  block. After editing a form with `delphi_edit`, run `delphi_designer lint
  path=<form>`: a property the class does not publish or an enum value that
  does not exist will not stream, and nobody tells you at build time.
- A binary `.dfm` reads on the fly; editing it needs `to-text` first (see
  above). `.fmx` is always text.

## FMX styles

- A project's look lives in text `.style` files (one master per theme, or a
  master plus a tokens `.ini`). Treat them BY NAME with `delphi_styles`,
  never by line: `view` lists the StyleNames a `StyleLookup` can use, `get`
  shows one, `set style=cardstyle child=background prop=Fill.Color
  value=xFF112233` changes one property (value exactly as the file writes
  it), `clone style=cardstyle name=cardstyle_alt` adds a variant and
  `delete style=cardstyle_alt` removes one (the `__delphi-patch` copy is
  the way back: `delphi_move` it over the file).
- Before and after touching a `.fmx`: `delphi_styles command=lint
  path=<Styles folder> project=<.dproj>` - a `StyleLookup` that no style
  defines renders with the default look and nobody tells you.
- After editing styles: `command=build path=<Styles folder>` (text ->
  `.bin.style` -> `.res`), then `delphi_build target=Build`: the app embeds
  the binary form; the text form loads but does not resolve `StyleLookup`.
- `delphi_search pattern=*.style` (or `*.ini`, `*.md`) searches files
  outside the Delphi set.

## Mail from the operator

- Any tool answer may end with `MENSAJES PENDIENTES: N`. When it does, call
  `delphi_messages command=read agent=<your id>` before going on: the
  operator answered a report of yours or changed the plan. Messages are
  delivered once; act on them and, when an answer is due, reply with
  `delphi_report`. Use the same `agent` id in both tools. If your client
  cannot set `clientInfo.name` to your id (it introduces itself as `mcp` or
  some generic name), `agent=` is not optional: without it the mailbox looks
  empty while mail waits under your name.

## Running on the target (not on this server)

- `delphi_build target=Deploy` ships the binary; to RUN it there use
  `delphi_paserver command=remote-run name=<profile> project=<the .dproj>
  args=... timeoutms=...`. It returns `exitCode` and the program's output.
  You never give a remote path: the server runs what THAT project deployed
  and nothing else on that machine (a script in the same folder is refused
  too - only native binaries).
- Nothing has to be installed on the target (v0.98): PAServer itself runs
  what this server sends. If the program has not finished when the timeout
  expires it is NOT killed - you get `stillRunning: true` and its partial
  output; a GUI app stays up, ready to be driven with delphi_desktop. If a
  job is stuck or no longer wanted, the same answer's `killNote` gives the
  call: `delphi_paserver command=kill name= project= job=<jobId>` - it
  stops only that job, on that machine.
- Only the NATIVE binary that project deployed can run (the launch script
  verifies the file signature). Remember
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
piece of the same capture at full resolution, with an `origin` to ADD to
what you measure on it - use it to read a small dialog, and go back to the
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
`RESPALDO:` line: same coordinates, no cursor, no taskbar.) On
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
  header and project entries. `view` lists the project's `units`.
- `delphi_build` runs MSBuild. The result declares the real `output`
  path - trust it, do not guess. `target=Deploy` on Android builds the
  full `.apk` (the server generates the deployment manifest if missing).
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
`delphi_build platform=Linux64` -> `delphi_package` -> `delphi_fetch`
(`download` link, sha256) to run the ELF on YOUR machine - or run it ON
the target with `command=remote-run` and drive its window with
`delphi_desktop`.

## Windows (PAServer too)

A Windows target - another PC, or this server's own desktop - is set up
the same way, and without PAServer there is nothing to talk to. On that
machine, once: start `paserver.exe` (it ships with RAD Studio under
`C:\Program Files (x86)\Embarcadero\PAServer\37.0\`; `packages` names the
installer for a machine without the IDE) from a terminal INSIDE the user's
session - never as a service, session 0 has no desktop - and open its port
in that machine's firewall, Windows' or the antivirus suite's (measured:
ESET's was the one blocking). From here: `test-connection host= port=`
(no name) is the probe - unreachable with the machine answering a ping is
a firewall - then `add-profile ... platform=Win64`, `test-connection
name=`, and `delphi_desktop profile=` deploys the node on its first gesture.

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
- `screenshot` writes a PNG **on the server** (`out=...png`); download
  with `delphi_fetch` if you can actually view images. If you cannot,
  do not guess from pixel heuristics - a nearly-empty FMX form is a
  uniform (238,238,238) gray that looks like a launcher. Prefer logcat
  evidence.
- `tap` coordinates are PHYSICAL pixels as measured on the screenshot -
  not your .fmx logical coordinates. Phones scale (a 360-logical-wide
  form is 720 physical at scale 2.0). If your taps land nowhere, your
  layout probably overflowed the screen: fix the form with `Align`.
- A wifi-adb device can drop its connection by itself. A `SIN CONEXION`
  answer tells you the recovery path; reconnecting may need a human hand
  on the device - say so instead of looping.

## After the server is updated

Your client caches the tool schemas when it connects. If a refusal asks
for a parameter your schema does not have (e.g. "Falta path"), the
server was updated after you connected: reconnect the MCP session (or
restart your client) and fetch the tools again. `initialize` tells you
the server version. A NEW optional parameter your cached schema does not
list (e.g. `fragment`) still travels if you send it; the contract you can
trust is `delphi_help command=tool name=<tool>`. A 404 on your session id
also happens when the session expired by inactivity (`[Server]
SessionTimeoutMinutes`, default 720): re-initialize, it is not a failure.

## When you hit a wall

`delphi_report` files your report (bug / limitation / suggestion /
question) on the server for the operator - it works at EVERY access
level and it is the correct move when a tool refuses you, something
looks broken, or a package you need is missing. One honest report beats
twenty blind retries.

## Access levels

A read-only credential can read, search, navigate, diagnose, list
components, fetch files, take screenshots and file reports - but every
mutating tool (edit/create/build/run/install/tap...) is refused at the
gate. If you are read-only and need a change, report it; do not fish
for bypasses (there are none).

Since v0.98 you always work inside ONE workspace: what its declaration
grants is ALL there is (an absent switch is off, an absent list is empty -
hosts, projects, devices, vault). A refusal naming `RemoteHosts`,
`RemoteRunProjects` or `AdbAllowedDevices` is your workspace's declared
reach, not a server bug: `delphi_report` it if you need more.
