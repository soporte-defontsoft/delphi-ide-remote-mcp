# `src/StyleConvert/` — the style converter

`DelphiStyleConvert.dproj` is a small console companion of the server: it
converts an FMX style between its text form (`.style`, what `delphi_styles`
reads and edits) and its binary form (`.bin.style`, what an application loads),
using FMX's own style classes. Its orders - `tobin`, `totext`, `defaults` (the
Windows platform style, as text) and `check` (what FMX ignores when it loads a
text style) - and the words of its output live in `StyleConvertProtocolo.inc`;
its first line is `PROTOCOL=<n>` (`SC_PROTOCOLO_VERSION`), and a converter that
states another one is refused (`STYLE-066`). `delphi_styles` `build`, `lint`,
`set` and the platform defaults run it, and so does an edit of a `.style`. The
server expects the exe **next to its own exe** and says so when it is missing;
it runs the copy in the helpers' box, inside a Windows container with no
capabilities, on a copy of the style in a folder of that call (`STYLE-065`
when that container cannot be prepared).

It ships in every release zip and in a deployment next to `DelphiLspMcp.exe`.
Build it with `delphi_build` or the group; output under `Compiled\Win32\Release`.
It is a 32-bit program on purpose, like the IDE: `totext` is then the IDE's own
text writer (floating-point values with 18 decimals; a 64-bit build writes 17),
and `delphi_styles set` asks it how a value is stored. Its binary output
(`tobin`) is the same byte for byte on both platforms.
