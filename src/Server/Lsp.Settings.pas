unit Lsp.Settings;

{ EL LECTOR DE LA CONFIGURACION: el settings.ini junto al exe y las
  variables de entorno del lanzamiento local, leidos UNA vez (LoadSecurity),
  y lo que vale para ESTA sesion: el workspace activo con sus raices, sus
  referencias, sus permisos y su vault, las credenciales y el modo de solo
  lectura. Hay UN lector de configuracion: quien necesita una clave la pide
  aqui, por su accesor, y nadie de fuera ve las variables ni la tabla de
  workspaces (que lleva los tokens).

  Sale de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movido sin cambiar una linea de logica. Debajo tiene Lsp.Rutas y
  Lsp.Casa (la ruta del settings.ini) y Lsp.Codificacion por BomUtf8En
  (el BOM delante de una cabecera de seccion; era Lsp.Patch, un ciclo que
  se fue cuando las codificaciones salieron a su unidad, el mismo dia). La
  jaula pregunta aqui y aqui no se pregunta a la jaula. Lo nuevo de la
  mudanza son cinco lectores de una o
  dos lineas (RaicesDeLosWorkspaces, RaicesDelModoLocal, RemoteProjectsNow,
  ToolsOnly, ToolsProfileNow): lo que las puertas de Guard leian de las
  variables directamente, ahora por su accesor, como AgentConfinementNow. }

interface

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

{ Las raices y referencias DECLARADAS: las del entorno y las de cada workspace
  que no esta cerrado, en ese orden; con AConVaults, tambien sus vaults. Las
  recorren las letras de red al cargar y las notas de arranque (la lista
  estaba montada a mano dentro de LoadSecurity). Despues de LoadSecurity. }
function SitiosDeclarados(AConVaults: Boolean): TArray<string>;

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
  siquiera es nuestro. Lo mismo uno en UTF-16 big endian (FE FF): esa API
  no lo lee y no veia ninguna seccion (9.2 de la 1.18.0). }
procedure ExigeSettingsIniLegible;

{ Por que el settings.ini que esta no se pudo leer ('' si se leyo, o si no
  hay): abierto en exclusiva por otro proceso, sin permiso de lectura para
  la cuenta del servidor. Entonces no se lee nada de el - sin workspaces no
  entra nadie, y [Server] queda en sus valores por defecto -, y lo dicen las
  notas de arranque (Lsp.Host) y delphi_workspace: cerrado y nunca callado
  (David, 9-oct-2026). Se leia callado con lo que diera la API de los ini. }
function IniSinLeer: string;

{ The knowledge-vault root (Obsidian notes). Empty when unset.
  Env DELPHI_MCP_VAULT_PATH (solo el workspace por defecto), si no el
  VaultPath= del workspace activo. Canonicalized, no trailing delimiter. The vault_read/vault_search tools register only when
  VaultConfigured is true. }
function VaultPath: string;         // DELPHI_MCP_VAULT_PATH / VaultPath= del workspace
function VaultConfigured: Boolean;  // VaultPath set AND the directory exists
function VaultConfiguredAnywhere: Boolean; // algun workspace declara vault (registro)

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
{ Host names git may talk to when an agent writes an explicit URL, comma
  separated; '' (the default) means none - see GitRemoteDenied. }
function GitRemoteHosts: string;   // DELPHI_MCP_GIT_REMOTES / GitRemotes=

{ Host names delphi_paserver may DIAL when the caller names one by hand
  (test-connection host=...) O cuando un comando marca por perfil, comma
  separated. Tener un perfil en el IDE NO da permiso: cuenta SOLO la lista
  del workspace activo (v0.98; medido que el perfil ajeno marcaba igual). }
function RemoteProbeHosts: string; // DELPHI_MCP_REMOTE_HOSTS / RemoteHosts=

{ Los hosts de una de esas dos listas: separados por coma o punto y coma, sin
  blancos alrededor ni entradas vacias. UN troceador para las dos: la puerta
  de git (GitRemoteDenied) y la del sondeo (ProbeHostDenied) troceaban cada
  una por su cuenta, con la misma forma escrita dos veces. }
