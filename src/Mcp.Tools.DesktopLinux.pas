unit Mcp.Tools.DesktopLinux;

{ delphi_adb_linux: el escritorio Linux de un target, como delphi_adb da el de
  un Android. Ver la pantalla y actuar sobre ella.

  La forma es la de adb, de arriba abajo: el agente habla con ESTE servidor,
  este habla con el nodo que vive en la maquina de destino, y el nodo habla
  con el escritorio. El nodo es un programa Delphi que este mismo servidor
  compila y despliega (delphi_build target=Deploy); en el Linux no se instala
  NADA mas - se apoya solo en las librerias que el escritorio ya trae.

  EL FLUJO, que es todo el truco (medido el 18-sep, y la simplificacion que
  lo hizo posible fue de David): se captura el ESCRITORIO ENTERO, se mira la
  imagen, se mide el pixel que interesa y se pulsa ahi. Sin geometrias de
  ventana, sin identificadores, sin tres espacios de coordenadas peleandose:
  el agente actua sobre LO QUE VE, y la conversion de escala la hace el nodo
  por dentro. Cuando una ventana tapa a otra, command=windows las ensena
  todas en miniatura y vuelve a ser un clic sobre algo visible.

  El target se nombra SIEMPRE por su perfil PAServer: el escritorio es el de
  ESA maquina, nunca el del agente ni el de este servidor. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDesktopLinuxParams = class
  private
    FCommand: string;
    FProfile: string;
    FProject: string;
    FX: string;
    FY: string;
    FCode: string;
    FOut: string;
  public
    [SchemaDescription(SP_ADBLINUX_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_ADBLINUX_PROFILE)]
    property Profile: string read FProfile write FProfile;
    [SchemaDescription(SP_ADBLINUX_PROJECT)]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_ADBLINUX_X)]
    property X: string read FX write FX;
    [SchemaDescription(SP_ADBLINUX_Y)]
    property Y: string read FY write FY;
    [SchemaDescription(SP_ADBLINUX_CODE)]
    property Code: string read FCode write FCode;
    [SchemaDescription(SP_ADBLINUX_OUT)]
    property Out_: string read FOut write FOut;
  end;

  TDesktopLinuxTool = class(TMCPToolBase<TDesktopLinuxParams>)
  protected
    function ExecuteWithParams(const Params: TDesktopLinuxParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.RemoteRun;

constructor TDesktopLinuxTool.Create;
begin
  inherited;
  FName := 'delphi_adb_linux';
  FDescription := SD_ADBLINUX;
end;

{ La linea CAPTURA=<ruta> que el nodo escribe al guardar una captura. }
function RutaDeCaptura(const ASalida: string): string;
var
  L: string;
begin
  Result := '';
  for L in ASalida.Split([#10]) do
    if L.TrimLeft.StartsWith('CAPTURA=') then
      Result := L.Trim.Substring(8);
end;

function TDesktopLinuxTool.ExecuteWithParams(const Params: TDesktopLinuxParams): string;
var
  Cmd, Args, Salida, Destino, Local, Fallo, Remota: string;
  Res: TJSONObject;
  Return: TJSONObject;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'screenshot';
  if not MatchStr(Cmd, ['screenshot', 'tap', 'key', 'windows', 'status']) then
    Exit(SR_ADBLINUX_CMD);

  { El jail decide si este token puede tocar ese proyecto, igual que en
    cualquier otra tool que nombre un fichero. }
  Result := PathDenied(Params.Project);
  if Result <> '' then
    Exit;

  Args := '';
  if Cmd = 'tap' then
  begin
    if (Params.X.Trim = '') or (Params.Y.Trim = '') then
      Exit(SR_ADBLINUX_NEEDXY);
    Args := Format('%d %d', [StrToIntDef(Params.X.Trim, -1),
      StrToIntDef(Params.Y.Trim, -1)]);
  end
  else if Cmd = 'key' then
  begin
    if Params.Code.Trim = '' then
      Exit(SR_ADBLINUX_NEEDCODE);
    Args := Format('tecla %d', [StrToIntDef(Params.Code.Trim, 0)]);
  end
  else if Cmd = 'windows' then
    Args := 'ventanas';
  { screenshot y status corren el nodo sin argumentos: el nodo siempre
    captura al arrancar y cuenta el estado del escritorio. }

  Res := RemoteRun(Params.Profile.Trim, Params.Project.Trim, '', Args, 60000);
  try
    Salida := '';
    if Res.GetValue('output') <> nil then
      Salida := Res.GetValue<string>('output');

    Return := TJSONObject.Create;
    Return.AddPair('command', Cmd);
    Return.AddPair('profile', Params.Profile.Trim);
    if Res.GetValue('success') <> nil then
      Return.AddPair('ran', TJSONBool.Create(Res.GetValue<Boolean>('success')));
    if Res.GetValue('error') <> nil then
      Return.AddPair('error', Res.GetValue<string>('error'));
    Return.AddPair('nodeOutput', Salida.Trim);

    { La captura vive en la carpeta que el nodo desplego; se trae aqui por el
      mismo transporte que lo llevo alli. }
    Remota := RutaDeCaptura(Salida);
    if (Cmd <> 'status') and (Remota <> '') then
    begin
      Destino := Params.Out_.Trim;
      if Destino = '' then
        Destino := TPath.Combine(TPath.GetTempPath, 'delphi-mcp-desktop');
      Fallo := FetchFromTarget(Params.Profile.Trim, Params.Project.Trim,
        TPath.GetFileName(Remota), Destino, Local);
      if Fallo = '' then
      begin
        Return.AddPair('screenshot', Local);
        Return.AddPair('screenshotBytes', TJSONNumber.Create(TFile.GetSize(Local)));
        Return.AddPair('note', 'mide el pixel SOBRE esta imagen y pasalo a ' +
          'command=tap; bajala con delphi_fetch');
      end
      else
        Return.AddPair('screenshotError', Fallo);
    end
    else if (Cmd = 'screenshot') and (Remota = '') then
      Return.AddPair('screenshotError', SR_ADBLINUX_NOSHOT);

    Result := Return.ToJSON;
    Return.Free;
  finally
    Res.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_adb_linux',
    function: IMCPTool begin Result := TDesktopLinuxTool.Create; end);

end.
