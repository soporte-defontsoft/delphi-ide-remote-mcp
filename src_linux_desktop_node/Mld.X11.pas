unit Mld.X11;

{ Los OJOS: enumerar las ventanas del escritorio por X11, cargando libX11 en
  ejecucion (ver [Mld.Dyn]). Sustituye a xdotool - una dependencia menos que
  instalar en la maquina destino.

  Dos lecciones del campo (18-sep) van incrustadas aqui:
   - PAServer NO hereda DISPLAY ni XAUTHORITY, asi que el nodo se las pone
     solo: ':0' y el fichero .mutter-Xwaylandauth.* mas reciente.
   - Los dialogos de una aplicacion FMX son ventanas SIN NOMBRE. Buscarlas por
     titulo NO las encuentra: hay que enumerar por PROCESO. Por eso se lee
     _NET_WM_PID de cada ventana. }

interface

uses
  Mld.Dyn;

type
  PXImage = ^TXImage;
  { struct _XImage de Xlib. Solo se nombran los campos que se usan; el resto
    esta para que las posiciones cuadren. }
  TXImage = record
    Ancho, Alto: Integer;
    XOffset, Formato: Integer;
    Datos: PByte;
    ByteOrder, BitmapUnit, BitmapBitOrder, BitmapPad: Integer;
    Depth, BytesPerLine, BitsPerPixel: Integer;
    RedMask, GreenMask, BlueMask: NativeUInt;
    ObData: Pointer;
    FCrear, FDestruir, FPixel, FPonPixel, FSubImagen, FSumaPixel: Pointer;
  end;

  TVentana = record
    Id: NativeUInt;
    Titulo: string;
    Pid: Cardinal;
    X, Y, Ancho, Alto: Integer;
    Visible: Boolean;
  end;

  TOjos = class
  private
    FLib: TLibreria;
    FDisp: Pointer;
    FError: string;
    function Resolver: Boolean;
    procedure PrepararEntorno;
    function LeerPid(AVentana: NativeUInt): Cardinal;
    function LeerTitulo(AVentana: NativeUInt): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Abrir: Boolean;
    { Todas las ventanas del escritorio, de la raiz hacia abajo. }
    function Enumerar(out AVentanas: TArray<TVentana>): Boolean;
    { Pixeles de una ventana; nil deja el motivo en Error. }
    function Imagen(AVentana: NativeUInt): PXImage;
    procedure LiberarImagen(AImagen: PXImage);
    { Donde esta el puntero, en coordenadas FISICAS de X11. }
    function DondeEstaElPuntero(out AX, AY: Integer): Boolean;
    { Por que no hay ojos, en palabras que el AGENTE pueda repetirle al
      operador para que abra sesion grafica. }
    function Diagnostico: string;
    property Error: string read FError;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Posix.Stdlib;

const
  IsViewable = 2;
  XA_CARDINAL = 6;

