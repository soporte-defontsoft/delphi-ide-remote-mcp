unit Mld.DBus;

{ Conversacion con el bus de sesion de D-Bus, por carga dinamica de
  libdbus-1.so.3 (ver [Mld.Dyn]). Es el canal por el que el nodo pedira al
  escritorio lo que necesita: nada se enlaza en compilacion.

  El bus de sesion se localiza solo a traves de DBUS_SESSION_BUS_ADDRESS, que
  PAServer ya hereda de la sesion grafica - medido 18-sep. }

interface

uses
  System.Classes,
  Mld.Dyn;

type
  { La terna que importa, calcada del modelo de TDisplay de FMX: lo que el
    escritorio dice en coordenadas LOGICAS, lo que mide en PIXELES y el
    factor entre ambas. Confundirlas fue el lio del 125% del 12-sep. }
  TPantalla = record
    X, Y: Integer;
    Escala: Double;
    Principal: Boolean;
  end;

  (* Un valor de una llamada: un argumento suelto (Clave vacia) o una entrada
     del diccionario de opciones a{sv} que piden el portal y Mutter. *)
  TValorDBus = record
    Clave: string;
    Tipo: Char;        // 's' cadena, 'o' ruta de objeto, 'u' entero sin signo
    Texto: string;
    Num: Cardinal;
    class function Cadena(const AClave, AValor: string): TValorDBus; static;
    class function Ruta(const AValor: string): TValorDBus; static;
    class function Entero(const AClave: string; AValor: Cardinal): TValorDBus; static;
  end;

  TConexionBus = class
  private
    FLib: TLibreria;
    FConn: Pointer;
    FError: string;
    FSuscrito: Boolean;   // ya se pidieron al bus las respuestas del portal
    FPorPortal: Boolean;  // las manos van por el portal estandar, no por Mutter
    function Resolver: Boolean;
    function Suscribir: Boolean;
    function EsperarRespuesta(const APeticion: string; AMs: Integer;
      out ACodigo: Cardinal; AResultados: TStringList): Boolean;
    function PedirAlPortal(const AIface, AMetodo: string;
      const APrevios, AOpciones: array of TValorDBus; AMs: Integer;
      const ANegadoFmt, ACalladoFmt: string; AResultados: TStringList): Boolean;
    function PrepararCanalPortal(out ASesion: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Abre libdbus y se engancha al bus de sesion, o al de SISTEMA con
      ADeSistema (ahi vive login1). False deja el motivo en Error. }
    function Conectar(ADeSistema: Boolean = False): Boolean;
    { El nombre unico que el bus asigna a esta conexion (p.ej. ':1.123'):
      la prueba de que la conexion es real y esta viva. }
    function NombreUnico: string;
    function Conectada: Boolean;
    property Error: string read FError;
    function ListarServicios(out ALista: TArray<string>): Boolean;
    function LeerPantallas(out APantallas: TArray<TPantalla>): Boolean;
    function Llamar(const ADestino, ARuta, AIface, AMetodo: string;
      const AArgs: array of string; out ARespuesta: Pointer): Boolean;
    function PrimeraCadena(AResp: Pointer; out AValor: string): Boolean;
    { El PRIMER valor de la respuesta como lista de cadenas (as), suelta o
      dentro de un variant (una propiedad llega asi): el gemelo de
      PrimeraCadena para listas. ListarServicios la leia a mano. }
    function ListaDeCadenas(AResp: Pointer; out ALista: TArray<string>): Boolean;
    { El entorno que el gestor de usuario de systemd da a lo que arranca: el
      que la sesion grafica le importa al empezar (DISPLAY, WAYLAND_DISPLAY,
      XAUTHORITY...), lo que contesta systemctl --user show-environment. Es el
      juez del entorno grafico de ESTE usuario: GNOME y Plasma lo escriben, y
      cada uno con su propio fichero de autorizacion de X. False si no
      contesta (sin systemd de usuario), con el motivo en Error. }
    function EntornoDelGestor(out AEntorno: TArray<string>): Boolean;
    function ProbarSesion(out ARuta, AId: string): Boolean;
    function AdmiteDescriptores: Boolean;
    (* Una llamada con sus argumentos sueltos (APrevios) y, detras, su
       diccionario de opciones a{sv} (AOpciones, las que sean): EL
       componedor de las llamadas al portal y a Mutter. *)
    function LlamarConOpciones(const ADestino, ARuta, AIface, AMetodo: string;
      const APrevios, AOpciones: array of TValorDBus; AMs: Integer;
      out ARespuesta: Pointer): Boolean;
    { La sesion de las manos. ELIGE EL BUS: si el escritorio ofrece la API de
      Mutter (GNOME), por ella, como siempre; si no (Plasma), por el portal
      estandar de escritorio remoto, que pide permiso una vez y con su token
      no vuelve a preguntar. AbrirCanal y CerrarSesion siguen el camino
      elegido aqui. }
    function PrepararCanal(out ARutaRd, ARutaSc, AStream: string): Boolean;
    procedure CerrarSesion(const ARuta: string);
    function AbrirCanal(const ARuta: string; out ADescriptor: Integer): Boolean;
    { La pantalla ENTERA, dialogos de Wayland incluidos: lo que X11 no puede
      dar en Xwayland rootless. Deja en AFichero la ruta del PNG que escribe
      el escritorio. }
    function CapturarEscritorio(out AFichero: string; AMs: Integer): Boolean;
    { El PRIMER valor de la respuesta como booleano, suelto o dentro de un
      variant (las propiedades de D-Bus llegan asi): el gemelo de
      PrimeraCadena. }
    function PrimerBooleano(AResp: Pointer; out AValor: Boolean): Boolean;
    { Si la sesion de logind AId esta bloqueada, segun login1 (bus de
      SISTEMA: Conectar(True)). False si login1 no contesta, con el motivo
      en Error: quien llama decide entonces seguir sin saberlo. }
    function SesionBloqueada(const AId: string; out ABloqueada: Boolean): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Diagnostics,
  Posix.SysStat,
  Mld.Textos;

{ Declarada aqui porque CapturarEscritorio la usa antes de su sitio. }
function DesdeUri(const AUri: string): string; forward;

