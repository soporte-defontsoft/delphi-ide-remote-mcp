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
  Mld.Dyn;

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
    FNombreAsiento: string;
    FSecuencia: Cardinal;
    FError: string;
    function Resolver: Boolean;
    procedure Atender(AEvento: Pointer; ATipo: Integer);
    procedure Emitir(ADisp: Pointer);
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
    property NombreAsiento: string read FNombreAsiento;
    property Error: string read FError;
    function Microsegundos: UInt64;
  end;

implementation

uses
  System.SysUtils, System.Diagnostics;

const
  { enum ei_device_capability }
  CAP_PUNTERO = 1;
  CAP_ABSOLUTO = 2;
  CAP_TECLADO = 4;
  CAP_BOTON = 32;
  { enum ei_event_type }
  EV_CONECTADO = 1;
  EV_ASIENTO = 3;
  EV_DISPOSITIVO = 5;
  EV_REANUDADO = 8;

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
  TEiAsientoNombre = function(AAs: Pointer): MarshaledAString; cdecl;
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
  EiAsientoNombre: TEiAsientoNombre;
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
  FLib.Free;
  inherited;
end;

function TManos.Resolver: Boolean;

  function Uno(const ASimbolo: string; out ADir: Pointer): Boolean;
  begin
    Result := FLib.Simbolo(ASimbolo, ADir);
    if not Result then
      FError := Format('falta %s en %s (%s)', [ASimbolo, FLib.Nombre, FLib.Error]);
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
    Uno('ei_seat_get_name', Pointer(@EiAsientoNombre)) and
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

procedure TManos.Emitir(ADisp: Pointer);
begin
  { reservado para la fase de emision de eventos }
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
        FNombreAsiento := Texto(EiAsientoNombre(FAsiento));
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
    FError := 'descriptor invalido';
    Exit;
  end;
  if not FLib.Abierta then
    if not FLib.Abrir('libei.so.1') then
    begin
      FError := 'no hay libei en esta maquina: ' + FLib.Error;
      Exit;
    end;
  if not Resolver then
    Exit;
  FEi := EiNuevo(nil);
  if FEi = nil then
  begin
    FError := 'ei_new_sender no devolvio contexto';
    Exit;
  end;
  U := UTF8String(ANombre);
  EiNombre(FEi, MarshaledAString(PAnsiChar(U)));
  { toma posesion del descriptor }
  Rc := EiBackendFd(FEi, ADescriptor);
  if Rc <> 0 then
  begin
    FError := Format('ei_setup_backend_fd devolvio %d', [Rc]);
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
    FError := Format('los dispositivos no llegaron a estar listos en %d ms ' +
      '(puntero=%s teclado=%s)', [AMs, BoolToStr(FPuntero <> nil, True),
      BoolToStr(FTeclado <> nil, True)]);
end;

function TManos.Mover(AX, AY: Double): Boolean;
var
  Lx, Ly: Double;
begin
  Result := False;
  if not FListo then
  begin
    FError := 'el canal no esta listo';
    Exit;
  end;
  if FEscala <= 0 then
    FEscala := 1.0;
  Lx := AX / FEscala;
  Ly := AY / FEscala;
  if (Lx < 0) or (Ly < 0) or (Lx >= FRegion.Ancho) or (Ly >= FRegion.Alto) then
  begin
    FError := Format('(%.0f,%.0f) de la captura cae fuera de la pantalla ' +
      '(escala %.2f, region %dx%d)',
      [AX, AY, FEscala, FRegion.Ancho, FRegion.Alto]);
    Exit;
  end;
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


function TManos.Pulsar(AX, AY: Double; ABoton: Cardinal = 272): Boolean;
var
  Disp: Pointer;
begin
  Result := False;
  if not Mover(AX, AY) then
    Exit;
  Sleep(120);
  { El boton viaja por el dispositivo que TIENE esa capacidad; si el
    escritorio no creo uno aparte, sirve el mismo del puntero. }
  Disp := FBoton;
  if Disp = nil then
    Disp := FPuntero;
  EiEmpezar(Disp, FSecuencia);
  Inc(FSecuencia);
  EiBoton(Disp, ABoton, True);
  EiCuadro(Disp, Microsegundos);
  EiParar(Disp);
  Bombear;
  Sleep(80);
  EiEmpezar(Disp, FSecuencia);
  Inc(FSecuencia);
  EiBoton(Disp, ABoton, False);
  EiCuadro(Disp, Microsegundos);
  EiParar(Disp);
  Bombear;
  Result := True;
end;

function TManos.Tecla(ACodigo: Cardinal; APulsada: Boolean): Boolean;
begin
  Result := False;
  if not FListo then
  begin
    FError := 'el canal no esta listo';
    Exit;
  end;
  if FTeclado = nil then
  begin
    FError := 'el escritorio no dio teclado';
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
const
  MAYUSCULA = 42;   { KEY_LEFTSHIFT }
var
  I, Codigo: Integer;
  C: Char;
  Mayus: Boolean;
begin
  Result := False;
  if not FListo then
  begin
    FError := 'el canal no esta listo';
    Exit;
  end;
  for I := 1 to Length(ATexto) do
  begin
    C := ATexto[I];
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
        FError := Format('no se teclear el caracter "%s" (posicion %d)', [C, I]);
        Exit;
      end;
    end;
    if Mayus and not Tecla(MAYUSCULA, True) then
      Exit;
    if not Tecla(Codigo, True) then
      Exit;
    Sleep(35);
    if not Tecla(Codigo, False) then
      Exit;
    if Mayus and not Tecla(MAYUSCULA, False) then
      Exit;
    Sleep(35);
  end;
  Result := True;
end;

end.
