unit Mcp.Vault.Seed;

{ First-run scaffolding for the knowledge vault.

  Point [Vault] Path at a folder that does not exist yet, or at an empty one,
  and the server creates a working starter vault there: the rules, the index,
  the write guide, the connect-time instructions, and one example project
  showing the context / progress / log split.

  The guard is simple and absolute: if the folder already contains ANY .md,
  nothing is written. An existing vault is never touched, never merged, never
  "upgraded" - somebody's accumulated knowledge is not ours to rearrange.

  The templates are embedded here (not read from the repo) so a deployed
  executable can seed a vault on a machine that has nothing else on it. They
  are deliberately generic - the shape, not anybody's content - and the same
  ones shipped in examples/vault/. Pure ASCII, per the project convention.

  Runs silently: seeding happens during unit initialization, BEFORE the host
  has configured the logger (and, in stdio mode, before stdout is safe to
  write to). What happened is recorded in VaultSeedNote for the host to log
  once logging is up. }

interface

{ Creates the starter vault when APath does not exist or holds no .md at all.
  Returns True when it seeded. Never raises: a vault that cannot be created is
  simply a vault that is not there. }
function SeedVaultIfEmpty(const APath: string): Boolean;

{ What SeedVaultIfEmpty did, for the host to log once the logger exists
  ('' when it did nothing). }
function VaultSeedNote: string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Types;

var
  GNote: string = '';

