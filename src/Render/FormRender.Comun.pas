unit FormRender.Comun;

{ Lo COMUN a los dos renderizadores de forms (DelphiFormRenderVcl y
  DelphiFormRenderFmx): la linea de comandos, la respuesta (el protocolo de
  FormRenderProtocolo.inc, UN escritor), el vigia del tiempo limite, los
  paquetes de diseno del IDE cargados fuera del IDE, el lector de .dfm/.fmx
  con frames inline y forms heredadas, el estado de vista y los iconos de
  los no visuales. Sin Vcl.* ni FMX.*: lo que pinta vive en cada renderizador.

  Lo que pinta cada uno ES lo que ensena el designer del IDE, no la
  aplicacion en marcha: la form se crea en modo diseno (csDesigning), los
  eventos no existen y nada sale al escritorio del servidor (RenderForm,
  medidas del 6-oct-2026 en el vault). }

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, System.Generics.Collections;

const
  {$I FormRenderProtocolo.inc}

type
  { Un rechazo nuestro (estado, estilo, argumentos): su mensaje ya lleva la
    etiqueta del catalogo y sale tal cual en ERROR=, sin la clase delante }
  ERender = class(Exception);

  TPeticion = record
    Path: string;        // --path <dfm|fmx>
    Salida: string;      // --out <png>
    Estilo: string;      // --style <fichero> | <plataforma> | none | '' (lo que traiga el fichero)
    Componente: string;  // --component <Nombre>: RECT= de ese componente
    Bds: string;         // --bds 37.0
    Paquetes: string;    // --packages auto | none | all
    Fidelidad: string;   // --fidelity auto | window | print (VCL)
    Raiz: string;        // --root auto | form | frame
    Estados: TArray<string>; // --state Comp.Prop=Valor (repetible)
    NoVisuales: Boolean; // --nonvisual on|off (off, como la tool: la imagen es el form como se vera; 3.4)
    TiempoMs: Integer;   // --timeout <ms>
    Verbose: Boolean;    // --verbose: trazas '#'
  end;

  { El lector comun de un .dfm/.fmx, texto o binario, sobre una instancia ya
    creada en modo diseno. Clases que no existen -> sustituto del framework
    con el nombre de la clase; eventos ignorados; errores del lector apuntados
    y saltados; un frame 'inline' se crea con la clase base del framework y
    se le lee su propio fichero (buscado por el nombre de su clase en la
    carpeta de la form); una form 'inherited' se lee tras sus ancestros (la
    cadena sale del .pas: 'TX = class(TY)'). }
  TCargador = class
  private
    FSustituidas: TStringList;
    FIgnoradas: TStringList;
    FAvisos: TStringList;
    FEventos: Integer;
    FCarpeta: string;
    FDesconocida: string;
    FFramePendiente: string;      // el fichero del frame inline que toca crear
    FPorClase: TDictionary<string, string>; // clase raiz -> fichero, en la carpeta
    procedure FindComponentClass(Reader: TReader; const ClassName: string; var ComponentClass: TComponentClass);
    procedure CreateComponent(Reader: TReader; ComponentClass: TComponentClass; var Component: TComponent);
    procedure FindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
    procedure ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
    procedure AncestorNotFound(Reader: TReader; const ComponentName: string;
      ComponentClass: TPersistentClass; var Component: TComponent);
    procedure IndexaCarpeta(const ACarpeta: string);
  protected
    { Cada framework pone su sustituto (un panel/rectangulo con el nombre de
      la clase que falta) y su clase de frame }
    function ClaseSustituto: TComponentClass; virtual; abstract;
    function CreaSustituto(AOwner: TComponent; const AClase: string): TComponent; virtual; abstract;
    function ClaseFrame: TComponentClass; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    { El fichero de la carpeta cuya raiz es de la clase AClase ('' si no hay) }
    function FicheroDeClase(const ACarpeta, AClase: string): string;
    { Lee AFichero (y antes sus ancestros, si su raiz es 'inherited') en AInstancia }
    procedure Lee(const AFichero: string; AInstancia: TComponent);
    { Solo ese fichero, sin ancestros }
    procedure LeeUno(const AFichero: string; AInstancia: TComponent);
    property Sustituidas: TStringList read FSustituidas;
    property Ignoradas: TStringList read FIgnoradas;
    property Avisos: TStringList read FAvisos;
    property Eventos: Integer read FEventos;
  end;

  { La primera linea de un .dfm/.fmx de texto (o la cabecera de uno binario):
    palabra (object|inherited|inline), nombre y clase de la raiz }
  TCabecera = record
    Palabra, Nombre, Clase: string;
    Binario: Boolean;
  end;

var
  GPeticion: TPeticion;

{ Linea de comandos -> GPeticion. '' si bien; si no, el error de uso. }
function ParseaArgumentos(out AUso: string): string;
function TextoDeUso(const AExe: string): string;

