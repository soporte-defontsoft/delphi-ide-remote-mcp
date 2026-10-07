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
  MACHINE PATH, so a server running as a Windows service finds them too
  (measured); without them Windows cannot start the renderer and the server
  answers `DSGN-063`.
- Nothing else. The standard palette (Standard, Additional, Win32, Dialogs,
  WinX, action bands, samples) is registered from the renderer's own `uses`,
  as the IDE does with the form it creates. Every other class — data
  controls, third parties, the user's own packages — comes from the IDE's
  Known Packages, loaded **at run time and only when the file names a class
  the palette does not know** (`--packages auto`). Installing a package in
  the IDE is all it takes for the renderer to see it.

## Command line (one switch per `preview` parameter)

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
                    [--bds 37.0] [--timeout ms] [--verbose]
DelphiFormRenderFmx --path <fmx> --out <png> [--state ...]* [--component Name]
                    [--style <file.style>|none|windows|win7|win8|win10|win11|mobile|android|ios|ios-dark|osx|linux|gnome]
                    [--nonvisual on|off] [--packages ...] [--root ...] [--bds] [--timeout] [--verbose]
```

- `--state`: a view state applied through RTTI after the form is built and
  shown, never written to the file: `PageControl1.ActivePage=TabSheet2`,
  `Edit1.Text=hello`. A class-typed value names a component.
- `--component`: the renderer answers `RECT=<name>=l,t,w,h` in PNG pixels;
  the server crops with its own cropper (`Lsp.Imagen.RecortaPng`).
- `--nonvisual on` (the renderer's default, like the designer's "Show
  non-visual components"): each non-visual component is drawn at the
  Left/Top the file stores, with the icon its package ships
  (`<CLASS>128_PNG` resource) or the class initials, and its name
  underneath. The server passes `off` unless the agent asks: what a model
  needs is to know they exist, and `NONVISUALS=` lists them either way.
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

## Output (stdout, `KEY=value` lines; the keys live in `FormRenderProtocolo.inc`)

```
DPI=96                        the process is DPI-unaware: 1 pixel = 1 dfm unit
SESSION=<n>                   0 = a service
STYLE=<what was applied>
ROOT=<Name>:<Class>:<form|frame>
PACKAGES=<loaded>/<known>     0/0 = the palette was enough
COMPONENTS=<n>
SUBSTITUTED=<classes>         not found in any package: pink box with the name
IGNORED=<reader error>        repeatable
WARNING=<text>                repeatable
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
ERROR=<text>                  with exit code 1 (3 = timeout, 2 = usage)
```

What reaches the agent in `ERROR=` and `WARNING=` lives in
`FormRender.Textos`, the renderers' message catalog (area `RENDER`, English,
the tag first: `tests/test_catalogo.py` checks it with the server's and the
node's). A refusal of ours (a `--state` that names nothing, an unknown
platform style) goes out tagged and the server passes it through as it is;
anything else comes out as `<class>: <message>`.

Nothing reaches the desktop: the form is created in design mode (no code
runs, events are ignored), FMX's dialog services are removed on start,
`Application.OnException` records instead of showing, and the watchdog kills
a render that waits on anything.

## What a form file can and cannot do to the renderer

The code the renderer loads is fixed by the machine, never by the file: its runtime BPLs,
and - only when the file names a class the standard palette does not know - the design
packages registered in the IDE (HKCU Known Packages, all of them, their initialization
included; the file can trigger that load, it cannot choose or add a package). BPLs opened
for icons and platform styles are opened as data: nothing of theirs runs. TReader creates
registered classes only; an unknown class becomes a labelled substitute. Every path involved
comes from the server through its read gate: the form, its sibling .pas and .dfm/.fmx files
in the same folder (links are skipped), a style file.

What a hostile file CAN do is feed bad values and binary blobs (pictures, image lists,
collections) to the loaded classes and crash or stall the renderer. That is why it runs as a
process of its own, with its watchdog and the server's own time limit, and why the server
answers with the error instead of dying with it. A deeper adversarial pass is listed for
1.18.0.

**Cleanup: what is measured and what is not.** The renderer starts no
processes of its own. Measured: its watchdog (exit code 3, in `Pruebas`) and
the server's time limit (`RunCapturedIn` kills the renderer when it runs
out). `RunCapturedIn` also puts it in a Job Object that kills the tree when it
is closed; that part is best-effort (if the job cannot be created the
renderer runs without one) and, for the renderer, not measured.

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
