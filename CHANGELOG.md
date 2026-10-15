# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- **`delphi_git` no longer passes on git's advice, which mostly names what
  the tool does not offer.** After a `stash pop`, git printed `(use "git
  restore <file>..." to discard changes in working directory)`; Hermes,
  validating 1.19.2, followed it, and the tree stayed dirty: `restore` here
  is always `--staged` (it undoes an `add`), and discarding a change is
  `command=stash` with its paths. It was not the only one: `commit` with
  nothing staged advised `git commit -a`, `add` of an ignored file `Use -f`,
  a merge that cannot go fast-forward `git merge --no-ff` or `git rebase`,
  a rejected push `git pull`, and every hint ended with `git config set
  advice.X false` - all written for someone typing git, and most of them
  not operations of this tool at all. Git has its own
  switch: the server now runs it with `GIT_ADVICE=0` (git 2.46 and later),
  which drops the hints and keeps the facts (`rejected (non-fast-forward)`,
  `Not possible to fast-forward`), measured with git 2.53 on `stash pop`,
  `commit`, `add`, `merge`, `pull` and `push`. The server's own notes stay
  (`GIT-008` for a merge that diverged), and so does `GIT-006` as the second
  barrier for an older git, which ignores the variable. And `restore`, which
  succeeds in silence, now says what it did and how to discard a change
  (`GIT-077`). Battery `test_git_consejos_1193` (red against 1.19.2 on all
  four, the control green).

## [1.19.2] - 2026-10-15

Nine fixes. Six come from Hermes' validation of 1.19.1 and the general
test of the edges that followed it, each one reproduced against 1.19.1
before anything was touched: `delphi_designer preview` names the root of a
form in `ignored`, and `lint` judges that root; `delphi_changeset` no
longer breaks a project by moving or deleting a Delphi file as a loose
one; a `delphi_upload` with a bad sha256 goes to the trash; `delphi_git`
finds a path written in another case; and `delphi_delete` takes a unit out
of a project in a sibling folder. Three more turned up while measuring
them. `delphi_references` and `delphi_rename_symbol` took a namesake in
another unit, or an overload, for an override, and the designer took the
first unit of the form's folder declaring a base class for the one the
`uses` names: both decided by a class's NAME what only the compiler knows,
and the engine answers both now (`Lsp.Herencia`). And `set`, which refused
a property a base class of the user's own publishes, judges it by the type
that class declares. No contract is taken away: `preview` gains a note
(`ignoredUserNote`), `rename_symbol` refuses a namesake it used to rename
(`RENAME-017`), and the changeset refuses what broke the project
(`CHSET-033`).

### Fixed

- **`delphi_designer preview` names the root of the form in `ignored`, with
  its line.** A property the loader skips on the ROOT (a `ModalResult` on a
  VCL form, an unknown one on an FMX form or a frame) came out with a name
  of the renderer's own - `TFormOculta`, `form_02BCC9C0`, `TFrame` - and no
  `line`, while the note says `line` tells where each one is (reported by
  Hermes on 1.19.1; a child came out right). In design mode `TReader` reads
  the root's name and drops it, and the renderer named the root only after
  reading, so the error carried the class of an unnamed component. The
  renderer now names the root from the file's header before reading it
  (`LeeRaiz`, shared by the VCL and FMX renderers). `test_preview_raiz_1192`.
- **`delphi_designer lint`, and the warning of `delphi_edit` on a form,
  judge the ROOT of the form.** `ModalResult = mrOK` (a `TForm` does not
  publish it) or a colour that does not exist on the root of a form said
  `LINT CLEAN`, and the edit that wrote it said nothing, while the loader
  skips them and the form does not open (reported by Hermes on 1.19.1).
  The root had been left unjudged since 1.12.0, because judging it BY ITS
  NAME took a user's `TForm1` for a demo's. `set` already judged it by the
  first class of its ancestor chain the tables know, read from its `.pas`;
  that walk now lives in one place (`ClaseDeJuezDeRaiz`) and lint asks it
  too. What a class of the user's own chain publishes (a `TBaseForm` with
  a `property Foo`) is not judged: the real class reads it and the tables
  do not know it. Measured on the 669 forms of the RAD Studio demos, the
  corpus that made 1.12.0 leave the root out: no answer changed, and an
  error planted on the root of a VCL and an FMX copy was named.
  `test_lint_raiz_1192`.
