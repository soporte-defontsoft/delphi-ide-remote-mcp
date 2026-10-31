unit Lsp.FormRender;

{ delphi_designer command=preview, la mitad del SERVIDOR: lanza los
  renderizadores de forms (src\Render: DelphiFormRenderVcl y
  DelphiFormRenderFmx, junto al exe del servidor como DelphiStyleConvert) y
  lee lo que contestan. Cada pieza, una vez:

    FormRenderExe          donde esta el renderizador de un framework: el
                           nombre del exe solo se compone aqui
    ComponeOrdenDeRender   LA orden, un interruptor por parametro de preview
                           (test_paisaje vigila que nadie mas la componga);
                           su inversa es ParseaArgumentos del ayudante
    LeeRespuestaDeRender   la inversa de FormRenderProtocolo.inc, que incluyen
                           el ayudante (el escritor, FormRender.Comun.Responde)
                           y este lector
    CorreRender            lo lanza con RunCapturedIn y su tiempo limite,
                           FUERA del AppContainer de delphi_test: el contenedor
                           no deja crear ventanas, y el VCL y el FMX mueren al
                           crear la form (medido 6 y 7-oct-2026, vault
                           renderform-ayudantes-2026-10-07). El ayudante lleva
                           ademas su propio vigia, un poco antes, para contestar
                           el por que.

  Por que procesos aparte y no una unidad del servidor: los paquetes de
  diseno del IDE se cargan EN el renderizador; si uno revienta muere el
  renderizador y el servidor contesta el error (src\Render\README.md). }

interface

uses
  Lsp.Styles,       // TStyleDoc: la linea de lo que dijo el lector (LineaDeLoLeido)
  Lsp.DesignerMeta; // TPropiedadDelUsuario: lo que publica una clase del usuario

type
  TPeticionRender = record
    Framework: string;         // vcl | fmx
    Path: string;              // el .dfm/.fmx, ya pasado por la puerta de lectura
    Salida: string;            // el .png que deja CorreRender, en la casa del servidor
    Estados: TArray<string>;   // Componente.Propiedad=Valor, uno por entrada
    Componente: string;        // '' = la form entera
    Estilo: string;            // fichero (ya por la puerta), plataforma, none o ''
    NoVisuales: Boolean;       // dibujar los no visuales
    Bds: string;               // la version del Delphi del servidor (37.0)
    RaizBds: string;           // su carpeta: el contenedor no lee el registro
    FicheroPaquetes: string;   // los .bpl que puede cargar, una ruta por linea (lo pone CorreRender)
    Raiz: string;              // form | frame, por el lector de clases del servidor; '' = que mire el ayudante
    // el JUEZ de lo que guarda el IDE (3.11 de la 1.18.0): sin png, el form
    // cargado y escrito por TWriter (WRITTEN=); Carpeta, la del form de verdad
    // cuando Path es una propuesta escrita en otra (sus hermanos y su .pas: se le
    // copian de ahi)
    Escribe: Boolean;
    Carpeta: string;
    // con Escribe, el que se acaba de soltar (insert, set parent=): el juez lo
    // deja como el disenador al soltarlo (FMX: el ultimo de su tabulador, V72)
    Soltado: string;
    // EL conversor del IDE (V71): text (binario -> texto) o binary (texto ->
    // binario), los bytes de Path escritos en Salida; sin form ni paquetes.
    // Lo pone ConversionDelIde
    Convierte: string;
    // --unreadableclasses: la pregunta al hacer la caja de paquetes; nada mas en la orden
    ClasesSinLeer: Boolean;
    // --boxes: sin png, donde queda cada control (BOX=). Lo pone delphi_designer layout
    Cajas: Boolean;
    // cuanto puede tardar cada ayudante, si no es RENDER_TIEMPO_MS: quien tiene otra
    // respuesta que dar no espera lo que espera un preview
    PlazoMs: Integer;
    // forms del proyecto, de otra carpeta, de las clases que el ayudante dijo que le
    // faltaban (ancestros y frames, V120b de la 1.24). Lo pone CorreRender
    Lejanos: TArray<string>;
  end;

  { Una propiedad que el lector se salto (IGNORED=, el OnError de TReader que
    el ayudante contesta Ignore), o el error que lo paro (NOTLOADED=): lo que
    dijo tal cual y sus partes, que da el ayudante con el formato que lo
    compuso (SPropertyException, en SU idioma: PartesDeLectura). Uno de otra
    forma queda solo en Texto (David, 7-oct-2026: que guien al modelo). }
  TIgnorada = record
    Texto: string;
    Componente, Propiedad, Motivo: string; // '' si no casa
    // la clase de la excepcion si NO era del lector (el codigo de un
    // componente: IBX sin gds32.dll, un AV de un bpl); '' si era del lector
    // (EFilerError, EParserError: el fichero). Lo dice el ayudante (IGNORED=)
    Origen: string;
  end;

  { Un no visual de la raiz (NONVISUALS=<Nombre:Clase,...>): el ayudante lo
    escribe 'Nombre:Clase' y aqui se lee en sus partes - lo troceaba la tool
    (segunda revision de la 1.17.0, 2.3 de la 1.18.0). }
  TNoVisual = record
    Nombre, Clase: string;
  end;

  { Un fichero que el ayudante leyo para cargar el form (READ=<sha256>|<ruta>):
    un ancestro, un frame, el .pas de la cadena, con la huella de los bytes
    que uso (B5 rev6 de la 1.18.2). }
  TLeidoPorElJuez = record
    Huella, Ruta: string;
  end;

  { Un control donde queda de verdad (BOX=), en coordenadas del form }
  TCajaDeRender = record
    Ruta, Clase, Padre: string; // Padre: su ruta, '' si es la raiz
    X, Y, W, H: Integer;
    Visible: Boolean;
    // donde esta de verdad, si no es su padre: el contenido de un TTabItem o un TScrollBox
    EnContenido: Boolean;
    CX, CY, CW, CH: Integer;
  end;

  TRespuestaRender = record
    Fallo: string;             // '' = hay imagen; si no, el mensaje para el agente
    Error: string;             // ERROR= del ayudante, tal cual
    // NOTLOADED=: lo que fallo fue el LECTOR mientras cargaba el form - el
    // fichero, no el ayudante (DSGN-061 de la 1.20)
    NoCarga: Boolean;
    Parada: TIgnorada;         // ...y el error con el que paro, en sus partes
    ClaseDeLaParada: string;   // ...y la clase de su excepcion (NOTLOADED=)
    LineaDeLaParada: Integer;  // LINE=: con --convert, la linea que nombra el parser (0, ninguna)
    Codigo: Cardinal;          // su codigo de salida
    Captura: string;           // CAPTURE=
    Ancho, Alto: Integer;      // SIZE=
    Dpi, Sesion: Integer;      // DPI=, SESSION=
    RaizNombre, RaizClase, RaizTipo: string; // ROOT=<nombre>:<clase>:<form|frame>
    Fidelidad, Estilo, Paquetes: string;     // FIDELITY=, STYLE=, PACKAGES=
    Componentes: Integer;      // COMPONENTS=
    Sustituidas, Avisos: TArray<string>;
    Ignoradas: TArray<TIgnorada>;
    NoVisuales: TArray<TNoVisual>; // NONVISUALS=
    NoVisualesDibujados: Integer; // NONVISUAL=
    HayRect: Boolean;          // RECT= del componente pedido
    RectX, RectY, RectW, RectH: Integer;
    MsCarga, MsPintado: Integer; // MS=
    MsTotal: Int64;            // lo que tardo de verdad, lanzamiento incluido
    Escrito: TArray<string>;   // WRITTEN=: el form como lo guarda el IDE, con sus blancos
    // ORDER=: del componente pedido, sus propiedades publicadas en el orden en
    // que las escribe su escritor (1.22.1)
    Orden: TArray<string>;
    // UNSTORED=: del componente pedido, las publicadas que su clase declara
    // stored False - el escritor no las escribe nunca por su nombre (1.22.1)
    NuncaGuardadas: TArray<string>;
    // UNAPPLIED=: lo que el lector leyo y no pudo aplicar - el metodo de un
    // evento, una referencia que no resolvio -, por su valor (1.22.1)
    NoAplicados: TArray<string>;
    SinLeer: TArray<string>;   // PARTIAL=: sin que ancestro (o fichero) se leyo el form
    ClasesSinLeer: TArray<string>; // UNREADABLECLASS=: las clases COM que su contenedor no busca
    Cajas: TArray<TCajaDeRender>;  // BOX=
    Leidos: TArray<TLeidoPorElJuez>; // READ=: lo que leyo para cargarlo, con su huella
  end;

{ El renderizador de AFramework (vcl|fmx) junto al exe del servidor; '' si
  no esta. ANombre sale siempre, para decir cual falta. }
function FormRenderExe(const AFramework: string; out ANombre: string): string;

{ LA orden de un render: '' y AOrden, o el rechazo. Un valor con comillas o
  con un caracter de control se niega: el lector de argumentos de Delphi no
  tiene escape para una comilla, y lo que fuera detras seria OTRO
  interruptor (un --out fuera de la jaula). }
function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

{ El --root de un render (form | frame): lo que es la raiz de la unidad para
  el IDE, por sus jueces (Lsp.ProjectUnits.RaizDeDesigner, EL lector: su cadena
  contra la tabla del marco, sin esperarla, y si no llega, el registro del
  IDE en un .dproj que la lista), y solo si su designer es el form pedido (un X.fmx al lado
  de un X.dfm: la unidad es del .dfm). Un modulo se lee en la form. Si no se
  sabe, '': que mire el ayudante. La unidad, ya por la puerta de lectura de
  quien llama. Nunca lanza (segunda revision de la 1.17.0: un sufijo
  adivinado viajaba como un hecho; despues, una lista de nombres). }
function RaizParaElRender(const ARuta: string): string;

{ La clase en la que el lector del IDE (el ayudante) lee la raiz, por la
  clase de raiz que dijo (RaizTipo: frame o form): su frame o su form. La
  componian igual, a mano, lo que no cargo (LoQueNoCargo) y preview. }
function ClaseDelSustituto(const ARaizTipo: string): string;

{ Un mensaje del lector EN PARTES (FR_PARTES_SEP, de IGNORED= y NOTLOADED=)
  -> TIgnorada: EL lector, inverso de FormRender.Comun.LecturaEnPartes.
  Componente es el Name del objeto (o su clase, el de un item de una
  coleccion: lo que pone TReader) y Propiedad su ruta (Font.Size). Aqui se
  partia el texto con el formato INGLES, y el RTL del ayudante habla el idioma
  de Windows (medido el 18-oct-2026: en aleman no nombraba nada). }
function PartesDeLectura(const AValor: string): TIgnorada;

{ La linea (1-based) de ADoc que nombra lo que dijo el lector en AI - su
  componente y su propiedad -, o 0 si no esta en ESTE fichero (de un
  ancestro, de un frame) o no nombra ninguna. EL localizador: lo hacia a mano
  el preview para sus ignored, y ahora lo piden tambien LoQueNoCargo. }
function LineaDeLoLeido(ADoc: TStyleDoc; const AI: TIgnorada): Integer;

{ Si lo que el lector se salto (AI) es una propiedad de la RAIZ (ARaizNombre)
  que publica una clase del USUARIO (APublicadas: PublicadasPorElUsuario): el
  renderizador no carga las clases del usuario y no la conoce, asi que no es
  un error del form (DSGN-152); ASuya, cual. EL juicio de preview, que dice
  cuales son, y de LoQueNoCargo, que no las da por lo que no carga. }
function IgnoradaDelUsuario(const ARaizNombre: string; const AI: TIgnorada;
  const APublicadas: TArray<TPropiedadDelUsuario>; out ASuya: TPropiedadDelUsuario): Boolean;

{ Lo que el LECTOR del IDE no cargo de un form (R: lo que se salto y, si fue
  suyo - NoCarga -, el error que lo paro), uno por linea, lo que dijo TAL
  CUAL con la linea de ADoc que nombra (SF_DSGN_LINEA_AVISO_FMT, la forma de
  los avisos del lint); sin linea, solo lo que dijo. Sin repetir: el error
  que lo paro suele ser el ultimo que se salto. ADoc nil: todo sin linea.
  AForm, el form de verdad (su .pas dice lo que publica el usuario).
  ANoConfirmado: el motivo de DSGN-154 por lo que NO va entre lo que no carga,
  porque no se puede afirmar del fichero: algo de la RAIZ que es de su clase y
  no de la form en la que la lee el lector (DeLaRaizQueElLectorNoVe), una
  excepcion del codigo de un componente (DelCodigoDeUnComponente) o las partes de un
  componente de una clase que no esta instalada (PartesDeClaseNoInstalada). }
