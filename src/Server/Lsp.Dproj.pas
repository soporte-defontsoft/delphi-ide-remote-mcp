unit Lsp.Dproj;

{ The ONE place that reads a Delphi .dproj (tolerant XML scanning, no MSBuild
  engine). Both the LSP config fabricator and the project/platform tools use
  it - never a second parser (measured house rule: do not reinvent wheels).

  A .dproj is MSBuild XML. What matters here:
  - <Platform value="Win64">True</Platform>  under <Platforms>  -> declared platforms
  - <BuildConfiguration Include="Debug"><Key>Cfg_2</Key>...     -> build configurations
  - <FrameworkType>VCL|FMX|None</FrameworkType>                 -> which UI framework
  - <AppType>Application|Console</AppType>
  Accumulating property lists (search paths) are merged with MergeProperty. }

interface

type
  TDprojPlatform = record
    Name: string;     // 'Win32', 'Win64', 'Linux64', 'OSX64', 'Android64'...
    Enabled: Boolean; // the value in <Platform value="X">VALUE</Platform>
  end;

  TDprojInfo = record
    FrameworkType: string; // 'VCL' | 'FMX' | 'None' | '' (unknown)
    AppType: string;       // 'Application' | 'Console' | ''
    Configs: TArray<string>;         // 'Base','Debug','Release',...
    Platforms: TArray<TDprojPlatform>;
    DefaultPlatform: string; // el selector <Platform Condition="'$(Platform)'==''">X</Platform>
    DefaultConfig: string;   // el selector <Config Condition="'$(Config)'==''">X</Config>
    function HasConfig(const AName: string): Boolean;
    function HasPlatform(const AName: string): Boolean;
    { La plataforma que compilan el IDE y msbuild mientras nadie pide otra: la
      que el proyecto tiene por defecto, y Win32 si no dice ninguna. }
    function PlataformaPorDefecto: string;
    { La configuracion que compilan el IDE y msbuild mientras nadie pide
      otra: la seleccionada (el selector), con el nombre que declara el
      proyecto; Debug si no tiene selector (un .dproj de antes de las
      plataformas: 339 de los 3295 de esta maquina, medido el 18-oct-2026). }
    function ConfigPorDefecto: string;
    { True si el proyecto DECLARA APlatform y la tiene activa: lo que el IDE
      compila sin tocar nada. Sin bloque <Platforms> (un proyecto anterior a
      las plataformas), solo la suya por defecto. }
    function Declara(const APlatform: string): Boolean;
    { True if this project's framework can target APlatform. VCL is Windows
      only; FMX and non-visual (console/None) cross platforms. }
    function CanTarget(const APlatform: string; out AReason: string): Boolean;
  end;

  { Una carpeta donde un build deja ficheros, tal como la declara el proyecto. }
  TBuildOutputDir = record
    Tag: string;   // DCC_ExeOutput, DCC_DcuOutput...
    Value: string; // el valor escrito, ya desescapado
    Dir: string;   // absoluto y resuelto; '' si no se sabe resolver
  end;

{ ---- tolerant XML primitives (shared) ---- }

{ Inner texts of <ATag ...>...</ATag>, in document order, como los da XML
  (ValorDeTramo): el valor de verdad, la inversa de XmlElemento. SIN distinguir
  mayusculas y con cualquier blanco tras el nombre: MSBuild no distingue
  mayusculas en el nombre de una propiedad, y una puerta lee con esta. }
function AllTagValues(const AXml, ATag: string): TArray<string>;

{ Value of one attribute across every <ATag attr="...">, in document order,
  como lo da XML (ValorDeAtributo). AConOcultos: tambien las etiquetas que hay
  dentro de un comentario o un CDATA, que para el juez no lo son - solo el
  escaner de peligros, mas estricto que el juez. }
function AllTagAttr(const AXml, ATag, AAttr: string; AConOcultos: Boolean = False): TArray<string>;

{ Merge an accumulating MSBuild property (each value may embed $(Prop) = the
  value so far). }
function MergeProperty(const AXml, APropName: string): string;

function XmlUnescape(const S: string): string;
{ Los trozos de una lista de MSBuild (a;b;c) tal como esta ESCRITA en el XML,
  con sus entidades: el ';' de un &amp; no separa. Para reescribir en su sitio
  SOLO el trozo que cambia: XmlUnescape de cada trozo da su valor, y XmlEscape
  del nuevo es lo que se escribe. Trocear la lista desescapada y escaparla
  entera de vuelta reescribia tambien lo que no se tocaba (&#38; -> &amp;#38;,
  revision del 26-sep-2026). }
function TrozosEscritos(const AEscrito: string): TArray<string>;
{ La inversa de XmlUnescape, para escribir un valor en un atributo o en el
  texto de un elemento: un & o unas comillas en una ruta (una carpeta R&D)
  rompen el fichero. }
