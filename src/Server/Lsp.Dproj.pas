unit Lsp.Dproj;

{ The ONE place that reads a Delphi .dproj (tolerant XML scanning, no MSBuild
  engine). Both the LSP config fabricator and the project/platform tools use
  it - never a second parser (measured house rule: do not reinvent wheels).

  A .dproj is MSBuild XML. What matters here:
  - <Platform value="Win64">True</Platform>  under <Platforms>  -> declared platforms
  - <BuildConfiguration Include="Debug"><Key>Cfg_2</Key>...     -> build configurations
  - <FrameworkType>VCL|FMX|None</FrameworkType>                 -> which UI framework
  - <AppType>Application|Console</AppType>
  The value of a property for ONE build is read with EffectiveProperty and
  written with PonPropiedadDelBuild (the group of that build, as the IDE). }

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
    // el texto no cierra su <Project>: un upload cortado o una edicion a
    // medias (DprojIncompleto); lo que se lea de el es de un fichero a medias
    Incompleto: Boolean;
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
    { Las configuraciones que se COMPILAN: las que declara, menos Base (de la
      que heredan las demas; el IDE no la deja activar), con su nombre y en su
      orden. Vacia si no declara ninguna. Estaba a mano en el juez del build y
      en set-active, y el manifiesto de despliegue escribia 'Debug','Release'
      a fuego (con otra configuracion no desplegaba nada y decia exito). }
    function Compilables: TArray<string>;
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

  { Un valor que el build LEE, tal como lo escribe el proyecto y como lo
    tiene msbuild donde lo lee (ValoresQueLeeElBuild). }
  TValorDelProyecto = record
    Elemento: string; // el nombre LOCAL del elemento, como esta escrito (Icon_MainIcon, RcCompile)
    Escrito: string;  // el valor entero (ya desescapado): el de la propiedad, o el Include
    // el valor con las propiedades del documento expandidas como las tiene
    // msbuild donde lo lee (las de una propiedad, en su punto; las de un
    // Include, al final) y con lo que el documento no sabe dejado escrito
    // como $(Nombre) para quien lo sabe (la tabla del build, el entorno, otro
    // documento, lo que nadie define). Puede ser una lista (;)
    Expandido: string;
    // el primer $(Nombre) cuyo valor NO se sabe donde el build lo lee (una
    // propiedad puesta bajo una Condition que no se sabe evaluar, o una
    // GLOBAL del build): '' si ninguno. Con uno, Expandido no vale
    Dudoso: string;
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

  { Un elemento del documento en el recorrido con pila (ElementosDe): su
    nombre LOCAL (sin prefijo de espacio de nombres) en minusculas y como
    esta escrito, los nombres de sus antepasados (Ruta[0] es la raiz) y su
    tramo, el de TramosDeEtiqueta (ValorDeTramo y AtributosDeTramo leen con
    el). }
  TElementoXml = record
    Nombre: string;
    Escrito: string;
    Ruta: TArray<string>;
    Tramo: TTramoXml;
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
{ ...y el definidor de una CONFIGURACION como lo escribe el IDE, entero y sin
  el salto del final: su Condition (ConfigDefinerCondition), <AClave>true y
  <CfgParent>Base si no es la base, y <Base>true. EL escritor: delphi_create
  y los fixtures de los tests lo componian cada uno (revisor del 21-oct-2026). }
function XmlGrupoDefinidorDeConfig(const AConfig, AClave: string): string;
{ ...y el de sus VALORES: la Condition de GroupCondition y AProps dentro (sus
  lineas, cada una con su salto), entero y sin el salto del final. EL
  escritor: delphi_create y add-platform (se escribia a mano en los dos;
  revision del 18-oct-2026). }
function XmlGrupoDeValores(const APlatform, AClave, AProps: string): string;
{ La plataforma (una de las conocidas, con su grafia) de un grupo de valores
  (ADefinidor = False) o de un definidor; '' si la Condition no es la de
  ninguna - la base tampoco: esa es GroupCondition(''). }
function PlataformaDeGrupo(const ACondicion: string; ADefinidor: Boolean): string;