const
  T_INSTRUCTIONS =
    'This server exposes a KNOWLEDGE VAULT: Markdown notes linked with' + #10 +
    '[[wikilinks]], holding the conventions, patterns, decisions and current' + #10 +
    'state of the projects worked on here.' + #10 + #10 +
    'PROTOCOL, at the start of any task:' + #10 + #10 +
    '1. Call `vault_read` with NO path. It returns the vault rules and the' + #10 +
    '   index of notes.' + #10 +
    '2. Identify which project you are working on and load its' + #10 +
    '   `projects/<name>/context.md` and `progress.md`.' + #10 +
    '3. Load anything else only on demand, when the index says it applies.' + #10 +
    '   Lazy loading: never read the vault in bulk.' + #10 + #10 +
    'If you write to the vault, read `AGENTS-VAULT-WRITE.md` first and follow' + #10 +
    'the vault own conventions.' + #10;

  T_RULES =
    '# Vault rules' + #10 + #10 +
    'Read in full at the start of every session, together with the index' + #10 +
    '([[MEMORY]]). Keep this file short - it is the one thing always loaded.' + #10 + #10 +
    '## Loading' + #10 + #10 +
    '1. **Lazy loading.** This file plus the index first; then only the notes' + #10 +
    '   the index says apply to your task. Never read the vault in bulk.' + #10 +
    '2. **Project first.** If the task is about a project, its' + #10 +
    '   `projects/<name>/context.md` (the stable why) and `progress.md` (what' + #10 +
    '   is true today) come before anything else.' + #10 +
    '3. **Follow the links.** `[[Wikilinks]]` point at other notes. Resolve' + #10 +
    '   them with `vault_search target=files`.' + #10 +
    '4. **The vault is the authority on conventions**, not your habits. When a' + #10 +
    '   note contradicts what you would do by default, the note wins.' + #10 + #10 +
    '## Writing' + #10 + #10 +
    '5. **Language.** Write notes in the language the vault is written in, no' + #10 +
    '   matter what language the conversation is in.' + #10 +
    '6. **`log.md` is history**: dated entries, append only. Never rewrite or' + #10 +
    '   reorder past entries - being able to trust the record is the point.' + #10 +
    '7. **`progress.md` is a snapshot**: only what is true today. Closing an' + #10 +
    '   item means REMOVING its line (`vault_patch`), not adding "done". If it' + #10 +
    '   needs remembering, it belongs in the log.' + #10 +
    '8. **New notes get indexed.** A note nobody can find does not exist. The' + #10 +
    '   index is human-curated: say explicitly that a line must be added.' + #10 +
    '9. **Prefer appending over rewriting.** If a note needs restructuring,' + #10 +
    '   stop and ask. A bad rewrite is invisible damage.' + #10 +
    '10. **Facts, not conclusions.** Write what happened and what was' + #10 +
    '    measured, with dates.' + #10 + #10 +
    '## Never' + #10 + #10 +
    '11. Do not reorganize folders or move existing notes without a human OK.' + #10 +
    '12. Do not touch the governance files (this one, [[MEMORY]] and' + #10 +
    '    [[AGENTS-VAULT-WRITE]]) - the server refuses anyway.' + #10 +
    '13. Do not record secrets: tokens, passwords, keys or personal data.' + #10;

  T_INDEX =
    '# MEMORY' + #10 + #10 +
    'The index of this vault. One line per note: link, then **what the note is' + #10 +
    'for** - written so a reader can decide whether to open it without opening' + #10 +
    'it. Curated by a human; agents ask for a line to be added.' + #10 + #10 +
    '## Conventions' + #10 + #10 +
    '- [Example conventions](conventions/example-conventions.md) - how we' + #10 +
    '  name, structure and review things here' + #10 + #10 +
    '## Projects' + #10 + #10 +
    '- [Example project - context](projects/example-project/context.md) - what' + #10 +
    '  it is, why it exists, the decisions that shaped it' + #10 +
    '- [Example project - progress](projects/example-project/progress.md) -' + #10 +
    '  what is true today: in flight, blocked, waiting' + #10 +
    '- [Example project - log](projects/example-project/log.md) - dated' + #10 +
    '  history of what was done and learned' + #10 + #10 +
    '## How to write a good index line' + #10 + #10 +
    '- Say what question the note answers, not what it is named.' + #10 +
    '- Keep one line. If it needs two, the note is doing too much.' + #10 +
    '- Sort by usefulness, not alphabetically.' + #10 + #10 +
    '> These example entries are here to show the shape. Replace them with' + #10 +
    '> your own as soon as you have real notes.' + #10;

  T_WRITE =
    '# How to write in this vault' + #10 + #10 +
    'Read this before creating a note. It answers one question: **where does' + #10 +
    'this go?** - and gives the templates.' + #10 + #10 +
    '## Decision tree' + #10 + #10 +
    '```' + #10 +
    'Something happened (a change, a fix, a decision taken)' + #10 +
    '   +- Is it still true right now, and does someone need to act on it?' + #10 +
    '        +- YES -> a line in projects/<name>/progress.md' + #10 +
    '        +- NO, it is history -> a dated entry in projects/<name>/log.md' + #10 + #10 +
    'Something we learned that will apply again' + #10 +
    '   +- Is it about HOW we work (naming, structure, review, style)?' + #10 +
    '        +- YES -> conventions/<topic>.md' + #10 +
    '        +- NO -> is it about WHY a project is the way it is?' + #10 +
    '             +- YES -> projects/<name>/context.md' + #10 +
    '             +- NO -> decisions/<slug>.md' + #10 +
    '```' + #10 + #10 +
    '## Templates' + #10 + #10 +
    'A project `context.md` - the stable why. Changes rarely.' + #10 + #10 +
    '```markdown' + #10 +
    '# <Project> - context' + #10 + #10 +
    '## What it is' + #10 +
    'One paragraph a newcomer could understand.' + #10 + #10 +
    '## Why it exists' + #10 +
    'The problem it solves, and what was there before.' + #10 + #10 +
    '## Shape' + #10 +
    'The pieces and how they fit.' + #10 + #10 +
    '## Decisions that stuck' + #10 +
    '- <decision> - because <reason> (<date>)' + #10 +
    '```' + #10 + #10 +
    'A project `progress.md` - a snapshot. Only what is true today.' + #10 + #10 +
    '```markdown' + #10 +
    '# <Project> - progress' + #10 + #10 +
    '## In flight' + #10 +
    '- <what is being done right now>' + #10 + #10 +
    '## Blocked / waiting' + #10 +
    '- <what, and on whom>' + #10 + #10 +
    '## Next' + #10 +
    '- <the next thing, when decided>' + #10 +
    '```' + #10 + #10 +
    'A project `log.md` - history. Append only, newest first.' + #10 + #10 +
    '```markdown' + #10 +
    '# <Project> - log' + #10 + #10 +
    '- **YYYY-MM-DD** - <what was done>. <what was learned or measured>.' + #10 +
    '```' + #10 + #10 +
    '## Rules of thumb' + #10 + #10 +
    '- **Date everything** that could age.' + #10 +
    '- **Write the measurement, not the impression.**' + #10 +
    '- **One idea per note.** If the title needs an "and", it is two notes.' + #10 +
    '- **Link generously.** A [[wikilink]] to a note that does not exist yet' + #10 +
    '  marks something worth writing.' + #10 +
    '- **The index is not optional.**' + #10;

  T_CONVENTIONS =
    '# Example conventions' + #10 + #10 +
    '> Example note - it shows the shape of a convention note. Replace it.' + #10 + #10 +
    '## Rule' + #10 + #10 +
    'Every unit that talks to the outside world (files, HTTP, database)' + #10 +
    'returns its errors; it never shows them. UI is the only layer allowed to' + #10 +
    'display anything.' + #10 + #10 +
    '## Why' + #10 + #10 +
    'A helper unit popped up a message box during a nightly unattended run and' + #10 +
    'the import hung until someone clicked OK the next morning (2024-01-22).' + #10 +
    'The rule exists because of that morning.' + #10 + #10 +
    '## Exceptions' + #10 + #10 +
    'None. If a helper "needs" to ask the user something, the design is wrong:' + #10 +
    'pass the decision back to the caller.' + #10;

  T_CONTEXT =
    '# Example project - context' + #10 + #10 +
    '> Example note: the stable "why" of a project, the part that does not' + #10 +
    '> change week to week. Replace all of it.' + #10 + #10 +
    '## What it is' + #10 + #10 +
    'A small service that imports supplier price lists and publishes them to' + #10 +
    'the main application. Runs unattended, nightly.' + #10 + #10 +
    '## Why it exists' + #10 + #10 +
    'Prices used to be pasted by hand, which meant a day of lag and regular' + #10 +
    'typos in the decimals. The importer removed both.' + #10 + #10 +
    '## Shape' + #10 + #10 +
    '- **Reader** - one adapter per supplier format.' + #10 +
    '- **Normalizer** - currency, VAT and unit conversion. All business rules' + #10 +
    '  live here; the adapters stay dumb on purpose.' + #10 +
    '- **Publisher** - writes to staging tables, never to live ones.' + #10 + #10 +
    '## Decisions that stuck' + #10 + #10 +
    '- **Nightly, not on demand** - two suppliers only refresh once a day and' + #10 +
    '  a third rate-limits hard, so on demand added latency and no freshness' + #10 +
    '  (2024-02-11).' + #10 +
    '- **Staging tables instead of direct writes** - one bad import reached' + #10 +
    '  production prices; staging plus a diff review made that impossible' + #10 +
    '  (2024-03-02).' + #10 +
    '- **Adapters never convert** - an early adapter did its own VAT maths and' + #10 +
    '  drifted from the rest. Conversion belongs in one place (2024-05-19).' + #10 + #10 +
    'See also [[Example conventions]].' + #10;

  T_PROGRESS =
    '# Example project - progress' + #10 + #10 +
    '> Snapshot: only what is true TODAY. History goes in the log. Closing' + #10 +
    '> something means deleting its line, not writing "done" under it.' + #10 +
    '> Example note - replace all of it.' + #10 + #10 +
    '## In flight' + #10 + #10 +
    '- New supplier adapter (XLSX with merged header rows) - reader works, the' + #10 +
    '  normalizer chokes on their unit column.' + #10 + #10 +
    '## Blocked / waiting' + #10 + #10 +
    '- Supplier C credentials - requested 2024-06-03, no answer yet.' + #10 + #10 +
    '## Next' + #10 + #10 +
    '- Decide whether to keep the SOAP adapter or ask for a CSV feed.' + #10;

  T_LOG =
    '# Example project - log' + #10 + #10 +
    '> History: dated entries, newest first, append only. Never rewritten -' + #10 +
    '> the value of a log is that you can trust it.' + #10 +
    '> Example note - replace all of it.' + #10 + #10 +
    '- **2024-06-05** - Added the XLSX adapter for the new supplier. Their' + #10 +
    '  header spans two merged rows, so the reader looks for the first row' + #10 +
    '  with a numeric price cell instead of assuming row 1. Import: 4812 rows' + #10 +
    '  in 38 s. The unit column is free text ("box of 12", "cx12", "12u") and' + #10 +
    '  the normalizer rejects all of it - needs a lookup table, not a parser.' + #10 + #10 +
    '- **2024-05-19** - One adapter was doing its own VAT maths and had' + #10 +
    '  drifted 0.3 % since March. Moved all conversion into the normalizer.' + #10 +
    '  Lesson: adapters read, they never interpret.' + #10 + #10 +
    '- **2024-03-02** - A malformed import reached live prices (a decimal' + #10 +
    '  comma read as a thousands separator). Introduced staging tables plus a' + #10 +
    '  diff review before publish. Caught two similar cases since.' + #10;

