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
  EFrameCiclico = class(ERender);

  TPeticion = record
    Path: string;        // --path <dfm|fmx>
    Salida: string;      // --out <png>
    Estilo: string;      // --style <fichero> | <plataforma> | none | '' (lo que traiga el fichero)
    Componente: string;  // --component <Nombre>: RECT= de ese componente
    Bds: string;         // --bds 37.0
    RaizBds: string;     // --bdsroot: la carpeta del IDE; la dice el servidor, el contenedor no lee el registro
    FicheroPaquetes: string; // --knownfile: los paquetes que puede cargar, una ruta por linea; sin el, ninguno
    Paquetes: string;    // --packages auto | none | all
    Fidelidad: string;   // --fidelity auto | window | print (VCL)
    Raiz: string;        // --root auto | form | frame
    Estados: TArray<string>; // --state Comp.Prop=Valor (repetible)
    NoVisuales: Boolean; // --nonvisual on|off (off, como la tool: la imagen es el form como se vera; 3.4)
    TiempoMs: Integer;   // --timeout <ms>
    // --packagestimeout <ms>: el plazo de la fase de los paquetes del IDE, dentro de lo
    // que espera un cliente; pasado, RENDER-027 en vez de seguir (1.26)
    TiempoPaquetesMs: Integer;
    Verbose: Boolean;    // --verbose: trazas '#'
    // --writeback on: EL JUEZ de lo que guarda el IDE (3.11 de la 1.18.0) -
    // la form cargada como la carga el designer y escrita por TWriter, sin
    // pintar nada (sin --out). Sus hermanos - frames, ancestros - y su .pas, junto
    // a --path: el servidor se lo copia todo a la carpeta de la llamada
    Escribe: Boolean;
    // --dropped <Nombre>: el que se acaba de soltar (insert, set parent=): el
    // juez lo deja como lo deja el disenador al soltarlo (FMX: el ultimo de
    // la lista de tabulacion de su padre, V72)
    Soltado: string;
    // --set Comp.Prop=Valor (repetible), con --writeback: lo que puso el agente,
    // aplicado sobre el form YA CARGADO (AplicaEstado), como el IDE lo pone desde
    // el Inspector. Leido con el form, el componente estaba en csReading y su
    // clase no hacia lo suyo: FMX no sacaba de StyledSettings lo que se cambiaba
    // y el estilo lo tapaba (B2 de la 1.28, medido)
    Puestas: TArray<string>;
    // --convert text|binary: EL conversor del IDE, sin cargar el form (V71):
    // los bytes de --path en la otra forma, escritos en --out
    Convierte: string;
    // --unreadableclasses: la pregunta del servidor al hacer la caja de paquetes:
    // que clases COM no se dejan buscar desde este contenedor (ListaClasesSinLeer)
    ClasesSinLeer: Boolean;
    // --boxes: donde queda cada control (BOX=), sin png: lo pide delphi_designer layout
    Cajas: Boolean;
  end;

  { Donde esta escrito un componente: el fichero que lo nombro y la raiz en la que
    se leia ese fichero (la del form, o la de un frame en linea) }
  TEscritoEn = record
    Fichero: string;
    Raiz: TComponent;
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
    FSinLeer: TStringList;
    FLeidos: TStringList;
    FNoAplicados: TStringList;
    FEventos: Integer;
    FCarpeta: string;
    FDesconocida: string;
    FFramePendiente: string;      // el fichero del frame inline que toca crear
    FFramesEnCurso: TStringList;  // los ficheros de los frames que se estan leyendo, del de fuera al de dentro
    FLeyendo: string;             // el fichero que se esta leyendo, el que nombra las clases
    FClaseFrame: string;          // y la clase con la que lo escribe el fichero
    FPorClase: TDictionary<string, TArray<string>>; // clase raiz -> sus ficheros, en la carpeta
    FNoCargan: TStringList;       // los de la carpeta que el lector del IDE no toma por texto (A28 de la 1.23)
    // lo creado con OTRA clase que la escrita (un sustituto, un frame inline):
    // la escrita, la que el agente conoce (ClaseEscrita)
    FEscritas: TDictionary<TComponent, string>;
    // donde esta escrito cada componente que nombro el lector (OnSetName): lo pide
    // layout para su linea (Hermes, dirigido de la 1.26: line=0 sin fichero)
    FEscritoEn: TDictionary<TComponent, TEscritoEn>;
    FRaizLeyendo: TComponent;     // la instancia en la que se lee FLeyendo
    // el fichero donde nacio la excepcion que aun no se ha dicho: la de un frame
    // llega al OnError del lector de fuera con FLeyendo ya devuelto al de fuera
    FFalloEn: string;
    procedure FindComponentClass(Reader: TReader; const ClassName: string; var ComponentClass: TComponentClass);
    procedure CreateComponent(Reader: TReader; ComponentClass: TComponentClass; var Component: TComponent);
    procedure FindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
    procedure FindComponentInstance(Reader: TReader; const Name: string; var Instance: Pointer);
    procedure ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
    procedure SetName(Reader: TReader; Component: TComponent; var Name: string);
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
    { El fichero de AClase en ACarpeta para quien la nombra (AQuienLaNombra, un
      form; su .pas decide si hay varios). '' si no hay ninguno. }
    function FicheroDeClase(const ACarpeta, AClase, AQuienLaNombra: string): string;
    { Lee AFichero (y antes sus ancestros, si su raiz es 'inherited') en AInstancia }
    procedure Lee(const AFichero: string; AInstancia: TComponent);
    { Solo ese fichero, sin ancestros }
    procedure LeeUno(const AFichero: string; AInstancia: TComponent);
    property Sustituidas: TStringList read FSustituidas;
    property Ignoradas: TStringList read FIgnoradas;
    property Avisos: TStringList read FAvisos;
    { Lo que Lee NO pudo leer y sin lo que leyo el form: un ancestro sin .pas
      que lo diga o sin fichero en la carpeta (PARTIAL=) }
    property SinLeer: TStringList read FSinLeer;
    { Lo que Lee leyo para cargar el form - ancestros, frames, el .pas de la
      cadena -, 'sha256|ruta' (READ=): lo de ESTE cargador, que con
      --packages auto el form se vuelve a leer con otro }
    property Leidos: TStringList read FLeidos;
    { Lo que el lector leyo y NO pudo aplicar (UNAPPLIED=): el nombre de cada
      metodo de un evento (aqui no hay codigo: FindMethod) y cada referencia a
      un componente que no resolvio en el form (OnFindComponentInstance,
      System.Classes DoFixupReferences: la de otro modulo, que no esta
      cargado). El escritor no las escribe, y no es porque el IDE no las
      guarde: el servidor las conserva (1.22.1) }
    property NoAplicados: TStringList read FNoAplicados;
    { El fichero en el que esta escrito AComp ('' si no se sabe) y su ruta en el
      (ARuta: desde la raiz de ese fichero) }
    function EscritoEn(AComp: TComponent; out ARuta: string): string;
    { El fichero en el que paro el lector, si paro sin decirlo ('' si no): NOTLOADED= }
    property ParoEn: string read FFalloEn;
    property Eventos: Integer read FEventos;
    { La clase de AObj como la escribe el fichero, la que el agente conoce:
      la de la cabecera para la raiz ARaiz (que se crea como una form o un
      frame NUESTROS: TFormOculta...), la escrita para un sustituto o un frame
      inline, y la suya para lo demas. Un mensaje que nombraba ClassName
      ensenaba nuestra clase interna (RENDER-012 decia TFormOculta: Hermes,
      test completo de la 1.21.0) }
    function ClaseEscrita(AObj: TObject; ARaiz: TComponent): string;
    { Lee (ancestros incluidos) la RAIZ de la peticion con ANombre, el de la
      cabecera del fichero: el que dicen sus errores y el que se le queda }
    procedure LeeRaiz(const AFichero, ANombre: string; ARaiz: TComponent);
  end;

  { La primera linea de un .dfm/.fmx de texto (o la cabecera de uno binario):
    palabra (object|inherited|inline), nombre y clase de la raiz }
  TCabecera = record
    Palabra, Nombre, Clase: string;
    Binario: Boolean;
    NoLaCargaElIde: Boolean; // no la toma por texto: un UTF-16 o un UTF-32 (A28 de la 1.23)
  end;

var
  GPeticion: TPeticion;

{ Linea de comandos -> GPeticion. '' si bien; si no, el error de uso. }
function ParseaArgumentos(out AUso: string): string;
function TextoDeUso(const AExe: string): string;
{ El arranque de los dos renderizadores: la peticion, lo que no carga ningun form
  (--convert, --unreadableclasses) y el vigia. False = ya se contesto, y el proceso
  sale con ACodigo. }
function ArrancaAyudante(out ACodigo: Integer): Boolean;

