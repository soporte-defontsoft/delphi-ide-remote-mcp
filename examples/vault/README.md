# Starter vault

A working knowledge vault, ready to copy. Nothing here is specific to any
project or company — it is the *shape*, not the content.

## Use it

```bash
cp -r examples/vault ~/MyVault        # or copy the folder in Explorer
```

```ini
; settings.ini next to the executable
[Vault]
Path=C:\Users\you\MyVault
ReadOnly=1        ; 0 when you want the agent to write too
```

Restart the server. Connect an agent and it will be told, at connect time, that
a vault exists and to start with `vault_read` (no path). Try `/vault` in Claude
Code to see the bootstrap yourself.

## What is in here

| File | Role |
|---|---|
| `VAULT-INSTRUCTIONS.md` | **The skill.** Sent to the model on every connection (MCP `instructions`). Short on purpose: what this vault is and what to do first. Edit this to name your projects and your language. |
| `AGENTS-VAULT.md` | **The rules.** Returned by the bootstrap call. How to load, how to write, what never to touch. |
| `MEMORY.md` | **The index.** One line per note with what it is *for* — this is what the agent reads to decide what to load. |
| `AGENTS-VAULT-WRITE.md` | **Where things go.** Decision tree + templates, read before creating a note. |
| `conventions/example-conventions.md` | A convention note, as an example of shape. |
| `projects/example-project/context.md` | Per-project context: the stable "why". |
| `projects/example-project/progress.md` | Per-project **snapshot**: only what is true today. |
| `projects/example-project/log.md` | Per-project **history**: dated entries, append-only. |

The `context` / `progress` / `log` split is the part worth keeping: a snapshot
that stays small because it is pruned, and a log that grows because it is never
rewritten. Without it, one file tries to be both and becomes unreadable.

## Growing it

Do not try to fill this in up front. The rule that works: **whenever you find
yourself explaining the same thing to an agent for the second time, that is a
note.** Write it, index it in `MEMORY.md`, move on.

The three governance files (`AGENTS-VAULT.md`, `AGENTS-VAULT-WRITE.md`,
`MEMORY.md`) are never writable by an agent — the server refuses. You curate
those; the agent fills in the rest.

Full explanation of how the vault works: [../../docs/VAULT.md](../../docs/VAULT.md).