function HostsDeLista(const ALista: string): TArray<string>;

{ El paclient que pone la bateria (DELPHI_MCP_PACLIENT, un stub), '' si no
  hay: lo pregunta PaClientPath (Lsp.RemoteRun). Se lee en cada llamada, como
  se leia alli; aqui para que la configuracion siga teniendo UN lector. }
function PaclientDeEntorno: string;

{ '' si este servidor PUEDE abrir una conexion TCP a AHost: SOLO los hosts de
  RemoteProbeHosts del workspace activo ('*' / '0.0.0.0' = cualquiera). LA
  puerta de red: test-connection, get-sdk, remote-run Y el deploy por perfil
  (el .profile dice COMO conectar, el workspace dice SI). }
function ProbeHostDenied(const AHost: string): string;

{ Whether the READ-ONLY library zone exists at all. Default True (reading the
  RTL and the installed components is what makes an agent competent here).
  LibraryZone=0 en el workspace lo corta: reads are then confined to the workspace
  roots, exactly like writes. Field 2026-08-24: an agent noted that the zone
  GROWS by itself with every component or SDK installed, so the operator
  deserves a way to say no. }
function LibraryZoneEnabled: Boolean; // DELPHI_MCP_LIBRARY_ZONE=0 / LibraryZone=0

{ Read-only mode. Two independent sources, OR-ed together:
  - process-wide: the whole server runs read-only (--readonly flag);
  - per-request: the HTTP transport marks the current worker thread according
    to which credential the request presented (full token = read-write,
    read-only token / anonymous read-only = read-only). }
procedure SetProcessReadOnly(AValue: Boolean);
procedure SetRequestReadOnly(AValue: Boolean);

{ Whether the CURRENT request/process is read-only (for delphi_workspace). }
function IsReadOnlyNow: Boolean;

{ Lo que la jaula (Lsp.Guard), el mapa de los lugares (Lsp.Lugares) y el
  enmascarador (Lsp.Mascara) preguntan a la configuracion, y que hasta la
  1.18.0 era privado de Lsp.Guard. LoadSecurity carga el settings.ini y el
  entorno UNA vez (llamarla otra vez no hace nada); lo demas lleva su nota
  en la implementacion. }
procedure LoadSecurity;
function TWorkspaceIx1: Integer;
function HasActiveWS: Boolean;
function AgentConfinementNow: Boolean;
function SharedFoldersNow: TArray<string>;
function EsSitioConLetra(const AFull: string): Boolean;
function TodosLosVaults: TArray<string>;
function VaultModoEscritura: Boolean;
function SitiosQueNoSeTocan: TArray<string>;
function AdbTargetAllowed(const ATarget: string): Boolean;

{ Las raices de ESCRITURA de todos los workspaces declarados, en el orden
  del settings.ini, y las del modo local de lanzamiento: lo que entra en la
  lista de lugares protegidos y lo que recorre la purga del arranque, que
  son de TODO lo declarado y no de la sesion (eso es WorkspaceRoots). }
function RaicesDeLosWorkspaces: TArray<string>;
function RaicesDelModoLocal: TArray<string>;
{ Lo que vale para ESTA sesion: los proyectos que remote-run puede ejecutar
  (los RemoteRunProjects= del [Workspace.<nombre>] activo o, sin workspace,
  los de DELPHI_MCP_REMOTE_RUN_PROJECTS del modo local; uno no hereda del
  otro), la lista explicita de tools que se anuncian (DELPHI_MCP_TOOLS_ONLY,
  o si no [Tools] Only=: UNA, de todo el servidor, tambien para las sesiones
  con workspace) y el perfil de tools (el del workspace si declara uno; si
  no, DELPHI_MCP_TOOLS_PROFILE o [Tools] Profile=). }
