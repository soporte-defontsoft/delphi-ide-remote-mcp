unit Mcp.Tools.DelphiPatch;

{ delphi_read + delphi_edit: encoding-correct reading and SAFE editing of
  Delphi sources, so any model - large or small - can modify code through
  this MCP without corrupting it. Engine in Lsp.Patch. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes,  // [RutaDelServidor]: que parametro es una ruta NUESTRA
  Lsp.Patch;

type
  TDelphiReadParams = class
  private
    FPath: string;
    FFromLine: Integer;
    FToLine: Integer;
  public
    [SchemaDescription('Absolute path of the Delphi file (.pas/.dpr/.dpk/.inc/.dfm/.fmx)')]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription('First line to show, 1-based (0 = from the start)')]
    property FromLine: Integer read FFromLine write FFromLine;
    [SchemaDescription('Last line to show, 1-based (0 = to the end; capped at 400 lines per call)')]
    property ToLine: Integer read FToLine write FToLine;
  end;

  TDelphiPatchParams = class
  private
    FPath: string;
    FOld: string;
    FNew: string;
    FAtLine: Integer;
    FToLine: Integer;
    FEdits: string;
    FFragment: string;
    FDelete: Boolean;
    FInsert: string;
    FCode: string;
    FInClass: string;
    FVisibility: string;
    FVisible: Boolean;
    FCreateUnit: Boolean;
    FContent: string;
    FEol: string;
    FRestore: Boolean;
    FConfirm: Boolean;
    FAddUses: string;
    FSection: string;
    FRemoveUses: string;
  public
    [SchemaDescription('Absolute path of the Delphi file')]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription('EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the | bar). Leading indentation may be omitted')]
    property Old: string read FOld write FOld;
    [SchemaDescription('EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new together with the added code)')]
    property New: string read FNew write FNew;
    [SchemaDescription('EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers)')]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription(SP_PATCH_TOLINE)]
    property ToLine: Integer read FToLine write FToLine;
    [SchemaDescription(SP_PATCH_EDITS)]
    property Edits: string read FEdits write FEdits;
    [SchemaDescription(SP_PATCH_FRAGMENT)]
    property Fragment: string read FFragment write FFragment;
    [SchemaDescription('DELETE mode: true = remove the "old" anchored line ENTIRELY (old+new="" only blanks it). No "new" here')]
    property Delete: Boolean read FDelete write FDelete;
    [SchemaDescription('INSERT mode (preferred for NEW routines/methods): "rutina-global" or "metodo". The tool places the block at the legal boundary (in a .dpr: between uses and the main begin; in a unit: before the final end./initialization); with "metodo" it also writes the class declaration. Pass code, not old/new')]
    property Insert: string read FInsert write FInsert;
    [SchemaDescription('INSERT mode: the COMPLETE block (unqualified signature + begin..end;). NEVER include end.')]
    property Code: string read FCode write FCode;
    [SchemaDescription('INSERT "metodo": exact class name (e.g. TFichaPedidos)')]
    property InClass: string read FInClass write FInClass;
    [SchemaDescription('INSERT "metodo" optional: section for the declaration (private/protected/public/published); empty = end of class. "published" works on form classes even without an explicit keyword: the declaration lands in the implicit published section right after the class header - the place for event handlers')]
    property Visibility: string read FVisibility write FVisibility;
    [SchemaDescription('INSERT "rutina-global" optional: true = also declare it in the interface section (visible outside the unit)')]
    property Visible: Boolean read FVisible write FVisible;
    [SchemaDescription('CREATE mode: true = create the .pas (never overwrites). Then register it in the .dpr uses clause')]
    property CreateUnit: Boolean read FCreateUnit write FCreateUnit;
    [SchemaDescription('CREATE mode: the COMPLETE file content in one call (empty = standard IDE skeleton). Use this when you already know the whole unit: one call instead of create + N patches')]
    property Content: string read FContent write FContent;
    [SchemaDescription('CREATE mode: line endings, "crlf" (default, Delphi standard) or "lf"')]
    property Eol: string read FEol write FEol;
    [SchemaDescription('RESTORE mode: true = restore the file from this tool''s backup. First call shows what would be LOST; repeat with confirm=true to execute')]
    property Restore: Boolean read FRestore write FRestore;
    [SchemaDescription('Only with restore: execute after having seen the losses')]
    property Confirm: Boolean read FConfirm write FConfirm;
    [SchemaDescription('ADDUSES mode: unit names to add to a uses clause of this .pas, separated by ; (System.SysUtils;UCliente). The engine writes the commas and the terminator, creates the clause under the section keyword when there is none, and skips the names already there, in this section or in the other one (idempotent; a unit cannot be in both, E2004). For a .dpr/.dpk use delphi_config add-unit instead')]
    property AddUses: string read FAddUses write FAddUses;
    [SchemaDescription('ADDUSES mode: "interface" or "implementation" (default implementation: a new unit goes there unless one of its types is used in the interface)')]
    property Section: string read FSection write FSection;
    [SchemaDescription('REMOVEUSES mode: unit names to take out of the uses clause of "section", separated by ; - the inverse of adduses. A directive around the entry stays glued to its neighbour, and the clause goes whole when it empties. Names not there are reported, not an error. For a .dpr/.dpk use delphi_config remove-unit')]
    property RemoveUses: string read FRemoveUses write FRemoveUses;
  end;

  TDelphiReadTool = class(TMCPToolBase<TDelphiReadParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiReadParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiPatchTool = class(TMCPToolBase<TDelphiPatchParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPatchParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  System.JSON,
  Lsp.Guard,
  Lsp.ProjectUnits,
  MCPServer.Registration;

{ TDelphiReadTool }

constructor TDelphiReadTool.Create;
begin
  inherited;
  FName := 'delphi_read';
  FDescription := 'Read a Delphi source file DECODED CORRECTLY (CP1252 / ' +
    'UTF-8 with or without BOM / UTF-16 detected for real). Returns numbered lines in ' +
    'the format number|content - to build a delphi_edit anchor, copy ' +
    'everything after the bar, exactly. ALWAYS use this instead of a generic ' +
    'read for Delphi files: generic reads turn CP1252 accents into U+FFFD ' +
    'and poison every anchor built from them.';
end;

function TDelphiReadTool.ExecuteWithParams(const Params: TDelphiReadParams): string;
begin
  Result := ReadNumbered(Params.Path, Params.FromLine, Params.ToLine);
end;

{ TDelphiPatchTool }

constructor TDelphiPatchTool.Create;
begin
  inherited;
  FName := 'delphi_edit';
  FDescription := 'SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus ' +
    'text .dfm/.fmx) preserving the real encoding and line endings. Modes: ' +
    'EDIT (old = ONE full line copied from delphi_read + new; for a LONG ' +
    'line, fragment + atline + new changes just a piece of it), DELETE ' +
    '(delete=true + old: removes the line entirely), INSERT ' +
    '(insert="rutina-global"|"metodo" + code: the tool picks the legal spot ' +
    '- also inside a .dpr - and, for methods, writes BOTH halves: ' +
    'declaration and qualified implementation), CREATE (createunit=true; ' +
    'new files honour the encoding configured in the IDE) and RESTORE ' +
    '(restore=true, two-step), ADDUSES (adduses="UnitA;UnitB" + ' +
    'section=interface|implementation: the units land in that section''s ' +
    'uses clause, commas and terminator written by the engine, the clause ' +
    'created under the section keyword when there is none, names already ' +
    'there skipped) and REMOVEUSES (removeuses="UnitA", the inverse: the ' +
    'clause goes whole when it empties; a .dpr/.dpk goes through ' +
    'delphi_config add-unit / remove-unit). It ' +
    'refuses to rewrite whole files, refuses ' +
    'binary designer files (TPF0), makes automatic backups, writes ' +
    'atomically, and audits the result (encoding, EOLs, mojibake, end. ' +
    'structure) reporting the REAL lines read back from disk - use that as ' +
    'evidence. Never edit Delphi files with generic tools: CP1252 sources ' +
    'get destroyed.';
end;

// Several anchored edits on ONE file, in one call, all or nothing.
//
// Why: stitching a new unit into an existing class took thirteen separate
// delphi_edit calls (uses, a field, two declarations, a property, constructor,
// destructor, four bodies), every anchor resolving first time. The anchor
// contract was never the problem - the granularity was. A changeset does give
// atomicity but costs begin + N stages + preview + commit, so for a SINGLE
// file the cheap road was the unsafe one and the safe road was the expensive
// one (measured 2026-08-25). This is the cheap road, made safe: the file is
// snapshotted before the first edit and restored whole if any of them fails.
//
// Format: a JSON array, [{"old": "...", "new": "...", "atline": 12}, ...],
// applied IN ORDER, each one with exactly the semantics of a single edit.
// Un ancla de VARIAS lineas se sustituye entera con ApplyBlockEdit, y
// "occurrence" se resuelve con NthOccurrenceLine EN EL MOMENTO en que corre
// la entrada, asi que sigue al fichero segun la tanda lo reordena. Las dos
// viven en Lsp.Patch desde 2026-09-20 para que delphi_textedit tenga lo
// mismo: son genericas, no tienen nada de Pascal.
function ApplyEdits(const APath, AEditsJson: string): string;
begin
  // El motor de tandas vive en Lsp.Patch (AplicaTanda) y lo comparten las DOS
  // tools de escritura. Aqui solo queda lo que es de delphi_edit: como se
  // aplica UNA edicion suelta sobre un fuente Pascal. Eran 132 lineas con un
  // 78% identico a las de delphi_textedit, y esa duplicacion se cobro el bug
  // de "occurrence" DOS veces el mismo dia.
  Result := AplicaTanda(APath, AEditsJson,
    function(const AOld, ANew: string; AAtLine, AToLine: Integer;
      ADelete: Boolean): string
    var
      A: TPatchArgs;
    begin
      A := Default(TPatchArgs);
      A.Path := APath;
      A.OldLine := AOld;
      A.NewText := ANew;
      A.HasOld := AOld <> '';
      A.HasNew := (ANew <> '') or A.HasOld;
      A.AtLine := AAtLine;
      A.ToLine := AToLine;
      A.DeleteLine := ADelete;
      Result := ExecutePatch(A);
    end);
end;


function TDelphiPatchTool.ExecuteWithParams(const Params: TDelphiPatchParams): string;
var
  A: TPatchArgs;
begin
  if Params.Edits.Trim <> '' then
  begin
    Result := WriteTargetDenied(Params.Path);
    if Result <> '' then
      Exit;
    Exit(ApplyEdits(TPath.GetFullPath(Params.Path), Params.Edits));
  end;
  // ADDUSES: la clausula la escribe el motor de clausulas (Lsp.ProjectUnits),
  // el mismo del .dpr y el .dpk; aqui solo la jaula y el reparto de nombres.
  if Params.AddUses.Trim <> '' then
  begin
    Result := WriteTargetDenied(Params.Path);
    if Result <> '' then
      Exit;
    Exit(AddUsesToUnit(TPath.GetFullPath(Params.Path),
      Params.AddUses.Split([';', ','], TStringSplitOptions.ExcludeEmpty), Params.Section));
  end;
  if Params.RemoveUses.Trim <> '' then
  begin
    Result := WriteTargetDenied(Params.Path);
    if Result <> '' then
      Exit;
    Exit(RemoveUsesFromUnit(TPath.GetFullPath(Params.Path),
      Params.RemoveUses.Split([';', ','], TStringSplitOptions.ExcludeEmpty), Params.Section));
  end;
  A := Default(TPatchArgs);
  A.Path := Params.Path;
  A.OldLine := Params.Old;
  A.NewText := Params.New;
  A.HasOld := Params.Old <> '';
  // old given + empty new = blank the line (legitimate); absent old + new
  // is caught by the whole-file-rewrite gate inside the engine.
  A.HasNew := (Params.New <> '') or A.HasOld;
  A.AtLine := Params.AtLine;
  A.ToLine := Params.ToLine;
  A.DeleteLine := Params.Delete;
  A.Fragment := Params.Fragment;
  A.Insert := Params.Insert.Trim.ToLower;
  A.Code := Params.Code;
  A.ClassName_ := Params.InClass;
  A.Visibility := Params.Visibility;
  A.Visible := Params.Visible;
  A.CreateUnit_ := Params.CreateUnit;
  A.Content := Params.Content;
  A.Eol := Params.Eol;
  A.Restore := Params.Restore;
  A.Confirm := Params.Confirm;
  Result := ExecutePatch(A);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_read',
    function: IMCPTool begin Result := TDelphiReadTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_edit',
    function: IMCPTool begin Result := TDelphiPatchTool.Create; end);

end.