{ EL escritor del protocolo: una linea CLAVE=valor en stdout }
procedure Responde(const AClave, AValor: string);
procedure Aviso(const S: string);
procedure Traza(const S: string);      // '# ...' solo con --verbose
procedure SinDesbordar(var S: string); // una linea: sin saltos
{ EL compositor de un mensaje del lector EN PARTES (FormRenderProtocolo.inc,
  FR_PARTES_SEP), partido por EL formato que lo compuso: SPropertyException
  de System.RTLConsts, en el idioma que cargo ESTE proceso (rtl370.de/.fr/.ja
  junto a rtl370.bpl, por el de Windows: medido el 18-oct-2026, "Fehler beim
  Lesen von EditRight.FontColor"). El servidor lo partia con el ingles, y un
  lector aleman no nombraba nada. }
function LecturaEnPartes(const AMensaje: string): string;

{ El vigia: pasado AMs (o --packagestimeout, si sigue cargando los paquetes del IDE)
  el proceso escribe ERROR= (RENDER-007, o RENDER-027) y se mata con FR_RC_TIMEOUT }
procedure ArrancaVigia(AMs: Integer);
procedure ParaVigia;

{ La guarda de ventanas del renderizador: un gancho CBT del hilo principal
  con el que NINGUN cuadro de dialogo nace (la clase '#32770' - MessageBox,
  TaskDialog, los dialogos comunes - y TMessageForm, el de la VCL) y NINGUNA
  ventana se activa. Nada llega al escritorio ni roba el foco, y el codigo
  de un componente que abre un cuadro sigue como si se hubiera aceptado;
  cada cuadro bloqueado se avisa (RENDER-022). Medido el 19-oct-2026: los
  demos de FireDAC de los Samples llevan conexiones activas contra
  definiciones que no existen en el ini de la maquina, y al cargarlos en
  modo diseno FireDAC abria un cuadro MODAL en el escritorio de David - uno
  por lint, robando el foco - y el renderizador se quedaba ahi hasta el
  plazo. Y una ventana de aplicacion de FMX (TFMAppClass) que se vaya a
  crear - la de la copia de FMX del IDE, dentro de la inicializacion de
  dclfmxstd<nnn>, donde ningun gancho nuestro llega - nace ya como tool
  window, sin WS_EX_APPWINDOW y sin activarse: nunca pisa la barra de tareas
  (medido el 19-oct-2026: nacia visible y activada - CreateAppHandle la
  ensena con SW_SHOWNORMAL - y la escondiamos 19 ms despues). }
procedure ArrancaGuardaDeVentanas;
procedure ParaGuardaDeVentanas;

{ Un pixel = una unidad del dfm: el proceso se declara ajeno al DPI ANTES de
  crear ventana alguna; devuelve el DPI que ve. }
function DeclaraAjenoAlDpi: Integer;

function SesionActual: Cardinal;
{ El juez de lo que guarda el IDE: ARaiz, ya cargada en modo diseno, escrita
  por TWriter (WriteComponent + ObjectBinaryToText, lo que hace el IDE al
  guardar) y devuelta linea a linea en WRITTEN= }
procedure EscribeComoElIde(ARaiz: TComponent);
{ --convert: los bytes de --path por EL conversor de la casa
  (Lsp.DesignerForma) en ESTE proceso de 32 bits, el del IDE - el servidor es
  Win64, donde Extended es Double, y un flotante convertido alli perdia sus
  ultimas cifras (V71 de la 1.23.1) -, escritos en --out. Lo que no convierte
  es el contenido: LINE= y NOTLOADED=, con ERROR=. Devuelve el codigo de
  salida. Sin form, sin paquetes y sin ventanas. }
function ConvierteComoElIde: Integer;
{ --unreadableclasses: las clases COM en proceso cuya clave InprocServer32 no
  abre ESTE proceso, UNREADABLECLASS= por cada una. El juez es el propio
  contenedor abriendola, no una lectura de sus permisos. Quien no se deja leer
  esta aqui: CoCreateInstance responderia acceso denegado, aunque la biblioteca
  se lea (medido el 30-oct-2026: 4 de 5181 clases de 32 bits, las de ADO de
  msado15.dll). Sin form, sin paquetes y sin ventanas. }
function ListaClasesSinLeer: Integer;
{ La ruta de AComp como lee la RTL una referencia, desde ARaiz (Marco1.LblAviso, uno
  de dentro de un frame inline; la inversa de ComponenteDeRuta). '' si no tiene nombre:
  lo de dentro de un control, que el form no escribe. }
function RutaDeComponente(ARaiz, AComp: TComponent): string;
{ EL escritor de BOX=, el que lee Lsp.FormRender.LeeRespuestaDeRender }
procedure RespondeCaja(const ARuta, AClase, APadre: string; AX, AY, AAncho, AAlto: Integer; AVisible: Boolean;
  const AContenido, AFichero, AEnFichero, APintada: string);
{ Los escritores de ROOT=, PACKAGES=, RECT=, SIZE= y MS=, los que lee
  Lsp.FormRender.LeeRespuestaDeRender: cada renderizador los escribia a mano, y
  si uno deriva el lector deja los campos vacios sin decir nada (P7 del revisor). }
procedure RespondeRaiz(const ANombre, AClase: string; AEsFrame: Boolean);
procedure RespondePaquetes(ACargados, AConocidos: Integer);
procedure RespondeRect(const ANombre: string; AX, AY, AAncho, AAlto: Integer);
procedure RespondeTamano(AAncho, AAlto: Integer);
procedure RespondeMs(ACarga, APintado: Int64);
{ <x>,<y>,<ancho>,<alto>: EL formato de una medida, el de RECT= y BOX=; lo lee
  Lsp.FormRender.LeeCuatroEnteros }
function MedidasEnTexto(AX, AY, AAncho, AAlto: Integer): string;
{ Lo leido, igual en los dos renderizadores: ROOT=, PACKAGES=, COMPONENTS=, lo del
  cargador (RespondeLoLeido) y NONVISUALS=. AYaLeido se pone en cuanto lo del
  cargador se dijo, para que RespondeFallo no lo repita. }
procedure RespondeLoCargado(ACargador: TCargador; ARaiz: TComponent; AEsFrame: Boolean;
  ACargados, AConocidos: Integer; AClaseControl: TClass; var AYaLeido: Boolean);
{ El final de un render: FIDELITY=, SIZE=, CAPTURE= y MS= }
procedure RespondeElPintado(const AFidelidad: string; AAncho, AAlto: Integer; AMsCarga, AMsPintado: Int64);
{ Lo que el cargador dice de lo leido, igual en los dos renderizadores:
  SUBSTITUTED=, IGNORED=, WARNING=, PARTIAL= y READ= }
procedure RespondeLoLeido(ACargador: TCargador);
{ El fallo de un render, igual en los dos renderizadores: lo que el cargador
  ya habia apuntado (lo que se salto, lo que leyo) sale TAMBIEN cuando falla,
  si no lo dijo ya (AYaLeido); NOTLOADED= si lo que fallo fue el LECTOR
  mientras se cargaba el form (ACargando, y la excepcion un EFilerError o un
  EParserError: la jerarquia de la RTL); y ERROR=. Devuelve el codigo de
  salida. Un valor que el Ignore se saltaba sin consumirlo dejaba al lector a
  mitad del flujo, y lo unico que salia era "Stream read error", sin la
  propiedad que lo habia causado (DSGN-061 de la 1.20, medido). }
function RespondeFallo(E: Exception; ACargador: TCargador; ACargando, AYaLeido: Boolean): Integer;
{ csDesigning en un componente recien creado (y en lo que se le inserte) }
procedure PonEnDiseno(AComp: TComponent);
function Cabecera(const AFichero: string): TCabecera;
{ Un ENLACE (Lsp.Reparse: no lo es un marcador de OneDrive): no se lee. El servidor paso por su
  puerta el fichero PEDIDO, por su ruta real; los hermanos que este ayudante
  lee por su cuenta (los .dfm/.fmx de la carpeta, para frames y ancestros, y
  el .pas) no, y uno enlazado sacaria al PNG algo de fuera de las raices
  (revision de Fable, 7-oct-2026). }
function EsEnlace(const AFichero: string): Boolean;
{ 'TX = class(TY' en el .pas hermano de AFichero: TY ('' si no hay). Con
  ALeidos, el .pas leido se anota ahi con su huella (READ=) }
function AncestroDeClase(const AFichero, AClase: string; ALeidos: TStrings = nil): string;
{ Es un frame: lo dice --root (el servidor, por sus jueces) o, sin el, la
  clase CARGADA del ancestro que escribe el .pas, que desciende de AFrame (el
  frame del marco) }
function EsFrame(const AFichero, AClase: string; AFrame: TClass): Boolean;

type
  { Crea la form del renderizador y lee en ella el fichero de la peticion }
  TCreaYLee = reference to function(ACargador: TCargador; out ARaiz: TComponent): TComponent;

{ La form de la peticion leida con su modo de paquetes, IGUAL en los dos
  renderizadores: con 'auto', una pasada con lo estandar y, si sustituyo
  alguna clase, otra con los paquetes del IDE y un cargador nuevo (ANuevo) -
  tambien cuando la primera CAYO. Sin los paquetes, la propiedad de una clase
  que falta leida en el sustituto puede dejar al lector a mitad del flujo: el
  Size de un TStringField en el sustituto FMX daba "Stream read error" y el
  form "no cargaba" sin haber probado con ellos (GridDemo, la corpus del
  18-oct-2026). Estaba escrito en los dos Main, sin ese reintento. }
function LeeConLosPaquetes(var ACargador: TCargador; const ANuevo: TFunc<TCargador>;
  const ALee: TCreaYLee; out ARaiz: TComponent; var ACargados, AConocidos: Integer): TComponent;

{ Los Known Packages del IDE de 32 bits (HKCU\...\BDS\<Bds>\Known Packages),
  con el Register de cada unidad llamado como lo hace el IDE; los expertos se
  saltan. ACargados/AConocidos para PACKAGES=. Solo carga una vez. }
procedure CargaPaquetesDelIde(out ACargados, AConocidos: Integer);
function RaizDelIde(const ABds: string): string;
{ La ventana de aplicacion que se le da a FMX en vez de la suya. Sin ella FMX
  se crea una (TFMAppClass: WS_EX_APPWINDOW, VISIBLE y ACTIVADA, en
  TPlatformWin.CreateAppHandle) en cuanto alguien pide Application.Handle -
  un paquete de diseno del IDE al cargarse -, y sale en la barra de tareas
  como "Delphiformrenderfmx" o "Delphiformrendervcl" robando el foco (David
  vio siete a la vez el 18-oct-2026, los ocho hilos del corpus; medido con
  EnumWindows: sin paquetes no aparece). RegisterApplicationHWNDProc es el
  gancho con el que el IDE le da la suya al designer; esta es una STATIC
  oculta (sin WS_VISIBLE, tool window: nunca en la barra), que vive lo que el
  proceso y que FMX no destruye porque es "de fuera". El renderizador FMX se
  la da a su copia estatica de FMX; a la copia de los paquetes se la da
  EnganchaVentanaEnFmxDelIde, en los dos renderizadores. }
function VentanaDeAplicacionOculta: HWND;

{ La OTRA copia de FMX, en los DOS renderizadores: los paquetes de diseno del
  IDE van con paquetes de ejecucion y traen al proceso fmx<nnn>.bpl, una
  segunda FMX.Platform.Win con su TPlatformWin, que se hace su propia ventana
  de aplicacion en cuanto un paquete pide Application.Handle. Medido el
  19-oct-2026: la ventana era del modulo fmx370.bpl y nacia dentro de la
  inicializacion de dclfmxstd370.bpl, que IMPORTA RegisterApplicationHWNDProc
  e instala el gancho del IDE (fuera del IDE devuelve 0). Se le da la misma
  ventana oculta por ese gancho, que el bpl exporta (buscado por el nombre de
  la rutina: el decorado lleva los tipos), en los tres pasos de la carga de
  cada paquete (antes, tras inicializarlo, tras su Register), en cuanto un
  paquete lo haya traido (nunca lo traemos nosotros: un bpl cargado con
  LoadLibrary no finaliza al salir y perdia sus atomos); si sus unidades no
  estan inicializadas todavia (su TPlatformWin es nil: el gancho lanza), al
  paso siguiente; y la ventana que naciera entre dos ganchos se esconde. La
  guarda de ventanas (abajo) hace ademas que toda TFMAppClass nazca ya
  oculta. }
procedure EnganchaVentanaEnFmxDelIde;
{ El modulo YA cargado en este proceso cuyo nombre de fichero casa con la regex
  APatron (0 si ninguno), por EnumProcessModules como VariableDeModulos }
function ModuloCargado(const APatron: string): HMODULE;
{ La direccion de un export de AModulo por el NOMBRE de la rutina (o de la
  variable) dentro del decorado (@Unidad@Rutina$<tipos>, @Unidad@Variable: los
  tipos cambian de una version a otra, el nombre no), recorriendo su tabla de
  exports; nil si no lo exporta }
function ExportDe(AModulo: HMODULE; const ARutina: string): Pointer;

{ Registro de clases como lo haria RegisterComponents }
procedure Apunta(const AClases: array of TComponentClass);

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
procedure AplicaEstado(ACargador: TCargador; ARoot: TComponent; const AEspec: string);

{ El icono de una clase como lo tiene el paquete de diseno: RCDATA
  '<CLASE>128_PNG' (el IDE actual) en los paquetes cargados o, si no, en los
  Known Packages abiertos como datos. PNG en bytes; False si no hay. }
function IconoPngDeClase(const AClase: string; out APng: TBytes): Boolean;

{ Left/Top de un no visual, como los guarda el dfm (DesignInfo) }
const
  LADO_DE_NO_VISUAL = 28; // el icono de un no visual, en los dos renderizadores (P17)

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
  System.TypInfo,
  System.IOUtils,
  System.RegularExpressions,
  System.RTLConsts,
  System.Actions,
  System.Variants,
  System.SyncObjs,
  System.Diagnostics,
  Winapi.PsAPI,      // EnumProcessModules: el paquete que exporta el registro de modulos
  FormRender.Textos,
  Lsp.DesignerForma, // la forma del fichero, la misma que lee el servidor
  Lsp.Pascal,        // EL lexico Pascal: que es codigo y que comentario
  Lsp.PascalDecl,    // EL lector de declaraciones: el ancestro de una clase, los uses
  Lsp.ShaCache,      // Sha256DeBytes: la huella de READ=, la misma con la que compara el servidor
  Lsp.Reparse,
  Lsp.AtomosRtl,
  System.StrUtils;

type
  TComponentCrack = class(TComponent);
  TPersistentCrack = class(TPersistent);

  { Un TFiler que no lee ni escribe: se le da a DefineProperties de un objeto y
    apunta lo que define sin escritor (WriteData nil) - TWriter no lo escribe
    nunca por su nombre: en FMX, FontColor o Font.Size de un TEdit solo se leen,
    por compatibilidad, y el lector los pone en TextSettings. EL juez es la
    clase cargada (norma 6), no una lista (C9 de la 1.28). }
  TEspiaDeDefinidas = class(TFiler)
  private
    FSinEscritor: TArray<string>;
  public
    procedure DefineProperty(const Name: string; ReadData: TReaderProc; WriteData: TWriterProc;
      HasData: Boolean); override;
    procedure DefineBinaryProperty(const Name: string; ReadData, WriteData: TStreamProc;
      HasData: Boolean); override;
    procedure FlushBuffer; override;
    // lo de AObj; [] si su DefineProperties no se deja preguntar (uno que da por
    // hecho un TReader o un TWriter): de ese objeto no se sabe
    class function SinEscritor(AObj: TPersistent): TArray<string>; static;
  end;

procedure TEspiaDeDefinidas.DefineProperty(const Name: string; ReadData: TReaderProc;
  WriteData: TWriterProc; HasData: Boolean);
begin
  if not Assigned(WriteData) then
    FSinEscritor := FSinEscritor + [Name];
end;

procedure TEspiaDeDefinidas.DefineBinaryProperty(const Name: string; ReadData, WriteData: TStreamProc;
  HasData: Boolean);
begin
  if not Assigned(WriteData) then
    FSinEscritor := FSinEscritor + [Name];
end;

procedure TEspiaDeDefinidas.FlushBuffer;
begin
  // no escribe nada
end;

class function TEspiaDeDefinidas.SinEscritor(AObj: TPersistent): TArray<string>;
begin
  Result := [];
  var Flujo := TMemoryStream.Create;
  try
    var Espia := TEspiaDeDefinidas.Create(Flujo, 16);
    try
      try
        TPersistentCrack(AObj).DefineProperties(Espia);
        Result := Espia.FSinEscritor;
      except
        Result := [];
      end;
    finally
      Espia.Free;
    end;
  finally
    Flujo.Free;
  end;
end;

var
  GVerbose: Boolean = False;
  GVigia: TThread = nil;
  GVigiaPara: TEvent = nil;
  // por la CLASE, no por su nombre: la VCL y FMX tienen clases con el mismo
  // (TCalendar, TMediaPlayer, TWebBrowser...), cada una en su grupo de la RTL,
  // y por el nombre la segunda no se registraba (18-oct-2026)
  GRegistradas: TDictionary<TClass, Boolean>;
  GModulos: TList<HMODULE>;          // paquetes cargados de verdad (su codigo corre)
  GModulosDatos: TDictionary<string, HMODULE>; // paquetes abiertos solo como datos (iconos)
  GConocidos: TStringList;           // rutas de los Known Packages
  GPaquetesCargados: Boolean = False;
  // la fase de los paquetes, para el vigia (otro hilo: solo los lee)
  GCargandoPaquetes: Boolean = False;
  GPaquetesHechos, GPaquetesListados: Integer;
  // ...y el paquete en el que esta: un INDICE de GConocidos, que no cambia en
  // el bucle (-1, ninguno). El nombre que reescribe el hilo principal no se
  // puede leer desde el del vigia (C2 del cierre de la 1.26)
  GPaqueteEnCurso: Integer = -1;

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

function LecturaEnPartes(const AMensaje: string): string;
var
  Formato: string;
  Trozos: TArray<string>;
  M: TMatch;
begin
  Result := FR_PARTES_SEP + FR_PARTES_SEP + FR_PARTES_SEP + AMensaje;
  // Format(SPropertyException, [Name, DotSep, PropPath, E.Message]) de
  // TReader.ReadProperty: cuatro %s; con otro especificador (%0:s, %%) no se
  // invierte a mano, y va sin partes
  Formato := SPropertyException;
  Trozos := Formato.Split(['%s']);
  if Length(Trozos) <> 5 then
    Exit;
  for var T in Trozos do
    if T.Contains('%') then
      Exit;
  // el Name no lleva puntos; la ruta (Font.Size) llega hasta lo que separa el
  // motivo, y el motivo es lo demas: uno anidado (una coleccion) es el suyo
  M := TRegEx.Match(AMensaje, '\A' + TRegEx.Escape(Trozos[0]) + '([^.]+)' +
    TRegEx.Escape(Trozos[1] + DotSep + Trozos[2]) + '(.+?)' + TRegEx.Escape(Trozos[3]) + '(.*)' +
    TRegEx.Escape(Trozos[4]) + '\z', [roSingleLine]);
  if not M.Success then
    Exit;
  for var G := 1 to 3 do
    if M.Groups[G].Value.Contains(FR_PARTES_SEP) then
      Exit;
  Result := M.Groups[1].Value + FR_PARTES_SEP + M.Groups[2].Value + FR_PARTES_SEP + M.Groups[3].Value +
    FR_PARTES_SEP + AMensaje;
end;

{ EL escritor de un valor <cabeza>|<fichero>|<mensaje en partes> (IGNORED=, NOTLOADED=):
  la cabeza (de quien, o la clase de la excepcion), el fichero que se leia (el de un
  frame o un ancestro, si fue ahi; '' si no hay fichero) y el mensaje en sus partes.
  Su lector es DeCabezaYPartes (Lsp.FormRender). V106 de la 1.23.1: se
  componia a mano en tres sitios. }
function EnCabezaYPartes(const ACabeza, AFichero, AMensaje: string): string;
begin
  Result := ACabeza + FR_PARTES_SEP + AFichero + FR_PARTES_SEP + LecturaEnPartes(AMensaje);
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
  // cinco formas de uso, cada una con el nombre del programa: con uno solo
  // salia "%s --path ..." y el "(No argument for format)" de MsgFmt
  Result := MsgFmt(SF_RENDER_USO_FMT, [AExe, AExe, AExe, AExe, AExe]);
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
  // antes que nada que pueda fallar: un argumento que este ayudante no conoce
  // tambien es otra version
  Responde(FR_PROTOCOL, IntToStr(FR_PROTOCOLO_VERSION));
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
      if P = FR_ARG_PATH then GPeticion.Path := Valor
      else if P = FR_ARG_OUT then GPeticion.Salida := Valor
      else if P = FR_ARG_STYLE then GPeticion.Estilo := Valor
      else if P = FR_ARG_COMPONENT then GPeticion.Componente := Valor
      else if P = FR_ARG_BDS then GPeticion.Bds := Valor
      else if P = FR_ARG_BDSROOT then GPeticion.RaizBds := Valor
      else if P = FR_ARG_KNOWNFILE then GPeticion.FicheroPaquetes := Valor
      else if P = FR_ARG_PACKAGES then GPeticion.Paquetes := Entre(Valor, ['auto', 'none', 'all'])
      else if P = FR_ARG_FIDELITY then GPeticion.Fidelidad := Entre(Valor, ['auto', 'window', 'print'])
      else if P = FR_ARG_ROOT then GPeticion.Raiz := Entre(Valor, ['auto', 'form', 'frame'])
      else if P = FR_ARG_STATE then GPeticion.Estados := GPeticion.Estados + [Valor]
      else if P = FR_ARG_NONVISUAL then
      begin
        V := Entre(Valor, [FR_ARG_SI, FR_ARG_NO, 'true', 'false', '1', '0']);
        GPeticion.NoVisuales := (V = FR_ARG_SI) or (V = 'true') or (V = '1');
      end
      else if P = FR_ARG_WRITEBACK then
      begin
        V := Entre(Valor, [FR_ARG_SI, FR_ARG_NO, 'true', 'false', '1', '0']);
        GPeticion.Escribe := (V = FR_ARG_SI) or (V = 'true') or (V = '1');
      end
      else if P = FR_ARG_DROPPED then GPeticion.Soltado := Valor
      else if P = FR_ARG_SET then GPeticion.Puestas := GPeticion.Puestas + [Valor]
      else if P = FR_ARG_CONVERT then GPeticion.Convierte := Entre(Valor, ['text', 'binary'])
      else if P = FR_ARG_UNREADABLE_CLASSES then GPeticion.ClasesSinLeer := True
      else if P = FR_ARG_BOXES then GPeticion.Cajas := True
      else if P = FR_ARG_TIMEOUT then GPeticion.TiempoMs := StrToInt(Valor)
      else if P = FR_ARG_PACKAGES_TIMEOUT then GPeticion.TiempoPaquetesMs := StrToInt(Valor)
      else if P = FR_ARG_VERBOSE then GPeticion.Verbose := True
      else
        raise ERender.Create(MsgFmt(SR_RENDER_ARG_DESCONOCIDO_FMT, [P]));
      Inc(I);
    end;
    if GPeticion.ClasesSinLeer then
      Exit;
    if GPeticion.Path = '' then
      raise ERender.Create(MsgFmt(SR_RENDER_FALTA_ARG_FMT, [FR_ARG_PATH]));
    // el juez no pinta: sin png
    if (GPeticion.Salida = '') and not GPeticion.Escribe and not GPeticion.Cajas then
      raise ERender.Create(MsgFmt(SR_RENDER_FALTA_ARG_FMT, [FR_ARG_OUT]));
    if not TFile.Exists(GPeticion.Path) then
      raise ERender.Create(MsgFmt(SR_RENDER_NO_EXISTE_FMT, [GPeticion.Path]));
    // ...y con una propiedad detras del ultimo punto: Button1.=x llegaba a
    // ObjetoDeRuta con la ruta vacia y leia fuera del array (EAccessViolation,
    // medido en vivo el 18-oct-2026)
    for var E in GPeticion.Estados do
      if (E.IndexOf('=') < 1) or (E.IndexOf('.') < 1) or (E.IndexOf('.') > E.IndexOf('=')) or
         E.Substring(0, E.IndexOf('=')).Trim.EndsWith('.') then
        raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_FORMA_FMT, [E]));
    GVerbose := GPeticion.Verbose;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