function RemoteProjectsNow: TArray<string>;
function ToolsOnly: TArray<string>;
function ToolsProfileNow: string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  System.RegularExpressions,
  MCPServer.Types,      // BearerToken: UN lector de la cabecera Authorization
  Lsp.NetDrives,        // las letras de red de los sitios declarados
  Lsp.Texts,
  Lsp.Codificacion,     // BomUtf8En y KindDeBom: el BOM delante de una seccion, el UTF-16 BE
  Lsp.Rutas,
  Lsp.Casa;             // ServerDir: la casa del settings.ini

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
  GIniIlegible: string = '';        // por que no se lee el settings.ini (un BOM delante de una seccion, UTF-16 BE): no arranca
  GIniSinLeer: string = '';         // por que no se pudo leer el que esta (lo dice el sistema): arranca cerrado y lo dice
  GServerIniDoble: Boolean = False; // [Server] dos veces, o su DelphiVersion: la clave no se escribe
  GWorkspaceConDelphiVersion: string = ''; // un workspace con DelphiVersion= de la 1.13: la clave no se escribe
  GAllowTests: Boolean = False;     // running test suites is opt-in too
  GGitRemotes: string = '';         // hosts an explicit git URL may name
  GRemoteHosts: string = '';        // hosts a raw TCP probe may dial
  GRemoteProjects: TArray<string>;  // los del modo local (DELPHI_MCP_REMOTE_RUN_PROJECTS)
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
  GRequestReadOnly: Boolean;
  TRequestWorkspaceIx1: Integer; // workspace de la peticion HTTP (lo pone el transporte)
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

{ 'a;b;c' -> resolved roots with trailing delimiter; quotes tolerated,
  unparseable entries ignored. Shared by the global Roots= and every
  [Workspace.*] Roots=. }
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

function SitiosDeclarados(AConVaults: Boolean): TArray<string>;
begin
  Result := GRoots + GRoRoots;
  if AConVaults and (VaultNormalizado(GVaultPath) <> '') then
    Result := Result + [IncludeTrailingPathDelimiter(VaultNormalizado(GVaultPath))];
  for var K := 0 to High(GWorkspaces) do
    if not GWorkspaces[K].Invalid then
    begin
      Result := Result + GWorkspaces[K].Roots + GWorkspaces[K].ReadOnlyRoots;
      if AConVaults and (VaultNormalizado(GWorkspaces[K].VaultPath) <> '') then
        Result := Result + [IncludeTrailingPathDelimiter(
          VaultNormalizado(GWorkspaces[K].VaultPath))];
    end;
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
  // 2. la misma clave dos veces en una seccion, o la misma seccion dos veces.
  // EXCEPCION DECLARADA de la puerta de leer (LeeTexto): settings.ini no es
  // un lugar de ninguna puerta (no lo lee ninguna tool) y su lector es este
  // modulo; las lineas crudas se leen aqui solo para ver lo que la API de
  // Windows (GetPrivateProfile*) calla: lo repetido.
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
  despues de que el ini se hubiera leido y usado). B: BytesDelIni. }
function LineaConBomAntesDeSeccion(const B: TArray<Byte>): Integer;
var
  I, J, Linea: Integer;
  ConBom: Boolean;
begin
  Result := 0;
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

{ Los bytes de settings.ini: UNA lectura para las preguntas de antes de
  leerlo (un BOM delante de una seccion, el UTF-16 big endian), y sin negar
  la escritura a otro proceso - TFile.ReadAllBytes abre con
  fmShareDenyWrite y, con el fichero abierto por un editor, fallaba donde
  la API de los ini si lo lee (revision del 9.2 de la 1.18.0). Sin poder
  leerlo, False y AMotivo el del sistema: LoadSecurity no lee nada de el y
  lo dice (David, 9-oct: cerrado y nunca callado). }
function BytesDelIni(const APath: string; out ABytes: TArray<Byte>; out AMotivo: string): Boolean;
var
  H: THandle;
  S: THandleStream;
