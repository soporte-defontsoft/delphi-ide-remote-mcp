# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

## [1.25.1] - 2026-11-02

A patch for what measuring everything left pending after 1.25.0 found, and for what two
agents found testing that. The form designer no longer writes an edit after a client gave
up on it, which could land a control twice, and `insert` no longer closes a cycle of frames.
A frame that contains itself is told apart instead of bringing the renderer down, and
`RENDER-007` says to repeat the call: measured with Microsoft Defender's own report, the
first load of design packages after a signature update can pass the renderer's 60 s. Nothing
in a contract changes. Validated before the release through Hermes on a second machine by
Qwen3.8 Flash Next and GPT-5.6 Luna (directed tests of what changed).

### Fixed

- `delphi_designer` no longer writes an edit after a client may have given up. When judging an `insert`, `set` or a rename took 50 s or more, the client had usually stopped waiting (many give up at a minute) while the server went on and wrote: the agent repeated the call and the control landed twice. Now nothing is written and the answer says so (`DSGN-185`); repeating it works, since what was slow the first time is ready.
- A frame that contains itself, directly or through others, is told apart (`RENDER-026`, with the chain), and the rest of the form is drawn without it. The renderer fell with an access violation after about 3 s, `preview` blamed a design package (`DSGN-061`) and `lint` answered CLEAN. `lint`, and a form edit, now ask the IDE's form reader about every form that holds an inline frame, which no table can judge.
- `delphi_designer insert` no longer closes such a cycle (`DSGN-186`, nothing written). Through another frame it wrote the cycle and answered `ok`, with the two units using each other. A frame into itself got `DSGN-015`, "not in the table", with the recipe to write it by hand, which leads to the cycle.
- `delphi_designer insert` gives a VCL frame the next `TabOrder`, as the designer does when dropping it: with three controls it took 0, the one of another control.
- An `insert` or a `set parent=` that writes without being able to ask the IDE's writer for the order no longer says "Nothing was written" in its `orderNote` (`DSGN-145`), of what it had just written. Only `set before=`, `after=` and `index=`, which do refuse, say it.
- `FILE-053` no longer sends you to delete the live file when what you named is the link itself: it says the link is the operator's, and that nothing was deleted.
- `RENDER-007` says what to do, and names the cause it left out. Microsoft Defender checks each design package it has not seen under its current signatures, up to about 10 s each: on a 4-core VM with 41 third-party packages the first load after a signature update took 86 to 110 s and passed the renderer's 60 s, with nothing wrong in the form or its packages. The answer blamed them. Now it says to repeat the call, since what was checked stays checked.

## [1.25.0] - 2026-11-01

A minor version around the protocol, and around what agents kept tripping on.
The server speaks MCP 2026-07-28 next to the sessions it already had, on the
same endpoint. **One contract changes: `delphi_desktop` now has its own
permission, per host, and it needs a line in your `settings.ini`**
(`DesktopAllowedHosts` to see and act, `DesktopViewHosts` only to see; the
refusal says what to write). `delphi_search` shows the lines around a hit and
leaves files out, `delphi_git` takes six more operations, one `delphi_changeset
stage` takes several, a build lists its hints, a unit below its project's folder
gets its warnings and hints, and a local with a common name can be renamed. What
`delphi_build` and `delphi_test` report now comes from MSBuild's classification
and DUnitX's own summary, where a folder or a test that printed the right words
could turn one result into another. Validated before the release through Hermes
on a second machine by Qwen3.8 Flash Next (a full test of every tool and directed
tests of what changed).

### Added

- **The server speaks MCP 2026-07-28, next to the sessions it already had.** That revision
  removes the handshake and the sessions. `server/discover` now answers with the versions
  spoken, the capabilities and the instructions, where it answered `-32601` and the clients
  fell back. A request with that version in its `_meta` is served with no session: its
  headers and required fields are judged (`SYS-035` to `SYS-038`, with the codes and HTTP
  statuses the revision names), and its results carry `resultType`, `serverInfo` and, on the
  ones a client may keep, `ttlMs` and `cacheScope`. An `initialize` still opens a session
  that works as it did, on the same endpoint. Your identity there is the `clientInfo.name`
  of each request: with no name, or one that sanitizes to nothing, a request gets an identity
  of its own and never the operator's, so what it sends to the trash cannot be purged by
  the next one. This opens nothing new: a holder of the token could already `initialize`
  with any name, and the name is still a courtesy between honest agents, as the revision
  says too. Requests with no session do not count in `sessions` of `delphi_workspace`.
  Not done: closing a response stream does not cancel the work in course, as before.