function LoQueNoCargo(const R: TRespuestaRender; ADoc: TStyleDoc; const AForm: string;
  out ANoConfirmado: string): TArray<string>;

{ Lo que el lector se salto por una excepcion que NO era suya (Origen: la
  clase, que dice el ayudante por la jerarquia de la RTL): la lanzo el codigo
  de un componente - IBX sin gds32.dll, un TActionManager sin su unidad de
  estilo, un AV de un bpl -, no la lectura de una linea. No es del fichero,
  que se sepa: DSGN-154 con el motivo, no un aviso (corpus del 18-oct-2026).
  Un "Ancestor for X not found" si es del lector (EReadError) y sigue siendo
  aviso: lo mide V3 de test_lint_vistas_1202. }
function DelCodigoDeUnComponente(const AI: TIgnorada): Boolean;

{ El componente de AI elige sus PARTES por una clase que esta instalacion no
  tiene: una propiedad suya '...ClassName' con un nombre de clase que la tabla
  del marco no conoce (ItemAppearanceClassName = 'TMultiDetailItemAppearance',
  que registra una unidad del proyecto y el lector no carga): lo que el lector
  salto debajo no se puede confirmar. AProp y AClase, cuales. Sin tabla, o sin
  documento, no se sabe: False (y queda como aviso). }
function PartesDeClaseNoInstalada(ADoc: TStyleDoc; const AI: TIgnorada; AFmx: Boolean;
  out AProp, AClase: string): Boolean;

{ Lo que dijo el lector de AI, con la clase de la excepcion delante si no era
  suya ('EIBClientError: ...'): EL compositor, para el lint (LoQueNoCargo) y
  el preview (revisor de la 1.20.2: dos emisores). }
function TextoDeIgnorada(const AI: TIgnorada): string;

{ La salida del renderizador -> sus campos (las lineas '#' son traza). }
function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;

{ Lanza el renderizador y lee lo que contesta. Fallo = '' si hay imagen en
  APeticion.Salida; si no, el mensaje que toca (el ERROR= del ayudante tal
  cual si ya lleva su etiqueta). Nunca lanza.
  Siempre DENTRO de un contenedor por llamada (V65 de la 1.24; Lsp.Sandbox): el
  codigo de diseno de los paquetes lee y escribe lo que un form le pida, y ahi
  no alcanza nada de las raices, del servidor ni de la red. Sus ficheros van
  COPIADOS a la carpeta de esta llamada, lo que dice se traduce de vuelta a las
  rutas de verdad, y sin contenedor no se dibuja (DSGN-177). }
function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;
{ Si esos bytes son un programa o una biblioteca, por su cabecera y no por su nombre:
  de eso no se copia nada al lado del ayudante. }
function EsEjecutable(const ABytes: TArray<Byte>): Boolean;

{ La ruta de un paquete de la lista del IDE (AValor, el nombre del valor en
  Known Packages: $(BDSBIN)\x.bpl o una ruta) con sus macros resueltas; una sin
  valor se queda, y el paquete sale como que falta: vacia daria \Bpl\x.bpl, la
  raiz de la unidad actual. }
function RutaDePaqueteDelIde(const AValor, ARaiz, AComun: string): string;

type
  { Una clase COM en proceso: su CLSID, su biblioteca y su modelo de hilos }
  TClaseCom = record
    Clsid, Dll, Hilos: string;
  end;

{ El manifiesto con el que un ayudante tiene AClases sin buscarlas en el
  registro: un <file> por biblioteca, con su ruta. De dos bibliotecas de igual
  nombre, la primera: un manifiesto no distingue un <file> de otro por su
  carpeta. '' si no hay clases. }
function ManifiestoDeClases(const AClases: TArray<TClaseCom>): string;

{ EL JUEZ de lo que guarda el IDE (3.11 de la 1.18.0; norma 6: lo que dice un
  juez real se le pregunta): ATexto, un form PROPUESTO para APath (en AEnc),
  cargado por el renderizador de su framework como lo carga el designer -
  modo diseno, los paquetes del IDE, sus frames y ancestros desde la carpeta
  de APath - y escrito por TWriter, lo que hace el IDE al guardar: AEscrito.
  ASustituidas, las clases que no pudo cargar (su sustituto no sabe como las
  escribe el IDE); ASinLeer, los ancestros sin los que leyo el form (PARTIAL=:
  un juicio a medias); ALeidos, los ficheros que leyo para cargarlo (READ=:
  quien escribe lo juzgado los vuelve a mirar, CambioEnLoLeido). '' si bien;
  si no, el fallo, en AError el ERROR= del ayudante tal cual y, si lo que
  fallo fue el lector (NOTLOADED=), en AParada su error en partes. La
  propuesta se escribe en una carpeta de descarga del temporal del disenador
  y se borra siempre. ASoltado: el componente que se acaba de soltar en el
  form (TPeticionRender.Soltado). }
function ComoLoEscribeElIde(const APath, ATexto, AEnc: string; out AEscrito: string;
  out ASustituidas, AAvisos, ASinLeer: TArray<string>; out ALeidos: TArray<TLeidoPorElJuez>;
  out AError: string; out AParada: TIgnorada; const ASoltado: string = ''): string;

{ EL JUEZ de las propiedades de UN componente (1.22.1): ATexto, un form
  PROPUESTO para APath, cargado y escrito como lo guarda el IDE (el de
  ComoLoEscribeElIde) y, del componente AComponente, el orden en que su
  escritor escribe sus propiedades (Orden). La respuesta entera, con lo que
  sustituyo, salto o no leyo; Fallo si no se pudo preguntar. }
function PropiedadesComoLasEscribeElIde(const APath, ATexto, AEnc, AComponente: string): TRespuestaRender;

{ Los colores sin alfa del form FMX APath con el texto ATexto (en AEnc): los
  candidatos de la gramatica (Lsp.Styles.CandidatosSinAlfa) que no estaban
  ya en AAntes (el texto de antes de una edicion; '' = todos), juzgados por
  el escritor del IDE (ComoLoEscribeElIde: el ayudante, un proceso aparte,
  FUERA de los cerrojos) con EL emparejado de Lsp.Styles. Sin candidatos
  nuevos no se le pregunta: un form normal no lo paga. delphi_edit escribia
  Fill.Color = xFF7DFC6 y el lint decia CLEAN (V154 de la 1.23.1, medido).
  False si no se pudo preguntar, o si el ayudante sustituyo una clase o leyo
  sin un ancestro (lo que escribe no seria lo que guarda el IDE). Nunca
  lanza. }
function ColoresSinAlfaDeForm(const APath, ATexto, AEnc, AAntes: string;
  out AColores: TArray<TColorSinAlfa>): Boolean;
{ ...y su nota (DSGN-176 y una linea por color), o []: la del lint y la de
  tras una edicion (Lsp.Patch.LintDeForm, con el lector) }
function NotaDeColoresSinAlfa(const APath, ATexto, AEnc, AAntes: string): TArray<string>;

{ CON el cerrojo, justo antes de escribir lo que juzgo el ayudante: '' si
  cada fichero que leyo para cargar el form (ALeidos) sigue con los bytes de
  su huella; si no, el nombre del primero que cambio (o que ya no se deja
  leer). La huella, por EL hash de la casa (Sha256DeBytes), el mismo con el
  que la compone el ayudante; los bytes, por la puerta de leer. }
function CambioEnLoLeido(const ALeidos: TArray<TLeidoPorElJuez>): string;

{ EL JUEZ de un form ENTERO por el lector del IDE (DSGN-061 de la 1.20):
  ATexto cargado como lo carga el designer - el mismo ayudante y la misma
  carpeta de ComoLoEscribeElIde - y lo que no cargo, con las lineas de ATexto
  (LoQueNoCargo). Lo piden el lint y el juicio de lo escrito cuando las
  tablas callan: el valor de una propiedad que la clase guarda por codigo no
  tiene tipo en la tabla, y solo lo juzga el lector (FontColor = -65536 en un
  TEdit FMX: delphi_edit lo escribia sin avisar y el lint decia CLEAN de un
  form que no abria). ANoPregunto: por que no se le pudo preguntar (sin
  renderizador, el tiempo, un paquete que revento al cargar): entonces no hay
  lineas y no se sabe. Nunca lanza. }
function LoQueNoCargaElIde(const APath, ATexto, AEnc: string; out ANoPregunto: string): TArray<string>;

{ LO COMUN de una peticion de render para el form APath (ya por la puerta de
  lectura): el framework (AFramework, o el del fichero si va vacio), la ruta,
  el Delphi del servidor y form o frame por EL lector de clases si su .pas se
  deja leer. Lo componian a mano preview y el juez (revisor 5 de la noche,
  B3); el resto (salida, estado, estilo...) lo pone cada uno. }
function PeticionDeRender(const APath, AFramework: string): TPeticionRender;

{ EL CONVERSOR del IDE (V71 de la 1.23.1): ABytes, un form binario (AATexto)
  o de texto, en la otra forma - el texto que ensena "Ver como texto" (sus
  bytes en UTF-8, sin BOM) o el binario de disco con su cabecera de recurso -
  por el ayudante de 32 bits (--convert), como el IDE: el servidor es Win64,
  donde Extended es Double, y un flotante convertido aqui perdia sus ultimas
  cifras (to-text escribia 17 decimales y otras cifras, to-binary otros
  bytes; medido con convert.exe el 27-oct-2026). '' si se le pudo preguntar:
  con ASalida, o con AClase, AMensaje y ALinea (la que nombra el parser, 0 si
  ninguna) si el CONTENIDO no se convierte; si no (sin ayudante, el tiempo),
  el fallo. Los bytes van y vuelven por una carpeta de descarga de ESTA
  llamada en el temporal del servidor, que se borra siempre. Nunca lanza. }
function ConversionDelIde(const ABytes: TArray<Byte>; AATexto: Boolean; out ASalida: TArray<Byte>;
  out AClase, AMensaje: string; out ALinea: Integer): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  Winapi.Windows,
  MCPServer.Logger,
  System.RegularExpressions,
  System.Win.Registry,
  Lsp.Dproj,        // XmlEscape: las rutas del manifiesto de la caja
  Lsp.Guard,
  Lsp.BuildRunner,  // RunCapturedEnContenedor: el lanzador de los programas externos
  Lsp.Sandbox,      // el contenedor del ayudante y el entorno que lleva
  Lsp.TodoONada,    // HuellaDeFichero: la generacion de la caja de paquetes
  Lsp.ProjectUnits, // RaizDeDesigner: a que raiz llega la unidad de un designer
  Lsp.DesignerForma, // UnidadDeDesigner
  Lsp.Texts,
  Lsp.DesignerBin,
  Lsp.Casa,         // ServerDir: la carpeta del exe del servidor
  Lsp.Patch,        // EscribeTexto: la puerta de escribir, la propuesta del juez
  Lsp.Codificacion, // EncKindOf
  Lsp.Discovery,    // DiscoverRadStudio: el Delphi del servidor
  Lsp.ShaCache,     // Sha256DeBytes: la huella de READ=, la misma que compone el ayudante
  Lsp.Rutas,        // RutaDesde: EL resolutor de una ruta leida de un fichero
  Lsp.NetDrives,    // PrefijoSinBarra y ConBarrasDeWindows: la forma de una ruta del IDE
  Lsp.Listas,
  System.StrUtils,
  Lsp.ProcessLaunch;

const
  {$I ..\Render\FormRenderProtocolo.inc}

  // Lo que espera el servidor, y el vigia del ayudante un poco antes: asi es
  // el ayudante quien contesta por que se paro (RENDER-007). Medido el
  // 7-oct-2026: una form estandar 20 ms, FichaCliente con 112 paquetes del
  // IDE ~1,2 s (9,4 s la primera vez, con la cache de disco fria).
  RENDER_TIEMPO_MS = 75000;
  RENDER_TIEMPO_AYUDANTE_MS = 60000;

  // Windows no pudo cargar el exe o sus paquetes de ejecucion (rtl/vcl/fmx
  // del Delphi): no hay ERROR= porque no llego a correr nada suyo
  STATUS_DLL_NOT_FOUND_ = $C0000135;
  STATUS_ENTRYPOINT_NOT_FOUND_ = $C0000139;
  STATUS_INVALID_IMAGE_FORMAT_ = $C000007B;

function FormRenderExe(const AFramework: string; out ANombre: string): string;
begin
  if SameText(AFramework, 'fmx') then
    ANombre := 'DelphiFormRenderFmx.exe'
  else
    ANombre := 'DelphiFormRenderVcl.exe';
  Result := ServerDir(ANombre);
  if not TFile.Exists(Result) then
    Result := '';
end;