function RutaDeComponente(ARaiz, AComp: TComponent): string;
begin
  Result := AComp.Name;
  var O := AComp.Owner;
  while (Result <> '') and (O <> nil) and (O <> ARaiz) and (O.Name <> '') do
  begin
    Result := O.Name + '.' + Result;
    O := O.Owner;
  end;
end;

procedure RespondeCaja(const ARuta, AClase, APadre: string; AX, AY, AAncho, AAlto: Integer; AVisible: Boolean;
  const AContenido, AFichero, AEnFichero, APintada: string);
begin
  Responde(FR_BOX, Format('%s|%s|%s|%s|%d|%s|%s|%s|%s', [ARuta, AClase, APadre, MedidasEnTexto(AX, AY, AAncho, AAlto),
    Ord(AVisible), AContenido, AFichero, AEnFichero, APintada]));
end;

procedure RespondeRaiz(const ANombre, AClase: string; AEsFrame: Boolean);
begin
  Responde(FR_ROOT, Format('%s:%s:%s', [ANombre, AClase, (if AEsFrame then 'frame' else 'form')]));
end;

procedure RespondePaquetes(ACargados, AConocidos: Integer);
begin
  Responde(FR_PACKAGES, Format('%d/%d', [ACargados, AConocidos]));
end;

procedure RespondeRect(const ANombre: string; AX, AY, AAncho, AAlto: Integer);
begin
  Responde(FR_RECT, ANombre + '=' + MedidasEnTexto(AX, AY, AAncho, AAlto));
end;

procedure RespondeTamano(AAncho, AAlto: Integer);
begin
  Responde(FR_SIZE, Format('%dx%d', [AAncho, AAlto]));
end;

procedure RespondeMs(ACarga, APintado: Int64);
begin
  Responde(FR_MS, Format('%d,%d', [ACarga, APintado]));
end;

function MedidasEnTexto(AX, AY, AAncho, AAlto: Integer): string;
begin
  Result := Format('%d,%d,%d,%d', [AX, AY, AAncho, AAlto]);
end;

procedure RespondeLoCargado(ACargador: TCargador; ARaiz: TComponent; AEsFrame: Boolean;
  ACargados, AConocidos: Integer; AClaseControl: TClass; var AYaLeido: Boolean);