- **`delphi_changeset` no longer breaks a project by moving or deleting a
  Delphi file as a loose one.** A `move` of a unit with its form said
  `COMMIT COMPLETE` and left the old `unit` header, the `.dfm` behind and
  the `.dpr` pointing at a `.pas` that no longer existed; a `delete` left
  the form orphaned and the project listing the unit (reported by Hermes
  on 1.19.1; measured with a form unit). `delphi_move` and `delphi_delete`
  do it whole - the `.dfm`/`.fmx`, the header, the projects, the relative
  paths that cross. A changeset `move` whose source or destination is a
  Delphi file (a source, a form, a project) is now refused when it is
  staged (`CHSET-033`, naming `delphi_move`); a `delete` of one leaves the
  preview unresolved, naming `delphi_delete`, unless a later `create` of the
  batch writes the same file again - deleting and creating a unit is
  rewriting it in place, and stays valid. The `kind` description says it.
  `test_changeset_unidad_1192`.
- **A `delphi_upload` whose sha256 does not match goes to the recoverable
  trash, not next to the file.** It was set aside as `<name>.corrupt` in
  the live folder, a name composed by hand, and stayed there for good -
  also after the file was uploaded right - where `delphi_list` showed it
  as one more file and `git add .` took it (reported by Hermes on 1.19.1).
  It now goes to a drawer of its own in the trash (`corrupt`), sealed by
  the namer of every copy and through its write gate, one copy per failed
  upload; `UPLOAD-011` says where and the description of `sha256` too. A
  file in a temporary folder, where there is no trash, stays under its
  name and `UPLOAD-012` says so. `test_upload_corrupt_1192`; the batteries
  that pinned the old place (`round8`, `round9`, `resultados`,
  `cuarentena_puerta_1184`) now pin this one.
- **`delphi_git` finds a path written in another case.** With `c01.txt`
  modified, `status paths=["C01.TXT"]` answered a clean `## master`, `diff`
  said `GIT-001` "NOTHING has changed", `log` found nothing and `add`
  "finished fine" having staged nothing: every path went to git as
  `:(literal)<path>`, which matches case, in a repository whose
  `core.ignorecase` is true on a disk that does not tell case apart
  (measured from Hermes' H4-01 on 1.19.1; the cache he suspected does not
  exist, and a network drive did not reproduce it). When git says the
  repository ignores case, the paths now go as `:(literal,icase)` - git's
  own rule, measured with git 2.53 on `status`, `diff`, `log`, `add`,
  `restore` and `stash`, files and folders. `test_git_mayusculas_1192`.
