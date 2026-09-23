# Agent guide — how to use this server well

The agent's manual is [skills/cmcpdelphiide/SKILL.md](../skills/cmcpdelphiide/SKILL.md).
Give it to the agent as a skill, or paste it into its instructions (`CLAUDE.md`,
`AGENTS.md`, system prompt). It is written FOR the model, not for humans. Full
parameter reference: [TOOLS.md](TOOLS.md).

The short version:

1. **First call `delphi_workspace`** — roots, access level, virtual drives, which
   Delphi. **Then `delphi_help`** for the map of the tools. And **identify
   yourself**: `clientInfo.name` = your agent id, or `agent=<id>` on every
   `delphi_report` / `delphi_messages` call (a generic client name leaves
   your mail unread).
2. **Nothing executes on the server** except a test project through `delphi_test` (`AllowTests`); a program runs on a target through `delphi_paserver remote-run`.
3. **Nothing is hard-deleted**: `delphi_delete` moves to the trash and `delphi_move`
   restores from it. The one exception is `delphi_delete purge=true`, which is
   allowed only inside the trash.