type
  TXWindowAttributes = record
    X, Y, Ancho, Alto: Integer;
    BorderWidth, Depth: Integer;
    Visual: Pointer;
    Root: NativeUInt;
    Clase, BitGravity, WinGravity, BackingStore: Integer;
    BackingPlanes, BackingPixel: NativeUInt;
    SaveUnder: Integer;
    Colormap: NativeUInt;
    MapInstalled, MapState: Integer;
    AllEventMasks, YourEventMask, DoNotPropagateMask: NativeInt;
    OverrideRedirect: Integer;
    Screen: Pointer;
  end;

  TXOpenDisplay = function(ANombre: MarshaledAString): Pointer; cdecl;
  TXCloseDisplay = function(ADisp: Pointer): Integer; cdecl;
  TXDefaultRootWindow = function(ADisp: Pointer): NativeUInt; cdecl;
  TXQueryTree = function(ADisp: Pointer; AVent: NativeUInt;
    out ARaiz, APadre: NativeUInt; out AHijos: PNativeUInt;
    out ANum: Cardinal): Integer; cdecl;
  TXGetWindowAttributes = function(ADisp: Pointer; AVent: NativeUInt;
    out AAtrib: TXWindowAttributes): Integer; cdecl;
  TXFetchName = function(ADisp: Pointer; AVent: NativeUInt;
    out ANombre: MarshaledAString): Integer; cdecl;
  TXFree = function(ADato: Pointer): Integer; cdecl;
  TXInternAtom = function(ADisp: Pointer; ANombre: MarshaledAString;
    ASoloSiExiste: Integer): NativeUInt; cdecl;
  TXGetWindowProperty = function(ADisp: Pointer; AVent: NativeUInt;
    APropiedad: NativeUInt; ADesde, ALargo: NativeInt; ABorrar: Integer;
    ATipoPedido: NativeUInt; out ATipoReal: NativeUInt; out AFormato: Integer;
    out ANum, ARestan: NativeUInt; out ADatos: Pointer): Integer; cdecl;
  TXQueryPointer = function(ADisp: Pointer; AVent: NativeUInt;
    out ARaiz, AHijo: NativeUInt; out ARx, ARy, AVx, AVy: Integer;
    out AMascara: Cardinal): Integer; cdecl;
  TXGetImage = function(ADisp: Pointer; ADibujable: NativeUInt;
    AX, AY: Integer; AAncho, AAlto: Cardinal; APlanos: NativeUInt;
    AFormato: Integer): PXImage; cdecl;

var
  XOpenDisplay: TXOpenDisplay;
  XCloseDisplay: TXCloseDisplay;
  XDefaultRootWindow: TXDefaultRootWindow;
  XQueryTree: TXQueryTree;
  XGetWindowAttributes: TXGetWindowAttributes;
  XFetchName: TXFetchName;
  XFree: TXFree;
  XInternAtom: TXInternAtom;
  XGetWindowProperty: TXGetWindowProperty;
  XGetImage: TXGetImage;
  XQueryPointer: TXQueryPointer;

function Texto(A: MarshaledAString): string;
begin
  if A = nil then
    Result := ''
  else
    Result := string(UTF8String(A));
end;

function Cadena(const S: string): UTF8String;
begin
  Result := UTF8String(S);
end;

constructor TOjos.Create;
begin
  inherited Create;
  FLib := TLibreria.Create;
end;

destructor TOjos.Destroy;
begin
  if (FDisp <> nil) and Assigned(XCloseDisplay) then
    XCloseDisplay(FDisp);
  FLib.Free;
  inherited;
end;

function TOjos.Resolver: Boolean;

  function Uno(const ASimbolo: string; out ADir: Pointer): Boolean;
  begin
    Result := FLib.Simbolo(ASimbolo, ADir);
    if not Result then
      FError := Format('falta %s en %s (%s)', [ASimbolo, FLib.Nombre, FLib.Error]);
  end;

begin
  Result :=
    Uno('XOpenDisplay', Pointer(@XOpenDisplay)) and
    Uno('XCloseDisplay', Pointer(@XCloseDisplay)) and
    Uno('XDefaultRootWindow', Pointer(@XDefaultRootWindow)) and
    Uno('XQueryTree', Pointer(@XQueryTree)) and
    Uno('XGetWindowAttributes', Pointer(@XGetWindowAttributes)) and
    Uno('XFetchName', Pointer(@XFetchName)) and
    Uno('XFree', Pointer(@XFree)) and
    Uno('XInternAtom', Pointer(@XInternAtom)) and
    Uno('XGetWindowProperty', Pointer(@XGetWindowProperty)) and
    Uno('XGetImage', Pointer(@XGetImage)) and
    Uno('XQueryPointer', Pointer(@XQueryPointer));
end;

procedure TOjos.PrepararEntorno;
var
  Mejor, F: string;
  MejorFecha: TDateTime;
  U, N: UTF8String;
