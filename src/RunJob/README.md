# `src/RunJob/` — the launcher PAServer starts on a target

`McpRunJob` is the small console program the server uploads with every remote
execution — `delphi_paserver remote-run` and every `delphi_desktop` gesture —
and that PAServer starts on the target machine. One source, two builds:
`McpRunJob` (Linux64, ELF) and `McpRunJob.exe` (Win64), both shipped in
[`node/`](../../node) next to the desktop nodes. `BuildGroup.bat Release`
compiles and copies both.

## Why it exists

`paclient` has no "execute with arguments" operation. What it has is a flag of
`--put` that makes PAServer **start the uploaded file, without arguments, and
wait for it to end** (measured 2026-09-22: flag 3 starts an ELF on Linux, flag 5
a PE on Windows; on Linux flag 5 is `/bin/sh file`, useless for a binary). So
the server uploads two things: `run-<job>.job` (UTF-8, one item per line: the
binary, the output file, then ONE ARGUMENT PER LINE) and this program named
`run-<job>` (Linux) or `run-<job>.exe` (Windows). PAServer starts it; it does
the rest and returns at once, so PAServer and `paclient` are free again.

Until 1.0.15 Linux went through a `/bin/sh` script composed by the server —
where the 1.0.15 command injection lived — and Windows through this program:
two writers, two readers, two branches. Since 1.0.16 both systems use the
launcher and **there is no shell anywhere in the path**: arguments go from the
job file to the program's argv untouched.

## What it does, in order

1. Reads and deletes its `.job` (found from its own name).
2. Writes `___ENV=` as the first line of the output. On Linux it completes the
   graphical environment that is MISSING — `XDG_RUNTIME_DIR`, the session D-Bus,
   `WAYLAND_DISPLAY`, `DISPLAY`, the newest `XAUTHORITY` — from the session of
   the user PAServer runs as (a PAServer running as a service is born without
   them). On Windows it reports the session it runs in (0 = a service, no
   desktop). The server turns that line into `graphicalEnv`.
3. Checks the binary's signature (ELF or MZ): only the program that project
   deployed runs, never a script sitting next to it. On Windows `<Project>` is
   accepted for `<Project>.exe`.
4. Starts it unattended, stdout+stderr into `<job>.out`, stdin from nothing.
5. Leaves a watcher that appends `___RC=<exit code>` when the program ends:
   on Linux a forked child (`fork` + `setsid`), on Windows a copy of itself
   (`<job>.wait.<pid>.exe` - the pid in the name survives a failed redeploy that wipes the `.pid` - because PAServer deletes `run-<job>.exe` the moment the
   launcher returns). The server sweeps finished watchers.

Nothing is installed on the target. Rebuilding belongs to whoever edits this
source; the copies in `node/` are what the server actually sends.