const
  { dbus-shared.h: el enumerado empieza en SESSION; 1 es el bus del SISTEMA
    (medido 18-sep), donde vive login1. }
  DBUS_BUS_SESSION = 0;
  DBUS_BUS_SYSTEM = 1;
  DBUS_TYPE_STRING = Ord('s');
  DBUS_TYPE_ARRAY = Ord('a');
  DBUS_TYPE_STRUCT = Ord('r');
  DBUS_TYPE_INT32 = Ord('i');
  DBUS_TYPE_UINT32 = Ord('u');
  DBUS_TYPE_DOUBLE = Ord('d');
  DBUS_TYPE_BOOLEAN = Ord('b');
  DBUS_TYPE_OBJECT_PATH = Ord('o');
  DBUS_TYPE_VARIANT = Ord('v');
  DBUS_TYPE_UNIX_FD = Ord('h');
  DBUS_TYPE_DICT_ENTRY = Ord('e');
  { DBusMessageIter es opaco; 128 bytes sobran para su tamano real (72). }
  TAM_ITER = 128;
  { el portal de escritorio (xdg-desktop-portal) y el de escritorio remoto }
  PORTAL = 'org.freedesktop.portal.Desktop';
  RUTA_PORTAL = '/org/freedesktop/portal/desktop';
  PORTAL_RD = 'org.freedesktop.portal.RemoteDesktop';
  { la API propia de GNOME: si el bus la ofrece, las manos van por ella }
  MUTTER_RD = 'org.gnome.Mutter.RemoteDesktop';
  { lo que espera una llamada con opciones, y una respuesta del portal: en el
    Start de las manos sale el dialogo de permiso la primera vez, y alguien
    tiene que aceptarlo delante de la pantalla }
  MS_LLAMADA = 60000;
  { lo que esperan las manos cada respuesta del portal. La primera vez en una
    maquina, Start espera a que alguien acepte el dialogo, que se va con la
    sesion cuando el nodo se rinde: medido el 5-nov-2026, un humano delante
    tardo 14,7 s y con 25 s "se fue demasiado rapido". Y con el despliegue y
    la captura la respuesta tiene que caber en el minuto de un cliente (con 60 s
    el cliente se rindio a los 60 y el servidor contesto a los 62). Con el
    token, Start contesta en 13 ms. }
  MS_RESPUESTA_MANOS = 40000;
  { SelectDevices: teclado (1) y puntero (2); el permiso dura hasta que el
    usuario lo quite (persist_mode 2), y el portal da un token para no
    volver a preguntar }
  TECLADO_Y_PUNTERO = 3;
  PERSISTIR_HASTA_REVOCAR = 2;
  { la cadena vacia de C: un PAnsiChar de '' es nil, y libdbus no lo acepta }
  CERO: AnsiChar = #0;

type
  { struct DBusError de dbus/dbus-errors.h: dos cadenas, un campo de bits y
    un hueco de alineacion. 32 bytes en x86-64. }
  TDBusError = record
    Nombre: MarshaledAString;
    Mensaje: MarshaledAString;
    Banderas: UInt32;
    Relleno: UInt32;
    Hueco: Pointer;
  end;

  TDbusErrorInit = procedure(AErr: Pointer); cdecl;
  TDbusErrorFree = procedure(AErr: Pointer); cdecl;
  TDbusErrorIsSet = function(AErr: Pointer): LongBool; cdecl;
  TDbusBusGet = function(ATipo: Integer; AErr: Pointer): Pointer; cdecl;
  TDbusBusGetUniqueName = function(AConn: Pointer): MarshaledAString; cdecl;
  TDbusSetExitOnDisconnect = procedure(AConn: Pointer; ASalir: LongBool); cdecl;
  TDbusMsgNew = function(ADestino, ARuta, AIface, AMetodo: MarshaledAString): Pointer; cdecl;
  TDbusEnviarYEsperar = function(AConn, AMsg: Pointer; AMs: Integer;
    AErr: Pointer): Pointer; cdecl;
  TDbusMsgUnref = procedure(AMsg: Pointer); cdecl;
  TDbusIterInit = function(AMsg, AIter: Pointer): LongBool; cdecl;
  TDbusIterTipo = function(AIter: Pointer): Integer; cdecl;
  TDbusIterEntrar = procedure(AIter, ASub: Pointer); cdecl;
  TDbusIterLeer = procedure(AIter, ADestino: Pointer); cdecl;
  TDbusIterSiguiente = function(AIter: Pointer): LongBool; cdecl;
  TDbusIterInitAppend = procedure(AMsg, AIter: Pointer); cdecl;
  TDbusIterAppend = function(AIter: Pointer; ATipo: Integer; AVal: Pointer): LongBool; cdecl;
  TDbusPuedeEnviar = function(AConn: Pointer; ATipo: Integer): LongBool; cdecl;
  TDbusIterAbrir = function(AIter: Pointer; ATipo: Integer;
    AFirma: MarshaledAString; ASub: Pointer): LongBool; cdecl;
  TDbusIterCerrar = function(AIter, ASub: Pointer): LongBool; cdecl;
  TDbusAnadirFiltro = procedure(AConn: Pointer; ARegla: MarshaledAString;
    AErr: Pointer); cdecl;
  TDbusLeerEscribir = function(AConn: Pointer; AMs: Integer): LongBool; cdecl;
  TDbusSacarMensaje = function(AConn: Pointer): Pointer; cdecl;
  TDbusMsgRuta = function(AMsg: Pointer): MarshaledAString; cdecl;
  TDbusMsgMiembro = function(AMsg: Pointer): MarshaledAString; cdecl;

var
  DbusErrorInit: TDbusErrorInit;
  DbusErrorFree: TDbusErrorFree;
  DbusErrorIsSet: TDbusErrorIsSet;
  DbusBusGet: TDbusBusGet;
  DbusBusGetUniqueName: TDbusBusGetUniqueName;
  DbusSetExitOnDisconnect: TDbusSetExitOnDisconnect;
  DbusMsgNew: TDbusMsgNew;
  DbusEnviarYEsperar: TDbusEnviarYEsperar;
  DbusMsgUnref: TDbusMsgUnref;
  DbusIterInit: TDbusIterInit;
  DbusIterTipo: TDbusIterTipo;
  DbusIterEntrar: TDbusIterEntrar;
  DbusIterLeer: TDbusIterLeer;
  DbusIterSiguiente: TDbusIterSiguiente;
  DbusIterInitAppend: TDbusIterInitAppend;
  DbusIterAppend: TDbusIterAppend;
  DbusPuedeEnviar: TDbusPuedeEnviar;
  DbusIterAbrir: TDbusIterAbrir;
  DbusIterCerrar: TDbusIterCerrar;
  DbusAnadirFiltro: TDbusAnadirFiltro;
  DbusLeerEscribir: TDbusLeerEscribir;
  DbusSacarMensaje: TDbusSacarMensaje;
  DbusMsgRuta: TDbusMsgRuta;
  DbusMsgMiembro: TDbusMsgMiembro;

function Texto(A: MarshaledAString): string;
begin
  if A = nil then
    Result := ''
  else
    Result := string(UTF8String(A));
end;

