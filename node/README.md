# `node/` — the compiled desktop nodes, ready to travel

> **These binaries do not work on their own.** Both of them require a key that
> the MCP server passes when it calls them; run one by hand and it prints what
> it is and exits without capturing or pressing anything. They are the server's
> arms, not a standalone screenshot tool. (It is a latch, not a lock: the node
> runs as the same user who could execute it and the key ships inside the
> binary — it stops accidents and stray scripts, not a determined local user.)

`McpDesktopNode` is the **compiled Linux64 binary** of the desktop node, and `McpDesktopNode.exe` the Win64 one that `delphi_desktop` runs on the server itself
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