{ ---- el grupo de VALORES de un build y su escritor: UNA casa ----
  Donde el IDE escribe una opcion de una plataforma y una configuracion, y
  de donde msbuild la lee para ese build: '$(Base)'!='' (sin ninguna de las
  dos: todos los builds), '$(Base_X)'!='' (la plataforma, todas las configs),
  '$(Cfg_N)'!='' (la config, todas las plataformas) y '$(Cfg_N_X)'!='' (las
  dos), con Cfg_N la clave de BuildConfiguration. Lo elegia cada uno a su
  manera: set-sdk / set-profile (solo plataforma, PonPropiedadDePlataforma en
  Mcp.Tools.Config), add-searchpath y remove-searchpath (EnsurePlatformGroups
  y el grupo por su Condition), y en un grupo de configuracion no escribia
  nadie: el keystore de Android que el IDE deja en '$(Cfg_1_Android64)'!=''
  no tenia tool que lo quitase (David, 21-oct-2026: "hay que unificar
  claramente la gestion de los ficheros de proyecto"). }
type
  { Por que un build no tiene grupo de valores ni se le puede crear: la
    configuracion no la declara el proyecto; le falta el definidor que el
    IDE escribe al declararla (sin el msbuild nunca pone su clave y un grupo
    suyo no se leeria); no hay grupo de valores ni definidor del que
    colgarlo; o el .dproj quedo inconsistente al quitar lo que habia. }
  TFaltaDeGrupo = (fgNinguna, fgConfigNoDeclarada, fgSinDefinidor, fgSinGrupoBase, fgInconsistente,
    fgClaveInvalida);

{ Un nombre de etiqueta que msbuild acepta en un PropertyGroup: letra o _ y
  luego letras, digitos, _ y - (medido el 21-oct-2026 con msbuild: un '.' es
  MSB5016 "caracter no valido", un '-' compila). Gramatica propia, UNA: la
  del nombre de una propiedad que escribe set-property y la de la clave de
  una configuracion con la que se compone un definidor. }
function EsNombreDeEtiqueta(const ANombre: string): Boolean;

{ La clave con la que el .dproj nombra el build de AConfig: Base sin config,
  y con ella la Cfg_N de su BuildConfiguration ('' si no la declara). }
function ClaveDelBuild(const AXml, AConfig: string): string;
{ Las claves de los builds del proyecto - Base y las de sus configuraciones
  (Cfg_N o como se llamen) - en el orden de sus DEFINIDORES en el documento,
  que es el de los grupos del IDE; las que no tienen definidor, al final. Lo
  que set-property no escribe (son estructura) y el orden en que
  AseguraGrupoDelBuild coloca un grupo nuevo. }
function ClavesDelProyecto(const AXml: string): TArray<string>;
{ El grupo de valores del build APlatform/AConfig ('' = sin esa mitad), si
  lo hay: EL lector del grupo. }
function GrupoDelBuild(const AXml, APlatform, AConfig: string; out AGrupo: TGrupoXml): Boolean;
{ ...y su inversa: de que build es el grupo de valores con esa Condition - la
  plataforma ('' = todas) y la configuracion con el nombre que declara el
  proyecto ('' = todas; la base, las dos vacias). False si la Condition no es
  la de un grupo de valores de un build (un definidor, otra cosa). La vista
  de los search paths la usa para nombrar cada grupo. }
function BuildDelGrupo(const AXml, ACondicion: string; out APlatform, AConfig: string): Boolean;
{ ...creandolo si falta, con su definidor, donde los pone el IDE (medido en
  un .dproj suyo el 21-oct-2026): los definidores por clave - el de la
  configuracion y tras el los de sus plataformas - y luego los grupos de
  valores en el mismo orden, Base y las configuraciones como las declara
  BuildConfiguration. El definidor de una plataforma va tras el ultimo
  definidor de su clave; el grupo de valores de una plataforma tras el ultimo
  de valores de su clave, y el de una clave sola tras los de las claves
  anteriores (la base, sin ninguno, tras los definidores). El definidor de
  la configuracion ('$(Config)'=='X' or '$(Cfg_N)'!='') tiene que estar: lo
  escribe el IDE al declararla y sin el msbuild no lee ese grupo. }
function AseguraGrupoDelBuild(var AXml: string; const APlatform, AConfig: string;
  out AGrupo: TGrupoXml; out AFalta: TFaltaDeGrupo): Boolean;
{ EL escritor de una propiedad de un build, el gemelo de EffectiveProperty:
  <ATag>AValor</ATag> en el grupo de valores de APlatform/AConfig, creado si
  falta (AseguraGrupoDelBuild). Si ese grupo ya la lleva, cambia en SU sitio
  (la ultima, la que valia: AAntes) y las demas copias con esa Condition se
  quitan con su linea; si no, entra al FINAL del grupo (AnadeAlGrupo), como
  la pone el IDE. Asi no cambia el orden en que msbuild las evalua: se
  quitaba y volvia al principio, y DCC_UnitSearchPath=$(X) creada despues de
  X quedaba encima de X y la veia vacia (22-oct-2026). Con el mismo valor ya
  puesto una sola vez no toca nada; quitar de un grupo que no existe no lo
  crea. False, con AFalta, si no hay grupo ni se pudo crear. }
function PonPropiedadDelBuild(var AXml: string; const ATag, AValor, APlatform, AConfig: string;
  AQuitar: Boolean; out AAntes: string; out AFalta: TFaltaDeGrupo): Boolean;
{ EL sitio de una propiedad NUEVA en un grupo, como la pone el IDE: al FINAL
  de su contenido, en su linea, detras de la ultima - en el orden en que se
  crean, que es el que cuenta para msbuild (orden de documento: una que usa
  $(X) creada despues de X la ve). Medido el 22-oct-2026 con el IDE: cinco
  opciones nuevas de Project Options quedaron detras de VerInfo_Keys, en el
  orden en que se rellenaron; una que ya estaba no se movio. AElemento, el
  elemento ya compuesto (XmlElemento). AGrupo, uno con su etiqueta de cierre
  (no un <PropertyGroup/>). }
procedure AnadeAlGrupo(var AXml: string; const AGrupo: TGrupoXml; const AElemento: string);
{ Si ANombre es un evento de build o una opcion libre al compilador: texto
  que va a una linea de ordenes, que el build vacia (los eventos) o niega
  (las opciones) y que ninguna tool escribe en un .dproj (set-property lo
  niega). }
function EsTextoLibreDelBuild(const ANombre: string): Boolean;
{ Si ANombre es una de las propiedades por las que los <Import> del IDE
  resuelven el fichero que cargan (RESERVED_IDE_IMPORT_PROPS: BDS, APPDATA,
  ProductVersion...): un proyecto nunca las define, el build que las lleve
  se niega (BUILD-019, RedefinedIdeImportProperty) y set-property no las
  escribe (la segunda barrera; revisor de seguridad del 21-oct-2026). }
function EsPropiedadReservadaDelIde(const ANombre: string): Boolean;
type
  { Lo que vale una Condition para un build: cierta, falsa, o no se sabe. }
  TVeredicto = (vSi, vNo, vNoSeSabe);

  { Lo que vale una propiedad al evaluar una Condition: sabida (puesta por un
    grupo que se aplica, o definida en el documento y aun no puesta: ''),
    dudosa (puesta por un grupo o un elemento que no se sabe si se aplica) o
    desconocida (msbuild la toma de fuera del documento: el entorno,
    rsvars.bat, la tabla del IDE, y la puerta no sabe que vale). }
  TEstadoDeBandera = (eSabida, eDudosa, eDesconocida);
  TBanderaDelBuild = record
    Valor: string;
    Estado: TEstadoDeBandera;
  end;
  TBuscaBandera = reference to function(const ANombre: string): TBanderaDelBuild;

{ Una Condition de un .dproj evaluada como la evalua msbuild para un build
  APlatform/AConfig, sobre lo PUESTO hasta ahi: '$(X)'!='' / '$(X)'=='' /
  '$(X)'=='v' / '$(X)'!='v' (sin distinguir mayusculas), 'and', 'or' y
  parentesis; $(Config) y $(Platform) valen lo pedido y las demas lo que los
  grupos anteriores dejaron en ABanderas (nombre=valor; '' si nadie la puso).
  Otra cosa - Exists(), una funcion de propiedad, un item, otro operador, otras
  comillas - es vNoSeSabe, y una bandera de ADudosas (puesta por un grupo o un
  elemento que no se sabe si se aplica) hace vNoSeSabe lo que la compare: lo
  que no se sabe se da por aplicado, una de mas es prudencia. Gramatica
  propia, UNA y declarada: el juez es msbuild, al que no se puede preguntar
  sin evaluar el proyecto antes de que la puerta lo juzgue (una Exists() en
  una condicion le haria mirar fuera de la jaula). No decide por el NOMBRE de
  la clave (Cfg_N) sino por lo que esta puesto: una bandera plantada en un
  grupo sin condicion, una configuracion hija que pone la de su madre o una
  clave renombrada en BuildConfiguration son grupos que msbuild lee
  (revisores del 21-oct-2026, medido). }
function EvaluaCondicion(const ACondicion, APlatform, AConfig: string;
  ABusca: TBuscaBandera): TVeredicto;
{ Para cada elemento de AElementos (los de ElementosDe) que esta en un
  PropertyGroup, lo que vale para el build APlatform/AConfig su Condition y
  la de su grupo, evaluadas como msbuild en orden de documento sobre lo que
  los grupos y elementos anteriores que se aplican dejan puesto (el ultimo
  gana): vNo si una de las dos es falsa, vNoSeSabe si ninguna es falsa y
  alguna no se sabe, vSi si las dos son ciertas; vSi tambien para lo que no
  esta en un PropertyGroup. Las propiedades dudosas (puestas por un grupo o
  un elemento que no se sabe si se aplica) hacen dudoso lo que las compare,
  y las que msbuild toma de fuera del documento - AExternas (la tabla con
  que el build expande) y el entorno del servidor - no se dan por vacias;
  una definida en el documento y aun no puesta vale ''; las GLOBALES del
  build (AGlobales: lo que pasa por /p:, que gana a lo escrito aun definido
  despues) son dudosas aunque el documento las ponga. Solo cuentan los
  PropertyGroup que cuelgan de la raiz: uno dentro de un Target o de
  ProjectExtensions no entra en la pasada de msbuild. Los valores se fijan
  expandidos, como msbuild al definirlos, y una comparacion coteja numeros y
  booleanos antes que texto, desescapando %XX (revisor E, medido el
  21-oct-2026 con el msbuild del IDE). EL juez de "este
  grupo se aplica a este build": para leer (EffectiveProperty: solo vSi
  cuenta) y para juzgar (la puerta del build: vNo no se juzga, lo demas si).
  Decidia por el NOMBRE de la clave (Cfg_N) y leia otra cosa que msbuild con
  una bandera plantada, una config hija o una clave renombrada (revisores
  del 21-oct-2026). }
function VeredictosDeElementos(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>): TArray<TVeredicto>; overload;
{ Lo mismo, y ademas cada elemento EXPANDIDO como lo tiene msbuild donde lo
  lee (AExpandidos): el valor de una propiedad de un PropertyGroup con lo que
  las propiedades del documento valen EN ESE PUNTO (lo ultimo puesto antes
  por un grupo y un elemento que se aplican; vacio si el documento la define
  y aun no la puso; lo del proyecto sobre lo del entorno), y el Include de un
  item con lo que valen AL FINAL (msbuild evalua los items despues de todas
  las propiedades). Lo que el documento no sabe (AExternas, el entorno, lo
  que nadie define) queda escrito como $(Nombre) para quien lo sabe, y
  ADudosos[I] es el primer macro cuyo valor no se sabe (puesto por un grupo o
  un elemento que no se sabe si se aplica, o una global del build; '' si
  ninguno). EL expansor de lo que lee la puerta del build (1.22.0): tres
  agujeros medidos el 22-oct-2026 expandian con otro valor que el que dcc
  lee - el ultimo del documento, el de la tabla con la propiedad redefinida
  por el proyecto, el definido despues del uso. }
function VeredictosDeElementos(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>;
  out AExpandidos, ADudosos: TArray<string>): TArray<TVeredicto>; overload;
{ True si ANombre es un nombre de propiedad de msbuild (letras, cifras, _ y -,
  como EsNombreDeEtiqueta): lo unico que vale dentro de un $() de un valor que el
  build lee (la lista blanca de la puerta, Lsp.BuildRunner.LecturasDelBuildDenegadas;
  1.22.0). msbuild acepta el '-' en un nombre (medido el 22-oct-2026: $(My-Path)
  se expande), asi que la puerta no lo niega (H9). }
function EsNombreDeMacro(const ANombre: string): Boolean;
{ Los %XX de una cadena de msbuild como el caracter que nombran (%2E = '.'):
  msbuild desescapa un valor tras expandirlo, y la puerta de lecturas juzga lo
  desescapado (H3, 22-oct-2026). }
function DesescapaDeMsbuild(const S: string): string;
{ Para cada elemento de AElementos (los de ElementosDe), si es de OTRO build
  que APlatform/AConfig: esta en un PropertyGroup cuya Condition, o la suya,
  es falsa (vNo) evaluada como msbuild en orden de documento, con las
  propiedades que los grupos y elementos anteriores que se aplican dejan
  puestas (el ultimo gana), dudosas las de los que no se sabe, y desconocidas
  las que msbuild toma de fuera del documento: AExternas (la tabla con que el
  build expande: la del IDE, rsvars.bat, las de msbuild) y el entorno del
  servidor; una definida en el documento y aun no puesta vale ''. Lo que no
  esta en un PropertyGroup no es de otro build. }
function ElementosDeOtroBuild(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>): TArray<Boolean>;
{ Los trozos de un valor de lista del proyecto (a;b;c): partidos por ';', sin
  blancos alrededor y sin vacios. EL troceador de lo que lee la puerta del
  build - lo escrito y lo que expande un macro - que eran tres Split a pelo. }
function TrozosDeLista(const AValor: string): TArray<string>;
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
{ EL escritor de un <ItemGroup Condition="..."> del .deployproj con sus
  entradas (las de XmlDeployFile, cada una con su salto) dentro: la apertura
  con su Condition, las entradas y el cierre con la sangria del IDE, sin la
  sangria de delante ni el salto del final (los pone quien lo coloca). Lo
  componian a mano cinco sitios: los dos manifiestos que genera el servidor,
  el hueco y el grupo nuevo de un manifiesto que se completa y add-deployfile
  (revisor del 21-oct-2026). Sin entradas, el vacio del IDE, auto-cerrado. }
function XmlGrupoDeDespliegue(const ACondicion, AEntradas: string): string;
{ AXml (un .deployproj) con AEntradas (de XmlDeployFile) en el grupo de
  APlataforma, '$(Platform)'=='X', como lo deja el IDE: el vacio que escribe
  (<ItemGroup .../>) se llena, en uno con otros ficheros van al principio, y
  sin ninguno se crea al final; '' si no tiene </Project>. Lo hacian a mano
  el completado del manifiesto (EnsurePlatformOutputEntries) y
  add-deployfile, que creaba un grupo nuevo en cada llamada. }
function ConEntradasEnSuGrupo(const AXml, APlataforma, AEntradas: string): string;
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
  { Un <DeployFile> de un .deployproj: su tramo, el ItemGroup que lo contiene
    y la plataforma de ese grupo ('' si su Condition no es de una). }
  TEntradaDelManifiesto = record
    Tramo: TTramoXml;
    Grupo: TGrupoXml;
    Plataforma: string;
  end;

{ Los <DeployFile> de un .deployproj, cada uno con su grupo y la plataforma
  de este, en orden de documento. EL recorrido: estaba a mano en
  FindDeployEntries y en la vista de delphi_config, y lo pide el exe= de
  remote-run (lo que el proyecto despliega en esa plataforma). }
function EntradasDelManifiesto(const AXml: string): TArray<TEntradaDelManifiesto>;

{ ---- la seccion Deployment del .dproj: el Deployment Manager del IDE ----
  Lo que escribe el IDE al anadir un fichero en Project > Deployment y lo que
  lee para GENERAR el .deployproj al desplegar (medido con David el
  23-oct-2026; msbuild no la lee, lee el .deployproj): en
  ProjectExtensions/BorlandProject/<Deployment Version="5">, una <DeployFile
  LocalName Configuration Class> por fichero, configuracion y plataforma, con
  su <Platform Name>: RemoteDir solo si no es el de su clase, en la forma
  .\sub\; RemoteName; Overwrite. }
type
  { Una <Platform> de verdad (la pseudo 'All Platforms' no) de una
    <DeployFile> de la seccion, con lo de su entrada; Entrada y Plat, sus
    tramos; Plataformas, cuantas de verdad lleva la entrada. }
  TDespliegueDelProyecto = record
    LocalName, Config, Clase, Plataforma, RemoteDir, RemoteName: string;
    Entrada, Plat: TTramoXml;
    Plataformas: Integer;
  end;

{ EL lector de la seccion: cada <Platform> de verdad de cada <DeployFile>, en
  orden de documento. }
function DesplieguesDelProyecto(const AXml: string): TArray<TDespliegueDelProyecto>;
{ EL escritor de una <DeployFile> de la seccion como la escribe el Deployment
  Manager, con su <Platform>; ARemoteDir '' = el de su clase (no se
  escribe). ASangria, la de la <DeployFile>; sin salto al final. }
function XmlDeployFileDelProyecto(const ALocalName, AConfig, AClase, APlataforma,
  ARemoteDir, ARemoteName, ASangria: string): string;
{ AXml con esa <DeployFile> donde la pone el IDE: entre las demas por su
  LocalName (en orden ordinal, medido), y la seccion <Deployment Version="5">
  creada al final de <BorlandProject> si no la hay (un .dproj de
  delphi_create no la trae). False si no hay <BorlandProject>. }
function ConDespliegueDelProyecto(const AXml, ALocalName, AConfig, AClase, APlataforma,
  ARemoteDir, ARemoteName: string; out AXmlNuevo: string): Boolean;
{ La carpeta del destino en que el IDE deja una entrada de APlataforma al
  generar el .deployproj, con su barra final: la raiz del proyecto en esa
  plataforma (su <ProjectRoot>, $(PROJECTNAME) = AProyecto; sin el,
  AProyecto) y la carpeta de la entrada sin su .\ o, sin ella, la de su clase
  (<DeployClass>): .\data\ -> Proyecto\data\ (medido en un .deployproj que
  genero el IDE). La comparten el .deployproj que se escribe y la vista. }
function DestinoDeDespliegue(const AXml, AProyecto, APlataforma, AClase, ARemoteDir: string): string;

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
{ Un .dproj que no CIERRA su <Project>: un upload cortado (Hermes, 21-oct-2026:
  el bloque <Platforms> va al final y el build decia BUILD-046 "plataforma no
  habilitada") o una edicion a medias. GRAMATICA PROPIA, declarada: el juez
  seria MSXML, el cargador del IDE, que es oraculo en tests/test_oraculo_xml y
  no entra en el servidor (decision del 17-oct-2026); esta pregunta - abre la
  raiz y no la cierra - es la unica que se hace aqui, y UNA vez. }
function DprojIncompleto(const AXml: string): Boolean;
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
{ La FUENTE PRINCIPAL de un proyecto por su extension: su programa (.dpr) o
  su paquete (.dpk). EL predicado de DprojDe y de quien pregunta "es el .dpr
  o el .dpk": estaba escrito a mano en cinco sitios (R1 del censo de Fable,
  depuracion de la 1.23). }
function EsFuentePrincipal(const APath: string): Boolean;
{ Lo que una tool acepta como PROYECTO: su .dproj o su fuente principal (.dpr,
  .dpk); un .groupproj es un grupo, otra cosa. Eran seis listas a mano, y la
  de delphi_test dejaba fuera el .dpk mientras su negativa (CFG-033) lo daba
  por bueno (R1 del censo de Fable). }
function EsProyectoOSuFuente(const APath: string): Boolean;

{ LA configuracion de un build, un test o lo que delphi_config escribe para
  una: la pedida (ARaw) o, sin ella, la seleccionada del proyecto
  (ConfigPorDefecto), juzgada, y con el nombre que declara en AConfig ('' o
  la negativa). Aceptar una que no tiene compilaba en Win64\<Inventada>\ con
  los ajustes de Base (medido el 2026-08-25 en test y el 27-sep en build).
  Antes que la lista, el NOMBRE (NombreDeConfigNoValido): el valor va a la
  linea de msbuild, y ni un proyecto sin configuraciones ni uno que declara
  un nombre raro lo hacen seguro (4.8, revision de la 1.18.1). Base, su
  negativa propia (CFG-120). Un proyecto que no declara ninguna (anterior a
  las plataformas) admite un nombre valido, como msbuild. La seleccionada que
  no declara lo dice (CFG-121): "no existe" de algo que el agente no habia
  pedido no se entendia (revision del 18-oct-2026). UN juez: eran
  ConfigDesconocida (build y test) y ConfigDeclarada (config), que negaba con
  la lista vacia lo que el build aceptaba, con su propio CFG-116, y
  add-deployfile tomaba la seleccionada sin juzgarla (Fable, 1.22.2). }
function ConfigDelBuild(const AInfo: TDprojInfo; const ARaw: string; out AConfig: string): string;

{ El nombre de una configuracion que puede llegar a la linea de msbuild del
  build (/p:Config=): letras, digitos, espacio, ".", "_" y "-". UNA
  definicion para la puerta (Lsp.Guard.BuildArgDenied) y el fondo
  (ConfigDelBuild); '' no es un nombre malo (es "la de por defecto"). }
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

type
  { El sistema de una plataforma de Delphi: lo que decide la extension del
    binario, el lanzador de PAServer, si despliega por PAServer o por adb...
    Lo dice UNA tabla (PLATAFORMAS, en la implementacion); era
    StartsWith('Win'), StartsWith('Android')... en ~20 sitios (censo de
    jueces del 18-oct-2026, lote 2). }
  TSistemaDePlataforma = (spDesconocido, spWindows, spMacOS, spLinux, spAndroid, spIOS);

{ True when APlatform is one that never needs a remote profile/SDK (it builds
  natively on this Windows host): las de Windows. }
function IsLocalPlatform(const APlatform: string): Boolean;

{ El sistema de APlatform; spDesconocido si no es una plataforma de Delphi. }
function SistemaDePlataforma(const APlatform: string): TSistemaDePlataforma;

{ El sistema del PAServer que despliega APlatform: el suyo, salvo iOS, que
  despliega por el PAServer de un Mac (paclient no conoce otra plataforma de
  Apple que OSX64), y Android, que no despliega por PAServer (el .apk se hace
  aqui y delphi_adb lo instala): spDesconocido. Un perfil sirve a una
  plataforma si su Profile_platform es de este sistema. }
function SistemaDelPAServer(const APlatform: string): TSistemaDePlataforma;

{ True si un binario de APlatform corre en ESTA maquina, que es lo que hace
  delphi_test: de Windows y de una arquitectura que este Windows ejecuta, y
  eso lo dice Windows (GetMachineTypeAttributes). Un WinARM64EC compila aqui
  pero no corre en un x64: reventaba con 0xC0000005 y la respuesta culpaba al
  runner (medido el 18-oct-2026). }
function CorreEnEstaMaquina(const APlatform: string): Boolean;
{ Las plataformas que CorreEnEstaMaquina deja correr aqui, unidas por ', ':
  lo que dicen TEST-001 y CFG-118, que decian "Win32 and Win64" a mano
  (Win64x corre en un x64, y WinARM64EC en un ARM; octava pasada de Fable). }
function PlataformasQueCorrenAqui: string;

{ La extension del ejecutable de APlatform, la ExeExt de los targets
  (CodeGear.Common.Targets): '.exe' en Windows, '.so' en Android, '' en el
  resto (un ELF de Linux, el binario de macOS y de iOS). }
function ExtensionDeEjecutable(const APlatform: string): string;

{ La carpeta del .apk donde van las librerias nativas de APlatform
  (library\lib\<abi>\); '' si no es de Android. La componian a mano el
  manifiesto de Android y add-deployfile, con el ABI escrito en cada uno. }
function CarpetaDeLibreriasDelApk(const APlatform: string): string;

{ El nombre con el que el .apk lleva y carga el binario de AProyecto:
  lib<proyecto>.so, el que recogen los targets ($(DllPlatformPrefix)
  $(MSBuildProjectName).so, CodeGear.Delphi.Targets). Es otro hecho que el
  fichero que deja el build (NombreDelBinario: con OutputExt, lib<p>.<ext>). }
function LibreriaDelApk(const AProyecto: string): string;

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

  { La carpeta de salida que el IDE escribe en un proyecto nuevo (Output
    directory; la de unidades cuelga de ella): UN literal para quien la
    supone cuando el proyecto no declara nada (ResolveBuildOutput,
    BuildOutputDefault), para quien la restaura (delphi_config set-output
    default) y para quien la escribe (Lsp.Scaffold). }
  IDE_OUTPUT_DEFAULT = '.\$(Platform)\$(Config)';

  { Las salidas que el build SUPLE cuando el proyecto no las declara para esa
    plataforma/config (David, 21-oct-2026: un proyecto real de veinte anos
    compilaba en el IDE y aqui no): sin ellas dcc deja los .dcu junto a cada
    fuente - los de un componente instalado, en su carpeta de Program Files
    (medido ese dia: 14 .dcu de un componente) - y el .bpl y el .dcp en las
    carpetas globales del
    IDE. La .hpp (salida C++) no se suple: C++ queda fuera del producto
    (David, 18-oct) y BuildOutputUndeclared la sigue pidiendo. }
  SALIDAS_QUE_SUPLE_EL_BUILD: array [0 .. 2] of string = (
    'DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput');

{ Value of <ATag>...</ATag> in a small TRUSTED XML (our own .profile/.sdk
  files, written by paclient or by this server). Not a general parser on
  purpose. One definition, shared by delphi_paserver, delphi_adb and
  remote-run. Ya desescapado, como AllTagValues: la inversa de XmlElemento. }
function TagValue(const AXml, ATag: string): string;


{ El valor EFECTIVO de ATag para un build APlatform/AConfig, como lo evalua
  msbuild: los grupos que se aplican a ese build - EL juez de la puerta,
  VeredictosDeElementos: las Condition evaluadas en orden de documento sobre
  lo que los grupos anteriores dejan puesto, no por el nombre de la clave -,
  en orden de documento, el ultimo que la fija gana, y un $(ATag) dentro del
  valor es lo que valia hasta ahi (<DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>,
  como escribe el IDE los defines de cada configuracion). Para LEER solo
  cuenta lo cierto: un grupo o un elemento cuya Condition no se sabe (un
  nombre de fuera, una funcion) no se da por declarado; la puerta, en cambio,
  lo juzga. El juez de las propiedades por grupos: la salida, el SDK, el
  perfil, los paquetes, los ajustes del motor y get-property. Una
  configuracion que hereda de otra que no es Base SI lee los grupos de esa
  otra, como msbuild: su definidor pone la clave de la madre (medido el
  21-oct-2026 con msbuild, G11 de test_build_grupos_1215). }
function EffectiveProperty(const AXml, ATag, APlatform, AConfig: string): string;
{ Las propiedades del documento que AValor usa ($(X)) y que msbuild lee
  VACIAS en el elemento ATag que lo lleva (en un PropertyGroup de la raiz,
  con ese valor), para el build APlatform/AConfig: ninguna definicion de X
  que se aplique antes de el y alguna despues - msbuild lee un .dproj de
  arriba abajo y fija cada valor al definirlo -, por EL juez de la puerta
  (VeredictosDeElementos). Ni la de ATag (la herencia que escribe el IDE) ni
  lo que el documento no define. Un set-property que cambia un valor en su
  sitio lo puede dejar encima de la X que usa: F2613 sin aviso (Opus en
  Hermes, 22-oct-2026). }
function UsadasAntesDeDefinirse(const AXml, ATag, AValor, APlatform, AConfig: string): TArray<string>;

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

{ Todos los elementos de AXml en orden de documento, con la pila de sus
  antepasados: EL recorrido del documento entero, el de la lista blanca del
  build (ElementoNoAdmitido) y el de lo que el build lee
  (ValoresQueLeeElBuild). Sobre el texto de busqueda SIN lo oculto: lo que
  hay en un comentario o un CDATA no es un elemento para msbuild, y negarlo
  rompia un .targets con ejemplos comentados. AMalFormado: '' o por que no
  se pudo seguir (un cierre que no casa, una etiqueta sin fin o sin cerrar),
  con lo recorrido hasta ahi: lo que no se deja seguir no se aprueba. }
function ElementosDe(const AXml: string; out AMalFormado: string): TArray<TElementoXml>;
{ Los nombres (como estan escritos) de las propiedades que definen los
  PropertyGroup de la raiz de un documento, sin repetir: lo que msbuild da
  por vacio hasta que se pone y lo que un documento importado deja puesto
  para los demas de la cadena (la puerta del build). }
function PropiedadesDefinidas(const AElementos: TArray<TElementoXml>): TArray<string>;

{ Lo que un build APlatform/AConfig LEE de un proyecto por lo que ESCRIBE
  (1.21.2): cada valor de cada propiedad de un PropertyGroup (menos los
  eventos de build, que el runner vacia y DprojBuildHazard juzga) y el
  Include de cada item de un ItemGroup, con el elemento que lo lleva, tal
  como esta escrito (Escrito, una lista entera) y EXPANDIDO como msbuild lo
  tiene donde lo lee (Expandido, por VeredictosDeElementos: lo que el
  documento no sabe queda escrito como $(Nombre) para la tabla del build, y
  Dudoso nombra el primer macro que no se sabe; 1.22.0). Quien lo juzga lo
  parte por ';' ya expandido. Lo que esta en un grupo (o un elemento con
  Condition) que este build NO evalua (la Condition es falsa, como la evalua
  msbuild en orden de documento) no lo lee y no se juzga: hasta la 1.21.4 se
  juzgaba todo, y un keystore solo de Android64 tumbaba un build Linux64
  (David, 21-oct-2026: se juzga la compilacion pedida, no las demas). Una
  condicion que no se sabe evaluar se sigue juzgando: una de mas es
  prudencia, una de menos es una puerta. Lo de ProjectExtensions no es del
  build: msbuild lo ignora. }
function ValoresQueLeeElBuild(const AXml, APlatform, AConfig: string;
  const AExternas, AGlobales: TArray<string>): TArray<TValorDelProyecto>;

{ Los textos del .dproj y de cada fichero DEL PROYECTO que importa (un
  .optset), recursivo hasta 4 niveles, con el fichero de cada texto en el
  mismo orden: lo que un build lee de este proyecto. Los del IDE no se leen
  (IsStockImport); lo que no se resuelve se salta aqui y lo rechaza
  DprojBuildHazard. UN lector para las preguntas sobre la salida
  (BuildOutputDirs, BuildOutputUndeclared) y sobre lo que lee
  (Lsp.BuildRunner.LecturasDelBuildDenegadas). }
function ProjectXmlChain(const ADprojPath: string; out AFicheros: TArray<string>): TArray<string>; overload;
function ProjectXmlChain(const ADprojPath: string): TArray<string>; overload;

{ The artifact a build just produced, found ON DISK (truth of the moment,
  never an index): candidate output dirs are every DCC_ExeOutput /
  DCC_BplOutput declared in the .dproj plus the IDE default
  .\$(Platform)\$(Config), with the common macros expanded; the newest
  existing <project>.exe/.dll/.bpl among them wins. Returns '' when nothing
  is there (build failed, macro we cannot resolve, unusual layout). }
function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;
{ EL expansor de los macros de un valor de SALIDA del .dproj: $(Platform),
  $(Config), $(MSBuildProjectDirectory) / $(ProjectDir) (ADir) y
  $(MSBuildProjectName) / $(SanitizedProjectName) (ABase). Lo que conserva
  '$(' no se sabe resolver aqui. UNA copia: ResolveBuildOutput, BuildOutputDirs
  (la puerta) y el ProjectOutput del manifiesto de despliegue (que expandia
  a mano; revisor del 21-oct-2026). }
function ExpandOutputMacros(const AValue, ADir, ABase, APlatform,
  AConfig: string): string;

{ El NOMBRE del binario (sin carpeta) que deja el build de APlatform/AConfig,
  como lo compone CodeGear.Delphi.Targets: <proyecto>.<OutputExt> cuando el
  .dproj declara OutputExt para ese build (Project Options > Application >
  Target file extension: App.x64.exe, App.Debug.exe, App.x64.Debug.exe, por
  plataforma y configuracion, lo que David llama
  "otro concepto": el nombre del exe), y si no, la extension de la
  plataforma (ExtensionDeEjecutable); en Android, lib<proyecto>.so, como los
  targets. UN nombrador: lo leen ResolveBuildOutput
  (el "output" de delphi_build y el exe de delphi_test) y los DeployFile del
  .deployproj (OutputDeployEntry y el manifiesto generado). Medido el
  21-oct-2026: el build Win32 de un proyecto real contesto "output" con un
  <proyecto>.exe de diciembre, el ultimo .exe que habia en la carpeta, mientras
  acababa de escribir el <proyecto>.<OutputExt> al lado; en Win64 no
  contesto ninguno. }
function NombreDelBinario(const AXml, ABase, APlatform, AConfig: string): string;

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

{ Las carpetas de salida que este proyecto NO declara PARA ESTE BUILD
  (APlatform/AConfig: cada plataforma y config puede tener la suya o heredar
  la global, EffectiveProperty) y que el IDE pondria fuera de el, en orden;
  vacio si declara todas las que usa. Sin DCC_DcuOutput los .dcu caen junto a
  cada fuente (tambien los de una referencia de solo lectura y los de un
  componente instalado, en Program Files); un paquete sin
  DCC_BplOutput/DCC_DcpOutput los deja en las carpetas globales del IDE, y la
  salida C++ (DCC_CBuilderOutput) sin DCC_HppOutput deja alli los .hpp (los
  .obj y .bpi van a la del .dcp). Hasta la 1.21.2 se rechazaba la primera que
  faltaba (David, 25-sep-2026; 1 de 22 proyectos de nuestras raices); desde
  la 1.21.3 las de SALIDAS_QUE_SUPLE_EL_BUILD las pone el build
  (BuildOutputDefault) y solo la .hpp se sigue pidiendo. }
function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): TArray<string>;

