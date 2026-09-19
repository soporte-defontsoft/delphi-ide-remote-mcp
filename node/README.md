# `node/` — the compiled Linux desktop node, ready to travel

`McpDesktopNode` is the **compiled Linux64 binary** of the desktop node
(sources: [`src_desktop_node/`](../src_desktop_node)). It ships in
every release zip and next to the server exe in a deployment, and you never
touch it by hand:

- With `delphi_adb_linux` and `project` empty (the normal case), the server
  **pushes this binary to each Linux target on first use** and stamps
  `node.ver` (its SHA-256) next to it.
- On every later session the stamp is compared **once per profile**; when this
  file changes (a server upgrade), the target heals itself on its next
  gesture — measured: 3.0 s for a gesture that also updated the node, 1.4 s
  warm.

GNOME targets only for now. Rebuilding it belongs to whoever edits the node's
sources — see the README in `src_desktop_node/`.