- **`delphi_docs search` pages like every other list.** `offset` takes its `nextOffset`, and
  the answer says `shown`, `hasMore` and `nextOffset`; it was refused (`DOCS-017`), so past
  the first 25 results a page of the help could not be reached.
- **`delphi_search` shows what is around a hit and leaves files out.** `context` adds up to 10
  lines to each hit, as `before` and `after`, so a search no longer needs a `delphi_read` per
  hit. `exclude` takes masks like `pattern`, judged the same way, and `excluded` counts what
  it left out.
- **`delphi_git` takes six more operations, by fields as always.** `diff format=name-only`;
  `log grep` (the commit message, as text, ignoring case); `add action=update` (every tracked
  file that changed, or only `paths`); `commit action=amend` (with `message` or keeping the one
  it has); `fetch action=prune`; `clone branch`. Two refusals keep them from destroying
  anything: `GIT-086` when a remote already has the commit to amend, and `GIT-087` when a
  refspec writes outside `refs/remotes`, where prune would delete local branches (measured with
  plain git: it took the current branch too).
- **`delphi_build` takes `configuration` and `command` as other names of `config` and `target`**,
  what agents send without looking; each one cost a call.
- **`delphi_changeset stage` takes several operations in one call.** `ops` is a list of the
  fields one `stage` takes; all are staged or none, and each goes through the same checks as one
  sent alone. A batch of N files costs four calls instead of N+3.
- **`delphi_build` lists the compiler's hints in `hints`**, read by the same reader as `warnings`:
  they only came inside `outputTail`. Nothing in `quiet`, no key when there are none, no repeat
  in the tail, and at most 50 with `hintsTotal` saying how many there were.
- **`delphi_diagnostics` gives warnings and hints of a unit below its project's folder.** The
  engine only gave its errors, and `LSP-046` said so; measured, what decides it is the folder of
  the project named in its settings, and that file does not have to exist. Such a unit is linted
  with its own settings, per folder, and nothing is written in the workspace. Each folder costs
  an engine, inside `MaxEngines`. `LSP-046` is gone.
- **`delphi_rename_symbol` refuses when a unit it does not write would silently change target**
  (`RENAME-023`, `retargeted`). With a global of the interface, if another unit uses both and the
  renamed one comes later in its uses, a call that resolves elsewhere today would take the new
  symbol, and it compiles (measured with dcc: the last of the uses wins, those of `implementation`
  count after those of `interface`). A method, a routine only in `implementation`, a local
  declaration or a qualified call do not count.
- **`delphi_definition` says what is at the destination**: `name` and `text`, the line as written,
  so finding out what it found no longer takes a `delphi_read`.
- **A local with a common name can be renamed.** `delphi_references` and `delphi_rename_symbol`
  look for a local in its routine only, and say so (`localTo`): every `I` of the project used up the
  candidates, and those of other routines blocked the rename as homonyms. The candidates inside are
  still judged by the engine; a parameter is not a local, its header lives in two places.

### Changed

- **`delphi_desktop` has its own permission, per host: this needs a line in your `settings.ini`.** `DesktopAllowedHosts` sees and acts on the desktops of those hosts, `DesktopViewHosts` only sees them (`screenshot`, `status`), and `RemoteHosts` is still needed too. `McpDesktopNode` or `all` in `RemoteRunProjects` no longer grant it, and a workspace that relied on them gets `RUN-020`, which says what to write. That entry was a permission disguised as a project in a list of project paths, and it could not tell one target from another, or looking from typing.
- `delphi_edit` `adduses` and `removeuses` read their list like `add-requires` does: `;`, `,` or a blank separates names. `"A B"` was refused as one invalid unit name.
- The account warning of `delphi_workspace` asks the process token whether the server runs as LocalSystem (SID `S-1-5-18`), so it no longer depends on the name of the account or on `USERPROFILE`.
- An agent's mailbox and report folder are its name in lower case, so `a--b` and `a-b`, two agents for the trash, no longer read and delete each other's mail.
- Rules that were written in several places now live in one: the text a new file is born with, the empty unit skeleton, the IDE's `bin` folder, where a sysroot keeps its `libc.so.6` and whether it mixes two distros, which `delphi_adb` commands need a named device, how a disabled IDE package is matched, what msbuild sees of the server's environment, the lines the form renderers write to the server, how an answer writes a position, what a note leaves out after an edit, and which `delphi_git` commands only consult. No result changes.
- The standard unit aliases the engine gets come from the installation's `CodeGear.Common.Targets`, where they were a copy of that list. Answers of several lines use one line break, LF: some used CRLF.

