# Agent guide — how to use this server well

Paste this file (or its rules) into your agent's context (`CLAUDE.md`, `AGENTS.md`,
system prompt) when it works against this MCP server. It is written FOR the model,
not for humans. Full parameter reference: [TOOLS.md](TOOLS.md).

## Golden rules

1. **Call `delphi_workspace` first**, once per session. It tells you the roots you can
   touch, the extra read-only zones (Delphi RTL/VCL sources), and your access level.
2. **Paths are virtual**: `srvd:\...`, `srvc:\...`. They are drive units of the REMOTE
   machine, not yours. Never invent local paths (`/home/...`, `C:\Users\you\...`) and
   never "translate" a `srvd:` path to a real one — use them verbatim in both directions.
3. **Prefer semantic tools over text search.** This server wraps the official DelphiLSP
   engine — the same compiler-grade resolver the IDE uses. Text search is the fallback,
   not the default:

   | You want | Use | Not |
   |---|---|---|
   | Where is this symbol used? | `delphi_references` | `delphi_search` |
   | Where is it defined/declared? | `delphi_definition` | `delphi_search` |
   | What type/doc is this? | `delphi_hover` | reading the whole unit |
   | Outline of a unit | `delphi_symbols` | `delphi_read` of everything |
   | Is the unit broken? | `delphi_diagnostics` | guessing from text |
   | Find a literal string / comment | `delphi_search` | (this IS its job) |

4. **Positions are 0-based** (line and character), LSP-style. Point *inside* the
   identifier, not at its first character boundary.
5. **A Delphi method exists twice** (interface declaration + implementation body).
   `delphi_definition` has a `kind` parameter to pick which one you want.
6. **Edit safely**: `delphi_edit` is anchored (exact old text -> new text). Read the
   real lines first, copy the anchor literally, keep it small and unique. After editing,
   verify with `delphi_diagnostics` and, when it matters, `delphi_build`.
7. **Build before run.** `delphi_run` executes compiled output inside a sandbox
   (low-integrity: it can only write to its own folder). If the response says
   `sandbox=NO`, say so in your report.
8. **Deletes are recoverable**: `delphi_delete` moves to a trash folder and returns the
   trash path; `delphi_move` can restore from it. Nothing is ever hard-deleted.
9. **Read-only mode is real.** With a read-only credential every mutating tool is
   refused at the single entry gate. Don't retry variations — report what you needed.
10. **Something wrong or missing?** Send it with `delphi_report` (works even in
    read-only). One short message per issue; it reaches the server operator as a file.

## Typical session

```
delphi_workspace                      -> roots, access level, virtual drives
delphi_projects / delphi_list        -> find the project and files
delphi_symbols / delphi_definition / delphi_references   -> understand
delphi_edit -> delphi_diagnostics -> delphi_build         -> change safely
delphi_run                            -> execute (sandboxed)
delphi_git                            -> commit
```
