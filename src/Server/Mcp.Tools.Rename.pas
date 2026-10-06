unit Mcp.Tools.Rename;

{ delphi_rename_symbol: semantic rename - preview, and since 1.0.17 apply
  over the changeset engine. See Lsp.Rename for the applicability rule. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiRenameParams = class
  private
    FPath: string;
    FLine: Integer;
    FCharacter: Integer;
    FNewName: string;
    FMode: string;
  public
    [SchemaDescription(SP_RENAME_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_RENAME_LINE)]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription(SP_RENAME_CHARACTER)]
    [Required]
    property Character: Integer read FCharacter write FCharacter;
    [SchemaDescription(SP_RENAME_NEWNAME)]
    [Required]
    property NewName: string read FNewName write FNewName;
    [SchemaDescription(SP_RENAME_MODE)]
    property Mode: string read FMode write FMode;
  end;

  TDelphiRenameTool = class(TMCPToolBase<TDelphiRenameParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiRenameParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,      // PositionOutOfRange
  Lsp.Rename,
  Lsp.References, // CONTENIDO_DE_UN_USO: los campos que son la linea tal cual
  Lsp.Listas;     // AgrupaPorFichero: los cambios por carpeta y fichero

constructor TDelphiRenameTool.Create;
begin
  inherited;
  FName := 'delphi_rename_symbol';
  FDescription := SD_RENAME;
end;

function TDelphiRenameTool.ExecuteWithParams(const Params: TDelphiRenameParams): string;
var
  Mode: string;
  Ret: TJSONObject;
begin
  Mode := Params.Mode.Trim.ToLower;
  if Mode = '' then
    Mode := 'preview';
  if (Mode <> 'preview') and (Mode <> 'apply') then
    Exit(MsgText(SR_RENAME_MODE));
  if Params.Path.Trim = '' then
    Exit(MsgText(SR_RENAME_NEED_PATH));
  if Params.NewName.Trim = '' then
    Exit(MsgText(SR_RENAME_NEED_NEWNAME));
  // preview solo lee; apply escribe, asi que pasa por la puerta de escritura
  // (jaula + credencial de solo lectura) ANTES de calcular nada. Cada
  // fichero que apply toque vuelve a pasar por ella al apilarse.
  if Mode = 'apply' then
    Result := PathDenied(Params.Path)
  else
    Result := ReadPathDenied(Params.Path);
  if Result = '' then
    // La sexta y ultima de la familia. Sin esto, una linea que no existe
    // salia como excepcion cruda en ingles en vez del mensaje que dice
    // cuantas lineas tiene el fichero - y en un rename, que es la tool mas
    // destructiva del lote, saber que te has equivocado de posicion importa
    // mas que en ninguna.
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  try
    if Mode = 'apply' then
      Ret := RenameApply(Params.Path, Params.Line, Params.Character,
        Params.NewName.Trim)
    else
      Ret := RenamePreview(Params.Path, Params.Line, Params.Character,
        Params.NewName.Trim);
    try
      // cada lista por carpeta y fichero (el organizador), al contestar: por
      // dentro sigue plana (apply la recorta y la apila asi)
      for var Campo in TArray<string>.Create('changes', 'unverified', 'lookalikes') do
        AgrupaPorFichero(Ret, Campo);
      // la linea de cada cambio, tal cual (un ancla); lo demas, enmascarado
      Result := EnmascaraJsonSalvo(Ret.ToJSON, CONTENIDO_DE_UN_USO);
    finally
      Ret.Free;
    end;
  except
    on E: Exception do
      Result := MaskDriveText('', MsgExcepcion(E.ClassName, E.Message));
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_rename_symbol',
    function: IMCPTool begin Result := TDelphiRenameTool.Create; end);

end.
