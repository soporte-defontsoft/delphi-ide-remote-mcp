# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- `delphi_build` (and the build `delphi_test` runs first) lost a compiler message when its line
  passed 128 characters. dcc cuts the start of such a line - the file name and the line number -
  and msbuild then no longer recognises it as an error or a warning, so it reached neither
  `errors` nor `warnings`: an error in a unit with a long path came back as the `.dpr`'s
  `F2063 Could not compile used unit` alone, a missing unit as `MSB6006 "dcc" exited with code 1`
  alone, with no `missingUnits`, and a warning or a hint not at all. The build now also reads
  the messages msbuild could not classify (a third file log, `minimal`, which keeps them with
  any `verbosity`) and puts each where its code says - `E`/`F` first in `errors`, ahead of the
  `F2063` or `MSB6006` it caused (so `firstError` is the cause), `W` in `warnings`, `H` in
  `hints` - as dcc printed them, and `cutMessagesNote` (`BUILD-074`) says the file name and the
  line number were cut. `missingUnits` finds the unit of a cut `F2613`, and the retry on an
  `F2039` (the `.exe` in use) reads them too. Measured on 12 and 13 November with the broken
  examples of the fine-tuning dataset, whose paths are long; with a short path nothing changes.

## [1.29.1] - 2026-11-11

A patch of the closing line. A long call keeps its client informed and what it did is not
lost: it sends `notifications/progress` while it runs, and an answer its client did not get -
it hung up or said it gave up - goes to that agent's mailbox (`SYS-041`), over HTTP and
stdio. While a long operation writes, the other calls say so instead of answering that a
folder does not exist (`SYS-042`, `SYS-043`, `SYS-044`). `delphi_db insert` returns the row
the database wrote, and `delphi_paserver remote-run` and `output` keep all of a program's
output in a file (`out=`). The server loads its DLLs only from its own folder and
`System32`, never from the `PATH`. For operators: the database connections file takes one
key, `access`, instead of `readonly` and `allowCreate`, and PostgreSQL's DLLs need the
Visual C++ runtime in `System32`. And it closes the project's last list: foreign code runs in
a Job Object capped in memory and CPU, `delphi_desktop` gets a double click and types what
the desktop composes, `delphi_db summary` adds and averages integers on SQL Server without
overflowing or truncating, an insert in a form at another `PixelsPerInch` is scaled as the
IDE drops it, the start says which `settings.ini` keys nobody reads, and `delphi_git`
deletes a local tag no remote has. After it, the project is in maintenance: patches only.

### Added

- `delphi_git command=tag action=delete name=<tag>` deletes a LOCAL tag that no remote has:
  `ls-remote` asks every remote of the repository first, through the same gate as an
  agent's own `ls-remote`. A tag a remote has is refused (`GIT-094`, naming the remote):
  deleted here it would come back with the next fetch, and this tool never deletes on a
  remote (push only adds). A remote that does not answer refuses it too (`GIT-095`): it
  cannot be known. The answer says which remotes were asked and how to put the tag back
  (`GIT-096`: `command=tag name=<tag> ref=<the id git printed>`). Until now a mistaken
  local tag needed a console - the release of this version had to do it that way.
- A call still running tells its client so: every `[Server] ProgressSeconds` (15 by default;
  0 = none) it sends a `notifications/progress` with the `progressToken` the client sent,
  the seconds it has been running and `SYS-040` naming the tool. Measured: Claude Code (the
  app and the CLI) gave up on a call after 300 s with no news and opencode after 60, and a
  progress notification starts their count again; until now the server sent none, so a
  long copy, delete or build was taken for lost although it finished, and an agent ran it
  again on top. One heartbeat for every tool and both transports (`Lsp.Progreso`): by
  stdio it is one more line; over HTTP, to a client that accepts `text/event-stream`, the
  first one opens the answer as a stream sent in chunks and the answer comes as its last
  event. A call that ends before the first one is answered byte for byte as before. The
  log line of a request without a session now carries its `Accept` header.
- The answer of a call whose client stopped waiting for it is not lost: when a heartbeat or
  the answer itself cannot be written (the client left), or when the client says it gave up
  (`notifications/cancelled` with the call's id, from the same workspace and session -
  and, without a session, from the same agent when the cancel says who it is: two agents
  of one token number their ids each; over stdio too, whose input is now read by a thread
  of its own, so a cancel is seen while the call still runs - it was read after it), the server
  finishes the call and leaves its answer in that agent's mailbox, once (`SYS-041`, read
  with `delphi_messages`), and
  every answer of the agent says mail is waiting until it reads it - so it does not run
  again, blind, what was already done (measured on 7-nov: a `remote-run` cut by its client
  ran twice on the target). The cancel is what Hermes sends: measured on 9-nov, its client
  cuts a call at 300 s, says so and keeps the connection open, so the heartbeat still got
  through and in its three test rounds the answer of a cut call never reached its mailbox;
  with this build, in three more rounds on 10-nov, all three reached it. An answer left in
  the mailbox goes without the "mail is waiting" note it carried when the call ended: it is
  read with the rest, and a cut answer read that night still said "PENDING MESSAGES: 1"
  about the one delivered with it. Writing a new document in the server's house without
  overwriting one is now one helper (`EscribeDocumentoNuevo`), used by `delphi_report` too,
  and a message whose text is still being written is not delivered empty. The mailbox is
  the one of the name the client gave at the handshake (`agent` in `delphi_workspace`), so
  the "mail is waiting" line now names the call that reads it (`delphi_messages
  command=read agent=<name>`), and `delphi_messages` reading any other mailbox carries
  that line too: an agent that passes its own `agent=`, as Hermes did in its full test of
  1.29.1, read another mailbox and got "No messages" while its answer waited (measured
  with a probe).
- A long operation that writes (`delphi_move`, `delphi_delete`, `delphi_build`,
  `delphi_package`, `delphi_test`, `delphi_git`, `delphi_paserver`) tells the other calls
  while it runs. Measured on 7-nov: while a `delphi_move` copy still ran, `delphi_list` of
  its destination said `WS-008` "does not exist" and repeating a delete already done said
  `SYS-012`, and the agent ran them again on top. Now the same call (the same named agent,
  the same arguments) is refused while it runs (`SYS-042`: its answer goes to the call that
  started it, or to that agent's mailbox if its client hung up; clients without a name are
  not "the same agent", and theirs is judged as any other write there); a call that writes
  where it is working is refused (`SYS-043`, which operation and since when; before, a
  `delphi_config set-version` rewrote a `.dproj` in the middle of its build) - a
  `delphi_changeset commit` too, whose paths go in its staged operations and not in its
  arguments -, except a build or a test over another build or test of another agent, which
  wait their turn as before (one msbuild at a time, each test in its own container); and one
  that reads there answers as always, with a note that what it shows may be half done
  (`SYS-044`, an `inProgressNote` field when the answer is JSON; a refusal does not carry
  it). One registry for the
  process (`Lsp.EnCurso`), filled at the
  gate with the paths the gate already reads and emptied when each call ends, whatever
  happens to it. A short write (an edit) is not registered: it queues on the write lock as
  before.
- `delphi_db insert` returns the new row as the database left it (`row`): the key it gave
  it (an identity or a `serial`), its defaults and what a trigger wrote in that row, in
  SQL Server and PostgreSQL - the agent no longer has to look for the row it just wrote.
  It goes through a FireDAC dataset that re-reads the whole row after posting (as ADO's
  resync does), names exactly the fields given (a `null` writes NULL, not the default)
  and leaves the rest to the database. A table without a primary key leaves FireDAC no way
  to find the row again: it is written as before and not read back, and the answer says so
  (`rowNote`, `DB-031`) - re-reading it there made SQL Server refuse an insert that left a
  field to its default. On 8-nov this path had been taken out because a
  call stayed hung when the network went silent; measured on 9-nov, that was the test
  harness, not FireDAC: its proxy did not pass on the database closing the cancel
  connection, which libpq waits for. With the harness fixed, a silent network is answered
  in time and the server still exits clean, and an insert waiting on a row another
  session holds is cancelled by its timeout and answered.