class function TValorDBus.Cadena(const AClave, AValor: string): TValorDBus;
begin
  Result := Default(TValorDBus);
  Result.Clave := AClave;
  Result.Tipo := 's';
  Result.Texto := AValor;
end;

class function TValorDBus.Ruta(const AValor: string): TValorDBus;
begin
  Result := Default(TValorDBus);
  Result.Tipo := 'o';
  Result.Texto := AValor;
end;

class function TValorDBus.Entero(const AClave: string; AValor: Cardinal): TValorDBus;
begin
  Result := Default(TValorDBus);
  Result.Clave := AClave;
  Result.Tipo := 'u';
  Result.Num := AValor;
end;

{ Anade AValor (sin su clave) en AIter con su tipo. libdbus copia lo que
  recibe, asi que la cadena puede morir al volver. }
function AnadeBasico(AIter: Pointer; const AValor: TValorDBus): Boolean;
var
  U: UTF8String;
  Pc: MarshaledAString;
  Num: Cardinal;
begin
  if AValor.Tipo = 'u' then
  begin
    Num := AValor.Num;
    Exit(DbusIterAppend(AIter, DBUS_TYPE_UINT32, @Num));
  end;
  U := UTF8String(AValor.Texto);
  if U = '' then
    Pc := MarshaledAString(@CERO)
  else
    Pc := MarshaledAString(PAnsiChar(U));
  if AValor.Tipo = 'o' then
    Result := DbusIterAppend(AIter, DBUS_TYPE_OBJECT_PATH, @Pc)
  else
    Result := DbusIterAppend(AIter, DBUS_TYPE_STRING, @Pc);
end;

{ EL sitio del token de las manos del portal: fuera de la carpeta del nodo,
  que cada despliegue reescribe, en el estado de ESTE usuario
  (XDG_STATE_HOME, o ~/.local/state). Solo el nodo lo escribe y lo lee. }
function FicheroDelToken: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('XDG_STATE_HOME');
  if Base = '' then
    Base := GetEnvironmentVariable('HOME') + '/.local/state';
  Result := Base + '/mcp-desktop-node/remote-desktop.token';
end;

{ El token que dio el portal la ultima vez; '' si no hay (entonces pregunta). }
function TokenDeLasManos: string;
begin
  Result := '';
  try
    if TFile.Exists(FicheroDelToken) then
      Result := TFile.ReadAllText(FicheroDelToken).Trim;
  except
    Result := '';
  end;
end;

{ Guarda el token nuevo, solo para ESTE usuario (la carpeta 0700, el fichero
  0600): con el, la proxima sesion no pregunta. Si no se puede, la proxima
  vez el portal vuelve a preguntar: no es un fallo de ahora. }
procedure GuardaTokenDeLasManos(const AToken: string);
var
  Carpeta: string;
begin
  if AToken = '' then
    Exit;
  try
    Carpeta := ExtractFileDir(FicheroDelToken);
    ForceDirectories(Carpeta);
    chmod(MarshaledAString(PAnsiChar(UTF8String(Carpeta))), $1C0); // 0700
    TFile.WriteAllText(FicheroDelToken, AToken, TEncoding.ASCII);
    chmod(MarshaledAString(PAnsiChar(UTF8String(FicheroDelToken))), $180); // 0600
  except
    // sin token guardado la proxima vez se pregunta: no se para por eso
  end;
end;

constructor TConexionBus.Create;
begin
  inherited Create;
  FLib := TLibreria.Create;
end;

destructor TConexionBus.Destroy;
begin
  { La conexion compartida del bus NO se cierra: libdbus la posee. }
  FLib.Free;
  inherited;
end;

function TConexionBus.Conectada: Boolean;
begin
  Result := FConn <> nil;
end;

function TConexionBus.Resolver: Boolean;

  function Uno(const ASimbolo: string; out ADir: Pointer): Boolean;
  begin
    Result := FLib.SimboloOMotivo(ASimbolo, ADir, FError);
  end;

begin
  Result :=
    Uno('dbus_error_init', Pointer(@DbusErrorInit)) and
    Uno('dbus_error_free', Pointer(@DbusErrorFree)) and
    Uno('dbus_error_is_set', Pointer(@DbusErrorIsSet)) and
    Uno('dbus_bus_get', Pointer(@DbusBusGet)) and
    Uno('dbus_bus_get_unique_name', Pointer(@DbusBusGetUniqueName)) and
    Uno('dbus_connection_set_exit_on_disconnect', Pointer(@DbusSetExitOnDisconnect)) and
    Uno('dbus_message_new_method_call', Pointer(@DbusMsgNew)) and
    Uno('dbus_connection_send_with_reply_and_block', Pointer(@DbusEnviarYEsperar)) and
    Uno('dbus_message_unref', Pointer(@DbusMsgUnref)) and
    Uno('dbus_message_iter_init', Pointer(@DbusIterInit)) and
    Uno('dbus_message_iter_get_arg_type', Pointer(@DbusIterTipo)) and
    Uno('dbus_message_iter_recurse', Pointer(@DbusIterEntrar)) and
    Uno('dbus_message_iter_get_basic', Pointer(@DbusIterLeer)) and
    Uno('dbus_message_iter_next', Pointer(@DbusIterSiguiente)) and
    Uno('dbus_message_iter_init_append', Pointer(@DbusIterInitAppend)) and
    Uno('dbus_message_iter_append_basic', Pointer(@DbusIterAppend)) and
    Uno('dbus_connection_can_send_type', Pointer(@DbusPuedeEnviar)) and
    Uno('dbus_message_iter_open_container', Pointer(@DbusIterAbrir)) and
    Uno('dbus_message_iter_close_container', Pointer(@DbusIterCerrar)) and
    Uno('dbus_bus_add_match', Pointer(@DbusAnadirFiltro)) and
    Uno('dbus_connection_read_write', Pointer(@DbusLeerEscribir)) and
    Uno('dbus_connection_pop_message', Pointer(@DbusSacarMensaje)) and
    Uno('dbus_message_get_path', Pointer(@DbusMsgRuta)) and
    Uno('dbus_message_get_member', Pointer(@DbusMsgMiembro));
end;

function TConexionBus.Conectar(ADeSistema: Boolean): Boolean;
var
  Err: TDBusError;
