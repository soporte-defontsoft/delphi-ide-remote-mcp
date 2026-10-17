# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [Unreleased]

### Fixed

- **`delphi_designer preview state=` follows a dotted path, as `prop` and
  `set` do.** `Label1.Font.Size=14`, `Label1.TextSettings.FontColor=claRed`
  or `FrameF1.RectF.Fill.Color=claRed` were refused with `RENDER-012 ...
  does not publish Font.Size`: the renderer looked the whole path up as ONE
  property of the component. It now walks it the way the RTL reads a form
  (`TReader`): each segment but the last is an object of the component's
  own (a `TFont`, a `TTextSettings`, a `TBrush`) and the last one is set on
  it. A segment the object does not publish names that object's class
  (`TFont does not publish Sise`); a segment that holds a value ends the
  path (`RENDER-020`); one that holds a reference to another component is
  not walked through (`RENDER-021`): in a form file that component is
  written by its Name, so its properties are set by its own Name - the same
  rule `set` applies. Measured by Hermes (Qwen3.8 Flash Next) in the
  targeted rounds of 1.20.0: two refusals for one task.

## [1.20.0] - 2026-10-16

What an agent reads back, measured with Hermes on Delphi 13.2 with two
models (a mixture-of-experts Flash and a dense 27B) before publishing: a
full pass over every tool, then targeted rounds repeated three times per
model on what each fix touched. Answers cost less: a JSON answer no longer
reaches the agent twice, and a `delphi_desktop` gesture says only what it
did, with its image inside one answer. The IDE's own form reader is asked
at every door that writes or shows a form, so a form the IDE would not
load is said with the reader's words and line instead of a renderer
failure. A single `delphi_edit` / `delphi_textedit` takes a block as its
anchor; a parameter that does not go with a command says where it does
go; a property of the other framework is said as such, and a whole number
that does not fit says how the same 32 bits do. `delphi_designer prop`
follows a dotted path as `set` does, a class-typed property points to its
class, and `info filter=` looks one level inside object properties.
Two answers change meaning: `delphi_definition kind=implementation` gives
the body (what `definition` gives), and `delphi_rename_symbol` is not
applicable when the name is inside a string in ANY unit of its scope.

### Changed

- **A JSON answer no longer reaches the agent twice.** Every answer that is
  a JSON object travels as text AND as `structuredContent`, and the MCP spec
  asks the text to be the serialized `structuredContent` - the backwards-
  compatible copy - so that a client can drop one of the two. Ours never
  were equal: the server added `"ok": true` (and `code` on a refusal) to
  `structuredContent` only. Hermes 0.22.2 drops the duplicate exactly when
  the text parses to the same JSON, so it kept both, and EVERY JSON answer
  reached its model twice - measured on 2026-10-16 by running our answers
  through its own renderer: `delphi_workspace` 4,807 characters, the
  `delphi_help` page of `delphi_designer` 20,105. The text now carries what
  is added, at the end of the object, and nothing else changes: the tool's
  own text keeps its form (it is not re-serialized), prose answers still
  publish no `structuredContent`, and a refusal keeps `isError` and its
  `{text, ok, code}`. Through the same renderer: 2,502 and 10,121, half of
  every JSON answer of every tool. A client that reads the text as JSON
  sees one more field, `ok`. (A refusal whose JSON carried its own `ok`
  keeps its text as it was: it travels with `isError`, and a client then
  takes the text.)
- **`delphi_desktop`: what a gesture answers is what that gesture did.**
  Every `tap`, `key`, `type`, `screenshot` and `overview` carried the
  node's whole startup in `nodeOutput` - its libraries, the session's
  cgroup, the scale, the window list twice (it already travels in
  `windows`), the node's own console usage, and a `CAPTURE=` line with the
  node's folder on the target: about 1,300 characters on every gesture,
  measured on 2026-10-16 in Hermes' history (228 gestures and captures, 215 with that
  path). Two of those cost it steps: it called the tool with
  `command=tecla` and `escribe`, words of the node's console usage, and it
  passed the node's capture folder as `out=`. Now a gesture or a capture
  that worked keeps only what the node said about it - the action
  (`CLICK at pixel ...`, `KEY ... sent`, `WRITTEN ... (the focus is NOT
  verified ...)`) and any warning (`FALLBACK:`, a channel that never got
  ready) - and with nothing to say `nodeOutput` is left out. `status` and
  a failure keep the node's diagnostics; no answer carries the capture
  path, the window protocol lines or the console usage. The startup lines
  are named by their ids in the node's own catalog
  (`NodeProtocolo.inc`), and `test_catalogo` checks every one is a note,
  never an action or a failure.