begin
  if GetEnvironmentVariable('DISPLAY') = '' then
  begin
    N := Cadena('DISPLAY');
    U := Cadena(':0');
    setenv(MarshaledAString(PAnsiChar(N)), MarshaledAString(PAnsiChar(U)), 1);
  end;
  if GetEnvironmentVariable('XAUTHORITY') <> '' then
    Exit;
  Mejor := '';
  MejorFecha := 0;
  try
    for F in TDirectory.GetFiles('/run/user/1000', '.mutter-Xwaylandauth.*') do
      if (Mejor = '') or (TFile.GetLastWriteTime(F) > MejorFecha) then
      begin
        Mejor := F;
        MejorFecha := TFile.GetLastWriteTime(F);
      end;
  except
    on E: Exception do
      FError := 'no pude mirar /run/user/1000: ' + E.Message;
  end;
  if Mejor <> '' then
  begin
    N := Cadena('XAUTHORITY');
    U := Cadena(Mejor);
    setenv(MarshaledAString(PAnsiChar(N)), MarshaledAString(PAnsiChar(U)), 1);
  end;
end;

function TOjos.Abrir: Boolean;
begin
  FError := '';
  if not FLib.Abierta then
    if not FLib.Abrir('libX11.so.6') then
    begin
      FError := 'no hay libX11 en esta maquina: ' + FLib.Error;
      Exit(False);
    end;
  if not Resolver then
    Exit(False);
  PrepararEntorno;
  FDisp := XOpenDisplay(nil);
  Result := FDisp <> nil;
  if not Result then
    FError := Diagnostico + ' [DISPLAY=' + GetEnvironmentVariable('DISPLAY') +
      ' XAUTHORITY=' + GetEnvironmentVariable('XAUTHORITY') + ']';
end;

function TOjos.LeerTitulo(AVentana: NativeUInt): string;
var
  P: MarshaledAString;
begin
  Result := '';
  P := nil;
  if (XFetchName(FDisp, AVentana, P) <> 0) and (P <> nil) then
  begin
    Result := Texto(P);
    XFree(P);
  end;
end;

function TOjos.LeerPid(AVentana: NativeUInt): Cardinal;
var
  Atomo, TipoReal, Num, Restan: NativeUInt;
  Formato: Integer;
  Datos: Pointer;
  N: UTF8String;
begin
  Result := 0;
  N := Cadena('_NET_WM_PID');
  Atomo := XInternAtom(FDisp, MarshaledAString(PAnsiChar(N)), 1);
  if Atomo = 0 then
    Exit;
  Datos := nil;
  if XGetWindowProperty(FDisp, AVentana, Atomo, 0, 1, 0, XA_CARDINAL,
       TipoReal, Formato, Num, Restan, Datos) <> 0 then
    Exit;
  if Datos <> nil then
  begin
    if (Num >= 1) and (Formato = 32) then
      Result := PCardinal(Datos)^;
    XFree(Datos);
  end;
end;

function TOjos.Enumerar(out AVentanas: TArray<TVentana>): Boolean;
var
  Acc: TArray<TVentana>;

  procedure Recorrer(AVentana: NativeUInt);
  var
    Raiz, Padre: NativeUInt;
    Hijos: PNativeUInt;
    Num, I: Cardinal;
    At: TXWindowAttributes;
    V: TVentana;
    P: PNativeUInt;
  begin
    FillChar(At, SizeOf(At), 0);
    if XGetWindowAttributes(FDisp, AVentana, At) <> 0 then
    begin
      V := Default(TVentana);
      V.Id := AVentana;
      V.X := At.X;
      V.Y := At.Y;
      V.Ancho := At.Ancho;
      V.Alto := At.Alto;
      V.Visible := At.MapState = IsViewable;
      V.Titulo := LeerTitulo(AVentana);
      V.Pid := LeerPid(AVentana);
      Acc := Acc + [V];
    end;
    Hijos := nil;
    Num := 0;
    if XQueryTree(FDisp, AVentana, Raiz, Padre, Hijos, Num) = 0 then
      Exit;
    if Hijos <> nil then
    try
      P := Hijos;
      for I := 1 to Num do
      begin
        Recorrer(P^);
        Inc(P);
      end;
    finally
      XFree(Hijos);
    end;
  end;