begin
  FError := '';
  if not FLib.Abierta then
    if not FLib.Abrir('libdbus-1.so.3') then
    begin
      FError := MsgFmt(SF_NODE_NO_HAY_LIB_FMT, ['libdbus', FLib.Error]);
      Exit(False);
    end;
  if not Resolver then
    Exit(False);

  FillChar(Err, SizeOf(Err), 0);
  DbusErrorInit(@Err);
  try
    if ADeSistema then
      FConn := DbusBusGet(DBUS_BUS_SYSTEM, @Err)
    else
      FConn := DbusBusGet(DBUS_BUS_SESSION, @Err);
    if DbusErrorIsSet(@Err) then
    begin
      FError := Format('%s: %s', [Texto(Err.Nombre), Texto(Err.Mensaje)]);
      FConn := nil;
      Exit(False);
    end;
  finally
    DbusErrorFree(@Err);
  end;

  if FConn = nil then
  begin
    FError := MsgText(SF_NODE_BUS_NO_DEVOLVIO_CONEXION);
    Exit(False);
  end;

  { Por defecto libdbus TUMBA el proceso si el bus se cae. Un servicio decide
    eso por su cuenta. }
  DbusSetExitOnDisconnect(FConn, False);
  Result := True;
end;

function TConexionBus.NombreUnico: string;
begin
  if FConn = nil then
    Exit('');
  Result := Texto(DbusBusGetUniqueName(FConn));
end;

function TConexionBus.ListarServicios(out ALista: TArray<string>): Boolean;
var
  Resp: Pointer;
begin
  ALista := nil;
  Result := False;
  if not Llamar('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
    'ListNames', [], Resp) then
    Exit;
  try
    Result := ListaDeCadenas(Resp, ALista);
  finally
    DbusMsgUnref(Resp);
  end;
end;

function TConexionBus.ListaDeCadenas(AResp: Pointer; out ALista: TArray<string>): Boolean;
var
  It, Vr, Sub: array[0..TAM_ITER - 1] of Byte;
  Lista: Pointer;
  Pc: MarshaledAString;
begin
  ALista := nil;
  Result := False;
  FillChar(It, SizeOf(It), 0);
  if not DbusIterInit(AResp, @It) then
  begin
    FError := MsgText(SF_NODE_RESPUESTA_SIN_ARGUMENTOS);
    Exit;
  end;
  Lista := @It;
  if DbusIterTipo(@It) = DBUS_TYPE_VARIANT then
  begin
    FillChar(Vr, SizeOf(Vr), 0);
    DbusIterEntrar(@It, @Vr);
    Lista := @Vr;
  end;
  if DbusIterTipo(Lista) <> DBUS_TYPE_ARRAY then
  begin
    FError := MsgText(SF_NODE_ESPERABA_ARRAY_CADENAS);
    Exit;
  end;
  FillChar(Sub, SizeOf(Sub), 0);
  DbusIterEntrar(Lista, @Sub);
  while DbusIterTipo(@Sub) = DBUS_TYPE_STRING do
  begin
    Pc := nil;
    DbusIterLeer(@Sub, @Pc);
    ALista := ALista + [Texto(Pc)];
    DbusIterSiguiente(@Sub);
  end;
  Result := True;
end;

function TConexionBus.EntornoDelGestor(out AEntorno: TArray<string>): Boolean;
const
  SD = 'org.freedesktop.systemd1';
var
  Resp: Pointer;
begin
  AEntorno := nil;
  Result := False;
  if not Llamar(SD, '/org/freedesktop/systemd1', 'org.freedesktop.DBus.Properties', 'Get',
    [SD + '.Manager', 'Environment'], Resp) then
    Exit;
  try
    Result := ListaDeCadenas(Resp, AEntorno);
  finally
    DbusMsgUnref(Resp);
  end;
end;

function TConexionBus.LeerPantallas(out APantallas: TArray<TPantalla>): Boolean;
var
  Err: TDBusError;
  Msg, Resp: Pointer;
  It, Arr, Est: array[0..TAM_ITER - 1] of Byte;
  P: TPantalla;
  Acc: TArray<TPantalla>;
  EnteroI: Integer;
  Doble: Double;
  Bool32: LongBool;
begin
  APantallas := nil;
  FError := '';
  Result := False;
  if FConn = nil then
  begin
    FError := MsgText(SF_NODE_NO_HAY_CONEXION_BUS);
    Exit;
  end;
  Msg := DbusMsgNew('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig',
    'org.gnome.Mutter.DisplayConfig', 'GetCurrentState');
  if Msg = nil then
  begin
    FError := MsgText(SF_NODE_NO_CONSTRUIR_MENSAJE);
    Exit;
  end;
  FillChar(Err, SizeOf(Err), 0);
  DbusErrorInit(@Err);
  try
    Resp := DbusEnviarYEsperar(FConn, Msg, 5000, @Err);
    if DbusErrorIsSet(@Err) then
    begin
      FError := Format('%s: %s', [Texto(Err.Nombre), Texto(Err.Mensaje)]);
      Exit;
    end;
    if Resp = nil then
    begin
      FError := MsgText(SF_NODE_ESCRITORIO_NO_RESPONDIO);
      Exit;
    end;
    try
      FillChar(It, SizeOf(It), 0);
      if not DbusIterInit(Resp, @It) then
      begin
        FError := MsgText(SF_NODE_RESPUESTA_SIN_ARGUMENTOS);
        Exit;
      end;
      DbusIterSiguiente(@It);
      DbusIterSiguiente(@It);
      if DbusIterTipo(@It) <> DBUS_TYPE_ARRAY then
      begin
        FError := MsgText(SF_NODE_TERCER_ARGUMENTO_NO_ARRAY);
        Exit;
      end;
      FillChar(Arr, SizeOf(Arr), 0);
      DbusIterEntrar(@It, @Arr);
      while DbusIterTipo(@Arr) = DBUS_TYPE_STRUCT do
      begin
        FillChar(Est, SizeOf(Est), 0);
        FillChar(P, SizeOf(P), 0);
        DbusIterEntrar(@Arr, @Est);
        if DbusIterTipo(@Est) = DBUS_TYPE_INT32 then
        begin
          DbusIterLeer(@Est, @EnteroI);
          P.X := EnteroI;
          DbusIterSiguiente(@Est);
        end;
        if DbusIterTipo(@Est) = DBUS_TYPE_INT32 then
        begin
          DbusIterLeer(@Est, @EnteroI);
          P.Y := EnteroI;
          DbusIterSiguiente(@Est);
        end;
        if DbusIterTipo(@Est) = DBUS_TYPE_DOUBLE then
        begin
          DbusIterLeer(@Est, @Doble);
          P.Escala := Doble;
          DbusIterSiguiente(@Est);
        end;
        if DbusIterTipo(@Est) = DBUS_TYPE_UINT32 then
          DbusIterSiguiente(@Est);
        if DbusIterTipo(@Est) = DBUS_TYPE_BOOLEAN then
        begin
          DbusIterLeer(@Est, @Bool32);
          P.Principal := Bool32;
        end;
        Acc := Acc + [P];
        DbusIterSiguiente(@Arr);
      end;
      APantallas := Acc;
      Result := True;
    finally
      DbusMsgUnref(Resp);
    end;
  finally
    DbusErrorFree(@Err);
    DbusMsgUnref(Msg);
  end;