{ EL escritor del protocolo: una linea CLAVE=valor en stdout }
procedure Responde(const AClave, AValor: string);
procedure Aviso(const S: string);
procedure Traza(const S: string);      // '# ...' solo con --verbose
procedure SinDesbordar(var S: string); // una linea: sin saltos

{ El vigia: pasado AMs el proceso escribe ERROR=timeout y se mata con FR_RC_TIMEOUT }
procedure ArrancaVigia(AMs: Integer);
procedure ParaVigia;

{ Un pixel = una unidad del dfm: el proceso se declara ajeno al DPI ANTES de
  crear ventana alguna; devuelve el DPI que ve. }
function DeclaraAjenoAlDpi: Integer;

function SesionActual: Cardinal;
{ csDesigning en un componente recien creado (y en lo que se le inserte) }
procedure PonEnDiseno(AComp: TComponent);
function Cabecera(const AFichero: string): TCabecera;
{ Un ENLACE (symlink, punto de reparse): no se lee. El servidor paso por su
  puerta el fichero PEDIDO, por su ruta real; los hermanos que este ayudante
  lee por su cuenta (los .dfm/.fmx de la carpeta, para frames y ancestros, y
  el .pas) no, y uno enlazado sacaria al PNG algo de fuera de las raices
  (revision de Fable, 7-oct-2026). El mismo criterio que Lsp.Guard.EsEnlace:
  el ayudante no enlaza el guard del servidor. }
function EsEnlace(const AFichero: string): Boolean;
{ 'TX = class(TY' en el .pas hermano de AFichero: TY ('' si no hay) }
function AncestroDeClase(const AFichero, AClase: string): string;
{ Es un frame segun el .pas: ancestro TFrame/TCustomFrame, o lo dice --root }
function EsFrame(const AFichero, AClase: string): Boolean;

{ Los Known Packages del IDE de 32 bits (HKCU\...\BDS\<Bds>\Known Packages),
  con el Register de cada unidad llamado como lo hace el IDE; los expertos se
  saltan. ACargados/AConocidos para PACKAGES=. Solo carga una vez. }
procedure CargaPaquetesDelIde(const ABds: string; out ACargados, AConocidos: Integer);
function RaizDelIde(const ABds: string): string;
function PaquetesCargados: Boolean;

{ Registro de clases como lo haria RegisterComponents }
procedure Apunta(const AClases: array of TComponentClass);
function ClaseRegistrada(const AClase: string): Boolean;

{ El componente de ARaiz que nombra ARuta como lee la RTL una referencia
  (FindNestedComponent: Marco1.LblAviso, dentro de un frame en linea), y
  tambien con el nombre de la raiz delante (FrameX.PanelFrame en un frame
  suelto) o la raiz misma; nil si no hay. UN lector para component= y
  state= (segunda revision de la 1.17.0: el estado con la raiz delante no
  llegaba en un frame suelto). }
function ComponenteDeRuta(ARaiz: TComponent; const ARuta: string): TComponent;

{ Estado de vista "Comp.Prop=Valor" por RTTI sobre un componente de ARoot;
  tkClass resuelve Valor como nombre de componente. Comp y Valor se resuelven
  como lee la RTL una referencia (ComponenteDeRuta): Marco1.LblAviso, uno
  dentro de un frame inline. Lanza si no existe. }
procedure AplicaEstado(ARoot: TComponent; const AEspec: string);

{ El icono de una clase como lo tiene el paquete de diseno: RCDATA
  '<CLASE>128_PNG' (el IDE actual) en los paquetes cargados o, si no, en los
  Known Packages abiertos como datos. PNG en bytes; False si no hay. }
function IconoPngDeClase(const AClase: string; out APng: TBytes): Boolean;

{ Left/Top de un no visual, como los guarda el dfm (DesignInfo) }
function PosicionDeNoVisual(AComp: TComponent): TPoint;

{ Los no visuales de ARaiz como los ensena el designer: componentes suyos
  (no los de un frame metido) que no son un control del framework
  (AClaseControl: el TControl de la VCL o el de FMX), y con posicion de
  diseno: DesignInfo distinto de cero (un item de menu o una columna no la
  tienen y el designer no los ensena sueltos). UN criterio para dibujarlos y
  para listarlos: estaba escrito en los dos renderizadores. }
function NoVisualesDe(ARaiz: TComponent; AClaseControl: TClass): TArray<TComponent>;
{ 'Nombre:Clase,Nombre:Clase' para NONVISUALS= }
function ListaDeNoVisuales(const ALista: TArray<TComponent>): string;

implementation

uses
  System.TypInfo, System.Win.Registry, System.IOUtils, System.RegularExpressions,
  System.Actions, System.Variants, System.SyncObjs, System.Diagnostics,
  FormRender.Textos,
  Lsp.DesignerForma, // la forma del fichero, la misma que lee el servidor
  Lsp.Pascal;        // EL lexico Pascal: que es codigo y que comentario