function VaultSeedNote: string;
begin
  Result := GNote;
end;

{ True when the folder holds no .md at all (at any depth). A folder with other
  files but no notes still counts as an empty VAULT. }
function HasNotes(const APath: string): Boolean;
begin
  Result := False;
  try
    Result := Length(TDirectory.GetFiles(APath, '*.md',
      TSearchOption.soAllDirectories)) > 0;
  except
    // unreadable: treat as "has content" so we never write into it
    Result := True;
  end;
end;

procedure WriteNote(const APath, AText: string);
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(APath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  // UTF-8 without BOM, same as every other vault write.
  TFile.WriteAllBytes(APath, TEncoding.UTF8.GetBytes(AText));
end;

function SeedVaultIfEmpty(const APath: string): Boolean;
var
  Root: string;
begin
  Result := False;
  GNote := '';
  if APath.Trim = '' then
    Exit;
  try
    Root := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath.Trim));
    if TDirectory.Exists(Root) then
    begin
      if HasNotes(Root) then
        Exit; // an existing vault is never touched
    end
    else
      TDirectory.CreateDirectory(Root);

    WriteNote(TPath.Combine(Root, 'VAULT-INSTRUCTIONS.md'), T_INSTRUCTIONS);
    WriteNote(TPath.Combine(Root, 'AGENTS-VAULT.md'), T_RULES);
    WriteNote(TPath.Combine(Root, 'MEMORY.md'), T_INDEX);
    WriteNote(TPath.Combine(Root, 'AGENTS-VAULT-WRITE.md'), T_WRITE);
    WriteNote(TPath.Combine(Root, 'conventions\example-conventions.md'), T_CONVENTIONS);
    WriteNote(TPath.Combine(Root, 'projects\example-project\context.md'), T_CONTEXT);
    WriteNote(TPath.Combine(Root, 'projects\example-project\progress.md'), T_PROGRESS);
    WriteNote(TPath.Combine(Root, 'projects\example-project\log.md'), T_LOG);

    GNote := 'Vault: empty folder at "' + Root + '" seeded with the starter ' +
      'templates (rules, index, write guide and an example project). Edit ' +
      'MEMORY.md and VAULT-INSTRUCTIONS.md to make it yours.';
    Result := True;
  except
    on E: Exception do
      GNote := 'Vault: could not create the starter vault at "' + APath +
        '" (' + E.Message + ').';
  end;
end;

end.
