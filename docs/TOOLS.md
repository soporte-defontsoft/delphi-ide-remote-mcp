# Tool reference

Every tool this MCP server exposes, with its parameters, types and access level. Generated from the server's own `tools/list` (the exact schema the client receives), so it never drifts from the code.

- **Paths** use virtual drive units (`srvd:\...`, `srvc:\...`) — call `delphi_workspace` first to learn the roots.
- **Positions** for the semantic tools are 0-based (line and character), like the LSP. Point *inside* the identifier.
- **Access**: with a read-only credential (or `AnonymousReadOnly`) only the read-only tools run; mutating ones are refused at the gate.
- **Required column**: the MCP schema marks every field required (a limitation of the vendor's schema generator); the table below reflects what each tool *actually* needs — the rest are optional and have sensible defaults, as their descriptions note.

## Index

- **Understand the code (semantic, DelphiLSP-backed)** — [`delphi_symbols`](#delphi_symbols), [`delphi_definition`](#delphi_definition), [`delphi_signature`](#delphi_signature), [`delphi_hover`](#delphi_hover), [`delphi_completion`](#delphi_completion), [`delphi_references`](#delphi_references), [`delphi_diagnostics`](#delphi_diagnostics)
- **Read files & explore** — [`delphi_read`](#delphi_read), [`delphi_search`](#delphi_search), [`delphi_list`](#delphi_list), [`delphi_projects`](#delphi_projects), [`delphi_installs`](#delphi_installs), [`delphi_workspace`](#delphi_workspace)
- **Edit code safely  (read-write only)** — [`delphi_edit`](#delphi_edit), [`delphi_textedit`](#delphi_textedit), [`delphi_create`](#delphi_create)
- **Manage files  (read-write only)** — [`delphi_delete`](#delphi_delete), [`delphi_move`](#delphi_move)
- **Build, run, package  (read-write only)** — [`delphi_build`](#delphi_build), [`delphi_run`](#delphi_run), [`delphi_package`](#delphi_package)
- **Cross-platform: build configs & remote platforms** — [`delphi_config`](#delphi_config), [`delphi_paserver`](#delphi_paserver)
- **Transfer files** — [`delphi_fetch`](#delphi_fetch), [`delphi_upload`](#delphi_upload)
- **Version control** — [`delphi_git`](#delphi_git)
- **Feedback** — [`delphi_report`](#delphi_report)
- **Knowledge vault (optional)** — [`vault_read`](#vault_read), [`vault_search`](#vault_search), [`vault_append`](#vault_append), [`vault_create`](#vault_create), [`vault_patch`](#vault_patch)


## Understand the code (semantic, DelphiLSP-backed)

### `delphi_symbols`

Document symbol tree of a Delphi unit (classes, methods, properties, sections) with 0-based ranges, straight from the official DelphiLSP engine. Works even without project settings.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi source file (.pas/.dpr) |

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

Compiler-grade errors/warnings/hints for one Delphi source file (Error Insight via the official DelphiLSP linter), WITHOUT building. Real compiler codes (E2003, W1000, H2164...) with exact 0-based positions. Severity: 1=error, 2=warning, 3=hint. Lints the CURRENT on-disk content.

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
| `root` | string | **yes** | Directory to search recursively (project root) |
| `query` | string | **yes** | Literal text to find (case-insensitive - it is Pascal) |
| `maxresults` | integer | optional | Maximum hits to return (default 100, cap 500) |
| `wholeword` | boolean | optional | true = match whole identifiers only (word boundaries) |

### `delphi_list`

List Delphi files under a directory recursively (sources and project files by default, or a custom mask), skipping IDE artifacts. Returns path, size and last-write time. Capped at 500 entries. With dirs=true it lists the SUBDIRECTORIES of root instead (one level, explorer-style) - use that to browse the machine and decide where to create or look for projects.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | **yes** | Directory to list recursively |
| `pattern` | string | optional | Filename mask, e.g. *.pas (default: Delphi source and project files) |
| `dirs` | boolean | optional | true = list SUBDIRECTORIES of root (one level, explorer-style) instead of files |

### `delphi_projects`

Locate Delphi projects (.dproj/.groupproj) under a directory - or under the workspace roots configured in settings.ini [Workspace] Roots when root is empty. Optional name filter. Use this to answer "open project X" without knowing the disk layout.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `root` | string | optional | Directory to search under. Empty = the roots configured in settings.ini [Workspace] Roots (semicolon-separated) |
| `name` | string | optional | Optional name filter (substring, case-insensitive), e.g. "comunicador" |

### `delphi_installs`

List EVERY RAD Studio / Delphi installation discovered on this machine (a machine may host several versions side by side): version, root directory, whether it ships DelphiLSP.exe (semantic engine) and rsvars.bat (msbuild). Also reports which one is ACTIVE for the LSP tools (the newest with DelphiLSP). Read-only, no parameters.

*Access: read-only OK.*

No parameters.

### `delphi_workspace`

The lay of the land on the SERVER: the workspace roots this server operates within (your entire allowed universe here), the access level (read-write / read-only), and the active RAD Studio. Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only exist inside this MCP: use them verbatim in every path argument and you will receive them back in results. They are NEVER your own local disks. Call this FIRST. Read-only, no parameters.

*Access: read-only OK.*

No parameters.


## Edit code safely  (read-write only)

### `delphi_edit`

SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus text .dfm/.fmx) preserving the real encoding and line endings. Modes: EDIT (old = ONE full line copied from delphi_read + new), DELETE (delete=true + old: removes the line entirely), INSERT (insert="rutina-global"|"metodo" + code: the tool picks the legal spot - also inside a .dpr - and, for methods, writes BOTH halves: declaration and qualified implementation), CREATE (createunit=true; new files honour the encoding configured in the IDE) and RESTORE (restore=true, two-step). It refuses to rewrite whole files, refuses binary designer files (TPF0), makes automatic backups, writes atomically, and audits the result (encoding, EOLs, mojibake, end. structure) reporting the REAL lines read back from disk - use that as evidence. Never edit Delphi files with generic tools: CP1252 sources get destroyed.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the Delphi file |
| `old` | string | optional | EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the \| bar). Leading indentation may be omitted |
| `new` | string | optional | EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new together with the added code) |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers) |
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

### `delphi_textedit`

SAFE editing of plain-text NON-Delphi files (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml - ANY plain text): docs, web assets, tests, scripts, config. Same discipline as delphi_edit - one-full-line unique anchor (old/new, atline tie-break), real encoding preserved (UTF-8 +/- BOM / CP1252), line endings preserved, automatic backup, atomic write - without the Pascal gates. CREATE mode (create=true + content) for new files, never overwrites. Whole-file rewrites are refused. Delphi sources/designers are refused (use delphi_edit) and so are .dproj and binaries. Read first with delphi_read and copy the anchor exactly.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the text file (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml ... any plain text - Delphi files are refused, use delphi_edit) |
| `old` | string | optional | EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the \| bar). Leading indentation may be omitted |
| `new` | string | optional | EDIT mode: the new text; may be several lines. Empty = blank the line |
| `atline` | integer | optional | EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence |
| `create` | boolean | optional | CREATE mode: true = create a NEW file (never overwrites). UTF-8, parent directories created |
| `content` | string | optional | CREATE mode: the initial content of the new file (may be empty) |
| `eol` | string | optional | CREATE mode: line endings, "crlf" (default) or "lf" |

### `delphi_create`

Create a NEW Delphi project (console/VCL/FMX: .dpr + buildable .dproj + main form) or a NEW form (VCL/FMX: .pas + .dfm/.fmx pair, registered in the .dpr uses and Application.CreateForm). IDE-equivalent skeletons, CRLF, source encoding follows the IDE's configured default (UTF-8/ANSI), never overwrites anything. For plain units use delphi_edit with createunit=true.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `kind` | string | **yes** | What to create: project-console \| project-vcl \| project-fmx \| form-vcl \| form-fmx |
| `dir` | string | optional | Projects: target directory (created if missing) |
| `name` | string | optional | Projects: project name. Forms: unit name (e.g. UClientes) |
| `project` | string | optional | Forms: absolute path of the project .dpr to register the form in |
| `formname` | string | optional | Forms optional: form name without the T (default: Form+unit name) |


## Manage files  (read-write only)

### `delphi_delete`

Delete a file or folder inside the workspace. NOT a hard delete: the target is moved to a recoverable trash (__delphi-patch\<date>\deleted\ next to it), so a mistake can be undone. Jailed to the workspace roots, refused in read-only mode. Use it to clean up stray files and leftovers.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted |

### `delphi_move`

Move or rename a file or folder inside the workspace. Both source and destination must be inside the workspace roots; parent folders of the destination are created. The source is copied to the recoverable trash first. Jailed, refused in read-only mode.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file or folder to move (inside the workspace roots) |
| `dest` | string | **yes** | Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same |


## Build, run, package  (read-write only)

### `delphi_build`

Build a Delphi project for real with MSBuild on this machine (rsvars located via registry). Returns success flag, compiler errors/warnings and the output tail. Use this as the closing verification after editing - the linter does not link nor produce binaries.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the .dproj to build |
| `platform` | string | optional | Target platform (default Win32): Win32/Win64 build natively here; Linux64/OSX64/OSXARM64/Android64/iOSDevice64... need the platform enabled in the project (delphi_config) and a PAServer profile (delphi_paserver) |
| `config` | string | optional | Debug or Release (default Debug) |
| `target` | string | optional | Build (full, default) or Make (incremental). After switching platforms use Build |

### `delphi_run`

Run a built executable ON THIS MACHINE (the one that compiled it) and capture its output - the closing step after delphi_build for console apps and test runners. Jailed to the workspace roots, no shell, hard timeout (default 30 s, max 5 min), process killed on expiry. GUI apps will open on the server desktop.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the .exe to run (must be inside the workspace roots) |
| `args` | string | optional | Optional command-line arguments (shell metacharacters rejected) |
| `workdir` | string | optional | Optional working directory (default: the exe directory; must be inside the roots) |
| `timeoutms` | integer | optional | Timeout in milliseconds (default 30000, max 300000); the process is killed on expiry |

### `delphi_package`

Zip a build-output directory ON the server into a single deploy artifact (recursive, *.dcu intermediates excluded), ready to download with ONE delphi_fetch. The standard way to bring a GUI app to the client machine: delphi_build -> delphi_package -> delphi_fetch.

*Access: read-write.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `dir` | string | **yes** | Directory to package (e.g. the build output Win64\Debug). Recursive; *.dcu and dcu\ intermediates excluded |
| `outfile` | string | optional | Optional zip path (default: sibling of dir, named <dirname>-deploy.zip). Must be inside the workspace roots |


## Cross-platform: build configs & remote platforms

### `delphi_config`

See and manage a project's build configurations and target PLATFORMS. command=view (read-only) reports the framework (VCL is Windows-only; FMX and console cross platforms), the build configurations (Debug/Release/custom) and every platform with whether it is enabled, whether THIS project can target it, and whether it needs a remote PAServer profile. command=add-platform enables a platform in the .dproj (a curated edit of the <Platforms> block only). To BUILD a specific combination use delphi_build with platform+config.

*Access: mixed (view read-only; add-platform read-write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project` | string | **yes** | Absolute path of the project .dproj |
| `command` | string | optional | view (default: list configurations and platforms) \| add-platform (enable a platform in the project) |
| `platform` | string | optional | add-platform: the platform to enable (Win64, Linux64, OSX64, OSXARM64, Android64, iOSDevice64...) |

### `delphi_paserver`

The bridge for building and running on OTHER platforms (Linux, macOS) through the Platform Assistant (PAServer). command=packages lists the PAServer installers that ship with each Delphi install (download them with delphi_fetch and run them on the target machine); command=platforms shows which platforms this server can target and whether each already has a connection profile and SDK; command=profiles lists the registered connection profiles and platform SDKs. Read-only. Building for a platform is delphi_build once its profile exists; enabling a platform in a project is delphi_config.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | optional | packages (PAServer installers to download and run on the target) \| platforms (what this server can target + profile/SDK status) \| profiles (registered connection profiles and SDKs). Default: platforms |


## Transfer files

### `delphi_fetch`

Download a file FROM the server in base64 chunks - the "get the deploy" tool: after delphi_build, fetch the exe (and any companion files listed with delphi_list) to run GUI apps on YOUR machine. Loop offset until eof=true, concatenate the decoded chunks, and verify the sha256 (computed over the whole file, returned on the offset=0 call). Jailed to the workspace roots.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Absolute path of the file to download from the server |
| `offset` | integer | optional | Byte offset to start from (0 = beginning). Loop increasing it until eof=true and reassemble |
| `maxbytes` | integer | optional | Bytes per chunk (default and cap: 8388608 = 8 MB) |

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

Whitelisted git operations on a repository of this machine, so a remote agent can bring in code and version its work: status, diff, log, show, branch, add, commit, init, push, tag, config, clone, pull, fetch. **clone** is the fast way to get a whole repo onto the server (URL in "message", destination directory in "repo", jailed to the workspace roots) - far better than recreating files one by one. commit/tag messages and config values also travel in "message"; push/pull use the credentials and remotes stored on the server. No arbitrary git commands, no shell.

*Access: mixed (query commands read-only; write commands read-write).*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `repo` | string | **yes** | Path of the git repository (or any path inside it). For clone: the DESTINATION directory (created if needed, must be inside the workspace roots) |
| `command` | string | **yes** | One of: status \| diff \| log \| show \| branch \| add \| commit \| init \| push \| tag \| config \| clone \| pull \| fetch (config: args=user.name\|user.email + value in message; clone: URL in message, destination in repo) |
| `args` | string | optional | Optional extra arguments (paths, --staged, a commit hash...). Shell metacharacters are rejected |
| `message` | string | optional | commit: the commit message. tag: makes the tag annotated. config: the value. clone: the repository URL |


## Feedback

### `delphi_report`

Report a problem, limitation or suggestion about THIS MCP server directly to its maintainers. Use it whenever a tool refuses something you believe is legitimate, an answer looks wrong, a message is confusing, or you had to work around a missing capability - that feedback is what fixes the server. Each report is stored as its own timestamped markdown file in a reports folder next to the server executable, with the server version and the date. Available at EVERY access level, read-only included. Be concrete: what you tried, what happened, what you expected.

*Access: read-only OK.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `message` | string | **yes** | The report itself: what you tried, what happened, what you expected. Markdown welcome, several paragraphs are fine |
| `title` | string | optional | Optional one-line summary (becomes part of the file name) |
| `kind` | string | optional | Optional: bug \| limitation \| suggestion \| question (default: bug) |
| `from` | string | optional | Optional: who is reporting (agent/model name, project) - helps us read the history later |

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
`delphi_create {kind:"project-vcl"|"project-fmx"|"project-console", dir, name}`, or `{kind:"form-vcl"|"form-fmx", project, name}` (registers it in the `.dpr`). For a plain unit prefer `delphi_edit {createunit:true}`.

### Build and get the binary onto your machine
1. `delphi_build {project, platform:"Win64", config:"Debug", target:"Build"}` — structured errors/warnings.
2. `delphi_run {path:"...\App.exe"}` to run it on the server and capture output, **or**
3. `delphi_package {dir:"...\Win64\Debug"}` to zip the deploy, then `delphi_fetch {path:"...deploy.zip"}` in a loop (increase `offset` until `eof:true`), verifying the whole-file `sha256`.

### Bring a repository onto the server, work, commit
1. `delphi_git {command:"clone", message:"https://...", repo:"srvd:\...\dest"}` — the whole repo in one call, jailed.
2. Edit with the tools above.
3. `delphi_git {command:"add", args:"-A"}` → `{command:"commit", message:"..."}` → `{command:"push"}` (uses the server's stored credentials). Set identity first with `{command:"config", args:"user.name", message:"..."}`.

### Send a file TO the server
`delphi_upload {path, offset:0, chunkbase64:"..."}` per chunk (increasing `offset`); on the last chunk pass the whole-file `sha256` to have the server verify the reassembly. For binaries you cannot recreate by editing (`.res`, icons).

### Build for another platform (Linux/macOS)
1. `delphi_config {project}` — see the framework and platforms. **VCL is Windows-only**; only FMX or console apps cross.
2. `delphi_config {project, command:"add-platform", platform:"Linux64"}` — enable the platform in the project (refused on a VCL project, with the reason).
3. `delphi_paserver {command:"packages"}` — get the PAServer installer for the target; download it with `delphi_fetch` and run it on your Linux/Mac (it listens on port 64211).
4. `delphi_paserver {command:"platforms"}` — check the platform's profile/SDK status.
5. `delphi_build {project, platform:"Linux64", config:"Debug"}` — once the profile/SDK is in place. (Creating the profile against a live PAServer target is the next piece of `delphi_paserver`.)

### Report a problem
`delphi_report {message, title, kind:"bug"|"limitation"|"suggestion"|"question", from}` — stored as a dated markdown next to the server exe. Works even read-only; use it whenever a tool blocks something you believe is legitimate.


## Knowledge vault (optional — only when `[Vault] Path` is configured)

Persistent memory: a folder of Markdown notes linked with `[[wikilinks]]`.
These tools are **not registered at all** unless a vault is configured, and the
three write ones need `[Vault] ReadOnly=0` on top of a read-write credential.

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
| `target` | string | **yes** | files (buscar por NOMBRE de nota, patron glob como *reunion*.md) \| content (buscar DENTRO de las notas, pattern es una expresion regular) |
| `pattern` | string | **yes** | Glob de nombre si target=files (*.md, *delphi*), o expresion regular si target=content |
| `subfolder` | string | optional | Opcional: carpeta relativa del vault para acotar la busqueda (projects, conventions...) |
| `maxresults` | number | optional | Maximo de resultados (defecto 50) |

### `vault_append`

Anade contenido a una nota existente del vault (entradas de log, avances de progress). Escribe SIEMPRE en espanol. Formato log: entrada fechada bajo la seccion del dia. En progress.md respeta su estructura snapshot: lineas de estado vivas, el historico va en log - no acumules; si cierras un asunto, elimina su linea con vault_patch en lugar de anadir "hecho". El servidor guarda copia del original antes de escribir.

*Access: read-write only, and [Vault] ReadOnly=0.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota (debe existir) |
| `content` | string | **yes** | Contenido markdown a anadir. En espanol |
| `anchor` | string | optional | Opcional: texto UNICO tras el cual insertar. Sin anchor, anade al final del fichero |

### `vault_create`

Crea una nota nueva en el vault. ANTES de crear: lee AGENTS-VAULT-WRITE.md (arbol de decision de donde va cada cosa y plantillas) y enlaza la nota desde el indice que corresponda con [[wikilinks]]. Escribe en espanol. No reorganices carpetas ni muevas notas existentes - eso requiere OK humano. Nunca sobreescribe: si la nota existe, se rechaza.

*Access: read-write only, and [Vault] ReadOnly=0.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota nueva (debe NO existir; nunca sobreescribe) |
| `content` | string | **yes** | Contenido markdown completo, con la estructura/plantilla que pida el vault |

### `vault_patch`

Edicion puntual de una nota: sustituye old_text (UNICO en el fichero) por new_text. Para tachar lineas cerradas de un progress o corregir un dato. Para anadir contenido usa vault_append; para reescrituras grandes, para y consulta al usuario. El servidor guarda copia del original antes de escribir.

*Access: read-write only, and [Vault] ReadOnly=0.*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | **yes** | Ruta RELATIVA de la nota |
| `old_text` | string | **yes** | Texto a sustituir: debe aparecer EXACTAMENTE UNA VEZ en el fichero |
| `new_text` | string | **yes** | Texto nuevo que lo sustituye |
