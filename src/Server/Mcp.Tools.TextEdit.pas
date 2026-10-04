unit Mcp.Tools.TextEdit;

{ delphi_textedit: safe editing of plain-text NON-Delphi files (docs, tests,
  scripts, config) so a remote agent can maintain a whole project - README,
  CHANGELOG, test batteries, .gitignore - through this MCP. Engine in
  Lsp.TextEdit; Delphi sources stay on delphi_edit. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes,  // [RutaDelServidor]: que parametro es una ruta NUESTRA
  Lsp.TextEdit;

type
  TDelphiTextEditParams = class
  private
    FPath: string;
    FOld: string;
    FNew: string;
    FAtLine: Integer;
    FToLine: Integer;
    FEdits: string;
    FFragment: string;
    FDelete: Boolean;
    FCreate: Boolean;
    FContent: string;
    FEol: string;
  public
    [SchemaDescription(SP_TEXT_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_EDIT_OLD)]
    property Old: string read FOld write FOld;
    [SchemaDescription(SP_TEXT_NEW + SP_NEW_SALTO_FINAL)]
    property New: string read FNew write FNew;
    [SchemaDescription(SP_TEXT_ATLINE)]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription(SP_PATCH_TOLINE_CORTO)]
    property ToLine: Integer read FToLine write FToLine;
    // La descripcion de "edits" estaba COPIADA aqui, palabra por palabra pero
    // no del todo, de la de delphi_edit: el rango, documentado en una sola,
    // era invisible para quien usaba la otra (2026-09-20). Desde el
    // 4-oct-2026 aqui va el resumen corto (el revisor de tokens: el largo
    // repetido costaba en cada sesion), y lo que no puede faltar en el lo
    // vigila test_docs_tokens: cada campo de CAMPOS_DE_UNA_EDICION, en las
    // dos descripciones.
    [SchemaDescription(SP_PATCH_EDITS_CORTO)]
    [JsonComoTexto]
    property Edits: string read FEdits write FEdits;
    [SchemaDescription(SP_PATCH_FRAGMENT_CORTO)]
    property Fragment: string read FFragment write FFragment;
    [SchemaDescription(SP_TEXT_DELETE)]
    property Delete: Boolean read FDelete write FDelete;
    [SchemaDescription(SP_TEXT_CREATE_)]
    property Create_: Boolean read FCreate write FCreate;
    [SchemaDescription(SP_TEXT_CONTENT)]
    property Content: string read FContent write FContent;
    [SchemaDescription(SP_TEXT_EOL)]
    property Eol: string read FEol write FEol;
  end;

  TDelphiTextEditTool = class(TMCPToolBase<TDelphiTextEditParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiTextEditParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard, // ParametroQueNoVa: lo que no va con el modo se dice
  Lsp.Patch; // ModosQueNoCombinan: la regla de los modos, la de delphi_edit

{ TDelphiTextEditTool }

constructor TDelphiTextEditTool.Create;
begin
  inherited;
  FName := 'delphi_textedit';
  FDescription := SD_TEXT_TEXTEDIT;
end;

function TDelphiTextEditTool.ExecuteWithParams(const Params: TDelphiTextEditParams): string;
var
  A: TTextEditArgs;
begin
  // los modos que no combinan: uno por llamada (Lsp.Patch.ModosQueNoCombinan)
  Result := ModosQueNoCombinan([
    IfThen(Params.Edits.Trim <> '', 'edits'),
    IfThen(Params.Create_, 'create'),
    IfThen((Params.Old <> '') or (Params.New <> '') or (Params.Fragment <> '') or Params.Delete,
      'old/new/fragment/delete')]);
  if Result <> '' then
    Exit;
  // lo que no es del modo de la llamada se dice (Lsp.Guard.ParametroQueNoVa):
  // content sin create (sexta revision), eol sin create, atline con edits
  // (septima)
  var Modo: string;
  if Params.Edits.Trim <> '' then Modo := 'edits'
  else if Params.Create_ then Modo := 'create'
  else Modo := 'old/new';
  var Suyos: string;
  var Sobra := ParametroQueNoVa(Modo, [
      'edits', 'edits',
      'create', 'create content eol',
      'old/new', 'old new fragment delete atline toline'],
    ['atline', IfThen(Params.AtLine <> 0, IntToStr(Params.AtLine)), '',
     'toline', IfThen(Params.ToLine <> 0, IntToStr(Params.ToLine)), '',
     'content', Params.Content, '', 'eol', Params.Eol, ''], Suyos);
  if Sobra <> '' then
    Exit(MsgFmt(SR_EDIT_NO_VA_CON_MODO_FMT, [Sobra, Modo, Modo, Suyos]));
  if Params.Edits.Trim <> '' then
    Exit(ExecuteTextEdits(Params.Path, Params.Edits));
  A := Default(TTextEditArgs);
  A.Path := Params.Path;
  A.OldLine := Params.Old;
  A.NewText := Params.New;
  A.HasOld := Params.Old <> '';
  A.HasNew := (Params.New <> '') or A.HasOld;
  A.AtLine := Params.AtLine;
  A.ToLine := Params.ToLine;
  A.DeleteLine := Params.Delete;
  A.Fragment := Params.Fragment;
  A.CreateFile_ := Params.Create_;
  A.Content := Params.Content;
  A.Eol := Params.Eol;
  Result := ExecuteTextEdit(A);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_textedit',
    function: IMCPTool begin Result := TDelphiTextEditTool.Create; end);

end.
