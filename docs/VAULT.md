# The knowledge vault — persistent memory for your agents

**Optional.** Everything in this document is off unless you set `[Vault] Path`.
Without it the `vault_*` tools are not registered at all and the server is
purely a Delphi build server.

## The problem it solves

An agent working through this MCP can read your code, but it starts every
session knowing nothing about *your* decisions: why that unit is structured
that way, which conventions your team follows, what was already tried and
rejected, where a project stands today. That knowledge usually lives in your
head, in a chat that scrolled away, or in a notes app the agent cannot reach —
and on a remote setup (agent on Linux, compiler on Windows) it is doubly out of
reach, because the agent has no filesystem access to the machine at all.

A vault is simply **a folder of Markdown notes** — the format Obsidian uses,
linked with `[[wikilinks]]`. Point the server at it and the agent gains a
memory it can consult, and optionally write to.

## The design: mechanism here, doctrine in the vault

This is the part worth copying even if you build your own:

- **The server provides the mechanism.** Search, read, append, create, anchored
  patch — plus every rule that can be enforced by code: the jail, `.md` only,
  governance files protected, and an automatic backup before any modification.
- **The vault provides the doctrine.** Its rules live *inside itself*, in
  `AGENTS-VAULT.md`. Its index, `MEMORY.md`, says what each note is for. None
  of your conventions are hardcoded in the server, so two people can point this
  at two completely different vaults and each gets their own rules.

Anything the model must merely *remember* eventually gets forgotten; anything
the server *enforces* holds every time. So the split is deliberate: doctrine
where a human can edit it, enforcement where a model cannot skip it.

## The loading protocol: lazy, never in bulk

The agent is told (in the tool descriptions themselves) to start every task
with `vault_read` **with no path**. That returns, in one call:

```
===== AGENTS-VAULT.md =====     the vault's own rules
===== MEMORY.md =====           the index: one line per note, with what it is for
```

From the index descriptions it decides which notes are worth loading, and pulls
only those with `vault_read`. The vault is never read in bulk — that is what
keeps a large accumulated memory usable inside a limited context window. Notes
reference each other with `[[wikilinks]]`; the agent resolves those with
`vault_search target=files`.

The two bootstrap filenames are a vault convention, not something a remote
agent should have to know in advance — hence the no-path call.

## The tools

| Tool | What it does |
|---|---|
| `vault_read` | Read a note by relative path, with line numbers and optional `offset`/`limit`. **No path = bootstrap** (rules + index). |
| `vault_search` | `target=files` (glob over note names) or `target=content` (regex inside notes, returns path + line number + line). Optional `subfolder`. |
| `vault_append` | Append to an existing note — a dated log entry, a progress line. Optional `anchor`: insert after a unique fragment instead of at the end. |
| `vault_create` | Create a new note. **Never overwrites**: an existing path is refused. |
| `vault_patch` | Replace `old_text` (which must appear **exactly once**) with `new_text`. For closing a line in a progress file or fixing a fact. |

Reading is available to read-only credentials. The three write tools need
`ReadOnly=0` **and** a read-write credential.

## What writing deliberately cannot do

There is no wholesale rewrite, no delete, no move, no git. `append` and
anchored `patch` cover essentially all day-to-day work — a dated log entry, a
progress line, a new decision note — without ever handing a model the ability
to destroy accumulated knowledge. If a task genuinely needs a restructure, the
right answer is a human doing it, and the tools say so.

On top of that:

- **Automatic backup.** Before modifying any note the original is copied to
  `backups/mcp/<timestamp>/<relative-path>` inside the vault. No parameter
  disables it. The first copy in a run is the one kept, so what is preserved is
  always the state before the session touched it.
- **Governance files are read-only**, always: `AGENTS-VAULT.md`,
  `AGENTS-VAULT-WRITE.md` and `MEMORY.md`. The rules and the index are curated
  by a human. An agent that needs a new note indexed says so in its answer.
- **Strict jail**: relative paths only, no drives, no `..`, `.md` only, and
  `backups/`, `.git/`, `.obsidian/`, `.claude/` and `*.bak*` are excluded from
  both reads and searches.
- **UTF-8 in, UTF-8 without BOM out.** A vault is UTF-8; none of the CP1252
  machinery used for Delphi sources applies here.
- **Long notes are truncated** at 100 000 characters with a note telling the
  agent to page through with `offset`/`limit`, so one huge file cannot eat the
  context window.

## Setting it up

```ini
[Vault]
Path=D:\Vaults\MyKnowledge
ReadOnly=1          ; 0 to also allow append/create/patch
```

Or the environment variables `DELPHI_MCP_VAULT_PATH` and
`DELPHI_MCP_VAULT_READONLY`, which take precedence.

Start with `ReadOnly=1`. Give an agent read access for a while, see what it
looks up and what it wishes it could record, and only then decide whether to
let it write.

## What the agent is told, and when

You do not have to teach an agent any of this — the server does it:

1. **On connect**, the MCP `initialize` response carries `instructions`: there
   is a vault, and the first call should be `vault_read` with no path. Short on
   purpose, because instructions ride along in every prompt.
   A vault can replace that text with its own by putting a
   **`VAULT-INSTRUCTIONS.md`** at its root — that file is the vault's "skill",
   where it names its projects, its language and anything specific to it.
   Without the file, a generic protocol text is used.
2. **On the first call**, `vault_read` (no path) returns the rules and the
   index — everything the agent needs to choose what to load.
3. **Any time**, the user can invoke the `vault` prompt (it appears as
   `/vault` in Claude Code) to reload rules + index mid-session, or to force
   the bootstrap on a client that ignores instructions.

## Starting a vault from scratch

**There is a ready-made starter vault in [`examples/vault/`](../examples/vault/)** —
copy the folder, point `[Vault] Path` at it and you have a working vault with
the rules, the index, the write guide and example `context`/`progress`/`log`
notes. It is deliberately generic: it shows the shape, not anyone's content.

If you prefer to start from nothing, you need two files at the root; everything
else is up to you.

**`MEMORY.md`** — the index. One line per note, and the description is what the
agent uses to decide whether to load it, so write it for that purpose ("what
would make me open this file?") rather than as a title:

```markdown
# MEMORY

- [Delphi conventions](conventions/delphi.md) — naming, units layout, what we never do
- [Billing module](projects/billing/context.md) — why it is split in two services
- [Rejected ideas](decisions/rejected.md) — approaches already tried that did not work
```

**`AGENTS-VAULT.md`** — the rules, written as instructions to the agent. Keep
it short enough to be read in full at every bootstrap. The kind of thing that
belongs here:

```markdown
# Rules

1. Load lazily: read this file and the index, then only the notes you need.
2. Write in the language of the vault, not the language of the conversation.
3. `log.md` is history: dated entries, append only.
4. `progress.md` is a snapshot: live status lines only. Closing something means
   removing its line, not adding "done".
5. Every new note gets linked from the index. Say so if you cannot do it.
```

Then grow it from real work: whenever you find yourself explaining the same
thing to an agent a second time, that is a note.