end;

function TConexionBus.Llamar(const ADestino, ARuta, AIface, AMetodo: string;
  const AArgs: array of string; out ARespuesta: Pointer): Boolean;
var
  Err: TDBusError;
  Msg: Pointer;
  It: array[0..TAM_ITER - 1] of Byte;
  I: Integer;
  Us: TArray<UTF8String>;
  Pc: MarshaledAString;
  UD, UR, UI, UM: UTF8String;
begin
  ARespuesta := nil;
  FError := '';
  Result := False;
  if FConn = nil then
  begin
    FError := MsgText(SF_NODE_NO_HAY_CONEXION_BUS);
    Exit;
  end;
  UD := UTF8String(ADestino); UR := UTF8String(ARuta);
  UI := UTF8String(AIface);  UM := UTF8String(AMetodo);
  Msg := DbusMsgNew(MarshaledAString(PAnsiChar(UD)), MarshaledAString(PAnsiChar(UR)),
    MarshaledAString(PAnsiChar(UI)), MarshaledAString(PAnsiChar(UM)));
  if Msg = nil then
  begin
    FError := MsgText(SF_NODE_NO_CONSTRUIR_MENSAJE);
    Exit;
  end;
  try
    if Length(AArgs) > 0 then
    begin
      SetLength(Us, Length(AArgs));
      FillChar(It, SizeOf(It), 0);
      DbusIterInitAppend(Msg, @It);
      for I := 0 to High(AArgs) do
      begin
        Us[I] := UTF8String(AArgs[I]);
        Pc := MarshaledAString(PAnsiChar(Us[I]));
        if not DbusIterAppend(@It, DBUS_TYPE_STRING, @Pc) then
        begin
          FError := MsgText(SF_NODE_NO_ANADIR_ARGUMENTO);
          Exit;
        end;
      end;
    end;
    FillChar(Err, SizeOf(Err), 0);
    DbusErrorInit(@Err);
    try
      ARespuesta := DbusEnviarYEsperar(FConn, Msg, 8000, @Err);
      if DbusErrorIsSet(@Err) then
      begin
        FError := Format('%s: %s', [Texto(Err.Nombre), Texto(Err.Mensaje)]);
        ARespuesta := nil;
        Exit;
      end;
      Result := ARespuesta <> nil;
      if not Result then
        FError := MsgText(SF_NODE_SIN_RESPUESTA);
    finally
      DbusErrorFree(@Err);
    end;
  finally
    DbusMsgUnref(Msg);
  end;
end;

function TConexionBus.PrimeraCadena(AResp: Pointer; out AValor: string): Boolean;
var
  It, Sub: array[0..TAM_ITER - 1] of Byte;
  Pc: MarshaledAString;
  Tipo: Integer;
begin
  AValor := '';
  Result := False;
  FillChar(It, SizeOf(It), 0);
  if not DbusIterInit(AResp, @It) then
    Exit;
  Tipo := DbusIterTipo(@It);
  if Tipo = DBUS_TYPE_VARIANT then
  begin
    FillChar(Sub, SizeOf(Sub), 0);
    DbusIterEntrar(@It, @Sub);
    Tipo := DbusIterTipo(@Sub);
    if (Tipo <> DBUS_TYPE_STRING) and (Tipo <> DBUS_TYPE_OBJECT_PATH) then
      Exit;
    Pc := nil;
    DbusIterLeer(@Sub, @Pc);
  end
  else
  begin
    if (Tipo <> DBUS_TYPE_STRING) and (Tipo <> DBUS_TYPE_OBJECT_PATH) then
      Exit;
    Pc := nil;
    DbusIterLeer(@It, @Pc);
  end;
  AValor := Texto(Pc);
  Result := True;
end;

function TConexionBus.ProbarSesion(out ARuta, AId: string): Boolean;
const
  RD = MUTTER_RD;
var
  Resp: Pointer;
begin
  ARuta := '';
  AId := '';
  Result := False;
  if not Llamar(RD, '/org/gnome/Mutter/RemoteDesktop', RD, 'CreateSession', [], Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, ARuta) then
    begin
      FError := MsgText(SF_NODE_CREATESESSION_SIN_RUTA_SESION);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if Llamar(RD, ARuta, 'org.freedesktop.DBus.Properties', 'Get',
    [RD + '.Session', 'SessionId'], Resp) then
  try
    PrimeraCadena(Resp, AId);
  finally
    DbusMsgUnref(Resp);
  end;
  if Llamar(RD, ARuta, RD + '.Session', 'Stop', [], Resp) then
    DbusMsgUnref(Resp);
  Result := True;
end;

function TConexionBus.PrimerBooleano(AResp: Pointer; out AValor: Boolean): Boolean;
var
  It, Sub: array[0..TAM_ITER - 1] of Byte;
  Bool32: LongBool;
begin
  AValor := False;
  Result := False;
  Bool32 := False;
  FillChar(It, SizeOf(It), 0);
  if not DbusIterInit(AResp, @It) then
    Exit;
  if DbusIterTipo(@It) = DBUS_TYPE_VARIANT then
  begin
    FillChar(Sub, SizeOf(Sub), 0);
    DbusIterEntrar(@It, @Sub);
    if DbusIterTipo(@Sub) <> DBUS_TYPE_BOOLEAN then
      Exit;
    DbusIterLeer(@Sub, @Bool32);
  end
  else
  begin
    if DbusIterTipo(@It) <> DBUS_TYPE_BOOLEAN then
      Exit;
    DbusIterLeer(@It, @Bool32);
  end;
  AValor := Bool32;
  Result := True;
end;

{ login1 da el objeto de la sesion por su id (GetSession) y ese objeto dice
  LockedHint. Es lo que loginctl show-session -p LockedHint pregunta; el
  fichero de /run/systemd/sessions no lo trae (medido 14-oct-2026). }
function TConexionBus.SesionBloqueada(const AId: string; out ABloqueada: Boolean): Boolean;
const
  LOGIN1 = 'org.freedesktop.login1';
var
  Resp: Pointer;
  Ruta: string;
begin
  ABloqueada := False;
  Result := False;
  if not Llamar(LOGIN1, '/org/freedesktop/login1', LOGIN1 + '.Manager', 'GetSession',
    [AId], Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, Ruta) then
    begin
      FError := MsgText(SF_NODE_LOGIN1_SIN_RUTA_SESION);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not Llamar(LOGIN1, Ruta, 'org.freedesktop.DBus.Properties', 'Get',
    [LOGIN1 + '.Session', 'LockedHint'], Resp) then
    Exit;
  try
    Result := PrimerBooleano(Resp, ABloqueada);
    if not Result then
      FError := MsgText(SF_NODE_LOGIN1_SIN_LOCKEDHINT);
  finally
    DbusMsgUnref(Resp);
  end;