begin
  RespondeRaiz(ARaiz.Name, Cabecera(GPeticion.Path).Clase, AEsFrame);
  RespondePaquetes(ACargados, AConocidos);
  Responde(FR_COMPONENTS, IntToStr(ARaiz.ComponentCount));
  RespondeLoLeido(ACargador);
  AYaLeido := True;
  // los no visuales, SIEMPRE: se dibujen o no, el agente sabe que estan
  Responde(FR_NONVISUALS, ListaDeNoVisuales(NoVisualesDe(ARaiz, AClaseControl)));
end;

procedure RespondeElPintado(const AFidelidad: string; AAncho, AAlto: Integer; AMsCarga, AMsPintado: Int64);
begin
  Responde(FR_FIDELITY, AFidelidad);
  RespondeTamano(AAncho, AAlto);
  Responde(FR_CAPTURE, GPeticion.Salida);
  RespondeMs(AMsCarga, AMsPintado);
end;

function ArrancaAyudante(out ACodigo: Integer): Boolean;
var
  Uso, Error: string;
begin
  Result := False;
  Error := ParseaArgumentos(Uso);
  if Error <> '' then
  begin
    Responde(FR_ERROR, Error);
    Writeln(ErrOutput, Uso);
    ACodigo := FR_RC_USAGE;
    Exit;
  end;
  // el conversor del IDE no carga ningun form (V71)
  if GPeticion.Convierte <> '' then
  begin
    ACodigo := ConvierteComoElIde;
    Exit;
  end;
  if GPeticion.ClasesSinLeer then
  begin
    ACodigo := ListaClasesSinLeer;
    Exit;
  end;
  ACodigo := FR_RC_OK;
  ArrancaVigia(GPeticion.TiempoMs);
  Result := True;
end;

function ListaClasesSinLeer: Integer;
var
  Clases, H: HKEY;
  Nombre: array[0..63] of Char;
  N, I, R: DWORD;
begin
  Result := FR_RC_OK;
  if RegOpenKeyEx(HKEY_LOCAL_MACHINE, 'SOFTWARE\Classes\CLSID', 0, KEY_READ, Clases) <> ERROR_SUCCESS then
    Exit(FR_RC_ERROR);
  try
    I := 0;
    while True do
    begin
      N := Length(Nombre);
      R := RegEnumKeyEx(Clases, I, Nombre, N, nil, nil, nil, nil);
      Inc(I);
      if R = ERROR_NO_MORE_ITEMS then
        Break;
      if R <> ERROR_SUCCESS then
        Continue; // un nombre que no cabe no es un CLSID
      R := RegOpenKeyEx(Clases, PChar(string(Nombre) + '\InprocServer32'), 0, KEY_READ, H);
      if R = ERROR_ACCESS_DENIED then
        Responde(FR_UNREADABLE_CLASS, Nombre)
      else if R = ERROR_SUCCESS then
        RegCloseKey(H);
    end;
  finally
    RegCloseKey(Clases);
  end;
end;

{ ---- la ventana de aplicacion de FMX ---- }

var
  GVentanaApp: HWND = 0;
  GFmxDelIde: HMODULE = 0;
  GRegistraDelIde: Pointer = nil;
  GFmxDelIdeSinGancho: Boolean = False; // no exporta el gancho: se queda con la suya
  GFmxDelIdeTrazado: Boolean = False;

