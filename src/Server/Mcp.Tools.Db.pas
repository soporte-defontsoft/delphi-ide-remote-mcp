unit Mcp.Tools.Db;

{ delphi_db (1.29): las bases de datos con nombre que define el operador
  (Lsp.Conexiones) y abre a cada workspace con DbAllowedProjects=, por
  OPERACIONES y nunca por SQL: el agente pide, el servidor compone y FireDAC
  traduce a cada motor (David, 6-nov-2026: "el agente no puede escribir sql",
  como las tools de tablas del Centro de IA de la casa; Lsp.BaseDeDatos).

  Primera parte: connections, las bases de ESTA sesion por su nombre
  <proyecto>/<alias>, su motor y si son de solo lectura; las declaradas mal,
  aparte con el porque (un fragmento: un SR_ no va en un campo JSON). }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiDbParams = class
  private
    FCommand: string;
  public
    [SchemaDescription(SP_DB_COMMAND)]
    property Command: string read FCommand write FCommand;
  end;

  TDelphiDbTool = class(TMCPToolBase<TDelphiDbParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDbParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  MCPServer.Registration,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Conexiones,
  Lsp.BaseDeDatos;

function Connections: string;
var
  Neg: string;
  Lista: TArray<TConexionDb>;
  R: TJSONObject;
  Bases, Inutiles: TJSONArray;
begin
  Lista := ConexionesDbDeLaSesion(Neg);
  if Neg <> '' then
    Exit(Neg);
  R := TJSONObject.Create;
  try
    R.AddPair('note', MsgText(SN_DB_CONNECTIONS));
    Bases := TJSONArray.Create;
    R.AddPair('databases', Bases);
    Inutiles := nil;
    for var C in Lista do
    begin
      var Por := DefectoDeConexion(C);
      if Por = '' then
      begin
        var B := TJSONObject.Create;
        Bases.AddElement(B);
        B.AddPair('db', NombreDeConexion(C));
        B.AddPair('engine', C.Motor);
        B.AddPair('readonly', TJSONBool.Create(C.SoloLectura));
      end
      else
      begin
        if Inutiles = nil then
        begin
          Inutiles := TJSONArray.Create;
          R.AddPair('unusable', Inutiles);
        end;
        var U := TJSONObject.Create;
        Inutiles.AddElement(U);
        U.AddPair('db', NombreDeConexion(C));
        U.AddPair('why', Por);
      end;
    end;
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

{ TDelphiDbTool }

constructor TDelphiDbTool.Create;
begin
  inherited;
  FName := 'delphi_db';
  FDescription := SD_DB;
end;

function TDelphiDbTool.ExecuteWithParams(const Params: TDelphiDbParams): string;
var
  Cmd: string;
begin
  Cmd := SinMayusculas(Params.Command.Trim);
  if (Cmd = '') or (Cmd = 'connections') then
    Exit(Connections);
  Result := MsgText(SR_DB_COMANDO);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_db',
    function: IMCPTool begin Result := TDelphiDbTool.Create; end);

end.
