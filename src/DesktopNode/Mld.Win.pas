unit Mld.Win;

{ OJOS Y MANOS EN WINDOWS: la otra mitad del nodo.

  En Linux el escritorio se habla por D-Bus y libei, cargadas en caliente
  porque no se puede dar por supuesto que esten ahi ([Mld.DBus], [Mld.Eis]).
  En Windows no hay nada que negociar ni que instalar: la pantalla se lee con
  GDI y las manos son SendInput, que vienen con el sistema. Por eso esta
  unidad no usa carga dinamica salvo en un punto -la conciencia de DPI, que
  no existe en Windows antiguos y se pide solo si esta.

  Mismos gestos que el lado Linux y mismo contrato de salida: las coordenadas
  que entran son PIXELES DE LA CAPTURA, y la captura es el escritorio virtual
  entero (todos los monitores). Asi quien llama mide sobre la imagen y no
  necesita saber nada de monitores, escalas ni margenes negativos. }

interface

{$IFDEF MSWINDOWS}

uses
  Winapi.Windows;

type
  { Una ventana visible del escritorio, en coordenadas de la captura. }
  TVentanaWin = record
    Handle: HWND;
    Titulo: string;
    X, Y, Ancho, Alto: Integer;  { lo que SE VE, sin el borde invisible }
    Entera: TRect;               { la ventana entera, como la pinta PrintWindow }
  end;

  TEscritorioWin = class
  private
    FError: string;
    FIzq, FSup, FAncho, FAlto: Integer;   { escritorio virtual, en pixeles }
    FEscala: Double;
    FRespaldo: string;                    { como se hizo la ultima captura si BitBlt fallo }
    FCodigo: DWORD;                       { el codigo de Windows del ultimo fallo de captura (0 = ninguno) }
    procedure MedirPantalla;
    function ComponerPorVentanas(ADestino: HDC): Integer;
    function EnviarEntradas(var AEntradas: array of TInput): Boolean;
    { El pixel de la captura en el 0..65535 de SendInput, y si cae en ella
      (si no, el motivo en Error): lo miran Pulsar y Arrastrar. }
    function Absolutas(AX, AY: Integer; out AAbsX, AAbsY: Integer): Boolean;
    { UNA entrada del raton: AFlags dice si mueve (MOVER_ABS), baja o sube. }
    function Raton(AAbsX, AAbsY: Integer; AFlags: DWORD): Boolean;
  public
    constructor Create;
    { Captura el escritorio virtual completo en ARuta (PNG). }
    function Capturar(const ARuta: string): Boolean;
    { Pulsa en el pixel (AX, AY) DE LA CAPTURA. }
    function Pulsar(AX, AY: Integer): Boolean;
    { Arrastra como una mano: pulsa en (AX1,AY1) DE LA CAPTURA, se mueve en
      pasos hasta (AX2,AY2) y suelta alli. El destino se mira ANTES de
      pulsar, y el boton se suelta siempre. }
    function Arrastrar(AX1, AY1, AX2, AY2: Integer): Boolean;
    { Escribe texto donde este el foco (Unicode, acentos incluidos). }
    function Escribir(const ATexto: string): Boolean;
    { Pulsa una combinacion: se mantienen pulsadas todas y se sueltan al
      reves, como haria una mano. Codigos VK de Windows. }
    function Combinacion(const ATeclas: array of Word): Boolean;
    { Las ventanas visibles con titulo, de arriba abajo en orden Z. }
    function Ventanas: TArray<TVentanaWin>;
    property Error: string read FError;
    property Escala: Double read FEscala;
    { '' = la captura salio por BitBlt del escritorio; si no, el camino de
      respaldo que se uso y por que. }
    property Respaldo: string read FRespaldo;
    { El codigo de Windows de la copia de pantalla que fallo, para el
      protocolo (NODO_CODIGO_WIN): el servidor juzga por el, no por la frase
      del idioma del destino (V85 de la 1.23.1). 0 si no lo hubo. }
    property Codigo: DWORD read FCodigo;
    property Ancho: Integer read FAncho;
    property Alto: Integer read FAlto;
  end;

{ Nombre de tecla -> codigo VK, para que el servidor pueda hablar por nombre
  ('escape', 'enter') y no por numeros distintos en cada sistema. 0 = no la
  conozco. }