function VentanaDeAplicacionOculta: HWND;
begin
  if GVentanaApp = 0 then
    GVentanaApp := CreateWindowEx(WS_EX_TOOLWINDOW, 'STATIC', nil,
      WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  Result := GVentanaApp;
end;

{ La ventana de aplicacion que el fmx del IDE llego a crearse (TFMAppClass)
  mientras su gancho era el del designer: se esconde y deja de ser una
  ventana de aplicacion (segunda barrera de la guarda). No se destruye: es suya. }
function EscondeVentanaDeApp(AVentana: HWND; AParam: LPARAM): BOOL; stdcall;
var
  Clase: array[0..63] of Char;
begin
  Result := True;
  if (GetClassName(AVentana, Clase, Length(Clase)) > 0) and (string(Clase) = 'TFMAppClass') and
     (IsWindowVisible(AVentana) or (GetWindowLong(AVentana, GWL_EXSTYLE) and WS_EX_APPWINDOW <> 0)) then
  begin
    ShowWindow(AVentana, SW_HIDE);
    SetWindowLong(AVentana, GWL_EXSTYLE,
      (GetWindowLong(AVentana, GWL_EXSTYLE) and not WS_EX_APPWINDOW) or WS_EX_TOOLWINDOW);
    Inc(PInteger(AParam)^);
  end;
end;

procedure EnganchaVentanaEnFmxDelIde;
type
  // la forma de FMX.Platform.Win.RegisterApplicationHWNDProc (TApplicationHWNDProc = function: HWND)
  TRegistra = procedure(const Proc: Pointer);
var
  H: HMODULE;
  Escondidas: Integer;
begin
  if GFmxDelIdeSinGancho then
    Exit;
  // lo que naciera entre dos ganchos (dclfmxstd<nnn> pone el suyo al
  // inicializarse y FMX se crea la ventana ahi mismo): escondido ya
  Escondidas := 0;
  EnumThreadWindows(MainThreadID, @EscondeVentanaDeApp, LPARAM(@Escondidas));
  if Escondidas > 0 then
    Traza(Format('%d ventana(s) de aplicacion del fmx del IDE escondida(s)', [Escondidas]));
  // solo cuando un paquete ya lo trajo: traerlo nosotros con LoadLibrary (fuera
  // de LoadPackage) dejaba sus unidades SIN finalizar al salir y cada render
  // con paquetes perdia los 6 atomos de las copias de VCL/FMX (medido el
  // 19-oct-2026: +6 por render; sin la precarga, 0). Lo que nazca antes del
  // gancho ya nace oculto por la guarda de ventanas
  H := GFmxDelIde;
  if H = 0 then
    H := ModuloCargado('^fmx\d+\.bpl$');
  if H = 0 then
    Exit;
  if GFmxDelIde <> H then
  begin
    GFmxDelIde := H;
    GRegistraDelIde := ExportDe(H, 'RegisterApplicationHWNDProc');
  end;
  if GRegistraDelIde = nil then
  begin
    Traza('el fmx del IDE no exporta RegisterApplicationHWNDProc: se queda con su ventana');
    GFmxDelIdeSinGancho := True;
    Exit;
  end;
  try
    TRegistra(GRegistraDelIde)(@VentanaDeAplicacionOculta);
    if not GFmxDelIdeTrazado then
      Traza('ventana de aplicacion enganchada al fmx del IDE');
    GFmxDelIdeTrazado := True;
  except
    on E: Exception do
      Traza('el fmx del IDE aun sin inicializar (' + E.Message + '): al paso siguiente');
  end;
end;

{ ---- guarda de ventanas ---- }

var
  GGuardaCbt: HHOOK = 0;

function CbtGuardaDeVentanas(ACodigo: Integer; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  Clase, Titulo: string;
  EsDialogo: Boolean;
begin
  case ACodigo of
    HCBT_CREATEWND:
      begin
        var CS := PCBTCreateWnd(ALParam).lpcs;
        // lpszClass es un nombre o un atomo (la palabra alta a cero): el de
        // los dialogos del sistema es 32770, como nombre '#32770'
        if HiWord(NativeUInt(CS.lpszClass)) <> 0 then
          Clase := string(CS.lpszClass)
        else
          Clase := '#' + IntToStr(LoWord(NativeUInt(CS.lpszClass)));
        EsDialogo := SameText(Clase, '#32770') or SameText(Clase, 'TMessageForm');
        if EsDialogo then
        begin
          if CS.lpszName <> nil then
            Titulo := string(CS.lpszName);
          Aviso(MsgFmt(SN_RENDER_CUADRO_BLOQUEADO_FMT, [Clase, Titulo]));
          Exit(1); // no nace: CreateWindow devuelve 0 y quien lo abria sigue
        end;
        // la ventana de aplicacion de FMX: fuera de la barra y sin activarse.
        // Sobre la VENTANA (AWParam: ya existe, aun sin mostrar), no sobre el
        // CREATESTRUCT: Windows ignora un dwExStyle cambiado en el gancho
        // (medido el 20-oct-2026 con una sonda: nacia con WS_EX_APPWINDOW y
        // se veia en la barra hasta que EscondeVentanaDeApp la escondia; las
        // 3 muestras de 4.043 del corpus y las 2 del 19-oct eran eso)
        if SameText(Clase, 'TFMAppClass') then
          SetWindowLong(AWParam, GWL_EXSTYLE,
            (GetWindowLong(AWParam, GWL_EXSTYLE) and not WS_EX_APPWINDOW) or
            WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE);
      end;
    HCBT_ACTIVATE:
      Exit(1); // ninguna ventana de este proceso se activa: nada roba el foco
  end;
  Result := CallNextHookEx(GGuardaCbt, ACodigo, AWParam, ALParam);
end;

procedure ArrancaGuardaDeVentanas;
begin
  if GGuardaCbt = 0 then
    GGuardaCbt := SetWindowsHookEx(WH_CBT, @CbtGuardaDeVentanas, 0, GetCurrentThreadId);
end;

procedure ParaGuardaDeVentanas;
begin
  if GGuardaCbt <> 0 then
    UnhookWindowsHookEx(GGuardaCbt);
  GGuardaCbt := 0;
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
var
  Reloj: TStopwatch;
  Espera: Integer;
begin
  Reloj := TStopwatch.StartNew;
  // la fase de los paquetes con su plazo (--packagestimeout); acabada, lo que
  // queda del render entero
  Espera := FMs;
  if (GPeticion.TiempoPaquetesMs > 0) and (GPeticion.TiempoPaquetesMs < FMs) then
    Espera := GPeticion.TiempoPaquetesMs;
  if GVigiaPara.WaitFor(Espera) <> wrTimeout then
    Exit;
  if (Espera < FMs) and not GCargandoPaquetes and (GVigiaPara.WaitFor(FMs - Espera) <> wrTimeout) then
    Exit;
  if GCargandoPaquetes then
  begin
    var En := GPaqueteEnCurso;
    var Paquete: string := '?';
    if (En >= 0) and (En < GConocidos.Count) then
      Paquete := ExtractFileName(GConocidos[En]);
    Responde(FR_ERROR, MsgFmt(SR_RENDER_PAQUETES_CARGANDO_FMT,
      [Reloj.ElapsedMilliseconds div 1000, GPaquetesHechos, GPaquetesListados, Paquete]));
  end
  else
    Responde(FR_ERROR, MsgFmt(SR_RENDER_TIEMPO_FMT, [FMs]));
  // lo que matamos, lo limpiamos: este proceso no va a finalizar, y sus
  // atomos globales (los del exe y los de cada bpl cargado) se quedarian
  // en la tabla de la sesion para siempre (Lsp.AtomosRtl; 18-oct-2026)
  BorraAtomosPropios;
  TerminateProcess(GetCurrentProcess, FR_RC_TIMEOUT);
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

{ Un fichero leido para cargar el form, con la huella de los bytes que se
  usaron, en ALeidos (READ=; B5 rev6 de la 1.18.2): el servidor juzga sin
  el cerrojo y, antes de escribir lo juzgado, vuelve a mirar cada uno - un
  ancestro que otro escritor cambie mientras tanto dejaria un juicio viejo.
  El pedido no se anota: con el juez es la propuesta del servidor, y el
  form de verdad ya lo compara el servidor por sus bytes. Sin ALeidos, nada. }
procedure AnotaLeido(ALeidos: TStrings; const AFichero: string; const ABytes: TBytes);
begin
  if (ALeidos <> nil) and not SameFileName(AFichero, GPeticion.Path) then
    ALeidos.Add(Sha256DeBytes(ABytes) + '|' + AFichero);
end;

{ El texto de un .pas que decide lo que se carga, anotado en ALeidos: la huella
  ANTES que el texto (que lo decodifica la RTL, sin imitarla): si cambia entre
  las dos lecturas, la huella es la vieja y el servidor da DSGN-144 de mas; al
  reves, aceptaria un juicio de un .pas que ya no esta. }
function TextoDeUnidadAnotada(const APas: string; ALeidos: TStrings): string;
begin
  if ALeidos <> nil then
    AnotaLeido(ALeidos, APas, TFile.ReadAllBytes(APas));
  Result := TFile.ReadAllText(APas);
end;

function Cabecera(const AFichero: string): TCabecera;
var
  Bytes: TBytes;
  Lineas: TStringList;
begin
  Result := Default(TCabecera);
  Lineas := TStringList.Create;
  try
    Bytes := TFile.ReadAllBytes(AFichero);
    // uno que el lector de forms del IDE no toma por texto (un UTF-16 o un
    // UTF-32: el juez de la casa, Lsp.DesignerForma) no tiene raiz que leer, y
    // quien indexa la carpeta lo nombra. TStringList si lee el UTF-16: el
    // ancestro se cargaba convertido, o en UTF-32 salia "sin fichero en la
    // carpeta" (A28 de la 1.23)
    if ElIdeNoLoTomaPorForm(Bytes) then
    begin
      Result.NoLaCargaElIde := True;
      Exit;
    end;
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

function AncestroDeClase(const AFichero, AClase: string; ALeidos: TStrings): string;
var
  Pas: string;
begin
  Result := '';
  Pas := UnidadDeDesigner(AFichero);
  if not TFile.Exists(Pas) or EsEnlace(Pas) then
    Exit;
  // por EL lector de declaraciones del servidor (Lsp.PascalDecl), el de
  // check-binding y el de la cadena de ancestros del servidor: era una regex
  // propia de 'TX = class(TY)' (R7 del revisor del paisaje de la 1.27). Con la
  // unidad delante (Vcl.Forms.TForm), su ultimo trozo; la raiz, form o frame, ya
  // la manda el servidor con --root (revision de la 1.17.0)
  var U := LeeFuentePascal(TextoDeUnidadAnotada(Pas, ALeidos));
  try
    // el mismo que el servidor (AncestroDelForm): C30 de la 1.28
    Result := AncestroSimple(U, AClase);
  finally
    U.Free;
  end;
end;

{ La VISTA de un form FMX (<unidad>.<Vista>.fmx): su ancestro es el maestro
  (<unidad>.fmx), y eso lo DICE el IDE en el .pas del maestro, con
  la directiva R '*.<Vista>.fmx ...' - por EL lector de directivas (Lsp.Pascal.
  DirectivasPascal: una comentada no cuenta). El IDE carga la vista ENCIMA de
  su maestro; leida sola, cada 'inherited' daba "Ancestor for X not found" y el
  lint decia que no cargaba (31 de las 78 vistas de los Samples, medido el
  18-oct-2026). '' si no es una vista que el .pas del maestro declare. Con
  ALeidos, el .pas leido se anota con su huella (READ=). }
function MaestroDeVista(const AFichero: string; ALeidos: TStrings): string;
var
  Maestro, Pas: string;
begin
  Result := '';
  Maestro := MaestroPorNombre(AFichero);
  if Maestro = '' then
    Exit;
  Pas := UnidadDeDesigner(Maestro);
  if not TFile.Exists(Maestro) or EsEnlace(Maestro) or not TFile.Exists(Pas) or EsEnlace(Pas) then
    Exit;
  // EL juez de "es una vista", el mismo del servidor (Lsp.DesignerForma.
  // VistasDeUnidad, V122 de la 1.23.1)
  for var V in VistasDeUnidad(Pas, TextoDeUnidadAnotada(Pas, ALeidos)) do
    if SameText(ExtractFileName(V), ExtractFileName(AFichero)) then
      Exit(Maestro);
end;

function EsFrame(const AFichero, AClase: string; AFrame: TClass): Boolean;
var
  C: TPersistentClass;
begin
  if GPeticion.Raiz = 'frame' then
    Exit(True);
  if GPeticion.Raiz = 'form' then
    Exit(False);
  // sin --root (el servidor no lo sabe, o llama otro): la clase CARGADA del
  // ancestro - la del marco o la de un paquete -, no su nombre ('frame' en
  // el nombre era un frame, y un TMainframeForm tambien). Una base que no
  // esta cargada (del usuario, de otra unidad) no se sabe: se lee en la form
  C := GetClass(AncestroDeClase(AFichero, AClase));
  Result := (C <> nil) and C.InheritsFrom(AFrame);
end;

{ ---- paquetes del IDE ---- }

var
  GPaqueteActual: string;

procedure Apunta(const AClases: array of TComponentClass);
begin
  for var C in AClases do
  begin
    if (C = nil) or GRegistradas.ContainsKey(C) then
      Continue;
    try
      System.Classes.RegisterClass(C);
      GRegistradas.Add(C, True);
    except
      on E: Exception do
        Traza(Format('%s: RegisterClass(%s): %s', [GPaqueteActual, C.ClassName, E.Message]));
    end;
  end;
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
    if (C <> nil) and not GRegistradas.ContainsKey(C) then
    begin
      System.Classes.RegisterClass(C);
      GRegistradas.Add(C, True);
    end;
end;

procedure DesapuntaAcciones(const AClasses: array of TBasicActionClass);
begin
end;

function RaizDelIde(const ABds: string): string;
begin
  if GPeticion.RaizBds = '' then
    raise ERender.Create(MsgFmt(SR_RENDER_SIN_IDE_FMT, [ABds]));
  Result := IncludeTrailingPathDelimiter(GPeticion.RaizBds);
end;

{ Los paquetes, de la lista que da el servidor (Lsp.FormRender.PaquetesDelIde:
  los de su IDE sin los desactivados, ya con su ruta): dentro del contenedor
  no se lee el registro del usuario (V65 de la 1.24, medido) }
procedure LeeConocidos;
begin
  if GConocidos <> nil then
    Exit;
  GConocidos := TStringList.Create;
  if GPeticion.FicheroPaquetes <> '' then
    GConocidos.LoadFromFile(GPeticion.FicheroPaquetes);
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
      // la decoracion de dcc, en ASCII (UpperCase/LowerCase): con .ToUpper/
      // .ToLower y el turco, System.UITypes daba @System@U<i sin punto>types@ y
      // el Register no se encontraba (V108 de la 1.23.1)
      Result := Result + UpperCase(Seg.Substring(0, 1)) + LowerCase(Seg.Substring(1)) + '@';
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

var
  // 'TClaseBase=TClaseDelModulo' de cada RegisterCustomModule de los paquetes
  GModulosDeDiseno: TStringList;

{ El RegisterCustomModuleProc del IDE (DesignIntf.TRegisterCustomModuleProc):
  lo que un paquete registra como raiz de un designer propio - un TWebModule,
  un modulo remoto -, con la clase de su modulo de diseno (AModulo, un
  TCustomModuleClass: aqui no se enlaza DesignIntf) }
procedure ApuntaModulo(AGrupo: Integer; ABase: TComponentClass; AModulo: TClass);
begin
  if (ABase <> nil) and (AModulo <> nil) then
    GModulosDeDiseno.Values[ABase.ClassName] := AModulo.ClassName;
end;

{ La variable RegisterCustomModuleProc de DesignIntf, por el simbolo que
  exporta el paquete que la tiene (designide, que llega como dependencia de
  los de diseno): el ayudante no enlaza DesignIntf. nil si no esta cargado. }
{ Los modulos cargados en este proceso (EnumProcessModules), TODOS: en Bytes
  devuelve lo que NECESITA, no lo que copio, y un bucle hasta ahi sobre un
  array fijo leia fuera de el con mas de 1024 modulos (revision 19-oct-2026);
  aqui se vuelve a pedir con sitio para todos y se recorta a lo copiado }
function ModulosDelProceso: TArray<HMODULE>;
var
  Bytes: DWORD;
begin
  SetLength(Result, 1024);
  if not EnumProcessModules(GetCurrentProcess, @Result[0], Length(Result) * SizeOf(HMODULE), Bytes) then
    Exit(nil);
  if Bytes > DWORD(Length(Result) * SizeOf(HMODULE)) then
  begin
    SetLength(Result, Bytes div SizeOf(HMODULE));
    if not EnumProcessModules(GetCurrentProcess, @Result[0], Length(Result) * SizeOf(HMODULE), Bytes) then
      Exit(nil);
    if Bytes > DWORD(Length(Result) * SizeOf(HMODULE)) then
      Bytes := Length(Result) * SizeOf(HMODULE);
  end;
  SetLength(Result, Bytes div SizeOf(HMODULE));
end;

function VariableDeModulos: PPointer;
begin
  for var M in ModulosDelProceso do
  begin
    Result := GetProcAddress(M, '@Designintf@RegisterCustomModuleProc');
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

{ Los ganchos de registro del IDE, apuntados a los nuestros }
procedure PonGanchos;
begin
  RegisterComponentsProc := ApuntaComponentes;
  RegisterNoIconProc := ApuntaSinIcono;
  RegisterNonActiveXProc := ApuntaNoActiveX;
  RegisterActionsProc := ApuntaAcciones;
  UnRegisterActionsProc := DesapuntaAcciones;
  var V := VariableDeModulos;
  if V <> nil then
    V^ := @ApuntaModulo;
end;

procedure CargaPaquetesDelIde(out ACargados, AConocidos: Integer);
const
  // expertos del IDE: no registran componentes y tocan BorlandIDEServices.
  // Una lista de la casa por el nombre del bpl: no hay juez sin cargarlo
  // (el registro no los distingue, Known IDE Packages no tiene ninguno de
  // estos; medido el 25-oct-2026). Las integraciones de control de
  // versiones (gitide, hgide, svnide) por 'ide' y su version, sin clavarla:
  // 'ide370' dejaba de casar con el IDE siguiente. Sin 'wizard': solo casaba
  // JvWizardsDesign370, el paquete de diseno de TJvWizard (sus forms salian
  // sustituidos), y MobileWizardExpert370, que ya casa 'expert' (V17 de la
  // 1.23). El juez seria cargar solo los paquetes que registran las clases
  // que faltan (apuntado para la 1.24)
  EXPERTOS = '(?i)(ide\d+\.bpl$|expert|explorer|visualizer|applet|quickedit|emacsedit|smpedit|mlwiz|netwiz|styledesigner|^svn)';
var
  H: HMODULE;
  Antes: Integer;
  Reloj: TStopwatch;
begin
  ACargados := 0;
  LeeConocidos;
  AConocidos := GConocidos.Count;
  if GPaquetesCargados then
  begin
    ACargados := GModulos.Count;
    Exit;
  end;
  GPaquetesCargados := True;
  PonGanchos;
  GPaquetesListados := AConocidos;
  GPaquetesHechos := 0;
  Responde(FR_PHASE, FR_FASE_PAQUETES);
  GCargandoPaquetes := True;
  for var I := 0 to GConocidos.Count - 1 do
  begin
    var Ruta := GConocidos[I];
    // antes del Exists: lo que tarda puede ser el (una carpeta de red)
    GPaqueteEnCurso := I;
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
      EnganchaVentanaEnFmxDelIde;
      H := LoadPackage(Ruta);
      GModulos.Add(H);
      EnganchaVentanaEnFmxDelIde; // tras su inicializacion, antes de su Register
      // OTRA vez, antes de su Register: ActionEditors (designide, que llega
      // como dependencia del primer paquete de diseno) pone a nil los de las
      // acciones al inicializarse (ToolsAPI\ActionEditors.pas:1613) y el IDE
      // pone los suyos despues. Sin esto cada RegisterActions daba "Invalid
      // action registration" y el Register entero se cortaba ahi: las acciones
      // de FMX, de LiveBindings y de datos salian sustituidas (18-oct-2026)
      PonGanchos;
      LlamaRegisters(H);
      EnganchaVentanaEnFmxDelIde; // y tras su Register
      Inc(ACargados);
      GPaquetesHechos := ACargados;
      Traza(Format('%s: %d clases, %d ms', [GPaqueteActual, GRegistradas.Count - Antes, Reloj.ElapsedMilliseconds]));
    except
      on E: Exception do
        Traza(Format('%s: no carga: %s: %s', [GPaqueteActual, E.ClassName, E.Message]));
    end;
  end;
  GCargandoPaquetes := False;
  GPaqueteEnCurso := -1;
  Responde(FR_PHASE, FR_FASE_FORM);
  for var I := 0 to GModulosDeDiseno.Count - 1 do
    Traza('modulo de diseno: ' + GModulosDeDiseno.Names[I] + ' -> ' + GModulosDeDiseno.ValueFromIndex[I]);
end;

{ Al salir del proceso, tras TODAS las finalizaciones (System.ExitProcessProc,
  justo antes de ExitProcess): los atomos del RTL que aun lleven este pid o
  este hilo son los de las copias de VCL y FMX de los bpl de ejecucion
  (vcl<nnn>.bpl, fmx<nnn>.bpl) que traen los paquetes de diseno. Las unidades
  de un bpl cargado con LoadPackage solo finalizan con UnloadPackage, y
  descargar los de diseno fuera del IDE revienta (AV en dclstd, rtl; medido
  el 19-oct-2026); asi que al salir del proceso quedaban sus 6 atomos
  (Delphi<pid>, FIREMONKEY, ControlOfs x2, WndProcPtr x2) POR CADA RENDER con
  paquetes, +6 medido a mano y 0 sin paquetes: eran los ~1.000
  "renderizadores matados" del censo del 18-oct, que eran renders normales.
  Los del exe ya los borro su finalizacion: aqui no queda ninguno suyo. }
procedure LimpiaAtomosAlSalir;
begin
  BorraAtomosPropios;
end;


function LeeConLosPaquetes(var ACargador: TCargador; const ANuevo: TFunc<TCargador>;
  const ALee: TCreaYLee; out ARaiz: TComponent; var ACargados, AConocidos: Integer): TComponent;

  function ConPaquetes: Boolean;
  begin
    Result := (GPeticion.Paquetes = 'auto') and (ACargador.Sustituidas.Count > 0);
  end;

begin
  Result := nil;
  ARaiz := nil;
  try
    Result := ALee(ACargador, ARaiz);
  except
    if not ConPaquetes then
      raise;
  end;
  if ConPaquetes then
  begin
    Traza('clases sin registrar: ' + string.Join(',', ACargador.Sustituidas.ToStringArray) + ' -> paquetes del IDE');
    FreeAndNil(Result);
    ACargador.Free;
    ACargador := ANuevo();
    CargaPaquetesDelIde(ACargados, AConocidos);
    Result := ALee(ACargador, ARaiz);
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

{ El objeto que tiene la ULTIMA propiedad de una ruta con punto (Font.Size,
  TextSettings.FontColor, Fill.Color) y esa propiedad en AHoja, recorrida
  como la recorre TReader.ReadProperty al leer el form: cada tramo menos el
  ultimo es una propiedad de clase y se entra en su objeto. Un objeto PROPIO
  (TFont, TTextSettings, TBrush) se cruza; una referencia a un componente
  no, juzgada por el TIPO de la propiedad (vacia o no): en el fichero se
  escribe su Name, no sus propiedades - la misma regla que set y prop en el
  servidor (EsObjetoPropio). Antes solo se miraba un nivel: Font.Size salia
  RENDER-012 (Flash, ronda del filtro de la 1.20, 16-oct). }
function ObjetoDeRuta(ACargador: TCargador; ARaiz, AComp: TComponent; const ARuta: string;
  out AHoja: string): TPersistent;
var
  Tramos: TArray<string>;
  PI: PPropInfo;
  Obj: TObject;
  Tramo, Ahora: string;
begin
  Result := AComp;
  Tramos := ARuta.Split(['.']);
  for var I := 0 to High(Tramos) - 1 do
  begin
    Tramo := Tramos[I].Trim;
    PI := GetPropInfo(Result, Tramo);
    if PI = nil then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_NO_PUBLICA_FMT, [ACargador.ClaseEscrita(Result, ARaiz), Tramo]));
    if PI.PropType^.Kind <> tkClass then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_NO_OBJETO_FMT, [Tramo, ACargador.ClaseEscrita(Result, ARaiz)]));
    Obj := GetObjectProp(Result, PI);
    if GetTypeData(PI.PropType^).ClassType.InheritsFrom(TComponent) then
    begin
      Ahora := 'nil';
      if Obj <> nil then
        Ahora := TComponent(Obj).Name;
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_REFERENCIA_FMT, [Tramo, ACargador.ClaseEscrita(Result, ARaiz), Ahora]));
    end;
    if not (Obj is TPersistent) then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_NO_OBJETO_FMT, [Tramo, ACargador.ClaseEscrita(Result, ARaiz)]));
    Result := TPersistent(Obj);
  end;
  AHoja := Tramos[High(Tramos)].Trim;
