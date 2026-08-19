unit Mcp.Tools.DelphiPatch;

{ delphi_read + delphi_patch: encoding-correct reading and SAFE editing of
  Delphi sources, so any model - large or small - can modify code through
  this MCP without corrupting it. Engine in Lsp.Patch. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Patch;

type
  TDelphiReadParams = class
  private
    FPath: string;
    FFromLine: Integer;
    FToLine: Integer;
  public
    [SchemaDescription('Absolute path of the Delphi file (.pas/.dpr/.dpk/.inc/.dfm/.fmx)')]
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
    FInsert: string;
    FCode: string;
    FInClass: string;
    FVisibility: string;
    FVisible: Boolean;
    FCreateUnit: Boolean;
    FRestore: Boolean;
    FConfirm: Boolean;
  public
    [SchemaDescription('Absolute path of the Delphi file')]
    property Path: string read FPath write FPath;
    [SchemaDescription('EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the | bar). Leading indentation may be omitted')]
    property Old: string read FOld write FOld;
    [SchemaDescription('EDIT mode: the new text; may be several lines (to insert code, anchor on an existing line and return it inside new together with the added code)')]
    property New: string read FNew write FNew;
    [SchemaDescription('EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence (the rejection lists the valid numbers)')]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription('INSERT mode (preferred for NEW routines/methods): "rutina-global" or "metodo". The tool places the block at the legal boundary; with "metodo" it also writes the class declaration. Pass code, not old/new')]
    property Insert: string read FInsert write FInsert;
    [SchemaDescription('INSERT mode: the COMPLETE block (unqualified signature + begin..end;). NEVER include end.')]
    property Code: string read FCode write FCode;
    [SchemaDescription('INSERT "metodo": exact class name (e.g. TFichaPedidos)')]
    property InClass: string read FInClass write FInClass;
    [SchemaDescription('INSERT "metodo" optional: section for the declaration (private/protected/public/published); empty = end of class')]
    property Visibility: string read FVisibility write FVisibility;
    [SchemaDescription('INSERT "rutina-global" optional: true = also declare it in the interface section (visible outside the unit)')]
    property Visible: Boolean read FVisible write FVisible;
    [SchemaDescription('CREATE mode: true = create the .pas with the standard IDE skeleton (never overwrites). Then register it in the .dpr uses clause')]
    property CreateUnit: Boolean read FCreateUnit write FCreateUnit;
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
  MCPServer.Registration;

{ TDelphiReadTool }

constructor TDelphiReadTool.Create;
begin
  inherited;
  FName := 'delphi_read';
  FDescription := 'Read a Delphi source file DECODED CORRECTLY (CP1252 / ' +
    'UTF-8 with or without BOM detected for real). Returns numbered lines in ' +
    'the format number|content - to build a delphi_patch anchor, copy ' +
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
  FName := 'delphi_patch';
  FDescription := 'SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus ' +
    'text .dfm/.fmx) preserving the real encoding and line endings. Modes: ' +
    'EDIT (old = ONE full line copied from delphi_read + new), INSERT ' +
    '(insert="rutina-global"|"metodo" + code: the tool picks the legal spot ' +
    'and, for methods, writes BOTH halves - declaration and qualified ' +
    'implementation), CREATE (createunit=true) and RESTORE (restore=true, ' +
    'two-step). It refuses to rewrite whole files, refuses binary designer ' +
    'files (TPF0), makes automatic backups, writes atomically, and audits ' +
    'the result (encoding, EOLs, mojibake, end. structure) reporting the ' +
    'REAL lines read back from disk - use that as evidence. Never edit ' +
    'Delphi files with generic tools: CP1252 sources get destroyed.';
end;

function TDelphiPatchTool.ExecuteWithParams(const Params: TDelphiPatchParams): string;
var
  A: TPatchArgs;
begin
  A := Default(TPatchArgs);
  A.Path := Params.Path;
  A.OldLine := Params.Old;
  A.NewText := Params.New;
  A.HasOld := Params.Old <> '';
  // old given + empty new = blank the line (legitimate); absent old + new
  // is caught by the whole-file-rewrite gate inside the engine.
  A.HasNew := (Params.New <> '') or A.HasOld;
  A.AtLine := Params.AtLine;
  A.Insert := Params.Insert.Trim.ToLower;
  A.Code := Params.Code;
  A.ClassName_ := Params.InClass;
  A.Visibility := Params.Visibility;
  A.Visible := Params.Visible;
  A.CreateUnit_ := Params.CreateUnit;
  A.Restore := Params.Restore;
  A.Confirm := Params.Confirm;
  Result := ExecutePatch(A);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_read',
    function: IMCPTool begin Result := TDelphiReadTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_patch',
    function: IMCPTool begin Result := TDelphiPatchTool.Create; end);

end.
