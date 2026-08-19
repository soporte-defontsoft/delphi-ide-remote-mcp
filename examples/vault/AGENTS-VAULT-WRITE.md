# How to write in this vault

Read this before creating a note. It answers one question: **where does this
go?** — and gives the templates.

## Decision tree

```
Something happened (a change, a fix, a decision taken)
   └─ Is it still true right now, and does someone need to act on it?
        ├─ YES → a line in projects/<name>/progress.md
        └─ NO, it is history → a dated entry in projects/<name>/log.md

Something we learned that will apply again
   └─ Is it about HOW we work (naming, structure, review, style)?
        ├─ YES → conventions/<topic>.md
        └─ NO → is it about WHY a project is the way it is?
             ├─ YES → projects/<name>/context.md
             └─ NO → decisions/<slug>.md (a standalone decision or finding)

A thing that did NOT work, and should not be tried again
   └─ decisions/<slug>.md, stating what was tried, what happened, and when
```

When two places seem right, prefer the more specific one and link the other
with a `[[wikilink]]`.

## Templates

**A project's `context.md`** — the stable "why". Changes rarely.

```markdown
# <Project> — context

## What it is
One paragraph a newcomer could understand.

## Why it exists
The problem it solves, and what was there before.

## Shape
The pieces and how they fit. Only what a reader must know to not break things.

## Decisions that stuck
- <decision> — because <reason> (<date>)
```

**A project's `progress.md`** — a snapshot. Only what is true today.

```markdown
# <Project> — progress

> Snapshot, not a diary. History lives in the log.

## In flight
- <what is being done right now>

## Blocked / waiting
- <what, and on whom or what>

## Next
- <the next thing, when it is decided>
```

**A project's `log.md`** — history. Append only, newest first.

```markdown
# <Project> — log

- **YYYY-MM-DD** — <what was done>. <what was learned or measured>. <what it means for next time>
```

**A convention or decision note**

```markdown
# <Title>

## Rule
The thing to do, in one sentence.

## Why
The reason, ideally with what went wrong when it was not followed.

## Exceptions
When this does not apply — or "none".
```

## Rules of thumb

- **Date everything** that could age. "Recently" means nothing in six months.
- **Write the measurement, not the impression.** Numbers and error messages
  survive; adjectives do not.
- **One idea per note.** If the title needs an "and", it is two notes.
- **Link generously.** A `[[wikilink]]` to a note that does not exist yet is
  fine — it marks something worth writing.
- **The index is not optional.** A new note that nobody indexed is lost.