end;

procedure AplicaEstado(ACargador: TCargador; ARoot: TComponent; const AEspec: string);
var
  Comp, Valor, Prop, Hoja: string;
  Partes: TArray<string>;
  C, Ref: TComponent;
  Obj: TPersistent;
  PI: PPropInfo;
  N64: Int64;
  Entero: Longint;
  Flotante: Extended;
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
  // la segunda barrera, donde nace: sin propiedad no hay ruta que seguir
  if Prop = '' then
    raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_FORMA_FMT, [AEspec]));
  Obj := ObjetoDeRuta(ACargador, ARoot, C, Prop, Hoja);
  PI := GetPropInfo(Obj, Hoja);
  if PI = nil then
    raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_NO_PUBLICA_FMT, [ACargador.ClaseEscrita(Obj, ARoot), Hoja]));
  if PI.PropType^.Kind = tkClass then
  begin
    Ref := ComponenteDeRuta(ARoot, Valor);
    if Ref = nil then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_SIN_REFERIDO_FMT, [Valor, Comp]));
    SetObjectProp(Obj, PI, Ref);
  end
  // un entero con NOMBRE (clRed en un TColor, crHandPoint en un TCursor,
  // claRed en un TAlphaColor), como lo lee TReader: el lector que registra
  // su tipo (RegisterIntegerConsts). SetPropValue con el texto salia
  // DSGN-061, EVariantTypeCastError (3.5 de la 1.18.0, Hermes)
  else if (PI.PropType^.Kind in [tkInteger, tkInt64]) and not TryStrToInt64(Valor, N64) and
          Assigned(FindIdentToInt(PI.PropType^)) and FindIdentToInt(PI.PropType^)(Valor, Entero) then
    SetOrdProp(Obj, PI, Entero)
  // un numero de coma flotante como lo escribe un form, por EL lector
  // (Lsp.DesignerForma.LeeFlotanteDeForm: el parser de forms, punto decimal
  // siempre): SetPropValue lo convertia por un Variant con el LOCALE del
  // usuario, y en es-ES Position.X=10.5 era 105 (V121 de la 1.23.1, medido)
  else if PI.PropType^.Kind = tkFloat then
  begin
    // ...y uno que ese parser no lee se niega: caia a SetPropValue, con el
    // locale, y 0,5 se pintaba en es-ES lo que designer set niega (DSGN-092):
    // dos jueces del mismo valor (V173k de la 1.23.1, medido)
    if not LeeFlotanteDeForm(Valor, Flotante) then
      raise ERender.Create(MsgFmt(SR_RENDER_ESTADO_FLOTANTE_FMT, [Valor, Hoja]));
    SetFloatProp(Obj, PI, Flotante);
  end
  else
    SetPropValue(Obj, Hoja, Valor);
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
begin
  Result := Lsp.Reparse.EsEnlace(AFichero);
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
  // el nombre del recurso, en ASCII: con .ToUpper y el turco, TEdit era
  // TED<I con punto>T y el icono no salia (V108)
  Nombre := UpperCase(AClase) + '128_PNG';
  for var M in GModulos do
    if PngDeModulo(M, Nombre, APng) then
      Exit(True);
  // sin paquetes cargados (una form estandar): los Known Packages como DATOS,
  // nada suyo se ejecuta; se abren una vez y se quedan abiertos
  LeeConocidos;
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
  FSinLeer := TStringList.Create;
  FLeidos := TStringList.Create;
  FLeidos.Sorted := True; // un frame dos veces en el form es UN fichero leido
  FLeidos.Duplicates := dupIgnore;
  FNoAplicados := TStringList.Create;
  FNoAplicados.Sorted := True;
  FNoAplicados.Duplicates := dupIgnore;
  FPorClase := TDictionary<string, TArray<string>>.Create;
  FNoCargan := TStringList.Create;
  FFramesEnCurso := TStringList.Create;
  FEscritas := TDictionary<TComponent, string>.Create;
  FEscritoEn := TDictionary<TComponent, TEscritoEn>.Create;
end;

destructor TCargador.Destroy;
begin
  FEscritoEn.Free;
  FEscritas.Free;
  FNoCargan.Free;
  FFramesEnCurso.Free;
  FPorClase.Free;
  FNoAplicados.Free;
  FLeidos.Free;
  FAvisos.Free;
  FSinLeer.Free;
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
  FNoCargan.Clear;
  Ext := ExtractFileExt(GPeticion.Path);
  for var F in TDirectory.GetFiles(ACarpeta, '*' + Ext) do
  if not EsEnlace(F) then // un hermano enlazado no se lee: ver EsEnlace
  try
    // uno que el lector del IDE no carga no es el ancestro de nadie: se
    // anota, y si falta uno, el aviso lo nombra (A28 de la 1.23)
    var C := Cabecera(F);
    if C.NoLaCargaElIde then
      FNoCargan.Add(ExtractFileName(F))
    else if C.Clase <> '' then
    begin
      var Ficheros: TArray<string>;
      if not FPorClase.TryGetValue(ClaveDeIdentificador(C.Clase), Ficheros) then
        Ficheros := nil;
      FPorClase.AddOrSetValue(ClaveDeIdentificador(C.Clase), Ficheros + [F]);
    end;
  except
    // un fichero que no se deja leer no es de este renderizador
  end;
end;

{ Las unidades de los uses de un fuente, por su clave: por EL lector de
  declaraciones del servidor (Lsp.PascalDecl), las del interface y las del
  implementation. Era una regex propia de 'uses ... ;' (R7 del revisor del
  paisaje de la 1.27). }
function UnidadesEnUses(const AFuente: string): TArray<string>;
begin
  Result := nil;
  var U := LeeFuentePascal(AFuente);
  try
    for var N in U.UsesInterface + U.UsesImplementation do
      Result := Result + [ClaveDeIdentificador(N)];
  finally
    U.Free;
  end;
end;

function TCargador.FicheroDeClase(const ACarpeta, AClase, AQuienLaNombra: string): string;
var
  Candidatos: TArray<string>;
  Pas: string;
begin
  IndexaCarpeta(ACarpeta);
  if not FPorClase.TryGetValue(ClaveDeIdentificador(AClase), Candidatos) then
    Exit('');
  Result := Candidatos[0];
  // la copia que deja el Explorador ("UBase - copia.dfm", con la misma clase) no es
  // la que enlaza el exe (V120 de la 1.24, medido). Lo dice el uses del que la nombra,
  // por el NOMBRE del fichero: la copia sigue diciendo "unit UBase;" y dcc la busca por
  // el suyo. Sin .pas no decide. Y una sola que el uses no nombra tampoco es: lo que
  // el proyecto enlaza esta en otra carpeta, y el servidor lo trae
  Pas := UnidadDeDesigner(AQuienLaNombra);
  if TFile.Exists(Pas) and not EsEnlace(Pas) then
  begin
    var Usadas := UnidadesEnUses(TextoDeUnidadAnotada(Pas, FLeidos)) +
      [ClaveDeIdentificador(TPath.GetFileNameWithoutExtension(Pas))];
    for var F in Candidatos do
      if IndexStr(ClaveDeIdentificador(TPath.GetFileNameWithoutExtension(F)), Usadas) >= 0 then
        Exit(F);
    if Length(Candidatos) = 1 then
      Exit('');
  end
  else if Length(Candidatos) = 1 then
    Exit;
  var Nombres: TArray<string> := nil;
  for var F in Candidatos do
    Nombres := Nombres + [ExtractFileName(F)];
  var Aviso := MsgFmt(SN_RENDER_CLASE_EN_VARIOS_FMT, [AClase, string.Join(', ', Nombres), ExtractFileName(Result)]);
  if FAvisos.IndexOf(Aviso) < 0 then
    FAvisos.Add(Aviso);
