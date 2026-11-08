unit Mld.Eis;

{ Las MANOS: el canal de entrada del escritorio (libei), alimentado con el
  descriptor que entrega ConnectToEIS (ver [Mld.DBus]).

  Trampas medidas el 12 y el 18-sep, incrustadas aqui para no repetirlas:
   - El boton izquierdo es BTN_LEFT = 272 (codigo de Linux), NO el 1 de X11.
   - Las teclas van en codigos evdev, NO keycodes X11: Enter es 28, no 36.
   - Las coordenadas son las LOGICAS del escritorio (la region que anuncia
     EIS), que en una pantalla al 125% NO coinciden con las de X11.
   - Nada llega hasta que el dispositivo avisa de que esta listo. }

interface

uses
  Mld.Dyn,
  Mld.Teclado;

type
  TRegion = record
    X, Y, Ancho, Alto: Cardinal;
  end;

  TManos = class
  private
    FLib: TLibreria;
    FEi: Pointer;
    FAsiento: Pointer;
    FPuntero: Pointer;
    FTeclado: Pointer;
    FBoton: Pointer;
    FListo: Boolean;
    FRegion: TRegion;
    FEscala: Double;
    FSecuencia: Cardinal;
    FError: string;
    FMapa: TMapaTeclado;
    FMapaMirado: Boolean;
    FMapaNota: string;
    procedure MirarMapa;
    function Resolver: Boolean;
    procedure Atender(AEvento: Pointer; ATipo: Integer);
    { El punto de la captura en coordenadas logicas, y si cae en la pantalla
      (si no, el motivo en Error): lo miran Mover y Arrastrar. }
    function EnPantalla(AX, AY: Double; out ALx, ALy: Double): Boolean;
    { Baja o sube un boton donde este el puntero: Pulsar hace las dos,
      Arrastrar las separa. }
    procedure Boton(ABoton: Cardinal; APulsado: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    { Toma el descriptor y hace el saludo con el escritorio. Bombea eventos
      hasta AMs milisegundos esperando a que los dispositivos esten listos. }
    function Abrir(ADescriptor: Integer; const ANombre: string;
      AMs: Integer): Boolean;
    procedure Bombear;
    { Lleva el puntero a un punto MEDIDO SOBRE LA CAPTURA DEL ESCRITORIO.
      La conversion de escala la hace el nodo: quien llama no tiene por que
      saber que existen coordenadas logicas, fisicas y de X11. }
    function Mover(AX, AY: Double): Boolean;
    { Pulsa en un punto medido sobre la captura del escritorio. El boton
      izquierdo es BTN_LEFT=272, codigo de Linux: el 1 de X11 no vale. }
    function Pulsar(AX, AY: Double; ABoton: Cardinal = 272): Boolean;
    { Arrastra como una mano: pulsa en (AX1,AY1), se mueve en pasos hasta
      (AX2,AY2) y suelta alli; los dos puntos, medidos sobre la captura. La
      barra de titulo de una ventana la mueve, su borde o su esquina la
      redimensiona. El destino se mira ANTES de pulsar, y el boton se suelta
      siempre. }
    function Arrastrar(AX1, AY1, AX2, AY2: Double; ABoton: Cardinal = 272): Boolean;
    { Teclas en codigos EVDEV (Escape 1, Tab 15, Enter 28, Alt izq 56).
      Ojo: NO son los keycodes de X11, que van 8 unidades por encima. }
    function Tecla(ACodigo: Cardinal; APulsada: Boolean): Boolean;
    { Una combinacion: pulsa en orden y suelta al reves, como una persona.
      Para cambiar de ventana: Combinacion([56, 15]) = Alt+Tab. }
    function Combinacion(const ACodigos: array of Cardinal): Boolean;
    { Escribe un texto tecla a tecla. Solo letras, cifras y unos pocos signos:
      lo que hace falta para rellenar un campo. Un caracter que no sepa
      teclear lo dice, en vez de escribir algo distinto a lo pedido. }
    function Escribir(const ATexto: string): Boolean;
    { La escala del escritorio (1,25 en el equipo medido). Se la da quien
      la lee por D-Bus; con ella el nodo traduce SOLO. }
    property Escala: Double read FEscala write FEscala;
    property Listo: Boolean read FListo;
    property Region: TRegion read FRegion;
    property Error: string read FError;
    { Con que teclea: la distribucion que entrego el escritorio, o por que
      se ha quedado con la tabla fija. Para que el eco lo DIGA. }
    property MapaNota: string read FMapaNota;
    function Microsegundos: UInt64;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Posix.SysMman,
  Mld.Textos;

const
  { enum ei_device_capability }
  CAP_PUNTERO = 1;
  CAP_ABSOLUTO = 2;
  CAP_TECLADO = 4;
  CAP_BOTON = 32;
  { enum ei_event_type }
  EV_ASIENTO = 3;
  EV_DISPOSITIVO = 5;
  EV_REANUDADO = 8;
  { El protocolo con el servidor: de el, los codigos evdev de las teclas que
    las manos pulsan por su cuenta (EVDEV_MAYUS, EVDEV_ALTGR, EVDEV_INTRO) }
  {$I NodeProtocolo.inc}

type
  TEiNuevo = function(ACtx: Pointer): Pointer; cdecl;
  TEiUnref = procedure(AEi: Pointer); cdecl;
  TEiNombre = procedure(AEi: Pointer; ANombre: MarshaledAString); cdecl;
  TEiBackendFd = function(AEi: Pointer; AFd: Integer): Integer; cdecl;
  TEiDispatch = procedure(AEi: Pointer); cdecl;
  TEiGetFd = function(AEi: Pointer): Integer; cdecl;
  TEiGetEvento = function(AEi: Pointer): Pointer; cdecl;
  TEiEventoUnref = procedure(AEv: Pointer); cdecl;
  TEiEventoTipo = function(AEv: Pointer): Integer; cdecl;
  TEiEventoAsiento = function(AEv: Pointer): Pointer; cdecl;
  TEiEventoDisp = function(AEv: Pointer): Pointer; cdecl;
  TEiDispNombre = function(AD: Pointer): MarshaledAString; cdecl;
  TEiDispRegion = function(AD: Pointer; AIdx: NativeUInt): Pointer; cdecl;
  TEiRegionVal = function(AR: Pointer): Cardinal; cdecl;
  TEiDispCapacidad = function(AD: Pointer; ACap: Integer): Boolean; cdecl;
  { variadica en C; en x86-64 los seis primeros enteros van en registros,
    asi que una firma fija equivalente sirve y evita depender de varargs. }
  TEiAsientoLigar = procedure(AAs: Pointer;
    A1, A2, A3, A4, AFin: NativeInt); cdecl;
  TEiEmpezar = procedure(AD: Pointer; ASec: Cardinal); cdecl;
  TEiParar = procedure(AD: Pointer); cdecl;
  TEiMover = procedure(AD: Pointer; AX, AY: Double); cdecl;
  TEiBoton = procedure(AD: Pointer; ABoton: Cardinal; APulsado: Boolean); cdecl;
  TEiTecla = procedure(AD: Pointer; ATecla: Cardinal; APulsada: Boolean); cdecl;
  TEiCuadro = procedure(AD: Pointer; AUs: UInt64); cdecl;
  TEiMapaDe = function(AD: Pointer): Pointer; cdecl;
  TEiMapaFd = function(AM: Pointer): Integer; cdecl;
  TEiMapaTam = function(AM: Pointer): NativeUInt; cdecl;

var
  EiNuevo: TEiNuevo;
  EiUnref: TEiUnref;
  EiNombre: TEiNombre;
  EiBackendFd: TEiBackendFd;
  EiDispatch: TEiDispatch;
  EiGetFd: TEiGetFd;
  EiGetEvento: TEiGetEvento;
  EiEventoUnref: TEiEventoUnref;
  EiEventoTipo: TEiEventoTipo;
  EiEventoAsiento: TEiEventoAsiento;
  EiEventoDisp: TEiEventoDisp;
  EiDispNombre: TEiDispNombre;
  EiDispRegion: TEiDispRegion;
  EiRegionX, EiRegionY, EiRegionAncho, EiRegionAlto: TEiRegionVal;
  EiDispCapacidad: TEiDispCapacidad;
  EiAsientoLigar: TEiAsientoLigar;
  EiEmpezar: TEiEmpezar;
  EiParar: TEiParar;
  EiMover: TEiMover;
  EiBoton: TEiBoton;
  EiTecla: TEiTecla;
  EiCuadro: TEiCuadro;
  { Opcionales: si esta libei no las trae, se teclea con la tabla fija. }
  EiMapaDe: TEiMapaDe;
  EiMapaFd: TEiMapaFd;
  EiMapaTam: TEiMapaTam;

function Texto(A: MarshaledAString): string;
begin
  if A = nil then
    Result := ''
  else
    Result := string(UTF8String(A));
end;

constructor TManos.Create;
begin
  inherited Create;
  FLib := TLibreria.Create;
  FSecuencia := 1;
  FEscala := 1.0;
end;

destructor TManos.Destroy;
begin
  if (FEi <> nil) and Assigned(EiUnref) then
    EiUnref(FEi);
  FMapa.Free;
  FLib.Free;
  inherited;
end;

function TManos.Resolver: Boolean;

  function Uno(const ASimbolo: string; out ADir: Pointer): Boolean;
  begin
    Result := FLib.SimboloOMotivo(ASimbolo, ADir, FError);
  end;

begin
  Result :=
    Uno('ei_new_sender', Pointer(@EiNuevo)) and
    Uno('ei_unref', Pointer(@EiUnref)) and
    Uno('ei_configure_name', Pointer(@EiNombre)) and
    Uno('ei_setup_backend_fd', Pointer(@EiBackendFd)) and
    Uno('ei_dispatch', Pointer(@EiDispatch)) and
    Uno('ei_get_fd', Pointer(@EiGetFd)) and
    Uno('ei_get_event', Pointer(@EiGetEvento)) and
    Uno('ei_event_unref', Pointer(@EiEventoUnref)) and
    Uno('ei_event_get_type', Pointer(@EiEventoTipo)) and
    Uno('ei_event_get_seat', Pointer(@EiEventoAsiento)) and
    Uno('ei_event_get_device', Pointer(@EiEventoDisp)) and
    Uno('ei_device_get_name', Pointer(@EiDispNombre)) and
    Uno('ei_device_get_region', Pointer(@EiDispRegion)) and
    Uno('ei_region_get_x', Pointer(@EiRegionX)) and
    Uno('ei_region_get_y', Pointer(@EiRegionY)) and
    Uno('ei_region_get_width', Pointer(@EiRegionAncho)) and
    Uno('ei_region_get_height', Pointer(@EiRegionAlto)) and
    Uno('ei_device_has_capability', Pointer(@EiDispCapacidad)) and
    Uno('ei_seat_bind_capabilities', Pointer(@EiAsientoLigar)) and
    Uno('ei_device_start_emulating', Pointer(@EiEmpezar)) and
    Uno('ei_device_stop_emulating', Pointer(@EiParar)) and
    Uno('ei_device_pointer_motion_absolute', Pointer(@EiMover)) and
    Uno('ei_device_button_button', Pointer(@EiBoton)) and
    Uno('ei_device_keyboard_key', Pointer(@EiTecla)) and
    Uno('ei_device_frame', Pointer(@EiCuadro));
end;

procedure TManos.Atender(AEvento: Pointer; ATipo: Integer);
var
  Disp, Reg: Pointer;
  Abs_, Bot, Tec: Boolean;
begin
  case ATipo of
    EV_ASIENTO:
      begin
        FAsiento := EiEventoAsiento(AEvento);
        { Pedir las capacidades: sin esto el escritorio no crea dispositivos. }
        EiAsientoLigar(FAsiento, CAP_PUNTERO, CAP_ABSOLUTO, CAP_TECLADO,
          CAP_BOTON, 0);
      end;
    EV_DISPOSITIVO:
      begin
        Disp := EiEventoDisp(AEvento);
        Abs_ := EiDispCapacidad(Disp, CAP_ABSOLUTO);
        Bot := EiDispCapacidad(Disp, CAP_BOTON);
        Tec := EiDispCapacidad(Disp, CAP_TECLADO);
        if Abs_ and Bot and (FPuntero = nil) then
        begin
          FPuntero := Disp;
          Reg := EiDispRegion(Disp, 0);
          if Reg <> nil then
          begin
            FRegion.X := EiRegionX(Reg);
            FRegion.Y := EiRegionY(Reg);
            FRegion.Ancho := EiRegionAncho(Reg);
            FRegion.Alto := EiRegionAlto(Reg);
          end;
        end;
        if Bot and not Abs_ and (FBoton = nil) then
          FBoton := Disp;
        if Tec and (FTeclado = nil) then
          FTeclado := Disp;
      end;
    EV_REANUDADO:
      begin
        Disp := EiEventoDisp(AEvento);
        if (Disp = FPuntero) or (Disp = FTeclado) then
          FListo := (FPuntero <> nil) and (FTeclado <> nil);
      end;
  end;
end;

procedure TManos.Bombear;
var
  Ev: Pointer;
begin
  if FEi = nil then
    Exit;
  EiDispatch(FEi);
  repeat
    Ev := EiGetEvento(FEi);
    if Ev = nil then
      Break;
    try
      Atender(Ev, EiEventoTipo(Ev));
    finally
      EiEventoUnref(Ev);
    end;
  until False;
end;

function TManos.Abrir(ADescriptor: Integer; const ANombre: string;
  AMs: Integer): Boolean;
var
  Rc: Integer;
  U: UTF8String;
  Reloj: TStopwatch;
begin
  FError := '';
  Result := False;
  if ADescriptor < 0 then
  begin
    FError := MsgText(SF_NODE_DESCRIPTOR_INVALIDO);
    Exit;
  end;
  if not FLib.Abierta then
    if not FLib.Abrir('libei.so.1') then
    begin
      FError := MsgFmt(SF_NODE_NO_HAY_LIB_FMT, ['libei', FLib.Error]);
      Exit;
    end;
  if not Resolver then
    Exit;
  FEi := EiNuevo(nil);
  if FEi = nil then
  begin
    FError := MsgText(SF_NODE_NO_DEVOLVIO_CONTEXTO);
    Exit;
  end;
  U := UTF8String(ANombre);
  EiNombre(FEi, MarshaledAString(PAnsiChar(U)));
  { toma posesion del descriptor }
  Rc := EiBackendFd(FEi, ADescriptor);
  if Rc <> 0 then
  begin
    FError := MsgFmt(SF_NODE_BACKEND_FD_DEVOLVIO_FMT, [Rc]);
    Exit;
  end;
  Reloj := TStopwatch.StartNew;
  while (not FListo) and (Reloj.ElapsedMilliseconds < AMs) do
  begin
    Bombear;
    if not FListo then
      Sleep(40);
  end;
  Result := FListo;
  if not Result then
    FError := MsgFmt(SF_NODE_DISPOSITIVOS_NO_LISTOS_FMT, [AMs, BoolToStr(FPuntero <> nil, True),
      BoolToStr(FTeclado <> nil, True)]);
end;

function TManos.EnPantalla(AX, AY: Double; out ALx, ALy: Double): Boolean;
begin
  if FEscala <= 0 then
    FEscala := 1.0;
  ALx := AX / FEscala;
  ALy := AY / FEscala;
  Result := (ALx >= 0) and (ALy >= 0) and (ALx < FRegion.Ancho) and (ALy < FRegion.Alto);
  if not Result then
    FError := MsgFmt(SF_NODE_CAE_FUERA_PANTALLA_FMT,
      [FormatFloat('0', AX), FormatFloat('0', AY), FormatFloat('0.00', FEscala), FRegion.Ancho, FRegion.Alto]);
end;

function TManos.Mover(AX, AY: Double): Boolean;
var
  Lx, Ly: Double;
begin
  Result := False;
  if not FListo then
  begin
    FError := MsgText(SF_NODE_CANAL_NO_ESTA_LISTO);
    Exit;
  end;
  if not EnPantalla(AX, AY, Lx, Ly) then
    Exit;
  EiEmpezar(FPuntero, FSecuencia);
  Inc(FSecuencia);
  EiMover(FPuntero, Lx, Ly);
  EiCuadro(FPuntero, Microsegundos);
  EiParar(FPuntero);
  Bombear;
  Result := True;
end;

function TManos.Microsegundos: UInt64;
begin
  Result := UInt64(Round(TStopwatch.GetTimeStamp *
    (1000000.0 / TStopwatch.Frequency)));
end;


procedure TManos.Boton(ABoton: Cardinal; APulsado: Boolean);
var
  Disp: Pointer;
begin
  { El boton viaja por el dispositivo que TIENE esa capacidad; si el
    escritorio no creo uno aparte, sirve el mismo del puntero. }
  Disp := FBoton;
  if Disp = nil then
    Disp := FPuntero;
  EiEmpezar(Disp, FSecuencia);
  Inc(FSecuencia);
  EiBoton(Disp, ABoton, APulsado);
  EiCuadro(Disp, Microsegundos);
  EiParar(Disp);
  Bombear;
end;

function TManos.Pulsar(AX, AY: Double; ABoton: Cardinal = 272): Boolean;
begin
  Result := False;
  if not Mover(AX, AY) then
    Exit;
  Sleep(120);
  Boton(ABoton, True);
  Sleep(80);
  Boton(ABoton, False);
  Result := True;
end;

function TManos.Arrastrar(AX1, AY1, AX2, AY2: Double; ABoton: Cardinal = 272): Boolean;
const
  { en pasos, como una mano: un escritorio no empieza un arrastre con un
    salto, sino cuando el puntero se mueve con el boton abajo }
  PASOS = 20;
var
  Lx, Ly: Double;
begin
  Result := False;
  if not FListo then
  begin
    FError := MsgText(SF_NODE_CANAL_NO_ESTA_LISTO);
    Exit;
  end;
  // el destino ANTES de pulsar: fuera de la pantalla, el boton quedaria abajo
  if not EnPantalla(AX2, AY2, Lx, Ly) then
    Exit;
  if not Mover(AX1, AY1) then
    Exit;
  Sleep(120);
  Boton(ABoton, True);
  try
    Sleep(150);
    for var I := 1 to PASOS do
    begin
      if not Mover(AX1 + (AX2 - AX1) * I / PASOS, AY1 + (AY2 - AY1) * I / PASOS) then
        Exit;
      Sleep(15);
    end;
    Sleep(100);
    Result := True;
  finally
    // se suelta SIEMPRE: un boton abajo dejaria el raton del operador arrastrando
    Boton(ABoton, False);
  end;
end;

{ Pide al escritorio su mapa de teclado, UNA vez. libei lo entrega como un
  descriptor a un texto XKB; se copia (acabado en #0) y lo lee Mld.Teclado. }
procedure TManos.MirarMapa;
var
  Dir, Mapa, Vista: Pointer;
  Fd: Integer;
  Tam: NativeUInt;
  Copia: TBytes;
begin
  if FMapaMirado then
    Exit;
  FMapaMirado := True;
  FMapaNota := MsgText(SF_NODE_TECLADO_TABLA_FIJA);
  if FTeclado = nil then
    Exit;
  if not (FLib.Simbolo('ei_device_keyboard_get_keymap', Dir)) then
  begin
    FMapaNota := FMapaNota + MsgText(SF_NODE_LIBEI_NO_ENTREGA_MAPA);
    Exit;
  end;
  EiMapaDe := TEiMapaDe(Dir);
  if not FLib.Simbolo('ei_keymap_get_fd', Dir) then Exit;
  EiMapaFd := TEiMapaFd(Dir);
  if not FLib.Simbolo('ei_keymap_get_size', Dir) then Exit;
  EiMapaTam := TEiMapaTam(Dir);
  Mapa := EiMapaDe(FTeclado);
  if Mapa = nil then
  begin
    FMapaNota := FMapaNota + MsgText(SF_NODE_ESCRITORIO_NO_ENTREGO_MAPA);
    Exit;
  end;
  Fd := EiMapaFd(Mapa);
  Tam := EiMapaTam(Mapa);
  if (Fd < 0) or (Tam = 0) or (Tam > 8 * 1024 * 1024) then
    Exit;
  Vista := mmap(nil, Tam, PROT_READ, MAP_PRIVATE, Fd, 0);
  if NativeInt(Vista) = -1 then
  begin
    FMapaNota := FMapaNota + MsgText(SF_NODE_NO_LEER_MAPA_ESCRITORIO);
    Exit;
  end;
  try
    SetLength(Copia, Tam + 1); // a ceros: el texto queda acabado en #0
    Move(Vista^, Copia[0], Tam);
  finally
    munmap(Vista, Tam);
  end;
  FMapa := TMapaTeclado.Create;
  if FMapa.Cargar(@Copia[0]) then
    FMapaNota := MsgFmt(SF_NODE_TECLADO_DEL_ESCRITORIO_FMT,
      [FMapa.Distribucion, FMapa.Cuantas])
  else
    FMapaNota := FMapaNota + ' - ' + FMapa.Error;
end;

function TManos.Tecla(ACodigo: Cardinal; APulsada: Boolean): Boolean;
begin
  Result := False;
  if not FListo then
  begin
    FError := MsgText(SF_NODE_CANAL_NO_ESTA_LISTO);
    Exit;
  end;
  if FTeclado = nil then
  begin
    FError := MsgText(SF_NODE_ESCRITORIO_NO_DIO_TECLADO);
    Exit;
  end;
  EiEmpezar(FTeclado, FSecuencia);
  Inc(FSecuencia);
  EiTecla(FTeclado, ACodigo, APulsada);
  EiCuadro(FTeclado, Microsegundos);
  EiParar(FTeclado);
  Bombear;
  Result := True;
end;

function TManos.Combinacion(const ACodigos: array of Cardinal): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(ACodigos) do
  begin
    if not Tecla(ACodigos[I], True) then
      Exit;
    Sleep(60);
  end;
  for I := High(ACodigos) downto 0 do
  begin
    if not Tecla(ACodigos[I], False) then
      Exit;
    Sleep(60);
  end;
  Result := True;
end;

function TManos.Escribir(const ATexto: string): Boolean;
var
  I, Codigo: Integer;
  C: Char;
  Mayus: Boolean;
  Gestos: TArray<TPulsacion>;

  { Pulsa y suelta ACodigo en su nivel (Mayusculas si es impar, AltGr de 2 en
    adelante), como una persona: el gesto de cada caracter, lo diga el mapa o
    la tabla fija, y el de un salto de linea. Estaba escrito dos veces. }
  function Pulsa(ACodigo: Cardinal; ANivel: Integer): Boolean;
  begin
    Result := False;
    if Odd(ANivel) and not Tecla(EVDEV_MAYUS, True) then Exit;
    if (ANivel >= 2) and not Tecla(EVDEV_ALTGR, True) then Exit;
    if not Tecla(ACodigo, True) then Exit;
    Sleep(35);
    if not Tecla(ACodigo, False) then Exit;
    if (ANivel >= 2) and not Tecla(EVDEV_ALTGR, False) then Exit;
    if Odd(ANivel) and not Tecla(EVDEV_MAYUS, False) then Exit;
    Sleep(35);
    Result := True;
  end;

  function Gesto(ACodigo: Cardinal; ANivel: Integer): TPulsacion;
  begin
    Result.Codigo := ACodigo;
    Result.Nivel := ANivel;
  end;

begin
  Result := False;
  if not FListo then
  begin
    FError := MsgText(SF_NODE_CANAL_NO_ESTA_LISTO);
    Exit;
  end;
  MirarMapa;
  // TODO el texto se traduce a pulsaciones ANTES de pulsar ninguna: con un
  // caracter sin tecla a mitad, lo de antes quedaba escrito en la ventana del
  // destino y la respuesta decia que no se pudo (R3 de la 1.29, medido en el
  // Fedora: "ab<TAB>cd" dejo "ab" escrito)
  Gestos := [];
  for I := 1 to Length(ATexto) do
  begin
    C := ATexto[I];
    // Un salto de linea es la tecla Intro y un tabulador la tecla Tab, en toda
    // distribucion: las que pulsa una persona (el servidor deja todo salto en
    // LF; J10 de la 1.28). El mapa no las da: no componen un caracter
    // imprimible (R4 de la 1.29: el tabulador cortaba el texto)
    if C = #10 then
    begin
      Gestos := Gestos + [Gesto(EVDEV_INTRO, 0)];
      Continue;
    end;
    if C = #9 then
    begin
      Gestos := Gestos + [Gesto(EVDEV_TAB, 0)];
      Continue;
    end;
    // otro control no tiene tecla: se nombra por su codigo, que crudo iba
    // tal cual en la salida del nodo
    if C < ' ' then
    begin
      FError := MsgFmt(SF_NODE_NO_SE_TECLEAR_FMT, [Format('#%d', [Ord(C)]), I]);
      Exit;
    end;
    // Con el mapa del escritorio en la mano, manda EL: la tecla y el nivel
    // (Mayusculas, AltGr) que el escritorio dice que dan ese caracter.
    if (FMapa <> nil) and (FMapa.Cuantas > 0) then
    begin
      // Una pulsacion si la tecla existe, DOS si el caracter sale por tecla
      // muerta ("´" y luego "i" = "í"): el mapa lo decide.
      var Secuencia: TArray<TPulsacion>;
      if not FMapa.Secuencia(Ord(C), Secuencia) then
      begin
        FError := MsgFmt(SF_NODE_TECLADO_SIN_TECLA_FMT,
          [FMapa.Distribucion, string(C), I, FMapa.CuantasMuertas]);
        Exit;
      end;
      Gestos := Gestos + Secuencia;
      Continue;
    end;
    // Sin mapa: la tabla fija de siempre, que es un teclado AMERICANO. En
    // otra distribucion '-' y '/' NO salen bien, y MapaNota lo dice.
    Mayus := CharInSet(C, ['A'..'Z']);
    if Mayus then
      C := Chr(Ord(C) + 32);
    case C of
      'a': Codigo := 30;  'b': Codigo := 48;  'c': Codigo := 46;
      'd': Codigo := 32;  'e': Codigo := 18;  'f': Codigo := 33;
      'g': Codigo := 34;  'h': Codigo := 35;  'i': Codigo := 23;
      'j': Codigo := 36;  'k': Codigo := 37;  'l': Codigo := 38;
      'm': Codigo := 50;  'n': Codigo := 49;  'o': Codigo := 24;
      'p': Codigo := 25;  'q': Codigo := 16;  'r': Codigo := 19;
      's': Codigo := 31;  't': Codigo := 20;  'u': Codigo := 22;
      'v': Codigo := 47;  'w': Codigo := 17;  'x': Codigo := 45;
      'y': Codigo := 21;  'z': Codigo := 44;
      '1': Codigo := 2;   '2': Codigo := 3;   '3': Codigo := 4;
      '4': Codigo := 5;   '5': Codigo := 6;   '6': Codigo := 7;
      '7': Codigo := 8;   '8': Codigo := 9;   '9': Codigo := 10;
      '0': Codigo := 11;  ' ': Codigo := 57;  '-': Codigo := 12;
      '.': Codigo := 52;  ',': Codigo := 51;  '/': Codigo := 53;
    else
      begin
        FError := MsgFmt(SF_NODE_NO_SE_TECLEAR_FMT, [string(C), I]);
        Exit;
      end;
    end;
    Gestos := Gestos + [Gesto(Codigo, Ord(Mayus))];
  end;
  // ...y solo con todo comprobado, se pulsa
  for var G in Gestos do
    if not Pulsa(G.Codigo, G.Nivel) then
      Exit;
  Result := True;
end;

end.