end;

function TConexionBus.AdmiteDescriptores: Boolean;
begin
  Result := (FConn <> nil) and DbusPuedeEnviar(FConn, DBUS_TYPE_UNIX_FD);
end;

function TConexionBus.LlamarConOpciones(const ADestino, ARuta, AIface, AMetodo: string;
  const APrevios, AOpciones: array of TValorDBus; AMs: Integer;
  out ARespuesta: Pointer): Boolean;
var
  Err: TDBusError;
  Msg: Pointer;
  It, Arr, Ent, Vari: array[0..TAM_ITER - 1] of Byte;
  UD, UR, UI, UM, UK, UF: UTF8String;
  Pc: MarshaledAString;
begin
  ARespuesta := nil;
  FError := '';
  Result := False;
  if FConn = nil then
  begin
    FError := MsgText(SF_NODE_NO_HAY_CONEXION_BUS);
    Exit;
  end;
  UD := UTF8String(ADestino); UR := UTF8String(ARuta);
  UI := UTF8String(AIface);   UM := UTF8String(AMetodo);
  Msg := DbusMsgNew(MarshaledAString(PAnsiChar(UD)), MarshaledAString(PAnsiChar(UR)),
    MarshaledAString(PAnsiChar(UI)), MarshaledAString(PAnsiChar(UM)));
  if Msg = nil then
  begin
    FError := MsgText(SF_NODE_NO_CONSTRUIR_MENSAJE);
    Exit;
  end;
  try
    FillChar(It, SizeOf(It), 0);
    DbusIterInitAppend(Msg, @It);
    for var P in APrevios do
      if not AnadeBasico(@It, P) then
      begin
        FError := MsgText(SF_NODE_NO_ANADIR_ARGUMENTO);
        Exit;
      end;
    FillChar(Arr, SizeOf(Arr), 0);
    UF := UTF8String('{sv}');
    if not DbusIterAbrir(@It, DBUS_TYPE_ARRAY, MarshaledAString(PAnsiChar(UF)), @Arr) then
    begin
      FError := MsgText(SF_NODE_NO_ABRIR_DICCIONARIO);
      Exit;
    end;
    for var O in AOpciones do
    begin
      FillChar(Ent, SizeOf(Ent), 0);
      DbusIterAbrir(@Arr, DBUS_TYPE_DICT_ENTRY, nil, @Ent);
      UK := UTF8String(O.Clave);
      Pc := MarshaledAString(PAnsiChar(UK));
      DbusIterAppend(@Ent, DBUS_TYPE_STRING, @Pc);
      FillChar(Vari, SizeOf(Vari), 0);
      UF := UTF8String(O.Tipo);
      DbusIterAbrir(@Ent, DBUS_TYPE_VARIANT, MarshaledAString(PAnsiChar(UF)), @Vari);
      AnadeBasico(@Vari, O);
      DbusIterCerrar(@Ent, @Vari);
      DbusIterCerrar(@Arr, @Ent);
    end;
    DbusIterCerrar(@It, @Arr);
    FillChar(Err, SizeOf(Err), 0);
    DbusErrorInit(@Err);
    try
      ARespuesta := DbusEnviarYEsperar(FConn, Msg, AMs, @Err);
      if DbusErrorIsSet(@Err) then
      begin
        FError := Format('%s: %s', [Texto(Err.Nombre), Texto(Err.Mensaje)]);
        ARespuesta := nil;
        Exit;
      end;
      Result := ARespuesta <> nil;
      if not Result then
        FError := MsgText(SF_NODE_SIN_RESPUESTA);
    finally
      DbusErrorFree(@Err);
    end;
  finally
    DbusMsgUnref(Msg);
  end;
end;

{ Las respuestas del portal llegan como SENAL Response sobre el objeto de
  peticion: hay que pedir al bus que las entregue ANTES de llamar, o se
  pierden. Una vez por conexion. }
function TConexionBus.Suscribir: Boolean;
var
  Err: TDBusError;
  U: UTF8String;
begin
  if FSuscrito then
    Exit(True);
  Result := False;
  FillChar(Err, SizeOf(Err), 0);
  DbusErrorInit(@Err);
  try
    U := UTF8String('type=''signal'',interface=''org.freedesktop.portal.Request''');
    DbusAnadirFiltro(FConn, MarshaledAString(PAnsiChar(U)), @Err);
    if DbusErrorIsSet(@Err) then
    begin
      FError := MsgFmt(SF_NODE_NO_SUSCRIBIRME_RESPUESTA_FMT, [Texto(Err.Mensaje)]);
      Exit;
    end;
  finally
    DbusErrorFree(@Err);
  end;
  FSuscrito := True;
  Result := True;
end;

{ La senal Response de APeticion, hasta AMs: su codigo (0 bien, 1 el usuario
  lo cancelo, 2 otra cosa) y sus resultados como clave=valor (los de tipo
  cadena, ruta de objeto y entero sin signo). False si no llego. Lo que llega
  de otras peticiones se tira, como hacia la captura. }
function TConexionBus.EsperarRespuesta(const APeticion: string; AMs: Integer;
  out ACodigo: Cardinal; AResultados: TStringList): Boolean;
var
  Msg: Pointer;
  Reloj: TStopwatch;
  It, Arr, Ent, Vari: array[0..TAM_ITER - 1] of Byte;
  Clave: string;
  Pc: MarshaledAString;
  Num: Cardinal;
