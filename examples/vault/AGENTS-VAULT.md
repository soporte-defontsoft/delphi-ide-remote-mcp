# Vault rules

Read in full at the start of every session, together with the index
([[MEMORY]]). Keep this file short — it is the one thing always loaded.

## Loading

1. **Lazy loading.** This file plus the index first; then only the notes the
   index says apply to your task. Never read the vault in bulk — the point of
   the index is that you do not have to.
2. **Project first.** If the task is about a project, its
   `projects/<name>/context.md` (the stable why) and `progress.md` (what is
   true today) come before anything else.
3. **Follow the links.** `[[Wikilinks]]` point at other notes. Resolve them
   with `vault_search target=files` when a note tells you to.
4. **The vault is the authority on conventions**, not your habits. When a note
   contradicts what you would do by default, the note wins.

## Writing

5. **Language.** Write notes in the same language the vault is written in, no
   matter what language the conversation is in.
6. **`log.md` is history**: dated entries, append only. Never rewrite or
   reorder past entries — being able to trust the record is the whole point.
7. **`progress.md` is a snapshot**: only what is true *today*. Closing an item
   means **removing its line** (`vault_patch`), not adding "done" under it. If
   it needs remembering, it belongs in the log.
8. **New notes get indexed.** A note nobody can find does not exist. Add its
   line to the index — and if you cannot (the index is human-curated), say so
   explicitly in your answer so a person does it.
9. **Prefer appending over rewriting.** If a note needs restructuring, stop and
   ask. Accumulated knowledge is expensive; a bad rewrite is invisible damage.
10. **Facts, not conclusions.** Write what happened and what was measured, with
    dates. "It failed because X, measured on 12 Mar" ages far better than "X is
    slow".

## Never

11. Do not reorganize folders or move existing notes without a human OK.
12. Do not touch the governance files ([[MEMORY]], this one, and
    [[AGENTS-VAULT-WRITE]]) — the server refuses anyway.
13. Do not record secrets: tokens, passwords, keys or personal data.