{ La carpeta que el build usa para una salida que el proyecto no declara
  (SALIDAS_QUE_SUPLE_EL_BUILD): la del binario de ESE build (DCC_ExeOutput
  efectivo del .dproj; un .optset no cuenta, se importa con su condicion),
  que es donde el IDE deja tambien los .dcu de un proyecto nuevo, o
  IDE_OUTPUT_DEFAULT si tampoco la declara. Tag vacio: quien la pide pone el
  suyo. Value tal como se escribiria; Dir resuelta como las declaradas
  (BuildOutputDirs), '' si no se sabe resolver, y la puerta la rechaza igual.
  Nunca pisa un valor declarado: solo se pregunta por lo que falta. }
function BuildOutputDefault(const ADprojPath, APlatform, AConfig: string): TBuildOutputDir;

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
  Winapi.Windows, // WindowsEjecuta: que maquinas corre este Windows (el primero: no tapa a SysUtils)
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults, // TIStringComparer: las banderas del build por nombre, sin distinguir mayusculas
  Lsp.Texts,
  Lsp.Patch, // LeeTexto: la puerta de leer (el .dproj y sus Import, en la jaula)
  Lsp.Rutas, // RutaDesde: EL resolutor de una ruta leida de un fichero
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
  Base, Ult: Integer;
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
        Nuevo := Nuevo + Copy(AXml, Ult, T.Ini - Ult) + Escrito;
        Ult := T.Fin;
        Break;
      end;
  Nuevo := Nuevo + Copy(AXml, Ult, MaxInt);
  if not EnBase then
  begin
    if Base < 0 then
      Exit(False);
    // al FINAL del grupo base, donde pone el IDE una propiedad nueva
    // (AnadeAlGrupo; era al principio): el grupo, leido del texto ya
    // cambiado (los mismos grupos, en el mismo orden)
    AnadeAlGrupo(Nuevo, GruposDePropiedades(Nuevo)[Base], XmlElemento(ATag, AValor));
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

function TDprojInfo.Compilables: TArray<string>;
begin
  Result := nil;
  for var C in Configs do
    if not SameText(C, 'Base') then
      Result := Result + [C];
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
  if EsFuentePrincipal(Result) then
    Result := TPath.ChangeExtension(Result, '.dproj');
end;

function EsFuentePrincipal(const APath: string): Boolean;
begin
  Result := MatchText(TPath.GetExtension(APath), ['.dpr', '.dpk']);
end;

function EsProyectoOSuFuente(const APath: string): Boolean;
begin
  Result := SameText(TPath.GetExtension(APath), '.dproj') or EsFuentePrincipal(APath);
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

function ConfigDelBuild(const AInfo: TDprojInfo; const ARaw: string; out AConfig: string): string;
begin
  Result := '';
  AConfig := ARaw.Trim;
  var DeLaSeleccion := AConfig = '';
  if DeLaSeleccion then
    AConfig := AInfo.ConfigPorDefecto;
  // el nombre antes que la lista: con la lista vacia se aceptaba todo, y un
  // nombre que el proyecto declara no es por eso un nombre limpio
  if NombreDeConfigNoValido(AConfig) then
    Exit(MsgFmt(SR_BUILD_CONFIG_FMT, [AConfig]));
  // Base no es una configuracion que se compile: es de la que heredan las
  // demas, y el IDE no la deja activar (lo que se compila aqui se compila
  // igual en el IDE); compilaba con los ajustes de la base en Win64\Base\
  var Validas := AInfo.Compilables;
  if SameText(AConfig, 'Base') then
    Exit(MsgFmt(SR_CFG_BASE_NO_SE_COMPILA_FMT, [string.Join(', ', Validas)]));
  if Length(AInfo.Configs) = 0 then
    Exit;
  // con SU nombre: lo que teclea el agente solo elige
  for var C in Validas do
    if SameText(C, AConfig) then
    begin
      AConfig := C;
      Exit;
    end;
  if DeLaSeleccion then
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

function DprojIncompleto(const AXml: string): Boolean;
var
  Low: string;
begin
  // el raiz abre y no cierra (un upload cortado): por el escaner de etiquetas
  // de esta unidad, que solo da por elemento lo que cierra. Un texto sin
  // <Project> no es incompleto, es otra cosa (lo dira el cargador del IDE)
  Low := TextoDeBusqueda(AXml);
  Result := (Length(AperturasDe(Low, 'Project')) > 0) and
    (Length(TramosEnTexto(AXml, Low, 'Project')) = 0);
end;

function InfoDeDproj(const AXml: string): TDprojInfo;
var
  D: TDprojPlatform;
  T: TTramoXml;
begin
  Result := Default(TDprojInfo);
  Result.Incompleto := DprojIncompleto(AXml);
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

type
  TPlataformaConocida = record
    Nombre: string;
    Sistema: TSistemaDePlataforma;
    Maquina: Word; // IMAGE_FILE_MACHINE_* de un binario de Windows; 0 en el resto
    Abi: string;   // la carpeta library\lib\<abi> del .apk; '' fuera de Android
  end;

const
  { Las plataformas de Delphi y lo que es cada una. Son las mismas 13 que las
    claves Library del registro del IDE (medido el 18-oct-2026 en el HKCU del
    servicio, iOSDevice32/iOSSimulator incluidas), pero el registro no dice
    el sistema, la maquina ni el ABI: no hay juez que los diga, y esta es la
    UNA tabla que los dice (test_paisaje la vigila). Win64x y WinARM64EC son
    de Delphi: su lib\ trae .dcu. WinARM64EC es la maquina ARM64 (un binario
    ARM64EC solo corre en un Windows ARM64). }
  PLATAFORMAS: array [0 .. 12] of TPlataformaConocida = (
    (Nombre: 'Win32'; Sistema: spWindows; Maquina: $014C; Abi: ''),
    (Nombre: 'Win64'; Sistema: spWindows; Maquina: $8664; Abi: ''),
    (Nombre: 'Win64x'; Sistema: spWindows; Maquina: $8664; Abi: ''),
    (Nombre: 'WinARM64EC'; Sistema: spWindows; Maquina: $AA64; Abi: ''),
    (Nombre: 'OSX64'; Sistema: spMacOS; Maquina: 0; Abi: ''),
    (Nombre: 'OSXARM64'; Sistema: spMacOS; Maquina: 0; Abi: ''),
    (Nombre: 'Linux64'; Sistema: spLinux; Maquina: 0; Abi: ''),
    (Nombre: 'Android'; Sistema: spAndroid; Maquina: 0; Abi: 'armeabi-v7a'),
    (Nombre: 'Android64'; Sistema: spAndroid; Maquina: 0; Abi: 'arm64-v8a'),
    (Nombre: 'iOSDevice32'; Sistema: spIOS; Maquina: 0; Abi: ''),
    (Nombre: 'iOSDevice64'; Sistema: spIOS; Maquina: 0; Abi: ''),
    (Nombre: 'iOSSimARM64'; Sistema: spIOS; Maquina: 0; Abi: ''),
    (Nombre: 'iOSSimulator'; Sistema: spIOS; Maquina: 0; Abi: ''));

{ La fila de APlatform en PLATAFORMAS, sin mirar mayusculas. }
function DatosDePlataforma(const APlatform: string; out AFila: TPlataformaConocida): Boolean;
begin
  for var P in PLATAFORMAS do
    if SameText(P.Nombre, APlatform.Trim) then
    begin
      AFila := P;
      Exit(True);
    end;
  Result := False;
end;

function SistemaDePlataforma(const APlatform: string): TSistemaDePlataforma;
var
  P: TPlataformaConocida;
begin
  if DatosDePlataforma(APlatform, P) then
    Result := P.Sistema
  else
    Result := spDesconocido;
end;

function IsLocalPlatform(const APlatform: string): Boolean;
begin
  Result := SistemaDePlataforma(APlatform) = spWindows;
end;

function SistemaDelPAServer(const APlatform: string): TSistemaDePlataforma;
begin
  Result := SistemaDePlataforma(APlatform);
  case Result of
    spIOS: Result := spMacOS;
    spAndroid: Result := spDesconocido;
  end;
end;

{ Si este Windows ejecuta en modo usuario un binario de AMaquina. Lo dice
  GetMachineTypeAttributes (Windows 11 y Server 2022; medido aqui: I386 5,
  AMD64 3, ARM64 0); antes, IsWow64Process2 da la maquina nativa (Windows 10
  1709), y la x86 corre siempre por WOW64. }
function WindowsEjecuta(AMaquina: Word): Boolean;
type
  TGetMachineTypeAttributes = function(Machine: Word; out Attributes: DWORD): HRESULT; stdcall;
  TIsWow64Process2 = function(hProcess: THandle; out ProcessMachine, NativeMachine: Word): BOOL; stdcall;