function RaizParaElRender(const ARuta: string): string;
begin
  // EL lector de la raiz de un designer (Lsp.ProjectUnits); lo que no sabe,
  // que lo mire el ayudante
  case RaizDeDesigner(ARuta) of
    rdFrame: Result := 'frame';
    rdForm, rdModulo: Result := 'form';
  else
    Result := '';
  end;
end;

function ClaseDelSustituto(const ARaizTipo: string): string;
begin
  // el frame que crea el ayudante es el del marco (Lsp.DesignerMeta), y su
  // form oculta, una TForm
  if SameText(ARaizTipo, 'frame') then
    Result := DesignClassDeFrame(False)
  else
    Result := 'TForm';
end;

{ Un valor que viaja como UN argumento entre comillas }
function ValorDeArgumento(const AValor: string): Boolean;
begin
  for var C in AValor do
    if (C = '"') or (C < ' ') then
      Exit(False);
  Result := True;
end;

function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

  function Arg(const AInterruptor, AValor: string): string;
  begin
    Result := ' ' + AInterruptor + ' ' + ComillasSinEscape(AValor);
  end;

begin
  Result := '';
  AOrden := '';
  if APeticion.ClasesSinLeer then
  begin
    AOrden := ComillasSinEscape(AExe) + ' --unreadableclasses';
    Exit;
  end;
  // un valor vacio no se pasa nunca: el lector de Delphi se salta un "" y
  // tomaria el interruptor siguiente como valor
  for var V in TArray<string>.Create(APeticion.Path, APeticion.Salida,
    APeticion.Componente, APeticion.Estilo, APeticion.Bds, APeticion.RaizBds,
    APeticion.FicheroPaquetes) + APeticion.Estados do
    if not ValorDeArgumento(V) then
      Exit(MsgFmt(SR_DESIGNER_VALOR_CON_COMILLAS_FMT, [V]));
  AOrden := ComillasSinEscape(AExe) + Arg('--path', APeticion.Path);
  // el conversor (V71) ni carga ni pinta: los bytes de --path, en --out
  if APeticion.Convierte <> '' then
    AOrden := AOrden + ' --convert ' + (if APeticion.Convierte = 'text' then 'text' else 'binary') +
      Arg('--out', APeticion.Salida)
  // el juez no pinta: sin --out (3.11)
  else if APeticion.Escribe then
    AOrden := AOrden + ' --writeback on'
  else if APeticion.Cajas then
    AOrden := AOrden + ' --boxes --nonvisual off'
  else
    AOrden := AOrden + Arg('--out', APeticion.Salida) +
      ' --nonvisual ' + (if APeticion.NoVisuales then 'on' else 'off');
  AOrden := AOrden + ' --timeout ' + IntToStr(RENDER_TIEMPO_AYUDANTE_MS);
  if APeticion.Bds <> '' then
    AOrden := AOrden + Arg('--bds', APeticion.Bds);
  if APeticion.RaizBds <> '' then
    AOrden := AOrden + Arg('--bdsroot', APeticion.RaizBds);
  if APeticion.FicheroPaquetes <> '' then
    AOrden := AOrden + Arg('--knownfile', APeticion.FicheroPaquetes);
  for var E in APeticion.Estados do
    if E <> '' then
      AOrden := AOrden + Arg('--state', E);
  if APeticion.Componente <> '' then
    AOrden := AOrden + Arg('--component', APeticion.Componente);
  if APeticion.Escribe and (APeticion.Soltado <> '') then
    AOrden := AOrden + Arg('--dropped', APeticion.Soltado);
  if (APeticion.Raiz = 'form') or (APeticion.Raiz = 'frame') then
    AOrden := AOrden + ' --root ' + APeticion.Raiz;
  if APeticion.Estilo <> '' then
    AOrden := AOrden + Arg('--style', APeticion.Estilo);
end;

function PartesDeLectura(const AValor: string): TIgnorada;
var
  P1, P2, P3: Integer;
begin
  Result := Default(TIgnorada);
  Result.Texto := AValor;
  // las tres partes no llevan el separador (el ayudante no parte si lo
  // llevaran) y el texto si puede: Split con tope tira lo que sobra
  P1 := AValor.IndexOf(FR_PARTES_SEP);
  if P1 < 0 then
    Exit;
  P2 := AValor.IndexOf(FR_PARTES_SEP, P1 + 1);
  if P2 < 0 then
    Exit;
  P3 := AValor.IndexOf(FR_PARTES_SEP, P2 + 1);
  if P3 < 0 then
    Exit;
  Result.Componente := AValor.Substring(0, P1);
  Result.Propiedad := AValor.Substring(P1 + 1, P2 - P1 - 1);
  Result.Motivo := AValor.Substring(P2 + 1, P3 - P2 - 1);
  Result.Texto := AValor.Substring(P3 + 1);
end;

{ EL lector de un valor <cabeza>|<mensaje en partes> (IGNORED=, NOTLOADED=),
  la inversa de EnCabezaYPartes (FormRender.Comun): la cabeza en ACabeza y el
  mensaje en sus partes. Sin separador no hay cabeza y todo es el texto: lo
  que no se sabe partir no se pierde. V106 de la 1.23.1: eran dos lectores, y
  el de NOTLOADED= no leia nada sin cabeza o sin separador. }
function DeCabezaYPartes(const AValor: string; out ACabeza: string): TIgnorada;
var
  P: Integer;
begin
  ACabeza := '';
  P := AValor.IndexOf(FR_PARTES_SEP);
  if P < 0 then
    Exit(PartesDeLectura(AValor));
  ACabeza := AValor.Substring(0, P);
  Result := PartesDeLectura(AValor.Substring(P + 1));
end;

function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;
var
  L, V: string;
  Trozos: TArray<string>;
  P: Integer;

  function Es(const AClave: string): Boolean;
  begin
    Result := L.StartsWith(AClave);
    if Result then
      V := L.Substring(Length(AClave));
  end;

begin
  Result := Default(TRespuestaRender);
  Result.Sesion := -1;
  for var Linea in LineasDelTexto(ASalida) do
  begin
    L := Linea;
    if (L = '') or L.StartsWith('#') then
      Continue;
    if Es(FR_CAPTURE) then
      Result.Captura := V
    else if Es(FR_SIZE) then
    begin
      Trozos := V.Split(['x']);
      if Length(Trozos) = 2 then
      begin
        Result.Ancho := StrToIntDef(Trozos[0], 0);
        Result.Alto := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_DPI) then
      Result.Dpi := StrToIntDef(V, 0)
    else if Es(FR_SESSION) then
      Result.Sesion := StrToIntDef(V, -1)
    else if Es(FR_ROOT) then
    begin
      Trozos := V.Split([':']);
      if Length(Trozos) = 3 then
      begin
        Result.RaizNombre := Trozos[0];
        Result.RaizClase := Trozos[1];
        Result.RaizTipo := Trozos[2];
      end;
    end
    else if Es(FR_FIDELITY) then
      Result.Fidelidad := V
    else if Es(FR_PACKAGES) then
      Result.Paquetes := V
    else if Es(FR_COMPONENTS) then
      Result.Componentes := StrToIntDef(V, 0)
    else if Es(FR_SUBSTITUTED) then
      Result.Sustituidas := V.Split([','], TStringSplitOptions.ExcludeEmpty)
    else if Es(FR_IGNORED) then
    begin
      // <de quien>|<mensaje en partes> (FR_ORIGEN_LECTOR = del lector)
      var Cabeza: string;
      var Ig := DeCabezaYPartes(V, Cabeza);
      if Cabeza <> FR_ORIGEN_LECTOR then
        Ig.Origen := Cabeza;
      Result.Ignoradas := Result.Ignoradas + [Ig];
    end
    else if Es(FR_NONVISUALS) then
      for var Item in V.Split([','], TStringSplitOptions.ExcludeEmpty) do
      begin
        var NV: TNoVisual;
        P := Item.LastIndexOf(':');
        NV.Nombre := Item;
        NV.Clase := '';
        if P >= 0 then
        begin
          NV.Nombre := Item.Substring(0, P);
          NV.Clase := Item.Substring(P + 1);
        end;
        Result.NoVisuales := Result.NoVisuales + [NV];
      end
    else if Es(FR_NONVISUAL) then
      Result.NoVisualesDibujados := StrToIntDef(V, 0)
    else if Es(FR_RECT) then
    begin
      // <Nombre>=<izq>,<arriba>,<ancho>,<alto>: el nombre no lleva '='
      P := V.LastIndexOf('=');
      Trozos := V.Substring(P + 1).Split([',']);
      if (P > 0) and (Length(Trozos) = 4) then
      begin
        Result.HayRect := True;
        Result.RectX := StrToIntDef(Trozos[0], 0);
        Result.RectY := StrToIntDef(Trozos[1], 0);
        Result.RectW := StrToIntDef(Trozos[2], 0);
        Result.RectH := StrToIntDef(Trozos[3], 0);
      end;
    end
    else if Es(FR_STYLE) then
      Result.Estilo := V
    else if Es(FR_WARNING) then
      Result.Avisos := Result.Avisos + [V]
    else if Es(FR_MS) then
    begin
      Trozos := V.Split([',']);
      if Length(Trozos) = 2 then
      begin
        Result.MsCarga := StrToIntDef(Trozos[0], 0);
        Result.MsPintado := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_WRITTEN) then
      Result.Escrito := Result.Escrito + [V]
    else if Es(FR_UNREADABLE_CLASS) then
      Result.ClasesSinLeer := Result.ClasesSinLeer + [V]
    else if Es(FR_BOX) then
    begin
      // <ruta>|<clase>|<padre>|<x>,<y>,<ancho>,<alto>|<visible>|<contenido>: un nombre no lleva '|'
      Trozos := V.Split(['|']);
      if Length(Trozos) = 6 then
      begin
        var Medidas := Trozos[3].Split([',']);
        if Length(Medidas) = 4 then
        begin
          var Caja: TCajaDeRender;
          Caja.Ruta := Trozos[0];
          Caja.Clase := Trozos[1];
          Caja.Padre := Trozos[2];
          Caja.X := StrToIntDef(Medidas[0], 0);
          Caja.Y := StrToIntDef(Medidas[1], 0);
          Caja.W := StrToIntDef(Medidas[2], 0);
          Caja.H := StrToIntDef(Medidas[3], 0);
          Caja.Visible := Trozos[4] = '1';
          var Contenido := Trozos[5].Split([',']);
          Caja.EnContenido := Length(Contenido) = 4;
          if Caja.EnContenido then
          begin
            Caja.CX := StrToIntDef(Contenido[0], 0);
            Caja.CY := StrToIntDef(Contenido[1], 0);
            Caja.CW := StrToIntDef(Contenido[2], 0);
            Caja.CH := StrToIntDef(Contenido[3], 0);
          end;
          Result.Cajas := Result.Cajas + [Caja];
        end;
      end;
    end
    else if Es(FR_ORDER) then
    begin
      // <Nombre>=<prop>,<prop>,...: el nombre no lleva '='
      P := V.IndexOf('=');
      if P > 0 then
        Result.Orden := V.Substring(P + 1).Split([','], TStringSplitOptions.ExcludeEmpty);
    end
    else if Es(FR_UNSTORED) then
    begin
      // <Nombre>=<prop>,<prop>,...: como ORDER=
      P := V.IndexOf('=');
      if P > 0 then
        Result.NuncaGuardadas := V.Substring(P + 1).Split([','], TStringSplitOptions.ExcludeEmpty);
    end
    else if Es(FR_UNAPPLIED) then
      Result.NoAplicados := Result.NoAplicados + [V]
    else if Es(FR_PARTIAL) then
      Result.SinLeer := Result.SinLeer + [V]
    else if Es(FR_READ) then
    begin
      // <sha256>|<ruta>: la huella es hexadecimal, y una ruta no lleva '|'
      P := V.IndexOf('|');
      if P > 0 then
      begin
        var Leido: TLeidoPorElJuez;
        Leido.Huella := V.Substring(0, P);
        Leido.Ruta := V.Substring(P + 1);
        Result.Leidos := Result.Leidos + [Leido];
      end;
    end
    else if Es(FR_ERROR) then
      Result.Error := V
    else if Es(FR_NOT_LOADED) then
    begin
      // <clase>|<su mensaje en partes>
      Result.NoCarga := True;
      Result.Parada := DeCabezaYPartes(V, Result.ClaseDeLaParada);
    end
    else if Es(FR_LINE) then
      Result.LineaDeLaParada := StrToIntDef(V, 0);
  end;
end;

function LineaDeLoLeido(ADoc: TStyleDoc; const AI: TIgnorada): Integer;
var
  Ini, Fin: Integer;
