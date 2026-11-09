unit Lsp.PuertaDeLaLlamada;

{ LA PUERTA DE LA LLAMADA: lo que se mira de cada tools/call antes de que la
  tool haga nada (ToolCallDenied y sus reglas, ReglasDeLaLlamadaDenegadas); la
  tabla de accesos de cada tool (ACCESOS, en ConstruyeAccesos), que dice lo
  que LEE o ESCRIBE una llamada para la credencial de solo lectura
  (LlamadaLee, LecturaDenegada) y lo que tools/list anuncia de ella
  (AnunciaAcceso); las marcas de los parametros, leidas por RTTI del registro
  real ([RutaDelServidor], [Contenido]...), y lo que la puerta hace con ellas:
  expandir las unidades virtuales, alargar las rutas, el suelo de la jaula
  (ArgPathOutsideDenied) y los UNC ajenos; y las tools que tools/list deja
  fuera (MotivoToolOculta). Las preguntas de la jaula siguen en Lsp.Guard y
  esta las hace; Lsp.Guard no usa nada de aqui. Vivia en Lsp.Guard (V94 de la
  depuracion de la 1.23, B6 de la 1.28): se mudo sin cambiar una linea. }

interface

uses
  System.JSON;

type
  { POR QUE tools/list deja fuera una tool (moNinguna = la anuncia).
    moSinDestino: delphi_adb, delphi_desktop o delphi_db sin nada declarado a
    donde ir. }
  TMotivoOculta = (moNinguna, moSinVault, moVaultLectura, moCredencialLectura, moPerfil,
    moSinDestino);

{ La regla de lo que tools/list anuncia, con su motivo: delphi_help lo dice
  (un agente contaba 37 tools donde la documentacion dice 42 y creyo que se
  habian fusionado: la VM no declara vault; Hermes, validacion de la 1.16.0). }
function MotivoToolOculta(const AToolName: string): TMotivoOculta;
{ La clave que abre una tool que solo se anuncia con un destino declarado
  (moSinDestino), lo que dice delphi_help; '' si ATool no es de esas. De LA
  tabla de MotivoToolOculta (B12 de la 1.29). }
