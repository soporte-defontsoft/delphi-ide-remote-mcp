unit Mcp.Tools.Vault;

{ vault_*: remote access to a KNOWLEDGE VAULT - a folder of Markdown notes
  linked with [[wikilinks]] (an Obsidian vault), so an agent working through
  this MCP has persistent memory besides the source tree.

  The split of responsibilities is deliberate:
  - the SERVER provides the mechanism (search, read, append, create, patch)
    and enforces every rule that CAN be enforced by code - jail, .md only,
    governance files protected, automatic backup before any modification;
  - the VAULT provides the doctrine: its own rules live inside it
    (AGENTS-VAULT.md) and its index (MEMORY.md) says what each note is for.
    Nothing about a particular vault's conventions is hardcoded here.

  Lazy loading is the protocol: an agent calls vault_read with NO path to get
  rules + index in one call, and only then decides which notes to load. The
  vault is never read in bulk.

  Registration is conditional: the read tools appear only when [Vault] Path
  points at an existing folder, and the write tools only when [Vault]
  ReadOnly=0 as well. Writing is additionally refused for a read-only
  credential at the single entry gate (Lsp.Guard).

  Encoding: a vault is UTF-8 (unlike Delphi sources, which are often CP1252),
  so none of the Delphi encoding machinery applies here. Written back as
  UTF-8 WITHOUT BOM, which is what Obsidian and git expect. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types;

type
  TVaultSearchParams = class
  private
    FTarget: string;
    FPattern: string;
    FSubfolder: string;
    FMaxResults: Integer;
  public
    [SchemaDescription('files (buscar por NOMBRE de nota, patron glob como *reunion*.md) | content (buscar DENTRO de las notas, pattern es una expresion regular)')]
    property Target: string read FTarget write FTarget;
    [SchemaDescription('Glob de nombre si target=files (*.md, *delphi*), o expresion regular si target=content')]
    property Pattern: string read FPattern write FPattern;
    [SchemaDescription('Opcional: carpeta relativa del vault para acotar la busqueda (projects, conventions...)')]
    property Subfolder: string read FSubfolder write FSubfolder;
    [SchemaDescription('Maximo de resultados (defecto 50)')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
  end;

  TVaultReadParams = class
  private
    FPath: string;
    FOffset: Integer;
    FLimit: Integer;
  public
    [SchemaDescription('Ruta RELATIVA de la nota dentro del vault (projects/x/context.md). SIN path devuelve las reglas + el indice: hazlo al empezar')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Opcional: primera linea a devolver (1 = principio)')]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription('Opcional: cuantas lineas devolver desde offset')]
    property Limit: Integer read FLimit write FLimit;
  end;

  TVaultAppendParams = class
  private
    FPath: string;
    FContent: string;
    FAnchor: string;
  public
    [SchemaDescription('Ruta RELATIVA de la nota (debe existir)')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Contenido markdown a anadir. En espanol')]
    property Content: string read FContent write FContent;
    [SchemaDescription('Opcional: texto UNICO tras el cual insertar. Sin anchor, anade al final del fichero')]
    property Anchor: string read FAnchor write FAnchor;
  end;

  TVaultCreateParams = class
  private
    FPath: string;
    FContent: string;
  public
    [SchemaDescription('Ruta RELATIVA de la nota nueva (debe NO existir; nunca sobreescribe)')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Contenido markdown completo, con la estructura/plantilla que pida el vault')]
    property Content: string read FContent write FContent;
  end;

  TVaultPatchParams = class
  private
    FPath: string;
    FOldText: string;
    FNewText: string;
  public
    [SchemaDescription('Ruta RELATIVA de la nota')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Texto a sustituir: debe aparecer EXACTAMENTE UNA VEZ en el fichero')]
    property Old_Text: string read FOldText write FOldText;
    [SchemaDescription('Texto nuevo que lo sustituye')]
    property New_Text: string read FNewText write FNewText;
  end;

  TVaultSearchTool = class(TMCPToolBase<TVaultSearchParams>)
  protected
    function ExecuteWithParams(const Params: TVaultSearchParams): string; override;
  public
    constructor Create; override;
  end;

  TVaultReadTool = class(TMCPToolBase<TVaultReadParams>)
  protected
    function ExecuteWithParams(const Params: TVaultReadParams): string; override;
  public
    constructor Create; override;
  end;

  TVaultAppendTool = class(TMCPToolBase<TVaultAppendParams>)
  protected
    function ExecuteWithParams(const Params: TVaultAppendParams): string; override;
  public
    constructor Create; override;
  end;

  TVaultCreateTool = class(TMCPToolBase<TVaultCreateParams>)
  protected
    function ExecuteWithParams(const Params: TVaultCreateParams): string; override;
  public
    constructor Create; override;
  end;

  TVaultPatchTool = class(TMCPToolBase<TVaultPatchParams>)
  protected
    function ExecuteWithParams(const Params: TVaultPatchParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Masks,
  System.RegularExpressions,
  System.Generics.Collections,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.Guard,
  Lsp.Texts,
  Mcp.Vault.Session;

const
  MAX_READ_CHARS = 100000; // ~25-35K tokens: protects a small model's context
  BOOT_RULES = 'AGENTS-VAULT.md';
  BOOT_INDEX = 'MEMORY.md';
  BACKUP_SUB = 'backups';

var
  GSessionStamp: string = ''; // one backup folder per server run

{ ---------------------------------------------------------------- helpers -- }

{ Folders that are never part of the knowledge: the server's own backups, git
  and tool metadata. Takes a vault-relative path with backslashes. }
function VaultExcluded(const ARel: string): Boolean;
const
  Dirs: array [0 .. 4] of string = ('backups\', '.git\', '.obsidian\',
    '.claude\', '.trash\');
var
  Low, D: string;
begin
  Low := ARel.Replace('/', '\').ToLower;
  if Low.Contains('.bak') then
    Exit(True);
  for D in Dirs do
    if Low.StartsWith(D) or Low.Contains('\' + D) then
      Exit(True);
  Result := False;
end;

{ The vault's own governance files: its rules and its index. A human curates
  these; an agent may READ them (that is the bootstrap) but never write them. }
function VaultGovernance(const ARel: string): Boolean;
var
  Name: string;
begin
  Name := TPath.GetFileName(ARel.Replace('/', '\'));
  Result := SameText(Name, BOOT_RULES) or SameText(Name, BOOT_INDEX) or
    SameText(Name, 'AGENTS-VAULT-WRITE.md');
end;

{ Resolves a vault-relative path to a full path inside the vault. Returns ''
  on success (AFull set), or the rejection message. The jail is strict: no
  absolute paths, no drive letters, no ".." escape, .md only. }
function VaultResolve(const ARel: string; out AFull: string): string;
var
  Rel, Full, Root: string;
begin
  AFull := '';
  Rel := ARel.Trim.Trim(['"']).Trim.Replace('/', '\');
  if Rel = '' then
    Exit('error: falta "path" (ruta relativa dentro del vault)');
  while Rel.StartsWith('\') do
    Rel := Rel.Substring(1);
  if Rel.Contains(':') then
    Exit(Format(SR_VAULT_JAIL_FMT, [ARel]));
  for var Seg in Rel.Split(['\']) do
    if Seg.Trim = '..' then
      Exit(Format(SR_VAULT_JAIL_FMT, [ARel]));
  if not SameText(TPath.GetExtension(Rel), '.md') then
    Exit(Format('RECHAZADO: "%s" no es una nota .md. El vault solo sirve ' +
      'notas Markdown.', [ARel]));
  if VaultExcluded(Rel) then
    Exit(Format('RECHAZADO: "%s" esta en una carpeta excluida (backups, .git, ' +
      '.obsidian): no es conocimiento del vault.', [ARel]));
  Root := VaultPath;
  try
    Full := TPath.GetFullPath(TPath.Combine(Root, Rel));
  except
    Exit(Format(SR_VAULT_JAIL_FMT, [ARel]));
  end;
  // Belt and braces: whatever the input did, the result must live in the vault.
  if not StartsText(IncludeTrailingPathDelimiter(Root), Full) then
    Exit(Format(SR_VAULT_JAIL_FMT, [ARel]));
  AFull := Full;
  Result := '';
end;

function VaultRelative(const AFull: string): string;
begin
  Result := AFull.Substring(Length(IncludeTrailingPathDelimiter(VaultPath)));
end;

{ Vault rule 11 made mechanical: the ORIGINAL of any note we are about to
  modify is copied to backups\mcp\<stamp>\<relative path> inside the vault,
  before the change. One folder per server run, and the FIRST copy of a file
  is kept (never overwritten by a later edit in the same run), so what is
  preserved is always the state before this session touched it. }
function VaultBackup(const AFull: string): string;
var
  Dest, DestDir: string;
begin
  Result := '';
  if not TFile.Exists(AFull) then
    Exit; // nothing to preserve (vault_create)
  if GSessionStamp = '' then
    GSessionStamp := FormatDateTime('yyyymmdd_hhnnss', Now);
  Dest := TPath.Combine(TPath.Combine(TPath.Combine(VaultPath, BACKUP_SUB),
    'mcp\' + GSessionStamp), VaultRelative(AFull));
  if TFile.Exists(Dest) then
    Exit(Dest); // already preserved earlier in this run: keep the original
  DestDir := TPath.GetDirectoryName(Dest);
  if not TDirectory.Exists(DestDir) then
    TDirectory.CreateDirectory(DestDir);
  TFile.Copy(AFull, Dest);
  Result := Dest;
end;

function VaultLoad(const AFull: string): string;
begin
  // UTF-8 (with or without BOM); never the Delphi CP1252 pipeline.
  Result := TFile.ReadAllText(AFull, TEncoding.UTF8);
end;

procedure VaultSave(const AFull, AText: string);
begin
  // UTF-8 WITHOUT BOM: GetBytes omits the preamble that WriteAllText would add.
  TFile.WriteAllBytes(AFull, TEncoding.UTF8.GetBytes(AText));
end;

{ Every .md note under ADir (recursive), excluding the non-knowledge folders.
  Tolerant: an unreadable subtree is skipped, never fatal. }
procedure CollectNotes(const ADir: string; AAcc: TStrings);
var
  F, Sub: string;
begin
  try
    for F in TDirectory.GetFiles(ADir, '*.md') do
      if not VaultExcluded(VaultRelative(F)) then
        AAcc.Add(F);
  except
  end;
  try
    for Sub in TDirectory.GetDirectories(ADir) do
      if not VaultExcluded(VaultRelative(Sub) + '\') then
        CollectNotes(Sub, AAcc);
  except
  end;
end;

{ Numbered rendering, same shape as delphi_read: "N|line". }
function Numbered(const AText: string; AOffset, ALimit: Integer;
  out ATotalLines: Integer): string;
var
  Lines: TArray<string>;
  Sb: TStringBuilder;
  I, First, Last: Integer;
begin
  // Normalize line endings FIRST: a vault edited on Windows is CRLF, and
  // String.Replace without rfReplaceAll only ever touches the FIRST match -
  // which left a stray CR at the end of every line (measured against a real
  // CRLF vault; an LF-only test fixture hid it).
  Lines := AText.Replace(#13#10, #10, [rfReplaceAll]).Split([#10]);
  ATotalLines := Length(Lines);
  First := 1;
  if AOffset > 0 then
    First := AOffset;
  Last := ATotalLines;
  if ALimit > 0 then
    Last := First + ALimit - 1;
  if Last > ATotalLines then
    Last := ATotalLines;
  Sb := TStringBuilder.Create;
  try
    for I := First to Last do
      Sb.AppendLine(I.ToString + '|' + Lines[I - 1]);
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ ------------------------------------------------------------ vault_search - }

constructor TVaultSearchTool.Create;
begin
  inherited;
  FName := 'vault_search';
  FDescription := SD_VAULT_SEARCH;
end;

function TVaultSearchTool.ExecuteWithParams(const Params: TVaultSearchParams): string;
var
  Notes: TStringList;
  Root, Rel, Pat, Line: string;
  Max, Hits, LineNo: Integer;
  Sb: TStringBuilder;
  ByContent: Boolean;
  Rx: TRegEx;
  F: string;
begin
  if not VaultConfigured then
    Exit(SR_VAULT_UNSET);
  Pat := Params.Pattern.Trim;
  if Pat = '' then
    Exit('error: falta "pattern"');
  ByContent := SameText(Params.Target.Trim, 'content');
  Max := Params.MaxResults;
  if Max <= 0 then
    Max := 50;
  if Max > 500 then
    Max := 500;

  Root := VaultPath;
  if Params.Subfolder.Trim <> '' then
  begin
    // Reuse the jail by resolving a dummy note inside the subfolder.
    var Probe := '';
    Result := VaultResolve(IncludeTrailingPathDelimiter(
      Params.Subfolder.Trim.Replace('/', '\')) + 'x.md', Probe);
    if Result <> '' then
      Exit;
    Root := TPath.GetDirectoryName(Probe);
    if not TDirectory.Exists(Root) then
      Exit(Format('error: la subcarpeta "%s" no existe en el vault',
        [Params.Subfolder.Trim]));
  end;

  if ByContent then
    try
      Rx := TRegEx.Create(Pat, [roIgnoreCase]);
    except
      on E: Exception do
        Exit('error: "pattern" no es una expresion regular valida (' +
          E.Message + ')');
    end;

  Notes := TStringList.Create;
  Sb := TStringBuilder.Create;
  try
    CollectNotes(Root, Notes);
    Notes.Sort;
    Hits := 0;
    for F in Notes do
    begin
      if Hits >= Max then
        Break;
      Rel := VaultRelative(F);
      if ByContent then
      begin
        var Text := '';
        try
          Text := VaultLoad(F);
        except
          Continue;
        end;
        LineNo := 0;
        for Line in Text.Replace(#13#10, #10, [rfReplaceAll]).Split([#10]) do
        begin
          Inc(LineNo);
          if Rx.IsMatch(Line) then
          begin
            Sb.AppendLine(Format('%s:%d: %s', [Rel, LineNo, Line.Trim]));
            Inc(Hits);
            if Hits >= Max then
              Break;
          end;
        end;
      end
      else if MatchesMask(TPath.GetFileName(F), Pat) or
              MatchesMask(Rel, Pat) then
      begin
        Sb.AppendLine(Rel);
        Inc(Hits);
      end;
    end;
    if Hits = 0 then
      Result := Format('Sin resultados para "%s" (%s). Recuerda: el indice ' +
        '(vault_read sin path) dice que notas existen y para que sirven.',
        [Pat, IfThen(ByContent, 'contenido', 'nombres')])
    else
      Result := Format('%d resultado(s)%s:'#10#10, [Hits,
        IfThen(Hits >= Max, ' (tope alcanzado)', '')]) + Sb.ToString;
  finally
    Sb.Free;
    Notes.Free;
  end;
end;

{ -------------------------------------------------------------- vault_read - }

constructor TVaultReadTool.Create;
begin
  inherited;
  FName := 'vault_read';
  FDescription := SD_VAULT_READ;
end;

function TVaultReadTool.ExecuteWithParams(const Params: TVaultReadParams): string;
var
  Full, Text, Rel: string;
  Total: Integer;
begin
  if not VaultConfigured then
    Exit(SR_VAULT_UNSET);

  // Bootstrap: no path = the vault's own rules + its index, in one call. The
  // names of these two files are a vault convention, not something a remote
  // agent should have to know.
  if Params.Path.Trim = '' then
  begin
    Result := VaultBootstrapText; // shared with the /vault prompt
    if Length(Result) > MAX_READ_CHARS then
      Result := Copy(Result, 1, MAX_READ_CHARS) + #10#10 +
        Format(SR_VAULT_TRUNCATED_FMT, [MAX_READ_CHARS]);
    Exit;
  end;

  Result := VaultResolve(Params.Path, Full);
  if Result <> '' then
    Exit;
  if not TFile.Exists(Full) then
    Exit(Format('error: la nota "%s" no existe en el vault. Localizala con ' +
      'vault_search target=files.', [Params.Path.Trim]));
  try
    Text := VaultLoad(Full);
  except
    on E: Exception do
      Exit('error: no se pudo leer la nota (' + E.Message + ')');
  end;
  Rel := VaultRelative(Full);
  Result := Numbered(Text, Params.Offset, Params.Limit, Total);
  if Length(Result) > MAX_READ_CHARS then
    Result := Copy(Result, 1, MAX_READ_CHARS) + #10#10 +
      Format(SR_VAULT_TRUNCATED_FMT, [MAX_READ_CHARS]);
  Result := Format('# %s (%d lineas)'#10#10, [Rel, Total]) + Result;
end;

{ ------------------------------------------------------------ vault_append - }

constructor TVaultAppendTool.Create;
begin
  inherited;
  FName := 'vault_append';
  FDescription := SD_VAULT_APPEND;
end;

function TVaultAppendTool.ExecuteWithParams(const Params: TVaultAppendParams): string;
var
  Full, Text, Add, Anchor, Backup: string;
  P: Integer;
begin
  if not VaultWritable then
    Exit(SR_VAULT_READONLY);
  Result := VaultResolve(Params.Path, Full);
  if Result <> '' then
    Exit;
  if VaultGovernance(Params.Path) then
    Exit(SR_VAULT_GOVERNANCE);
  if not TFile.Exists(Full) then
    Exit(Format('error: la nota "%s" no existe. vault_append solo anade a ' +
      'notas existentes; para una nota nueva usa vault_create.',
      [Params.Path.Trim]));
  Add := Params.Content;
  if Add.Trim = '' then
    Exit('error: falta "content"');

  try
    Text := VaultLoad(Full);
  except
    on E: Exception do
      Exit('error: no se pudo leer la nota (' + E.Message + ')');
  end;

  Anchor := Params.Anchor;
  if Anchor.Trim <> '' then
  begin
    P := Pos(Anchor, Text);
    if P = 0 then
      Exit(Format('error: el anchor no aparece en la nota. Lee la nota con ' +
        'vault_read y copia un fragmento EXACTO de ella.', []));
    if Pos(Anchor, Text, P + Length(Anchor)) > 0 then
      Exit('error: el anchor aparece VARIAS veces; usa un fragmento mas ' +
        'largo que sea unico en la nota.');
    Insert(#10 + Add.TrimRight + #10, Text, P + Length(Anchor));
  end
  else
  begin
    if not Text.EndsWith(#10) then
      Text := Text + #10;
    Text := Text + Add.TrimRight + #10;
  end;

  Backup := VaultBackup(Full); // rule 11, before touching anything
  VaultSave(Full, Text);
  TLogger.Info('vault_append: ' + VaultRelative(Full));
  Result := Format('ANADIDO a %s (%s). Copia previa en %s.',
    [VaultRelative(Full),
     IfThen(Anchor.Trim <> '', 'tras el anchor', 'al final'),
     IfThen(Backup = '', '(sin copia)', VaultRelative(Backup))]);
end;

{ ------------------------------------------------------------ vault_create - }

constructor TVaultCreateTool.Create;
begin
  inherited;
  FName := 'vault_create';
  FDescription := SD_VAULT_CREATE;
end;

function TVaultCreateTool.ExecuteWithParams(const Params: TVaultCreateParams): string;
var
  Full, Dir: string;
begin
  if not VaultWritable then
    Exit(SR_VAULT_READONLY);
  Result := VaultResolve(Params.Path, Full);
  if Result <> '' then
    Exit;
  if VaultGovernance(Params.Path) then
    Exit(SR_VAULT_GOVERNANCE);
  if TFile.Exists(Full) then
    Exit(Format('RECHAZADO: la nota "%s" YA existe. vault_create nunca ' +
      'sobreescribe: usa vault_append para anadir, o vault_patch para ' +
      'corregir un fragmento.', [Params.Path.Trim]));
  if Params.Content.Trim = '' then
    Exit('error: falta "content" (la nota nueva no puede estar vacia)');

  Dir := TPath.GetDirectoryName(Full);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  VaultSave(Full, Params.Content.TrimRight + #10);
  TLogger.Info('vault_create: ' + VaultRelative(Full));
  Result := Format('CREADA la nota %s. Recuerda enlazarla desde el indice ' +
    'que corresponda con [[wikilinks]] (vault_append sobre ese indice).',
    [VaultRelative(Full)]);
end;

{ ------------------------------------------------------------- vault_patch - }

constructor TVaultPatchTool.Create;
begin
  inherited;
  FName := 'vault_patch';
  FDescription := SD_VAULT_PATCH;
end;

function TVaultPatchTool.ExecuteWithParams(const Params: TVaultPatchParams): string;
var
  Full, Text, Backup: string;
  P: Integer;
begin
  if not VaultWritable then
    Exit(SR_VAULT_READONLY);
  Result := VaultResolve(Params.Path, Full);
  if Result <> '' then
    Exit;
  if VaultGovernance(Params.Path) then
    Exit(SR_VAULT_GOVERNANCE);
  if not TFile.Exists(Full) then
    Exit(Format('error: la nota "%s" no existe.', [Params.Path.Trim]));
  if Params.Old_Text = '' then
    Exit('error: falta "old_text"');

  try
    Text := VaultLoad(Full);
  except
    on E: Exception do
      Exit('error: no se pudo leer la nota (' + E.Message + ')');
  end;

  P := Pos(Params.Old_Text, Text);
  if P = 0 then
    Exit('error: "old_text" no aparece en la nota. Lee la nota con vault_read ' +
      'y copia el fragmento EXACTO (los numeros de linea NO son parte del texto).');
  if Pos(Params.Old_Text, Text, P + Length(Params.Old_Text)) > 0 then
    Exit('error: "old_text" aparece VARIAS veces en la nota; amplia el ' +
      'fragmento hasta que sea unico.');

  Text := Copy(Text, 1, P - 1) + Params.New_Text +
    Copy(Text, P + Length(Params.Old_Text), MaxInt);
  Backup := VaultBackup(Full); // rule 11, before touching anything
  VaultSave(Full, Text);
  TLogger.Info('vault_patch: ' + VaultRelative(Full));
  Result := Format('MODIFICADA %s (1 sustitucion). Copia previa en %s.',
    [VaultRelative(Full), IfThen(Backup = '', '(sin copia)', VaultRelative(Backup))]);
end;

initialization
  // Conditional registration: no vault configured, no vault tools in
  // tools/list at all. Writing needs [Vault] ReadOnly=0 as well - and, on top
  // of that, a read-write credential (enforced at the gate).
  if VaultConfigured then
  begin
    TMCPRegistry.RegisterTool('vault_search',
      function: IMCPTool begin Result := TVaultSearchTool.Create; end);
    TMCPRegistry.RegisterTool('vault_read',
      function: IMCPTool begin Result := TVaultReadTool.Create; end);
    if VaultWritable then
    begin
      TMCPRegistry.RegisterTool('vault_append',
        function: IMCPTool begin Result := TVaultAppendTool.Create; end);
      TMCPRegistry.RegisterTool('vault_create',
        function: IMCPTool begin Result := TVaultCreateTool.Create; end);
      TMCPRegistry.RegisterTool('vault_patch',
        function: IMCPTool begin Result := TVaultPatchTool.Create; end);
    end;
  end;

end.
