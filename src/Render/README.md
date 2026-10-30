# `src/Render/` — the form renderers

Two small console companions of the server, one per framework, that turn a
`.dfm` / `.fmx` into a PNG of **what the IDE designer shows** — without the
IDE, without running the application and without putting anything on the
server's desktop. `delphi_designer command=preview` runs them; the server
expects the exe **next to its own exe** (like `DelphiStyleConvert.exe`).

| Project | Builds | Renders |
|---|---|---|
| `DelphiFormRenderVcl.dproj` | Win32, runtime packages `rtl;vcl;vclimg;vclx;vclactnband;vclwinx;vclsmp` | a VCL form or frame |
| `DelphiFormRenderFmx.dproj` | Win32, runtime packages `rtl;fmx` | an FMX form or frame, with its style |

**Why two processes and not a unit in the server.** The IDE's design
packages (and every third-party package the user installed) are loaded
*into* the renderer, exactly as the IDE loads them when it opens a form. A
package that crashes on load kills the renderer, never the server; FMX must
not be linked into a Windows service; and the VCL and FMX control classes
share names. Each renderer is launched with a time limit, carries its own
watchdog (`--timeout`, exit code 3) and answers on stdout only.

**Why Win32.** RAD Studio keeps two IDEs; most third-party and GetIt
packages register only in the 32-bit one (`HKCU\...\BDS\<ver>\Known Packages`).
The renderers load that list, so they are 32-bit too — and they belong to
one Delphi version (the `370` BPLs), like the server since 1.14.0.

## What the exe needs

- The BPLs of its runtime packages (`<BDS>\bin`) on the PATH, like any exe
  built with packages. The RAD Studio installer puts that folder on the
  MACHINE PATH, and the server keeps it on the renderer's PATH; without them
  Windows cannot start the renderer and the server answers `DSGN-063`.
- Where the IDE is (`--bdsroot`) and which packages it may load (`--knownfile`,
  one path per line). The server reads them from the IDE's registry and tells
  it: inside its container the renderer cannot read the registry.
- Nothing else. The standard palette (Standard, Additional, Win32, Dialogs,
  WinX, action bands, samples) is registered from the renderer's own `uses`,
  as the IDE does with the form it creates. Every other class — data
  controls, third parties, the user's own packages — comes from the IDE's
  Known Packages, loaded **at run time and only when the file names a class
  the palette does not know** (`--packages auto`). Installing a package in
  the IDE is all it takes for the renderer to see it.

## Where it runs: its container

The design code of a package reads and writes whatever a form asks it to, so
the server always runs the renderer inside an AppContainer with no
capabilities, one per call, with its Job Object, and never outside one: if the
container cannot be prepared nothing is drawn (`DSGN-177`). Measured: from
there it opens nothing of the workspace roots, of the server's folder, of the
user's profile or of a mapped drive, and it has no network. Windows and the two
Program Files folders it can read, as any application package can; that is why
a form literal that names something there is refused by its text (`DSGN-115`),
exists or not. What a literal names anywhere else is not checked at all: the
answer must not say whether a file exists.

What it needs travels to it:

- **The folder of the call**, in the server's home: the form, its siblings of
  the same type and their units, what a form literal names below the form's
  folder if the session can read it (up to 64 MiB: a `TAnimate`'s `.avi`), and a
  style file. The renderer's answer is translated back to the real paths, and
  the folder goes when the call ends. A component that opens a file by its FULL
  path does not reach it, even inside the roots: it fails as with a missing
  file.
- **The package box**, also in the server's home, shared by every call and
  readable, not writable, by every container: the renderers and the `.bpl` and
  `.dll` of the folders that hold a Known Package, of `$(BDSCOMMONDIR)\Bpl` and of
  the PATH folders with packages, except the ones the container reads where they
  are. It is named after what it holds, so a package added or rebuilt makes a
  new box.
- **The COM classes it cannot look up.** Windows keeps a few classes under a
  registry key no container may read, while the DLL itself is readable: of 5181
  32-bit in-process classes measured, 4, the ADO ones (`Command`, `Parameter`,
  `Recordset`, `Error`). Without them a form with a `TADOQuery` loses the
  component. When the box is made the renderer is asked which keys it cannot open
  (`--unreadableclasses`); the server reads those keys and gives the classes
  whose DLL the container reads to the box's copy of the renderers, in their
  manifest, and Windows judges that manifest by starting them. If any of this
  fails the copy keeps no manifest and the server logs it: those components stay
  out of the form, reported in `ignored`. The code of the class still runs inside
  the container, with what the container reads and nothing else.

The language of the RTL's messages is Windows's: the per-exe override in
`HKCU\Software\Embarcadero\Locales` does not reach the container.

## Command line

The server composes it in ONE place, `Lsp.FormRender.ComponeOrdenDeRender`
(and `ParseaArgumentos` here is its inverse; `tests/test_paisaje.py` keeps
anyone else from writing it). Every value travels as one quoted argument, so
a value with a double quote or a control character is refused before
anything is launched (`DSGN-065`): Delphi's argument reader has no escape for
a quote, and what followed it would be another switch.

```
DelphiFormRenderVcl --path <dfm> --out <png> [--state Comp.Prop=Value]* [--component Name]
                    [--style <file.vsf>] [--nonvisual on|off] [--packages auto|none|all]
                    [--root auto|form|frame] [--fidelity auto|window|print]
                    [--bds 37.0] [--bdsroot <dir>] [--knownfile <file>] [--timeout ms] [--verbose]
DelphiFormRenderFmx --path <fmx> --out <png> [--state ...]* [--component Name]
                    [--style <file.style>|none|windows|win7|win8|win10|win11|mobile|android|ios|ios-dark|osx|linux|gnome]
                    [--nonvisual on|off] [--packages ...] [--root ...] [--bds] [--bdsroot] [--knownfile] [--timeout] [--verbose]
DelphiFormRender*   --unreadableclasses
```

- `--state`: a view state applied through RTTI after the form is built and
  shown, never written to the file: `PageControl1.ActivePage=TabSheet2`,
  `Edit1.Text=hello`. A class-typed value names a component, and an integer
  with a name (`clRed`, `crHandPoint`, `claRed`) is read by its type's own
  reader, as the form loader reads it.
- `--writeback on`: the judge of what the IDE saves. No PNG: the form is
  loaded the same way and written by the IDE's own writer (TWriter), each
  line as `WRITTEN=`. Its siblings (frames, ancestors) and its `.pas` are read
  from next to `--path`: the server copies them there, with the proposal in
  the place of the real form.
  `delphi_designer` `insert` and `set` ask it before writing; `--dropped` names
  the control just dropped, which gets what the designer gives it (alignment,
  tab order).
- `--convert text|binary`: no load and no paint: the bytes of `--path` converted
  into `--out`, with the IDE's own conversion. `delphi_designer to-text`/`to-binary`
  and every reading of a binary `.dfm` use it.
- `--component`: the renderer answers `RECT=<name>=l,t,w,h` in PNG pixels;
  the server crops with its own cropper (`Lsp.Imagen.RecortaPng`).
- `--nonvisual on` (like the designer's "Show non-visual components"):
  each non-visual component is drawn at the Left/Top the file stores (0,0
  without one), with the icon its package ships (`<CLASS>128_PNG`
  resource) or the class initials, and its name underneath. The default
  is `off`, the same as `delphi_designer`'s: what a model needs is to know
  they exist, and `NONVISUALS=` lists them either way.
- `--style`: VCL takes a `.vsf` and renders **out of design mode** (the VCL
  style engine never styles a designed control, which is why the VCL
  designer paints unstyled). FMX applies the style **as an application
  would**, a `TStyleBook` on the form (the global `TStyleManager` style loses
  glyphs — measured): the form's own StyleBook by default, `none` for the
  Windows default, a `.style` file, or one of the designer's platform
  previews read straight from `fmx370.bpl` / `fmxdesigner370.bpl` resources
  (opened as data, nothing of theirs runs).
- `--root auto`: form or frame decided from the sibling `.pas`
  (`TX = class(TFrame)`); a frame is rendered inside a form of its size, as
  the designer shows it.
- `inline` frames are built from their own `.dfm`/`.fmx` found by class name
  in the form's folder, then the form's `inherited` overrides are applied;
  an `inherited` form is read after its ancestors (chain from the `.pas`).
  An FMX view (`<unit>.<View>.fmx`, whose class no `.pas` declares) is read
  on top of its master (`<unit>.fmx`) when the master's `.pas` declares it
  with `{$R *.<View>.fmx ...}`, as the IDE does.

## Output (stdout, `KEY=value` lines; the keys live in `FormRenderProtocolo.inc`)

```
DPI=96                        the process is DPI-unaware: 1 pixel = 1 dfm unit
SESSION=<n>                   0 = a service
STYLE=<what was applied>
ROOT=<Name>:<Class>:<form|frame>
PACKAGES=<loaded>/<known>     0/0 = the palette was enough
COMPONENTS=<n>
SUBSTITUTED=<classes>         not found in any package: pink box with the name
IGNORED=<reader error>        repeatable; also before a failure: what the
                              reader skipped is usually WHY it failed (a value
                              skipped without being consumed leaves the reader
                              lost, and the failure says only "Stream read error")
WARNING=<text>                repeatable
PARTIAL=<ancestor or file>    repeatable: the form was read WITHOUT it (an
                              ancestor with no .pas saying which, or with no
                              form file in the folder)
WRITTEN=<line>                repeatable, --writeback on: the form as the
                              IDE's own writer saves it (no CAPTURE)
NONVISUAL=<n>                 icons drawn (only with --nonvisual on)
NONVISUALS=<Name:Class,...>   the root's non-visual components, drawn or not
RECT=<name>=<l>,<t>,<w>,<h>   with --component
FIDELITY=window|print|canvas  VCL: real painting (needs DWM, an interactive
                              session) or WM_PRINT per control (works from a
                              service; controls that paint their own way come
                              out native-looking). FMX: always its canvas.
SIZE=<w>x<h>
CAPTURE=<png>
MS=<load>,<paint>
NOTLOADED=<exception class>   before ERROR=: what failed was the form READER
                              while loading (EFilerError or EParserError) - the
                              file, not the renderer; the server answers DSGN-153
                              with the reader's words and the line, not DSGN-061
ERROR=<text>                  with exit code 1 (3 = timeout, 2 = usage)
```

What reaches the agent in `ERROR=` and `WARNING=` lives in
`FormRender.Textos`, the renderers' message catalog (area `RENDER`, English,
the tag first: `tests/test_catalogo.py` checks it with the server's and the
node's). A refusal of ours (a `--state` that names nothing, an unknown
platform style) goes out tagged and the server passes it through as it is;
anything else comes out as `<class>: <message>`.

Nothing reaches the desktop: the form is created in design mode (application event
handlers are ignored), FMX's dialog services are removed on start,
`Application.OnException` records instead of showing, and the watchdog kills
a render that waits on anything.

## What a form file can and cannot do to the renderer

The code the renderer loads is fixed by the machine, never by the file: its runtime BPLs,
and - only when the file names a class the standard palette does not know - the design
packages registered in the IDE (HKCU Known Packages, as the server lists them, their
initialization included; the file can trigger that load, it cannot choose or add a package). BPLs opened
for icons and platform styles are opened as data: nothing of theirs runs. TReader creates
registered classes only; an unknown class becomes a labelled substitute. Its input comes from
the server through its read gate, copied to the folder of the call: the form, its sibling .pas
and .dfm/.fmx files in the same folder (links are skipped), a style file.

What a hostile file CAN do is feed bad values and binary blobs (pictures, image lists,
collections) to the loaded classes and crash or stall the renderer. That is why it runs as a
process of its own, with its watchdog and the server's own time limit, and why the server
answers with the error instead of dying with it.

The server checks string literals and requested view-state values before starting the
helper, using the existing form reader and read-path gate, by their text and for what the
container can read (see above). The requested form and its
examined siblings share a 16 MiB input budget; larger input is refused before decoding.
This budget bounds the server's preliminary read, which runs outside the helper's job.

**Cleanup: what is measured and what is not.** The renderer starts no
processes of its own. Measured: its watchdog (exit code 3, in `Pruebas`) and
the server's time limit (`RunCapturedEnContenedor` kills the renderer when it
runs out). It also puts it in a Job Object that kills the tree when it is
closed; without one the renderer does not run. A DUMMY measurement with the inner watchdog disabled
confirmed the outer 75-second deadline, stopped parent and child, a stationary child
counter and a responsive server. Omitting the job assignment left the child alive.
Job creation and assignment failure paths remain unmeasured.