function XmlEscape(const S: string): string;
{ ...para escribir DENTRO de un atributo ya escrito, con la comilla que lo
  cierra (AXml[AAtributo.Ini - 1]): entre comillas simples se escapa tambien
  la ' (lo que compone el servidor va siempre entre dobles: XmlAtributo). }
function XmlEscapeEn(const S: string; AComilla: Char): string;
{ EL escritor de un atributo: Nombre="valor escapado". Una ruta con & o
  comillas (una carpeta R&D) rompia el .dproj, el .deployproj o el grupo:
  nueve sitios lo componian a mano (26-sep-2026). Su lector es AllTagAttr,
  que devuelve el valor ya desescapado. }
function XmlAtributo(const ANombre, AValor: string): string;
{ EL escritor de un elemento de texto: <ATag>valor escapado</ATag>. Un & en
  una ruta (una carpeta R&D) escrito tal cual rompia el .dproj, el
  .deployproj o el .profile, y una treintena de sitios lo componian a mano
  (26-sep-2026). Sus lectores (AllTagValues, TagValue, PlatformProperty)
  devuelven el valor ya desescapado. }
function XmlElemento(const ATag, AValor: string): string;

type
  { Una <Tag> que FijaPropiedadParaTodos ha reescrito: la Condition del
    PropertyGroup que la lleva, tal cual esta escrita ('' = sin condicion), el
    valor que tenia, ya desescapado, y si ese grupo es el base. }
  TValorReescrito = record
    Grupo: string;
    Antes: string;
    EnBase: Boolean;
  end;

{ Una propiedad con el MISMO valor en todas las configuraciones y plataformas
  de un .dproj - la inversa de AllTagValues para escribir, con su mismo
  analisis: cada <ATag> de un PropertyGroup, en el grupo que sea, pasa a valer
  AValor, y si el grupo base ('$(Base)'!='') no la lleva se le escribe, que es
  de donde la heredan los demas. ACambios: una entrada por cada una que ya
  estaba, en orden de documento. False, con AXml sin tocar, si habia que
  escribirla en la base y el .dproj no tiene grupo base. set-output solo
  cambiaba la primera <DCC_ExeOutput>: una config con su propia carpeta se
  quedaba con ella y el build de Debug salia alli mientras la respuesta decia
  Compiled (D4 de la auditoria de la 1.20.1, medido el 17-oct-2026: de los 296
  .dproj de los Samples de la 37.0, 192 la fijan y 5 en mas de un grupo). }
function FijaPropiedadParaTodos(var AXml: string; const ATag, AValor: string;
  out ACambios: TArray<TValorReescrito>): Boolean;

{ ---- los grupos y las etiquetas de un .dproj: UN analisis ----
  Lo leian y escribian a mano cinco sitios, cada uno a su manera: la etiqueta
  exacta sin atributos, "el ultimo <propertygroup abierto antes", el grupo por
  su Condition escrita letra a letra, una regex por vista (D4 de la auditoria
  de la 1.20.1). Uno que leia y otro que escribia distinto es como set-output
  reescribio la carpeta equivocada. }

type
  { Una <Tag>..</Tag>: el elemento entero es AXml[Abre .. Cierra - 1], y su
    valor, sin desescapar, AXml[Ini .. Fin - 1]. Vacio: era un <Tag/>, y
    Ini = Fin = Cierra. }
  TTramoXml = record
    Abre, Ini, Fin, Cierra: Integer;
    Vacio: Boolean;
  end;

  { Un <PropertyGroup> o un <ItemGroup>: el grupo entero es AXml[Abre ..
    Cierra - 1], su contenido AXml[Ini .. Fin - 1], y su Condition tal cual
    esta escrita ('' = sin condicion). Vacio: era un <Grupo .../>. }
  TGrupoXml = record
    Abre, Ini, Fin, Cierra: Integer;
    Vacio: Boolean;
    Condicion: string;
  end;

  { Un atributo de una etiqueta de apertura: su nombre tal cual esta escrito
    (empieza en AXml[Abre]) y su valor, sin comillas y sin desescapar, en
    AXml[Ini .. Fin - 1] - para reescribirlo en su sitio, o quitarlo entero
    hasta su comilla de cierre (AXml[Fin]); ValorDeAtributo da lo que vale. }
  TAtributoXml = record
    Nombre: string;
    Abre, Ini, Fin: Integer;
  end;

{ Cada <ATag>..</ATag> de AXml, en orden de documento: el UNICO analisis de una
  etiqueta - sin distinguir mayusculas, con atributos y blancos tras el nombre,
  un '>' entre comillas no la cierra, cada una con SU cierre aunque lleve
  dentro otra del mismo nombre, y lo que hay en un comentario, un CDATA o una
  instruccion de proceso no es una etiqueta -, con el que lee AllTagValues y
  escriben los editores del .dproj, el .deployproj y el .groupproj. Contrastado
  con MSXML, el juez que carga el IDE, por tests/test_oraculo_xml.py. Una
  <ATag/> no tiene valor y solo sale si se piden (AConVacios: un grupo vacio
  que el IDE deja escrito es donde van las entradas de esa plataforma);
  AConOcultos, tambien las de dentro de un comentario o un CDATA (el escaner de
  peligros, mas estricto que el juez). }
function TramosDeEtiqueta(const AXml, ATag: string; AConVacios: Boolean = False;
  AConOcultos: Boolean = False): TArray<TTramoXml>;
{ El texto en que se buscan las etiquetas de AXml: en minusculas y, salvo
  AConOcultos, con los comentarios, los CDATA y las instrucciones de proceso
  tapados. Quien busca VARIAS etiquetas en el mismo texto lo calcula una vez
  y se lo da a TramosEnTexto: la mudanza busca veinte por fichero, y
  calcularlo veinte veces la hacia un 20% mas lenta que las regex de antes
  con una raiz de 300 proyectos (medido el 17-oct-2026). }
function TextoDeBusqueda(const AXml: string; AConOcultos: Boolean = False): string;
{ ...y TramosDeEtiqueta sobre ese texto ya calculado (ALow, el de AXml). }
function TramosEnTexto(const AXml, ALow, ATag: string; AConVacios: Boolean = False): TArray<TTramoXml>;
{ El texto de un elemento como lo da XML: los CDATA tal cual, los comentarios
  fuera, las entidades decodificadas y los saltos de linea en LF. }
function ValorDeTramo(const AXml: string; const ATramo: TTramoXml): string;
{ Los atributos de la etiqueta de apertura de ATramo, en orden y con la
  posicion de su valor: EL lector de atributos (AllTagAttr lee con el). }
function AtributosDeTramo(const AXml: string; const ATramo: TTramoXml): TArray<TAtributoXml>;
{ Lo que vale un atributo, como lo da el juez (MSXML6, el que carga el IDE):
  las entidades decodificadas y los saltos de linea en LF, como el texto. Los
  tabuladores y los saltos NO pasan a blancos, aunque XML lo pida: MSXML no lo
  hace, ni con preserveWhiteSpace ni sin el (medido el 17-oct-2026; lo vigila
  el fichero plantado de tests/test_oraculo_xml.py). }
function ValorDeAtributo(const AXml: string; const AAtributo: TAtributoXml): string;
{ ...las que estan dentro de AGrupo }
function TramosEnGrupo(const AXml, ATag: string; const AGrupo: TGrupoXml;
  AConVacios: Boolean = False): TArray<TTramoXml>;
{ ...las que estan dentro del elemento ADentro (las <Key> de un
  <BuildConfiguration>, las <Platform> de un <Platforms>, la <FileMask> de
  un <ProfileInclude>). }
function TramosDentro(const AXml, ATag: string; const ADentro: TTramoXml;
  AConVacios: Boolean = False): TArray<TTramoXml>;
{ El valor (ValorDeTramo, sin blancos alrededor) de la primera <ATag> que hay
  dentro de ADentro; '' si no la lleva: la <FileMask> y el <SubDirs> de una
  ruta de un SDK. }
function ValorDentro(const AXml, ATag: string; const ADentro: TTramoXml): string;
{ AXml[AIni .. AFin - 1] con su linea, para reescribirlo o quitarlo sin dejar
  un hueco: ADesde retrocede sobre los blancos de delante y AHasta, si tras
  el solo hay blancos hasta el salto de linea, llega detras del salto (o al
  final). La forma que escriben DccRefXml y los items del .groupproj, que la
  buscaban con cinco regex [ \t]*...\r?\n. }
procedure ConSuLinea(const AXml: string; AIni, AFin: Integer; out ADesde, AHasta: Integer);
{ El '<' del </Project> del elemento raiz; 0 si no lo tiene. Donde entra lo
  que va al final de un .dproj, un .deployproj o un .groupproj: eran tres
  Pos de '</Project>' a mano, uno sin mirar mayusculas. }
function CierreDelProyecto(const AXml: string): Integer;
{ El valor de un atributo del elemento de ATramo (Include, Condition...), ya
  desescapado; '' si no lo lleva. Por EL lector de atributos (AllTagAttr):
  en cualquier orden, con comillas simples o dobles. }
function AtributoDeTramo(const AXml: string; const ATramo: TTramoXml;
  const ATag, AAtributo: string): string;
{ Los grupos AElemento (PropertyGroup, ItemGroup) de AXml con su Condition,
  en orden de documento: el UNICO recorrido de los grupos, sobre
  TramosDeEtiqueta. }
function GruposDe(const AXml, AElemento: string; AConVacios: Boolean = False): TArray<TGrupoXml>;
{ ...los <PropertyGroup> con contenido. }
function GruposDePropiedades(const AXml: string): TArray<TGrupoXml>;
{ Una Condition en la forma en que se comparan: minusculas y sin blancos. }
function CondicionNormalizada(const ACondicion: string): string;
{ El primer grupo cuya Condition es ACondicion, comparadas normalizadas: el IDE
  y una mano no escriben los blancos igual. }
function GrupoConCondicion(const AXml, ACondicion: string; out AGrupo: TGrupoXml): Boolean;
{ Las Condition de los grupos que el IDE escribe para una plataforma - EL
  nombrador, y PlataformaDeGrupo su inversa -: la de sus VALORES,
  '$(Base_X)'!='' (con APlatform = '', '$(Base)'!='': la base), y la de su
  DEFINIDOR, ('$(Platform)'=='X' and '$(Base)'=='true') or '$(Base_X)'!=''.
  AClave: la de una configuracion (Cfg_1: '$(Cfg_1_X)'!='', '$(Cfg_1)'!=''),
  Base si no se dice. Las escribian a mano delphi_create y el evaluador
  (1.20.2). }
function GroupCondition(const APlatform: string; const AClave: string = 'Base'): string;
function DefinerCondition(const APlatform: string; const AClave: string = 'Base'): string;
{ ...y la del definidor de una CONFIGURACION: '$(Config)'=='Debug' or
  '$(Cfg_1)'!='' (la base: '$(Config)'=='Base' or '$(Base)'!=''). }
function ConfigDefinerCondition(const AConfig, AClave: string): string;
{ El grupo DEFINIDOR de AClave en APlatform como lo escribe el IDE, entero y
  sin el salto del final: su Condition (DefinerCondition), <AClave_X>true,
  <CfgParent>AClave y las claves de las que hereda (<Cfg_1>true si no es la
  base, y <Base>true). EL escritor: delphi_create y add-platform. }
function XmlGrupoDefinidor(const APlatform, AClave: string): string;
{ ...y el de sus VALORES: la Condition de GroupCondition y AProps dentro (sus
  lineas, cada una con su salto), entero y sin el salto del final. EL
  escritor: delphi_create y add-platform (se escribia a mano en los dos;
  revision del 18-oct-2026). }
function XmlGrupoDeValores(const APlatform, AClave, AProps: string): string;
{ La plataforma (una de las conocidas, con su grafia) de un grupo de valores
  (ADefinidor = False) o de un definidor; '' si la Condition no es la de
  ninguna - la base tampoco: esa es GroupCondition(''). }
function PlataformaDeGrupo(const ACondicion: string; ADefinidor: Boolean): string;
{ Las Condition de plataforma y config, como las escriben el IDE y el servidor
  en un grupo o en un elemento - EL nombrador, y CondicionDePlataformaYConfig
  su inversa -: '$(Platform)'=='X' (el ItemGroup de una plataforma en el
  .deployproj), con AConfig '$(Platform)'=='X' And '$(Config)'=='Y' (el
  manifiesto que genera el servidor), y ConfigCondition, '$(Config)'=='Y' (un
  DeployFile de una config). Se componian a mano en siete sitios. }
function DeployGroupCondition(const APlatform: string; const AConfig: string = ''): string;
function ConfigCondition(const AConfig: string): string;
{ EL escritor de una entrada <DeployFile> del .deployproj, como la escribe el
  IDE (sangrias de 8 y 12, un salto por linea, que PatchSaveConSuSalto deja
  como el del fichero); AConfig '' = sin Condition. Eran cuatro compositores
  a mano, cada uno con sus campos: el manifiesto que se genera, el de
  Android, la salida que se le anade y add-deployfile. Lo leen
  FindDeployEntries y TramosEnGrupo. }
function XmlDeployFile(const AInclude, AConfig, ARemoteDir, ARemoteName, AClase: string;
  AOperacion: Integer; ARequerido: Boolean): string;
{ La plataforma y la config que nombra una Condition de esas formas - la
  plataforma sola, la config sola, o las dos con And en cualquier orden, que el
  IDE escribe '$(Config)'=='Debug' And '$(Platform)'=='Win32' -, tal cual
  estan escritas ('' la que no nombra). False si la Condition es otra cosa: lo
  que no se sabe si se aplica no se da por aplicado. }
function CondicionDePlataformaYConfig(const ACondicion: string; out APlataforma, AConfig: string): Boolean;
{ La plataforma (con la grafia de las conocidas, y la que no lo es tal cual) de
  un ItemGroup del .deployproj; '' si su Condition no es de una plataforma. }
function PlataformaDeGrupoDeDespliegue(const ACondicion: string): string;

type
  { Un trozo de un texto escrito: AEscrito[Ini .. Fin - 1]. }
  TTrozoEscrito = record
    Ini, Fin: Integer;
  end;

{ Las rutas de los Exists('...') de una Condition tal como esta ESCRITA (con
  sus entidades), por su posicion en ella: la otra parte de la gramatica de
  condiciones de msbuild que lee el servidor, junto a
  CondicionDePlataformaYConfig. La mudanza re-apunta asi el .optset que
  importa un .dproj; era una regex Exists\('...'\) sobre el texto entero. }
function RutasDeExists(const AEscrita: string): TArray<TTrozoEscrito>;
{ Quita AXml[AIni .. AFin - 1] y, si eso ocupaba su linea solo, la linea con
  ello: sus blancos de delante y el salto que la precede. Lo escribian a mano,
  de tres maneras, remove-searchpath, set-sdk / set-profile y
  remove-deployfile (D3 de la auditoria de la 1.20.1). }
procedure QuitaConSuLinea(var AXml: string; AIni, AFin: Integer);

{ ---- .dproj reading ---- }

{ Reads a .dproj file. Missing file / unreadable -> empty record (all fields
  blank), never raises. }
function ReadDproj(const ADprojPath: string): TDprojInfo;
{ ...lo mismo de un texto ya leido: quien lee el .dproj una vez para varias
  preguntas (los ajustes del motor) no lo lee dos. }
function InfoDeDproj(const AXml: string): TDprojInfo;
{ El SELECTOR de ATag (Config o Platform): el primer <ATag Condition="...">X</ATag>
  sin value, lo que el IDE y msbuild compilan mientras nadie pide otro. EL
  lector (ReadDproj) y el sitio donde escribe set-active. False si no hay. }
function SelectorDe(const AXml, ATag: string; out ATramo: TTramoXml): Boolean;
{ ...y su escritor: <ATag Condition="'$(ATag)'==''">AValor</ATag>, como lo
  escribe el IDE (delphi_create; set-active cambia el valor en su sitio). }
function XmlSelector(const ATag, AValor: string): string;

type
  { Una plataforma del bloque <Platforms>: <Platform value="Win64">True</Platform>.
    Nombre, su value (desescapado); su valor esta en AXml[Tramo.Ini ..
    Tramo.Fin - 1], para reescribirlo en su sitio. }
  TPlataformaDelBloque = record
    Nombre: string;
    Activa: Boolean;
    Tramo: TTramoXml;
  end;

{ El bloque <Platforms> (el primero); False si el .dproj no lo tiene. }
function BloqueDePlataformas(const AXml: string; out ABloque: TTramoXml): Boolean;
{ Las plataformas que declara el .dproj, en orden de documento: EL lector del
  bloque (ReadDproj, add-platform, remove-platform). El nombre y si esta
  activa salen del MISMO elemento (R6-A), y el selector
  <Platform Condition="...">X</Platform>, que no lleva value, no es una. Eran
  un Pos de '<platform value="' en ReadDproj y otro, con su formato, en cada
  editor de Mcp.Tools.Config. }
function PlataformasDelBloque(const AXml: string): TArray<TPlataformaDelBloque>;
{ ...y su escritor: <Platform value="X">True</Platform> (o False). }
function XmlPlataformaDelBloque(const APlatform: string; AActiva: Boolean): string;

type
  { Una clave de un <VerInfo_Keys> (FileVersion=1.0.0.0;minSdkVersion=23;...):
    su nombre tal cual y su valor, escrito, en AXml[Ini .. Fin - 1]. }
  TClaveDeVersion = record
    Nombre: string;
    Ini, Fin: Integer;
  end;

{ Las claves de cada <VerInfo_Keys> de AXml, en orden de documento: EL lector
  (set-version, el manifiesto de Android). Buscar FileVersion= en todo el
  texto no es leer una clave: set-version reescribia tambien lo que dijera un
  evento de build, y el manifiesto preguntaba por minSdkVersion en cualquier
  sitio del .dproj. }
function ClavesDeVersion(const AXml: string): TArray<TClaveDeVersion>;

{ EL .dproj de lo que nombra el agente: el de al lado de un .dpr o un .dpk,
  y cualquier otra cosa tal cual (la tool decide si es un proyecto). Solo
  cambia la extension: ni completa ni normaliza la ruta, quien la necesite
  entera la pide aparte. delphi_config resolvia el .dpr y delphi_build lo
  rechazaba con BUILD-016 diciendo que no era un proyecto (Hermes, validacion
  de la 1.16.0), y la regla estaba escrita a mano en diez sitios. }
function DprojDe(const AProject: string): string;
{ Su inversa: la FUENTE PRINCIPAL de un .dproj - el .dpr de al lado, o el
  .dpk si no hay .dpr y si hay .dpk (un paquete; lo decide el disco) - y
  cualquier otra cosa tal cual. Estaba escrita a mano en tres sitios (el
  filtro de directivas del build, el de delphi_test y el lector del
  scaffold; 2.2 de la 1.18.0), y el paquete solo lo sabia
  ResolveProjectPair: un form en un paquete dado por su .dproj se juzgaba
  como el de un programa de consola (P9 de la segunda revision de la
  1.17.0). }
function DprDe(const AProject: string): string;

{ La negativa de una configuracion que el proyecto no tiene ('' = la tiene,
  o el proyecto no declara ninguna). UNA regla para delphi_test y
  delphi_build: aceptarla en silencio compilaba en Win64\<Inventada>\ con
  los ajustes de Base (medido el 2026-08-25 en test y el 27-sep en build).
  Antes que la lista, el NOMBRE (NombreDeConfigNoValido): el valor va a la
  linea de msbuild (por cmd.exe hasta 2an de la 1.18.2; sin shell ahora, el
  juez queda de segunda barrera), y ni un proyecto sin configuraciones ni uno que
  declara un nombre raro lo hacen seguro (4.8, revision de la 1.18.1). Base,
  su negativa propia (CFG-120). ADeLaSeleccion: AConfig no lo pidio el agente,
  es la seleccionada del proyecto (ConfigPorDefecto), y la negativa lo dice
  (CFG-121): "no existe" de algo que no habia pedido no se entendia (revision
  del 18-oct-2026). }
function ConfigDesconocida(const ADproj, AConfig: string;
  ADeLaSeleccion: Boolean = False): string;

{ El nombre de una configuracion que puede llegar a la linea de msbuild del
  build (/p:Config=): letras, digitos, espacio, ".", "_" y "-". UNA
  definicion para la puerta (Lsp.Guard.BuildArgDenied) y el fondo
  (ConfigDesconocida); '' no es un nombre malo (es "la de por defecto"). }
{ Los cuatro targets de delphi_build, con SU nombre: la puerta los admite
  (BuildArgDenied) y el build elige entre ellos el que va a /t: (UNA lista,
  dos lectores; punto 3 del build, 1.19.0). }
const
  TARGETS_DE_BUILD: array[0..3] of string = ('Build', 'Make', 'Clean', 'Deploy');

function NombreDeConfigNoValido(const AConfig: string): Boolean;

{ La negativa de una plataforma que el proyecto no declara o tiene
  desactivada ('' = la declara activa). Lo que compila un agente lo tiene que
  compilar igual el operador al abrir el proyecto en el IDE, sin
  reconfigurar nada (David, 6-oct-2026): msbuild compilaba Linux64 de un
  proyecto que no la declaraba, sin sus ajustes de plataforma, y el IDE no la
  mostraba (medido; el GuiProbe de Hermes "perdio" asi una plataforma que
  nunca tuvo). delphi_config add-platform / remove-platform las declaran. }
function PlataformaNoDeclarada(const AInfo: TDprojInfo; const APlatform: string): string;

{ Las plataformas de paclient, para los mensajes que las ensenan: las de
  PACLIENT_PLATFORMS, la misma lista que valida (estaban copiadas a mano). }
function PaclientPlatformsList: string;

{ True when APlatform is one that never needs a remote profile/SDK (it builds
  natively on this Windows host). }
function IsLocalPlatform(const APlatform: string): Boolean;

{ The CANONICAL set of Delphi target platforms. add-platform validates
  against this: a platform name is a fixed, known token, so anything else is
  rejected outright - which also makes it impossible to inject XML into the
  .dproj through the platform name (measured RCE vector, field round 5).
  Returns the correctly-cased canonical name, or '' if unknown. }
function CanonicalPlatform(const AName: string): string;

{ La plataforma -nombre canonico, el del .dproj, delphi_build y los .sdk
  (Profile_platform)- de una clave Library del registro del IDE. Iguales
  salvo UNA: el IDE llama Android32 a la clave Library de la plataforma que
  el proyecto, los .sdk y la carpeta lib\android llaman Android (medido en el
  registro el 14-oct-2026). '' si la clave no es una plataforma conocida.
  (M4 del revisor de cierre: platforms la preguntaba por el nombre de la clave
  y decia "needs a PAServer profile + SDK" con su .sdk puesto.) }
function PlataformaDeClaveLibrary(const AClave: string): string;

{ La lista de plataformas validas, para los mensajes que la ensenan: la
  misma que valida CanonicalPlatform (estaba copiada a mano en tres textos
  con 11 nombres mientras el validador aceptaba 13). }
function KnownPlatformsList: string;

{ Una carpeta RELATIVA al proyecto, apta para acabar escrita DENTRO de un
  .dproj o de un .dpr: nombre simple o con niveles (Compiled, bin\out,
  Dominio\Modelos), sin unidad ni ruta absoluta, sin "..", y solo con
  caracteres de una lista blanca - para que nada pueda inyectarse en el XML
  del .dproj como hizo R5-B. Devuelve el token limpio en AClean.

  Vivia en Mcp.Tools.Config, privada, para set-output. Se sube aqui el
  2026-09-21 porque delphi_create necesita EXACTAMENTE la misma regla para la
  subcarpeta donde crea una unit (su ruta acaba en DCCReference Include=".."
  y en el in '..' del .dpr): iba a escribirse una hermana a mano, SIN la
  lista blanca. Lo paro David: "cuidado que no exista ya algo parecido". }
function ValidOutputFolder(const AFolder: string; out AClean: string): Boolean;

const
  { The platforms paclient.exe accepts for --platform= (its own help lists
    exactly these). Narrower than CanonicalPlatform - Android deploys without
    PAServer. One definition, shared by the gate and delphi_paserver. }
  PACLIENT_PLATFORMS: array[0..4] of string =
    ('Win32', 'Win64', 'WinARM64EC', 'OSX64', 'Linux64');

  { Las propiedades con las que dcc decide DONDE deja lo que produce:
    -E exe/dll, -NU dcu, -LE bpl, -LN dcp, -NH hpp, -NO obj, -NB bpi. UNA
    lista: la puerta del build (BuildOutputDirs) y la mudanza, que las
    re-apunta (estaba repetida en Lsp.ProjectUnits, revision 26-sep). Y
    BRCC_OutputDir, donde los targets dejan el .res de version y el de cada
    .rc: no estaba, y un .dproj que la apuntaba fuera de las raices escribia
    alli su P.res (medido el 14-oct-2026, 1.18.3). }
  BUILD_OUTPUT_TAGS: array [0 .. 7] of string = (
    'DCC_ExeOutput', 'DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput',
    'DCC_HppOutput', 'DCC_ObjOutput', 'DCC_BpiOutput', 'BRCC_OutputDir');

{ Value of <ATag>...</ATag> in a small TRUSTED XML (our own .profile/.sdk
  files, written by paclient or by this server). Not a general parser on
  purpose. One definition, shared by delphi_paserver, delphi_adb and
  remote-run. Ya desescapado, como AllTagValues: la inversa de XmlElemento. }
function TagValue(const AXml, ATag: string): string;

{ El valor de una propiedad DE PLATAFORMA (PlatformSDK, Profile...) como lo
  ve msbuild para esa plataforma sin mirar la config: de los grupos que le
  aplican - sin condicion, la base y el de esa plataforma ('$(Base_<Plat>)'!='',
  donde la escriben el IDE y delphi_config set-sdk / set-profile) -, el ultimo
  que la fija; la del grupo de OTRA plataforma, nunca. Es la inversa de los
  escritores: leer "el primer <PlatformSDK> del fichero" le daba a un build
  OSX64 el SDK de Linux64 (paisaje del 2026-09-22). '' si no hay. }
function PlatformProperty(const AXml, APlatform, ATag: string): string;

{ El valor EFECTIVO de ATag para un build APlatform/AConfig, como lo evalua
  msbuild: los grupos que se aplican a ese build, en orden de documento, el
  ultimo que la fija gana, y un $(ATag) dentro del valor es lo que valia
  hasta ahi (<DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>, como escribe el IDE
  los defines de cada configuracion). El juez de las propiedades por
  grupos: la salida, el SDK, el perfil, los paquetes y los ajustes del motor.
  Una configuracion que hereda de otra que no es Base no suma los grupos de
  esa otra: medido el 18-oct-2026, 0 de los 3295 .dproj de esta maquina. }
function EffectiveProperty(const AXml, ATag, APlatform, AConfig: string): string;

type
  { Una entrada del search path de un proyecto: tal como esta escrita (ya
    desescapada) y resuelta contra la carpeta del .dproj. Carpeta = '' si
    no se deja resolver (lleva caracteres que no son de ruta). }
  TRutaDeBusqueda = record
    Escrita: string;
    Carpeta: string;
  end;

{ Las entradas del search path (DCC_UnitSearchPath) de un .dproj, en orden
  de documento, sin las vacias ni las que llevan una macro sin resolver.
  Si existen o si se pueden leer lo decide quien llama. Era el mismo bucle
  escrito tres veces: el informe de fix-references, delphi_projects y los
  proyectos que compilan contra una carpeta (26-sep-2026). }
function RutasDeBusqueda(const ADprojPath, AXml: string): TArray<TRutaDeBusqueda>;
{ True si una entrada del search path de ADprojPath (AXml, su texto) es la
  carpeta ADir: el proyecto compila contra las unidades de alli aunque no las
  liste. La pregunta de las referencias (los proyectos que consumen una
  carpeta) y la de que proyecto sirve a una unidad (Lsp.Session.FindDproj). }
function BuscaEnCarpeta(const ADprojPath, AXml, ADir: string): Boolean;

{ Whether a project would EXECUTE a shell during a build: a custom MSBuild
  <Target> or <Exec> task (with or without an XML namespace prefix), a
  non-empty RAD Studio build-event command, or an <Import> of anything that is
  not one of the IDE's own targets files. A stock RAD Studio project has none
  of these. Their presence turns "build" into "run", which a compile-only
  server must refuse unless the operator opted into execution.

  Imports are FOLLOWED: an import that resolves to a readable file inside the
  project is scanned too, recursively. Field round 8 defeated a rule that only
  looked at the .dproj by importing "$(MSBuildProjectDirectory)\payload.targets"
  - macro-based, so it passed a naive macro check, while resolving to a file
  uploaded right next to the project. Only the IDE's own imports are trusted
  without reading them; anything unresolvable is refused rather than assumed
  harmless.

  AProjectPath is the .dproj being built (used to resolve the imports).
  Returns the offending construct, or '' when the project is safe to build. }
{ AIgnoreBuildEvents: no contar los eventos pre/post build (firma, copia):
  delphi_build los SALTA en vez de rechazar el proyecto, vaciandolos en la
  linea de msbuild, y lo dice (David, 24-sep-2026: "una cosa es compilar la
  version final, otra poder trabajar y ejecutar mientras tanto"). }
function DprojBuildHazard(const AXml, AProjectPath: string;
  AIgnoreBuildEvents: Boolean = False): string;

{ The artifact a build just produced, found ON DISK (truth of the moment,
  never an index): candidate output dirs are every DCC_ExeOutput /
  DCC_BplOutput declared in the .dproj plus the IDE default
  .\$(Platform)\$(Config), with the common macros expanded; the newest
  existing <project>.exe/.dll/.bpl among them wins. Returns '' when nothing
  is there (build failed, macro we cannot resolve, unusual layout). }
function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;

{ TODAS las carpetas donde un build de ADprojPath (APlatform/AConfig) deja
  ficheros, tal como las declaran el .dproj y lo que importa del proyecto
  (un .optset): cada valor de cada DCC_*Output, en CUALQUIER grupo - las
  condiciones no se evaluan: una de mas es prudencia, una de menos es una
  puerta -, con las macros comunes expandidas y resuelto contra la carpeta
  del proyecto. Dir = '' cuando el valor no se sabe resolver (una macro, un
  escape): quien pregunta decide, y la puerta de build lo rechaza. Una
  etiqueta ausente o vacia no sale: es la del IDE por defecto. }
function BuildOutputDirs(const ADprojPath, APlatform, AConfig: string): TArray<TBuildOutputDir>;

{ Los ficheros de recursos que los targets escriben JUNTO al .dproj cuando no
  hay BRCC_OutputDir ($(BRCC_OutputDir)<nombre>.res, CodeGear.Common.Targets):
  el de version del proyecto (<proyecto>.res y su .vrc) y el de cada .rc que
  compila (RcCompile). Siempre los de la carpeta del proyecto: con la carpeta
  declarada, uno de mas es prudencia. Rutas completas. }
function BuildResourceFiles(const ADprojPath: string): TArray<string>;

{ La carpeta de salida que este proyecto NO declara y que el IDE pondria
  fuera de el, o '' si declara todas las que usa: sin DCC_DcuOutput los .dcu
  caen junto a cada fuente (tambien las de una referencia de solo lectura);
  un paquete sin DCC_BplOutput/DCC_DcpOutput los deja en las carpetas
  globales del IDE, y la salida C++ (DCC_CBuilderOutput) sin DCC_HppOutput
  deja alli los .hpp (los .obj y .bpi van a la del .dcp). Decidido con David
  (25-sep-2026): se rechaza y se pide declararla. Medido: 1 de 22 proyectos
  de nuestras raices. Se mira PARA ESTE BUILD (APlatform/AConfig): cada
  plataforma y config puede tener su carpeta, o heredar la global
  (EffectiveProperty). }
function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): string;

{ True si el build APlatform/AConfig de ADprojPath enlaza con paquetes en
  tiempo de ejecucion (UsePackages=true en su valor EFECTIVO, en el .dproj o
  en lo que importa del proyecto): el exe cargara .bpl de fuera al
  arrancar. Basta con que uno de la cadena lo diga. Lo pregunta delphi_test,
  cuya jaula no deja leer esos .bpl (David, 2-oct-2026: "lo compilas entero
  o no molestes"). }
function UsaPaquetesEnEjecucion(const ADprojPath, APlatform, AConfig: string): Boolean;

{ La propiedad de ENTORNO del IDE que este proyecto -o algo que importa-
  REDEFINE, o '' si no toca ninguna. Los <Import> de CodeGear.Common.Targets
  (EnvironmentSettings/EnvOptions/Profiles/GlobalOptionFile) y de
  CodeGear.Profiles.Targets, mas el UserTools.proj de todo .dproj, resuelven A
  TRAVES de estas propiedades el fichero que cargan; el servidor confia esos
  <Import> del IDE sin leerlos (IsStockImport), asi que redefinir una las
  desvia a un fichero elegido por el proyecto: codigo cargado y ejecutado en el
  build SIN un <Import> visible. Se mira la misma cadena que
  BuildOutputUndeclared (el .dproj y lo que importa del proyecto). Es la parte
  2 del gate del build, hermana de BuildOutputUndeclared (la 1). }
function RedefinedIdeImportProperty(const ADprojPath: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  Lsp.Texts,
  Lsp.Patch, // LeeTexto: la puerta de leer (el .dproj y sus Import, en la jaula)
  System.Character;

{ El '>' que cierra la etiqueta abierta antes de AFrom, saltando lo que va
  entre comillas: un Condition="'$(A)'>'1'" no la cierra. 0 si no hay. }
function FinDeEtiqueta(const AXml: string; AFrom: Integer): Integer;
var
  Q: Char;
begin
  Q := #0;
  Result := AFrom;
  while Result <= Length(AXml) do
  begin
    if Q <> #0 then
    begin
      if AXml[Result] = Q then
        Q := #0;
    end
    else if CharInSet(AXml[Result], ['"', '''']) then
      Q := AXml[Result]
    else if AXml[Result] = '>' then
      Exit;
    Inc(Result);
  end;
  Result := 0;
end;

{ El texto en que se buscan las etiquetas: en minusculas (LowerCase solo toca
  A..Z, asi que las posiciones valen en AXml) y, salvo AConOcultos, con los
  comentarios, los CDATA y las instrucciones de proceso tapados con blancos:
  lo que hay dentro no son etiquetas para un parser de XML - el juez, MSXML,
  no las ve. Los saltos de linea se quedan (alguien cuenta lineas). }
{ True si en AText[AAt] empieza ASub, comparando en sitio: TextoDeBusqueda
  lo pregunta en cada '<' del fichero, y un Copy por pregunta era la mitad
  de su coste (medido el 17-oct-2026). }
function HayEn(const AText: string; AAt: Integer; const ASub: string): Boolean;
begin
  Result := (AAt >= 1) and (AAt + Length(ASub) - 1 <= Length(AText)) and
    CompareMem(@AText[AAt], Pointer(ASub), Length(ASub) * SizeOf(Char));
end;

function TextoDeBusqueda(const AXml: string; AConOcultos: Boolean): string;
var
  P, Q: Integer;
  Cierre: string;
begin
  Result := LowerCase(AXml);
  if AConOcultos then
    Exit;
  P := 1;
  while True do
  begin
    P := Pos('<', Result, P);
    if P = 0 then
      Break;
    if HayEn(Result, P, '<!--') then
      Cierre := '-->'
    else if HayEn(Result, P, '<![cdata[') then
      Cierre := ']]>'
    else if HayEn(Result, P, '<?') then
      Cierre := '?>'
    else
    begin
      Inc(P);
      Continue;
    end;
    Q := Pos(Cierre, Result, P + 2);
    if Q = 0 then
      Q := Length(Result) - Length(Cierre) + 1; // sin cierre: hasta el final
    var Hasta := Q + Length(Cierre) - 1;
    if Hasta > Length(Result) then
      Hasta := Length(Result);
    for var I := P to Hasta do
      if not CharInSet(Result[I], [#13, #10]) then
        Result[I] := ' ';
    P := Q + Length(Cierre);
  end;
end;

type
  { Una etiqueta de apertura: AXml[Abre .. Cierra - 1], '>' incluido }
  TAperturaXml = record
    Abre, Cierra: Integer;
    Vacia: Boolean; // <Tag/>
  end;

{ Cada etiqueta de apertura de ATag en ALow (TextoDeBusqueda), en orden: EL
  buscador de aperturas, el de los elementos y el de los atributos (eran dos
  bucles gemelos, uno en TramosDeEtiqueta y otro en AllTagAttr). }
function AperturasDe(const ALow, ATag: string): TArray<TAperturaXml>;
var
  Open: string;
  P, After, TagEnd: Integer;
  A: TAperturaXml;
begin
  Result := [];
  Open := '<' + LowerCase(ATag);
  P := 1;
  while True do
  begin
    P := Pos(Open, ALow, P);
    if P = 0 then
      Break;
    After := P + Length(Open);
    if (After > Length(ALow)) or
       not CharInSet(ALow[After], ['>', '/', ' ', #9, #13, #10]) then
    begin
      P := After; // <Platforms> no es <Platform>
      Continue;
    end;
    TagEnd := FinDeEtiqueta(ALow, After);
    if TagEnd = 0 then
      Break;
    A.Abre := P;
    A.Cierra := TagEnd + 1;
    A.Vacia := ALow[TagEnd - 1] = '/';
    Result := Result + [A];
    P := TagEnd + 1;
  end;
end;

{ El cierre de AAbierta, contando las del mismo nombre que lleve dentro: el
  IDE escribe <VersionInfo><VersionInfo Name="..."> en ProjectExtensions, y
  cerrar en el primer </VersionInfo> perdia el de dentro (lo vio el oraculo
  contra MSXML, 17-oct-2026). AFin, el '<' de </Tag; ACierra, lo primero
  tras su '>' (que admite blancos delante: </Tag >). False si no lo tiene. }
function CierreDe(const ALow, ATag: string; const AAbierta: TAperturaXml;
  out AFin, ACierra: Integer): Boolean;
var
  Open, CloseOpen: string;
  P, C, Q, O, After, TagEnd, Nivel: Integer;
begin
  Result := False;
  Open := '<' + LowerCase(ATag);
  CloseOpen := '</' + LowerCase(ATag);
  Nivel := 1;
  P := AAbierta.Cierra;
  while True do
  begin
    // el siguiente cierre
    C := P;
    while True do
    begin
      C := Pos(CloseOpen, ALow, C);
      if C = 0 then
        Exit;
      Q := C + Length(CloseOpen);
      while (Q <= Length(ALow)) and CharInSet(ALow[Q], [' ', #9, #13, #10]) do
        Inc(Q);
      if (Q <= Length(ALow)) and (ALow[Q] = '>') then
        Break;
      C := Q;
    end;
    // las del mismo nombre que se abren antes de el (y no son <Tag/>) suben
    O := P;
    while True do
    begin
      O := Pos(Open, ALow, O);
      if (O = 0) or (O >= C) then
        Break;
      After := O + Length(Open);
      if (After <= Length(ALow)) and CharInSet(ALow[After], ['>', '/', ' ', #9, #13, #10]) then
      begin
        TagEnd := FinDeEtiqueta(ALow, After);
        if TagEnd = 0 then
          Break;
        if ALow[TagEnd - 1] <> '/' then
          Inc(Nivel);
        O := TagEnd + 1;
      end
      else
        O := After;
    end;
    Dec(Nivel);
    if Nivel = 0 then
    begin
      AFin := C;
      ACierra := Q + 1;
      Exit(True);
    end;
    P := Q + 1;
  end;
end;

{ Los atributos de la etiqueta de apertura AXml[AAbre .. ACierra - 1], con la
  posicion de su valor. Uno a uno ('Include' no casa dentro de 'XInclude'), con
  comillas simples o dobles; uno mal formado corta la lectura. }
function AtributosDeApertura(const AXml: string; AAbre, ACierra: Integer): TArray<TAtributoXml>;
var
  A, K, NombreFin, ValEnd, TagEnd: Integer;
  At: TAtributoXml;
begin
  Result := [];
  TagEnd := ACierra - 1; // el '>'
  A := AAbre + 1;
  // el nombre de la etiqueta
  while (A < TagEnd) and not CharInSet(AXml[A], [' ', #9, #13, #10, '/', '>']) do
    Inc(A);
  while A < TagEnd do
  begin
    while (A < TagEnd) and CharInSet(AXml[A], [' ', #9, #13, #10, '/']) do
      Inc(A);
    K := A;
    while (K < TagEnd) and not CharInSet(AXml[K], ['=', ' ', #9, #13, #10, '/']) do
      Inc(K);
    NombreFin := K;
    while (K < TagEnd) and CharInSet(AXml[K], [' ', #9, #13, #10]) do
      Inc(K);
    if (K >= TagEnd) or (AXml[K] <> '=') then
      Break; // no es un atributo bien formado
    Inc(K);
    while (K < TagEnd) and CharInSet(AXml[K], [' ', #9, #13, #10]) do
      Inc(K);
    if (K >= TagEnd) or not CharInSet(AXml[K], ['"', '''']) then
      Break;
    ValEnd := Pos(AXml[K], AXml, K + 1);
    if (ValEnd = 0) or (ValEnd > TagEnd) then
      Break;
    At.Nombre := Copy(AXml, A, NombreFin - A);
    At.Abre := A;
    At.Ini := K + 1;
    At.Fin := ValEnd;
    Result := Result + [At];
    A := ValEnd + 1;
  end;
end;

function TramosDeEtiqueta(const AXml, ATag: string; AConVacios: Boolean;
  AConOcultos: Boolean): TArray<TTramoXml>;
begin
  Result := TramosEnTexto(AXml, TextoDeBusqueda(AXml, AConOcultos), ATag, AConVacios);
end;

function TramosEnTexto(const AXml, ALow, ATag: string; AConVacios: Boolean): TArray<TTramoXml>;
var
  T: TTramoXml;
  Fin, Cierra: Integer;
begin
  // SIN distinguir mayusculas y con cualquier blanco tras el nombre: con esta
  // funcion lee la puerta de las carpetas de salida (BuildOutputDirs), y ni
  // <DCC_EXEOUTPUT>, ni un salto de linea antes de Condition=, ni un '>'
  // dentro de una condicion pueden saltarsela (25-sep-2026).
  Result := [];
  for var A in AperturasDe(ALow, ATag) do
  begin
    T.Abre := A.Abre;
    if A.Vacia then
    begin
      // <Tag/> o <Tag Condition="..."/>: vacia, sin valor
      if not AConVacios then
        Continue;
      T.Ini := A.Cierra;
      T.Fin := A.Cierra;
      T.Cierra := A.Cierra;
      T.Vacio := True;
    end
    else
    begin
      // sin cierre, esa no es un elemento, pero lo que sigue se sigue leyendo:
      // con AConOcultos, un comentario puede llevar una etiqueta sin cerrar y
      // el XML seguir bien formado, y cortar aqui escondia al escaner de
      // peligros el evento de verdad que venia detras (revision del diff,
      // 17-oct-2026)
      if not CierreDe(ALow, ATag, A, Fin, Cierra) then
        Continue;
      T.Ini := A.Cierra;
      T.Fin := Fin;
      T.Cierra := Cierra;
      T.Vacio := False;
    end;
    Result := Result + [T];
  end;
end;

function ValorDeTramo(const AXml: string; const ATramo: TTramoXml): string;
var
  S, L, Cierre: string;
  P, Q, Salta: Integer;
begin
  // el IDE escribe los eventos de build en CDATA, y se leian con su
  // <![CDATA[ delante (lo vio el oraculo contra MSXML, 17-oct-2026)
  S := Copy(AXml, ATramo.Ini, ATramo.Fin - ATramo.Ini);
  Result := '';
  L := LowerCase(S);
  P := 1;
  while P <= Length(S) do
  begin
    Q := Pos('<', S, P);
    while Q > 0 do
    begin
      if HayEn(L, Q, '<![cdata[') or HayEn(L, Q, '<!--') or HayEn(L, Q, '<?') then
        Break;
      Q := Pos('<', S, Q + 1);
    end;
    if Q = 0 then
    begin
      Result := Result + XmlUnescape(Copy(S, P, MaxInt));
      Break;
    end;
    Result := Result + XmlUnescape(Copy(S, P, Q - P));
    if HayEn(L, Q, '<![cdata[') then
    begin
      Cierre := ']]>';
      Salta := 9;
    end
    else if HayEn(L, Q, '<!--') then
    begin
      Cierre := '-->';
      Salta := 4;
    end
    else
    begin
      Cierre := '?>';
      Salta := 2;
    end;
    P := Pos(Cierre, S, Q + Salta);
    if P = 0 then
      P := Length(S) + 1;
    if Cierre = ']]>' then
      Result := Result + Copy(S, Q + Salta, P - Q - Salta); // literal
    P := P + Length(Cierre);
  end;
  Result := Result.Replace(#13#10, #10).Replace(#13, #10);
end;

function AtributosDeTramo(const AXml: string; const ATramo: TTramoXml): TArray<TAtributoXml>;
begin
  // la etiqueta de apertura acaba donde empieza el valor ('/>' en una vacia)
  Result := AtributosDeApertura(AXml, ATramo.Abre, ATramo.Ini);
end;

function ValorDeAtributo(const AXml: string; const AAtributo: TAtributoXml): string;
begin
  Result := XmlUnescape(Copy(AXml, AAtributo.Ini, AAtributo.Fin - AAtributo.Ini)
    .Replace(#13#10, #10).Replace(#13, #10));
end;

function AllTagValues(const AXml, ATag: string): TArray<string>;
begin
  Result := [];
  for var T in TramosDeEtiqueta(AXml, ATag) do
    Result := Result + [ValorDeTramo(AXml, T)]; // el valor de verdad
end;

function TramosDentro(const AXml, ATag: string; const ADentro: TTramoXml;
  AConVacios: Boolean): TArray<TTramoXml>;
begin
  Result := [];
  for var T in TramosDeEtiqueta(AXml, ATag, AConVacios) do
    if (T.Abre >= ADentro.Ini) and (T.Cierra <= ADentro.Fin) then
      Result := Result + [T];
end;

function TramosEnGrupo(const AXml, ATag: string; const AGrupo: TGrupoXml;
  AConVacios: Boolean): TArray<TTramoXml>;
var
  T: TTramoXml;
begin
  T.Abre := AGrupo.Abre;
  T.Ini := AGrupo.Ini;
  T.Fin := AGrupo.Fin;
  T.Cierra := AGrupo.Cierra;
  T.Vacio := AGrupo.Vacio;
  Result := TramosDentro(AXml, ATag, T, AConVacios);
end;

function ValorDentro(const AXml, ATag: string; const ADentro: TTramoXml): string;
begin
  Result := '';
  for var T in TramosDentro(AXml, ATag, ADentro) do
    Exit(ValorDeTramo(AXml, T).Trim);
end;

procedure ConSuLinea(const AXml: string; AIni, AFin: Integer; out ADesde, AHasta: Integer);
var
  P: Integer;
begin
  ADesde := AIni;
  while (ADesde > 1) and CharInSet(AXml[ADesde - 1], [' ', #9]) do
    Dec(ADesde);
  AHasta := AFin;
  P := AFin;
  while (P <= Length(AXml)) and CharInSet(AXml[P], [' ', #9]) do
    Inc(P);
  // con algo mas detras en su linea, solo el elemento
  if P > Length(AXml) then
    AHasta := P
  else if AXml[P] = #10 then
    AHasta := P + 1
  else if AXml[P] = #13 then
  begin
    AHasta := P + 1;
    if (AHasta <= Length(AXml)) and (AXml[AHasta] = #10) then
      Inc(AHasta);
  end;
end;

function CierreDelProyecto(const AXml: string): Integer;
var
  T: TArray<TTramoXml>;
begin
  // el raiz es el primero en orden de documento (<ProjectExtensions> y
  // <Projects> son otras etiquetas para el analisis)
  T := TramosDeEtiqueta(AXml, 'Project');
  if Length(T) = 0 then
    Exit(0);
  Result := T[0].Fin;
end;

function AtributoDeTramo(const AXml: string; const ATramo: TTramoXml;
  const ATag, AAtributo: string): string;
begin
  // el ultimo, si lo repite
  Result := '';
  for var At in AtributosDeTramo(AXml, ATramo) do
    if SameText(At.Nombre, AAtributo) then
      Result := ValorDeAtributo(AXml, At);
end;

function GruposDe(const AXml, AElemento: string; AConVacios: Boolean): TArray<TGrupoXml>;
var
  G: TGrupoXml;
begin
  // un grupo es una etiqueta mas su Condition: era un segundo bucle, gemelo
  // del de TramosDeEtiqueta, solo para los PropertyGroup
  Result := [];
  for var T in TramosDeEtiqueta(AXml, AElemento, AConVacios) do
  begin
    G.Abre := T.Abre;
    G.Ini := T.Ini;
    G.Fin := T.Fin;
    G.Cierra := T.Cierra;
    G.Vacio := T.Vacio;
    G.Condicion := AtributoDeTramo(AXml, T, AElemento, 'Condition');
    Result := Result + [G];
  end;
end;

function GruposDePropiedades(const AXml: string): TArray<TGrupoXml>;
begin
  Result := GruposDe(AXml, 'PropertyGroup');
end;

{ Una Condition en la forma en que se comparan: minusculas y sin blancos }
function CondicionNormalizada(const ACondicion: string): string;
begin
  Result := LowerCase(ACondicion).Replace(' ', '', [rfReplaceAll])
    .Replace(#9, '', [rfReplaceAll]).Replace(#13, '', [rfReplaceAll])
    .Replace(#10, '', [rfReplaceAll]);
end;

function GrupoConCondicion(const AXml, ACondicion: string; out AGrupo: TGrupoXml): Boolean;
var
  N: string;
begin
  N := CondicionNormalizada(ACondicion);
  for var G in GruposDePropiedades(AXml) do
    if CondicionNormalizada(G.Condicion) = N then
    begin
      AGrupo := G;
      Exit(True);
    end;
  Result := False;
end;

procedure QuitaConSuLinea(var AXml: string; AIni, AFin: Integer);
var
  Linea: Integer;
begin
  Linea := AIni;
  while (Linea > 1) and not CharInSet(AXml[Linea - 1], [#10, #13]) do
    Dec(Linea);
  // sola en su linea: se va la linea, con el salto que la precede; con algo
  // delante, solo lo que se quita
  if Copy(AXml, Linea, AIni - Linea).Trim = '' then
  begin
    AIni := Linea;
    if (AIni > 1) and (AXml[AIni - 1] = #10) then
      Dec(AIni);
    if (AIni > 1) and (AXml[AIni - 1] = #13) then
      Dec(AIni);
  end;
  AXml := Copy(AXml, 1, AIni - 1) + Copy(AXml, AFin, MaxInt);
end;

function AllTagAttr(const AXml, ATag, AAttr: string; AConOcultos: Boolean): TArray<string>;
begin
  // EL buscador de aperturas y EL lector de atributos, los de TramosDeEtiqueta:
  // sin distinguir mayusculas, con cualquier blanco, el valor entre comillas
  // dobles O simples (las dos son XML) y como lo da XML (ValorDeAtributo)
  Result := [];
  for var A in AperturasDe(TextoDeBusqueda(AXml, AConOcultos), ATag) do
    for var At in AtributosDeApertura(AXml, A.Abre, A.Cierra) do
      if SameText(At.Nombre, AAttr) then
        Result := Result + [ValorDeAtributo(AXml, At)];
end;

function MergeProperty(const AXml, APropName: string): string;
var
  V: string;
begin
  Result := '';
  for V in AllTagValues(AXml, APropName) do
    Result := V.Replace('$(' + APropName + ')', Result, [rfReplaceAll, rfIgnoreCase]);
end;

function XmlUnescape(const S: string): string;
var
  B: TStringBuilder;
  I, J: Integer;
  Ent, Numero, Valor: string;
  N: Int64;
begin
  // Una pasada: la entidad que produce '&' no vuelve a desescaparse.
  // XML tambien admite referencias numericas, decimales y hexadecimales.
  B := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(S) do
    begin
      Valor := '';
      J := 0;
      if S[I] = '&' then
      begin
        J := Pos(';', S, I + 1);
        if J > 0 then
        begin
          Ent := Copy(S, I + 1, J - I - 1);
          if Ent = 'amp' then Valor := '&'
          else if Ent = 'lt' then Valor := '<'
          else if Ent = 'gt' then Valor := '>'
          else if Ent = 'quot' then Valor := '"'
          else if Ent = 'apos' then Valor := ''''
          else if Ent.StartsWith('#') then
          begin
            Numero := Copy(Ent, 2, MaxInt);
            if Numero.StartsWith('x') then
              Numero := '$' + Copy(Numero, 2, MaxInt);
            if TryStrToInt64(Numero, N) and
               ((N = 9) or (N = 10) or (N = 13) or
                ((N >= $20) and (N <= $D7FF)) or
                ((N >= $E000) and (N <= $FFFD)) or
                ((N >= $10000) and (N <= $10FFFF))) then
            begin
              if N <= $FFFF then
                Valor := Char(N)
              else
                Valor := Char($D800 + ((N - $10000) shr 10)) +
                         Char($DC00 + ((N - $10000) and $3FF));
            end;
          end;
        end;
      end;
      if Valor <> '' then
      begin
        B.Append(Valor);
        I := J + 1;
      end
      else
      begin
        B.Append(S[I]);
        Inc(I);
      end;
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function TrozosEscritos(const AEscrito: string): TArray<string>;
var
  I, J, Ini: Integer;
begin
  Result := [];
  Ini := 1;
  I := 1;
  while I <= Length(AEscrito) do
  begin
    if AEscrito[I] = '&' then
    begin
      // una entidad (&amp; &#38; &#x26;) llega hasta su ';', que no separa
      J := I + 1;
      while (J <= Length(AEscrito)) and
            CharInSet(AEscrito[J], ['#', 'a'..'z', 'A'..'Z', '0'..'9']) do
        Inc(J);
      if (J > I + 1) and (J <= Length(AEscrito)) and (AEscrito[J] = ';') then
        I := J;
    end
    else if AEscrito[I] = ';' then
    begin
      Result := Result + [Copy(AEscrito, Ini, I - Ini)];
      Ini := I + 1;
    end;
    Inc(I);
  end;
  Result := Result + [Copy(AEscrito, Ini, MaxInt)];
end;

function XmlEscape(const S: string): string;
begin
  // & primero: si no, el de los &lt; que se acaban de poner se doblaria
  Result := S.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    .Replace('"', '&quot;');
end;

function XmlEscapeEn(const S: string; AComilla: Char): string;
begin
  Result := XmlEscape(S);
  if AComilla = '''' then
    Result := Result.Replace('''', '&apos;');
end;

function XmlAtributo(const ANombre, AValor: string): string;
begin
  Result := ANombre + '="' + XmlEscape(AValor) + '"';
end;

function XmlElemento(const ATag, AValor: string): string;
begin
  Result := '<' + ATag + '>' + XmlEscape(AValor) + '</' + ATag + '>';
end;

function FijaPropiedadParaTodos(var AXml: string; const ATag, AValor: string;
  out ACambios: TArray<TValorReescrito>): Boolean;
var
  Grupos: TArray<TGrupoXml>;
  Escrito, Nuevo: string;
  Base, Ult, Desplaza: Integer;
  EnBase: Boolean;
  C: TValorReescrito;
begin
  ACambios := [];
  Grupos := GruposDePropiedades(AXml);
  Base := -1;
  for var I := 0 to High(Grupos) do
    if CondicionNormalizada(Grupos[I].Condicion) = CondicionNormalizada(GroupCondition('')) then
    begin
      Base := I;
      Break;
    end;
  Escrito := XmlEscape(AValor);
  Nuevo := '';
  Ult := 1;
  Desplaza := 0; // lo que crece o encoge el texto por delante del grupo base
  EnBase := False;
  for var T in TramosDeEtiqueta(AXml, ATag) do
    for var I := 0 to High(Grupos) do
      // solo la de un PropertyGroup es una propiedad para MSBuild
      if (T.Ini >= Grupos[I].Ini) and (T.Fin <= Grupos[I].Fin) then
      begin
        C.Grupo := Grupos[I].Condicion;
        C.Antes := ValorDeTramo(AXml, T);
        C.EnBase := I = Base;
        EnBase := EnBase or C.EnBase;
        ACambios := ACambios + [C];
        if (Base >= 0) and (T.Fin <= Grupos[Base].Ini) then
          Inc(Desplaza, Length(Escrito) - (T.Fin - T.Ini));
        Nuevo := Nuevo + Copy(AXml, Ult, T.Ini - Ult) + Escrito;
        Ult := T.Fin;
        Break;
      end;
  Nuevo := Nuevo + Copy(AXml, Ult, MaxInt);
  if not EnBase then
  begin
    if Base < 0 then
      Exit(False);
    // al principio del grupo base, donde la ponia set-output; el salto lo
    // deja como el del fichero quien lo guarda (PatchSaveConSuSalto)
    var En := Grupos[Base].Ini + Desplaza;
    Nuevo := Copy(Nuevo, 1, En - 1) + sLineBreak + '        ' +
      XmlElemento(ATag, AValor) + Copy(Nuevo, En, MaxInt);
  end;
  AXml := Nuevo;
  Result := True;
end;

{ TDprojInfo }

function TDprojInfo.HasConfig(const AName: string): Boolean;
var
  C: string;
begin
  for C in Configs do
    if SameText(C, AName) then
      Exit(True);
  Result := False;
end;

function TDprojInfo.HasPlatform(const AName: string): Boolean;
var
  P: TDprojPlatform;
begin
  for P in Platforms do
    if SameText(P.Name, AName) then
      Exit(True);
  Result := False;
end;

function TDprojInfo.PlataformaPorDefecto: string;
begin
  Result := CanonicalPlatform(DefaultPlatform);
  if Result = '' then
    Result := 'Win32';
end;

function TDprojInfo.ConfigPorDefecto: string;
begin
  Result := DefaultConfig.Trim;
  if Result = '' then
    Exit('Debug');
  // con SU nombre, el que declara el proyecto (msbuild no distingue)
  for var C in Configs do
    if SameText(C, Result) then
      Exit(C);
end;

function TDprojInfo.Declara(const APlatform: string): Boolean;
var
  P: TDprojPlatform;
begin
  if Length(Platforms) = 0 then
    Exit(SameText(APlatform, PlataformaPorDefecto));
  for P in Platforms do
    if SameText(P.Name, APlatform) then
      Exit(P.Enabled);
  Result := False;
end;

function DprojDe(const AProject: string): string;
begin
  Result := AProject;
  if MatchText(TPath.GetExtension(Result), ['.dpr', '.dpk']) then
    Result := TPath.ChangeExtension(Result, '.dproj');
end;

function DprDe(const AProject: string): string;
begin
  Result := AProject;
  if SameText(TPath.GetExtension(Result), '.dproj') then
  begin
    Result := TPath.ChangeExtension(AProject, '.dpr');
    var Dpk := TPath.ChangeExtension(AProject, '.dpk');
    if not TFile.Exists(Result) and TFile.Exists(Dpk) then
      Result := Dpk;
  end;
end;

function PlataformaNoDeclarada(const AInfo: TDprojInfo; const APlatform: string): string;
var
  P: TDprojPlatform;
  Activas: TArray<string>;
begin
  Result := '';
  if AInfo.Declara(APlatform) then
    Exit;
  Activas := nil;
  if Length(AInfo.Platforms) = 0 then
    Activas := [AInfo.PlataformaPorDefecto]
  else
    for P in AInfo.Platforms do
      if P.Enabled then
        Activas := Activas + [P.Name];
  Result := MsgFmt(SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT,
    [APlatform, ONinguno(string.Join(', ', Activas)), APlatform]);
end;

function TDprojInfo.CanTarget(const APlatform: string; out AReason: string): Boolean;
begin
  AReason := '';
  // VCL is Windows-only: Vcl.Forms does not exist on Linux/macOS/mobile.
  if SameText(FrameworkType, 'VCL') and not IsLocalPlatform(APlatform) then
  begin
    AReason := MsgFmt(SF_CFG_VCL_SOLO_WINDOWS_FMT, [APlatform]);
    Exit(False);
  end;
  Result := True;
end;

function PaclientPlatformsList: string;
begin
  Result := string.Join(', ', PACLIENT_PLATFORMS);
end;

function NombreDeConfigNoValido(const AConfig: string): Boolean;
var
  C: Char;
begin
  for C in AConfig do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) then
      Exit(True);
  Result := False;
end;

function ConfigDesconocida(const ADproj, AConfig: string;
  ADeLaSeleccion: Boolean): string;
var
  Info: TDprojInfo;
begin
  // el nombre antes que la lista: con la lista vacia se aceptaba todo, y un
  // nombre que el proyecto declara no es por eso un nombre limpio
  if NombreDeConfigNoValido(AConfig) then
    Exit(MsgFmt(SR_BUILD_CONFIG_FMT, [AConfig]));
  Result := '';
  Info := ReadDproj(ADproj);
  // Base no es una configuracion que se compile: es de la que heredan las
  // demas, y el IDE no la deja activar (lo que se compila aqui se compila
  // igual en el IDE); compilaba con los ajustes de la base en Win64\Base\. La
  // lista, sin ella, como la de set-active
  var Validas: TArray<string> := nil;
  for var C in Info.Configs do
    if not SameText(C, 'Base') then
      Validas := Validas + [C];
  if SameText(AConfig.Trim, 'Base') then
    Exit(MsgFmt(SR_CFG_BASE_NO_SE_COMPILA_FMT, [string.Join(', ', Validas)]));
  if (Length(Info.Configs) > 0) and not Info.HasConfig(AConfig) then
    if ADeLaSeleccion then
      Result := MsgFmt(SR_CFG_SELECCIONADA_NO_DECLARADA_FMT, [AConfig, string.Join(', ', Validas)])
    else
      Result := MsgFmt(SR_TEST_CONFIG_FMT, [AConfig, string.Join(', ', Validas)]);
end;

function BloqueDePlataformas(const AXml: string; out ABloque: TTramoXml): Boolean;
var
  B: TArray<TTramoXml>;
begin
  B := TramosDeEtiqueta(AXml, 'Platforms');
  Result := Length(B) > 0;
  if Result then
    ABloque := B[0];
end;

function PlataformasDelBloque(const AXml: string): TArray<TPlataformaDelBloque>;
var
  P: TPlataformaDelBloque;
begin
  Result := [];
  for var B in TramosDeEtiqueta(AXml, 'Platforms') do
    for var T in TramosDentro(AXml, 'Platform', B) do
    begin
      P.Nombre := AtributoDeTramo(AXml, T, 'Platform', 'value').Trim;
      if P.Nombre = '' then
        Continue;
      P.Activa := SameText(ValorDeTramo(AXml, T).Trim, 'True');
      P.Tramo := T;
      Result := Result + [P];
    end;
end;

function ClavesDeVersion(const AXml: string): TArray<TClaveDeVersion>;
var
  C: TClaveDeVersion;
  Base, Igual: Integer;
begin
  Result := [];
  for var T in TramosDeEtiqueta(AXml, 'VerInfo_Keys') do
  begin
    // por trozos ESCRITOS (el ';' de un &amp; no separa), con su posicion
    // para reescribir un valor en su sitio; uno con un CDATA o un comentario
    // dentro no se sabe reescribir y no se toca
    var Escrito := Copy(AXml, T.Ini, T.Fin - T.Ini);
    if Escrito.Contains('<') then
      Continue;
    Base := T.Ini;
    for var Trozo in TrozosEscritos(Escrito) do
    begin
      Igual := Pos('=', Trozo);
      if Igual > 0 then
      begin
        C.Nombre := Copy(Trozo, 1, Igual - 1).Trim;
        C.Ini := Base + Igual;
        C.Fin := Base + Length(Trozo);
        Result := Result + [C];
      end;
      Inc(Base, Length(Trozo) + 1);
    end;
  end;
end;

function XmlPlataformaDelBloque(const APlatform: string; AActiva: Boolean): string;
begin
  Result := '<Platform ' + XmlAtributo('value', APlatform) + '>' +
    IfThen(AActiva, 'True', 'False') + '</Platform>';
end;

function SelectorDe(const AXml, ATag: string; out ATramo: TTramoXml): Boolean;
begin
  // el selector no lleva value: <Platform value="Win64">True</Platform> es
  // una entrada del bloque <Platforms>, no el que elige
  for var T in TramosDeEtiqueta(AXml, ATag) do
    if (AtributoDeTramo(AXml, T, ATag, 'Condition') <> '') and
       (AtributoDeTramo(AXml, T, ATag, 'value') = '') then
    begin
      ATramo := T;
      Exit(True);
    end;
  Result := False;
end;

function XmlSelector(const ATag, AValor: string): string;
begin
  Result := '<' + ATag + ' ' + XmlAtributo('Condition', '''$(' + ATag + ')''==''''') + '>' +
    XmlEscape(AValor) + '</' + ATag + '>';
end;

function ReadDproj(const ADprojPath: string): TDprojInfo;
var
  Xml: string;
begin
  Result := Default(TDprojInfo);
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  try
    Xml := LeeTexto(ADprojPath, [ltJaula]);
  except
    Exit;
  end;
  Result := InfoDeDproj(Xml);
end;

function InfoDeDproj(const AXml: string): TDprojInfo;
var
  D: TDprojPlatform;
  T: TTramoXml;
begin
  Result := Default(TDprojInfo);
  var Fw := AllTagValues(AXml, 'FrameworkType');
  if Length(Fw) > 0 then
    Result.FrameworkType := Fw[0].Trim;
  var At := AllTagValues(AXml, 'AppType');
  if Length(At) > 0 then
    Result.AppType := At[0].Trim;
  // Build configurations: <BuildConfiguration Include="Debug">
  Result.Configs := AllTagAttr(AXml, 'BuildConfiguration', 'Include');
  // las plataformas, por EL lector del bloque
  Result.Platforms := [];
  for var P in PlataformasDelBloque(AXml) do
  begin
    D.Name := P.Nombre;
    D.Enabled := P.Activa;
    Result.Platforms := Result.Platforms + [D];
  end;
  // la plataforma y la configuracion por defecto: los selectores, los que
  // compilan el IDE y msbuild si nadie pide otra
  if SelectorDe(AXml, 'Platform', T) then
    Result.DefaultPlatform := ValorDeTramo(AXml, T).Trim;
  if SelectorDe(AXml, 'Config', T) then
    Result.DefaultConfig := ValorDeTramo(AXml, T).Trim;
end;

function IsLocalPlatform(const APlatform: string): Boolean;
begin
  Result := MatchText(APlatform,
    ['Win32', 'Win64', 'Win64x', 'WinARM64EC']);
end;

const
  KNOWN_PLATFORMS: array [0 .. 12] of string = (
    'Win32', 'Win64', 'Win64x', 'WinARM64EC',
    'OSX64', 'OSXARM64', 'Linux64',
    'Android', 'Android64',
    'iOSDevice32', 'iOSDevice64', 'iOSSimARM64', 'iOSSimulator');

  // MSBuild tasks whose presence turns a build into arbitrary execution or an
  // out-of-tree file write. A <Target> that uses NONE of these (only Message,
  // PropertyGroup, ItemGroup, CallTarget...) is inert and allowed to build; one
  // that uses ANY of these needs AllowBuildScripts en su workspace. Local names,
  // lowercase; HasElement matches them with or without a namespace prefix.
  //   exec/usingtask/code  -> run a shell / load a task assembly / inline code
  //   copy..touch          -> plant, move or delete files by arbitrary path
  //   write*/downloadfile   -> write a file (a payload, a .targets for later)
  //   unzip/zipdirectory    -> materialise files from an archive
  //   csc/vbc/fsc/xslt/genres-> invoke a compiler / transform = run a program
  DANGER_TASKS: array [0 .. 20] of string = (
    'exec', 'usingtask', 'code', 'msbuild',
    'copy', 'move', 'delete', 'makedir', 'removedir', 'touch',
    'writelinestofile', 'writecodefragment', 'downloadfile',
    'readlinesfromfile', // Lectura de una ruta arbitraria durante el build.
    'unzip', 'zipdirectory',
    'csc', 'vbc', 'fsc', 'xslttransformation', 'generateresource');

function ValidOutputFolder(const AFolder: string; out AClean: string): Boolean;
var
  C: Char;
  Seg: string;
begin
  Result := False;
  AClean := AFolder.Trim.Trim(['"']).Trim;
  AClean := AClean.Replace('/', '\');
  while AClean.StartsWith('\') do AClean := AClean.Substring(1);
  while AClean.EndsWith('\') do AClean := AClean.Substring(0, AClean.Length - 1);
  if AClean = '' then Exit;
  if AClean.Contains('..') or AClean.Contains(':') then Exit; // no escape, no drive
  for C in AClean do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ', '\']) then
      Exit;
  for Seg in AClean.Split(['\']) do
    if Seg.Trim = '' then Exit; // no empty segments (\\ , trailing, etc.)
  Result := True;
end;

function KnownPlatformsList: string;
begin
  Result := string.Join(', ', KNOWN_PLATFORMS);
end;

function CanonicalPlatform(const AName: string): string;
var
  P: string;
begin
  Result := '';
  for P in KNOWN_PLATFORMS do
    if SameText(P, AName.Trim) then
      Exit(P); // canonical casing, and proven metachar-free
end;

function PlataformaDeClaveLibrary(const AClave: string): string;
begin
  if SameText(AClave.Trim, 'Android32') then
    Exit(CanonicalPlatform('Android'));
  Result := CanonicalPlatform(AClave);
end;

function GroupCondition(const APlatform: string; const AClave: string): string;
begin
  if APlatform = '' then
    Result := '''$(' + AClave + ')''!='''''
  else
    Result := '''$(' + AClave + '_' + APlatform + ')''!=''''';
end;

function DefinerCondition(const APlatform: string; const AClave: string): string;
begin
  Result := '(''$(Platform)''==''' + APlatform + ''' and ''$(' + AClave + ')''==''true'') or ' +
    GroupCondition(APlatform, AClave);
end;

function ConfigDefinerCondition(const AConfig, AClave: string): string;
begin
  // las dos mitades, por sus nombradores (se componian aqui a mano)
  Result := ConfigCondition(AConfig) + ' or ' + GroupCondition('', AClave);
end;

function XmlGrupoDefinidor(const APlatform, AClave: string): string;
begin
  Result := '    <PropertyGroup ' + XmlAtributo('Condition', DefinerCondition(APlatform, AClave)) + '>' + sLineBreak +
    '        ' + XmlElemento(AClave + '_' + APlatform, 'true') + sLineBreak +
    '        ' + XmlElemento('CfgParent', AClave) + sLineBreak;
  if not SameText(AClave, 'Base') then
    Result := Result + '        ' + XmlElemento(AClave, 'true') + sLineBreak;
  Result := Result + '        <Base>true</Base>' + sLineBreak + '    </PropertyGroup>';
end;

function XmlGrupoDeValores(const APlatform, AClave, AProps: string): string;
begin
  Result := '    <PropertyGroup ' + XmlAtributo('Condition', GroupCondition(APlatform, AClave)) + '>' +
    sLineBreak + AProps + '    </PropertyGroup>';
end;

{ Lo que va entre AAntes (sin distinguir mayusculas) y ACierre en ACondicion,
  tal cual esta escrito; '' si no esta. }
function TrozoDeCondicion(const ACondicion, AAntes, ACierre: string): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos(LowerCase(AAntes), LowerCase(ACondicion));
  if P = 0 then
    Exit;
  Inc(P, Length(AAntes));
  Q := Pos(ACierre, ACondicion, P);
  if Q > 0 then
    Result := Copy(ACondicion, P, Q - P);
end;

{ El valor entre comillas que sigue a AClave ('$(Platform)', '$(Config)') en
  ACondicion - '$(Platform)' == 'X' -, tal cual esta escrito; '' si no esta. }
function ValorDeCondicion(const ACondicion, AClave: string): string;
var
  P: Integer;
begin
  P := Pos(LowerCase(AClave), LowerCase(ACondicion));
  if P = 0 then
    Exit('');
  // lo de detras de la clave, y en ello lo de dentro de las comillas siguientes
  Result := TrozoDeCondicion(Copy(ACondicion, P + Length(AClave), MaxInt), '''', '''');
end;

{ La plataforma leida de una Condition con la grafia de las conocidas, y la
  que no lo es tal cual esta escrita: un .deployproj del IDE lleva grupos de
  OSX32, que ya no esta entre ellas, y la vista los dejaba de ensenar }
function ConSuGrafia(const APlataforma: string): string;
begin
  Result := CanonicalPlatform(APlataforma);
  if Result = '' then
    Result := APlataforma;
end;

function PlataformaDeGrupo(const ACondicion: string; ADefinidor: Boolean): string;
var
  X, N: string;
begin
  // la inversa del nombrador: la plataforma que la Condition nombra, si con
  // ella el nombrador vuelve a escribir ESA Condition (elegir entre las
  // conocidas dejaba fuera las de proyectos de otra version)
  Result := '';
  X := TrozoDeCondicion(ACondicion, '$(Base_', ')').Trim;
  if X = '' then
    Exit;
  N := CondicionNormalizada(ACondicion);
  if (not ADefinidor and (N = CondicionNormalizada(GroupCondition(X)))) or
     (ADefinidor and (N = CondicionNormalizada(DefinerCondition(X)))) then
    Result := ConSuGrafia(X);
end;

function DeployGroupCondition(const APlatform: string; const AConfig: string): string;
begin
  Result := '''$(Platform)''==''' + APlatform + '''';
  if AConfig <> '' then
    Result := Result + ' And ' + ConfigCondition(AConfig);
end;

function ConfigCondition(const AConfig: string): string;
begin
  Result := '''$(Config)''==''' + AConfig + '''';
end;

function XmlDeployFile(const AInclude, AConfig, ARemoteDir, ARemoteName, AClase: string;
  AOperacion: Integer; ARequerido: Boolean): string;
begin
  Result := '        <DeployFile ' + XmlAtributo('Include', AInclude);
  if AConfig <> '' then
    Result := Result + ' ' + XmlAtributo('Condition', ConfigCondition(AConfig));
  Result := Result + '>' + sLineBreak +
    '            ' + XmlElemento('RemoteDir', ARemoteDir) + sLineBreak +
    '            ' + XmlElemento('RemoteName', ARemoteName) + sLineBreak +
    '            ' + XmlElemento('DeployClass', AClase) + sLineBreak +
    '            ' + XmlElemento('Operation', AOperacion.ToString) + sLineBreak +
    '            <LocalCommand/>' + sLineBreak +
    '            <RemoteCommand/>' + sLineBreak +
    '            ' + XmlElemento('Overwrite', 'True') + sLineBreak;
  if ARequerido then
    Result := Result + '            ' + XmlElemento('Required', 'True') + sLineBreak;
  Result := Result + '        </DeployFile>' + sLineBreak;
end;

function RutasDeExists(const AEscrita: string): TArray<TTrozoEscrito>;
var
  Low: string;
  P, Q, R: Integer;
  T: TTrozoEscrito;
begin
  Result := [];
  Low := LowerCase(AEscrita);
  P := 1;
  while True do
  begin
    P := Pos('exists(', Low, P);
    if P = 0 then
      Break;
    Q := P + Length('exists(');
    while (Q <= Length(Low)) and CharInSet(Low[Q], [' ', #9]) do
      Inc(Q);
    if (Q <= Length(Low)) and (Low[Q] = '''') then
    begin
      R := Pos('''', Low, Q + 1);
      if R > 0 then
      begin
        T.Ini := Q + 1;
        T.Fin := R;
        Result := Result + [T];
        P := R + 1;
        Continue;
      end;
    end;
    P := Q;
  end;
end;

function CondicionDePlataformaYConfig(const ACondicion: string; out APlataforma, AConfig: string): Boolean;
var
  N: string;
begin
  // la inversa del nombrador, como PlataformaDeGrupo: los valores que la
  // Condition da a '$(Platform)' y a '$(Config)', y que con ellos se vuelva a
  // escribir ESA Condition en una de sus formas. Era un ContainsText del texto
  // de la etiqueta en tres sitios, y una regex en la vista
  APlataforma := ValorDeCondicion(ACondicion, '''$(Platform)''').Trim;
  AConfig := ValorDeCondicion(ACondicion, '''$(Config)''').Trim;
  N := CondicionNormalizada(ACondicion);
  if (APlataforma <> '') and (AConfig <> '') then
    Result := (N = CondicionNormalizada(DeployGroupCondition(APlataforma, AConfig))) or
      (N = CondicionNormalizada(ConfigCondition(AConfig) + ' And ' + DeployGroupCondition(APlataforma)))
  else if APlataforma <> '' then
    Result := N = CondicionNormalizada(DeployGroupCondition(APlataforma))
  else if AConfig <> '' then
    Result := N = CondicionNormalizada(ConfigCondition(AConfig))
  else
    Result := False;
  if not Result then
  begin
    APlataforma := '';
    AConfig := '';
  end;
end;

function PlataformaDeGrupoDeDespliegue(const ACondicion: string): string;
var
  X, C: string;
begin
  Result := '';
  if CondicionDePlataformaYConfig(ACondicion, X, C) and (X <> '') then
    Result := ConSuGrafia(X);
end;

{ Si una Condition (de un grupo o de un elemento) se aplica a un build de
  APlatform / AConfig: sin condicion, si; de plataforma y/o config, si nombra
  esas (una config sin AConfig: no se sabe, no); otra cosa, no - lo que no se
  sabe si se aplica no se da por aplicado. }
function SeAplicaA(const ACondicion, APlatform, AConfig: string): Boolean;
var
  X, C: string;
begin
  if ACondicion.Trim = '' then
    Exit(True);
  if not CondicionDePlataformaYConfig(ACondicion, X, C) then
    Exit(False);
  Result := ((X = '') or SameText(X, APlatform)) and
    ((C = '') or ((AConfig <> '') and SameText(C, AConfig)));
end;

function TagValue(const AXml, ATag: string): string;
var
  V: TArray<string>;
begin
  // el primero, por el lector de la casa: sin distinguir mayusculas y con
  // atributos, como todos (distinguia, y un lector de regex con (?i) que
  // paso a llamarlo dejo de leer lo que leia)
  V := AllTagValues(AXml, ATag);
  if Length(V) > 0 then
    Result := V[0].Trim
  else
    Result := '';
end;

function RutasDeBusqueda(const ADprojPath, AXml: string): TArray<TRutaDeBusqueda>;
var
  R: TRutaDeBusqueda;
begin
  Result := [];
  for var V in AllTagValues(AXml, 'DCC_UnitSearchPath') do
    for var Seg in V.Split([';']) do
    begin
      R.Escrita := Seg.Trim;
      if (R.Escrita = '') or R.Escrita.Contains('$(') then
        Continue;
      try
        R.Carpeta := R.Escrita;
        if not TPath.IsPathRooted(R.Carpeta) then
          R.Carpeta := TPath.Combine(TPath.GetDirectoryName(ADprojPath), R.Carpeta);
        R.Carpeta := TPath.GetFullPath(R.Carpeta);
      except
        R.Carpeta := '';
      end;
      Result := Result + [R];
    end;
end;

function BuscaEnCarpeta(const ADprojPath, AXml, ADir: string): Boolean;
var
  Target: string;
begin
  // la comparacion de ProjectsSearching (Lsp.References), sacada aqui para
  // que la haga tambien quien busca el proyecto de una unidad
  Result := False;
  if ADir = '' then
    Exit;
  Target := IncludeTrailingPathDelimiter(TPath.GetFullPath(ADir)).ToLower;
  for var R in RutasDeBusqueda(ADprojPath, AXml) do
    if (R.Carpeta <> '') and (IncludeTrailingPathDelimiter(R.Carpeta).ToLower = Target) then
      Exit(True);
end;

{ True when the XML contains an element whose LOCAL name is AName, with or
  without a namespace prefix (<Target>, <msb:Target>, <Target ...>). ALow must
  already be lowercase. A prefix is [A-Za-z0-9_.-]* before a ':'. }
function HasElement(const ALow, AName: string): Boolean;
var
  P, After: Integer;
begin
  Result := False;
  P := 1;
  while True do
  begin
    P := Pos(AName, ALow, P);
    if P = 0 then
      Exit;
    After := P + Length(AName);
    // Opened by '<' directly, or by a namespace prefix ("<msb:target"), and
    // closed by whitespace, '>' or '/' - so "targets" or "myTarget" do not match.
    if (P > 1) and CharInSet(ALow[P - 1], ['<', ':']) and
       ((After > Length(ALow)) or
        CharInSet(ALow[After], [' ', '>', #9, #13, #10, '/'])) then
      Exit(True);
    Inc(P);
  end;
end;

{ Expands the few MSBuild macros that point INSIDE the project, so an import
  written with them can be resolved and read. Returns '' when the path still
  carries a macro we cannot resolve (which the caller then refuses). }
function ResolveImportPath(const APath, AProjectFile: string): string;
var
  Dir, Name: string;
begin
  Dir := ExtractFileDir(AProjectFile);
  Name := TPath.GetFileNameWithoutExtension(AProjectFile);
  Result := APath;
  Result := Result.Replace('$(MSBuildProjectDirectory)', Dir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildThisFileDirectory)',
    IncludeTrailingPathDelimiter(Dir), [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectName)', Name, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(ProjectDir)', Dir, [rfReplaceAll, rfIgnoreCase]);
  if Result.Contains('$(') then
    Exit(''); // still macro-based: not resolvable here
  if not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(Dir, Result);
  try
    Result := TPath.GetFullPath(Result);
  except
    Result := '';
  end;
end;

{ The IDE's OWN imports, trusted without reading them: they live in the RAD
  Studio installation or the user's IDE profile, not in the project. }
function IsStockImport(const APathLow: string): Boolean;
begin
  // A traversal disqualifies it outright: "$(BDS)\..\..\evil.targets" is
  // macro-based AND ends in .targets, and a looser rule trusted it (caught by
  // our own evasion test while fixing field round 8).
  if APathLow.Contains('..') then
    Exit(False);
  // Solo rutas del IDE: el nombre de un fichero del proyecto no da confianza.
  Result := (APathLow.StartsWith('$(bds)\bin\codegear.') and
             (Pos('$(', APathLow, 2) = 0) and APathLow.EndsWith('.targets')) or
    (APathLow = '$(appdata)\embarcadero\$(bdsappdatabasedir)\$(productversion)\usertools.proj');
end;

{ Las macros comunes de una carpeta de salida, para una plataforma/config.
  Lo que conserva '$(' no se sabe resolver aqui. UNA copia: la usan
  ResolveBuildOutput (buscar el binario) y BuildOutputDirs (la puerta). }
function ExpandOutputMacros(const AValue, ADir, ABase, APlatform,
  AConfig: string): string;
begin
  Result := AValue;
  Result := Result.Replace('$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(Config)', AConfig, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectDirectory)', ADir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(ProjectDir)', ADir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectName)', ABase, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(SanitizedProjectName)', ABase, [rfReplaceAll, rfIgnoreCase]);
end;

{ El texto del .dproj y el de cada fichero DEL PROYECTO que importa (un
  .optset), recursivo hasta 4 niveles: lo que un build lee de este proyecto.
  Los del IDE no se leen (IsStockImport); lo que no se resuelve se salta
  aqui y lo rechaza DprojBuildHazard. UN lector para las dos preguntas sobre
  la salida (BuildOutputDirs, BuildOutputUndeclared). }
function ProjectXmlChain(const ADprojPath: string): TArray<string>;
var
  List: TList<string>;

  procedure Lee(const AFile: string; ADepth: Integer);
  var
    Xml, V, Resolved: string;
  begin
    try
      // un Import fuera de las raices no se lee: DprojBuildHazard lo rechaza
      Xml := LeeTexto(AFile, [ltJaula]);
    except
      Exit;
    end;
    List.Add(Xml);
    if ADepth >= 4 then
      Exit;
    for V in AllTagAttr(Xml, 'Import', 'Project') do
    begin
      if IsStockImport(LowerCase(V.Trim)) then
        Continue;
      Resolved := ResolveImportPath(V.Trim, AFile);
      if (Resolved <> '') and TFile.Exists(Resolved) then
        Lee(Resolved, ADepth + 1);
    end;
  end;

begin
  Result := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  List := TList<string>.Create;
  try
    Lee(TPath.GetFullPath(ADprojPath), 0);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function BuildOutputDirs(const ADprojPath, APlatform, AConfig: string): TArray<TBuildOutputDir>;
var
  List: TList<TBuildOutputDir>;
  Dir, Base, Xml, V, Cand: string;
  Item: TBuildOutputDir;
begin
  Result := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  List := TList<TBuildOutputDir>.Create;
  try
    // Un valor relativo se resuelve contra la carpeta del PROYECTO aunque
    // venga de un .optset: dcc trabaja alli.
    for Xml in ProjectXmlChain(ADprojPath) do
      for var Tag in BUILD_OUTPUT_TAGS do
        for var T in TramosDeEtiqueta(Xml, Tag) do
        begin
          V := ValorDeTramo(Xml, T);
          var Escrito := Copy(Xml, T.Ini, T.Fin - T.Ini);
          Item.Tag := Tag;
          Item.Value := V.Trim;
          Item.Dir := '';
          Cand := ExpandOutputMacros(Item.Value, Dir, Base,
            APlatform, AConfig).Trim;
          if Cand = '' then
            Continue; // vacia: la del IDE por defecto (BuildOutputUndeclared)
          // Una macro sin resolver, un escape de MSBuild (%3A), una entidad
          // numerica (&#58;) o un CDATA: msbuild lo leeria distinto que
          // nosotros, y lo que no se puede comprobar no se aprueba. El lector
          // lee ya el CDATA como XML (17-oct-2026), y aqui se sigue sin aprobar
          // lo que no esta escrito tal cual: la segunda barrera se queda.
          if not (Cand.Contains('$(') or Cand.Contains('@(') or
                  Cand.Contains('%') or Item.Value.Contains('&#') or
                  Cand.Contains('<') or Escrito.Contains('<')) then
          begin
            if not TPath.IsPathRooted(Cand) then
              Cand := TPath.Combine(Dir, Cand);
            try
              Item.Dir := TPath.GetFullPath(Cand);
            except
              Item.Dir := '';
            end;
          end;
          List.Add(Item);
        end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function BuildResourceFiles(const ADprojPath: string): TArray<string>;
var
  Dir, Base: string;
begin
  Result := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  Result := [TPath.Combine(Dir, Base + '.res'), TPath.Combine(Dir, Base + '.vrc')];
  for var Xml in ProjectXmlChain(ADprojPath) do
    for var R in AllTagAttr(Xml, 'RcCompile', 'Include') do
      if R.Trim <> '' then
        Result := Result + [TPath.Combine(Dir, TPath.GetFileNameWithoutExtension(R.Trim) + '.res')];
end;

{ La clave (Cfg_N) con la que el .dproj nombra una configuracion:
  <BuildConfiguration Include="Debug"><Key>Cfg_2</Key>. No se supone: en
  lo que escribe delphi_create, Cfg_1 es Release. '' si no esta. }
function ConfigKey(const AXml, AConfig: string): string;
begin
  // por EL analisis: era un recorredor gemelo de '<buildconfiguration'
  Result := '';
  for var T in TramosDeEtiqueta(AXml, 'BuildConfiguration') do
    if SameText(AtributoDeTramo(AXml, T, 'BuildConfiguration', 'Include').Trim, AConfig) then
      for var K in TramosDentro(AXml, 'Key', T) do
        Exit(ValorDeTramo(AXml, K).Trim);
end;

{ El valor EFECTIVO de ATag para un build APlatform/AConfig: los grupos del
  .dproj con las condiciones que escribe el IDE - ninguna, '$(Base)' (la
  global: todas las configs y plataformas), '$(Base_<plataforma>)',
  '$(Cfg_N)' y '$(Cfg_N_<plataforma>)' -, en orden de documento, y el
  ultimo que lo fija gana, como en MSBuild: sin definicion particular se
  hereda la global, y una particular vacia la anula. Cada plataforma y
  config puede tener su carpeta (David, 25-sep-2026). Un grupo con otra
  condicion NO cuenta: lo que no se sabe si se aplica no se da por
  declarado. Y un $(ATag) dentro del valor es lo que valia hasta ahi, como
  en MSBuild: el IDE escribe asi los defines de cada configuracion, y sin
  expandirlo el de Debug era el texto "DEBUG;$(DCC_Define)" (1.20.2). }
function EffectiveProperty(const AXml, ATag, APlatform, AConfig: string): string;
var
  Key: string;
  Validas: TArray<string>;
  Suyas: TArray<TTramoXml>;
begin
  Result := '';
  // las etiquetas ATag del documento UNA vez, repartidas luego por grupos: con
  // TramosEnGrupo era un recorrido del documento entero por cada grupo, 7 ms
  // en un .dproj de 117 KB por propiedad, y los ajustes del motor piden
  // cuatro en cada peticion (medido el 18-oct-2026, FabProbe). Las mismas, en
  // el mismo orden: las de dentro de cada grupo, por su posicion
  Suyas := TramosDeEtiqueta(AXml, ATag, True);
  Key := ConfigKey(AXml, AConfig);
  Validas := ['', CondicionNormalizada(GroupCondition('')),
    CondicionNormalizada(GroupCondition(APlatform))];
  // las de la configuracion, por EL nombrador (se componian aqui a mano)
  if Key <> '' then
    Validas := Validas + [CondicionNormalizada(GroupCondition('', Key)),
      CondicionNormalizada(GroupCondition(APlatform, Key))];
  for var G in GruposDePropiedades(AXml) do
    // el grupo: los que escribe el IDE (la base, la plataforma, la config) o
    // uno de plataforma y/o config que se aplique a este build
    if MatchStr(CondicionNormalizada(G.Condicion), Validas) or
       ((G.Condicion.Trim <> '') and SeAplicaA(G.Condicion, APlatform, AConfig)) then
      // cada etiqueta con SU Condition, y la vacia (<X/>) tambien: deja el
      // valor vacio, como en msbuild. El juez (MSXML, 17-oct-2026) las veia y
      // el escaner no: un <Profile Condition="'$(Platform)'=='Win32'"> de 5
      // Samples del IDE se contaba para OSX64 e iOS
      for var T in Suyas do
        if (T.Abre >= G.Ini) and (T.Cierra <= G.Fin) and
           SeAplicaA(AtributoDeTramo(AXml, T, ATag, 'Condition'), APlatform, AConfig) then
          Result := ValorDeTramo(AXml, T).Trim.Replace('$(' + ATag + ')', Result,
            [rfReplaceAll, rfIgnoreCase]); // el ultimo gana, con lo de antes dentro
end;

function PlatformProperty(const AXml, APlatform, ATag: string): string;
begin
  // EL juez de una propiedad por grupos, sin config: tenia su propio recorrido
  // ("el ultimo <propertygroup abierto antes de la etiqueta", el primero que
  // la fija, un grupo de config contando como base y la etiqueta solo sin
  // atributos), y msbuild da la ultima (D4, 1.20.1)
  Result := EffectiveProperty(AXml, ATag, APlatform, '');
end;

function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): string;
var
  Chain: TArray<string>;

  // Declarada PARA ESTE BUILD en el .dproj: la global o la particular que
  // se aplica. Un .optset no cuenta aqui: se importa con su condicion y no
  // se sabe si se aplica.
  function Declara(const ATag: string): Boolean;
  begin
    Result := EffectiveProperty(Chain[0], ATag, APlatform, AConfig) <> '';
  end;

var
  Xml, V: string;
  Paquete, Cpp: Boolean;
begin
  Result := '';
  Chain := ProjectXmlChain(ADprojPath);
  if Chain = nil then
    Exit;
  // Paquete o salida C++ con que UN sitio lo diga: se exige su carpeta
  // (una de mas es prudencia).
  Paquete := False;
  Cpp := False;
  for Xml in Chain do
  begin
    for V in AllTagValues(Xml, 'AppType') do
      if SameText(V.Trim, 'Package') then
        Paquete := True;
    for V in AllTagValues(Xml, 'DCC_CBuilderOutput') do
      if (V.Trim <> '') and not SameText(V.Trim, 'None') then
        Cpp := True;
  end;
  if not Declara('DCC_DcuOutput') then
    Exit('DCC_DcuOutput');
  if Paquete and not Declara('DCC_BplOutput') then
    Exit('DCC_BplOutput');
  if (Paquete or Cpp) and not Declara('DCC_DcpOutput') then
    Exit('DCC_DcpOutput');
  if Cpp and not Declara('DCC_HppOutput') then
    Exit('DCC_HppOutput');
end;

function UsaPaquetesEnEjecucion(const ADprojPath, APlatform, AConfig: string): Boolean;
var
  Xml: string;
begin
  Result := False;
  for Xml in ProjectXmlChain(ADprojPath) do
    if SameText(EffectiveProperty(Xml, 'UsePackages', APlatform, AConfig), 'true') then
      Exit(True);
end;

const
  // Las propiedades de ENTORNO con las que los <Import> propios del IDE
  // localizan lo que cargan: los cuatro punteros a fichero de
  // CodeGear.Common.Targets (<Import Project="$(EnvironmentSettings)"> y sus
  // hermanos EnvOptions/Profiles/GlobalOptionFile), y la raiz
  // $(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(ProductVersion) con la que
  // CodeGear.Profiles.Targets importa el .sdk y todo .dproj importa
  // UserTools.proj. Un proyecto NUNCA las define: las pone el entorno del IDE.
  // PlatformSDK queda fuera aposta - esa SI la fija el proyecto (delphi_config
  // set-sdk) y vive en proyectos reales; rechazarla romperia builds legitimos.
  // Y BDS: la raiz de los propios imports del IDE ($(BDS)\Bin\CodeGear.*.Targets),
  // que IsStockImport reconoce por el texto (medido el 25-sep-2026).
  RESERVED_IDE_IMPORT_PROPS: array [0 .. 7] of string = (
    'EnvironmentSettings', 'EnvOptions', 'Profiles', 'GlobalOptionFile',
    'APPDATA', 'BDSAPPDATABASEDIR', 'ProductVersion', 'BDS');

function RedefinedIdeImportProperty(const ADprojPath: string): string;
var
  Xml, Prop: string;
begin
  Result := '';
  // El .dproj y lo que importa del proyecto (ProjectXmlChain, el mismo lector
  // que BuildOutputUndeclared). Una definicion <Prop>...</Prop> en cualquier
  // fichero de la cadena cuenta, sin evaluar su condicion (una de mas es
  // prudencia); una referencia $(Prop) no es una definicion y AllTagValues no
  // la ve, asi que el $(APPDATA)\...\UserTools.proj de todo .dproj no cuenta.
  for Xml in ProjectXmlChain(ADprojPath) do
    for Prop in RESERVED_IDE_IMPORT_PROPS do
      if Length(AllTagValues(Xml, Prop)) > 0 then
        Exit(Prop);
end;

function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;
var
  Xml, Dir, Base, D, Cand, Ext, Artifact: string;
  ArtifactExts: TArray<string>;
  Dirs: TList<string>;
  Best: string;
  BestTime, T: TDateTime;

  function Expand(const AValue: string): string;
  begin
    Result := ExpandOutputMacros(AValue, Dir, Base, APlatform, AConfig);
  end;

begin
  Result := '';
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  try
    Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
    Xml := LeeTexto(ADprojPath, [ltJaula]);
  except
    Exit;
  end;
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  // What a build leaves per platform family: Windows .exe/.dll/.bpl, Linux
  // an ELF WITHOUT extension (plus .so), macOS the same (plus .dylib),
  // Android/iOS a .so. Measured 2026-08-23: a Linux64 build declared no
  // output at all and the agent had to hunt the ELF with delphi_list.
  if APlatform.StartsWith('Win', True) then
    ArtifactExts := ['.exe', '.dll', '.bpl']
  else if APlatform.StartsWith('Linux', True) then
    ArtifactExts := ['', '.so']
  else if APlatform.StartsWith('OSX', True) then
    ArtifactExts := ['', '.dylib']
  else
    ArtifactExts := ['.so', ''];
  Best := '';
  BestTime := 0;
  Dirs := TList<string>.Create;
  try
    for D in AllTagValues(Xml, 'DCC_ExeOutput') do
      Dirs.Add(D.Trim);
    for D in AllTagValues(Xml, 'DCC_BplOutput') do
      Dirs.Add(D.Trim);
    Dirs.Add('.\$(Platform)\$(Config)'); // the IDE default when unset
    for D in Dirs do
    begin
      Cand := Expand(D);
      if (Cand = '') or Cand.Contains('$(') then
        Continue; // still macro-based: not resolvable here
      if not TPath.IsPathRooted(Cand) then
        Cand := TPath.Combine(Dir, Cand);
      try
        Cand := TPath.GetFullPath(Cand);
      except
        Continue;
      end;
      for Ext in ArtifactExts do
      begin
        // Android and iOS name the artifact lib<Project>.so, not <Project>.so,
        // so the search used to come up empty and delphi_build answered
        // success with no "output" at all - the agent had to guess the path
        // (field round 8).
        Artifact := TPath.Combine(Cand, Base + Ext);
        if not TFile.Exists(Artifact) and (Ext = '.so') then
          Artifact := TPath.Combine(Cand, 'lib' + Base + Ext);
        if TFile.Exists(Artifact) then
        begin
          T := TFile.GetLastWriteTime(Artifact);
          if (Best = '') or (T > BestTime) then
          begin
            Best := Artifact;
            BestTime := T;
          end;
        end;
      end;
    end;
  finally
    Dirs.Free;
  end;
  Result := Best;
end;

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean): string; forward;

function DprojBuildHazard(const AXml, AProjectPath: string;
  AIgnoreBuildEvents: Boolean): string;
begin
  Result := HazardScan(AXml, AProjectPath, 0, AIgnoreBuildEvents);
end;

{ LISTA NEGRA: DANGER_TASKS y otras construcciones peligrosas conocidas.
  No es un interprete cerrado de MSBuild; AllowBuildScripts lo decide el operador. }
function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean): string;
var
  Low, V, Resolved, Imported: string;
begin
  Result := '';
  // The whole scan is CASE-INSENSITIVE on purpose. MSBuild itself is picky
  // about element casing, but a guard must not depend on that subtlety: the
  // cost of being insensitive is nil (no real project has a <PreBuildEvent>
  // in odd casing) and the cost of being wrong is arbitrary execution.
  Low := LowerCase(AXml);

  // Las funciones de propiedad se evaluan antes de los targets: tambien
  // pueden leer disco. Desescapar UNA vez es la misma regla del lector XML.
  var Evaluado := XmlUnescape(AXml);
  var Funcion := Pos('$(', Evaluado);
  while Funcion > 0 do
  begin
    var Inicio := Funcion + 2;
    while (Inicio <= Length(Evaluado)) and
          Evaluado[Inicio].IsWhiteSpace do
      Inc(Inicio);
    if (Inicio <= Length(Evaluado)) and (Evaluado[Inicio] = '[') then
      Exit(MsgText(SF_CFG_HAZARD_PROPERTY_FUNCTION));
    Funcion := Pos('$(', Evaluado, Funcion + 2);
  end;

  // A custom <Target> is NOT a hazard in itself. Real projects legitimately use
  // targets to copy their OWN output, print a message or set a property after a
  // build; refusing every target was a false positive as serious as a hole - it
  // broke legitimate projects, Authenticode signing among them (field round 9).
  // What turns "build" into "run" is a TASK that executes a program or plants/
  // deletes files. Scan for THOSE, wherever they sit (inside a target or not),
  // matched with or without a namespace prefix (<msb:Exec> passed a literal
  // "<Exec" check in field round 8; MSBuild rejected it, but the guard must not
  // depend on that). A trusted project that needs one of these enables it with
  // AllowBuildScripts del workspace (checked by the caller), never here.
  for var Danger in DANGER_TASKS do
    if HasElement(Low, Danger) then
      Exit(MsgFmt(SF_CFG_HAZARD_TASK_FMT,
        [Danger]));

  // RAD Studio build-event commands: only a NON-EMPTY one runs a shell.
  // Con AIgnoreBuildEvents no cuentan: el runner los vacia al compilar.
  if not AIgnoreBuildEvents then
  for var Tag in ['prebuildevent', 'postbuildevent', 'prelinkevent',
                  'postlinkevent', 'buildevent'] do
    // por EL analisis, pero mas estricto que el juez: tambien dentro de un
    // comentario, y el texto ESCRITO (un CDATA vacio o un comentario dentro
    // cuentan). Buscaba '<prebuildevent' como prefijo, y el
    // <PreBuildEventIgnoreExitCode> que el IDE escribe junto a cada evento
    // contaba como un evento con texto (oraculo, 17-oct-2026)
    for var T in TramosDeEtiqueta(AXml, Tag, False, True) do
      if Copy(AXml, T.Ini, T.Fin - T.Ini).Trim <> '' then
        Exit(MsgFmt(SF_CFG_HAZARD_SHELL_COMMAND_FMT, [Tag]));

  // <Import> brings in another MSBuild file, which carries its own targets -
  // so the payload can sit one file away from the project. Being macro-based
  // proves nothing: "$(MSBuildProjectDirectory)\payload.targets" is a macro
  // AND resolves next to the project (field round 8, confirmed execution).
  // Rule: trust ONLY the IDE's own imports without reading them; resolve and
  // SCAN anything else; refuse what cannot be resolved.
  // UN lector de atributos XML: comillas, blancos y entidades compartidos.
  // (tambien los de dentro de un comentario: mas estricto que el juez)
  for var Importado in AllTagAttr(AXml, 'Import', 'Project', True) do
  begin
    V := Importado.Trim;
    if V.StartsWith('\\') or V.StartsWith('//') then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_UNC_FMT, [V]));
    if IsStockImport(LowerCase(V)) then
      Continue;
    if ADepth >= 4 then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_PROFUNDO_FMT, [V]));
    Resolved := ResolveImportPath(V, AProjectFile);
    if Resolved = '' then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_NO_VERIFICABLE_FMT, [V]));
    if not TFile.Exists(Resolved) then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_NO_ESTA_FMT, [V]));
    // lo que no es del IDE se escanea si esta en las raices (o en la zona de
    // biblioteca); de fuera, se rechaza: el build lo cargaria de alli
    if LugarDeLecturaDenegado(Resolved, [ltJaula]) <> '' then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_FUERA_FMT, [V]));
    Imported := '';
    try
      Imported := LeeTexto(Resolved, [ltJaula]);
    except
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_ILEGIBLE_FMT, [V]));
    end;
    Result := HazardScan(Imported, Resolved, ADepth + 1, AIgnoreBuildEvents);
    if Result <> '' then
      Exit(MsgFmt(SF_CFG_HAZARD_POR_IMPORT_FMT, [Result, V]));
  end;
end;

end.
