# `tests/` — the regression batteries and the release gate

Python end-to-end batteries that drive the **built server binary** exactly like
an MCP client would (stdio JSON-RPC or HTTP), plus the release gate:

- `run_all.py` — runs every `test_*.py` against a **copy** of the exe (so
  batteries that plant a `settings.ini` next to it never pollute the build)
  and prints one summary line, `== N baterias | N checks OK | N fallos | N baterias
  rojas | N notas ==`, then what batteries say they did NOT measure (NOTA/SKIP).
  `-k <substring>` runs only the matching ones; a battery that measured nothing
  and says nothing counts as red.
- `release_check.py` — the gate: version sources agree, the exe embeds the
  version, docs are coherent, `skills/SKILL.md` ends with the mark of the
  version whose contract was reviewed, the regression is green, and it packages the
  release zip with its SHA-256. `--skip-regression` only packages again right
  after a full run of it passed (as a release does after its commit), never in
  place of that full run.
- `rendertests_manual.py` — the manual battery of the form renderers
  (`src/Render/Pruebas`), run from the user's session after touching a renderer
  and before every release; a red pass keeps its output in `release-out`.
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
