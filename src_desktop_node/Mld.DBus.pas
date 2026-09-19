unit Mld.DBus;

{ Conversacion con el bus de sesion de D-Bus, por carga dinamica de
  libdbus-1.so.3 (ver [Mld.Dyn]). Es el canal por el que el nodo pedira al
  escritorio lo que necesita: nada se enlaza en compilacion.

  El bus de sesion se localiza solo a traves de DBUS_SESSION_BUS_ADDRESS, que
  PAServer ya hereda de la sesion grafica - medido 18-sep. }

interface

uses
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

  TConexionBus = class
  private
    FLib: TLibreria;
    FConn: Pointer;
    FError: string;
    function Resolver: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Abre libdbus y se engancha al bus de sesion. False deja el motivo
      en Error. }
    function Conectar: Boolean;
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
    function ProbarSesion(out ARuta, AId: string): Boolean;
    function AdmiteDescriptores: Boolean;
    function LlamarOpciones(const ADestino, ARuta, AIface, AMetodo: string;
      AUsaCadena: Boolean; const ACadena, AClave, AValorTexto: string;
      AValorNum: Cardinal; ATipoValor: Char; out ARespuesta: Pointer): Boolean;
    function PrepararCanal(out ARutaRd, ARutaSc, AStream: string): Boolean;
    procedure CerrarSesion(const ARuta: string);
    function AbrirCanal(const ARuta: string; out ADescriptor: Integer): Boolean;
    { La pantalla ENTERA, dialogos de Wayland incluidos: lo que X11 no puede
      dar en Xwayland rootless. Deja en AFichero la ruta del PNG que escribe
      el escritorio. }
    function CapturarEscritorio(out AFichero: string; AMs: Integer): Boolean;
  end;

implementation

uses
  System.SysUtils, System.Diagnostics;

{ Declarada aqui porque CapturarEscritorio la usa antes de su sitio. }
function DesdeUri(const AUri: string): string; forward;

const
  { dbus-shared.h: el enumerado empieza en SESSION. Poner 1 aqui conecta al
    bus del SISTEMA y todo parece funcionar - medido 18-sep. }
  DBUS_BUS_SESSION = 0;
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
    Result := FLib.Simbolo(ASimbolo, ADir);
    if not Result then
      FError := Format('falta %s en %s (%s)', [ASimbolo, FLib.Nombre, FLib.Error]);
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

function TConexionBus.Conectar: Boolean;
var
  Err: TDBusError;
begin
  FError := '';
  if not FLib.Abierta then
    if not FLib.Abrir('libdbus-1.so.3') then
    begin
      FError := 'no hay libdbus en esta maquina: ' + FLib.Error;
      Exit(False);
    end;
  if not Resolver then
    Exit(False);

  FillChar(Err, SizeOf(Err), 0);
  DbusErrorInit(@Err);
  try
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
    FError := 'el bus no devolvio conexion (sin DBUS_SESSION_BUS_ADDRESS?)';
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
  Err: TDBusError;
  Msg, Resp: Pointer;
  Iter, Sub: array[0..TAM_ITER - 1] of Byte;
  Cadena: MarshaledAString;
  Acc: TArray<string>;
begin
  ALista := nil;
  FError := '';
  Result := False;
  if FConn = nil then
  begin
    FError := 'no hay conexion con el bus';
    Exit;
  end;
  Msg := DbusMsgNew('org.freedesktop.DBus', '/org/freedesktop/DBus',
    'org.freedesktop.DBus', 'ListNames');
  if Msg = nil then
  begin
    FError := 'no se pudo construir el mensaje';
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
      FError := 'el bus no respondio';
      Exit;
    end;
    try
      FillChar(Iter, SizeOf(Iter), 0);
      FillChar(Sub, SizeOf(Sub), 0);
      if not DbusIterInit(Resp, @Iter) then
      begin
        FError := 'respuesta sin argumentos';
        Exit;
      end;
      if DbusIterTipo(@Iter) <> DBUS_TYPE_ARRAY then
      begin
        FError := 'se esperaba un array de cadenas';
        Exit;
      end;
      DbusIterEntrar(@Iter, @Sub);
      while DbusIterTipo(@Sub) = DBUS_TYPE_STRING do
      begin
        Cadena := nil;
        DbusIterLeer(@Sub, @Cadena);
        Acc := Acc + [Texto(Cadena)];
        DbusIterSiguiente(@Sub);
      end;
      ALista := Acc;
      Result := True;
    finally
      DbusMsgUnref(Resp);
    end;
  finally
    DbusErrorFree(@Err);
    DbusMsgUnref(Msg);
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
    FError := 'no hay conexion con el bus';
    Exit;
  end;
  Msg := DbusMsgNew('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig',
    'org.gnome.Mutter.DisplayConfig', 'GetCurrentState');
  if Msg = nil then
  begin
    FError := 'no se pudo construir el mensaje';
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
      FError := 'el escritorio no respondio';
      Exit;
    end;
    try
      FillChar(It, SizeOf(It), 0);
      if not DbusIterInit(Resp, @It) then
      begin
        FError := 'respuesta sin argumentos';
        Exit;
      end;
      DbusIterSiguiente(@It);
      DbusIterSiguiente(@It);
      if DbusIterTipo(@It) <> DBUS_TYPE_ARRAY then
      begin
        FError := 'el tercer argumento no es el array de monitores logicos';
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
    FError := 'no hay conexion con el bus';
    Exit;
  end;
  UD := UTF8String(ADestino); UR := UTF8String(ARuta);
  UI := UTF8String(AIface);  UM := UTF8String(AMetodo);
  Msg := DbusMsgNew(MarshaledAString(PAnsiChar(UD)), MarshaledAString(PAnsiChar(UR)),
    MarshaledAString(PAnsiChar(UI)), MarshaledAString(PAnsiChar(UM)));
  if Msg = nil then
  begin
    FError := 'no se pudo construir el mensaje';
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
          FError := 'no se pudo anadir un argumento';
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
        FError := 'sin respuesta';
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
  RD = 'org.gnome.Mutter.RemoteDesktop';
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
      FError := 'CreateSession no devolvio ruta de sesion';
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