- **A single `delphi_edit` / `delphi_textedit` takes a block as its anchor.**
  An `old` of several consecutive lines was refused (`EDIT-001`: "the anchor
  of a SINGLE edit is ONE line... send it in `edits`") while the engine
  already applied exactly that as an `edits` entry. Measured in Hermes'
  history on 2026-10-16: 14 refusals (10 with the 27B, 4 with Flash Next),
  12 of them fixed on the very next call - one call lost every time - and
  Claude hit it twice the same day. Now such an edit IS the one-entry batch:
  the block is found whole and in order and replaced (`delete:true`, or an
  empty `new`, removes it), `atline` is the line where it starts when it
  appears more than once, and `toline` with a block is refused as in `edits`
  (`EDIT-020`). An anchor of ONE line works as always.
- **A parameter that does not go with the command says where it does go.**
  The eleven tools with several modes refuse a parameter their mode does not
  take (`DSGN-047`, `EDIT-115`, `CFG-110`, `GIT-038`...) and listed what that
  mode takes. A small model that FORGOT the command read "`path` does not go
  with command=info" - info being only the default: 4 of the 10 such
  refusals in Hermes' history (measured on 2026-10-16). The answer now adds,
  from the same table, the modes that do take it: everything that was sent,
  when one mode takes all of it (`What you sent (path, maxdepth) goes with:
  tree.`), or else the parameter itself (`"code" goes with:
  insert=rutina-global, insert=metodo.`). Parameter names only, never a value.
- **`delphi_designer`: a property of the other framework is said as such,
  and "Did you mean" only proposes what exists.** Of the property refusals
  in Hermes' history that were not its own border tests, half were the
  other platform's property - `Alignment` on an FMX `TLabel` (21 warnings
  over two edits), `Caption` on an FMX `TButton`,
  `Position.X` on a VCL `TLabel` - and the near-name guess got two of three
  wrong: "Did you mean Action?" for `Caption`, `Hint.Color` for `Font.Color`
  (`Hint` is a string). The judge of a property - `set`, `insert`, `lint` and
  the warnings after an edit - now asks the table of the OTHER framework of
  the same install whether the class of the same name publishes it (`"Alignment"
  is what the VCL TLabel publishes; this form is FMX`), from the segment that
  fails (`TextSettings.Font.Color`: the VCL `TFont`'s). When that applies
  there is no near-name guess, and a guess is made only when the whole path
  exists. The first time the other framework's table is needed it is read:
  about 0.9 s and 78 MB for the VCL one, once per process. 300 such lines
  add 11 ms and 19 KB to a `lint`.
- **A whole number that does not fit says how the same 32 bits do.**
  `TextSettings.FontColor = $FF00A152` - an ARGB colour written by hand - is
  more than the form loader's signed 32 bits, and `DSGN-093` (and the `lint`
  line) said only the limit: Hermes took six calls to get out of it on
  2026-10-16 and ended up writing `-16735918`. Now the answer computes the
  way out: the same 32 bits as a signed number, and - when the type's own
  reader also takes `x` and a hexadecimal, as `TAlphaColor`'s does, read from
  its source - that form first (`xFF00A152`, the way the IDE's own forms
  write it).

### Fixed

