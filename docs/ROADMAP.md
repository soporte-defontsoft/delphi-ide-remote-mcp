# Roadmap

Status page as of 2026-11-11 (current release v1.29.1; 44 tools).

## Delivered

- Foundations (former phases 0-5): DelphiLSP validated end-to-end (see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md)), architecture (see [ARCHITECTURE.md](ARCHITECTURE.md)), LSP core, MCP stdio + Streamable HTTP with Bearer auth, Config Fabricator, `delphi_diagnostics` / `delphi_references` / `delphi_build`, remote file toolset, one executable as service / terminal / tray
- Safe editing (`delphi_edit`, `delphi_read`), `delphi_changeset` and fragment mode (0.4x–1.0.15)
- Designer: read, lint, check-binding, layout (0.5x)
- Styles (0.5x)
- `delphi_test` (0.58)
- `delphi_git` switch / merge / stash (0.57); the whitelist now covers status, diff, log, show, branch, switch, merge, stash, add, commit, init, push, tag, config, clone, pull, fetch, worktree, restore (1.7.6, always --staged)
- PAServer chain, get-sdk per distro, remote-run + kill (0.5x–1.0.16)
- adb, including display and tapScale (1.0.17)
- One desktop tool through PAServer (`delphi_desktop profile=`), Linux + Windows node, PrintWindow fallback, region / window crops (1.0.16)
- Native run-job launcher (`node/McpRunJob`), no shell; the on-target runner was removed in 0.98 (1.0.16)
- Vault, messages, reports
- Auth model: workspace-or-nothing (0.91) and nothing-global (0.98)
- Jail floor at the gate (1.0.14); `__delphi-temp` inside the jail (1.0.12; superseded in 1.18.2: what the server does for itself lives in its own house, never in a root)
- `DelphiVersion` per workspace and the named Delphi (1.0.17) - superseded: one server, one Delphi, `[Server] DelphiVersion` (written by the server at its first start)
- `rename_symbol mode=apply` (1.0.17)
- HTTP session TTL (1.0.17)
- Bounded per-client notification queue (200)
- Dead keys and key modifiers on the desktop node; the `delphi_adb_linux` alias retired; unit rename follows into every unit and qualified reference (superseded in 1.23: the unit rename is retired - a move touches only what is named, and `fix-references` re-points); DUnitX failures listed; the engine's warm-up told apart from "not a symbol" (1.1.0)
- Designer binary `.dfm` read on the fly, and `to-text` / `to-binary` conversion (1.1.2)
- `delphi_create kind=project-test` and the engine's own DUnitX suite (1.2.0)
- Reference projects: `[Workspace.<name>] ReadOnlyRoots=` (1.3.0)
- `delphi_git worktree` (1.4.0)
- `delphi_paserver command=output` for a `remote-run` job (1.5.0)
- `delphi_move` re-points relative paths across the border (superseded in 1.23: it moves as an operator does and the answer names what crosses the border, `MOVE-023`); `delphi_config` on a `.groupproj` (`add-project` / `remove-project`); `fix-references`; standalone sources in `delphi_create` (1.6.0)
- Every message tagged with its outcome from one catalog, the server in English, and ten review rounds of all or nothing, the jail and the contract (1.7.0)
- The changeset preview rehearses with the engines; a unit move whose project cannot be re-pointed is all or nothing (`MOVE-019`; superseded in 1.23 with the re-pointing itself); `docs/TOOLS.md` contract blocks generated from `tools/list`; one access table that the gate consults and `tools/list` announces (`annotations.readOnlyHint`, `_meta.access`); `clean` for domain verdicts; long paths refused honestly (1.7.1-1.7.3)