end;

procedure TCargador.FindComponentClass(Reader: TReader; const ClassName: string;
  var ComponentClass: TComponentClass);
begin
  if ComponentClass <> nil then
    Exit;
  // un frame inline (o una form metida en otra): su fichero esta en la carpeta
  FFramePendiente := FicheroDeClase(ExtractFilePath(GPeticion.Path), ClassName, FLeyendo);
  if FFramePendiente <> '' then
  begin
    FClaseFrame := ClassName;
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
    // el que ya se esta leyendo, o el form pedido: la lectura no acabaria nunca
    if SameFileName(Fichero, GPeticion.Path) or (FFramesEnCurso.IndexOf(Fichero) >= 0) then
    begin
      // lo lleva el ultimo de la cadena; se dice su clase y su fichero, porque
      // OnCreateComponent no recibe el nombre del componente
      var Cadena := ExtractFileName(GPeticion.Path);
      var LoLleva := Cadena;
      for var EnCurso in FFramesEnCurso do
      begin
        LoLleva := ExtractFileName(EnCurso);
        Cadena := Cadena + ' > ' + LoLleva;
      end;
      raise EFrameCiclico.Create(MsgFmt(SR_RENDER_FRAME_CICLICO_FMT,
        [FClaseFrame, Cadena + ' > ' + ExtractFileName(Fichero), LoLleva]));
    end;
    Component := ClaseFrame.Create(Reader.Owner);
    FEscritas.AddOrSetValue(Component, FClaseFrame);
    PonEnDiseno(Component);
    // su propio fichero, con sus ancestros; luego el lector exterior aplica
    // los 'inherited' del inline sobre lo que ya tiene. Para eso el lector
    // tiene que buscar los hijos EN el frame (FLookupRoot): solo lo hace si el
    // componente lleva csInline, y cuando lo crea OnCreateComponent el lector
    // no se lo pone (System.Classes 11869-11873: solo en su propio camino).
    FFramesEnCurso.Add(Fichero);
    try
      Lee(Fichero, Component);
    finally
      FFramesEnCurso.Delete(FFramesEnCurso.Count - 1);
    end;
    TComponentCrack(Component).SetInline(True);
    Exit;
  end;
  if ComponentClass = ClaseSustituto then
  begin
    Component := CreaSustituto(Reader.Owner, FDesconocida);
    FEscritas.AddOrSetValue(Component, FDesconocida);
  end;
end;

function TCargador.ClaseEscrita(AObj: TObject; ARaiz: TComponent): string;
begin
  if (AObj = ARaiz) and (GPeticion.Path <> '') then
  begin
    Result := Cabecera(GPeticion.Path).Clase;
    if Result <> '' then
      Exit;
  end;
  if (AObj is TComponent) and FEscritas.TryGetValue(TComponent(AObj), Result) then
    Exit;
  Result := AObj.ClassName;
end;

procedure TCargador.FindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
begin
  Address := nil;
  Error := False;
  Inc(FEventos);
  FNoAplicados.Add(MethodName);
end;

procedure TCargador.FindComponentInstance(Reader: TReader; const Name: string; var Instance: Pointer);
begin
  // el lector no la encontro en el form: Instance sigue nil, como sin este
  // manejador, y se apunta
  FNoAplicados.Add(Name);
end;

procedure TCargador.ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
var
  Origen: string;
begin
  // de quien es la excepcion que TReader nos deja ignorar: la suya (EFilerError,
  // EParserError: el fichero) o la del codigo de un componente (IBX sin
  // gds32.dll al CREARLO, un TActionManager sin su unidad de estilo, un AV de
  // un bpl): OnError corre dentro de un except de TReader con ExceptObject
  // vivo. La MISMA regla que RespondeFallo para NOTLOADED=. LIMITE medido
  // (System.Classes 12220: ReadProperty): la excepcion de un SETTER llega ya
  // envuelta en el EReadError de SPropertyException y sale como del lector;
  // la clase original solo se ve al crear o nombrar el componente
  // (ReadComponent.Recover) y en los fixups (revisor de la 1.20.2)
  Origen := FR_ORIGEN_LECTOR;
  var E := ExceptObject;
  if E is EFrameCiclico then
    Origen := FR_ORIGEN_FRAME_CICLICO
  else if (E <> nil) and not ((E is EFilerError) or (E is EParserError)) then
    Origen := E.ClassName;
  // el fichero que se leia: el de un frame si la excepcion salio de su lectura
  // (su Lee ya devolvio FLeyendo al de fuera), y si no, el que se lee
  var Fichero := (if FFalloEn <> '' then FFalloEn else FLeyendo);
  FFalloEn := '';
  FIgnoradas.Add(Origen + FR_PARTES_SEP + Fichero + FR_PARTES_SEP + Message);
  Handled := True;
end;

procedure TCargador.SetName(Reader: TReader; Component: TComponent; var Name: string);
var
  E: TEscritoEn;
begin
  // el nombre no se toca: se apunta donde esta escrito
  E.Fichero := FLeyendo;
  E.Raiz := FRaizLeyendo;
  FEscritoEn.AddOrSetValue(Component, E);
end;

function TCargador.EscritoEn(AComp: TComponent; out ARuta: string): string;
var
  E: TEscritoEn;
begin
  ARuta := '';
  if not FEscritoEn.TryGetValue(AComp, E) then
    Exit('');
  Result := E.Fichero;
  ARuta := RutaDeComponente(E.Raiz, AComp);
end;

procedure TCargador.AncestorNotFound(Reader: TReader; const ComponentName: string;
  ComponentClass: TPersistentClass; var Component: TComponent);
begin
  // un 'inherited X' sin ancestro cargado: con nil TReader SALTA su bloque (no
  // lo crea: System.Classes, Recover/SkipComponent) y la form se carga sin el;
  // el juez del orden lo nota porque falta en lo escrito (DSGN-143)
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
    // la huella de ESTOS bytes, los que se cargan (READ=)
    var Bytes: TBytes;
    SetLength(Bytes, Texto.Size);
    if Texto.Size > 0 then
      Move(Texto.Memory^, Bytes[0], Texto.Size);
    AnotaLeido(FLeidos, AFichero, Bytes);
    // texto, flujo TPF0 o el recurso del IDE: el flujo que lee TReader
    DesignerAFlujo(Texto, Bin);
    Bin.Position := 0;
    Reader := TReader.Create(Bin, 4096);
    try
      Reader.OnFindComponentClass := FindComponentClass;
      Reader.OnCreateComponent := CreateComponent;
      Reader.OnFindMethod := FindMethod;
      Reader.OnFindComponentInstance := FindComponentInstance;
      Reader.OnError := ReaderError;
      Reader.OnSetName := SetName;
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

procedure RespondeLoLeido(ACargador: TCargador);
begin
  if ACargador.Sustituidas.Count > 0 then
    Responde(FR_SUBSTITUTED, string.Join(',', ACargador.Sustituidas.ToStringArray));
  // <de quien>|<fichero>|<mensaje en partes>: ReaderError guarda 'origen|fichero|mensaje',
  // y ni el origen ni una ruta llevan el separador
  for var S in ACargador.Ignoradas do
  begin
    var Partes := S.Split([FR_PARTES_SEP], 3);
    Responde(FR_IGNORED, EnCabezaYPartes(Partes[0], Partes[1], Partes[2]));
  end;
  for var S in ACargador.Avisos do
    Aviso(S);
  for var S in ACargador.SinLeer do
    Responde(FR_PARTIAL, S);
  for var S in ACargador.Leidos do
    Responde(FR_READ, S);
  for var S in ACargador.NoAplicados do
    Responde(FR_UNAPPLIED, S);
end;

function RespondeFallo(E: Exception; ACargador: TCargador; ACargando, AYaLeido: Boolean): Integer;
begin
  if not AYaLeido and (ACargador <> nil) then
    RespondeLoLeido(ACargador);
  if ACargando and ((E is EFilerError) or (E is EParserError)) then
    Responde(FR_NOT_LOADED, EnCabezaYPartes(E.ClassName, (if ACargador <> nil then ACargador.ParoEn else ''),
      E.Message));
  if E is ERender then
    Responde(FR_ERROR, E.Message) // ya lleva su etiqueta
  else
    Responde(FR_ERROR, E.ClassName + ': ' + E.Message);
  Result := FR_RC_ERROR;
end;

{ Las propiedades publicadas de la clase de AObj en el orden en que las
  escribe TWriter.WriteProperties (GetPropInfos: el NameIndex, el de la clase
  que la publico primero), separadas por coma. Solo la RTTI. }
function OrdenDelEscritor(AObj: TPersistent): string;
var
  Lista: PPropList;
  N: Integer;
begin
  Result := '';
  N := GetTypeData(AObj.ClassInfo)^.PropCount;
  if N = 0 then
    Exit;
  GetMem(Lista, N * SizeOf(Pointer));
  try
    GetPropInfos(AObj.ClassInfo, Lista);
    for var I := 0 to N - 1 do
    begin
      if Lista^[I] = nil then
        Break;
      Result := Result + (if Result <> '' then ',' else '') + GetPropName(Lista^[I]);
    end;
  finally
    FreeMem(Lista);
  end;
end;

{ Las publicadas de la clase de AObj que esa clase declara stored False, la
  CONSTANTE: TWriter no las escribe nunca por su nombre (en FMX, Width y Height
  van en Size). La regla es la de la RTL (TypInfo.IsStoredPropRTTI: un
  StoredProc sin nada por encima del byte bajo es una constante, y ese byte su
  valor); un stored con metodo depende de la instancia - el valor por defecto -
  y no entra. Separadas por coma. Tambien las de sus SUBOBJETOS, por su ruta:
  TWriter escribe en linea un TPersistent que no es un componente
  (TextSettings.Font), y la TFont de FMX guarda Style como StyleExt
  (DefineProperties) - se decia "no se guarda" de lo que el IDE escribio
  (Fable sobre la 1.22.2, B2). Un componente al que apunta una propiedad es
  una referencia, no un subobjeto: no se baja. En APorCodigo, de los mismos
  objetos, lo que su DefineProperties define sin escritor (TEspiaDeDefinidas):
  tampoco se escribe nunca por su nombre (C9 de la 1.28). }
function NuncaGuardadas(AObj: TPersistent; out APorCodigo: string): string;
var
  Juntas, PorCodigo: string;

  procedure Junta(AO: TPersistent; const APrefijo: string; ANivel: Integer);
  var
    Lista: PPropList;
    N: Integer;
  begin
    for var Nombre in TEspiaDeDefinidas.SinEscritor(AO) do
      PorCodigo := PorCodigo + (if PorCodigo <> '' then ',' else '') + APrefijo + Nombre;
    N := GetTypeData(AO.ClassInfo)^.PropCount;
    if N = 0 then
      Exit;
    GetMem(Lista, N * SizeOf(Pointer));
    try
      GetPropInfos(AO.ClassInfo, Lista);
      for var I := 0 to N - 1 do
      begin
        if Lista^[I] = nil then
          Break;
        var Nombre := APrefijo + GetPropName(Lista^[I]);
        var Guarda := UIntPtr(Lista^[I]^.StoredProc);
        if ((Guarda and not NativeUInt($FF)) = 0) and ((Guarda and $FF) = 0) then
          Juntas := Juntas + (if Juntas <> '' then ',' else '') + Nombre
        // tres niveles bastan (TextSettings.Font.Style) y cortan un ciclo
        else if (ANivel < 3) and (Lista^[I]^.PropType^.Kind = tkClass) then
        try
          var Sub := GetObjectProp(AO, Lista^[I]);
          if (Sub is TPersistent) and not (Sub is TComponent) then
            Junta(TPersistent(Sub), Nombre + '.', ANivel + 1);
        except
          // un getter que no se deja leer: de ese subobjeto no se sabe
        end;
      end;
    finally
      FreeMem(Lista);
    end;
  end;