function TConexionBus.AdmiteDescriptores: Boolean;
begin
  Result := (FConn <> nil) and DbusPuedeEnviar(FConn, DBUS_TYPE_UNIX_FD);
end;

function TConexionBus.LlamarOpciones(const ADestino, ARuta, AIface, AMetodo: string;
  AUsaCadena: Boolean; const ACadena, AClave, AValorTexto: string;
  AValorNum: Cardinal; ATipoValor: Char; out ARespuesta: Pointer): Boolean;
var
  Err: TDBusError;
  Msg: Pointer;
  It, Arr, Ent, Vari: array[0..TAM_ITER - 1] of Byte;
  UD, UR, UI, UM, UC, UK, UV, UF: UTF8String;
  Pc: MarshaledAString;
  Num: Cardinal;
begin
  ARespuesta := nil;
  FError := '';
  Result := False;
  if FConn = nil then
  begin
    FError := 'no hay conexion con el bus';
    Exit;
  end;
  UD := UTF8String(ADestino); UR := UTF8String(ARuta);
  UI := UTF8String(AIface);   UM := UTF8String(AMetodo);
  Msg := DbusMsgNew(MarshaledAString(PAnsiChar(UD)), MarshaledAString(PAnsiChar(UR)),
    MarshaledAString(PAnsiChar(UI)), MarshaledAString(PAnsiChar(UM)));
  if Msg = nil then
  begin
    FError := 'no se pudo construir el mensaje';
    Exit;
  end;
  try
    FillChar(It, SizeOf(It), 0);
    DbusIterInitAppend(Msg, @It);
    if AUsaCadena then
    begin
      UC := UTF8String(ACadena);
      Pc := MarshaledAString(PAnsiChar(UC));
      if UC = '' then
        Pc := MarshaledAString(PAnsiChar(UTF8String(#0)));
      DbusIterAppend(@It, DBUS_TYPE_STRING, @Pc);
    end;
    FillChar(Arr, SizeOf(Arr), 0);
    UF := UTF8String('{sv}');
    if not DbusIterAbrir(@It, DBUS_TYPE_ARRAY, MarshaledAString(PAnsiChar(UF)), @Arr) then
    begin
      FError := 'no pude abrir el diccionario';
      Exit;
    end;
    if ATipoValor <> #0 then
    begin
      FillChar(Ent, SizeOf(Ent), 0);
      DbusIterAbrir(@Arr, DBUS_TYPE_DICT_ENTRY, nil, @Ent);
      UK := UTF8String(AClave);
      Pc := MarshaledAString(PAnsiChar(UK));
      DbusIterAppend(@Ent, DBUS_TYPE_STRING, @Pc);
      FillChar(Vari, SizeOf(Vari), 0);
      if ATipoValor = 'u' then
      begin
        UF := UTF8String('u');
        DbusIterAbrir(@Ent, DBUS_TYPE_VARIANT, MarshaledAString(PAnsiChar(UF)), @Vari);
        Num := AValorNum;
        DbusIterAppend(@Vari, DBUS_TYPE_UINT32, @Num);
      end
      else
      begin
        UF := UTF8String('s');
        DbusIterAbrir(@Ent, DBUS_TYPE_VARIANT, MarshaledAString(PAnsiChar(UF)), @Vari);
        UV := UTF8String(AValorTexto);
        Pc := MarshaledAString(PAnsiChar(UV));
        DbusIterAppend(@Vari, DBUS_TYPE_STRING, @Pc);
      end;
      DbusIterCerrar(@Ent, @Vari);
      DbusIterCerrar(@Arr, @Ent);
    end;
    DbusIterCerrar(@It, @Arr);
    FillChar(Err, SizeOf(Err), 0);
    DbusErrorInit(@Err);
    try
      ARespuesta := DbusEnviarYEsperar(FConn, Msg, 60000, @Err);
      if DbusErrorIsSet(@Err) then
      begin
        FError := Format('%s: %s', [Texto(Err.Nombre), Texto(Err.Mensaje)]);
        ARespuesta := nil;
        Exit;
      end;
      Result := ARespuesta <> nil;
      if not Result then
        FError := 'sin respuesta';
    finally
      DbusErrorFree(@Err);
    end;
  finally
    DbusMsgUnref(Msg);
  end;
end;

function TConexionBus.PrepararCanal(out ARutaRd, ARutaSc, AStream: string): Boolean;
const
  RD = 'org.gnome.Mutter.RemoteDesktop';
  SC = 'org.gnome.Mutter.ScreenCast';
var
  Resp: Pointer;
  Id: string;
begin
  ARutaRd := '';
  ARutaSc := '';
  AStream := '';
  Result := False;
  if not Llamar(RD, '/org/gnome/Mutter/RemoteDesktop', RD, 'CreateSession', [], Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, ARutaRd) then
    begin
      FError := 'CreateSession no devolvio ruta';
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
      FError := 'no pude leer SessionId';
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not LlamarOpciones(SC, '/org/gnome/Mutter/ScreenCast', SC, 'CreateSession',
    False, '', 'remote-desktop-session-id', Id, 0, 's', Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, ARutaSc) then
    begin
      FError := 'ScreenCast.CreateSession no devolvio ruta';
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  if not LlamarOpciones(SC, ARutaSc, SC + '.Session', 'RecordMonitor',
    True, '', '', '', 0, #0, Resp) then
    Exit;
  try
    PrimeraCadena(Resp, AStream);
  finally
    DbusMsgUnref(Resp);
  end;
  Result := True;
end;

procedure TConexionBus.CerrarSesion(const ARuta: string);
const
  RD = 'org.gnome.Mutter.RemoteDesktop';
var
  Resp: Pointer;
begin
  if ARuta = '' then
    Exit;
  if Llamar(RD, ARuta, RD + '.Session', 'Stop', [], Resp) then
    DbusMsgUnref(Resp);
end;

function TConexionBus.AbrirCanal(const ARuta: string; out ADescriptor: Integer): Boolean;
const
  RD = 'org.gnome.Mutter.RemoteDesktop';
  TODOS_LOS_DISPOSITIVOS = 7;
var
  Resp: Pointer;
  It: array[0..TAM_ITER - 1] of Byte;
begin
  ADescriptor := -1;
  Result := False;
  if not Llamar(RD, ARuta, RD + '.Session', 'Start', [], Resp) then
    Exit;
  DbusMsgUnref(Resp);
  if not LlamarOpciones(RD, ARuta, RD + '.Session', 'ConnectToEIS',
    False, '', 'device-types', '', TODOS_LOS_DISPOSITIVOS, 'u', Resp) then
    Exit;
  try
    FillChar(It, SizeOf(It), 0);
    if not DbusIterInit(Resp, @It) then
    begin
      FError := 'ConnectToEIS no devolvio nada';
      Exit;
    end;
    if DbusIterTipo(@It) <> DBUS_TYPE_UNIX_FD then
    begin
      FError := Format('ConnectToEIS devolvio tipo %d, se esperaba un descriptor',
        [DbusIterTipo(@It)]);
      Exit;
    end;
    DbusIterLeer(@It, @ADescriptor);
    Result := ADescriptor >= 0;
    if not Result then
      FError := 'el descriptor recibido no es valido';
  finally
    DbusMsgUnref(Resp);
  end;
end;

function TConexionBus.CapturarEscritorio(out AFichero: string; AMs: Integer): Boolean;
const
  PORTAL = 'org.freedesktop.portal.Desktop';
var
  Resp, Msg: Pointer;
  Peticion: string;
  U: UTF8String;
  Err: TDBusError;
  Reloj: TStopwatch;
  It, Arr, Ent, Vari: array[0..TAM_ITER - 1] of Byte;
  Clave, Uri: string;
  Pc: MarshaledAString;
  Codigo: Cardinal;
begin
  AFichero := '';
  Result := False;
  FError := '';
  if FConn = nil then
  begin
    FError := 'no hay conexion con el bus';
    Exit;
  end;
  { La respuesta llega como SEÑAL sobre el objeto de peticion: hay que pedir
    que el bus nos la entregue ANTES de llamar, o se pierde. }
  FillChar(Err, SizeOf(Err), 0);
  DbusErrorInit(@Err);
  U := UTF8String('type=''signal'',interface=''org.freedesktop.portal.Request''');
  DbusAnadirFiltro(FConn, MarshaledAString(PAnsiChar(U)), @Err);
  if DbusErrorIsSet(@Err) then
  begin
    FError := 'no pude suscribirme a la respuesta: ' + Texto(Err.Mensaje);
    DbusErrorFree(@Err);
    Exit;
  end;
  DbusErrorFree(@Err);
  { opciones vacias: 'interactive' vale falso por defecto, que es lo que
    queremos - nadie va a pulsar nada. }
  if not LlamarOpciones(PORTAL, '/org/freedesktop/portal/desktop',
    'org.freedesktop.portal.Screenshot', 'Screenshot',
    True, '', '', '', 0, #0, Resp) then
    Exit;
  try
    if not PrimeraCadena(Resp, Peticion) then
    begin
      FError := 'el portal no devolvio objeto de peticion';
      Exit;
    end;
  finally
    DbusMsgUnref(Resp);
  end;
  Reloj := TStopwatch.StartNew;
  while Reloj.ElapsedMilliseconds < AMs do
  begin
    DbusLeerEscribir(FConn, 200);
    Msg := DbusSacarMensaje(FConn);
    if Msg = nil then
      Continue;
    try
      if (Texto(DbusMsgRuta(Msg)) <> Peticion) or
         (Texto(DbusMsgMiembro(Msg)) <> 'Response') then
        Continue;
      FillChar(It, SizeOf(It), 0);
      if not DbusIterInit(Msg, @It) then
        Continue;
      Codigo := 1;
      if DbusIterTipo(@It) = DBUS_TYPE_UINT32 then
        DbusIterLeer(@It, @Codigo);
      if Codigo <> 0 then
      begin
        FError := Format('el portal rechazo la captura (codigo %d)', [Codigo]);
        Exit;
      end;
      DbusIterSiguiente(@It);
      if DbusIterTipo(@It) <> DBUS_TYPE_ARRAY then
      begin
        FError := 'la respuesta no trae resultados';
        Exit;
      end;
      FillChar(Arr, SizeOf(Arr), 0);
      DbusIterEntrar(@It, @Arr);
      Uri := '';
      while DbusIterTipo(@Arr) = DBUS_TYPE_DICT_ENTRY do
      begin
        FillChar(Ent, SizeOf(Ent), 0);
        DbusIterEntrar(@Arr, @Ent);
        Pc := nil;
        DbusIterLeer(@Ent, @Pc);
        Clave := Texto(Pc);
        DbusIterSiguiente(@Ent);
        if (Clave = 'uri') and (DbusIterTipo(@Ent) = DBUS_TYPE_VARIANT) then
        begin
          FillChar(Vari, SizeOf(Vari), 0);
          DbusIterEntrar(@Ent, @Vari);
          if DbusIterTipo(@Vari) = DBUS_TYPE_STRING then
          begin
            Pc := nil;
            DbusIterLeer(@Vari, @Pc);
            Uri := Texto(Pc);
          end;
        end;
        DbusIterSiguiente(@Arr);
      end;
      if Uri = '' then
      begin
        FError := 'la respuesta no trae la direccion del fichero';
        Exit;
      end;
      AFichero := DesdeUri(Uri);
      Result := AFichero <> '';
      if not Result then
        FError := 'no entiendo la direccion ' + Uri;
      Exit;
    finally
      DbusMsgUnref(Msg);
    end;
  end;
  { Un silencio del portal NO es un fallo del nodo: medido en Zorin 18 el
    19-sep, el journal decia "Failed to show access dialog: timeout". El
    portal quiso pedir permiso, no pudo pintar su dialogo -sesion remota,
    pantalla bloqueada- y no devolvio ni respuesta ni error. Quien lee esto
    es un agente que no ve esa pantalla: hay que decirle QUE PEDIR, porque
    reintentar no arregla nada. }
  FError := Format('el portal se quedo callado %d ms: ni respuesta ni error. ' + 'Lo normal es que no llegara a mostrar el dialogo del permiso de ' + 'captura (pasa en sesion remota o con la pantalla bloqueada). Pide al ' + 'operador que conceda UNA vez la captura de pantalla en esa maquina, ' + 'con la pantalla delante; despues esto funciona en silencio', [AMs]);
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
