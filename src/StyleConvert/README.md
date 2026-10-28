# `src/StyleConvert/` — the style converter

`DelphiStyleConvert.dproj` is a small console companion of the server: it
converts a VCL/FMX style between its text form (`.style`, what `delphi_styles`
reads and edits) and its binary form (`.bin.style`, what an application loads),
using the framework's own style classes. `delphi_styles command=build` runs it;
the server expects the exe **next to its own exe** and says so when it is
missing.

It ships in every release zip and in a deployment next to `DelphiLspMcp.exe`.
Build it with `delphi_build` or the group; output under `Compiled\Win32\Release`.
It is a 32-bit program on purpose, like the IDE: `totext` is then the IDE's own
text writer (floating-point values with 18 decimals; a 64-bit build writes 17),
and `delphi_styles set` asks it how a value is stored. Its binary output
(`tobin`) is the same byte for byte on both platforms.