type
  TComponentCrack = class(TComponent);

var
  GVerbose: Boolean = False;
  GVigia: TThread = nil;
  GVigiaPara: TEvent = nil;
  GRegistradas: TDictionary<string, Boolean>;
  GModulos: TList<HMODULE>;          // paquetes cargados de verdad (su codigo corre)
  GModulosDatos: TDictionary<string, HMODULE>; // paquetes abiertos solo como datos (iconos)
  GConocidos: TStringList;           // rutas de los Known Packages
  GPaquetesCargados: Boolean = False;
  GBdsRoot: string;

{ ---- respuesta ---- }

procedure SinDesbordar(var S: string);
begin
  S := S.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
end;

procedure Responde(const AClave, AValor: string);
var
  V: string;
begin
  V := AValor;
  SinDesbordar(V);
  Writeln(AClave + V);
  Flush(Output);
end;

procedure Aviso(const S: string);
begin
  Responde(FR_WARNING, S);
end;

procedure Traza(const S: string);
begin
  if GVerbose then
  begin
    Writeln('# ' + S);
    Flush(Output);
  end;
end;

{ ---- argumentos ---- }

function TextoDeUso(const AExe: string): string;
begin
  Result := MsgFmt(SF_RENDER_USO_FMT, [AExe]);
end;

function ParseaArgumentos(out AUso: string): string;
var
  I: Integer;
  P, V: string;

  function Valor: string;
  begin
    if I >= ParamCount then
      raise ERender.Create(MsgFmt(SR_RENDER_ARG_SIN_VALOR_FMT, [P]));
    Inc(I);
    Result := ParamStr(I);
  end;

  function Entre(const AValor: string; const AOpciones: array of string): string;
  begin
    for var O in AOpciones do
      if SameText(O, AValor) then
        Exit(O);
    raise ERender.Create(MsgFmt(SR_RENDER_ARG_FUERA_FMT, [P, AValor, string.Join('|', AOpciones)]));
  end;

begin
  Result := '';
  AUso := TextoDeUso(ExtractFileName(ParamStr(0)));
  GPeticion := Default(TPeticion);
  GPeticion.Bds := '37.0';
  GPeticion.Paquetes := 'auto';
  GPeticion.Fidelidad := 'auto';
  GPeticion.Raiz := 'auto';
  // UN solo defecto, el de delphi_designer: off (era on, como el designer, y
  // la tool off - dos defectos para lo mismo: 3.4 de la 1.18.0)
  GPeticion.NoVisuales := False;
  GPeticion.TiempoMs := 60000;
  try
    I := 1;
    while I <= ParamCount do
    begin
      P := ParamStr(I);
      if P = '--path' then GPeticion.Path := Valor
      else if P = '--out' then GPeticion.Salida := Valor
      else if P = '--style' then GPeticion.Estilo := Valor
      else if P = '--component' then GPeticion.Componente := Valor
      else if P = '--bds' then GPeticion.Bds := Valor
      else if P = '--packages' then GPeticion.Paquetes := Entre(Valor, ['auto', 'none', 'all'])
      else if P = '--fidelity' then GPeticion.Fidelidad := Entre(Valor, ['auto', 'window', 'print'])
      else if P = '--root' then GPeticion.Raiz := Entre(Valor, ['auto', 'form', 'frame'])
      else if P = '--state' then GPeticion.Estados := GPeticion.Estados + [Valor]
      else if P = '--nonvisual' then
      begin
        V := Entre(Valor, ['on', 'off', 'true', 'false', '1', '0']);
        GPeticion.NoVisuales := (V = 'on') or (V = 'true') or (V = '1');
      end
      else if P = '--timeout' then GPeticion.TiempoMs := StrToInt(Valor)
      else if P = '--verbose' then GPeticion.Verbose := True
      else
        raise ERender.Create(MsgFmt(SR_RENDER_ARG_DESCONOCIDO_FMT, [P]));
      Inc(I);
    end;
    if GPeticion.Path = '' then
      raise ERender.Create(MsgFmt(SR_RENDER_FALTA_ARG_FMT, ['--path']));
    if GPeticion.Salida = '' then
      raise ERender.Create(MsgFmt(SR_RENDER_FALTA_ARG_FMT, ['--out']));
    if not TFile.Exists(GPeticion.Path) then
      raise ERender.Create(MsgFmt(SR_RENDER_NO_EXISTE_FMT, [GPeticion.Path]));
    for var E in GPeticion.Estados do
      if (E.IndexOf('=') < 1) or (E.IndexOf('.') < 1) or (E.IndexOf('.') > E.IndexOf('=')) then
        raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_FORMA_FMT, [E]));
    GVerbose := GPeticion.Verbose;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

{ ---- vigia ---- }

type
  TVigia = class(TThread)
  private
    FMs: Integer;
  protected
    procedure Execute; override;
  end;