function ClaveQueAbreLaTool(const ATool: string): string;
{ True = leave this tool OUT of tools/list under the active [Tools] profile
  or allowlist. Listing only - the tool stays callable; permissions are
  ToolCallDenied's job. delphi_help/messages/report always stay listed. }
function ToolHiddenFromList(const AToolName: string): Boolean;

{ THE single entry gate, consulted by the tools dispatcher before ANY tool
  executes. '' = allowed; otherwise the rejection message returned to the
  agent. In read-only mode every mutating tool is refused; delphi_git is
  mixed and resolved by its "command" argument (query commands pass).
  It also NORMALIZES the arguments in place: virtual drive units
  (srvd:\x -> D:\x) are expanded here, before any check or tool. }
{ Cuantos parametros de todo el contrato vigila el suelo de la jaula: los
  marcados [RutaDelServidor], leidos por RTTI del registro real de tools. Se
  publica (delphi_workspace) para que un suelo VACIO se pueda ver: es una
  capa redundante, y si dejase de funcionar no romperia nada. }
function ServerPathParamCount: Integer;

type
  { El ACCESO de una tool para una credencial de solo lectura: la lee entera
    (atLectura), la niega entera (atEscritura) o depende del comando (atMixta:
    Lecturas = lo que LEE; lo que no este ahi se niega, cerrado). UNA tabla
    (ACCESOS, en ConstruyeAccesos): la mira la puerta (LecturaDenegada) y la
    anuncia tools/list (annotations.readOnlyHint y _meta.access /
    readOnlyCommands, AnunciaAcceso; y el perfil reader son sus atLectura,
    MotivoToolOculta), de donde TOOLS.md saca su linea Access
    y test_http_auth mide el anuncio contra la puerta. Antes la lista de
    mutantes estaba DOS veces en la puerta (una con delphi_desktop y otra
    sin) y cada mixta en su if; la linea Access del doc, a mano (28-sep-2026). }
  TAccesoTool = (atLectura, atEscritura, atMixta);
  TAccesoDeTool = record
    Tool: string;
    Acceso: TAccesoTool;
    Lecturas: TArray<string>; // atMixta: los comandos que leen ('' = el primero)
    Parametro: string;        // atMixta: el parametro que lleva el comando
    // atMixta: comandos que leen SOLO con una condicion (pares comando,
    // condicion en texto): se anuncian como readOnlyWhen; quien decide es la
    // puerta (git por GitCommandIsQuery)
    Condiciones: TArray<string>;
    // atLectura con un efecto fuera del workspace (un reporte que se
    // escribe, un mensaje que se consume): la credencial de solo lectura
    // puede llamarla, pero readOnlyHint (MCP: "no modifica su entorno") es
    // falso y _meta.sideEffect lo dice (undecima revision)
    Efecto: string;
    // atMixta: pares comando, parametros (separados por espacio) que, con
    // valor, hacen que ESE comando no lea: out= escribe un fichero de la
    // jaula, el project= del escritorio ejecuta ese proyecto en el destino y
    // el state= del preview pone propiedades de los componentes vivos. Se
    // anuncian en readOnlyWhen y la puerta niega cualquiera de ellos, y out=,
    // con el comando que sea (ParametrosQueNoLeen; 2ab de la 1.18.2)
    SinParametros: TArray<string>;
  end;

{ La fila de la tabla para una tool; lo que no esta en ella ESCRIBE (cerrado:
  la tabla declara todas, y test_paisaje exige una fila por tool registrada). }
function AccesoDeTool(const ATool: string): TAccesoDeTool;
{ El comando ACmd de la tool ATool LEE, por LA tabla (la que juzga una
  credencial de solo lectura): una de lectura siempre, una de escritura nunca,
  una mixta sin comando o con uno de sus Lecturas. La preguntan la puerta
  (LlamadaLee) y las tools que eligen por comando entre la puerta de leer y la
  de escribir: delphi_config y delphi_styles tenian su propia lista al lado de
  la de la tabla (B6 de la depuracion de la 1.23, I18 del cierre de la 1.28). }
function ComandoQueLee(const ATool, ACmd: string): Boolean;
{ '' si una credencial de solo lectura puede hacer ESTA llamada; si no, la
  negativa READ-002 con lo que pedia. delphi_git decide por argumentos
  (GitCommandIsQuery: branch/tag sin ellos listan, worktree y stash solo list), el
  resto por la tabla. Fuera del modo solo lectura, siempre ''. }
{ LA clasificacion de una llamada: LEE o ESCRIBE, por la tabla ACCESOS y los
  argumentos (el comando de una mixta, ComandoDeTest, logcat out=, la mitad
  de consulta de git). AQue: como se nombra la llamada en una negativa. La
  hacen la puerta de solo lectura (LecturaDenegada) y el suelo de la jaula
  (ArgPathOutsideDenied): una tool que ESCRIBE no lleva la pista de lectura
  de la zona en su negativa (duodecima revision, r12c). Vivia dentro de
  LecturaDenegada y el suelo no la podia usar. }
function LlamadaLee(const AToolName: string; const AArguments: TJSONObject;
  out AQue: string): Boolean;
{ Las rutas ABSOLUTAS que nombra una llamada: cada texto de cada parametro
  marcado [RutaDelServidor] (tambien los de una lista de rutas), como los
  juzga el suelo (RutaQueSeJuzga: la carpeta de un comodin), salvo el de un
  comando cuya ruta es lo que el proyecto DICE ([NombreSiComando]). Ya pasadas
  por la entrada: unidades virtuales traducidas y alargadas. Con las piezas
  del suelo (ArgPathOutsideDenied): lo pregunta el registro de las
  operaciones en curso (Lsp.EnCurso, R3 de la 1.29.1). }
function RutasDeLaLlamada(const AToolName: string; const AArguments: TJSONObject): TArray<string>;
function LecturaDenegada(const AToolName: string; const AArguments: TJSONObject): string;
{ Lo que tools/list anuncia de la tool, desde la tabla: annotations
  (readOnlyHint, MCP) y _meta (access: read-only | read-write | mixed;
  las mixtas, commandParameter y readOnlyCommands). }
procedure AnunciaAcceso(const AToolName: string; const AEntry: TJSONObject);

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Rtti,
  MCPServer.Serializer, // NormalizeKey: ONE rule for argument names
  MCPServer.Tool.Base,     // IMCPToolParams: la clase de parametros de una tool
  MCPServer.Registration,  // el registro REAL de tools, no una lista nuestra
  Lsp.Attributes,          // [RutaDelServidor]
  Lsp.NetDrives,        // las letras de red de los sitios declarados
  Lsp.Texts,
  Lsp.Json,
  Lsp.Rutas,
  Lsp.Settings,
  Lsp.ProcessLaunch, // EnComillas: la linea de una orden
  Lsp.Args,
  Lsp.Lugares,
  Lsp.Mascara,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Conexiones, // MetodoQueLee: si una peticion de delphi_api lee
  Lsp.JuecesDeArgumentos,
  // la ultima: lo suyo pesaba mas que lo de cualquier otra unidad cuando
  // vivia alli, y asi sigue
  Lsp.Guard;

{ '' unless APath IS one of the configured roots (the jail itself). With no
  roots configured (unrestricted local mode) there is no jail to protect and
  nothing is refused - same model as PathDenied. }
function RootItselfDenied(const APath: string): string;
var
  Raiz, Full: string;
begin
  Result := '';
  if APath.Trim = '' then
    Exit;
  try
    Full := SinBarraFinal(FormaLarga(TPath.GetFullPath(APath)));
  except
    Exit; // an unparseable path is PathDenied's business, not ours
  end;
  // por EL juez de la raiz que contiene una ruta (Lsp.Lugares.RaizQueContiene,
  // en su forma larga): aqui se comparaba raiz a raiz y en las dos formas, a
  // mano (menores de A del revisor del paisaje de la 1.29)
  Raiz := RaizQueContiene(Full);
  if (Raiz <> '') and SameFileName(Raiz, Full) then
    Result := MsgFmt(SR_ROOT_ITSELF_FMT, [Raiz]);
end;

// Parameter ALIASES, per tool, applied only when the real name is absent:
// the same idea is spelled query / pattern / filter across tools and an
// agent that learned one spelling loses a call ("Unknown parameter") on the
// next tool (measured 2026-08-23: three in a 25-minute session). Never an
// alias that the tool already declares with another meaning (delphi_search
// has both query and pattern). The declared name stays the documented one.
// An alias that comes WITH its real name: the same value is dropped; another
// value is refused, naming both - it was dropped in silence (V93 de la 1.23.1).
// '' = applied.
function ApplyArgAliases(const AToolName: string; AArguments: TJSONObject): string;
const
  // tool, alias, real
  Aliases: array [0 .. 27, 0 .. 2] of string = (
    // "path" is what almost every other tool calls it; delphi_list calls it
    // "root" and delphi_projects too. Each spelling cost a wasted call
    // (measured 2026-08-25), and the fix is free: accept both.
    ('delphi_list', 'path', 'root'),
    ('delphi_list', 'dir', 'root'),
    ('delphi_projects', 'path', 'root'),
    // add-unit/remove-unit take "path"; "unit" is what everybody types first.
    ('delphi_config', 'unit', 'path'),
    ('delphi_config', 'file', 'path'),
    // Names that cost a call every time somebody guessed the obvious one.
    ('delphi_read', 'from', 'fromline'),
    ('delphi_read', 'to', 'toline'),
    ('delphi_search', 'path', 'root'),
    ('delphi_report', 'body', 'message'),
    ('delphi_report', 'text', 'message'),
    ('vault_search', 'query', 'pattern'),
    ('vault_search', 'filter', 'pattern'),
    ('delphi_list', 'filter', 'pattern'),
    ('delphi_list', 'mask', 'pattern'),
    ('delphi_components', 'pattern', 'filter'),
    ('delphi_components', 'query', 'filter'),
    ('delphi_read', 'startline', 'fromline'),
    ('delphi_read', 'endline', 'toline'),
    ('delphi_search', 'text', 'query'),
    ('vault_read', 'linecount', 'limit'),
    ('delphi_designer', 'class', 'classname'),
    // El rango de delphi_edit / delphi_textedit se llama "toline" porque asi
    // se llama ya en delphi_read: mismo concepto, mismo nombre. Y por lo
    // mismo se le aceptan los mismos dos apodos.
    ('delphi_edit', 'to', 'toline'),
    ('delphi_edit', 'endline', 'toline'),
    ('delphi_textedit', 'to', 'toline'),
    ('delphi_textedit', 'endline', 'toline'),
    // El perfil de PAServer es "profile" en delphi_build, delphi_desktop y
    // delphi_config, y era "name" en delphi_paserver: el mismo concepto con
    // dos nombres (Hermes, validacion de la 1.16.0, PAS-051). Se llama
    // "profile" en todas desde la 1.17.0; el nombre viejo sigue valiendo.
    ('delphi_paserver', 'name', 'profile'),
    // Lo que un agente manda a delphi_build sin mirar (Hermes, 22-oct-2026: dos
    // SYS-015 seguidos). No cuestan nada en el contrato: V46 de la 1.25.
    ('delphi_build', 'configuration', 'config'),
    ('delphi_build', 'command', 'target'));
var
  I: Integer;
  P: TJSONPair;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  for I := Low(Aliases) to High(Aliases) do
  begin
    if not SameText(Aliases[I, 0], AToolName) then
      Continue;
    P := nil;
    for var Q in AArguments do
      if TMCPSerializer.NormalizeKey(Q.JsonString.Value) =
         TMCPSerializer.NormalizeKey(Aliases[I, 1]) then
      begin
        P := Q;
        Break;
      end;
    if P = nil then
      Continue;
    if ArgStr(AArguments, Aliases[I, 2]) <> '' then
    begin
      // the real name is there: with the SAME value the alias is dropped; with
      // another, one of the two would be ignored without a word (V93). El
      // valor del alias por EL lector (ArgStr): un null es "no viene", y su
      // .Value es el texto 'null' (V100 de la 1.23.1)
      var DelAlias := ArgStr(AArguments, Aliases[I, 1]).Trim;
      if (DelAlias <> '') and (DelAlias <> ArgStr(AArguments, Aliases[I, 2]).Trim) then
        Exit(MsgFmt(SR_ARG_ALIAS_OTRO_VALOR_FMT, [P.JsonString.Value, Aliases[I, 2], AToolName,
          Aliases[I, 2]]));
      AArguments.RemovePair(P.JsonString.Value).Free;
      Continue;
    end;
    var V := P.JsonValue.Clone as TJSONValue;
    AArguments.RemovePair(P.JsonString.Value).Free;
    // el nombre real que venia VACIO o null se va: quedaban dos claves con el
    // mismo nombre detras de DuplicateArgDenied, y ArgStr, el binder y las
    // reescrituras por nombre leian la primera - la vacia, o la que la puerta
    // no habia expandido ni alargado (revisor de B-9, 10-oct-2026: GUARD-023
    // enganoso con srvd:\, una ruta 8.3 que llegaba corta a la tool)
    for var K := AArguments.Count - 1 downto 0 do
      if TMCPSerializer.NormalizeKey(AArguments.Pairs[K].JsonString.Value) =
         TMCPSerializer.NormalizeKey(Aliases[I, 2]) then
        AArguments.RemovePair(AArguments.Pairs[K].JsonString.Value).Free;
    AArguments.AddPair(Aliases[I, 2], V);
  end;
end;

{ EL SUELO DE LA JAULA, en la puerta y para TODAS las tools.

  La regla ya estaba en una sola funcion (PathDenied / ReadPathDenied). Lo que
  no estaba centralizado era ACORDARSE de llamarla: ~60 llamadas a mano en
  una veintena de units, y nada obligaba a una tool nueva -ni a un parametro
  nuevo de una vieja- a pasar por ahi. Medido el 2026-09-21 con los destinos
  que elige quien llama: delphi_adb y delphi_package comprobaban, y
  delphi_desktop -en Windows y en Linux- no; con el nodo real, una llamada
  consiguio que el servidor escribiera una captura del escritorio del
  operador FUERA de la jaula. La frontera de verdad era "te acordaste?". Lo
  pregunto David: "tambien controlamos la jaula en 7 sitios o lo tenemos
  centralizado?".

  HISTORIA, porque la idea tuvo un primer intento y conviene no repetirlo:
  el 21-sep se escribio reconociendo las rutas por EXCLUSION (todo argumento
  que no fuera de contenido) y tumbo un delphi_search con
  query="D:\Proyectos" - un texto a buscar que PARECE una ruta. Tres baterias
  en rojo y retirado el mismo dia. Una lista de exclusion vale para
  REESCRIBIR, donde equivocarse es inocuo; esto RECHAZA, y entonces lo que no
  conoces tiene que pasar. Ahora solo muerde lo que lleva la marca
  [RutaDelServidor] (Lsp.Attributes): inclusion, declarada por quien diseno
  el parametro, leida por RTTI del registro REAL de tools.

  QUE ES Y QUE NO ES. Es un SUELO, una capa REDUNDANTE: no sustituye a las
  llamadas de cada tool. La puerta no sabe si la tool va a LEER o a ESCRIBIR
  ese argumento, asi que aplica la regla ANCHA (ReadPathDenied, que perdona
  la zona de biblioteca y las carpetas de solo lectura): nunca rechaza algo
  que una tool habria aceptado, solo caza lo que NINGUNA deberia aceptar. NO
  ve a un agente escribiendo en el subarbol confinado de otro, ni en la RTL:
  eso sigue siendo de PathDenied, en cada tool. El dia que alguien quite esas
  llamadas "porque ya esta centralizado", esta lista pasa de red a punto
  unico de fallo y un parametro sin marca es una ruta sin jaula (dictamen de
  la auditoria del 21-sep). No se quitan.

  LAS RELATIVAS, en una SEGUNDA pasada y la ULTIMA. Una relativa que la tool
  resuelve contra una base suya (delphi_config.path va contra la carpeta del
  proyecto) o que explica ella (un NOMBRE en delphi_test.project) lleva
  [RutaRelativa] y la puerta no la mira. Las demas se resolvian contra la
  carpeta del PROCESO y se niegan (quinta revision) - pero al final de
  ToolCallDenied: en el sitio de las absolutas se adelantaba a la negativa
  propia de cada tool (el profile sucio de delphi_build, el solo lectura de
  adb install, la unidad no servida por su nombre; gate del 28-sep). }
type
  { Las marcas de los parametros de TODAS las tools, por su clave
    'tool|parametro' (ClaveDeParam): las rutas del servidor (el valor dice si
    la tool acepta una relativa, [RutaRelativa]) y los que llevan contenido
    ([Contenido]: la expansion de ida de las unidades virtuales no los toca)
    y las LISTAS de textos ([JsonComoTexto('string')]: "paths" de delphi_git,
    que un cliente puede mandar como array o como su texto JSON, y la entrada
    deja en UNA forma: NormalizaListas). Las lineas de ordenes
    ([LineaDeOrdenes]) se fueron con los args de git en la 1.19.0: ningun
    parametro lo es ya, y ninguno nace asi (CLAUDE.md). }
  TMarcasDeParams = class
  public
    Rutas: TDictionary<string, Boolean>;
    DeContenido: TDictionary<string, Boolean>;
    DeLista: TDictionary<string, Boolean>;
    // [NombreSiComando]: con estos valores de "command" (separados por coma)
    // la ruta es lo que el proyecto DICE, y el suelo no la juzga
    NombreSi: TDictionary<string, string>;
    // [ComodinEnNombre]: su nombre puede llevar un comodin, y la entrada
    // juzga y alarga su carpeta (V19)
    ConComodin: TDictionary<string, Boolean>;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TMarcasDeParams.Create;
begin
  inherited Create;
  Rutas := TDictionary<string, Boolean>.Create;
  DeContenido := TDictionary<string, Boolean>.Create;
  DeLista := TDictionary<string, Boolean>.Create;
  NombreSi := TDictionary<string, string>.Create;
  ConComodin := TDictionary<string, Boolean>.Create;
end;

destructor TMarcasDeParams.Destroy;
begin
  Rutas.Free;
  DeContenido.Free;
  DeLista.Free;
  NombreSi.Free;
  ConComodin.Free;
  inherited;
end;

var
  GMarcas: TMarcasDeParams = nil;

{ LA clave de un parametro de una tool en los mapas de las marcas: la tool en
  minusculas y el parametro con la MISMA normalizacion con la que el binder
  casa argumento y propiedad (TMCPSerializer.NormalizeKey). Un solo
  nombrador, o la puerta miraria un nombre y la tool recibiria otro: estaba
  escrita a mano en los cuatro sitios que la usaban (B-9, 10-oct-2026). }
function ClaveDeParam(const ATool, AParametro: string): string;
begin
  Result := LowerCase(ATool) + '|' + TMCPSerializer.NormalizeKey(AParametro);
end;

{ Las marcas de los parametros, montadas UNA vez desde el registro real y en
  UN recorrido por RTTI para todas: [RutaDelServidor] y [Contenido] se leian
  en sitios distintos, la segunda como una lista de nombres que imitaba a la
  marca (PARAMS_CON_CONTENIDO, Lsp.Mascara; B-9, 10-oct-2026). Sin cerrojo:
  cada hilo que llegue a la vez monta el suyo y solo uno se publica; los
  demas tiran el suyo. Instanciar las tools aqui es barato (un constructor
  que pone nombre y descripcion) y pasa una sola vez. }
function MarcasDeParams: TMarcasDeParams;
var
  Marcas: TMarcasDeParams;
  Ctx: TRttiContext;
  Nombre: string;
  Tool: IMCPTool;
  Con: IMCPToolParams;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
begin
  Result := GMarcas;
  if Result <> nil then
    Exit;
  Marcas := TMarcasDeParams.Create;
  Ctx := TRttiContext.Create;
  try
    for Nombre in TMCPRegistry.GetToolNames do
    begin
      Tool := TMCPRegistry.CreateTool(Nombre);
      if not Supports(Tool, IMCPToolParams, Con) then
        Continue;
      for Prop in Ctx.GetType(Con.ParamsClass).GetProperties do
      begin
        // el valor del mapa de las rutas: si la ruta acepta un valor RELATIVO
        // que la tool resuelve contra una base suya ([RutaRelativa])
        var EsRuta := False;
        var AceptaRelativa := False;
        var EsContenido := False;
        var EsLista := False;
        var NombreSi := '';
        var EsComodin := False;
        for Attr in Prop.GetAttributes do
          if Attr is RutaDelServidorAttribute then
            EsRuta := True
          else if Attr is RutaRelativaAttribute then
            AceptaRelativa := True
          else if Attr is NombreSiComandoAttribute then
            NombreSi := NombreSiComandoAttribute(Attr).Comandos
          else if Attr is ComodinEnNombreAttribute then
            EsComodin := True
          else if Attr is ContenidoAttribute then
            EsContenido := True
          else if (Attr is JsonComoTextoAttribute) and
                  SameText(JsonComoTextoAttribute(Attr).Items, 'string') then
            EsLista := True;
        if EsRuta then
          Marcas.Rutas.AddOrSetValue(ClaveDeParam(Nombre, Prop.Name), AceptaRelativa);
        if EsRuta and (NombreSi <> '') then
          Marcas.NombreSi.AddOrSetValue(ClaveDeParam(Nombre, Prop.Name), NombreSi);
        if EsRuta and EsComodin then
          Marcas.ConComodin.AddOrSetValue(ClaveDeParam(Nombre, Prop.Name), True);
        if EsContenido then
          Marcas.DeContenido.AddOrSetValue(ClaveDeParam(Nombre, Prop.Name), True);
        if EsLista then
          Marcas.DeLista.AddOrSetValue(ClaveDeParam(Nombre, Prop.Name), True);
      end;
    end;
  finally
    Ctx.Free;
  end;
  if InterlockedCompareExchangePointer(Pointer(GMarcas),
       Pointer(Marcas), nil) <> nil then
    Marcas.Free;
  Result := GMarcas;
end;

{ Los parametros marcados [RutaDelServidor], por ClaveDeParam. }
function RutasNuestras: TDictionary<string, Boolean>;
begin
  Result := MarcasDeParams.Rutas;
end;

{ UNA forma para una lista de textos ([JsonComoTexto('string')]) antes de
  que nadie la mire: la que llega como su TEXTO JSON (un cliente con el
  esquema viejo, que el deserializador acepta a proposito) pasa a ser el
  array. Sin esto, la traduccion de las unidades virtuales, el suelo y la
  pasada de UNC veian un texto y no las rutas de dentro: 'srvd:\x' en un
  paths de texto llegaba sin traducir y caia en GUARD-023 (medido en vivo el
  14-oct-2026, con el esquema en cache del cliente). Un texto que no es una
  lista se queda como esta: el handler lo dice (GIT-069). }
procedure NormalizaListas(const AToolName: string; const AArguments: TJSONObject);
var
  DeLista: TDictionary<string, Boolean>;
  I: Integer;
  P: TJSONPair;
  Nombres: TArray<string>;
begin
  if not Assigned(AArguments) then
    Exit;
  DeLista := MarcasDeParams.DeLista;
  Nombres := nil;
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    if (P.JsonValue is TJSONString) and not (P.JsonValue is TJSONNumber) and
       DeLista.ContainsKey(ClaveDeParam(AToolName, P.JsonString.Value)) then
      Nombres := Nombres + [P.JsonString.Value];
  end;
  for var Nombre in Nombres do
  begin
    var Lista: TArray<string>;
    var Texto := TJSONString(AArguments.GetValue(Nombre)).Value;
    if (Texto.Trim = '') or not ListaDeTextos(Texto, Lista) then
      Continue;
    var Nueva := TJSONArray.Create;
    for var S in Lista do
      Nueva.Add(S);
    AArguments.RemovePair(Nombre).Free;
    AArguments.AddPair(Nombre, Nueva);
  end;
end;

{ La expansion de ida de las unidades virtuales de ESTA llamada
  (ExpandVirtualDrives, Lsp.Mascara), con la pregunta "que es este
  argumento?" contestada por la marca [Contenido] de la tool. }
procedure ExpandeUnidadesVirtuales(const AToolName: string;
  const AArguments: TJSONObject);
var
  DeContenido: TDictionary<string, Boolean>;
  Tool: string;
begin
  DeContenido := MarcasDeParams.DeContenido;
  Tool := AToolName;
  ExpandVirtualDrives(AArguments,
    function(const ANombre: string): TClaseDeArg
    begin
      if DeContenido.ContainsKey(ClaveDeParam(Tool, ANombre)) then
        Result := caContenido
      else
        Result := caEntero;
    end);
end;

{ Cuantos parametros vigila el suelo. Lo publica delphi_workspace y lo mide
  test_round45 contra las marcas del fuente: un suelo redundante que se
  quedase VACIO (RTTI que no emite, un registro que cambia) no romperia nada
  y nadie lo notaria - que es justo el fallo que hay que poder ver. }
function ServerPathParamCount: Integer;
begin
  Result := RutasNuestras.Count;
end;

{ True si el parametro de AClave lleva [NombreSiComando] y el "command" de
  esta llamada es uno de los suyos: entonces la ruta es la ENTRADA que la
  tool quita del proyecto (remove-unit, remove-searchpath, remove-project),
  no un sitio del servidor que vaya a leer o escribir, y el suelo no la
  juzga: la tool juzga el proyecto, para escribir. El comando se busca con la
  misma normalizacion que el binder (ClaveDeParam). Medido el 21-oct-2026:
  BUILD-050 pedia quitar una <DCCReference> de fuera y remove-unit la negaba
  (GUARD-002) por esa misma ruta, que nadie abre. }
function EsNombreConEsteComando(const AToolName: string;
  const AArguments: TJSONObject; const AClave: string): Boolean;
var
  Comandos, Cmd: string;
  P: TJSONPair;
  I: Integer;
begin
  Result := False;
  if not MarcasDeParams.NombreSi.TryGetValue(AClave, Comandos) then
    Exit;
  Cmd := '';
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    if (ClaveDeParam(AToolName, P.JsonString.Value) = ClaveDeParam(AToolName, 'command')) and
       (P.JsonValue is TJSONString) and not (P.JsonValue is TJSONNumber) then
      Cmd := TJSONString(P.JsonValue).Value;
  end;
  // coma, no ';': el censo del fuente de test_jaula_generica lee los
  // atributos de una propiedad hasta el primer ';'
  Result := (Cmd.Trim <> '') and MatchText(Cmd.Trim, Comandos.Split([',']));
end;

{ Lo que el suelo juzga de una ruta marcada: ella o, con un comodin en el
  NOMBRE de un parametro [ComodinEnNombre], su carpeta (la tool juzga despues
  cada entrada que case; un comodin en la carpeta lo niega PathAnomaly). }
function RutaQueSeJuzga(const AClave, AValor: string): string;
begin
  Result := AValor;
  if MarcasDeParams.ConComodin.ContainsKey(AClave) and TieneComodin(AValor) then
    Result := CarpetaDelComodin(AValor);
end;

type
  TRutaNombrada = record
    Clave, Valor: string;
  end;

{ Las rutas que el AGENTE nombra en esta llamada, como las ve el suelo: cada
  texto no vacio de cada parametro marcado [RutaDelServidor] (RutasNuestras),
  menos los que con este comando son lo que el proyecto DICE
  ([NombreSiComando]); de una lista de rutas ("paths" de delphi_git), cada
  una. UN recorrido para el suelo (ArgPathOutsideDenied) y para el registro de
  lo que sigue en curso (RutasDeLaLlamada, Lsp.EnCurso): el segundo era una
  copia del primero (hallazgo 6 del revisor de la 1.29.1). }
function RutasNombradas(const AToolName: string; const AArguments: TJSONObject): TArray<TRutaNombrada>;
var
  I: Integer;
  P: TJSONPair;
  V: string;
  N: TRutaNombrada;
begin
  Result := [];
  if not Assigned(AArguments) then
    Exit;
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    N.Clave := ClaveDeParam(AToolName, P.JsonString.Value);
    // con estos comandos la ruta es lo que el proyecto DICE, no un sitio que
    // la tool toque ([NombreSiComando]): el suelo no la juzga
    if not RutasNuestras.ContainsKey(N.Clave) or EsNombreConEsteComando(AToolName, AArguments, N.Clave) then
      Continue;
    // cada texto del valor: el suyo, o cada uno de una lista de rutas
    // ("paths" de delphi_git, 1.19.0): una ruta en una lista no se salta el
    // suelo; un parametro opcional vacio no es una ruta: si falta, lo dice
    // la tool
    for V in CadenasDeValor(P.JsonValue) do
      if V.Trim <> '' then
      begin
        N.Valor := V;
        Result := Result + [N];
      end;
  end;
end;

{ Las DOS pasadas del suelo, una funcion: ARelativas=False mira las rutas
  absolutas y va en su sitio de siempre; ARelativas=True mira las que no lo
  son y va la ultima. Las dos preguntan lo que preguntaria la tool
  (ReadPathDenied) y en su orden: una unidad virtual no servida (srvz:\,
  srv0:\) sale por su NOMBRE, no como "relativa". }
function ArgPathOutsideDenied(const AToolName: string;
  const AArguments: TJSONObject; ARelativas: Boolean): string;
var
  Que, R: string;
  Mapa: TDictionary<string, Boolean>;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  // Sin jaula configurada no hay nada que hacer cumplir (modo local de
  // confianza): el suelo no se inventa una.
  if not HayJaula then
    Exit;
  Mapa := RutasNuestras;
  for var N in RutasNombradas(AToolName, AArguments) do
  begin
    R := RutaQueSeJuzga(N.Clave, N.Valor);
    if EsRutaAbsoluta(N.Valor) = ARelativas then
      Continue;
    // Una relativa que la tool resuelve contra una base suya, o que explica
    // ella ([RutaRelativa]), es de la tool. En las demas se resolvia contra
    // la carpeta del proceso (fuera: DENIED enganoso; dentro, si el servidor
    // se lanzo desde una raiz: aceptada y escrita donde nadie dijo).
    if ARelativas and Mapa[N.Clave] then
      Continue;
    // Quien LEE recibe la negativa de lectura (con la pista de la zona);
    // quien ESCRIBE, la jaula a secas: una pista de lectura en la negativa
    // de un textedit create despistaba (duodecima revision, r12c)
    if LlamadaLee(AToolName, AArguments, Que) then
      Result := ReadPathDenied(R, SameText(AToolName, 'delphi_git'))
    else
      Result := JaulaDenegada(R, SameText(AToolName, 'delphi_git'));
    if Result <> '' then
      Exit;
    // Dentro, pero en una raiz cuya LETRA no esta conectada en el servidor:
    // ninguna tool puede salir bien ahi, y cada una lo decia a su manera
    // ("Directory not found", WS-008) sin decir que no es un error de nombre
    // ni que el arreglo es del operador (Hermes, 5-oct-2026). Sin disco ni
    // red, asi que cabe en cada llamada; y no niega nada que una tool habria
    // aceptado. Una raiz LOCAL cuya carpeta no existe no se niega aqui: una
    // tool que crea podria crearla.
    if not ARelativas then
    begin
      Result := RaizEnLetraNoConectada(R);
      if Result <> '' then
        Exit;
      // ...ni en una ruta mas larga de lo que Windows abre a este proceso: cada
      // tool decia "no existe" con el fichero alli (A24 de la 1.29, medido)
      Result := RutaQueWindowsNoAbre(R);
      if Result <> '' then
        Exit;
    end;
  end;
end;

function RutasDeLaLlamada(const AToolName: string; const AArguments: TJSONObject): TArray<string>;
begin
  Result := [];
  for var N in RutasNombradas(AToolName, AArguments) do
    if EsRutaAbsoluta(N.Valor) then
      Result := Result + [RutaQueSeJuzga(N.Clave, N.Valor)];
end;

{ La forma de UNA ruta absoluta de la entrada (la regla, en AlargaRutas). }
function AlargaUna(const AValor: string): string;
begin
  Result := AValor;
  // Alargar NUNCA cambia a que fichero se refiere la llamada. La forma
  // canonica de Windows quita el punto o el espacio final y deshace un
  // ::$DATA: "X.pas." pasaba a ser "X.pas" y "X.pas::$DATA" otra ruta,
  // que se CREABA (medido, test_guard B0c). Una ruta con anomalia sigue
  // tal cual y su negativa (PathAnomaly) la ve como vino.
  if PathAnomaly(AValor) <> '' then
    Exit;
  // ...y el separador de Windows: '/' vale para el sistema, pero no para
  // ExtractFileDir y los suyos, que solo ven '\'. Con "D:/a/x.pas" la
  // carpeta real del escritor salia "D:" y la escritura se negaba como si
  // hubiera un ENLACE (GUARD-037) despues de que read leyera la misma
  // ruta (Hermes, validacion de la 1.21.1; medido en produccion). UNA
  // forma, aqui, para todas las tools
  Result := ConBarrasDeWindows(AValor);
  if Result.IndexOf('~') < 0 then
    Exit;
  try
    Result := LongCanonical(Result);
  except
    Exit(ConBarrasDeWindows(AValor)); // una ruta que no parsea sigue a su negativa
  end;
  // ...y el NOMBRE final como lo escribio quien llama si solo cambian las
  // mayusculas: alargar resuelve un alias, no renombra (el dest ABC.txt de un
  // move de abc.txt llegaba como abc.txt; 25-oct-2026)
  var Dado := ExtractFileName(SinBarraFinal(ConBarrasDeWindows(AValor)));
  var Largo := ExtractFileName(SinBarraFinal(Result));
  if (Dado <> Largo) and SameFileName(Dado, Largo) then
    Result := ExtractFilePath(SinBarraFinal(Result)) + Dado;
  // la separacion final, como venia: una carpeta se nombra igual
  if AValor.EndsWith('\') or AValor.EndsWith('/') then
    Result := IncludeTrailingPathDelimiter(Result);
end;

{ Una ruta marcada [RutaDelServidor] que trae un nombre corto 8.3 (~) llega a
  la tool en su forma LARGA, como una unidad virtual llega ya traducida. Todo
  lo que sale de una ruta -el nombre de una unit, "es la raiz", "es un lugar
  protegido", "es el vault"- se miraba en el texto: UPROVE~1.PAS no era la
  unit UProveedorModelo y el .dpr la seguia listando tras borrarla, y
  OTHERW~1 no era la raiz de otro workspace y se borraba (sexta revision). La
  regla vive aqui, en la entrada, para todas las tools a la vez; las
  comparaciones de dentro usan ademas FormaLarga, por las raices y lugares
  que el operador declara en 8.3. Solo absolutas: una relativa es de la tool
  o de la negativa GUARD-021. }
procedure AlargaRutas(const AToolName: string; const AArguments: TJSONObject);
var
  Mapa, Comodines: TDictionary<string, Boolean>;
  Tool: string;
begin
  Mapa := RutasNuestras;
  Comodines := MarcasDeParams.ConComodin;
  Tool := AToolName; // la clave la compone ClaveDeParam
  ReescribeCadenas(AArguments,
    function(const ANombre, AValor: string): string
    begin
      Result := AValor;
      if ((AValor.IndexOf('~') < 0) and (AValor.IndexOf('/') < 0)) or not EsRutaAbsoluta(AValor) or
         not Mapa.ContainsKey(ClaveDeParam(Tool, ANombre)) then
        Exit;
      // con un comodin en el NOMBRE de un parametro [ComodinEnNombre] (V19) se
      // alarga su CARPETA y el nombre vuelve detras tal cual: entera, la
      // negaria PathAnomaly y la tool la recibiria corta
      var Win := ConBarrasDeWindows(AValor);
      if Comodines.ContainsKey(ClaveDeParam(Tool, ANombre)) and TieneComodin(Win) then
        Exit(IncludeTrailingPathDelimiter(AlargaUna(CarpetaDelComodin(Win))) +
          ExtractFileName(SinBarraFinal(Win)));
      Result := AlargaUna(AValor);
    end);
end;

{ La pasada de los UNC ajenos en la ENTRADA, sobre las rutas marcadas
  [RutaDelServidor] - cada texto de su valor, tambien los de una lista de
  rutas ("paths" de delphi_git): antes de alargarlas (AlargaRutas las
  resuelve) y antes de que la tool haga nada con ellas. La negativa, la de
  NegativaDeUnc. Pasaba tambien por cada trozo de una linea de ordenes (los
  args de git: un '-- \\host\s\x' en un git log abria SMB hacia ese host;
  revisor de version de la 1.18.1): desde la 1.19.0 no hay lineas de
  ordenes, y una ruta de "paths" es una ruta. }
function UncAjenoEnArgumentos(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Mapa: TDictionary<string, Boolean>;
  I: Integer;
  P: TJSONPair;
  EsFormaDeRed: Boolean;
  Valor: string;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  Mapa := RutasNuestras;
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    if not Mapa.ContainsKey(ClaveDeParam(AToolName, P.JsonString.Value)) then
      Continue;
    for Valor in CadenasDeValor(P.JsonValue) do
      if UncFueraDeLugares(Valor) then
        Exit(NegativaDeUnc(Valor, EsFormaDeRed));
  end;
end;

var
  GAccesos: TArray<TAccesoDeTool>;

procedure AnadeAcceso(const ATool: string; AAcceso: TAccesoTool;
  const ALecturas: TArray<string>; const AParametro: string = 'command';
  const ACondiciones: TArray<string> = nil; const AEfecto: string = '';
  const ASinParametros: TArray<string> = nil);
var
  F: TAccesoDeTool;
begin
  F.Tool := ATool;
  F.Acceso := AAcceso;
  F.Lecturas := ALecturas;
  F.Parametro := AParametro;
  F.Condiciones := ACondiciones;
  F.Efecto := AEfecto;
  F.SinParametros := ASinParametros;
  GAccesos := GAccesos + [F];
end;

{ LA tabla (ACCESOS), con TODAS las tools: lo que no esta aqui ESCRIBE. Lo
  ausente era de lectura, y una tool nueva que escribiese y cuyo autor
  olvidase su fila la llamaba una credencial de solo lectura (quinta ronda de
  Fable, depuracion de la 1.23); test_paisaje exige una fila por tool
  registrada. Las mixtas listan lo que LEE: un comando desconocido se niega,
  cerrado (una credencial de solo lectura reescribia forms por un comando que
  no estaba en ninguna lista; auditoria 25-sep-2026). }
procedure ConstruyeAccesos;
begin
  GAccesos := [];
  // enteras de lectura: el codigo, los ficheros, el paisaje, la ayuda, el vault
  for var T in TArray<string>.Create('delphi_read', 'delphi_list', 'delphi_search',
    'delphi_symbols', 'delphi_definition', 'delphi_hover', 'delphi_signature',
    'delphi_completion', 'delphi_diagnostics', 'delphi_references', 'delphi_projects',
    'delphi_installs', 'delphi_workspace', 'delphi_components', 'delphi_fetch',
    'delphi_help', 'delphi_docs', 'vault_read', 'vault_search') do
    AnadeAcceso(T, atLectura, []);
  // enteras de escritura: negadas de plano en modo solo lectura
  AnadeAcceso('delphi_edit', atEscritura, []);
  AnadeAcceso('delphi_textedit', atEscritura, []);
  AnadeAcceso('delphi_create', atEscritura, []);
  AnadeAcceso('delphi_changeset', atEscritura, []);
  AnadeAcceso('delphi_build', atEscritura, []);
  AnadeAcceso('delphi_package', atEscritura, []);
  AnadeAcceso('delphi_upload', atEscritura, []);
  AnadeAcceso('delphi_delete', atEscritura, []);
  AnadeAcceso('delphi_move', atEscritura, []);
  // mirar el escritorio del destino (screenshot, status) es lectura y lo
  // juzga el permiso de control remoto (EjecucionRemotaDenegada); tap, type y
  // key actuan, y overview abre la vista de actividades: cambia lo que hay en
  // pantalla (2ab de la 1.18.2, David: "una credencial de solo lectura no
  // deberia permitir acciones"). out= escribe, y project= EJECUTA ese proyecto
  // en el destino, lo que remote-run le niega (revisor del 2ab, R1, medido)
  AnadeAcceso('delphi_desktop', atMixta, ['screenshot', 'status'], 'command', nil, '',
    ['screenshot', 'out project', 'status', 'out project']);
  // el vault: leerlo vale en solo lectura, escribirlo nunca
  AnadeAcceso('vault_append', atEscritura, []);
  AnadeAcceso('vault_create', atEscritura, []);
  AnadeAcceso('vault_patch', atEscritura, []);
  // mixtas: "view" y "get-property" leen, "add-platform" escribe el .dproj
  AnadeAcceso('delphi_config', atMixta, ['view', 'get-property']);
  // discover solo mira; run construye y EJECUTA
  AnadeAcceso('delphi_test', atMixta, ['discover']);
  AnadeAcceso('delphi_styles', atMixta, ['view', 'get', 'lint']);
  // los listados leen; add-profile escribe un perfil en el servidor y
  // test-connection marca al destino con su credencial guardada
  AnadeAcceso('delphi_paserver', atMixta, ['platforms', 'packages', 'profiles']);
  // to-text / to-binary, insert, set y delete reescriben el .dfm/.fmx; el
  // resto mira. preview tambien MIRA: el PNG es trabajo nuestro, en la casa
  // de capturas del servidor, y lo juzga la lectura del form (2ab de la
  // 1.18.2, David: "un preview depende de que tengas permiso de lectura en la
  // carpeta del form"); out= escribe un fichero de la jaula, y state= pone
  // propiedades de los componentes VIVOS con los paquetes de diseno cargados
  // (un dataset con CommandText y Active ejecutaria su SQL; revisor, R2)
  AnadeAcceso('delphi_designer', atMixta, ['info', 'prop', 'tree', 'get', 'lint',
    'check-binding', 'binding', 'layout', 'preview'], 'command', nil, '',
    ['preview', 'out state']);
  // mirar el dispositivo (lista, log, pantalla) no cambia nada y lo juzga
  // AdbAllowedDevices; screenshot y logcat con out= ESCRIBEN un fichero en la
  // jaula (LlamadaLee). El screenshot sin out= contaba como escritura por el
  // PNG, que es trabajo nuestro (r11a H5; 2ab de la 1.18.2).
  // connect/disconnect/install/run/tap/key mutan o ejecutan
  AnadeAcceso('delphi_adb', atMixta, ['discover', 'devices', 'logcat', 'screenshot'], 'command', nil, '',
    ['logcat', 'out', 'screenshot', 'out']);
  // git decide por sus CAMPOS (GitCommandIsQuery): se anuncia lo
  // INCONDICIONAL como lectura y lo condicionado con su condicion (tag lista
  // sin name ni message; worktree y stash solo action=list). Se anunciaban
  // branch/tag como lecturas y la puerta los negaba con args (r11b H1, r11c
  // H3); branch solo lista desde la 1.19.0
  AnadeAcceso('delphi_git', atMixta, ConsultasDeGit, 'command',
    ['tag', MsgText(SF_ACCESO_GIT_TAG),
     'worktree', MsgText(SF_ACCESO_GIT_ACTION_LIST),
     'stash', MsgText(SF_ACCESO_GIT_ACTION_LIST),
     'config', MsgText(SF_ACCESO_GIT_CONFIG)]);
  // lecturas para la puerta, con un EFECTO fuera del workspace: el hint MCP
  // "no modifica su entorno" es falso y se dice (r11e H6)
  AnadeAcceso('delphi_report', atLectura, [], 'command', nil, MsgText(SF_ACCESO_REPORT_EFECTO));
  AnadeAcceso('delphi_messages', atLectura, [], 'command', nil, MsgText(SF_ACCESO_MESSAGES_EFECTO));
  // preview lee; apply escribe por el motor de changesets (lo negaba el
  // escritor al llegar a escribir; ahora la puerta, a la entrada, como a todas)
  AnadeAcceso('delphi_rename_symbol', atMixta, ['preview'], 'mode');
  // las bases con nombre (1.29): connections lee la configuracion y tables,
  // fields, rows y summary leen la base (en una transaccion que se deshace);
  // lo que no esta en la lista se niega a una credencial de lectura, cerrado:
  // insert, update y delete escriben (y la tool, ademas, solo donde el json
  // de conexiones no dice access=read)
  AnadeAcceso('delphi_db', atMixta, ['connections', 'tables', 'fields', 'rows', 'summary']);
  // las APIs con nombre (1.29): connections lee la configuracion; request LEE
  // con GET, HEAD u OPTIONS y sin out= (MetodoQueLee, Lsp.Conexiones: la MISMA
  // regla para la puerta, LlamadaLee, y para el anuncio) y escribe con los
  // demas metodos
  AnadeAcceso('delphi_api', atMixta, ['connections'], 'command',
    ['request', MsgText(SF_ACCESO_API_REQUEST)]);
end;

function ComandoQueLee(const ATool, ACmd: string): Boolean;
var
  F: TAccesoDeTool;
begin
  F := AccesoDeTool(ATool);
  case F.Acceso of
    atLectura:
      Exit(True);
    atEscritura:
      Exit(False);
  end;
  Result := (ACmd.Trim = '') or MatchText(ACmd.Trim, F.Lecturas);
end;

function AccesoDeTool(const ATool: string): TAccesoDeTool;
var
  F: TAccesoDeTool;
begin
  for F in GAccesos do
    if SameText(F.Tool, ATool) then
      Exit(F);
  Result.Tool := ATool;
  Result.Acceso := atEscritura; // cerrado: lo que la tabla no declara
  Result.Lecturas := [];
  Result.Parametro := '';
  Result.Condiciones := nil;
  Result.Efecto := '';
  Result.SinParametros := nil;
end;

{ Los parametros que, con valor, hacen que una llamada de una mixta no lea:
  out= siempre (escribe un fichero de la jaula en la tool que lo tome) y los
  que la tabla nombra para sus comandos (SinParametros). }
function ParametrosQueNoLeen(const F: TAccesoDeTool): TArray<string>;
var
  K: Integer;
begin
  Result := ['out'];
  K := 1;
  while K <= High(F.SinParametros) do
  begin
    for var P in F.SinParametros[K].Split([' '], TStringSplitOptions.ExcludeEmpty) do
      if not MatchText(P, Result) then
        Result := Result + [P];
    Inc(K, 2);
  end;
end;

{ La condicion de readOnlyWhen de un comando de SinParametros ("without out=
  or project="), del mismo par que lee la puerta. }
function CondicionSinParametros(const AParams: string): string;
var
  Ps: TArray<string>;
begin
  Ps := AParams.Split([' '], TStringSplitOptions.ExcludeEmpty);
  for var I := 0 to High(Ps) do
    Ps[I] := Ps[I] + '=';
  Result := MsgFmt(SF_ACCESO_SIN_FMT, [string.Join(' or ', Ps)]);
end;

function LlamadaLee(const AToolName: string; const AArguments: TJSONObject;
  out AQue: string): Boolean;
var
  F: TAccesoDeTool;
  Cmd: string;
begin
  AQue := AToolName;
  F := AccesoDeTool(AToolName);
  case F.Acceso of
    atLectura:
      Exit(True);
    atEscritura:
      Exit(False);
  end;
  Cmd := Trim(ArgStr(AArguments, F.Parametro));
  // delphi_test: sin command, project significa run: LA regla de la tool
  // (ComandoDeTest); '' se perdonaba y llegaba al constructor (r11c H2)
  if SameText(AToolName, 'delphi_test') then
    Cmd := ComandoDeTest(Cmd, ArgStr(AArguments, 'project'), ArgStr(AArguments, 'path'));
  // Lo que hace que una lectura escriba o actue es un PARAMETRO: out= nombra
  // un fichero de la jaula donde escribir en toda mixta que lo tome, y la
  // tabla nombra los demas (SinParametros: project=, state=). Se niegan con
  // el comando que sea, cerrado (2ab de la 1.18.2: era un caso suelto de
  // logcat, y el project= del escritorio ejecutaba con solo lectura, R1)
  for var P in ParametrosQueNoLeen(F) do
    if Trim(ArgStr(AArguments, P)) <> '' then
    begin
      AQue := Trim(AToolName + ' ' + Cmd) + ' ' + P + '=';
      Exit(False);
    end;
  if SameText(AToolName, 'delphi_api') and SameText(Cmd, 'request') then
  begin
    // una peticion lee o escribe por su METODO (el out= ya se nego arriba)
    AQue := AToolName + ' ' + Cmd + ' ' + MetodoDePeticion(ArgStr(AArguments, 'method'));
    Exit(MetodoQueLee(ArgStr(AArguments, 'method')));
  end;
  if SameText(AToolName, 'delphi_git') then
  begin
    // la mitad de consulta de git depende de los argumentos: la MISMA
    // clasificacion que usa la propia tool (GitCommandIsQuery)
    AQue := Trim(AToolName + ' ' + Cmd);
    Exit(GitCommandIsQuery(Cmd, ArgStr(AArguments, 'action'), ArgStr(AArguments, 'name'),
      ArgStr(AArguments, 'message')));
  end;
  AQue := AToolName + ' ' + Cmd;
  Result := ComandoQueLee(AToolName, Cmd);
end;

function LecturaDenegada(const AToolName: string; const AArguments: TJSONObject): string;
var
  Que: string;
begin
  Result := '';
  if not IsReadOnlyNow then
    Exit;
  if not LlamadaLee(AToolName, AArguments, Que) then
    Result := WriteDenied(Que);
end;

procedure AnunciaAcceso(const AToolName: string; const AEntry: TJSONObject);
var
  F: TAccesoDeTool;
  Ann, Meta: TJSONObject;
  Arr: TJSONArray;
  S: string;
begin
  F := AccesoDeTool(AToolName);
  Ann := TJSONObject.Create;
  // el hint MCP es "no modifica su entorno": una lectura con efecto fuera
  // del workspace (un reporte, un mensaje consumido) no lo cumple
  Ann.AddPair('readOnlyHint', TJSONBool.Create((F.Acceso = atLectura) and (F.Efecto = '')));
  AEntry.AddPair('annotations', Ann);
  Meta := TJSONObject.Create;
  case F.Acceso of
    atLectura:
      Meta.AddPair('access', 'read-only');
    atEscritura:
      Meta.AddPair('access', 'read-write');
    atMixta:
      begin
        Meta.AddPair('access', 'mixed');
        Meta.AddPair('commandParameter', F.Parametro);
        Arr := TJSONArray.Create;
        for S in F.Lecturas do
          Arr.Add(S);
        Meta.AddPair('readOnlyCommands', Arr);
        if (Length(F.Condiciones) > 0) or (Length(F.SinParametros) > 0) then
        begin
          var Cuando := TJSONObject.Create;
          var K := 0;
          while K + 1 <= High(F.Condiciones) do
          begin
            Cuando.AddPair(F.Condiciones[K], F.Condiciones[K + 1]);
            Inc(K, 2);
          end;
          // ...y los de SinParametros, con el texto del mismo par que lee la
          // puerta (ParametrosQueNoLeen)
          K := 0;
          while K + 1 <= High(F.SinParametros) do
          begin
            Cuando.AddPair(F.SinParametros[K], CondicionSinParametros(F.SinParametros[K + 1]));
            Inc(K, 2);
          end;
          Meta.AddPair('readOnlyWhen', Cuando);
        end;
      end;
  end;
  if F.Efecto <> '' then
    Meta.AddPair('sideEffect', F.Efecto);
  AEntry.AddPair('_meta', Meta);
end;

{ Un parametro que la tool YA NO tiene (lo retiro una version, y un cliente con
  el esquema viejo lo sigue mandando): se le dice a donde fue, con su codigo,
  antes del SYS-015 generico del deserializador, que solo lista los que hay.
  La hermana de ApplyArgAliases (alli, un nombre que SI vale, con otro nombre).
  Era un if de delphi_git (args, 1.19.0); delphi_edit perdio createunit,
  content y eol en la 1.28 (I33 del cierre: Hermes los mando en las tres
  rondas del dirigido, con su cache de esquemas del 4-nov). '' si no hay. }
function ParametroRetiradoDenegado(const AToolName: string; const AArguments: TJSONObject): string;
const
  // tool y parametro retirado; la negativa, la de su tool (abajo)
  Retirados: array[0..3, 0..1] of string = (
    ('delphi_git', 'args'),
    ('delphi_edit', 'createunit'),
    ('delphi_edit', 'content'),
    ('delphi_edit', 'eol'));
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  for var I := Low(Retirados) to High(Retirados) do
    // leido como lo resuelve el binder (ArgStr: sin mayusculas ni '_'), no
    // con GetValue: "Args" se saltaba una puerta que leia la clave exacta
    // (test_guard, auditoria de campo). Uno vacio cae en el SYS-015 del binder
    if SameText(Retirados[I, 0], AToolName) and (ArgStr(AArguments, Retirados[I, 1]) <> '') then
      // delphi_git dice sus campos (GIT-068) y delphi_edit a donde fue la
      // creacion de units (EDIT-132); por su helper, como todo mensaje
      if SameText(AToolName, 'delphi_git') then
        Exit(MsgText(SR_GIT_ARGS_RETIRADO))
      else
        Exit(MsgText(SR_EDIT_CREATEUNIT_RETIRADO));
end;

function ReglasDeLaLlamadaDenegadas(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  GitArgs: string;
begin
  // Duplicate parameter names FIRST, before normalization and before any other
  // check: two keys that normalize the same would let the gate inspect one
  // value while the binder hands the tool the other, and ExpandVirtualDrives
  // below rewrites by first exact name. Fail closed on the ambiguity.
  Result := DuplicateArgDenied(AArguments);
  if Result <> '' then
    Exit;
  // Normalization second, unconditionally: the aliases become the declared
  // names, and then the virtual drive units in the arguments become real
  // server paths before any check or any tool - by the DECLARED name, so a
  // [Contenido] mark covers its aliases too (body/text of delphi_report were
  // expanded while message was not; B-9, 10-oct-2026).
  Result := ApplyArgAliases(AToolName, AArguments);
  if Result <> '' then
    Exit;
  // una lista de textos, en UNA forma (el array) antes de que la traduccion,
  // el suelo y la pasada de UNC miren sus rutas (1.19.0)
  NormalizaListas(AToolName, AArguments);
  ExpandeUnidadesVirtuales(AToolName, AArguments);
  // un UNC que no es de ningun sitio declarado, fuera por TEXTO antes de
  // tocarlo: alargarlo abajo ya era abrir SMB hacia ese host
  Result := UncAjenoEnArgumentos(AToolName, AArguments);
  if Result <> '' then
    Exit;
  // ...y el nombre LARGO de las rutas marcadas (AlargaRutas)
  AlargaRutas(AToolName, AArguments);
  Result := '';
  // Read-only comes FIRST, for EVERY tool: LA tabla de accesos (ACCESOS,
  // LecturaDenegada), la misma que anuncia tools/list. The argument filters
  // below are universal on purpose, but letting one of them answer first
  // meant a read-only server explained a git remote policy instead of
  // saying the obvious thing: nothing writes here (v0.62). La lista de
  // mutantes estaba DOS veces (una con delphi_desktop, otra sin) y cada
  // mixta en su if, al final de la puerta (28-sep-2026)
  Result := LecturaDenegada(AToolName, AArguments);
  if Result <> '' then
    Exit;
  // EL SUELO de la jaula, para todas las tools: todo argumento marcado
  // [RutaDelServidor] que sea una ruta absoluta tiene que caer dentro de lo
  // que este workspace puede LEER. Redundante a proposito - la nota larga
  // esta sobre ArgPathOutsideDenied. Las RELATIVAS, al final (ToolCallDenied).
  Result := ArgPathOutsideDenied(AToolName, AArguments, False);
  if Result <> '' then
    Exit;
  // un parametro que la tool ya no tiene (delphi_git args desde la 1.19.0:
  // David, 14-oct-2026, el agente pide una operacion; delphi_edit createunit,
  // content y eol desde la 1.28): a donde fue, antes del SYS-015 generico
  Result := ParametroRetiradoDenegado(AToolName, AArguments);
  if Result <> '' then
    Exit;
  if SameText(AToolName, 'delphi_git') and Assigned(AArguments) then
  begin
    // An explicit URL in a git call is an outbound connection this machine
    // is about to make: the clone's, which travels in message. It goes
    // through the operator's allowlist WHOLE, as one argument (split, the
    // two halves of 'ssh://allowed:22 @other/x' had no host each and git
    // went to the other; review of addc44e). In the other commands message
    // is text - a commit's goes through -F.
    if SameText(ArgStr(AArguments, 'command').Trim, 'clone') then
      Result := GitRemoteDenied(EnComillas(UrlDeClone(ArgStr(AArguments, 'message'))));
    if Result <> '' then
      Exit;
  end;
  // Universal build-argument filter (BOTH access levels): platform, config and
  // target land in msbuild's line - through cmd.exe until 2an of 1.18.2, where
  // a metacharacter was arbitrary execution; with no shell now, this stays as
  // the second barrier. delphi_test compila por el MISMO
  // RunMsBuild y no pasa por aqui: su config la juzga el FONDO, donde vive la
  // regla del nombre (Lsp.Dproj.ConfigDelBuild, por la que pasan los dos
  // antes de la linea; 4.8, revision de la 1.18.1), y su platform la lista
  // exacta con su propio mensaje (TEST-001: lo que se puede EJECUTAR aqui).
  // Con delphi_test tambien aqui, una plataforma inventada recibia el
  // BUILD-003 generico en vez de ese (test_round10 P8, medido).
  if SameText(AToolName, 'delphi_build') then
  begin
    Result := BuildArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
  // The workspace ROOT is the jail, not a file: delete/move would relocate the
  // whole workspace and write its recoverable copy in the root's PARENT,
  // outside the roots. Refused for EVERY credential - a read-write agent does
  // it just as thoroughly as a read-only one would like to.
  if MatchText(AToolName, ['delphi_delete', 'delphi_move']) then
  begin
    Result := RootItselfDenied(ArgStr(AArguments, 'path'));
    if Result <> '' then
      Exit;
  end;
  // Universal PAServer-argument filter (BOTH access levels): profile name,
  // host, port, platform and password land on the paclient command line, and
  // the name becomes a file in %APPDATA%.
  if SameText(AToolName, 'delphi_paserver') then
  begin
    Result := PAServerArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
  // ...y el perfil de delphi_desktop, que llega a la misma linea de paclient
  // con LA misma regla: no se miraba, y un '..' en el nombre componia la ruta
  // del .profile fuera de la carpeta de perfiles (V8 de la 1.23, medido)
  if SameText(AToolName, 'delphi_desktop') then
  begin
    Result := PerfilDeLaLlamadaDenegado(ArgStr(AArguments, 'profile'));
    if Result <> '' then
      Exit;
  end;
  // Universal adb-argument filter (BOTH access levels): address and serial
  // land on the adb command line.
  if SameText(AToolName, 'delphi_adb') then
  begin
    Result := AdbArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
end;

{ La puerta de cada llamada: sus reglas y, la ULTIMA, la pasada de las rutas
  relativas del suelo (la nota sobre el suelo dice por que la ultima). }
function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
begin
  Result := ReglasDeLaLlamadaDenegadas(AToolName, AArguments);
  if Result = '' then
    Result := ArgPathOutsideDenied(AToolName, AArguments, True);
end;

type
  { Una tool que solo se anuncia donde el workspace declara A DONDE ir
    (moSinDestino): su nombre, si lo declara y la clave que la abre (lo que dice
    delphi_help). UNA tabla: la leian MotivoToolOculta y delphi_help, cada uno
    con sus nombres (B12 del revisor del paisaje de la 1.29) }
  TToolConDestino = record
    Tool: string;
    Clave: string;
    Hay: function: Boolean;
  end;

function HayProyectosDeBases: Boolean;
begin
  Result := Length(ProyectosDeConexionDeLaSesion(False)) > 0;
end;

function HayProyectosDeApis: Boolean;
begin
  Result := Length(ProyectosDeConexionDeLaSesion(True)) > 0;
end;

const
  TOOLS_CON_DESTINO: array[0..3] of TToolConDestino = (
    (Tool: 'delphi_adb'; Clave: SF_HELP_SIN_DESTINO_ADB; Hay: HayDispositivosAdb),
    (Tool: 'delphi_desktop'; Clave: SF_HELP_SIN_DESTINO_DESKTOP; Hay: HayHostsDeEscritorio),
    (Tool: 'delphi_db'; Clave: SF_HELP_SIN_DESTINO_DB; Hay: HayProyectosDeBases),
    (Tool: 'delphi_api'; Clave: SF_HELP_SIN_DESTINO_API; Hay: HayProyectosDeApis));

function ClaveQueAbreLaTool(const ATool: string): string;
begin
  for var D in TOOLS_CON_DESTINO do
    if SameText(D.Tool, ATool.Trim) then
      Exit(MsgText(D.Clave));
  Result := '';
end;

function MotivoToolOculta(const AToolName: string): TMotivoOculta;
const
  // the mailbox and the manual never disappear: they are how an agent asks
  // for help and how it reports that something is missing
  ALWAYS: array [0 .. 2] of string = ('delphi_help', 'delphi_messages',
    'delphi_report');
  // coder hides only the shipping trio; everything else is a coder's tool
  DEPLOY_ONLY: array [0 .. 2] of string = ('delphi_adb', 'delphi_paserver',
    'delphi_package');
var
  N, Prof: string;
begin
  N := SinMayusculas(AToolName.Trim);
  if MatchText(N, ALWAYS) then
    Exit(moNinguna);
  // Las vault_* se registran si CUALQUIER workspace declara vault, pero solo
  // se anuncian donde sirven: ninguna a un workspace sin vault, y las de
  // escritura (las atEscritura de LA tabla de accesos) no a uno de solo
  // lectura - eran 2.760 caracteres por ronda de tools que solo rechazan
  // (6-oct-2026). Siguen llamables: la llamada dice por que no. Por lo
  // DECLARADO, sin mirar el disco: esto corre en cada tools/list, y un vault
  // en una letra de red caida lo paraba (revision del 6-oct-2026); si la
  // carpeta no esta, la llamada lo dice.
  if N.StartsWith('vault_') and (VaultPath = '') then
    Exit(moSinVault);
  if N.StartsWith('vault_') and (AccesoDeTool(N).Acceso = atEscritura) and
     not VaultModoEscritura then
    Exit(moVaultLectura);
  // delphi_adb y delphi_desktop, solo donde el workspace declara a DONDE
  // (AdbAllowedDevices; DesktopAllowedHosts o DesktopViewHosts): sin nada toda
  // llamada se niega, y eran ~10 KB de cada tools/list (B10 de la 1.28, medido
  // en superficie-tools-1-27). Como el vault: siguen llamables y la llamada
  // dice que falta; delphi_help dice que no estan y por que.
  // delphi_db y delphi_api, igual con DbAllowedProjects / ApiAllowedProjects
  // (1.29): sin ninguno, DB-002 / API-002. Las cuatro, por LA tabla
  for var D in TOOLS_CON_DESTINO do
    if SameText(N, D.Tool) and not D.Hay() then
      Exit(moSinDestino);
  // A una credencial de SOLO LECTURA no se le anuncian las tools enteras de
  // escritura: la puerta se las niega siempre (LecturaDenegada) y solo
  // ocupaban sitio. Las mixtas se quedan, sus lecturas valen (David,
  // 6-oct-2026). Lo mismo que arriba: siguen llamables y la llamada dice por que.
  if IsReadOnlyNow and (AccesoDeTool(N).Acceso = atEscritura) then
    Exit(moCredencialLectura);
  if Length(ToolsOnly) > 0 then
  begin
    if MatchText(N, ToolsOnly) then
      Exit(moNinguna);
    Exit(moPerfil);
  end;
  Prof := ToolsProfileNow;
  if Prof = 'reader' then
  begin
    // reader: las tools que solo LEEN, las atLectura de LA tabla de accesos.
    // Era una lista de 20 nombres al lado de la tabla, y delphi_components,
    // que lee desde antes que el perfil, no estaba (depuracion de la 1.23)
    if AccesoDeTool(N).Acceso = atLectura then
      Exit(moNinguna);
    Exit(moPerfil);
  end;
  if (Prof = 'coder') and MatchText(N, DEPLOY_ONLY) then
    Exit(moPerfil);
  Result := moNinguna; // full, or an unknown profile name: hide nothing
end;

function ToolHiddenFromList(const AToolName: string): Boolean;
begin
  Result := MotivoToolOculta(AToolName) <> moNinguna;
end;

initialization
  ConstruyeAccesos; // la tabla de accesos, antes de la primera llamada

end.