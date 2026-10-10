# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [1.18.0] - 2026-10-10

Consolidation. The big units sorted by what they hold, each rule in one
home; ANSI as the machine's code page, the first accent of a source written
as the IDE writes it, and no writer leaving a file that would not read back
the same; the Git jail closed - the repository's configuration as a
whitelist, `.git` a place only `delphi_git` reaches, LFS endpoints and every
remote host judged, no signing with the person's key; what a form names
judged before it is rendered; a mailbox and a reports folder per workspace.
Five version reviewers and one more for the zones of the build and git
filters before the tag, each finding fixed with its red or moved, by name,
to the next version.

### Fixed

- **A build compiles the bytes its gate scanned.** The compile-only scan of
  the `.dproj` (an `<Exec>`, a foreign `<Import>`, a redefined property of
  the IDE's imports, an include from outside) ran before the build waited
  for its turn, and msbuild read the project again when it started: a
  `delphi_edit` in between - easy to time behind another, long build - put
  in an `<Exec>` the scan never saw, and it ran on the server. The scan now
  runs once the build has its turn, under the write lock every writer takes,
  held until msbuild ends, so nothing changes those files in between. The
  price: while an untrusted build runs, the edits of every session wait for
  it (a trusted project, `AllowBuildScripts=1`, is not scanned and takes no
  lock). Version reviewers of 1.18.0, the cause confirmed in the code and
  then live: `test_build_toctou_118` holds the turn with a long build, queues
  a clean project behind it and rewrites that project's `.dproj` meanwhile -
  against the previous binary the planted `<Exec>` ran and the edit did not
  wait; now it never runs, in either order the lock can give. Also
  `test_build_evaluacion`, `test_build_imports`.

- **`DSGN-145` says why the judge of the order could not answer.** The note
  of an `insert` or `set parent=` that stayed last always blamed the
  renderer for not loading the form whole, also when the judge refused for
  another reason (a literal of the form, `DSGN-115`) or when the anchor was a
  child of the ancestor that the derived form does not write: it now carries
  the judge's own reason, and the order of the IDE is compared only with the
  children that are in the text - when the block is already last of those,
  it is where the IDE keeps it and no note is given.

- **The writer of a text asks its gate before it reads anything.** The
  round-trip rule of `PatchSaveText` (the designer, the changeset, the
  rename, `delphi_textedit`) read the bytes of the file before the writer's
  gate judged the path: a caller writing a file it had found in a `.dpr`, or
  a UNC, caused I/O wherever that pointed, and `EDIT-038` told that it
  existed and its encoding. The gate is asked first now.

- **`set parent=` does not carry the `[n]` of a component to its new
  parent.** In an inherited form a new component placed among the
  ancestor's children carries `[n]`, its place among the children of the
  ancestor of its OLD parent; moved whole, the reader of the form applied it
  in the new one and the component went first among its new siblings. The
  header is written again without it, and the judge of the order places the
  block where the IDE keeps it.

- **The comments of a uses clause stay with their own entry (11.3).** A
  comment behind the `;` of a compact clause (`uses UA, UB; // de UB`)
  followed the clause edited in place - behind the new unit after an
  `adduses`, or with the unit left after a `removeuses` of its own; that
  clause is now rewritten by the writer that knows whose it is. And an
  own-line comment that repeats the text of another one behind a comma
  (`// TODO`) no longer goes away with the removed entry above it: the
  comment that goes is the one behind the comma of the removed entry, not
  any comma with that text behind it.

- **Deleting or moving an entry is judged by the folder it really sits in.**
  `delphi_delete`, `delphi_move` and the `delete`/`move` of a changeset asked
  the write gate about the real path of the file, which follows the last
  link too: a folder of the jail that is a junction out of it, holding a
  file link back inside, passed - and the delete or the rename happened in
  the folder outside. The folder the entry really sits in (its real parent
  plus its name) must now be one the session writes in, or `GUARD-038`. The
  same check the writers make about where their temporary file is born
  (`GUARD-037`), without the read-only attribute: a read-only file can still
  be moved or trashed. Measuring it takes the privilege to create a file
  link; without it `test_puerta_escribir` says so (NOTA W2).

- **`removeuses` keeps each comma inside its conditional, or says it
  cannot.** Removing an entry followed by a conditional that opens behind its
  name (`A, B {$IFDEF X}, C{$ENDIF};`) left `A, {$IFDEF X} C{$ENDIF};`, which
  does not compile without `X` (`E2029`). The comma that goes with an entry
  is now the one in its own region: the one behind it as before, or the one
  in front when a conditional opens behind the name (`A {$IFDEF X}, C
  {$ENDIF};`, compiled with and without `X`). And the writer of a uses clause
  checks that what it leaves is still a list in every combination of
  branches, when the clause it found was one: where no comma can go safely it
  refuses with `USES-023` and writes nothing. `remove-unit` too.

- **`add-requires` extends the `requires` of a one-line package.** In
  `package P; requires rtl; end.` the clause was looked for at the start of a
  line, a second one was opened behind it (`E2029`) and the answer said the
  clause was only the new name. It is read now where the reader of the
  clause reads it: first thing after the package header.

- **`delphi_package` never puts Git metadata in the zip.** It read every
  file of the folder on its own, so a folder holding a repository went out
  with its `.git` whole - `.git\config` with the credentials of a remote,
  the hooks - ready to download with `delphi_fetch`, while `GUARD-033`
  promised that no file tool reads it. Each file now goes through the read
  gate, and what it does not admit is left out and counted (`leftOut`,
  `WS-024`).

- **A batch range with `atline` ends where it was asked.** Inside `edits`,
  `atline` counts on the file as the earlier entries left it, and `toline`
  was always corrected for those entries as if it counted on the file
  before the batch - so after an entry that added two lines, `atline: 14,
  toline: 15` removed lines 14 to 17 and answered `APPLIED`. The end of a
  range now counts as its start does: with `atline`, in the same moved
  numbers; without it, on the file before the batch, corrected on its own
  as before. Both `delphi_edit` and `delphi_textedit`.

- **Each workspace has its own mailbox and its own reports, and
  `delphi_report` reads them.** `messages\<agent>\` and `reports\<agent>\`
  were one folder for every token: an agent of one workspace could list and
  consume the mail of an id it guessed in another, and no tool read the
  reports at all - the operator copied them by hand. The same structure is
  now split by workspace, `messages\<workspace>\<agent>\` and
  `reports\<workspace>\<agent>\`, and the workspace comes from the
  session's token, never from a parameter (the local process, which enters
  without a token, uses `_local`). The folder is `Workspace.` and the
  workspace's name made safe, in lower case - a form no agent folder of the
  old layout can have, so an old `reports\hermes\` is never read as the box
  of a workspace called `hermes`; a name that loses something on the way (an
  accent, a sign, more than 40 characters) gets eight characters of its MD5
  behind, so `Hermes VM` and `Hermes-VM` never share one. `delphi_report command=list`
  shows the reports of the caller's workspace by agent folder, newest first,
  and `command=read name=<dir>\<name>` one whole; nothing is moved or
  deleted, a name that is not a report of that box is `REPORT-008`, and an
  agent folder that is a junction out of the server's home shows nothing.
  `message` is no longer `required` in the schema (list and read do not take
  it); filing a report without it is still `REPORT-002`. **For the
  operator:** a message for an agent now goes into
  `messages\<workspace>\<agent>\` (`messages\Workspace.claude\hermes\` for the
  agent `hermes` of `[Workspace.Claude]`), and a workspace's reports are in
  `reports\<workspace>\`; what was left in the old folders is neither
  delivered nor listed.

- **`insert` and `set parent=` put the component where the IDE keeps it.**
  Both wrote the new or moved block as the LAST child of its parent; the
  IDE writes a VCL graphic control (a `TLabel`) before the windowed ones,
  an inherited form places by its `[n]`..., so the file was not in the
  IDE's order and the IDE moved it the first time it saved. Now they ask
  the same judge as `set before=/after=/index=` (the form loaded as the
  designer loads it and written by TWriter) and place the block right after
  the sibling the IDE writes right before it (before the next one when it
  is the first): in a file that was already out of the IDE's order,
  anchoring before the next one changed its place among the graphic
  controls written before it - its z-order. When the judge cannot answer
  (a sibling no package loads, an ancestor not found) the block goes last
  as before and `orderNote` says so (DSGN-145): nothing is refused for it.
  The judge runs without the write lock - the tool's own gate kept insert
  and `set parent=` inside it until their reviewer measured another edit
  waiting for them -, so the form, and the unit for insert, is checked to
  be the one judged before writing (DSGN-144), as the order already did;
  the three share one judge (`JuezDelOrden`) and one open/check pair.
  `test_designer_orden` I1-I5, red before.

- **An alias with the declared name empty leaves one key.** `root: ""`
  with `path: srvd:\...` (an alias of `delphi_list`), or `path: ""` with
  `unit:` in `delphi_config`, left two keys with the same name behind the
  duplicate check, and the tool, the binder and the rewrites by name read
  the first - the empty one, or the one the gate had not expanded nor
  lengthened: a misleading GUARD-023 for a `srvd:\` path, and an 8.3 path
  reaching the tool short (the UPROVE~1.PAS case of the sixth review, by
  the alias). The empty declared name now goes when the alias takes its
  place. `test_mascara_contenido` M11/M11b, red before.

- **`vault_search` with nothing found echoes the pattern masked.** Its echo
  is content and skips the output filter, and its "No results for ..." put
  the pattern the gate had already expanded: `C:\...` for a `srvc:\...`.
  It goes through the mask now, and so does the mask note of
  `delphi_search`. `test_mascara_contenido` M12, red before.

- **`delphi_test run` lists what the test left by folder, like every file
  list.** Its `files` was the one list of files of another shape - flat,
  each entry with its relative name - while every other tool groups by
  folder through one organizer (`delphi_test discover` too). Now `files =
  [{dir, files = [{name, size, content...}]}]`, with `dir` `.` for the
  test's own folder (it is deleted with the call, so the paths are relative
  to it) and `.\sub` for what it wrote below. `test_delphi_test_contenedor`
  K3c.

- **What is written inside a file is content, by a mark, and a path in a
  form value works.** The entry gate turns `srvd:\` back into the real
  drive in every argument except those that carry content - and which ones
  did was a list of NAMES for all tools at once. It missed `old_text` /
  `new_text` of `vault_patch` (an `old_text` copied from `vault_read` with
  a `srvd:\` in it did not match its note) and `body` / `text`, the aliases
  of `message` in `delphi_report`, and it named a `data` no tool has any
  more. And the designer only got the expansion of a WHOLE value: a quoted
  `value='srvd:\x'`, or any value inside `props`, landed in the `.dfm` as
  `srvd:\x`, a path that does not exist at run time. Now the rule is
  written once (`[Contenido]`, `Lsp.Attributes`): what is written inside a
  file, or in a message, or goes to a program on another machine, is
  content and the gate leaves it alone; `value`, `props` and `state` of
  `delphi_designer` are the declared exception - the designer expands the
  TEXT of each value, because a path literal in a form has to work when it
  runs. The parameters carry the mark, read by the same RTTI walk as
  `[RutaDelServidor]`, and the gate expands after the aliases, so an alias
  is judged as its parameter. Changed for whoever relies on it:
  `old_text` / `new_text` of `vault_patch`, `anchor` of `vault_append`,
  `body` / `text` of `delphi_report` and `value` of `delphi_styles` are no
  longer expanded; the key `code` of adb-linux now is (no key code starts
  with `srvX:`). The cost of the exception: a `Caption` or a `Hint` that
  starts with `srvd:\` on purpose is written with the real drive. And
  something to know: `new_text` of the vault is content, so a path copied
  from `delphi_list` stays `srvd:\` in the note. `test_mascara_contenido`
  M7-M10: M8, M9, M10 and M10b red against the build before, M7 and M10c
  against a mutant without the mark and without the designer's expansion;
  from its reviewer, M7b-M7g (the rest of the editing family: a mark taken
  off one parameter goes red) and M10d (the state of preview, drawn with
  the real drive). The descriptions of `value` and `state` and the README
  say it.

- **A local path is never looked for in a network place.** Every write asks
  whether its path falls in a vault - of any workspace - and the place's
  real path was resolved on disk each time: a vault on a network drive
  whose server is down made each first check wait 21 s (measured raw). A
  path on a local drive cannot be inside a UNC or a drive that is not
  local, so `EnLugar` and `EnAlgunLugar` (`Lsp.Rutas`) now say no from the
  session's drive table alone (`LugarDeRedParaRutaLocal`, no network), for
  every place they compare: vaults, roots, references. Nothing they
  answered changes. DUnitX `TLugarDeRedTests`: asking for a local path in
  a UNC place on TEST-NET takes 21 s with the rule taken out and none with
  it (the suite run outside the test container, where the network is).

- **`adduses` puts a library unit into a `.dpr`.** A unit of the library
  (`FMX.Edit`, `System.SysUtils`) had no tool into a program's uses:
  `adduses` refused every `.dpr` and `add-unit` is for the project's own
  units (it writes `in '...'` and the `DCCReference`) - a wall measured
  moving a form between frameworks. `adduses` now takes library units -
  no path, the compiler finds them - into a `.dpr`, by the same writer as
  `add-unit`, and creates the clause after the header when there is none
  (one writer for that now, `EstrenaUsesTrasCabecera`, which `add-unit`
  also uses); a unit of the project - its `.pas` next to the `.dpr` - is
  refused with `add-unit` named (`USES-021`), and a `.dpk` goes on being
  refused, now pointing to `add-unit` and `add-requires`.
  `test_delphi_patch`, red before.

- **A removed unit takes the comment on its line with it.** `removeuses`
  (and `remove-unit`, the same writer) left the `//` written on the line of
  the entry it removed as a loose line inside the clause (found moving
  `Lsp.Sandbox`: an orphan `// ServerDir y ClaveDeCarpeta...`). The rule is
  the house's - there is no judge for it - and it is declared: a comment on
  the same line as an entry is that entry's and goes with it, the one
  after a comma and the one after the final `;`; a comment on a line of
  its own stays, also when it sat right above the removed entry. Until now
  "a comment is never deleted" (2-oct). `test_delphi_patch` and
  `test_project_units`, the four checks of the old rule moved to the new
  one, red against it, and two more cases.

- **The startup log says which roots it cannot reach.** A root or a
  reference the server could not reach when it started was said by
  `delphi_workspace` (`unavailableRoots`) and by the tool that touched it,
  never at startup: in production a declared root did not exist and the
  log said nothing. Every root and reference declared - the environment's
  and each workspace's - is now asked to the same judge,
  `MotivoRaizNoDisponible` (a drive that is not connected, a local folder
  that does not exist; it never goes to the network), and each one that
  fails is a startup warning with its reason. It only informs: the jail
  stays as declared. `RaicesNoDisponibles` (`Lsp.Guard`) is the one walk
  for that and for `delphi_workspace`, and `SitiosDeclarados`
  (`Lsp.Settings`) the one list of declared places, which the network
  drives used to build by hand. `test_paredes_1131` W10, red without it.

- **`delphi_edit` reads the final `end.` the way dcc does.** Its audit
  counted an `end.` only alone on its line, so writing a statement before
  it - `Writeln('x'); end.`, or a program as `program P; begin end.`, both
  compile - answered `EDIT-085` BROKEN STRUCTURE and told the agent to
  restore and stop (measured live). One reader now, `EndsConPunto`
  (`Lsp.Pascal`): the word, blanks (line breaks too) and the dot, as dcc
  reads it (`end` with its `.` on the next line compiles, measured), and
  the seven places that read it by hand with two spellings go through it.
  So `insert` also finds the end of a unit written that way (it answered
  `EDIT-049`), still refuses one whose `end.` has code before it on its
  line (`end; end.`: the routine would land inside the line above), and
  refuses a block with an `end.` anywhere in it (`EDIT-043`; one in the
  middle of a line went in, and the file was left with two). And a batch
  judges the structure of a source at the end even when no one-line entry
  warned: a block entry never asked, so a batch of blocks that took the
  `end.` away said nothing (measured). The audit is also relative now, as
  dcc reads: the first `end.` is the final one, and `EDIT-086` speaks only
  when what follows it changed - notes left uncommented after the `end.`,
  which the compiler never reads, answered it on every edit of the file,
  and on a batch that wrote nothing, with the order to restore (its own
  reviewer). And `insert` takes the boundary of a unit from the class
  reader (`TUnidadPas.FinDeclaraciones`: `initialization`, the main
  `begin` or the final `end`): a unit with `begin ... end.` as its
  initialization got the routine INSIDE that block (measured: E2070), and
  one with no implementation section got it in its interface (it answers
  `EDIT-049` now, nothing written).
  `test_delphi_patch`, each case red with its part undone - the two
  refusals kept from before are guards, red only with their guard taken
  out; the `test_paisaje` rule holds one house.
- **Ref and revision names are judged by git, not by a regex** (`9.A`, the
  landscape rule "what can be measured is not hard-coded"). `check-ref-format
  --branch` for a NAME the agent writes (a push refspec's destination, a
  `worktree add` ref) and `rev-parse --verify --quiet --end-of-options` for a
  REVISION that must exist. git accepts what git accepts - a non-ASCII branch,
  `x{y}` - which the regex refused, and refuses `-x`, ranges and `x.lock`
  (which the regex let through to git, that then errored). A push refspec's
  FORM stays closed BEFORE asking git: a leading `+` (force) and an empty
  source (`:dst`, delete) are refused by shape, because `check-ref-format`
  accepts `+main` as a name ("no remote destruction", David). `test_git_refs`.
- **Git metadata is judged by git in the write gate, not only by a `.git`
  path segment** (`9.A`). `git init --separate-git-dir` leaves the real git
  directory with no `.git` segment, so the shortcut missed it and an agent
  could plant `sep.gitdir/hooks/pre-commit` - a hook that runs the person's
  git. The write gate now also asks git (`rev-parse --absolute-git-dir
  --git-common-dir` from the file's folder, through a hook `Lsp.Guard` lets
  `Mcp.Tools.Git` fill so the low security unit does not depend on the git
  tool): a path inside the git dir or the common dir is metadata and is
  refused. The `.git` segment stays as a cheap shortcut; only writes pay (one
  git process per folder inside a repo, ~43 ms, cached per folder -
  `--separate-git-dir` is banned in init/clone, so a folder's git status
  cannot change under the tools and the cache cannot go stale). `test_git_meta`.
- **The LFS wall (`GIT-061`) rises only when the repo actually uses LFS**
  (`9.A`, `2.1h`). The judge of "this repo uses LFS" is git, not that the
  `filter.lfs.*` program is present in config (it is, on any machine with
  git-lfs installed): `git ls-files ':(attr:filter=lfs)'`, across every
  attribute source. Before, `GIT-061` refused `worktree add`, `switch`,
  `merge`, `pull` and `stash` on ANY repo whose origin was outside
  `GitRemotes`, LFS or not, without touching the network (a false positive
  measured on this very repo: the night's `stash` and `worktree` of `1.3` had
  to go through the console). Now, with the tree materialized and no LFS file,
  the checkout smudges nothing, so the derived endpoint is not examined and the
  operation runs; with an LFS file the endpoint is judged as before and the
  wall stands. An explicit `lfs.url`/`remote.*.lfsurl` and a `.lfsconfig`
  redirect are judged through the config path regardless, and an empty index
  (a fresh `clone --no-checkout`, a bare repo) keeps the old examination so a
  clone's checkout still cannot smudge from an unjudged host. A git failure
  while judging is not a "yes". `test_git_lfs_muro`.
- **Git metadata is for `delphi_git` alone (`GUARD-033`).** The file tools
  refuse a path inside `.git`, or a folder that holds one, also through a
  junction or a symbolic link: `.git\config` can carry the credentials of a
  remote, and a hook planted under `.git\hooks` runs the next time the person
  uses git. Only `delphi_git` reaches repository metadata. A whole repository
  folder may still move, or go to the recoverable trash and come back, inside
  the workspace, as long as its metadata links stay inside the allowed
  places; a copy of a tree that holds `.git`, and a `.git` that links outward,
  stay refused. `delphi_projects` still shows a repository's branch: it reads
  `.git\HEAD` with git's own permission, without opening `.git` to the file
  tools. `test_git_config_cerrado`, `test_git_repo_entero_118`.
- **The local configuration of a repository is a whitelist (`GIT-051`).**
  Before running, `delphi_git` reads the repository's local and worktree
  configuration, and since 1.11.3 it refused the keys known to load another
  file or run a program (includes, filters, external diffs, credential
  helpers, the ssh command...) - a list that could only miss the next one.
  It is the other way round now: only known keys that neither run nor read
  anything are admitted - the `core` basics (`longpaths`, `fscache` and
  `untrackedCache` too, which an ordinary Windows repository carries),
  `pull.rebase`, the identity, the signing
  switches, a remote's addresses and refspecs, a branch's upstream, a
  submodule's place - and Git LFS is the one program admitted, with its exact
  standard commands. Anything else is `GIT-051`, which names the key and
  never its value (it may hold credentials); a configuration git cannot list
  is `GIT-052`. `test_git_config_cerrado`.
- **An agent cannot sign with the person's GPG key.** Every git the server
  runs gets `commit.gpgsign=false` and `tag.gpgsign=false`, so a repository
  set to sign does not sign, and a call that asks for it is refused: `-S`,
  `--gpg-sign` and its abbreviations on `commit`; `-s`, `-u`, `--local-user`
  and `--sign` on `tag`. A group of short options is read to its end: an
  `S` anywhere in it signs, unless an option that takes a value comes first
  (`-mS` is the message `S`) - the version reviewers measured `-sS`, `-nS`,
  `-asS` and `-vsS` reaching gpg. A commit's `--signoff` (and `-s`,
  `--sign`) only adds a `Signed-off-by` line and is allowed.
  `test_git_config_cerrado`.