- `delphi_paserver` `remote-run` and `output` take `out=`, a `.txt`/`.log` file of the
  workspace that receives ALL the program wrote, with its own bytes and without the
  launcher's two lines (`RUN-028`); the answer names it, with its lines and size, instead
  of carrying the last 400 lines. Reported by Hermes on 9-nov: its measuring tool writes
  its verdict at the head of ~412 lines, the tail lost it, and a read output is deleted
  from the target, so there was no way back. A program still running when `remote-run`
  returns writes nothing yet (`RUN-030`); `output` with `out=` writes what it has so far
  (`RUN-029`) and, once it ended, all of it. If the file cannot be written, the output
  stays on the target (`RUN-032`). `RUN-023` says how to keep all of it, and counts the
  program's bytes, the same as the file's `size` (it counted the launcher's two lines too:
  Hermes saw 12527 against 12508 for one output, 10-nov). A `remote-run` whose program
  ended says so (`stillRunning: false`), as `output` did: it was there only while it ran,
  and an `exitCode` with `durationMs` equal to the timeout did not say who ended it. The check that
  such a file ends in `.txt`/`.log` is now one, shared with `delphi_adb logcat out=`.
- The answer of a call that changed or replaced files names the copies it left in the trash
  for them (`SYS-045`, the path of each copy: `delphi_move` brings one back). About 25
  answers said "Backup in `__delphi-patch`." without the file - a project setting, a unit
  added to a `.dpr`, a style, the summary of a changeset; one note for all of them, only
  for a copy the call made (the first change of the day), not for one that already existed
  nor for one the answer already names (its `backup`, also inside a JSON answer).
- At start, the server says which sections and keys of `settings.ini` it does not read: a
  misspelled name, or one this version does not have, did nothing and nothing said so. The
  reader itself is the catalogue - what the server asks is noted, and what the file holds
  and nobody asked is said - so a key added tomorrow needs no list. Measured: the
  `settings.ini` of the machine this server is built on still had
  `[Server] MessagesRetentionDays`, gone in 1.3. A misspelled workspace section keeps its
  own warning, which says how it is written.
