unit Mcp.Tools.Desktop;

{ delphi_desktop: el escritorio de la maquina de un perfil PAServer -Linux o
  Windows, incluida ESTA misma si su PAServer corre en la sesion del usuario-,
  como delphi_adb da el de un Android. Ver la pantalla y actuar sobre ella.
  Hasta 1.0.15 se llamaba delphi_adb_linux y habia otra tool, delphi_desktop,
  que corria el nodo en LOCAL con un interruptor propio (AllowDesktopControl):
  dos caminos y dos modelos de permiso para lo mismo. Decision de David
  (21-sep-2026): un solo camino, por PAServer y perfil; el nombre viejo sigue
  registrado como ALIAS en desuso con los mismos parametros.

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
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDesktopLinuxParams = class
  private
    FCommand: string;
    FProfile: string;
    FProject: string;
    FX: string;
    FY: string;
    FCode: string;
    FText: string;
    FOut: string;
  public
    [SchemaDescription(SP_ADBLINUX_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_ADBLINUX_PROFILE)]
    property Profile: string read FProfile write FProfile;
    // Ruta de un .dproj de ESTE servidor cuando se da (PathDenied la
    // comprueba 139 lineas mas abajo, como en cualquier tool); vacio = el
    // nodo incluido junto al exe. Aqui ponia "es un NOMBRE, no una ruta",
    // que era FALSO - y ademas contaba "dos excepciones" enumerando tres.
    // La clasificacion falsa que la puerta central habria heredado
    // (auditoria 2026-09-21).
    [SchemaDescription(SP_ADBLINUX_PROJECT)]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_ADBLINUX_X)]
    property X: string read FX write FX;
    [SchemaDescription(SP_ADBLINUX_Y)]
    property Y: string read FY write FY;
    [SchemaDescription(SP_ADBLINUX_CODE)]
    property Code: string read FCode write FCode;
    [SchemaDescription(SP_ADBLINUX_TEXT)]
    property Text: string read FText write FText;
    // La carpeta LOCAL donde baja la captura del destino: ruta NUESTRA,
    // aunque la imagen venga de otra maquina.
    [SchemaDescription(SP_ADBLINUX_OUT)]
    [RutaDelServidor]
    property Out_: string read FOut write FOut;
  end;

  TDesktopLinuxTool = class(TMCPToolBase<TDesktopLinuxParams>)
  protected
    function ExecuteWithParams(const Params: TDesktopLinuxParams): string; override;
  public
    constructor Create; override;
  end;

  { El nombre viejo, en desuso: la MISMA tool, para que un cliente con el
    esquema cacheado siga funcionando una version mas. }
  TDesktopAliasTool = class(TDesktopLinuxTool)
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Mcp.Tools.PAServer,
  Lsp.RemoteRun;

constructor TDesktopLinuxTool.Create;
begin
  inherited;
  FName := 'delphi_desktop';
  FDescription := SD_ADBLINUX;
end;

constructor TDesktopAliasTool.Create;
begin
  inherited;
  FName := 'delphi_adb_linux';
  FDescription := SD_ADBLINUX_ALIAS;
end;

var
  { UN gesto por MAQUINA a la vez - no uno por servidor: dos Linux distintos
    pueden ir en paralelo (es justo para lo que existe el parametro profile),
    pero dos agentes sobre EL MISMO target se interleavan las pulsaciones y se
    pisan el captura.png que el nodo escribe en su carpeta de despliegue. Un
    cerrojo por perfil, creado la primera vez que ese perfil se usa. }
  GPerfilesLock: TCriticalSection;
  GPerfiles: TObjectDictionary<string, TCriticalSection>;

function CerrojoDePerfil(const APerfil: string): TCriticalSection;
begin
  GPerfilesLock.Enter;
  try
    if not GPerfiles.TryGetValue(APerfil.Trim.ToLower, Result) then
    begin
      Result := TCriticalSection.Create;
      GPerfiles.Add(APerfil.Trim.ToLower, Result);
    end;
  finally
    GPerfilesLock.Leave;
  end;
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

{ El nombre del perfil, apto para un nombre de fichero (lo eligio el operador
  en el IDE: puede traer espacios y acentos). }
