unit Mcp.Tools.Desktop;

{ delphi_desktop: el escritorio de la maquina de un perfil PAServer -Linux o
  Windows, incluida ESTA misma si su PAServer corre en la sesion del usuario-,
  como delphi_adb da el de un Android. Ver la pantalla y actuar sobre ella.
  Hasta 1.0.15 se llamaba delphi_adb_linux y habia otra tool, delphi_desktop,
  que corria el nodo en LOCAL con un interruptor propio (AllowDesktopControl):
  dos caminos y dos modelos de permiso para lo mismo. Decision de David
  (21-sep-2026): un solo camino, por PAServer y perfil. El nombre viejo quedo
  dos releases como ALIAS en desuso y se retiro (22-sep-2026).

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
    FModifiers: string;
    FText: string;
    FOut: string;
    FRegion: string;
    FWindow: string;
    FInline: string;
    FMaxWidth: Integer;
    FFrame: string;
  public
    [SchemaDescription(SP_ADBLINUX_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_ADBLINUX_PROFILE)]
    [Required]
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
    [SchemaDescription(SP_ADBLINUX_MODIFIERS)]
    property Modifiers: string read FModifiers write FModifiers;
    [SchemaDescription(SP_ADBLINUX_TEXT)]
    property Text: string read FText write FText;
    // La carpeta LOCAL donde baja la captura del destino: ruta NUESTRA,
    // aunque la imagen venga de otra maquina.
    [SchemaDescription(SP_ADBLINUX_OUT)]
    [RutaDelServidor]
    property Out_: string read FOut write FOut;
    [SchemaDescription(SP_ADBLINUX_REGION)]
    property Region: string read FRegion write FRegion;
    [SchemaDescription(SP_ADBLINUX_WINDOW)]
    property Window: string read FWindow write FWindow;
    [SchemaDescription(SP_CAPTURE_INLINE)]
    property Inline_: string read FInline write FInline;
    [SchemaDescription(SP_CAPTURE_MAXWIDTH)]
    property MaxWidth: Integer read FMaxWidth write FMaxWidth;
    [SchemaDescription(SP_CAPTURE_FRAME)]
    property Frame: string read FFrame write FFrame;
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
  System.SyncObjs,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Imagen,
  Mcp.Tools.PAServer,
  Lsp.InlineImages, // DeliverCapture: como se entrega una captura, la misma en toda tool
  Lsp.RemoteRun;

{ "x,y,w,h" en pixeles del escritorio -> cuatro enteros; w y h > 0. }
function ParseRegion(const ATexto: string; out X, Y, W, H: Integer): Boolean;
var
  P: TArray<string>;
begin
  P := ATexto.Replace(' ', '').Split([',']);
  Result := (Length(P) = 4) and TryStrToInt(P[0], X) and TryStrToInt(P[1], Y) and
    TryStrToInt(P[2], W) and TryStrToInt(P[3], H) and (W > 0) and (H > 0);
end;

{ Las lineas "VENTANA x y w h titulo" que el nodo Windows escribe con
  command=windows, como JSON, y de paso la primera que casa con AWindow. }
function VentanasDeLaSalida(const ASalida, AWindow: string;
  out X, Y, W, H: Integer; out AHay: Boolean): TJSONArray;
var
  L: string;
  T: TArray<string>;
  O: TJSONObject;
  Titulo: string;
  Lineas: TArray<string>;
  Desde, I: Integer;
begin
  Result := TJSONArray.Create;
  AHay := False;
  // La lista de la ULTIMA captura: el nodo imprime una detras de cada
  // CAPTURA= (24-sep), y la que describe la imagen devuelta es la ultima
  Lineas := ASalida.Split([#10]);
  Desde := 0;
  for I := 0 to High(Lineas) do
    if Lineas[I].Contains('ventanas visibles') then
      Desde := I;
  for I := Desde to High(Lineas) do
  begin
    L := Lineas[I];
    if not L.TrimLeft.StartsWith('VENTANA ') then
      Continue;
    // "VENTANA x y w h <titulo con espacios>": Split con tope TIRA el resto
    // (medido: "Experiencia de entrada" quedaba en "Experiencia"), asi que
    // el titulo se corta a mano tras el quinto espacio
    T := L.Trim.Split([' ']);
    if Length(T) < 6 then
      Continue;
    Titulo := L.Trim;
    for var K := 1 to 5 do
      Titulo := Titulo.Substring(Titulo.IndexOf(' ') + 1);
    Titulo := Titulo.Trim([#13, ' ']);
    O := TJSONObject.Create;
    Result.AddElement(O);
    O.AddPair('title', Titulo);
    O.AddPair('x', TJSONNumber.Create(StrToIntDef(T[1], 0)));
    O.AddPair('y', TJSONNumber.Create(StrToIntDef(T[2], 0)));
    O.AddPair('w', TJSONNumber.Create(StrToIntDef(T[3], 0)));
    O.AddPair('h', TJSONNumber.Create(StrToIntDef(T[4], 0)));
    if (not AHay) and (AWindow <> '') and
       Titulo.ToLower.Contains(AWindow.ToLower) then
    begin
      AHay := True;
      X := StrToIntDef(T[1], 0);
      Y := StrToIntDef(T[2], 0);
      W := StrToIntDef(T[3], 0);
      H := StrToIntDef(T[4], 0);
    end;
  end;
end;

constructor TDesktopLinuxTool.Create;
begin
  inherited;
  FName := 'delphi_desktop';
  FDescription := SD_ADBLINUX;
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
  Cmd, Salida, Destino, Local, Fallo, Remota, Proj, Nota: string;
  Args: TArray<string>;
  Bajada, Propia: string;
  Res: TJSONObject;
  Return: TJSONObject;
  EsWin, HayVentana, ConRecorte: Boolean;
  RX, RY, RW, RH, AnchoOrig, AltoOrig, PX, PY: Integer;
  Ventanas: TJSONArray;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'screenshot';
  { "windows" se leia como el sistema operativo, y desde el 24-sep ademas
    es el nombre de la LISTA que trae cada captura: el gesto pasa a llamarse
    overview (David, 24-sep-2026) y "windows" sigue aceptado sin anunciarse,
    que un agente puede tenerlo apuntado. }
  if Cmd = 'windows' then
    Cmd := 'overview';
  if not MatchStr(Cmd, ['screenshot', 'tap', 'type', 'key', 'overview', 'status']) then
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

  { Sin perfil no hay destino: ProfileHostDenied con '' no encuentra nada y
    dejaba pasar, y el fallo salia de paclient con otro nombre. }
  if Params.Profile.Trim = '' then
    Exit(SR_ADBLINUX_NEEDPROFILE);
  Result := ProfileHostDenied(Params.Profile.Trim);
  if Result <> '' then
    Exit;
  { El destino dice que nodo y que teclas espera: lo lee el .profile, nunca
    el nombre del perfil (que no significa nada). }
  EsWin := PlataformaDelPerfil(Params.Profile.Trim).StartsWith('Win', True);
  { Recorte: una VISTA del mismo fotograma, hecha aqui (Lsp.Imagen). region
    vale en todos; window por la lista que trae cada captura (en Linux, las
    ventanas X11/Xwayland: toda aplicacion FMX). }
  ConRecorte := False;
  RX := 0; RY := 0; RW := 0; RH := 0;
  if (Params.Region.Trim <> '') and (Params.Window.Trim <> '') then
    Exit(SR_ADBLINUX_REGION_OR_WINDOW);
  if Params.Region.Trim <> '' then
  begin
    if Cmd <> 'screenshot' then
      Exit(SR_ADBLINUX_CROP_ONLY_SHOT);
    if not ParseRegion(Params.Region.Trim, RX, RY, RW, RH) then
      Exit(SR_ADBLINUX_REGION_BAD);
    ConRecorte := True;
  end;
  if Params.Window.Trim <> '' then
  begin
    if Cmd <> 'screenshot' then
      Exit(SR_ADBLINUX_CROP_ONLY_SHOT);
  end;
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

  { Los argumentos del nodo van como argv, uno a uno: no hay shell en medio
    (hasta el 2026-09-22 el texto viajaba por un /bin/sh y un "hola; lo que
    sea" ejecutaba la segunda mitad; el lanzador lo entrega tal cual). }
  Args := [NODE_KEY];
  if Cmd = 'tap' then
  begin
    if (Params.X.Trim = '') or (Params.Y.Trim = '') then
      Exit(SR_ADBLINUX_NEEDXY);
    // Con frame, x,y son de la imagen que el agente miro y el servidor los
    // pasa a pixeles de captura (Lsp.InlineImages.FramePoint).
    var FP := FramePoint(Params.Frame, Params.X, Params.Y, PX, PY);
    if FP <> '' then
      Exit(FP);
    Args := Args + [IntToStr(PX), IntToStr(PY)];
  end
  else if Cmd = 'type' then
  begin
    if Params.Text.Trim = '' then
      Exit(SR_ADBLINUX_NEEDTEXT);
    { Con coordenadas es UN solo viaje: pulsa para dar el foco y escribe. }
    if (Params.X.Trim <> '') and (Params.Y.Trim <> '') then
    begin
      var FT := FramePoint(Params.Frame, Params.X, Params.Y, PX, PY);
      if FT <> '' then
        Exit(FT);
      Args := Args + ['escribe', IntToStr(PX), IntToStr(PY), Params.Text.Trim];
    end
    else
      Args := Args + ['texto', Params.Text.Trim];
  end
  else if Cmd = 'key' then
  begin
    { Cada nodo habla el idioma de su sistema: en Linux un codigo evdev (una
      POSICION del teclado), en Windows el NOMBRE de la tecla. Un numero en
      Windows no es la misma tecla que en Linux, asi que no se traduce: se
      rechaza diciendo lo que ese destino espera. }
    { Modificadores (Ctrl+K, Alt+Tab, Ctrl+Shift+S): por nombre en la tool,
      y el nodo los recibe DELANTE de la tecla, que es el orden en que se
      pulsan (y se sueltan al reves). En Linux viajan como codigos evdev; en
      Windows por su nombre, que el nodo ya conoce. Hasta 1.0.17 no habia
      forma (informe de Hermes 2026-09-22: un campo que solo abre Ctrl+K). }
    var Mods: TArray<string> := nil;
    for var M in Params.Modifiers.ToLower.Split([',', '+', ' '], TStringSplitOptions.ExcludeEmpty) do
    begin
      var Mo := M.Trim;
      if Mo = 'control' then Mo := 'ctrl';
      if Mo = 'win' then Mo := 'super';
      if not MatchText(Mo, ['ctrl', 'shift', 'alt', 'super']) then
        Exit(Format(SR_ADBLINUX_MODIFIERS_BAD_FMT, [M.Trim]));
      if EsWin then
        Mods := Mods + [Mo]
      else if Mo = 'ctrl' then Mods := Mods + ['29']
      else if Mo = 'shift' then Mods := Mods + ['42']
      else if Mo = 'alt' then Mods := Mods + ['56']
      else Mods := Mods + ['125'];
    end;
    if EsWin then
    begin
      if not NombreDeTeclaValido(Params.Code.Trim) then
        Exit(SR_DESKTOP_NEEDCODE);
      Args := Args + ['tecla'] + Mods + [Params.Code.Trim];
    end
    else
    begin
      if (Params.Code.Trim = '') or (StrToIntDef(Params.Code.Trim, 0) <= 0) then
        Exit(SR_ADBLINUX_NEEDCODE);
      Args := Args + ['tecla'] + Mods + [IntToStr(StrToIntDef(Params.Code.Trim, 0))];
    end;
  end
  else if Cmd = 'overview' then
    Args := Args + ['ventanas'];
  { La lista de ventanas viaja con CADA captura (24-sep): window= no manda
    nada al nodo; se recorta aqui con la lista que trae la captura. }
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
  Res := RemoteRun(Params.Profile.Trim, Proj, '', Args, 60000);
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
      contesta "Acceso denegado" a cualquier captura: se nombra, que despista.
      Solo cuando NO hubo captura: desde 1.0.16 el nodo tiene un respaldo
      (PrintWindow) y su linea RESPALDO cita el mismo error con captura hecha. }
    if (RutaDeCaptura(Salida) = '') and
       (Salida.Contains('Acceso denegado') or Salida.Contains('Access is denied')) then
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
      Fallo := CaptureTarget(Params.Out_, CAPTURE_SUB_DESKTOP,
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
      Bajada := NuevaCarpetaDescarga(Destino); // EL nombrador: el guard del borrado la reconoce
      Fallo := FetchFromTarget(Params.Profile.Trim, Proj,
        TPath.GetFileName(Remota), Bajada, Local);
      end;
      if Fallo = '' then
      begin
        try
          CrearCarpeta(Destino);
          TFile.Move(Local, Propia);
          Local := Propia;
        except
          // Antes la imagen se quedaba 'donde cayo', dentro de la .tmp-, y la
          // .tmp- se quedaba para siempre (una de Hermes, 25-sep-2026). Ahora
          // se dice y no queda nada.
          on E: Exception do
            Fallo := 'no pude colocar la captura bajada: ' + E.Message;
        end;
        try
          BorraArbol(Bajada); // SIEMPRE, sin cruzar enlaces: ver Lsp.Guard
        except
          // limpiar no puede tumbar la respuesta
        end;
        { La lista de ventanas viaja CON cada captura (David, 24-sep), en los
          dos sistemas y en pixeles de la imagen: titulo y rectangulo. En
          Linux son las X11/Xwayland (toda aplicacion FMX; las nativas
          Wayland no salen) y la nota lo dice. window= recorta por ella. }
        Ventanas := VentanasDeLaSalida(Salida, Params.Window.Trim, RX, RY, RW, RH, HayVentana);
        Return.AddPair('windows', Ventanas);
        Return.AddPair('windowsNote', IfThen(EsWin, SN_DESKTOP_WINDOWS_WIN, SN_DESKTOP_WINDOWS_LINUX));
        { En Linux "windows" abre la vista de actividades y la captura es ESA
          vista: se dice como leerla (un agente la tomo por el escritorio a
          secas, 24-sep). }
        if (Cmd = 'overview') and not EsWin then
          Return.AddPair('overviewNote', SN_DESKTOP_OVERVIEW_LINUX);
        if (Cmd = 'screenshot') and (Params.Window.Trim <> '') then
        begin
          if not HayVentana then
            Fallo := Format(SR_ADBLINUX_WINDOW_NOMATCH_FMT, [Params.Window.Trim])
          else
            ConRecorte := True;
        end;
        if (Fallo = '') and ConRecorte then
        begin
          Fallo := RecortaPng(Local, RX, RY, RW, RH, AnchoOrig, AltoOrig);
          if Fallo = '' then
          begin
            var Origen := TJSONObject.Create;
            Origen.AddPair('x', TJSONNumber.Create(RX));
            Origen.AddPair('y', TJSONNumber.Create(RY));
            Return.AddPair('origin', Origen);
            Return.AddPair('region', Format('%d,%d,%d,%d', [RX, RY, RW, RH]));
            Return.AddPair('croppedFrom', Format('%dx%d', [AnchoOrig, AltoOrig]));
          end;
        end;
        if Fallo <> '' then
          Return.AddPair('screenshotError', Fallo)
        else
        begin
          Return.AddPair('screenshot', Local);
          Return.AddPair('screenshotBytes', TJSONNumber.Create(TFile.GetSize(Local)));
          // UN SOLO PASO (David, 25-sep-2026): la imagen viaja en esta misma
          // respuesta, o fichero + enlace con inline=false. Lo decide
          // DeliverCapture, el mismo para toda tool que capture.
          // El frame lleva el origen del recorte: el agente no suma nada.
          var OX := 0;
          var OY := 0;
          if ConRecorte then
          begin
            OX := RX;
            OY := RY;
          end;
          var EnLinea := DeliverCapture('delphi_desktop', Local, Params.Inline_,
            Params.MaxWidth, OX, OY, 1.0, 1.0, Return);
          if ConRecorte then
            Return.AddPair('note', Format(SN_ADBLINUX_CROP_NOTE_FMT, [RX, RY]))
          else if not EnLinea then
            Return.AddPair('note', 'mide el pixel SOBRE esta imagen y pasalo a ' +
              'command=tap; bajala con download o delphi_fetch. Al recogerla ENTERA ' +
              'se borra del servidor: si la necesitas otra vez, pide otra captura ' +
              '(una pedida con out= no se borra)');
        end;
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

finalization
  GPerfiles.Free;
  GPerfilesLock.Free;

end.