begin
  Juntas := '';
  PorCodigo := '';
  Junta(AObj, '', 0);
  Result := Juntas;
  APorCodigo := PorCodigo;
end;

{ <Nombre>=<prop>,<prop>,... de ORDER=, UNSTORED= y BYCODE= (ALista ya va
  separada por comas). La inversa: Lsp.FormRender.LeeRespuestaDeRender }
function ListaDelComponente(const ANombre, ALista: string): string;
begin
  Result := ANombre + '=' + ALista;
end;

procedure EscribeComoElIde(ARaiz: TComponent);
var
  Bin: TMemoryStream;
  Bytes: TBytes;
  Lineas: TStringList;
begin
  Bin := TMemoryStream.Create;
  Lineas := TStringList.Create;
  try
    Bin.WriteComponent(ARaiz); // el flujo TPF0, lo que guarda el IDE
    SetLength(Bytes, Bin.Size);
    if Bin.Size > 0 then
      Move(Bin.Memory^, Bytes[0], Bin.Size);
    // a texto por EL conversor de la casa (Lsp.DesignerForma), el del servidor
    Lineas.Text := DesignerBinarioATexto(Bytes);
    for var L in Lineas do
      Responde(FR_WRITTEN, L);
    // ...y del componente pedido, el orden de su escritor (ORDER=): ahi coloca
    // el servidor lo que este escritor no puede dar (1.22.1)
    if GPeticion.Componente <> '' then
    begin
      var C := ComponenteDeRuta(ARaiz, GPeticion.Componente);
      if C <> nil then
      begin
        Responde(FR_ORDER, ListaDelComponente(GPeticion.Componente, OrdenDelEscritor(C)));
        // ...y las que su clase no guarda nunca por su nombre (UNSTORED=), y lo
        // que define por codigo sin escritor (BYCODE=)
        var PorCodigo: string;
        Responde(FR_UNSTORED, ListaDelComponente(GPeticion.Componente, NuncaGuardadas(C, PorCodigo)));
        Responde(FR_BYCODE, ListaDelComponente(GPeticion.Componente, PorCodigo));
      end;
    end;
  finally
    Lineas.Free;
    Bin.Free;
  end;
end;

function ConvierteComoElIde: Integer;
var
  Bytes, Salida: TBytes;
begin
  Result := FR_RC_OK;
  ArrancaVigia(GPeticion.TiempoMs);
  try
    try
      Bytes := TFile.ReadAllBytes(GPeticion.Path);
      try
        if GPeticion.Convierte = 'text' then
          Salida := TEncoding.UTF8.GetBytes(DesignerBinarioATexto(Bytes))
        else
          Salida := DesignerTextoARecurso(Bytes);
      except
        on E: Exception do
        begin
          // el conversor solo lee esos bytes: lo que lanza es del contenido,
          // y la linea la dice el formato de ESTE proceso (su idioma)
          Responde(FR_LINE, IntToStr(LineaDeErrorDelParser(E.Message)));
          Responde(FR_NOT_LOADED, EnCabezaYPartes(E.ClassName, '', E.Message)); // bytes, sin fichero
          Responde(FR_ERROR, E.ClassName + ': ' + E.Message);
          Exit(FR_RC_ERROR);
        end;
      end;
      TFile.WriteAllBytes(GPeticion.Salida, Salida);
    except
      on E: Exception do
      begin
        // leer --path o escribir --out: del ayudante, no del form
        Responde(FR_ERROR, E.ClassName + ': ' + E.Message);
        Result := FR_RC_ERROR;
      end;
    end;
  finally
    ParaVigia;
  end;
end;

procedure TCargador.Lee(const AFichero: string; AInstancia: TComponent);
var
  Cab: TCabecera;
  Ancestro, Fichero: string;
  Cadena: TStringList;

  // una clase del MARCO (TForm, TCustomForm, TFrame, TDataModule...): la
  // dicen las cadenas de herencia de las raices que disena el IDE - la clase
  // de la raiz que se acaba de crear, el frame de este marco y el modulo de
  // datos, que se carga en la form oculta (revisor 7, M1: con la raiz sola se
  // perdia TDataModule) - y no una lista (norma 6; habia cuatro nombres a
  // mano). Esas no tienen fichero ni componentes que leer
  function DelMarco(const AClase: string): Boolean;

    function EnCadena(C: TClass): Boolean;
    begin
      while C <> nil do
      begin
        if SameText(C.ClassName, AClase) then
          Exit(True);
        C := C.ClassParent;
      end;
      Result := False;
    end;

  begin
    Result := EnCadena(AInstancia.ClassType) or EnCadena(ClaseFrame) or EnCadena(TDataModule);
  end;

begin
  // la cadena de ancestros, del mas lejano al propio fichero
  Cadena := TStringList.Create;
  try
    Cadena.Add(AFichero);
    Cab := Cabecera(AFichero);
    Fichero := AFichero;
    while SameText(Cab.Palabra, 'inherited') do
    begin
      Ancestro := AncestroDeClase(Fichero, Cab.Clase, FLeidos);
      if Ancestro = '' then
      begin
        // una VISTA FMX: ningun .pas declara su clase (la crea el IDE al
        // disenar), y su ancestro es el maestro que el .pas de este declara
        var Maestro := MaestroDeVista(Fichero, FLeidos);
        if (Maestro <> '') and (Cadena.IndexOf(Maestro) < 0) then
        begin
          Fichero := Maestro;
          Cadena.Insert(0, Fichero);
          Cab := Cabecera(Fichero);
          Continue;
        end;
        FAvisos.Add(MsgFmt(SN_RENDER_HEREDA_SIN_PAS_FMT, [ExtractFileName(Fichero)]));
        FSinLeer.Add(ExtractFileName(Fichero));
        Break;
      end;
      Fichero := FicheroDeClase(ExtractFilePath(AFichero), Ancestro, Fichero);
      if Fichero = '' then
      begin
        if not DelMarco(Ancestro) then
        begin
          if FNoCargan.Count > 0 then
            FAvisos.Add(MsgFmt(SN_RENDER_ANCESTRO_NO_CARGA_FMT, [Ancestro,
              string.Join(', ', FNoCargan.ToStringArray)]))
          else
            FAvisos.Add(MsgFmt(SN_RENDER_ANCESTRO_SIN_FICHERO_FMT, [Ancestro]));
          FSinLeer.Add(Ancestro);
        end;
        Break;
      end;
      if Cadena.IndexOf(Fichero) >= 0 then
        Break; // un ciclo no es una cadena
      Cadena.Insert(0, Fichero);
      Cab := Cabecera(Fichero);
    end;
    // quien nombra una clase es el fichero que se esta leyendo, no el form pedido
    var Antes := FLeyendo;
    var RaizAntes := FRaizLeyendo;
    try
      try
        for var F in Cadena do
        begin
          FLeyendo := F;
          FRaizLeyendo := AInstancia;
          LeeUno(F, AInstancia);
        end;
      except
        // el fichero donde nacio: el de mas dentro, el primero que lo apunta
        if FFalloEn = '' then
          FFalloEn := FLeyendo;
        raise;
      end;
    finally
      FLeyendo := Antes;
      FRaizLeyendo := RaizAntes;
    end;
  finally
    Cadena.Free;
  end;
end;

procedure TCargador.LeeRaiz(const AFichero, ANombre: string; ARaiz: TComponent);
begin
  // el nombre de la cabecera ANTES de leer: en modo diseno TReader lee el de
  // la raiz y lo descarta (ReadRootComponent), y el error de una propiedad de
  // un componente sin nombre lleva su ClassName - "ignored" decia nuestra
  // clase (TFormOculta, form_XXXX, TFrame) y sin linea (H9 de la 1.19.2).
  // Fuera de diseno lo pone el propio lector, unico entre los globales
  if (ANombre <> '') and (csDesigning in ARaiz.ComponentState) then
    ARaiz.Name := ANombre;
  Lee(AFichero, ARaiz);
  if ANombre <> '' then
    ARaiz.Name := ANombre;
end;


function ModuloCargado(const APatron: string): HMODULE;
var
  Nombre: array[0..MAX_PATH] of Char;
begin
  Result := 0;
  for var M in ModulosDelProceso do
    if (GetModuleFileName(M, Nombre, Length(Nombre)) > 0) and
       TRegEx.IsMatch(ExtractFileName(string(Nombre)), '(?i)' + APatron) then
      Exit(M);
end;

function ExportDe(AModulo: HMODULE; const ARutina: string): Pointer;
var
  Dos: PImageDosHeader;
  Nt: PImageNtHeaders;
  Dir: PImageExportDirectory;
  Nombres, Funciones: PDWORD;
  Ordinales: PWord;
  Base: NativeUInt;
begin
  Result := nil;
  if AModulo = 0 then
    Exit;
  Base := NativeUInt(AModulo);
  Dos := Pointer(Base);
  if Dos._lfanew <= 0 then
    Exit;
  Nt := Pointer(Base + NativeUInt(Dos._lfanew));
  if Nt.Signature <> IMAGE_NT_SIGNATURE then
    Exit;
  var Rva := Nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
  if Rva = 0 then
    Exit;
  Dir := Pointer(Base + Rva);
  Nombres := Pointer(Base + Dir.AddressOfNames);
  Ordinales := Pointer(Base + Dir.AddressOfNameOrdinals);
  Funciones := Pointer(Base + Dir.AddressOfFunctions);
  for var I := 0 to Integer(Dir.NumberOfNames) - 1 do
  begin
    var Nombre := string(PAnsiChar(Base + PDWORD(NativeUInt(Nombres) + NativeUInt(I) * SizeOf(DWORD))^));
    // '@Unidad@Rutina$<tipos>': la rutina entera, entre '@' y '$'; una
    // VARIABLE se exporta sin tipos: '@Unidad@Variable'
    if Nombre.Contains('@' + ARutina + '$') or Nombre.EndsWith('@' + ARutina) then
    begin
      var Ordinal := PWord(NativeUInt(Ordinales) + NativeUInt(I) * SizeOf(Word))^;
      Exit(Pointer(Base + PDWORD(NativeUInt(Funciones) + NativeUInt(Ordinal) * SizeOf(DWORD))^));
    end;
  end;
end;

initialization
  // lo que matamos, lo limpiamos; y lo que nunca finaliza (los bpl), tambien
  ExitProcessProc := LimpiaAtomosAlSalir;
  // el protocolo, en UTF-8: con stdout en un pipe la RTL escribia en la ANSI y
  // el servidor lo leia con otra pagina - un nombre con acento llegaba roto en
  // WRITTEN=, ROOT=, NONVISUALS= e IGNORED= (revisor 5 de la noche, A1: el
  // juez del orden perdia al hermano y aceptaba en falso)
  SetTextCodePage(Output, CP_UTF8);
  GRegistradas := TDictionary<TClass, Boolean>.Create;
  GModulosDeDiseno := TStringList.Create;
  GModulos := TList<HMODULE>.Create;
  GModulosDatos := TDictionary<string, HMODULE>.Create;

finalization
  GModulosDatos.Free;
  GModulos.Free;
  GRegistradas.Free;
  GModulosDeDiseno.Free;
  GConocidos.Free;

end.