begin
  ACodigo := 2;
  AResultados.Clear;
  Result := False;
  Reloj := TStopwatch.StartNew;
  while Reloj.ElapsedMilliseconds < AMs do
  begin
    DbusLeerEscribir(FConn, 200);
    Msg := DbusSacarMensaje(FConn);
    if Msg = nil then
      Continue;
    try
      if (Texto(DbusMsgRuta(Msg)) <> APeticion) or
         (Texto(DbusMsgMiembro(Msg)) <> 'Response') then
        Continue;
      Result := True;
      FillChar(It, SizeOf(It), 0);
      if not DbusIterInit(Msg, @It) then
        Exit;
      if DbusIterTipo(@It) = DBUS_TYPE_UINT32 then
        DbusIterLeer(@It, @ACodigo);
      DbusIterSiguiente(@It);
      if DbusIterTipo(@It) <> DBUS_TYPE_ARRAY then
        Exit;
      FillChar(Arr, SizeOf(Arr), 0);
      DbusIterEntrar(@It, @Arr);
      while DbusIterTipo(@Arr) = DBUS_TYPE_DICT_ENTRY do
      begin
        FillChar(Ent, SizeOf(Ent), 0);
        DbusIterEntrar(@Arr, @Ent);
        Pc := nil;
        DbusIterLeer(@Ent, @Pc);
        Clave := Texto(Pc);
        DbusIterSiguiente(@Ent);
        if DbusIterTipo(@Ent) = DBUS_TYPE_VARIANT then
        begin
          FillChar(Vari, SizeOf(Vari), 0);
          DbusIterEntrar(@Ent, @Vari);
          case DbusIterTipo(@Vari) of
            DBUS_TYPE_STRING, DBUS_TYPE_OBJECT_PATH:
              begin
                Pc := nil;
                DbusIterLeer(@Vari, @Pc);
                AResultados.Values[Clave] := Texto(Pc);
              end;
            DBUS_TYPE_UINT32:
              begin
                Num := 0;
                DbusIterLeer(@Vari, @Num);
                AResultados.Values[Clave] := UIntToStr(Num);
              end;
          end;
        end;
        DbusIterSiguiente(@Arr);
      end;
      Exit;
    finally
      DbusMsgUnref(Msg);
    end;
  end;
end;

{ Una peticion al portal de escritorio y su respuesta, con los resultados en
  AResultados. False si no se pudo pedir, si el portal la nego (ANegadoFmt,
  con su codigo) o si se quedo callado AMs (ACalladoFmt, con AMs); el motivo,
  en Error. }
function TConexionBus.PedirAlPortal(const AIface, AMetodo: string;
  const APrevios, AOpciones: array of TValorDBus; AMs: Integer;
  const ANegadoFmt, ACalladoFmt: string; AResultados: TStringList): Boolean;
var
  Resp: Pointer;
  Peticion: string;
  Codigo: Cardinal;
begin
  Result := False;
  if FConn = nil then
  begin
    FError := MsgText(SF_NODE_NO_HAY_CONEXION_BUS);
    Exit;
  end;
  if not Suscribir then
    Exit;
  if not LlamarConOpciones(PORTAL, RUTA_PORTAL, AIface, AMetodo, APrevios, AOpciones,
    MS_LLAMADA, Resp) then
  begin
    // que paso del portal fallo: sin el nombre, tres pasos daban el mismo error
    FError := MsgFmt(SF_NODE_PASO_DEL_PORTAL_FMT, [AMetodo, FError]);
    Exit;
  end;
  try
    if not PrimeraCadena(Resp, Peticion) then
    begin
      FError := MsgText(SF_NODE_PORTAL_SIN_OBJETO_PETICION);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not EsperarRespuesta(Peticion, AMs, Codigo, AResultados) then
  begin
    FError := MsgFmt(SF_NODE_PASO_DEL_PORTAL_FMT, [AMetodo, MsgFmt(ACalladoFmt, [AMs])]);
    Exit;
  end;
  if Codigo <> 0 then
  begin
    FError := MsgFmt(SF_NODE_PASO_DEL_PORTAL_FMT, [AMetodo, MsgFmt(ANegadoFmt, [Codigo])]);
    Exit;
  end;
  Result := True;
end;

{ Las manos por el portal estandar: CreateSession -> SelectDevices (teclado y
  puntero, el permiso persistente y el token de la ultima vez) -> Start, que
  la primera vez saca el dialogo de permiso, y su token nuevo se guarda.
  Medido en el Fedora 44 con Plasma 6.8 (4-nov-2026): RemoteDesktop v2, un
  dialogo con "no volver a preguntar", y con el token la segunda sesion no
  pregunta. }
function TConexionBus.PrepararCanalPortal(out ASesion: string): Boolean;
var
  Res: TStringList;
  Opciones: TArray<TValorDBus>;
  Token: string;
begin
  ASesion := '';
  Result := False;
  Res := TStringList.Create;
  try
    // session_handle_token es obligatorio: sin el, xdg-desktop-portal 1.22.1 no
    // contesta un error, ABORTA (assertion session->token != NULL; medido en el
    // Fedora 44 el 5-nov-2026, dos volcados). Basta uno fijo: la ruta de la sesion
    // lleva ademas el nombre unico de esta conexion
    if not PedirAlPortal(PORTAL_RD, 'CreateSession', [],
      [TValorDBus.Cadena('session_handle_token', 'mcpnode')], MS_RESPUESTA_MANOS,
      SF_NODE_PORTAL_MANOS_NEGO_FMT, SF_NODE_PORTAL_MANOS_CALLADO_FMT, Res) then
      Exit;
    ASesion := Res.Values['session_handle'];
    if ASesion = '' then
    begin
      FError := MsgText(SF_NODE_CREATESESSION_NO_DEVOLVIO_RUTA);
      Exit;
    end;
    Opciones := [TValorDBus.Entero('types', TECLADO_Y_PUNTERO),
      TValorDBus.Entero('persist_mode', PERSISTIR_HASTA_REVOCAR)];
    Token := TokenDeLasManos;
    if Token <> '' then
      Opciones := Opciones + [TValorDBus.Cadena('restore_token', Token)];
    if not PedirAlPortal(PORTAL_RD, 'SelectDevices', [TValorDBus.Ruta(ASesion)], Opciones,
      MS_RESPUESTA_MANOS, SF_NODE_PORTAL_MANOS_NEGO_FMT, SF_NODE_PORTAL_MANOS_CALLADO_FMT, Res) then
      Exit;
    if not PedirAlPortal(PORTAL_RD, 'Start', [TValorDBus.Ruta(ASesion), TValorDBus.Cadena('', '')], [],
      MS_RESPUESTA_MANOS, SF_NODE_PORTAL_MANOS_NEGO_FMT, SF_NODE_PORTAL_MANOS_CALLADO_FMT, Res) then
      Exit;
    GuardaTokenDeLasManos(Res.Values['restore_token']);
    Result := True;
  finally
    Res.Free;
    if not Result and (ASesion <> '') then
    begin
      // cerrar la sesion es otra llamada, que deja Error vacio: el motivo es el de antes
      var Motivo := FError;
      CerrarSesion(ASesion);
      FError := Motivo;
    end;
  end;
end;

function TConexionBus.PrepararCanal(out ARutaRd, ARutaSc, AStream: string): Boolean;
const
  RD = MUTTER_RD;
  SC = 'org.gnome.Mutter.ScreenCast';
var
  Resp: Pointer;
  Id: string;
  Servicios: TArray<string>;
