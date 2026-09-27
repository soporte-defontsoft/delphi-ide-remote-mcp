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
    { Las ventanas PRINCIPALES: las hijas de la raiz que se ven y tienen
      nombre, con titulo y PID propios o -si no los llevan: bajo Mutter el
      marco y el cliente son ventanas distintas- los del primer descendiente
      que los tenga. Es la lista que viaja con cada captura (24-sep-2026).
      Coordenadas de X11, relativas a la raiz. }
    function Principales(out AVentanas: TArray<TVentana>): Boolean;
    { El tamano de la raiz de X11: con el de la captura da el factor para
      pasar un rectangulo de X11 a pixeles de la imagen (bajo Xwayland la
      raiz no mide lo que el monitor: 5504x2304 frente a 3440x1440, medido). }
    function TamanoRaiz(out AAncho, AAlto: Integer): Boolean;
    { Por que no hay ojos, en palabras que el AGENTE pueda repetirle al
      operador para que abra sesion grafica. }
    function Diagnostico: string;
    property Error: string read FError;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Posix.Stdlib,
  Mld.Sesion,
  Mld.Textos; // EL detector de sesion, el mismo que usa el lanzador

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
    Result := FLib.SimboloOMotivo(ASimbolo, ADir, FError);
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
    Uno('XGetWindowProperty', Pointer(@XGetWindowProperty));
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
    // el X de ESTE usuario (no siempre es :0: un xrdp es :10)
    U := Cadena(SesionGrafica.Display);
    if U = '' then
      U := Cadena(':0');
    setenv(MarshaledAString(PAnsiChar(N)), MarshaledAString(PAnsiChar(U)), 1);
  end;
  if GetEnvironmentVariable('XAUTHORITY') <> '' then
    Exit;
  Mejor := '';
  MejorFecha := 0;
  try
    for F in TDirectory.GetFiles(RuntimeDelUsuario, '.mutter-Xwaylandauth.*') do
      if (Mejor = '') or (TFile.GetLastWriteTime(F) > MejorFecha) then
      begin
        Mejor := F;
        MejorFecha := TFile.GetLastWriteTime(F);
      end;
  except
    on E: Exception do
      FError := MsgFmt(SF_NODE_NO_PUDE_MIRAR_FMT, [RuntimeDelUsuario, E.Message]);
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
      FError := MsgFmt(SF_NODE_NO_HAY_LIB_FMT, ['libX11', FLib.Error]);
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

function TOjos.TamanoRaiz(out AAncho, AAlto: Integer): Boolean;
var
  At: TXWindowAttributes;
begin
  AAncho := 0;
  AAlto := 0;
  Result := False;
  if FDisp = nil then
    Exit;
  FillChar(At, SizeOf(At), 0);
  if XGetWindowAttributes(FDisp, XDefaultRootWindow(FDisp), At) = 0 then
    Exit;
  AAncho := At.Ancho;
  AAlto := At.Alto;
  Result := (AAncho > 0) and (AAlto > 0);
end;

function TOjos.Principales(out AVentanas: TArray<TVentana>): Boolean;
var
  Raiz, Padre: NativeUInt;
  Hijos, P: PNativeUInt;
  Num, I: Cardinal;
  At: TXWindowAttributes;
  V: TVentana;
  RaizW, RaizH: Integer;

  { Titulo y PID del primer descendiente que los tenga (pocos niveles: un
    marco lleva dentro al cliente, no un arbol). }
  procedure Completar(AVentana: NativeUInt; var AV: TVentana; ANivel: Integer);
  var
    R, Pa: NativeUInt;
    H, Q: PNativeUInt;
    N, K: Cardinal;
  begin
    if (ANivel > 4) or ((AV.Titulo <> '') and (AV.Pid <> 0)) then
      Exit;
    H := nil;
    N := 0;
    if XQueryTree(FDisp, AVentana, R, Pa, H, N) = 0 then
      Exit;
    if H = nil then
      Exit;
    try
      Q := H;
      for K := 1 to N do
      begin
        if AV.Titulo = '' then
          AV.Titulo := LeerTitulo(Q^);
        if AV.Pid = 0 then
          AV.Pid := LeerPid(Q^);
        Completar(Q^, AV, ANivel + 1);
        if (AV.Titulo <> '') and (AV.Pid <> 0) then
          Break;
        Inc(Q);
      end;
    finally
      XFree(H);
    end;
  end;

begin
  AVentanas := nil;
  FError := '';
  if FDisp = nil then
  begin
    FError := MsgText(SF_NODE_SIN_CONEXION_X11);
    Exit(False);
  end;
  TamanoRaiz(RaizW, RaizH);
  Hijos := nil;
  Num := 0;
  if XQueryTree(FDisp, XDefaultRootWindow(FDisp), Raiz, Padre, Hijos, Num) = 0 then
  begin
    FError := MsgText(SF_NODE_NO_LEER_ARBOL_X11);
    Exit(False);
  end;
  if Hijos <> nil then
  try
    P := Hijos;
    for I := 1 to Num do
    begin
      FillChar(At, SizeOf(At), 0);
      if (XGetWindowAttributes(FDisp, P^, At) <> 0) and
         (At.MapState = IsViewable) and (At.Ancho > 1) and (At.Alto > 1) then
      begin
        V := Default(TVentana);
        V.Id := P^;
        V.X := At.X;
        V.Y := At.Y;
        V.Ancho := At.Ancho;
        V.Alto := At.Alto;
        V.Visible := True;
        V.Titulo := LeerTitulo(P^);
        V.Pid := LeerPid(P^);
        Completar(P^, V, 0);
        { Sin nombre no es una ventana para quien mira (un menu, un tooltip).
          Y la ventana GUARDIA de Mutter lleva nombre ("mutter guard window",
          medido 24-sep) pero no es de nadie: sin PID y tapando la raiz entera. }
        if (V.Titulo <> '') and not ((V.Pid = 0) and (V.X = 0) and (V.Y = 0) and
           (V.Ancho = RaizW) and (V.Alto = RaizH)) then
          AVentanas := AVentanas + [V];
      end;
      Inc(P);
    end;
  finally
    XFree(Hijos);
  end;
  Result := True;
end;

function TOjos.Diagnostico: string;
var
  S: TSesionGrafica;
  HayXauth: Boolean;
begin
  S := SesionGrafica;
  if not S.Hay then
    Exit(S.Motivo);
  try
    HayXauth := Length(TDirectory.GetFileSystemEntries(RuntimeDelUsuario,
      '.mutter-Xwaylandauth.*')) > 0;
  except
    on E: Exception do
      Exit(MsgFmt(SF_NODE_NO_PUDE_MIRAR_FMT, [RuntimeDelUsuario, E.Message]));
  end;
  if (S.WaylandDisplay <> '') and not HayXauth then
    Exit(MsgText(SF_NODE_XWAYLAND_SIN_AUTORIZACION));
  Result := MsgText(SF_NODE_SESION_SIN_CONECTAR);
end;

end.