procedure TVigia.Execute;
begin
  if GVigiaPara.WaitFor(FMs) = wrTimeout then
  begin
    Responde(FR_ERROR, MsgFmt(SR_RENDER_TIEMPO_FMT, [FMs]));
    TerminateProcess(GetCurrentProcess, FR_RC_TIMEOUT);
  end;
end;

procedure ArrancaVigia(AMs: Integer);
begin
  if AMs <= 0 then
    Exit;
  GVigiaPara := TEvent.Create(nil, True, False, '');
  var V := TVigia.Create(True);
  V.FMs := AMs;
  V.FreeOnTerminate := False;
  GVigia := V;
  V.Start;
end;

procedure ParaVigia;
begin
  if GVigiaPara <> nil then
    GVigiaPara.SetEvent;
  if GVigia <> nil then
  begin
    GVigia.WaitFor;
    FreeAndNil(GVigia);
  end;
  FreeAndNil(GVigiaPara);
end;

{ ---- DPI y sesion ---- }

const
  DPI_AWARENESS_CONTEXT_UNAWARE_ = THandle(-1);

function DeclaraAjenoAlDpi: Integer;
type
  TSetCtx = function(ctx: THandle): BOOL; stdcall;
var
  U: HMODULE;
  P: TSetCtx;
  DC: HDC;
begin
  U := GetModuleHandle(user32);
  P := GetProcAddress(U, 'SetProcessDpiAwarenessContext');
  if Assigned(P) then
    P(DPI_AWARENESS_CONTEXT_UNAWARE_);
  DC := GetDC(0);
  try
    Result := GetDeviceCaps(DC, LOGPIXELSX);
  finally
    ReleaseDC(0, DC);
  end;
end;

procedure PonEnDiseno(AComp: TComponent);
begin
  TComponentCrack(AComp).SetDesigning(True);
end;

function SesionActual: Cardinal;
begin
  if not ProcessIdToSessionId(GetCurrentProcessId, Result) then
    Result := High(Cardinal);
end;

{ ---- cabecera, ancestros, frames ---- }

function Cabecera(const AFichero: string): TCabecera;
var
  Bytes: TBytes;
  Lineas: TStringList;
begin
  Result := Default(TCabecera);
  Lineas := TStringList.Create;
  try
    Bytes := TFile.ReadAllBytes(AFichero);
    // la forma por el lector de la casa (Lsp.DesignerForma): el binario del
    // IDE lleva cabecera de recurso, y un texto UTF-16 empieza por FF FE
    if DesignerShapeOf(Bytes) <> dsText then
    begin
      Result.Binario := True;
      // EL conversor de la casa, el del servidor (P10 de la segunda revision
      // de la 1.17.0: este ayudante tenia el suyo)
      Lineas.Text := DesignerBinarioATexto(Bytes);
    end
    else
      Lineas.LoadFromFile(AFichero);
    // EL lector de la raiz (Lsp.DesignerForma), el del servidor: la primera
    // linea no vacia, si es de objeto - aqui se tomaba la primera linea de
    // objeto de CUALQUIER sitio, la de uno anidado tambien (P10); y por
    // LineaDeObjeto: con \w un nombre con acento se cortaba (1.17.0)
    LineaRaizDeDesigner(Lineas.ToStringArray, Result.Palabra, Result.Nombre, Result.Clase);
  finally
    Lineas.Free;
  end;
end;

function AncestroDeClase(const AFichero, AClase: string): string;
var
  Pas: string;
  M: TMatch;
begin
  Result := '';
  Pas := UnidadDeDesigner(AFichero);
  if not TFile.Exists(Pas) or EsEnlace(Pas) then
    Exit;
  // 'TX = class(TY)', tambien 'class abstract(...)' y con la unidad delante
  // (Unidad.TY); el nombre por lo que lo rodea, no por \w (ASCII). El lector
  // de clases del servidor (Lsp.PascalDecl) no se enlaza aqui; la raiz, form
  // o frame, ya la manda el servidor con --root (revision de la 1.17.0). Sobre
  // el CODIGO solo (CodigoPascal): una declaracion vieja comentada encima de
  // la buena se tomaba por ella (segunda revision de la 1.17.0)
  M := TRegEx.Match(CodigoPascal(TFile.ReadAllText(Pas)), '\b' + TRegEx.Escape(AClase) +
    '\s*=\s*class(?:\s+(?:abstract|sealed))?\s*\(\s*([^\s,)]+)', [roIgnoreCase]);
  if M.Success then
    Result := M.Groups[1].Value.Substring(M.Groups[1].Value.LastIndexOf('.') + 1);
end;

function EsFrame(const AFichero, AClase: string): Boolean;
var
  A: string;
begin
  if GPeticion.Raiz = 'frame' then
    Exit(True);
  if GPeticion.Raiz = 'form' then
    Exit(False);
  A := AncestroDeClase(AFichero, AClase);
  Result := SameText(A, 'TFrame') or SameText(A, 'TCustomFrame') or A.ToLower.Contains('frame');
