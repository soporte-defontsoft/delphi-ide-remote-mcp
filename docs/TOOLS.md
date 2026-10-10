# Tool reference

Every tool this MCP server exposes, with its parameters, types and access level.

> **The contract of every tool below - its description and its parameter table - is GENERATED from the live `tools/list`** by `scripts/tools_md.py`, between two `<!-- contract -->` markers inside each section, and `tests/test_docs_consistency.py` fails when a block differs from the server; the *Access* line inside the block comes from the server's own access table (what `tools/list` announces as `annotations.readOnlyHint` and `_meta.access`, the same table its gate consults); the notes around each block (history, worked examples) are written by hand. Until 2026-09-28 the whole page was written by hand: an audit on 2026-09-20 found it missing the headline features of three releases, and a measurement on 2026-09-28 found 35 of 41 descriptions and 127 parameter texts saying something other than the server, with 4 parameters missing. The authority is still the server itself: **`delphi_help command=tool name=<tool>`** returns the live schema of one tool, and `docs/CAPABILITIES.json` is generated from the same `tools/list`. To refresh this page after changing a tool: `python scripts/tools_md.py`.

- **Paths** use virtual drive units (`srvd:\...`, `srvc:\...`) — call `delphi_workspace` first to learn the roots.
- **Positions** for the semantic tools are 0-based (line and character), like the LSP. Point *inside* the identifier. Every answer that names a location uses one convention (1.15.0): `line` is the 1-based line `delphi_read` shows and `delphi_edit` takes; `line0` and `character0` are the 0-based position the semantic tools take, so a hit is chained by passing its `line0`/`character0` (search, references, rename, symbols, definition). Definition and diagnostics keep the engine's raw `range` (0-based) next to them; hover answers its `range` only.
- **Access**: with a read-only credential only the read-only tools run; mutating ones are refused at the gate. Without a workspace token there is no access at all (HTTP 401; a tokenless local stdio process is read-only unless `DELPHI_MCP_ROOTS` gives it roots).
- **Required column**: every schema carries its real `required` list (the same one `delphi_help command=tool` returns); the table below says the same — the rest are optional and have sensible defaults, as their descriptions note.


> **Parameter aliases.** Some spellings are accepted as aliases and mapped to the declared name when it is absent: `vault_search query|filter` → `pattern`, `delphi_list filter|mask` → `pattern`, `delphi_components pattern|query` → `filter`, `delphi_read startline|endline` → `fromline|toline`, `delphi_search text` → `query`. The declared name always wins.

## Index