- **An inline image always fits in one answer.** Over HTTP the whole
  answer of a tool travels as ONE server-sent event, and the MCP Python SDK
  2.x reads events with `httpx2`, which drops one over 1 MiB: the call
  ended in `SSE stream ended without a response`. A 3440-wide desktop with
  a photo as wallpaper, scaled to 1280, is a 972 KB PNG - 1.3 MB in base64
  - and Hermes lost three screenshots of its Zorin that way on 2026-10-16
  (another client without that limit got the same image). An inline image
  now weighs at most 737,280 bytes: the PNG when it fits, otherwise the
  SAME image - same width and height, so `frame`, `inlineScale` and every
  tap measured on it are unchanged - as JPEG at quality 85, 70 or 55; if
  not even that fits, it comes as a file with its link (`CAPT-014`). A
  model counts an image by its pixels, so this saves no tokens: it makes
  the image arrive. One place for every tool that captures (`delphi_desktop`,
  `delphi_adb`, `delphi_designer preview`).
- **`preview` of a form the IDE cannot load says so, with the reader's own
  words and the line.** It answered `DSGN-061 INTERNAL` - "the renderer
  could not draw" - for a file the agent had written wrong, eight times in
  Hermes' history. Now the renderer tells the server when the failure came
  from the form reader itself (the RTL's `EFilerError`/`EParserError` while
  loading) and the answer is `DSGN-153`: the file, not the renderer, with
  each thing the reader said and the line it names (`line 15: FontColor =
  -65536  ->  Error reading Edit1.FontColor: Invalid property value`). And
  the real cause no longer gets lost: a number that does not fit a published
  property (`TextSettings.FontColor = $FF00A152`) was skipped by the
  renderer's Ignore without being consumed, the reader lost its place, and
  all that came out was `Stream read error`. What the reader skipped now
  comes out on a failure too, and the first line of the answer is the
  property that broke it. `DSGN-061` stays for what is really ours: a design
  package or a component that fails while painting.
- **A value only the IDE's reader can judge is judged by it - in `lint`,
  after `delphi_edit` and the changeset, and in `delphi_upload`.** A
  property a class stores by code (`DefineProperties`: `FontColor` or
  `HorzTextAlign` on an FMX `TEdit`) has no type in the tables, so its value
  went unjudged: `designer set` already asked the IDE's reader (`DSGN-149`),
  but `delphi_edit` wrote `FontColor = -65536` without a word and `lint`
  answered `CLEAN` for a form the IDE would not open (measured in production
  on 2026-10-16). Now, when the tables find nothing wrong and leave a line
  unjudged, the form goes whole to the same reader: `lint` says `CLEAN` only
  if it loads (`DSGN-154` when it could not be asked), and a write that
  leaves a form the reader does not load gets `EDIT-127` with the reader's
  words and the line. Counted over 4,938 real forms (the IDE's samples and
  ours): nearly every form has such a line - `Explicit*`, `Left`/`Top` of a
  non-visual, `DesignerMasterStyle` - so a form write costs one load of the
  form (0.3 s on a plain form, about 1 s with 112 design packages, 5 s the
  first time), done after the server's write lock is released, never under
  it. `delphi_upload` now judges a text form like `delphi_edit` does
  (`designer` in its answer) once the file is whole - the IDE's parser reads
  it, or the chunk carries `sha256`; it judged none before. What the reader
  skips from a class that is not installed is not a warning: that is
  `DSGN-039`'s note.
- **`delphi_rename_symbol` blocks on a string with the name in ANY unit of
  its scope.** Its description promises that a hit inside a string literal
  (`FindComponent`, RTTI or `StyleLookup` by name) makes it not applicable,
  but only the strings of the files it was going to edit were looked at: a
  `'Saluda'` in another unit was a mere warning (`RENAME-007`) and the rename
  was applicable - leaving that lookup pointing to a name that no longer
  exists, with the compiler silent. Hermes found it in the pre-release
  validation of 2026-10-16. `delphi_references` now counts apart the
  mentions that fall inside a string, by the lexer, in its whole scan
  (`stringMentionsCount`), and the rename blocks on that count
  (`RENAME-020`); its own scan of the edited files is gone.