end;

{ ---- paquetes del IDE ---- }

var
  GPaqueteActual: string;

procedure Apunta(const AClases: array of TComponentClass);
begin
  for var C in AClases do
  begin
    if (C = nil) or GRegistradas.ContainsKey(C.ClassName) then
      Continue;
    try
      System.Classes.RegisterClass(C);
      GRegistradas.Add(C.ClassName, True);
    except
      on E: Exception do
        Traza(Format('%s: RegisterClass(%s): %s', [GPaqueteActual, C.ClassName, E.Message]));
    end;
  end;
end;

function ClaseRegistrada(const AClase: string): Boolean;
begin
  Result := GetClass(AClase) <> nil;
end;

procedure ApuntaComponentes(const Page: string; const ComponentClasses: array of TComponentClass);
begin
  Apunta(ComponentClasses);
end;

procedure ApuntaSinIcono(const ComponentClasses: array of TComponentClass);
begin
  Apunta(ComponentClasses);
end;

procedure ApuntaNoActiveX(const ComponentClasses: array of TComponentClass; AxRegType: TActiveXRegType);
begin
end;

procedure ApuntaAcciones(const CategoryName: string; const AClasses: array of TBasicActionClass;
  Resource: TComponentClass);
begin
  for var C in AClasses do
    if (C <> nil) and not GRegistradas.ContainsKey(C.ClassName) then
    begin
      System.Classes.RegisterClass(C);
      GRegistradas.Add(C.ClassName, True);
    end;
end;

procedure DesapuntaAcciones(const AClasses: array of TBasicActionClass);
begin
end;

function RaizDelIde(const ABds: string): string;
var
  Reg: TRegistry;
begin
  if GBdsRoot <> '' then
    Exit(GBdsRoot);
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS\' + ABds) then
      raise ERender.Create(MsgFmt(SR_RENDER_SIN_IDE_FMT, [ABds]));
    GBdsRoot := IncludeTrailingPathDelimiter(Reg.ReadString('RootDir'));
  finally
    Reg.Free;
  end;
  Result := GBdsRoot;
end;

