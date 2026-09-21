unit Mcp.Tools.DesktopWin;

{ delphi_desktop: el escritorio de ESTE servidor - la maquina Windows con
  RAD Studio - visto y manejado por el agente.

  Es la tercera pata de la misma idea: delphi_adb en Android, delphi_adb_linux
  en un Linux con PAServer, y aqui la maquina a la que el agente ya esta
  hablando. Sirve para lo que ninguna otra tool alcanza: el propio IDE, un
  instalador, un dialogo modal, una app Windows recien compilada.

  El motor es el MISMO nodo Delphi que viaja a los Linux (node\McpDesktopNode,
  con su .exe para Windows): un programa por gesto, sin nada residente. Aqui
  no hay que desplegar nada - el nodo ya esta al lado del servidor - asi que
  el gesto es un CreateProcess y leer su salida.

  LA DIFERENCIA QUE IMPORTA respecto a sus hermanas: alli el escritorio es una
  maquina de pruebas; aqui es la del operador. Por eso este es el unico camino
  del servidor que exige su propio interruptor por workspace
  (AllowDesktopControl=1) y que se niega en una credencial de solo lectura. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDesktopWinParams = class
  private
    FCommand: string;
    FX: string;
    FY: string;
    FCode: string;
    FText: string;
    FOut: string;
  public
    [SchemaDescription(SP_DESKTOP_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_DESKTOP_X)]
    property X: string read FX write FX;
    [SchemaDescription(SP_DESKTOP_Y)]
    property Y: string read FY write FY;
    [SchemaDescription(SP_DESKTOP_CODE)]
    property Code: string read FCode write FCode;
    [SchemaDescription(SP_DESKTOP_TEXT)]
    property Text: string read FText write FText;
    // La carpeta donde cae la captura: ruta NUESTRA, y la que el 2026-09-21
    // se escribia fuera de la jaula por no tener donde declararlo.
    [SchemaDescription(SP_DESKTOP_OUT)]
    [RutaDelServidor]
    property Out_: string read FOut write FOut;
  end;

  TDesktopWinTool = class(TMCPToolBase<TDesktopWinParams>)
  protected
    function ExecuteWithParams(const Params: TDesktopWinParams): string; override;
  public
    constructor Create; override;
  end;

{ El nodo de escritorio de ESTA maquina: node\McpDesktopNode.exe junto al
  servidor. Se expone porque el registro de la tool pregunta si existe. }
function NodoWindowsPath: string;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.SyncObjs,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.BuildRunner,
  Lsp.RemoteRun;   { NODE_KEY: la clave la sirve el mismo sitio para los dos nodos }

const
  NODO_TIMEOUT = 30000;   { un gesto no deberia pasar de unos segundos }

var
  { El escritorio es UNO. Dos agentes pulsando o mirando a la vez no solo se
    interleavan los gestos: el nodo escribe SIEMPRE el mismo captura.png a su
    lado, asi que entre capturar y mover la imagen el otro ya la habia pisado y
    las dos llamadas recibian la MISMA foto (medido 2026-09-20, bateria de
    concurrencia). Un gesto cada vez, que es lo unico que significa "este
    escritorio". }
  GEscritorio: TCriticalSection;

function NodoWindowsPath: string;
begin
  Result := TPath.Combine(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'node'), 'McpDesktopNode.exe');
end;

constructor TDesktopWinTool.Create;
begin
  inherited;
  FName := 'delphi_desktop';
  FDescription := SD_DESKTOP;
end;

{ La linea CAPTURA=<ruta> que el nodo escribe al guardar la imagen. }
function RutaDeCaptura(const ASalida: string): string;
var
  L: string;
begin
  Result := '';
  for L in ASalida.Split([#10]) do
    if L.TrimLeft.StartsWith('CAPTURA=') then
      Result := L.Trim.Substring(8);
end;

{ Las teclas se pasan POR NOMBRE. El nodo las traduce a codigos de Windows;
  aqui solo se comprueba que no venga un numero suelto, que en Linux era el
  codigo evdev y aqui significaria otra tecla distinta: mejor un rechazo
  claro que un gesto equivocado. }
function NombreDeTeclaValido(const ACode: string): Boolean;
begin
  Result := (ACode <> '') and
    ((ACode[Low(ACode)] < '0') or (ACode[Low(ACode)] > '9'));
end;

function TDesktopWinTool.ExecuteWithParams(const Params: TDesktopWinParams): string;
var
  Cmd, Args, Salida, Nodo, Origen, Local: string;
  Codigo: Cardinal;
  Return: TJSONObject;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'screenshot';
  if not MatchStr(Cmd, ['screenshot', 'tap', 'type', 'key', 'windows', 'status']) then
    Exit(SR_DESKTOP_CMD);

  { El interruptor va ANTES que nada: mirar la pantalla del operador ya es
    el gesto, no hace falta pulsar para que importe. }
  if not AllowDesktopControl then
    Exit(SR_DESKTOP_DISABLED);

  { "out" es una ruta que elige QUIEN LLAMA, y hasta el 2026-09-21 no pasaba
    por la jaula: el servidor creaba la carpeta y soltaba el PNG donde le
    dijeran. Su gemela delphi_adb SI lo comprobaba -misma idea, mismo nombre
    de parametro, la comprobacion en una y no en la otra-, asi que aqui va la
    suya con la misma forma y en el mismo sitio: ANTES de tocar el nodo.
    Escribir es escribir: PathDenied, no ReadPathDenied - la zona de
    biblioteca se lee, no se llena de capturas. }
  if Params.Out_.Trim <> '' then
  begin
    var Denied := PathDenied(Params.Out_.Trim);
    if Denied <> '' then
      Exit(Denied);
  end;

  Nodo := NodoWindowsPath;
  if not TFile.Exists(Nodo) then
    Exit(Format(SR_DESKTOP_NONODE_FMT, [Nodo]));

  Args := '';
  if Cmd = 'tap' then
  begin
    if (Params.X.Trim = '') or (Params.Y.Trim = '') then
      Exit(SR_DESKTOP_NEEDXY);
    Args := Format('%d %d', [StrToIntDef(Params.X.Trim, -1),
      StrToIntDef(Params.Y.Trim, -1)]);
  end
  else if Cmd = 'type' then
  begin
    if Params.Text.Trim = '' then
      Exit(SR_DESKTOP_NEEDTEXT);
    if (Params.X.Trim <> '') and (Params.Y.Trim <> '') then
      Args := Format('escribe %d %d %s', [StrToIntDef(Params.X.Trim, -1),
        StrToIntDef(Params.Y.Trim, -1), Params.Text.Trim])
    else
      Args := 'texto ' + Params.Text.Trim;
  end
  else if Cmd = 'key' then
  begin
    if not NombreDeTeclaValido(Params.Code.Trim) then
      Exit(SR_DESKTOP_NEEDCODE);
    Args := 'tecla ' + Params.Code.Trim;
  end
  else if Cmd = 'windows' then
    Args := 'ventanas';
  { screenshot y status corren el nodo sin argumentos: siempre captura al
    terminar y cuenta lo que ve del escritorio. }

  { El nodo solo obedece al servidor: la clave va SIEMPRE delante (NodeKey.inc),
    y aqui solo se llega si el workspace declaro AllowDesktopControl=1. }
  { Un gesto cada vez: el nodo y su captura.png son recursos de LA maquina,
    no de la llamada (ver GEscritorio). El cerrojo abarca desde el gesto hasta
    que la imagen esta a salvo con su nombre propio. }
  GEscritorio.Enter;
  try
  Salida := RunCaptured(Format('"%s" %s %s', [Nodo, NODE_KEY, Args]),
    NODO_TIMEOUT, Codigo);

  Return := TJSONObject.Create;
  try
    Return.AddPair('command', Cmd);
    Return.AddPair('ran', TJSONBool.Create(Codigo = 0));
    Return.AddPair('nodeOutput', Salida.Trim);

    Origen := RutaDeCaptura(Salida);
    if (Cmd <> 'status') and (Origen <> '') and TFile.Exists(Origen) then
    begin
      { La captura se mueve a su sitio: el nodo siempre escribe el mismo
        captura.png al lado suyo, asi que dejarla ahi seria pisarsela al
        siguiente gesto. }
      // ENTREGABLE, no temporal del servidor: la descripcion de esta tool
      // dice "bajatela con delphi_fetch", y delphi_fetch comprueba la jaula.
      // Sin "out" cae dentro del workspace y en la carpeta del agente: una
      // jaula puede estar compartida, y la captura de uno no se le pone
      // delante a otro. Donde cae y como se llama lo decide CaptureTarget
      // (Lsp.Guard), el mismo para toda la familia - y el formato lo dice la
      // captura que ha hecho el nodo, no una constante de aqui.
      try
        var Veto := CaptureTarget(Params.Out_, 'desktop', 'desktop',
          TPath.GetExtension(Origen), Local);
        if Veto <> '' then
          raise Exception.Create(Veto);
        CrearCarpeta(TPath.GetDirectoryName(Local));
        TFile.Copy(Origen, Local, True);
        TFile.Delete(Origen);
        Return.AddPair('screenshot', Local);
        Return.AddPair('screenshotBytes', TJSONNumber.Create(TFile.GetSize(Local)));
        Return.AddPair('note', 'mide el pixel SOBRE esta imagen y pasalo a ' +
          'command=tap; bajala con delphi_fetch');
      except
        on E: Exception do
          Return.AddPair('screenshotError', E.Message);
      end;
    end
    else if Cmd <> 'status' then
    begin
      Return.AddPair('screenshotError', SR_DESKTOP_NOSHOT);
      { El sintoma de la sesion bloqueada es siempre el mismo y despista
        bastante, asi que se nombra por su nombre. }
      if Salida.Contains('Acceso denegado') or Salida.Contains('Access is denied') then
        Return.AddPair('hint', SD_DESKTOP_LOCKED);
    end;

    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
  finally
    GEscritorio.Leave;
  end;
end;

initialization
  GEscritorio := TCriticalSection.Create;
  TMCPRegistry.RegisterTool('delphi_desktop',
    function: IMCPTool begin Result := TDesktopWinTool.Create; end);

finalization
  GEscritorio.Free;

end.