- **git never waits for a password, and does not see the server's
  settings.** Every git the server launches gets the server's environment
  without its `DELPHI_MCP_*` variables, plus `GIT_TERMINAL_PROMPT=0` and
  `GCM_INTERACTIVE=never`: a remote that asks for credentials fails at once
  instead of waiting, until the time limit, for an answer nobody can give.
  One reader of a child's environment, the one the `delphi_test` container
  already used. `test_git_config_cerrado`.
- **Every network address of a remote passes the operator's host list.**
  `GitRemotes` judged the address written in the call; the ones already
  stored in the repository's remotes were taken as good. Now each network
  address, from the call or from the repository, goes through the same list,
  and the call's remote is judged before the configuration and LFS gates, so
  a remote that is not allowed is refused as a remote (a folder outside the
  roots: `GIT-044`), not by what it would trip later. `test_git_jaula`,
  `test_git_config_cerrado`.
- **Git LFS downloads only from where the operator allows (`GIT-061`).**
  Materializing a tree with LFS files makes git-lfs fetch them from an
  endpoint derived from the remote, or set in `lfs.url`,
  `remote.<name>.lfsurl` or a `.lfsconfig` - a second network address nobody
  judged. The orders that materialize a tree (`clone`, `switch`, `merge`,
  `pull`, `stash push`/`pop`, `worktree add`) judge the effective endpoint
  with the judge of a remote - a network address by `GitRemotes`, a folder by
  the workspace's folder gate - and refuse with `GIT-061`, never showing it.
  A `clone` checks out only after that judgement, and the judged endpoint is
  kept for the whole operation, so a `.lfsconfig` arriving with the new tree
  cannot change it. Commands that only read metadata (`status`, `log`...) do
  not ask git-lfs, so a system-wide `filter.lfs.*` does not deny them.
  `test_git_lfs_118`, `test_git_lfs_sistema_118`.
