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
    FEdits: string;
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
  public
    [SchemaDescription('Absolute path of the Delphi file')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the | bar). Leading indentation may be omitted')]
    property Old: string read FOld write FOld;
    [SchemaDescription('EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new together with the added code)')]
    property New: string read FNew write FNew;
    [SchemaDescription('EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers)')]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription(SP_PATCH_EDITS)]
    property Edits: string read FEdits write FEdits;
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
  MCPServer.Registration;

{ TDelphiReadTool }

constructor TDelphiReadTool.Create;
begin
  inherited;
  FName := 'delphi_read';
  FDescription := 'Read a Delphi source file DECODED CORRECTLY (CP1252 / ' +
    'UTF-8 with or without BOM detected for real). Returns numbered lines in ' +
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
    'EDIT (old = ONE full line copied from delphi_read + new), DELETE ' +
    '(delete=true + old: removes the line entirely), INSERT ' +
    '(insert="rutina-global"|"metodo" + code: the tool picks the legal spot ' +
    '- also inside a .dpr - and, for methods, writes BOTH halves: ' +
    'declaration and qualified implementation), CREATE (createunit=true; ' +
    'new files honour the encoding configured in the IDE) and RESTORE ' +
    '(restore=true, two-step). It refuses to rewrite whole files, refuses ' +
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
function ApplyEdits(const APath, AEditsJson: string): string;
var
  Arr: TJSONArray;
  V: TJSONValue;
  Obj: TJSONObject;
  A: TPatchArgs;
  Snapshot: TBytes;
  Existed: Boolean;
  Sb: TStringBuilder;
  One: string;
  N, Failed: Integer;
begin
  V := TJSONObject.ParseJSONValue(AEditsJson);
  if not (V is TJSONArray) then
  begin
    V.Free;
    Exit(SR_PATCH_EDITS_JSON);
  end;
  Arr := TJSONArray(V);
  try
    if Arr.Count = 0 then
      Exit(SR_PATCH_EDITS_EMPTY);
    if Arr.Count > 50 then
      Exit(SR_PATCH_EDITS_TOOMANY);
    Existed := TFile.Exists(APath);
    if not Existed then
      Exit(Format(SR_PATCH_EDITS_NOFILE_FMT, [APath]));
    Snapshot := TFile.ReadAllBytes(APath);
    Sb := TStringBuilder.Create;
    try
      N := 0;
      Failed := 0;
      for V in Arr do
      begin
        Inc(N);
        if not (V is TJSONObject) then
        begin
          Failed := N;
          Sb.AppendLine(Format('  %d: no es un objeto {old,new}', [N]));
          Break;
        end;
        Obj := TJSONObject(V);
        A := Default(TPatchArgs);
        A.Path := APath;
        A.OldLine := Obj.GetValue<string>('old', '');
        A.NewText := Obj.GetValue<string>('new', '');
        A.HasOld := A.OldLine <> '';
        A.HasNew := (A.NewText <> '') or A.HasOld;
        A.AtLine := Obj.GetValue<Integer>('atline', 0);
        A.DeleteLine := Obj.GetValue<Boolean>('delete', False);
        One := ExecutePatch(A);
        // The engine says RECHAZADO / error when it refused; anything else is
        // an applied edit with its audit.
        if One.StartsWith('RECHAZADO') or One.StartsWith('error') then
        begin
          Failed := N;
          Sb.AppendLine(Format('  %d: %s', [N, One.Replace(#10, ' ')]));
          Break;
        end;
        Sb.AppendLine(Format('  %d OK: %s', [N,
          A.OldLine.Trim.Substring(0, Min(70, Length(A.OldLine.Trim)))]));
      end;
      if Failed > 0 then
      begin
        // all or nothing: the file goes back byte for byte
        TFile.WriteAllBytes(APath, Snapshot);
        Exit(Format(SR_PATCH_EDITS_ROLLED_FMT,
          [Failed, Arr.Count, Sb.ToString.TrimRight]));
      end;
      Result := Format(SN_PATCH_EDITS_OK_FMT,
        [Arr.Count, TPath.GetFileName(APath), Sb.ToString.TrimRight]);
    finally
      Sb.Free;
    end;
  finally
    Arr.Free;
  end;
end;

function TDelphiPatchTool.ExecuteWithParams(const Params: TDelphiPatchParams): string;
var
  A: TPatchArgs;
begin
  if Params.Edits.Trim <> '' then
  begin
    Result := PathDenied(Params.Path);
    if Result <> '' then
      Exit;
    Exit(ApplyEdits(TPath.GetFullPath(Params.Path), Params.Edits));
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
  A.DeleteLine := Params.Delete;
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