begin
  Result := 0;
  if (ADoc = nil) or (AI.Componente = '') then
    Exit;
  // el lector nombra a secas, tambien a uno de dentro de un frame en linea
  var Obj := ADoc.ObjetoDeNombre(AI.Componente, True);
  if (Obj <> nil) and ADoc.PropLines(Obj, AI.Propiedad, Ini, Fin) then
    Result := Ini + 1;
end;

function IgnoradaDelUsuario(const ARaizNombre: string; const AI: TIgnorada;
  const APublicadas: TArray<TPropiedadDelUsuario>; out ASuya: TPropiedadDelUsuario): Boolean;
begin
  ASuya := Default(TPropiedadDelUsuario);
  Result := (ARaizNombre <> '') and SameText(AI.Componente, ARaizNombre) and
    PropiedadDelUsuarioLlamada(APublicadas, AI.Propiedad, ASuya);
end;

function DelCodigoDeUnComponente(const AI: TIgnorada): Boolean;
begin
  Result := AI.Origen <> '';
end;

function TextoDeIgnorada(const AI: TIgnorada): string;
begin
  Result := AI.Texto;
  if AI.Origen <> '' then
    Result := AI.Origen + ': ' + AI.Texto;
end;

function PartesDeClaseNoInstalada(ADoc: TStyleDoc; const AI: TIgnorada; AFmx: Boolean;
  out AProp, AClase: string): Boolean;
var
  Falta: TFaltaTabla;
  Id, Nombre: string;
  Nivel: Integer;
begin
  Result := False;
  AProp := '';
  AClase := '';
  if (ADoc = nil) or (AI.Componente = '') or (AI.Propiedad = '') then
    Exit;
  var Obj := ADoc.ObjetoDeNombre(AI.Componente, True);
  if Obj = nil then
    Exit;
  var M := MetaTable(AFmx, Falta, 0);
  if M = nil then
    Exit;
  // las propiedades del nivel propio del objeto (ni las de sus hijos ni las
  // de un item de coleccion) que acaban en ClassName, por EL lector de lineas.
  // '...ClassName' es gramatica NUESTRA, declarada (test_paisaje) y sin juez:
  // lo decide el setter de cada clase con GetClass. Y solo cuenta lo saltado
  // que cuelga de esas partes (ItemAppearance -> ItemAppearanceObjects...):
  // una errata en otra propiedad del mismo componente sigue siendo aviso
  // (revisor de la 1.20.2)
  var Lineas := LineasDeForm(ADoc.Lines);
  Nivel := 0;
  for var I := Obj.StartLine to Obj.EndLine - 2 do // 0-based: de debajo del object a encima del end
  begin
    if I > High(Lineas) then
      Break;
    case Lineas[I].Clase of
      clfObjeto: Inc(Nivel);
      clfFin: Dec(Nivel);
      clfPropiedad:
        if (Nivel = 0) and (Lineas[I].Coleccion = 0) and Lineas[I].Prop.EndsWith('ClassName', True) and
           AI.Propiedad.StartsWith(Lineas[I].Prop.Substring(0, Lineas[I].Prop.Length - Length('ClassName')), True) and
           LeeLiteralDeForm(Lineas[I].Valor, Nombre) and (Nombre <> '') and not M.ClaseDeNombre(Nombre, Id) then
        begin
          AProp := Lineas[I].Prop;
          AClase := Nombre;
          Exit(True);
        end;
    end;
  end;
end;

type
  // las partes de un componente de una clase que no esta instalada: que
  // propiedad las elige, con que clase, y lo que el lector salto debajo
  TPartesDelProyecto = record
    Componente, Prop, Clase, Saltado: string;
  end;

function LoQueNoCargo(const R: TRespuestaRender; ADoc: TStyleDoc; const AForm: string;
  out ANoConfirmado: string): TArray<string>;
var
  Vistos: TArray<string>;
  Lineas, SinProp: TArray<string>;
  RaizNombre, RaizClase, Sustituto, NoVistas, PropCn, ClaseCn: string;
  Raiz: TRaizParaElLector;
  Proyecto: TArray<TPartesDelProyecto>;

  procedure Pon(const AI: TIgnorada);
  begin
    for var V in Vistos do
      if V = AI.Texto then
        Exit;
    Vistos := Vistos + [AI.Texto];
    var N := LineaDeLoLeido(ADoc, AI);
    if N > 0 then
      Lineas := Lineas + [MsgFmt(SF_DSGN_LINEA_AVISO_FMT, [N, ADoc.Lines[N - 1].Trim, AI.Texto])]
    else
      Lineas := Lineas + [MsgFmt(SF_DSGN_LECTOR_SIN_LINEA_FMT, [AI.Texto])];
  end;

  // lo que se salto de un objeto cuya clase el ayudante SUSTITUYO (no esta
  // instalada: el sustituto no publica sus propiedades) no es un valor malo:
  // es la nota de una clase de terceros (DSGN-039), no un aviso por edicion
  function DeSustituida(const AI: TIgnorada): Boolean;
  begin
    Result := False;
    if (ADoc = nil) or (AI.Componente = '') then
      Exit;
    var Obj := ADoc.ObjetoDeNombre(AI.Componente, True);
    if Obj <> nil then
      for var S in R.Sustituidas do
        if SameText(S, Obj.ClassName_) then
          Exit(True);
  end;

begin
  Vistos := [];
  Lineas := [];
  SinProp := [];
  Proyecto := [];
  // la raiz: la que dijo el ayudante, o (si fallo antes de decirla) la del
  // fichero; lo que publica su cadena del usuario no lo conoce el lector
  RaizNombre := R.RaizNombre;
  RaizClase := R.RaizClase;
  if (RaizNombre = '') and (ADoc <> nil) and (ADoc.Root <> nil) then
  begin
    RaizNombre := ADoc.Root.ObjName;
    RaizClase := ADoc.Root.ClassName_;
  end;
  Raiz := Default(TRaizParaElLector);
  if (AForm <> '') and (RaizClase <> '') then
    Raiz := RaizParaElLector(AForm, RaizClase, EsDesignerFmx(AForm));
  // la clase en la que el lector lee la raiz
  Sustituto := ClaseDelSustituto(R.RaizTipo);
  NoVistas := '';
  for var I in R.Ignoradas do
  begin
    var Suya: TPropiedadDelUsuario;
    if DeSustituida(I) or IgnoradaDelUsuario(RaizNombre, I, Raiz.Propias, Suya) then
      Continue;
    // de la raiz, y de su clase y no de la form en la que la lee el lector: un
    // TQuickRep, un TForm3D, un modulo de datos FMX - no se sabe (DSGN-154)
    if (RaizNombre <> '') and SameText(I.Componente, RaizNombre) and
       DeLaRaizQueElLectorNoVe(Raiz, Sustituto, I.Propiedad) then
    begin
      NoVistas := NoVistas + (if NoVistas <> '' then ', ' else '') + I.Propiedad;
      Continue;
    end;
    // una excepcion del codigo de un componente (no del lector) y lo saltado
    // bajo las partes de una clase del proyecto: no se sabe (DSGN-154)
    if DelCodigoDeUnComponente(I) then
    begin
      SinProp := SinProp + [TextoDeIgnorada(I)];
      Continue;
    end;
    if PartesDeClaseNoInstalada(ADoc, I, EsDesignerFmx(AForm), PropCn, ClaseCn) then
    begin
      var K := -1;
      for var J := 0 to High(Proyecto) do
        if SameText(Proyecto[J].Componente, I.Componente) then
          K := J;
      if K < 0 then
      begin
        var Nueva: TPartesDelProyecto;
        Nueva.Componente := I.Componente;
        Nueva.Prop := PropCn;
        Nueva.Clase := ClaseCn;
        Nueva.Saltado := I.Propiedad;
        Proyecto := Proyecto + [Nueva];
      end
      else
        Proyecto[K].Saltado := Proyecto[K].Saltado + ', ' + I.Propiedad;
      Continue;
    end;
    Pon(I);
  end;
  ANoConfirmado := '';
  if NoVistas <> '' then
    ANoConfirmado := MsgFmt(SF_DSGN_LECTOR_RAIZ_NO_VISTA_FMT, [Sustituto, Raiz.Clase, NoVistas]);
  if Length(SinProp) > 0 then
    ANoConfirmado := ANoConfirmado + (if ANoConfirmado <> '' then '; ' else '') +
      MsgFmt(SF_DSGN_LECTOR_DEL_CODIGO_FMT, [string.Join(' | ', SinProp)]);
  for var Pr in Proyecto do
    ANoConfirmado := ANoConfirmado + (if ANoConfirmado <> '' then '; ' else '') +
      MsgFmt(SF_DSGN_LECTOR_CLASE_DEL_PROYECTO_FMT, [Pr.Componente, Pr.Prop, Pr.Clase, Pr.Saltado]);
  if R.NoCarga then
  begin
    // el error que lo paro, sin la clase delante: como lo dice el lector, y
    // como lo dicen las que se salto
    var E := R.Parada;
    if E.Texto = '' then
      E.Texto := R.Error;
    Pon(E);
  end;
  Result := Lineas;
end;

{ Lo que el contenedor SI puede leer: gramatica de la casa, porque el juez (que
  abra el fichero) diria tambien si existe. Por su texto y sin preguntar por el
  fichero. }
function LoLeeElContenedor(const ARuta: string): Boolean;
begin
  Result := False;
  for var C in CarpetasDelSistema do
    if (C <> '') and EnLugar(ARuta, C) then
      Exit(True);
end;

{ La forma del VALOR decide, nunca una lista de propiedades.
  El contenedor ya no deja leer las raices, la casa ni la red, asi que aqui solo
  queda lo que si leeria (las carpetas del sistema), juzgado por el unico juez
  de lectura; y por el TEXTO, exista el fichero o no: mirar si existia decia a
  un agente, por la respuesta, que ficheros hay en el servidor (V65 de la 1.24).
  El ayudante interpreta relativos desde su cwd, AEtapa.
  AJunto, de paso: lo que los literales nombran por debajo de la carpeta del form
  y la sesion puede leer (un .avi de un TAnimate), relativo a ella y con su tope,
  para copiarselo: alli donde esta ya no lo alcanza. Solo se pregunta si existe
  por lo que la puerta deja leer, asi que no dice nada de fuera. }
function EsEjecutable(const ABytes: TArray<Byte>): Boolean;
begin
  Result := (Length(ABytes) >= 2) and (ABytes[0] = Ord('M')) and (ABytes[1] = Ord('Z'));
end;

function LiteralesDeRenderDenegados(const APeticion: TPeticionRender; const AEtapa: string;
  out AJunto: TArray<string>): string;
const
  TOPE_JUNTO_BYTES = 64 * 1024 * 1024;