- **What a form names is judged before it is rendered (`DSGN-115`).**
  `preview` hands the form to a helper that loads it with the IDE's reader,
  and a string property naming a file - a picture, a style, whatever a
  third-party setter opens - was opened by the helper wherever it pointed.
  Before launching it the server now reads the string literals of the form,
  of the sibling forms the helper can resolve (frames, ancestors; linked ones
  are skipped, as the helper skips them) and the `state` values of the call,
  and asks the read gate about each one that names an existing file: one
  outside the allowed read locations is `DSGN-115`, naming the property and
  never its value. A literal that is a UNC or device path (`\\server\...`,
  `\\?\`, `\\.\`) is decided by its text before any I/O, so a form cannot
  make the server wait on SMB. A form that cannot be checked is `DSGN-116`,
  and the form and its siblings share a 16 MiB budget, looked at before
  decoding (`DSGN-117`: 65 MiB of text cost 416 MiB in the server).
  `test_render_jaula_118`, `test_render_unc_118`.
- **`delphi_edit` and `delphi_textedit` delete a blank line.** `delete`
  asked for `old` with the line, and a blank line has no text to copy: the
  way round was a three-line block. Now `delete` with `atline` and no `old`
  removes that line if it is blank - what an empty anchor matches, by each
  engine's own rule - and refuses a line with text, quoting it (`EDIT-123`),
  or one that is not there (`EDIT-124`); a single edit and a batch, in both
  tools. A range (`toline`) is never anchored on a number alone (`EDIT-125`),
  and `occurrence`, which counts an anchor's text, says so for a blank line
  (`EDIT-126`). `delphi_textedit` also refuses an anchor of only blanks
  (`EDIT-060`, as `delphi_edit` does): it matched every blank line and
  rewrote one. And `delphi_changeset`'s `delete-line`, born for blank lines,
  follows the same rule: without `old` it removed ANY line, now only a blank
  one (the preview says so). `test_delphi_patch`, `test_changeset`.
- **`edits` is published as an array of objects.** The schema said text, so
  a client that validates the call against it refused an array before
  sending it, and the model ended up sending the JSON inside a string
  (Hermes, measured). The parameter marked as carrying JSON
  (`[JsonComoTexto]`) is published as an `array` of `object` - one reader of
  the mark for the schema and for the binder - and a string with the JSON
  inside is still read. `test_delphi_patch`.
- **EDIT-091 sees a brace written inside a comment that opens on another
  line.** The warning for a brace comment with a brace inside looked only at
  the new text, so a line written in the middle of a `{ }` comment of
  several lines - with a quoted `{$I}` in it, or a brace - said nothing, and
  dcc stopped with E2029 (measured, in a single edit and in a batch). It now
  looks at the file as written, at the comments that touch the lines written
  (or the seam a deletion leaves: deleting the line that closed a comment
  can put the next one inside it); a nested comment elsewhere in the file
  still says nothing. `test_delphi_patch`.
- **The jail reads the IDE's library zone by its real path.** With the
  library zone on, a path outside the roots was readable if its TEXT began
  with a folder of the Library Search Path: a link already planted inside
  such a folder and pointing elsewhere was followed (measured with a test
  folder in the Library Search Path of a throwaway registry layer: the file
  behind the link came out through `delphi_read`), and a folder registered
  in 8.3 form refused even its own files. The zone is now judged as the
  roots are: inside by the long form of the text, and inside for real by the
  real path, with the comparator the read gate already used (it moved to
  `Lsp.Rutas`); a link that leads out is refused saying so (GUARD-036). A
  library folder on a network share is still read (only the folder the
  path names is asked, not every one). `test_paisaje` keeps the raw list
  out of the jail; DUnitX `ElComparadorDeLugaresVaPorLaRutaReal`; the end to
  end case needs a library folder in the IDE's registry, so it was measured
  with a probe (red with the previous binary) and has no battery.
- **The jail's writer judges where its temporary file is born.** Every
  write in the workspace replaces the file through a temporary one next to
  it, in the folder it was GIVEN, while the gate judged the real path of the
  file, which follows the last link too: a folder of a root that is a link
  to somewhere else, holding a file link that points back inside, passed,
  and the temporary file - and then the written one - landed outside (the
  shape the P3 reviewer measured in the vault and the IDE's places). The
  writer now also asks whether the real folder plus the name is a place it
  writes in for real - a root, and no reference, read-only folder or vault,
  each by its real path (GUARD-037) -, never comparing a real path with a
  declared text: a root declared through a junction stays writable
  (`test_puerta_escribir` W2, red against the first version of this fix).
  W1, the case itself, needs a file link, which this account cannot create:
  it says it is not measured.
- **A cropped desktop capture is cropped before it is placed.**
  `delphi_desktop screenshot window=` placed the capture in `out=` and then
  rewrote that file in place to crop it, a raw write behind the gate and the
  lock; the crop now happens on the downloaded copy and what is placed is
  the crop, as `delphi_designer preview` already did; the crop's origin is
  reported only when the crop was placed.
- **Undoing a batch writes whole or not at all, and never deletes the only
  copy.** When a batch, a changeset or a project change failed half-way,
  each file went back with a plain overwrite, so a failure during the undo
  itself (a full disk, another process) left half-written the very file it
  was restoring; it now goes back through the jail's atomic writer (a path
  too long for its temporary file, written directly as before). The undo
  restores what existed BEFORE it removes what the operation created, and
  keeps a created file when something did not come back: it may be the only
  copy (the destination of a move). The read-only attribute comes back even
  when the write fails. `test_changeset` A-1, DUnitX
  `LoCreadoSeQuedaSiAlgoNoVolvio`.
- **The IDE's own form parser judges forms and styles before they are
  written, and lint asks it.** `delphi_designer` and `delphi_styles` checked
  what they composed with a grammar of our own and wrote it, and `lint`
  answered CLEAN to a `.fmx` with a `//` comment that only the IDE refused
  when it loaded it ("Identifier expected on line 2", measured). Now every
  write of `delphi_designer` (insert, set, delete, rename, move) and of
  `delphi_styles` passes the result, in the file's own encoding, through the
  parser the IDE loads forms with (`ObjectTextToBinary`), in memory: a
  result it does not read is not written (DSGN-124), and a file it already
  could not read says so (DSGN-125); `lint` puts the parser's message first,
  with the line it names and that line's text (DSGN-123), table or no table;
  and `preview` asks it before starting the renderer (DSGN-126 instead of a
  renderer failure). The line comes from the parser's own message format,
  not from a text written here. `test_parser_form` (P1-P4 red against the
  previous binary: lint said CLEAN, set wrote into a broken form, a `{zz}`
  block went into a style). A list with commas, `('a', 'b')`, which our
  grammar took for a closed list, is one the parser refuses - a form writes
  `('a' 'b')` -; `test_styles` asserted the old opinion and was corrected.
  The writers of the designer also say DSGN-121 after writing a text form
  in UTF-16 or UTF-32 (the compiler does not build one), as lint did.
  The three lints of a form are one (`LintDeForm`): the one after
  `delphi_edit`, a batch or a changeset on a `.dfm`/`.fmx` did not ask the
  parser - the very door of the 8-oct case - and now puts DSGN-123 first
  too, marked `***` like the other warnings that stop a form from loading.
  The parser judges the TEXT as it will be on disk, with its line breaks (a
  `.fmx` of only CR, one line for the parser, was judged joined by CRLF),
  counts lines as it does, by LF, says when its message names no line (a
  number too big: DSGN-123 said "the end of the file"), and judges a UTF-32
  form by its text in UTF-16, as the IDE opens it (it was not judged at
  all). `delphi_create` and a changeset's `create` write a new form only in
  an encoding the parser reads (one rule, `EncDeFormNuevo`): with the IDE
  set to ANSI, a form name with an accent was born unreadable; a changeset
  that creates a form the parser reads in no encoding writes it and says
  DSGN-123, as `delphi_edit` does. DUnitX `ElJuezLeeEnLaCodificacionDelFichero` (the file's
  encoding, the critical part, had no test) and `ElJuezSinLineaYAlFinal`;
  `test_parser_form` P7/P8.
- **`delphi_designer insert` and `set` take several properties at once.**
  `props` (`Caption=Save;Left=24;Font.Style=[fsBold]`) gives a new
  component its initial properties or sets several of one: each judged as
  `set` judges one, all in memory and one write, all or none (DSGN-127 to
  DSGN-132: the entry that does not pass, Name alone, a property twice). A
  `;` inside a quoted value does not split, in `props` and in `preview`'s
  `state` (one reader: it split `Caption = 'a;b'` in two). Asked by Hermes,
  copying a form one call per property. `test_designer_props`. A quote
  opens a quoted value only when it STARTS the value (so does a `#N`, as in
  `#39'a;b'`): in `Caption=Don't
  save` it is a letter (the first reader swallowed the rest of the list into
  it without a word - in `state`, a regression), and a quoted value that
  never closes is refused (DSGN-134). In `state` a quoted value is a form
  literal and the renderer gets its text (it painted the quotes). Only `nil`
  on references that are not there writes nothing (DSGN-112, as `set` of
  one did); `insert` says it in that entry.
- **`delphi_designer set` orders a component among its siblings.**
  `before=`, `after=` or `index=` (1 = the first), alone, move its block
  among its siblings, and only where the IDE keeps it: before writing, the
  form as proposed is loaded by the renderer the way the designer loads it
  (its packages, frames and ancestors) and written by the IDE's own writer
  (`--writeback`, `Lsp.FormRender.ComoLoEscribeElIde`); a place it would
  not keep is refused with the order it would save (DSGN-136). No list of
  our own decides what goes before what: the VCL writes graphic controls
  before windowed ones, a toolbar in the order of its buttons, an inherited
  form places a new component by its `[n]`, FMX leaves last what is not one
  of its objects - the first version imitated the writer with a list and
  went wrong in a toolbar and an inherited form (its own reviewer). A
  sibling whose class no package loads cannot be asked about (DSGN-140);
  not siblings, an index out of range (0 included), itself, or two of them
  at once are said (DSGN-135 to DSGN-141). What the renderer could not load
  (an ancestor it did not find next to the form - it now says so, `PARTIAL=`
  -, a parent no package loads) is not judged half-way: DSGN-143 / DSGN-140,
  nothing written. `before=`/`after=` hold against the sibling named and
  every sibling jumped; `index=` is a position, held against all. The
  judge runs outside the global write lock - it takes seconds - and the
  form is written only if its bytes are still the ones judged (DSGN-144).
  The renderer now answers in UTF-8: a component name with an accent
  reached the server mangled, in `preview` too (`ROOT=`, `NONVISUALS=`,
  `IGNORED=`). The literal gate of the renderer now also looks at the
  folder it reads siblings from. Asked by Hermes. `test_designer_orden`
  (red with the judge's verdict ignored, without UTF-8, without the bytes
  check).
- **A `delphi_edit` batch judges a block entry as it judges a line.** An
  entry whose anchor is a block went straight to the block engine and
  skipped what `delphi_edit` checks: it wrote a `.md` (EDIT-032 refused only
  the one-line entries) and a form written by a block was never read by the
  IDE's parser - a `//` in a `.fmx` came back with no DSGN-123. One gate,
  `FicheroQueNoEditaDelphiEdit`, now answers for an edit and for a whole
  batch, and a block on a form is judged as a line is. Found using the
  server. `test_round49` (E5, E6).
- **A file `delphi_references` cannot read is said, not fatal.** One file
  of its scope held by another process made the whole call fail - and with
  it `delphi_rename_symbol`; so did the unit of the definition, and a form
  file rename reads. It is now skipped and listed in `unreadable` (LSP-040,
  once each, up to 25), since a reference in it would be missed, it is not
  counted in `filesScanned`, and a rename is not applicable while any is
  listed (RENAME-022). `test_rename`.
- **The folder digest lists a long `uses` whole, and a comment no longer
  decides a project's framework.** `delphi_symbols` of a folder joined at
  most nine lines of a statement, so a `uses` with one unit per line came
  back cut (twelve units: eight and a hanging comma), and so did an enum or
  a routine with one parameter per line, there and in a file's symbols (a
  function without its result type); the names of the `uses` now come from
  the Pascal reader (`Lsp.PascalDecl`) and a statement joins as many lines
  as it takes, up to a safety cap. `delphi_create` told VCL from FMX
  with a regex over the raw `.dpr`, so a comment naming `FMX.Forms` made a
  VCL project "FMX" and its VCL form was refused (CREATE-017); the units of
  its `uses` decide now, read the same way, and with unit scope names
  (`uses Forms`) the IDE's own `FrameworkType` in the `.dproj` (a VCL
  project was taken for a console one). Measured on the live server.
  `test_lector_clases` (C14c, C14d), `test_round8` (#4b, #4c).
- **A changeset says what the engine warned.** Its commit kept only "done"
  from each edit, so the engine's warnings - a brace inside a brace
  comment, a broken structure - never reached the agent (CHSET-032 now
  lists them with their file); a Delphi source it creates gets the brace
  check `delphi_create` gives. A warning comes with the lines under it (the
  list of properties of EDIT-076, the binding's), in a changeset and in a
  batch (`edits`): one reader of the warnings of an engine answer
  (`AvisosDelMotor`), where both kept only the `***` lines.
- **`edits` and `fragment` are content.** Sent as text, `edits` went
  through the expansion of virtual drives that only paths should get (as an
  array it did not); now they are left as written, like `old` and `new`.

- **The git remote gate reads a host only where git, ssh and curl all read
  the same one.** It took for the host whatever followed the first `@` of
  the rest of the address, so with a host allowed in `GitRemotes=`, an
  address carrying that host after an `@` of its PATH
  (`https://other.host/x@allowed.host`, `other.host:x@allowed.host`,
  `git@other.host:x@allowed.host`) passed the gate and git connected to the
  other machine (measured against the production binary: git ran), and so
  did a bracket or a `%xx` before the host. The host now comes from the
  address's authority (up to the first `/` of a URL, or the first `:` of the
  scp form, past an IPv6 literal), and only from what every program reads
  alike: a plain user, one `@`, a plain host or `[v6]`, a numeric port. An
  address with a `% \ ? #`, a blank, a misplaced bracket, two `@`, an `@[`
  outside its authority, a user in `git://` or no host at all is refused
  as unreadable (`GIT-062`) instead of guessed; a first version of this fix
  chose some terminators and its reviewer measured a dozen addresses each
  program split differently, some of which passed with `GitRemotes=` empty.
  `clone`'s message is judged whole, as git receives it, and only `clone`'s:
  a link in a commit message was refused as a connection (`GIT-004`).
  `test_git_argfilter` and `test_git_jaula` (J15b, J15c) carry the cases,
  red against both earlier binaries.
- **A batch of `delphi_edit` judges the structure of the WHOLE file at the
  end.** Each entry was audited on the file half-way through the batch, so
  an entry that opened a `(*` and the next one that closed it warned of a
  BROKEN STRUCTURE (EDIT-085) the final file did not have. The one-`end.`
  and last-line checks now run once, from the file before the batch to the
  file after it (the same helper a single edit asks), and a batch that does
  leave the file broken still warns, once. `test_round34` B6/B6b.
- **`adduses` and `removeuses` keep the shape of a compact `uses` clause.**
  A clause with several units on a line was rewritten one unit per line by
  either, a forty-line diff for one unit (the tray's own unit, measured).
  A compact clause (no comments or directives, plain unit names) is now
  edited in place: the units that go leave with their comma, a line left
  empty goes with them, and new units are appended after the last one, on
  its line while it fits in 80 columns (or the widest line the clause
  already had), else on a new line with the clause's indent. Any other
  clause, and every `.dpr`/`.dpk`, is written one unit per line as before.
- **A GET that asks for an SSE stream gets `405 Method Not Allowed`** (with
  `Allow: GET, POST, OPTIONS`), as the MCP transport lets a server that
  offers no stream on GET answer. It got a `200` stream that closed at once,
  and the Python SDK reopened it every second. A dead session still gets
  its `404` first; a GET without the event-stream `Accept` still gets the
  endpoint's card. `test_resultados` E94b.
- **When the engine crashes on a file with no project, the answer says
  where to go.** DelphiLSP outside a project cannot read two overloads of
  equal arity that differ only in `TArray<string>` and `string` and answers
  `-32603` (measured on 13.1; next to its `.dproj` the same unit answers).
  The `LSP-022` error now carries `LSP-036` ("outside a project; next to
  its .dproj it usually answers") when the file has no project settings;
  the two places that composed the error share one helper.
  `docs/DELPHILSP-NOTES.md` records it; `test_round16` S6/S6b.
- **Retired `settings.ini` keys are named at startup instead of ignored in
  silence**: `AllowDesktopControl` (gone in 1.0.16) and `AllowRun` (gone in
  1.1.1) in a `[Workspace.<name>]`. Each gets a WARNING line in the startup
  log that says it does nothing; a key retired later is one more entry in
  the same table. (The old `[Security]` section stays unnamed, as decided
  in 0.98.0.)
  `test_un_delphi` U2b.
- **`delphi_styles` asks the designer's shape reader whether a `.style` is
  binary.** It looked only at a leading `$FF`, so a TEXT style saved in
  UTF-16 (`FF FE`) was refused as compiled, and a raw `TPF0` stream passed
  as text. `DesignerShapeOf` (the resource header `FF 0A 00`, the `TPF0`
  stream) decides now, plus the `FMX_STYLE` signature of a compiled FMX
  style. `test_styles`.
- **`delphi_designer layout` reads a control's own properties, not its
  collection items'.** Its reader of one property had a regex of its own,
  which took the `Width` of a column (`Columns = < item Width = 999 >`) for
  the control's: a list view with no width of its own came out 999 wide and
  "outside the form". It now asks the designer's reader of a property's
  value (`TStyleDoc.ValorDe`: the object's own level, a split string whole).
  `test_layout` L10.
- **`delphi_styles lint` reads a style name the way the form reader does.**
  `StyleLookup` (in a `.fmx` and in a `.pas`) and the platform's default
  `StyleName`s were read with a regex of their own that knew neither a `#N`
  code nor a split string: `'card'#115'tyle'` was read `card` and reported
  as a lookup with no style. They go through the form's reader of a
  property line and of a literal now. `test_styles`; `test_paisaje` keeps
  the regex out.
- **`delphi_styles set` refuses a list or a binary block left open**
  (`('a', 'b'` or `{ 0102`): the value's grammar took anything that started
  with `(` or `{`, and wrote a style the IDE could not open. `test_styles`.
- **`delphi_config set-profile` judges a profile name by the gate's rule**
  (letters, digits, `_`, `-`, at most 64 - PAS-015). It had a regex of its
  own that let a dot through, so it pinned in the `.dproj` a profile that
  `delphi_build profile=` then refused; `delphi_paserver remove-profile`
  had the same copy behind the gate. Both ask the gate's one judge now
  (`BadProfileName`), and PAS-031, the message that promised the dot, is
  retired. `test_sdk`; `test_paisaje` keeps the judge in its home.
- **A name given as a form literal is read the same way everywhere.**
  `delphi_designer set Name=` (and `insert` with a name) took the quotes off
  by hand, so `'Btn'#83'i'` - a name the way the IDE writes it - was refused
  as an invalid identifier; `delphi_styles clone` took the name as it came
  and refused its quotes, while `delphi_styles set StyleName` read the
  literal. The three read it with one reader now (`NombreDeValor`: the
  form's literal reader, or the value as it is). `test_designer_edit` V7,
  `test_styles`.
- **A form in a package is no longer judged as a console program's.**
  `delphi_create` of a form in a package said "that project is a CONSOLE
  one" (CREATE-016), and registering it announced an `Application.CreateForm`
  it did not write, plus a CFG-046 about a `.dpr` the package does not have.
  A package's framework now comes from its `requires` (`vcl` or `fmx`): an
  FMX form in a package that requires `vcl` is refused like in a program,
  and a package gets neither the console note nor a `CreateForm`. The main
  source of a `.dproj` - its `.dpr`, or the `.dpk` of a package - is
  `DprDe` for everyone (the build, `delphi_test`, the scaffold and the unit
  registrar, which was the only one that knew the package), and the
  `requires` clause has one reader (`ClausulaRequires`). `test_scaffold`.
- **`delphi_styles` compares style names the way FMX does.** FMX's style
  indexer keys a `StyleName` by `ToLowerInvariant`, so `BOTÓN` and `Botón`
  are the same style to whoever looks it up; `clone`, `set` and the child
  paths compared with `SameText`, which folds only ASCII, and cloned
  `BOTÓN` next to `Botón` as a new style. One key now (`ClaveDeEstilo`) for
  finding a style, its children, the lint's duplicates and lookups, the
  platform's default names and `view`'s filter. `test_styles`.
- **`delphi_styles set` writes a string value the way the IDE does**, as
  `delphi_designer set` already did: accents as `#N`, and a long one in
  pieces of 64 on the lines below - it went in raw, and one of 4,095
  characters or more on a single line the IDE cannot read. The designer
  does the same now for a literal given to a property whose type it does
  not know as a string. `test_styles`.
- **A product placed on an `out=` goes through one writer, which asks the
  gate when it writes.** `delphi_adb logcat` wrote its dump after up to 55 s
  of adb without asking the gate again, `delphi_package` placed its zip the
  same way, and the captures (adb, preview, desktop) were moved with a
  delete and a move, with no retry. `ColocaProducto` / `ColocaContenido`
  (`Lsp.Patch`) now ask the gate for the folder and the file under the
  write lock, from the question to the rename; seal what was there (and
  drop that seal when the replacement fails); replace through a temp beside
  the destination and `AtomicWrite`'s rename with its retries; and never
  leave the product, the temp or the folders created for it behind.
  `logcat` refuses at the entry what that writer would refuse at the end (a
  folder named like the file, a read-only file, a path too long for its
  temp), and `package` says a read-only zip before packaging. PKG-002 is
  retired: the cause comes from the system's rule or from the gate. The zip
  in progress takes the writer's temp name, so packaging skips any call's
  intermediate, not only its own. `test_deploy_adb`, `test_escritor_guardado`.
  `ColocaContenido` itself threw on every call (`GetDirectoryName('')`
  raises in the RTL), so `logcat out=` placed nothing; it showed up while
  giving it a second user, and it is fixed in its core.
- **`delphi_designer delete` points `usesInCode` at the unit as it is left.**
  The lines came from the unit before the delete, and removing the
  component's field (and its empty handlers) above a use moved it: the
  agent went to the wrong line (measured by Hermes). They are listed again
  on the unit that remains. `test_designer_edit` V11.
- **`delphi_designer` says where an FMX control's place really is.** In FMX
  `Left` and `Top` are streamed by `TComponent` - the designer's position of
  a non-visual component's icon - so `set Left` on a control wrote a line,
  answered fine and moved nothing (measured by Hermes). `set` refuses it now
  naming `Position.X` / `Position.Y` (DSGN-118), and `lint` warns of such a
  line in a control. `test_designer_edit` F1b.
- **`preview` lists and draws a non-visual component that has no position.**
  The renderer skipped every component without a design position, so one
  with no `Left`/`Top` was neither drawn nor listed, while the answer said
  `nonVisualDrawn: true` (measured by Hermes). Only what lives inside
  another component (a menu item, an action, a field) is skipped now; the
  rest goes to 0,0 as in the IDE, and `nonVisualDrawn` says what was drawn,
  not what was asked. `test_designer_preview` P7b.
- **`preview state=` reads a named integer the way the form loader does.**
  `state=Panel1.Color=clRed` failed with DSGN-061 (a variant cast error):
  the renderer set the text through RTTI. A name for an integer type
  (`clRed`, `crHandPoint`, `claRed`) is now resolved by the reader its type
  registers, as `TReader` resolves it in a form. `test_designer_preview` P3.
- **DSGN-093 shows everything a `TAlphaColor` takes, whatever the value.**
  For a value that was not a name (`'rojo'` in quotes) it listed only the
  `cla...` names; for an open list like `TAlphaColor` it now also shows what
  its reader takes (`xFF00FF00`, the `cl` forms), as it already did for a
  wrong name (measured by Hermes). `test_designer_edit` F2.
- **`delphi_designer lint` judges a value's type the way `set` does.** It
  checked that a property exists and that an enum member is valid, but
  said CLEAN of `Color = 'hola'` or `Opacity = 'hola'`, which keep the form
  from loading. It now asks the same judge `set` asks before writing (a
  number, a string, a whole number or one of its named constants), and
  what that judge cannot know goes to the notes. `test_designer_edit` F1c.
- **`insert` and a rename in an inherited form see the ancestor's
  components.** A component of the base form that the inherited one does
  not change is written neither in the inherited `.dfm` nor in its class,
  so its name looked free: `insert TButton` in a `TForm2 = class(TForm1)`
  picked `Button1`, and the form raised `EComponentError` when created. The
  published fields of the project's ancestors (the form's folder, up the
  chain) count now, and a refusal says which ancestor has the name.
  `test_designer_edit` R11b.
- **The Windows desktop node reads a lone digit as its key.** Run by hand,
  `tecla 5` sent virtual-key code 5 (a mouse button), since a number was
  taken as a code; a single digit is now its own key, as a letter already
  was, and a number of two or more digits stays a virtual-key code. (The
  server already refused a digit with DESK-010.) Not measured live: it
  would send keystrokes to the operator's desktop.
- **A settings.ini saved as UTF-16 big endian stops the server, and says
  why.** The Windows ini reader does not read that encoding, so no section
  was seen: the server started without its `[Server]` port and bind IP and
  without a single workspace, said nothing, and added its `DelphiVersion`
  line to the file in another encoding. It now refuses to start, like a BOM
  in front of a section, and the message says to save the file as UTF-8
  without BOM or as UTF-16 little endian, which is read and written as
  before. The check reads the file once and no longer fails while an
  editor holds it open, and the `DelphiVersion` writer refuses an
  unreadable ini by itself. `test_un_delphi` U11d, with U11e as the
  little-endian control.
- **`delphi_designer set` no longer writes a path through a reference.**
  With `PopupMenu = PopupMenu1` in a button, `prop=PopupMenu.AutoPopup`
  was written into the button's block and answered OK, and `lint` called
  the form clean - but the form loader reads that line before references
  are resolved, the property is still empty there, and the form does not
  load. `set` refuses it now (DSGN-119) and says where it belongs
  (`component=PopupMenu1 prop=AutoPopup`), and `lint` warns about such a
  line. A sub-component, written as sub-properties by the IDE
  (`EditLabel.Caption` of a `TLabeledEdit`), is not a reference and is
  written as before. Measured: not one of 4,429 text forms here and in the
  RAD Studio samples has both lines in a block. `test_designer_edit` V10d.
- **`to-binary` says why a form with a non-ASCII name stays text.** A
  component, class or property name with letters outside ASCII made the
  RTL's form parser fail, and the answer was its bare `EParserError:
  Identifier expected on line 3`. The compiler does read such a name (it
  stores it as UTF-8, measured), so the refusal (DSGN-120) now names it
  and its line and says to keep the form as text or rename it.
  `test_designer_binary`.
- **A text form with no BOM is read as ANSI, the way the compiler reads
  it.** dcc, the IDE's form parser and the renderer read a `.dfm`/`.fmx`
  without a BOM in the ANSI code page (measured in the bytes of a built
  exe: a caption with an accent saved as UTF-8 without BOM runs as
  `AcciÃ³n`); the IDE calls that encoding "Text Form" and saves a typed
  accent as one raw byte of that page (CP1252 there, measured by the
  operator). The server
  detected such a file as UTF-8 whenever its bytes were valid UTF-8, so
  `delphi_read`, the designer commands, `to-binary` and the search showed
  and converted another string than the one that runs. The one detector
  now takes whether the file is a form (one predicate, `EsRutaDeDesigner`,
  written by hand in nine places before): a form without BOM is ANSI - the
  machine's code page, below -, the bytes already there stay as they are,
  and a new accent goes in as the IDE writes it. A form with a BOM is read
  as before. `test_designer_binary`.
- **A CP1252 file with one of the five bytes the code page leaves undefined
  can be edited.** Windows reads 81, 8D, 8F, 90 and 9D as U+0081... and
  writes them back to the same byte, but the encoder refused them: a file
  holding one refused EVERY edit, on any line, naming a character the agent
  never typed (EDIT-078). With forms now read as ANSI, that took in any
  UTF-8 form without BOM with an accented A or I (C3 81, C3 8D), a closing
  quote (E2 80 9D) or Cyrillic text. The encoder now writes back what the
  codec gives when it reads each byte. `LspTests.Encodings` (all 256 bytes
  round-trip), `test_designer_binary`.
- **`inline` is a boolean in the schema of `delphi_designer`,
  `delphi_desktop` and `delphi_adb`**, true when it is not sent; it was a
  string in the same tool as the boolean `nonvisual`, and a client that
  validates against the schema refused a JSON `false`. The text values
  `"true"` and `"false"` are still read, for a client with the old schema
  cached; `"0"` and `"no"` are refused now, like any other boolean
  (SYS-016). `test_designer_preview` P3b.
- **A settings.ini that exists and cannot be read is said, and nothing in
  it is in force.** Held open exclusively by another process, or with no
  read access for the server's account, it was read silently with whatever
  the Windows ini reader returned - nothing. The server now reads nothing
  from it (no workspace, so every token is refused; with no workspace
  token HTTP binds only to 127.0.0.1 unless `DELPHI_MCP_BIND_IP` says
  otherwise), says why at startup and in `delphi_workspace`
  (`server.settingsUnreadable`, with the system's reason), and does not
  write its `DelphiVersion` into it. A stdio process started with a token
  admits nothing (GUARD-030): the workspace of that token may be in the
  file, and it used to fall into the trusted local mode. A file another
  process holds open with delete access and full sharing is read as
  before - the Windows ini reader reads it. `test_un_delphi` U11f, U11g.
- **`delphi_edit`: indentation does not count in an anchor, as its
  description says, and `occurrence` counts the lines an agent counts.** A
  line matched when it ENDED with the anchor, so the anchor's own
  indentation worked as a minimum: with three `X := 1;` lines indented 2, 4
  and 6 spaces, occurrence 2 of the 4-space anchor was the 6-space line, and
  a batch wrote the wrong line answering APPLIED (measured). Both sides are
  now compared without their indentation (spaces and tabs) and with the end
  exact, as before; `delphi_textedit` already counted that way. An anchor
  that only its indentation made unique is now refused as ambiguous, with
  its lines, instead of matching. And when an anchor that CARRIES
  indentation picks, by `occurrence`, a line indented otherwise, the batch
  is refused (EDIT-121) naming that line and the matching ones indented as
  the anchor, each as `line N = occurrence K`, so the answer is that
  `occurrence` (it counts the file as it was before the batch and follows
  the lines earlier entries move) - the indentation is never a silent
  tie-break, in `delphi_edit` and in `delphi_textedit` alike. EDIT-094 now
  says the end of the line counts. `test_round34` B7-B10.
- **In a batch, the `atline` of a block anchor is honoured.** It never
  reached the block engine: without `occurrence` the block had to be unique
  anyway, and with it the block was counted on the file as the batch had
  already changed it - the first block was written, answering APPLIED.
  Now `atline` wins, as it does for one-line anchors. `test_round34` B7d.
- **The first non-ASCII character of a pure-ASCII Delphi source is written
  the way the compiler reads it.** Such a file has no encoding to keep,
  and the server wrote the new character in the IDE's configured encoding
  - with UTF-8 configured, UTF-8 WITHOUT a BOM, which dcc reads as ANSI
  (`AcciÃ³n` in the running program). Now it does what the IDE does when
  it saves (measured by the operator): ANSI when every new character
  fits, UTF-8 with a BOM when one does not. For `.pas`, `.dpr`, `.dpk` and
  `.inc` (dcc reads each include by its own BOM, measured) and every writer
  - an edit, a block, an insert, a changeset; a file that already has an
  encoding keeps it. A NEW unit goes in the IDE's encoding, and in UTF-8
  with a BOM when that is ANSI and its content does not fit (it was
  refused). What counts is the file as it was
  before the CALL, so a batch or a changeset gives the same file in any
  order (one adding an accented vowel and then an Omega was refused, the
  reverse order was written, and a changeset's commit refused what its
  preview had accepted). The designer asks the same writer: a component
  name with an accent in an ASCII unit was refused (DSGN-111) by the IDE's
  setting, and the name the IDE gives in an insert without one (a class
  with a non-ASCII letter) was never checked. A file the server wrote
  earlier in UTF-8 without a BOM, accents
  included, has an encoding now and keeps it: re-save it from the IDE with
  a BOM if the compiler shows its accents wrong. `test_delphi_patch`,
  `test_designer_edit` R17, `LspTests.Encodings`.
- **A file whose bytes do not come back the same in its encoding is never
  written back - and is read.** A UTF-8 BOM over a CP1252 body, a damaged
  UTF-32 or UTF-16. Such a file could not be read or searched (SYS-006),
  and its writers failed (SYS-006, SYS-009) - except a UTF-16 file with a
  stray last byte, which `delphi_edit` wrote back without it. Now it is
  read, its bad bytes as U+FFFD, and `delphi_read` says so (READ-007,
  naming the first line that does not fit and, in a UTF-8 file, how that
  line reads in ANSI); and one question every writer asks refuses to
  write it back (EDIT-038): `delphi_edit`, `delphi_textedit`, the designer
  commands (`to-binary` too), `delphi_changeset`, `vault_append`,
  `vault_patch` and the rest. EDIT-038 only guarded `delphi_edit`'s entry,
  and blocked restoring such a file. A changeset that deletes such a file
  and creates it again goes through (it failed with SYS-009).
  `test_delphi_patch`, `test_vault`, `test_designer_binary`,
  `LspTests.Encodings`.
- **No writer leaves a file that would be read back in another encoding
  than it wrote.** Some pairs of characters are, in ANSI, the bytes of
  one UTF-8 character - `Ã³` is a UTF-8 `ó`, and so is an accented capital
  followed by a curly quote - and a file whose high bytes all formed such
  pairs was read back as UTF-8, with other characters, by the server and by
  the IDE (which detects UTF-8 without a BOM). A source with no encoding yet
  gets UTF-8 with a BOM in that case; any other file is refused (EDIT-122).
  The mojibake warning (EDIT-083) stays for the rest. A file that already
  had an encoding keeps the one it had when the call began, even if an
  earlier edit of the same batch removed its last accent (it ended in UTF-8
  without a BOM, by order). `test_delphi_patch`, `LspTests.Encodings`.
- **A binary form with a non-ASCII component name is read whole.** Its
  conversion to text kept, inside the text, the UTF-8 BOM the RTL writes
  for such names, so the designer commands found no root object
  (`class: ""`). `to-text` writes it with the BOM, as the IDE saves it.
  `test_designer_binary`.
- **EDIT-080 no longer calls a UTF-8 file with a BOM "pure ASCII".** The
  note that a file had no encoding to keep counted high bytes without the
  BOM, so a BOM over ASCII text got it when its first accent was written.
  `test_delphi_patch`.
- **UTF-8 is detected strictly, as RFC 3629 defines it, by the RTL's own
  check.** The server had a hand copy of it that let overlong forms,
  surrogates and values past U+10FFFF pass as UTF-8, so a CP1252 file
  whose only high bytes looked like one (`à€€`) was read as UTF-8 and could
  not be read at all. It asks `TEncoding.UTF8.IsBufferValid` now, the check
  `TFile.ReadAllText` uses to choose between UTF-8 and ANSI: valid UTF-8 is
  UTF-8, anything else is ANSI, as the IDE and the compiler read it - also a
  UTF-8 file with one bad sequence. `LspTests.Encodings`, `test_delphi_patch`.
- **A UTF-32 file is read and edited in UTF-32.** The IDE offers it when
  saving a source (the compiler does not compile it, F2438); its
  little-endian BOM starts like UTF-16's, so it was read as UTF-16 with a
  NUL between letters, and the big-endian one as binary. And a settings.ini
  saved in UTF-32 does not start, like one in UTF-16 big endian: the
  Windows ini reader sees no section in it (measured). `test_delphi_patch`,
  `test_un_delphi` U11h.
- **ANSI is the machine's code page, not CP1252.** The server read and
  wrote every source without a BOM that is not UTF-8 in CP1252, hard-coded,
  while the IDE and the compiler read it in the machine's ANSI code page
  (measured: `E1 C3 A1` compiles as `áÃ¡` here and as `бГЎ` with page
  1251), and two other places used the machine's page (`to-binary`, the
  style check). On this machine both are 1252 and nothing changes; on a
  Russian, Greek or Polish Windows the accents of every such source were
  read and written in the wrong page. There is now one ANSI, measured where
  the server runs (`TEncoding.ANSI`'s, `GetACP`), and whether a text fits in
  it is asked of its codec: Windows silently writes an Omega as `O` in 1252
  and an `é` as `e` in 1251, and the round trip catches it, on any page,
  one byte per character or several. The encoding is reported as
  `cp<page>` (`cp1252` here). A project's `DCC_CodePage` is not read: the
  encoding is decided per file (a BOM wins over it, measured), and none of
  the 3,258 projects on the author's machines sets it; if one set it to
  another page, the compiler would read that project's ANSI sources in it,
  unlike the IDE's editor and this server. `LspTests.Encodings`,
  `test_paisaje`.
- **The help is read in its own character set, not the machine's ANSI.**
  A page is UTF-8 when it says so (its BOM or its meta) and Windows-1252
  otherwise - how HTML reads the `windows-1252` the RTL's 20,034 pages and
  TeeChart's 69 declare, and the `iso-8859-1` of Indy's 12,407, which carry
  1252's curly quotes (all measured) - so it reads the same on any Windows;
  it used the server's ANSI, hard-coded as CP1252. A search of a UTF-8
  index looked for its words in CP1252 bytes. `LspTests.Docs`.
- **A source in UTF-8 without a BOM says what the compiler will do with it
  (READ-008).** The IDE shows its accents right, but the compiler reads a
  source without a BOM as ANSI unless the project sets
  `DCC_CodePage=65001` (both measured), so its accented literals and names
  reach the program as mojibake. `delphi_read` says so, with the IDE's way
  out: open it and save it, and the IDE writes it as UTF-8 with a BOM. The
  server keeps its bytes as they are. `test_delphi_patch`.
- **A text form in UTF-16 or UTF-32 does not compile, and `lint` and
  `preview` say so (DSGN-121).** The IDE can save a form that way, but the
  compiler refuses it (RLINK32, E2161, measured with all four). `preview`
  still draws a UTF-16 form; a UTF-32 one is refused before the renderer
  starts (DSGN-122) - its parser took it for UTF-16 and failed with a
  syntax error that did not say why. `test_designer_binary`,
  `test_designer_preview` P1u.
- **An `<Import>` of a file outside the workspace is refused, even a
  harmless one.** The build's hazard scanner read every file a `.dproj`
  imported, wherever it was, and when it found no execution task the build
  went ahead and msbuild loaded that file from outside the roots. A file
  that is not one of the IDE's own imports is now scanned only inside the
  roots (or the read-only library zone), and one from anywhere else is
  refused (`BUILD-017`, "an <Import> of a file outside the workspace").
  `test_build_imports` (`fuera`), red against the previous binary, which
  built the project.
- **A mailbox that is a link to somewhere else is neither delivered nor
  deleted.** `delphi_messages` read the mailboxes by itself: with
  `messages\<agent>` a junction to a folder outside the server's home,
  `check` listed that folder's notes and `read` delivered them and DELETED
  them - a delete outside the roots through a link (only someone who can
  write next to the exe could plant it). The mailbox is now read through
  the read gate, by its real path, and the answer is `GUARD-034`.
  `test_messages`, red against the previous binary.
- **The folder of the IDE's SDKs is taken from the SDKs it has registered,
  as documented.** That step never found anything: each SDK's key was
  opened with a path that `TRegistry` reads as relative to the key already
  open, so the server always fell back to the default folder (the right
  one on a default installation, which is why nothing failed). The SDK
  Manager's sysroots are read by one reader now.
- **What the server writes for itself goes through one gate, and never
  behind a link.** Its cache, the reports, the vault, its temp folder and
  what it keeps of the IDE were each written their own way. With a junction
  inside the cache folder the designer tables were written behind it,
  outside the roots (`test_puerta_escribir` C1, red against the previous
  binary, whose tables landed in the victim folder); a report whose folder
  is a junction is now refused before anything is created, the folder and
  the reserved name included (R1). Where a place is judged by its real
  path (the vault, the IDE), a write is judged by the real path of its
  FOLDER, where the temporary file and the rename happen: a vault folder
  that was a junction out, with a link there back into the vault, passed
  the gate on the file's own real path and the temporary file, with the
  note in it, was created outside (`test_vault` 9-bis c); and a path that
  is itself a link is neither written nor deleted. The vault's seed for an
  empty folder whose `projects` was a junction created `example-project`
  behind it and stayed half-seeded for good: every note is now asked first
  (`test_vault` 13). What the server deletes of its own - the temp files of
  `remote-run` and `delphi_git`, a read message, the designer's old
  tables - goes through the same gate (`BorraFichero`): it deleted by hand,
  and behind a junction it would have deleted outside. A cache that cannot
  be replaced (another thread is reading it) is kept only when it already
  says the same; a stale one was kept silently. A path too long for the
  whole-or-nothing writer is refused before anything is written
  (GUARD-028).
- **A vault note is written whole or not at all**, as decided: a file next
  to the note and a rename. It was written in place, so a failure half-way
  left the note broken; the vault's seed for an empty vault had no gate at
  all. Every write of the server by replacement - the workspace's too -
  now keeps the file's creation date (the rename left the temporary
  file's: a vault sorted by creation saw the note born again on each
  append); permissions, attributes and alternate streams are those of a
  new file in that folder, as they already were for the workspace. A note
  that is a hard link of a file outside the vault no longer writes through
  it (`test_vault` 9-bis a and b).
- **The server never overwrites or deletes a file of the IDE without a
  copy.** `get-sdk` overwrote a `<sdk>.sdk` that was already there, and
  `remove-profile` and `remove-sdk` deleted for good; now the file - and,
  for `get-sdk`, the card of its sysroot - is first copied to the server's
  cache (`ide-copias\<the original's folder>`, so the card of each sysroot
  says where it came from; the last 10 of each file are kept), and the
  answer says where (`previousSdkCopy`, `previousSdkRecordCopy`,
  `removedCopy`, PAS-058). What the server writes of the IDE goes only to
  its data folder, its SDK folder and the sysroots its SDK Manager
  registers - never to its installation, nor to a folder a `.sdk` merely
  lists: the libraries the linker asks for were copied into whatever folder
  the `.sdk`'s library path named; when the gate refuses one, the answer
  says so (BUILD-047) instead of telling to install the library on the
  target (BUILD-035). `test_sdk` checks the copies of `remove-sdk` and
  `remove-profile` byte for byte, and the purge.
- **What the engine knows about units outside the roots is not shown.**
  DelphiLSP reads, through the project's search path, units that no tool
  lets the session read. Measured against the bare engine: completion gave
  the name AND THE VALUE of a constant of a unit outside the roots, hover
  its signature and its path, signature the whole signature, definition the
  path; and a variable declared inside with a type from outside listed the
  outside members after `G.` in a file that does not even use that unit
  (completion items do not say where they come from). Now, as decided
  ("trim and deny"): the engine settings the server fabricates leave out
  the project's search-path folders the session may not read, and the
  answers say so (LSP-037: definition, hover, completion, signature,
  diagnostics); the IDE's own `.delphilsp.json` is not taken for a project
  that has such folders (the trimmed one is fabricated instead), and what
  was trimmed is part of the cached settings' name, so two sessions that
  see different things never share settings nor an engine; a definition
  that still lands outside is denied by one judge in definition, in the
  declaration chain and in hover (LSP-038); completion and signature are
  denied for a project whose `.dpr` names units outside the roots
  (LSP-039), each entry judged on its own: one entry whose path cannot be
  judged no longer hides the others (one guard for the whole list let
  completion give the value of a constant from outside, F7b), and a `.dpr`
  that cannot be read right now answers with that instead of with names.
  The IDE's library - the Library Search Path, GetIt's
  components included - is a read-only place of the gates, so the engine
  still talks about installed components with the library zone off. What
  the engine opens on its own - the target of `kind=declaration`, a
  candidate of `delphi_references` - is judged by the engine's places too,
  not by the jail: with the library zone off, `kind=declaration` of an RTL
  routine answered GUARD-002 while `definition` gave that very location
  (F8c; it did before this version too), and `delphi_references` of it
  answered LSP-014, whose causes were both false there: references judges
  "outside" with the same judge as LSP-038 now (F8d).
  `delphi_references`' LSP-014 and the new LSP-038 now name both causes (a
  unit the `.dpr` names outside the roots, or an unconfigured unit); LSP-014
  sent the agent to `delphi_definition`, which no longer shows where such a
  definition goes. `test_motor_fuera` (F1-F8d, F7b), red against the previous
  binary.
- **What the server read of a file on its own goes through the read gate.**
  The text and bytes the engine is given, and what `delphi_references` and
  `delphi_search` read, were loaded from any path they were handed - also a
  path the ENGINE gave; the jail's text reader trusted the tool to have
  checked. The build's scan of `{$I}`/`{$R}` walked the project folder with
  the RTL and crossed a junction: a source behind it with an `{$I}` from
  outside refused the build naming that source (`test_puerta_leer` L1). The
  package suggestion for an implicit import (W1033) looked into the sibling
  folders of the workspace and read - and suggested by name - the `.dpk`
  behind a junction (L2). `delphi_move` of a project whose `.dpr` names a
  unit outside the roots read that unit to re-point it: now it is neither
  read nor re-pointed, and the answer lists it among what could not be
  done (L3). An open document whose path now leads outside (the roots
  changed, or a link in its way) is closed instead of read again. The
  designer's table generator reads the components' sources, and the build
  the IDE's Android manifest template, through the gate with the IDE's
  places; `delphi_styles lint` reads its `.rc` files through the one walker.
  L1-L3 are red with both layers removed (the walker or the move's own
  question, and the jail's reader asking the gate); each layer holds the
  three alone. `test_designer_tablas` and the Android part of
  `test_deploy_adb` now run with the library zone off, where the jail no
  longer reads the installation and the place each read names is what
  decides.
- **A `.deployproj` the server generates is written as the IDE writes
  one**, UTF-8 with a BOM (measured on the IDE's own): it went out in ASCII,
  so a project name that is not ASCII came out with `?` in its `Include`.
  The owner mark of a trash copy goes through the write gate in UTF-8 too:
  an agent name that is not ASCII came out `?` and no longer matched its
  owner when the trash was purged. `test_deploy_adb`.
- **A character outside the Basic Multilingual Plane (an emoji) that does
  not fit a file's code page is refused by its own name.** The refusal named
  only its high surrogate (U+D83D) and offered that half as a Pascal
  literal; it names U+1F600 now and offers its UTF-16 pair
  (`#$D83D#$DE00`) or `Char.ConvertFromUtf32` - `ChrW` stops at `$FFFF`.
  `test_resultados` E148b; `LspTests.Encodings` checks with the compiler
  that the pair it offers IS the character.
- **READ-008 only when the accents are in what the compiler reads.** A UTF-8
  source without a BOM whose accents were only in comments got the note,
  though the compiler puts nothing of a comment in the program; the one
  Pascal lexicon decides now - the code, its strings and its directives (the
  path of an `{$I}`, which the compiler reads in ANSI too). `test_delphi_patch`.

### Internal

- **Batteries that could pass for the wrong reason, mended** (version
  reviewers of 1.18.0). `test_motor_fuera` asked only for the absence of
  what must not leak, so a timeout or an engine still indexing passed: hover,
  completion and signature must now answer and say `LSP-037`, as promised, and
  the battery has a cache of its own (it took the newest engine settings of a
  folder other batteries share). `test_render_unc_118` reserved its TEST-NET
  hosts in the machine's temp folder and never freed them - red for good
  after about 150 runs -: markers older than a day are recycled. The
  absence checks that wrote the server's names by hand (`.delphi-patch-tmp`,
  `__delphi-temp`, `ide-copias`, `reports`) read them from its sources
  through `mcp_cliente`, and `test_paisaje` watches the first and the third
  in the batteries. And `test_paisaje` gains three rules on the server: a
  tree moved or copied by the RTL (`TDirectory.Move`/`Copy`, the hole of
  25-sep), a folder created outside `CrearCarpeta`, an attribute or a date
  written outside the five places that do it behind their gate, each with
  its mutant. The frozen copy of `Lsp.Guard` in `tests/fixtures`, which no
  battery read since `test_round16` generates its unit, is gone.

- **The jail rounds of 8-oct were written by Codex** (the third one and its
  run_all reds with Claude Opus 4.8): the entries above on Git metadata, the
  configuration whitelist, signing, git's environment, remote hosts, LFS and
  the renderer's literals. New batteries `test_git_config_cerrado`,
  `test_git_lfs_118`, `test_git_lfs_sistema_118`, `test_git_repo_entero_118`,
  `test_render_jaula_118`, `test_render_unc_118`, and three manual ones that
  report instead of counting (`test_render_enlaces_118`,
  `test_render_hijos_118`, `test_render_fmx_diseno_118`), with DUMMY
  fixtures for the renderer (`src/Render/Pruebas/DUMMY`). Measured with them:
  with the helper's own watchdog off, the server's 75-second deadline stops
  the helper and the child it started (`DSGN-062`) and the server keeps
  answering; without the Job Object the child outlived it. The paths where
  the job cannot be created or assigned are not measured.
  `src/Render/README.md` shows the operator how to declare an outbound block
  rule per helper; the server never installs one.

- **One walk of a tree for several masks.** `delphi_references` walked each
  folder three times (once for `*.pas`, `*.dpr`, `*.inc`), the designer
  check of `delphi_rename_symbol` twice and `delphi_projects` twice, each
  walk with its own purge of the trash on the way, although `WalkFiles`
  takes several masks and lists each file once. One walk each now (so
  `delphi_references` meets the files folder by folder instead of every
  `.pas` first: when it stops at its cap of candidates, the ones it kept
  can differ); in
  `delphi_projects` a folder's `.groupproj` now sits next to its `.dproj`
  instead of after every `.dproj` of the tree. `test_paisaje` refuses a
  loop over masks that walks once per mask.

- **One key for the parameter marks, one walk for all of them.** The key
  `tool|parameter` of the marks map was composed by hand in four places of
  `Lsp.Guard`; it is `ClaveDeParam` now, and `MarcasDeParams` reads
  `[RutaDelServidor]`, `[RutaRelativa]` and `[Contenido]` in one RTTI walk.
  `test_paisaje` watches both homes: the key, and where a virtual unit is
  expanded (the gate, the `/files` route and the designer's exception).

- **The form renderer tells a framework class by the class it loaded.** An
  `inherited` form whose ancestor has no form file was read without a
  warning only if that ancestor was one of four names written by hand
  (TForm, TFrame, TCustomForm, TDataModule); now it is any class in the
  chains of the roots the IDE designs - the root the renderer created, the
  framework's frame and TDataModule, since a data module is loaded into the
  hidden form (rule 6; its own reviewer caught TDataModule lost in between).
  `test_designer_orden` O21 and O22, red with the check broken.
- **The Pascal grammar read by hand, declared.** `test_paisaje` now holds
  three rules for what `Lsp.PascalDecl` already reads and several places
  read again by themselves: the final `end.` (two spellings in seven
  places), a unit/program/library/package header (five readers) and the
  interface/implementation section (declared in three places: the insert
  boundary of ExecutePatch, the digest, and the five copies inside ProjectUnits that are
  one, `FinDeSeccion`; the echo of adduses and removeuses is one,
  `ClausulaReleida`). Today's copies are listed and can only shrink; a new
  one fails the battery, each rule with its planted mutant.
- **A path's canonical form is asked to Windows in one place.**
  `test_paisaje` now watches `GetLongPathName` / `GetFinalPathNameByHandle`:
  only `Lsp.Rutas` asks them (`LongCanonical`, `NombreFinal`) - two forms
  of the same root at once once made the workspace root deletable. The
  rule found one more than the inventory of 8-oct, which looked only at
  `src/Server`: the job launcher's `RutaLarga` (`McpRunJob`), declared, since
  that program travels to the target and links no server unit but
  `Lsp.ProcessLaunch`. With its planted mutant.
- **The source header has one reader.** `CabeceraDeFuente` (`Lsp.Pascal`)
  reads the unit/program/library/package header on the code view - its
  word, its name as dcc reads it with where what is written starts and
  how long it is, and where it ends, past its `;` - and the five readers
  declared above are gone (only one saw `package`, only one gave a
  position, one wanted the header on a single line). Where that changes
  what they did: `delphi_edit insert` into a `.dpr` with no uses clause
  puts the routine after a header split over two lines (it answered
  EDIT-048), and still refuses a one-line program (`program P; begin
  end.`), where it would land after the `end.`; `unit A . B;` compiles and
  is `A.B` (measured), and `create`, `add-unit` and `delphi_move` take it
  (they said the name did not match, or found no header), the move
  rewriting all that is written; a unit rename leaves only the header's
  NAME alone, so a `uses` written on the header's line follows the rename
  (whole lines were skipped); and `add-requires` on a package with no
  requires writes it before the `contains` that `FindUses` reads (in a
  one-line `.dpk` it landed after it). The `test_paisaje` rules of the
  header and the `end.` look for more spellings, and declare the class
  reader (`TLectorPas.Lee`) as the parser it is. `test_delphi_patch`,
  `test_project_units`, `test_scaffold`, each case red with its part
  undone.
- **One gate to read files** (the doors block of 1.18.0, first part).
  `LeeTexto` and `LeeBytes` (`Lsp.Patch`) read a file only if it is in one
  of the PLACES the caller names - the workspace (the jail's own read
  rule), the IDE's places, the server's home, its temp folder, the vault -
  judged by its real path, and decode it with the one detector. The
  server's own home and temp folder are judged by their long form with no
  link on the way instead: under the desktop app's MSIX virtualization a
  NEW subfolder of a real folder in AppData resolves to the package's
  LocalCache (measured), which is not a link, while a junction is. 41 reads
  went their own way (the inventory of 9-oct-2026): the `.dproj` and its
  imports, the IDE's `.sdk`/`.profile`/`rsvars.bat`, `System.pas`, the
  designer's tables, the fabricated engine settings, the token `.ini` of
  `delphi_styles`, the vault's notes and bootstrap, the mailbox, what a
  test leaves in its container, what a target sends back. The IDE's places
  are its installation, its user data folder, its SDK folder and the
  sysroot of every SDK it has registered, in its SDK Manager (Android's
  live in the catalog repository) or in a `.sdk` of its profiles folder
  (what msbuild and paclient read); anything else of the IDE is refused,
  as decided. The sysroot of a `.sdk` is resolved by one reader now (three
  places resolved it by hand). The
  server's home as a place is its cache, the mailboxes and the reports -
  never the exe's folder, where `settings.ini` lives. What still reads on
  its own is declared, with its reason, in a new `test_paisaje` rule
  (`settings.ini`, `.git\HEAD`, the bytes `delphi_fetch` serves, and the
  programs that are not the server), and can only shrink.
  `LspTests.Rutas` covers the places that do not depend on the machine,
  with a junction in the temp folder; the places judged by their real path
  are measured through the server, because inside `delphi_test`'s container
  `GetFinalPathNameByHandle` refuses a drive-letter answer (access denied;
  only the NT form answers) and a link cannot be resolved there.
- **One gate to write files** (the doors block, second part).
  `EscribeTexto` and `EscribeBytes` (`Lsp.Patch`) write what the server
  composes - not a file being edited in its own encoding, which is
  `PatchSaveText` - into ONE place: whole or not at all, in the encoding of
  its format through the one encoder, with the copy the place asks for.
  The workspace is `AtomicWrite`; the vault, its real path (the vault tools'
  own "inside the vault" is now this question); the server's home and temp
  folder, their long form with no link on the way; the IDE, its data and SDK
  folders and its registered sysroots, copying first what it overwrites.
  The cache writer moved from `Lsp.Casa` to the gate. `BorraFichero` is
  its delete, with the same places (the workspace deletes to its trash and
  is refused there, GUARD-035). Two new `test_paisaje` rules declare what
  still writes or deletes on its own (the jail's walkers, moves, trash and
  undo, the vault copies, `settings.ini`, the log, the upload by chunks,
  the three findings left for the jail point, and the programs that are
  not the server), and can only shrink; the write rule sees `CreateFile`
  for writing, every write mode of a stream (on its own line too), the
  ini, zip and rename writers and the public copy of the jail.
- **The read rule sees bytes too** (the doors block, third part).
  `test_paisaje`'s rule for reading without the gate now also sees the byte
  readers - `TFile.ReadAllBytes`, `OpenRead` and `Open`, a file stream not
  opened to write, `FileOpen`, `CreateFile` for reading: 36 measured. The
  vault's note editor and the unit inspector read through `LeeBytes` now;
  the rest is declared with its reason (the sniffers that read a header,
  the jail's edit engine, the whole-or-nothing photo, the log, the server's
  own binaries, `settings.ini`, the programs that are not the server) and
  can only shrink. The write rule sees `TFile.Open` for writing. The IDE's
  library is a place of `Lsp.Lugares` (`LugaresDeLaBiblioteca`), as the
  IDE's own places are: the gate walked the raw list.
- `EscribeBytes` into the workspace takes the jail's write lock, like its
  other writers (nobody calls it yet), and the binary a target gets from
  `node\` (`McpRunJob`, `McpDesktopNode`, with or without `.exe`) has one
  namer instead of three hand-written names.

- `Lsp.Guard` is split by families, one family per commit and moves only:
  not a line of logic changes, and the suite runs whole after each one. The
  dependency graph of its routines decided the order, not the plan: a
  family goes where nothing it uses is above it.
  - The canonical forms of a path go to **`Lsp.Rutas`**, below everything:
    `LongCanonical` (8.3 aliases undone), `RealPath` (links followed),
    `FormaLarga` (the form places are compared in) and `EnLugar` (THE "is
    it in that place" comparer). They use nothing of the jail, and the
    jail, the settings reader and the server's home all compare places
    with them.
  - The namers of the server's home go to **`Lsp.Casa`**: its folders
    (`ServerDir`, the temp folder, the caches under LOCALAPPDATA), the
    unique names it makes for one operation (`FragmentoUnico`,
    `SelloUnico`, the download folder), its mutex names and `Slug`. What
    is done WITH those folders - the agent's deliverables, the startup
    purge, the instance presence - asks the gates and stays in
    `Lsp.Guard`. `Lsp.Sandbox` no longer uses `Lsp.Guard`: the cycle
    between the two is gone.
  - The settings reader goes to **`Lsp.Settings`**: `settings.ini` and the
    environment, loaded once, and what holds for THIS session (the active
    workspace, its roots, references, permissions and vault, the
    credentials, read-only mode, the session and engine limits). Nobody
    outside it sees its variables or the table of workspaces, which holds
    the tokens: four gates of `Lsp.Guard` that read those variables by hand
    now ask five readers of one or two lines (`RaicesDeLosWorkspaces`,
    `RaicesDelModoLocal`, `RemoteProjectsNow`, `ToolsOnly`,
    `ToolsProfileNow`), the same shape as `AgentConfinementNow`. It still
    uses `Lsp.Patch` for one encoding helper, a cycle that goes when the
    encodings get a unit of their own. `Lsp.Service` no longer uses
    `Lsp.Guard`.
  - Who is calling goes to **`Lsp.Identidad`**: the identity of each
    request (the name a client gives in `initialize`, bound to its HTTP
    session, or the stdio process's) and the session registry, with why a
    session ended. It uses nothing of the jail, only how long a session
    lasts (`Lsp.Settings`); its lock and lists are created in its own
    `initialization`, as they were in `Lsp.Guard`'s. The vendored HTTP
    server and core manager used `Lsp.Guard` only for this and now use
    `Lsp.Identidad`; `Mcp.Tools.Messages` no longer uses `Lsp.Guard`.
  - All-or-nothing goes to **`Lsp.TodoONada`**: the photo of the files an
    operation will touch (`TFotoDeFicheros`) and the wrapper that undoes it
    when something fails halfway (`FicherosTodoONada`). It is the first
    family that goes ABOVE the jail: undoing asks the write gates and uses
    the guarded writers, and nothing in `Lsp.Guard` uses it.
  - The arguments of a command go to **`Lsp.Args`**: the one splitter of an
    argument line (`TrocearArgs`, the Windows C runtime's rules) and its
    inverse (`EnComillas`), the gates on what reaches a git or launcher
    command line (`GitArgDenied`, `GitRemoteDenied` with its host reader
    `GitUrlHost`, `ShellArgDenied`), the query half of `delphi_git`
    (`GitCommandIsQuery`), the namer of a commit's message file and
    `PrimerTrozo`, the one piece of the jail they used (Patch, Scaffold,
    RemoteRun and git call it too). They go BELOW the jail, which asks
    them, and they ask only `Lsp.Settings` (the declared remotes) and
    `Lsp.Casa` (the server's temp folder).
    `GitArgDenied` is now in an interface: the jail's entry gate calls it
    from another unit.
  - The codecs go to **`Lsp.Codificacion`**: the encoding kinds
    (`TEncKind`), their names (`EncName` / `EncKindOf`), the BOM bytes
    (`PreambleLen`, `BomUtf8En`), strict UTF-8 (`ValidUtf8`), the decoder
    and the encoder (`DecodeBytes` / `EncodeText`, with `ECaracterNoCabe`)
    and the one ANSI codec they share (the machine's page, see "ANSI is the
    machine's code page"). They are pure: DECIDING what encoding some bytes
    are stays in `Lsp.Patch` (`DetectEnc`, which asks the IDE about plain
    ASCII), and `test_paisaje` now pins it there: nobody else reads a BOM or
    calls `GetBufferEncoding`, only the detector asks `ValidUtf8`, and every
    codec is created in that one unit. One loose detector, the renderers'
    (`DesignerAFlujo`: they do not link the unit), is declared debt that can
    only shrink; the help's, with a CP1252 codec of its own, is gone. The
    cycle between `Lsp.Settings`
    and `Lsp.Patch` is gone, and `Lsp.Docs` and `Lsp.DesignerBin` no longer
    use `Lsp.Patch`.
  - The namers of the trash join the server's home in **`Lsp.Casa`**: the
    name of its folder (`TrashFolderName`, `BACKUP_SUB`) and the owner mark
    whole - its writer (`MarcaDeDueno`), its inverse (`CopiaDeLaMarca`),
    what recognises it (`EsMarcaDeDueno`) and the format that binds them
    (`MARCA_DUENO_EXT`), which travel together or not at all. What is done
    WITH the trash (stamping, keeping) stays in `Lsp.Patch`, and
    `test_paisaje` pins the mark's extension to its one home. (Purging it
    went later to the jail, and `Lsp.Guard` no longer uses `Lsp.Patch`: see
    the trash's namers below.)
  - The IDE's macros go to **`Lsp.Discovery`**, which already reads the
    rest of the IDE (`IdeMacroVars`, `ExpandIdeMacros`,
    `IdePlatformLibraryPaths`), and the network gate `ProbeHostDenied` goes
    to **`Lsp.Settings`**, next to the list it reads (`RemoteProbeHosts`).
    `Lsp.Discovery` no longer uses `Lsp.Guard` - the cycle between the two
    is gone - and neither do `Lsp.Docs` and `Mcp.Tools.Components`. This is
    the first of four steps that take the drive mask out of `Lsp.Guard`.
  - The predicates on the SHAPE of a path go to **`Lsp.Rutas`**
    (`EsRutaAbsoluta`, `EsUnc`, `EsPrefijoDeDispositivo`), and the walk that
    rewrites a call's text arguments in place (`ReescribeCadenas`) goes to
    **`Lsp.Json`**, below the jail and the coming drive mask, which both use
    it. The note of `EsRutaAbsoluta`, which sat above another function,
    travels with it. The second of the four steps.
  - The map of the declared places goes to **`Lsp.Lugares`**: the one list
    of what the operator declared (`LugaresDeclarados`), the IDE's library
    zone (`LibraryRoots`, and `LibraryReadRoots`, the one announced), which
    places sit on a network drive letter and their network path
    (`SitiosEnLetraDeRed`), the UNC host `\\srvhost\` stands for
    (`HostUncDeclarado`), and the DECLARED form of a resolved path or text
    (`FormaDeclarada`, `FormaDeclaradaDe`, `FormaDeclaradaEnTexto`). It
    decides no access: the jail stays in `Lsp.Guard` and reads the map.
    `Lsp.Guard` no longer uses `Lsp.Discovery`. `test_paisaje` now keeps the
    raw lists of places (`WorkspaceRoots`, `WorkspaceReadOnlyRoots`,
    `WorkspaceReadOnlyPaths`, `LugaresDeclarados`, `LibraryRoots`,
    `LibraryReadRoots`, `TodosLosVaults`, `RaicesDeLosWorkspaces`,
    `RaicesDelModoLocal`, `SitiosQueNoSeTocan`) in `Lsp.Settings`, which
    reads them, and
    `Lsp.Lugares`, which walks them; the 21 routines in seven units that walk
    them on their own today are declared debt, by routine, that can only
    shrink (a home written `TClass.Method` is that method only, so one tool's
    exception does not cover its siblings). The third of the four steps.
  - The drive mask goes to **`Lsp.Mascara`**, above the map of places and
    below the jail: the virtual units both ways (`ExpandVirtualDrives` and
    `ExpandDriveValue` in, `MaskDriveText` out), the three maskers of an
    answer that carries file content (`EnmascaraSalvoContenido`,
    `EnmascaraJsonSalvo`, `EnmascaraSalvoCodigo`) with what each call notes
    (`CitaDeLinea`, `OlvidaSalidaHecha`), the namer and the one test of the
    `srvX:` form (`VirtualUnitOf`, `EmpiezaPorUnidadVirtual`) and the letters
    served (`ServedDriveLetters`). Its lock is created in its own
    `initialization`, as it was in `Lsp.Guard`'s. `Lsp.Listas`,
    `Mcp.Tools.Docs` and `Mcp.Vault.Session` no longer use `Lsp.Guard`,
    `Lsp.Guard` drops `System.SyncObjs`, and `test_paisaje` finds the `srvX:`
    form in its new home. The last of the four steps: `Lsp.Guard` goes from
    8,207 lines to 3,693.
- Five reviewers read the whole cleanup over its final state: start-up
  order and `uses`, the public surface and the jail, the texts against the
  code, the landscape, and whatever was not a pure move. No behaviour had
  changed (the entry gate and every gate of the jail arrive byte for byte).
  What they found is fixed: 22 texts that still sent the reader to
  `Lsp.Guard` for something that had moved (the credentials, the ini, the
  IDE's macros, the server's temp folder, a masker) or said something the
  code does not do, six `uses` left with nothing to use, a second name for
  the trash folder in `Mcp.Tools.FileOps`, and the raw-lists rule, which
  missed three lists. `test_paisaje` now also checks that every declared
  home still holds its format, so the declared debt can only shrink. Of the
  four homes that held nothing, three are gone, each for its own reason, and
  `FlotanteDeForm`'s stays: the rule now sees how it writes the eighteen
  zeros (`StringOfChar('0', 18)`), so a copy written the same way is caught.
- The cleanup closes with a map, in `Lsp.Guard`'s header, of where each
  family went and what stays. Seven notes that earlier moves (some from
  before this cleanup) had left above the wrong function are back with their
  own, three that said what the code no longer does are corrected (the
  header's "three layers" lists four; the content parameters are read by one
  pass, not two; a `uses` comment named a function of another unit), and
  `EnLugar` carries `RealPath`'s warning: it compares, it never decides a
  permission. Two units sat in a `uses` with nothing left to use: `Lsp.Guard`
  in the tray and `Lsp.Patch` in `Mcp.Tools.Desktop`.
- Second writers of a format, each back to its one home: the server's
  folder in the protected places (`ServerDir`, no longer
  `ExtractFileDir(ParamStr(0))`), the commit message's file name
  (`FragmentoUnico`, no longer a GUID of its own), the paclient a battery
  points to (`PaclientDeEntorno` in `Lsp.Settings`, the one reader of the
  configuration), the `srvhost` of a masked network path (one constant,
  `HOST_VIRTUAL`, for the masker that writes it and the expansion that reads
  it back), the host lists of `GitRemotes=` and `RemoteHosts=` (one splitter,
  `HostsDeLista`, for the git gate and the probe gate), and the command line
  of `McpRunJob`, which had a twin of `EnComillas`: the splitter
  `TrocearArgs` and its inverse move to `Lsp.ProcessLaunch`, next to the
  launcher, where the job launcher already reaches them. `test_paisaje`
  watches the server's folder and `srvhost`, each with its mutant.
- The connection fields of a profile (`Profile_host`, `_port`, `_platform`
  and the password paclient already encrypted) are read in one place,
  `CamposDePerfil` in `Lsp.Discovery`, from whatever `.profile` or `.sdk`
  text the caller holds; they were read by hand in twelve places of three
  units (`HostDePerfil` now reads with it). `test_paisaje` keeps them there.
- `test_paisaje` refuses, in our units, two overloads of equal arity that
  differ only in `TArray<T>` and `T`: DelphiLSP outside a project crashes on
  the whole unit (measured), and agents read loose copies. Its first pass
  found one: `TStyleDoc.SetProp` with a string and with pieces - a loose
  copy of `Lsp.Styles.pas` got `-32603` (measured tonight; renamed, it
  answers). The pieces version is now `SetPropTrozos`.
- The trash gets one namer per format. Its folder next to a file was
  composed by hand in three places of `Lsp.Patch` (`TrashDayDir`, the
  pre-edit copy, the restore), the day folder was recognized by two regexes
  of its own and the purge composed its limit with its own date format, and
  `Mcp.Tools.FileOps` built the mask of the owner marks by hand. They are
  now `CarpetaDePapelera`, `TrashDayDir`, `NombreDeDia` with its reader
  `EsCarpetaDeDia`, and `MascaraDeMarcas`, all in `Lsp.Casa`, whose folder
  and mark constants stop being public. The purge on pass and the purge of
  a trash (`PurgaAlPasar`, `PurgeOldBackups`) move to `Lsp.Guard`, where the
  gates and the walker they use live: `Lsp.Guard` no longer uses
  `Lsp.Patch`. `test_paisaje` keeps the day's name and its reader in their
  homes. The purge on pass already had its checks (`test_round47` P1-P3,
  through `delphi_list`); `test_round31` R9 adds, through `delphi_search`,
  that a folder that sorts before the limit but is not a day survives.
- The inverses of two namers get written once: the forms a unit can have
  (`DesignersDeUnidad` in `Lsp.Patch`, next to the list of designer
  extensions: the `.dfm` and the `.fmx` beside it, in that order) for the
  delete, the move, its twin finder and the project's unit reader, which
  composed them extension by extension in five places; and the `.dpr` of a
  `.dproj` (`DprDe`, next to `DprojDe` in `Lsp.Dproj`) for the build's
  directive filter, `delphi_test` and the scaffold's reader. `test_paisaje`
  keeps both out of hand-written code.
- The indentation of a level of a text designer (two spaces per level, as
  the IDE writes it) is `SangriaDeNivel` in `Lsp.DesignerBin`; four places
  of the styles and the designer's editor computed it by hand, and
  `test_paisaje` keeps it there. Likewise whether a designer is FMX
  (`EsDesignerFmx` in `Lsp.DesignerForma`, by its extension), asked by hand
  in seven places in three spellings.
- The rest of the low findings of the second 1.17.0 review: layout asks the
  object line's reader whether a control is inherited instead of a regex of
  its own; the FMX frame template writes its size with the property-line
  composer; "is this value a list, a binary block or a collection?" is
  `EsValorDeBloque` (three places asked it by hand); the renderer's
  `NONVISUALS=` items are split by the protocol's reader (`TNoVisual`), not
  by the tool; `test_designer_binary` checks the resource header `FF 0A 00`,
  not the first byte. `test_paisaje` gets a rule for each home of the form
  reader that had none (the line grammar, a literal read by hand, the
  number grammar, a property line composed by hand, the block value, the
  property-line regex, binary by the first byte, the edit distance, the
  most similar name, the class chain of the table), and the object-line
  rule now sees a single keyword too.
- The renderer and the server converted a binary form to text each with
  its own call to the RTL, and read the root line differently (the
  renderer took the first object line found anywhere, a nested one too).
  `DesignerBinarioATexto` and `LineaRaizDeDesigner` in `Lsp.DesignerForma`,
  which both link, are the one converter and the one root reader;
  `test_paisaje` keeps the RTL conversions in their homes.
- The form renderer, run by hand, drew the non-visual components by default
  (`--nonvisual on`, like the IDE designer) while `delphi_designer preview`
  defaults to off; the server always passes it, so agents saw no
  difference, but one switch had two defaults. The renderer defaults to off
  now; its README and usage text say so, and its DUnitX case asks for `on`
  (RenderTests 13/13).
- `test_paisaje` looks at the batteries too: the trash folder's name (63
  places), its day (6) and its "deleted" drawer (7) were written by hand in
  `tests/*.py`, and a check of ABSENCE with a hand-written name stays green
  if the server renames it. They come from the server's own namers now
  (`mc.PAPELERA`, `mc.CAJON_BORRADOS`, `mc.dia_de_papelera`), and three
  rules with their mutants keep them there. The two binary forms written by
  the IDE and the RTL reference for the literal composer (T7, T8) watch the
  form writers.
- `delphi_git` gets a unit of its own, **`Mcp.Tools.Git`**: its parameters
  and tool, the composer of its command line, its one launcher
  (`GitCorre`), the gates on remotes, pushes and the repo's configuration,
  and its answers - moved out of `Mcp.Tools.Workspace` without changing a
  line ("where is git?" was answered "in Workspace", which nobody guesses).
  Workspace's header now names the tools it really registers, and it drops
  four units only git used. The order of `tools/list` is unchanged
  (measured), and `test_paisaje` finds the git launcher in its new home.
- `test_round16` measures the symbols summary against a big unit it
  GENERATES, as it already did with the small one: the live `Lsp.Guard.pas`
  changed with this cleanup, the summary-to-tree ratio had climbed from 16%
  to 24.3% unseen since 1.13.0 (the full tree got leaner), and a frozen copy
  of a unit of the jail in the repo was a second home of that code for every
  search. The generated unit has the shape of a real one (routines with
  their notes, default values, classes with methods and properties) and no
  overloads that `DelphiLSP` cannot read outside a project. Base 27.4%,
  ceiling 30%: a red is an alarm to look at the shape of the answer.
- Fixes of the second 1.17.0 review that no check guarded get
  their checks, each run first against a build with the fix taken out: the
  event of a collection item in `check-binding`, a second root object in a
  form, a field and a handler declaration whose block comment goes on below
  (`delete`), a multi-line text that follows the name and the reference
  lines counted after it changes length (`set Name`), `1e3` and an unclosed
  string in `delphi_styles set`, and a `state=` value that names a
  component by its path inside a frame. (A write gate asked at the moment of
  placing a capture and the designer table wait outside the lock still have
  no deterministic check.)

### House rules

- **What can be measured is not hard-coded** - point 6 of "Survey the
  landscape" in `CLAUDE.md`: what a real judge can answer (the table
  generated from the source, the class loaded, the IDE's parser, the
  compiler, git, Windows) is asked of it, never imitated with a list, a
  regex or a grammar of our own; and before writing a rule of our own, name
  the judge that would make it unnecessary, or say there is none.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