const
  MAQUINA_I386 = $014C;
  MAQUINA_AMD64 = $8664;
  USER_ENABLED = 1;
var
  K: HMODULE;
  Atributos: TGetMachineTypeAttributes;
  Wow64: TIsWow64Process2;
  Dato: DWORD;
  Proceso, Nativa: Word;
begin
  K := GetModuleHandle(kernel32);
  @Atributos := GetProcAddress(K, 'GetMachineTypeAttributes');
  if Assigned(Atributos) then
    Exit(Succeeded(Atributos(AMaquina, Dato)) and (Dato and USER_ENABLED <> 0));
  @Wow64 := GetProcAddress(K, 'IsWow64Process2');
  if Assigned(Wow64) and Wow64(GetCurrentProcess, Proceso, Nativa) then
    Exit((AMaquina = Nativa) or (AMaquina = MAQUINA_I386));
  // un Windows anterior: el servidor es de 64 bits, asi que x64 (y x86)
  Result := (AMaquina = MAQUINA_AMD64) or (AMaquina = MAQUINA_I386);
end;

function CorreEnEstaMaquina(const APlatform: string): Boolean;
var
  P: TPlataformaConocida;
begin
  Result := DatosDePlataforma(APlatform, P) and (P.Sistema = spWindows) and
    WindowsEjecuta(P.Maquina);
end;

function PlataformasQueCorrenAqui: string;
begin
  Result := '';
  for var P in PLATAFORMAS do
    if CorreEnEstaMaquina(P.Nombre) then
      Result := Result + IfThen(Result <> '', ', ') + P.Nombre;
end;

function ExtensionDeEjecutable(const APlatform: string): string;
begin
  case SistemaDePlataforma(APlatform) of
    spWindows: Result := '.exe';
    spAndroid: Result := '.so';
  else
    Result := '';
  end;
end;

function LibreriaDelApk(const AProyecto: string): string;
begin
  Result := 'lib' + AProyecto + '.so';
end;

function CarpetaDeLibreriasDelApk(const APlatform: string): string;
var
  P: TPlataformaConocida;
begin
  Result := '';
  if DatosDePlataforma(APlatform, P) and (P.Abi <> '') then
    Result := 'library\lib\' + P.Abi + '\';
end;

const
  // MSBuild tasks whose presence turns a build into arbitrary execution or an
  // out-of-tree file write. Desde la 1.21.2 la puerta es la LISTA BLANCA de
  // abajo (ElementoNoAdmitido): esta lista queda de segunda barrera (tambien
  // dentro de un comentario) y para nombrar el porque de una tarea conocida;
  // cualquiera de ellas needs AllowBuildScripts en su workspace. Local names,
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

  { LISTA BLANCA del build compile-only (1.21.2, ElementoNoAdmitido): lo que
    puede haber bajo <Project> y dentro de un <Target>; dentro de una tarea
    admitida, solo <Output>; lo demas se niega por su nombre. Nombres
    locales, en minusculas. OPACOS: lo de dentro no se mira - un
    PropertyGroup/ItemGroup lleva propiedades, items y metadatos (texto para
    msbuild, aunque se llamen Exec) y ProjectExtensions lo ignora msbuild. }
  ELEMENTOS_DE_PROJECT: array [0 .. 4] of string =
    ('propertygroup', 'itemgroup', 'import', 'projectextensions', 'target');
  ELEMENTOS_DE_TARGET: array [0 .. 6] of string =
    ('message', 'warning', 'error', 'calltarget', 'onerror', 'propertygroup', 'itemgroup');
  ELEMENTOS_OPACOS: array [0 .. 2] of string =
    ('propertygroup', 'itemgroup', 'projectextensions');
  { Los eventos de build de RAD Studio: un texto de shell, que el runner
    vacia (BUILD-018) y HazardScan juzga; no son rutas (ValoresQueLeeElBuild
    los salta). En minusculas, como el texto de busqueda. }
  EVENTOS_DE_BUILD: array [0 .. 4] of string =
    ('prebuildevent', 'postbuildevent', 'prelinkevent', 'postlinkevent', 'buildevent');
  { Opciones LIBRES al compilador: su texto va tal cual a la linea de
    ordenes de dcc/brcc32 (CodeGear.Delphi.Targets), y un texto libre no se
    juzga: HazardScan las niega si no estan vacias. }
  OPCIONES_LIBRES: array [0 .. 2] of string =
    ('DCC_AdditionalSwitches', 'BRCC_UserSuppliedOptions', 'BRCC_ResponseFilename');

function EsTextoLibreDelBuild(const ANombre: string): Boolean;
begin
  Result := MatchText(ANombre.Trim, EVENTOS_DE_BUILD) or MatchText(ANombre.Trim, OPCIONES_LIBRES);
end;

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
  Result := '';
  for var P in PLATAFORMAS do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + P.Nombre;
  end;
end;

function CanonicalPlatform(const AName: string): string;
var
  P: TPlataformaConocida;
begin
  Result := '';
  if DatosDePlataforma(AName, P) then
    Result := P.Nombre; // canonical casing, and proven metachar-free
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

function XmlGrupoDefinidorDeConfig(const AConfig, AClave: string): string;
begin
  Result := '    <PropertyGroup ' + XmlAtributo('Condition', ConfigDefinerCondition(AConfig, AClave)) + '>' + sLineBreak;
  if not SameText(AClave, 'Base') then
    Result := Result + '        ' + XmlElemento(AClave, 'true') + sLineBreak +
      '        ' + XmlElemento('CfgParent', 'Base') + sLineBreak;
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

function EsGrupoDeClave(const ACondicion, AClave: string; ADefinidor: Boolean;
  out APlataforma: string): Boolean; forward;

function PlataformaDeGrupo(const ACondicion: string; ADefinidor: Boolean): string;
begin
  // la inversa del nombrador, por LA inversa de las claves (EsGrupoDeClave,
  // con la de Base): era una segunda inversa, con el literal '$(Base_' dentro
  // (revisor del 21-oct-2026)
  if not EsGrupoDeClave(ACondicion, 'Base', ADefinidor, Result) then
    Result := '';
end;

{ Un nombre de propiedad dentro de un $(...): letras, digitos y _ (lo demas
  -una funcion de propiedad, un registro- no se resuelve). }
function EsNombreDeMacro(const ANombre: string): Boolean;
begin
  Result := ANombre <> '';
  for var C in ANombre do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Exit(False);
end;