function ExpandeMacros(const S, ARoot: string): string;
begin
  Result := StringReplace(S, '$(BDSCOMMONDIR)',
    TPath.Combine(TPath.GetSharedDocumentsPath, 'Embarcadero\Studio\' + GPeticion.Bds), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDSBIN)', ARoot + 'bin', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDS)', ExcludeTrailingPathDelimiter(ARoot), [rfReplaceAll, rfIgnoreCase]);
end;

procedure LeeConocidos(const ABds: string);
var
  Reg: TRegistry;
  Nombres: TStringList;
  Root: string;
begin
  if GConocidos <> nil then
    Exit;
  GConocidos := TStringList.Create;
  Root := RaizDelIde(ABds);
  Nombres := TStringList.Create;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS\' + ABds + '\Known Packages') then
    begin
      Reg.GetValueNames(Nombres);
      Reg.CloseKey;
    end;
    for var N in Nombres do
      GConocidos.Add(ExpandeMacros(N, Root));
  finally
    Reg.Free;
    Nombres.Free;
  end;
end;

{ Lo que hace el IDE tras LoadPackage y nadie mas hace: llamar al Register de
  cada unidad del paquete por su simbolo decorado '@Unidad@Register$qqrv'
  (los puntos de la unidad son '@', cada tramo Mayuscula-minusculas). }
procedure ApuntaUnidad(const Name: string; NameType: TNameType; Flags: Byte; Param: Pointer);
begin
  if NameType = ntContainsUnit then
    TStringList(Param).Add(Name);
end;

function NombreDecorado(const AUnidad: string): string;
begin
  Result := '@';
  for var Seg in AUnidad.Split(['.']) do
    if Seg <> '' then
      Result := Result + Seg.Substring(0, 1).ToUpper + Seg.Substring(1).ToLower + '@';
  Result := Result + 'Register$qqrv';
end;

procedure LlamaRegisters(H: HMODULE);
var
  Unidades: TStringList;
  Flags: Integer;
  P: Pointer;
begin
  Unidades := TStringList.Create;
  try
    GetPackageInfo(H, Unidades, Flags, ApuntaUnidad);
    for var U in Unidades do
    begin
      P := GetProcAddress(H, PAnsiChar(AnsiString(NombreDecorado(U))));
      if P = nil then
        Continue;
      try
        TProcedure(P)();
      except
        on E: Exception do
          Traza(Format('%s: %s.Register: %s: %s', [GPaqueteActual, U, E.ClassName, E.Message]));
      end;
    end;
  finally
    Unidades.Free;
  end;
end;

function PaquetesCargados: Boolean;
begin
  Result := GPaquetesCargados;
end;

procedure CargaPaquetesDelIde(const ABds: string; out ACargados, AConocidos: Integer);
const
  // expertos del IDE: no registran componentes y tocan BorlandIDEServices
  EXPERTOS = '(?i)(ide370|expert|wizard|explorer|visualizer|applet|quickedit|emacsedit|smpedit|mlwiz|netwiz|styledesigner|^svn)';
var
  H: HMODULE;
  Antes: Integer;
  Reloj: TStopwatch;
begin
  ACargados := 0;
  LeeConocidos(ABds);
  AConocidos := GConocidos.Count;
  if GPaquetesCargados then
  begin
    ACargados := GModulos.Count;
    Exit;
  end;
  GPaquetesCargados := True;
  RegisterComponentsProc := ApuntaComponentes;
  RegisterNoIconProc := ApuntaSinIcono;
  RegisterNonActiveXProc := ApuntaNoActiveX;
  RegisterActionsProc := ApuntaAcciones;
  UnRegisterActionsProc := DesapuntaAcciones;
  for var Ruta in GConocidos do
  begin
    if not TFile.Exists(Ruta) then
    begin
      Traza('falta ' + Ruta);
      Continue;
    end;
    if TRegEx.IsMatch(ExtractFileName(Ruta), EXPERTOS) then
      Continue;
    GPaqueteActual := ExtractFileName(Ruta);
    Antes := GRegistradas.Count;
    Reloj := TStopwatch.StartNew;
    try
      H := LoadPackage(Ruta);
      GModulos.Add(H);
      LlamaRegisters(H);
      Inc(ACargados);
      Traza(Format('%s: %d clases, %d ms', [GPaqueteActual, GRegistradas.Count - Antes, Reloj.ElapsedMilliseconds]));
    except
      on E: Exception do
        Traza(Format('%s: no carga: %s: %s', [GPaqueteActual, E.ClassName, E.Message]));
    end;
  end;
end;

{ ---- estado de vista ---- }

function ComponenteDeRuta(ARaiz: TComponent; const ARuta: string): TComponent;
begin
  if (ARaiz.Name <> '') and SameText(ARuta, ARaiz.Name) then
    Exit(ARaiz);
  Result := FindNestedComponent(ARaiz, ARuta);
  if (Result = nil) and (ARaiz.Name <> '') and ARuta.StartsWith(ARaiz.Name + '.', True) then
    Result := FindNestedComponent(ARaiz, ARuta.Substring(Length(ARaiz.Name) + 1));
end;

procedure AplicaEstado(ARoot: TComponent; const AEspec: string);
var
  Comp, Valor, Prop: string;
  Partes: TArray<string>;
  C, Ref: TComponent;
  PI: PPropInfo;
  N64: Int64;
  Entero: Longint;
begin
  Comp := AEspec.Substring(0, AEspec.IndexOf('=')).Trim;
  Valor := AEspec.Substring(AEspec.IndexOf('=') + 1).Trim;
  // el componente es el prefijo MAS LARGO que nombra uno, como lee la RTL una
  // referencia: Marco1.LblAviso.Caption, dentro de un frame inline; lo que
  // sigue es la propiedad (revision de la 1.17.0: no se llegaba a los hijos
  // de un frame)
  Partes := Comp.Split(['.']);
  C := nil;
  for var N := High(Partes) downto 1 do
  begin
    C := ComponenteDeRuta(ARoot, string.Join('.', Partes, 0, N).Trim);
    if C <> nil then
    begin
      Prop := string.Join('.', Partes, N, Length(Partes) - N).Trim;
      Break;
    end;
  end;
  if C = nil then
  begin
    if Comp.Contains('.') then
      Comp := Comp.Substring(0, Comp.LastIndexOf('.')).Trim;
    raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_SIN_COMPONENTE_FMT, [Comp]));
  end;
  PI := GetPropInfo(C, Prop);
  if PI = nil then
    raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_NO_PUBLICA_FMT, [C.ClassName, Prop]));
  if PI.PropType^.Kind = tkClass then
  begin
    Ref := ComponenteDeRuta(ARoot, Valor);
    if Ref = nil then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_SIN_REFERIDO_FMT, [Valor, Comp]));
    SetObjectProp(C, PI, Ref);
  end
  // un entero con NOMBRE (clRed en un TColor, crHandPoint en un TCursor,
  // claRed en un TAlphaColor), como lo lee TReader: el lector que registra
  // su tipo (RegisterIntegerConsts). SetPropValue con el texto salia
  // DSGN-061, EVariantTypeCastError (3.5 de la 1.18.0, Hermes)
  else if (PI.PropType^.Kind in [tkInteger, tkInt64]) and not TryStrToInt64(Valor, N64) and
          Assigned(FindIdentToInt(PI.PropType^)) and FindIdentToInt(PI.PropType^)(Valor, Entero) then
    SetOrdProp(C, PI, Entero)
  else
    SetPropValue(C, Prop, Valor);
end;

{ ---- iconos de los no visuales ---- }

