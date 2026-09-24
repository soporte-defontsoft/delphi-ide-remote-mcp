# `src/DesktopNode/` — sources of the desktop node

The **node** is the tiny Delphi console program that `delphi_desktop` runs on
the target - a Linux or a Windows behind a PAServer profile: the server's eyes
and hands there. One short-lived process
per gesture — capture the desktop, convert the screen scale, press a pixel,
type text — launched through PAServer, nothing resident.

**It was developed entirely through the MCP server it now serves**: an AI
agent wrote these units, compiled them for Linux64, deployed them over
PAServer and debugged them against live Zorin and Fedora desktops — without
ever sitting at the Windows machine. Every trap documented in the unit
headers (the portal's mute timeout, libei's handshake, the PNG written by
hand) was measured through that same remote loop. Dogfooding, start to
finish.

**One program, two desktops.** The same `.dpr` and the same commands build
for Linux and for Windows; an `{$IFDEF}` picks who it talks to underneath, and
adding a third system means writing its unit plus its `Ejecutar<System>` and
hanging it off the same dispatch:

- **Linux** (GNOME only for today, measured live on Zorin 18 and Fedora):
  capture through the XDG desktop portal, input through libei, scale from
  Mutter, every system library opened at runtime.
- **Windows** (`Mld.Win.pas`): GDI for the eyes and `SendInput` for the hands,
  both already in the system — nothing to load, nothing to install. It grabs
  the whole virtual desktop (every monitor), so the caller still measures on
  the image and knows nothing about monitors or scaling.

Nothing gets installed on the target in either case, and the output contract
is identical: coordinates are pixels OF THE CAPTURE and the node answers with
`CAPTURA=<path>`.

| Unit | Role |
|---|---|
| `Mld.Dyn.pas` | Dynamic loading (`dlopen`/`dlsym`) — the node links NOTHING of the desktop at compile time |
| `Mld.DBus.pas` | The D-Bus session bus conversation: portals (screenshot, input) over `libdbus-1.so.3` |
| `Mld.Captura.pas` | The eyes, part two: write the PNG **by hand** (no ImageMagick, no external tools). The writer is SHARED: X11 and a Windows DIB both hand over BGR pixels |
| `Mld.Eis.pas` | The hands: input injection through libei, fed by the descriptor D-Bus negotiated |
| `Mld.Teclado.pas` | The keymap the desktop really has: which key gives each character directly, and which dead key plus base letter composes the rest (`í` = dead_acute + `i`), from Unicode's canonical decomposition |
| `Mld.X11.pas` | The eyes, part one: enumerate windows via libX11 at runtime (replaces xdotool — one dependency fewer) |
| `Mld.Win.pas` | Windows: eyes (GDI capture of the virtual desktop), hands (`SendInput`: click, Unicode typing, key combos) and the window list, with DPI awareness asked for at runtime |

**It only answers the server.** Both builds require a key that the MCP server
passes as the first argument (`NodeKey.inc`, included by the node and by the
server so the two cannot drift). Launched by hand it prints what it is and
exits, touching nothing. Be honest about what that buys: the node runs as the
same user who could run it, and the key lives inside the binary, so this is a
latch against accidents and careless scripts — not a lock against someone with
access to the machine and an interest in opening it.

**You normally never build this.** The compiled Release ships as
[`node/McpDesktopNode`](../../node) (Linux) and `node/McpDesktopNode.exe` (Windows) inside every release zip, and the server
deploys/updates it on targets by itself (the `node.ver` SHA-256 stamp). Build
it only to work ON the node: from the IDE (needs the Linux64 SDK in the SDK
Manager) or `delphi_build platform=Linux64`, or raw msbuild adding
`/p:PlatformSDK=Linux64.sdk` — without that property the linker dies with
`cannot find -lgcc_s` (measured). After a rebuild, copy the Release binary
over `node/McpDesktopNode`: every provisioned target updates itself on its
next gesture.