function TeclaPorNombre(const ANombre: string): Word;

{ El estado del escritorio ahora mismo: escritorio de entrada, sesion remota
  o de consola, ventana con foco. El nodo lo escribe en cada ejecucion para
  poder comparar los casos en que la captura falla con los que no. }
function EstadoDelEscritorio: string;

{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  Winapi.Dwmapi,
  Mld.Captura,
  Mld.Textos;

const
  { No estan en Winapi.Windows de esta version; valores de la API de Win32. }
  CAPTUREBLT = $40000000;               { incluir ventanas por capas }
  MOUSEEVENTF_VIRTUALDESK = $4000;      { coordenadas del escritorio virtual }
  PW_RENDERFULLCONTENT = $00000002;     { PrintWindow: el bufer del DWM, no WM_PRINT }

{ No esta en Winapi.Windows de esta version. Pinta UNA ventana desde su
  superficie del DWM; llamado desde OTRO proceso (este nodo lo es) con
  PW_RENDERFULLCONTENT trae los pixeles reales aunque la tape otra. Desde el
  hilo de la propia ventana degenera en WM_PRINT (leccion de una app real,
  2026-07-04), pero ese caso aqui no se da. }
function PrintWindow(hwnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external user32 name 'PrintWindow';

function WTSQuerySessionInformationW(hServer: THandle; SessionId: DWORD;
  WTSInfoClass: Integer; out ppBuffer: Pointer; out pBytesReturned: DWORD): BOOL;
  stdcall; external 'wtsapi32.dll';
procedure WTSFreeMemory(pMemory: Pointer); stdcall; external 'wtsapi32.dll';

{ Si ESTA sesion esta desconectada, por el juez de Windows (WTSConnectState =
  WTSDisconnected): un escritorio de entrada que no se deja abrir es tanto una
  sesion desconectada como una bloqueada, y solo la primera se arregla
  reconectando (medido el 6-nov-2026 con David: desconectada, la sesion dice
  Disconnected y no se abre su escritorio de entrada). False si no lo dice. }
function SesionDesconectada: Boolean;
const
  SESION_ACTUAL = DWORD(-1);   { WTS_CURRENT_SESSION }
  WTS_CONNECT_STATE = 8;       { WTSConnectState }
  WTS_DISCONNECTED = 4;        { WTSDisconnected }
var
  Buf: Pointer;
  Bytes: DWORD;
begin
  Result := False;
  if WTSQuerySessionInformationW(0, SESION_ACTUAL, WTS_CONNECT_STATE, Buf, Bytes) then
  try
    Result := (Bytes >= SizeOf(Integer)) and (PInteger(Buf)^ = WTS_DISCONNECTED);
  finally
    WTSFreeMemory(Buf);
  end;
end;

{ El nombre del escritorio de ENTRADA (Default; Winlogon = el seguro de un
  UAC o del bloqueo); '' si no lo dice, y en AFallo el motivo si no se deja
  abrir. Lo leen EstadoDelEscritorio y el aviso de una entrada negada. }
function NombreDelEscritorioDeEntrada(out AFallo: string): string;
var
  D: HDESK;
  Nombre: array[0..255] of Char;
  Largo: DWORD;
begin
  Result := '';
  AFallo := '';
  D := OpenInputDesktop(0, False, DESKTOP_READOBJECTS);
  if D = 0 then
  begin
    AFallo := SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    Largo := 0;
    if GetUserObjectInformation(D, UOI_NAME, @Nombre[0], SizeOf(Nombre), Largo) then
      Result := string(PChar(@Nombre[0]));
  finally
    CloseDesktop(D);
  end;
end;

{ El estado del escritorio EN EL INSTANTE en que el DC de pantalla nego la
  copia: se cuenta solo, para comparar los casos buenos con los malos.
  Medido 2026-09-22: ni el cliente RDP minimizado ni el terminal de PAServer
  minimizado lo causaban. Medido 2026-11-06 con David (su RDP, anidado: el
  host de la VM y desde ahi este PC): con la ventana RDP de esta sesion
  MINIMIZADA en su maquina, la copia de pantalla se niega Y la entrada
  tambien (0 de N, Acceso denegado); restaurada, aunque sin foco, las dos
  van - el aviso de EnviarEntradas lo dice. Escritorio de entrada (Default;
  Winlogon = escritorio seguro de un UAC o del bloqueo), si la sesion es
  remota, y la ventana con el foco. }
function EstadoDelEscritorio: string;
var
  Foco: HWND;
  Titulo: array[0..255] of Char;
  Fallo, Nombre: string;
begin
  Nombre := NombreDelEscritorioDeEntrada(Fallo);
  if Fallo <> '' then
    Result := MsgFmt(SF_NODE_ESCRITORIO_ENTRADA_NO_ABRIR_FMT, [Fallo])
  else if Nombre <> '' then
    Result := MsgFmt(SF_NODE_ESCRITORIO_ENTRADA_FMT, [Nombre])
  else
    Result := MsgText(SF_NODE_ESCRITORIO_ENTRADA_SIN_NOMBRE);
  if GetSystemMetrics(SM_REMOTESESSION) <> 0 then
  begin
    Result := Result + MsgText(SF_NODE_SESION_REMOTA);
    if SesionDesconectada then
      Result := Result + MsgText(SF_NODE_SESION_DESCONECTADA);
  end
  else
    Result := Result + MsgText(SF_NODE_SESION_CONSOLA);
  Foco := GetForegroundWindow;
  if (Foco <> 0) and (GetWindowText(Foco, Titulo, Length(Titulo)) > 0) then
    Result := Result + MsgFmt(SF_NODE_FOCO_EN_FMT, [string(PChar(@Titulo[0]))])
  else
    Result := Result + MsgText(SF_NODE_SIN_VENTANA_FOCO);
end;

type
  TListaVentanas = TList<TVentanaWin>;

var
  GLista: TListaVentanas;   { EnumWindows no lleva contexto tipado comodo }
  GIzq, GSup: Integer;


function TeclaPorNombre(const ANombre: string): Word;
var
  N: string;
begin
  N := LowerCase(Trim(ANombre));
  if (N = 'escape') or (N = 'esc') then Result := VK_ESCAPE
  else if (N = 'enter') or (N = 'return') then Result := VK_RETURN
  else if N = 'tab' then Result := VK_TAB
  else if (N = 'super') or (N = 'win') then Result := VK_LWIN
  else if N = 'alt' then Result := VK_MENU
  else if N = 'ctrl' then Result := VK_CONTROL
  else if N = 'shift' then Result := VK_SHIFT
  else if N = 'space' then Result := VK_SPACE
  else if (N = 'backspace') or (N = 'back') then Result := VK_BACK
  else if N = 'delete' then Result := VK_DELETE
  else if N = 'home' then Result := VK_HOME
  else if N = 'end' then Result := VK_END
  else if N = 'up' then Result := VK_UP
  else if N = 'down' then Result := VK_DOWN
  else if N = 'left' then Result := VK_LEFT
  else if N = 'right' then Result := VK_RIGHT
  // una letra es su propia tecla virtual (VK_A..VK_Z son 'A'..'Z'): Ctrl+S
  // llega como "tecla ctrl s" (6-oct-2026; hasta hoy "no conozco la tecla")
  else if (Length(N) = 1) and CharInSet(N[1], ['a'..'z']) then
    Result := Ord(UpCase(N[1]))
  // ...y una cifra la suya (VK_0..VK_9 son '0'..'9'): "tecla 5" mandaba el
  // codigo virtual 5, un boton del raton (9.1 de la 1.18.0)
  else if (Length(N) = 1) and CharInSet(N[1], ['0'..'9']) then
    Result := Ord(N[1])
  else if (N = 'f1') or (N = 'f2') or (N = 'f3') or (N = 'f4') or (N = 'f5') or
          (N = 'f6') or (N = 'f7') or (N = 'f8') or (N = 'f9') or (N = 'f10') or
          (N = 'f11') or (N = 'f12') then
    Result := VK_F1 + Word(StrToIntDef(Copy(N, 2, 2), 1)) - 1
  else
    Result := 0;
end;

{ La conciencia de DPI se pide EN CALIENTE: sin ella Windows miente sobre el
  tamano de la pantalla (devuelve las medidas escaladas) y la captura sale
  borrosa y con las coordenadas corridas. En sistemas donde la funcion no
  existe, no pasa nada: se sigue con lo que haya. }
procedure PedirConcienciaDePixeles;
type
  TSetCtx = function(AValor: THandle): BOOL; stdcall;
  TSetAware = function: BOOL; stdcall;
var
  Lib: HMODULE;
  Ctx: TSetCtx;
  Aware: TSetAware;
begin
  Lib := GetModuleHandle('user32.dll');
  if Lib = 0 then
    Exit;
  @Ctx := GetProcAddress(Lib, 'SetProcessDpiAwarenessContext');
  if Assigned(Ctx) then
  begin
    { -4 = PER_MONITOR_AWARE_V2 }
    if Ctx(THandle(-4)) then
      Exit;
  end;
  @Aware := GetProcAddress(Lib, 'SetProcessDPIAware');
  if Assigned(Aware) then
    Aware;
end;

constructor TEscritorioWin.Create;
begin
  inherited Create;
  PedirConcienciaDePixeles;
  MedirPantalla;
end;

procedure TEscritorioWin.MedirPantalla;
var
  DC: HDC;
begin
  FIzq := GetSystemMetrics(SM_XVIRTUALSCREEN);
  FSup := GetSystemMetrics(SM_YVIRTUALSCREEN);
  FAncho := GetSystemMetrics(SM_CXVIRTUALSCREEN);
  FAlto := GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (FAncho <= 0) or (FAlto <= 0) then
  begin
    FAncho := GetSystemMetrics(SM_CXSCREEN);
    FAlto := GetSystemMetrics(SM_CYSCREEN);
  end;
  { La escala se informa para que el que llama sepa lo que ve, pero aqui NO
    se aplica a nada: ya capturamos y pulsamos en pixeles reales. }
  FEscala := 1.0;
  DC := GetDC(0);
  if DC <> 0 then
  try
    FEscala := GetDeviceCaps(DC, LOGPIXELSX) / 96.0;
  finally
    ReleaseDC(0, DC);
  end;
end;

function TEscritorioWin.Capturar(const ARuta: string): Boolean;
var
  DCPantalla, DCMemoria: HDC;
  Info: TBitmapInfo;
  Bmp, Previo: HBITMAP;
  Pixeles: Pointer;
  Cod: DWORD;
begin
  Result := False;
  FError := '';
  FRespaldo := '';
  FCodigo := 0;
  DCPantalla := GetDC(0);
  if DCPantalla = 0 then
  begin
    FError := MsgText(SF_NODE_NO_ABRIR_CONTEXTO_PANTALLA);
    Exit;
  end;
  try
    DCMemoria := CreateCompatibleDC(DCPantalla);
    if DCMemoria = 0 then
    begin
      FError := MsgText(SF_NODE_NO_CREAR_CONTEXTO_MEMORIA);
      Exit;
    end;
    try
      FillChar(Info, SizeOf(Info), 0);
      Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
      Info.bmiHeader.biWidth := FAncho;
      { Altura NEGATIVA: filas de arriba abajo, que es como las quiere el
        PNG. Con altura positiva saldria del reves. }
      Info.bmiHeader.biHeight := -FAlto;
      Info.bmiHeader.biPlanes := 1;
      Info.bmiHeader.biBitCount := 32;
      Info.bmiHeader.biCompression := BI_RGB;
      Pixeles := nil;
      Bmp := CreateDIBSection(DCMemoria, Info, DIB_RGB_COLORS, Pixeles, 0, 0);
      if (Bmp = 0) or (Pixeles = nil) then
      begin
        FError := MsgText(SF_NODE_NO_RESERVAR_IMAGEN);
        Exit;
      end;
      try
        Previo := SelectObject(DCMemoria, Bmp);
        try
          { CAPTUREBLT incluye ventanas por capas (menus, tooltips): sin el,
            justo lo que quieres mirar puede salir en negro. Pero en sesiones
            remotas y maquinas virtuales el propio CAPTUREBLT puede ser
            rechazado por el controlador de pantalla (medido: "Acceso
            denegado" en una VM por RDP), asi que si falla se reintenta sin
            el: mejor una captura sin menus flotantes que ninguna. }
          { El fallo del DC de pantalla es intermitente y no se provoca a
            voluntad: con MCPDESKTOP_SIN_BITBLT=1 en el entorno se salta
            BitBlt y se va derecho al respaldo, para poder medirlo. }
          if (GetEnvironmentVariable('MCPDESKTOP_SIN_BITBLT') = '1') or
             not BitBlt(DCMemoria, 0, 0, FAncho, FAlto, DCPantalla,
               FIzq, FSup, SRCCOPY or CAPTUREBLT) then
          begin
            Cod := GetLastError;   { antes de formatear nada: FormatMessage lo pisa }
            FError := MsgFmt(SF_NODE_CON_CAPTUREBLT_FMT, [SysErrorMessage(Cod), Cod]);
            if (GetEnvironmentVariable('MCPDESKTOP_SIN_BITBLT') = '1') or
               not BitBlt(DCMemoria, 0, 0, FAncho, FAlto, DCPantalla,
                 FIzq, FSup, SRCCOPY) then
            begin
              Cod := GetLastError;
              FCodigo := Cod;
              FError := MsgFmt(SF_NODE_COPIA_PANTALLA_FALLO_FMT,
                [FError, SysErrorMessage(Cod), Cod, EstadoDelEscritorio]);
              { RESPALDO: el DC de pantalla niega la copia a ratos (medido
                2026-09-22 con la sesion activa: "Acceso denegado" en un
                BitBlt y no en el siguiente). Cada ventana de arriba tiene su
                propia superficie en el DWM y PrintWindow la lee sin pasar
                por el DC de pantalla: se compone el escritorio ventana a
                ventana, de abajo arriba, sobre un fondo gris. Sin cursor ni
                fondo de pantalla, pero con lo que importa: las ventanas. }
              GdiFlush;
              FillChar(Pixeles^, FAncho * FAlto * 4, $40);
              if ComponerPorVentanas(DCMemoria) = 0 then
                Exit;
              FRespaldo := MsgFmt(SF_NODE_PRINTWINDOW_PORQUE_FMT, [FError]);
            end;
            FError := '';
            FCodigo := 0;
          end;
        finally
          SelectObject(DCMemoria, Previo);
        end;
        { Un DIB de 32 bits viene en BGRA, el mismo orden que entrega X11:
          por eso el escritor de PNG es EL MISMO para los dos sistemas. }
        Result := GuardarPNG(ARuta, PByte(Pixeles), FAncho, FAlto, FAncho * 4, 32);
        if not Result then
          FError := MsgFmt(SF_NODE_NO_ESCRIBIR_PNG_FMT, [ARuta]);
      finally
        DeleteObject(Bmp);
      end;
    finally
      DeleteDC(DCMemoria);
    end;
  finally
    ReleaseDC(0, DCPantalla);
  end;
end;

{ Pinta en ADestino, en coordenadas de la captura, cada ventana visible del
  escritorio desde su superficie del DWM (PrintWindow), de abajo arriba en
  orden Z, como las compone el propio escritorio. Devuelve cuantas entraron.
  PrintWindow pinta en el origen del DC que le das, asi que cada ventana pasa
  por un bitmap propio y de ahi a su sitio con un BitBlt memoria a memoria,
  que no tiene nada que negar. }
function TEscritorioWin.ComponerPorVentanas(ADestino: HDC): Integer;
var
  Lista: TArray<TVentanaWin>;
  Motivo: string;
  I: Integer;
  DCV: HDC;
  Info: TBitmapInfo;
  Bmp, Previo: HBITMAP;
  Pix: Pointer;
begin
  Result := 0;
  Motivo := FError;          { Ventanas lo limpia y aqui aun hace falta }
  Lista := Ventanas;
  FError := Motivo;
  DCV := CreateCompatibleDC(ADestino);
  if DCV = 0 then
    Exit;
  try
    for I := High(Lista) downto 0 do
    begin
      FillChar(Info, SizeOf(Info), 0);
      Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
      Info.bmiHeader.biWidth := Lista[I].Entera.Width;
      Info.bmiHeader.biHeight := -Lista[I].Entera.Height;
      Info.bmiHeader.biPlanes := 1;
      Info.bmiHeader.biBitCount := 32;
      Info.bmiHeader.biCompression := BI_RGB;
      Pix := nil;
      Bmp := CreateDIBSection(DCV, Info, DIB_RGB_COLORS, Pix, 0, 0);
      if Bmp = 0 then
        Continue;
      try
        Previo := SelectObject(DCV, Bmp);
        try
          { PrintWindow pinta la ventana ENTERA; a su sitio va solo lo que
            se ve, sin la franja de su borde invisible }
          if PrintWindow(Lista[I].Handle, DCV, PW_RENDERFULLCONTENT) and
             BitBlt(ADestino, Lista[I].X, Lista[I].Y, Lista[I].Ancho,
               Lista[I].Alto, DCV, Lista[I].X - Lista[I].Entera.Left,
               Lista[I].Y - Lista[I].Entera.Top, SRCCOPY) then
            Inc(Result);
        finally
          SelectObject(DCV, Previo);
        end;
      finally
        DeleteObject(Bmp);
      end;
    end;
  finally
    DeleteDC(DCV);
  end;
end;

function TEscritorioWin.EnviarEntradas(var AEntradas: array of TInput): Boolean;
var
  Enviadas: UINT;
  Cod: DWORD;
  Fallo: string;
begin
  if Length(AEntradas) = 0 then
    Exit(False);
  Enviadas := SendInput(Length(AEntradas), AEntradas[0], SizeOf(TInput));
  Result := Enviadas = UINT(Length(AEntradas));
  if not Result then
  begin
    Cod := GetLastError;   { antes de formatear nada: FormatMessage lo pisa }
    FError := MsgFmt(SF_NODE_SISTEMA_ACEPTO_ENTRADAS_FMT,
      [Enviadas, Length(AEntradas), SysErrorMessage(Cod)]);
    { Ninguna aceptada, Acceso denegado, en una sesion REMOTA: lo que pedir
      va en la negativa (B14 de la 1.28; medido el 6-nov-2026, ver
      EstadoDelEscritorio). Desconectada (el juez, WTSConnectState): que se
      reconecte. Conectada y con el escritorio de entrada normal (no el
      seguro de un UAC o del bloqueo): su ventana esta minimizada en la
      maquina del operador. }
    if (Enviadas = 0) and (Cod = ERROR_ACCESS_DENIED) and
       (GetSystemMetrics(SM_REMOTESESSION) <> 0) then
    begin
      if SesionDesconectada then
        FError := FError + MsgText(SF_NODE_SESION_REMOTA_DESCONECTADA)
      else if SameText(NombreDelEscritorioDeEntrada(Fallo), 'Default') then
        FError := FError + MsgText(SF_NODE_SESION_REMOTA_SIN_PINTAR);
    end;
  end;
end;

function TEscritorioWin.Absolutas(AX, AY: Integer; out AAbsX, AAbsY: Integer): Boolean;
begin
  AAbsX := 0;
  AAbsY := 0;
  Result := (AX >= 0) and (AY >= 0) and (AX < FAncho) and (AY < FAlto);
  if not Result then
  begin
    FError := MsgFmt(SF_NODE_PIXEL_FUERA_CAPTURA_FMT, [AX, AY, FAncho, FAlto]);
    Exit;
  end;
  { SendInput habla en un sistema de 0..65535 sobre el escritorio virtual,
    no en pixeles. La conversion es esta y solo esta. }
  AAbsX := Round(AX * 65535 / Max(FAncho - 1, 1));
  AAbsY := Round(AY * 65535 / Max(FAlto - 1, 1));
end;

const
  { mover el raton a un punto absoluto del escritorio virtual }
  MOVER_ABS = MOUSEEVENTF_MOVE or MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_VIRTUALDESK;

function TEscritorioWin.Raton(AAbsX, AAbsY: Integer; AFlags: DWORD): Boolean;
var
  E: array[0..0] of TInput;
begin
  FillChar(E, SizeOf(E), 0);
  E[0].Itype := INPUT_MOUSE;
  E[0].mi.dx := AAbsX;
  E[0].mi.dy := AAbsY;
  E[0].mi.dwFlags := AFlags;
  Result := EnviarEntradas(E);
end;

function TEscritorioWin.Arrastrar(AX1, AY1, AX2, AY2: Integer): Boolean;
const
  { en pasos, como una mano: Windows empieza un arrastre cuando el puntero se
    mueve con el boton abajo, no con un salto }
  PASOS = 20;
var
  X1, Y1, X2, Y2: Integer;
begin
  FError := '';
  Result := False;
  // el destino ANTES de pulsar: fuera de la captura, el boton quedaria abajo
  if not Absolutas(AX1, AY1, X1, Y1) or not Absolutas(AX2, AY2, X2, Y2) then
    Exit;
  if not Raton(X1, Y1, MOVER_ABS) then
    Exit;
  Sleep(120);
  if not Raton(X1, Y1, MOUSEEVENTF_LEFTDOWN) then
    Exit;
  try
    Sleep(150);
    for var I := 1 to PASOS do
    begin
      if not Raton(X1 + Round((X2 - X1) * I / PASOS), Y1 + Round((Y2 - Y1) * I / PASOS), MOVER_ABS) then
        Exit;
      Sleep(15);
    end;
    Sleep(100);
    Result := True;
  finally
    // se suelta SIEMPRE, donde este: un boton abajo dejaria el raton del operador arrastrando
    Raton(0, 0, MOUSEEVENTF_LEFTUP);
  end;
end;

function TEscritorioWin.Pulsar(AX, AY: Integer): Boolean;
var
  E: array[0..2] of TInput;
  I: Integer;
  AbsX, AbsY: Integer;
begin
  FError := '';
  if not Absolutas(AX, AY, AbsX, AbsY) then
    Exit(False);
  FillChar(E, SizeOf(E), 0);
  for I := 0 to High(E) do
    E[I].Itype := INPUT_MOUSE;
  E[0].mi.dx := AbsX;
  E[0].mi.dy := AbsY;
  E[0].mi.dwFlags := MOVER_ABS;
  E[1].mi.dwFlags := MOUSEEVENTF_LEFTDOWN;
  E[2].mi.dwFlags := MOUSEEVENTF_LEFTUP;
  Result := EnviarEntradas(E);
end;

function TEscritorioWin.Escribir(const ATexto: string): Boolean;
var
  E: TArray<TInput>;
  I, N: Integer;
begin
  FError := '';
  if ATexto = '' then
    Exit(True);
  { Una pulsacion Unicode por unidad UTF-16: asi entran acentos y emojis sin
    depender de la distribucion de teclado que tenga el operador. Un salto de
    linea es la tecla Intro (VK_RETURN), la que pulsa una persona: un caracter
    13 Unicode llega como VK_PACKET, y lo que espera la tecla (el boton por
    defecto de un dialogo, un OnKeyDown) no lo ve. El servidor deja todo salto
    en LF (J10 de la 1.28). }
  SetLength(E, Length(ATexto) * 2);
  N := 0;
  for I := 1 to Length(ATexto) do
  begin
    E[N].Itype := INPUT_KEYBOARD;
    E[N].ki.time := 0;
    E[N].ki.dwExtraInfo := 0;
    if ATexto[I] = #10 then
    begin
      E[N].ki.wVk := VK_RETURN;
      E[N].ki.wScan := 0;
      E[N].ki.dwFlags := 0;
      E[N + 1] := E[N];
      E[N + 1].ki.dwFlags := KEYEVENTF_KEYUP;
    end
    else
    begin
      E[N].ki.wVk := 0;
      E[N].ki.wScan := Word(ATexto[I]);
      E[N].ki.dwFlags := KEYEVENTF_UNICODE;
      E[N + 1] := E[N];
      E[N + 1].ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
    end;
    Inc(N, 2);
  end;
  Result := EnviarEntradas(E);
end;

function TEscritorioWin.Combinacion(const ATeclas: array of Word): Boolean;
var
  E: TArray<TInput>;
  I, N, Total: Integer;
begin
  FError := '';
  Total := Length(ATeclas);
  if Total = 0 then
    Exit(False);
  SetLength(E, Total * 2);
  N := 0;
  for I := 0 to Total - 1 do          { se pulsan en orden... }
  begin
    E[N].Itype := INPUT_KEYBOARD;
    E[N].ki.wVk := ATeclas[I];
    E[N].ki.wScan := 0;
    E[N].ki.dwFlags := 0;
    E[N].ki.time := 0;
    E[N].ki.dwExtraInfo := 0;
    Inc(N);
  end;
  for I := Total - 1 downto 0 do      { ...y se sueltan al reves }
  begin
    E[N].Itype := INPUT_KEYBOARD;
    E[N].ki.wVk := ATeclas[I];
    E[N].ki.wScan := 0;
    E[N].ki.dwFlags := KEYEVENTF_KEYUP;
    E[N].ki.time := 0;
    E[N].ki.dwExtraInfo := 0;
    Inc(N);
  end;
  Result := EnviarEntradas(E);
end;

{ Una ventana "visible" que en realidad no esta en el escritorio: minimizada
  (su rectangulo vive en -32000), ENCAPOTADA por el DWM (las apps de la
  tienda y las de otro escritorio virtual quedan IsWindowVisible pero no se
  ven) o una SUPERPOSICION: transparente a los clics (WS_EX_TRANSPARENT, el
  cursor de un agente) o que nunca toma el foco ni sale en la barra
  (WS_EX_NOACTIVATE + WS_EX_TOOLWINDOW: la de NVIDIA GeForce, medida
  2026-09-22 en un Windows remoto con ex=8080080). No se pueden pulsar, al
  listarlas despistan, y en la composicion de respaldo, al ir por encima de
  todo en Z, la taparian entera. Un solo sitio decide que es "estar en el
  escritorio", para la lista y para la captura. }
function NoEstaEnElEscritorio(AHandle: HWND): Boolean;
var
  Tapada: DWORD;
  Ex: NativeInt;
begin
  if IsIconic(AHandle) then
    Exit(True);
  Ex := GetWindowLongPtr(AHandle, GWL_EXSTYLE);
  if (Ex and WS_EX_TRANSPARENT) <> 0 then
    Exit(True);
  if ((Ex and WS_EX_NOACTIVATE) <> 0) and ((Ex and WS_EX_TOOLWINDOW) <> 0) then
    Exit(True);
  Tapada := 0;
  { Winapi.Dwmapi la carga en diferido: en un Windows sin DWM la llamada
    fallaria y se sigue como si no estuviera encapotada. }
  try
    Result := Succeeded(DwmGetWindowAttribute(AHandle, DWMWA_CLOAKED, @Tapada,
      SizeOf(Tapada))) and (Tapada <> 0);
  except
    Result := False;
  end;
end;

function RecogerVentana(AHandle: HWND; ADato: LPARAM): BOOL; stdcall;
var
  Buf: array[0..511] of Char;
  R, Vista: TRect;
  V: TVentanaWin;
begin
  Result := True;
  if not IsWindowVisible(AHandle) or NoEstaEnElEscritorio(AHandle) then
    Exit;
  if GetWindowText(AHandle, Buf, Length(Buf)) <= 0 then
    Exit;
  if not GetWindowRect(AHandle, R) then
    Exit;
  if (R.Right - R.Left <= 0) or (R.Bottom - R.Top <= 0) then
    Exit;
  V.Handle := AHandle;
  V.Titulo := Buf;
  { Lo que SE VE: desde Vista el rectangulo de una ventana incluye su borde
    invisible, el de redimensionar, y una maximizada salia en (-9,-9) y 18
    px mas ancha que la pantalla (medido el 5-nov-2026 a 125%). El juez es
    el DWM, DWMWA_EXTENDED_FRAME_BOUNDS, en pixeles fisicos como todo en
    este nodo (consciente de DPI por monitor); sin DWM, el rectangulo
    entero. Gemelo de _GTK_FRAME_EXTENTS en Mld.X11. }
  Vista := R;
  try
    if not Succeeded(DwmGetWindowAttribute(AHandle, DWMWA_EXTENDED_FRAME_BOUNDS,
         @Vista, SizeOf(Vista))) or not IntersectRect(Vista, Vista, R) then
      Vista := R;
  except
    Vista := R;
  end;
  { En coordenadas de LA CAPTURA: el escritorio virtual puede empezar en
    negativo si hay un monitor a la izquierda del principal. }
  V.Entera := R;
  V.Entera.Offset(-GIzq, -GSup);
  V.X := Vista.Left - GIzq;
  V.Y := Vista.Top - GSup;
  V.Ancho := Vista.Right - Vista.Left;
  V.Alto := Vista.Bottom - Vista.Top;
  GLista.Add(V);
end;

function TEscritorioWin.Ventanas: TArray<TVentanaWin>;
begin
  FError := '';
  GLista := TListaVentanas.Create;
  try
    GIzq := FIzq;
    GSup := FSup;
    EnumWindows(@RecogerVentana, 0);
    Result := GLista.ToArray;
  finally
    FreeAndNil(GLista);
  end;
end;

{$ENDIF}

end.