begin
  AVentanas := nil;
  FError := '';
  if FDisp = nil then
  begin
    FError := 'no hay conexion con X11';
    Exit(False);
  end;
  Recorrer(XDefaultRootWindow(FDisp));
  AVentanas := Acc;
  Result := True;
end;

function TOjos.Imagen(AVentana: NativeUInt): PXImage;
const
  ZPixmap = 2;
  TodosLosPlanos = NativeUInt($FFFFFFFFFFFFFFFF);
var
  At: TXWindowAttributes;
begin
  Result := nil;
  FError := '';
  if FDisp = nil then
  begin
    FError := 'no hay conexion con X11';
    Exit;
  end;
  FillChar(At, SizeOf(At), 0);
  if XGetWindowAttributes(FDisp, AVentana, At) = 0 then
  begin
    FError := 'esa ventana ya no existe';
    Exit;
  end;
  if At.MapState <> IsViewable then
  begin
    FError := 'la ventana no esta visible: no hay nada que capturar';
    Exit;
  end;
  Result := XGetImage(FDisp, AVentana, 0, 0, At.Ancho, At.Alto,
    TodosLosPlanos, ZPixmap);
  if Result = nil then
    FError := 'XGetImage no devolvio imagen (ventana tapada o sin respaldo)';
end;

procedure TOjos.LiberarImagen(AImagen: PXImage);
type
  TDestruir = function(AImg: PXImage): Integer; cdecl;
begin
  if AImagen = nil then
    Exit;
  if AImagen.FDestruir <> nil then
    TDestruir(AImagen.FDestruir)(AImagen)
  else if Assigned(XFree) then
    XFree(AImagen);
end;

function TOjos.Diagnostico: string;
var
  Rt: string;
  HayWayland, HayXauth, HayX: Boolean;
begin
  Rt := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if Rt = '' then
    Rt := '/run/user/1000';
  HayWayland := False;
  HayXauth := False;
  HayX := False;
  try
    HayWayland := Length(TDirectory.GetFileSystemEntries(Rt, 'wayland-*')) > 0;
    HayXauth := Length(TDirectory.GetFileSystemEntries(Rt, '.mutter-Xwaylandauth.*')) > 0;
    if TDirectory.Exists('/tmp/.X11-unix') then
      HayX := Length(TDirectory.GetFileSystemEntries('/tmp/.X11-unix', 'X*')) > 0;
  except
    on E: Exception do
      Exit('no pude mirar ' + Rt + ': ' + E.Message);
  end;
  if not (HayWayland or HayX) then
    Exit('NO hay sesion grafica abierta en esta maquina. Pidele al operador ' +
      'que inicie sesion en el escritorio (o abra una sesion remota) y ' +
      'vuelve a intentarlo: sin escritorio no hay nada que ver ni que pulsar.');
  if HayWayland and not HayXauth then
    Exit('Hay sesion Wayland pero no encuentro la autorizacion de Xwayland ' +
      '(.mutter-Xwaylandauth.*). Pidele al operador que abra alguna ' +
      'aplicacion en esa sesion, o comprueba que Xwayland este activo.');
  Result := 'Hay sesion grafica, pero no pude conectar con ella.';
end;

function TOjos.DondeEstaElPuntero(out AX, AY: Integer): Boolean;
var
  Raiz, Hijo: NativeUInt;
  Vx, Vy: Integer;
  Mascara: Cardinal;
begin
  AX := 0;
  AY := 0;
  Result := False;
  if FDisp = nil then
  begin
    FError := 'no hay conexion con X11';
    Exit;
  end;
  Result := XQueryPointer(FDisp, XDefaultRootWindow(FDisp), Raiz, Hijo,
    AX, AY, Vx, Vy, Mascara) <> 0;
  if not Result then
    FError := 'el puntero no esta en esta pantalla';
end;

end.