var
  Bases: TArray<string>;
  Hermanos: string;
  BytesLeidos, BytesJunto: Int64;
  Doc: TStyleDoc;
  Form: TArray<TLineaForm>;
  Texto, Valor, Prop: string;

  function Comprueba(const AProp, AValor: string): string;
  var
    Ruta: string;
  begin
    Result := '';
    // El valor se juzga por su texto ANTES de alargarlo o preguntar si existe.
    if RutaSinTocarElDisco(AValor) then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    if AValor = '' then
      Exit;
    for var Base in Bases do
    begin
      // como lo lee el ayudante, cuya carpeta actual es AEtapa (EL resolutor).
      // "X:y" de OTRA unidad, por la carpeta de esa unidad que el ayudante
      // hereda del servidor con su entorno: la de este proceso
      Ruta := RutaDesde(Base, AValor);
      if Ruta = '' then
      try
        Ruta := TPath.GetFullPath(AValor);
      except
        Continue; // una cadena que no es ruta no nombra un fichero
      end;
      // lo normal, un texto: se queda en esa carpeta y no nombra el sistema.
      // Por su texto y antes de tocar el disco: un form trae miles, y por cada uno
      // de los hermanos en el NAS tardaba 80 s en lugar de 15 (medido)
      var Trozo: string;
      if not TrozoBajo(Base, Ruta, Trozo) and LoLeeElContenedor(Ruta) and (ReadPathDenied(Ruta) <> '') then
        Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    end;
    // ...y solo uno con forma de fichero, con su extension, se busca al lado del form
    if ExtractFileExt(AValor).Length < 2 then // (TPath.GetExtension lanza con un | o un <)
      Exit;
    Ruta := RutaDesde(Hermanos, AValor);
    var Trozo: string;
    if (Ruta <> '') and TrozoBajo(Hermanos, Ruta, Trozo) and TFile.Exists(Ruta) and
       (ReadPathDenied(Ruta) = '') and not EsEnlace(Ruta) then
    begin
      var Tam: Int64;
      var Fecha: TDateTime;
      // un programa no es lo que un form lee: el ayudante no carga nada que no sea del IDE
      if not RutaEnLista(Trozo, AJunto) and HuellaDeFichero(Ruta, Tam, Fecha) and
         (BytesJunto + Tam <= TOPE_JUNTO_BYTES) and not EsEjecutable(LeeBytes(Ruta, LUGARES_DEL_MOTOR)) then
      begin
        Inc(BytesJunto, Tam);
        AJunto := AJunto + [Trozo];
      end;
    end;
  end;

  function CompruebaForm(const ARuta: string; AEnTemporal: Boolean = False): string;
  begin
    Result := '';
    // 65 MiB de texto costaron 416 MiB en el servidor; la pasada previa
    // sucede antes del job. El presupuesto total se mira ANTES de cargar.
    const TOPE_LITERAL_BYTES = 16 * 1024 * 1024;
    Inc(BytesLeidos, TFile.GetSize(ARuta));
    if BytesLeidos > TOPE_LITERAL_BYTES then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_TOPE_FMT, [TOPE_LITERAL_BYTES div (1024 * 1024)]));
    // la propuesta del juez vive en el temporal del servidor, que la puerta
    // de la jaula no lee: por su lugar, y es texto (la escribio el servidor)
    if AEnTemporal then
      Doc := TStyleDoc.DeTexto(LeeTexto(ARuta, [ltTemporal]))
    else
      Doc := TStyleDoc.Create(ARuta); // tambien el binario, por el lector existente
    try
      // los literales se juzgan por las lineas de LineasDeForm, y el ayudante
      // carga el form con el lector del IDE: uno que el parser no lee por
      // lineas como LineasDeForm no se juzga, y no se dibuja (DSGN-160, 3b
      // del censo de jueces)
      Result := FormaDistintaDeLineas(Doc.Lines, TPath.GetFileName(ARuta));
      if Result <> '' then
        Exit;
      Form := LineasDeForm(Doc.Lines);
      for var I := 0 to High(Doc.Lines) do
        if Form[I].Clase = clfPropiedad then
        begin
          Prop := Form[I].Prop;
          Valor := ValorEnteroDe(Doc.Lines, Form, I);
          if LeeLiteralDeForm(Valor, Texto) then
          begin
            Result := Comprueba(Prop, Texto);
            if Result <> '' then
              Exit;
          end
          else if Valor = '(' then
            // Strings de una lista: sus elementos por SU lector (Lsp.DesignerBin)
            // y cada uno por el mismo lector de literales. A mano se saltaba el
            // ultimo, el del ')' que el IDE escribe detras (V109 de la 1.23.1)
            for var Elem in ElementosDeLista(Doc.Lines, I, Form[I].Fin) do
              if LeeLiteralDeForm(Elem, Texto) then
              begin
                Result := Comprueba(Prop, Texto);
                if Result <> '' then
                  Exit;
              end;
        end;
    finally
      Doc.Free;
    end;
  end;

begin
  Result := '';
  AJunto := [];
  BytesLeidos := 0;
  BytesJunto := 0;
  // la carpeta en la que el ayudante resuelve un relativo: su cwd, la de esta
  // llamada, y de ahi nombra lo que quiera subiendo con ..\. Sus hermanos, los
  // de la carpeta del form de verdad: se le copian (CopiaLoQueLee). Una base que
  // no mira es un relativo que pasa la puerta (revisor 3 de la noche, A-1)
  Hermanos := TPath.GetDirectoryName(APeticion.Path);
  if APeticion.Carpeta <> '' then
    Hermanos := APeticion.Carpeta;
  Bases := [AEtapa];
  try
    // lo que se le da a leer al ayudante, TAMBIEN la propuesta del juez
    // (Carpeta): el form de verdad se leyo en otro momento y un escritor que
    // esperaba el cerrojo pudo cambiarlo (revisor 6 del 3.11, M1)
    Result := CompruebaForm(APeticion.Path, APeticion.Carpeta <> '');
    if Result <> '' then
      Exit;
    // Los frames y ancestros que el ayudante puede resolver son hermanos.
    // (con Carpeta, el form de verdad no es un hermano: el ayudante lee su
    // propuesta, que ya se miro arriba; mirarlo otra vez dependia de que no
    // lo borrasen mientras - medido con O20)
    var ElDeVerdad := '';
    if APeticion.Carpeta <> '' then
      ElDeVerdad := TPath.Combine(APeticion.Carpeta, TPath.GetFileName(APeticion.Path));
    for var Hermano in WalkFiles(Hermanos, ['*' + ExtractFileExt(APeticion.Path)], False, False) do
      if not EsEnlace(Hermano) and not SameFileName(Hermano, APeticion.Path) and
         not SameFileName(Hermano, ElDeVerdad) then
      begin
        Result := CompruebaForm(Hermano);
        if Result <> '' then
          Exit;
      end;
    for var Lejano in APeticion.Lejanos do
    begin
      Result := CompruebaForm(Lejano);
      if Result <> '' then
        Exit;
    end;
    for var Estado in APeticion.Estados do
    begin
      var P := Pos('=', Estado);
      if P = 0 then
        Continue; // el lector de state dara su diagnostico de forma
      Prop := Copy(Estado, 1, P - 1).Trim;
      Valor := Copy(Estado, P + 1, MaxInt).Trim;
      Result := Comprueba(Prop, Valor); // state se entrega crudo al ayudante (AplicaEstado)
      if Result = '' then
        if LeeLiteralDeForm(Valor, Texto) then
          Result := Comprueba(Prop, Texto);
      if Result <> '' then
        Exit;
    end;
  except
    Result := MsgText(SR_DESIGNER_LITERAL_NO_VERIFICABLE);
  end;
end;

function RutaDePaqueteDelIde(const AValor, ARaiz, AComun: string): string;
begin
  Result := ConBarrasDeWindows(AValor);
  if AComun <> '' then
    Result := StringReplace(Result, '$(BDSCOMMONDIR)', AComun, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDSBIN)', ARaiz + '\bin', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDS)', ARaiz, [rfReplaceAll, rfIgnoreCase]);
end;

{ Los paquetes del IDE de 32 bits del usuario, sin los desactivados (V124, por el
  nombre del fichero: el registro no escribe igual la misma ruta). }
function PaquetesDelIde(const AInfo: TRadStudioInfo): TArray<string>;
begin
  Result := [];
  var Off := IdeBplsDesactivados32(AInfo.Version);
  var Raiz := PrefijoSinBarra(AInfo.RootDir);
  var Comun := BdsCommonDir(AInfo);
  for var V in IdeValoresDeClave(AInfo.Version, 'Known Packages', False) do
    if not MatchText(TPath.GetFileName(ConBarrasDeWindows(V.Nombre)), Off) then
      Result := Result + [RutaDePaqueteDelIde(V.Nombre, Raiz, Comun)];
end;

function ManifiestoDeClases(const AClases: TArray<TClaseCom>): string;

  function SuModelo(const AHilos: string): string;
  begin
    Result := '';
    // los que entiende un manifiesto, como los escribe; el resto (Single, nada): sin atributo
    for var M in TArray<string>.Create('Apartment', 'Both', 'Free', 'Neutral') do
      if SameText(M, AHilos) then
        Result := ' threadingModel="' + M + '"';
  end;

begin
  Result := '';
  var Nombres: TArray<string> := [];
  for var C in AClases do
  begin
    var Nombre := TPath.GetFileName(C.Dll);
    if MatchText(Nombre, Nombres) then
      Continue;
    Nombres := Nombres + [Nombre];
    Result := Result + '<file name="' + XmlEscape(Nombre) + '" loadFrom="' + XmlEscape(C.Dll) + '">';
    for var D in AClases do
      if SameFileName(D.Dll, C.Dll) then
        Result := Result + '<comClass clsid="' + XmlEscape(D.Clsid) + '"' + SuModelo(D.Hilos) + '/>';
    Result := Result + '</file>';
  end;
  if Result <> '' then
    Result := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">' + Result + '</assembly>';
end;

{ De las clases ACLSIDs, las que el contenedor puede cargar si se las dan: su
  biblioteca, en lo que el contenedor lee. La vista de 32 bits, la del ayudante. }
function ClasesDeBibliotecaLegible(const ACLSIDs: TArray<string>): TArray<TClaseCom>;
var
  Expandida: array[0..MAX_PATH * 2] of Char;