- **`delphi_definition kind=implementation` is `definition`.** It sent
  DelphiLSP's `textDocument/implementation`, which on a call site answers the
  declaration of the method that CONTAINS the call (`ShowMessage` inside
  `TFormMain.Greet` -> `Greet`), measured on 13.1 and, by Hermes, on 13.2;
  the description said it answered "like declaration", which stopped being
  true when `declaration` started chaining through `definition`. The
  implementation of a symbol is its body, which is what `definition` gives.
- **`delphi_designer prop` follows a dotted path, as `set` does.** It looked
  the property up on the first level of the class only, so
  `prop TLabel fmx TextSettings.HorzAlign` and `prop TLabel vcl Font.Size`
  answered "is not a published property" (`DSGN-016`) for what `set` writes
  without complaint. Measured in the pre-release rounds of 2026-10-16: the
  27B model guessed `TextSettings.HorzAlign` right, checked it with `prop`
  BEFORE writing - what the tool's description asks for - and was sent
  looking for a class that does not exist; the model that wrote without
  asking got there in one call. `prop` now asks the same judge as `set`: down
  a class-typed property and into the descendant its instance holds, with
  the enum's members at the leaf; what does not exist comes back in the
  judge's words, with the other framework's hint. A class-typed property
  points to its class (`DSGN-155`: `command=info classname=TTextSettings`
  lists its own), as Delphi's help links a property to its type - never an
  equivalence between frameworks. And the list of what a class publishes in
  a "does not exist" (`DSGN-087`, the lint), which comes cut from the table,
  ends with the way to the whole one: `info classname=... framework=...`.
  `info` with `filter` now also looks one level inside the object properties
  (`filter=Horz` on an FMX `TLabel` finds `TextSettings.HorzAlign`, dotted as
  `set` writes it): it said "the class simply has no such member" (`DSGN-048`),
  and a hand-written coda ("an FMX text control keeps its font in
  TextSettings") stood in for the table in one case - it is gone. On a class
  that publishes nothing itself (`TTextSettings`, where `DSGN-155` leads),
  the filter searches what its descendants publish: it said "no such member"
  next to a `descendantsPublish` that listed `FontColor`. A property
  that holds a REFERENCE to a component (`PopupMenu`) is not opened and gets no
  `DSGN-155`: whether a class-typed property is an object of its own or a
  reference is one rule (`EsObjetoPropio`), the one `set` already used, now
  asked by `prop` and the filter too - and `test_paisaje` watches that it is
  not written again by hand.
- **Three descriptions said what the tools do not do.** `delphi_diagnostics`
  spoke of the settings of `"project"` - a field of its answer - and Hermes
  read it as a parameter (`SYS-015`); `delphi_hover` promised `null` on a
  declaration, while the implementation header answers on 13.1 and both do
  on 13.2; and `delphi_help`'s refusals `HELP-007` and `HELP-002` listed the
  whole registry as "the ones there are" - `vault_*` included in a
  workspace whose `tools/list` has no vault. They now list what `tools/list`
  announces to that session.
- **`delphi_upload` of a form the IDE's parser cannot read says so.** A
  text form uploaded without `sha256` is judged only when the parser reads it
  whole, because a first chunk is not a form yet - and when it did not, the
  answer was `ok: true` and nothing else. Hermes uploaded a whole form with
  its BOM mistyped and found out two calls later with `read` and `lint`. Now
  such an upload carries `designerNote` (`UPLOAD-013`): not judged yet, what
  the parser said and on which line, and that it is expected only if more
  chunks follow.
- **`delphi_upload` no longer invites what it refuses.** Its description
  listed "binary designer files" among what to upload, and the tool refuses
  them (`UPLOAD-002`) - whose text said this server does not read binary
  designers, which stopped being true in 1.1.2. The description no longer
  lists them, and the refusal gives the real reason: upload writes designers
  as text, the shape `delphi_edit` and `delphi_designer` edit; convert first
  (`delphi_designer to-text`) or upload the text form.

## Earlier versions

Each earlier line is kept whole, entry by entry, in `docs/changelog/`:
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