function PosicionDeNoVisual(AComp: TComponent): TPoint;
begin
  Result.X := LongRec(AComp.DesignInfo).Lo;
  Result.Y := LongRec(AComp.DesignInfo).Hi;
end;

function NoVisualesDe(ARaiz: TComponent; AClaseControl: TClass): TArray<TComponent>;
begin
  Result := [];
  for var I := 0 to ARaiz.ComponentCount - 1 do
  begin
    var C := ARaiz.Components[I];
    if C.InheritsFrom(AClaseControl) or (C.Owner <> ARaiz) then
      Continue;
    // sin posicion de diseno Y viviendo DENTRO de otro (un item de menu, una
    // accion, un campo): lo muestra su contenedor. Solo con DesignInfo = 0
    // se saltaba tambien un no visual de la raiz sin Left/Top: ni se dibujaba
    // ni se listaba (3.6 de la 1.18.0, Hermes); va en 0,0, como en el IDE.
    // La raiz como padre cuenta como ninguno: en FMX un no visual de la form
    // tiene la form de Parent (TFmxObject.HasParent es Parent <> nil)
    var Padre := C.GetParentComponent;
    if (C.DesignInfo = 0) and (Padre <> nil) and (Padre <> ARaiz) then
      Continue;
    Result := Result + [C];
  end;
end;

function EsEnlace(const AFichero: string): Boolean;
var
  A: DWORD;