function NombreSeguro(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Result := Result + C;
  if Result = '' then
    Result := 'perfil';
  Result := Result.ToLower;
end;

{ Una tecla de Windows se nombra (escape, enter, f4); un numero seria un
  codigo de OTRO sistema y pulsaria otra tecla. }
function NombreDeTeclaValido(const ACode: string): Boolean;
begin
  Result := (ACode <> '') and
    ((ACode[Low(ACode)] < '0') or (ACode[Low(ACode)] > '9'));
end;

{ El gesto; ExecuteWithParams lo envuelve en el cerrojo de SU maquina. }
function GestoEnElTarget(const Params: TDesktopLinuxParams): string;
var
  Cmd, Args, Salida, Destino, Local, Fallo, Remota, Proj, Nota, Literal: string;
  Bajada, Propia: string;
  Res: TJSONObject;
  Return: TJSONObject;
  EsWin: Boolean;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'screenshot';
  if not MatchStr(Cmd, ['screenshot', 'tap', 'type', 'key', 'windows', 'status']) then
    Exit(SR_ADBLINUX_CMD);

  { Ejecutar en el destino es remote-run con otro volante: mismos
    interruptores del workspace que delphi_paserver (v0.98; antes este
    camino no pasaba ni por AllowRemoteRun ni por las listas). }
  if not AllowRemoteRun then
    Exit(SR_PASERVER_RUN_DISABLED);

  { "out" es una ruta LOCAL que elige QUIEN LLAMA -donde baja la captura del
    destino- y no pasaba por la jaula: el servidor creaba la carpeta y
    escribia el PNG donde le dijeran. Se comprueba lo PROPIO antes que lo
    remoto: es un argumento del que llama y no depende de ningun perfil, asi
    que falla rapido y no hace falta un destino vivo para verlo fallar.
    Justo debajo se comprueba "project" con esta misma llamada desde siempre:
    era uno de dos. Su gemela de Windows tenia el mismo hueco (2026-09-21), y
    delphi_adb -misma idea, mismo nombre de parametro- si lo comprobaba. }
  if Params.Out_.Trim <> '' then
  begin
    Result := PathDenied(Params.Out_.Trim);
    if Result <> '' then
      Exit;
  end;

  Result := ProfileHostDenied(Params.Profile.Trim);
  if Result <> '' then
    Exit;
  { El destino dice que nodo y que teclas espera: lo lee el .profile, nunca
    el nombre del perfil (que no significa nada). }
  EsWin := PlataformaDelPerfil(Params.Profile.Trim).StartsWith('Win', True);
  Proj := Params.Project.Trim;
  if Proj <> '' then
  begin
    { El jail decide si este token puede tocar ese proyecto, igual que en
      cualquier otra tool que nombre un fichero. }
    Result := PathDenied(Proj);
    if Result <> '' then
      Exit;
  end;
  Result := RemoteRunProjectDenied(IfThen(Proj <> '', Proj, NODE_PROJECT));
  if Result <> '' then
    Exit;

  Args := '';
  Literal := '';
  if Cmd = 'tap' then
  begin
    if (Params.X.Trim = '') or (Params.Y.Trim = '') then
      Exit(SR_ADBLINUX_NEEDXY);
    Args := Format('%d %d', [StrToIntDef(Params.X.Trim, -1),
      StrToIntDef(Params.Y.Trim, -1)]);
  end
  else if Cmd = 'type' then
  begin
    if Params.Text.Trim = '' then
      Exit(SR_ADBLINUX_NEEDTEXT);
    { Con coordenadas es UN solo viaje: pulsa para dar el foco y escribe. }
    { El TEXTO no va en Args: viaja como argumento LITERAL (ver
      Lsp.RemoteRun.GuionDeEjecucion). Pegado aqui llegaba a pelo al /bin/sh
      del destino, y un "hola; lo-que-sea" ejecutaba la segunda mitad alli
      (medido 2026-09-21). }
    Literal := Params.Text.Trim;
    if (Params.X.Trim <> '') and (Params.Y.Trim <> '') then
      Args := Format('escribe %d %d', [StrToIntDef(Params.X.Trim, -1),
        StrToIntDef(Params.Y.Trim, -1)])
    else
      Args := 'texto';
  end
  else if Cmd = 'key' then
  begin
    { Cada nodo habla el idioma de su sistema: en Linux un codigo evdev (una
      POSICION del teclado), en Windows el NOMBRE de la tecla. Un numero en
      Windows no es la misma tecla que en Linux, asi que no se traduce: se
      rechaza diciendo lo que ese destino espera. }
    if EsWin then
    begin
      if not NombreDeTeclaValido(Params.Code.Trim) then
        Exit(SR_DESKTOP_NEEDCODE);
      Args := 'tecla ' + Params.Code.Trim;
    end
    else
    begin
      if (Params.Code.Trim = '') or (StrToIntDef(Params.Code.Trim, 0) <= 0) then
        Exit(SR_ADBLINUX_NEEDCODE);
      Args := Format('tecla %d', [StrToIntDef(Params.Code.Trim, 0)]);
    end;
  end
  else if Cmd = 'windows' then
    Args := 'ventanas';
  { screenshot y status corren el nodo sin argumentos: el nodo siempre
    captura al arrancar y cuenta el estado del escritorio. }

  { Sin project (lo normal): el nodo EMPAQUETADO junto al servidor. El
    primer gesto de la sesion por perfil comprueba el sello node.ver y, si
    falta o difiere, despliega/actualiza el nodo sin compilar nada. }
  Nota := '';
  if Proj = '' then
  begin
    Result := EnsureNodeCurrent(Params.Profile.Trim, Nota);
    if Result <> '' then
      Exit;
    Proj := NODE_PROJECT;
  end;
  { El nodo del target solo obedece al servidor: la clave (NodeKey.inc) va
    delante de la orden, igual que en el escritorio local. Un nodo ya
    desplegado por un servidor viejo no la pide, pero EnsureNodeCurrent lo
    habra sustituido antes de llegar aqui. }
  Res := RemoteRun(Params.Profile.Trim, Proj, '',
    Trim(NODE_KEY + ' ' + Args), 60000, Literal);
  try
    Salida := '';
    if Res.GetValue('output') <> nil then
      Salida := Res.GetValue<string>('output');

    Return := TJSONObject.Create;
    try // su gemela de Windows ya lo protegia; esta no (auditoria 2026-09-21)
    Return.AddPair('command', Cmd);
    Return.AddPair('profile', Params.Profile.Trim);
    if Nota <> '' then
      Return.AddPair('nodeDeploy', Nota);
    if Res.GetValue('success') <> nil then
      Return.AddPair('ran', TJSONBool.Create(Res.GetValue<Boolean>('success')));
    if Res.GetValue('error') <> nil then
      Return.AddPair('error', Res.GetValue<string>('error'));
    // en que sesion/entorno grafico corrio el nodo: lo cuenta remote-run y
    // aqui es lo primero que explica una captura negra o denegada
    if Res.GetValue('graphicalEnv') <> nil then
      Return.AddPair('graphicalEnv', Res.GetValue<string>('graphicalEnv'));
    Return.AddPair('nodeOutput', Salida.Trim);
    { Un Windows con la sesion bloqueada, desconectada o sin escritorio
      contesta "Acceso denegado" a cualquier captura: se nombra, que despista. }
    if Salida.Contains('Acceso denegado') or Salida.Contains('Access is denied') then
      Return.AddPair('hint', SD_DESKTOP_LOCKED);

    { La captura vive en la carpeta que el nodo desplego; se trae aqui por el
      mismo transporte que lo llevo alli. }
    Remota := RutaDeCaptura(Salida);
    if (Cmd <> 'status') and (Remota <> '') then
    begin
      // Lo mismo que su gemela de Windows, y por la MISMA funcion: donde cae
      // la captura y como se llama lo decide CaptureTarget (Lsp.Guard), con
      // el formato que trae la captura remota. Se resuelve ANTES de bajar
      // nada: un "out" con la extension equivocada no merece el viaje.
      Fallo := CaptureTarget(Params.Out_, 'desktop',
        'desktop-' + NombreSeguro(Params.Profile.Trim),
        TPath.GetExtension(Remota), Propia);
      { Con un "out" rechazado Propia viene VACIA, y calcular su carpeta
        reventaba con "File name is empty" en vez de dar la negativa - lo
        cazo la primera prueba en vivo contra el Fedora (2026-09-21); en
        Windows no pasaba porque alli el rechazo sale por excepcion. Todo lo
        que depende del destino va DENTRO del if. }
      if Fallo = '' then
      begin
      Destino := TPath.GetDirectoryName(Propia);
      { La captura baja con SU nombre remoto (captura.png), igual para todos
        los perfiles: con un destino comun, dos maquinas a la vez se pisaban la
        imagen y una llamada acababa con la pantalla de la otra. Baja a una
        carpeta propia y se queda con un nombre que dice de quien es. }
      Bajada := TPath.Combine(Destino, '.tmp-' +
        LowerCase(TGUID.NewGuid.ToString.Substring(1, 8)));
      Fallo := FetchFromTarget(Params.Profile.Trim, Proj,
        TPath.GetFileName(Remota), Bajada, Local);
      end;
      if Fallo = '' then
      begin
        try
          CrearCarpeta(Destino);
          TFile.Move(Local, Propia);
          Local := Propia;
          BorraArbol(Bajada); // sin cruzar enlaces: ver Lsp.Guard
        except
          // si no se puede renombrar, la imagen vale igual donde cayo
        end;
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
    finally
      Return.Free;
    end;
  finally
    Res.Free;
  end;
end;

function TDesktopLinuxTool.ExecuteWithParams(const Params: TDesktopLinuxParams): string;
var
  Cerrojo: TCriticalSection;
begin
  Cerrojo := CerrojoDePerfil(Params.Profile);
  Cerrojo.Enter;
  try
    Result := GestoEnElTarget(Params);
  finally
    Cerrojo.Leave;
  end;
end;

initialization
  GPerfilesLock := TCriticalSection.Create;
  GPerfiles := TObjectDictionary<string, TCriticalSection>.Create([doOwnsValues]);
  TMCPRegistry.RegisterTool('delphi_desktop',
    function: IMCPTool begin Result := TDesktopLinuxTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_adb_linux',
    function: IMCPTool begin Result := TDesktopAliasTool.Create; end);

finalization
  GPerfiles.Free;
  GPerfilesLock.Free;

end.