- The life of the engines: asked to `shutdown` before their input is closed and launched so that no child can open an error dialog (1.7.10); stopped when nobody uses them for `[Server] EngineIdleMinutes`, and stopped and replaced when they hang (1.8.0)
- `delphi_docs`: the RAD Studio help installed with Delphi, searched and read in pieces - the list of help files is the IDE's own (1.10.0)
- One lexicon for Pascal text (`Lsp.Pascal`): what is code, a string, a comment or a directive, asked by every tool that reads Pascal instead of a dozen readers with a piece of the rule each (1.10.0)
- The designer tables read from the source of each installed Delphi - its own preprocessor and declarations reader, generated in the background and cached per version - instead of tables of one RAD Studio compiled into the exe (1.12.0)
- A cap on warm DelphiLSP engines: `[Server] MaxEngines`, the least recently used one that is not working makes room (1.13.0)
- One reader for Pascal classes, one composer for the citation of a line, the agent's regular expressions through PCRE, `delphi_git ls-remote`; a jail where Git never recurses into submodules and no tool names what lies behind a junction (1.13.0)
- Answers that say whose fix it is: a root whose drive is not connected (`WS-022`, `unavailableRoots`, `PROJ-005`), Git's dubious ownership (`GIT-057`), the download link above 1 MB (1.13.1)
- One server, one Delphi (`[Server] DelphiVersion`, and `DelphiUpdate` to check the installed update); tool descriptions about 11% shorter, each change measured against a small local model; `tools/list` without the tools the caller cannot use - the vault's where there is none or it is read-only, the write tools for a read-only credential (1.14.0)
- File lists that name each folder once (about 40% fewer tokens over ten list calls, measured); one convention for line numbers in every answer (`line` 1-based, `line0`/`character0` for the engine tools); `delphi_list` and `vault_search` by pages; a lint with no project settings answers at once (`LSP-035`) (1.15.0)
- A build is what the IDE would build (only a declared platform, `BUILD-046`; without `platform`, the project's default); a deploy through the `RemoteHosts` gate and a profile gate that fails closed (`PAS-052` to `PAS-055`); one helper for every paclient call, which says what to do against another Delphi's PAServer (`PAS-056`, `PAS-057`); a recursion limit for the agent's regular expressions; a battery that watches each format has one home (`test_paisaje`) (1.16.0)
- The designer sees and edits: `preview`, a PNG of what the IDE designer shows, drawn by a renderer of its own in design mode with the IDE's packages; `insert` (a visual control with the IDE's minimum, its published field and its unit, named by `component` or the IDE's first free name), `set` (one property checked against the tables before it is written; `parent=` moves, `prop=Name` renames) and `delete` (refused while a method of the component still has code); the form, and its unit when the edit touches it, all or nothing (1.17.0)
- Consolidation: the big units sorted by what they hold (`Lsp.Guard` split into `Lsp.Rutas`, `Lsp.Casa`, `Lsp.Settings`, `Lsp.Identidad`, `Lsp.TodoONada`, `Lsp.Args`, `Lsp.Lugares` and `Lsp.Mascara`, the codecs in `Lsp.Codificacion`, `delphi_git` in `Mcp.Tools.Git`); `lint` judging values as `set` does; `insert` and a rename on an inherited form seeing the ancestor's names; ANSI as the machine's code page, the first accent of a source written as the IDE writes it, and no writer leaving what would not read back the same; the Git jail closed (the repository's configuration as a whitelist, `.git` a protected place, LFS endpoints and every remote host judged, no signing); what a form names judged before it is rendered; a `delphi_edit` batch audited as a whole; one mailbox and one reports folder per workspace, which `delphi_report` lists and reads (1.18.0)

- An agent asks for operations: `delphi_git` without free `args`, each command with its own fields judged by git itself; the program the server launches by its name found only where the agent cannot write; a link inside a repository no longer lets git read or rewrite what is behind it; `delphi_build` choosing the profile and the target from what the IDE knows (1.19.0)

- What an agent reads back, measured with an independent agent and two models before publishing: answers sent once; desktop gestures that say only what they did; the IDE's own form reader asked at every door that writes or shows a form; a block as the anchor of a single edit; refusals that say where a parameter goes and which framework a property belongs to; `prop` and `info` that follow a class-typed property into its class (1.20.0)

- What the IDE would do, and nothing left behind: `delphi_config set-active` and a build without `config` that builds the project's selected one; the engine with the settings of the selected configuration and platform; a project `delphi_create` makes born as the IDE makes it; the IDE's form reader judging lines, numbers and the language of Windows; a `.rc` read by tokens and confined to its styles folder; `push` that never forces; every process the server kills cleaned from Windows' global atom table, and form renderers that put nothing on the desktop (1.21.0)

- The patches of 1.21: a hard link to a file outside the roots neither read, copied nor written through (every door, the server's own copies included); the build gate a whitelist of what a compile-only build understands, and what the build reads through the project judged by the read gate, whether it exists or not; the build supplying the output folders a project leaves undeclared, a `remove-*` of `delphi_config` taking an entry that points outside, an `<RcItem>` judged by its path and the binary's name following `OutputExt`, all found by compiling a real twenty-year-old project through the server; the library read zone following the IDE's Library Path while the server runs, `add-searchpath` taking several folders in one call, `delphi_git untrack`, a `.dproj` cut short refused as incomplete instead of "platform not enabled", a folder on a NAS released from the engine that had a document open under it, and the judges of the compiler's and git's output reading their codes instead of their prose (1.21.1, 1.21.2, 1.21.3, 1.21.4)

- A project of the IDE builds through the server the way the IDE builds it: the build gate judging only what the requested platform and configuration read, evaluating the groups of the `.dproj` as msbuild does, and a macro that expands to a list judged piece by piece (a real FMX project with an Android keystore outside the roots and the IDE's package list built for Windows and Linux on two machines); `delphi_config set-property` / `remove-property` / `get-property`, one property of the `.dproj` by name in the group of a build, written where the IDE writes it, on one reader and one writer of a project property; and a search path written with Windows' extended-path prefix judged like any other (1.22.0)

- The patch of 1.22: accents wherever an agent reads or points - the position tools on a line with accents, the failure messages of `delphi_test`, `delphi_git diff`/`show` of a source in the machine's ANSI code page -; `delphi_designer insert`/`set` writing what the IDE's own writer stores, and saying when it is not what was given; the build gate resolving a search path the way msbuild and `dcc` do; and a new project property written where the IDE writes it (1.22.1)

- The cleanup of 1.23: one rule where there were several. Files move, copy and delete as an operator does (only what is named, never overwriting, a folder that exists merged into, `Form1.*`), with a note of what crosses the border instead of rewriting projects; the jail comparing paths as the filesystem does; holes of the published 1.22.1 closed (a unit read through the main source's `in`, a profile and a move's note telling what exists outside the roots, a deploy command reaching the build); the server's house cleaning up a folder a test left locked; a copy taking a project and a whole repository

- The patch of 1.23: the holes a review of the whole source found in the published 1.23.0 closed (a build running code left in the project's folder; a project name or a hand-written `.deployproj` sending a file of the server's folder to a target; the instructions every client receives, the vault through a link and another agent's trash; a workspace with a repeated key staying open) (1.23.1)

- The form designer, and the renderer in its own container: `delphi_create` making inherited forms and frames, `insert` taking a frame of the project, `layout` measuring FMX forms and giving a VCL form the rectangles the VCL resolved; the form renderer always inside an AppContainer with no capabilities and no network, a form whose ancestor or frame lives in another folder drawn whole, a package disabled in the IDE no longer loaded; `delphi_adb stop` (1.24.0)

- The MCP revision 2026-07-28 next to the sessions, and what agents kept asking for: `delphi_search` with `context` and `exclude`, six more `delphi_git` operations, several operations in one `delphi_changeset stage`, the compiler's `hints` in a build, warnings and hints of a unit below its project's folder, the rename of a local and `RENAME-023`; `delphi_desktop` a permission of its own, per host; what a build and a test say read from their judges (MSBuild's classification, DUnitX's summary) instead of the console text; form renderers that state their protocol (1.25.0)

- The patch of 1.25: the designer never writing an edit after the client gave up (`DSGN-185`); a frame that contains itself told apart (`RENDER-026`) and never written by `insert` (`DSGN-186`); `RENDER-007` saying to repeat a first load of design packages under an antivirus (1.25.1)

- What the judges say, read from them: the build gate reading a `.dproj` as msbuild does (a `$(...)` name as written, `<Import>` paths unescaped, the body's macros as msbuild has them there, device prefixes refused); names compared as NTFS compares them; arguments composed as a Delphi program's `ParamStr` reads them (`RUN-025`, `TEST-037`); the style converter in its own container, with a protocol (`STYLE-065`, `STYLE-066`); the IDE's design packages loaded under a budget of their own (`RENDER-027`, `DSGN-187`); the file and line of what lives in another file of a form (render protocol 4); `delphi_config view` showing the version the build puts in the binary; a second, measured pass over the tool descriptions (1.26.0)

- The patch of 1.26: what a build reads because the project says so judged by one rule, the workspace or the IDE's library, never the IDE's per-user data folder; the build getting the variables the IDE gives its own build, and `add-searchpath` taking `$(Config)`; `set-version` refusing what it cannot rewrite (`CFG-146`); a Linux binary without the service's temporary folder (1.26.1)

- What the server starts and how long a client waits: every container run in one of a fixed set of slots, so a long session still starts them; no child given the server's configuration, and a program taken from a written path judged where it lives; the IDE's form reader asked only within the time a client waits (`DSGN-185`, `DSGN-188`, `EDIT-131`); `layout` judging what the renderer measured, FMX by the VCL's judge; the form renderers with the manifest the IDE gives an application (native FMX controls drawn) and a form's ancestor chain brought whole (render protocol 5); a deploy that says what another configuration ships (`BUILD-068`); window titles in UTF-8 on the desktop node, and KDE Plasma measured (1.27.0)

- The patch of 1.27: `delphi_styles set` saying `UNCHANGED` (`STYLE-069`) for a file it leaves as it was, without writing it or taking a backup, and how FMX's own writer stores the value (1.27.1)

- The close of the open list: `delphi_desktop` on KDE Plasma (the desktop portal's hands, KWin's overview, the scale measured where the desktop does not say it) and `drag`, which moves and resizes windows; creating a unit is `delphi_create`'s alone; `delphi_adb` and `delphi_desktop` announced only where the workspace declares somewhere for them to go, and the `instructions` opening with a map of the tools; a form the IDE's parser would stop reading never written by an edit (`DSGN-124`); a rename that asks each project's engine about a namesake; a long written block echoed head and tail; and what a review of the landscape of the whole source found failing, fixed (1.28.0)

- Databases and HTTP APIs by name (`delphi_db`, `delphi_api`): the operator defines them in two files of the server's own house and opens them per workspace; the agent asks for operations - tables, fields, rows, a summary, writes of at most `max` rows, tables and views where the operator allows them, a request to an API - and never sees a server, an address or a credential. And the designer: events bound by `set` (judged by the event's signature), several controls in one `insert` (`items`), `preview` at another display scale (`scale=`), the service's way of painting compared pixel by pixel with the desktop's on the 355 forms of the samples, `lint styles=`; `delphi_config save-as`; `delphi_create kind=project-library` and `autocreate=no`; the help of Delphi 13.2 read as 13.1's (1.29.0)

- A long call that tells its client it is still running (`notifications/progress`), and its answer kept in the agent's mailbox when the client gave up on it (`SYS-041`, also after a `notifications/cancelled`); the other calls told while a long operation writes (`SYS-042`, `SYS-043`, `SYS-044`); the row an insert wrote, from `delphi_db`; all of a program's output into a file (`delphi_paserver out=`); the server's DLLs only from its house and `System32`; one `access` key per database. And the close of the last list: the Job Object of foreign code capped in memory and CPU, sums and averages that SQL Server overflowed or truncated, the `settings.ini` keys nobody reads said at start, a control inserted in a form at another `PixelsPerInch` scaled as the IDE drops it, the trash copies a call made named in its answer, a local tag no remote has deleted by `delphi_git` (1.29.1)

- The protections that need a privilege, measured in the suite: the Python batteries plant symbolic links, and the unit tests run from a folder next to the repository's build output, where Windows does not refuse them (1.29)

## Next

For the server, nothing: 1.29.1 closed the last list, each item done, measured, declared or declined. The project is in maintenance: what follows are patches, and a declared item reopens only with a case from the field.

Beside it, for later: a model trained with the [Delphi fine-tuning dataset](../training-dataset-delphi/README.md) and measured before and after, on questions it never trained on (the dataset keeps a held-out set for that) - Delphi that compiles at the first attempt, invented APIs, twins written, and another language that must not drop. The dataset is being built as an extra, example by example; no model has been trained with it yet.

## Declared limits

- `delphi_designer insert` of a `TTabSheet` neither makes it the `ActivePage` nor gives it an `ImageIndex`, as the IDE's New Page does: at run time the first page shows (measured with `preview`)
- From a Windows service, `preview` paints control by control (`WM_PRINT`): some controls keep Windows' native look instead of the IDE designer's - an edit's border, the weight of a group box's caption -, never their size or place. Measured in a desktop session on the 355 forms of the samples, 257 identical pixel by pixel
- An SDK folder the IDE declares through `$(USERPROFILE)` in `BDSPLATFORMSDKSDIR`: not measured, no machine here has one
- Git LFS against GitHub (an upload, an `href` to another host, redirects): not measured, it needs a real LFS repository and the network to reach it

## Declined by the operator (do not re-propose)

- Interpreters: running arbitrary interpreters on the server (`delphi_run` itself was retired on 2026-09-23)
- `[URGENTE]`-style priority messages in the mailbox
- macOS as a target: not measured; the operator does not use it
- Non-visual components and collections through `delphi_designer insert` / `set` (events are bound by `set` since 1.29): they are written as text
- GetIt / package installation from the MCP
- GUI control of Linux from the MCP outside the PAServer node
- Several Delphi versions on one machine: one server serves one Delphi (`[Server] DelphiVersion`). To work with several versions, run one server per version - for example one virtual machine per Delphi, each with its own MCP server - and let the agent choose which one it talks to
- Several servers federated behind one endpoint: the same reason - each Delphi has its own server, and the agent chooses
- Stopping a call on its client's `notifications/cancelled`, and an asynchronous mode (a job id to ask for later): a call runs to its end, sends its progress meanwhile, and an answer its client gave up on goes to the agent's mailbox (`SYS-041`, 1.29.1); and a `POST /files` upload: files travel through `delphi_upload` and `delphi_fetch`
- LSIF as a references backend (measured feasible, see [DELPHILSP-NOTES.md](DELPHILSP-NOTES.md)): the references come from the DelphiLSP engine with each project's own settings
- A more restricted token (LPAC) for the resource compiler of `delphi_styles build`: measured on 2026-10-24 that it would not lift the styles-folder rule of 1.21.0 (`STYLE-052`), since `C:\Windows` and `Program Files` grant read to restricted application packages as well; the `.rc` it compiles is composed by the server from a whitelist
- Attaching a style to a StyleBook as the IDE does (an embedded style): styles are worked on as text `.style` files and built with `delphi_styles build`
- Watching a running application from inside (accessibility trees): what runs is seen through the captures of the desktop node and `delphi_adb`
- Renaming a unit as one operation: a move touches only what it names, and `delphi_config fix-references` re-points the projects
- Dead code by symbol as an operation of the server: no agent asked for one (measured in 1.28 over some 41,000 calls of the test agents), and the compiler's own hints already come through `delphi_diagnostics` and `delphi_build`
- `delphi_api` against an API that needs a login call first, and then the session token it returns on every request: the operator's credential is static, and the agent cannot make that login without the password travelling from it (declined at the close of 1.29.1: maintenance)
- The defaults a component's constructor sets, read from its source: `preview` draws them - it builds the real control -, `insert` writes the size the constructor gives as the IDE stores it, and `layout` judges the box the renderer measured; beyond `insert`/`set`/`delete`, the designer binds events (1.29)
- Remote debugging from the agent (breakpoints through the IDE's remote debugger): not on the list of any version, and a build plus `delphi_test` or `remote-run` with its output covers what the agents asked for
