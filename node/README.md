# `node/` — the compiled desktop nodes, ready to travel

> **These binaries do not work on their own.** Both of them require a key that
> the MCP server passes when it calls them; run one by hand and it prints what
> it is and exits without capturing or pressing anything. They are the server's
> arms, not a standalone screenshot tool. (It is a latch, not a lock: the node
> runs as the same user who could execute it and the key ships inside the
> binary — it stops accidents and stray scripts, not a determined local user.)

`McpDesktopNode` is the **compiled Linux64 binary** of the desktop node and `McpDesktopNode.exe` the Win64 one - the target gets the one that fits its PAServer profile
(sources: [`src/DesktopNode/`](../src/DesktopNode)). `McpRunJob` and `McpRunJob.exe` are the **native launcher** for Linux and Windows targets (one source: [`src/RunJob/`](../src/RunJob)): PAServer starts an uploaded file only without arguments and waits for it, so for every remote execution - `remote-run` and every desktop gesture - the server sends this program as `run-<job>` next to a job file (binary, output, then one argument per line); it completes the graphical environment when missing, checks the binary is native, starts it unattended with the arguments as argv, leaves a watcher that writes the exit code, and returns. No shell anywhere. It ships in
every release zip and next to the server exe in a deployment, and you never
touch it by hand:

- With `delphi_desktop` and `project` empty (the normal case), the server
  **pushes the right binary to each target on first use** and stamps
  `node.ver` (its SHA-256) next to it.
- On every later session the stamp is compared **once per profile**; when this
  file changes (a server upgrade), the target heals itself on its next
  gesture — measured: 3.0 s for a gesture that also updated the node, 1.4 s
  warm.

GNOME targets only for now on Linux; on Windows the PAServer must run inside the
user's session. Rebuilding belongs to whoever edits the sources — `BuildGroup.bat
Release` compiles the four (two projects, each for Linux and for Windows) and copies them here.
None of the four is versioned (since 2026-09-24): they are build output, and
`tests/release_check.py` refuses to package one that is missing or older than
its sources, so a release always carries binaries of the code it publishes.