## Outbound network policy (operator installation)

Rendering needs no network access, and its container has none: no firewall rule is
needed for it. The server never installs or modifies firewall policy.

Third-party components remain available. Design mode avoids application event
handlers, but loaded components still run their constructors and property setters,
as the IDE runs them when it opens a form - in the container, which is what bounds
them. A component that waits - a design-time connection with nothing to open, a
package that hangs while loading - ends at the helper's budget with `RENDER-007`
(measured 2026-10-14 with a `TFDConnection` set to `Connected = True` and no
database to open: 60 s, nothing written, no process left).

## Tests, in three layers

- **`tests/test_designer_preview.py`** (every `run_all`): `preview` through the
  server, against hand-made forms written into its jail - inherited forms,
  inline frames, crops, view states, styles, non-visuals, inline delivery,
  the refusals - checked by PIXEL.
- **`LspTests.FormRender`** in `src/UnitTests` (every `run_all`, through
  `delphi_test`): what launches nothing - the reader as the inverse of
  `FormRenderProtocolo.inc`, the composed command line and its refusals, and
  the non-visual criterion of `FormRender.Comun`.
- **`Pruebas/RenderTests.dproj`**, MANUAL, outside `run_all`: DUnitX that
  launches both exes the way the server does and checks the protocol, the
  exit codes and the pixels - including what neither layer above can: the
  watchdog's exit code 3 (`--timeout 1`), the usage exit code 2 and
  `--fidelity print` forced in a session with a desktop. It cannot run in
  `delphi_test`'s container (no windows can be created there), so it runs
  from the user's session: build it with `delphi_build` and start
  `Pruebas\Win64\Debug\RenderTests.exe`. **Run it after touching a renderer
  and before every release.** Its hand-made guinea pigs live in `Pruebas/`
  and must always pass; a second fixture with real-world forms (third-party
  packages, real styles) is registered only when `RENDER_COBAYAS`, or the
  first line of `render_cobayas.txt` next to the runner, names their folder
  - they are not in this public repository - and otherwise the runner says
  `NO MEDIDO` and leaves them out.