### Fixed

- `delphi_changeset` refuses `delete` and `move` of a link when staging (CHSET-036): undoing a batch that failed turned a link into a plain file with its target's content, while the answer said every file was back byte for byte. `delphi_delete` and `delphi_move` handle the link itself.
- `delphi_test` with `nobuild` runs the binary of the configuration it was asked for. With a literal output folder per configuration, the newest binary won: Release ran the Debug binary and reported its results as Release's. The `output` of `delphi_build` reads the same output folder, the one of that build.
- `delphi_edit` `insert=rutina-global` in a `.dpr` whose `uses` is split in `{$IFDEF}` branches places the routine after the whole clause. It landed inside the first branch, so with the other branch active the routine did not exist.
- An Android project with no version keys gets the `minSdkVersion` and `targetSdkVersion` of the installed IDE, read from its Android package (36 on 37.0), where the server wrote a fixed 35.
- `delphi_build` takes `errors`, `warnings` and `hints` from MSBuild's own classification, in log files of the server. They were found by searching its console text: with `verbosity=normal`, a warning whose text said `: error` came back in `errors` next to `success: true`, and with `verbose` a folder named `My error Example` sent there every line that named it, and each warning came back twice.
- `delphi_designer set`, `delphi_edit` and `lint` say when a string value names a path that `preview` refuses (DSGN-183): `set` wrote it, `lint` answered CLEAN, and only `preview` refused the form, and any other form of its folder, afterwards (DSGN-115). The form stays valid and the value is written: it is a note, by the same judge as `preview`. After an edit it names only what that edit brought.
- `delphi_test` reads the DUnitX summary as its own block of whole lines, the last one in the output, and its failures only after it. A test that printed `Tests Failed : 7` turned a green suite red, one that printed `Tests Failed : 0` hid the count of a red one, a line `Failing Tests` from a test filled `failures` of a green suite, and a failure message with `Tests Failed : 0` in it could make a red suite with exit code 0 come back green.
- `delphi_build` retries a locked binary and reports it only when the compiler said F2039. A project in a folder named `F2039Demo` with any other error built five times, about 17 s, and came back with a note about a locked binary. The same goes for what it reads of the linker's `cannot find -l` and of `W1033`, which now come from MSBuild's error and warning logs.
- `delphi_rename_symbol` gives `character0` on the row of the definition too, like every other row of `changes`.
- A form renderer from another version says so (DSGN-184) instead of being misread. The renderers now state their protocol first thing and the server compares it: with a stale renderer, `preview` blamed a design package (DSGN-061), and what it skipped could turn into "not confirmed" with no notice.
- `delphi_designer prop` says that an integer property with no named constants the form reader understands takes a whole number. On `ModalResult` it said nothing, and the way to find out was to try `mrOk`, which is refused.
- The description of `delphi_delete` says what a reference project is (`ReadOnlyRoots`): an agent read it as any project with its repository, tried a delete expecting the refusal, and it went to the trash, as a folder of your roots does.
- `scripts\Enviar-Mensaje.ps1` leaves the message where the server reads it, in the workspace's folder (`-Workspace`), and refuses a folder that does not exist. Since each workspace got its own mailbox (1.18.0) it wrote to a folder nobody read, and `docs/TOOLS.md` said the same.
- An engine stopped under another agent's request ends clean: `shutdown` is now the last thing it receives. A request that had already passed the check of "is it stopped?" could be written after it, and then the engine, having answered everything, died with `0xC0000005` when its input was closed. Nobody lost an answer, but the log said so and the suite went red about one run in forty.
- **`delphi_desktop` against a PAServer that does not answer costs one wait, and only that
  profile's.** `paclient` gives up by itself (21 s against an address that does not answer,
  and its `--timeout` does not shorten that), so no `timeoutms` was added: what went away is
  ours. The first gesture on a profile tried to upload the node after being told there was no
  connection, paying the wait twice; while it waited it held a lock shared by every profile, so
  a gesture on a live target waited behind a dead one; and each attempt left a folder in the
  server's temporary area. `status` still answers `reachable: false` with the reason; a gesture
  now says `FETCH-004` instead of `RUN-010`, with what `paclient` said.
- **A routine whose header spans several lines is found again.** For a call to it the engine
  answers a line inside the header, which does not name the routine: `delphi_definition` pointed
  there, `delphi_references` took the call for a homonym and `delphi_rename_symbol` was blocked
  (`RENAME-017`). Now the answer is the header itself.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