- **Understand the code (semantic, DelphiLSP-backed)** — [`delphi_symbols`](#delphi_symbols), [`delphi_definition`](#delphi_definition), [`delphi_signature`](#delphi_signature), [`delphi_hover`](#delphi_hover), [`delphi_completion`](#delphi_completion), [`delphi_references`](#delphi_references), [`delphi_diagnostics`](#delphi_diagnostics)
- **Read files & explore** — [`delphi_read`](#delphi_read), [`delphi_docs`](#delphi_docs), [`delphi_search`](#delphi_search), [`delphi_list`](#delphi_list), [`delphi_projects`](#delphi_projects), [`delphi_installs`](#delphi_installs), [`delphi_workspace`](#delphi_workspace)
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

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Document symbol tree of a Delphi unit (classes, methods, properties, sections) with 0-based ranges, from the official DelphiLSP engine; works without project settings. Big trees come as a compact summary by default (mode/filter control it); a FOLDER answers with the interface digest of every unit inside. The engine parses as the COMPILER would for Windows: code inside an inactive {$IFDEF} (LINUX, ANDROID, MACOS...) is not in the tree, and nothing says so - for those blocks use delphi_search or delphi_read.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | A Delphi file (.pas/.dpr) for its symbols - or a FOLDER: at once, what each unit in it OFFERS (its interface: types, classes, routines, properties, uses), without bodies - ONE call to find your way around code you did not write. |
| `mode` | string | optional | For a FILE only: summary = the skeleton (each section with its members and line; containers say how many they hold) \| full = the LSP tree with its ranges, minus what repeats. Empty = full if the tree is small, summary if large (the answer says which, and how big the full one was). |
| `filter` | string | optional | For a file: only the symbols whose name contains this (case-insensitive), with kind, declaration as written (decl), line and container. Ignores mode. The cheap way to find a method without the whole tree. |
<!-- /contract -->

**Since v1.0.7 each symbol also carries `decl`: the declaration as it is WRITTEN IN THE SOURCE.** DelphiLSP's `name` is not a name, it is a rendered signature, and it is lossy — `function Alta(const A: string; B: Integer = 0): Boolean` comes back as `Alta(const A: string; B: Integer)` and `FBuffer: array [0..7] of Byte` as `FBuffer: Byte`. The tree, the kinds and the lines are still the language server's; only the way a declaration is written is read from the file.

### `delphi_definition`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Resolve the identifier at a 0-based line:character position in a Delphi source file, using the official DelphiLSP engine (compiler-grade, cross-unit, including RTL/VCL sources). Point INSIDE the identifier. kind selects the half of the unit (a Delphi method exists in BOTH): definition (default) = the BODY in the implementation section; declaration = the interface declaration OF THE TARGET SYMBOL (on a call site the tool chains definition->declaration, so you get the callee; when definition does not resolve, the answer is the direct declaration and a note says so). (kind=implementation is accepted but DelphiLSP answers it like declaration - measured.) Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `kind` | string | optional | Optional: definition (default) \| declaration (jump to the interface declaration) \| implementation (accepted, but DelphiLSP answers it like declaration - measured) |
| `line` | integer | **yes** | Zero-based line number of the identifier: the "line0" of a search, references, symbols or definition hit (their "line" is 1-based) |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier (a hit's "character0") |
| `path` | string | **yes** | A Delphi file (.pas/.dpr/.dpk/.inc). ONE file goes here, not a folder: these tools resolve a position inside a source. To see at once what each unit of a folder offers, that is delphi_symbols. |
<!-- /contract -->

### `delphi_signature`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Signature help (parameter completion) for the call under a 0-based line:character position: the routine signatures with their parameter list, from the official DelphiLSP engine - the IDE's Ctrl+Shift+Space. Point INSIDE the parentheses of the call (right after "(" or a ","). Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `line` | integer | **yes** | Zero-based line number of the identifier: the "line0" of a search, references, symbols or definition hit (their "line" is 1-based) |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier (a hit's "character0") |
| `path` | string | **yes** | A Delphi file (.pas/.dpr/.dpk/.inc). ONE file goes here, not a folder: these tools resolve a position inside a source. To see at once what each unit of a folder offers, that is delphi_symbols. |
<!-- /contract -->

### `delphi_hover`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Type/signature information for the identifier at a 0-based line:character position (official DelphiLSP engine). IMPORTANT: hover answers on identifier USAGES (call sites, type references); hovering a declaration itself returns null. Requires project settings for full answers.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `line` | integer | **yes** | Zero-based line number of the identifier: the "line0" of a search, references, symbols or definition hit (their "line" is 1-based) |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier (a hit's "character0") |
| `path` | string | **yes** | A Delphi file (.pas/.dpr/.dpk/.inc). ONE file goes here, not a folder: these tools resolve a position inside a source. To see at once what each unit of a folder offers, that is delphi_symbols. |
<!-- /contract -->

### `delphi_completion`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Code completion candidates at a 0-based line:character position (official DelphiLSP engine). Returns at most 50 items (label/kind/detail) plus the total count.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `trigger` | string | optional | Optional trigger character, e.g. "." (empty = manual invocation) |
| `line` | integer | **yes** | Zero-based line number of the identifier: the "line0" of a search, references, symbols or definition hit (their "line" is 1-based) |
| `character` | integer | **yes** | Zero-based character (column) inside the identifier (a hit's "character0") |
| `path` | string | **yes** | A Delphi file (.pas/.dpr/.dpk/.inc). ONE file goes here, not a folder: these tools resolve a position inside a source. To see at once what each unit of a folder offers, that is delphi_symbols. |
<!-- /contract -->

### `delphi_references`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Find references to the identifier at a 0-based line:character position. Hybrid method (DelphiLSP has no native references): project-wide text scan, then every candidate is validated by asking the compiler engine for its definition - only candidates resolving to the SAME symbol are confirmed, homonyms are rejected. A name written in a COMMENT or inside a string literal is not a reference and does not count as unverified: those go to "mentions". A comment is harmless; a string literal blocks delphi_rename_symbol (RENAME-020), because it may be a FindComponent/RTTI by name. Bounded work: leftovers are listed as unverified, never silently dropped; a file it cannot read, as unreadable.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file |
| `line` | integer | **yes** | Zero-based line of the identifier to find references for (a hit's "line0"; its "line" is 1-based) |
| `character` | integer | **yes** | Zero-based character inside the identifier (a hit's "character0") |
<!-- /contract -->

### `delphi_diagnostics`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Compiler-grade errors/warnings/hints for one Delphi source file (Error Insight via the official DelphiLSP linter), WITHOUT building. Real compiler codes (E2003, W1000, H2164...) with exact 0-based positions (range) and line, the 1-based line delphi_read shows. Severity is the LSP scale: 1=error, 2=warning, 3=information, 4=hint. The "hints" counter groups 3 and 4 together; the per-diagnostic severity tells them apart. Lints the CURRENT on-disk content. A big unit can take over a minute the first time: the answer then says the lint is in progress - call again with the same file and the result is returned (the lint is not restarted while the file is unchanged).

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file to lint (.pas/.dpr) |
<!-- /contract -->

## Read files & explore

### `delphi_read`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Read a Delphi source file DECODED CORRECTLY (ANSI - the machine's code page, CP1252 on a Western Windows - / UTF-8 with or without BOM / UTF-16 / UTF-32 detected for real). Returns numbered lines in the format number|content - to build a delphi_edit anchor, copy everything after the bar, exactly. ALWAYS use this instead of a generic read for Delphi files: generic reads turn ANSI accents into U+FFFD and poison every anchor built from them.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi file (.pas/.dpr/.dpk/.inc/.dfm/.fmx) |
| `fromline` | integer | optional | First line to show, 1-based (0 = from the start) |
| `toline` | integer | optional | Last line to show, 1-based (0 = to the end; capped at 400 lines per call) |
<!-- /contract -->

### `delphi_docs`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

THE DELPHI DOCUMENTATION installed with RAD Studio - the F1 help of the version installed here: classes, routines and properties (RTL, VCL, FMX, FireDAC, Indy...), the language, the IDE, code examples, and the help of installed components that register one. command=search query=\<a concept or a class>: a short list of pages (id + title), best first - a qualified name (System.SysUtils.FormatDateTime, FMX.StdCtrls.TButton) lands on the exact page, a bare one (TButton, TStringList.Sort) or a concept ("class helpers") finds it too; framework=vcl|fmx puts that framework's page first when both have one. command=read id=\<an id of that list>: the page as plain text, in chunks (offset); a long page first gives its introduction and its sections, and \<id>#\<section> (its anchor or its title as the text shows it) reads one alone. The first chunk also lists related: the pages around it (a class: its unit and member lists; a topic: its parent index); other pages it names (See Also, examples) are found with search. Read-only, in any workspace, only the help files the IDE registers. It says what something is for and how it is used; for its exact signature, the installed sources win (delphi_hover, delphi_definition). The manual of THIS server is delphi_help.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | search (find pages: query) \| read (one page: id). Without it: read when there is an id (a query beside it is ignored), search when there is only a query |
| `query` | string | optional | search: a concept or a class, as you would type it in the IDE help: FormatDateTime, TStringList.Sort, FMX.StdCtrls.TButton, "anonymous methods" |
| `id` | string | optional | read: the id of a page, as a search gives it (system:System.SysUtils.FormatDateTime.htm); with #section, that section alone (its anchor or its title as the text shows it) |
| `framework` | string | optional | search optional: vcl \| fmx - the page of that framework first, when VCL and FMX both have one (TButton, TEdit) |
| `offset` | integer | optional | read optional: where to start in the text of the page (the nextOffset of the previous chunk) |
| `limit` | integer | optional | search optional: how many results (default 10, at most 25) |
<!-- /contract -->

The help files are the IDE's own list (`Help\HtmlHelp1Files` of the active Delphi, current user then machine), opened in any workspace - no switch: only the files the IDE registers, and an id never leaves its file - and read in place through Windows' help storage: nothing is extracted and nothing is cached, so a search reads the indexes again (0.4-0.7 s measured over 37 concepts and classes; a lone word found almost everywhere, such as `e` or `object`, takes 3-4 s). A typical walk: `search query=TEdit framework=fmx` → `read id=fmx:FMX.Edit.TEdit.htm` (its ancestors, its description, and `related` with its unit and its member lists) → `read id=fmx:FMX.Edit.TEdit_Events.htm` (one member per line). A long page answers first with its introduction and `sections`; `read id=<page>#<section>` gives one, named by its anchor or by its title as the text shows it (the answer's `id` carries the anchor). A section the rest of the page hangs from - `Description` in the API pages - stops where its first sub-section starts and lists them in `subsections` (1.12.0). The help can be older than the code: for an exact signature, `delphi_hover` / `delphi_definition` on the installed sources (1.10.0).

### `delphi_search`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Search Delphi sources recursively for a text (case-insensitive; literal, or a regular expression with regex=true), skipping IDE artifacts BELOW the root (__history, Win32/Win64, dcu, .git, the server's __delphi-temp...) - naming such a folder as root searches inside it, and skipped files are counted with why ("hidden" + "note"). Files are decoded with their real encoding, so accented text matches. Hits come grouped by folder and file: folders = [{dir, files = [{name, hits = [{line (1-based, as delphi_read numbers it), line0 and character0 (0-based, what the LSP tools take), text}]}]}]; total and shown count hits. A file over 8 MB is not read: the result names it.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | **yes** | Directory to search recursively (project root) - or ONE file (a .dproj, .dpr, .inc, .xml...) to search inside it in a single call |
| `query` | string | **yes** | Text to find on ONE line (case-insensitive - it is Pascal): literal, or a regular expression with regex=true. Line by line, so a query with a line break is refused. |
| `maxresults` | integer | optional | Hits PER PAGE (default 100, cap 500) - not a global limit: offset walks the whole list. |
| `offset` | integer | optional | Pagination: skip the first N hits of the FULL list - pass the previous answer's nextOffset; walking it until hasMore=false reaches every hit. |
| `wholeword` | boolean | optional | true = match whole identifiers only (word boundaries) |
| `pattern` | string | optional | Optional file mask to search instead of the Delphi set, e.g. *.style, *.ini, *.md, *.rc (one mask) |
| `regex` | boolean | optional | true = query is a regular expression (PCRE, case-insensitive), matched line by line: ^ and $ are the ends of a line; \w and \b only see ASCII letters. |
<!-- /contract -->

### `delphi_list`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

List Delphi files under a directory recursively (sources and project files, or a mask), skipping IDE artifacts BELOW the root (naming a build-output folder - Win32/Win64/Debug/Release... - as root lists inside it; hidden entries are counted). Each folder once with its files by name, size and last-write time: folders = [{dir, files = [{name, size, modified}]}]; 500 entries per page (offset walks the rest; a page that starts inside a folder names it again). dirs=true lists the SUBDIRECTORIES of root instead (one level, explorer-style: folders = [{dir, dirs = [names]}]) - to browse the machine and decide where to create or look for projects. includeTrash=true also shows the recoverable trash (__delphi-patch), to find a file delphi_delete moved and restore it with delphi_move.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | **yes** | Directory to list recursively |
| `pattern` | string | optional | Filename mask, e.g. *.pas (default: Delphi source and project files) |
| `dirs` | boolean | optional | true = list SUBDIRECTORIES of root (one level, explorer-style) instead of files |
| `includetrash` | boolean | optional | true = also show the recoverable trash (__delphi-patch). Default false. |
| `maxresults` | integer | optional | Entries PER PAGE (default and cap 500). |
| `offset` | integer | optional | Skip the first N entries of the FULL list: pass the previous answer's nextOffset; walking it until hasMore=false reaches every entry. |
<!-- /contract -->

What it does not show is counted BY REASON (1.5.0, one counter shared with `delphi_search`): `hidden` is the total, and each reason that is not zero gets its field - `hiddenBuildArtifacts` (Win32/Win64/Debug/Release/dcu/__history/__recovery/__pycache__: pass that folder as root to see it), `hiddenServerTemp` (the server's `__delphi-temp`: never shown, not even with includetrash), `hiddenGitInternals` (.git), `hiddenTrash` (`__delphi-patch`: includetrash shows it) and, in dirs mode only, `hiddenToolFolders` (.vs, .github, .idea...). The `note` says what each one is and how to see it. Until 1.5.0 the server temp was counted as a build folder, with the advice to pass it as root.

### `delphi_projects`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Locate Delphi projects (.dproj/.groupproj) under a directory - or under the workspace roots when root is empty; optional name filter. The way to answer "open project X" without knowing the disk layout. Answers in PAGES (maxresults, default 50; offset + nextOffset to walk them): a work machine holds thousands of .dproj. Grouped by folder: projects = [{dir, files = [{name, kind}]}], and each git repository once in repos = [{dir, branch}]: a project's is the LONGEST dir its folder is inside.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | optional | Directory to search under; empty = the workspace roots. |
| `name` | string | optional | Optional name filter (substring, case-insensitive), e.g. "messenger" |
| `maxresults` | integer | optional | Projects PER PAGE (default 50, cap 300). |
| `offset` | integer | optional | Skip the first N projects of the FULL list: pass the previous answer's nextOffset. |
<!-- /contract -->

**Answer (hand-written).** The projects come grouped by folder, each folder once: `projects = [{dir, files = [{name, kind, readOnly?, compilesAgainst?}]}]`, like every list of files of this server (the list keeps its name; only `files` and `dirs` become `folders`, since the name would repeat inside); each git repository once in `repos = [{dir, branch}]` - a project's repository is the LONGEST `dir` its folder is inside (a nested repository or a submodule is its own entry; a submodule has no `branch`). Pages: `maxresults` (default 50) and `offset` + `nextOffset` to walk them; when there are more, the answer also reports `byFolder` - the ten folders holding the most projects - so the next call can narrow `root` instead of walking pages. Measured on a server whose root was a whole drive: 6420 of 7025 projects were third-party component sources and their backups, and the operator's own were 73.

### `delphi_installs`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

List EVERY RAD Studio installation on this machine: version, root directory, whether it ships DelphiLSP.exe and rsvars.bat (msbuild), and the name, personality, edition and build each one states about itself ("RAD Studio 13", "Delphi 13", "Enterprise", "37.0.59082.6021"), plus installedUpdate (its installer's label). activeForLsp is the one THIS server uses, pinned by [Server] DelphiVersion (requested; written at the first start); requestedUpdate, the declared [Server] DelphiUpdate. A server whose pinned version is not installed does not start. Read-only, no parameters.

*Access: read-only OK.*

No parameters.
<!-- /contract -->

### `delphi_workspace`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

The lay of the land on the SERVER: the workspace roots this server operates within (your entire allowed universe here), the access level (read-write / read-only), the [Workspace.\<name>] section of the server this token is scoped to ("workspace"), and the active RAD Studio by version AND by name (activeDelphiName / Personality / Edition / Build, read from the installation - use them when you look anything up for this Delphi), plus delphiUpdate if declared. It also says WHO is answering ("server"): version, how this process was started (tray / service / console), transport, pid, uptime, the open sessions, the machine it runs on ("host", also in serverInfo) and the Windows account it runs as - the way to check a deployment without looking at the machine from outside. Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only exist inside this MCP: use them verbatim in every path argument and you will receive them back in results. They are NEVER your own local disks. Call this FIRST. Read-only, no parameters.

*Access: read-only OK.*

No parameters.
<!-- /contract -->

**Answer fields (hand-written).** The roots, the access level, `workspace` (the `[Workspace.<name>]` section this token is scoped to), the active RAD Studio by BDS number (`activeDelphi`) and by name (`activeDelphiName` "RAD Studio 13", `activeDelphiPersonality` "Delphi 13"), its edition and build from `bds.exe` (`activeDelphiEdition`, `activeDelphiBuild`) and its folder (`activeDelphiRoot`) - a field the machine lacks is absent; `delphiVersionRequested` is the version its settings.ini pins (`[Server] DelphiVersion`, which the server writes there at its first start when it is missing); a server whose pinned version is not installed does not start; `delphiUpdate` is the update its operator declares (`[Server] DelphiUpdate=13.2`, absent when none is) - 13.1 and 13.2 are both 37.0 and nothing reads it to decide anything yet. `server` says who is answering: version, how the process was started (tray / service / console), transport, pid and uptime.

## Edit code safely  (read-write only)

### `delphi_edit`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus text .dfm/.fmx), keeping their real encoding and line endings. Modes: EDIT (old = ONE full line from delphi_read + new; fragment + atline for a piece of a LONG line; edits for several at once), DELETE, INSERT (a new routine or method at the legal spot, both halves of a method), CREATE (in the encoding configured in the IDE, or UTF-8 with a BOM when ANSI cannot hold it), RESTORE, ADDUSES and REMOVEUSES - each parameter says which mode it belongs to. Refuses whole-file rewrites and binary designer files (TPF0); backs up, writes atomically and audits the result (encoding, EOLs, mojibake, end. structure, a brace comment with a brace inside - warned, never refused), reporting the REAL lines read back from disk: use them as evidence. Never edit Delphi files with generic tools: ANSI sources get destroyed.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi file |
| `old` | string | optional | EDIT mode: the line to replace - ONE full line copied from delphi_read (everything after the \| bar). It must be UNIQUE in the whole file, and indentation does not count: if the same text is on another line too, add atline (occurrence inside edits). |
| `new` | string | optional | EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new with the added code). A final line break is dropped; each extra one adds a blank line. Same rule for one-line and block anchors. |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers) |
| `toline` | integer | optional | RANGE (1-based, inclusive): with this, "old" becomes the FIRST line of a range that ends here - delete:true removes it all (a whole method, without pasting it), "new" replaces it all. Refused if backwards, past the end or the whole file. |
| `edits` | array | optional | SEVERAL edits on THIS SAME file, in a single call and ALL OR NOTHING: a JSON array [{"old":"...","new":"...","atline":12}, ...] applied IN ORDER. Each entry accepts two forms of anchor: ONE LINE (the same as a single edit) or a BLOCK of several consecutive lines in "old", searched for whole and in order - useful for replacing in one piece the body of a method or a long documentation paragraph. If the anchor appears more than once, break the tie with "occurrence": 1, 2... (better than "atline" inside a batch: line numbers MOVE as earlier entries add or remove lines, and "occurrence" does not: it counts on the file as it was BEFORE the batch, so if one entry changes occurrence 1, the next entry asks for 2, not for 1 again; two entries on the same line are refused). "delete": true removes the line (a BLANK one: "atline" and no "old"); and with "toline": \<number> the anchor stops being ONE line and becomes a RANGE - from the anchor's line to that one, both included - that is removed whole (delete) or replaced by "new". It is the way to drop a method without pasting it whole as an anchor. Inside a batch the range shifts too: if an earlier entry added or removed lines, "toline" is corrected on its own; with "toline", "old" is ONE line (a block already says what it replaces: EDIT-020). If an entry fails, the file goes back byte for byte to how it was and you are told which one failed. At most 50 entries per call (EDIT-026). For a LONG line, an entry can carry "fragment" instead of "old": {"fragment":"68","new":"69","atline":12} changes only that piece of line 12 (atline mandatory, and the piece exactly once in it). If the change touches SEVERAL files, that is delphi_changeset. "edits" is the whole call: old/new/fragment/delete are another mode (EDIT-111) and atline/toline go INSIDE each entry (EDIT-115). |
| `fragment` | string | optional | FRAGMENT mode for a LONG line: "fragment" = the exact piece to change (case-sensitive, EXACTLY ONCE in that line), "atline" = its 1-based line (MANDATORY) and "new" = what replaces just that piece; the rest of the line stays byte for byte. One line only; it goes INSTEAD of "old" and combines with no other mode (nor toline). |
| `delete` | boolean | optional | DELETE mode: true = remove the "old" anchored line ENTIRELY (old+new="" only blanks it). A BLANK line has no text to copy: delete + atline, without old, removes it if that line is blank. No "new" here |
| `insert` | string | optional | INSERT mode (preferred for NEW routines/methods): "rutina-global" or "metodo". The tool places the block at the legal boundary (in a .dpr: between uses and the main begin; in a unit: before the final end./initialization); with "metodo" it also writes the class declaration. Pass code, not old/new |
| `code` | string | optional | INSERT mode: the COMPLETE block, signature UNQUALIFIED (procedure Save; - not procedure TOrder.Save;) + begin..end;. NEVER include end. For a method, attributes before the signature ([Test]) and directives after it (virtual; override; static;...) go to the class declaration, and the implementation goes without them, as the IDE writes it. |
| `inclass` | string | optional | INSERT "metodo": exact class name (e.g. TOrderForm) |
| `visibility` | string | optional | INSERT "metodo" optional: private/protected/public/published; empty = end of class. "published" also works on a form class without the keyword (the implicit section after the class header, where event handlers go). |
| `visible` | boolean | optional | INSERT "rutina-global" optional: true = also declare it in the interface section (visible outside the unit) |
| `createunit` | boolean | optional | CREATE mode: true = create the .pas (never overwrites). Then register it with delphi_config command=add-unit |
| `content` | string | optional | CREATE mode: the COMPLETE file content in one call (empty = standard IDE skeleton). Use this when you already know the whole unit: one call instead of create + N patches |
| `eol` | string | optional | CREATE mode: line endings, "crlf" (default, Delphi standard) or "lf" |
| `restore` | boolean | optional | RESTORE mode: true = restore the file from this tool's backup. First call shows what would be LOST; repeat with confirm=true to execute |
| `confirm` | boolean | optional | Only with restore: execute after having seen the losses |
| `adduses` | string | optional | ADDUSES mode: units to add to a uses clause of this .pas, separated by ; (System.SysUtils;UCustomer). The engine writes the commas and the terminator, creates the clause when there is none, and skips units already in either section (a unit cannot be in both). In a .dpr it takes LIBRARY units (no path; section does not apply); a unit of the project goes by delphi_config add-unit, and a .dpk by add-unit / add-requires. |
| `section` | string | optional | ADDUSES mode: "interface" or "implementation" (default implementation: a new unit goes there unless one of its types is used in the interface) |
| `removeuses` | string | optional | REMOVEUSES mode: units to take out of the uses clause of "section", separated by ; - the inverse of adduses. A directive around the entry stays with its neighbour, the clause goes when it empties, and names not there are reported. For a .dpr/.dpk: delphi_config remove-unit. |
<!-- /contract -->

### `delphi_changeset`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

MULTI-FILE TRANSACTIONS: when one change touches several files, the whole batch lands or none of it. Flow: begin (gives an id) -> stage one operation per call (kind=edit|create|delete|move; nothing touches disk yet) -> preview (resolves every edit anchor, rehearses each edit and create with the engine - encoding, read-only attribute, binary content, the write gate - and fingerprints every file the batch touches) -> commit (fingerprints re-checked: a file changed since preview refuses the WHOLE batch; byte snapshots taken, operations applied in order; any failure restores every file byte-exact and says which operation failed). rollback discards a staged batch; status lists the open ones. Edits follow delphi_edit: old = ONE full line, unique in the file (atline pins a duplicate) - or fragment + atline + new for a LONG line, resolved when you stage it. Every anchor resolves against the file as it is BEFORE the changeset: an edit cannot anchor on a line an earlier edit of it writes (several edits of one file: delphi_edit edits=). It expires after 30 minutes unused. For renames, refactors and any change where a half-applied batch would break the project; for one file, delphi_edit is simpler.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | begin (new changeset -> id) \| stage (add ONE operation) \| unstage (take operation "n" back out; n=0 = the last one) \| preview (resolve anchors, rehearse, fingerprint; required before commit) \| commit (all or nothing) \| rollback (discard) \| status (the open ones) |
| `id` | string | optional | The changeset id returned by begin (every command except begin and status) |
| `kind` | string | optional | stage: edit (replace ONE line by anchor) \| create (new file, never overwrites) \| delete (the WHOLE FILE; the snapshot is the way back) \| delete-line (remove ONE line by atline: a BLANK one, which has no usable anchor, or with old the line you name) \| move (rename/move; the destination must not exist) |
| `path` | string | optional | stage: the file the operation touches (inside the workspace roots) |
| `dest` | string | optional | stage kind=move: the destination path |
| `old` | string | optional | stage kind=edit: the anchor - ONE full line copied verbatim from delphi_read, unique in the file (or fragment + atline instead). kind=delete-line: the line you expect at atline, compared like an anchor (the preview refuses when it is not that one); without it, that line must be blank (EDIT-123), as in delphi_edit. |
| `new` | string | optional | stage kind=edit: the replacement text (may span several lines). A final line break is dropped; each extra one adds a blank line. Same rule for one-line and block anchors. |
| `content` | string | optional | stage kind=create: the whole content of the new file |
| `atline` | integer | optional | stage kind=edit optional: the 1-based line that pins the anchor when the same line appears more than once. REQUIRED for kind=delete-line. Rebased automatically against what earlier operations of the changeset did to that file. |
| `fragment` | string | optional | FRAGMENT mode for a LONG line: "fragment" = the exact piece to change (case-sensitive, EXACTLY ONCE in that line), "atline" = its 1-based line (MANDATORY) and "new" = what replaces just that piece; the rest of the line stays byte for byte. One line only; it goes INSTEAD of "old" and combines with no other mode (nor toline). |
| `n` | integer | optional | unstage: number of the operation to remove, the one preview shows (0 or empty = the last one staged) |
<!-- /contract -->

### `delphi_textedit`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

SAFE editing of plain-text NON-Delphi files (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml - ANY plain text): docs, web assets, tests, scripts, config. Same discipline as delphi_edit - one-full-line unique anchor (old/new, atline tie-break; for a LONG line such as a README paragraph, fragment + atline + new changes just a piece of it), DELETE mode (delete=true + old), several edits on the SAME file in one all-or-nothing call ("edits", where an anchor may be ONE line or a contiguous BLOCK), real encoding preserved (UTF-8 +/- BOM / ANSI / UTF-16 / UTF-32), line endings preserved, automatic backup, atomic write - without the Pascal gates. CREATE mode (create=true + content) for new files, never overwrites. Whole-file rewrites are refused. Delphi sources/designers are refused (use delphi_edit) and so are .dproj and binaries. Read first with delphi_read and copy the anchor exactly.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the text file (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml ... any plain text - Delphi files are refused, use delphi_edit) |
| `old` | string | optional | EDIT mode: the line to replace - ONE full line copied from delphi_read (everything after the \| bar). It must be UNIQUE in the whole file, and indentation does not count: if the same text is on another line too, add atline (occurrence inside edits). |
| `new` | string | optional | EDIT mode: the new text; may be several lines. Empty = blank the line. A final line break is dropped; each extra one adds a blank line. Same rule for one-line and block anchors. |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence |
| `toline` | integer | optional | RANGE (1-based, inclusive): with this, "old" becomes the FIRST line of a range that ends here - delete:true removes it all (a whole method, without pasting it), "new" replaces it all. Refused if backwards, past the end or the whole file. |
| `edits` | array | optional | SEVERAL edits on THIS SAME file in ONE all-or-nothing call: a JSON array [{"old":"...","new":"...","atline":12}, ...] applied in order. An entry anchors on ONE line or on a BLOCK of consecutive lines; "occurrence": N breaks a tie (counted on the file BEFORE the batch, so it does not move like atline); "delete": true removes (a blank line: atline, no old); "toline" makes the anchor the first line of a range; "fragment" + "atline" changes a piece of a long line. If one entry fails, the file goes back byte for byte and you are told which one. At most 50 entries per call. Several files: delphi_changeset. |
| `fragment` | string | optional | FRAGMENT mode for a LONG line: "fragment" = the exact piece to change (case-sensitive, EXACTLY ONCE in that line), "atline" = its 1-based line (MANDATORY) and "new" = what replaces just that piece; the rest of the line stays byte for byte. One line only; it goes INSTEAD of "old" and combines with no other mode (nor toline). |
| `delete` | boolean | optional | DELETE mode: true = remove the "old" anchored line ENTIRELY (old + an empty new only blanks it). A BLANK line has no text to copy: delete + atline, without old, removes it if that line is blank. No "new" here |
| `create` | boolean | optional | CREATE mode: true = create a NEW file (never overwrites). UTF-8, parent directories created |
| `content` | string | optional | CREATE mode: the initial content of the new file (may be empty) |
| `eol` | string | optional | CREATE mode: line endings, "crlf" (default) or "lf" |
<!-- /contract -->

### `delphi_create`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Create a NEW Delphi project - console/VCL/FMX (.dpr + buildable .dproj + main form), a runtime PACKAGE (.dpk + .dproj, built to BPL+DCP in its folder, never installed) or a TEST project (a DUnitX console runner with its first fixture, what delphi_test runs) - or a NEW form, frame, data module or unit (.pas, plus its .dfm/.fmx for the visual ones), registered in the project (.dpr uses - with Application.CreateForm for forms and data modules - and the .dproj). IDE-equivalent skeletons, CRLF, the IDE's configured source encoding (UTF-8 with a BOM when that is ANSI and the content does not fit), never overwrites anything. kind=unit with NO project and an ABSOLUTE dir creates it STANDALONE (no project lists it yet); kind=include creates a .inc with its content. An EXISTING .pas joins a project with delphi_config add-unit. A uses clause split in {$IFDEF} branches (each ending in its own ";") is never rewritten by add-unit, remove-unit or a rename - it would land in the wrong branch: edit the branch with delphi_edit.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `kind` | string | **yes** | project-console \| project-vcl \| project-fmx \| project-package (requires rtl; its units go into contains with kind=unit or add-unit) \| project-test (green at birth; DUnitX ships with RAD Studio) \| form-vcl \| form-fmx \| frame-vcl \| frame-fmx \| datamodule \| unit \| include (never registered; used with {$I}). The description says what each one creates. |
| `dir` | string | optional | Projects: ABSOLUTE target folder (created if missing). Units, forms, frames, data modules: optional SUBFOLDER relative to the project, as deep as you like (Domain\Models\Dto), created if missing and registered with that path - no drive, no absolute path, no "..". Empty = next to the .dpr. kind=unit or include WITHOUT project: the ABSOLUTE folder of the standalone file. |
| `name` | string | **yes** | Projects: project name. Forms, frames, data modules and units: unit name (e.g. UCustomers) |
| `project` | string | optional | Everything but projects: the ABSOLUTE path of the .dpr, .dpk or .dproj that registers the new unit (uses of a program, contains of a package). kind=unit may go without it, with an ABSOLUTE dir (standalone, listed by no project yet). kind=include: optional, and dir is then relative to it. |
| `formname` | string | optional | Forms/frames/data modules optional: instance name without the T (default: Form+unit, Frame+unit, DM+unit) |
| `content` | string | optional | kind=unit optional: the FULL source, written as it comes (CRLF) and registered in the same call - no empty skeleton first. Its `unit X;` must match "name" and it must end in `end.`. Without it, a standard empty skeleton. kind=include: REQUIRED, the text of the .inc. |
<!-- /contract -->

## Manage files  (read-write only)

### `delphi_delete`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Delete a file or folder inside the workspace - NOT a hard delete: it goes to a recoverable trash (__delphi-patch\\<date>\deleted\ next to it), so a mistake can be undone. The exception is the server's __delphi-temp: nothing is restored from a temp, so a delete there is for good (the temp folder itself is refused: it is every agent's). Jailed to the workspace roots, refused in read-only mode; a folder that is or holds a workspace root, a reference project or a read-only folder is refused (it would go along). Use it to clean up stray files and leftovers. Deleting a unit (.pas) also trashes its .dfm/.fmx and takes it out of every project that lists it (uses, CreateForm, DCCReference), looked for from its folder up to the edge of the workspace. To keep the file but drop it from a project: delphi_config remove-unit.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted |
| `purge` | boolean | optional | true = DELETE FOR REAL, with no way back - only INSIDE the trash (__delphi-patch), to clean up your own copies when you no longer need them, not to skip the trash: a live file always goes through it first. |
<!-- /contract -->

### `delphi_move`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Move or rename a file or folder inside the workspace, or COPY it with copy=true (how something is brought in from a reference project). The destination must be inside the workspace roots, and so must the source of a move; parent folders are created; a move copies the source to the recoverable trash first. Jailed, refused in read-only mode. A FOLDER moves only as a rename on the same drive, whole or not at all (links inside travel as links); to another drive, copy=true and then delphi_delete. A folder that is or holds a root, a reference or a read-only folder is refused. Moving or renaming a unit (.pas) takes its .dfm/.fmx along, rewrites its "unit X;" header on a rename and re-points every project that lists it (the .dpr uses and DCCReference, the uses of the project's other units and their qualified UnitOld.X references), looked for from its folder up to the edge of the workspace - all or nothing: a project that cannot be re-pointed (read-only, open elsewhere) refuses the whole move with nothing changed (MOVE-019). A FOLDER re-points every unit inside it the same way: reorganise freely, the projects follow. Every RELATIVE path that crosses the border of what moved is re-pointed in the same call: inside it (the units from outside each project lists, the .dproj search/output paths, icon, manifest, .rc, deployed files and .optset, {$I}/{$R}/{$L} - only if the file was where the directive says -, the projects and dependencies of a .groupproj) and outside it, in everything this session can write (a sibling project, an {$I} from another unit, a group): a project moved one level deeper still compiles. What it could not re-point is named, for delphi_config fix-references. A copy re-points only its OWN relative paths that cross its border, so it compiles where it lands, and touches no project that lists the source (see copy); to start a project from another, delphi_create.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to move (inside the workspace roots) |
| `dest` | string | **yes** | Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same |
| `copy` | boolean | optional | true = COPY instead of move: the source stays untouched, no trash copy, and NO project is re-pointed (the copy is a new unit nobody lists yet - delphi_config add-unit). A unit copied under another name gets its "unit X;" header rewritten and its .dfm/.fmx copied along. The source only has to be READABLE (your roots, ReadOnlyRoots, the library zone): the way to bring a file in from a reference project. Refused for a folder that holds a .dproj/.dpk (a project never lives in two places) and for anything inside the trash. |
<!-- /contract -->

`copy=true` (1.2.2) copies instead of moving, through the same gate: the source
stays, no trash copy is taken, a copied unit named differently gets its `unit X;`
header rewritten and its designer file copied along, and **no project is made to
list the copy** (it is a new unit nobody lists yet; `delphi_config add-unit`
puts it in one) - what the copy itself points to outside IS re-pointed, so it
compiles where it lands. Refused for a folder that holds a `.dproj`/`.dpk` (a project never
lives in two places; `delphi_create` starts one from another) and from the trash.

**Relative paths that cross the border are re-pointed (1.6.0).** Moving a folder (or a file) makes every RELATIVE path that crosses its border point somewhere else, so `delphi_move` re-points them in the same call, with the IDE's relative form, once the unit and its designer file are in place. Inside what moved: the units from OUTSIDE that each project lists (`.dpr`/`.dpk` and `DCCReference`), the `.dproj`'s search and output paths, its icon, manifest, `.rc` files, deployed files and imported `.optset`, the `{$I}`/`{$R}`/`{$L}` directives (only when the file was where the directive says: one the compiler finds through the include path is left alone) and the projects and dependencies of each `.groupproj`. Outside it, in everything this session can write - a sibling project, an `{$I}` from another unit, a group and its dependencies -, whatever pointed inside. What points inside what moved travels with it and is not touched. A path with `&` is escaped in the XML. The answer counts what it re-pointed and where; what it could not is named, for `delphi_config command=fix-references`.

Both refuse a workspace **root** itself: the trash folder is created next to the
target, so for a root it would land in the root's parent - a write outside the
jail - and take the whole workspace with it. Delete or move what lives *inside*
a root. Changing the roots is the operator's job, in `settings.ini`.

## Build, run, package  (read-write only)

### `delphi_build`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Build a Delphi project for real with MSBuild on this machine - the closing check after editing (the linter neither links nor produces binaries). The answer carries the success flag, the compiler errors/warnings (as much as "verbosity" asks), the output tail, where the binary landed and, with several Delphi, which one built. Compile-only: a project that would EXECUTE a shell during build (a custom \<Target>/\<Exec>, a foreign \<Import>) is refused unless the workspace declares AllowBuildScripts=1; its pre/post build EVENTS (signing, copies) are skipped instead (buildEventsSkipped says so) - the final binary is built where the events run. For a package (.dpk) the answer adds implicitImports (units of OTHER packages it compiled into itself, W1033) and requiresSuggested (their packages, from this install's BPLs, or a .dpk of your workspace with requiresWorkspaceNote telling you to build it first), the list delphi_config add-requires takes; a unit dcc cannot find at all (F2613) comes back in missingUnits.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the project's .dproj (its .dpr/.dpk resolves to it) |
| `platform` | string | optional | Target platform. Omitted: the project's own default, the one the IDE builds while nobody changes it. Only a platform the project declares and has enabled (delphi_config add-platform / remove-platform), so the IDE builds the same: Win32/Win64 build natively here; Linux64/OSX64/OSXARM64/Android64/iOSDevice64... need their SDK pulled once (delphi_paserver get-sdk). Building is LOCAL against that SDK and does NOT use profile - a profile is only for target=Deploy. |
| `config` | string | optional | A configuration the project declares, e.g. Debug (default) or Release; another is refused (delphi_config view lists them). |
| `target` | string | optional | Build (full, default) \| Make (incremental) \| Clean \| Deploy (builds first, then deploys: to the PAServer of "profile" for Linux/macOS, or packages the app for Android). After switching platforms use Build. |
| `profile` | string | optional | target=Deploy on a PAServer platform: the connection profile (delphi_paserver command=profiles). The files land on the target under its PAServer scratch dir, in \<windows user>-\<profile>/\<project name>/. |
| `sdk` | string | optional | The platform SDK to link against, by name (delphi_paserver command=profiles lists them with their glibc). Omit it and the project decides (its own PlatformSDK), or the only one there is; with several and no hint the build is refused instead of guessing. |
| `verbosity` | string | optional | quiet (DEFAULT: errors + the summary - cheapest for "does it still compile"; warnings are not even asked for) \| normal (warnings and msbuild milestones) \| verbose (everything, the whole linker command line included - when a quiet error is not clear enough). It sets msbuild's own verbosity: quiet asks for less, it does not just hide it. |
| `deviceid` | string | optional | target=Deploy: device id - msbuild installs only on iOS devices with it; for Android, Deploy builds the .apk and delphi_adb install puts it on a device. |
<!-- /contract -->

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

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

THE MAP of this server, so you do not have to work it out by trial and error. command=tasks (default) gives the task -> tool table, one line each: what to use to read, to edit, to build, for several files at once, to rename, for tests, to deploy. command=tool name=\<tool> gives ONE whole tool (description + parameters) without asking for tools/list again, which brings them ALL at once. command=conventions gives the rules that apply to all of them: paths and virtual drives, the jail, how editing by anchor works, backups and encodings. The Delphi documentation itself (classes, routines, the language) is delphi_docs. Start here if you have just connected.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | tasks (task -> tool table; default) \| tool (one whole tool, with "name") \| conventions (the rules common to all of them) |
| `name` | string | optional | command=tool: name of the tool (delphi_edit, or just "edit") |
<!-- /contract -->

### `delphi_test`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

TESTS: the difference between "it compiles" and "it works". discover (path = a folder or project): the test projects underneath (a .dpr that uses DUnitX, or a console one whose name says test/spec). run (project = the test .dproj): builds and runs that runner and returns the STRUCTURED result - total, passed, failed, errored (a DUnitX test that raised; it fails the run too), the failures, exitCode, duration and the tail of its output - read from the DUnitX summary or the PASS/FAIL + ExitCode convention of a hand-written runner; verdictFrom (counts or exitCode) says where the verdict comes from, never invented. Running tests is RUNNING, the only thing that runs on this server, behind its own switch [Workspace.\<name>] AllowTests (without it, discover works and run is refused). The binary runs in a Windows container of its own, on a COPY of its output folder: it reads and writes that copy and only what Windows gives every container (its own temp folder, deleted with it, and the system files) - no other file, no network, no network drive - and it is cut off at the timeout. So a test here is for LOGIC: what it reads has to travel in its output folder, and a project built with runtime packages (UsePackages) is refused before building: build it whole. What it writes in that folder comes back in "files" (text files with their content, capped).

*Access: mixed (`command` discover read-only; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | discover (list the test projects under "path") \| run (build and run the one in "project"). Default: discover |
| `path` | string | optional | discover: folder (or project) under which to look for test projects |
| `project` | string | optional | run: the .dproj (or .dpr) of the test project to run |
| `config` | string | optional | run: configuration to build and run (Debug by default) |
| `filter` | string | optional | run optional: test filter for frameworks that read it (DUnitX --run:, through TDUnitX.CheckCommandLine, which the delphi_create kind=project-test project calls); a runner that does not read its command line ignores it. |
| `timeoutms` | integer | optional | run optional: maximum run time in milliseconds (120000 by default, maximum 600000); a test that hangs is cut off and the answer says so. |
| `platform` | string | optional | run optional: platform to build and run - by default the project's own, as the IDE. Only one the project declares and of THIS machine: the binary runs here |
| `nobuild` | boolean | optional | run optional: true = run the binary that already exists, without building first (by default it builds: running an old binary is lying). |
<!-- /contract -->

**`run` answer (hand-written).** `total`, `passed`, `failed`, the failing lines, `exitCode`, `durationMs` and a bounded tail of what the runner printed; `verdictFrom: counts | exitCode` says where the verdict came from (DUnitX's own summary, or the plain PASS/FAIL + ExitCode convention of a hand-written console runner) and never guesses.

### `delphi_package`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Zip a build-output directory ON the server into a single deploy artifact (recursive, *.dcu intermediates excluded), ready to download with ONE delphi_fetch. The standard way to bring a GUI app to the client machine: delphi_build -> delphi_package -> delphi_fetch.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `dir` | string | **yes** | Directory to package (e.g. the build output Win64\Debug). Recursive; *.dcu and dcu\ intermediates excluded |
| `outfile` | string | optional | Optional zip path, ending in .zip (default: sibling of dir, named \<dirname>-deploy.zip). An existing .zip there is replaced. Must be inside the workspace roots |
<!-- /contract -->

## Cross-platform: build configs, remote platforms & devices

### `delphi_config`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

See and manage a project's build configurations and target PLATFORMS. view (read-only): the framework (VCL is Windows-only; FMX and console cross platforms), the configurations (Debug/Release/custom), the defaultPlatform (what delphi_build builds without platform=) and every platform - enabled or not, possible for THIS project, needing a PAServer profile. add-platform / remove-platform: enable or disable a platform in the .dproj (a curated edit of \<Platforms> only). set-version: the project VERSION everywhere it must agree. set-output: every binary under one folder (Compiled by default), keeping the platform/config subfolders. add-searchpath / remove-searchpath: a unit search path for ONE platform, as the IDE's Project Options > Search path; a platform added to a project inherits NO search paths from the others - the usual reason a unit is "not found" only there. add-deployfile / remove-deployfile: ship an extra file with the build on ONE platform, as the IDE's Deployment Manager (a native .so/.dylib/.dll a component loads, data files), into the .deployproj, creating the standard manifest if missing. add-unit / remove-unit: the IDE's Add to / Remove from project for an EXISTING .pas (.dpr uses, CreateForm for forms, the .dproj); the file stays on disk. fix-references, on a project or a group: re-points what was moved by hand, finding it by name in the workspace - one match only, never a guess. On a .groupproj: view lists its projects, and add-project / remove-project write what the IDE's Add existing project writes. set-sdk, set-profile and add-requires: see command. To BUILD a combination: delphi_build with platform+config.

*Access: mixed (`command` view read-only; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the project .dproj (its .dpr/.dpk resolves to it). A .groupproj (a project group) takes view, add-project, remove-project and fix-references; every other command is refused |
| `command` | string | optional | view (default; section= for the detail) \| add-platform \| remove-platform \| set-output \| set-version \| set-sdk (the SDK this project builds a remote platform with, by name; "none" = back to the SDK Manager default) \| set-profile (the PAServer profile it deploys and runs that platform with; "none" = the platform's active profile) \| add-searchpath \| remove-searchpath \| add-deployfile \| remove-deployfile \| add-unit \| remove-unit \| add-requires (packages: names for the .dpk requires clause, from requiresSuggested after a W1033) \| fix-references \| add-project \| remove-project. The description says what each does. |
| `platform` | string | optional | add/remove-platform: the platform name (Win32, Win64, Linux64, Android64...; an unknown one is refused with the list). add/remove-searchpath: the platform whose path changes; empty = the base group (all). add/remove-deployfile: the platform it ships on (required). set-sdk / set-profile: the platform they apply to. |
| `sdk` | string | optional | set-sdk: the SDK this PROJECT builds that platform with, by name (delphi_paserver command=profiles lists them with their glibc); without it everything rides on the SDK Manager default. "none" = back to that default. add-platform takes it too, in the same call (all or nothing). |
| `profile` | string | optional | set-profile: the PAServer profile this PROJECT deploys and runs that platform with (delphi_paserver command=profiles lists them) - the twin of set-sdk: in the IDE a target gets both. "none" = back to the platform's active profile. add-platform takes it too, in the same call (all or nothing). |
| `path` | string | optional | add/remove-searchpath: the folder where the compiler looks for .pas/.dcu (e.g. an installed component's Source; delphi_workspace lists the readable library zone); $(BDS)-style macros accepted, relative = from the project folder; it must exist inside the workspace or the library zone. add/remove-unit: the .pas. add/remove-deployfile: the file to ship. add/remove-project: the .dproj, in the .groupproj given in project. |
| `section` | string | optional | view only: summary (default) \| platforms (state and reasons) \| searchpaths (by group) \| deploy (files by platform) \| units (all the project units) \| all (everything, large). |
| `remotedir` | string | optional | add-deployfile: destination folder on the target, relative to the deployment root (the IDE's RemoteDir). Default: next to the binary - for a .so on Android, the apk's library\lib\\<abi>\. No absolute paths, no "..". |
| `version` | string | optional | set-version: 2 to 4 numbers (1.2, 1.2.3, 1.2.3.4; a suffix like -beta is ignored - VERSIONINFO is numeric). Written to the Windows VerInfo numbers AND the FileVersion/ProductVersion keys at once, which is what drifts by hand. Android and iOS versions are NOT touched. |
| `output` | string | optional | set-output: a simple relative folder name (Compiled by default): .exe to \<folder>\$(Platform)\$(Config), .dcu to \<folder>\Dcu\$(Platform)\$(Config). "default" restores the RAD Studio layout. No absolute paths, no "..". |
| `requires` | string | optional | add-requires: package names for the .dpk requires clause, separated by ; (vcl;dbrtl) - take them from requiresSuggested of delphi_build. Names already there are kept. |
<!-- /contract -->

**`view` fields (hand-written).** The summary carries the framework, the build configurations, the enabled platforms and `remoteTargets`: each enabled remote platform with the `sdk` and the PAServer `profile` it builds and deploys with and where each comes from (`sdkSource` / `profileSource`: `project`, IDE default, or none - with the command that fixes it); `section=platforms` carries the same four fields on every remote platform. `set-sdk` writes the `PlatformSDK` property (the one the IDE writes from Project Options); `set-version` touches the Windows VERSIONINFO numbers and the FileVersion/ProductVersion keys only - Android and iOS numbering is a different thing and is not touched.

### `delphi_paserver`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

The bridge for building and running on OTHER platforms (Linux, macOS) through PAServer: its installers, this server's connection profiles and SDKs, and running what a project deployed on the target (each subcommand in "command"). The first time: packages (download the installer with delphi_fetch and run it on the target) -> add-profile (the password is stored encrypted) -> test-connection -> get-sdk (the libraries the linker needs, once per target and again after an OS upgrade there; minutes) -> delphi_build for that platform -> delphi_build target=Deploy -> remote-run. Enabling a platform in a project is delphi_config.

*Access: mixed (`command` platforms / packages / profiles read-only; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | platforms (default: what this server can target + profile/SDK status) \| packages (PAServer installers to download and run on the target) \| profiles (connection profiles and SDKs) \| reseat (write the missing IDE seats of profiles already on disk; no PAServer, no password) \| add-profile (profile, host, password; optional port, platform. The host must be allowed in the workspace's RemoteHosts: registering a profile IS declaring where this machine may connect. An existing name is refused, never overwritten; the profile shows in the IDE too) \| remove-profile (that profile, from the IDE too; profiles live outside the workspace, so there is no trash: a copy of its file is kept first in the server's own folder and the answer says where) \| test-connection (with profile: full handshake; with host+port and no profile: raw TCP probe, same host rule) \| get-sdk (pull the sysroot from the PAServer of "profile" into a folder of its own named after the target distro, registered for delphi_build AND the IDE SDK Manager; minutes. An .sdk file or SDK record it replaces is copied first and the answer says where: previousSdkCopy, previousSdkRecordCopy) \| reseat-sdk (rewrite the IDE seat of an SDK already on disk, no network; "sdk" names one, none = all) \| remove-sdk (its .sdk file - copied first: removedCopy - and IDE seat; the sysroot stays on disk and the answer says where) \| remote-run (run what THAT project deployed on the target of "profile" - nothing else - and return exit code and output; nothing to install, PAServer runs it. On timeout it is NOT killed: a program with a window stays up, you get its partial output and stillRunning=true) \| kill (stop a job a remote-run left running: profile, project and its job id; only a job of THAT project on THAT machine) \| output (what a running job wrote SINCE its answer: so far while it lives; once it ended, all of it with its exit code, and then it is deleted on the target; same profile, project and job as kill) |
| `profile` | string | optional | The PAServer connection profile, by name (letters, digits, "_", "-") - the same "profile" delphi_build and delphi_desktop take: add-profile creates it; test-connection, get-sdk, remote-run, kill and output use it |
| `host` | string | optional | Host or IP where the target PAServer listens (add-profile, or test-connection without profile for a raw TCP probe) |
| `port` | string | optional | Port of the target PAServer (add-profile / test-connection). Default: 64211 |
| `password` | string | optional | The PAServer password (add-profile). Used once to create the profile, stored encrypted, never shown back |
| `platform` | string | optional | Platform of the profile, one that paclient takes (Linux64, OSX64, Win64...; a wrong one is refused with the list). Default: Linux64 |
| `project` | string | optional | remote-run, kill, output: the ABSOLUTE path of the .dproj (or its .dpr) whose DEPLOYED program it is (not its name); the server derives the path on the target (\<user>-\<profile>/\<Project>/\<Project>, what target=Deploy wrote) - nothing else there can be run. |
| `exe` | string | optional | remote-run OPTIONAL: another file of that same deploy folder to run instead of the project binary - a plain file name, no path. |
| `args` | string | optional | remote-run: optional command-line arguments for the program (no shell metacharacters) |
| `job` | string | optional | kill / output: the "jobId" a remote-run answer gave you; with profile and project (the same .dproj path) - only a job of THAT project on THAT machine. |
| `sdk` | string | optional | get-sdk optional: the NAME of the SDK folder to write. Default: the target distro from its /etc/os-release (zorin18, fedora44, ubuntu2404). Pass one to keep "the one this shop builds with". reseat-sdk: the SDK whose IDE seat is rewritten (none = all). remove-sdk: the SDK to remove, by name (command=profiles lists them). |
| `active` | string | optional | get-sdk optional: "yes" makes it the ACTIVE SDK of the platform (the bold entry of the IDE SDK Manager, used by projects that declare none). Default: nothing is touched - what a project builds with belongs to the project (delphi_config set-sdk) or to you. |
| `timeoutms` | integer | optional | remote-run: max milliseconds to wait for the program (default 30000, max 300000) |
<!-- /contract -->

**Why `reseat` exists (hand-written).** `add-profile` writes the `.profile` file AND the twin seat the IDE keeps in the registry (`RemoteProfiles\<name>`); the IDE builds its Connection Profile Manager list from that key and reads it at startup, so a profile created while the IDE runs appears at its next start. A profile on disk that the IDE does not list is repaired by `command=reseat`: it walks the `.profile` files and writes the missing seats, reading each encrypted password from its own file (no PAServer, no password needed; measured 2026-09-20: two invisible profiles, one `reseat`, both listed). `paclient`, MSBuild and every tool here read the `.profile` FILES, with or without a seat. `get-sdk` registers the SDK for `delphi_build` and in the IDE's SDK Manager (path table from that install's own `Linux64.defaultsdkpaths`).

**One SDK = one folder, and the project says which one it builds with** — the same model RAD Studio uses for its Android SDKs. `get-sdk` writes the sysroot into a folder of its own, named after the target's distribution (`fedora44.sdk`, `zorin18.sdk`), registers it for msbuild and in the IDE's SDK Manager, and **refuses to pull one distribution on top of another**. That refusal exists because the opposite was measured: until 2026-09-20 every target was pulled into a single `Linux64.sdk`, and the operator's folder ended up holding the Debian/Ubuntu tree AND the Red Hat one — two `libc.so.6` (2.39 and 2.43), two gcc trees, and both lib directories on the linker's path. It linked correctly only because of the ORDER of that list.

`command=remove-sdk` is the other half: it deletes the `.sdk` file and the IDE seat, so the SDK stops being offered — and it deliberately leaves the sysroot on disk, reporting its path in `sysrootLeftBehind`. Carrying off gigabytes of somebody's disk is not a tool's job; deleting that folder is a decision, and a one-line one in any file manager.

`command=reseat-sdk` is the SDK twin of `reseat`: it re-writes the IDE's SDK Manager seats from the SDKs already on disk, with no network and nothing downloaded again. It exists because that seat lives in the REGISTRY, so it only lands where the operator's own server can write it — if the SDK shows up for `delphi_build` but not in the IDE, run this from the server you started yourself and reopen the IDE (it reads that list at startup).

**You do NOT need one SDK per Linux, and that is the point.** A binary linked against an OLD glibc runs on newer distributions; the reverse dies with `GLIBC_2.xx not found`. So keep pulling each target into its own folder, and build everything with the one whose glibc is the OLDEST in your fleet — `command=profiles` reports the `glibc` of every SDK you have (the IDE's own included) plus a `warning` on any folder that holds two distributions.

`remote-run` also needs TWO declarations in the calling workspace: `AllowRemoteRun=1` and a `RemoteRunProjects=` list naming the project (an empty list allows nothing - fail closed). OFF by default, and the only way this product executes a program.

**Stopping what you started.** A program that outlives the timeout is left running on purpose (`stillRunning=true`, a window is meant to stay up) - and since 1.0.16 the same answer carries a `killNote`: `command=kill profile=<profile> project=<the same .dproj> job=<jobId>` stops it. It is not a general kill: the launcher wrote `<job>.pid` next to the program when it started it and its watcher removes it when the program ends, so `kill` can only reach a job this server started for THAT project on THAT machine (SIGTERM, three seconds of grace, then SIGKILL on Linux; `TerminateProcess` on Windows). A job that already ended answers `killed=false` and says so. Measured 2026-09-22 on Zorin and Windows.

**Reading what it wrote later (1.5.0).** The same `stillRunning` answer carries an `outputNote`: the job's output STAYS on the target, and `command=output profile=<profile> project=<the same .dproj> job=<jobId>` reads it whenever you want - while the program lives, what it has written so far; once it ended, all of it and its `exitCode`, and then it is deleted on the target (read whole = gone, like the mailbox). That is how you see what a program with a window writes after the deadline: the error when it closes after a login, its exit code, the `___RC` of a job you killed. Until 1.5.0 the output was deleted when `remote-run` came back, and anything written after that was lost.

**How a run travels, on every target.** `paclient` has no "execute" operation, and PAServer starts an uploaded file only without arguments and waits for it to end (measured 2026-09-22 on Zorin, Fedora and Windows). So the server uploads a job file (`run-<job>.job`: the binary, the output file, then ONE ARGUMENT PER LINE) and the native launcher `node\McpRunJob` (the ELF for a Linux, `McpRunJob.exe` for a Windows), named `run-<job>`, which PAServer starts (`--put` flag 3 on Linux, flag 5 on Windows). The launcher reads and deletes its job, writes `___ENV=`, checks the binary is native (ELF or PE - a script in the deploy folder is refused), starts it unattended with its output in `<job>.out` and its arguments as argv, leaves a watcher that appends `___RC=<code>` when the program ends, and returns at once so PAServer and `paclient` are free. **There is no shell anywhere in the path**: nothing to quote, nothing to inject. Until 1.0.15 Linux went through a `/bin/sh` script composed by the server (where the 1.0.15 injection lived) and Windows through the launcher; since 1.0.16 both are the launcher, one source (`src/RunJob/`) compiled for each system.

The launcher also takes care of the **graphical environment** of the target. On Linux a PAServer started as a service (the normal setup) is born outside the desktop session and a program with a window dies at once (GTK, exit 134, "Can't create a GtkStyleContext without a display connection"); before launching, the launcher completes only what is MISSING - `XDG_RUNTIME_DIR`, the session D-Bus, `WAYLAND_DISPLAY`, `DISPLAY` and the newest `XAUTHORITY` - from the session of the SAME user PAServer runs as. On Windows it reports the SESSION it runs in: a Windows service lives in session 0, which has no desktop. Every answer says which case it met in `graphicalEnv`: inherited (nothing added), completed (lists the variables), no graphical session at all (a console program runs anyway), or the Windows session number. Measured on a Fedora with PAServer as a systemd service, a Zorin with PAServer in the session and a Windows with PAServer in the user's session (2026-09-22).

### `delphi_adb`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Android devices for remote development: phones/tablets hang off THIS server (USB or wifi adb) while you program from anywhere. Each subcommand is in "command"; discover gives the ip:port of what announces wireless debugging (no address to know up front), and connect makes the device ask for authorization the first time. The adb used is the one of the IDE's own Android SDK. Building the .apk is delphi_build target=Deploy (the deployment manifest is generated if missing). screenshot (the screen, in this answer), tap and key are your eyes and hands on the device, and logcat shows what the app did. Typical flow: discover -> connect -> devices -> delphi_build target=Deploy -> install -> run -> screenshot -> tap -> logcat.

*Access: mixed (`command` discover / devices / logcat read-only; logcat only without out= (out= writes the log to a file); every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | discover (devices announcing wireless debugging, by mDNS, with their ip:port) \| devices (attached devices; default) \| connect (over the network: address) \| disconnect (address) \| install (an .apk: apk, device) \| run (launch an installed app: app, device - the IDE's Deploy and Run) \| logcat (the device log, bounded: device, optional filter and lines) \| screenshot (the screen, in this answer: device, optional out) \| tap (x, y measured on a screenshot, device) \| key (a navigation key: key, device) |
| `address` | string | optional | ip:port of the device for connect/disconnect (from command=discover, or the device's wireless-debugging screen) |
| `device` | string | optional | Device serial or ip:port (from command=devices). REQUIRED for every command that touches a device, and it must be in the workspace's AdbAllowedDevices: the device is named, never implied, even when only one is attached. |
| `apk` | string | optional | Path of the .apk to install (inside the workspace) |
| `app` | string | optional | run: package name of the installed app to launch (e.g. com.embarcadero.MyApp - the build/install results state it) |
| `out` | string | optional | screenshot, optional: where the capture lands: a FOLDER (existing, or ending in \ - the server names the file) or a FILE whose extension matches the capture's real format. Empty = __delphi-temp\\<agent>, wiped on server restart. On THIS server, jailed like any path. With inline=false the capture stays there and the answer carries its download link. logcat: an optional .txt/.log FILE to dump into instead of answering inline - read it in ranges with delphi_read. |
| `x` | string | optional | tap: X measured on a screenshot; pass its frame and the server converts to display pixels. Without frame, X is display pixels (multiply by tapScale.x when the answer carried it). |
| `y` | string | optional | tap: Y measured on a screenshot; pass its frame and the server converts to display pixels. Without frame, Y is display pixels (multiply by tapScale.y when the answer carried it). |
| `key` | string | optional | key: back \| home \| enter \| appswitch \| wakeup \| up \| down \| left \| right \| tab |
| `filter` | string | optional | logcat: only lines containing this text (e.g. your app tag or package). Optional |
| `lines` | string | optional | logcat: how many recent lines (default 300, max 5000; 0 = the default). An inline answer carries at most the newest 400 - for more, pass out=\<file.txt> and read it in ranges. |
| `inline` | boolean | optional | Default true: the capture this answer brings - a screenshot, the one every gesture returns (tap, type, swipe...), a preview - comes back IN this answer as an image (scaled to maxwidth), and no file is kept to download later. false = a file and its download link (a client without vision, or one that wants the bytes). |
| `maxwidth` | integer | optional | Inline only: the width the image is scaled to before it travels (0 = 1280). The answer says inlineScale: divide what you measure on the inline image by it to get capture pixels, or use the answer's frame (a tap takes it, and delphi_desktop's type too; preview's converts to form units). |
| `frame` | string | optional | tap (and type, on delphi_desktop): the "frame" of the screenshot you measured on, copied verbatim; then x,y are pixels of THAT image and the server converts them (inline scale, crop origin, device display). Without it, x,y are capture pixels. |
<!-- /contract -->

Since 1.3.1 `screenshot` is delivered like `delphi_desktop`'s (same helper): the
image inline in the answer, or file + `download` with `inline=false`, always with
a `frame`; `tap` with `frame=` converts to DISPLAY pixels, so `tapScale` no longer
has to be applied by hand.

**The screenshot says what the display really is.** Every `screenshot` answer carries `image` (the PNG's size) and `display` - the device's `physical` size, its `override` size when one is set and its `density`, from `wm size` / `wm density` - because `input tap` takes pixels of the display in force, not of the picture. Normally they are the same and what you measure on the image is what you tap; when they differ (a device that captures at another scale) the answer carries `tapScale {x, y}` and its note says to multiply first. A rotated display (WxH against HxW) is not a scale: screencap and input share the orientation.

Devices are allowlisted PER WORKSPACE — `AdbAllowedDevices=192.168.1.163;SERIAL123` in its section (semicolon list; an IP entry covers any port wifi debugging negotiates). Targets outside the workspace list are refused at BOTH access levels, every device-addressing command must name its `device` explicitly, and an absent list means NO devices (v0.98).

### `delphi_desktop`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

The desktop of the machine behind a PAServer profile (a Linux or Windows target, or this server itself when a PAServer runs in its user session), like adb for Android: SEE it and ACT on it. A small Delphi node does the work there; this server deploys and updates it by itself (leave "project" empty) - nothing else is installed or compiled on the target. THE FLOW: command=screenshot brings the whole desktop; measure the pixel you want on it and tap (or type, which presses there first) at that x,y - the node handles the screen scale. Every capture lists "windows" (title and rectangle in capture pixels; on Linux the X11/Xwayland ones, which is every FMX application - native Wayland windows show in the image but are not listed) and graphicalEnv. The target needs a graphical session open for the user PAServer runs as: a headless box, a locked Windows or a Windows service (session 0) has nothing to show (command=status says what to ask the operator for). It is a permission of its own: AllowRemoteRun=1, the profile's host in RemoteHosts and McpDesktopNode (or all) in RemoteRunProjects - only the operator sets them, and a refusal names the missing one.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | screenshot (default: the whole desktop as a PNG) \| tap (press at x,y measured on that screenshot) \| type (write "text"; with x,y it presses there first and pays the startup once (tap + type pays it twice). Typed means the keys were SENT: nothing checks where the focus was, so read the screenshot each answer brings) \| key (one key: Linux code on a Linux target, key NAME on a Windows one) \| overview (when one window covers another - Linux: the Super overview brings every window into view; Windows: only a fresh capture with the windows list) \| status (is the desktop reachable, and what to ask for if not) |
| `profile` | string | **yes** | PAServer profile of the target machine - Linux, Windows, or this server in its user session (delphi_paserver command=profiles lists them). The desktop is THAT machine's, never yours. |
| `project` | string | optional | OPTIONAL: empty = the node bundled with this server, deployed on first use and updated when its version changes. A .dproj path only when you develop the node itself (deployed with delphi_build target=Deploy). |
| `x` | string | optional | tap/type: horizontal pixel measured on the screenshot this tool returned (pass its frame too and the server converts) |
| `y` | string | optional | tap/type: vertical pixel measured on the screenshot this tool returned (pass its frame too and the server converts) |
| `code` | string | optional | key. Linux target: the evdev key code (NOT an X11 keycode): Escape 1, Tab 15, Enter 28, left Alt 56, Super 125. Windows target: the key NAME - escape, enter, tab, space, backspace, delete, home, end, up, down, left, right, super, alt, ctrl, shift, f1..f12, or a letter a..z. The other kind is refused. |
| `modifiers` | string | optional | key OPTIONAL: keys held while it is pressed, comma separated - ctrl, shift, alt, super (Ctrl+K on Linux: code=37 modifiers=ctrl; Alt+F4 on Windows: code=f4 modifiers=alt). Pressed in that order and released in reverse. |
| `text` | string | optional | type: the text to write. Windows: typed as Unicode. Linux: key by key with the target's own keyboard layout (Shift, AltGr, dead keys); a character it cannot compose (an emoji) is refused by name, and the answer says which keyboard was used. Typed as TEXT, never run. With x,y it presses there first to focus the field. |
| `out` | string | optional | screenshot: where the capture lands: a FOLDER (existing, or ending in \ - the server names the file) or a FILE whose extension matches the capture's real format. Empty = __delphi-temp\\<agent>, wiped on server restart. On THIS server, jailed like any path. With inline=false the capture stays there and the answer carries its download link. |
| `region` | string | optional | screenshot OPTIONAL: "x,y,w,h" in desktop pixels - only that piece, at full resolution (every image is shrunk to one fixed size, so a crop is how you read a small dialog). The answer carries origin {x,y}: press at (origin.x + x, origin.y + y), or pass its frame. Not with window: for a piece of a window, add the window's origin and use region. When in doubt (a dialog may open elsewhere), capture the whole desktop. |
| `window` | string | optional | screenshot OPTIONAL: part of a window title; the capture is cropped to the first window of "windows" whose title contains it (case-insensitive), with origin {x,y} like region, plus the whole list (a dialog outside the crop still shows there). A native Wayland window has no rectangle: use region. Not with region. |
| `inline` | boolean | optional | Default true: the capture this answer brings - a screenshot, the one every gesture returns (tap, type, swipe...), a preview - comes back IN this answer as an image (scaled to maxwidth), and no file is kept to download later. false = a file and its download link (a client without vision, or one that wants the bytes). |
| `maxwidth` | integer | optional | Inline only: the width the image is scaled to before it travels (0 = 1280). The answer says inlineScale: divide what you measure on the inline image by it to get capture pixels, or use the answer's frame (a tap takes it, and delphi_desktop's type too; preview's converts to form units). |
| `frame` | string | optional | tap (and type, on delphi_desktop): the "frame" of the screenshot you measured on, copied verbatim; then x,y are pixels of THAT image and the server converts them (inline scale, crop origin, device display). Without it, x,y are capture pixels. |
<!-- /contract -->

Since 1.3.1 a screenshot is **one step**: the image travels in the same answer
(an MCP `image` content item, scaled to `maxwidth`, 1280 by default) and its temp
file is consumed on the spot; `inline=false` returns the file and its `download`
link instead. Every capture carries a `frame` token
(`<imgW>x<imgH>@<srcW>x<srcH>+<x>+<y>`): `tap`/`type` with x,y measured on that
image and `frame=` copied verbatim, and the server converts scale and crop origin -
the agent never does arithmetic. Without `frame`, x,y are capture pixels, as before.

The desktop of the machine behind a PAServer profile - a Linux target, a Windows target, or **this server itself** when a PAServer runs in its own user session - the way `delphi_adb` gives you an Android one: SEE the screen and ACT on it. Until 1.0.15 this tool was `delphi_adb_linux`, and a second tool called `delphi_desktop` ran the node locally under a switch of its own (`AllowDesktopControl`): two paths and two permission models for one thing. Since 1.0.16 there is ONE path, PAServer and a profile, and the machine is a parameter; `delphi_adb_linux` stayed two releases as a deprecated alias and no longer exists, and neither does `AllowDesktopControl`.

The machine hangs off a PAServer profile (the same profiles `delphi_paserver` builds and deploys with) and runs a small Delphi node **this server deploys and updates by itself**, the right binary for that system (the ELF for a Linux, the `.exe` for a Windows, read from the profile's own platform) - nothing else is installed on it. With `project` empty (the normal case) the bundled node is pushed to the target on first use and refreshed whenever its version stamp stops matching: the server compares the target's `node.ver` (the binary's SHA-256) against its bundled copy once per profile and session, so an updated server heals every already-provisioned machine on the next gesture. The node's sources live in `src/DesktopNode/`. **Linux: GNOME only for now** (Zorin 18 and Fedora, measured): portal capture, Mutter scale, Super overview. **Windows: measured 2026-09-22** against a PAServer running in the user's session of this very server (`windows-local`, 127.0.0.1).

THE FLOW, and it is the whole trick: `command=screenshot` brings the WHOLE desktop here as a PNG; you LOOK at it, measure the pixel you want, `command=tap` presses exactly there and `command=type` writes text (with `x`,`y` it presses there first - the real gesture is "write this here", and it pays the startup once) - x and y measured *on that screenshot*, because the node converts the screen scale itself. An agent never deals with logical versus physical coordinates: it acts on what it sees. `command=key` presses one key - on a Linux target by its Linux code (evdev, NOT X11 keycodes: Escape 1, Tab 15, Enter 28), on a Windows target by NAME (escape, enter, tab, f4, a letter a..z...); the tool reads the profile's platform and refuses the other kind, because a number on Windows would press a different key - and with `modifiers` held (`ctrl`, `shift`, `alt`, `super`): Ctrl+K, Alt+Tab, Ctrl+Shift+S are one gesture on both targets (an agent in the field found a field that only opens with Ctrl+K and no way to send it). `command=type` writes with the keyboard the target really has: on Linux the desktop's own keymap, DEAD KEYS included - "í" is typed as the dead acute key and then "i", exactly as a person does on a Spanish keyboard (without dead keys every accented letter was refused on a Spanish layout, measured by a field agent); a character the layout cannot produce at all is still refused by name. Every answer with a capture carries `windows`: title and rectangle of each window in pixels of that capture, on both targets - on Windows every visible top-level window, on Linux the X11/Xwayland ones, which is every FMX application (native Wayland windows such as the terminal are not listed, and `windowsNote` says so). Tap inside one, or crop to it with `window=`. `command=overview` brings them ALL into view when one covers another: on Linux the Super overview (every window reduced, its icon underneath - tap one or Escape; the answer's `overviewNote` explains it), on Windows a fresh capture with the list. If the enumeration fails the capture still comes back and the node output says why. `command=status` says whether the desktop is reachable and, when it is not, what to ask the operator for. Every answer carries `graphicalEnv`: the session the node ran in.

**How a gesture travels.** The same way as `remote-run`, on every system: a job file with the node's arguments one per line and the native launcher `node\McpRunJob` / `McpRunJob.exe` that PAServer starts - no shell in the path, so the text you type reaches the node untouched. A Windows PAServer must run **inside the user's session**: a Windows service lives in session 0, which has no desktop, and `graphicalEnv` says so.

The target needs a graphical session open - a headless box has nothing to show - for the SAME user PAServer runs as. On GNOME **the screen-capture permission must have been granted once** on that machine, as part of setting it up; without it the desktop portal tries to ask, and when it cannot paint its dialog - a remote session, a locked screen - it answers nothing: the symptom is a mute 20-second timeout that names no cause. A locked Windows answers "Access denied" to any capture, and the tool says so in `hint`. An UNLOCKED Windows sometimes answers the same to the screen copy (measured 2026-09-22, one capture in a few); then the node composes the desktop window by window from the DWM surfaces (`PrintWindow`) and says so in a `FALLBACK:` line of `nodeOutput` - that capture has every window with its real pixels but no cursor and no taskbar, and `hint` is only given when there is no capture at all.

**Coordinates are real pixels** on both systems: the Windows node is DPI-aware, so what it reports matches the screenshot exactly; a tool that is NOT DPI-aware sees the same window somewhere else (on a 125% display, the same Notepad was at 600,254 for a non-aware caller and at 750,318 for the node). Measure on the screenshot or on `windows`, never mix in coordinates from another source.

**A crop when you need detail, the whole desktop when you need the truth.** A small dialog on a 3440-pixel screen is unreadable in the whole-desktop image - the API shrinks every picture to one fixed size, so a crop buys detail, not tokens. `screenshot region="x,y,w,h"` returns only that piece of the SAME capture (cropped on the server, `Lsp.Imagen`, so it works on every target), and `screenshot window="<part of a title>"` does the measuring for you on a Windows target (the node lists the visible windows with their rectangles; on Linux the node lists the X11/Xwayland windows it can see - native Wayland windows do not appear, and for those you use `region`). Every cropped answer carries `origin {x,y}`, `region` and `croppedFrom`, and its note spells the rule: what you measure on the crop is pressed at (origin.x + x, origin.y + y) - one frame, one coordinate space, never a second one. Against the old trap (a modal opened elsewhere and the agent, looking at one window, never saw it): on Windows every cropped answer also carries the full `windows` list, so a dialog outside the crop still shows by title; on Linux the rule is the old one - when in doubt, capture the whole desktop. Measured 2026-09-22.

**The target machine is the unit of exclusion, not the call.** `profile` says which machine every gesture goes to - the server never remembers a "current profile" - so one agent can drive two machines at the same time and nothing mixes. Gestures to the SAME profile are serialized (the node writes its capture in its own deploy folder on that machine), and each capture lands here named after its profile, so two machines answering at once never overwrite one another.

### `delphi_components`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

What this server's RAD Studio has INSTALLED to program with: every component/design package REGISTERED in the IDE (Known Packages - what the IDE loads into its palette), whatever the channel (GetIt, a vendor installer, manual). Each line: the package description and its .bpl; disabled ones are marked, IDE plumbing excluded. Read-only: there is no install command; if a library you need is missing, say so with delphi_report. The base RTL units are always there and never appear here.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `filter` | string | optional | Optional: only entries whose description or file name contains this text (case-insensitive), e.g. "FMX", "TMS", "JEDI". |
| `platform` | string | optional | Optional: a platform (Win32\|Win64\|Linux64\|Android64\|OSX64\|iOSDevice64...) to see instead the IDE's Library Search Path FOR IT, expanded, plus the component roots other platforms register and this one does not - the list to walk when a build on a new platform fails with F2613 (then delphi_config add-searchpath to the Source folder). |
<!-- /contract -->

### `delphi_rename_symbol`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

SEMANTIC RENAME of a Delphi symbol: point at the identifier (path + 0-based line/character, like delphi_definition) and give newname. mode=preview (default, never writes) lists every CONFIRMED occurrence (each re-resolved against the same definition), the files touched and whether the rename is APPLICABLE; mode=apply does the same and, when applicable, WRITES it through the changeset engine (all files or none, fingerprints, a backup of each in __delphi-patch) and answers with the commit. Strict on purpose, in both modes: one unverified reference, a file of the scope it cannot read, a hit in a .dfm/.fmx (form bindings break), a hit inside a string literal (FindComponent/RTTI/StyleLookup by name), a symbol defined outside the workspace (RTL/components) or a collision with the new name = applicable=false with the reasons, and apply writes nothing. It renames CODE only: a mention in a comment keeps the old name (on an occurrence's line too) and is reported as a warning for you to look at. Rebuild afterwards.

*Access: mixed (`mode` preview read-only; every other mode read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | The .pas/.dpr with the symbol (any occurrence works) |
| `line` | integer | **yes** | Zero-based line of the identifier (a hit's "line0"; same convention as delphi_definition) |
| `character` | integer | **yes** | Zero-based column inside the identifier (a hit's "character0") |
| `newname` | string | **yes** | The new identifier (legal Delphi name, no reserved words) |
| `mode` | string | optional | preview (default; never writes) \| apply (writes it when applicable, through the changeset engine; refused with the blockers otherwise) |
<!-- /contract -->

**`mode=apply` (1.0.17) writes it - through the changeset engine, not on its own.** The same analysis runs first; when applicable, every touched line is staged as one edit (the identifier replaced as a WORD, so a qualified header `TClass.Method` keeps its class and two occurrences on one line change at once), the batch is previewed and committed: all files or none, fingerprints re-checked, a byte snapshot of each file taken first and a copy in `__delphi-patch` as with any edit. The answer is the preview's plus `applied`, `editsApplied` and the `commit` audit; not applicable = `applied:false`, nothing written, blockers given. It renames code only (1.10.0): a mention in a comment keeps the old name, also on the line of an occurrence, and comes back in `warnings`. Rebuild afterwards - the tool does not.

### `delphi_designer`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

FORMS AND COMPONENTS, structured - never guess what a class publishes or what a form contains (each command in "command"). Classes (info, prop) are read from the source of the active Delphi - its library and browsing paths, so installed components with source are in too; forms (tree, get, lint, check-binding, layout) from the .dfm/.fmx, a BINARY .dfm read on the fly; preview DRAWS the form as the IDE designer shows it and returns the image. insert, set and delete EDIT the form and its unit the way the IDE does: to add a visual control use insert (its block is not written by hand; a non-visual component, or a class the table does not have, is - the refusal says how), to change one property set, to remove one delete; then preview to see it. to-text/to-binary convert a .dfm. A read-only credential gets the reading commands (preview leaves its PNG in the workspace temp, so it is not one of them).

*Access: mixed (`command` info / prop / tree / get / lint / check-binding / binding / layout read-only; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | info (every property a class really publishes: kind and type, events apart) \| prop (one property in detail, with the legal members of an enum/set) \| tree (the component tree: name, class, line) \| get (one component's block, verbatim) \| lint (first what the IDE's own form parser says, then properties the class does not publish and values their type does not take, as set judges them; objects it could not check - a class not in the table, or ambiguous - go apart as notes) \| check-binding (does the .dfm agree with the class in the .pas: components with no published field, events naming a method that is not published, published fields with no component, duplicate names - all of which COMPILE and then throw when the form is created) \| layout (WHERE things end up on a VCL .dfm: resolves Align and returns every control's rectangle plus those of size zero, outside their container, overlapping or clipped by the bands around them - a form can bind perfectly and still be unusable) \| to-text (a BINARY .dfm becomes text on disk, the IDE's own conversion, backup first - reading never needs it) \| to-binary (the way back, the resource-wrapped form the IDE writes) \| preview (a PNG of what the IDE designer shows for the .dfm/.fmx, in this answer: built in design mode with the IDE's installed packages, no code run and nothing on any screen; nonVisual lists the non-visual components, fidelity says how it was painted) \| insert (a NEW visual control: classname; component, its Name - the IDE's Button1, Button2... by default; parent - the form by default; placed at 10,10 as the last child, with its published field in the form's class and its unit in the uses; the answer is its numbered block) \| set (ONE property: prop + value, checked against the property's type and the class BEFORE writing; parent= alone moves the component; before=, after= or index= alone reorders it among its siblings; prop=Name renames it, its field and the form lines that name it) \| delete (the component and what is inside it, the references to it in the form, its field and its EMPTY handlers; refused while a method of its own has code - the answer lists them with their line, to clean first). Default: info |
| `path` | string | optional | tree/get/lint/check-binding/layout/preview/insert/set/delete/to-text/to-binary: the .dfm or .fmx file. The reading commands and preview read a binary .dfm too, on the fly; insert, set and delete edit a text form (command=to-text converts it, backup first). insert, delete and a rename also write its unit, the .pas of the same name |
| `classname` | string | optional | info/prop: the component class, e.g. TButton, TEdit, TLayout. insert: the class of the new control |
| `prop` | string | optional | prop: the property name, e.g. Align, Caption, TextSettings. set: the property to write, dotted for a sub-property (Font.Size, Position.X); Name renames the component |
| `component` | string | optional | get: the component Name as it appears in the form (object \<Name>: \<Class>). preview: crop the image to that component (one inside an inline frame goes as Frame1.Name); componentRect says where it is in the form. set/delete: the component to change or delete. insert optional: the Name of the new control (an identifier free in the form and its class), its text too when the class shows one; without it, the IDE's own (Button1, Button2...) |
| `unit` | string | optional | check-binding, optional: the .pas with the form's class. By default, the one with the same name as the .dfm. |
| `framework` | string | optional | info/prop: vcl \| fmx (default vcl). preview: the file decides (.dfm = vcl, .fmx = fmx); if given, it must agree |
| `filter` | string | optional | info optional: only properties whose name contains this text |
| `maxdepth` | integer | optional | tree optional: how many levels to show (1 = only the form; 0 or empty = all). An object on the last level shows childrenCount instead of its children |
| `state` | string | optional | preview optional: a VIEW state applied before drawing, never written to the file - Component.Property=Value (inside an inline frame, Frame1.Component.Property=Value), several separated by ; (PageControl1.ActivePage=TabSheet2;Edit1.Text=hello). A value with a ; goes in single quotes as in a form (Edit1.Text='a;b'; a quote inside is written twice); a quote that does not start the value is just a letter (Label1.Caption=It's). A property that holds a component takes the component's name. No double quotes. |
| `style` | string | optional | preview optional. VCL: a .vsf file (the form is then drawn out of design mode: VCL styles never apply to designed controls) or none (the default, as the designer). FMX: empty = the form's own StyleBook (as the designer), none = the Windows default, a .style file, or a platform of the designer's Style list (android, ios, win11...; an unknown name is answered with the list). A file goes by absolute path. |
| `nonvisual` | boolean | optional | preview optional: true = draw the non-visual components (TTimer, TActionList, datasets...) where the designer puts them, with their icon and name. Default false: the image shows the form as it will look, and nonVisual lists them anyway. |
| `inline` | boolean | optional | Default true: the capture this answer brings - a screenshot, the one every gesture returns (tap, type, swipe...), a preview - comes back IN this answer as an image (scaled to maxwidth), and no file is kept to download later. false = a file and its download link (a client without vision, or one that wants the bytes). |
| `maxwidth` | integer | optional | Inline only: the width the image is scaled to before it travels (0 = 1280). The answer says inlineScale: divide what you measure on the inline image by it to get capture pixels, or use the answer's frame (a tap takes it, and delphi_desktop's type too; preview's converts to form units). |
| `out` | string | optional | preview: where the PNG lands: a FOLDER (existing, or ending in \ - the server names the file) or a FILE whose extension matches the capture's real format. Empty = __delphi-temp\\<agent>, wiped on server restart. On THIS server, jailed like any path. With inline=false the capture stays there and the answer carries its download link. |
| `parent` | string | optional | insert: the container that receives the new control, by its Name (the form by default). set: MOVE the component, with its children, into this container - alone, without prop or value; it keeps its Left/Top, now relative to the new parent, and takes the next TabOrder there. |
| `value` | string | optional | set: the new value, as the form file writes it: 120, True, alClient, [akLeft, akTop], clRed, the Name of another component (PopupMenu1), nil to clear one. A string goes quoted ('OK', 'Acci'#243'n') or not (OK): set writes it the way the IDE does, accents as #N and a long one in pieces; so does a number as typed (0.7). |
| `props` | string | optional | insert / set optional: SEVERAL properties at once, Prop=value pairs separated by ; (Caption=Save;Left=24;Font.Style=[fsBold]) - each value as in "value", and a ; inside a quoted value does not split (a quote that does not start the value is just a letter: Caption=Don't). insert: the initial properties of the new component; set: instead of prop/value. Each one is judged as set judges one, and it is all or none: one that does not pass and nothing is written. Name goes alone. |
| `before` | string | optional | set optional: put the component just BEFORE this sibling (its Name, the same parent), alone. Before writing, the IDE's own writer is asked with the form loaded as the designer loads it: an order it would not keep (VCL graphic controls go before windowed ones, an inherited form places by its [n]...) is refused with the order it would save. |
| `after` | string | optional | set optional: put the component just AFTER this sibling (its Name), alone - the same check as before. |
| `index` | integer | optional | set optional: the component's position among its siblings in the file, 1 = the first, alone - the same check as before. The file order is the z-order (a later one is drawn on top; an inherited form counts only what its own file writes); TabOrder is the keyboard order. |
<!-- /contract -->

`preview` (1.17.0) is drawn by two renderers that ship next to the server,
`DelphiFormRenderVcl.exe` and `DelphiFormRenderFmx.exe` (`src/Render`): the form
is built in design mode with the IDE's installed packages loaded into the
renderer, never into the server, and nothing of the form's code runs. The image
comes back in the answer like any capture, with its `frame`: a point measured on
the image is `ox + x*srcW/imgW`, `oy + y*srcH/imgH` of the form's client area,
in `.dfm`/`.fmx` units (the renderer is not DPI-aware). `fidelity` says how it
was painted - `window` (the real painting, an interactive session: the tray),
`print` (control by control, what a Windows service can do: controls that paint
their own way come out native-looking), `canvas` (FMX, always its own canvas).
The answer lists `nonVisual` always, `substituted` for classes no installed
package registers (a named box at their place), `ignored` and `warnings` from
the reader, and `ms`.

`insert`, `delete` and a rename (`set prop=Name`) (1.17.0) write the form and
its unit together, all or nothing; any other `set` writes the form only
(`Lsp.DesignerEdit`). What `insert` cannot place - a non-visual component, a
class or a parent the tables do not have, a unit missing from a `uses` split in
`{$IFDEF}` branches - is written by hand, and its refusal says how. A name, given by `insert component=` or by
`set prop=Name`, is judged by one rule: an identifier, not a reserved word, taken
by nothing in the form or its class (`DSGN-095`/`096`); without one, insert takes the IDE's
first free `Button1`, `Button2`... The Caption/Text follows the name when the
class's `SetName` does that, read from the source by the table generator.
`delete` is refused (`DSGN-086`) while a method of the component - a handler it
is bound to, or one named after it - still has code; an empty one goes with it,
a shared one stays, and `usesInCode` lists the code that still names it.
`set` checks a value against what its type takes, as the form loader
(`TReader`) reads it, from facts the table generator takes from the Delphi
source: what a simple type reduces to (`TColor` is a subrange of integers,
`TCaption` a string) and the named constants an integer type registers
(`RegisterIntegerConsts`: `clRed`, `crHandPoint`; a misspelt one gets the
close one). A reference has to name a component of the property's class or
of a descendant: the `DataSource` of a `TDBGrid` takes a `TDataSource`, and
`DSGN-107` lists the components of the form that fit. A number with decimals is
written as the 32-bit IDE writes it (`FloatToStrF(V, ffFixed, 16, 18)` of the
value the property stores - a `Single` rounded as a `Single`: `0.7` becomes
`0.699999988079071000`), computed from the exact digits of the number, because
the 64-bit RTL of the server rounds differently; no IDE rewrites the form
afterwards. An inline frame's class belongs to the project and is not in the
table: `set` judges its properties as a `TFrame`'s. A string is written as
`ObjectBinaryToText` writes it (accents and quotes as `#N`, a long one in
pieces of 64 on the lines below); `nil` clears a reference; a reference to a
component inside an inline frame is written `Frame1.Name`, as the form loader
resolves it (the frame's names are not the form's), and like one to another
form (`Form2.ImageList1`) it goes as given: set does not read the other file.
The frame's own components are edited in its own file (`DSGN-083`).

Since 1.2.3 `check-binding` is not only on request: `lint` includes it when the
`.pas` sits next to the form, every write to a designer through `delphi_edit`
reports it at once, and `delphi_edit insert=metodo` without `visibility` puts a
method in `published` when the paired designer already wires it as an event. An
event to a method that is not `published` builds fine and kills the form at load
time ("Invalid property value"): the loader only sees published methods.

## FMX styles

### `delphi_styles`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

FMX STYLES of a project, by StyleName: the text .style files (what the Bitmap Style Designer exports and a style pipeline keeps as source of truth). command=view lists the styles of a file (StyleName, class, lines, parts); get shows one whole; set changes or adds ONE property of a style or of a part inside it (child=background/text), value written exactly as the file does (xAARRGGBB colors, floats with 18 decimals, quoted strings); clone copies a style under a new StyleName - the way to add a variant; delete removes a whole style by StyleName (the copy in __delphi-patch is the way back); lint checks the whole thing: duplicated StyleNames, StyleLookup values in the project's .fmx/.pas that NO style defines (the platform default style counts), design tokens missing in a theme of a *Tokens.ini, .rc entries whose file is missing; build converts every text .style of the folder to .bin.style (the form an app embeds: embedded TEXT loads but does not resolve StyleLookup) and compiles the folder's .rc to .res with brcc32. Binary styles are never edited. Edits keep encoding and leave a __delphi-patch copy.

*Access: mixed (`command` view / get / lint read-only; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | view (styles of a .style file: StyleName, class, lines) \| get (one style, whole text) \| set (one property of a style or of one of its parts) \| clone (a new style copied from an existing one) \| delete (remove a whole style by StyleName; the __delphi-patch copy is the way back) \| lint (duplicated StyleNames, StyleLookup values of the project's .fmx that no style defines, design tokens missing in a theme, .rc entries without file) \| build (every text .style of the folder -> .bin.style, then the .rc -> .res with brcc32) |
| `path` | string | **yes** | The text .style file (view/get/set/clone) or the styles FOLDER (lint/build; a file there stands for its folder). Binary styles (FMX_STYLE / .bin.style) are refused for editing: edit the text one and run build. |
| `project` | string | optional | lint: the project .dproj (or a folder) whose .fmx/.pas files are scanned for StyleLookup. Default: the parent folder of the styles folder |
| `style` | string | optional | get/set/clone: the StyleName of the style (top-level object of the container), e.g. buttonstyle or cardstyle |
| `child` | string | optional | set optional: a part inside the style, by StyleName or object name, as a path: background or background/text |
| `prop` | string | optional | set: the property, as written in the file: Fill.Color, Size.Height, Visible, TextSettings.Font.Size... |
| `value` | string | optional | set: the value EXACTLY as it appears in a .style file: xFFF6ECDB (colors AARRGGBB), 44.000000000000000000 (floats), True/False, 'text' (strings quoted), Center (enums) |
| `name` | string | optional | clone: the StyleName of the new style |
| `filter` | string | optional | view optional: substring the StyleName must contain |
| `delete` | boolean | optional | set: true = remove the property instead of setting it |
<!-- /contract -->

The server ships `DelphiStyleConvert.exe` next to its own exe for `build` and for the platform default style names used by `lint`.

## Transfer files

### `delphi_fetch`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Download a file FROM the server - the "get the deploy" tool: after delphi_build, fetch the exe (and the companion files delphi_list shows) to run GUI apps on YOUR machine. Two ways: (1) the answer's "download" field is a direct HTTP GET on this same server (/files?path=...): run it with curl and your same Bearer token - the standard way for any file, installers and binaries included; (2) base64 chunks inline, for small files or clients without a shell: loop offset until eof=true, concatenate the decoded chunks, verify the sha256 (of the whole file, given on the offset=0 call). Files over 1 MB answer with the download link only; maxbytes<=1048576 forces inline chunks instead. Jailed to the workspace roots and the read-only library zone.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file to download from the server |
| `offset` | integer | optional | Byte offset to start from (0 = beginning). Loop increasing it until eof=true and reassemble |
| `maxbytes` | integer | optional | NOTE: maxbytes<=1048576 (1 MB) FORCES inline base64 chunks - the opposite of what you want with a large file. For a large download OMIT it: above 1 MB the answer carries the download LINK and no inline chunk ("inline":false, "bytes":0), the cheap way. maxbytes only sets the chunk size (max 8388608) when the content goes inline. |
<!-- /contract -->

**Answer fields** (HTTP hosts): `path`, `size`, `offset`, `bytes`, `eof`, `sha256` (offset=0), `chunkBase64` (omitted on the link-only answer), **`download`** (relative URL, e.g. `/files?path=srvd%3A%5C...`), `downloadNote` (the exact `curl`), `note` (on the link-only answer).

#### The `/files` download route

`GET http://<host>:<port>/files?path=srvd:\...\file` with the same `Authorization: Bearer` header you use for `/mcp` (both tokens work — downloading is reading). Streams the file with `Content-Disposition` and an **`X-File-SHA256`** header to verify with `sha256sum`. Same read jail as `delphi_read`: outside the roots/library zone → 403; a directory → 400 (it names a folder, and this route serves files: never a listing); unserved virtual units and relative paths are refused by name without touching disk; missing → 404; other methods → 405. Example:

```bash
curl -H "Authorization: Bearer $TOKEN" -o LinuxPAServer37.0.tar.gz \
  "http://WINDOWS-HOST:3000/files?path=srvc%3A%5CProgram%20Files%20(x86)%5CEmbarcadero%5CStudio%5C37.0%5CPAServer%5CLinuxPAServer37.0.tar.gz"
```

### `delphi_upload`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Upload a file TO the server in base64 chunks - the mirror of delphi_fetch, for what you cannot recreate by editing: binaries (.res, icons, images), binary designer files, archives, reference material. Chunks in order: offset=0 creates/truncates, later offsets append and must match the current size. sha256 on the LAST chunk has the server verify the assembled file; chunkSha256 on ANY chunk checks that chunk BEFORE it is written. Jailed to the workspace roots; parent folders are created; a fresh upload over an existing file backs the old one up to the recoverable trash first. For SOURCE CODE prefer delphi_edit / delphi_textedit (they audit encoding and keep backups).

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file to write ON the server (inside the workspace roots) |
| `chunkbase64` | string | **yes** | One chunk of the file, base64-encoded. offset=0 truncates/creates; later offsets append |
| `offset` | integer | optional | Byte offset this chunk starts at (0 = beginning). Send chunks in order, increasing offset by the bytes written |
| `sha256` | string | optional | Optional, on the LAST chunk: the whole-file SHA-256; a mismatch FAILS the call and the file is set aside as \<name>.corrupt instead of being published. |
| `chunksha256` | string | optional | Optional: the SHA-256 of THIS chunk (of its decoded bytes), verified BEFORE it is written - a slip in transit is caught at the chunk that carried it, with nothing on disk. |
<!-- /contract -->

## Version control

### `delphi_git`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Whitelisted git operations on a repository of this machine, so a remote agent can bring in code and version its work - the rules of each are in "command". clone is the fast way to get a whole repo onto the server (far better than recreating files one by one). worktree puts ANOTHER version of the repo next to it to build and compare, without touching anybody's working tree (yours to clean up). Commit/tag messages, config values and the clone URL travel in "message"; push/pull use the credentials and remotes stored on the server. The repository - root folder and .git - has to be inside your roots: git works on the whole repository it finds from "repo" upwards, so one that starts above your roots is refused (GIT-041). No arbitrary git commands, no shell.

*Access: mixed (`command` status / diff / log / show / ls-remote read-only; branch only without args or message (then it lists); tag only without args or message (then it lists); worktree only with args=list; stash only with args=list; every other command read-write, refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `repo` | string | **yes** | Path of the repository (or any path inside it). The repository ITSELF - root folder and .git - has to be inside your roots: git works on the whole tree. clone: the DESTINATION folder (created if needed, inside your roots). |
| `command` | string | **yes** | status \| diff \| log \| show \| branch \| switch \| merge \| stash \| add \| restore \| commit \| init \| push \| tag \| config \| clone \| pull \| fetch \| ls-remote \| worktree. switch: args=\<branch> (create=true for a new one). merge: args=\<branch>, always --ff-only (one needing a commit is refused, never left half-done). pull: args=\<remote> \<branch>, always --ff-only; options: only the download ones (--tags, --no-tags, --prune, --depth=\<n>, --unshallow). fetch: those and --all. push: --tags, -u, --set-upstream, --dry-run, and after the remote the NAMES to send (main, v1.3.2, local:remote): it adds to the remote, never overwrites or deletes. ls-remote: args=\<remote> [refs], read-only, same remote policy (--heads, --tags, --refs, --symref, --exit-code). The remote of these is a network address the operator allows or a folder inside your roots. stash: args=push\|pop\|list (never drop); push -- \<paths> parks ONLY those paths and sets them back to HEAD - how you discard one file's changes without losing them (pop brings them back); its label goes in message. config: args=user.name\|user.email, the value in message. clone: URL in message, destination in repo. worktree: args=list \| add (path = a NEW folder inside your roots, ref = tag\|branch\|commit, detached) \| remove (path = one that list shows; refused with changes or a link inside). restore: args=\<paths> (. = all), always --staged: they leave the index and the working tree is never touched - how you undo an add (to discard changes: stash push -- \<paths>). |
| `args` | string | optional | Optional extra arguments (paths, --staged, a commit hash...), SPLIT ON SPACES: a path with spaces goes in double quotes (args="my notes.txt"). No shell, and shell metacharacters (; \| & ` $ < >) are refused anyway - if a legitimate option needs one (--pretty=format:...), ask for it with delphi_report. |
| `create` | boolean | optional | switch: true = create the branch and move to it (git switch -c). Refused with any other command (GIT-038). |
| `message` | string | optional | commit: the commit message. tag: makes the tag annotated. config: the value. clone: the repository URL |
| `path` | string | optional | worktree add: a NEW folder inside your roots for the second working copy (like the destination of a clone). worktree remove: a folder that command=worktree args=list shows |
| `ref` | string | optional | worktree add: the tag, branch or commit to put there, detached - a version to build and compare, not a place to work (v1.3.2, main, HEAD~3, a commit hash) |
| `offset` | integer | optional | status/diff/log/show, branch/tag without arguments, stash list, worktree list: lines to skip when the answer did not fit in one page - pass the offset its note gives. |
<!-- /contract -->

**What the answer carries (hand-written).** A git that exits non-zero is an ERROR: `[GIT-036 DENIED] exit=N` with git's own output after it; a success starts with `exit=0` (`diff --quiet` / `--exit-code` with differences answers `exit=1`, and that is a success too: `[GIT-037]`).

## Feedback

### `delphi_report`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Report a problem, limitation or suggestion about THIS MCP server to its maintainers - whenever a tool refuses something you believe legitimate, an answer looks wrong, a message is confusing, or you had to work around a missing capability: that feedback is what fixes the server. Each report is its own timestamped markdown file (with the server version and date) in a reports folder next to the server; a stable "agent" id gives your reports their own subfolder. Available at EVERY access level, read-only included. Be concrete: what you tried, what happened, what you expected.

*Access: read-only OK (side effect: writes a report file on the server for the operator).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `message` | string | **yes** | The report itself: what you tried, what happened, what you expected. Markdown welcome, several paragraphs are fine |
| `title` | string | optional | Optional one-line summary (becomes part of the file name) |
| `kind` | string | optional | Optional: bug \| limitation \| suggestion \| question (default: bug) |
| `from` | string | optional | Optional: who is reporting (agent/model name, project) - helps us read the history later |
| `agent` | string | optional | Optional short id of the reporting agent (e.g. "hermes"): its reports go to a folder of that name, apart from other agents. Keep it STABLE. Letters, digits and dashes; anything else is normalized away. |
<!-- /contract -->

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
`delphi_create {kind:"project-vcl"|"project-fmx"|"project-console"|"project-package"|"project-test", dir, name}`, or `{kind:"form-vcl"|"form-fmx"|"frame-vcl"|"frame-fmx"|"datamodule"|"unit", project, name}` (registered in the `.dpr` and the `.dproj` on creation). An existing `.pas` joins with `delphi_config {project, command:"add-unit", path}`; `remove-unit` takes it out and keeps the file. `delphi_delete`/`delphi_move` on a unit keep the projects that list it consistent (designer pair included).

### Build and get the binary onto your machine
1. `delphi_build {project, platform:"Win64", config:"Debug", target:"Build"}` — structured errors/warnings.
2. `delphi_package {dir:"...\Win64\Debug"}` to zip the deploy, then `delphi_fetch {path:"...deploy.zip"}` in a loop (increase `offset` until `eof:true`), verifying the whole-file `sha256` — and run it on YOUR machine, **or**
3. deploy it to a target: `delphi_build {target:"Deploy", profile}` + `delphi_paserver {command:"remote-run"}` on a PAServer machine, or `delphi_adb {command:"install"}` on an Android device. Nothing executes on the server itself except a test project through `delphi_test` (`AllowTests`).

### Bring a repository onto the server, work, commit
1. `delphi_git {command:"clone", message:"https://...", repo:"srvd:\...\dest"}` — the whole repo in one call, jailed.
2. Edit with the tools above.
3. `delphi_git {command:"add", repo:"...", args:"-A"}` → `{command:"commit", repo:"...", message:"..."}` → `{command:"push", repo:"..."}` (uses the server's stored credentials). Set identity first with `{command:"config", repo:"...", args:"user.name", message:"..."}`.

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
2. **Open the port in THAT machine's firewall** - Windows' own or the antivirus suite's. Measured: the port answered nothing until a rule was added in ESET's firewall; Windows' was not the one blocking. `test-connection host=<ip> port=64211` with no profile is the probe: `tcpReachable=false` with the machine answering a ping is a firewall.
3. **Register the profile from here**: `add-profile profile=<name> host=<ip> port=64211 password=<yours> platform=Win64`, then `test-connection profile=<name>` for the full handshake. The host must be inside the workspace's `RemoteHosts`.

From then on `delphi_desktop profile=<name>` does the rest by itself: the first gesture deploys the node (`nodeDeploy: deployed`), and capture, `windows`, `window=` crops and `tap` work as on Linux. Nothing else is installed on that machine.

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
4. `delphi_paserver {command:"test-connection", host:"...", port:"64211"}` — raw TCP probe: does this server reach your PAServer at all? Then `{command:"add-profile", profile:"mi-linux", host, password}` and `{command:"test-connection", profile:"mi-linux"}` — full handshake.
5. `delphi_paserver {command:"get-sdk", profile:"mi-linux"}` — pull the SDK/sysroot once (can take minutes); after this the linker works.
6. `delphi_build {project, platform:"Linux64", config:"Debug"}` — build; add `target:"Deploy", profile:"mi-linux"` to build **and ship** to the target's PAServer scratch dir, exec bit set.

### Deploy and drive an app on an Android device (the device hangs off the server)
1. `delphi_adb {command:"discover"}` — devices announcing wireless debugging on the server's network, each with its ip:port (or the developer reads it off the device screen and hands it to you).
2. `delphi_adb {command:"connect", address:"192.168.1.163:5556"}` — attach it (the device asks to authorize the first time); `{command:"devices"}` lists what is attached.
3. `delphi_config {project, command:"add-platform", platform:"Android64"}` then `delphi_build {project, platform:"Android64", config:"Debug", target:"Deploy"}` — the server generates the deployment manifest if the project has none and the result declares the built `.apk`.
4. `delphi_adb {command:"install", apk:"...\bin\App.apk", device:"..."}` → `{command:"run", app:"com.embarcadero.App", device:"..."}` — the IDE's "Deploy and Run", by tools.
5. `delphi_adb {command:"screenshot", device:"..."}` (the screen comes back in the answer), `{command:"tap", x, y, device:"..."}`, `{command:"key", key:"back", device:"..."}`, `{command:"logcat", filter:"MyApp", device:"..."}` — your remote eyes and hands to drive and debug it.

### Report a problem
`delphi_report {message, title, kind:"bug"|"limitation"|"suggestion"|"question", from}` — stored as a dated markdown next to the server exe. Works even read-only; use it whenever a tool blocks something you believe is legitimate.


### `delphi_messages`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Your MAILBOX: messages the operator leaves for you (the way back of delphi_report). command=read delivers every pending message in YOUR box and DELETES it (read once, nothing kept); check only lists what waits. While mail for you waits, every tool answer ends with a PENDING MESSAGES line - read it then: it may change what you are doing. PRIVACY, honestly: the box is indexed by the agent id YOU declare and nothing ties that id to the caller - everyone here shares one token - so anyone can list and consume the mail of an id they guess, and a consumed message is gone. Treat it as a shared noticeboard: read YOUR id, not other people's, and send nothing secret.

*Access: read-only OK (side effect: command=read consumes (deletes) the message it delivers).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | read (default: deliver every pending message in your box, then DELETE it) \| check (titles and dates of what waits, nothing consumed) |
| `agent` | string | optional | Your agent id - the same value you give delphi_report as "agent" (e.g. dsh, hermes). Omitted: the id your client declared at the handshake |
<!-- /contract -->

Operator side: drop a `.md` in `messages\<agent>\` next to the server exe (`scripts\Enviar-Mensaje.ps1 -Agente dsh -Titulo ... -Texto ...`). The agent gets it once and reading DELETES it: nothing is kept aside and nothing is purged later. There is no box "for everyone": a notice for all is dropped once per agent. An agent with no id has no mailbox.

## Knowledge vault (optional — only for workspaces that declare `VaultPath=`)

Persistent memory: a folder of Markdown notes linked with `[[wikilinks]]`.
These tools are **not registered at all** unless a vault is configured, and
`tools/list` announces each workspace only the ones its vault allows: none
without a vault of its own, and not the three write ones while it is
read-only (`VaultReadOnly=0` turns them on; they also need a read-write
credential).

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

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Reads a note of the knowledge vault by relative path. WITHOUT path it returns the rules (AGENTS-VAULT.md) + the index (MEMORY.md): do that when starting. The [[wikilinks]] in the content refer to other notes - locate them with vault_search target=files. NOTE: the vault this server serves is the one its operator has exposed (the VaultPath= of YOUR [Workspace.\<name>] in settings.ini), which may be a COPY and not the user's live folder: if something sounds outdated, ask before taking it as good.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | optional | RELATIVE path of the note inside the vault (projects/x/context.md). WITHOUT path it returns the rules + the index: do that when you start |
| `offset` | integer | optional | Optional: first line to return (1 = beginning) |
| `limit` | integer | optional | Optional: how many lines to return from offset |
<!-- /contract -->

### `vault_search`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Searches the knowledge vault (Markdown notes linked with [[wikilinks]]). PROTOCOL: when starting a task, first call vault_read WITHOUT path to get the rules and the index; decide from the index descriptions which notes to load with vault_read - lazy loading, never read the vault in bulk.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `target` | string | optional | files (search by note NAME, a glob pattern such as *meeting*.md) \| content (search INSIDE the notes, pattern is a regular expression) |
| `pattern` | string | **yes** | Name glob if target=files (*.md, *delphi*), or a regular expression if target=content |
| `subfolder` | string | optional | Optional: vault-relative folder to narrow the search (projects, conventions...) |
| `maxresults` | integer | optional | Results PER PAGE (default 50, cap 500). |
| `offset` | integer | optional | Skip the first N results of the FULL list: pass the offset the previous answer gives; walking it reaches every result. |
<!-- /contract -->

### `vault_append`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Appends content to an existing vault note (log entries, progress updates). Write in the vault's language (AGENTS-VAULT-WRITE.md says which). Log format: dated entry under the section of the day. In progress.md respect its snapshot structure: live status lines, the history goes in log - do not accumulate; if you close a matter, delete its line with vault_patch instead of adding "done". The server keeps a copy of the original before writing.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | RELATIVE path of the note (must exist) |
| `content` | string | **yes** | Markdown content to add, in the vault's language |
| `anchor` | string | optional | Optional: UNIQUE text after which to insert. Without anchor, it is appended at the end of the file |
<!-- /contract -->

### `vault_create`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Creates a new note in the vault. BEFORE creating: read AGENTS-VAULT-WRITE.md (decision tree of where each thing goes, and templates) and link the note with [[wikilinks]] from the project notes (context.md, log.md, progress.md) - NOT from MEMORY.md: that root index is governance and is always refused; if the note deserves an entry there, ask for it in your answer or in a delphi_report and a person will do it. Write in the vault's language (AGENTS-VAULT-WRITE.md says which). Do not reorganize folders or move existing notes - that requires a human OK. It never overwrites: if the note exists, it is refused.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | RELATIVE path of the new note (must NOT exist; never overwrites) |
| `content` | string | **yes** | Full markdown content, with the structure/template the vault asks for |
<!-- /contract -->

### `vault_patch`

<!-- contract: generated from tools/list by scripts/tools_md.py - change the server, not this block -->

Targeted edit of a note: replaces old_text (UNIQUE in the file) with new_text. For striking closed lines of a progress or correcting a fact. To add content use vault_append; for large rewrites, stop and ask the user. The server keeps a copy of the original before writing.

*Access: read-write (refused to a read-only credential).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | RELATIVE path of the note |
| `old_text` | string | **yes** | Text to replace: it must appear EXACTLY ONCE in the file |
| `new_text` | string | **yes** | New text that replaces it |
<!-- /contract -->