begin
  ARutaRd := '';
  ARutaSc := '';
  AStream := '';
  Result := False;
  // ELIGE EL BUS (David, 5-nov-2026): la API de Mutter donde el escritorio la
  // ofrece (GNOME: medido, sin dialogo); donde no (Plasma), el portal. Si no
  // se puede listar el bus, Mutter, como siempre.
  FPorPortal := ListarServicios(Servicios) and not MatchStr(MUTTER_RD, Servicios);
  if FPorPortal then
    Exit(PrepararCanalPortal(ARutaRd));
  if not Llamar(RD, '/org/gnome/Mutter/RemoteDesktop', RD, 'CreateSession', [], Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, ARutaRd) then
    begin
      FError := MsgText(SF_NODE_CREATESESSION_NO_DEVOLVIO_RUTA);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not Llamar(RD, ARutaRd, 'org.freedesktop.DBus.Properties', 'Get',
    [RD + '.Session', 'SessionId'], Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, Id) then
    begin
      FError := MsgText(SF_NODE_NO_LEER_SESSIONID);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not LlamarConOpciones(SC, '/org/gnome/Mutter/ScreenCast', SC, 'CreateSession',
    [], [TValorDBus.Cadena('remote-desktop-session-id', Id)], MS_LLAMADA, Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, ARutaSc) then
    begin
      FError := MsgText(SF_NODE_SCREENCAST_NO_DEVOLVIO_RUTA);
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not LlamarConOpciones(SC, ARutaSc, SC + '.Session', 'RecordMonitor',
    [TValorDBus.Cadena('', '')], [], MS_LLAMADA, Resp) then
    Exit;
  try
    PrimeraCadena(Resp, AStream);
  finally
    DbusMsgUnref(Resp);
  end;
  Result := True;
end;

procedure TConexionBus.CerrarSesion(const ARuta: string);
var
  Resp: Pointer;
begin
  if ARuta = '' then
    Exit;
  if FPorPortal then
  begin
    if Llamar(PORTAL, ARuta, 'org.freedesktop.portal.Session', 'Close', [], Resp) then
      DbusMsgUnref(Resp);
  end
  else if Llamar(MUTTER_RD, ARuta, MUTTER_RD + '.Session', 'Stop', [], Resp) then
    DbusMsgUnref(Resp);
end;

function TConexionBus.AbrirCanal(const ARuta: string; out ADescriptor: Integer): Boolean;
const
  RD = MUTTER_RD;
  TODOS_LOS_DISPOSITIVOS = 7;
var
  Resp: Pointer;
  It: array[0..TAM_ITER - 1] of Byte;
begin
  ADescriptor := -1;
  Result := False;
  if FPorPortal then
  begin
    // la sesion ya se arranco (Start, en PrepararCanalPortal): el socket de EIS
    if not LlamarConOpciones(PORTAL, RUTA_PORTAL, PORTAL_RD, 'ConnectToEIS',
      [TValorDBus.Ruta(ARuta)], [], MS_LLAMADA, Resp) then
      Exit;
  end
  else
  begin
    if not Llamar(RD, ARuta, RD + '.Session', 'Start', [], Resp) then
      Exit;
    DbusMsgUnref(Resp);
    if not LlamarConOpciones(RD, ARuta, RD + '.Session', 'ConnectToEIS',
      [], [TValorDBus.Entero('device-types', TODOS_LOS_DISPOSITIVOS)], MS_LLAMADA, Resp) then
      Exit;
  end;
  try
    FillChar(It, SizeOf(It), 0);
    if not DbusIterInit(Resp, @It) then
    begin
      FError := MsgText(SF_NODE_CONNECTTOEIS_NO_DEVOLVIO_NADA);
      Exit;
    end;
    if DbusIterTipo(@It) <> DBUS_TYPE_UNIX_FD then
    begin
      FError := MsgFmt(SF_NODE_CONNECTTOEIS_DEVOLVIO_TIPO_FMT,
        [DbusIterTipo(@It)]);
      Exit;
    end;
    DbusIterLeer(@It, @ADescriptor);
    Result := ADescriptor >= 0;
    if not Result then
      FError := MsgText(SF_NODE_DESCRIPTOR_NO_VALIDO);
  finally
    DbusMsgUnref(Resp);
  end;
end;

function TConexionBus.CapturarEscritorio(out AFichero: string; AMs: Integer): Boolean;
var
  Res: TStringList;
  Uri: string;
begin
  AFichero := '';
  Result := False;
  FError := '';
  { Opciones vacias: 'interactive' vale falso por defecto, que es lo que
    queremos - nadie va a pulsar nada. Un silencio del portal NO es un fallo
    del nodo: medido en Zorin 18 el 19-sep, el journal decia "Failed to show
    access dialog: timeout". El portal quiso pedir permiso, no pudo pintar su
    dialogo -sesion remota, pantalla bloqueada- y no devolvio ni respuesta ni
    error. Quien lee esto es un agente que no ve esa pantalla: hay que
    decirle QUE PEDIR (SF_NODE_PORTAL_QUEDO_CALLADO_FMT), porque reintentar
    no arregla nada. }
  Res := TStringList.Create;
  try
    if not PedirAlPortal('org.freedesktop.portal.Screenshot', 'Screenshot',
      [TValorDBus.Cadena('', '')], [], AMs, SF_NODE_PORTAL_RECHAZO_CAPTURA_FMT,
      SF_NODE_PORTAL_QUEDO_CALLADO_FMT, Res) then
      Exit;
    Uri := Res.Values['uri'];
  finally
    Res.Free;
  end;
  if Uri = '' then
  begin
    FError := MsgText(SF_NODE_RESPUESTA_SIN_DIRECCION);
    Exit;
  end;
  AFichero := DesdeUri(Uri);
  Result := AFichero <> '';
  if not Result then
    FError := MsgFmt(SF_NODE_NO_ENTIENDO_DIRECCION_FMT, [Uri]);
end;

function DesdeUri(const AUri: string): string;
var
  I, N: Integer;
  S: string;
  B: TBytes;
begin
  { OJO: el porcentaje codifica BYTES, no caracteres. Decodificarlo a
    caracteres uno a uno rompe cualquier acento -en UTF-8 ocupa dos bytes- y
    deja una ruta que NO existe. Medido 18-sep: con /home/.../Imagenes,
    TFile.GetSize devolvia -1 y TFile.Copy fallaba. Hay que juntar los BYTES
    y despues interpretarlos como UTF-8. }
  Result := '';
  if not AUri.StartsWith('file://') then
    Exit;
  S := Copy(AUri, 8, MaxInt);
  SetLength(B, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      B[N] := Byte(StrToIntDef('$' + Copy(S, I + 1, 2), 32));
      Inc(I, 3);
    end
    else
    begin
      B[N] := Byte(Ord(S[I]));
      Inc(I);
    end;
    Inc(N);
  end;
  SetLength(B, N);
  Result := TEncoding.UTF8.GetString(B);
end;

end.
