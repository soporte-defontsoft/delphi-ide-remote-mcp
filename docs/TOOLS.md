# Tool reference

Every tool this MCP server exposes, with its parameters, types and access level.

> **This page is written by hand and it does drift.** It used to claim it was generated from `tools/list` "so it never drifts from the code", and an audit on 2026-09-20 found it missing the headline features of three releases (`delphi_edit`'s `edits`, `delphi_search`'s `offset`, `delphi_list`'s `includetrash`, `delphi_test`'s `platform`, `delphi_changeset`'s `unstage` — all documented below since 2026-09-22). The authority is the server itself: **`delphi_help command=tool name=<tool>`** returns the live schema of one tool, and `docs/CAPABILITIES.json` IS generated from `tools/list`. When this page and the server disagree, the server is right.

- **Paths** use virtual drive units (`srvd:\...`, `srvc:\...`) — call `delphi_workspace` first to learn the roots.
- **Positions** for the semantic tools are 0-based (line and character), like the LSP. Point *inside* the identifier. Every answer that names a location also carries the 1-based line next to it (`line1` in definition, hover, signature, references and diagnostics; `line` + `line0` in symbols, search and rename): the 1-based one is what `delphi_read` shows and `delphi_edit` takes.
- **Access**: with a read-only credential only the read-only tools run; mutating ones are refused at the gate. Without a workspace token there is no access at all (HTTP 401; a tokenless local stdio process is read-only).
- **Required column**: every schema carries its real `required` list (the same one `delphi_help command=tool` returns); the table below says the same — the rest are optional and have sensible defaults, as their descriptions note.


> **Parameter aliases.** Some spellings are accepted as aliases and mapped to the declared name when it is absent: `vault_search query|filter` → `pattern`, `delphi_list filter|mask` → `pattern`, `delphi_components pattern|query` → `filter`, `delphi_read startline|endline` → `fromline|toline`, `delphi_search text` → `query`. The declared name always wins.

## Index

- **Understand the code (semantic, DelphiLSP-backed)** — [`delphi_symbols`](#delphi_symbols), [`delphi_definition`](#delphi_definition), [`delphi_signature`](#delphi_signature), [`delphi_hover`](#delphi_hover), [`delphi_completion`](#delphi_completion), [`delphi_references`](#delphi_references), [`delphi_diagnostics`](#delphi_diagnostics)
- **Read files & explore** — [`delphi_read`](#delphi_read), [`delphi_search`](#delphi_search), [`delphi_list`](#delphi_list), [`delphi_projects`](#delphi_projects), [`delphi_installs`](#delphi_installs), [`delphi_workspace`](#delphi_workspace)
- **Edit code safely  (read-write only)** — [`delphi_edit`](#delphi_edit), [`delphi_textedit`](#delphi_textedit), [`delphi_create`](#delphi_create)
- **Manage files  (read-write only)** — [`delphi_delete`](#delphi_delete), [`delphi_move`](#delphi_move)
- **Build, package  (read-write only)** — [`delphi_build`](#delphi_build), [`delphi_package`](#delphi_package)
- **Cross-platform: build configs, remote platforms & devices** — [`delphi_config`](#delphi_config), [`delphi_paserver`](#delphi_paserver), [`delphi_adb`](#delphi_adb), [`delphi_desktop`](#delphi_desktop), [`delphi_components`](#delphi_components)
- **FMX styles** — [`delphi_styles`](#delphi_styles)
- **Transfer files** — [`delphi_fetch`](#delphi_fetch), [`delphi_upload`](#delphi_upload)
- **Several files in one transaction** — [`delphi_changeset`](#delphi_changeset)
- **Rename a symbol (preview, then apply)** — [`delphi_rename_symbol`](#delphi_rename_symbol)
- **Forms & designers** — [`delphi_designer`](#delphi_designer)
- **Run the tests of a project** — [`delphi_test`](#delphi_test)
- **The map, and the house rules** — [`delphi_help`](#delphi_help)
- **Version control** — [`delphi_git`](#delphi_git)
- **Feedback** — [`delphi_report`](#delphi_report), [`delphi_messages`](#delphi_messages)
- **Knowledge vault (optional)** — [`vault_read`](#vault_read), [`vault_search`](#vault_search), [`vault_append`](#vault_append), [`vault_create`](#vault_create), [`vault_patch`](#vault_patch)


## Understand the code (semantic, DelphiLSP-backed)

### `delphi_symbols`

Document symbol tree of a Delphi unit (classes, methods, properties, sections) with 0-based ranges, straight from the official DelphiLSP engine. Works even without project settings. Big trees come back as a compact summary by default (`mode`/`filter` control it); a FOLDER answers with the interface digest of every unit inside. The engine parses as the COMPILER would for Windows: code inside an inactive `{$IFDEF}` (LINUX, ANDROID, MACOS...) is not in the tree, and nothing says so - for those blocks use `delphi_search` or `delphi_read`.

**Since v1.0.7 each symbol also carries `decl`: the declaration as it is WRITTEN IN THE SOURCE.** DelphiLSP's `name` is not a name, it is a rendered signature, and it is lossy — `function Alta(const A: string; B: Integer = 0): Boolean` comes back as `Alta(const A: string; B: Integer)` and `FBuffer: array [0..7] of Byte` as `FBuffer: Byte`. The tree, the kinds and the lines are still the language server's; only the way a declaration is written is read from the file.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) — or a folder for the per-unit interface digest |
| `mode` | string | optional | File only: `summary` = the skeleton (each section with its members and line; containers say how many they hold), `full` = the complete LSP tree with ranges. Empty = automatic: full when the tree is small, summary when it is big (the answer says which and how much the full one weighed) |
| `filter` | string | optional | Name search inside a file's tree (substring, case-insensitive): returns ONLY the matching symbols, each with its clean `name`, the real `decl`, kind, line, line0 and container. Ignores `mode`. The cheap way to find one method without the whole tree. It matches the NAME, not the signature: to search text inside sources use `delphi_search` |

### `delphi_definition`

Resolve the identifier at a 0-based line:character position in a Delphi source file, using the official DelphiLSP engine (compiler-grade, cross-unit, including RTL/VCL sources). Point INSIDE the identifier. kind selects the half of the unit (a Delphi method exists in BOTH): definition (default) = the BODY in the implementation section; declaration = the interface declaration OF THE TARGET SYMBOL (on a call site the tool chains definition->declaration, so you get the callee, never the enclosing method). (kind=implementation is accepted but DelphiLSP answers it like declaration - measured.) Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `kind` | string | optional | Optional: definition (default) \| declaration (jump to the interface declaration) \| implementation (jump to the method body) |
| `line` | integer | **yes** | Zero-based line number of the identifier |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier |
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) |

### `delphi_signature`

Signature help (parameter completion) for the call under a 0-based line:character position: the routine signatures with their parameter list, from the official DelphiLSP engine - the IDE's Ctrl+Shift+Space. Point INSIDE the parentheses of the call (right after "(" or a ","). Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `line` | integer | **yes** | Zero-based line number of the identifier |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier |
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) |

### `delphi_hover`

Type/signature information for the identifier at a 0-based line:character position (official DelphiLSP engine). IMPORTANT: hover answers on identifier USAGES (call sites, type references); hovering a declaration itself returns null. Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `line` | integer | **yes** | Zero-based line number of the identifier |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier |
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) |

### `delphi_completion`

Code completion candidates at a 0-based line:character position (official DelphiLSP engine). Returns at most 50 items (label/kind/detail) plus the total count.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `trigger` | string | optional | Optional trigger character, e.g. "." (empty = manual invocation) |
| `line` | integer | **yes** | Zero-based line number of the identifier |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier |
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) |

### `delphi_references`

Find references to the identifier at a 0-based line:character position. Hybrid method (DelphiLSP has no native references): project-wide text scan, then every candidate is validated by asking the compiler engine for its definition - only candidates resolving to the SAME symbol are confirmed, homonyms are rejected. Bounded work: leftovers are listed as unverified, never silently dropped.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file |
| `line` | integer | **yes** | Zero-based line of the identifier to find references for |
| `character` | integer | **yes** | Zero-based character inside the identifier |

### `delphi_diagnostics`

Compiler-grade errors/warnings/hints for one Delphi source file (Error Insight via the official DelphiLSP linter), WITHOUT building. Real compiler codes (E2003, W1000, H2164...) with exact 0-based positions (range) and line1, the 1-based line delphi_read shows. Severity: 1=error, 2=warning, 3=information, 4=hint. Lints the CURRENT on-disk content.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file to lint (.pas/.dpr) |


## Read files & explore

### `delphi_read`

Read a Delphi source file DECODED CORRECTLY (CP1252 / UTF-8 with or without BOM detected for real). Returns numbered lines in the format number|content - to build a delphi_edit anchor, copy everything after the bar, exactly. ALWAYS use this instead of a generic read for Delphi files: generic reads turn CP1252 accents into U+FFFD and poison every anchor built from them.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi file (.pas/.dpr/.dpk/.inc/.dfm/.fmx) |
| `fromline` | integer | optional | First line to show, 1-based (0 = from the start) |
| `toline` | integer | optional | Last line to show, 1-based (0 = to the end; capped at 400 lines per call) |

### `delphi_search`

Search Delphi sources recursively for a literal text (case-insensitive), skipping IDE artifacts (__history, Win32/Win64, dcu, .git...). Files are decoded with their real encoding, so accented text matches correctly. Returns path, 1-based line and the line text (same numbering as delphi_read).

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | **yes** | Directory to search recursively (project root) - or ONE file (a .dproj, .dpr, .inc, .xml...) to search inside it in a single call |
| `query` | string | **yes** | Literal text to find (case-insensitive - it is Pascal) |
| `maxresults` | integer | optional | Maximum hits to return PER PAGE (default 100, cap 500 per page — not a global limit: the offset walk covers the full hit list) |
| `offset` | integer | optional | Skip the first N matches of the FULL hit list (default 0): pagination — pass the `nextOffset` of the previous answer and walk it until `hasMore=false` |
| `wholeword` | boolean | optional | true = match whole identifiers only (word boundaries) |
| `pattern` | string | optional | Optional file mask to search instead of the Delphi set, e.g. *.style, *.ini, *.md, *.rc (one mask) |

### `delphi_list`

List Delphi files under a directory recursively (sources and project files by default, or a custom mask), skipping IDE artifacts. Returns path, size and last-write time. Capped at 500 entries. With dirs=true it lists the SUBDIRECTORIES of root instead (one level, explorer-style) - use that to browse the machine and decide where to create or look for projects.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | **yes** | Directory to list recursively |
| `pattern` | string | optional | Filename mask, e.g. *.pas (default: Delphi source and project files) |
| `dirs` | boolean | optional | true = list SUBDIRECTORIES of root (one level, explorer-style) instead of files |
| `includetrash` | boolean | optional | true = also show the recoverable trash `__delphi-patch` (default false: skipped like the other IDE artifacts). With it on, the answer says how many of the entries are trash copies (`shownTrash`, `trashNote`) |

### `delphi_projects`

Locate Delphi projects (.dproj/.groupproj) under a directory - or under the workspace roots configured in settings.ini [Workspace.<name>] Roots when root is empty. Optional name filter. Use this to answer "open project X" without knowing the disk layout. Answers in PAGES (`maxresults`, default 50; `offset` + `nextOffset` to walk them), and when there are more it also reports `byFolder` - the ten folders holding the most - so the next call can narrow `root` instead of walking pages. That matters on a broad jail: measured on a server whose root was a whole drive, 6420 of 7025 projects were third-party component sources and their backups, and the operator's own were 73.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | optional | Directory to search under. Empty = the roots configured in settings.ini [Workspace.<name>] Roots (semicolon-separated) |
| `name` | string | optional | Optional name filter (substring, case-insensitive), e.g. "comunicador" |
| `maxresults` | number | optional (default 50) | Maximum projects to return PER PAGE (cap 300) |
| `offset` | number | optional (default 0) | Skip the first N projects of the FULL list - pass the `nextOffset` of the previous answer |

### `delphi_installs`

List EVERY RAD Studio / Delphi installation discovered on this machine (a machine may host several versions side by side): version, root directory, whether it ships DelphiLSP.exe (semantic engine) and rsvars.bat (msbuild). Also reports which one is ACTIVE for the calling workspace: the version its `DelphiVersion=` asks for when installed, otherwise the newest with DelphiLSP - and, when the requested one is missing, `requested` plus a `requestedNote` saying which one answers instead (the same note `delphi_workspace` gives as `delphiVersionNote`). Each install carries its own `name`, `personality`, `edition` and `build`, read from the registry and `bds.exe`. Read-only, no parameters.

*Access: read-only OK.*

No parameters.

### `delphi_workspace`

The lay of the land on the SERVER: the workspace roots this server operates within (your entire allowed universe here), the access level (read-write / read-only), the `[Workspace.<name>]` section of the server this token is scoped to (`workspace`), and the active RAD Studio - by BDS number (`activeDelphi`), by NAME as the IDE registers itself (`activeDelphiName` "RAD Studio 13", `activeDelphiPersonality` "Delphi 13": the words to search the web with), its edition and exact build from `bds.exe` (`activeDelphiEdition`, `activeDelphiBuild`) and its folder (`activeDelphiRoot`) - all read from the installation, a field the machine lacks is absent; when the workspace pinned a `DelphiVersion=` that is not installed, `delphiVersionRequested` and `delphiVersionNote` say so. It also says WHO is answering (`server`): version, how this process was started (tray / service / console), transport, pid and uptime - the way to check a deployment without looking at the machine from outside. Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only exist inside this MCP: use them verbatim in every path argument and you will receive them back in results. They are NEVER your own local disks. Call this FIRST. Read-only, no parameters.

*Access: read-only OK.*

No parameters.


## Edit code safely  (read-write only)

### `delphi_edit`

SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus text .dfm/.fmx) preserving the real encoding and line endings. Modes: EDIT (old = ONE full line copied from delphi_read + new), DELETE (delete=true + old: removes the line entirely), INSERT (insert="rutina-global"|"metodo" + code: the tool picks the legal spot - also inside a .dpr - and, for methods, writes BOTH halves: declaration and qualified implementation), CREATE (createunit=true; new files honour the encoding configured in the IDE) and RESTORE (restore=true, two-step) and ADDUSES (adduses="UnitA;UnitB" + section=interface|implementation: the units land in that section's uses clause, commas and terminator written by the engine, the clause created under the section keyword when there is none, names already there skipped) and REMOVEUSES (removeuses="UnitA", the inverse: the clause goes whole when it empties; a .dpr/.dpk goes through delphi_config add-unit / remove-unit). It refuses to rewrite whole files, refuses binary designer files (TPF0), makes automatic backups, writes atomically, and audits the result (encoding, EOLs, mojibake, end. structure) reporting the REAL lines read back from disk - use that as evidence. Never edit Delphi files with generic tools: CP1252 sources get destroyed.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi file |
| `old` | string | optional | EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the \| bar). Leading indentation may be omitted |
| `new` | string | optional | EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new together with the added code) |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers) |
| `toline` | integer | optional | RANGE (1-based, included): the LAST line of the stretch. With it `old` stops being the line to touch and becomes the FIRST of a range that ends here: `delete:true` removes them all, `new` replaces them all with that text. The way to drop or replace a whole method without pasting it as the anchor. Refused if the range runs backwards, runs past the end of the file, or swallows the file whole |
| `edits` | string | optional | Several edits on THIS SAME file, in one call and ALL OR NOTHING: a JSON array `[{"old":"...","new":"...","atline":12},...]` applied IN ORDER. An anchor may be ONE full line or a contiguous BLOCK of lines, matched whole and in order; `"occurrence": 1, 2...` picks which one when it repeats (better than `atline` inside a batch: line numbers MOVE as earlier entries add or remove lines; `occurrence` counts on the file as it is BEFORE the batch, so after an entry changes occurrence 1 the next one asks for 2 - two entries on the same line are refused); `"delete": true` removes the line; `"toline": N` makes that entry a range. Ranges are dragged too, so an earlier entry that adds lines corrects the later `toline` by itself. For a LONG line an entry may carry `"fragment"` instead of `"old"`: `{"fragment":"68","new":"69","atline":12}` changes just that piece of line 12. A field that is not one of old/new/atline/toline/delete/occurrence/fragment is REFUSED, not ignored. If one entry fails the file goes back byte for byte and the answer names it. Changes across SEVERAL files are delphi_changeset |
| `fragment` | string | optional | FRAGMENT mode, for LONG lines (a long string, a long comment): instead of `old`, the exact piece of text to change INSIDE one line, with `atline` = that line's 1-based number (MANDATORY) and `new` = what replaces just that piece. The rest of the line is kept byte for byte. Case-sensitive, and the fragment must appear EXACTLY ONCE in that line: zero or several is a refusal that shows the real line. The engine then matches the WHOLE line again before writing, so the full-line rule is not relaxed. No line breaks; does not combine with old, delete or toline, nor with another mode (insert, createunit, restore) |
| `delete` | boolean | optional | DELETE mode: true = remove the "old" anchored line ENTIRELY (old+new="" only blanks it). No "new" here |
| `insert` | string | optional | INSERT mode (preferred for NEW routines/methods): "rutina-global" or "metodo". The tool places the block at the legal boundary (in a .dpr: between uses and the main begin; in a unit: before the final end./initialization); with "metodo" it also writes the class declaration. Pass code, not old/new |
| `code` | string | optional | INSERT mode: the COMPLETE block (unqualified signature + begin..end;). NEVER include end. |
| `inclass` | string | optional | INSERT "metodo": exact class name (e.g. TFichaPedidos) |
| `visibility` | string | optional | INSERT "metodo" optional: section for the declaration (private/protected/public/published); empty = end of class. "published" works on form classes even without an explicit keyword: the declaration lands in the implicit published section right after the class header - the place for event handlers |
| `visible` | boolean | optional | INSERT "rutina-global" optional: true = also declare it in the interface section (visible outside the unit) |
| `createunit` | boolean | optional | CREATE mode: true = create the .pas (never overwrites). Then register it in the .dpr uses clause |
| `content` | string | optional | CREATE mode: the COMPLETE file content in one call (empty = standard IDE skeleton). Use this when you already know the whole unit: one call instead of create + N patches |
| `eol` | string | optional | CREATE mode: line endings, "crlf" (default, Delphi standard) or "lf" |
| `restore` | boolean | optional | RESTORE mode: true = restore the file from this tool's backup. First call shows what would be LOST; repeat with confirm=true to execute |
| `confirm` | boolean | optional | Only with restore: execute after having seen the losses |
| `adduses` | string | optional | ADDUSES mode: unit names to add to a uses clause of this .pas, separated by ; (System.SysUtils;UCliente). The engine writes the commas and the terminator, creates the clause under the section keyword when there is none, and skips the names already there, in this section or in the other one (idempotent; a unit cannot be in both, E2004). For a .dpr/.dpk use delphi_config add-unit instead |
| `section` | string | optional | ADDUSES mode: "interface" or "implementation" (default implementation: a new unit goes there unless one of its types is used in the interface) |
| `removeuses` | string | optional | REMOVEUSES mode: unit names to take out of the uses clause of "section", separated by ; - the inverse of adduses. A directive around the entry stays glued to its neighbour, and the clause goes whole when it empties. Names not there are reported, not an error. For a .dpr/.dpk use delphi_config remove-unit |

### `delphi_changeset`

MULTI-FILE TRANSACTIONS: when one change touches several files, either the whole batch lands or none of it. Flow: `begin` (returns an id) → `stage` one operation per call (kind=edit|create|delete|move; nothing touches disk yet) → `preview` (resolves every edit anchor and fingerprints every file the batch will touch) → `commit` (fingerprints re-checked — a file changed since preview refuses the WHOLE batch —, byte snapshots taken, operations applied in order; any failure restores every file byte-exact and reports which operation failed). `rollback` discards a staged batch; `status` lists open changesets. Edits use the delphi_edit contract (old = ONE full line, unique; `atline` pins a duplicate). A changeset expires after 30 minutes unused.

*Access: read-write only.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | begin (new changeset → id) \| stage (add ONE operation) \| preview (resolve anchors + fingerprint files; required before commit) \| commit (apply all or nothing) \| unstage (take operation `n` back out of the batch; n=0 = the last one) \| rollback (discard) \| status (list open ones) |
| `id` | string | optional | The changeset id returned by begin (every command except begin/status) |
| `n` | integer | optional | unstage: the number of the staged operation to take back out (as `status` lists them); 0 = the last one |
| `kind` | string | optional | stage: edit (replace ONE line by anchor; Delphi sources and plain text alike) \| create (new file, never overwrites) \| delete (the WHOLE FILE) \| delete-line (remove ONE line by `atline` — the only way to remove a BLANK line) \| move (destination must not exist) |
| `path` | string | optional | stage: the file the operation touches (inside the workspace roots) |
| `dest` | string | optional | stage kind=move: the destination path |
| `old` | string | optional | stage kind=edit: the anchor — ONE full line copied verbatim from delphi_read, unique in the file |
| `new` | string | optional | stage kind=edit: the replacement text (may span several lines) |
| `fragment` | string | optional | stage kind=edit, instead of `old`: a piece of ONE long line, with `atline` mandatory; same rules as in `delphi_edit`. It is resolved against the file when you stage it, so an ambiguous fragment is refused there and not at commit |
| `content` | string | optional | stage kind=create: the whole content of the new file |
| `atline` | integer | optional | stage kind=edit: 1-based line number to pin the anchor when the same line appears more than once. REQUIRED for kind=delete-line. Line numbers are rebased automatically against what earlier operations of the same changeset did to that file |

### `delphi_textedit`

SAFE editing of plain-text NON-Delphi files (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml - ANY plain text): docs, web assets, tests, scripts, config. Same discipline as delphi_edit - one-full-line unique anchor (old/new, atline tie-break), DELETE mode (delete=true + old), several edits on the SAME file in one all-or-nothing call (`edits`), real encoding preserved (UTF-8 +/- BOM / CP1252), line endings preserved, automatic backup, atomic write - without the Pascal gates. CREATE mode (create=true + content) for new files, never overwrites. Whole-file rewrites are refused. Delphi sources/designers are refused (use delphi_edit) and so are .dproj and binaries. Read first with delphi_read and copy the anchor exactly.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the text file (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml ... any plain text - Delphi files are refused, use delphi_edit) |
| `old` | string | optional | EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the \| bar). Leading indentation may be omitted |
| `new` | string | optional | EDIT mode: the new text; may be several lines. Empty = blank the line |
| `fragment` | string | optional | FRAGMENT mode, for LONG lines (a README paragraph): instead of `old`, the exact piece of text to change INSIDE one line, with `atline` = that line's 1-based number (MANDATORY) and `new` = what replaces just that piece. The rest of the line is kept byte for byte. Case-sensitive, and the fragment must appear EXACTLY ONCE in that line: zero or several is a refusal that shows the real line. No line breaks; does not combine with old, delete or toline, nor with create |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence |
| `toline` | integer | optional | RANGE (1-based, included): the LAST line of the stretch. With it `old` stops being the line to touch and becomes the FIRST of a range that ends here: `delete:true` removes them all, `new` replaces them all with that text. Refused if the range runs backwards, runs past the end of the file, or swallows the file whole |
| `edits` | string | optional | Several edits on THIS SAME file, in one call and ALL OR NOTHING: a JSON array `[{"old":"...","new":"...","atline":12},...]` applied IN ORDER. An anchor may be ONE full line or a contiguous BLOCK of lines, matched whole and in order; `"occurrence": 1, 2...` picks which one when it repeats (better than `atline` inside a batch: line numbers MOVE as earlier entries add or remove lines; `occurrence` counts on the file as it is BEFORE the batch, so after an entry changes occurrence 1 the next one asks for 2 - two entries on the same line are refused); `"delete": true` removes the line; `"toline": N` makes that entry a range. Ranges are dragged too, so an earlier entry that adds lines corrects the later `toline` by itself. For a LONG line an entry may carry `"fragment"` instead of `"old"`: `{"fragment":"68","new":"69","atline":12}` changes just that piece of line 12. A field that is not one of old/new/atline/toline/delete/occurrence/fragment is REFUSED, not ignored. If one entry fails the file goes back byte for byte and the answer names it. Changes across SEVERAL files are delphi_changeset. When `edits` is given, old/new/atline/delete/toline are ignored |
| `delete` | boolean | optional | DELETE mode: true = remove the line anchored by `old` ENTIRELY (old + empty new only blanks it). No `new` here |
| `create` | boolean | optional | CREATE mode: true = create a NEW file (never overwrites). UTF-8, parent directories created |
| `content` | string | optional | CREATE mode: the initial content of the new file (may be empty) |
| `eol` | string | optional | CREATE mode: line endings, "crlf" (default) or "lf" |

### `delphi_create`

Create a NEW Delphi project (console/VCL/FMX: .dpr + buildable .dproj + main form) or a NEW form, frame or data module (VCL/FMX: .pas + .dfm/.fmx pair, registered in the .dpr uses - with Application.CreateForm for forms and data modules - and in the .dproj). IDE-equivalent skeletons, CRLF, source encoding follows the IDE's configured default (UTF-8/ANSI), never overwrites anything. kind=unit creates a plain .pas and registers it in the project (uses of the .dpr + DCCReference of the .dproj); forms get their Application.CreateForm too. An EXISTING .pas joins a project with delphi_config command=add-unit.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `kind` | string | **yes** | What to create: project-console \| project-vcl \| project-fmx \| project-package (a runtime package: .dpk + .dproj, requires rtl; units go into its contains clause with kind=unit or add-unit; built to BPL+DCP in its own folder, never installed in the IDE) \| form-vcl \| form-fmx \| frame-vcl \| frame-fmx \| datamodule \| unit (a plain .pas). Everything but projects is registered in the project given |
| `dir` | string | optional | Projects: ABSOLUTE target directory (created if missing). Everything else (unit, form, frame, data module): optional SUBFOLDER of the project, RELATIVE to it and as deep as you like (`Dominio\Modelos\Dto`) - created if missing, and the unit is registered with that relative path. The folder layout is yours to decide. No absolute paths, no drive, no `..`. Empty = next to the .dpr |
| `name` | string | **yes** | Projects: project name. Forms, frames, data modules and units: unit name (e.g. UClientes) |
| `project` | string | optional | Everything but projects: absolute path of the project .dpr (or .dproj) to register the new unit in |
| `formname` | string | optional | Forms/frames/data modules optional: instance name without the T (default: Form+unit, Frame+unit, DM+unit) |
| `content` | string | optional | kind=unit: the FULL source of the unit, instead of the skeleton; its `unit X;` must match `name` |


## Manage files  (read-write only)

### `delphi_delete`

Delete a file or folder inside the workspace. NOT a hard delete: the target is moved to a recoverable trash (__delphi-patch\<date>\deleted\ next to it), so a mistake can be undone. Jailed to the workspace roots, refused in read-only mode. Use it to clean up stray files and leftovers. Deleting a unit (.pas) also trashes its .dfm/.fmx and takes it out of every project that lists it (uses, CreateForm, DCCReference) - looked for from its folder UP to the edge of the workspace. Deleting a whole FOLDER takes the units inside it out of the project too. To keep the file but drop it from a project use delphi_config command=remove-unit.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted |
| `purge` | boolean | optional | true = the one HARD delete: allowed only INSIDE the trash `__delphi-patch`, and only for what the same agent trashed. Everything else is always the recoverable move |

### `delphi_move`

Move or rename a file or folder inside the workspace. Both source and destination must be inside the workspace roots; parent folders of the destination are created. The source is copied to the recoverable trash first. Jailed, refused in read-only mode. Moving or renaming a unit (.pas) moves its .dfm/.fmx with it, rewrites its "unit X;" header on a rename, and re-points every project that lists it: the .dpr uses and DCCReference, the uses of every other unit of the project and every qualified `UnitOld.X` reference in them (outside string literals) - looked for from its folder UP to the edge of the workspace, however deep the unit sits. Moving a whole FOLDER re-points the units inside it too.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to move (inside the workspace roots) |
| `dest` | string | **yes** | Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same |

Both refuse a workspace **root** itself: the trash folder is created next to the
target, so for a root it would land in the root's parent - a write outside the
jail - and take the whole workspace with it. Delete or move what lives *inside*
a root. Changing the roots is the operator's job, in `settings.ini`.


## Build, run, package  (read-write only)

### `delphi_build`

Build a Delphi project for real with MSBuild on this machine (rsvars located via registry). Returns success flag, compiler errors/warnings and the output tail. Use this as the closing verification after editing - the linter does not link nor produce binaries. Compile-only: a project that would EXECUTE a shell during build (a custom `<Target>`/`<Exec>`, a foreign `<Import>`) is refused unless the workspace declares `AllowBuildScripts=1`; its pre/post build EVENTS (signing, copies) are skipped instead, with `buildEventsSkipped` and a note - the binary is for working and testing, the final one is built where the events run. For a package (.dpk) the answer adds `implicitImports` (units of OTHER packages it compiled into itself, W1033) and `requiresSuggested` (their packages, read from the BPLs of this install - or, for a unit that lives in a `.dpk` of your own workspace, that package, found by climbing the folders from the one being built, with `requiresWorkspaceNote` telling you to build it first: installing packages stays the operator's job), the list `delphi_config add-requires` takes; a unit dcc cannot find at all is F2613 and comes back in `missingUnits` instead.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the .dproj to build |
| `platform` | string | optional | Target platform (default Win32): Win32/Win64 build natively here. Linux64/OSX64/OSXARM64/Android64/iOSDevice64... need the platform enabled in the project (delphi_config) and their SDK pulled once (delphi_paserver get-sdk). Building is LOCAL against that SDK and does NOT use profile — a PAServer profile is only needed for target=Deploy |
| `config` | string | optional | Debug or Release (default Debug), or any configuration the project declares. A simple name: letters, digits, space, `.`, `_`, `-` |
| `target` | string | optional | Build (full, default), Make (incremental), Clean, or Deploy (always builds first, then deploys: to the PAServer of `profile` for Linux/macOS, or packages the app for Android). After switching platforms use Build |
| `profile` | string | optional | Connection profile name for target=Deploy on a PAServer platform (see `delphi_paserver command=profiles`). The deployed files land on the target under its PAServer scratch dir, in `<profile>/<project name>/` |
| `sdk` | string | optional | Which platform SDK to link against, BY NAME (`delphi_paserver command=profiles` lists them with their glibc). One SDK = one folder, the same model as the Android SDKs |
| `verbosity` | string | optional (default `quiet`) | How much of the build comes back, the same contract as the house build script: `quiet` = errors + summary (a few lines, what "does it still compile" needs; msbuild is not even asked for the warnings, so none are reported rather than reporting zero), `normal` = warnings and milestones, `verbose` = everything, linker command line included |
| `deviceid` | string | optional | Android device serial for target=Deploy on Android platforms (see `delphi_adb command=devices`) — measured: msbuild only auto-installs on iOS; on Android install the built .apk with `delphi_adb command=install` |

**Which SDK a cross-platform build links against**, in this order: what the call asks for (`sdk`), what the PROJECT declares (its own `PlatformSDK` property — the IDE's model), the **default of the IDE's own SDK Manager** for that platform (an explicit choice of the operator, so it wins over any guess of ours), and otherwise the only one registered. Every answer says which one it used and why, in `sdk` and `sdkNote`. Only with several SDKs, no default and no hint is the build **refused, naming them**: linking against the wrong sysroot produces a binary that dies on the target with `GLIBC_2.xx not found`, which is a far worse way to find out. The answer always carries the `sdk` it used, and `sdkWarning` when that sysroot holds two distributions at once (what the old get-sdk left behind by pulling every target into one folder).

One msbuild at a time, server-wide: two builds share output folders and would corrupt each other, so a second one queues (the answer says how long it waited in `queuedMs`). If the `.exe` the build has to write is OPEN — typically a `delphi_test` of that same project still alive — the compiler answers F2039; the build retries for a few seconds and, if it gets through, says so in `lockedRetries`. If it does not, `lockedOutputNote` explains what to do: this server never kills a process of the machine, because somebody may be working at the other end.

When the build fails with F2613 (`Unit 'X' not found`) or F1026, the result carries `missingUnits`: each unit with the `sourceFolders` of the library zone where its `.pas` lives (shortest first, at most 6) and a note with the `delphi_config command=add-searchpath platform=<platform> path=<folder>` to run. An empty list means the component is not installed or brings no source for that platform (`delphi_components platform=<platform>`, then `delphi_report`).

When a Linux link fails with `cannot find -lX`, the usual cause is not the project: the sysroot was pulled from a machine without the `-dev` package, so it carries `libX.so.1` but not the development name `libX.so` the linker looks up. The build completes that name in the SDK (a copy of the shortest versioned file, in the first `Profile_librarypath` folder that has it - never over an existing `libX.so`), retries ONCE and reports it in `sdkLinksCompleted` / `sdkLinkNote`; nothing is installed on the target. If the sysroot has NO version of that library at all, the note says so: the target machine lacks the package itself. Completing every name at `get-sdk` time was measured and rejected (2,117 names and 2.2 GB of copies on one Zorin).

Everything above reaches an MSBuild command line, so it is validated at the
gate: `platform` must be one Delphi knows, `target` is one of the four,
`config` admits no character a shell would interpret, `profile` follows the
PAServer profile-name rule and `deviceid` the adb device rule. A rejected
value names what is valid instead.

On `target=Deploy` with no `.deployproj` in the project, the server generates
the deployment manifest (minimal for PAServer platforms; the full apk staging
map for Android, plus an `AndroidManifest.template.xml` seed and fallback
version/jar properties in the `.dproj`, each conditioned so IDE-written values
always win). Files the IDE wrote are never overwritten. A successful Android
Deploy declares the built `.apk` as `output`.

### `delphi_help`

THE MAP of this server, so an agent does not have to spend context working it out. `command=tasks` (the default) gives the task → tool table, one line each: what do I use to read, to edit, to compile, to change several files at once, to rename, to test, to deploy. `command=tool name=<tool>` gives ONE tool in full (description + parameters) without asking for `tools/list`, which returns all 42 at once. `command=conventions` gives the rules that hold for every tool: paths and virtual drives, the jail, anchored editing, the backups, encodings. Start here after connecting.

*Access: read-only.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | tasks (task → tool table; the default) \| tool (one tool in full, with `name`) \| conventions (the rules common to all) |
| `name` | string | optional | `command=tool`: the tool's name (`delphi_edit`, or just `edit`) |

### `delphi_test`

TESTS — the difference between "it compiles" and "it works". `discover path=<folder or project>` lists the test projects underneath (a `.dpr` using DUnitX, or a console one whose name says test/tests/spec). `run project=<the test .dproj>` builds and runs that runner and answers STRUCTURED: `total`, `passed`, `failed`, the failing lines, `exitCode`, `durationMs` and a bounded tail of what it printed. Two dialects are understood: DUnitX's own summary and the plain `PASS`/`FAIL` + ExitCode convention of a hand-written console runner. The verdict says where it came from (`verdictFrom: counts | exitCode`) and never guesses. Running tests IS execution: its own switch, `AllowTests=1` declared in the calling workspace, and the one thing that ever runs on this server; the binary is built here, comes from a project of the jail, and runs in a low-integrity sandbox, with a timeout. Without the switch, `discover` still works and `run` is refused.

*Access: mixed (discover read-only; run read-write + AllowTests).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | discover (list test projects under `path`) \| run (build and run the one in `project`). Default: discover |
| `path` | string | optional | discover: folder (or project) to search under |
| `project` | string | optional | run: the `.dproj` (or `.dpr`) of the test project |
| `config` | string | optional | run: configuration to build and run (Debug by default) |
| `platform` | string | optional | run: platform to build and run on (default Win64) — the platforms of THIS machine only, Win32/Win64: the runner executes here |
| `filter` | string | optional | run: test filter for frameworks that support it (DUnitX `--run:`); a hand-written runner ignores it |
| `timeoutms` | integer | optional | run: max milliseconds (120000 default, 600000 max). A hanging test is cut and said so |
| `nobuild` | boolean | optional | run: true = do not build first, run the existing binary. By default it builds (running a stale binary is a lie) |

### `delphi_package`

Zip a build-output directory ON the server into a single deploy artifact (recursive, *.dcu intermediates excluded), ready to download with ONE delphi_fetch. The standard way to bring a GUI app to the client machine: delphi_build -> delphi_package -> delphi_fetch.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `dir` | string | **yes** | Directory to package (e.g. the build output Win64\Debug). Recursive; *.dcu and dcu\ intermediates excluded |
| `outfile` | string | optional | Optional zip path (default: sibling of dir, named <dirname>-deploy.zip). Must be inside the workspace roots |


## Cross-platform: build configs, remote platforms & devices

### `delphi_config`

See and manage a project's build configurations and target PLATFORMS. command=view (read-only) answers a SUMMARY by default — framework (VCL is Windows-only; FMX and console cross platforms), build configurations, enabled platforms and counts of the rest, plus `remoteTargets`: each ENABLED remote platform with the `sdk` and the PAServer `profile` it builds and deploys with and where each comes from (`sdkSource` / `profileSource`: `project`, IDE default, or none - with the command that fixes it); `section=platforms` carries the same four fields on every remote platform — and `section=platforms|searchpaths|deploy|units|all` brings each detail on demand (platform states and reasons, unit search paths per group, deployment files, project units, or the old everything-at-once view). command=add-platform enables a platform in the .dproj (a curated edit of the `<Platforms>` block only) and, when given `sdk` and/or `profile`, leaves both set on the project in the same call - adding a target to a project is one gesture, the same three things the IDE's dialog asks for; remove-platform disables it again. command=set-profile does the same for the PAServer connection - the `Profile` property - so a `target=Deploy` no longer needs to be told the profile on every call; in the IDE both halves are one gesture, because adding a target to a project IS giving it a connection and an SDK. command=set-sdk fixes WHICH platform SDK this project builds a platform with - the `PlatformSDK` property, the same one the IDE writes from Project Options, and the way the model is meant to work: many SDKs registered, and the project choosing. Without it the build rides on the SDK Manager default, which is a fallback, not a decision. command=set-version writes the project VERSION where it has to agree with itself: the Windows VERSIONINFO numbers (VerInfo_MajorVer/MinorVer/Release/Build) AND the FileVersion/ProductVersion keys, which is exactly what drifts when a release is cut by hand; a suffix like -beta is accepted and ignored because the VERSIONINFO is numeric, and Android (versionCode/versionName) and iOS (CFBundleVersion) are NOT touched - that numbering is a different thing. command=set-output puts every binary under one folder (output=Compiled by default): a curated edit that sets DCC_ExeOutput/DCC_DcuOutput, keeping the per-platform/config subfolders. command=add-searchpath adds a unit search path (where the compiler looks for .pas/.dcu, e.g. the Source folder of an installed component) to ONE platform - the IDE's Project Options > Search path - creating the platform's property groups exactly as the IDE would; a platform added to a project inherits NO search paths from the others, which is the usual reason a unit is "not found" on the new platform only. remove-searchpath takes it out again. command=add-deployfile ships an extra file with the build on ONE platform - the IDE's Deployment Manager: the native library a component loads at runtime (.so/.dylib/.dll), data files - written into the .deployproj as the IDE does (Debug and Release), generating the standard manifest first if the project has none; remove-deployfile takes it out again. command=add-unit / remove-unit is the IDE's Add to project / Remove from project for an EXISTING .pas (uses of the .dpr, CreateForm for forms, DCCReference of the .dproj); the file stays on disk. To BUILD a specific combination use delphi_build with platform+config.

*Access: mixed (view read-only; every other command read-write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the project .dproj |
| `section` | string | optional | view: summary (default) \| platforms \| searchpaths \| deploy \| units \| all — which detail the view brings (platform states and reasons, unit search paths per group, deployment files, project units, or everything at once) |
| `command` | string | optional | view (default: project summary; section= brings the detail per area) \| add-platform (enable a platform; with `sdk` and/or `profile` it also leaves them set on the project, which is what the IDE's own dialog does: platform + connection + SDK in one gesture) \| remove-platform (disable it again) \| set-output (put every binary under one folder, e.g. Compiled) \| set-version (the project VERSION: the Windows VERSIONINFO numbers and the FileVersion/ProductVersion keys, which have to agree; Android and iOS numbering is not touched) \| set-sdk (the SDK this PROJECT builds a platform with - its own PlatformSDK, which is the IDE's model; \"none\" goes back to the SDK Manager default)  \| set-profile (the PAServer profile this PROJECT deploys and runs a platform with - its own Profile property; the twin of set-sdk, because adding a target to a project is giving it BOTH) \| add-searchpath (add a unit search path for one platform, or for all) \| remove-searchpath (take it out again) \| add-deployfile (ship an extra file with the build on one platform: a component's runtime .so/.dll/.dylib) \| remove-deployfile (take it out again) \| add-unit (register an existing .pas in the project: uses of the .dpr, CreateForm for forms, DCCReference of the .dproj) \| remove-unit (take it out of the project; the file stays on disk) \| add-requires (packages only: add package names to the requires clause of the .dpk - what the IDE offers after a build reports W1033, and what delphi_build lists in requiresSuggested) |
| `platform` | string | optional | add/remove-platform: the platform, from the fixed set Win32\|Win64\|Win64x\|WinARM64EC\|OSX64\|OSXARM64\|Linux64\|Android\|Android64\|iOSDevice64\|iOSSimARM64 (anything else is refused). add/remove-searchpath: the platform whose search path changes; empty = the base group (every platform). add/remove-deployfile: the platform the file ships on (required) |
| `path` | string | optional | add/remove-searchpath: the unit search path to add or remove - a folder where the compiler looks for .pas/.dcu, e.g. the Source folder of an installed component. IDE macros like `$(BDS)` accepted; relative paths resolve from the project folder. Must resolve inside the workspace or the library zone and exist. add/remove-unit: the .pas to register in / take out of the project. add/remove-deployfile: the file to ship (e.g. a component's `Library\Linux64\libzbar.so`) |
| `remotedir` | string | optional | add-deployfile: destination folder on the target, relative to the deployment root (the IDE's RemoteDir). Default: the project folder, next to the binary - or, for a .so on Android, the apk's `library\lib\<abi>\`. No absolute paths, no `..` |
| `sdk` | string | optional | set-sdk: the SDK by name (`delphi_paserver command=profiles` lists them with their glibc). `none` removes the setting and falls back to the SDK Manager default |
| `profile` | string | optional | set-profile: the PAServer connection profile by name (`delphi_paserver command=profiles` lists them). Refused on local platforms - Windows builds here and takes no profile. `none` removes the setting |
| `output` | string | optional | set-output: the output folder for binaries, a simple relative name like Compiled (default). The .exe goes to `<folder>\$(Platform)\$(Config)` and .dcu to `<folder>\Dcu\$(Platform)\$(Config)`. Use "default" to restore the RAD Studio layout. No absolute paths, no ".." |
| `version` | string | optional | set-version: the version to write, 2 to 4 numbers (1.2, 1.2.3, 1.2.3.4); a suffix like -beta is accepted and ignored, because the VERSIONINFO is numeric. It goes to the Windows VerInfo numbers AND to the FileVersion/ProductVersion keys at once - they have to agree and that is exactly what drifts when they are edited by hand. Android (versionCode/versionName) and iOS (CFBundleVersion) are NOT touched |
| `requires` | string | optional | add-requires: the package names to add to the requires clause of the .dpk, separated by ; (vcl;dbrtl) - take them from requiresSuggested of the delphi_build answer. Names already there are kept, not repeated |

### `delphi_paserver`

The bridge for building and running on OTHER platforms (Linux, macOS) through the Platform Assistant (PAServer). command=packages lists the PAServer installers that ship with each Delphi install (download them with delphi_fetch and run them on the target machine); command=platforms shows which platforms this server can target; command=profiles lists the registered connection profiles and SDKs; command=add-profile registers a connection profile against a live PAServer (the password is used once by `paclient` to write the profile and stored ENCRYPTED, never shown back) - and since v0.98 it also writes the twin seat the IDE keeps in the registry (`RemoteProfiles\<name>`), refuses to overwrite an existing name and warns when another profile already points at the same host:port. The IDE builds its Connection Profile Manager list from THAT registry key, and it reads it **at startup**: a profile created while the IDE is running appears at its next start, not before. If a profile exists on disk but the IDE does not list it, `command=reseat` repairs exactly that - it walks the `.profile` files and writes the missing seats, reading each encrypted password from its own file, so it needs no PAServer and nobody ever has to know a password. (Measured 2026-09-20 on a live setup: two profiles invisible in the IDE, one `reseat`, and both appeared in the registry and in the IDE's list.) The other half is what actually builds: `paclient`, MSBuild and every tool here read the `.profile` FILES - connecting, pulling an SDK, building, deploying and running on a target all work from them, with or without a seat; command=test-connection with name dials the PAServer of that profile (full handshake, credentials included), and with host+port and NO name it is a raw TCP reachability probe - the quick "does this server reach my PAServer at all?" answer, no credentials involved; command=get-sdk pulls the platform SDK/sysroot (the libraries the linker needs) from the PAServer of profile `name` and registers it for delphi_build AND in the IDE's SDK Manager (path table read from that install's own Linux64.defaultsdkpaths, nothing hardcoded) - run it once per target (can take minutes; re-run after OS upgrades on the target). Building for the platform is delphi_build once profile and SDK exist. command=remote-run EXECUTES a program on the target of profile `name` and returns its exit code and output (optional `exe` naming another file of the SAME deploy folder, `args` and `timeoutms`) - and NOTHING has to be installed on the target: the server uploads a job file (the binary, the output file, one argument per line) and the native launcher `node\McpRunJob` (paclient's put flag 3 on Linux, 5 on Windows), which PAServer starts - no shell anywhere in the path. The launcher checks the binary is native (ELF/PE) so only the NATIVE BINARY that project deployed ever runs - never another file of the machine, never a script sitting in the folder. The program's output lands in a file ending in an `___RC=<code>` sentinel; while the sentinel is missing the program is still running, and when the timeout expires it is NOT killed: you get `stillRunning: true` plus its PARTIAL output (a GUI app is meant to stay up - drive it with delphi_desktop).

*Access: mixed (platforms / packages / profiles read-only; reseat / add-profile / remove-profile / test-connection / get-sdk / reseat-sdk / remove-sdk / remote-run / kill read-write).*

**One SDK = one folder, and the project says which one it builds with** — the same model RAD Studio uses for its Android SDKs. `get-sdk` writes the sysroot into a folder of its own, named after the target's distribution (`fedora44.sdk`, `zorin18.sdk`), registers it for msbuild and in the IDE's SDK Manager, and **refuses to pull one distribution on top of another**. That refusal exists because the opposite was measured: until 2026-09-20 every target was pulled into a single `Linux64.sdk`, and the operator's folder ended up holding the Debian/Ubuntu tree AND the Red Hat one — two `libc.so.6` (2.39 and 2.43), two gcc trees, and both lib directories on the linker's path. It linked correctly only because of the ORDER of that list.

`command=remove-sdk` is the other half: it deletes the `.sdk` file and the IDE seat, so the SDK stops being offered — and it deliberately leaves the sysroot on disk, reporting its path in `sysrootLeftBehind`. Carrying off gigabytes of somebody's disk is not a tool's job; deleting that folder is a decision, and a one-line one in any file manager.

`command=reseat-sdk` is the SDK twin of `reseat`: it re-writes the IDE's SDK Manager seats from the SDKs already on disk, with no network and nothing downloaded again. It exists because that seat lives in the REGISTRY, so it only lands where the operator's own server can write it — if the SDK shows up for `delphi_build` but not in the IDE, run this from the server you started yourself and reopen the IDE (it reads that list at startup).

**You do NOT need one SDK per Linux, and that is the point.** A binary linked against an OLD glibc runs on newer distributions; the reverse dies with `GLIBC_2.xx not found`. So keep pulling each target into its own folder, and build everything with the one whose glibc is the OLDEST in your fleet — `command=profiles` reports the `glibc` of every SDK you have (the IDE's own included) plus a `warning` on any folder that holds two distributions.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | platforms (what this server can target + profile/SDK status) \| packages (PAServer installers) \| profiles (registered profiles and SDKs, plus what the IDE's own registry holds: `ideRegistrySeats` for the connection profiles, `ideSdkSeats` for the SDKs and `ideSdkDefaults` for the SDK each platform builds with when nobody says - files on one side, registry on the other, and the pair tells you why the IDE shows what it shows) \| reseat (write the missing IDE seats for profiles already on disk; no PAServer, no passwords needed) \| add-profile (register a profile: name, host, password; optional port, platform) \| remove-profile (delete one by name) \| test-connection (with name: full handshake; with host+port and no name: raw TCP probe) \| get-sdk (pull the SDK/sysroot of profile "name" into a folder of its own, named after the target distribution) \| reseat-sdk (re-write the IDE SDK Manager seats of the SDKs already on disk - no network, nothing downloaded again) \| remove-sdk (take an SDK out of the way: its `.sdk` file and its IDE seat. The sysroot itself - gigabytes - is NOT deleted: the answer says where it is) \| remote-run (run the program `project` DEPLOYED on the target of profile "name"; the remote path is derived by the server, never given; nothing installed on the target - PAServer itself launches it) \| kill (stop a program a remote-run left running: `name`, `project`, `job`). Default: platforms |
| `name` | string | optional | Profile name (letters, digits, `_`, `-`): add-profile creates it, test-connection dials it, get-sdk pulls from it |
| `sdk` | string | optional | get-sdk: the NAME for the SDK it writes (its own folder). Default: the target's distribution, read from its `/etc/os-release` — `zorin18`, `fedora44`, `ubuntu2404` |
| `active` | string | optional | get-sdk: make this the ACTIVE SDK of the platform — the bold entry of the IDE's SDK Manager, the one a project builds with when it declares none (the dialog's "Make the selected SDK active"). Default: NOTHING is touched; `si`/`yes`/`true`/`1` makes it active, anything else leaves the seat alone |
| `host` | string | optional | Host or IP where the target PAServer listens (add-profile, or test-connection without name for the raw TCP probe) |
| `port` | string | optional | Port of the target PAServer (add-profile / test-connection). Default: 64211 |
| `password` | string | optional | The PAServer password (add-profile). Used once to create the profile, stored encrypted, never shown back - and masked in the server logs |
| `platform` | string | optional | Platform of the profile: Win32 \| Win64 \| WinARM64EC \| OSX64 \| Linux64. Default: Linux64 |
| `project` | string | optional | remote-run: the `.dproj` whose DEPLOYED program you want to run. The server derives the remote path (`<user>-<profile>/<Project>/<Project>`) — nothing else of the target can be executed |
| `exe` | string | optional | remote-run: another file OF THAT SAME deploy folder instead of the project binary — a plain file name, no separators, no `..` |
| `args` | string | optional | remote-run: command-line arguments for the program (no shell metacharacters) |
| `timeoutms` | integer | optional | remote-run: max milliseconds to wait for the program (default 30000, max 300000) |
| `job` | string | optional | kill: the `jobId` a remote-run answer gave you. With `name` and `project`: only a job of THAT project on THAT machine can be killed |

`remote-run` also needs TWO declarations in the calling workspace: `AllowRemoteRun=1` and a `RemoteRunProjects=` list naming the project (an empty list allows nothing - fail closed). OFF by default, and the only way this product executes a program.

**Stopping what you started.** A program that outlives the timeout is left running on purpose (`stillRunning=true`, a window is meant to stay up) - and since 1.0.16 the same answer carries a `killNote`: `command=kill name=<profile> project=<the same .dproj> job=<jobId>` stops it. It is not a general kill: the launcher wrote `<job>.pid` next to the program when it started it and its watcher removes it when the program ends, so `kill` can only reach a job this server started for THAT project on THAT machine (SIGTERM, three seconds of grace, then SIGKILL on Linux; `TerminateProcess` on Windows). A job that already ended answers `killed=false` and says so. Measured 2026-09-22 on Zorin and Windows.

**How a run travels, on every target.** `paclient` has no "execute" operation, and PAServer starts an uploaded file only without arguments and waits for it to end (measured 2026-09-22 on Zorin, Fedora and Windows). So the server uploads a job file (`run-<job>.job`: the binary, the output file, then ONE ARGUMENT PER LINE) and the native launcher `node\McpRunJob` (the ELF for a Linux, `McpRunJob.exe` for a Windows), named `run-<job>`, which PAServer starts (`--put` flag 3 on Linux, flag 5 on Windows). The launcher reads and deletes its job, writes `___ENV=`, checks the binary is native (ELF or PE - a script in the deploy folder is refused), starts it unattended with its output in `<job>.out` and its arguments as argv, leaves a watcher that appends `___RC=<code>` when the program ends, and returns at once so PAServer and `paclient` are free. **There is no shell anywhere in the path**: nothing to quote, nothing to inject. Until 1.0.15 Linux went through a `/bin/sh` script composed by the server (where the 1.0.15 injection lived) and Windows through the launcher; since 1.0.16 both are the launcher, one source (`src_run_job/`) compiled for each system.

The launcher also takes care of the **graphical environment** of the target. On Linux a PAServer started as a service (the normal setup) is born outside the desktop session and a program with a window dies at once (GTK, exit 134, "Can't create a GtkStyleContext without a display connection"); before launching, the launcher completes only what is MISSING - `XDG_RUNTIME_DIR`, the session D-Bus, `WAYLAND_DISPLAY`, `DISPLAY` and the newest `XAUTHORITY` - from the session of the SAME user PAServer runs as. On Windows it reports the SESSION it runs in: a Windows service lives in session 0, which has no desktop. Every answer says which case it met in `graphicalEnv`: inherited (nothing added), completed (lists the variables), no graphical session at all (a console program runs anyway), or the Windows session number. Measured on a Fedora with PAServer as a systemd service, a Zorin with PAServer in the session and a Windows with PAServer in the user's session (2026-09-22).

### `delphi_adb`

Android devices for remote development: the phones/tablets hang off THIS server (USB or wifi adb), while you program from anywhere. command=discover finds devices ANNOUNCING wireless debugging on the server's network (mDNS) and hands you each one's ip:port; command=devices lists what adb has ATTACHED (the same list the IDE shows as deploy targets); command=connect attaches one over the network (the device shows an authorize prompt the first time); command=disconnect detaches it; command=install installs a built .apk; command=run launches the installed app (the IDE's "Deploy and Run"); command=logcat hands you the device log (a bounded dump, optionally filtered) - remote debugging of the deployed app; command=screenshot grabs the device screen to a PNG you then `delphi_fetch` (your remote EYES) and command=tap / command=key touch the screen and press navigation keys (your remote HANDS) - enough to drive the deployed app end to end. The adb used is the IDE's own Android SDK's, discovered per install. Typical flow: discover → connect → devices → `delphi_build target=Deploy` → install → run → screenshot → tap → logcat.

**The screenshot says what the display really is.** Every `screenshot` answer carries `image` (the PNG's size) and `display` - the device's `physical` size, its `override` size when one is set and its `density`, from `wm size` / `wm density` - because `input tap` takes pixels of the display in force, not of the picture. Normally they are the same and what you measure on the image is what you tap; when they differ (a device that captures at another scale) the answer carries `tapScale {x, y}` and its note says to multiply first. A rotated display (WxH against HxW) is not a scale: screencap and input share the orientation.

*Access: mixed (discover / devices / logcat / screenshot read-only; connect / disconnect / install / run / tap / key read-write).*

Devices are allowlisted PER WORKSPACE — `AdbAllowedDevices=192.168.1.163;SERIAL123` in its section (semicolon list; an IP entry covers any port wifi debugging negotiates). Targets outside the workspace list are refused at BOTH access levels, every device-addressing command must name its `device` explicitly, and an absent list means NO devices (v0.98).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | discover \| devices (default) \| connect \| disconnect \| install \| run \| logcat \| screenshot \| tap \| key |
| `address` | string | optional | ip:port of the device for connect/disconnect (from command=discover, or the device's wireless-debugging screen) |
| `device` | string | **yes** for install/run/tap/key/logcat/screenshot | Device serial or ip:port (from command=devices). REQUIRED for every device-addressing command, and it must be in the workspace's `AdbAllowedDevices` list |
| `apk` | string | optional | install: path of the .apk (inside the workspace). Build it with `delphi_build target=Deploy` |
| `app` | string | optional | run: package name of the installed app (e.g. com.embarcadero.MiApp - the build/install results state it) |
| `out` | string | optional | screenshot / logcat: optional since 1.0.14 — a FOLDER, or a FILE whose extension matches (`.png` for screenshot, `.txt`/`.log` for logcat); empty = `__delphi-temp\<agent>` under the workspace. screenshot: where the PNG lands (then delphi_fetch it). logcat: dump into a file instead of answering inline — then read it in RANGES with `delphi_read` (400 lines/call). Inside the workspace |
| `x` / `y` | string | optional | tap: coordinates in DISPLAY pixels, measured on a screenshot - when that answer carried `tapScale`, multiply by it first |
| `key` | string | optional | key: back \| home \| enter \| appswitch \| wakeup \| up \| down \| left \| right \| tab |
| `filter` | string | optional | logcat: only lines containing this text (e.g. your app tag or package) |
| `lines` | string | optional | logcat: how many recent lines to capture (default 300, max 5000; 0 = default). Inline answers carry at most the newest 400 — bigger dumps via `out=` |

### `delphi_desktop`

The desktop of the machine behind a PAServer profile - a Linux target, a Windows target, or **this server itself** when a PAServer runs in its own user session - the way `delphi_adb` gives you an Android one: SEE the screen and ACT on it. Until 1.0.15 this tool was `delphi_adb_linux`, and a second tool called `delphi_desktop` ran the node locally under a switch of its own (`AllowDesktopControl`): two paths and two permission models for one thing. Since 1.0.16 there is ONE path, PAServer and a profile, and the machine is a parameter; `delphi_adb_linux` stayed two releases as a deprecated alias and no longer exists, and neither does `AllowDesktopControl`.

The machine hangs off a PAServer profile (the same profiles `delphi_paserver` builds and deploys with) and runs a small Delphi node **this server deploys and updates by itself**, the right binary for that system (the ELF for a Linux, the `.exe` for a Windows, read from the profile's own platform) - nothing else is installed on it. With `project` empty (the normal case) the bundled node is pushed to the target on first use and refreshed whenever its version stamp stops matching: the server compares the target's `node.ver` (the binary's SHA-256) against its bundled copy once per profile and session, so an updated server heals every already-provisioned machine on the next gesture. The node's sources live in `src_desktop_node/`. **Linux: GNOME only for now** (Zorin 18 and Fedora, measured): portal capture, Mutter scale, Super overview. **Windows: measured 2026-09-22** against a PAServer running in the user's session of this very server (`windows-local`, 127.0.0.1).

THE FLOW, and it is the whole trick: `command=screenshot` brings the WHOLE desktop here as a PNG; you LOOK at it, measure the pixel you want, `command=tap` presses exactly there and `command=type` writes text (with `x`,`y` it presses there first - the real gesture is "write this here", and it pays the startup once) - x and y measured *on that screenshot*, because the node converts the screen scale itself. An agent never deals with logical versus physical coordinates: it acts on what it sees. `command=key` presses one key - on a Linux target by its Linux code (evdev, NOT X11 keycodes: Escape 1, Tab 15, Enter 28), on a Windows target by NAME (escape, enter, tab, f4...); the tool reads the profile's platform and refuses the other kind, because a number on Windows would press a different key - and with `modifiers` held (`ctrl`, `shift`, `alt`, `super`): Ctrl+K, Alt+Tab, Ctrl+Shift+S are one gesture on both targets (an agent in the field found a field that only opens with Ctrl+K and no way to send it). `command=type` writes with the keyboard the target really has: on Linux the desktop's own keymap, DEAD KEYS included - "í" is typed as the dead acute key and then "i", exactly as a person does on a Spanish keyboard (without dead keys every accented letter was refused on a Spanish layout, measured by a field agent); a character the layout cannot produce at all is still refused by name. Every answer with a capture carries `windows`: title and rectangle of each window in pixels of that capture, on both targets - on Windows every visible top-level window, on Linux the X11/Xwayland ones, which is every FMX application (native Wayland windows such as the terminal are not listed, and `windowsNote` says so). Tap inside one, or crop to it with `window=`. `command=overview` brings them ALL into view when one covers another: on Linux the Super overview (every window reduced, its icon underneath - tap one or Escape; the answer's `overviewNote` explains it), on Windows a fresh capture with the list. If the enumeration fails the capture still comes back and the node output says why. `command=status` says whether the desktop is reachable and, when it is not, what to ask the operator for. Every answer carries `graphicalEnv`: the session the node ran in.

**How a gesture travels.** The same way as `remote-run`, on every system: a job file with the node's arguments one per line and the native launcher `node\McpRunJob` / `McpRunJob.exe` that PAServer starts - no shell in the path, so the text you type reaches the node untouched. A Windows PAServer must run **inside the user's session**: a Windows service lives in session 0, which has no desktop, and `graphicalEnv` says so.

The target needs a graphical session open - a headless box has nothing to show - for the SAME user PAServer runs as. On GNOME **the screen-capture permission must have been granted once** on that machine, as part of setting it up; without it the desktop portal tries to ask, and when it cannot paint its dialog - a remote session, a locked screen - it answers nothing: the symptom is a mute 20-second timeout that names no cause. A locked Windows answers "Access denied" to any capture, and the tool says so in `hint`. An UNLOCKED Windows sometimes answers the same to the screen copy (measured 2026-09-22, one capture in a few); then the node composes the desktop window by window from the DWM surfaces (`PrintWindow`) and says so in a `RESPALDO:` line of `nodeOutput` - that capture has every window with its real pixels but no cursor and no taskbar, and `hint` is only given when there is no capture at all.

**Coordinates are real pixels** on both systems: the Windows node is DPI-aware, so what it reports matches the screenshot exactly; a tool that is NOT DPI-aware sees the same window somewhere else (on a 125% display, the same Notepad was at 600,254 for a non-aware caller and at 750,318 for the node). Measure on the screenshot or on `windows`, never mix in coordinates from another source.

**A crop when you need detail, the whole desktop when you need the truth.** A small dialog on a 3440-pixel screen is unreadable in the whole-desktop image - the API shrinks every picture to one fixed size, so a crop buys detail, not tokens. `screenshot region="x,y,w,h"` returns only that piece of the SAME capture (cropped on the server, `Lsp.Imagen`, so it works on every target), and `screenshot window="<part of a title>"` does the measuring for you on a Windows target (the node lists the visible windows with their rectangles; on Linux the desktop does not hand rectangles out, so `window` is refused there and you use `region`). Every cropped answer carries `origin {x,y}`, `region` and `croppedFrom`, and its note spells the rule: what you measure on the crop is pressed at (origin.x + x, origin.y + y) - one frame, one coordinate space, never a second one. Against the old trap (a modal opened elsewhere and the agent, looking at one window, never saw it): on Windows every cropped answer also carries the full `windows` list, so a dialog outside the crop still shows by title; on Linux the rule is the old one - when in doubt, capture the whole desktop. Measured 2026-09-22.

**The target machine is the unit of exclusion, not the call.** `profile` says which machine every gesture goes to - the server never remembers a "current profile" - so one agent can drive two machines at the same time and nothing mixes. Gestures to the SAME profile are serialized (the node writes its capture in its own deploy folder on that machine), and each capture lands here named after its profile, so two machines answering at once never overwrite one another.

*Access: read-write (tap, type and key act on the target's desktop; screenshot and status are read-only in spirit but travel the same path), refused to a read-only credential. It runs under the SAME workspace switches as remote-run: `AllowRemoteRun=1`, `McpDesktopNode` (or the wildcard `all`) in `RemoteRunProjects`, and the profile's host inside `RemoteHosts` - the server's own desktop is just the profile whose host is `127.0.0.1`. Remember whose screen a profile may be: an operator's own machine is in frame, whatever they have open.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | screenshot (default) \| tap \| type \| key \| overview \| status |
| `profile` | string | required | PAServer profile of the target machine - a Linux, a Windows, or this server itself when a PAServer runs in its user session (`delphi_paserver command=profiles` lists them). The desktop is THAT machine's, never the agent's |
| `project` | string | optional | Empty (normal): the BUNDLED node is deployed/updated automatically. A .dproj path only when developing the node itself (deployed via `delphi_build target=Deploy`) |
| `x` / `y` | string | optional | tap: the pixel MEASURED ON THE SCREENSHOT this tool returned |
| `text` | string | optional | type: the text to write, key by key. On Linux it uses the keyboard layout the TARGET desktop really has (the desktop hands its keymap over): any character that layout gives with a key, Shift or AltGr; a character it has no key for is refused BY NAME, and the answer says which keyboard was used. On Windows it is typed as Unicode. Typed as TEXT, never run: quotes, `;` and `$` arrive as characters. With `x`,`y` it presses there first to focus the field: one trip, one startup |
| `code` | string | optional | key. Linux target: the Linux (evdev) key code - Escape 1, Tab 15, Enter 28, left Alt 56, Super 125. Windows target: the key NAME - escape, enter, tab, space, backspace, delete, home, end, up, down, left, right, super, alt, ctrl, shift, f1..f12 |
| `modifiers` | string | optional | key: modifier keys held while `code` is pressed - `ctrl`, `shift`, `alt`, `super`, comma separated (Ctrl+K on Linux: `code=37 modifiers=ctrl`). Pressed in that order, released in reverse, one gesture, both targets |
| `out` | string | optional | screenshot: folder (or file with the capture's real extension) where the PNG lands, jailed like any path of ours. Retrieve it with `delphi_fetch` |
| `region` | string | optional | screenshot: `x,y,w,h` in DESKTOP pixels - the answer is only that piece of the same capture, at full resolution, with `origin {x,y}`: what you measure on the crop is pressed at (origin.x + x, origin.y + y) |
| `window` | string | optional | screenshot: part of a window title - the capture cropped to the first window of the `windows` list whose title contains it, with `origin` like region, plus the whole list. On Linux the list holds the X11/Xwayland windows (every FMX application); a native Wayland window has no rectangle: use `region` |

### `delphi_components`

What this server's RAD Studio has INSTALLED to program with: every component/design package REGISTERED in the IDE (Known Packages — the same list the IDE loads into its palette), whatever the install channel: GetIt, a vendor installer or manual. Each line is the package's description plus its `.bpl` file; disabled packages are marked, IDE-plumbing packages are excluded. Read-only by design — there is no install command; if a library you need is missing, say so with delphi_report. The base RTL units are always available and never appear here.

*Access: read-only (always available).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `filter` | string | optional | Only entries whose description or file name contains this text (case-insensitive), e.g. "FMX", "TMS", "JEDI" |
| `platform` | string | optional | A platform (Win32, Win64, Linux64, Android64, OSX64, iOSDevice64...) to see instead the IDE's Library Search Path FOR THAT PLATFORM, expanded, plus the component install roots other platforms register and this one does not — the list to walk when a build on a new platform fails with F2613 (unit not found): `delphi_config add-searchpath` to the Source folder |


### `delphi_rename_symbol`

SEMANTIC RENAME. Point at the identifier (path + 0-based line/character, same convention as delphi_definition) and give `newname`. `mode=preview` (default, never writes) lists every CONFIRMED occurrence (each one re-resolved against the same definition), the files touched, and whether the rename is APPLICABLE. The rule is strict on purpose: one single unverified reference, a hit in a `.dfm`/`.fmx` (form bindings break), a hit inside a string literal (FindComponent/RTTI/StyleLookup by name), a symbol whose definition lives outside the workspace (RTL/components), or a collision with the new name = `applicable=false` with the reasons.

**`mode=apply` (1.0.17) writes it - through the changeset engine, not on its own.** The same analysis runs first; when applicable, every touched line is staged as one edit (the identifier replaced as a WORD, so a qualified header `TClass.Method` keeps its class and two occurrences on one line change at once), the batch is previewed and committed: all files or none, fingerprints re-checked, a byte snapshot of each file taken first and a copy in `__delphi-patch` as with any edit. The answer is the preview's plus `applied`, `editsApplied` and the `commit` audit; not applicable = `applied:false`, nothing written, blockers given. Mentions in comments are renamed only on lines that also carry a real occurrence; the rest come back as `warnings`. Rebuild afterwards - the tool does not.

*Access: preview read-only; apply read-write (jailed and refused to a read-only credential, like every write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | The .pas/.dpr with the symbol (any occurrence works) |
| `line` | integer | **yes** | Zero-based line of the identifier |
| `character` | integer | **yes** | Zero-based column inside the identifier |
| `newname` | string | **yes** | The new identifier (legal Delphi name, no reserved words) |
| `mode` | string | optional | preview (default; never writes) \| apply (writes the rename when applicable, through the changeset engine: all files or none, backups in `__delphi-patch`) |

### `delphi_designer`

FORMS AND COMPONENTS, structured — never guess what a class publishes or what a form contains. `info class=TButton`: every property the framework really publishes for that class (kind and type, events apart), from RTTI tables generated at release time (`tools/designer-meta-dump`). `prop class=X prop=Y`: one property in detail, with the legal members when it is an enum/set and the runtime class of class-typed properties. `tree path=<.dfm|.fmx>`: the component tree (name, class, line). `get path=... component=<Name>`: that component's block verbatim. `lint path=...`: unknown classes (warned once per class; root, inherited and inline excluded), properties the class does not publish, enum values that do not exist. `check-binding path=<.dfm|.fmx>` (+ `unit` when the .pas is not beside it): does the designer agree with the form class in the .pas — components with no published field, events naming a method that is not published, published fields with no component, duplicate names, all of which compile and then throw when the form is created. `layout path=<.dfm>`: WHERE things end up on a VCL form — resolves Align and returns every control's rectangle plus the ones of size zero, outside their container, overlapping or clipped by the bands around them. Text designers only (binary TPF0 refused). Read-only: editing a form is phase 2 and will go through `delphi_changeset`.

*Access: read-only (always available).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | info (what a class publishes) \| prop (one property in detail) \| tree (component tree of a .dfm/.fmx; a BINARY .dfm is read on the fly, the IDE's own conversion, and the answer says so) \| get (one component's block) \| lint (designer lint on demand) \| check-binding (does the .dfm agree with the class in the .pas: components with no published field, events naming a method that is not published, published fields with no component, duplicate names - all of which COMPILE and then throw when the form is created) \| layout (WHERE things end up on a VCL .dfm: resolves Align and returns the resolved rectangle of every control plus controls of size zero, outside their container, overlapping, or clipped by the bands around them - a form can bind perfectly and still be unusable) \| to-text (a BINARY .dfm becomes text on disk, the same conversion the IDE runs on "View as Text", backup in `__delphi-patch` first; reading never needs it, editing does) \| to-binary (the way back: the resource-wrapped form the IDE writes, reproduced byte for byte). Default: info |
| `path` | string | optional | tree/get/lint/check-binding/layout/to-text/to-binary: the .dfm or .fmx file. A binary .dfm is read on the fly (`binaryOnDiskNote` in the answer); a damaged one is refused with the RTL's reason; `.fmx` is always text |
| `unit` | string | optional | check-binding: the .pas of the form, when it is not next to the designer file (default: the same name beside it) |
| `classname` | string | optional | info/prop: the component class, e.g. TButton, TEdit, TLayout (`class` accepted as alias) |
| `prop` | string | optional | prop: the property name, e.g. Align, Caption, TextSettings |
| `component` | string | optional | get: the component Name as it appears in the form |
| `framework` | string | optional | info/prop: vcl \| fmx. Optional when path is given (.dfm=vcl, .fmx=fmx); default vcl |
| `filter` | string | optional | info: only properties whose name contains this text |

## FMX styles

### `delphi_styles`

FMX STYLES of a project, by StyleName: the text .style files (what the Bitmap Style Designer exports and a style pipeline keeps as source of truth). command=view lists the styles of a file (StyleName, class, lines, parts); get shows one whole; set changes or adds ONE property of a style or of a part inside it (child=background/text), value written exactly as the file does (xAARRGGBB colors, floats with 18 decimals, quoted strings); clone copies a style under a new StyleName - the way to add a variant; lint checks the whole thing: duplicated StyleNames, StyleLookup values in the project's .fmx/.pas that NO style defines (the platform default style counts), design tokens missing in a theme of a *Tokens.ini, .rc entries whose file is missing; build converts every text .style of the folder to .bin.style (the form an app embeds: embedded TEXT loads but does not resolve StyleLookup) and compiles the folder's .rc to .res with brcc32. Binary styles are never edited. Edits keep encoding and leave a __delphi-patch copy.

*Access: mixed (view / get / lint read-only; set / clone / delete / build read-write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | view (styles of a .style file: StyleName, class, lines) \| get (one style, whole text) \| set (one property of a style or of one of its parts) \| clone (a new style copied from an existing one) \| delete (remove a whole style by StyleName; the __delphi-patch copy is the way back) \| lint (duplicated StyleNames, StyleLookup values of the project's .fmx that no style defines, design tokens missing in a theme, .rc entries without file) \| build (every text .style of the folder -> .bin.style, then the .rc -> .res with brcc32) |
| `path` | string | **yes** | The text .style file (view/get/set/clone) or the styles FOLDER (lint/build; a file is accepted too). Binary styles (FMX_STYLE / .bin.style) are refused for editing: edit the text one and run build |
| `project` | string | optional | lint: the project .dproj (or a folder) whose .fmx/.pas files are scanned for StyleLookup. Default: the parent folder of the styles folder |
| `style` | string | optional | get/set/clone: the StyleName of the style (top-level object of the container), e.g. buttonstyle or cardstyle |
| `child` | string | optional | set optional: a part inside the style, by StyleName or object name, as a path: background or background/text |
| `prop` | string | optional | set: the property, as written in the file: Fill.Color, Size.Height, Visible, TextSettings.Font.Size... |
| `value` | string | optional | set: the value EXACTLY as it appears in a .style file: xFFF6ECDB (colors AARRGGBB), 44.000000000000000000 (floats), True/False, 'text' (strings quoted), Center (enums) |
| `name` | string | optional | clone: the StyleName of the new style |
| `filter` | string | optional | view optional: substring the StyleName must contain |
| `delete` | boolean | optional | set: true = remove the property instead of setting it |

The server ships `DelphiStyleConvert.exe` next to its own exe for `build` and for the platform default style names used by `lint`.

## Transfer files

### `delphi_fetch`

Download a file FROM the server - the "get the deploy" tool: after delphi_build, fetch the exe (and any companion files listed with delphi_list) to run GUI apps on YOUR machine. Two ways: (1) the `download` field of the answer is a direct HTTP GET on this same server (`/files?path=...`) - run it with curl and your same Bearer token - the standard way for any file, installers and binaries included; (2) base64 chunks inline, for small files or clients without a shell: loop offset until eof=true, concatenate the decoded chunks, verify the sha256 (whole file, returned on the offset=0 call). Files over 4 MB answer with the download link only; pass maxbytes<=1048576 explicitly to get inline chunks instead. Jailed to the workspace roots and the read-only library zone.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file to download from the server |
| `offset` | integer | optional | Byte offset to start from (0 = beginning). Loop increasing it until eof=true and reassemble |
| `maxbytes` | integer | optional | Bytes per chunk (default and cap: 8388608 = 8 MB). On a file over 4 MB, an explicit value ≤ 1048576 is the opt-in for inline chunks instead of the link-only answer |

**Answer fields** (HTTP hosts): `path`, `size`, `offset`, `bytes`, `eof`, `sha256` (offset=0), `chunkBase64` (omitted on the link-only answer), **`download`** (relative URL, e.g. `/files?path=srvd%3A%5C...`), `downloadNote` (the exact `curl`), `note` (on the link-only answer).

#### The `/files` download route

`GET http://<host>:<port>/files?path=srvd:\...\file` with the same `Authorization: Bearer` header you use for `/mcp` (both tokens work — downloading is reading). Streams the file with `Content-Disposition` and an **`X-File-SHA256`** header to verify with `sha256sum`. Same read jail as `delphi_read`: outside the roots/library zone → 403; directories → 403 (never a listing); unserved virtual units and relative paths are refused by name without touching disk; missing → 404; other methods → 405. Example:

```bash
curl -H "Authorization: Bearer $TOKEN" -o LinuxPAServer37.0.tar.gz \
  "http://WINDOWS-HOST:3000/files?path=srvc%3A%5CProgram%20Files%20(x86)%5CEmbarcadero%5CStudio%5C37.0%5CPAServer%5CLinuxPAServer37.0.tar.gz"
```

### `delphi_upload`

Upload a file TO the server in base64 chunks - the mirror of delphi_fetch, for material you cannot recreate by editing: binaries (.res, icons, images), binary designer files, archives, reference material. Send chunks in order: offset=0 creates/truncates, later offsets append and must match the current size. Pass sha256 on the LAST chunk to have the server verify the assembled file. Jailed to the workspace roots; parent directories are created. For SOURCE CODE prefer delphi_edit / delphi_textedit (they audit encoding and keep backups).

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file to write ON the server (inside the workspace roots) |
| `chunkbase64` | string | **yes** | One chunk of the file, base64-encoded. offset=0 truncates/creates; later offsets append |
| `offset` | integer | optional | Byte offset this chunk starts at (0 = beginning). Send chunks in order, increasing offset by the bytes written |
| `sha256` | string | optional | Optional: on the LAST chunk, the whole-file SHA-256; the server verifies the assembled file and reports verified true/false |


## Version control

### `delphi_git`

Whitelisted git operations on a repository of this machine, so a remote agent can bring in code and version its work: status, diff, log, show, branch, switch (args=<branch>, create=true for a new one), merge (always --ff-only), stash (args=push|pop|list, never drop), add, commit, init, push, tag, config, clone, pull, fetch. **clone** is the fast way to get a whole repo onto the server (URL in "message", destination directory in "repo", jailed to the workspace roots) - far better than recreating files one by one. commit/tag messages and config values also travel in "message"; push/pull use the credentials and remotes stored on the server. No arbitrary git commands, no shell.

*Access: mixed (query commands read-only; write commands read-write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `repo` | string | **yes** | Path of the git repository (or any path inside it). For clone: the DESTINATION directory (created if needed, must be inside the workspace roots) |
| `command` | string | **yes** | One of: status \| diff \| log \| show \| branch \| switch \| merge \| stash \| add \| commit \| init \| push \| tag \| config \| clone \| pull \| fetch (config: args=user.name\|user.email + value in message; clone: URL in message, destination in repo) |
| `args` | string | optional | Optional extra arguments (paths, --staged, a commit hash...). Shell metacharacters are rejected |
| `create` | boolean | optional | `switch`: true = create the branch and move to it (`git switch -c`). Ignored by every other command |
| `message` | string | optional | commit: the commit message. tag: makes the tag annotated. config: the value. clone: the repository URL |


## Feedback

### `delphi_report`

Report a problem, limitation or suggestion about THIS MCP server directly to its maintainers. Use it whenever a tool refuses something you believe is legitimate, an answer looks wrong, a message is confusing, or you had to work around a missing capability - that feedback is what fixes the server. Each report is stored as its own timestamped markdown file in a reports folder next to the server executable, with the server version and the date; pass a short stable `agent` id and your reports get their own subfolder, separate from other agents. Available at EVERY access level, read-only included. Be concrete: what you tried, what happened, what you expected.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `message` | string | **yes** | The report itself: what you tried, what happened, what you expected. Markdown welcome, several paragraphs are fine. Up to 256 KB per report - split a longer one, reports accumulate and are never overwritten |
| `title` | string | optional | Optional one-line summary (becomes part of the file name) |
| `kind` | string | optional | Optional: bug \| limitation \| suggestion \| question (default: bug) |
| `from` | string | optional | Optional: who is reporting (agent/model name, project) - helps us read the history later |
| `agent` | string | optional | Optional short id of the reporting agent (e.g. "hermes"): its reports are stored in a folder of that name, separate from other agents. Keep it STABLE across your reports. Letters, digits and dashes |

---

## Typical workflows

Concrete sequences that string the tools together. Paths shown as `srvd:\...` are what the server hands you back.

### Get oriented on a fresh connection
1. `delphi_workspace` — the roots you may touch, your access level, the active Delphi, and `readableExtra` (RTL/VCL/FMX sources and components you may READ outside the roots).
2. `delphi_projects` (empty `root`) — every `.dproj`/`.groupproj` under the roots.
3. `delphi_list {root, dirs:true}` — browse a project's folders explorer-style; `delphi_list {root, pattern:"*.pas"}` to list sources.

### Understand a symbol
1. `delphi_read {path, fromline, toline}` — read the numbered lines (encoding-correct). Copy anchors from here.
2. Put the cursor **inside** an identifier and note its 0-based line/character.
3. `delphi_definition {path, line, character}` — the body; add `kind:"declaration"` for the interface declaration (works on call sites too).
4. `delphi_hover` for the type, `delphi_signature` for a call's parameters (point inside the parentheses), `delphi_references` to find uses.

### Edit a source safely
1. `delphi_read` the region; copy the exact line to replace.
2. `delphi_edit {path, old:"<the full line>", new:"<replacement>"}`. For a NEW routine use `insert:"rutina-global"` or `insert:"metodo"`+`inclass`+`code`; to remove a line use `delete:true`; to create a unit use `createunit:true` (+ optional `content`).
3. Read the tool's audit output (encoding, EOLs, the real lines re-read from disk). If it warns, `delphi_edit {path, restore:true}` then `confirm:true`.
4. `delphi_diagnostics {path}` — compiler codes with no build; then `delphi_build` as the real check.

### Non-Delphi files (docs, web assets, config)
Use `delphi_textedit` (same anchor/encoding/backup discipline) for `.md .html .js .css .py .ini ...`. `delphi_edit` refuses them on purpose.

### Scaffold a new project or form
`delphi_create {kind:"project-vcl"|"project-fmx"|"project-console"|"project-package", dir, name}`, or `{kind:"form-vcl"|"form-fmx"|"frame-vcl"|"frame-fmx"|"datamodule"|"unit", project, name}` (registered in the `.dpr` and the `.dproj` on creation). An existing `.pas` joins with `delphi_config {project, command:"add-unit", path}`; `remove-unit` takes it out and keeps the file. `delphi_delete`/`delphi_move` on a unit keep the projects that list it consistent (designer pair included).

### Build and get the binary onto your machine
1. `delphi_build {project, platform:"Win64", config:"Debug", target:"Build"}` — structured errors/warnings.
2. `delphi_package {dir:"...\Win64\Debug"}` to zip the deploy, then `delphi_fetch {path:"...deploy.zip"}` in a loop (increase `offset` until `eof:true`), verifying the whole-file `sha256` — and run it on YOUR machine, **or**
3. deploy it to a target: `delphi_build {target:"Deploy", profile}` + `delphi_paserver {command:"remote-run"}` on a PAServer machine, or `delphi_adb {command:"install"}` on an Android device. Nothing executes on the server itself except a test project through `delphi_test` (`AllowTests`).

### Bring a repository onto the server, work, commit
1. `delphi_git {command:"clone", message:"https://...", repo:"srvd:\...\dest"}` — the whole repo in one call, jailed.
2. Edit with the tools above.
3. `delphi_git {command:"add", args:"-A"}` → `{command:"commit", message:"..."}` → `{command:"push"}` (uses the server's stored credentials). Set identity first with `{command:"config", args:"user.name", message:"..."}`.

### Send a file TO the server
`delphi_upload {path, offset:0, chunkbase64:"..."}` per chunk (increasing `offset`); on the last chunk pass the whole-file `sha256` to have the server verify the reassembly. For binaries you cannot recreate by editing (`.res`, icons).

### Build, deploy and run on another platform (Linux/macOS via PAServer)

> **Bootstrapping a target needs hands ON the machine — and they do not have to be human.** Everything this server does on a Linux/macOS machine — deploy, execute, the desktop node — travels through a PAServer already listening there. This server cannot start the first one from outside: with nothing listening there is no way in (the same bootstrap adb has — nothing enters a phone until USB debugging is enabled on the phone itself). The hands can be a person's, or an **AI agent running on the target** (OpenCode, Claude, ...): a local agent prepares the machine autonomously through this same MCP — `delphi_paserver {command:"packages"}` to learn the right installer, `delphi_fetch` to download it, then unpack and start it from inside the user's graphical session it runs in. Once that first channel is live, this server operates the machine from outside from then on.
>
> **While you are there, grant the screen-capture permission too** — it belongs to the same one-time setup as starting PAServer, and skipping it is expensive. The first capture on a machine makes the desktop portal ask for consent; if that dialog cannot be painted (a remote session, a locked screen), the portal answers **nothing at all** and `delphi_desktop` dies on a mute 20 s timeout with no hint of what is missing. Measured on a fresh Zorin 18 / GNOME on 2026-09-19: `journalctl --user -u xdg-desktop-portal.service` said `Failed to show access dialog: timeout reached`. Trigger the dialog on purpose once, with the screen in front of you, and accept it — everything after that is silent:
>
> ```
> gdbus call --session --dest org.freedesktop.portal.Desktop \
>   --object-path /org/freedesktop/portal/desktop \
>   --method org.freedesktop.portal.Screenshot.Screenshot "" "{'interactive': <true>}"
> ```
>
> The grant is stored per requesting app id (`~/.local/share/flatpak/db/screenshot`), so it survives reboots and only has to be given once per machine.

#### Setting up a Windows target: PAServer first, like everywhere else

**An agent reaches a Windows desktop only through a PAServer listening on that machine** - a remote Windows or this server's own: the node and every gesture travel through PAServer and are started by it, so without one there is nothing to talk to, whatever the network says. Three things, once, on that machine (measured 2026-09-22 against a second Windows on the LAN):

1. **Start PAServer inside the user's session** - from a terminal of that session, never as a service: a Windows service lives in session 0, which has no desktop, and `graphicalEnv` says so. It ships with RAD Studio (`C:\Program Files (x86)\Embarcadero\PAServer\37.0\paserver.exe`; `delphi_paserver command=packages` names the installer for a machine without the IDE):
   ```
   & "C:\Program Files (x86)\Embarcadero\PAServer\37.0\paserver.exe" -port=64211 -password=<yours>
   ```
2. **Open the port in THAT machine's firewall** - Windows' own or the antivirus suite's. Measured: the port answered nothing until a rule was added in ESET's firewall; Windows' was not the one blocking. `test-connection host=<ip> port=64211` with no name is the probe: `tcpReachable=false` with the machine answering a ping is a firewall.
3. **Register the profile from here**: `add-profile name=<name> host=<ip> port=64211 password=<yours> platform=Win64`, then `test-connection name=<name>` for the full handshake. The host must be inside the workspace's `RemoteHosts`.

From then on `delphi_desktop profile=<name>` does the rest by itself: the first gesture deploys the node (`nodeDeploy: desplegado`), and capture, `windows`, `window=` crops and `tap` work as on Linux. Nothing else is installed on that machine.

#### Setting up a new Linux target: what happens ON the machine, and what this server does

Two things need hands on the target — a person's or a local AI agent's — and everything else is the server's. Knowing which is which is the difference between ten minutes and a lost morning (measured, 2026-09-19, on a Zorin 18):

| On the machine, once | Why it cannot come from here |
|---|---|
| **1. Install and start PAServer, inside the graphical session** (a terminal in the session, never SSH) | It is the only channel in; with nothing listening there is no way to reach the machine. And the desktop node inherits the session's D-Bus from it, so a PAServer started outside the session can deploy but cannot drive the screen |
| **2. Grant the screen-capture permission**, with the screen in front of you (see the note above) | The portal asks the human at the machine. If it cannot paint its dialog it answers *nothing*, and every capture dies on a mute timeout |
| **3. That is all.** Running a deployed program, holding a GUI open to drive it, collecting output - it all travels through PAServer now (v0.98 removed the on-target runner and its Python dependency) | - |

From then on this server does the rest with no hands anywhere: `get-sdk` (once per target), `delphi_build` (compile), `target=Deploy` (ship), `remote-run` (run the deployed binary and collect its output), and the whole of `delphi_desktop` — see the desktop, press, type, show windows.

1. `delphi_config {project}` — see the framework and platforms. **VCL is Windows-only**; only FMX or console apps cross.
2. `delphi_config {project, command:"add-platform", platform:"Linux64"}` — enable the platform (refused on a VCL project, with the reason).
3. `delphi_paserver {command:"packages"}` — get the PAServer installer; download it with `delphi_fetch` and run it on the target (it listens on port 64211).
4. `delphi_paserver {command:"test-connection", host:"...", port:"64211"}` — raw TCP probe: does this server reach your PAServer at all? Then `{command:"add-profile", name:"mi-linux", host, password}` and `{command:"test-connection", name:"mi-linux"}` — full handshake.
5. `delphi_paserver {command:"get-sdk", name:"mi-linux"}` — pull the SDK/sysroot once (can take minutes); after this the linker works.
6. `delphi_build {project, platform:"Linux64", config:"Debug"}` — build; add `target:"Deploy", profile:"mi-linux"` to build **and ship** to the target's PAServer scratch dir, exec bit set.

### Deploy and drive an app on an Android device (the device hangs off the server)
1. `delphi_adb {command:"discover"}` — devices announcing wireless debugging on the server's network, each with its ip:port (or the developer reads it off the device screen and hands it to you).
2. `delphi_adb {command:"connect", address:"192.168.1.163:5556"}` — attach it (the device asks to authorize the first time); `{command:"devices"}` lists what is attached.
3. `delphi_config {project, command:"add-platform", platform:"Android64"}` then `delphi_build {project, platform:"Android64", config:"Debug", target:"Deploy"}` — the server generates the deployment manifest if the project has none and the result declares the built `.apk`.
4. `delphi_adb {command:"install", apk:"...\bin\App.apk", device:"..."}` → `{command:"run", app:"com.embarcadero.App", device:"..."}` — the IDE's "Deploy and Run", by tools.
5. `delphi_adb {command:"screenshot", out:"...\pantalla.png", device:"..."}` (then `delphi_fetch` it), `{command:"tap", x, y}`, `{command:"key", key:"back"}`, `{command:"logcat", filter:"MiApp"}` — your remote eyes and hands to drive and debug it.

### Report a problem
`delphi_report {message, title, kind:"bug"|"limitation"|"suggestion"|"question", from}` — stored as a dated markdown next to the server exe. Works even read-only; use it whenever a tool blocks something you believe is legitimate.


### `delphi_messages`

Your MAILBOX: messages the operator leaves for you (the way back of delphi_report). command=read delivers every pending message addressed to your agent id or to everyone, once; check only lists what waits. While mail waits, every tool answer ends with a MENSAJES PENDIENTES line - read it then: it may change what you are doing.

*Access: read-only.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | read (default: deliver every pending message for this agent, then mark it delivered) \| check (titles and dates of what is pending, nothing consumed) |
| `agent` | string | optional | Your agent id - the same value you give delphi_report as "agent" (e.g. dsh, hermes). Messages addressed to everyone are delivered too |

Operator side: drop a `.md` in `messages\<agent>\` or `messages\` next to the server exe (`scripts\Enviar-Mensaje.ps1 -Agente dsh -Titulo ... -Texto ...`). A message addressed to ONE agent moves to `messages\_entregados\<agent>\` when it is delivered. A message left in the ROOT is for **everyone**: it stays there and each agent gets a copy in `messages\_entregados\<agent>\` as the mark that it already read it — so it reaches all of them and none of them twice. Retire it when it has been seen (after `MessagesRetentionDays`, 30 by default, the marks are purged and it would be delivered again). A caller with no identity — stdio, the operator's own console — still takes it off the board, the same rule the recoverable trash uses.

## Knowledge vault (optional — only for workspaces that declare `VaultPath=`)

Persistent memory: a folder of Markdown notes linked with `[[wikilinks]]`.
These tools are **not registered at all** unless a vault is configured, and the
three write ones need the workspace's `VaultReadOnly=0` on top of a read-write credential.

- **Start with `vault_read` and NO path**: it returns the vault's rules plus its
  index, which is how you decide what to load. Lazy loading — never read a vault
  in bulk.
- Paths are **relative to the vault** (`projects/x/context.md`), `.md` only. The
  vault is a separate jail from the workspace roots.
- Before modifying any note the server copies the original to
  `backups/mcp/<timestamp>/`. The governance files (`AGENTS-VAULT.md`,
  `AGENTS-VAULT-WRITE.md`, `MEMORY.md`) are never writable.

Full explanation: [VAULT.md](VAULT.md).

### `vault_read`

Lee una nota del vault de conocimiento por ruta relativa. SIN path devuelve las reglas (AGENTS-VAULT.md) + el indice (MEMORY.md): hazlo al empezar. Los [[wikilinks]] del contenido refieren a otras notas - localizalas con vault_search target=files.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | optional | Ruta RELATIVA de la nota dentro del vault (projects/x/context.md). SIN path devuelve las reglas + el indice: hazlo al empezar |
| `offset` | number | optional | Opcional: primera linea a devolver (1 = principio) |
| `limit` | number | optional | Opcional: cuantas lineas devolver desde offset |

### `vault_search`

Busca en el vault de conocimiento (notas Markdown enlazadas con [[wikilinks]]). PROTOCOLO: al empezar una tarea, llama primero a vault_read SIN path para obtener las reglas y el indice; decide por las descripciones del indice que notas cargar con vault_read - carga perezosa, nunca leas el vault en masa.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `target` | string | optional (default files) | files (buscar por NOMBRE de nota, patron glob como *reunion*.md) \| content (buscar DENTRO de las notas, pattern es una expresion regular) |
| `pattern` | string | **yes** | Glob de nombre si target=files (*.md, *delphi*), o expresion regular si target=content |
| `subfolder` | string | optional | Opcional: carpeta relativa del vault para acotar la busqueda (projects, conventions...) |
| `maxresults` | number | optional | Maximo de resultados (defecto 50) |

### `vault_append`

Anade contenido a una nota existente del vault (entradas de log, avances de progress). Escribe SIEMPRE en espanol. Formato log: entrada fechada bajo la seccion del dia. En progress.md respeta su estructura snapshot: lineas de estado vivas, el historico va en log - no acumules; si cierras un asunto, elimina su linea con vault_patch en lugar de anadir "hecho". El servidor guarda copia del original antes de escribir.

*Access: read-write only, and VaultReadOnly=0 en el workspace.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota (debe existir) |
| `content` | string | **yes** | Contenido markdown a anadir. En espanol |
| `anchor` | string | optional | Opcional: texto UNICO tras el cual insertar. Sin anchor, anade al final del fichero |

### `vault_create`

Crea una nota nueva en el vault. ANTES de crear: lee AGENTS-VAULT-WRITE.md (arbol de decision de donde va cada cosa y plantillas) y enlaza la nota con [[wikilinks]] desde las notas del proyecto (context.md, log.md, progress.md) - nunca desde MEMORY.md, el indice raiz, que se rechaza. Escribe en espanol. No reorganices carpetas ni muevas notas existentes - eso requiere OK humano. Nunca sobreescribe: si la nota existe, se rechaza.

*Access: read-write only, and VaultReadOnly=0 en el workspace.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota nueva (debe NO existir; nunca sobreescribe) |
| `content` | string | **yes** | Contenido markdown completo, con la estructura/plantilla que pida el vault |

### `vault_patch`

Edicion puntual de una nota: sustituye old_text (UNICO en el fichero) por new_text. Para tachar lineas cerradas de un progress o corregir un dato. Para anadir contenido usa vault_append; para reescrituras grandes, para y consulta al usuario. El servidor guarda copia del original antes de escribir.

*Access: read-write only, and VaultReadOnly=0 en el workspace.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota |
| `old_text` | string | **yes** | Texto a sustituir: debe aparecer EXACTAMENTE UNA VEZ en el fichero |
| `new_text` | string | **yes** | Texto nuevo que lo sustituye |
