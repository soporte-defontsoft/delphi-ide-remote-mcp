# `src_linux_desktop_node/` — sources of the Linux desktop node

The **node** is the tiny Delphi console program that `delphi_adb_linux` runs on
the Linux target: the server's eyes and hands there. One short-lived process
per gesture — capture the desktop, convert the screen scale, press a pixel,
type text — launched through PAServer, nothing resident.

**GNOME only for today** (measured live on Zorin 18 and Fedora): capture goes
through the XDG desktop portal, input through libei, the scale comes from
Mutter. Nothing gets installed on the target: every system library is opened
at runtime.

| Unit | Role |
|---|---|
| `Mld.Dyn.pas` | Dynamic loading (`dlopen`/`dlsym`) — the node links NOTHING of the desktop at compile time |
| `Mld.DBus.pas` | The D-Bus session bus conversation: portals (screenshot, input) over `libdbus-1.so.3` |
| `Mld.Captura.pas` | The eyes, part two: grab the content and write the PNG **by hand** (no ImageMagick, no external tools) |
| `Mld.Eis.pas` | The hands: input injection through libei, fed by the descriptor D-Bus negotiated |
| `Mld.X11.pas` | The eyes, part one: enumerate windows via libX11 at runtime (replaces xdotool — one dependency fewer) |

**You normally never build this.** The compiled Release ships as
[`node/McpLinuxDesktop`](../node) inside every release zip, and the server
deploys/updates it on targets by itself (the `node.ver` SHA-256 stamp). Build
it only to work ON the node: from the IDE (needs the Linux64 SDK in the SDK
Manager) or `delphi_build platform=Linux64`, or raw msbuild adding
`/p:PlatformSDK=Linux64.sdk` — without that property the linker dies with
`cannot find -lgcc_s` (measured). After a rebuild, copy the Release binary
over `node/McpLinuxDesktop`: every provisioned target updates itself on its
next gesture.
