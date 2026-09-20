# This repository is worked THROUGH its own MCP server

**Hard rule (David, 2026-09-20).** When working on this repo, an agent reads,
searches, edits, configures, builds and versions **through the `delphi_*` MCP
tools** — not through the generic file/shell tools — even when it happens to be
running on the very Windows machine that hosts Delphi and the server.

**Why.** The only real test of this product is being used as a client. On
2026-09-20 v1.0.0-beta shipped with `delphi_read` (the most used tool here),
`delphi_help` (the first call the manual tells an agent to make) and
`delphi_git status` answering `{"ok": true}` and **not one line of content** to
any MCP client that understands `structuredContent`. The suite was green: 51
batteries, 1293 checks, 0 failures — they speak the raw protocol and read
`content`, so not one of them could see it. Using the server as an agent found
it in the first call.

## What it means in practice

| Job | Tool |
| --- | --- |
| Read a source, its symbols, find text, list a folder | `delphi_read`, `delphi_symbols`, `delphi_search`, `delphi_list` |
| Edit Pascal / other text / several files at once | `delphi_edit`, `delphi_textedit`, `delphi_changeset` |
| Create a unit, form, project | `delphi_create` |
| Project settings, platforms, SDK, PAServer profile | `delphi_config` |
| Compile, run the tests of a project | `delphi_build`, `delphi_test` |
| Branches, diff, commit, tag, push | `delphi_git` |
| Linux / Android targets | `delphi_paserver`, `delphi_adb` |

If a tool makes a job harder than the shell would, **that is the bug to fix**,
not a reason to go around it: write it down or send it with `delphi_report`.

## The exceptions, and they are few

- **The whole project group** (`BuildGroup.bat`) and the **python batteries**
  (`tests/run_all.py`, `tests/release_check.py`) — the server builds projects,
  not its own group, and the batteries are the harness, not a client.
- **The release ritual** — it reads a credential file, and a credential never
  travels through a tool.
- **What is not Delphi work**: the knowledge vault and the server's own
  `settings.ini` (which lives outside the workspace roots). Neither belongs to
  these tools and neither counts as a gap.
- **Deploying the exe** to `C:\Delphi-mcp-Server\`. Production is closed and
  started **by David**. This is not a prohibition, it is a measured
  constraint: Claude Desktop ships as an MSIX package, and everything it
  launches inherits the package's private registry hive, so a server started
  by the agent stops seeing the operator's IDE - its SDKs and its profiles.
- **A wall.** If a tool genuinely cannot do the job, fix it the conventional
  way as a last resort and go straight back to the MCP — but **the wall IS the
  finding**: write down what you were doing, which tool you expected to do it,
  and what you did instead. That list is the roadmap.
- **The tray being down.** The agent talks to production over HTTP
  (127.0.0.1:3131), so with no tray there are no tools — getting it back is
  then the only job.