- `delphi_desktop command=double-tap`: the double click, at `x`,`y` like `tap`. Two `tap`
  calls never made one - each is a run of the node, a second or two apart, and a desktop
  takes two presses as a double click only within its interval (400 ms in GNOME) - so a
  row that opens on a double click could not be opened: Hermes spent some 30 calls on a
  grid in three days and asked its operator to try it on a tablet. The node presses twice
  at the same point (libei on Linux; on Windows one `SendInput` with both, judged by the
  system's double-click time). Measured on Fedora 44 with GNOME: a word double-clicked in
  the text editor is selected, and one `tap` there only moves the cursor. A gesture like
  the others: a host the workspace only lets see refuses it.

### Changed

- **Operators: the database connections file changes.** What an agent may do in each
  database is now ONE key, `"access"`: `"read"` (only reads), `"write"` (also inserts,
  updates and deletes) or `"create"` (also creates tables and views). In 1.29.0 it was two
  yes/no keys, `readonly` and `allowCreate`, with a combination that made no sense
  (`readonly: true` with `allowCreate: true`). An entry that still has either of them, or
  no `access`, is not used, and `delphi_db connections` lists it under `unusable` saying
  why: change `"readonly": true` to `"access": "read"`, `"readonly": false` to
  `"access": "write"`, and `"readonly": false` with `"allowCreate": true` to
  `"access": "create"`. `connections` shows each database's `access` instead of the two
  keys; the example in the zip and `docs/CONFIGURATION.md` use the new key.

### Security

- The DLLs the server loads come from its own folder, `System32` and the folders it adds -
  never from the `PATH`. With `libpq.dll` alone in `drivers\PG\lib\`, the five DLLs it
  loads were taken from the folders of the `PATH` (measured: the OpenSSL of Git for Windows
  and a `pgsql\bin`), code nobody put in the server's house running with the service's
  account; FireDAC sets its folder with `SetDllDirectory` and Windows looked for the rest
  in the `PATH` too. The server now calls `SetDefaultDllDirectories` when it starts.
  Measured before changing it: everything the process loaded (FireDAC with PostgreSQL and
  SQL Server, the help through COM, the XML of a `.dproj`) already came from those three
  places. It is not inherited: msbuild, the compiler, the engine and the form renderers
  (which load the IDE's packages through their `PATH`) are as they were. An operator who
  serves HTTPS (`[SSL] Enabled`) with OpenSSL libraries found in the `PATH` puts them next to
  the server's exe. On updating, PostgreSQL in `delphi_db` answers `DB-030` until
  `drivers\PG\lib\` holds the five companions of `libpq.dll` (if only `libpq.dll` was there)
  and the Visual C++ runtime they need is in `System32` (its redistributable), if it was
  found only in the `PATH`.
- The Job Object that confines foreign code - a `delphi_test` run, a form render, the
  `brcc32` of a style `.rc` - caps the memory of all its processes together at a quarter
  of the machine's RAM (never more than the 3 GB a process already had) and its CPU at
  every logical processor but one (a hard cap). Until now only each process had a cap
  (3 GB, and 128 processes), so a test could take the machine - the IDE's, the server's
  and the other agents' - for up to its timeout. Measured before choosing them: the
  server's own unit suite peaks at 32 MB and a render with 110 packages at 170 MB, on a
  machine of 8 GB and 4 processors (2047 MB and 75 %). What a test asks for past the cap
  Windows refuses; Windows says so through the job, and `delphi_test` tells why the test
  saw an out-of-memory error (`memoryCapNote`, `TEST-039`). Its description names the cap
  next to the timeout, so a test can be written for it.

### Fixed

- `delphi_desktop` answered `"ran": false` and nothing else when the node on the target
  ended with an error code or was still running at the end of its 60 s, even with the
  capture taken and in the answer: the agent could not tell a failed node from a slow one,
  or know whether the capture was good. It now says which: `exitCode` and `DESK-028`, or
  `stillRunning` and `DESK-029`, and the capture stays. Found by Hermes's directed test of
  this version, right after the Fedora target restarted.
- The DUnitX runner of `delphi_create kind=project-test` ran only the fixtures registered
  with `TDUnitX.RegisterTestFixture`: a `[TestFixture]` class without that line never ran,
  and the run said `pass` with one test less. It now finds them by RTTI, as the runner of the
  IDE's DUnitX wizard does (`{$STRONGLINKTYPES ON}` and `UseRTTI`; measured on a project
  created in the IDE: 2 tests there, 1 here). A registered one is not counted twice. The
  rest of the wizard's runner stays out: on an exception its exit code is 0, and its NUnit
  XML file would come back in `files` on every run.
- `delphi_db summary` on SQL Server: the sum of an integer column past 2^31-1 refused the
  whole query (`DB-010`, arithmetic overflow) and the average of integers came truncated
  (1 and 2 gave 1, where PostgreSQL gives 1.5): SQL Server adds and averages an `int` as an
  `int`. An integer column is now added as `BIGINT` and averaged as `FLOAT` through
  FireDAC's `CONVERT` escape, which writes each engine's form, and the counts use
  `COUNT_BIG` there (`COUNT` is an `int` too). Measured on both engines with the same
  rows: 4000000000 and 1.5.
- `delphi_designer insert` in a `.dfm` saved at another `PixelsPerInch` than 96 wrote the
  size its constructor gives at 96 (a button 75x25 in a form at 120, where the IDE had saved
  its buttons at 94x31 and their margins at 4): loaded on a screen at 96, the new one came
  out smaller than its neighbours. The IDE scales a control it drops to the designer's PPI
  (`TControl.SetParent`); the form's own file says that PPI here, and the VCL scales it
  (`ChangeScale`, in the renderer, before it writes): 94x31 and margins 4, still at 10,10. A
  `.fmx` has no `PixelsPerInch`; what the agent gives in the insert (`props: Width=200`) is in
  the file's units and stays as given; a `set` or `set parent=` of a control already there is
  not scaled again.
- `delphi_desktop type` on a Linux desktop composes a character the way that desktop
  does, asking its compose table (libxkbcommon's, for the session's locale) what each dead
  key gives with a space and with every other key. On a Spanish keyboard "^" and "`" exist
  only as a dead key and a space, and `type` refused them (`NODE-009`, Hermes on 9-nov);
  and the table, not Unicode, says what comes out: measured on Fedora with GNOME, a dead
  key and a space give "^" and "`" with the circumflex and the grave, but "'" and "\""
  with the acute and the diaeresis. `a^b`c` and the accented letters are typed as a person
  types them there (measured). Where the table cannot be read, the node composes from
  Unicode as before.
- `x`, `y`, `tox`, `toy` of `delphi_desktop` and `x`, `y`, `lines` of `delphi_adb` are
  integers from 0 in the schema: a client that checks the arguments against it refused `152`
  ("is not of type 'string'", nine times in Hermes' sessions). Text still works.
- A vault declared but unreachable (a network folder that does not answer) said
  "no vault configured": it now says it is declared and cannot be reached (`VAULT-043`),
  and `prompts/list` no longer asks the disk on every request for it (the first look at a
  server that does not answer took 21 s, measured). One unreachable when the server
  started had no vault tools, prompt or instructions until a restart, so `VAULT-043`
  never came: they now go by what is declared, as the rest of what the server announces.
- `delphi_paserver remote-run` and `output` took a program that writes a line tagged like
  one of this server's refusals (`[NODE-015 DENIED] ...`, the desktop node run by hand)
  and exits with an error for the launcher refusing to run it: the answer came as a
  failure with that line as its `error`, and `out=` was not written. Only the launcher's
  own refusals (`JOB-`) are taken as its now.
- Small texts an agent met, each where it happens: the preview of a `delphi_changeset`
  create writes the line ending as the files say it (`LF`, `CRLF`); `delphi_designer` reading a
  binary `.dfm` no longer calls its tree the TEXT designer's (`DSGN-019`);
  `delphi_config view` says what remote targets need only for a project that has one
  (`CFG-073`); `LIST-003` names the build folders it left out; and `delphi_styles lint`
  and `build` say when there are `.style` files in subfolders, which they do not walk
  (`STYLE-070`).

- `delphi_db` without its engine's client library said `DB-009` with FireDAC's text and its
  hint "check it is in the PATH or application EXE directories", which does not apply here;
  it is now `DB-030`, told apart by FireDAC's error code and not its text, and it names the
  file FireDAC looked for next to the server (`drivers\PG\lib\libpq.dll`), where it goes
  with the DLLs it loads, 64-bit; that the server takes them from there, its own folder and
  `System32`, so a runtime Windows does not bring goes in `System32` with its installer; and
  that the next call tries again, without a restart. Measured on a new Windows with the six
  in place and no Visual C++ runtime: `DB-030`, and with the redistributable installed the
  next call opened (the first text said "nowhere else", which sent the operator to copy the
  runtime into that folder).
- Docs: what an operator puts next to the server for `delphi_db`, which the zip does not
  carry. `docs/CONFIGURATION.md` named only `drivers\PG\lib\libpq.dll` "with the DLLs it
  depends on" and `QUICKSTART.md` nothing; both now name the five (`libssl-3-x64`, `libcrypto-3-x64`,
  `libintl-9`, `libiconv-2`, `libwinpthread-1` with the 18.3 x64 build), say all six are
  64-bit, where to take them from and that all six are needed, plus Microsoft's Visual C++
  runtime they import (`VCRUNTIME140.dll`), which Windows does not bring. For SQL Server, the order
  in which FireDAC picks the system's ODBC driver (ODBC Driver 18, 17, Native Client
  11.0...; measured here: Native Client 11.0).
- Small things an agent met in the 1.29 test rounds, each said where it happens:
  `delphi_move` and copy create the missing folders of `dest` and now say so (`MOVE-027`);
  `delphi_adb discover` and `devices` gave adb's lines with its column tab inside the text,
  now two blanks as a console shows them; `delphi_git config` read a value without saying
  whether it was the repository's or the server account's, and now says it as git does
  (`--show-scope`, `GIT-088`), and a value set says it went to this repository's config
  (`GIT-089`); `delphi_report` without a title says its name is only date, time and kind
  (`REPORT-015`); `delphi_workspace` says the agent's name, its folder in
  `delphi_messages` and `delphi_report` (`agent`); `delphi_signature` says the position is
  the index of the `(` or `,` plus one (measured: on the `(` itself the engine has none);
  `delphi_test discover` with a file searches the folder that holds it and, finding no test
  project there, now says which folder that was (`TEST-038`); and the preview of a
  `delphi_changeset` create says the line ending it will write (`eol`).
- `delphi_desktop` on KDE Plasma (Wayland): the rectangle of a window in `windows`, and
  the crop of `screenshot window=`, left out its title bar (35 px short at the top,
  measured on Fedora 45). KWin draws that bar outside the X11 window and declares it in
  `_NET_FRAME_EXTENTS`, which the node now adds; on GNOME, where an FMX window draws its
  own frame, nothing changes (both measured with an FMX application).
- `delphi_db create-table` refuses a decimal column (`dtFmtBCD`, `dtBCD`) without its
  `precision` and `scale` (`DB-014`, which says why and gives 18 and 2 as an example).
  Without them FireDAC writes `DECIMAL(64)`: PostgreSQL created it with scale 0 and stored
  12.34 as 12 without a word, and SQL Server refused it (its maximum is 38); with only the
  precision both made a column with no decimals, and with only the scale SQL Server refused
  it again (measured on both engines; found by Hermes' full test of 1.29.1).
- `delphi_textedit` gives the path of the copy it keeps of a file before its first change
  of the day (`backup=`), as `delphi_edit` does, and says on the next changes that it
  already existed; it said "backup in `__delphi-patch\`", without the file or the day
  (Hermes' full test of 1.29.1).

## [1.29.0] - 2026-11-09

A minor version that closes the project's list: what follows are patches. Two new tools give
an agent the databases and the HTTP APIs the operator defines, by name and through
operations: `delphi_db` reads, sums up and writes (at most `max` rows at a time) without ever
writing SQL, and creates tables and views where the operator allows it; `delphi_api` sends
requests to an API, and the server keeps its address and credential. The agent never sees a
server, an address or a credential; the operator writes them in two files of the server's
own house (examples in the zip, `connections\`) and opens them per workspace with the new
keys `DbAllowedProjects` and `ApiAllowedProjects`. The designer binds events (`set
OnClick=<method>`, judged by the event's signature), inserts several controls in one write,
draws a form at another display scale and an MDI child, and judges a form's style names
against a `.style`; `delphi_config save-as` copies a project under another name as the IDE's Save As does, and
`delphi_create` makes a DLL as the IDE does. An edit that would leave a unit without its
final `end.`, or rewrite a file through one block anchor, is refused before writing, and the
help of Delphi 13.2 reads as 13.1's. Pending tests: an API that needs a login call first.
Deploy the server with its two form renderers (protocol 14) and the style converter
(protocol 2). Validated before the release through Hermes on a second machine by Qwen3.8
Flash Next (a directed test of what changed, a full test of every tool, and three rounds of
what those found); the databases and APIs were measured here against SQL Server, PostgreSQL
and a real API.

### Added

- `delphi_db`: the databases the operator gives a workspace, used by NAME and through operations - the agent never writes SQL. The operator defines them in the server's connections file (`connections\databases\db-connections.json`, next to `settings.ini` and outside every root: projects, each with its databases - server, database, user, password, port, engine, readonly) and opens projects to a workspace with `DbAllowedProjects=` in its section of `settings.ini` (`*` = all); without one, `delphi_db` is not in `tools/list` and a call answers `DB-002`. `command=connections` lists the databases of the workspace as `project/alias` - the name every command takes - with their engine (the FireDAC driver) and whether they are read-only; the ones declared wrong come under `unusable` with why (`DB-001`, `DB-005`). The agent never sees the server, the real database or the credentials. `command=tables` and `fields` say what a database holds (its tables and views in the connection's schema; each field with the database's own type, length, precision, nullability and key); `rows` reads a table - `filters` as a list of `{field, op, value}` with a closed set of ops (equals, not_equals, greater, less, greater_or_equal, less_or_equal, contains, starts_with, words, empty), `fields`, `order`, `limit`/`offset`, and always the `total` with the same filters - and `summary` groups (also by a date's year, month, day or hour) and adds up (`sum`, `avg`, `min`, `max`, `count`, and `n` per group). The server composes the SQL once for every engine and FireDAC turns it into each dialect: names come from the database's catalog and are quoted by FireDAC, every value travels as a parameter typed by its field (PostgreSQL does not compare an integer with a text), and text compares as the database's collation does. Reads run in a transaction that is always rolled back; a database that does not answer is given up after 12 seconds (`DB-007`: SQL Server took 42 with its own login timeout of 5), and one that opens and then goes silent in the middle of a call after 65 (`DB-022`; nothing that call does afterwards is committed): FireDAC's own connection orders - BEGIN, COMMIT, ROLLBACK, the preparing of a command - carry no command timeout, the cancel of one that does comes back through the same silent connection, and the call did not come back in 240 seconds (measured with a proxy that goes silent); with such a call still waiting on PostgreSQL the server now stops at once (it closes that connection's socket, the only thing measured to wake libpq: it hung, or ended with an access violation), while one waiting on SQL Server keeps it from stopping on its own, as before (its ODBC driver gives no way to wake the call; the service manager ends it), a refused login is `DB-008`, and whatever the database says comes back with the operator's server, user, port, password and real database name masked. A PostgreSQL connection never reads the server account's `pgpass` file: it connected without a password through it (measured). `insert`, `update` and `delete` write, only where the connections file says `"readonly": false` (on a read-only database they are refused before connecting, `DB-017`, and a read-only credential cannot ask for them): `values` is a list of `{field, value}` (`null` writes NULL; a binary field takes only `null`), `update` and `delete` change only the rows their `filters` select and never run without filters - an empty list included (`DB-011`) -, each runs in a transaction committed only when the database accepts it, and the answer says how many rows it touched (`affected`); no DDL, no procedures. A date without a zone is the one written: it is never moved to the server's time zone. The engines are the FireDAC drivers the server links (MSSQL and PostgreSQL); a driver that needs a client library loads it from `drivers\<DriverID>\` of the server, never from anywhere else. The budget of `tools/list` rises to 110,000 characters for the new tools.

- `delphi_api`: the HTTP APIs the operator gives a workspace, used by NAME - a generic mini Postman. The operator defines them in the server's API connections file (`connections\apis\api-connections.json`, outside every root): per project, each API with its `baseUrl`, its credential (`auth`: `basic`, `bearer`, a key in a `header` or in the `query`, or a list of them), fixed `headers`, an optional certificate `pin` (`sha256/<base64 of the SHA-256 of its SubjectPublicKeyInfo>`), the `methods` it allows (an entry without them is not used) and a `timeout`; `ApiAllowedProjects=` opens projects to a workspace, and without one `delphi_api` is not in `tools/list` (`API-002`). `command=connections` lists them as `project/alias` with their methods; `command=request` sends a method, a path RELATIVE to the API (no host, no `..` even encoded, no `?`), `query`, the agent's own `headers` and a `body` (JSON goes as `application/json`) or a `form`, and answers with the status, the headers, the time and the body (JSON as JSON; a binary or very long body is saved whole with `out=`). The base address, the credential and the pin never travel from the agent and are hidden in what comes back (an API that echoes the credential shows `<project/alias>`). Redirects are returned, never followed; the service's Windows account is never offered (the RTL offers it by default); headers that the operator, the credential or the transport set cannot be overridden, nor can a header carry a line break. With a pin, only the server holding that key is spoken to, checked on the very connection that carries the request before anything is sent (a mismatch sends nothing, `API-014`, measured); without one, Windows judges the certificate, and one it does not trust is refused with the pin it presented, for the operator to pin (`API-013`). To a read-only credential, `request` answers only with GET, HEAD or OPTIONS and without `out=`. Pending tests: an API that needs a login call first, and then the session token it returns on every request, cannot be used yet - the operator's credential is static, and the agent cannot make that login without the password travelling from it (measured against a real API: every call answered 403 without the session token).

- `delphi_designer preview scale=`: the form as an application shows it on a display at that Windows scale, in percent (125, 150, 200...; 100 to 500), whatever the scale of the server's own display. Each framework does it its own way: the VCL scales the form as it does when a form moves to a display of another DPI (`ScaleForPPI`, from the PixelsPerInch the form was saved at; a form with `Scaled = False` is drawn at its own size and the answer says so, `RENDER-031`), before showing it, as an application that scales its forms does; FMX draws with the window's scale forced to it, so the style picks its bitmaps for that scale (stretching the image instead blurred them, and a scaled layout left seams in nine-patch bitmaps; measured). `componentRect` and `frame` stay in form units, so what an agent measures on the bigger image still goes into the file. In the VCL, the parts Windows paints natively (the square of a check box, the arrow of a combo box) stay at their 100% size: the renderer does not follow the machine's DPI, and the answer's `scaleNote` says so (`DSGN-191`). A scale outside the range is `DSGN-190`.

- `delphi_designer lint styles=<a .style, or a folder of them>`: the form's `StyleLookup` values are judged against those styles and the platform's default one even when the form takes its styles from a StyleBook the lint does not read, or is a frame (it takes the hosting form's): until now they were only counted as not judged (`DSGN-178`), and `delphi_styles lint` set such a form apart, so a misspelt name - which FMX draws with the class's own style, with no error - had no judge (an agent's report: 167 in one frame). The ones neither defines come under `DSGN-192`; a `.style` whose lines the IDE's parser would read differently does not count and is named (`DSGN-194`); a path that gives no style, or a VCL form, is `DSGN-193`.

- `delphi_db command=create-table` and `command=create-view`, only where the connections file gives that database `"allowCreate": true` (and `readonly: false`; an `allowCreate` that is not true or false makes the entry unusable). create-table takes `columns=[{name, type, size, precision, scale, required, key, autoinc}]`, the type as FireDAC names it (`dtInt32`, `dtWideString`, `dtFmtBCD`...), and the SQL is what FireDAC's own generator writes for that engine - an identity column, `NVARCHAR(MAX)` or `TEXT`, a quoted reserved word - run in one transaction and returned in the answer; a type the engine does not have is refused by FireDAC (`-353`), never skipped (FireDAC's `TFDTable.CreateTable` skips it silently). create-view is `CREATE VIEW` over the chosen `fields` of one table, with no filters: a view's `WHERE` would carry its values as literals, and FireDAC's literal macros leave the SQL unterminated when a value holds a quote (measured on SQL Server and PostgreSQL). Nothing is ever dropped or altered: an existing name is `DB-024`; a name that is not an identifier, `DB-025`; no permission, `DB-023`. New names follow the generator's rule (PostgreSQL folds them to lower case, as unquoted names).

- `delphi_designer insert items=[{classname, component, parent, props}, ...]`: several inserts in ONE write, all or nothing - each exactly as a single insert puts it (its properties as the IDE's writer stores them, its place among its siblings, its published field and its units), applied on what the one before left, so a parent may be an earlier entry. A refused entry refuses them all and says which (`DSGN-196`); a malformed list is `DSGN-195`, and `items` with the single-insert parameters is `DSGN-198`. The limit of one call is the client's wait (`DSGN-185`, which now says how many fitted): about 2.5 s per control measured on this server. An agent rebuilding a screen of about 150 controls wrote the form and the class fields by hand, without the IDE's writer (its report).

- `delphi_designer set` binds an event to its handler: `prop=OnClick value=Button1Click` writes the line as the IDE does (the name, unquoted) when the method is the one the form loader will find - the first published method of that name in the form's class and its ancestors of the unit, not a class method - and has the shape of the event's signature: procedure or function, how many parameters, the mode of each (`var`, `const`, `out`), an open array, a result. The names of the types are not judged: whether two are the same type is the compiler's to say, and the IDE writes `Char` where FMX's `TKeyEvent` declares `WideChar` (the 12 `OnKeyDown` handlers of the samples). The signature comes from the source of the event's type, in the designer's tables (generation 20; an event type is now known by its unit too, as an enumeration: the FMX table also reads VCL editors, and the two `TKeyEvent` were one with two signatures). `value=nil` removes the line. Otherwise `DSGN-088` says why - not declared, not published, a class method, another signature (both shown), or the class goes on in a unit the server cannot see - and how to create it (`delphi_edit insert=metodo visibility=published`). Until now `set` refused every event and the agent wrote the line by hand. `prop` of an event gives its handler's `signature`. `check-binding` judges with the same rule and lists a handler of another shape, or a class method, under `eventsWithOtherSignature` (it compiles and loads, and the event calls the method with other parameters); `lint` and the warnings after a write say it too. Measured on the 669 forms of the IDE's samples (about 4,000 event lines): every list `check-binding` already had comes out the same, and none has another signature.

- `delphi_create kind=project-library`: a DLL as the IDE creates one (File > New > Dynamic-link Library, measured on a project the IDE had just created): a `.dpr` that starts with `library`, with `System.SysUtils` and `System.Classes`, its resource and an empty block, and a `.dproj` with `AppType=Library` and `GenDll` in the base, without the manifest, icon or DPI awareness of an application; Win32 and Win64 active, as the other kinds. An agent started from a console project and changed the header, and the project stayed without `GenDll`: the compiler wrote the DLL with an executable's name (`BUILD-072` says so since this version).

### Changed

- `delphi_config command=save-as name=X`: the IDE's Save Project As, as measured on three copies saved in the IDE. It COPIES: `X.dpr` (or `.dpk`) is the old main source with `program X;`, and `X.dproj` is the old project with its main source, its names (`ProjectName`, `SanitizedProjectName`, the `MainSource` of its extensions) and the binary of each deployed output (its local and remote name, as the compiler names it), both beside the old ones, which stay - deleting them is up to the operator. The `.res` comes with the first build and the `.deployproj` is not copied: its remote folder carries the old name. The units are not copied either - both projects list the same `.pas` files, as after the IDE's Save As - and the answer says so. Nothing is overwritten, and the name is judged as `delphi_create` judges a project's. An agent had no way to rename a project: `MainSource` is structure (`CFG-132`, which now points here) and `delphi_textedit` does not write a `.dproj`.
- `delphi_desktop type` presses Enter for each line break in `text` (LF, CRLF or a lone CR: one press each), on Windows and on Linux: the Enter key, as a person presses it - not a character, so a dialog's default button and a key handler see it - and on Linux the same key whatever the keyboard layout. In 1.28 a line break was refused with `DESK-027`, which now refuses only a NUL character (it does not travel to the target). What the node echoes it typed shows each line break as `\n`, on one line. Measured on Fedora 44 with KDE Plasma (a Spanish layout: three lines in a new document) and on Windows 11 (the Enter of a typed line launched the search result, which a character 13 does not do).
- `delphi_build deviceid` must be one of the devices the workspace allows (`AdbAllowedDevices`, the list `delphi_adb` already uses): it reached msbuild's line (`/p:DeviceId=`) as free text with only its characters judged. Outside the list it is refused with `ADB-005` before anything runs.
- `delphi_create` of a form or a data module and `delphi_config add-unit` take `autocreate=no`: the unit is registered (uses of the `.dpr`, the `.dproj`) without its `Application.CreateForm`, as the IDE's "Available forms", for a project whose code creates it on demand (an agent's report: with both ways it was created twice, `EComponentError`). On `add-unit`, a `CreateForm` the unit already had goes. The answer says it went without one (`CFG-155`). Default `yes`, as the IDE does; a value that is not a yes or a no is `CREATE-041`.
- The notes that come with every deploy, remote run and desktop capture are shorter (`BUILD-006`, `RUN-017`, `RUN-019`, `RUN-003`, `RUN-004`, `DESK-007`): the same instructions in about half the text, about 1,200 characters less per deploy-run-look cycle, which an agent iterating on a screen repeats dozens of times (an agent's report).
- `delphi_db rows` pages in a TOTAL order: the `order` asked for and then the primary key (without `order`, the key alone), so the next page neither repeats nor skips a row - without `ORDER BY` no engine promises the same order twice (measured on PostgreSQL: an updated row moved to the end, and `offset=2` gave rows 4 and 5 instead of 3 and 4). SQL Server now pages in the engine too: without `ORDER BY`, FireDAC asked for `TOP offset+limit` and dropped the first rows itself (read in its SQL generator). A table without a primary key says so (`DB-021`). `rows` and `summary` answer their page as every list of the server does - `total`, `shown`, `offset`, `hasMore` and `nextOffset`, and a note when `limit` asks for more than the cap (500), which was lowered in silence - and `summary` counts its groups in the database; it takes `offset` and orders its groups by their fields after the value it ranks by. `fields` also lists the table's foreign keys (with the table and fields they point to) and its indexes (primary, unique), from the database's catalog. A text longer than a third of an answer comes cut as `{"text", "length", "truncated"}`: the first row of a page always goes, and a 1 MB memo went whole.
- The two form renderers speak protocol 14: the values their arguments and answers share with the server (form or frame, the fidelity, the style, the packages, text or binary, the separators of the non-visual list) are named once in the protocol, on the wire the same, and they take the scale of a preview and say how many pixels of the image make a unit of the file (`--scale`, `SCALE=`). The suffix of the installation's packages, which an FMX platform style is read from (`fmxdesigner370.bpl`), is the one the server measures in the IDE's `bin` (`--bplsuffix`): the renderer deduced it from the BDS number, which matches only from Delphi 13 - Delphi 12 is BDS 23.0 and its packages are 290. Deploy them with the server, as always: a renderer of an older protocol is refused by name. The style converter speaks protocol 2: what FMX ignores of a style travels in its parts (the object's class, the property, the reason), split by the converter with the format of its own RTL, as the renderers do; deploy it with the server too.
- `delphi_designer layout` of a VCL form lists hidden controls (`Visible = False`) in `boxes`, and every box carries `visible`, as an FMX form's already did: the VCL left them out, so an agent placing a control did not know a hidden panel was in that spot. Measured or worked out from the text, a hidden control still takes no band and is not judged (it does not overlap, it has no size of zero); without the renderer its rectangle is the one the `.dfm` writes. What is inside a hidden container comes too, each with its own `Visible`, as the renderer gives it, and is not judged at any depth (with the renderer only the hidden control and its children were exempt: a grandchild of a hidden panel was judged, and not from the text). `preview` draws a hidden control, as the VCL designer shows it.
- `delphi_designer lint` and `delphi_styles lint` name, next to a `StyleLookup` no style defines, the closest name one does define when one is clearly closest (`Did you mean 'tarjetastyle'?`; `didYouMean` in an entry of `delphi_styles lint`): the agent had the styles' names in another file to find it in (found by Hermes' directed test of 1.29). One rule for a name almost right (`NombreParecido`) - a third of its length, at least 2 - which `set` and the value judge of the designer wrote by hand.

- `delphi_db update` and `delete` change at most `max` rows (default 100): with more, nothing is changed - the transaction is rolled back - and the answer says how many it would have changed and how to repeat it (`DB-028`). A filter that selects more than the agent meant touched them all, and a row of a database does not go to a trash; found using `delphi_db` as an agent against a real database. `fields` says what the database fills in by itself when an insert does not give it: `autoinc` (an identity or serial column; SQL Server's catalog does not say it of an identity, so it is read from the table as FireDAC opens it) and `default` (a column with a default value), measured in SQL Server and PostgreSQL: an agent found out which required fields it had to give one error at a time. `tables` of a database whose schema has no tables or views says which schema it looked in (`DB-029`): the agent could not tell an empty database from one it did not see. The new row's key is not returned by `insert` yet: through a FireDAC dataset it came back in both engines, but its INSERT left in execution with its timeout and, with the network silent, the cancel left the worker thread hung for good (measured); that is for 1.29.1.

### Fixed

- `delphi_edit` (one edit, a batch) and `delphi_changeset` refuse, before writing, a change that leaves a Delphi source without the final `end.` it had (`EDIT-133`); a batch or a changeset is judged on what remains, so one entry may take it out and another put it back. It was written, and `EDIT-085` said afterwards to restore and stop (Hermes' directed test of 1.29: an edit took the `end.` of a unit).
- `delphi_edit` and `delphi_textedit` refuse a BLOCK anchor that takes the whole file, as they already refused a range from the first line to the last (`EDIT-019`, which now says which of the two it was): a block with every line and a `new` rewrote the file whole (Hermes' full test of 1.29). `delphi_changeset` takes one-line anchors only.
- `delphi_changeset stage kind=create` takes `eol` (`crlf`, the default, or `lf`), as `delphi_textedit create` and `delphi_create` do: it always wrote CRLF, without saying so (Hermes' full test of 1.29). Another value is refused by the same rule as theirs.
- `delphi_report command=read` by the report's name alone (as `REPORT-012` offers) finds it in its agent's folder, where reports go since this version: it looked only at the root of the mailbox and answered `REPORT-008` (Hermes' full test of 1.29). A name in two agents' folders is `REPORT-014`, which names both as `list` shows them; nothing is read.

- `delphi_designer preview` of a VCL form draws a hidden control (`Visible = False`) the same from a Windows service as from a desktop session, as the IDE designer shows it (the VCL shows hidden controls while designing: `UpdateShowing` and `AlignControls`). The service's way of painting (`fidelity=print`) walked the child windows by `Visible` and left them out, so the same form gave two images: Hermes' directed test of 1.29 saw a hidden panel over a button on a desktop session, and here it did not show (measured: a hidden red panel came red with `window` and white with `print`). It now asks the VCL's own `Showing`.

- `delphi_designer preview` and `layout` draw an MDI child form (`FormStyle = fsMDIChild`): it never drew, from a service or a desktop, and answered `DSGN-061`, blaming a design package. The renderer hid the form after taking the picture by asking the VCL to, and the VCL does not hide an MDI child without its parent, not even while designing (`Cannot hide an MDI Child Form`); it now hides the window itself. And from a Windows service an empty edit or combo box shows its `TextHint`, in grey, as the IDE designer does: there Windows paints none of those controls' text and the server painted only `Text`, so they came blank (measured on the service). Found by comparing the two ways of painting pixel by pixel on the 355 forms of RAD Studio's samples: 257 identical, the rest in the native look (a control's border, the weight of a group box's caption), none in size or geometry.
- `delphi_changeset stage` says what a kind takes when it refuses a parameter that is not of it: `kind=delete takes path no parameters` is now `kind=delete takes path` (Hermes' directed test of 1.29). A clean `preview` says that each operation was rehearsed on its own and that `commit` judges each file as the whole batch leaves it (its final `end.`, a form the IDE can read): Hermes took a clean preview for a batch the commit would refuse.
- Every document that says how many tools the server has says 44: three still said 42, and the check that counts them only read the README.

- `delphi_designer preview` and `layout` name the file that keeps the renderer from drawing when a form of the same folder cannot be read (`DSGN-116`). The renderer may load any form of the folder as a frame or an ancestor, so one that cannot be checked still refuses the render, as before; but the answer said "the form strings" and sent the agent to look at the form it had asked for, which was fine, and `layout` fell back to the text with that same answer (measured: one damaged binary `.dfm` left every form beside it without the renderer).

- A Linux64 build against a sysroot that lacks the development name of a library (`libz.so`, when the target machine has only `libz.so.1`) completes it and builds again with Delphi 13.2 too: its linker, lld, says `unable to find library -lz`, and the server only recognised the `cannot find -lz` of 13.1's linker - in the check that starts the completion and in the completion itself. One reader now knows both (measured on a 13.2 machine: a project using `System.ZLib` against `fedora44.sdk`).
- `delphi_desktop type` on a Linux target checks the whole text before pressing a key: a character the keyboard cannot compose half way through left the first part typed in the window and answered that nothing could be typed (measured on a Fedora desktop: `ab<TAB>cd` left `ab`). A tab is the Tab key, as a line break is the Enter key; any other control character is refused before typing, by its code, and a character outside the basic plane (an emoji) is refused by its name, not as `?`.
- `delphi_adb logcat` with `filter` searches the device's whole log and returns the most recent `lines` that match: it took the last lines first and filtered those, so an app's lines further back never came (measured on a tablet: 302,624 lines, the app's 27,000 back; `filter` answered `ADB-022`, empty). A dump adb did not finish (the device dropped half way) says so (`ADB-036`) with what arrived: it came as the whole log, or, when the device's own log carried words such as `offline`, as a refusal with the raw dump inside.
- `remote-run` sweeps on the target only the watchers of its own jobs: the cleanup after a run asked PAServer to remove `*.wait*.exe` in the project's folder, so a deployed file of the project such as `Bus.waitlist.exe` went with them. The mask now has the shape of a job's id (`*-*-*.wait.*.exe`), composed by the namer of those files.
- `delphi_db rows` orders by a field whose name holds a space (`order="Fecha Alta desc"`): the order was split at every space and refused with `DB-016`. A space that is not part of a real field is still `DB-016`. `summary` refuses two columns of a group with the same name - a field to group by called `n` beside the count `n`, or `sum_x` beside the sum of `x` - with `DB-027`: each group came with the key twice. An entry of the connections file whose project or name is empty or holds `/` is not used and says why: `a/b` + `c` and `a` + `b/c` made the same name, and the first hid the other.
- `delphi_docs`: a link of one help to a file that two installed helps share (two vendors' `IDE.chm`) leads to the one in its own folder, as HTML Help opens it; it led to the first one (none shares a name in a standard installation, measured in the IDE's registry).
- `delphi_docs` with the help of Delphi 13.2 reads an inherited member as 13.1 does: `FMX.Forms.TForm.StyleBook inherits from FMX.Forms.TCommonCustomForm.StyleBook`. Its help files (September 2026) carry the wiki's templates unresolved - three `{{#multireplace:NAME|H21=&#33;|H28=&#40;...}}` in the inherited line of about 25,900 pages, some 300 characters each -, and an operator came as `operator H28H29` instead of `operator ()`. Each template now leaves its name with the substitutions it declares itself; any other template, or one that does not close, stays as the page has it. Measured against the 13.1 help, which the wiki resolved: 25,831 of the 25,835 pages both versions have read the same (the other 4 changed their content). Nothing on this side resolves them: neither the IDE's installation nor the pages' own script and style sheet mention the template (measured).
- `delphi_desktop` on Windows: a window title or an error text with a line break no longer splits the node's line (`STATE`, the reason it could not do something).
- A process that a launched program leaves running inside its Job - a component inside the renderer that starts a helper, a test that starts another program - is killed when the Job closes, and if it was a VCL or FMX program its global atoms stayed behind: the server cleaned only the program it launched. They are now taken alive before the Job closes, and what they leave is cleaned (measured: three atoms for every preview cut by the deadline of such a form). A full atom table stops Windows from starting any process.
- `delphi_config add-requires` also writes the package's `.dproj` as the IDE does: a `DCCReference` to the `.dcp` of each package it asks for, after the last `.dcp` and ahead of the units (measured in the 17 packages of the RAD Studio Samples, each with one per `requires`). It wrote only the `.dpk`. The answer names what the `.dproj` received (`CFG-154`), and a package already in the `requires` whose reference the `.dproj` lacks gets it, and the answer says so (`CFG-153`); with no `.dproj` at all, `CFG-048` names the `.dpk` that was written (it said `.dpr`, from `add-unit` too); the two files change all or nothing, as with `add-unit`. And `delphi_create kind=project-package` makes the `.dproj` with the reference to `rtl.dcp` that its `.dpk` requires.
- A path longer than Windows opens for this server (260 characters or more, on its long form) is refused by its length in any tool (`GUARD-046`): each tool said `does not exist` (`LSP-011`, `SYS-012`...) with the file there, and a write said reading it was fine. Measured on a machine with `LongPathsEnabled`: 259 characters read, 260 did not. Writes keep their own limit of 232 (`GUARD-028`).
- `delphi_paserver get-sdk` pulls the libraries, and writes in the `.sdk` the folders and the linker's startup objects, that the installation's `Linux64.defaultsdkpaths` lists: they were written in the server, copies of that file (the same for 37.0). Without the file it says so (`PAS-075`).

- `delphi_designer lint` (and the note after a write) no longer says `CLEAN` of an FMX form with a `StyleLookup` nobody judged. Its judge is the platform's default style, which the style converter gives; when the server could not read it - the converter not deployed with the server, or it failed - the lint said nothing and called the form clean (measured: the same insert says `DSGN-175` with the converter). It now says how many were not judged and why (`DSGN-199`). `delphi_styles lint` said the converter was missing whatever the cause, and ran it twice when it failed: it says the cause once (`STYLE-017`).

- `delphi_build target=Deploy` for Android with a `.deployproj` that already existed but did not deploy Android - written by a deploy to another platform, or by the IDE with an empty Android group: msbuild stopped with `E8712` (`AndroidManifest.xml does not exist`), because the server generated the Android entries only when there was no `.deployproj` at all, while for the other platforms it completes an existing one (`BUILD-014`). It now adds the standard Android entries - the generated AndroidManifest, styles/strings/colors, default icons and splash artwork, the compiled library - for each configuration that has none, without touching the other platforms' entries, and says so (`BUILD-073`). Reported twice by agents (31-oct and 7-nov; the second measured it: with the `.deployproj` deleted the `.apk` came out and ran).

- `delphi_designer preview` with a `.vsf` style of a VCL form saved at another PixelsPerInch (120, say): out of design mode the VCL scales such a form to the display's DPI as it loads it, so the image was 96/120 of the file, while `componentRect` and `frame` said it was in the file's units (measured: a button at 375,10,94,31 in the `.dfm` came as 300,8,75,25). The renderer now says how many pixels of the image make a unit of the file, and `componentRect` and `frame` are in the file's units again.

- `delphi_build` says when the project's main source is a `library` but the build does not ask dcc for one (no `GenDll`): dcc wrote the library under an executable's name (`MideLib.exe`, measured) and the answer pointed at it as if it were the program. A project that became a library through the tools - a console project with its header changed - stayed that way. The note next to the output (`BUILD-072`) says how to fix it: `GenDll=true`, as a library project has.
- `delphi_designer` on a form that inherits a frame placed in an ancestor form: `get` and `set` reach the frame's components by their path (`Frame11.Edit1`) whether or not the inherited form has a block for them. The IDE writes such a frame in the inherited form as `inherited Frame11: TFrame1` (measured), and the designer knew a frame only by the word `inline`: `Frame11.Edit1` was `DSGN-078` with its block right there, a bare `Edit1` took the frame's, and without a block not even `Frame11` was found. Which inherited blocks are frames is what the IDE's form reader says, and a block written for one carries the frame's class as the ancestor writes it - not `TFrame`, the class the reader loads a project frame with.
- `delphi_config remove-deployfile` takes the entry as the project lists it, even one that points outside the workspace, as `remove-unit`, `remove-searchpath` and `remove-project` already did: a `DeployFile` that a project copied from another machine names on that machine's disk was refused with `GUARD-002`, and the `.dproj` - which only `delphi_config` writes - kept it, so `delphi_build` kept refusing the project with `BUILD-050` (found by an agent, 6-nov). The entry goes from the `.dproj` and the `.deployproj`, and the file it names is never opened. `BUILD-050` now says that `remove-deployfile` removes a file to ship.
- Security: a UNC path that a project names - its search path, a `{$I}` - is no longer resolved on disk before it is refused. The read gate of the IDE's, the vault's and the library's places resolved it, and `delphi_projects` looked whether the folder existed before the jail did: both reached the named host over SMB with the service's account (measured: 21 s and 23 s against an address that does not answer, against 0.02 and 2 s with a local folder that does not exist). A UNC is resolved only when its text falls inside a place of that kind.
- Security: a symbolic link inside the roots to a hard link whose other name is outside them was read and written through (`delphi_read` returned the outside file, measured): the hard-link judge counted the names of the link itself. It judges the file behind a link now.
- Security: a project's search path can no longer hand the language engine the IDE's user data folder, where the `.profile` files keep the PAServer password; the build already refused it.
- Security: `delphi_db` refuses a `contains`, `starts_with` or `words` filter with nothing to look for: it matched every row, and an `update` or a `delete` with it passed the guard that refuses one without filters.
- Security: what a database says comes back without any IP address and without the operator's user in the database's own language. With the server given by NAME in the connections file, PostgreSQL's refusal carried the address it resolved (`(fe80::...)`) and, from its `pg_hba`, this server's own; and a PostgreSQL that answers in Spanish quotes the user between angle quotation marks (U+00AB, U+00BB), which the masking took for part of a word and left in clear (measured). Whether a piece of the text is an address is decided by Windows' own parser.
- Security: `delphi_api` does not use an entry with a `pin` and an `http` base address: a pin checks a certificate, there is none without TLS, and the request (with its credential) went out before the refusal said that nothing had been sent.
- Security: `delphi_git` writes to the server's log only the host of a clone's address, never the address, which may carry `user:password@`.
- Security: the desktop node's folder on a target belongs to the server. A project named like the node (`McpDesktopNode`) is refused on every door that sends a project to a target (`PAS-074`): `remote-run` ran the agent's binary from the node's folder (measured), and its `Deploy` put it there. And a deployment entry lands in its own project's folder: PAServer places a `DeployFile` relative to the profile's folder and the IDE starts its `RemoteDir` with the project's name, so another first folder - the node's, or that of a project the operator lets run - overwrote it, and the desktop sessions of other agents, or a `remote-run` of the other project, then ran what was put there. Off macOS and iOS a `RemoteDir` must start with the project's folder, without `..` or a macro, and a `RemoteName` never goes up (`BUILD-070`); measured on the 68 `.deployproj` of the IDE's samples and of real projects, 1,393 entries of Linux64, Win32, Win64 and Android, all of them in that folder. On macOS and iOS, whose bundles the IDE names `P.app\..\` and `$(PROJECTNAME)`, nothing may go above the profile's folder. Only a build that deploys judges them, and only the entries it deploys: those of another platform's group are not, and a build that only compiles never was (a project renamed by hand whose manifest still names its old folder compiles as before).
- Security: `delphi_db` on PostgreSQL opens a database with its connections file and nothing else. libpq filled what the file does not say from the server account's environment (`PGSSLMODE=require` changed the connection, `PGHOSTADDR` would send it to another machine, `PGSERVICE` to a service file; measured): the server removes the `PG*` variables from its own environment when it starts. It never offers the account's client certificate, its Kerberos encryption or its Windows identity (`sslcertmode=disable`, `gssencmode=disable`, `require_auth=!gss,!sspi`): the file gives a user and a password. These need libpq 16 or later; an older one refuses to open, saying so.
- Security: `delphi_git clone` judges the branch it is given without asking the repository above the destination, which may be outside the roots: `@{-1}` read that repository's reflog, and whether the clone went ahead told whether it had a previous branch (measured). The name is checked as a full ref (`refs/heads/<name>`), which git does without reading any repository.
- Security: `delphi_db` and `delphi_api` hide a credential also as it comes back ESCAPED or ENCODED: an API that returned its token inside a JSON with its `/` written `\/` or its `+` as a `\u` escape, or inside a URL as `%2F` and `%2B`, showed it - and a JSON body, parsed after the masking, gave it in clear (measured). A JSON body is masked as the server's own encoder writes it, so any mix of escapes is covered, and the raw text (a truncated body, what `out=` saves) with the usual JSON and URL forms of each secret.
- Security: `delphi_api` refuses the agent's headers that override the method or the path the API serves (`X-HTTP-Method-Override`, `X-HTTP-Method`, `X-Method-Override`, `X-Original-URL`, `X-Rewrite-URL`) with `API-010`: on an API whose `methods` allow only GET, a GET carrying `X-HTTP-Method-Override: DELETE` reached the server, and one that honours it would delete. `API-010` now says what it judges in a header's name (a space, a colon or a control character): it promised the HTTP token of RFC 9110, which it did not check.
- `adduses` and the reference tools find a unit's `implementation` and `interface` as whole words also next to an accented letter: in a unit that declares a `procedure MenuImplementation;` with an accented `u`, `adduses section=implementation` wrote the clause inside that declaration (`procedure ...Implementation uses System.Classes;;`, measured).
- `delphi_references` and `delphi_rename_symbol` read a binary `.dfm` as the form it is: its uses came back with the binary's bytes as their text and a meaningless line, or not at all when a neighbouring byte was a letter. They come with the text and the line `delphi_designer to-text` gives.
- `delphi_create kind=include` takes a file name (`my-defs`, `Vcl.Defs`): it was judged as a unit name and refused (`CREATE-007`). A name with a folder, a drive or a stream is refused with `CREATE-040`; a standalone unit still takes a unit name.
- `delphi_create`'s subfolder of a project and `delphi_config set-output` take letters of any alphabet (an accented `Modulos`, a Cyrillic name): only ASCII letters passed (`CREATE-001`). What the `.dproj`'s XML, msbuild or the `.dpr`'s literal would read as syntax is still refused.
- `delphi_config set-output output=default` says what it restores: the layout `delphi_create` writes (the binary in `.\$(Platform)\$(Config)`, the `.dcu` in a `dcu` folder below it). Its description and its answer called it the RAD Studio layout, but the IDE's own project templates put the `.dcu` next to the binary (measured in its seven `.dproj` templates). What it writes is unchanged.
- The connections files of `delphi_db` and `delphi_api` are read while another program has them open for writing, as `settings.ini` is: the call failed with `SYS-027` (measured).
- `delphi_db` on SQL Server no longer searches the network for SQL servers: reading the driver's parameter table started FireDAC's server browse (`SQLBrowseConnect`, about 16 seconds of network enumeration) in a task that outlived the call, and when the server stopped it returned into the ODBC library already unloaded - an access violation on every exit (a service stop included) and the RTL's global atoms left behind (measured with a debugger and the event log).
- `delphi_designer preview state=` reads a number's sign as the form parser does: `--5` and `- 5`, which the IDE refuses, were read as 5 and -5. An integer the form parser does not read is refused with `RENDER-028` and a value its property's type does not take (an enumeration's unknown name) with `RENDER-029`, both `INVALID_PARAM`: they came out as `DSGN-061 INTERNAL`, an error of ours.
- `delphi_upload` with an `offset` into a folder that does not exist refuses before creating the folder, which stayed behind empty.
- `delphi_db` writes and finds a path as the database holds it: what a database says goes out with the server's drives as their virtual units (`D:\` as `srvd:\`), and the agent hands it back as it read it, so an `update` wrote `srvd:\` into the database and an `equals` with it found nothing (measured). A text value that starts with a served virtual unit goes back to its real drive, by the same rule as every argument of a call.
- `delphi_search regex=true` and `vault_search` find what they should in a line with a lone surrogate (a UTF-16 source keeps one as it is): the engine joined two of them as if they were a pair, so `[^a]X` missed one line and gave another one character early (measured). Each lone surrogate is searched as U+FFFD, one for one, and the positions are the text's.
- Every tool that rewrites a text file refuses one that looks binary (NUL bytes) with `TEXT-008`, as `delphi_read` and `delphi_edit old/new` already did: `adduses` and `removeuses` edited a `.pas` with NUL bytes (measured). A binary form keeps its own way (`to-text`).
- `delphi_edit adduses` adds to a uses clause that carries comments without rewriting it: the last unit's `;` becomes `,` (its comment stays with it) and the new units go on new lines with the clause's indentation. The clause was rewritten one unit per line, so five units on one line became five lines for one added (measured).
- `delphi_references` and `delphi_rename_symbol` read every unit the project lists, also one in a folder named like a build artefact (`debug`, `release`, `win32`...): a use there was not found, and a rename left it with the old name (measured). A folder of that name that the project does not list is still skipped. A unit the `.dpr` writes with other capitals than the disk is read once: its uses came twice.
- `delphi_changeset`: an `atline` on a file the same batch creates counts the lines of what it creates (a `delete-line atline=2` went to line 5, the whole batch was undone, and the preview had said clean - measured), and an `atline` staged on the destination of a `move` follows the edits made to the file before it moved. The path a `move` leaves free is another file from then on: a `create` there in the same batch, and what is staged on it, are judged against what the batch creates - the preview judged them against the file that moved away and refused a batch that the commit would apply.
- `delphi_test` counts a console program as a test project when its name has the WORD test, tests, testing, spec or specs (`MyAppTests`, `unit_tests`, `Tests.Core`), or starts with test or spec, or ends with tests or specs (`mormot2tests`, the runner of mORMot2, `Testrunner`): any name with those letters inside passed, so `Latest` and `Inspector` were taken for suites and run. Word boundaries are the ones the designer already used to tell a component's events (`Ok` is not in `OkayClick`), now one rule for both.
- `delphi_search` with `wholeword`, `delphi_references` and `delphi_rename_symbol` take a time in proportion to a long line: in a line of 300,000 characters where the text appears many times inside other words, a regular-expression search took 111 seconds and a plain one about a minute, because each rejected match copied or folded the whole line again (measured); now about a second.
- `delphi_desktop key` on a Windows target takes a single digit or a key name (letters and digits, starting with a letter), and the node reads a number only when it is digits: `+5`, `$1B` or `-1` reached the node, which read them as a virtual key code (5 is a mouse button). A single digit was refused although the node presses it. `type` of only blanks types them (it was refused as empty).
- `delphi_desktop` and `delphi_paserver remote-run` without `exe=` run the binary the project builds for the target - its `OutputExt` included - instead of the project's bare name.
- `delphi_build` names the binary of a library or a package as the compiler leaves it, and returns it as `output`: a Linux64 library (`libX.so`), a package with a suffix (`{$LIBSUFFIX AUTO}` gives `X370.bpl`, a literal one its text) and a Linux64 package (`bplX370.so`) came back without `output` (measured). The kind comes from the main source's header, the prefix, suffix and version from its naming directives (the `.dproj`'s `DllSuffix` is not what the compiler uses), and each platform's extensions and prefixes from the installed `CodeGear.Common.Targets`, which were written by hand. The deployment manifests and `remote-run` take the same name.
- `delphi_api` no longer hides a default port it did not write: an `https` address without a port turned a `Content-Length: 443` into the API's name.
- The symbols the compiler always defines, which the reader of the installed sources uses to choose their `{$IFDEF}` branches, are the ones the compiler defines: `CPU386` on Win32 and `WEAKREF` and `WEAKINTFREF` on both were missing (measured by asking the compiler, one `{$IFDEF}` per symbol). A battery now asks the compiler and compares.
- A wildcard (`*` or `?`) in something a build reads - a `<DCCReference Include="sub\*.pas"/>` - is refused with its own reason, `BUILD-071`: msbuild would expand it into files nobody named, and a build's reads are judged file by file. It was refused as `BUILD-050`, "outside what a build may read", also for a folder inside the project.
- `delphi_styles build` keeps every piece of its answer when reading, writing or placing a style fails halfway (a style another program holds open): the list of converted styles was attached to the answer only at the end.
- `delphi_search` and `delphi_list` without `pattern` also look at the IDE's deployment manifest (`.deployproj`), the project's other file: a search for a `RemoteDir` scanned two of a project's three files and did not find it.
- `delphi_config set-property` without `platform` and `config` writes the base group, as the IDE does for "All configurations - All platforms", and now says which other groups set the same property and still win for their own builds: it answered "for all platforms" while a new VCL project's Win64 Release kept reading `PerMonitorV2` from its own group (measured).
- The note of every `delphi_db rows` page (`DB-019`) says the same in half the text.
- `delphi_styles` reads the style converter's messages in UTF-8: an accented name in a `.style` came out broken in `lint` and `set`.
- `delphi_config add-project` names a project's targets in a group as the IDE does, a dot as `_` (`MakerAi.UI.dproj` gives `MakerAi_UI`): msbuild refuses a dot in a target's name and the group stopped loading.
- `delphi_report` without `agent` files the report in the folder of the name the client declared at the handshake, as `delphi_messages` reads the mailbox and as both descriptions promised ("`agent=` wins over the handshake"): it went to the root of the reports folder. A session that declared no name still goes to the root.
- `delphi_paserver get-sdk sdk=` refuses a name with anything but letters and digits (`PAS-076`, with the name it would take), before connecting: `Ubuntu_24.04` became `ubuntu2404` in silence, and a build with the name the agent wrote did not find it.
- `delphi_build`'s `missingUnits` and its note about units implicitly imported into a package (`W1033`) read the unit from the line by its compiler code, as the rest of the build does: a folder named like a code in the path of an error (`F2613Demo`) gave a unit that was not missing, and the note's unit could be taken from the next line. Whether a project is a package is judged by the header of its source, as the compiler does.
- `delphi_test` refuses a `.dpr` that starts with `package` (`TEST-018`): it went by the extension, built the package and launched it.
- `delphi_search`, `delphi_list`, `delphi_references` and the walkers of a move or `fix-references` treat the output folder of every platform as build output, as they did with `Win32` and `Win64`: `Linux64\Prod` (a configuration of its own) was walked as source.
- The cache of a project's location is kept for a folder synced by OneDrive: its reparse attribute was taken for a link, so it never had a stamp.
- The server's own temporary folder is emptied at startup also of a read-only file at its root (one a folder below already went).
- `delphi_paserver add-profile` warns about a profile that already points to the same host and port also when that profile does not say its port (the default 64211): it compared the text. `test-connection` of a profile that does not connect says how long the probe took (`elapsedMs`), as the probe without a profile does.
- `delphi_desktop key` on a Windows target lists the digits among the key names it takes (`DESK-010`); it pressed them already.
- `Out` can name a form, a component, a unit or the new name of a rename, and `delphi_references` finds the uses of a variable called `Out`: the reserved-word list had it, and dcc takes it as a name (it is a directive, like `operator`). The list was measured against dcc one word at a time; the other 64 are refused by the compiler.
- `delphi_changeset kind=` takes the names its description lists: an undocumented `deleteline` is refused (`CHSET-010`, which names `delete-line`).
- `delphi_edit` judges an anchor with a lone CR the same alone and in a batch (`edits`), which looked only for LF and refused it again and again; a file in the trash called like a stamp (`lote-123456789`) comes back with its name; moving something out of an old `__delphi-temp` leaves no trash inside it; the language tools of a folder with one project that the session cannot read go on without its settings instead of refusing; the note about the version `.res` looks at the `.res` of THIS build; `adduses` in a `.dpr` judges whether a unit is the project's as dcc resolves it, as `removeuses` did; `delphi_config fix-references` re-points the macOS icon, the UWP logos and the Android keystore of a `.dproj`, which it said it had re-pointed.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
- [1.28](docs/changelog/1.28.md)
- [1.27](docs/changelog/1.27.md)
- [1.26](docs/changelog/1.26.md)
- [1.25](docs/changelog/1.25.md)
- [1.24](docs/changelog/1.24.md)
- [1.23](docs/changelog/1.23.md)
- [1.22](docs/changelog/1.22.md)
- [1.21](docs/changelog/1.21.md)
- [1.20](docs/changelog/1.20.md)
- [1.19](docs/changelog/1.19.md)
- [1.18](docs/changelog/1.18.md)
- [1.17](docs/changelog/1.17.md)
- [1.16](docs/changelog/1.16.md)
- [1.15](docs/changelog/1.15.md)
- [1.14](docs/changelog/1.14.md)
- [1.13](docs/changelog/1.13.md)
- [1.12](docs/changelog/1.12.md)
- [1.11](docs/changelog/1.11.md)
- [1.10](docs/changelog/1.10.md)
- [1.9](docs/changelog/1.9.md)
- [1.8](docs/changelog/1.8.md)
- [1.7](docs/changelog/1.7.md)
- [1.6](docs/changelog/1.6.md)
- [1.5](docs/changelog/1.5.md)
- [1.4](docs/changelog/1.4.md)
- [1.3](docs/changelog/1.3.md)
- [1.2](docs/changelog/1.2.md)
- [1.1](docs/changelog/1.1.md)
- [1.0](docs/changelog/1.0.md)
- [0.x](docs/changelog/0.x.md)