- **`delphi_references` and `delphi_rename_symbol` no longer take a
  namesake for family.** A class `TFoo` declared in two unrelated units,
  two copied `TBase`/`TDer` hierarchies, or an overload `Sobre(string)`
  next to `Sobre(Integer)` came out confirmed, marked `via: "override"`,
  and `rename_symbol` was applicable across both units (measured while
  reproducing Hermes' H5-01 on 1.19.1, which was not this). The kinship
  between two classes was decided by the simple class name over the
  scanned sources, and a class counted as its own relative. The engine
  decides it now, hop by hop: the definition of the ancestor written in
  `class(...)` - the class reader notes where it is -, a class is not its
  own relative, and two classes are the same by file and line, never by
  name. The `TFoo` of a qualified header `procedure TFoo.Pinta;`, which
  the engine resolves to the method, is the class itself: it was a
  "relative", it is confirmed plain now, so a rename of the class keeps
  its headers. Namesakes are listed in `rejected`, and `rename_symbol`
  refuses them with `RENAME-017` instead of writing into the other unit.
  `test_referencias_familia_1192`.
- **`delphi_delete` takes a unit out of a project in a sibling folder.**
  With `app\P.dpr` listing `..\scratch\UDef.pas`, deleting the unit said
  `FILE-002` "no .dpr listed it" and left the `.dpr` pointing at a file
  that was gone (reported by Hermes on 1.19.1). The search for the
  projects that list a unit climbed from its folder only; the one for
  packages already looked into the folders right under each level. One
  walker for both now (`SitiosDeProyectos`), and `FILE-002` says where it
  looked. A `move` was already re-pointing such a `.dpr` through the
  relative-path fixer (`MOVE-005`) while noting `FILE-002`: it names the
  project now. `test_delete_proyecto_lateral_1192`.
- **The root judge of the designer and the inherited components ask the
  engine which class a base is.** `ClaseDeJuezDeRaiz` (the root judge of
  `lint`, `set` and the form warning of `delphi_edit`, from the fix above)
  and `NombresHeredados` (the names `insert` and `set` keep free for the
  components a form inherits) located a user's base class - `TFormMain =
  class(TBaseForm)` - by scanning the form's FOLDER for a unit declaring
  that name, and took the first one in file order, not the one the `uses`
  names. With two `TBaseForm` in the folder (measured on 15-oct, right
  after that fix: one publishing `Modo`, a namesake without it sorted
  first), `lint` refused `Modo = 1` with `DSGN-038` and `insert` named a
  new button `Button1`, the base's own field - an
  `EComponentError` when the form is created; sorted after, everything
  passed. Which `TBaseForm` a unit means is the compiler's call (its `uses`,
  the last one wins, a qualified name), so it is asked of the engine: the
  ancestor chain by DelphiLSP (`Lsp.Herencia`, the walk `delphi_references`
  uses since the entry above - one home for the three), hop by hop, and only
  when the chain leaves the unit: a form on `TForm` starts no engine. The
  base may now live in any folder of the project; without project settings
  there is no engine and the root stays unjudged, as before.
  `test_juez_raiz_motor_1192`.
- **`delphi_designer set` writes a property published by a base class of
  the user's own.** With `TFormMain = class(TBaseForm)` and a `TBaseForm`
  publishing `Modo: Integer`, `set Modo=2` on the root was refused with
  `DSGN-087` "`Modo` does not exist in TForm according to the framework"
  - false: the real form reads it - while `lint` already kept quiet about
  it (the fix of `lint` above left `set` judging the root against the
  framework only, and the point was declared for 1.20). The value is now
  judged by the type the user's class declares, with the same judges the
  framework's properties get: a type of the compiler (`Integer`, `string`,
  `Boolean`, `Double`...), a type the table knows by its name (`TAlign`,
  `TColor`, `TFont`), or an enumeration or set declared in that unit, with
  its members read from the source (`TTono = (toClaro, toOscuro)`); the
  rest of the judgement (a whole number that fits, a string written as the
  IDE writes it, a colour constant) follows as for any property. What
  nobody can judge - a class of the user's own, a type of another unit, a
  type two framework units declare - is refused saying so, and so is a
  path into such a property (`Modo.X`): write the line with `delphi_edit`.
  `preview` cannot load the user's classes, so it skips those properties as
  the IDE would without them: `ignoredUserNote` (`DSGN-152`) now names
  them and says it is not an error of the form.
  `test_set_propiedad_usuario_1192`.

### Changed

- The `STYLE-016` note of `delphi_styles lint` says that
  `duplicatedStyleNames` is the same name twice in ONE file: two theme
  files sharing names is how themes work (asked by Hermes).
- `LSP-003`, the answer of `delphi_references` and `delphi_rename_symbol`
  when the position is not a symbol, sent the reader to `delphi_read` for
  line and column - whose lines are 1-based, the very slip that produces
  it (Hermes' H5-01: the line of a read in the 0-based parameter). It says
  so now, as `LSP-029` does, and points at `delphi_symbols filter=<name>`,
  which gives both.

## [1.19.1] - 2026-10-15

Six fixes from Hermes' validation of 1.19.0, each one reproduced against
it before anything was touched: `delphi_git` keeps the server's trash out
of the agent's repository (`add paths=["."]` put it into the index);
`remove-sdk` and `reseat-sdk` find the SDK `profiles` lists, by its name;
`delphi_changeset preview` sees an operation that anchors on a line an
earlier one writes; the designer judges `ModalResult` as the integer it
is; a `restore` after a copy or a rename gives back the new `unit` header;
and `delphi_diagnostics` names the project it linted with and says when
its "0 warnings, 0 hints" says nothing - DelphiLSP gives neither for a
unit below its project's folder. No contract is taken away: one answer
gains a field (`project`) and a note (`LSP-046`).

### Fixed

- **`delphi_git` no longer puts the server's own folders into the agent's
  repository.** The trash (`__delphi-patch`, with a copy of every edited
  file and its owner marks) and the temporary folder of older versions
  (`__delphi-temp`) live inside the roots, next to what is edited. The
  `.gitignore` that `delphi_create` writes covers them in the project's
  folder, but not at the root of a repository above it nor in a folder of
  loose units: `add paths=["."]` put the trash into the index (and so into
  the next commit and push), and `status` listed it as untracked (measured
  on 15-oct against 1.19.0, reported by Hermes). `status` and `add` now
  leave both out with git's own mechanism - an exclude pathspec built from
  their namers - without touching the agent's `.gitignore`; named on
  purpose, the trash does not go in either. `test_git_papelera_1191`.
- **`remove-sdk` and `reseat-sdk` find the SDK `profiles` lists, by its
  name.** They passed the name through the composer of a NEW SDK's folder,
  which keeps only letters and digits, so `AndroidAPI36.1_64bit` became
  `androidapi36164bit` and was never found (`PAS-008` echoing the mangled
  name; `PAS-059` unreachable for every real Android SDK). The name of an
  existing SDK is now chosen, case-insensitively, from the two lists
  `profiles` shows (the `.sdk` files and the IDE's seats); `PAS-008` echoes
  the name as written. And `remove-sdk` closes when it cannot read an SDK
  file's platform: the seat branch did since 1.19.0, the file branch still
  removed such a `.sdk` (measured: a `.sdk` without `Profile_platform` was
  removed). `test_sdk` 6d-6f, on the throwaway APPDATA.
- **`delphi_changeset preview` sees an operation that anchors on a line an
  earlier one writes.** Every anchor resolves against the file as it was
  before the changeset, and the tool's description says an edit cannot
  anchor on a line an earlier edit writes; the preview did not check it:
  an edit and a `delete-line` of the same line got a clean preview
  (`CHSET-023`, `unresolved: 0`) and the commit failed and rolled back
  (`CHSET-026`; reported by Hermes). The preview now names the line and the
  earlier operation and counts it as unresolved. `test_changeset_solape_1191`;
  the rollback battery of `test_changeset` used that very overlap as its
  trap and now uses a file another process holds at commit time.
- **`delphi_designer set` and `lint` judge `ModalResult` as the integer it
  is.** `TModalResult` is `Low(Integer)..High(Integer)`; the designer tables
  took a subrange for an integer only when its low bound started with a
  digit (`TColor`, `TCursor`), so this one had no base and anything went:
  `set ModalResult=mrOK` was written, `lint` said CLEAN, and the loader
  refused it (the preview ignored it with `DSGN-114`: the form would not
  open; reported by Hermes). A `Low(T)` / `High(T)` bound now takes the base
  of `T`, asked of the same classifier; `set` answers `DSGN-093` (a whole
  number, as the IDE writes it) and `lint` names it. The tables regenerate
  on their own (generation 13). `test_designer_modalresult_1191`.
- **A `restore` after a copy or a rename gives back the new `unit` header.**
  `delphi_move` rewrites the header to the new name (`MOVE-015`) with the
  usual writer, which kept the file with the OLD header as the first copy of
  the day; after the agent's next change, `restore` went back to it -
  `unit UOrig;` inside `UCopia.pas`, with `audit=clean` (reported by Hermes;
  the rename by `move` had the same twin, measured). That copy is a step of
  the server's own work, not a state the agent ever had: it is dropped, and
  the first copy is the one of the agent's next change. `test_restore_cabecera_1191`.
- **`delphi_diagnostics` says when its "0 warnings, 0 hints" says nothing,
  and with which project it linted.** Of a unit in a folder BELOW the one of
  its project (`Sub\`, `Domain\Models\`), listed in it or not, DelphiLSP
  publishes the errors and never the warnings or hints; in the project's
  folder and in a sibling folder it publishes everything. Measured on
  15-oct with the engine alone and our settings, on this machine and on the
  13.2 VM, after Hermes saw an `H2077` from `delphi_build` that diagnostics
  never showed; ruled out by name: `projectFiles` in the IDE's own shape,
  the folder in the search path, the `.dpr` opened first, an absolute `in`
  path and the shape of the uri. The answer now carries `project` (the
  `.dproj` whose settings linted the file - a unit no project lists takes
  the nearest one above it, which was Hermes' case) and, below its folder,
  the note `LSP-046`; `delphi_build` reports the rest. The description
  says it too, rewritten to fit: `tools/list` stays under its budget.
  `test_diagnostics_debajo_1191`.

## [1.19.0] - 2026-10-15

`delphi_git` asks for operations, not command lines: the free `args` is
gone and every command takes its own fields (`paths`, `ref`, `branch`,
`remote`, `action`...), with git itself as the judge of each value - the
minor change of this version. Around it, the fixes of 14-oct: a link
inside a repository no longer lets git read or rewrite what is behind it
outside the roots (the jail hole the closing review measured); git
launched by its full path from the server's PATH; `delphi_build` choosing
the profile and the target instead of copying them onto msbuild's line;
the tree copier failing closed on a folder it cannot list, and a folder
the server cannot list no longer taken for an empty one; the upload
quarantine kept inside the write gate; `get-sdk` / `reseat-sdk` /
`remove-sdk` kept to their own SDKs; a file that already says the same not
rewritten; and `delphi_desktop` on Linux naming a locked session or a
desktop without a monitor instead of "the portal refused the screenshot
(code 2)". Nothing here is a new capability: those go to 1.20.

### Changed (contract: `delphi_git`)

- **`delphi_git` has no `args` any more: each command takes its own
  fields, and the server composes the git command line.** An agent asks
  for an OPERATION, never a command line (the rule of 13-oct). Free `args`
  sat behind a deny list of options that kept losing: `switch -`,
  `--detach`, `-f`, `-c <new> <start>` and `--discard-changes` went
  through it (measured on 13-oct). Now nothing the agent types reaches git
  as an option. Revisions (`ref`, `to`, the branch of a merge) are judged
  by `git rev-parse`; new names (a branch, a tag) by `git
  check-ref-format`; `remote` is the NAME of a remote of the repository;
  `paths` is a LIST of files or folders of the repository, each one after
  `--` as a literal pathspec. The fields, per command: `status` (paths),
  `diff` (paths, ref, to, staged, format = stat / shortstat / words,
  context), `log` (paths, ref, to, format = oneline / dated / full, count,
  search), `show` (ref, paths, patch), `add` and `restore` (paths),
  `commit` (message), `stash` (action = push / pop / list, paths,
  message), `switch` (branch, create), `merge` (branch, or action=abort),
  `tag` (name, ref, message; no name lists), `config` (name =
  user.name / user.email, message), `pull` (remote, branch), `fetch` and
  `ls-remote` (remote), `push` (remote, ref), `worktree` (action, path,
  ref); `branch` and `init` take nothing. They are the ones in use
  (measured in the production logs); what is needed later is added as a
  field, with its case. A call that still sends `args` gets `GIT-068`,
  which names the fields. The deny list of options went with `args`; as a
  second barrier, no value that goes alone on the line may start with `-`
  (`GIT-075`). `paths` goes through the virtual-drive translation and the
  jail's entry floor like any path parameter: a list does not skip them,
  and a list a client sends as its JSON text (an old schema in its cache)
  is turned into the array at the entry, before anything reads it
  (measured live: a `srvd:` path inside such a text reached git
  untranslated).
  Gone with the free arguments: the network options (`--tags`, `--prune`,
  `--depth`, `-u`, `--dry-run`...), a remote written as a URL or a folder
  in the call, the refspec forms, `diff --quiet`, and `branch` creating or
  deleting (create with `switch create=true`). New messages: `GIT-068` to
  `GIT-075`; retired: `GIT-003`, `GIT-027`, `GIT-037`, `GIT-040` (now
  `GIT-012` for every command), `GIT-042`, `GIT-043`, `GIT-059`.
  `test_git_operaciones_119`; the git batteries moved to the fields.

### Fixed

- **A link inside a repository no longer lets git read or rewrite what is
  behind it, outside the roots (JAIL, since 1.7.6).** git goes through a
  junction as if it were a folder, and the repository gate judged the three
  folders of the repository (root, `.git`, common), not the tree: with a
  junction inside the repo pointing at a folder outside every root, `add
  paths=["."]` put the files behind it in the index (a read outside the
  jail), `switch` to a branch without them deleted them, and `stash` push
  rewrote them; `merge`, `pull` and `stash pop` reached git and failed
  inside it, already writing through the link (measured against 1.18.3+ on
  14-oct, `test_git_enlace_arbol_119`; found by the closing review). Now,
  before every command that walks the tree (`status`, `diff`, `add`) or
  rewrites it (`switch` to a branch, `merge` - `abort` included -, `pull`,
  `stash` push and pop), the server walks the working tree itself with the
  guard's walker (`.git` aside): a link whose real target this session
  cannot read (the walking commands) or write (the rewriting ones) refuses
  the command with `GIT-076` before git runs and before any network; a
  link to a place inside the roots is admitted, and what is behind it is
  walked too (a link behind a link counts); a folder of the tree the server
  cannot list refuses the command (`GUARD-040`) instead of being taken for
  checked. The commands that do not touch the tree (`log`, `branch`,
  `commit`, `tag`, `config`, `restore --staged`, `switch create=true`,
  `fetch`, `push`) keep working with the link there. One rule, in the guard
  (`EnlaceAjenoEn`), next to the link rule of the readers; the git tool
  says which commands touch the tree (`GitTocaArbol`). Measured the same
  day, with no hole: a junction whose target is written as a volume by its
  GUID (`\??\Volume{...}\...`) is followed by Windows and judged by the
  real path Windows gives, so `delphi_read`, `delphi_list` and `delphi_move
  copy=true` through it refuse or skip it (`test_union_volumen_119`).
- **The small things of the closing review of 1.19.0.** The program the
  server launches by its name (git for `delphi_git`, msbuild for
  `delphi_build`) has to live where this session cannot write: a `git.exe`
  found in a PATH folder inside the roots is the agent's, not the
  operator's, and the call answers `GIT-050` (one helper in the guard,
  `ProgramaDelOperador`; `test_git_por_ruta_119` R4, red against the build
  before). `worktree add` composes its two values with the house quoter, as
  `commit -F`, `tag -F` and `worktree remove` now do (a revision with a
  blank that `rev-parse` admits was split in two). The value of `config`
  joins the second barrier against a value that starts with `-`, and
  `GIT-075` shows the field and its value. `GIT-045` says that `remote` is
  a name and that the address judged is the one that name has in the
  repository; `GIT-056` no longer speaks of arguments; the description of
  `ref` says what `log` does with it alone (the newest commit shown), and
  `context` says it takes 1 or more (0 is the default, not "no context").
  `delphi_delete` of a folder lists the units that go with it without
  crossing a link, as the deleter does (a unit behind a junction was taken
  out of its project and then not deleted). The Linux desktop node no
  longer asserts why there is no monitor ("typically" a remote session that
  disconnected). Docs: the hand note of `delphi_git` in TOOLS.md dropped
  `GIT-037` / `diff --quiet`, the README says `stash` with `paths`,
  CONFIGURATION.md says `args` is gone, and the 1.19.0 entries name the R1
  witness and `test_union_volumen_119`. `delphi_paserver`: `remove-sdk`
  refuses a seat whose platform it cannot read instead of removing it
  (`PAS-059` with "unknown"); a `get-sdk` that fails half way no longer
  tells the agent to delete a folder that was already a registered SDK;
  the `distro` and `pulled` fields of the SDK record go through the house's
  text-field reader (a `{}` there ended in an internal error). The Linux
  node reads the monitors once for its two questions. Repository: the two
  `.res` of the desktop node and the job runner are no longer tracked; they
  hold only msbuild's `PLATFORMTARGETS` marker (4 bytes, the platform
  linked last), every build rewrites them and a build creates them when
  they are missing (measured), so they showed as modified after every
  build for nothing. Docs: the renderer's README and CONFIGURATION say what
  a preview runs and with which account - the operator's installed
  components, as the IDE does - what the server judges first (the form's
  values with the shape of a path) and how a component that waits ends
  (`RENDER-007`; measured with a `TFDConnection` that had nothing to
  open: 60 s, nothing written, no process left).

- **`delphi_git` launches git by its full path, found only in the PATH the
  server started with.** It launched `git.exe` by name, and Windows looks a
  bare name up FIRST in the folder of the exe and in the CURRENT folder of
  the server process: a service runs in its own folder, but over stdio that
  folder is whoever launched the server - the agent's repository - and a
  `git.exe` left there ran with the server's account (measured on 14-oct
  with an inert probe: a copy of `whoami.exe` planted as `git.exe` in the
  server's current folder answered `delphi_git status`). Now git is resolved
  as msbuild is since 1.18.2 (`ProgramaEnPath`: the PATH entries only, never
  the current folder nor the exe's) and launched quoted, by that path; with
  no git in that PATH the call answers `GIT-050` before launching anything,
  and the message says where git is looked for. `test_git_por_ruta_119` (red
  against the previous build; its R1 is the witness: a bare `git.exe`
  launched with the parent's current folder there runs the planted probe,
  because CreateProcess searches the PARENT's current folder, not the
  child's, and the harness's `NoDefaultCurrentDirectoryInExePath` - which
  the service does not have - is what hid it the first time).
- **`BUILD-029` no longer sends the agent to `delphi_config set-output` for
  an output that command does not set.** The refusal for a `BRCC_OutputDir`
  (or any other output property) outside the workspace said that
  `set-output` places the outputs inside; it only sets `DCC_ExeOutput` and
  `DCC_DcuOutput`. The message now names what `set-output` covers and says
  the other properties are set in the project by the operator.
- **The tree copier fails closed on a folder it cannot list, and the two
  searches that still crossed any junction go through the guard's walker.**
  `CopiaArbol` (the safety copy of a move, `copy=true`, the copy into the
  test container, the styles build) listed each level with the RTL, which
  answers an empty list when Windows refuses the listing (the finding of
  "a folder the server cannot list is no longer taken for an empty one"):
  such a branch was copied empty, in silence. It now lists with the reader
  that tells the two apart and the copy stops there, with the reason; the
  move's gate already refused earlier, so for it this is the second
  barrier. The build's search for a unit's folder and the discovery of a
  unit's `.dproj` in sibling folders used `TDirectory.GetFiles` across
  subfolders, which follows every junction (each candidate was then refused
  one by one); both go through `WalkFiles`, which follows only the links the
  session may read. The filter of `delphi_test` (`--run:`) travels quoted,
  so a filter with a space reaches the runner whole. Measured and not
  changed: deleting a folder that holds a junction to a sibling folder with
  a unit does not take that unit out of its project (the theory said it
  would); `test_borrar_carpeta_union_119` guards it.
- **`delphi_build` chooses the profile and the target; it no longer copies
  them onto msbuild's line.** The profile - the call's `profile`, or the
  `.dproj`'s own `Profile` property on a Deploy - reached `/p:Profile=` as
  written: the gate only looked at its characters, and the project's one
  had no judge at all. Both now have to be one of the profiles the IDE
  declares (the judge `delphi_config set-profile` uses), with the IDE's
  spelling, or the build answers `PAS-053` (the refusal the deploy already
  gave for a missing profile) before anything runs; the host rule stays
  behind it. The target goes to `/t:` with its own name from the fixed four, and
  that list lives in one place for the gate and the build. The profile, the
  SDK and the device id travel quoted like the configuration (a second
  barrier: all of them come from a list or a character judge). `BUILD-015`
  no longer mentions a build shell that is gone since 1.18.2.
  `test_build_perfil_119` (red against the previous build).
- **Three documentation gaps Hermes hit (13-oct).** `delphi_config
  set-version` says, in its `version` text, that the project
  needs its VERSIONINFO block (the IDE's Version Info page) and answers
  `CFG-003` without it. Two messages said "send a delphi_report" and an
  agent called `command=send`; they say `command=report` now. The worked
  example of `delphi_git` in `docs/TOOLS.md` used the free `args` that
  1.19.0 retires; it shows `paths`, `name`, `remote` and `ref`.

- **`delphi_desktop` on a Linux target says what is wrong with the user's
  session, instead of "the portal refused the screenshot (code 2)".** Hermes
  got that answer and retried believing the node broken (13-oct); measured
  on the Zorin on 14-oct, step by step: with the session merely LOCKED the
  portal still captures (the lock screen, with the window list), so that was
  not it; when the remote desktop that opened the session DISCONNECTS, the
  desktop is left without a monitor (the client was the screen), the portal
  answers code 2, and about twenty seconds later GNOME Remote Desktop ends
  the whole session, taking every program inside with it - which is how the
  deployed application "died during the lock". The node now asks login1 for
  the `LockedHint` of its session (over the system bus, the judge `loginctl`
  uses) and refuses a locked desktop by name (nothing to act on, and no
  typing into an unlock prompt); asks Mutter how many monitors there are
  and, with none, says the remote session is gone and what to ask for; and
  the existing "no open graphical session" covers the session once it has
  ended. `status` answers `reachable` and, when the desktop is not, that
  line as `hint` (it travelled only inside `nodeOutput`, while the Windows
  node's reason went to `hint`). Where login1 or Mutter do not
  answer, the portal is tried as before. The node's bus connection takes
  which bus to join; the session detector also reports the session's logind
  id and its user. The tool's description now names a locked session of
  either system.

- **A file written whole that already says the same is not rewritten, and
  not copied first.** `delphi_paserver get-sdk` composes the `.sdk` from
  the same inputs every time, so a re-run (what its description asks for
  after an OS upgrade on the target) wrote identical bytes and still left a
  copy of the previous file in the server's house, and the same for the
  SDK record, whose `pulled` date changed on every call. Hermes saw the
  copies pile up (13-oct); measured on 14-oct against 1.18.3: a second
  `get-sdk` that pulled zero files answered `previousSdkCopy` and
  `previousSdkRecordCopy` with the `.sdk` byte-identical. The rule the
  edits already had ("nothing changes: nothing is written, nothing is
  copied") now lives in the one writer of the IDE's, the house's and the
  temporary places (`EscribeBytes`), so profiles, `.sdk` files, records
  and caches get it at once; the house writer's own half of it (a fallback
  on failure) goes. `get-sdk` says `sdkFileUnchanged` when the `.sdk` was
  already that, and a pull that brought nothing keeps the record's `pulled`
  date, so the record is unchanged too. The description of `get-sdk` now
  says the last 10 copies per file are kept. `LspTests.Rutas`
  (`EscribirLoMismoNoReescribe`).
- **`delphi_paserver remove-sdk` only removes PAServer SDKs; `reseat-sdk`
  only seats a sysroot that lives in the IDE's SDK folder (judged with the
  path comparator of the house, so `<SDKs>\..\elsewhere` does not pass);
  `get-sdk` says
  what it could not write and what it left behind.** `remove-sdk` deleted
  the SDK Manager seat of ANY SDK by its name, the Android ones GetIt
  installs included (`reseat-sdk` already skipped them); it now refuses an
  SDK whose file, or whose seat, says another platform (`PAS-059`), by
  reading, since measuring it meant destroying a real SDK. `reseat-sdk`
  registered as sysroot whatever the `.sdk` file said, wherever it was,
  which made that folder a place of the IDE's for the server's writers;
  one outside the IDE's SDK folder is skipped and named (`PAS-060`). A
  `get-sdk` whose SDK record could not be written swallowed the error and
  the next call had no distro guard: the answer says it (`PAS-061`); and
  one that fails after pulling names the folder it left behind, like
  `remove-sdk` does (`PAS-062`). `test_sdk` (6b, 6c).
- **`delphi_upload`'s quarantine no longer deletes or overwrites a
  read-only `<name>.corrupt`.** An upload whose final sha256 does not match
  is set aside as `<name>.corrupt`, and a previous quarantine there goes to
  the trash first. The upload's gate judged `<name>` only, and the move and
  the delete ran on the derived name with no gate of their own. Measured
  on 14-oct, against 1.18.3: a `<name>.corrupt` that `ReadOnlyPaths` named
  was deleted and replaced by the bad upload. The derived name now goes
  through the same gate as the upload's own destination before anything
  touches it; when the quarantine is refused (or the previous one cannot be
  copied), the bad file stays under its name and the error says so and why
  (`UPLOAD-012`). Until now that error said "I set it aside in `<name>`"
  even when it had not. `test_cuarentena_puerta_1184` (red against
  production).
- **A folder the server cannot list is no longer taken for an empty one.**
  The RTL's `TDirectory.GetFileSystemEntries` returns an empty list when
  Windows refuses the listing (`FindFirst` fails, and `System.IOUtils` says
  nothing). The gate that walks a tree before it is copied, moved, deleted
  or purged ("what cannot be checked is not moved") therefore passed a
  branch it had never seen. Measured on 14-oct, against 1.18.3, with a
  subfolder whose listing was denied: `delphi_move copy=true` answered
  `COPIED` with that subfolder copied EMPTY, and `purge=true` deleted half
  the copy and advised to "retry in a moment". One lister now asks Windows
  whether an empty answer is really empty (`EntradasDeCarpeta`, the error
  of `FindFirstFile`): the walk fails closed with `GUARD-040`, which names
  the folder and what Windows said, instead of `GUARD-033` ("is Git
  metadata"), which it used to give when a walk failed. The temp purge's
  "when in doubt, keep it" and `delphi_delete`'s "empty folder" check use
  the same lister. `test_arbol_ilegible_1184` (red against production);
  `test_paisaje` keeps `TDirectory.GetFileSystemEntries` in that one place.
  On the way, the hard-delete gate checks its allow and deny lists before
  it walks the tree for Git metadata: a delete those lists refuse no longer
  pays for the walk (refusing `C:\Windows` used to walk all of it).
  `test_purga_bordes_1184` guards three purge edges that had no battery (a
  `.git` FILE whose `gitdir:` points outside the roots, a repository inside
  a `__delphi-temp`, and the same with a link in its `.git`), and a unit
  test now measures the gate's own refusal of a `.git` inside the trash.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