begin
  Result := [];
  var Reg := TRegistry.Create(KEY_READ or KEY_WOW64_32KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    for var C in ACLSIDs do
      if Reg.OpenKeyReadOnly('SOFTWARE\Classes\CLSID\' + C + '\InprocServer32') then
      begin
        var Clase: TClaseCom;
        Clase.Clsid := C;
        try
          Clase.Dll := Reg.ReadString('');
          Clase.Hilos := Reg.ReadString('ThreadingModel');
        except
          Clase.Dll := ''; // una clave que no es de texto: esa clase, no todas
        end;
        Reg.CloseKey;
        var N := ExpandEnvironmentStrings(PChar(Clase.Dll), Expandida, Length(Expandida));
        if (N > 0) and (N <= DWORD(Length(Expandida))) then
          Clase.Dll := Expandida;
        if LoLeeElContenedor(Clase.Dll) and TFile.Exists(Clase.Dll) then
          Result := Result + [Clase];
      end;
  finally
    Reg.Free;
  end;
end;

{ Las clases COM que el contenedor no puede buscar donde estan, dadas a los
  ayudantes de ACaja (AAyudantes, sus originales) en el manifiesto de su copia:
  ese contexto lo crea quien crea el proceso, fuera del contenedor, que dentro
  no puede ni CreateActCtx ni CoRegisterClassObject (acceso denegado; medido el
  30-oct-2026). Quien las carga sigue siendo el proceso del contenedor, con lo
  que este lee y nada mas. Sin ellas un form con un TADOQuery perdia el
  componente y el juez del orden no lo juzgaba. Que clases, lo dice el contenedor
  (--unreadableclasses); si el manifiesto vale, Windows al crear el proceso. Si
  algo falla, esta generacion de la caja se queda sin manifiesto (con su aviso en
  el log), que es solo perder esas clases. }
procedure DaSusClasesAlContenedor(const ACaja, APath: string; const AAyudantes: TArray<string>);
const
  PREGUNTA_TIEMPO_MS = 30000;

  // lo que responde o, si no acaba bien o ni arranca, por que
  function Pregunta(const AExe: string; out ASalida: string): Boolean;
  var
    AC: TContenedor;
    Orden: string;
    Codigo: Cardinal;
    Vencido: Boolean;
  begin
    Result := False;
    try
      var Pet := Default(TPeticionRender);
      Pet.ClasesSinLeer := True;
      ASalida := ComponeOrdenDeRender(AExe, Pet, Orden);
      if ASalida <> '' then
        Exit;
      var Err := CreaContenedor(AC);
      if Err <> 0 then
        RaiseLastOSError(Err);
      try
        AC.ConVentanas := True;
        ASalida := RunCapturedEnContenedor(Orden, ACaja, AC, PREGUNTA_TIEMPO_MS,
          Codigo, Vencido, phConsola, EntornoSinConfiguracion(['PATH=' + APath]));
        Result := not Vencido and (Codigo = FR_RC_OK);
      finally
        BorraContenedor(AC);
      end;
    except
      on E: Exception do
        ASalida := E.Message;
    end;
  end;

  procedure PonManifiesto(const AExe: string; const ABytes: TArray<Byte>);
  begin
    var H := BeginUpdateResource(PChar(AExe), False);
    Win32Check(H <> 0);
    if not UpdateResource(H, RT_MANIFEST, MakeIntResource(1), 0, @ABytes[0], Length(ABytes)) then
    begin
      var Err := GetLastError;
      EndUpdateResource(H, True);
      RaiseLastOSError(Err);
    end;
    Win32Check(EndUpdateResource(H, False));
  end;

begin
  try
    if Length(AAyudantes) = 0 then
      Exit;
    var Salida: string;
    if not Pregunta(TPath.Combine(ACaja, TPath.GetFileName(AAyudantes[0])), Salida) then
      raise Exception.Create(Salida);
    var Manifiesto := ManifiestoDeClases(ClasesDeBibliotecaLegible(LeeRespuestaDeRender(Salida).ClasesSinLeer));
    if Manifiesto = '' then
      Exit;
    var Bytes := TEncoding.UTF8.GetBytes(Manifiesto);
    for var A in AAyudantes do
    begin
      var Copia := TPath.Combine(ACaja, TPath.GetFileName(A));
      PonManifiesto(Copia, Bytes);
      // el juez de un manifiesto es Windows, al crear el proceso
      if not Pregunta(Copia, Salida) then
      begin
        TFile.Copy(A, Copia, True);
        TLogger.Warning(MsgFmt(SL_RENDER_CLASES_SIN_DAR_FMT, [Salida]));
      end;
    end;
  except
    on E: Exception do
      TLogger.Warning(MsgFmt(SL_RENDER_CLASES_SIN_DAR_FMT, [E.Message]));
  end;
end;

{ El mensaje de un fallo de disco, de camino al agente, sin nuestra casa: es lo
  unico de ella que podria nombrar una respuesta. Solo para mensajes: un texto
  del form la puede llevar de verdad. }
function SinNuestraCasa(const AMensaje: string): string;
begin
  Result := StringReplace(AMensaje, PrefijoSinBarra(ServerTempDir), '(server)',
    [rfReplaceAll, rfIgnoreCase]);
end;

const
  PREFIJO_CAJA_DE_PAQUETES = 'render-paquetes-';

var
  GCajaDePaquetes: TObject;
  GUsosDeCaja: TDictionary<string, Integer>; // los ayudantes que usan cada generacion, bajo ese cerrojo

{ El ayudante que usaba ACaja ya acabo. }
procedure SueltaCaja(const ACaja: string);
begin
  System.TMonitor.Enter(GCajaDePaquetes);
  try
    var Usos: Integer;
    if GUsosDeCaja.TryGetValue(ClaveDeRuta(ACaja), Usos) then
      if Usos > 1 then
        GUsosDeCaja[ClaveDeRuta(ACaja)] := Usos - 1
      else
        GUsosDeCaja.Remove(ClaveDeRuta(ACaja));
  finally
    System.TMonitor.Exit(GCajaDePaquetes);
  end;
end;

function PlazoDeRender(const APeticion: TPeticionRender): Integer;
begin
  Result := APeticion.PlazoMs;
  if Result <= 0 then
    Result := RENDER_TIEMPO_MS;
end;

{ LA CAJA DE PAQUETES: los .bpl y .dll que un contenedor no leeria donde estan
  (la carpeta publica del IDE, las de terceros; las del sistema si las lee: es
  LoLeeElContenedor) y el propio ayudante (con DaSusClasesAlContenedor), copiados
  a una carpeta de la casa que todos los contenedores leen y ninguno escribe. La
  misma para todas las llamadas: su nombre es la huella de lo que lleva, asi que un paquete nuevo o
  cambiado es otra caja y la vieja se va. Lo copia todo una vez; 102 MB, 0,4 s
  (medido el 30-oct-2026). '' si esta, y APaquetes ya con las rutas que tiene
  que leer el ayudante; si no, el motivo. }
function CajaDePaquetes(const AInfo: TRadStudioInfo; out ACaja, APath: string;
  out APaquetes: TArray<string>): string;
var
  Fuentes: TDictionary<string, string>;
  Vistas, Ayudantes, PathDelServidor, Claves: TArray<string>;

  // los ficheros de ACarpeta con esa mascara. Por EntradasDeCarpeta y no por
  // WalkFiles: esto es trabajo del servidor con la instalacion, no lo que nombra
  // un agente, y su jaula niega la casa y el IDE. Una carpeta que no se deja
  // listar (una del PATH): la que falte sale como cualquier paquete que falta
  function Lista(const ACarpeta, AMascara: string): TArray<string>;
  begin
    Result := [];
    try
      for var F in EntradasDeCarpeta(ACarpeta) do
        if TPath.MatchesPattern(TPath.GetFileName(F), AMascara, False) and not EsEnlace(F) then
          Result := Result + [F];
    except
    end;
  end;

  procedure Mira(const ACarpeta, AMascara: string);
  begin
    for var F in Lista(ACarpeta, AMascara) do
      if not Fuentes.ContainsKey(ClaveDeRuta(TPath.GetFileName(F))) then
        Fuentes.Add(ClaveDeRuta(TPath.GetFileName(F)), F);
  end;

  procedure MiraCarpeta(const ACarpeta: string);
  begin
    if (ACarpeta = '') or LoLeeElContenedor(ACarpeta) or RutaEnLista(ACarpeta, Vistas) then
      Exit;
    Vistas := Vistas + [ACarpeta];
    Mira(ACarpeta, '*.bpl');
    Mira(ACarpeta, '*.dll');
  end;

  // el que no se pueda copiar sale como cualquier paquete que falta, y se vuelve a
  // intentar en la llamada siguiente: no es de esta generacion dejarlo fuera
  procedure CopiaLoQueFalta(const ACarpeta: string);
  begin
    for var K in Claves do
      if not TFile.Exists(TPath.Combine(ACarpeta, TPath.GetFileName(Fuentes[K]))) then
        try
          TFile.Copy(Fuentes[K], TPath.Combine(ACarpeta, TPath.GetFileName(Fuentes[K])));
        except
          on E: Exception do
            TLogger.Warning(MsgFmt(SL_RENDER_PAQUETE_SIN_COPIAR_FMT, [Fuentes[K], E.Message]));
        end;
  end;

  // lo que un contenedor con el ayudante en ACarpeta encuentra por el PATH: esa
  // carpeta y lo del PATH del servidor que el contenedor lee
  function SuPath(const ACarpeta: string): string;
  begin
    Result := ACarpeta;
    for var D in PathDelServidor do
      if LoLeeElContenedor(D) then
        Result := Result + ';' + D;
  end;

begin
  Result := '';
  ACaja := '';
  APath := '';
  APaquetes := PaquetesDelIde(AInfo);
  Vistas := [];
  Ayudantes := [];
  Fuentes := TDictionary<string, string>.Create;
  try
    try
      // los ayudantes, con los recursos de idioma que lleven a su lado
      for var Fw in TArray<string>.Create('vcl', 'fmx') do
      begin
        var Nombre: string;
        var Ayudante := FormRenderExe(Fw, Nombre);
        Mira(ServerDir, ChangeFileExt(Nombre, '.*'));
        if Ayudante <> '' then
          Ayudantes := Ayudantes + [Ayudante];
      end;
      // donde el IDE deja lo compilado, los paquetes declarados, y lo que el
      // PATH le da a sus dependencias (por donde las busca Windows). Un nombre
      // repetido: el primero, como el cargador
      var Comun := BdsCommonDir(AInfo);
      if Comun <> '' then
        MiraCarpeta(TPath.Combine(Comun, 'Bpl'));
      for var P in APaquetes do
        MiraCarpeta(TPath.GetDirectoryName(P));
      PathDelServidor := CarpetasDelPath(GetEnvironmentVariable('PATH'));
      for var D in PathDelServidor do
        if not LoLeeElContenedor(D) and (Length(Lista(D, '*.bpl')) > 0) then
          MiraCarpeta(D);
      // la generacion: nombre, tamano y fecha de lo que lleva
      Claves := Fuentes.Keys.ToArray;
      TArray.Sort<string>(Claves);
      var Sello := '';
      for var K in Claves do
      begin
        var Tam: Int64;
        var Fecha: TDateTime;
        if HuellaDeFichero(Fuentes[K], Tam, Fecha) then
          Sello := Sello + K + '|' + IntToStr(Tam) + '|' + FloatToStr(Fecha) + #10;
      end;
      ACaja := ServerTempDir(PREFIJO_CAJA_DE_PAQUETES +
        PrincipioDeTexto(Sha256DeBytes(TEncoding.UTF8.GetBytes(Sello)), 16));
      System.TMonitor.Enter(GCajaDePaquetes);
      try
        if not TDirectory.Exists(ACaja) then
        begin
          // entera o ninguna: se llena al lado y entra de un renombre
          var Nueva := ACaja + '.' + FragmentoUnico;
          try
            CrearCarpeta(Nueva);
            var Err := PreparaCarpetaParaLosContenedores(Nueva);
            if Err <> 0 then
              RaiseLastOSError(Err);
            CopiaLoQueFalta(Nueva);
            DaSusClasesAlContenedor(Nueva, SuPath(Nueva), Ayudantes);
            if not MoveFile(PChar(Nueva), PChar(ACaja)) then
              RaiseLastOSError;
          except
            try
              BorraArbol(Nueva);
            except
              // la purga del arranque se la lleva
            end;
            raise;
          end;
          // las generaciones viejas, las que ningun ayudante usa: borrar una en uso
          // la dejaba a medias, y si volvia ese conjunto se usaba con agujeros
          for var D in EntradasDeCarpeta(ServerTempDir) do
            if TPath.GetFileName(D).StartsWith(PREFIJO_CAJA_DE_PAQUETES) and not SameFileName(D, ACaja) and
               not GUsosDeCaja.ContainsKey(ClaveDeRuta(D)) then
              try
                BorraArbol(D); // sin cruzar enlaces: ver Lsp.Guard
              except
              end;
        end
        else
          // lo que no se pudo copiar otra vez, o lo que se llevo una purga a medias
          CopiaLoQueFalta(ACaja);
        var Usos: Integer;
        if not GUsosDeCaja.TryGetValue(ClaveDeRuta(ACaja), Usos) then
          Usos := 0;
        GUsosDeCaja.AddOrSetValue(ClaveDeRuta(ACaja), Usos + 1);
      finally
        System.TMonitor.Exit(GCajaDePaquetes);
      end;
      // lo que el ayudante lee: lo del sistema donde esta, lo demas en la caja
      for var I := 0 to High(APaquetes) do
        if not LoLeeElContenedor(APaquetes[I]) then
          APaquetes[I] := TPath.Combine(ACaja, TPath.GetFileName(APaquetes[I]));
      // y sus dependencias: la caja y lo del PATH que el contenedor lee
      APath := SuPath(ACaja);
    except
      on E: Exception do
        Result := MsgFmt(SR_DESIGNER_SIN_CONTENEDOR_FMT, [SinNuestraCasa(E.Message)]);
    end;
  finally
    Fuentes.Free;
  end;
end;

{ Lo que el ayudante lee de las raices, COPIADO a AEtapa: el form (APeticion.Path,
  a veces una propuesta en la casa), sus hermanos del mismo tipo por sus frames y
  ancestros, y las unidades de todos, que dicen de que clase hereda cada uno. Por
  la puerta de leer: un hermano que la sesion no lee no va, ni un enlace, como
  no los leia el ayudante. AJunto, lo que sus literales nombran junto a el, en su
  sitio bajo AEtapa. La propuesta del juez va la ultima, encima del form de
  verdad de la Carpeta. Devuelve la ruta del form en AEtapa. Lanza si no puede
  con el form. }
function CopiaLoQueLee(const APeticion: TPeticionRender; const AEtapa: string;
  const AJunto: TArray<string>): string;
var
  Hermanos: string;

  procedure Copia(const AOrigen, ADestino: string);
  begin
    // un lejano no pisa a un hermano del mismo nombre: la propuesta si, abajo
    if EsEnlace(AOrigen) or not TFile.Exists(AOrigen) or TFile.Exists(ADestino) then
      Exit;
    try
      var Bytes := LeeBytes(AOrigen, LUGARES_DEL_MOTOR);
      CrearCarpeta(TPath.GetDirectoryName(ADestino));
      EscribeBytes(ADestino, Bytes, ltTemporal);
    except
      // lo que la sesion no lee no va: para el ayudante, un fichero que no esta
    end;
  end;

  procedure CopiaAlLado(const AOrigen: string);
  begin
    Copia(AOrigen, TPath.Combine(AEtapa, TPath.GetFileName(AOrigen)));
  end;

begin
  Hermanos := TPath.GetDirectoryName(APeticion.Path);
  if APeticion.Carpeta <> '' then
    Hermanos := APeticion.Carpeta;
  for var R in AJunto do
    Copia(TPath.Combine(Hermanos, R), TPath.Combine(AEtapa, R));
  for var F in WalkFiles(Hermanos, ['*' + ExtractFileExt(APeticion.Path)], False, False) do
  begin
    CopiaAlLado(F);
    CopiaAlLado(UnidadDeDesigner(F));
  end;
  CopiaAlLado(UnidadDeDesigner(TPath.Combine(Hermanos, TPath.GetFileName(APeticion.Path))));
  for var L in APeticion.Lejanos do
  begin
    CopiaAlLado(L);
    CopiaAlLado(UnidadDeDesigner(L));
  end;
  Result := TPath.Combine(AEtapa, TPath.GetFileName(APeticion.Path));
  // el pedido, por su lugar: una propuesta de la casa o un form ya juzgado
  EscribeBytes(Result, LeeBytes(APeticion.Path, LUGARES_DEL_MOTOR + [ltTemporal]), ltTemporal);
end;

{ UNA ejecucion del ayudante en su contenedor: la carpeta de esta llamada, lo que
  lee copiado dentro, la orden sobre esas copias y, si dibujo, la imagen en
  APeticion.Salida. Lo que dice sale ya con las rutas de verdad: ni un agente ve
  nuestra casa ni CambioEnLoLeido relee una copia. '' o el fallo; lo demas lo
  juzga quien llama. }
function CorreEnSuContenedor(const APeticion: TPeticionRender; const AExe: string;
  out ASalida: string; out ACodigo: Cardinal; out AVencido: Boolean): string;
var
  AC: TContenedor;
  Etapa, Caja, PathHijo, Orden, Origen: string;
  Paquetes, Junto: TArray<string>;
  Err: DWORD;
begin
  Result := '';
  ASalida := '';
  ACodigo := 0;
  AVencido := False;
  Caja := '';
  Err := CreaContenedor(AC);
  if Err <> 0 then
    Exit(MsgFmt(SR_DESIGNER_SIN_CONTENEDOR_FMT, [IntToHex(Err, 8) + ' ' + SysErrorMessage(Err)]));
  AC.ConVentanas := True;
  Etapa := NuevaCarpetaDescarga(ServerTempDir(CAPTURE_SUB_DESIGNER));
  try
    try
      CrearCarpeta(Etapa);
      Err := PreparaCarpetaDelContenedor(AC, Etapa);
      if Err <> 0 then
        Exit(MsgFmt(SR_DESIGNER_SIN_CONTENEDOR_FMT, [IntToHex(Err, 8) + ' ' + SysErrorMessage(Err)]));
      // el conversor (V71) no carga el form: ningun literal suyo se resuelve, y
      // juzgarlos leeria la copia por TStyleDoc, que de un binario le pregunta a
      // el mismo - medido con el mutante: una recursion de cientos de carpetas de
      // descarga hasta el plazo
      if APeticion.Convierte = '' then
        Result := LiteralesDeRenderDenegados(APeticion, Etapa, Junto);
      if Result <> '' then
        Exit;
      Result := CajaDePaquetes(DiscoverRadStudio, Caja, PathHijo, Paquetes);
      if Result <> '' then
        Exit;
      var Pet := APeticion;
      Pet.Path := CopiaLoQueLee(APeticion, Etapa, Junto);
      Pet.Carpeta := '';
      Pet.RaizBds := PrefijoSinBarra(DiscoverRadStudio.RootDir);
      Pet.FicheroPaquetes := TPath.Combine(Etapa, 'paquetes.lst');
      EscribeBytes(Pet.FicheroPaquetes, TEncoding.UTF8.GetPreamble +
        TEncoding.UTF8.GetBytes(string.Join(#13#10, Paquetes)), ltTemporal);
      if APeticion.Salida <> '' then
        Pet.Salida := TPath.Combine(Etapa, TPath.GetFileName(APeticion.Salida));
      // un estilo por fichero, ya por su puerta: lo que no se ve tampoco se lee
      if EsRutaAbsoluta(APeticion.Estilo) then
      begin
        Pet.Estilo := TPath.Combine(Etapa, TPath.GetFileName(APeticion.Estilo));
        EscribeBytes(Pet.Estilo, LeeBytes(APeticion.Estilo, LUGARES_DEL_MOTOR), ltTemporal);
      end;
      Result := ComponeOrdenDeRender(TPath.Combine(Caja, TPath.GetFileName(AExe)), Pet, Orden);
      if Result <> '' then
        Exit;
      ASalida := RunCapturedEnContenedor(Orden, Etapa, AC, PlazoDeRender(APeticion), ACodigo, AVencido,
        phConsola, EntornoSinConfiguracion(['PATH=' + PathHijo]));
      Origen := TPath.GetDirectoryName(APeticion.Path);
      if APeticion.Carpeta <> '' then
        Origen := APeticion.Carpeta;
      // un lejano vuelve a su carpeta, no a la del form: CambioEnLoLeido lo relee
      for var L in APeticion.Lejanos do
      begin
        ASalida := StringReplace(ASalida, TPath.Combine(Etapa, TPath.GetFileName(L)), L, [rfReplaceAll, rfIgnoreCase]);
        var Unidad := UnidadDeDesigner(L);
        ASalida := StringReplace(ASalida, TPath.Combine(Etapa, TPath.GetFileName(Unidad)), Unidad, [rfReplaceAll, rfIgnoreCase]);
      end;
      ASalida := StringReplace(ASalida, Etapa, Origen, [rfReplaceAll, rfIgnoreCase]);
      // un paquete o un componente que nombre su ruta: su nombre lleva la huella,
      // ningun texto de un form la trae
      ASalida := StringReplace(ASalida, Caja, '(packages)', [rfReplaceAll, rfIgnoreCase]);
      if (APeticion.Salida <> '') and TFile.Exists(Pet.Salida) then
        ColocaProducto(Pet.Salida, APeticion.Salida, ltTemporal);
    except
      // sin Job no corre: fail-closed, y no es cosa de delphi_test
      on E: ETestNoConfinado do
        Result := MsgFmt(SR_DESIGNER_SIN_CONTENEDOR_FMT, [SinNuestraCasa(E.Message)]);
      on E: Exception do
        Result := MsgFmt(SR_DESIGNER_RENDER_NO_ARRANCA_FMT, [TPath.GetFileName(AExe), SinNuestraCasa(E.Message)]);
    end;
  finally
    if Caja <> '' then
      SueltaCaja(Caja);
    BorraContenedor(AC);
    try
      ReclamaArbol(Etapa); // una carpeta que dejo cerrada el codigo de un paquete
      BorraArbol(Etapa);   // sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta: la purga del arranque se la lleva
    end;
  end;
end;

{ Los forms del proyecto de APeticion, fuera de la carpeta que el ayudante ve, cuya
  raiz es de una de AClases (lo que dijo que le faltaba: un ancestro o un frame).
  El proyecto, el .dpr o .dpk que lista la unidad del form (ProjectsUsingUnit),
  porque ahi dcc encuentra esas unidades; a cuales llega lo dice FormsDeLasClases.
  Nunca lanza: sin proyecto, el form sigue a medias y lo dice. }
function FormsLejanos(const APeticion: TPeticionRender; const AClases: TArray<string>): TArray<string>;
begin
  Result := [];
  if Length(AClases) = 0 then
    Exit;
  try
    var Form := APeticion.Path;
    if APeticion.Carpeta <> '' then
      Form := TPath.Combine(APeticion.Carpeta, TPath.GetFileName(APeticion.Path));
    var Carpeta := TPath.GetDirectoryName(Form);
    for var P in ProjectsUsingUnit(UnidadDeDesigner(Form)) do
      for var F in FormsDeLasClases(P, AClases, ExtractFileExt(Form)) do
        if not SameFileName(TPath.GetDirectoryName(F.Designer), Carpeta) and not RutaEnLista(F.Designer, Result) then
          Result := Result + [F.Designer];
  except
    // lo que no se lee no se trae
  end;
end;

function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;
const
  // el form, su ancestro, el de este y un frame suyo: cada vuelta es un ayudante entero
  VUELTAS_POR_LO_LEJANO = 3;
var
  Exe, Nombre, Salida, Fallo: string;
  Codigo: Cardinal;
  Reloj: TStopwatch;
  Pet: TPeticionRender;
  Vencido: Boolean;

  function Salio(const AR: TRespuestaRender): Boolean;
  begin
    Result := (Codigo = FR_RC_OK) and (AR.Error = '') and not AR.NoCarga and
      (if APeticion.Escribe then Length(AR.Escrito) > 0
       else APeticion.Cajas or TFile.Exists(APeticion.Salida));
  end;

  // el fallo del ayudante con su por que: no dibujo el form o, con --convert,
  // no lo convirtio (V71: ahi el form es una copia nuestra, y se nombra el
  // ayudante); uno que ya lleva etiqueta sale tal cual
  function FalloDelAyudante(const APorQue: string): string;
  begin
    if APeticion.Convierte <> '' then
      Result := MsgEnvuelve(SR_DSGN_CONVERSOR_FALLO_FMT, SinNuestraCasa(APorQue), [Nombre, SinNuestraCasa(APorQue)])
    else
      Result := MsgEnvuelve(SR_DESIGNER_RENDER_FALLO_FMT, APorQue, [TPath.GetFileName(APeticion.Path), APorQue]);
  end;

begin
  Result := Default(TRespuestaRender);
  Exe := FormRenderExe(APeticion.Framework, Nombre);
  if Exe = '' then
  begin
    Result.Fallo := MsgFmt(SR_DESIGNER_SIN_RENDER_FMT, [Nombre]);
    Exit;
  end;
  Reloj := TStopwatch.StartNew;
  Pet := APeticion;
  var Buena := Default(TRespuestaRender);
  var HayBuena := False;
  var CodigoBueno: Cardinal := 0;
  var LoTraido: TArray<string> := [];
  for var Vuelta := 0 to VUELTAS_POR_LO_LEJANO do
  begin
    Fallo := CorreEnSuContenedor(Pet, Exe, Salida, Codigo, Vencido);
    if Fallo <> '' then
    begin
      Result.Fallo := Fallo;
      Exit;
    end;
    Result := LeeRespuestaDeRender(Salida);
    // lo que se trajo hizo fallar al ayudante: el form a medias que ya salio es mejor
    // respuesta que un fallo, y dice que no entro
    if HayBuena and not Salio(Result) then
    begin
      Result := Buena;
      Codigo := CodigoBueno;
      Vencido := False;
      Result.Avisos := Result.Avisos + [MsgFmt(SN_DESIGNER_LEJANO_NO_ENTRO_FMT, [string.Join(', ', LoTraido)])];
      Break;
    end;
    if Salio(Result) then
    begin
      Buena := Result;
      HayBuena := True;
      CodigoBueno := Codigo;
    end;
    // lo que le falto y el proyecto tiene en otra carpeta: otra vuelta con ello, si
    // queda tiempo: el plazo es de la llamada y no de cada vuelta
    if (Vuelta = VUELTAS_POR_LO_LEJANO) or (APeticion.Convierte <> '') or
       (Reloj.ElapsedMilliseconds >= PlazoDeRender(APeticion)) then
      Break;
    var Nuevos: TArray<string> := [];
    for var F in FormsLejanos(APeticion, Result.SinLeer + Result.Sustituidas) do
      if not RutaEnLista(F, Pet.Lejanos) then
        Nuevos := Nuevos + [F];
    if Length(Nuevos) = 0 then
      Break;
    Pet.Lejanos := Pet.Lejanos + Nuevos;
    LoTraido := [];
    for var F in Nuevos do
      LoTraido := LoTraido + [TPath.GetFileName(F)];
  end;
  Result.Codigo := Codigo;
  Result.MsTotal := Reloj.ElapsedMilliseconds;
  if (Codigo = FR_RC_OK) and (Result.Error = '') and
     (if APeticion.Escribe then Length(Result.Escrito) > 0
      else APeticion.Cajas or TFile.Exists(APeticion.Salida)) then
    Exit;
  // (no por Salio: un NOTLOADED con codigo bueno y sin imagen sale por su rama)
  // el LECTOR no cargo el form (NOTLOADED=): es el fichero, y se dice con lo
  // que dijo y su linea. Salia como DSGN-061 INTERNAL, y con un valor que el
  // Ignore se saltaba, solo "Stream read error" (DSGN-061 de la 1.20, Hermes)
  if Result.NoCarga then
  begin
    // con --convert, lo que no se convirtio es el contenido: lo dice quien la
    // pidio, con la clase, el mensaje y la linea (ConversionDelIde)
    if APeticion.Convierte <> '' then
      Exit;
    var Doc: TStyleDoc := nil;
    try
      try
        Doc := TStyleDoc.Create(APeticion.Path);
      except
        Doc := nil; // sin lineas: lo que dijo el lector, tal cual
      end;
      // el form de verdad: el del juez es una propuesta escrita en otra
      // carpeta, y su .pas (lo que publica el usuario) esta en Carpeta
      var Form := APeticion.Path;
      if APeticion.Carpeta <> '' then
        Form := TPath.Combine(APeticion.Carpeta, TPath.GetFileName(APeticion.Path));
      // (lo de la raiz que el lector no ve no va en la lista; el error que lo
      // paro, si)
      var NoVista: string;
      Result.Fallo := MsgFmt(SR_DESIGNER_NO_CARGA_FMT, [TPath.GetFileName(APeticion.Path),
        #10 + string.Join(#10, LoQueNoCargo(Result, Doc, Form, NoVista))]);
    finally
      Doc.Free;
    end;
  end
  else if Result.Error <> '' then
    // con etiqueta (un estado que no existe, el vigia) sale tal cual
    Result.Fallo := FalloDelAyudante(Result.Error)
  else if (Codigo = STATUS_DLL_NOT_FOUND_) or (Codigo = STATUS_ENTRYPOINT_NOT_FOUND_) or
    (Codigo = STATUS_INVALID_IMAGE_FORMAT_) then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_SIN_BPL_FMT, [Nombre, APeticion.Bds, Codigo])
  else if Vencido and (APeticion.Convierte <> '') then
    // el conversor no carga el form: "algo del form espera" no es su causa (V102)
    Result.Fallo := FalloDelAyudante(MsgFmt(SF_DSGN_CONVERSOR_TIEMPO_FMT, [PlazoDeRender(APeticion) div 1000]))
  else if Vencido then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_TIEMPO_FMT, [Nombre, PlazoDeRender(APeticion) div 1000])
  else
    Result.Fallo := FalloDelAyudante(MsgFmt(SF_DESIGNER_RENDER_SIN_RESPUESTA_FMT,
      [Codigo, PrincipioDeTexto(Salida.Trim, 300)]));
end;

function PeticionDeRender(const APath, AFramework: string): TPeticionRender;
begin
  Result := Default(TPeticionRender);
  Result.Framework := AFramework;
  if Result.Framework = '' then
    Result.Framework := (if EsDesignerFmx(APath) then 'fmx' else 'vcl');
  Result.Path := APath;
  Result.Bds := DiscoverRadStudio.Version;
  // form o frame lo dice EL lector de clases (RaizParaElRender): el ayudante
  // lo adivinaba con su regex. Sin .pas legible, o sin saberlo, que mire el
  var Pas := UnidadDeDesigner(APath);
  if ExisteYSeLee(Pas) then
    Result.Raiz := RaizParaElRender(APath);
end;

function ConversionDelIde(const ABytes: TArray<Byte>; AATexto: Boolean; out ASalida: TArray<Byte>;
  out AClase, AMensaje: string; out ALinea: Integer): string;
var
  Pet: TPeticionRender;
  Dir: string;
  R: TRespuestaRender;
begin
  Result := '';
  ASalida := nil;
  AClase := '';
  AMensaje := '';
  ALinea := 0;
  // una carpeta de descarga de ESTA llamada en el temporal del servidor (EL
  // nombrador, como la propuesta del juez): los bytes los da quien llama, ya
  // leidos por su puerta, y el ayudante solo ve esta copia
  Dir := NuevaCarpetaDescarga(ServerTempDir(CAPTURE_SUB_DESIGNER));
  try
    try
      CrearCarpeta(Dir);
      // la peticion por SU nombrador (PeticionDeRender): compuesta a mano iba sin
      // la version del IDE, y DSGN-063 salia sin ella (V102 de la 1.23.1). El
      // conversor es la RTL de 32 bits, la misma en los dos ayudantes; junto a
      // la copia no hay .pas que leer
      Pet := PeticionDeRender(TPath.Combine(Dir, 'form.dfm'), 'vcl');
      Pet.Salida := TPath.Combine(Dir, 'convertido');
      Pet.Convierte := (if AATexto then 'text' else 'binary');
      EscribeBytes(Pet.Path, ABytes, ltTemporal);
      R := CorreRender(Pet);
      if R.NoCarga then
      begin
        AClase := R.ClaseDeLaParada;
        AMensaje := R.Parada.Texto;
        ALinea := R.LineaDeLaParada;
        Exit;
      end;
      if R.Fallo <> '' then
        Exit(R.Fallo);
      ASalida := LeeBytes(Pet.Salida, [ltTemporal]);
    except
      on E: Exception do
        Result := MsgExcepcion(E.ClassName, E.Message);
    end;
  finally
    try
      BorraArbol(Dir); // SIEMPRE, sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta
    end;
  end;
end;

{ La propuesta ATexto para APath, escrita en una carpeta de descarga de ESTA
  llamada y cargada por el ayudante de su framework en modo juez (--writeback:
  el form como lo carga el designer, sin pintar): lo que contesto, con Fallo
  si ni se pudo escribir. La carpeta se borra siempre. EL juez de
  ComoLoEscribeElIde y de LoQueNoCargaElIde. }
function JuezDelIde(const APath, ATexto, AEnc: string; const AComponente: string = '';
  const ASoltado: string = ''): TRespuestaRender;
var
  Pet: TPeticionRender;
  Dir, Cand: string;
begin
  Result := Default(TRespuestaRender);
  // una carpeta de descarga de ESTA llamada en el temporal del SERVIDOR (EL
  // nombrador: el guard del borrado la reconoce), con la propuesta bajo el
  // nombre del form de verdad: su .pas y sus hermanos los lee el ayudante de
  // la carpeta de APath (--folder). Es del servidor, no un entregable del
  // agente: en el __delphi-temp de la raiz la escritura pasaba por la puerta
  // del agente y el confinamiento la negaba (revisor 5 de la noche, M1)
  Dir := NuevaCarpetaDescarga(ServerTempDir(CAPTURE_SUB_DESIGNER));
  try
    try
      CrearCarpeta(Dir);
      Cand := TPath.Combine(Dir, TPath.GetFileName(APath));
      // LAXO: es la copia que se le PREGUNTA al ayudante, no la escritura del
      // form - como ParserDeForm (Lsp.DesignerBin), "juzgar el parseo, no
      // escribir". En estricto, un sustituto suelto que ya estaba en un .dfm
      // UTF-16 tumbaba el juicio con EDIT-078 "nothing written" cuando el
      // escritor de verdad (PatchSaveText) si escribia (revisor propio de la
      // 1.18.1); lo NUEVO lo sigue negando ese escritor
      EscribeTexto(Cand, ATexto, ltTemporal, EncKindOf(AEnc), False);
    except
      on E: Exception do
      begin
        Result.Fallo := MsgExcepcion(E.ClassName, E.Message);
        Exit;
      end;
    end;
    Pet := PeticionDeRender(APath, '');
    Pet.Path := Cand;
    Pet.Carpeta := TPath.GetDirectoryName(APath);
    Pet.Escribe := True;
    Pet.Componente := AComponente; // con el, tambien su orden (ORDER=)
    Pet.Soltado := ASoltado;
    Result := CorreRender(Pet);
  finally
    try
      BorraArbol(Dir); // SIEMPRE, sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta
    end;
  end;
end;

function ComoLoEscribeElIde(const APath, ATexto, AEnc: string; out AEscrito: string;
  out ASustituidas, AAvisos, ASinLeer: TArray<string>; out ALeidos: TArray<TLeidoPorElJuez>;
  out AError: string; out AParada: TIgnorada; const ASoltado: string): string;
begin
  AEscrito := '';
  ASustituidas := [];
  AAvisos := [];
  ASinLeer := [];
  ALeidos := [];
  var R := JuezDelIde(APath, ATexto, AEnc, '', ASoltado);
  AError := R.Error;
  AParada := R.Parada;
  Result := R.Fallo;
  if Result <> '' then
    Exit;
  AEscrito := string.Join(#13#10, R.Escrito);
  ASustituidas := R.Sustituidas;
  AAvisos := R.Avisos;
  ASinLeer := R.SinLeer;
  ALeidos := R.Leidos;
end;

function PropiedadesComoLasEscribeElIde(const APath, ATexto, AEnc, AComponente: string): TRespuestaRender;
begin
  Result := JuezDelIde(APath, ATexto, AEnc, AComponente);
end;

function ColoresSinAlfaDeForm(const APath, ATexto, AEnc, AAntes: string;
  out AColores: TArray<TColorSinAlfa>): Boolean;
var
  Doc, DocAntes, DocE: TStyleDoc;
begin
  AColores := [];
  Result := False;
  Doc := nil;
  DocAntes := nil;
  DocE := nil;
  try
    try
      Doc := TStyleDoc.DeTexto(ATexto);
      var Candidatos := CandidatosSinAlfa(Doc);
      // los que ya estaban (su componente, su propiedad y su valor) no los
      // trae la edicion, como la nota de los StyleLookup (V143)
      if (Length(Candidatos) > 0) and (AAntes <> '') then
      begin
        DocAntes := TStyleDoc.DeTexto(AAntes);
        var Estaban: TArray<string> := [];
        for var C in CandidatosSinAlfa(DocAntes) do
          Estaban := Estaban + [C.Componente + #0 + C.Prop + #0 + C.Valor];
        var Nuevos: TArray<TColorSinAlfa> := [];
        for var C in Candidatos do
          if IndexText(C.Componente + #0 + C.Prop + #0 + C.Valor, Estaban) < 0 then
            Nuevos := Nuevos + [C];
        Candidatos := Nuevos;
      end;
      if Length(Candidatos) = 0 then
        Exit(True);
      var Escrito, Error: string;
      var Sustituidas, Avisos, SinLeer: TArray<string>;
      var Leidos: TArray<TLeidoPorElJuez>;
      var Parada: TIgnorada;
      if (ComoLoEscribeElIde(APath, ATexto, AEnc, Escrito, Sustituidas, Avisos, SinLeer, Leidos,
            Error, Parada) <> '') or (Length(Sustituidas) > 0) or (Length(SinLeer) > 0) then
        Exit;
      DocE := TStyleDoc.DeTexto(Escrito);
      Result := ColoresSinAlfaEntre(Doc, DocE, Candidatos, AColores);
    except
      Result := False; // un juicio que no se pudo hacer no dice nada
      AColores := [];
    end;
  finally
    DocE.Free;
    DocAntes.Free;
    Doc.Free;
  end;
end;

function NotaDeColoresSinAlfa(const APath, ATexto, AEnc, AAntes: string): TArray<string>;
var
  Colores: TArray<TColorSinAlfa>;
begin
  Result := [];
  if not ColoresSinAlfaDeForm(APath, ATexto, AEnc, AAntes, Colores) or (Length(Colores) = 0) then
    Exit;
  Result := [MsgFmt(SN_DESIGNER_COLORES_SIN_ALFA_FMT, [ExtractFileName(APath), Length(Colores),
    IfThen(AAntes <> '', MsgText(SF_DESIGNER_LOOKUPS_DE_LA_EDICION), '')])];
  for var C in Colores do
    Result := Result + [MsgFmt(SF_DESIGNER_COLOR_SIN_ALFA_FMT, [C.Componente, C.Prop, C.Valor, C.Linea,
      IfThen(C.ComoLoCarga <> '', C.ComoLoCarga, MsgText(SF_COLOR_NO_GUARDADO))])];
end;

function CambioEnLoLeido(const ALeidos: TArray<TLeidoPorElJuez>): string;
begin
  Result := '';
  for var L in ALeidos do
  begin
    var Igual := False;
    try
      Igual := SameText(Sha256DeBytes(LeeBytes(L.Ruta, [ltJaula])), L.Huella);
    except
      // borrado, renombrado o negado mientras se juzgaba: cambio
    end;
    if not Igual then
      Exit(TPath.GetFileName(L.Ruta));
  end;
end;

function LoQueNoCargaElIde(const APath, ATexto, AEnc: string; out ANoPregunto: string): TArray<string>;
var
  Doc: TStyleDoc;
begin
  Result := [];
  ANoPregunto := '';
  try
    var R := JuezDelIde(APath, ATexto, AEnc);
    // leido SIN un ancestro (PARTIAL=): cada 'inherited' sin el dice "Ancestor
    // for X not found", y eso es de NUESTRA lectura, no del form - una vista
    // FMX sin el .pas de su maestro al lado, o con uno que no la declara, "no
    // cargaba" (medido el 18-oct-2026). No se sabe, y se dice por que
    if Length(R.SinLeer) > 0 then
    begin
      ANoPregunto := MsgFmt(SF_DSGN_LECTOR_SIN_ANCESTRO_FMT, [string.Join(', ', R.SinLeer)]);
      Exit;
    end;
    // lo cargo, o fallo por otra cosa (sin renderizador, el tiempo, un
    // paquete): de lo suyo el lector no dijo nada
    if not R.NoCarga and (Length(R.Ignoradas) = 0) then
    begin
      ANoPregunto := R.Fallo;
      Exit;
    end;
    Doc := nil;
    try
      try
        Doc := TStyleDoc.DeTexto(ATexto);
      except
        Doc := nil; // sin lineas: lo que dijo el lector, tal cual
      end;
      var NoVista: string;
      Result := LoQueNoCargo(R, Doc, APath, NoVista);
      // lo no confirmado (la raiz que el lector no ve, una excepcion del codigo
      // de un componente, las partes de una clase del proyecto) se dice
      // TAMBIEN cuando hay avisos de verdad: el lint imprime las dos partes
      // (se tiraba si habia aviso; revisor de la 1.20.2)
      if NoVista <> '' then
        ANoPregunto := NoVista;
    finally
      Doc.Free;
    end;
  except
    on E: Exception do
    begin
      Result := [];
      ANoPregunto := MsgExcepcion(E.ClassName, E.Message);
    end;
  end;
end;

initialization
  GCajaDePaquetes := TObject.Create;
  GUsosDeCaja := TDictionary<string, Integer>.Create;

finalization
  GUsosDeCaja.Free;
  GCajaDePaquetes.Free;

end.
