This server exposes a KNOWLEDGE VAULT: Markdown notes linked with
[[wikilinks]], holding the conventions, patterns, decisions and current state
of the projects worked on here.

PROTOCOL, at the start of any task:

1. Call `vault_read` with NO path. It returns the vault rules and the index of
   notes.
2. Identify which project you are working on and load its
   `projects/<name>/context.md` and `progress.md`.
3. Load anything else only on demand, when the index says it applies. Lazy
   loading: never read the vault in bulk.

If you write to the vault, read `AGENTS-VAULT-WRITE.md` first and follow the
vault's own conventions.