begin
  ABytes := nil;
  AMotivo := '';
  // compartido del todo, el borrado incluido: la API de los ini lo lee aunque
  // otro lo tenga abierto con acceso de borrado, y fmShareDenyNone (lectura y
  // escritura, sin FILE_SHARE_DELETE) fallaba alli con un error 32 - arrancaba
  // cerrado por un ini que se podia leer (revisor propio, 9-oct-2026)
  H := CreateFile(PChar(APath), GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AMotivo := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  try
    try
      S := THandleStream.Create(H);
      try
        SetLength(ABytes, S.Size);
        if Length(ABytes) > 0 then
          S.ReadBuffer(ABytes[0], Length(ABytes));
      finally
        S.Free;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        ABytes := nil;
        AMotivo := E.Message;
        Result := False;
      end;
    end;
  finally
    CloseHandle(H); // THandleStream no lo cierra
  end;
end;

type
  TClaveRetirada = record
    Clave, Desde: string;
  end;

const
  { Las claves de un [Workspace.<nombre>] que ya no se leen: no hacen nada, y
    el arranque lo dice (11.1 de la 1.18.0). DelphiVersion= tiene su propio
    aviso, porque ademas cambia lo que el servidor escribe. Una clave que se
    retire entra aqui con la version que la quito. }
  CLAVES_RETIRADAS: array [0 .. 1] of TClaveRetirada = (
    (Clave: 'AllowDesktopControl'; Desde: '1.0.16'), // la tool local, con su interruptor
    (Clave: 'AllowRun'; Desde: '1.1.1'));            // delphi_run

procedure LoadSecurity;
var
  IniPath: string;
  Ini: TIniFile;
  Fuera: TArray<string>;
  LineaBom: Integer;
  IniBytes: TArray<Byte>;
  IniBom: TEncKind;
  MotivoIni: string;
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
  // uno que esta y no se puede leer (abierto en exclusiva por otro, sin
  // permiso para la cuenta del servidor): no se lee nada de el - sin
  // workspaces no entra nadie - y se dice al arrancar y en delphi_workspace
  // (IniSinLeer). Se leia callado con lo que diera TIniFile: nada (David,
  // 9-oct-2026: cerrado y nunca callado)
  // la fecha ANTES de intentarlo, tambien si no se lee: sin ella,
  // delphi_workspace decia que el ini se habia tocado despues de arrancar
  // (revisor propio, 9-oct-2026)
  if TFile.Exists(IniPath) then
    GIniCargadoEn := TFile.GetLastWriteTime(IniPath);
  if TFile.Exists(IniPath) and not BytesDelIni(IniPath, IniBytes, MotivoIni) then
    GIniSinLeer := MsgFmt(SL_GUARD_INI_SIN_LEER_FMT, [IniPath, MotivoIni])
  else if TFile.Exists(IniPath) then
  begin
    LineaBom := LineaConBomAntesDeSeccion(IniBytes);
    if LineaBom > 0 then
      GIniIlegible := MsgFmt(SE_GUARD_INI_BOM_FMT, [IniPath, LineaBom])
    // ...ni uno en UTF-16 big endian o en UTF-32, que esa API no lee: sin
    // ninguna seccion se arrancaba callado (9.2 de la 1.18.0; UTF-32 medido
    // el 9-oct-2026 con GetPrivateProfileStringW)
    else if KindDeBom(IniBytes, IniBom) and (IniBom in [ekUtf16BE, ekUtf32LE, ekUtf32BE]) then
      GIniIlegible := MsgFmt(SE_GUARD_INI_CODIFICACION_FMT, [IniPath, EncName(IniBom)]);
  end;
  if TFile.Exists(IniPath) and (GIniIlegible = '') and (GIniSinLeer = '') then
  begin
    // (la fecha, arriba, ANTES de leerlo: si lo tocan mientras, se avisa de
    // mas, nunca de menos)
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
              for var R in CLAVES_RETIRADAS do
                if Ini.ValueExists(S, R.Clave) then
                  GWorkspaceNotes := GWorkspaceNotes +
                    [MsgFmt(SL_GUARD_CLAVE_RETIRADA_FMT, [S, R.Clave, R.Desde])];
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
  // Un token en el entorno con el ini sin leer: el workspace que lo ataba
  // puede estar en el, y no se sabe. Cerrado - entraba en el modo local de
  // confianza, que sin DELPHI_MCP_ROOTS lee toda la maquina, un cliente al
  // que su operador habia dado una jaula (revisor propio, 9-oct-2026)
  if (GIniSinLeer <> '') and (GStdioIx1 = 0) and
     ((GAuthToken <> '') or (GReadOnlyToken <> '')) then
    GLocalCerrado := MsgText(SF_CIERRE_INI_SIN_LEER);
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
  var Sitios := SitiosDeclarados(True);
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
  if (GIniIlegible <> '') or (GIniSinLeer <> '') then
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

const
  SESSION_TIMEOUT_DEFAULT_MIN = 720; // 12 h de inactividad
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

function HostsDeLista(const ALista: string): TArray<string>;
begin
  Result := [];
  for var H in ALista.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
    if H.Trim <> '' then
      Result := Result + [H.Trim];
end;

function PaclientDeEntorno: string;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_PACLIENT');
end;

{ Medido 2026-08-25: la lista blanca que cerro el agujero de git dejaba esta
  puerta abierta de par en par. `test-connection host=127.0.0.1 port=3131`
  marcaba el propio puerto MCP, y cualquier host:port contestaba. Misma
  primitiva, misma regla: SOLO lo que el operador escribio en RemoteHosts del
  workspace activo. Desde v0.98 ni los hosts de los perfiles del IDE: el
  perfil dice COMO conectar, el workspace dice SI. (Movida de
  Mcp.Tools.PAServer a Lsp.Guard el 2026-10-06: la comparten las tools y el
  deploy; y a Lsp.Settings, junto a la lista que lee, el 8-oct-2026.) }
function ProbeHostDenied(const AHost: string): string;
var
  H, Allowed: string;
begin
  Result := '';
  H := AHost.Trim.ToLower;
  if H = '' then
    Exit;
  Allowed := RemoteProbeHosts;
  for var A in HostsDeLista(Allowed) do
    if SameText(A, H) or (A = '*') or (A = '0.0.0.0') then
      Exit; // '*' / 0.0.0.0: el operador declaro CUALQUIER host
  Result := MsgFmt(SR_PASERVER_HOST_DENIED_FMT, [AHost.Trim, ONinguno(Allowed)]);
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

function IniSinLeer: string;
begin
  LoadSecurity;
  Result := GIniSinLeer;
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
  // uno que no se lee tampoco se escribe: el escritor lo pregunta el mismo y
  // no depende de que Wire haya parado antes (revision del 9.2 de la 1.18.0)
  if GIniIlegible <> '' then
  begin
    AError := GIniIlegible;
    Exit;
  end;
  // ...ni se dice nada aqui: ni siquiera se sabe si tiene la clave ("has no
  // DelphiVersion" era falso), y la nota de arranque del ini sin leer ya lo
  // cuenta entero (revisor propio, 9-oct-2026)
  if GIniSinLeer <> '' then
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

function RaicesDeLosWorkspaces: TArray<string>;
var
  W: TWorkspaceDef;
begin
  LoadSecurity;
  Result := nil;
  for W in GWorkspaces do
    Result := Result + W.Roots;
end;

function RaicesDelModoLocal: TArray<string>;
begin
  LoadSecurity;
  Result := GRoots;
end;

function RemoteProjectsNow: TArray<string>;
begin
  LoadSecurity;
  if HasActiveWS then
    Result := ActiveWS.RemoteProjects
  else
    Result := GRemoteProjects;
end;

function ToolsOnly: TArray<string>;
begin
  Result := GToolsOnly;
end;

function ToolsProfileNow: string;
begin
  // a workspace may carry its own profile; it wins over the global one
  Result := GToolsProfile;
  if HasActiveWS and
     (ActiveWS.Profile <> '') then
    Result := ActiveWS.Profile;
end;

end.