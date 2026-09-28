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
    [SchemaDescription(SP_EDIT_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_EDIT_FROMLINE)]
    property FromLine: Integer read FFromLine write FFromLine;
    [SchemaDescription(SP_EDIT_TOLINE)]
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
    [SchemaDescription(SP_EDIT_PATH_2)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_EDIT_OLD)]
    property Old: string read FOld write FOld;
    [SchemaDescription(SP_EDIT_NEW + SP_NEW_SALTO_FINAL)]
    property New: string read FNew write FNew;
    [SchemaDescription(SP_EDIT_ATLINE)]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription(SP_PATCH_TOLINE)]
    property ToLine: Integer read FToLine write FToLine;
    [SchemaDescription(SP_PATCH_EDITS)]
    [JsonComoTexto]
    property Edits: string read FEdits write FEdits;
    [SchemaDescription(SP_PATCH_FRAGMENT)]
    property Fragment: string read FFragment write FFragment;
    [SchemaDescription(SP_EDIT_DELETE)]
    property Delete: Boolean read FDelete write FDelete;
    [SchemaDescription(SP_EDIT_INSERT)]
    property Insert: string read FInsert write FInsert;
    [SchemaDescription(SP_EDIT_CODE)]
    property Code: string read FCode write FCode;
    [SchemaDescription(SP_EDIT_INCLASS)]
    property InClass: string read FInClass write FInClass;
    [SchemaDescription(SP_EDIT_VISIBILITY)]
    property Visibility: string read FVisibility write FVisibility;
    [SchemaDescription(SP_EDIT_VISIBLE)]
    property Visible: Boolean read FVisible write FVisible;
    [SchemaDescription(SP_EDIT_CREATEUNIT)]
    property CreateUnit: Boolean read FCreateUnit write FCreateUnit;
    [SchemaDescription(SP_EDIT_CONTENT)]
    property Content: string read FContent write FContent;
    [SchemaDescription(SP_EDIT_EOL)]
    property Eol: string read FEol write FEol;
    [SchemaDescription(SP_EDIT_RESTORE)]
    property Restore: Boolean read FRestore write FRestore;
    [SchemaDescription(SP_EDIT_CONFIRM)]
    property Confirm: Boolean read FConfirm write FConfirm;
    [SchemaDescription(SP_EDIT_ADDUSES)]
    property AddUses: string read FAddUses write FAddUses;
    [SchemaDescription(SP_EDIT_SECTION)]
    property Section: string read FSection write FSection;
    [SchemaDescription(SP_EDIT_REMOVEUSES)]
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
  System.StrUtils, // IfThen: la lista de modos de ModosQueNoCombinan
  MCPServer.Registration;

{ TDelphiReadTool }

constructor TDelphiReadTool.Create;
begin
  inherited;
  FName := 'delphi_read';
  FDescription := SD_EDIT_READ;
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
  FDescription := SD_EDIT_PATCH;
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
  // los modos que no combinan: uno por llamada (Lsp.Patch.ModosQueNoCombinan)
  Result := ModosQueNoCombinan([
    IfThen(Params.Edits.Trim <> '', 'edits'),
    IfThen(Params.AddUses.Trim <> '', 'adduses'),
    IfThen(Params.RemoveUses.Trim <> '', 'removeuses'),
    IfThen(Params.Insert.Trim <> '', 'insert'),
    IfThen(Params.CreateUnit, 'createunit'),
    IfThen(Params.Restore, 'restore'),
    IfThen((Params.Old <> '') or (Params.New <> '') or (Params.Fragment <> '') or Params.Delete,
      'old/new/fragment/delete')]);
  if Result <> '' then
    Exit;
  // content es de createunit: sin el, se ignoraba en silencio
  if (Params.Content <> '') and not Params.CreateUnit then
    Exit(MsgFmt(SR_EDIT_CONTENT_SIN_MODO_FMT, ['createunit']));
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
