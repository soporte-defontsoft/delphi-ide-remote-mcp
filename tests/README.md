# `tests/` — the regression batteries and the release gate

Python end-to-end batteries that drive the **built server binary** exactly like
an MCP client would (stdio JSON-RPC or HTTP), plus the release gate:

- `run_all.py` — runs every `test_*.py` against a **copy** of the exe (so
  batteries that plant a `settings.ini` next to it never pollute the build)
  and prints one summary line: `74 baterias | N checks OK | N fallos`.
- `release_check.py` — the gate: version sources agree, the exe embeds the
  version, docs are coherent, the regression is green, and it packages the
  release zip with its SHA-256. `--skip-regression` when a full run just
  passed.
- `paclient_stub.py` — a fake `paclient.exe` (via `DELPHI_MCP_PACLIENT`) that
  starts the real native launcher (`node/McpRunJob.exe`) on the uploaded job
  file, exactly as PAServer would (`--put` flag 3 on Linux, 5 on Windows), so
  `remote-run` is tested end-to-end without a live PAServer.

Since v0.98 every battery declares its world explicitly, like any client:
stdio batteries declare their jail in the environment (`DELPHI_MCP_ROOTS` and
friends — the launch workspace), HTTP batteries write a
`[Workspace.Bateria]` section next to their exe copy and authenticate with
its token, and adb batteries declare their devices. There is no open mode to
lean on — the tests live under the same contract they verify.
