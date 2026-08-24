---
name: cmcpdelphiide
description: Work a remote RAD Studio (Delphi IDE) machine through the Delphi IDE Remote MCP Server (delphi_* / vault_* tools). Load when connected to an MCP server exposing delphi_workspace, delphi_build, delphi_edit and friends - it teaches the path model, the safe-editing contract, the build/deploy chains (Windows, Linux via PAServer, Android via adb) and how to move files and logs the right way.
---

# Delphi IDE Remote MCP - field guide for agents

You are talking to a Windows machine that has RAD Studio installed. The
projects, the compiler, the devices and the files all live THERE. You
build, edit, deploy and drive apps through tools; you never need Delphi
on your side.

## First contact (always, in this order)

1. `delphi_workspace` - your allowed roots, your access level, and the
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
- Binary designer files (TPF0 stream or `$FF` resource wrapper) are
  refused - they belong to the IDE. Do not try to work around it.
- Prefer `Align`/anchors over absolute Position/Size in forms: absolute
  coordinates designed on a desktop form overflow phone screens.

## Forms (.dfm/.fmx)

- Never guess what a class publishes: `delphi_designer info class=TButton`
  (add `framework=fmx` for FMX) lists the REAL published properties and
  events; `prop class=TPanel prop=Align` gives the legal enum members.
- `tree path=<form>` shows the component tree; `get component=<Name>` one
  block. After editing a form with `delphi_edit`, run `delphi_designer lint
  path=<form>`: a property the class does not publish or an enum value that
  does not exist will not stream, and nobody tells you at build time.
- Binary designers (TPF0) are refused everywhere: have a person save the
  form as text from the IDE first.

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
  `delphi_report`. Use the same `agent` id in both tools.

## Running on the target (not on this server)

- `delphi_build target=Deploy` ships the binary; to RUN it there use
  `delphi_paserver command=remote-run name=<profile> project=<the .dproj>
  args=... timeoutms=...`. It returns `exitCode` and the program's output.
  You never give a remote path: the server runs what THAT project deployed
  and nothing else on that machine (a script in the same folder is refused
  too - only native binaries).
- It needs the runner installed ONCE on the target: `delphi_paserver
  command=install-runner name=<profile>` copies it there and answers with
  the single line somebody with a shell on that machine must run (`nohup
  python3 _mcp-runner/mcp-runner.py &`). Without that launch the call times
  out and tells you so - that is the opt-in, not a bug.
- The runner refuses anything outside the scratch dir. Remember
  `target=Deploy` REWRITES that folder: copy state you need before
  redeploying.

## Create and build

- `delphi_create` scaffolds console/VCL/FMX projects, and inside a
  project: `form-vcl`/`form-fmx`, `frame-vcl`/`frame-fmx`, `datamodule`
  and `unit` (a plain .pas). Everything compiles at birth and is already
  registered in the `.dpr` and the `.dproj`. Then `delphi_config
  command=add-platform` for extra targets.
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
is ~70 MB) -> install and start it on the target -> `add-profile` ->
`test-connection` -> `get-sdk` once (pulls the sysroot; can take minutes)
-> `delphi_build platform=Linux64` -> `delphi_package` -> `delphi_fetch`
(`download` link, sha256) -> run the ELF on YOUR machine.

## Android (`delphi_adb`) - eyes and hands

Flow: `discover` (mDNS) -> `connect address=ip:port` -> `devices` ->
`delphi_build target=Deploy` -> `install` -> `run` -> `logcat` ->
`screenshot` -> `tap`/`key`.

- An allowlist may be active: name your `device=` explicitly.
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
the server version.

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