{ AValor con sus $(X) resueltos de izquierda a derecha y UNA sola vez, como
  msbuild expande un valor al definirlo y la cadena de una Condition al
  evaluarla (lo que entra expandido no se vuelve a expandir): Config y
  Platform valen lo pedido, las demas lo que diga ABusca. ADuda queda con el
  nombre del primer macro que no se sabe ('' si ninguno). Para una Condition
  (AParaValor False) no se sabe una dudosa, una desconocida ni una sabida
  con un $( sin resolver dentro: no se pueden comparar. Para un VALOR que el
  build lee (AParaValor True) solo no se sabe una dudosa (puesta por un grupo
  que no se sabe si se aplica, o una global del build); una desconocida (la
  tabla del build, el entorno, otro documento, lo que nadie define) se deja
  escrita como $(X) para que la expanda quien la sabe (la puerta del build,
  con su tabla). False si algo no se resuelve (una funcion de propiedad, un
  item @(, un metadato %(, un macro sin cerrar). }
function ExpandeMacrosDelBuild(var AValor: string; const APlatform, AConfig: string;
  ABusca: TBuscaBandera; var ADuda: string; AParaValor: Boolean = False): Boolean;
var
  A, B: Integer;
  Nombre, V: string;
  Bandera: TBanderaDelBuild;
begin
  Result := False;
  A := Pos('$(', AValor);
  while A > 0 do
  begin
    B := Pos(')', AValor, A + 2);
    if B = 0 then
      Exit;
    Nombre := Copy(AValor, A + 2, B - A - 2).Trim;
    if not EsNombreDeMacro(Nombre) then
      Exit;
    if SameText(Nombre, 'Config') then
      V := AConfig
    else if SameText(Nombre, 'Platform') then
      V := APlatform
    else
    begin
      Bandera := ABusca(Nombre);
      V := Bandera.Valor;
      if AParaValor and (Bandera.Estado = eDesconocida) then
        V := Copy(AValor, A, B - A + 1) // se deja escrito tal cual
      else if (Bandera.Estado <> eSabida) or (not AParaValor and (Pos('$(', V) > 0)) then
        if ADuda = '' then
          ADuda := Nombre;
    end;
    AValor := Copy(AValor, 1, A - 1) + V + Copy(AValor, B + 1, MaxInt);
    A := Pos('$(', AValor, A + Length(V));
  end;
  Result := (Pos('@(', AValor) = 0) and (Pos('%(', AValor) = 0);
end;

{ Los %XX de una cadena de msbuild (dos hexadecimales) como el caracter que
  nombran: msbuild desescapa la cadena de una Condition tras expandirla
  (medido el 21-oct-2026: '%74rue'=='true'). }
function DesescapaDeMsbuild(const S: string): string;

  function Hex(C: Char): Boolean;
  begin
    Result := CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']);
  end;

var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and Hex(S[I + 1]) and Hex(S[I + 2]) then
    begin
      Result := Result + Char(StrToInt('$' + Copy(S, I + 1, 2)));
      Inc(I, 3);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

{ Lo que msbuild toma por numero en una comparacion: decimal con signo y
  punto, sin exponente ni blancos, o hexadecimal 0x (medido el 21-oct-2026
  con el msbuild 4.8 del IDE: '1.0', '+1', '1.', '.5' y '0X1' son numeros;
  ' 1 ', '1e3' y 'abc' no). }
function NumeroDeMsbuild(const S: string; out AValor: Double): Boolean;
var
  I: Int64;
  Cuerpo, Entera, Decimal: string;
  Punto: Integer;
begin
  Result := False;
  if S.StartsWith('0x', True) then
  begin
    Cuerpo := S.Substring(2);
    if Cuerpo = '' then
      Exit;
    for var C in Cuerpo do
      if not CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']) then
        Exit;
    Result := TryStrToInt64('$' + Cuerpo, I);
    if Result then
      AValor := I;
    Exit;
  end;
  Cuerpo := S;
  if (Cuerpo <> '') and CharInSet(Cuerpo[1], ['+', '-']) then
    Cuerpo := Cuerpo.Substring(1);
  if Cuerpo = '' then
    Exit;
  for var C in Cuerpo do
    if not CharInSet(C, ['0'..'9', '.']) then
      Exit;
  Punto := Pos('.', Cuerpo);
  if Punto > 0 then
  begin
    Entera := Copy(Cuerpo, 1, Punto - 1);
    Decimal := Copy(Cuerpo, Punto + 1, MaxInt);
    if Pos('.', Decimal) > 0 then
      Exit;
  end
  else
  begin
    Entera := Cuerpo;
    Decimal := '';
  end;
  if (Entera = '') and (Decimal = '') then
    Exit;
  if Entera = '' then
    Entera := '0';
  if Decimal = '' then
    Decimal := '0';
  Result := TryStrToFloat(Entera + '.' + Decimal, AValor, TFormatSettings.Invariant);
  if Result and (S[1] = '-') then
    AValor := -AValor;
end;

{ Lo que msbuild toma por booleano: true/on/yes y !false/!off/!no, false/off/
  no y !true/!on/!yes, sin distinguir mayusculas (medido el 21-oct-2026);
  un numero no es un booleano ('true'=='1' es falso). }
function BooleanoDeMsbuild(const S: string; out AValor: Boolean): Boolean;
begin
  Result := True;
  if MatchText(S, ['true', 'on', 'yes', '!false', '!off', '!no']) then
    AValor := True
  else if MatchText(S, ['false', 'off', 'no', '!true', '!on', '!yes']) then
    AValor := False
  else
    Result := False;
end;

{ 'a'=='b' como lo decide msbuild: los dos numeros, como numeros; si no, los
  dos booleanos, como booleanos; si no, texto sin distinguir mayusculas
  (medido el 21-oct-2026 con el msbuild del IDE: 'yes'=='true', '1.0'=='1',
  '0x1'=='1' y 'TRUE'=='yes' son ciertas; 'abc'=='1.0' y 'true'=='1' no). }
function IgualesComoMsbuild(const A, B: string): Boolean;
var
  NA, NB: Double;
  BA, BB: Boolean;
begin
  if NumeroDeMsbuild(A, NA) and NumeroDeMsbuild(B, NB) then
    Exit(NA = NB);
  if BooleanoDeMsbuild(A, BA) and BooleanoDeMsbuild(B, BB) then
    Exit(BA = BB);
  Result := SameText(A, B);
end;

{ Un elemento de un PropertyGroup que cuelga de la raiz: lo que msbuild
  evalua en la pasada de propiedades. Uno dentro de un Target solo cuenta al
  ejecutarlo y uno en ProjectExtensions nunca (medido el 21-oct-2026): ni
  ponen banderas ni los lee el lector. }
function EsDeGrupoDeLaRaiz(const AElemento: TElementoXml): Boolean;
begin
  Result := (Length(AElemento.Ruta) = 2) and (AElemento.Ruta[1] = 'propertygroup');
end;

function PropiedadesDefinidas(const AElementos: TArray<TElementoXml>): TArray<string>;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.CaseSensitive := False;
    for var E in AElementos do
      if EsDeGrupoDeLaRaiz(E) and (L.IndexOf(E.Escrito) < 0) then
        L.Add(E.Escrito);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function EvaluaCondicion(const ACondicion, APlatform, AConfig: string;
  ABusca: TBuscaBandera): TVeredicto;
var
  S: string;
  P: Integer;
  Duda: string; // el primer macro dudoso o desconocido de la comparacion en curso ('' si ninguno)

  procedure SaltaBlancos;
  begin
    while (P <= Length(S)) and (S[P] <= ' ') do
      Inc(P);
  end;

  // la palabra APalabra en P, seguida de blanco, parentesis o comilla
  function EsPalabra(const APalabra: string): Boolean;
  var
    N: Integer;
  begin
    N := Length(APalabra);
    Result := SameText(Copy(S, P, N), APalabra) and
      ((P + N > Length(S)) or (S[P + N] <= ' ') or CharInSet(S[P + N], ['(', '''']));
  end;

  function Palabra(const APalabra: string): Boolean;
  begin
    Result := EsPalabra(APalabra);
    if Result then
      Inc(P, Length(APalabra));
  end;

  // lo que no se entiende se salta hasta el siguiente and / or / ')' de este
  // nivel (o el final), para que el resto de la condicion cuente igual
  procedure SaltaDesconocido;
  var
    Nivel: Integer;
    EnComillas: Boolean;
  begin
    Nivel := 0;
    EnComillas := False;
    while P <= Length(S) do
    begin
      if S[P] = '''' then
        EnComillas := not EnComillas
      else if not EnComillas then
      begin
        if S[P] = '(' then
          Inc(Nivel)
        else if S[P] = ')' then
        begin
          if Nivel = 0 then
            Exit;
          Dec(Nivel);
        end
        else if (Nivel = 0) and (P > 1) and (S[P - 1] <= ' ') and
                (EsPalabra('and') or EsPalabra('or')) then
          Exit;
      end;
      Inc(P);
    end;
  end;

  // la cadena entre comillas simples que empieza en P, con sus $(X) resueltos
  // UNA vez (ExpandeMacrosDelBuild, lo mismo que al fijar un valor: Config y
  // Platform valen lo pedido, las demas lo que diga ABusca, y una dudosa o
  // desconocida deja la comparacion en no se sabe) y desescapada despues,
  // como msbuild ('%74rue' es 'true'). False si no hay cadena o lleva algo
  // que no se resuelve (una funcion de propiedad, un item, un metadato, un
  // macro sin cerrar)
  function Cadena(out AValor: string): Boolean;
  var
    Q: Integer;
  begin
    Result := False;
    SaltaBlancos;
    if (P > Length(S)) or (S[P] <> '''') then
      Exit;
    Q := Pos('''', S, P + 1);
    if Q = 0 then
      Exit;
    AValor := Copy(S, P + 1, Q - P - 1);
    P := Q + 1;
    Result := ExpandeMacrosDelBuild(AValor, APlatform, AConfig, ABusca, Duda);
    if Result then
      AValor := DesescapaDeMsbuild(AValor);
  end;

  function Expresion: TVeredicto; forward;

  // '(' expresion ')' o una comparacion 'a' == 'b' / 'a' != 'b'; msbuild
  // compara sin distinguir mayusculas
  function Comparacion: TVeredicto;
  var
    Izq, Der, Op: string;
  begin
    Result := vNoSeSabe;
    SaltaBlancos;
    if (P <= Length(S)) and (S[P] = '(') then
    begin
      Inc(P);
      Result := Expresion;
      SaltaBlancos;
      if (P <= Length(S)) and (S[P] = ')') then
        Inc(P)
      else
        Result := vNoSeSabe;
      Exit;
    end;
    Duda := '';
    if not Cadena(Izq) then
    begin
      SaltaDesconocido;
      Exit;
    end;
    SaltaBlancos;
    Op := Copy(S, P, 2);
    if (Op <> '==') and (Op <> '!=') then
    begin
      SaltaDesconocido;
      Exit;
    end;
    Inc(P, 2);
    if not Cadena(Der) then
    begin
      SaltaDesconocido;
      Exit;
    end;
    if Duda <> '' then
      Exit; // compara una propiedad dudosa o desconocida: no se sabe
    if IgualesComoMsbuild(Izq, Der) = (Op = '==') then
      Result := vSi
    else
      Result := vNo;
  end;

  // comparaciones unidas por and: falso con cualquier cosa es falso, y lo que
  // no se sabe mancha lo demas
  function Termino: TVeredicto;
  var
    Sig: TVeredicto;
  begin
    Result := Comparacion;
    SaltaBlancos;
    while Palabra('and') do
    begin
      Sig := Comparacion;
      if (Result = vNo) or (Sig = vNo) then
        Result := vNo
      else if (Result = vNoSeSabe) or (Sig = vNoSeSabe) then
        Result := vNoSeSabe;
      SaltaBlancos;
    end;
  end;

  // terminos unidos por or: cierto con cualquier cosa es cierto
  function Expresion: TVeredicto;
  var
    Sig: TVeredicto;
  begin
    Result := Termino;
    SaltaBlancos;
    while Palabra('or') do
    begin
      Sig := Termino;
      if (Result = vSi) or (Sig = vSi) then
        Result := vSi
      else if (Result = vNoSeSabe) or (Sig = vNoSeSabe) then
        Result := vNoSeSabe;
      SaltaBlancos;
    end;
  end;

begin
  S := ACondicion;
  P := 1;
  Duda := '';
  if S.Trim = '' then
    Exit(vSi);
  Result := Expresion;
  SaltaBlancos;
  if P <= Length(S) then
    Result := vNoSeSabe; // algo que no se ha entendido
end;

function VeredictosDeElementos(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>): TArray<TVeredicto>;
var
  Expandidos, Dudosos: TArray<string>;
begin
  Result := VeredictosDeElementos(AXml, APlatform, AConfig, AElementos, AExternas, AGlobales,
    Expandidos, Dudosos);
end;

function VeredictosDeElementos(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>;
  out AExpandidos, ADudosos: TArray<string>): TArray<TVeredicto>;
var
  Banderas: TDictionary<string, string>;
  Dudosas, Definidas: TStringList;
  Hecho: TArray<Boolean>; // ya expandido en su punto
  Grupo, Elemento: TVeredicto;
  V, Dudoso: string;
  Resuelto: Boolean;
  D: Integer;
  Busca: TBuscaBandera;

  // el valor de AElementos[I] (el texto de una propiedad, el Include de un
  // item) expandido con lo puesto hasta ahora, para quien lo lee
  procedure Expande(I: Integer; const AValor: string);
  begin
    V := AValor;
    Dudoso := '';
    Resuelto := ExpandeMacrosDelBuild(V, APlatform, AConfig, Busca, Dudoso, True);
    AExpandidos[I] := V;
    ADudosos[I] := Dudoso;
    Hecho[I] := True;
  end;

begin
  SetLength(Result, Length(AElementos));
  SetLength(AExpandidos, Length(AElementos));
  SetLength(ADudosos, Length(AElementos));
  SetLength(Hecho, Length(AElementos));
  // lo que no esta en un PropertyGroup no es de otro build
  for var I := 0 to High(Result) do
    Result[I] := vSi;
  // las puestas, por nombre sin distinguir mayusculas y con su valor aunque
  // sea vacio (un TStringList borra la pareja al poner '', y una <X></X>
  // no dejaba a X vacia sino con lo del entorno)
  Banderas := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  Dudosas := TStringList.Create;
  Definidas := TStringList.Create;
  try
    Dudosas.CaseSensitive := False;
    Definidas.CaseSensitive := False;
    // lo que el documento define en algun PropertyGroup de la raiz: una de
    // esas, aun no puesta, vale '' (como en msbuild); un nombre que no define
    // nadie puede venir de fuera (el entorno, rsvars, el IDE) y no se da por
    // vacio
    Definidas.AddStrings(PropiedadesDefinidas(AElementos));
    Busca := function(const ANombre: string): TBanderaDelBuild
      begin
        Result.Valor := '';
        // una GLOBAL del build (/p:) gana a lo que el documento ponga, aun
        // definida despues (medido el 21-oct-2026), y su valor no se sabe aqui
        if MatchText(ANombre, AGlobales) or (Dudosas.IndexOf(ANombre) >= 0) then
          Result.Estado := eDudosa
        else if Banderas.TryGetValue(ANombre, Result.Valor) then
          Result.Estado := eSabida
        else if MatchText(ANombre, AExternas) or (GetEnvironmentVariable(ANombre) <> '') then
          Result.Estado := eDesconocida
        else if Definidas.IndexOf(ANombre) >= 0 then
          Result.Estado := eSabida
        else
          Result.Estado := eDesconocida;
      end;
    for var G in GruposDePropiedades(AXml) do
    begin
      Grupo := EvaluaCondicion(G.Condicion, APlatform, AConfig, Busca);
      for var I := 0 to High(AElementos) do
      begin
        var E := AElementos[I];
        // solo lo de un PropertyGroup de la raiz: uno dentro de un Target o
        // de ProjectExtensions no entra en la pasada de msbuild (revisor E)
        if (E.Tramo.Abre < G.Ini) or (E.Tramo.Cierra > G.Fin) or not EsDeGrupoDeLaRaiz(E) then
          Continue;
        if Grupo = vNo then
        begin
          Result[I] := vNo;
          Hecho[I] := True; // de otro build: no se lee
          Continue;
        end;
        Elemento := EvaluaCondicion(AtributoDeTramo(AXml, E.Tramo, E.Escrito, 'Condition'),
          APlatform, AConfig, Busca);
        if Elemento = vNo then
        begin
          Result[I] := vNo;
          Hecho[I] := True;
          Continue;
        end;
        // EXPANDIDO en su punto, como msbuild fija un valor al definirlo: un
        // <Tarde>$(Antes)</Tarde> vale lo que Antes valia entonces, no lo
        // que valga despues (medido el 21-oct-2026); y asi lo lee la puerta
        // del build (22-oct-2026: expandia con otro valor)
        Expande(I, ValorDeTramo(AXml, E.Tramo).Trim);
        // lo que deja puesto para los siguientes: seguro si el grupo y el
        // elemento son ciertos (el ultimo gana, como en msbuild) y el valor
        // se resolvio sin dudas; dudoso si alguno no se sabe
        D := Dudosas.IndexOf(E.Escrito);
        if (Grupo = vSi) and (Elemento = vSi) then
        begin
          Result[I] := vSi;
          if Resuelto and (Dudoso = '') then
          begin
            Banderas.AddOrSetValue(E.Escrito, V);
            if D >= 0 then
              Dudosas.Delete(D);
          end
          else if D < 0 then
            Dudosas.Add(E.Escrito);
        end
        else
        begin
          Result[I] := vNoSeSabe;
          if D < 0 then
            Dudosas.Add(E.Escrito);
        end;
      end;
    end;
    // lo demas que el build lee, con lo que las propiedades valen AL FINAL:
    // el Include de un item (msbuild evalua los items despues de todas las
    // propiedades) y una propiedad fuera de la pasada (la de un Target, que
    // se juzga por prudencia)
    for var I := 0 to High(AElementos) do
      if not Hecho[I] and (Length(AElementos[I].Ruta) > 0) then
      begin
        var Padre := AElementos[I].Ruta[High(AElementos[I].Ruta)];
        if Padre = 'propertygroup' then
          Expande(I, ValorDeTramo(AXml, AElementos[I].Tramo).Trim)
        else if Padre = 'itemgroup' then
          for var At in AtributosDeTramo(AXml, AElementos[I].Tramo) do
            if SameText(At.Nombre, 'Include') then
              Expande(I, ValorDeAtributo(AXml, At).Trim);
      end;
  finally
    Definidas.Free;
    Dudosas.Free;
    Banderas.Free;
  end;
end;

function ElementosDeOtroBuild(const AXml, APlatform, AConfig: string;
  const AElementos: TArray<TElementoXml>; const AExternas, AGlobales: TArray<string>): TArray<Boolean>;
var
  V: TArray<TVeredicto>;
begin
  // de otro build = su Condition o la de su grupo es FALSA; lo que no se
  // sabe se juzga (una de mas es prudencia)
  V := VeredictosDeElementos(AXml, APlatform, AConfig, AElementos, AExternas, AGlobales);
  SetLength(Result, Length(V));
  for var I := 0 to High(V) do
    Result[I] := V[I] = vNo;
end;

function TrozosDeLista(const AValor: string): TArray<string>;
begin
  Result := [];
  for var T in AValor.Split([';']) do
    if T.Trim <> '' then
      Result := Result + [T.Trim];
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

function XmlGrupoDeDespliegue(const ACondicion, AEntradas: string): string;
begin
  // sin entradas, el que el IDE escribe para cada plataforma: auto-cerrado
  // (lo que deja remove-deployfile al vaciarlo; Fable, revision de la 1.22.2)
  if AEntradas = '' then
    Exit('<ItemGroup ' + XmlAtributo('Condition', ACondicion) + '/>');
  Result := '<ItemGroup ' + XmlAtributo('Condition', ACondicion) + '>' + sLineBreak +
    AEntradas + '    </ItemGroup>';
end;

function ConEntradasEnSuGrupo(const AXml, APlataforma, AEntradas: string): string;
var
  Hueco, Suyo: TGrupoXml;
  HayHueco, HaySuyo: Boolean;
begin
  var Cond := DeployGroupCondition(APlataforma);
  // el grupo de la plataforma: el vacio que el IDE deja escrito, o el que
  // tiene otros ficheros
  HayHueco := False;
  HaySuyo := False;
  for var G in GruposDe(AXml, 'ItemGroup', True) do
    if CondicionNormalizada(G.Condicion) = CondicionNormalizada(Cond) then
      if G.Vacio and not HayHueco then
      begin
        Hueco := G;
        HayHueco := True;
      end
      else if not G.Vacio and not HaySuyo then
      begin
        Suyo := G;
        HaySuyo := True;
      end;
  // el vacio se llena (la sangria ya esta delante del hueco)
  if HayHueco then
    Exit(Copy(AXml, 1, Hueco.Abre - 1) + XmlGrupoDeDespliegue(Cond, AEntradas) +
      Copy(AXml, Hueco.Cierra, MaxInt));
  // en uno con otros ficheros, al principio
  if HaySuyo then
    Exit(Copy(AXml, 1, Suyo.Ini - 1) + #13#10 + AEntradas +
      Copy(AXml, Suyo.Ini, MaxInt).TrimLeft([#13, #10]));
  // sin grupo, uno nuevo al final
  var P := CierreDelProyecto(AXml);
  if P = 0 then
    Exit('');
  Result := Copy(AXml, 1, P - 1) + '    ' + XmlGrupoDeDespliegue(Cond, AEntradas) + #13#10 +
    Copy(AXml, P, MaxInt);
end;

const
  // la pseudo plataforma del Deployment Manager (los valores de todas): en
  // ella no se despliega
  TODAS_LAS_PLATAFORMAS = 'All Platforms';

function DesplieguesDelProyecto(const AXml: string): TArray<TDespliegueDelProyecto>;
begin
  Result := [];
  // las <Platform> del documento una vez (las de <Platforms> no estan dentro
  // de ninguna <DeployFile>)
  var Todas := TramosDeEtiqueta(AXml, 'Platform');
  for var Dep in TramosDeEtiqueta(AXml, 'Deployment') do
    for var E in TramosDentro(AXml, 'DeployFile', Dep) do
    begin
      var Suyas: TArray<TTramoXml> := [];
      for var P in Todas do
        if (P.Abre >= E.Ini) and (P.Cierra <= E.Fin) and
           not SameText(AtributoDeTramo(AXml, P, 'Platform', 'Name').Trim, TODAS_LAS_PLATAFORMAS) and
           (AtributoDeTramo(AXml, P, 'Platform', 'Name').Trim <> '') then
          Suyas := Suyas + [P];
      for var P in Suyas do
      begin
        var D := Default(TDespliegueDelProyecto);
        D.LocalName := AtributoDeTramo(AXml, E, 'DeployFile', 'LocalName');
        D.Config := AtributoDeTramo(AXml, E, 'DeployFile', 'Configuration');
        D.Clase := AtributoDeTramo(AXml, E, 'DeployFile', 'Class');
        D.Plataforma := AtributoDeTramo(AXml, P, 'Platform', 'Name').Trim;
        D.RemoteDir := ValorDentro(AXml, 'RemoteDir', P);
        D.RemoteName := ValorDentro(AXml, 'RemoteName', P);
        D.Entrada := E;
        D.Plat := P;
        D.Plataformas := Length(Suyas);
        Result := Result + [D];
      end;
    end;
end;

function XmlDeployFileDelProyecto(const ALocalName, AConfig, AClase, APlataforma,
  ARemoteDir, ARemoteName, ASangria: string): string;
begin
  Result := ASangria + '<DeployFile ' + XmlAtributo('LocalName', ALocalName) + ' ' +
    XmlAtributo('Configuration', AConfig) + ' ' + XmlAtributo('Class', AClase) + '>' + sLineBreak +
    ASangria + '    <Platform ' + XmlAtributo('Name', APlataforma) + '>' + sLineBreak;
  if ARemoteDir <> '' then
    Result := Result + ASangria + '        ' + XmlElemento('RemoteDir', ARemoteDir) + sLineBreak;
  Result := Result + ASangria + '        ' + XmlElemento('RemoteName', ARemoteName) + sLineBreak +
    ASangria + '        ' + XmlElemento('Overwrite', 'true') + sLineBreak +
    ASangria + '    </Platform>' + sLineBreak +
    ASangria + '</DeployFile>';
end;

function ConDespliegueDelProyecto(const AXml, ALocalName, AConfig, AClase, APlataforma,
  ARemoteDir, ARemoteName: string; out AXmlNuevo: string): Boolean;
var
  Desde, Hasta: Integer;
begin
  AXmlNuevo := AXml;
  var Borland := TramosDeEtiqueta(AXml, 'BorlandProject');
  if Length(Borland) = 0 then
    Exit(False);
  var Deps := TramosDentro(AXml, 'Deployment', Borland[0], True);
  // sin seccion (un .dproj de delphi_create): al final de <BorlandProject>,
  // con la sangria de sus hijos
  if Length(Deps) = 0 then
  begin
    ConSuLinea(AXml, Borland[0].Fin, Borland[0].Cierra, Desde, Hasta);
    var S := SangriaDeLaLineaEn(AXml, Borland[0].Fin) + '    ';
    AXmlNuevo := Copy(AXml, 1, Desde - 1) + S + '<Deployment Version="5">' + sLineBreak +
      XmlDeployFileDelProyecto(ALocalName, AConfig, AClase, APlataforma, ARemoteDir, ARemoteName,
        S + '    ') + sLineBreak + S + '</Deployment>' + sLineBreak + Copy(AXml, Desde, MaxInt);
    Exit(True);
  end;
  var Dep := Deps[0];
  if Dep.Vacio then
  begin
    var S := SangriaDeLaLineaEn(AXml, Dep.Abre);
    AXmlNuevo := Copy(AXml, 1, Dep.Abre - 1) + '<Deployment Version="5">' + sLineBreak +
      XmlDeployFileDelProyecto(ALocalName, AConfig, AClase, APlataforma, ARemoteDir, ARemoteName,
        S + '    ') + sLineBreak + S + '</Deployment>' + Copy(AXml, Dep.Cierra, MaxInt);
    Exit(True);
  end;
  var Entradas := TramosDentro(AXml, 'DeployFile', Dep, True);
  var Sangria := SangriaDeLaLineaEn(AXml, Dep.Abre) + '    ';
  if Length(Entradas) > 0 then
    Sangria := SangriaDeLaLineaEn(AXml, Entradas[0].Abre);
  var Bloque := XmlDeployFileDelProyecto(ALocalName, AConfig, AClase, APlataforma, ARemoteDir,
    ARemoteName, Sangria);
  // delante de la primera que va detras por su LocalName: el IDE las ordena
  // por el, ordinal ('..\fuera' 'Linux64\..' 'N:\..' 'datos\..', medido)
  for var E in Entradas do
    if CompareStr(AtributoDeTramo(AXml, E, 'DeployFile', 'LocalName'), ALocalName) > 0 then
    begin
      ConSuLinea(AXml, E.Abre, E.Cierra, Desde, Hasta);
      AXmlNuevo := Copy(AXml, 1, Desde - 1) + Bloque + sLineBreak + Copy(AXml, Desde, MaxInt);
      Exit(True);
    end;
  // ...o detras de la ultima; o, la primera, tras la apertura de la seccion
  var Tras := Dep.Ini;
  if Length(Entradas) > 0 then
    Tras := Entradas[High(Entradas)].Cierra;
  AXmlNuevo := Copy(AXml, 1, Tras - 1) + sLineBreak + Bloque + Copy(AXml, Tras, MaxInt);
  Result := True;
end;

function DestinoDeDespliegue(const AXml, AProyecto, APlataforma, AClase, ARemoteDir: string): string;
var
  Sub: string;
begin
  // la raiz del proyecto en la plataforma
  Result := AProyecto;
  for var T in TramosDeEtiqueta(AXml, 'ProjectRoot', True) do
    if SameText(AtributoDeTramo(AXml, T, 'ProjectRoot', 'Platform').Trim, APlataforma) then
    begin
      Result := StringReplace(AtributoDeTramo(AXml, T, 'ProjectRoot', 'Name').Trim, '$(PROJECTNAME)',
        AProyecto, [rfIgnoreCase]);
      Break;
    end;
  // la carpeta de la entrada o, sin ella, la de su clase en esa plataforma
  Sub := ARemoteDir.Trim;
  if Sub = '' then
    for var C in TramosDeEtiqueta(AXml, 'DeployClass') do
      if SameText(AtributoDeTramo(AXml, C, 'DeployClass', 'Name').Trim, AClase) then
        for var P in TramosDentro(AXml, 'Platform', C) do
          if SameText(AtributoDeTramo(AXml, P, 'Platform', 'Name').Trim, APlataforma) then
            Sub := ValorDentro(AXml, 'RemoteDir', P);
  if Sub.StartsWith('.\') then
    Sub := Sub.Substring(2)
  else if Sub = '.' then
    Sub := '';
  Result := IncludeTrailingPathDelimiter(Result);
  if Sub <> '' then
    Result := IncludeTrailingPathDelimiter(Result + Sub);
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

function EntradasDelManifiesto(const AXml: string): TArray<TEntradaDelManifiesto>;
var
  E: TEntradaDelManifiesto;
begin
  Result := [];
  for var G in GruposDe(AXml, 'ItemGroup') do
  begin
    E.Grupo := G;
    E.Plataforma := PlataformaDeGrupoDeDespliegue(G.Condicion);
    for var T in TramosEnGrupo(AXml, 'DeployFile', G, True) do
    begin
      E.Tramo := T;
      Result := Result + [E];
    end;
  end;
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
  Carpeta: string;
begin
  Result := [];
  // la carpeta en la que corre msbuild: desde ella se lee cada trozo
  Carpeta := '';
  try
    Carpeta := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  except
    // una ruta de .dproj que no parsea: sin carpeta, EL resolutor solo
    // resuelve lo completo
  end;
  // por EL troceador de las listas del proyecto (TrozosDeLista): era un
  // Split a pelo, gemelo suyo (revisor del 21-oct-2026)
  for var V in AllTagValues(AXml, 'DCC_UnitSearchPath') do
    for var Seg in TrozosDeLista(V) do
    begin
      R.Escrita := Seg;
      if R.Escrita.Contains('$(') then
        Continue;
      R.Carpeta := RutaDesde(Carpeta, R.Escrita); // '' si no se resuelve
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
  carries a macro we cannot resolve (which the caller then refuses).
  ACarpetaDelBuild: la del .dproj que se compila, en la que corre msbuild: un
  "\x" o un "X:y" se lee desde ella aunque lo escriba un Import de otra
  carpeta; lo relativo, desde la del fichero que lo escribe. }
function ResolveImportPath(const APath, AProjectFile, ACarpetaDelBuild: string): string;
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
  // como lo lee msbuild (EL resolutor): se juzgaba en la unidad del PROCESO
  // del servidor (A9b de la 1.23, medido)
  Result := RutaDesde(Dir, Result, ACarpetaDelBuild);
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

{ Un valor de salida YA expandido (ACand, de ExpandOutputMacros), resuelto a
  carpeta real contra la del proyecto; '' si no se puede comprobar: una macro
  sin resolver, un escape de MSBuild (%3A), una entidad numerica (&#58;) o un
  CDATA (AEscrito, el tramo tal cual) los leeria msbuild distinto que
  nosotros, y lo que no se puede comprobar no se aprueba (el lector lee ya el
  CDATA como XML, 17-oct-2026, y aqui se sigue sin aprobar lo que no esta
  escrito tal cual: la segunda barrera se queda). UNA copia: BuildOutputDirs
  (lo declarado) y BuildOutputDefault (lo suplido). }
function ResuelveSalida(const ACand, AValue, AEscrito, ADir: string): string;
begin
  Result := '';
  if ACand.Contains('$(') or ACand.Contains('@(') or ACand.Contains('%') or
     AValue.Contains('&#') or ACand.Contains('<') or AEscrito.Contains('<') then
    Exit;
  // donde la deja msbuild, que corre en ADir (EL resolutor): se juzgaba en la
  // unidad del PROCESO del servidor (A9b de la 1.23, medido)
  Result := RutaDesde(ADir, ACand);
end;

{ ProjectXmlChain: EL lector, con los ficheros; la forma sin ellos, debajo. }
function ProjectXmlChain(const ADprojPath: string; out AFicheros: TArray<string>): TArray<string>;
var
  List, Files: TList<string>;
  CarpetaDelBuild: string;

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
    Files.Add(AFile);
    if ADepth >= 4 then
      Exit;
    for V in AllTagAttr(Xml, 'Import', 'Project') do
    begin
      if IsStockImport(LowerCase(V.Trim)) then
        Continue;
      Resolved := ResolveImportPath(V.Trim, AFile, CarpetaDelBuild);
      if (Resolved <> '') and TFile.Exists(Resolved) then
        Lee(Resolved, ADepth + 1);
    end;
  end;

begin
  Result := nil;
  AFicheros := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  CarpetaDelBuild := ExtractFileDir(TPath.GetFullPath(ADprojPath));
  List := TList<string>.Create;
  Files := TList<string>.Create;
  try
    Lee(TPath.GetFullPath(ADprojPath), 0);
    Result := List.ToArray;
    AFicheros := Files.ToArray;
  finally
    Files.Free;
    List.Free;
  end;
end;

function ProjectXmlChain(const ADprojPath: string): TArray<string>;
var
  Ficheros: TArray<string>;
begin
  Result := ProjectXmlChain(ADprojPath, Ficheros);
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
          // lo que no se puede comprobar queda con Dir = '' (ResuelveSalida)
          Item.Dir := ResuelveSalida(Cand, Item.Value, Escrito, Dir);
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
  <BuildConfiguration Include="Debug"><Key>Cfg_1</Key>. No se supone: en
  lo que escribe delphi_create desde la 1.21.0, como el IDE, Cfg_1 es Debug
  (era al reves). '' si no esta. }
function ConfigKey(const AXml, AConfig: string): string;
begin
  // por EL analisis: era un recorredor gemelo de '<buildconfiguration'
  Result := '';
  for var T in TramosDeEtiqueta(AXml, 'BuildConfiguration') do
    if SameText(AtributoDeTramo(AXml, T, 'BuildConfiguration', 'Include').Trim, AConfig) then
      for var K in TramosDentro(AXml, 'Key', T) do
        Exit(ValorDeTramo(AXml, K).Trim);
end;

function ClaveDelBuild(const AXml, AConfig: string): string;
begin
  if AConfig.Trim = '' then
    Result := 'Base'
  else
    Result := ConfigKey(AXml, AConfig.Trim);
end;

function ClavesDelProyecto(const AXml: string): TArray<string>;
var
  Configs: TArray<string>;
  X: string;
begin
  // en el orden de los DEFINIDORES de configuracion del documento, que es el
  // de los grupos del IDE: el de BuildConfiguration NO lo es (en 230 de los
  // 296 Samples de la 37.0 va Release, Base, Debug con los grupos en Base,
  // Cfg_1, Cfg_2: revisor B, 21-oct-2026, medido); con una config hija, el
  // grupo nuevo caia antes que los de la madre y la madre lo pisaba
  Result := ['Base'];
  Configs := InfoDeDproj(AXml).Configs;
  for var G in GruposDePropiedades(AXml) do
    for var C in Configs do
    begin
      var K := ConfigKey(AXml, C);
      if (K <> '') and (IndexText(K, Result) < 0) and
         EsGrupoDeClave(G.Condicion, K, True, X) and (X = '') then
        Result := Result + [K];
    end;
  // las que no tienen definidor, al final (AseguraGrupoDelBuild las niega)
  for var C in Configs do
  begin
    var K := ConfigKey(AXml, C);
    if (K <> '') and (IndexText(K, Result) < 0) then
      Result := Result + [K];
  end;
end;

{ Si ACondicion es la de un grupo de la clave AClave - de valores
  (GroupCondition) o definidor (DefinerCondition, y el de la configuracion,
  ConfigDefinerCondition) -: la inversa de los nombradores, con la plataforma
  que nombra en APlataforma ('' = el de la clave sola). }
function EsGrupoDeClave(const ACondicion, AClave: string; ADefinidor: Boolean;
  out APlataforma: string): Boolean;
var
  N, X: string;
begin
  Result := False;
  APlataforma := '';
  N := CondicionNormalizada(ACondicion);
  if N = '' then
    Exit;
  if ADefinidor then
  begin
    X := ValorDeCondicion(ACondicion, '''$(Platform)''').Trim;
    if X = '' then
      // el de la configuracion: '$(Config)'=='Debug' or '$(Cfg_1)'!=''
      Result := N = CondicionNormalizada(ConfigDefinerCondition(
        ValorDeCondicion(ACondicion, '''$(Config)''').Trim, AClave))
    else
      Result := N = CondicionNormalizada(DefinerCondition(X, AClave));
  end
  else
  begin
    // el nombre entre $( y ): Base, Base_Win64, Cfg_1, Cfg_1_Win64
    X := TrozoDeCondicion(ACondicion, '$(', ')').Trim;
    if SameText(X, AClave) then
    begin
      X := '';
      Result := N = CondicionNormalizada(GroupCondition('', AClave));
    end
    else if X.StartsWith(AClave + '_', True) then
    begin
      X := Copy(X, Length(AClave) + 2, MaxInt);
      Result := N = CondicionNormalizada(GroupCondition(X, AClave));
    end;
  end;
  if Result and (X <> '') then
    APlataforma := ConSuGrafia(X);
end;

function EsNombreDeEtiqueta(const ANombre: string): Boolean;
begin
  Result := (ANombre <> '') and CharInSet(ANombre[1], ['A'..'Z', 'a'..'z', '_']);
  for var C in ANombre do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Exit(False);
end;

{ Los grupos con esa Condition, en orden de documento: msbuild los aplica
  todos y el ULTIMO gana, asi que el de un build es el ultimo (escribir en el
  primero dejaba el valor viejo del segundo mandando; revisor D, 21-oct-2026). }
function GruposConCondicion(const AXml, ACondicion: string): TArray<TGrupoXml>;
var
  N: string;
begin
  Result := [];
  N := CondicionNormalizada(ACondicion);
  for var G in GruposDePropiedades(AXml) do
    if CondicionNormalizada(G.Condicion) = N then
      Result := Result + [G];
end;

function UltimoGrupoConCondicion(const AXml, ACondicion: string; out AGrupo: TGrupoXml): Boolean;
var
  Grupos: TArray<TGrupoXml>;
begin
  Grupos := GruposConCondicion(AXml, ACondicion);
  Result := Length(Grupos) > 0;
  if Result then
    AGrupo := Grupos[High(Grupos)];
end;

function GrupoDelBuild(const AXml, APlatform, AConfig: string; out AGrupo: TGrupoXml): Boolean;
var
  Clave: string;
begin
  Clave := ClaveDelBuild(AXml, AConfig);
  Result := (Clave <> '') and UltimoGrupoConCondicion(AXml, GroupCondition(APlatform, Clave), AGrupo);
end;

function BuildDelGrupo(const AXml, ACondicion: string; out APlatform, AConfig: string): Boolean;
var
  Clave: string;
begin
  Result := False;
  APlatform := '';
  AConfig := '';
  // cada configuracion que declara el proyecto (Base la primera), por su
  // clave, contra la inversa de los nombradores (EsGrupoDeClave)
  for var C in InfoDeDproj(AXml).Configs do
  begin
    Clave := ConfigKey(AXml, C);
    if (Clave <> '') and EsGrupoDeClave(ACondicion, Clave, False, APlatform) then
    begin
      if not SameText(C, 'Base') then
        AConfig := C;
      Exit(True);
    end;
  end;
end;

function AseguraGrupoDelBuild(var AXml: string; const APlatform, AConfig: string;
  out AGrupo: TGrupoXml; out AFalta: TFaltaDeGrupo): Boolean;
var
  Clave, Nombre, X: string;
  Claves: TArray<string>;
  Mia, Tras: Integer;
  G: TGrupoXml;

  { La posicion de la clave de la Condition de un grupo (de valores o
    definidor) entre las del proyecto; -1 si no es de ninguna. }
  function IndiceDe(const ACondicion: string; ADefinidor: Boolean): Integer;
  begin
    for var I := 0 to High(Claves) do
      if EsGrupoDeClave(ACondicion, Claves[I], ADefinidor, X) then
        Exit(I);
    Result := -1;
  end;

begin
  Result := False;
  AFalta := fgNinguna;
  Clave := ClaveDelBuild(AXml, AConfig);
  if Clave = '' then
  begin
    AFalta := fgConfigNoDeclarada;
    Exit;
  end;
  if UltimoGrupoConCondicion(AXml, GroupCondition(APlatform, Clave), AGrupo) then
    Exit(True);
  // la clave va a ser NOMBRE de etiqueta en el definidor (<Cfg_1_Win64>): una
  // <Key> rara de BuildConfiguration ("Cfg 1") dejaria el XML roto (revisor D)
  if not EsNombreDeEtiqueta(Clave) then
  begin
    AFalta := fgClaveInvalida;
    Exit;
  end;
  // el definidor de la configuracion (o de la base) tiene que estar: sin el
  // msbuild nunca pone la clave y el grupo no se leeria
  Nombre := IfThen(AConfig.Trim = '', 'Base', AConfig.Trim);
  if not GrupoConCondicion(AXml, ConfigDefinerCondition(Nombre, Clave), G) then
  begin
    AFalta := fgSinDefinidor;
    Exit;
  end;
  Claves := ClavesDelProyecto(AXml);
  Mia := IndexText(Clave, Claves);
  if (APlatform <> '') and not GrupoConCondicion(AXml, DefinerCondition(APlatform, Clave), G) then
  begin
    // EL escritor del definidor (XmlGrupoDefinidor, el de delphi_create),
    // tras el ultimo definidor de mi clave o de una anterior (el de la
    // configuracion esta: Tras > 0)
    Tras := 0;
    for var D in GruposDePropiedades(AXml) do
    begin
      var I := IndiceDe(D.Condicion, True);
      if (I >= 0) and (I <= Mia) then
        Tras := D.Cierra;
    end;
    AXml := Copy(AXml, 1, Tras - 1) + sLineBreak + XmlGrupoDefinidor(APlatform, Clave) +
      Copy(AXml, Tras, MaxInt);
  end;
  // EL escritor del grupo de valores (XmlGrupoDeValores), tras el ultimo de
  // valores de mi clave (una plataforma) o de las claves anteriores (la
  // clave sola, que va delante de sus plataformas); sin ninguno (la base de
  // un .dproj sin grupos de valores), tras los definidores
  Tras := 0;
  for var V in GruposDePropiedades(AXml) do
  begin
    var I := IndiceDe(V.Condicion, False);
    if (I >= 0) and ((I < Mia) or ((I = Mia) and (APlatform <> ''))) then
      Tras := V.Cierra;
  end;
  if Tras = 0 then
    for var D in GruposDePropiedades(AXml) do
      if IndiceDe(D.Condicion, True) >= 0 then
        Tras := D.Cierra;
  if Tras = 0 then
  begin
    AFalta := fgSinGrupoBase;
    Exit;
  end;
  AXml := Copy(AXml, 1, Tras - 1) + sLineBreak + XmlGrupoDeValores(APlatform, Clave, '') +
    Copy(AXml, Tras, MaxInt);
  Result := UltimoGrupoConCondicion(AXml, GroupCondition(APlatform, Clave), AGrupo);
  if not Result then
    AFalta := fgInconsistente;
end;

procedure AnadeAlGrupo(var AXml: string; const AGrupo: TGrupoXml; const AElemento: string);
var
  P: Integer;
begin
  // delante del salto que precede a la sangria del cierre: la nueva, en su
  // linea, tras la ultima del grupo (Fin es el '<' del </PropertyGroup>)
  P := AGrupo.Fin;
  while (P > AGrupo.Ini) and CharInSet(AXml[P - 1], [' ', #9]) do
    Dec(P);
  if (P > AGrupo.Ini) and (AXml[P - 1] = #10) then
  begin
    Dec(P);
    if (P > AGrupo.Ini) and (AXml[P - 1] = #13) then
      Dec(P);
  end
  else
    P := AGrupo.Fin; // un grupo sin salto delante de su cierre: justo delante de el
  // el salto lo deja como el del fichero quien lo guarda (PatchSaveConSuSalto)
  AXml := Copy(AXml, 1, P - 1) + sLineBreak + '        ' + AElemento + Copy(AXml, P, MaxInt);
end;

function PonPropiedadDelBuild(var AXml: string; const ATag, AValor, APlatform, AConfig: string;
  AQuitar: Boolean; out AAntes: string; out AFalta: TFaltaDeGrupo): Boolean;
var
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
begin
  Result := False;
  AAntes := '';
  AFalta := fgNinguna;
  if AQuitar then
  begin
    if ClaveDelBuild(AXml, AConfig) = '' then
    begin
      AFalta := fgConfigNoDeclarada;
      Exit;
    end;
    // sin grupo no hay nada que quitar, y no se crea
    if not GrupoDelBuild(AXml, APlatform, AConfig, G) then
      Exit(True);
  end
  else if not AseguraGrupoDelBuild(AXml, APlatform, AConfig, G, AFalta) then
    Exit;
  // lo que hubiera DENTRO de ese grupo (una <ATag/> vacia tambien), no en
  // cualquier sitio del fichero, y sin Condition propia: una con Condition es
  // de otro build y se deja (el IDE no las escribe en los grupos de valores,
  // 0 de 296 Samples; revisor B, 21-oct-2026). De la ultima a la primera,
  // para que las de delante no se muevan
  // ...y de TODOS los grupos con esa Condition (msbuild los aplica todos y
  // gana el ultimo: la nueva va al ultimo, G, y las copias de los demas se
  // quitan, que si no mandaba la del segundo grupo; revisor D)
  Tramos := [];
  for var G2 in GruposConCondicion(AXml, GroupCondition(APlatform, ClaveDelBuild(AXml, AConfig))) do
    for var T in TramosEnGrupo(AXml, ATag, G2, True) do
      if AtributoDeTramo(AXml, T, ATag, 'Condition').Trim = '' then
        Tramos := Tramos + [T];
  if Length(Tramos) > 0 then
  begin
    AAntes := ValorDeTramo(AXml, Tramos[High(Tramos)]);
    // el mismo valor, una sola vez: nada que escribir
    if not AQuitar and (Length(Tramos) = 1) and (AAntes = AValor) then
      Exit(True);
    // la que vale ya esta en G: cambia en SU sitio y se quitan las otras (las
    // de delante, de la ultima a la primera: no mueven lo de antes)
    var Ultimo := Tramos[High(Tramos)];
    if not AQuitar and (Ultimo.Abre >= G.Ini) and (Ultimo.Cierra <= G.Fin) then
    begin
      AXml := Copy(AXml, 1, Ultimo.Abre - 1) + XmlElemento(ATag, AValor) + Copy(AXml, Ultimo.Cierra, MaxInt);
      for var K := High(Tramos) - 1 downto 0 do
        QuitaConSuLinea(AXml, Tramos[K].Abre, Tramos[K].Cierra);
      Exit(True);
    end;
    for var K := High(Tramos) downto 0 do
      QuitaConSuLinea(AXml, Tramos[K].Abre, Tramos[K].Cierra);
    if not GrupoDelBuild(AXml, APlatform, AConfig, G) then
    begin
      AFalta := fgInconsistente;
      Exit;
    end;
  end;
  if not AQuitar then
    AnadeAlGrupo(AXml, G, XmlElemento(ATag, AValor)); // (XmlElemento escapa el valor)
  Result := True;
end;

{ El valor EFECTIVO de ATag para un build APlatform/AConfig: los grupos del
  .dproj que se aplican a ese build, en orden de documento, y el ultimo que
  lo fija gana, como en MSBuild: sin definicion particular se hereda la
  global, y una particular vacia la anula. Cada plataforma y config puede
  tener su carpeta (David, 25-sep-2026). Y un $(ATag) dentro del valor es lo
  que valia hasta ahi, como en MSBuild: el IDE escribe asi los defines de
  cada configuracion, y sin expandirlo el de Debug era el texto
  "DEBUG;$(DCC_Define)" (1.20.2). }
function EffectiveProperty(const AXml, ATag, APlatform, AConfig: string): string;
var
  Mal, Tag: string;
  Elementos: TArray<TElementoXml>;
  V: TArray<TVeredicto>;
begin
  Result := '';
  // EL juez de "este grupo se aplica a este build", el de la puerta
  // (VeredictosDeElementos): las Condition evaluadas como msbuild, en orden
  // de documento, sobre lo que los grupos anteriores dejan puesto, y no por
  // el NOMBRE de la clave (los grupos del IDE elegidos por su Condition
  // escrita leian otra cosa que msbuild con una bandera plantada, una config
  // hija o una clave renombrada: revisores del 21-oct-2026). Para LEER solo
  // cuenta lo cierto: lo que no se sabe si se aplica (un nombre de fuera,
  // una funcion) no se da por declarado; la puerta, en cambio, lo juzga. Cada
  // elemento con SU Condition, y la vacia (<X/>) tambien: deja el valor
  // vacio, como en msbuild (un <Profile Condition="'$(Platform)'=='Win32'">
  // de 5 Samples del IDE se contaba para OSX64 e iOS; MSXML, 17-oct-2026)
  Elementos := ElementosDe(AXml, Mal);
  V := VeredictosDeElementos(AXml, APlatform, AConfig, Elementos, [], []);
  Tag := LowerCase(ATag);
  // y solo de un PropertyGroup de la raiz: el de un Target o de
  // ProjectExtensions no lo lee msbuild en la pasada (revisor E, 21-oct-2026)
  for var I := 0 to High(Elementos) do
    if (V[I] = vSi) and (Elementos[I].Nombre = Tag) and EsDeGrupoDeLaRaiz(Elementos[I]) then
      Result := ValorDeTramo(AXml, Elementos[I].Tramo).Trim.Replace('$(' + ATag + ')', Result,
        [rfReplaceAll, rfIgnoreCase]); // el ultimo gana, con lo de antes dentro
end;

function UsadasAntesDeDefinirse(const AXml, ATag, AValor, APlatform, AConfig: string): TArray<string>;
var
  Mal: string;
  Elementos: TArray<TElementoXml>;
  V: TArray<TVeredicto>;
  Definidas, Nombres: TArray<string>;
  P, Q: Integer;
begin
  Result := [];
  // los $(X) de AValor que el documento define, sin el propio (la herencia)
  Nombres := [];
  Elementos := ElementosDe(AXml, Mal);
  Definidas := PropiedadesDefinidas(Elementos);
  P := Pos('$(', AValor);
  while P > 0 do
  begin
    Q := Pos(')', AValor, P + 2);
    if Q = 0 then
      Break;
    var N := Copy(AValor, P + 2, Q - P - 2);
    if EsNombreDeMacro(N) and not SameText(N, ATag) and MatchText(N, Definidas) and
       not MatchText(N, Nombres) then
      Nombres := Nombres + [N];
    P := Pos('$(', AValor, Q + 1);
  end;
  if Length(Nombres) = 0 then
    Exit;
  V := VeredictosDeElementos(AXml, APlatform, AConfig, Elementos, [], []);
  for var I := 0 to High(Elementos) do
  begin
    if not SameText(Elementos[I].Escrito, ATag) or not EsDeGrupoDeLaRaiz(Elementos[I]) or
       (V[I] = vNo) or (ValorDeTramo(AXml, Elementos[I].Tramo).Trim <> AValor) then
      Continue;
    for var N in Nombres do
    begin
      // definida antes (y se aplica) o solo despues; lo de otro build no cuenta
      var Antes := False;
      var Despues := False;
      for var J := 0 to High(Elementos) do
        if SameText(Elementos[J].Escrito, N) and EsDeGrupoDeLaRaiz(Elementos[J]) and (V[J] <> vNo) then
          if Elementos[J].Tramo.Abre < Elementos[I].Tramo.Abre then
            Antes := True
          else
            Despues := True;
      if Despues and not Antes and not MatchText(N, Result) then
        Result := Result + [N];
    end;
  end;
end;

function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): TArray<string>;
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
  Result := nil;
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
  // TODAS las que faltan, en este orden: el llamante suple las que puede
  // (SALIDAS_QUE_SUPLE_EL_BUILD) y rechaza por la primera que no
  if not Declara('DCC_DcuOutput') then
    Result := Result + ['DCC_DcuOutput'];
  if Paquete and not Declara('DCC_BplOutput') then
    Result := Result + ['DCC_BplOutput'];
  if (Paquete or Cpp) and not Declara('DCC_DcpOutput') then
    Result := Result + ['DCC_DcpOutput'];
  if Cpp and not Declara('DCC_HppOutput') then
    Result := Result + ['DCC_HppOutput'];
end;

function BuildOutputDefault(const ADprojPath, APlatform, AConfig: string): TBuildOutputDir;
var
  Chain: TArray<string>;
  Dir, Base, Cand: string;
begin
  Result.Tag := '';
  Result.Value := '';
  Result.Dir := '';
  Chain := ProjectXmlChain(ADprojPath);
  if Chain = nil then
    Exit;
  // la del binario de ESTE build, tal como la declara el .dproj; sin ella,
  // la que el IDE escribe en un proyecto nuevo
  Result.Value := EffectiveProperty(Chain[0], 'DCC_ExeOutput', APlatform, AConfig).Trim;
  if Result.Value = '' then
    Result.Value := IDE_OUTPUT_DEFAULT;
  Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  Cand := ExpandOutputMacros(Result.Value, Dir, Base, APlatform, AConfig).Trim;
  if Cand <> '' then
    Result.Dir := ResuelveSalida(Cand, Result.Value, Result.Value, Dir);
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

function EsPropiedadReservadaDelIde(const ANombre: string): Boolean;
begin
  Result := MatchText(ANombre.Trim, RESERVED_IDE_IMPORT_PROPS);
end;

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

function NombreDelBinario(const AXml, ABase, APlatform, AConfig: string): string;
var
  Ext: string;
begin
  // la extension efectiva de ESE build (EffectiveProperty: el grupo de la
  // plataforma y la config, como msbuild); los targets la ponen tras el punto
  // (-TX.$(OutputExt)), con o sin punto delante en el .dproj
  Ext := EffectiveProperty(AXml, 'OutputExt', APlatform, AConfig).Trim;
  if Ext <> '' then
    Result := ABase + '.' + Ext.TrimLeft(['.'])
  else
    Result := ABase + ExtensionDeEjecutable(APlatform);
  // en Android el compilador le antepone lib (medido el 23-oct-2026:
  // libAndExt.so, y con OutputExt=mx libAndExt.mx). Se componia a mano en el
  // manifiesto de Android y en ResolveBuildOutput, que solo probaba lib
  // delante de un .so y con OutputExt no daba output (R11 del censo de Fable)
  if SistemaDePlataforma(APlatform) = spAndroid then
    Result := 'lib' + Result;
end;

function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;
var
  Xml, Dir, Base, D, Cand, Ext, Artifact, Nombre: string;
  ArtifactExts, Nombres: TArray<string>;
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
  // an ELF WITHOUT extension (plus .so), macOS the same (plus .dylib), iOS
  // its executable without extension (ExeExt vacia en CodeGear.Common.Targets;
  // decia .so, que es el de Android). Measured 2026-08-23: a Linux64 build
  // declared no output at all and the agent had to hunt the ELF with
  // delphi_list.
  case SistemaDePlataforma(APlatform) of
    spWindows: ArtifactExts := ['.exe', '.dll', '.bpl'];
    spLinux: ArtifactExts := ['', '.so'];
    spMacOS: ArtifactExts := ['', '.dylib'];
  else
    ArtifactExts := [''];
  end;
  // los NOMBRES candidatos: con OutputExt declarada, o en Android (su
  // lib<proyecto>.so), el que compone el nombrador y ninguno mas (un
  // <proyecto>.exe viejo al lado no es el de este build); si no, el proyecto
  // con cada extension de la plataforma
  Nombres := [];
  if (SistemaDePlataforma(APlatform) = spAndroid) or
     (EffectiveProperty(Xml, 'OutputExt', APlatform, AConfig).Trim <> '') then
    Nombres := [NombreDelBinario(Xml, Base, APlatform, AConfig)]
  else
    for Ext in ArtifactExts do
      Nombres := Nombres + [Base + Ext];
  Best := '';
  BestTime := 0;
  Dirs := TList<string>.Create;
  try
    for D in AllTagValues(Xml, 'DCC_ExeOutput') do
      Dirs.Add(D.Trim);
    for D in AllTagValues(Xml, 'DCC_BplOutput') do
      Dirs.Add(D.Trim);
    Dirs.Add(IDE_OUTPUT_DEFAULT); // the IDE default when unset
    for D in Dirs do
    begin
      Cand := Expand(D);
      if (Cand = '') or Cand.Contains('$(') then
        Continue; // still macro-based: not resolvable here
      // donde la deja msbuild, que corre en la carpeta del .dproj (EL resolutor)
      Cand := RutaDesde(Dir, Cand);
      if Cand = '' then
        Continue;
      for Nombre in Nombres do
      begin
        // (Android: lib<Project>.so por el nombrador; buscando <Project>.so el
        // build contestaba exito sin "output", field round 8)
        Artifact := TPath.Combine(Cand, Nombre);
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

function ElementosDe(const AXml: string; out AMalFormado: string): TArray<TElementoXml>;
var
  Low: string;
  Lista: TList<TElementoXml>;
  Pila: TList<Integer>; // indices en Lista de los elementos abiertos
  Ruta: TArray<string>;
  P, Inicio, NombreFin, TagEnd: Integer;
  Cierre: Boolean;
  Nombre: string;
  E: TElementoXml;

  // el nombre local: lo de detras del prefijo de espacio de nombres (msb:Target)
  function NombreLocal(const S: string): string;
  var
    C: Integer;
  begin
    Result := S;
    C := Result.LastIndexOf(':');
    if C >= 0 then
      Result := Result.Substring(C + 1);
  end;

begin
  AMalFormado := '';
  Low := TextoDeBusqueda(AXml, False);
  Lista := TList<TElementoXml>.Create;
  Pila := TList<Integer>.Create;
  try
    Ruta := nil;
    P := 1;
    while True do
    begin
      P := Pos('<', Low, P);
      if P = 0 then
        Break;
      Cierre := (P < Length(Low)) and (Low[P + 1] = '/');
      Inicio := P + 1;
      if Cierre then
        Inc(Inicio);
      NombreFin := Inicio;
      while (NombreFin <= Length(Low)) and
            not CharInSet(Low[NombreFin], [' ', #9, #13, #10, '/', '>', '<']) do
        Inc(NombreFin);
      Nombre := NombreLocal(Copy(Low, Inicio, NombreFin - Inicio));
      if Nombre = '' then
      begin
        AMalFormado := MsgText(SF_CFG_XML_SIN_NOMBRE);
        Break;
      end;
      // el '>' de la etiqueta, saltando lo que va entre comillas
      TagEnd := FinDeEtiqueta(Low, NombreFin);
      if TagEnd = 0 then
      begin
        AMalFormado := MsgFmt(SF_CFG_XML_SIN_FIN_FMT, [Nombre]);
        Break;
      end;
      if Cierre then
      begin
        if Pila.Count = 0 then
        begin
          AMalFormado := MsgFmt(SF_CFG_XML_CIERRE_SIN_APERTURA_FMT, [Nombre]);
          Break;
        end;
        E := Lista[Pila.Last];
        if E.Nombre <> Nombre then
        begin
          AMalFormado := MsgFmt(SF_CFG_XML_CIERRE_FMT, [Nombre, E.Nombre]);
          Break;
        end;
        E.Tramo.Fin := P;
        E.Tramo.Cierra := TagEnd + 1;
        Lista[Pila.Last] := E;
        Pila.Delete(Pila.Count - 1);
        SetLength(Ruta, Length(Ruta) - 1);
      end
      else
      begin
        E := Default(TElementoXml);
        E.Nombre := Nombre;
        E.Escrito := NombreLocal(Copy(AXml, Inicio, NombreFin - Inicio));
        E.Ruta := Copy(Ruta);
        E.Tramo.Abre := P;
        E.Tramo.Ini := TagEnd + 1;
        E.Tramo.Vacio := Low[TagEnd - 1] = '/';
        E.Tramo.Fin := E.Tramo.Ini;
        E.Tramo.Cierra := E.Tramo.Ini;
        Lista.Add(E);
        if not E.Tramo.Vacio then
        begin
          Pila.Add(Lista.Count - 1);
          Ruta := Ruta + [Nombre];
        end;
      end;
      P := TagEnd + 1;
    end;
    if (AMalFormado = '') and (Pila.Count > 0) then
      AMalFormado := MsgFmt(SF_CFG_XML_SIN_CERRAR_FMT, [Lista[Pila.Last].Nombre]);
    Result := Lista.ToArray;
  finally
    Pila.Free;
    Lista.Free;
  end;
end;

{ El primer elemento de AXml que no esta en la LISTA BLANCA del build, con su
  padre; '' si todos lo estan. Lo que un build compile-only entiende: bajo
  <Project>, ELEMENTOS_DE_PROJECT; dentro de un <Target>, ELEMENTOS_DE_TARGET;
  dentro de una tarea admitida, solo <Output>; lo de dentro de un OPACO no se
  mira. Una tarea de DANGER_TASKS se nombra como tarea (el porque que ya
  entiende el agente); lo demas, por su nombre y el de su padre. }
function ElementoNoAdmitido(const AXml: string): string;
var
  Mal, Padre: string;
  Admitido: Boolean;
begin
  Result := '';
  for var E in ElementosDe(AXml, Mal) do
  begin
    Admitido := False;
    for var A in E.Ruta do
      if MatchStr(A, ELEMENTOS_OPACOS) then
      begin
        Admitido := True; // dentro de un opaco: contenido, no estructura
        Break;
      end;
    if Admitido then
      Continue;
    if Length(E.Ruta) = 0 then
    begin
      if E.Nombre <> 'project' then
        Exit(MsgFmt(SF_CFG_HAZARD_RAIZ_FMT, [E.Nombre]));
      Continue;
    end;
    Padre := E.Ruta[High(E.Ruta)];
    if Padre = 'project' then
      Admitido := MatchStr(E.Nombre, ELEMENTOS_DE_PROJECT)
    else if Padre = 'target' then
      Admitido := MatchStr(E.Nombre, ELEMENTOS_DE_TARGET)
    else if MatchStr(Padre, ELEMENTOS_DE_TARGET) then
      Admitido := E.Nombre = 'output'; // lo unico que lleva una tarea
    if Admitido then
      Continue;
    if MatchStr(E.Nombre, DANGER_TASKS) then
      Exit(MsgFmt(SF_CFG_HAZARD_TASK_FMT, [E.Nombre]));
    Exit(MsgFmt(SF_CFG_HAZARD_ELEMENTO_FMT, [E.Nombre, Padre]));
  end;
  if Mal <> '' then
    Result := MsgFmt(SF_CFG_HAZARD_XML_FMT, [Mal]);
end;

function ValoresQueLeeElBuild(const AXml, APlatform, AConfig: string;
  const AExternas, AGlobales: TArray<string>): TArray<TValorDelProyecto>;
var
  Mal, Padre: string;
  V: TValorDelProyecto;
  Elementos: TArray<TElementoXml>;
  Veredictos: TArray<TVeredicto>;
  Expandidos, Dudosos: TArray<string>;
begin
  Result := nil;
  Elementos := ElementosDe(AXml, Mal);
  // lo que esta en un grupo que ESTE build no evalua no lo lee: se juzga la
  // compilacion pedida, no las demas (un keystore solo de Android64 tumbaba
  // un build Linux64, 21-oct-2026), decidido como msbuild sobre lo que los
  // grupos anteriores dejan puesto y no por el nombre de la clave (una
  // bandera plantada, una config hija: revisores, 21-oct-2026); de otro
  // build = su Condition o la de su grupo es FALSA, y lo que no se sabe se
  // juzga (una de mas es prudencia). Y cada valor expandido como msbuild lo
  // tiene donde lo lee (22-oct-2026), por EL recorrido
  Veredictos := VeredictosDeElementos(AXml, APlatform, AConfig, Elementos, AExternas, AGlobales,
    Expandidos, Dudosos);
  for var I := 0 to High(Elementos) do
  begin
    var E := Elementos[I];
    if (Length(E.Ruta) = 0) or MatchStr('projectextensions', E.Ruta) then
      Continue;
    Padre := E.Ruta[High(E.Ruta)];
    V.Elemento := E.Escrito;
    V.Expandido := Expandidos[I];
    V.Dudoso := Dudosos[I];
    if Padre = 'propertygroup' then
    begin
      if E.Tramo.Vacio or MatchStr(E.Nombre, EVENTOS_DE_BUILD) or (Veredictos[I] = vNo) then
        Continue;
      V.Escrito := ValorDeTramo(AXml, E.Tramo).Trim;
      if V.Escrito <> '' then
        Result := Result + [V];
    end
    else if Padre = 'itemgroup' then
      // un Include es una LISTA para msbuild (a.pas;b.pas): quien lo juzga
      // lo parte (TrozosDeLista) ya expandido
      for var At in AtributosDeTramo(AXml, E.Tramo) do
        if SameText(At.Nombre, 'Include') then
        begin
          V.Escrito := ValorDeAtributo(AXml, At).Trim;
          if V.Escrito <> '' then
            Result := Result + [V];
        end;
  end;
end;

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean; const ACarpetaDelBuild: string): string; forward;

function DprojBuildHazard(const AXml, AProjectPath: string;
  AIgnoreBuildEvents: Boolean): string;
begin
  Result := HazardScan(AXml, AProjectPath, 0, AIgnoreBuildEvents, ExtractFileDir(AProjectPath));
end;

{ LISTA BLANCA (1.21.2): lo que un build compile-only entiende, y nada mas
  (ElementoNoAdmitido); las funciones de propiedad, los eventos, las
  opciones libres y los Import se juzgan aparte. DANGER_TASKS queda de
  segunda barrera (tambien dentro de un comentario) y para nombrar el porque
  de una tarea conocida. No es un interprete de MSBuild; AllowBuildScripts lo
  decide el operador. }
function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean; const ACarpetaDelBuild: string): string;
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

  // LISTA BLANCA (1.21.2): un elemento que no es de la estructura de un
  // proyecto se niega por su nombre y el de su padre, y una tarea conocida
  // por el suyo (ElementoNoAdmitido). Un <Target> inerte (Message,
  // PropertyGroup, ItemGroup, CallTarget...) sigue compilando: negar todo
  // Target fue un falso positivo tan grave como un agujero (ronda 9: la
  // firma Authenticode). Antes era una LISTA NEGRA (DANGER_TASKS) que solo
  // conocia 21 tareas, y la deuda solo podia encoger.
  Result := ElementoNoAdmitido(AXml);
  if Result <> '' then
    Exit;
  // DANGER_TASKS, segunda barrera: tambien lo de dentro de un comentario o
  // un CDATA, mas estricto que el juez, y con o sin prefijo de espacio de
  // nombres (<msb:Exec> paso una busqueda literal en la ronda 8).
  for var Danger in DANGER_TASKS do
    if HasElement(Low, Danger) then
      Exit(MsgFmt(SF_CFG_HAZARD_TASK_FMT,
        [Danger]));

  // RAD Studio build-event commands: only a NON-EMPTY one runs a shell.
  // Con AIgnoreBuildEvents no cuentan: el runner los vacia al compilar.
  if not AIgnoreBuildEvents then
  for var Tag in EVENTOS_DE_BUILD do
    // por EL analisis, pero mas estricto que el juez: tambien dentro de un
    // comentario, y el texto ESCRITO (un CDATA vacio o un comentario dentro
    // cuentan). Buscaba '<prebuildevent' como prefijo, y el
    // <PreBuildEventIgnoreExitCode> que el IDE escribe junto a cada evento
    // contaba como un evento con texto (oraculo, 17-oct-2026)
    for var T in TramosDeEtiqueta(AXml, Tag, False, True) do
      if Copy(AXml, T.Ini, T.Fin - T.Ini).Trim <> '' then
        Exit(MsgFmt(SF_CFG_HAZARD_SHELL_COMMAND_FMT, [Tag]));

  // Opciones LIBRES al compilador (1.21.2): un texto que va tal cual a la
  // linea de ordenes de dcc o brcc32 no se juzga, se niega (el proyecto de
  // confianza, con AllowBuildScripts, como las tareas). Lo escrito, y
  // tambien dentro de un comentario, como los eventos.
  for var Tag in OPCIONES_LIBRES do
    for var T in TramosDeEtiqueta(AXml, Tag, False, True) do
      if Copy(AXml, T.Ini, T.Fin - T.Ini).Trim <> '' then
        Exit(MsgFmt(SF_CFG_HAZARD_OPCIONES_FMT, [Tag]));

  // <Import> brings in another MSBuild file, which carries its own targets -
  // so the payload can sit one file away from the project. Being macro-based
  // proves nothing: "$(MSBuildProjectDirectory)\payload.targets" is a macro
  // AND resolves next to the project (field round 8, confirmed execution).
  // Rule: trust ONLY the IDE's own imports without reading them; resolve and
  // SCAN anything else; refuse what cannot be resolved.
  // UN lector de atributos XML: comillas, blancos y entidades compartidos.
  // (tambien los de dentro de un comentario: mas estricto que el juez)
  // El Project y la Condition del MISMO <Import>, por las piezas de ese lector
  // (AperturasDe + AtributosDeApertura, las de AllTagAttr)
  for var Apertura in AperturasDe(TextoDeBusqueda(AXml, True), 'Import') do
  begin
    var Importado := '';
    var Condicion := '';
    var ConProject := False;
    for var At in AtributosDeApertura(AXml, Apertura.Abre, Apertura.Cierra) do
      if SameText(At.Nombre, 'Project') then
      begin
        Importado := ValorDeAtributo(AXml, At);
        ConProject := True;
      end
      else if SameText(At.Nombre, 'Condition') then
        Condicion := ValorDeAtributo(AXml, At);
    if not ConProject then
      Continue;
    V := Importado.Trim;
    if V.StartsWith('\\') or V.StartsWith('//') then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_UNC_FMT, [V]));
    if IsStockImport(LowerCase(V)) then
      Continue;
    if ADepth >= 4 then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_PROFUNDO_FMT, [V]));
    Resolved := ResolveImportPath(V, AProjectFile, ACarpetaDelBuild);
    if Resolved = '' then
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_NO_VERIFICABLE_FMT, [V]));
    if not TFile.Exists(Resolved) then
    begin
      // el que el IDE escribe para el manifiesto de despliegue lleva
      // Condition="Exists('<su mismo Project>')": sin el fichero msbuild -el
      // juez- no lo importa, y se negaba todo proyecto recien creado en el IDE
      // hasta su primer despliegue (BUILD-017; 17-oct y 19-oct-2026, medido).
      // Solo ESA forma, literal: otra condicion no se evalua aqui (frontera:
      // se le pregunta a msbuild, no se amplia el evaluador). Que aparezca
      // entre este escaneo y msbuild no se puede por el MCP: los dos van bajo
      // el cerrojo de escritura (Lsp.BuildRunner, EscaneoCompileOnly)
      if SameText(Condicion.Trim, 'Exists(''' + Importado + ''')') then
        Continue;
      Exit(MsgFmt(SF_CFG_HAZARD_IMPORT_NO_ESTA_FMT, [V]));
    end;
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
    Result := HazardScan(Imported, Resolved, ADepth + 1, AIgnoreBuildEvents, ACarpetaDelBuild);
    if Result <> '' then
      Exit(MsgFmt(SF_CFG_HAZARD_POR_IMPORT_FMT, [Result, V]));
  end;
end;

end.