begin
  A := GetFileAttributes(PChar(AFichero));
  Result := (A <> INVALID_FILE_ATTRIBUTES) and ((A and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

function ListaDeNoVisuales(const ALista: TArray<TComponent>): string;
begin
  Result := '';
  for var C in ALista do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + C.Name + ':' + C.ClassName;
  end;
end;

function PngDeModulo(H: HMODULE; const ANombre: string; out APng: TBytes): Boolean;
var
  R: TResourceStream;
begin
  Result := FindResource(H, PChar(ANombre), RT_RCDATA) <> 0;
  if not Result then
    Exit;
  R := TResourceStream.Create(H, ANombre, RT_RCDATA);
  try
    SetLength(APng, R.Size);
    if R.Size > 0 then
      R.ReadBuffer(APng[0], R.Size);
  finally
    R.Free;
  end;
end;

function IconoPngDeClase(const AClase: string; out APng: TBytes): Boolean;
var
  Nombre: string;
  H: HMODULE;
begin
  Nombre := AClase.ToUpper + '128_PNG';
  for var M in GModulos do
    if PngDeModulo(M, Nombre, APng) then
      Exit(True);
  // sin paquetes cargados (una form estandar): los Known Packages como DATOS,
  // nada suyo se ejecuta; se abren una vez y se quedan abiertos
  LeeConocidos(GPeticion.Bds);
  for var Ruta in GConocidos do
  begin
    if not GModulosDatos.TryGetValue(Ruta, H) then
    begin
      H := 0;
      if TFile.Exists(Ruta) then
        H := LoadLibraryEx(PChar(Ruta), 0, LOAD_LIBRARY_AS_DATAFILE);
      GModulosDatos.Add(Ruta, H);
    end;
    if (H <> 0) and PngDeModulo(H, Nombre, APng) then
      Exit(True);
  end;
  Result := False;
end;

{ ---- TCargador ---- }

constructor TCargador.Create;
begin
  inherited;
  FSustituidas := TStringList.Create;
  FSustituidas.Duplicates := dupIgnore;
  FSustituidas.Sorted := True;
  FIgnoradas := TStringList.Create;
  FAvisos := TStringList.Create;
  FPorClase := TDictionary<string, string>.Create;
end;

destructor TCargador.Destroy;
begin
  FPorClase.Free;
  FAvisos.Free;
  FIgnoradas.Free;
  FSustituidas.Free;
  inherited;
end;

procedure TCargador.IndexaCarpeta(const ACarpeta: string);
var
  Ext: string;
begin
  if SameText(FCarpeta, ACarpeta) then
    Exit;
  FCarpeta := ACarpeta;
  FPorClase.Clear;
  Ext := ExtractFileExt(GPeticion.Path);
  for var F in TDirectory.GetFiles(ACarpeta, '*' + Ext) do
  if not EsEnlace(F) then // un hermano enlazado no se lee: ver EsEnlace
  try
    var C := Cabecera(F);
    if (C.Clase <> '') and not FPorClase.ContainsKey(C.Clase.ToUpper) then
      FPorClase.Add(C.Clase.ToUpper, F);
  except
    // un fichero que no se deja leer no es de este renderizador
  end;
end;

function TCargador.FicheroDeClase(const ACarpeta, AClase: string): string;
begin
  IndexaCarpeta(ACarpeta);
  if not FPorClase.TryGetValue(AClase.ToUpper, Result) then
    Result := '';
end;

procedure TCargador.FindComponentClass(Reader: TReader; const ClassName: string;
  var ComponentClass: TComponentClass);
begin
  if ComponentClass <> nil then
    Exit;
  // un frame inline (o una form metida en otra): su fichero esta en la carpeta
  FFramePendiente := FicheroDeClase(ExtractFilePath(GPeticion.Path), ClassName);
  if FFramePendiente <> '' then
  begin
    ComponentClass := ClaseFrame;
    Exit;
  end;
  FDesconocida := ClassName;
  FSustituidas.Add(ClassName);
  ComponentClass := ClaseSustituto;
end;

procedure TCargador.CreateComponent(Reader: TReader; ComponentClass: TComponentClass;
  var Component: TComponent);
var
  Fichero: string;
begin
  if (FFramePendiente <> '') and (ComponentClass = ClaseFrame) then
  begin
    Fichero := FFramePendiente;
    FFramePendiente := '';
    Component := ClaseFrame.Create(Reader.Owner);
    PonEnDiseno(Component);
    // su propio fichero, con sus ancestros; luego el lector exterior aplica
    // los 'inherited' del inline sobre lo que ya tiene. Para eso el lector
    // tiene que buscar los hijos EN el frame (FLookupRoot): solo lo hace si el
    // componente lleva csInline, y cuando lo crea OnCreateComponent el lector
    // no se lo pone (System.Classes 11869-11873: solo en su propio camino).
    Lee(Fichero, Component);
    TComponentCrack(Component).SetInline(True);
    Exit;
  end;
  if ComponentClass = ClaseSustituto then
    Component := CreaSustituto(Reader.Owner, FDesconocida);
end;

procedure TCargador.FindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
begin
  Address := nil;
  Error := False;
  Inc(FEventos);
end;

procedure TCargador.ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
begin
  FIgnoradas.Add(Message);
  Handled := True;
end;

procedure TCargador.AncestorNotFound(Reader: TReader; const ComponentName: string;
  ComponentClass: TPersistentClass; var Component: TComponent);
begin
  // un 'inherited X' sin ancestro cargado: se crea como si fuera 'object'
  Component := nil;
end;

procedure TCargador.LeeUno(const AFichero: string; AInstancia: TComponent);
var
  Texto, Bin: TMemoryStream;
  Reader: TReader;
begin
  Texto := TMemoryStream.Create;
  Bin := TMemoryStream.Create;
  try
    Texto.LoadFromFile(AFichero);
    // texto, flujo TPF0 o el recurso del IDE: el flujo que lee TReader
    DesignerAFlujo(Texto, Bin);
    Bin.Position := 0;
    Reader := TReader.Create(Bin, 4096);
    try
      Reader.OnFindComponentClass := FindComponentClass;
      Reader.OnCreateComponent := CreateComponent;
      Reader.OnFindMethod := FindMethod;
      Reader.OnError := ReaderError;
      Reader.OnAncestorNotFound := AncestorNotFound;
      Reader.ReadRootComponent(AInstancia);
    finally
      Reader.Free;
    end;
  finally
    Bin.Free;
    Texto.Free;
  end;
end;

procedure TCargador.Lee(const AFichero: string; AInstancia: TComponent);
var
  Cab: TCabecera;
  Ancestro, Fichero: string;
  Cadena: TStringList;
begin
  // la cadena de ancestros, del mas lejano al propio fichero
  Cadena := TStringList.Create;
  try
    Cadena.Add(AFichero);
    Cab := Cabecera(AFichero);
    Fichero := AFichero;
    while SameText(Cab.Palabra, 'inherited') do
    begin
      Ancestro := AncestroDeClase(Fichero, Cab.Clase);
      if Ancestro = '' then
      begin
        FAvisos.Add(MsgFmt(SN_RENDER_HEREDA_SIN_PAS_FMT, [ExtractFileName(Fichero)]));
        Break;
      end;
      Fichero := FicheroDeClase(ExtractFilePath(AFichero), Ancestro);
      if Fichero = '' then
      begin
        if not (SameText(Ancestro, 'TForm') or SameText(Ancestro, 'TFrame') or
          SameText(Ancestro, 'TCustomForm') or SameText(Ancestro, 'TDataModule')) then
          FAvisos.Add(MsgFmt(SN_RENDER_ANCESTRO_SIN_FICHERO_FMT, [Ancestro]));
        Break;
      end;
      if Cadena.IndexOf(Fichero) >= 0 then
        Break; // un ciclo no es una cadena
      Cadena.Insert(0, Fichero);
      Cab := Cabecera(Fichero);
    end;
    for var F in Cadena do
      LeeUno(F, AInstancia);
  finally
    Cadena.Free;
  end;
end;

initialization
  GRegistradas := TDictionary<string, Boolean>.Create;
  GModulos := TList<HMODULE>.Create;
  GModulosDatos := TDictionary<string, HMODULE>.Create;

finalization
  GModulosDatos.Free;
  GModulos.Free;
  GRegistradas.Free;
  GConocidos.Free;

end.
