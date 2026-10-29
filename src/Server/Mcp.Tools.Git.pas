unit Mcp.Tools.Git;

{ delphi_git: las ordenes de git de la lista blanca sobre un repositorio de
  esta maquina - el compositor de la linea (GitLinea), el
  lanzador UNICO (GitCorre), las puertas de los remotos, de los envios y de
  la configuracion del repo, y sus respuestas (GitExito / GitFallo, la
  pagina de la salida).

  Sale de Mcp.Tools.Workspace el 8-oct-2026 (la 1.18.0, la version de la
  limpieza), movida sin cambiar una linea: "donde esta git" se contestaba
  "en Workspace", que nadie adivina. La puerta de los remotos
  (GitRemoteDenied) y la clasificacion en consulta o escritura viven en
  Lsp.Args; la jaula, en Lsp.Guard. Desde la 1.19.0 no hay argumentos
  libres: cada comando compone su orden con campos que elige (David,
  14-oct-2026: el agente pide una operacion). }

interface

uses
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts live there, and attributes are interface-level
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  { Sin "args" desde la 1.19.0 (David, 14-oct-2026): el agente pide una
    OPERACION y el servidor compone la orden ELIGIENDO de lo que sabe - una
    revision que git encuentra, un nombre que git admite, un remoto del
    repo, una ruta del repo -; ningun texto del agente llega a git como
    opcion. Los campos son los que USAMOS; lo que haga falta despues se
    anade aqui, con su caso. }
  TDelphiGitParams = class
  private
    FRepo: string;
    FCommand: string;
    FPaths: string;
    FTo: string;
    FStaged: Boolean;
    FFormat: string;
    FContext: Integer;
    FCount: Integer;
    FSearch: string;
    FPatch: Boolean;
    FBranch: string;
    FRemote: string;
    FAction: string;
    FName: string;
    FCreate: Boolean;
    FMessage: string;
    FPath: string;
    FRef: string;
    FOffset: Integer;
  public
    [SchemaDescription(SP_WS_REPO)]
    [Required]
    [RutaDelServidor]
    property Repo: string read FRepo write FRepo;
    [SchemaDescription(SP_WS_COMMAND)]
    [Required]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_GIT_PATHS)]
    [JsonComoTexto('string')]
    [RutaDelServidor]
    [RutaRelativa]
    property Paths: string read FPaths write FPaths;
    [SchemaDescription(SP_GIT_TO)]
    property &To: string read FTo write FTo;
    [SchemaDescription(SP_GIT_STAGED)]
    property Staged: Boolean read FStaged write FStaged;
    [SchemaDescription(SP_GIT_FORMAT)]
    property Format: string read FFormat write FFormat;
    [SchemaDescription(SP_GIT_CONTEXT)]
    property Context: Integer read FContext write FContext;
    [SchemaDescription(SP_GIT_COUNT)]
    property Count: Integer read FCount write FCount;
    [SchemaDescription(SP_GIT_SEARCH)]
    [Contenido]
    property Search: string read FSearch write FSearch;
    [SchemaDescription(SP_GIT_PATCH)]
    property Patch: Boolean read FPatch write FPatch;
    [SchemaDescription(SP_GIT_BRANCH)]
    property Branch: string read FBranch write FBranch;
    [SchemaDescription(SP_GIT_REMOTE)]
    property Remote: string read FRemote write FRemote;
    [SchemaDescription(SP_GIT_ACTION)]
    property Action: string read FAction write FAction;
    [SchemaDescription(SP_GIT_NAME)]
    property Name: string read FName write FName;
    [SchemaDescription(SP_WS_CREATE)]
    property Create: Boolean read FCreate write FCreate;
    [SchemaDescription(SP_WS_MESSAGE)]
    [Contenido]
    property Message: string read FMessage write FMessage;
    [SchemaDescription(SP_WS_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_WS_REF)]
    property Ref: string read FRef write FRef;
    [SchemaDescription(SP_WS_OFFSET_GIT)]
    property Offset: Integer read FOffset write FOffset;
  end;

  TDelphiGitTool = class(TMCPToolBase<TDelphiGitParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiGitParams): string; override;
  public
    constructor Create; override;
  end;

{ ADir tiene su .git: una carpeta, o un FICHERO "gitdir: ..." (un worktree
  enlazado, un submodulo). La pregunta barata de "aqui hay un repo" antes de
  preguntarselo a git; estaba escrita tres veces, y clone solo miraba la
  carpeta (R3 del censo de Fable, depuracion de la 1.23). }
function TieneGit(const ADir: string): Boolean;
{ La rama de ARepo, preguntada a git: symbolic-ref, que da tambien la de un
  worktree enlazado y la de un repo sin commits; con HEAD suelto, el commit
  corto y ' (detached)'. '' si git no la da o si el repo, su carpeta de git o
  la comun no se pueden LEER (la jaula de las consultas de delphi_git).
  delphi_projects la leia de .git\HEAD a mano: cortaba fix/x en x y en un
  worktree enlazado no daba ninguna (medido el 23-oct-2026). }
function RamaDelRepo(const ARepo: string): string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.Generics.Collections, // la cache por carpeta del gitdir (9.A)
  System.SyncObjs,             // su cerrojo
  System.IOUtils,
  System.RegularExpressions,
  Winapi.Windows,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.BuildRunner,
  Lsp.Guard,
  Lsp.Patch,     // EscribeTexto: la puerta de escribir, con el temporal como lugar
  Lsp.Codificacion, // ekUtf8
  Lsp.NetDrives,
  Lsp.Sandbox,
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.ProcessLaunch, // EnComillas: cada campo, UN argumento de la linea de git
  Lsp.Json,          // ListaDeTextos: la lista de "paths"
  Lsp.Args,
  Lsp.Lugares,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Mascara,
  Lsp.Listas;

// la tool git va por delante de sus compositores
function GitExito(const ACuerpo: string; AExit: Integer): string; forward;
function GitFallo(ACodigo: Cardinal; const ASalida: string): string; forward;

{ TDelphiGitTool }

constructor TDelphiGitTool.Create;
begin
  inherited;
  FName := 'delphi_git';
  FDescription := SD_WS_GIT;
end;


{ LAS RUTAS de "paths", de todos los comandos que las llevan (status, diff,
  log, show, add, restore, stash push): cada una es un fichero o carpeta DE
  ESTE repo, con su nombre tal cual (sin comodines), y sale como "--" y
  :(literal)<relativa> entre comillas - :(literal,icase) si ASinMayusculas,
  lo que git dice del repo (RepoSinMayusculas) -, lista para el final de la
  linea de git: detras de "--" nada es una opcion. Con AEscribeFicheros cada ruta
  pasa por la puerta del escritor (stash push reescribe el fichero; los
  demas solo leen o tocan el indice). '' = bien; si no, la negativa
  (GIT-012, con AComando). Era el bucle de stash push y restore, cada uno
  con su texto (1.7.6); desde la 1.19.0, el de todos. ACarpetas: la carpeta
  de cada ruta (ella misma si es una carpeta), para quien tiene que soltar
  lo nuestro de ahi antes de que git la reescriba. ARelativas: las mismas
  rutas sin magia, para la orden de git que no la admite (check-ignore, de
  IgnoradosDeGit; 1.19.3). }
function RutasDeGit(const ARepo: string; const ALista: TArray<string>;
  AEscribeFicheros, ASinMayusculas: Boolean; const AComando: string;
  out ARutas: string; out ACarpetas, ARelativas: TArray<string>): string;
var
  Base, Ruta, Rel: string;
  I: Integer;
begin
  Result := '';
  ARutas := '';
  ACarpetas := nil;
  ARelativas := nil;
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARepo));
  for I := 0 to High(ALista) do
  begin
    // Una ruta de "paths" es UNA RUTA: los jueces de texto de toda ruta
    // (PathAnomaly: unidad virtual no servida, prefijo de dispositivo,
    // comodin, flujo alternativo, controles). Una relativa ([RutaRelativa])
    // es de la tool, y el suelo de la entrada no la mira: un 'srvq:\x' no
    // servido llegaba a git como nombre (GIT-060) en vez de CFG-006 (medido
    // por la migracion de test_git_jaula J19, 1.19.0)
    Result := PathAnomaly(ALista[I]);
    if Result <> '' then
      Exit;
    // Una ruta de ESTE repo, con su nombre tal cual: un comodin no es un
    // nombre en Windows, y lo que GetFullPath no entiende no es una ruta.
    Ruta := '';
    try
      if (ALista[I].Trim <> '') and
         not (ALista[I].Contains('*') or ALista[I].Contains('?')) then
        Ruta := SinBarraFinal(TPath.GetFullPath(
          TPath.Combine(Base, ConBarrasDeWindows(ALista[I]))));
    except
      Ruta := '';
    end;
    // dentro del repo, por EL juez de rutas (el del sistema de ficheros, H1 de la
    // 1.23), y su trozo por el corte del mismo texto (TrozoBajo)
    if (Ruta = '') or not TrozoBajo(Base, Ruta, Rel) then
      Exit(MsgFmt(SR_GIT_STASH_RUTA_FMT, [AComando, ALista[I], ARepo]));
    // Devolver un fichero a HEAD es ESCRIBIRLO: la pregunta de todo
    // escritor, por la ruta real de cada uno.
    if AEscribeFicheros then
    begin
      Result := EscrituraDenegada(Ruta);
      if Result <> '' then
        Exit;
    end;
    Rel := ConBarrasNormales(Rel);
    if Rel = '' then
      Rel := '.'; // la carpeta del propio repo
    // :(literal): el nombre es el nombre, sin comodines ni magia; y en un
    // repo que git dice que no distingue mayusculas, icase (RepoSinMayusculas)
    if ARutas = '' then
      ARutas := ' --';
    ARutas := ARutas + ' ' + EnComillas(IfThen(ASinMayusculas, ':(literal,icase)', ':(literal)') + Rel);
    ARelativas := ARelativas + [Rel];
    // la carpeta de la ruta, UNA vez cada una (dos ficheros de la misma
    // carpeta eran dos avisos, uno detras de otro)
    if not TDirectory.Exists(Ruta) then
      Ruta := ExtractFileDir(Ruta);
    if not RutaEnLista(Ruta, ACarpetas) then
      ACarpetas := ACarpetas + [Ruta];
  end;
end;

{ LO NUESTRO, fuera de lo que git recorre del arbol del agente: la papelera
  (TrashFolderName) y la temporal de versiones viejas (TempFolderName), a
  cualquier profundidad, como pathspec de EXCLUSION (el mecanismo de git, sin
  tocar el .gitignore del agente). Va detras del "--" de status y de add: sin
  rutas positivas, git entiende "todo menos esto"; nombrada a proposito,
  tampoco entra. El .gitignore que escribe delphi_create solo cubre la
  carpeta del proyecto: medido el 15-oct-2026 (Hermes), add "." metia en el
  indice app/__delphi-patch/<dia>/U.pas, el before-restore y su marca .by. }
function LoNuestroFuera: string;
begin
  Result := ' ' + EnComillas(':(exclude,glob)**/' + TrashFolderName + '/**') +
    ' ' + EnComillas(':(exclude,glob)**/' + TempFolderName + '/**');
end;

{ LA orden de estado de esta tool: porcelana con la rama y LO NUESTRO fuera.
  La usan command=status y lo que se ensena del arbol tras un stash pop o un
  commit que no hizo nada: el status que git imprime solo en esos dos no
  pasa por LoNuestroFuera y listaba la papelera como "Untracked files" (V66
  de la 1.23.1). ACola: ' --' o las rutas, con el suyo. }
function OrdenDeEstado(const ACola: string): string;
begin
  Result := 'status --porcelain=v1 -b' + ACola + LoNuestroFuera;
end;

{ EL git del servidor, por su RUTA COMPLETA: git.exe en el PATH con el que
  arranco el proceso del servidor (el del operador) y SOLO ahi
  (ProgramaEnPath: ni la carpeta actual ni la del exe). Se lanzaba por su
  nombre a secas, y a un nombre sin carpeta CreateProcess lo busca PRIMERO en
  la carpeta del exe y en la CARPETA ACTUAL del proceso: en el servicio es la
  del servidor, pero por stdio es la de quien lo lanza -el repo del agente- y
  un git.exe plantado ahi corria con la cuenta del servidor (medido el
  14-oct-2026 con una sonda inerte: test_git_por_ruta_119). La regla del
  13-oct: el programa por su ruta completa, encontrada donde el agente no
  escribe. Sin git, GIT-050 aqui, antes de lanzar nada. Se resuelve en cada
  llamada (SearchPath, microsegundos) y sin estado compartido entre hilos. }
function RutaDeGit: string;
begin
  // ...y donde el agente no escribe (ProgramaDelOperador, B1 del cierre)
  Result := ProgramaDelOperador('git.exe', GetEnvironmentVariable('PATH'));
  if Result = '' then
    raise Exception.Create(MsgFmt(SR_GIT_NO_HAY_GIT_FMT, [MsgText(SF_GIT_SIN_GIT_EN_PATH)]));
end;

{ LA LINEA de git, por UN compositor: git por su ruta (RutaDeGit), -C con la
  carpeta de la llamada - por el compositor de la casa (EnComillas), como
  todo argumento -, lo que lo fija (AFijado: --git-dir...) y el comando. Se
  componia a mano en cada sitio, con -C "%s": una carpeta acabada en barra
  invertida se comia la comilla de cierre y el resto de la linea entraba en
  el argumento de -C (medido en la 1.7.6: GIT-036, "cannot change to ...";
  cuarta revision de la 1.7.7). }
function GitLinea(const ARepo, AFijado, AResto: string): string;
begin
  // La orden de red no hereda una recursion a remotos de submodulos sin juzgar.
  var Comando := PrimerTrozo(AResto, [' ']);
  var Resto := AResto;
  if MatchText(Comando, ['fetch', 'pull', 'push']) then
    Resto := Comando + ' --no-recurse-submodules' + Copy(AResto, Length(Comando) + 1, MaxInt);
  // Nunca ejecutar los hooks ni el monitor de un repo del workspace.
  // El directorio del servidor no admite escrituras de los clientes.
  // La regla general tambien manda en switch/restore y en los hijos de Git.
  // core.quotePath=false: git entrecomillaba en octal todo nombre con acento
  // ("Caf\303\251.txt"): el agente lo leia en status, diff y show sin poder
  // usarlo de ruta, y el juez de protegidos moria con SYS-011 al hacer una
  // ruta de eso (medido el 15-oct-2026). Es el interruptor del propio git; en
  // Windows un nombre valido no lleva comilla, barra invertida ni controles,
  // asi que con el git no entrecomilla ninguno. Lo que aun llegue con
  // comillas (la ruta de un fichero de git bajo el --git-dir) lo lee
  // LeeRutaDeGit.
  Result := EnComillas(RutaDeGit) + ' -c submodule.recurse=false -c core.fsmonitor=false ' +
    '-c core.quotePath=false ' +
    '-c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=' +
    EnComillas(ServerTempDir('git-hooks-off')) + ' -C ' +
    EnComillas(ARepo) + AFijado + ' ' + Resto;
end;

{ git, LANZADO por un solo sitio: la linea del compositor por el lanzador de
  la casa. El servidor SIN git lo dice RutaDeGit (GIT-050) antes de lanzar
  nada; aqui queda la segunda barrera: un git que estaba al resolver y no al
  lanzar (error 2) recibe el mismo GIT-050 con su error, en vez de "[SYS-006
  INTERNAL] ... CreateProcess failed (2)", que no decia ni que falta ni de
  quien es el arreglo (medido el 30-sep-2026 en una maquina sin git: init y
  status). Sigue siendo una excepcion - quien pregunta para juzgar no toma un
  fallo por un "no hay" -, con el mensaje ya etiquetado. }
function GitCorre(const ARepo, AFijado, AResto: string; ATimeoutMs: Integer;
  out ACodigo: Cardinal): string;
begin
  try
    // GIT_ADVICE=0: sin los consejos de git ("hint:", "(use git ...)"). Son
    // para quien teclea git, y por esta tool casi ninguno se puede seguir:
    // restore es --staged, no hay -f, ni rebase, ni config de advice, que
    // todos nombran. Hermes (15-oct-2026, sobre la 1.19.2) siguio el "use git
    // restore to discard" de un stash pop y el arbol siguio sucio. Es el
    // interruptor del propio git (2.46 en adelante): quita los consejos y deja
    // los hechos (medido con git 2.53 en stash pop, commit, add, merge, pull y
    // push); un git anterior lo ignora y sigue GIT-006 de segunda barrera.
    // LC_ALL=C / LANGUAGE=C: git habla en ingles haga lo que haga el sistema,
    // porque lo que de su salida se JUZGA por prosa (fast-forward, --no-ff,
    // "specify the URL", las pistas de abajo) es ingles; un git traducido las
    // dejaba sin casar (lote 4 del censo de jueces, 18-oct-2026; 1.21.4).
    // phPorLinea: su texto es UTF-8 y lo de los ficheros (diff, show) va tal
    // cual - un fuente ANSI, en la ANSI de la maquina (completo de Opus de la
    // 1.22.1: salia leido en la de la consola, 1252 leido en 850)
    Result := RunCapturedIn(GitLinea(ARepo, AFijado, AResto), '', ATimeoutMs,
      ACodigo, EntornoSinConfiguracion(['GIT_TERMINAL_PROMPT=0', 'GCM_INTERACTIVE=never',
      'GIT_ADVICE=0', 'LC_ALL=C', 'LANGUAGE=C']), phPorLinea);
  except
    on E: EOSError do
    begin
      // solo el 2: un git que ESTA y no arranca (5, 193) no es "no hay
      // git": sigue con el mensaje de siempre
      if E.ErrorCode = ERROR_FILE_NOT_FOUND then
        raise Exception.Create(MsgFmt(SR_GIT_NO_HAY_GIT_FMT,
          [MsgFmt(SF_GIT_GIT_NO_ARRANCA_FMT, [E.ErrorCode])]));
      raise;
    end;
  end;
end;

{ La configuracion LOCAL tambien manda programas aunque args sea limpio.
  Se lee sin includes: una inclusion del repo puede sacar la lectura de la
  jaula y esconder un filtro. La configuracion del servidor sigue siendo suya. }

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  ADelRepo: Boolean; out ACarpeta: string; out ANoEsta: Boolean): string; forward;

function RemotosDelRepo(const ARepo, AFijado: string;
  out ANombres: TArray<string>): Boolean; forward;

function GitContesta(const ARepo, AFijado, APregunta: string;
  out ALineas: TArray<string>; ATalCual: Boolean = False): Boolean; forward;

{ Medido con objetos LFS ausentes: estas ordenes materializan el arbol.
  Los filtros clean de add/commit/status no descargan objetos. }
function GitMaterializaArbol(const ACmd, AAccion: string): Boolean;
begin
  Result := MatchText(ACmd, ['clone', 'switch', 'merge', 'pull']);
  if ACmd = 'stash' then
    Result := MatchText(AAccion.Trim, ['', 'push', 'pop'])
  else if ACmd = 'worktree' then
    Result := SameText(AAccion.Trim, 'add');
end;

{ Lo que git hace con el ARBOL DE TRABAJO en cada orden, para quien tiene
  que mirarlo ENTERO antes de dejarselo (EnlaceAjenoEn): True si lo RECORRE
  -status, diff y add lo leen fichero a fichero, y un junction como si
  fuera una carpeta- o lo REESCRIBE (AEscribe: switch de rama, merge -abort
  incluido: deshace escribiendo-, pull, stash push y pop: unpack_trees
  escribe y borra a traves del junction). Lo demas no lo toca: log, show,
  branch, tag, config, fetch, push, ls-remote, init, commit (el indice),
  restore --staged y untrack (rm --cached: el indice), switch -c (sale de HEAD), clone y worktree
  add (una carpeta nueva; remove tiene su GIT-020). Hermano de
  GitMaterializaArbol (que ordenes bajan objetos LFS) y del juez de
  GitReescribeProtegido (que ficheros cambiaria, preguntado a git): tres
  preguntas distintas sobre las mismas ordenes. Medido el 14-oct-2026
  contra la 1.18.3+: add paths=["."] metia lo de detras de un junction en
  el indice y switch, merge, pull y stash lo borraban o reescribian
  (revision A del cierre de la 1.19.0; test_git_enlace_arbol_119). }
function GitTocaArbol(const ACmd, AAccion: string; ACrear: Boolean;
  out AEscribe: Boolean): Boolean;
begin
  AEscribe := (SameText(ACmd, 'switch') and not ACrear) or
    MatchText(ACmd, ['merge', 'pull']) or
    (SameText(ACmd, 'stash') and MatchText(AAccion.Trim, ['', 'push', 'pop']));
  Result := AEscribe or MatchText(ACmd, ['status', 'diff', 'add']);
end;

{ Los metadatos de git no son del arbol: el recorredor los salta (la puerta
  del repo ya los juzgo por su sitio real: DondeViveElRepo + PathDenied). }
function EsCarpetaGit(const APath: string): Boolean;
begin
  Result := SameFileName(TPath.GetFileName(SinBarraFinal(APath)), '.git');
end;

function ConfiguracionGitDenegada(const ARepo, ARaiz: string;
  AExaminarLfs: Boolean; var AFijado: string): string;
var
  Salida, RutaLfs, Endpoint: string;
  Codigo: Cardinal;
  HayLfs, HayFuenteLfs: Boolean;
  NombresLfs: TArray<string>;
  FicherosLfs, FicherosIndice: TArray<string>;

  function NombreDelEndpoint(const ALinea: string): string;
  var
    P: Integer;
  begin
    if ALinea.StartsWith('Endpoint (') then
    begin
      P := Pos(')', ALinea);
      if P > 11 then Exit(Copy(ALinea, 11, P - 11));
    end;
    if Length(NombresLfs) = 1 then Exit(NombresLfs[0]);
    Result := '(default: git-lfs)';
  end;

  function EndpointLfsDenegado(const ADireccion, ARemoto: string): string;
  var
    Carpeta, Base: string;
    NoEsta: Boolean;
  begin
    Base := ARaiz;
    if Base = '' then Base := ARepo;
    // El endpoint LFS se juzga con EL MISMO juez que un remoto: la red por
    // los hosts de GitRemotes, la carpeta por la puerta de carpetas del
    // workspace. Su valor nunca se muestra: la negativa nombra el remoto.
    if DireccionDeRemotoDenegada('lfs', ADireccion, Base, True, Carpeta, NoEsta) <> '' then
      Result := MsgFmt(SR_GIT_LFS_ENDPOINT_FMT, [ARemoto])
    else
      Result := '';
  end;

  function RevisaConfiguracion(const ATexto: string; ASoloLocal: Boolean): string;
  var
    Registro, Clave, Valor: string;
    Registros: TArray<string>;
    P: Integer;
  begin
    Result := '';
    Registros := ATexto.Split([#0], TStringSplitOptions.ExcludeEmpty);
    if Odd(Length(Registros)) then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    for var I := 0 to Length(Registros) div 2 - 1 do
    begin
      if IndexStr(Registros[I * 2],
        ['system', 'global', 'local', 'worktree', 'command']) < 0 then
        Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if not ASoloLocal or
         (IndexStr(Registros[I * 2], ['local', 'worktree']) >= 0) then
      begin
        Registro := Registros[I * 2 + 1];
        P := Pos(#10, Registro);
        // Una clave sin valor es un booleano true valido en la sintaxis de git.
        if P = 0 then
        begin
          Clave := LowerCase(Registro);
          Valor := 'true';
        end
        else
        begin
          Clave := LowerCase(Copy(Registro, 1, P - 1));
          Valor := Copy(Registro, P + 1, MaxInt);
        end;
        // El valor no sale en el rechazo: podria llevar credenciales.
        // LISTA BLANCA: claves conocidas sin programas ni rutas de lectura.
        // No se permiten familias enteras: gc.*, diff.* o remote.* crecen.
        var Permitida := MatchText(Clave, [
          'core.repositoryformatversion', 'core.filemode', 'core.bare',
          'core.logallrefupdates', 'core.symlinks', 'core.ignorecase',
          'core.autocrlf', 'core.eol', 'core.safecrlf', 'core.precomposeunicode',
          'core.protectntfs', 'core.protecthfs', 'core.worktree',
          'core.longpaths', 'core.fscache', 'core.untrackedcache',
          'user.name', 'user.email', 'user.signingkey',
          'commit.gpgsign', 'tag.gpgsign', 'extensions.worktreeconfig',
          'extensions.objectformat', 'fetch.recursesubmodules',
          'push.recursesubmodules', 'submodule.recurse', 'push.default',
          'pull.rebase']);
        var Partes := Clave.Split(['.']);
        if Length(Partes) >= 3 then
        begin
          var Familia := Partes[0];
          var Campo := Partes[High(Partes)];
          if Familia = 'remote' then
            Permitida := MatchText(Campo, ['url', 'pushurl', 'fetch', 'push',
              'mirror', 'tagopt', 'prune', 'prunetags'])
          else if Familia = 'branch' then
            Permitida := MatchText(Campo, ['remote', 'pushremote', 'merge', 'description'])
          else if Familia = 'submodule' then
            Permitida := MatchText(Campo, ['url', 'path', 'active', 'ignore',
              'branch', 'fetchrecursesubmodules']);
        end;
        // LFS es el UNICO programa local admitido, con su comando estandar EXACTO.
        if Clave = 'filter.lfs.clean' then
          Permitida := Valor = 'git-lfs clean -- %f'
        else if Clave = 'filter.lfs.smudge' then
          Permitida := Valor = 'git-lfs smudge -- %f'
        else if Clave = 'filter.lfs.process' then
          Permitida := Valor = 'git-lfs filter-process'
        else if Clave = 'filter.lfs.required' then
          Permitida := SameText(Valor, 'true');
        // El endpoint pasa por EL juez de direcciones de los remotos.
        if MatchText(Clave, ['lfs.url', 'lfs.pushurl']) or
           ((Length(Partes) >= 3) and (Partes[0] = 'remote') and
            MatchText(Partes[High(Partes)], ['lfsurl', 'lfspushurl'])) then
        begin
          Permitida := True;
          if AExaminarLfs then
          begin
            var Remoto := NombreDelEndpoint('');
            if Partes[0] = 'remote' then
              Remoto := Copy(Clave, 8, Length(Clave) - 8 - Length(Partes[High(Partes)]));
            Result := EndpointLfsDenegado(Valor, Remoto);
            if Result <> '' then Exit;
          end;
        end
        else if Clave = 'lfs.repositoryformatversion' then
          Permitida := Valor = '0';
        if not Permitida then
          Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, [Clave]));
      end;
    end;
  end;

  function RevisaFuenteLfs(const AArgumento: string): string;
  begin
    Salida := GitCorre(ARepo, AFijado,
      'config --no-includes --null --list --show-scope ' + AArgumento, 60000, Codigo);
    if Codigo <> 0 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    Result := RevisaConfiguracion(Salida, False);
  end;

begin
  Result := '';
  Salida := GitCorre(ARepo, AFijado,
    'config --no-includes --null --list --show-scope', 60000, Codigo);
  if Codigo <> 0 then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  HayLfs := ContainsText(Salida, 'filter.lfs.');
  HayFuenteLfs := False;
  NombresLfs := nil;
  if AExaminarLfs and not RemotosDelRepo(ARepo, AFijado, NombresLfs) then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Result := RevisaConfiguracion(Salida, True);
  if Result <> '' then Exit;
  if not AExaminarLfs then Exit;
  if ARaiz <> '' then
  begin
    RutaLfs := TPath.Combine(ARaiz, '.lfsconfig');
    if TFile.Exists(RutaLfs) then
    begin
      HayFuenteLfs := True;
      if (ReadPathDenied(RutaLfs) <> '') or EsEnlace(RutaLfs) then
        Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, ['.lfsconfig']));
      Result := RevisaFuenteLfs('--file ' + EnComillas(RutaLfs));
      if Result <> '' then Exit;
    end;
    // Se midio la precedencia: fichero de trabajo, indice y despues HEAD.
    if not HayFuenteLfs then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-files --stage -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        HayFuenteLfs := True;
        Result := RevisaFuenteLfs('--blob :.lfsconfig');
        if Result <> '' then Exit;
      end;
    end;
  end;
  // HEAD sirve tambien a un bare y a clone --no-checkout.
  if not HayFuenteLfs then
  begin
    Salida := GitCorre(ARepo, AFijado, 'rev-parse --verify --quiet HEAD', 60000, Codigo);
    if Codigo = 0 then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-tree --name-only HEAD -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        Result := RevisaFuenteLfs('--blob HEAD:.lfsconfig');
        if Result <> '' then Exit;
      end;
    end
    else if Codigo <> 1 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  end;
  if not HayLfs then Exit;
  // El juez de "este repo USA LFS" es git (norma 6 del paisaje): ls-files por
  // TODAS las fuentes de atributos (tambien info/attributes y
  // core.attributesFile). Que filter.lfs.* este en la config del SISTEMA
  // (git-lfs instalado) NO es usarlo: GIT-061 negaba switch/merge/stash/pull y
  // worktree add en CUALQUIER repo con origin en GitHub, sin tocar la red
  // (falso positivo medido, 2.1h/9.A). Con el arbol materializado y sin
  // ficheros LFS, el checkout no hara smudge: no hay endpoint que tocar. Un
  // indice vacio (un clone recien traido --no-checkout, un bare) no sabe aun
  // de sus ficheros: ahi se mantiene el examen de siempre. Un fallo de git al
  // juzgar no es un "vale".
  if not GitContesta(ARepo, AFijado, 'ls-files ' + EnComillas(':(attr:filter=lfs)'), FicherosLfs) then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  if Length(FicherosLfs) = 0 then
  begin
    if not GitContesta(ARepo, AFijado, 'ls-files', FicherosIndice) then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    if Length(FicherosIndice) > 0 then Exit;
  end;
  // El programa estandar interpreta la precedencia; no hacemos otro lector.
  // Su salida (rutas y posibles credenciales) nunca se devuelve al agente.
  Salida := GitCorre(ARepo, AFijado, 'lfs env', 60000, Codigo);
  if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Endpoint := '';
  for var Linea in LineasDelTexto(Salida) do
    if Linea.StartsWith('Endpoint') then
    begin
      var P := Pos('=', Linea);
      if P = 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      var Direccion := Copy(Linea, P + 1, MaxInt).Trim;
      P := Pos(' (auth=', Direccion);
      if P > 0 then Direccion := Copy(Direccion, 1, P - 1);
      if Direccion = '' then Continue;
      Result := EndpointLfsDenegado(Direccion, NombreDelEndpoint(Linea));
      if Result <> '' then Exit;
      if Endpoint = '' then Endpoint := Direccion;
    end;
  // Fijarlo evita que un checkout cambie .lfsconfig durante la misma orden.
  // La precedencia de -c lfs.url se midio contra .lfsconfig y remote.*.lfsurl.
  AFijado := AFijado + ' -c ' + EnComillas('lfs.url=' + Endpoint) +
    ' -c ' + EnComillas('lfs.pushurl=' + Endpoint);
end;

{ DONDE VIVE el repo de ARepo (o de una carpeta de dentro), preguntado a git:
  su carpeta de git (AGitDir: la de ESTA copia de trabajo), la comun (AComun:
  la del repo principal, cuando ARepo es un worktree enlazado) y la raiz del
  arbol de trabajo (ARaiz: '' en un repo bare y dentro de la propia .git).
  Con barras de Windows. False si git no lo da: ASalida y ACodigo son
  entonces su respuesta ("not a git repository").

  Es la pregunta de la JAULA de git (la tool no deja trabajar en un repo que
  vive fuera de las raices) y la de quien suelta lo nuestro antes de que git
  reescriba el arbol; worktree add ya preguntaba la raiz.

  git contesta una carpeta por linea y su salida llega mezclada con la de
  errores: cuentan SOLO las lineas que son una carpeta que existe, en su
  orden. Un aviso de git con exit 0 hacia la raiz de varias lineas, y no
  casaba con nada, en silencio. }
function DondeViveElRepo(const ARepo: string; out AGitDir, AComun, ARaiz,
  ASalida: string; out ACodigo: Cardinal): Boolean;
var
  Linea, Ruta: string;
  Carpetas: TArray<string>;
begin
  AGitDir := '';
  AComun := '';
  ARaiz := '';
  ASalida := GitCorre(ARepo, '', 'rev-parse --absolute-git-dir ' +
    '--git-common-dir --show-toplevel', 60000, ACodigo);
  Carpetas := nil;
  for Linea in LineasDelTexto(ASalida) do
  begin
    Ruta := ConBarrasDeWindows(Linea.Trim);
    if Ruta = '' then
      Continue;
    try
      // la comun llega RELATIVA a ARepo (..\..\.git) fuera de un worktree
      // enlazado (medido, git 2.53)
      Ruta := SinBarraFinal(
        TPath.GetFullPath(TPath.Combine(ARepo, Ruta)));
      // git contesta la ruta REAL: bajo una raiz declarada en una letra de
      // red es su UNC, y la puerta juzga por la forma declarada. Se le da
      // escrita asi (Lsp.Lugares.FormaDeclarada; era GIT-041, 30-sep-2026)
      Ruta := FormaDeclarada(Ruta, ARepo);
      if TDirectory.Exists(Ruta) then
        Carpetas := Carpetas + [Ruta];
    except
      // lo que no es una ruta es un aviso de git
    end;
  end;
  // las tres, o las dos primeras cuando no hay arbol de trabajo (git sale
  // entonces con 128 y las ha dado igual)
  Result := (Length(Carpetas) = 2) or (Length(Carpetas) = 3);
  if not Result then
    Exit;
  AGitDir := Carpetas[0];
  AComun := Carpetas[1];
  if Length(Carpetas) = 3 then
    ARaiz := Carpetas[2];
end;

var
  { La cache por carpeta del gitdir (9.A): carpeta(lower) -> gitdir#10comun,
    '' = no es repo. Positivo y negativo, de por vida: el estado git de una
    carpeta no cambia por las tools (--separate-git-dir esta prohibido en
    init/clone, Lsp.Args), asi que la cache no se queda rancia. }
  GCacheGitDir: TDictionary<string, string>;
  GCacheGitDirLock: TCriticalSection;

{ El gancho que la puerta de ESCRITURA (Lsp.Guard.DameGitDirDeCarpeta) usa
  para ver si una ruta es metadato de un gitdir SEPARADO (sin segmento .git).
  Un rev-parse por carpeta (medido: ~43 ms con el spawn de git), CACHEADO por
  carpeta. Por DondeViveElRepo, el mismo juez que la jaula de git. }
function GitDirDeCarpeta(const ACarpeta: string; out AGitDir, AComun: string): Boolean;
var
  Clave, Guardado, Raiz, Salida: string;
  Codigo: Cardinal;
  P: Integer;
begin
  AGitDir := '';
  AComun := '';
  Clave := LowerCase(ACarpeta);
  GCacheGitDirLock.Enter;
  try
    if GCacheGitDir.TryGetValue(Clave, Guardado) then
    begin
      if Guardado = '' then
        Exit(False);
      P := Pos(#10, Guardado);
      AGitDir := Copy(Guardado, 1, P - 1);
      AComun := Copy(Guardado, P + 1, MaxInt);
      Exit(True);
    end;
  finally
    GCacheGitDirLock.Leave;
  end;
  Result := DondeViveElRepo(ACarpeta, AGitDir, AComun, Raiz, Salida, Codigo);
  if not Result then
  begin
    AGitDir := '';
    AComun := '';
  end;
  GCacheGitDirLock.Enter;
  try
    if Result then
      GCacheGitDir.AddOrSetValue(Clave, AGitDir + #10 + AComun)
    else
      GCacheGitDir.AddOrSetValue(Clave, '');
  finally
    GCacheGitDirLock.Leave;
  end;
end;

{ El gancho SIN cache (Lsp.Guard.DameRepoDeCarpeta): el gitdir, el comun y la
  raiz del arbol de una carpeta, por DondeViveElRepo, para decidir si la copia
  de un arbol lleva su git dentro (V19). Sin cache: un "no es repo" de antes
  de un init se quedaria para siempre (como en RamaDelRepo). False si git no
  lo reconoce o no esta (GIT-050). }
function RepoDeCarpeta(const ACarpeta: string; out AGitDir, AComun, ARaiz: string): Boolean;
var
  Salida: string;
  Codigo: Cardinal;
begin
  try
    Result := DondeViveElRepo(ACarpeta, AGitDir, AComun, ARaiz, Salida, Codigo);
  except
    Result := False;
  end;
end;

{ Los trozos que no son opciones de un texto con forma de linea, en su orden.
  Desde la 1.19.0 la llamada no trae ninguno: solo los lee el juez de lo que
  un remote.<n>.push de la CONFIGURACION del repo enviaria
  (EnvioConfiguradoDenegado). }
function TrozosSinGuion(const AArgs: string): TArray<string>;
var
  Trozo: string;
begin
  Result := nil;
  for Trozo in TrocearArgs(AArgs) do
    if not Trozo.StartsWith('-') then
      Result := Result + [Trozo];
end;

(* EL juez de un nombre de ref o de una revision es GIT (norma 6 del paisaje:
  lo medible no se hardcodea; medida refs-git del 9-oct). AConRevision False:
  un NOMBRE que el agente escribe (una rama, un tag), por
  check-ref-format --branch, que acepta lo que git acepta -no ASCII, llaves- y
  niega -x, x.lock, los rangos y los metacaracteres que la regex negaba a
  mano. AConRevision True: una REVISION que ademas debe EXISTIR, por
  rev-parse --verify --quiet --end-of-options, que entiende HEAD^, @{1} y
  x^{commit}. --end-of-options protege un nombre que empieza por '-' sin
  lista. Un fallo de git al juzgar no es un "vale": Codigo<>0 (timeout, o no
  hay git -EOSError, que sube-) es "no". Por el lanzador de la casa. *)
function EsNombreDeRef(const ARepo, AFijado, ANombre: string; AConRevision: Boolean): Boolean;
var
  Codigo: Cardinal;
begin
  if AConRevision then
    GitCorre(ARepo, AFijado,
      'rev-parse --verify --quiet --end-of-options ' + EnComillas(ANombre), 60000, Codigo)
  else
    GitCorre(ARepo, AFijado, 'check-ref-format --branch ' + EnComillas(ANombre), 60000, Codigo);
  Result := Codigo = 0;
end;

{ Un campo de la llamada que es una REVISION (ref, to, la rama de un merge):
  '' si esta vacio o git la encuentra; si no, GIT-070 con el nombre del
  campo. El juez, EsNombreDeRef. }
function RevisionDenegada(const ARepo, AFijado, ACampo, AValor: string): string;
begin
  Result := '';
  if (AValor.Trim <> '') and not EsNombreDeRef(ARepo, AFijado, AValor.Trim, True) then
    Result := MsgFmt(SR_GIT_REF_NO_VALE_FMT, [ACampo, AValor.Trim]);
end;

{ ...y uno que es un NOMBRE de rama o de tag (la rama de un switch o un
  pull, el tag nuevo): '' si git lo admite (check-ref-format: tampoco uno
  que empieza por '-', que git leeria como opcion); si no, GIT-071. }
function NombreDenegado(const ARepo, AFijado, ACampo, AValor: string): string;
begin
  Result := '';
  if (AValor.Trim <> '') and not EsNombreDeRef(ARepo, AFijado, AValor.Trim, False) then
    Result := MsgFmt(SR_GIT_NOMBRE_NO_VALE_FMT, [ACampo, AValor.Trim]);
end;

{ La FORMA de un refspec que destruye en el remoto: un '+' inicial FUERZA y un
  src vacio (':dst') BORRA. Se niega por la forma, ANTES de preguntar a git y
  juzgue lo que juzgue el: check-ref-format ACEPTA "+main" como nombre (medido
  el 9-oct) y rev-parse lo encuentra en cuanto hay una ref que se llama asi -
  medido el 18-oct-2026: tag name="+main" y luego push ref="+main" FORZABA el
  remoto (la 1.19.0 dejo el ref de push solo con los jueces de git). EL juez de
  la forma: lo que envia la configuracion (EnvioQueNoVale) y el ref de push, en
  su juez y en la segunda barrera. }
function RefspecQueDestruye(const ATrozo: string): Boolean;
begin
  Result := ATrozo.StartsWith('+') or ATrozo.StartsWith(':');
end;

{ LO QUE push ENVIA: los trozos sin guion de detras del remoto. push ANADE
  al remoto; lo que ya hay alli no se reescribe ni se borra por esta tool
  (David, 29-sep-2026: "nada de destruccion remota"). La sintaxis del refspec
  es [+]src[:dst]: un '+' inicial FUERZA y un src vacio (:dst) BORRA; las dos
  se niegan por la FORMA, ANTES de preguntar a git, porque check-ref-format
  ACEPTA "+main" como nombre (medido el 9-oct). Lo demas lo juzga git
  (EsNombreDeRef): el src de un par es una REVISION que ya esta en el repo, el
  dst el NOMBRE que tendra alli; un trozo suelto vale como nombre O como
  revision (push origin HEAD). True si hay uno que no (AMalo).

  Medido el 29-sep-2026 por la tool, con --force y --delete ya negados por su
  nombre: args="origin +main", con las historias divergidas, reescribia la
  rama del remoto, y args="origin :sobra" la borraba. }
function EnvioQueNoVale(const ARepo, AFijado, AArgs: string; out AMalo: string): Boolean;
var
  Trozos: TArray<string>;
  I, P: Integer;
  Vale: Boolean;
  Trozo, Src, Dst: string;
begin
  Result := False;
  AMalo := '';
  Trozos := TrozosSinGuion(AArgs);
  // (el primero es el remoto: lo juzga RemotoDenegado)
  for I := 1 to High(Trozos) do
  begin
    Trozo := Trozos[I];
    // la forma que fuerza o borra, fuera (RefspecQueDestruye)
    if RefspecQueDestruye(Trozo) then
    begin
      AMalo := Trozo;
      Exit(True);
    end;
    P := Trozo.IndexOf(':');
    if P >= 0 then
    begin
      Src := Trozo.Substring(0, P);
      Dst := Trozo.Substring(P + 1);
      Vale := EsNombreDeRef(ARepo, AFijado, Src, True) and
        EsNombreDeRef(ARepo, AFijado, Dst, False);
    end
    else
      // un trozo suelto: nombre (main, v1.7.7) o revision (HEAD)
      Vale := EsNombreDeRef(ARepo, AFijado, Trozo, False) or
        EsNombreDeRef(ARepo, AFijado, Trozo, True);
    if not Vale then
    begin
      AMalo := Trozo;
      Exit(True);
    end;
  end;
end;

{ Lo que git contesta a una pregunta, linea a linea (las que traen algo).
  False si git sale con error o no contesta en su plazo: quien pregunta para
  JUZGAR no toma un fallo por un "no hay" (cuarta revision de la 1.7.7: una
  pregunta que fallaba acababa en "se puede"). Por eso las preguntas se
  hacen de forma que "no hay" salga con 0: el que se queda sin plazo sale
  con 1, que es tambien con lo que git config dice que una clave no esta.
  ATalCual: cada linea como la da git, sin quitarle los blancos - lo que se
  juzga como lo usa git, una direccion de remoto (V168 de la 1.23.1) -. }
function GitContesta(const ARepo, AFijado, APregunta: string;
  out ALineas: TArray<string>; ATalCual: Boolean): Boolean;
var
  Salida, Linea: string;
  Codigo: Cardinal;
begin
  ALineas := nil;
  Salida := GitCorre(ARepo, AFijado, APregunta, 60000, Codigo);
  Result := Codigo = 0;
  if Result then
    for Linea in LineasDelTexto(Salida) do
    if Linea.Trim <> '' then
      if ATalCual then
        ALineas := ALineas + [Linea]
      else
        ALineas := ALineas + [Linea.Trim];
end;

{ Si GIT dice que este repo no distingue mayusculas (core.ignorecase, que git
  init y clone ponen MIDIENDO el disco: en Windows, true). Entonces una ruta
  de "paths" con otra mayuscula es el mismo fichero, y su magia lleva icase:
  con :(literal) solo, status decia limpio y diff "NOTHING has changed" de un
  fichero modificado (H4-01 de Hermes; H10 de la 1.19.2). El juez es git,
  no una regla nuestra de "Windows no distingue". La clave sin poner (git
  sale con 1) es "si distingue", el valor por defecto de git. }
function RepoSinMayusculas(const ARepo, AFijado: string): Boolean;
var
  Lineas: TArray<string>;
begin
  Result := GitContesta(ARepo, AFijado, 'config --get --type=bool core.ignorecase', Lineas) and
    (Length(Lineas) > 0) and SameText(Lineas[0], 'true');
end;

function TieneGit(const ADir: string): Boolean;
begin
  Result := TDirectory.Exists(TPath.Combine(ADir, '.git')) or
    TFile.Exists(TPath.Combine(ADir, '.git'));
end;

function RamaDelRepo(const ARepo: string): string;
var
  GitDir, Comun, Raiz, Salida, Fijado: string;
  Codigo: Cardinal;
  Lineas: TArray<string>;
begin
  Result := '';
  // ANTES de lanzar git: delphi_projects encuentra el repo subiendo, y puede
  // estar por encima de las raices
  if ReadPathDenied(ARepo, True) <> '' then
    Exit;
  try
    // por DondeViveElRepo y no por su cache (GitDirDeCarpeta): un "no es
    // repo" de antes de un init se quedaria para siempre
    if not DondeViveElRepo(ARepo, GitDir, Comun, Raiz, Salida, Codigo) then
      Exit;
    for var Sitio in TArray<string>.Create(GitDir, Comun) do
      if (Sitio <> '') and (ReadPathDenied(Sitio, True) <> '') then
        Exit;
    // fijado a lo que se juzgo, como la tool
    Fijado := ' --git-dir=' + EnComillas(GitDir);
    // symbolic-ref sale con 1 y sin salida con HEAD suelto (medido, git 2.53)
    if GitContesta(ARepo, Fijado, 'symbolic-ref --short -q HEAD', Lineas) and (Length(Lineas) > 0) then
      Exit(Lineas[0]);
    if GitContesta(ARepo, Fijado, 'rev-parse --short HEAD', Lineas) and (Length(Lineas) > 0) then
      Result := Lineas[0] + ' (detached)';
  except
    // sin git en el servidor (GIT-050): la rama no se sabe
    Result := '';
  end;
end;

{ EL LECTOR de una ruta que git escribe entrecomillada (quote_c_style de git):
  entre comillas van \\ \" \t \n... y los bytes que no son ASCII en octal
  (\303\261 es una n con tilde, en UTF-8); sin comillas, va tal cual. Git
  entrecomilla una ruta con acentos (core.quotePath, por defecto) o con
  barras invertidas: la fuente de una regla de check-ignore bajo el --git-dir
  absoluto que fija el servidor sale "C:\\...\\.git/info/exclude" (medido el
  15-oct-2026; -z, que lo evitaria, en check-ignore solo va con --stdin). Es
  la inversa del escritor de git, no una regla nuestra. No lanza: unos bytes
  que no son UTF-8 dejan la ruta como llego. }
function LeeRutaDeGit(const ARuta: string): string;
var
  Bytes: TBytes;
  Tramo: string;
  I, N: Integer;
  C: Char;
begin
  N := Length(ARuta);
  if (N < 2) or (ARuta[1] <> '"') or (ARuta[N] <> '"') then
    Exit(ARuta);
  Bytes := nil;
  Tramo := '';
  I := 2;
  while I < N do
  begin
    C := ARuta[I];
    if (C <> '\') or (I + 1 >= N) then
      Tramo := Tramo + C
    else
    begin
      // lo que va sin escapar, de una vez: un par suplente no se parte
      Bytes := Bytes + TEncoding.UTF8.GetBytes(Tramo);
      Tramo := '';
      Inc(I);
      C := ARuta[I];
      case C of
        'a': Bytes := Bytes + [7];
        'b': Bytes := Bytes + [8];
        't': Bytes := Bytes + [9];
        'n': Bytes := Bytes + [10];
        'v': Bytes := Bytes + [11];
        'f': Bytes := Bytes + [12];
        'r': Bytes := Bytes + [13];
        '0'..'3':
          if (I + 2 < N) and CharInSet(ARuta[I + 1], ['0'..'7']) and
             CharInSet(ARuta[I + 2], ['0'..'7']) then
          begin
            Bytes := Bytes + [Byte((Ord(C) - Ord('0')) * 64 +
              (Ord(ARuta[I + 1]) - Ord('0')) * 8 + Ord(ARuta[I + 2]) - Ord('0'))];
            Inc(I, 2);
          end
          else
            Tramo := C;
      else
        Tramo := C; // \" y \\: el caracter mismo
      end;
    end;
    Inc(I);
  end;
  Bytes := Bytes + TEncoding.UTF8.GetBytes(Tramo);
  try
    Result := TEncoding.UTF8.GetString(Bytes);
  except
    Result := ARuta;
  end;
end;

{ Lo que git IGNORA de las rutas de un add que fallo, con su regla (GIT-078).
  Con :(literal,icase) (H10 de la 1.19.2) git no dice "The following paths
  are ignored" de un ignorado: dice "pathspec ... did not match any files" y
  no anade nada, y el agente creia que el fichero no existia (medido el
  15-oct-2026 con git 2.53; con :(literal) si lo decia). El juez es git
  check-ignore, que respeta core.ignorecase y nombra la regla. No admite
  magia ("pathspec magic not supported"): van las relativas de RutasDeGit, y
  --non-matching da una linea por ruta y en su orden, asi que no hace falta
  leer el nombre que git devuelve. Un rastreado no esta ignorado, como para
  add. La fuente de la regla se lee con LeeRutaDeGit: la de dentro del arbol
  (ARaiz) se dice relativa a el (.gitignore, .git/info/exclude); la de fuera
  (core.excludesFile, el info/exclude del repo principal de un worktree) es
  de la casa del servidor o de otro arbol: se dice que es de fuera, sin su
  ruta. Nada de TPath sobre texto de git: una comilla en la fuente lanzaba
  "Invalid characters in path" y se llevaba la respuesta entera del add
  (medido en la bateria, 15-oct-2026). '' si ninguna lo esta o git no
  contesta (GitContesta: el 1 de check-ignore es "ninguna"). }
function IgnoradosDeGit(const ARepo, AFijado, ARaiz: string;
  const ARelativas: TArray<string>): string;
var
  Lineas: TArray<string>;
  Orden, Rel, Fuente, Ignorados: string;
  Regla: TMatch;
  I: Integer;
begin
  Result := '';
  if (Length(ARelativas) = 0) or (ARaiz = '') then
    Exit;
  Orden := 'check-ignore --verbose --non-matching --';
  for Rel in ARelativas do
    Orden := Orden + ' ' + EnComillas(Rel);
  if not GitContesta(ARepo, AFijado, Orden, Lineas) or (Length(Lineas) <> Length(ARelativas)) then
    Exit;
  Ignorados := '';
  for I := 0 to High(Lineas) do
  begin
    // <fuente>:<linea>:<patron><TAB><ruta>; la que no casa, "::<TAB><ruta>"
    Regla := TRegEx.Match(PrimerTrozo(Lineas[I], [#9]), '^(.+?):(\d+):(.*)$');
    if not Regla.Success then
      Continue;
    if Ignorados <> '' then
      Ignorados := Ignorados + ', ';
    Fuente := ConBarrasDeWindows(LeeRutaDeGit(Regla.Groups[1].Value));
    // con raiz (C:\..., \\servidor, \...) es de dentro solo si cuelga del arbol
    if ((Length(Fuente) >= 2) and (Fuente[2] = ':')) or Fuente.StartsWith('\') then
    begin
      var Trozo: string;
      if TrozoBajo(ARaiz, Fuente, Trozo) then
        Fuente := Trozo
      else
        Fuente := '';
    end;
    if Fuente = '' then
      Ignorados := Ignorados + MsgFmt(SF_GIT_IGNORADO_FUERA_FMT,
        [ARelativas[I], Regla.Groups[3].Value])
    else
      Ignorados := Ignorados + MsgFmt(SF_GIT_IGNORADO_POR_FMT,
        [ARelativas[I], Regla.Groups[3].Value, ConBarrasNormales(Fuente), Regla.Groups[2].Value]);
  end;
  if Ignorados <> '' then
    Result := #10 + MsgFmt(SN_GIT_ADD_IGNORADO_FMT, [Ignorados]);
end;

{ Una direccion de RED con su esquema. La lista es la de clone; el esquema,
  por EL lector de la puerta de los hosts (Lsp.Args.EsquemaDeDireccion), sin
  mayusculas: miraba cuatro prefijos en minusculas y negaba HTTPS://, que git
  lleva como https (V130 de la 1.23.1, medido). }
function EsUrlDeRed(const ADireccion: string): Boolean;
begin
  Result := MatchStr(EsquemaDeDireccion(ADireccion), ['https', 'http', 'git', 'ssh']);
end;

{ QUE ES la direccion de un remoto. Una lista de lo que vale:
    drRed      una direccion de red: con su esquema (EsUrlDeRed) o en la
               forma corta de ssh, [usuario@]maquina:ruta
    drCarpeta  una carpeta (ACarpeta, tal como viene): su ruta, o
               file:///<unidad>:/<ruta> sin nada codificado, que es la forma
               de file:// que se lee igual aqui que en git
    drOtra     lo demas, que no se admite
  Medido el 29-sep-2026 por la tool (cuarta revision): git DECODIFICA los
  %xx de un file:// y aqui se leian tal cual - "mi%20repo.git" era para el
  juez una carpeta y para git otra -, y un remoto del repo con su direccion
  en file://C:/... (dos barras) pasaba por direccion de red: fetch traia la
  historia de una carpeta de fuera de las raices y push escribia en ella. }
type
  TDireccionDeRemoto = (drRed, drCarpeta, drOtra);

function ClaseDeDireccion(const ADireccion: string; out ACarpeta: string): TDireccionDeRemoto;
begin
  ACarpeta := '';
  if StartsText('file:', ADireccion) then
  begin
    if not TRegEx.IsMatch(ADireccion, '^file:///[A-Za-z]:/[^%]*$') then
      Exit(drOtra);
    ACarpeta := ADireccion.Substring(8);
    Exit(drCarpeta);
  end;
  // un remote-helper de git (<helper>::<direccion>): ni red que la lista
  // entienda ni carpeta (V130 de la 1.23.1)
  if HelperDeDireccion(ADireccion) <> '' then
    Exit(drOtra);
  if EsUrlDeRed(ADireccion) then
    Exit(drRed);
  if EsquemaDeDireccion(ADireccion) <> '' then
    Exit(drOtra);
  // la forma corta de ssh ([usuario@]maquina:ruta) la decide EL MISMO lector
  // de host que el resto (GitUrlHost con scp corto): un solo juez, sin regex
  // gemela aqui, y asi no discrepan (C:\ o C:/ no es una maquina).
  if GitUrlHost(ADireccion, True) <> '' then
    Exit(drRed);
  ACarpeta := ADireccion;
  Result := drCarpeta;
end;

{ Los remotos del repo, por su nombre. False si git no lo dice. }
function RemotosDelRepo(const ARepo, AFijado: string; out ANombres: TArray<string>): Boolean;
begin
  Result := GitContesta(ARepo, AFijado, 'remote', ANombres);
end;

{ UNA CARPETA que hace de remoto, juzgada: '' = se puede usar. La puerta de
  lectura para traer, la de escritura para enviar. Pasa la carpeta y pasa EL
  REPO QUE VIVE ALLI, con sus tres carpetas, como el de la llamada
  (DondeViveElRepo): una carpeta de dentro de las raices cuyo .git es un
  puntero - un worktree enlazado - sirve y escribe el repo al que apunta.
  Medido el 29-sep-2026 por la tool (cuarta revision): con un worktree de
  dentro de un repo de fuera por remoto, fetch traia la historia de fuera y
  push escribia una rama alli. }
function CarpetaDeRemotoDenegada(const ACmd, ACarpeta: string;
  out ANoEsta: Boolean): string;

  function Puerta(const ASitio: string): string;
  begin
    if ACmd = 'push' then
      Result := PathDenied(ASitio, True)
    else
      Result := ReadPathDenied(ASitio, True);
    if Result <> '' then
      Result := MsgFmt(SR_GIT_REMOTO_FUERA_FMT, [ACmd, ASitio,
        IfThen(ACmd = 'push', 'write', 'read')]);
  end;

var
  GitDir, Comun, Raiz, Salida, Sitio: string;
  Codigo: Cardinal;
begin
  ANoEsta := False;
  Result := Puerta(ACarpeta);
  if Result <> '' then
    Exit;
  // UNA CARPETA QUE ESTA. git abre mas cosas que una carpeta - el fichero
  // puntero de un worktree enlazado, o una ruta a la que el le pone el
  // sufijo .git -, y lo que abre entonces no es lo que aqui se ha mirado.
  // Medido el 29-sep-2026 por la tool (el revisor de este mismo arreglo):
  // con el remoto en "<worktree>\.git", que es un fichero, fetch traia la
  // historia del repo de fuera y push escribia una rama alli.
  // (de lo que NO esta, solo despues de la puerta: de una ruta de fuera no
  // se dice ni si existe)
  if not TDirectory.Exists(ACarpeta) then
  begin
    ANoEsta := True;
    Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ACarpeta]));
  end;
  if not DondeViveElRepo(ACarpeta, GitDir, Comun, Raiz, Salida, Codigo) then
    Exit(GitFallo(Codigo, Salida));
  for Sitio in TArray<string>.Create(GitDir, Comun, Raiz) do
    if Sitio <> '' then
    begin
      Result := Puerta(Sitio);
      if Result <> '' then
        Exit;
    end;
end;

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  ADelRepo: Boolean; out ACarpeta: string; out ANoEsta: Boolean): string;
begin
  Result := '';
  ACarpeta := '';
  ANoEsta := False;
  case ClaseDeDireccion(ADireccion, ACarpeta) of
    drRed:
      begin
        if GitUrlHost(ADireccion, True) = '' then
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        Result := GitRemoteDenied(EnComillas(ADireccion), True, ADelRepo);
      end;
    drCarpeta:
      begin
        try
          ACarpeta := SinBarraFinal(TPath.GetFullPath(
            TPath.Combine(ABase, ConBarrasDeWindows(ACarpeta))));
        except
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        end;
        Result := CarpetaDeRemotoDenegada(ACmd, ACarpeta, ANoEsta);
      end;
  else
    Result := MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]);
  end;
end;

{ EL REMOTO de una llamada de red, juzgado: '' = se puede usar.

  El remoto es adonde git va a leer (fetch, pull) o a escribir (push). En la
  llamada se da por el NOMBRE que tiene en el repo, y solo asi desde la
  1.19.0 (una direccion o una carpeta escritas en la llamada eran args). Sus
  direcciones son una de dos cosas (ClaseDeDireccion): de RED, o una
  CARPETA, que pasa por la jaula (CarpetaDeRemotoDenegada). Lo que no es ni
  lo uno ni lo otro se niega.

  Un nombre se cambia por sus direcciones - TODAS las que tenga: git envia a
  cada una - y se juzgan esas. Sin remoto en la llamada, git usa uno de los
  del repo: se juzgan todos. Cada direccion de red pasa por la lista de
  hosts. Tiene que ser una direccion que esa lista entiende: con su
  esquema, o con usuario.

  Si git no contesta a lo que se le pregunta para juzgar, no se usa.

  Medido el 29-sep-2026 por la tool: con una carpeta de fuera de las raices,
  por su ruta o por su nombre, fetch traia su historia y push escribia ramas
  alli. La lista de hosts solo entiende direcciones de red, y una carpeta no
  la miraba nadie. }
function RemotoDenegado(const ACmd, ARepo, AFijado, ABase, ARemoto: string): string;
var
  Nombres, Mirar, Lineas: TArray<string>;
  Nombre, Direccion, Carpeta, Pregunta: string;
  NoEsta: Boolean;
begin
  Result := '';
  Pregunta := 'remote get-url --all ';
  if ACmd = 'push' then
    Pregunta := 'remote get-url --push --all ';
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
  // el de la llamada, elegido de los del repo: lo que git lista
  if ARemoto.Trim <> '' then
  begin
    var Idx := IndexStr(ARemoto.Trim, Nombres);
    if Idx < 0 then
      Exit(MsgFmt(SR_GIT_REMOTO_NO_ESTA_FMT, [ARemoto.Trim,
        IfThen(Length(Nombres) = 0, '(none)', string.Join(', ', Nombres))]));
    Mirar := [Nombres[Idx]];
  end
  else
    Mirar := Nombres;
  for Nombre in Mirar do
  begin
    // las direcciones tal como las usa git: con un blanco delante, git no la
    // lee como de red (V168 de la 1.23.1)
    if not GitContesta(ARepo, AFijado, Pregunta + EnComillas(Nombre), Lineas, True) or
       (Length(Lineas) = 0) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
    // las del repo: su negativa no aconseja usar el nombre del remoto, que
    // ya se uso (GIT-063)
    for Direccion in Lineas do
    begin
      Result := DireccionDeRemotoDenegada(ACmd, Direccion, ABase, True, Carpeta, NoEsta);
      if Result <> '' then
        Exit;
    end;
  end;
end;

{ LO QUE push ENVIA CUANDO NO SE LE DICE: sin nombres en la llamada lo
  decide la configuracion del repo, y tambien se juzga. '' = vale. Un repo
  ESPEJO (remote.<n>.mirror) envia a la fuerza y quita del remoto lo que
  aqui ya no esta; un remote.<n>.push dice que enviar, y tiene que ser de
  nombres, como lo que se escribe en la llamada. Medido el 29-sep-2026 por
  la tool (cuarta revision): desde un repo espejo, push a secas borro del
  remoto una rama. }
function EnvioConfiguradoDenegado(const ARepo, AFijado, ARemoto, ARef: string): string;
var
  Nombres, Lineas, Todas: TArray<string>;
  Nombre, Linea, Malo, Clave: string;
begin
  Result := '';
  if ARef.Trim <> '' then
    Exit; // con un nombre en la llamada manda el (y lo juzga git: EsNombreDeRef)
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  // (el remoto ya es uno del repo: RemotoDenegado, antes)
  if ARemoto.Trim <> '' then
    Nombres := [ARemoto.Trim];
  // La configuracion ENTERA, de una vez: sale con 0 haya lo que haya, y de
  // sus lineas cuentan las de cada remoto (un aviso de git mezclado en la
  // salida no empieza por el nombre de una clave).
  if not GitContesta(ARepo, AFijado, 'config --list', Todas) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  for Nombre in Nombres do
  begin
    // espejo: lo dice git, que sabe leer sus si y sus no (true, yes, on, 1)
    if not GitContesta(ARepo, AFijado, 'config --type=bool --default false --get ' +
         EnComillas('remote.' + Nombre + '.mirror'), Lineas) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
    if IndexStr('true', Lineas) >= 0 then
      Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre, 'mirror', Nombre]));
    Clave := 'remote.' + Nombre + '.push=';
    for Linea in Todas do
      if Linea.StartsWith(Clave) and
         EnvioQueNoVale(ARepo, AFijado, 'remoto ' + Linea.Substring(Length(Clave)), Malo) then
        Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre,
          'push = ' + Linea.Substring(Length(Clave)), Nombre]));
  end;
end;

const
  TOPE_SALIDA_GIT = 30000; // caracteres de una pagina de la respuesta de git
  // los commits que log ensena cuando el agente no da su -n
  LOG_POR_DEFECTO = 20;

{ EL compositor de la orden log: el tope y lo demas que ya compuso la tool
  (formato, busqueda, rango, rutas; AResto, con sus comillas). Lo usan la
  orden y la pregunta de si hay mas (D7 de los revisores de cierre), con un
  commit mas de tope. }
function OrdenDeLog(ATope: Integer; const AResto: string): string;
begin
  Result := Format('log -n %d', [ATope]) + AResto;
end;

{ Las lineas de AOutput desde la ADesde (0-based) que caben en una pagina, y
  si queda algo, la nota que dice cuales son y como pedir el resto. Corta
  siempre en un salto; una linea mas larga que la pagina, sola, se corta y
  se dice (GIT-055): la siguiente pagina empieza en la otra, y su cola se
  perdia sin aviso (revision de la 1.13.0) }
function PaginaDeSalidaGit(const AOutput: string; ADesde: Integer): string;
var
  Lineas: TArray<string>;
  Sb: TStringBuilder;
  K: Integer;
  Cortadas: string;
begin
  if (ADesde <= 0) and (Length(AOutput) <= TOPE_SALIDA_GIT) then
    Exit(AOutput);
  Lineas := AOutput.Split([#10]);
  if (Length(Lineas) > 0) and (Lineas[High(Lineas)] = '') then
    SetLength(Lineas, Length(Lineas) - 1); // el salto del final no es una linea
  if ADesde >= Length(Lineas) then
    Exit(MsgFmt(SN_GIT_OFFSET_FUERA_FMT, [ADesde, Length(Lineas)]));
  Cortadas := '';
  Sb := TStringBuilder.Create;
  try
    K := ADesde;
    while (K < Length(Lineas)) and
          ((K = ADesde) or (Sb.Length + Length(Lineas[K]) + 1 <= TOPE_SALIDA_GIT)) do
    begin
      Sb.Append(Copy(Lineas[K], 1, TOPE_SALIDA_GIT)).Append(#10);
      if Length(Lineas[K]) > TOPE_SALIDA_GIT then
        Cortadas := Cortadas + IfThen(Cortadas <> '', ', ') + IntToStr(K + 1);
      Inc(K);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
  if Cortadas <> '' then
    Result := Result + MsgFmt(SN_GIT_LINEA_CORTADA_FMT, [Cortadas, TOPE_SALIDA_GIT]) + #10;
  if K < Length(Lineas) then
    Result := Result + MsgFmt(SN_GIT_PAGINA_FMT, [ADesde + 1, K, Length(Lineas), K]);
end;

{ Lo que una operacion que REESCRIBE el arbol tocaria, por el juez que lo sabe
  -git- y no por una lista nuestra (regla 6; 2x de la 1.18.2): se le piden los
  ficheros que cambiaria (diff --name-only HEAD <destino>, o stash show para un
  pop) y cada uno pasa por la puerta de siempre (PathDenied, fichero a fichero).
  Si alguno es un lugar protegido -ReadOnlyPaths / ReadOnlyRoots dentro del
  repo-, la negativa los NOMBRA (GIT-065) y no se hace nada: switch, merge,
  pull y stash pop reescribian un .dfm o un vendor de solo lectura al cambiar
  de rama (medido). '' = nada protegido que tocar, o no reescribe el arbol.
  Se juzga solo donde hace falta: sin un lugar protegido DENTRO del arbol
  (ProtegidoDentroDe) git no puede reescribir nada protegido, y no se lanza
  ni git ni la puerta por fichero. Donde lo hay, FALLA CERRADO (GIT-066): un
  destino que el juez no lee (pull sin el fetch de arriba hecho, porque
  entonces FETCH_HEAD no es el destino o es viejo) o un git que no contesta
  es un "no", como en EsNombreDeRef. Hasta la 1.18.x el destino se sacaba de
  los trozos de args, y cada forma nueva (switch -, --detach, -f, -c nb b2)
  era una que el juez no leia (revision 5.5, medido); desde la 1.19.0 llega
  con tipo: la rama (ARama) y la accion (AAccion). merge action=abort no se
  juzga: deshace, y negarlo dejaria el repo a medio merge sin salida por
  esta tool. ARaiz vacia (bare) no tiene arbol. }
function GitReescribeProtegido(const ARepo, AFijado, ARaiz, ACmd, AAccion, ARama: string;
  ACrear, AFetchHecho: Boolean): string;
var
  Objetivo, Pregunta, Rel, Nombre, Abs, Dentro: string;
  Reescribe, Legible, EsStashPop: Boolean;
  Ficheros, Malos: TArray<string>;
begin
  Result := '';
  if ARaiz = '' then
    Exit;
  Objetivo := '';
  Reescribe := False;
  EsStashPop := False;
  if SameText(ACmd, 'switch') then
  begin
    // "switch -c <nueva>" deja el arbol como esta: sale de HEAD
    Reescribe := not ACrear;
    Objetivo := ARama.Trim;
  end
  else if SameText(ACmd, 'merge') then
  begin
    Reescribe := not SameText(AAccion.Trim, 'abort');
    Objetivo := ARama.Trim;
  end
  else if SameText(ACmd, 'pull') then
  begin
    Reescribe := True;
    if AFetchHecho then
      Objetivo := 'FETCH_HEAD';
  end
  else if SameText(ACmd, 'stash') and SameText(AAccion.Trim, 'pop') then
  begin
    Reescribe := True;
    EsStashPop := True;
  end;
  Legible := EsStashPop or (Objetivo <> '');
  if not Reescribe then
    Exit;
  Dentro := ProtegidoDentroDe(ARaiz);
  if Dentro = '' then
    Exit;
  if not Legible then
    Exit(MsgFmt(SR_GIT_REESCRIBE_SIN_JUEZ_FMT, [ACmd, Dentro]));
  if EsStashPop then
    Pregunta := 'stash show --name-only'
  else
    // el -- final: Objetivo es una REVISION. Sin el, una rama que se llama
    // como un fichero del arbol (U.dfm) es ambigua y git no contesta (medido)
    Pregunta := 'diff --name-only HEAD ' + EnComillas(Objetivo) + ' --';
  if not GitContesta(ARepo, AFijado, Pregunta, Ficheros) then
    Exit(MsgFmt(SR_GIT_REESCRIBE_SIN_JUEZ_FMT, [ACmd, Dentro]));
  for Rel in Ficheros do
  begin
    if Rel.Trim = '' then
      Continue;
    // por el lector de las comillas de git, de segunda barrera de
    // core.quotePath=false (GitLinea): con la comilla, TPath.Combine lanzaba
    // "Invalid characters in path" y switch/merge/pull/stash pop morian con
    // SYS-011 si el cambio tocaba un fichero con acento (medido el
    // 15-oct-2026, 1.19.3)
    Nombre := LeeRutaDeGit(Rel.Trim);
    Abs := TPath.Combine(ARaiz, ConBarrasDeWindows(Nombre));
    // la puerta de siempre, fichero a fichero: '' si se puede escribir. Con el
    // permiso de git (APermiteGit): un fichero versionado nunca esta en los
    // metadatos, y sin el cada carpeta lanzaba un git (el gitdir separado)
    if PathDenied(Abs, True) <> '' then
      Malos := Malos + [Nombre];
  end;
  if Length(Malos) > 0 then
    Result := MsgFmt(SR_GIT_REESCRIBE_PROTEGIDO_FMT, [ACmd, string.Join(', ', Malos)]);
end;

function TDelphiGitTool.ExecuteWithParams(const Params: TDelphiGitParams): string;
var
  Cmd, GitArgs, Repo, Output, MsgFile: string;
  ExitCode: Cardinal;
  Destino, Enlace: string; // worktree
  GitDir, Comun, Raiz: string; // donde vive el repo (DondeViveElRepo)
  Fijado: string; // --git-dir y --work-tree: git trabaja donde la puerta miro
  SeQuitan: TArray<string>; // las carpetas que git puede quitar: lo nuestro, fuera
  Sitio: string;
begin
  MsgFile := '';
  SeQuitan := nil;
  GitDir := '';
  Comun := '';
  Raiz := '';
  Fijado := '';
  Repo := Params.Repo;
  if Repo = '' then
    Exit(MsgText(SR_GIT_MISSING_REPO));
  // En un proyecto de REFERENCIA (ReadOnlyRoots) vale la mitad de CONSULTA
  // de git - la misma clasificacion que la credencial de solo lectura, en
  // UNA funcion (Lsp.Args.GitCommandIsQuery). Lo demas pasa por la puerta
  // de escritura y sale con el motivo de referencia.
  if (ReadOnlyRootOf(Repo) <> '') and
     GitCommandIsQuery(Params.Command, Params.Action, Params.Name, Params.Message) then
    Result := ReadPathDenied(Repo, True)
  // el destino de un clone es un sitio donde se ESCRIBE: la puerta de
  // escritura (jaula + carpetas muertas), como su gemela worktree add. Se
  // clonaba dentro de __delphi-temp, __delphi-patch o __history (septima)
  else if SameText(Params.Command.Trim, 'clone') then
  begin
    Result := WriteTargetDenied(Repo);
    // el checkout --force del clone escribe el arbol en el destino: que no
    // CONTENGA un lugar protegido (ReadOnlyPaths/raices), como worktree add
    // (2v de la 1.18.2; 4.o emisor de la regla del 2r)
    if Result = '' then
      Result := ProtegidoDenegado(Repo, True);
  end
  else
    Result := PathDenied(Repo, True);
  if Result <> '' then
    Exit;
  if TFile.Exists(Repo) then
    Repo := TPath.GetDirectoryName(Repo);
  // clone is the one command whose target directory may not exist yet: it
  // is created (inside the jail, already checked above) right before git
  // runs, and a failed clone removes it only if THIS clone created it. Se
  // creaba aqui arriba: un rechazo de la URL la dejaba, y la limpieza de
  // abajo borraba una carpeta vacia que ya estaba (la raiz vacia de otro
  // workspace; sexta revision).
  var CreadaPorElClone := False;
  var AncestroDelClone := ''; // lo que el clone cree debajo es suyo
  if not SameText(Params.Command.Trim, 'clone') and not TDirectory.Exists(Repo) then
  begin
    Result := MsgFmt(SR_GIT_DIR_NOT_FOUND_FMT, [Repo]);
    // init no la crea: se dice como crearla (Hermes, 1.18.0)
    if SameText(Params.Command.Trim, 'init') then
      Result := Result + MsgText(SN_GIT_INIT_NO_CREA);
    Exit;
  end;

  // The message never goes through a shell (git is spawned with a direct
  // command line): normal punctuation is welcome. Line breaks are refused
  // ONLY for the commands that embed the message in the command line -
  // commit and tag write it to a file and pass -F, so there a multi-line
  // message is exactly what you want: subject, blank line, body with the
  // WHY. Refusing it left every agent-made history as one-line subjects
  // (field report 2026-08-25).
  if (Params.Message.Contains(#13) or Params.Message.Contains(#10)) and
     not MatchText(Params.Command.Trim, ['commit', 'tag']) then
    Exit(MsgText(SR_GIT_MESSAGE_LINES));
  Cmd := SinMayusculas(Params.Command.Trim);
  // "paths" es una LISTA (el esquema la publica asi; un texto suelto no lo
  // es): se lee una vez, aqui, y la lee RutasDeGit para cada comando
  var Lista: TArray<string>;
  if not ListaDeTextos(Params.Paths, Lista) then
    Exit(MsgText(SR_GIT_PATHS_NO_ES_LISTA));
  // lo que no va con el comando se dice (Lsp.Guard.ParametroQueNoVa): commit
  // con path hacia un commit de TODO el indice (octava revision). stash y
  // worktree tienen SUBcomando (action): la tabla es por comando y accion
  // (stash list admitia message, worktree list path y worktree remove ref;
  // novena revision). Desde la 1.19.0 cada campo es de quien lo usa: no hay
  // un args de todos que mire otro
  var ModoGit := Cmd;
  if Cmd = 'stash' then
  begin
    ModoGit := 'stash push';
    if Params.Action.Trim <> '' then
      ModoGit := 'stash ' + LowerCase(Params.Action.Trim);
  end
  else if Cmd = 'worktree' then
    ModoGit := 'worktree ' + LowerCase(Params.Action.Trim);
  var SuyosGit, VaConGit: string;
  var SobraGit := ParametroQueNoVa(ModoGit, [
      'status', 'paths offset',
      'diff', 'paths ref to staged format context offset',
      'log', 'paths ref to format count search offset',
      'show', 'paths ref patch offset',
      'branch', 'offset', 'add', 'paths', 'restore', 'paths', 'untrack', 'paths',
      'commit', 'message',
      'pull', 'remote branch', 'fetch', 'remote', 'push', 'remote ref',
      'ls-remote', 'remote offset', 'init', '', 'clone', 'message',
      'config', 'name message', 'merge', 'branch action', 'switch', 'branch create',
      'tag', 'name ref message offset',
      'stash push', 'action paths message', 'stash pop', 'action',
      'stash list', 'action offset',
      'worktree add', 'action path ref', 'worktree list', 'action offset',
      'worktree remove', 'action path'],
    ['paths', IfThen(Length(Lista) > 0, 'true'), '',
     'ref', Params.Ref, '', 'to', Params.&To, '',
     'staged', IfThen(Params.Staged, 'true'), '', 'format', Params.Format, '',
     'context', IfThen(Params.Context <> 0, IntToStr(Params.Context)), '',
     'count', IfThen(Params.Count <> 0, IntToStr(Params.Count)), '',
     'search', Params.Search, '', 'patch', IfThen(Params.Patch, 'true'), '',
     'branch', Params.Branch, '', 'remote', Params.Remote, '',
     'action', Params.Action, '', 'name', Params.Name, '',
     'message', Params.Message, '', 'path', Params.Path, '',
     'create', IfThen(Params.Create, 'true'), '',
     'offset', IfThen(Params.Offset <> 0, IntToStr(Params.Offset)), ''], SuyosGit, VaConGit);
  if SobraGit <> '' then
  begin
    // como viaja en el cable: command=stash action=pop, no "command=stash
    // pop" (un agente lo repetia literal y caia en GIT-034; r11b H5)
    var Muestra := Cmd;
    if ModoGit <> Cmd then
      Muestra := Cmd + ' action=' + Copy(ModoGit, Length(Cmd) + 2, MaxInt);
    // ...y si era crear una rama, como se crea (V133 de la 1.23.1)
    Exit(MsgFmt(SR_GIT_NO_VA_CON_COMANDO_FMT, [SobraGit, Muestra, Muestra, ONinguno(SuyosGit)]) + VaConGit +
      IfThen((Cmd = 'branch') and (Params.Create or (Params.Name <> '') or (Params.Branch <> '')),
        MsgText(SF_GIT_RAMA_NUEVA), ''));
  end;
  // offset, solo con una CONSULTA: branch y tag listan (su nota GIT-053 lo
  // ofrece); tag con nombre escribe
  if (Params.Offset <> 0) and not GitCommandIsQuery(Cmd, Params.Action, Params.Name, Params.Message) then
    Exit(MsgFmt(SR_GIT_OFFSET_SOLO_CONSULTA_FMT, [Cmd]));
  // Un comando que no es de la lista se dice ANTES de preguntar nada a git
  // (la lista de abajo acaba en el mismo texto: esta es la que manda, y un
  // comando nuevo que no se apunte aqui no funciona - cerrado).
  if not MatchText(Cmd, ['status', 'diff', 'log', 'show', 'branch', 'add',
       'commit', 'clone', 'pull', 'fetch', 'init', 'config', 'switch', 'merge',
       'stash', 'restore', 'untrack', 'push', 'tag', 'worktree', 'ls-remote']) then
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  // LA JAULA DEL REPO. git no trabaja sobre la carpeta que se le da: sube
  // desde ella hasta dar con el repo, y lee y reescribe ESE arbol entero. La
  // puerta de arriba miraba solo la carpeta: con la raiz del repo por encima
  // de las raices de la sesion, status y diff ensenaban lo de fuera, y
  // stash, switch y commit lo reescribian (medido el 29-sep-2026: una sesion
  // con mono\a por unica raiz reescribio mono\b y escribio en mono\.git).
  // Las TRES carpetas del repo pasan por la misma puerta que paso la suya -
  // la raiz del arbol, su carpeta de git y la comun (la del repo principal
  // de un worktree enlazado) -, y git corre FIJADO a ellas: trabaja donde
  // la puerta miro, no donde el encuentre un repo al volver a buscar. clone
  // hace su repo. init tambien REINICIALIZA el .git que ya exista: su
  // fichero gitdir puede apuntar fuera, y pasa por la misma puerta.
  if (Cmd <> 'clone') and ((Cmd <> 'init') or TieneGit(Repo)) then
  begin
    if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
    begin
      // una carpeta sin repo no es una negativa sino que no hay repo: lo
      // dice git (en ingles, LC_ALL=C); lo demas, su respuesta (GIT-036)
      if Output.Contains('not a git repository') then
        Exit(MsgFmt(SR_GIT_NO_ES_REPO_FMT, [Params.Repo, Output.Trim]));
      Exit(GitFallo(ExitCode, Output));
    end;
    for Sitio in TArray<string>.Create(Raiz, GitDir, Comun) do
      if Sitio <> '' then
      begin
        if (ReadOnlyRootOf(Sitio) <> '') and
           GitCommandIsQuery(Params.Command, Params.Action, Params.Name, Params.Message) then
          Result := ReadPathDenied(Sitio, True)
        else
          Result := PathDenied(Sitio, True);
        if Result <> '' then
          Exit(MsgFmt(SR_GIT_REPO_FUERA_FMT, [Params.Repo, Sitio]));
      end;
    // por el compositor de la casa (EnComillas), como todo argumento
    Fijado := ' --git-dir=' + EnComillas(GitDir);
    if Raiz <> '' then
      Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
    else
      // SIN arbol de trabajo (un repo bare, o "repo" apuntando a la propia
      // .git): --bare. Con --git-dir solo, git toma el directorio actual por
      // arbol de trabajo: status ensenaba el contenido de .git como si
      // fueran los fuentes y switch escribia los ficheros de la rama DENTRO
      // de .git (medido con git a pelo el 29-sep-2026, tercera revision).
      // Con --bare contesta lo que contesta sin fijar: log y branch van, y
      // lo que necesita un arbol dice que no lo tiene.
      Fijado := Fijado + ' --bare';
    // EL REMOTO antes que su endpoint LFS: un pull desde una carpeta de
    // fuera se niega por el remoto (GIT-044), no por el endpoint que de el
    // deriva. La puerta del remoto va delante de la de la configuracion.
    if MatchText(Cmd, ['pull', 'fetch', 'push', 'ls-remote']) then
    begin
      Result := RemotoDenegado(Cmd, Repo, Fijado, IfThen(Raiz <> '', Raiz, Repo),
        Params.Remote);
      if (Result = '') and (Cmd = 'push') then
        Result := EnvioConfiguradoDenegado(Repo, Fijado, Params.Remote, Params.Ref);
      if Result <> '' then
        Exit;
    end;
    Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Action), Fijado);
    if Result <> '' then
      Exit;
    // EL ARBOL ENTERO antes de dejarselo a git (GIT-076): un enlace de
    // dentro hacia donde esta sesion no lee (status, diff, add lo recorren)
    // o no escribe (switch, merge, pull, stash push/pop lo reescriben) para
    // la orden aqui, antes de la red y de git. Por el recorredor del guard,
    // .git aparte; una carpeta que no se deja listar, GUARD-040. La puerta
    // de arriba mira las tres carpetas del repo; git atraviesa un junction
    // como una carpeta (medido el 14-oct-2026: una victima de fuera borrada
    // por switch y stash, metida en el indice por add)
    var Escribe := False;
    if (Raiz <> '') and GitTocaArbol(Cmd, Params.Action, Params.Create, Escribe) then
    begin
      try
        Enlace := EnlaceAjenoEn(Raiz, Escribe, EsCarpetaGit);
      except
        on E: EInOutError do
          Exit(E.Message);
      end;
      if Enlace <> '' then
        Exit(MsgFmt(SR_GIT_ENLACE_AJENO_FMT, [Cmd, Enlace,
          MsgText(IfThen(Escribe, SF_GIT_ENLACE_ESCRIBIR, SF_GIT_ENLACE_LEER))]));
    end;
  end;
  // LAS RUTAS de "paths", por su lector (RutasDeGit): " -- :(literal)...",
  // al final de la orden; sin rutas, " --" solo, para que una revision que
  // se llama como un fichero no sea ambigua. stash push las REESCRIBE: con
  // la puerta del escritor, una a una
  var Rutas := '';
  var Carpetas: TArray<string> := nil;
  var Relativas: TArray<string> := nil;
  if Length(Lista) > 0 then
  begin
    Result := RutasDeGit(Repo, Lista, Cmd = 'stash', RepoSinMayusculas(Repo, Fijado), Cmd, Rutas,
      Carpetas, Relativas);
    if Result <> '' then
      Exit;
  end;
  var Cola := IfThen(Rutas <> '', Rutas, ' --');
  // lo que mas abajo se vuelve a usar: el log con un commit mas de tope
  // ("hay mas") y el fetch de antes de un pull
  var RestoDelLog := '';
  var TopeDelLog := LOG_POR_DEFECTO;
  var RedDelPull := '';
  // LAS REVISIONES, por su juez (git): ref y to. to sin ref no es un rango
  var Desde := Params.Ref.Trim;
  var Hasta := Params.&To.Trim;
  if (Hasta <> '') and (Desde = '') then
    Exit(MsgText(SR_GIT_TO_SIN_REF));
  if MatchText(Cmd, ['diff', 'log', 'show', 'tag']) then
  begin
    Result := RevisionDenegada(Repo, Fijado, 'ref', Desde);
    if Result = '' then
      Result := RevisionDenegada(Repo, Fijado, 'to', Hasta);
    if Result <> '' then
      Exit;
  end;
  if Cmd = 'status' then
    GitArgs := OrdenDeEstado(Cola)
  else if Cmd = 'diff' then
  begin
    var Forma := '';
    case IndexText(Params.Format.Trim, ['', 'stat', 'shortstat', 'words']) of
      0: ;
      1: Forma := ' --stat';
      2: Forma := ' --shortstat';
      3: Forma := ' --word-diff';
    else
      Exit(MsgFmt(SR_GIT_FORMATO_FMT, [Params.Format.Trim, 'diff', 'stat, shortstat, words']));
    end;
    GitArgs := 'diff' + IfThen(Params.Staged, ' --staged') + Forma;
    if Params.Context > 0 then
      GitArgs := GitArgs + ' -U' + IntToStr(Params.Context);
    if Desde <> '' then
      GitArgs := GitArgs + ' ' + EnComillas(Desde);
    if Hasta <> '' then
      GitArgs := GitArgs + ' ' + EnComillas(Hasta);
    GitArgs := GitArgs + Cola;
  end
  else if Cmd = 'ls-remote' then
    GitArgs := 'ls-remote' + IfThen(Params.Remote.Trim <> '', ' ' + EnComillas(Params.Remote.Trim))
  else if Cmd = 'log' then
  begin
    var Forma := '';
    case IndexText(Params.Format.Trim, ['', 'oneline', 'dated', 'full']) of
      0, 1: Forma := ' --oneline';
      2: Forma := ' ' + EnComillas('--format=%h %ci %s');
      3: ;
    else
      Exit(MsgFmt(SR_GIT_FORMATO_FMT, [Params.Format.Trim, 'log', 'oneline, dated, full']));
    end;
    RestoDelLog := Forma;
    // el texto que se busca, CONTENIDO: un solo argumento pegado a -S
    if Params.Search <> '' then
      RestoDelLog := RestoDelLog + ' ' + EnComillas('-S' + Params.Search);
    if Hasta <> '' then
      RestoDelLog := RestoDelLog + ' ' + EnComillas(Desde + '..' + Hasta)
    else if Desde <> '' then
      RestoDelLog := RestoDelLog + ' ' + EnComillas(Desde);
    RestoDelLog := RestoDelLog + Cola;
    if Params.Count > 0 then
      TopeDelLog := Params.Count;
    GitArgs := OrdenDeLog(TopeDelLog, RestoDelLog);
  end
  else if Cmd = 'show' then
  begin
    GitArgs := 'show --stat --format=medium' + IfThen(Params.Patch, ' --patch');
    if Desde <> '' then
      GitArgs := GitArgs + ' ' + EnComillas(Desde);
    GitArgs := GitArgs + Cola;
  end
  else if Cmd = 'branch' then
    GitArgs := 'branch -vv'
  else if Cmd = 'add' then
  begin
    if Length(Lista) = 0 then
      Exit(MsgText(SR_GIT_ADD_NEEDS_PATHS));
    GitArgs := 'add' + Rutas + LoNuestroFuera;
  end
  else if Cmd = 'commit' then
  begin
    if Params.Message.Trim = '' then
      Exit(MsgText(SR_GIT_COMMIT_NEEDS_MESSAGE));
    // -F <file>: the message reaches git byte-exact. Embedding it in the
    // command line mangled double quotes (measured in the field: " -> '').
    // Temporal DEL SERVIDOR, y de los que importan: lleva el mensaje que
    // escribe quien llama. Vivia en el %TEMP% de la MAQUINA, fuera de toda
    // jaula; se borra siempre (mas abajo), pero mientras existe no tiene por
    // que estar donde lo vea cualquiera. Por el nombrador (Lsp.Casa).
    // la carpeta, la del nombre que da EL nombrador (su subcarpeta de la casa
    // vivia a mano aqui y en el tag: H9 de Fable)
    MsgFile := NombreDeMensajeGit;
    CrearCarpeta(ExtractFileDir(MsgFile));
    // por la puerta de escribir, con el temporal como lugar: UTF-8 sin BOM
    EscribeTexto(MsgFile, Params.Message, ltTemporal, ekUtf8);
    GitArgs := 'commit -F ' + EnComillas(MsgFile);
  end
  else if Cmd = 'clone' then
  begin
    // The URL travels in "message" (a URL legitimately carries ':' '/'
    // '@'). Destination = repo (jailed).
    var Url := UrlDeClone(Params.Message);
    if Url = '' then
      Exit(MsgText(SR_GIT_CLONE_NEEDS_REPOSITORY_URL));
    if not EsUrlDeRed(Url) then
      Exit(MsgText(SR_GIT_CLONE_URLS_ACCEPTED));
    if ShellArgDenied(Url) <> '' then
      Exit(MsgText(SR_GIT_SHELL_METACHARS_URL));
    if Url.Contains('--upload-pack') or Url.Contains('--config') or
       Url.StartsWith('-') then
      Exit(MsgText(SR_GIT_URL_NOT_ALLOWED));
    // carpeta O fichero .git: clonar en un worktree enlazado no es clonar
    if TieneGit(Repo) then
      Exit(MsgFmt(SR_GIT_YA_ES_REPOSITORIO_FMT, [Repo]));
    // El destino se crea AQUI, pasadas todas las negativas: un rechazo no
    // deja nada, y si el clone falla se quita solo si lo creo el.
    if not TDirectory.Exists(Repo) then
    begin
      AncestroDelClone := PrimerAncestroQueExiste(Repo);
      CrearCarpeta(Repo);
      CreadaPorElClone := True;
    end;
    // clone into "." of the (jailed, existing) destination directory. The
    // "--" separator guarantees the URL is a POSITIONAL, never parsed as an
    // option, whatever it contains (field round 9). Primero los objetos:
    // ningun filtro ve un endpoint aun sin juzgar.
    GitArgs := Format('clone --no-checkout -- %s .', [EnComillas(Url)]);
  end
  else if Cmd = 'pull' then
  begin
    // SIEMPRE --ff-only, como merge: pull es bajar e integrar, y lo segundo
    // lo hacia como git quisiera. Con las historias divergidas dejaba un
    // commit de mezcla; con --rebase reescribia la historia, y con --squash
    // dejaba el arbol a medias (medido el 29-sep-2026). La rama, un nombre
    // que git admite, y con su remoto: sin el, git la tomaria por uno
    if (Params.Branch.Trim <> '') and (Params.Remote.Trim = '') then
      Exit(MsgFmt(SR_GIT_SIN_REMOTO_FMT, ['pull', 'branch']));
    Result := NombreDenegado(Repo, Fijado, 'branch', Params.Branch);
    if Result <> '' then
      Exit;
    RedDelPull := IfThen(Params.Remote.Trim <> '', ' ' + EnComillas(Params.Remote.Trim)) +
      IfThen(Params.Branch.Trim <> '', ' ' + EnComillas(Params.Branch.Trim));
    GitArgs := 'pull --ff-only' + RedDelPull;
    SeQuitan := [Raiz]; // reescribe el arbol: puede quitar carpetas
  end
  else if Cmd = 'fetch' then
    GitArgs := 'fetch' + IfThen(Params.Remote.Trim <> '', ' ' + EnComillas(Params.Remote.Trim))
  else if Cmd = 'init' then
    GitArgs := 'init'
  else if Cmd = 'config' then
  begin
    // Only the commit identity, so a remote agent can commit on a fresh
    // repo/machine. Anything else in git config stays off-limits.
    if not (SameText(Params.Name.Trim, 'user.name') or
            SameText(Params.Name.Trim, 'user.email')) then
      Exit(MsgText(SR_GIT_CONFIG_ONLY_ACCEPTS_USER));
    // Sin valor LEE el que hay: el que usaria un commit aqui (el del repo, o
    // el global de la cuenta del servidor). Se negaba con GIT-033 y no habia
    // forma de saber con que identidad se iba a firmar (1.21.1)
    if Params.Message.Trim = '' then
      GitArgs := 'config --get ' + SinMayusculas(Params.Name.Trim)
    else
      GitArgs := 'config ' + SinMayusculas(Params.Name.Trim) + ' ' + EnComillas(Params.Message);
  end
  else if Cmd = 'switch' then
  begin
    // Changing branch is what a real workflow needs: an agent could CREATE a
    // branch and never move to it (review 2026-08-25). Only the branch form:
    // the file-restoring forms of checkout DISCARD work, and discarding has
    // its own command with its own words (stash with paths). La rama, un
    // nombre que git admite: sin '-' delante, nunca una opcion
    if Params.Branch.Trim = '' then
      Exit(MsgText(SR_GIT_SWITCH_NEEDS));
    Result := NombreDenegado(Repo, Fijado, 'branch', Params.Branch);
    if Result <> '' then
      Exit;
    if Params.Create then
      GitArgs := 'switch -c ' + EnComillas(Params.Branch.Trim) // el arbol se queda como esta
    else
    begin
      GitArgs := 'switch ' + EnComillas(Params.Branch.Trim);
      SeQuitan := [Raiz]; // la otra rama puede no tener la carpeta de un proyecto
    end;
  end
  else if Cmd = 'merge' then
  begin
    // --ff-only: a merge that would need a commit (and could conflict half
    // way) is refused rather than left half-done. Real conflicts are a
    // human's business, not an agent's guess. A branch git finds, or
    // action=abort. Nothing else.
    SeQuitan := [Raiz]; // lo que entra (o lo que se deshace) puede quitar carpetas
    if SameText(Params.Action.Trim, 'abort') and (Params.Branch.Trim = '') then
      GitArgs := 'merge --abort'
    else if Params.Action.Trim <> '' then
      Exit(MsgText(SR_GIT_MERGE_ARGS))
    else if Params.Branch.Trim = '' then
      Exit(MsgText(SR_GIT_MERGE_NEEDS))
    else
    begin
      Result := RevisionDenegada(Repo, Fijado, 'branch', Params.Branch);
      if Result <> '' then
        Exit;
      GitArgs := 'merge --ff-only ' + EnComillas(Params.Branch.Trim);
    end;
  end
  else if Cmd = 'stash' then
  begin
    // push (default) / pop / list: park work to change branch and get it
    // back. Never "stash drop" - that destroys.
    // Y push con RUTAS es como se DESCARTAN los cambios de unos ficheros
    // sin destruirlos: vuelven a HEAD y lo de antes queda en el stash, de
    // donde pop lo devuelve. Faltaba: devolver dos .res a HEAD obligo a
    // salir a la consola (muro, 26-sep-2026).
    var Accion := LowerCase(Params.Action.Trim);
    if Accion = '' then
      Accion := 'push';
    if MatchText(Accion, ['pop', 'list']) then
    begin
      GitArgs := 'stash ' + Accion;
      // list solo ENSENA; pop reescribe el arbol con lo aparcado
      if Accion = 'pop' then
      begin
        // sin el status que git imprime solo: detras va el nuestro (V66)
        GitArgs := GitArgs + ' --quiet';
        SeQuitan := [Raiz];
      end;
    end
    else if Accion = 'push' then
    begin
      GitArgs := 'stash push';
      if Params.Message.Trim <> '' then
        GitArgs := GitArgs + ' -m ' + EnComillas(Params.Message.Trim);
      // Vuelve a HEAD lo que se aparca, y lo que HEAD no tiene se va: con
      // rutas (ya por la puerta del escritor, arriba), solo bajo sus
      // carpetas; sin ellas, en todo el arbol.
      SeQuitan := [Raiz];
      if Rutas <> '' then
      begin
        GitArgs := GitArgs + Rutas;
        SeQuitan := Carpetas;
      end;
    end
    else
      Exit(MsgFmt(SR_GIT_STASH_ARGS_FMT, [Params.Action.Trim]));
  end
  else if Cmd = 'restore' then
  begin
    // SIEMPRE --staged: deshacer un add. Solo rutas (. = todo): para
    // descartar cambios esta stash con rutas. Hermes (28-sep-2026): sin rm
    // ni reset en la lista, tras un add no habia forma de deshacer el
    // staging y borro el .git para volver a empezar. El indice es del repo
    // (la puerta ya paso por Repo): las rutas no vuelven a preguntar.
    if Length(Lista) = 0 then
      Exit(MsgText(SR_GIT_RESTORE_NEEDS_PATHS));
    GitArgs := 'restore --staged' + Rutas;
  end
  else if Cmd = 'untrack' then
  begin
    // rm --cached: quitar del INDICE lo que git sigue, sin tocar el disco
    // (dos .res regenerados por msbuild obligaron a la consola el
    // 14-oct-2026; Hermes choco con la falta de rm/reset el 28-sep). -r para
    // una carpeta; --quiet, que el eco lo pone la nota (GIT-081). Como
    // restore: el arbol de trabajo, nunca.
    if Length(Lista) = 0 then
      Exit(MsgText(SR_GIT_UNTRACK_NEEDS_PATHS));
    GitArgs := 'rm --cached -r --quiet' + Rutas;
  end
  else if Cmd = 'push' then
  begin
    // uses the SERVER's stored credentials/remotes - consistent with the
    // centralized model (the repo lives next to the compiler). Lo que se
    // envia, UN nombre de rama o de tag que esta aqui: va al remoto con ese
    // mismo nombre. Asi push solo ANADE (David, 29-sep-2026: "nada de
    // destruccion remota"): un '+' (forzar) o un ':dst' (borrar) se niegan por
    // la FORMA (RefspecQueDestruye) antes que por git, que ACEPTA "+main" en
    // cuanto hay una ref que se llama asi (medido el 18-oct-2026: forzaba)
    if (Params.Ref.Trim <> '') and (Params.Remote.Trim = '') then
      Exit(MsgFmt(SR_GIT_SIN_REMOTO_FMT, ['push', 'ref']));
    if (Params.Ref.Trim <> '') and (RefspecQueDestruye(Params.Ref.Trim) or
       not (EsNombreDeRef(Repo, Fijado, Params.Ref.Trim, False) and
       EsNombreDeRef(Repo, Fijado, Params.Ref.Trim, True))) then
      Exit(MsgFmt(SR_GIT_PUSH_NOMBRE_FMT, [Params.Ref.Trim]));
    GitArgs := 'push' + IfThen(Params.Remote.Trim <> '', ' ' + EnComillas(Params.Remote.Trim)) +
      IfThen(Params.Ref.Trim <> '', ' ' + EnComillas(Params.Ref.Trim));
  end
  else if Cmd = 'tag' then
  begin
    if Params.Name.Trim = '' then
    begin
      // sin nombre, lista: ref y message van con un nombre
      if (Desde <> '') or (Params.Message.Trim <> '') then
        Exit(MsgFmt(SR_GIT_NO_VA_CON_COMANDO_FMT, [IfThen(Desde <> '', 'ref', 'message'),
          Cmd, Cmd, MsgText(SF_GIT_TAG_SUYOS)]));
      GitArgs := 'tag';
    end
    else
    begin
      Result := NombreDenegado(Repo, Fijado, 'name', Params.Name);
      if Result <> '' then
        Exit;
      GitArgs := 'tag';
      if Params.Message.Trim <> '' then
      begin
        // -F makes it annotated (like -m) and keeps quotes byte-exact
        MsgFile := NombreDeMensajeGit;
        CrearCarpeta(ExtractFileDir(MsgFile));
        EscribeTexto(MsgFile, Params.Message, ltTemporal, ekUtf8);
        GitArgs := 'tag -F ' + EnComillas(MsgFile);
      end;
      GitArgs := GitArgs + ' ' + EnComillas(Params.Name.Trim);
      if Desde <> '' then
        GitArgs := GitArgs + ' ' + EnComillas(Desde);
    end;
  end
  else if Cmd = 'worktree' then
  begin
    // OTRA version del repo al lado, sin tocar el arbol de nadie: con lo que
    // un agente REMOTO compara con una version anterior sin salirse del MCP
    // (1.4.0; David, 26-sep-2026: 'lo que nos falta para que el agente remoto
    // pueda revisar'). Como clone: la carpeta la elige el agente dentro de sus
    // raices. Sin carpetas temporales ni limpiezas al arrancar (David): la
    // quita quien la pone, y list se la ensena.
    var Sub := SinMayusculas(Params.Action.Trim);
    if Sub = 'list' then
      GitArgs := 'worktree list'
    else if (Sub = 'add') or (Sub = 'remove') then
    begin
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_GIT_WORKTREE_PATH));
      Destino := SinBarraFinal(TPath.GetFullPath(Params.Path.Trim));
      // Crear o quitar una copia de trabajo es ESCRIBIR alli: la pregunta de
      // todo escritor, por la ruta real, y nunca en una carpeta muerta.
      Result := WriteTargetDenied(Destino);
      // ...y que el destino no CONTENGA un lugar protegido: worktree add hace
      // un checkout que escribe el arbol dentro, y un ReadOnlyPaths que nombre
      // un fichero de ahi se escribia (2v de la 1.18.2, medido; el 3.er emisor
      // de la regla del 2r: el destino por la misma pregunta, MOVE-020)
      if (Result = '') and (Sub = 'add') then
        Result := ProtegidoDenegado(Destino, True);
      if Result <> '' then
        Exit;
      if Sub = 'add' then
      begin
        if TDirectory.Exists(Destino) or TFile.Exists(Destino) then
          Exit(MsgFmt(SR_GIT_WORKTREE_EXISTS_FMT, [Destino]));
        if not EsNombreDeRef(Repo, Fijado, Params.Ref.Trim, True) then
          Exit(MsgText(SR_GIT_WORKTREE_REF));
        // Nunca DENTRO del propio repo: el arbol principal la veria como una
        // carpeta sin seguimiento, y un add -A se la llevaria.
        // Por la ruta REAL de los dos: git da nombres largos y el agente
        // puede pasar la forma 8.3 (medido: C:\Users\DFONTA~1 frente a
        // C:/Users/dfontanet - el texto no casaba y lo dejaba dentro).
        var RaizReal := SinBarraFinal(RealPath(Raiz));
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        if (Raiz <> '') and
           RutaDentroDe(RaizReal, DestinoReal) then // dentro o el mismo (H1 de la 1.23)
          Exit(MsgFmt(SR_GIT_WORKTREE_INSIDE_FMT, [Raiz]));
        // por el compositor de la casa, los dos: una revision con un blanco
        // que rev-parse admite se partia en dos argumentos (A2 del cierre)
        GitArgs := 'worktree add --detach ' + EnComillas(Destino) + ' ' + EnComillas(Params.Ref.Trim);
      end
      else
      begin
        // Solo lo que git lista como worktree de ESTE repo, y nunca el
        // principal (el primero): remove no sirve para borrar otra cosa.
        var Copias := GitCorre(Repo, Fijado, 'worktree list --porcelain', 60000, ExitCode);
        var Listado := False;
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        var Primero := True;
        for var Linea in LineasDelTexto(Copias) do
          if Linea.StartsWith('worktree ') then
          begin
            // por la ruta real, como arriba: git lista nombres largos
            if not Primero and SameText(DestinoReal, SinBarraFinal(
                 RealPath(ConBarrasDeWindows(Linea.Substring(9).Trim)))) then
              Listado := True;
            Primero := False;
          end;
        if not Listado then
          Exit(MsgFmt(SR_GIT_WORKTREE_NOT_LISTED_FMT, [Destino]));
        // git worktree remove ATRAVIESA un enlace de dentro y borra lo que hay
        // detras (medido el 26-sep-2026: un junction en una carpeta ignorada
        // dejo vacia una victima de fuera). Con un enlace dentro no se quita.
        Enlace := '';
        RecorreSinEnlaces(Destino,
          procedure(const APath: string)
          begin
          end,
          procedure(const APath: string)
          begin
            if Enlace = '' then
              Enlace := APath;
          end);
        if Enlace <> '' then
          Exit(MsgFmt(SR_GIT_WORKTREE_LINK_FMT, [Enlace]));
        // Lo NUESTRO, fuera antes de que git la borre: con un DelphiLSP vivo
        // en el worktree (un hover basta) git borraba el contenido, no podia
        // con la carpeta y salia con 255 (medido el 29-sep-2026). Se suelta
        // abajo, junto al git y con el cerrojo de escritura ya cogido.
        SeQuitan := [Destino];
        // Sin --force: con cambios, git se niega y lo dice.
        GitArgs := 'worktree remove ' + EnComillas(Destino);
      end;
    end
    else
      Exit(MsgText(SR_GIT_WORKTREE_ARGS));
  end
  else
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  // SEGUNDA BARRERA (David, 11-oct-2026: la redundante se queda). Sin args,
  // cada campo que va SUELTO en la linea tiene su juez (git rev-parse,
  // check-ref-format, la lista de remotos del repo), arriba, y ninguno deja
  // pasar un valor que empiece por '-', que git leeria como una opcion. Si
  // un juez cambia, esto no: se mira aqui, con la orden ya compuesta y antes
  // de todo git que lleve esos valores (el juez de lo protegido, el fetch
  // de un pull, la orden)
  // (y el valor de config, que va suelto detras del nombre; el message de
  // commit y tag va por -F y el de stash detras de -m: nunca sueltos)
  for var Campo in TArray<string>.Create('ref', 'to', 'branch', 'remote', 'name', 'message') do
  begin
    var Valor := '';
    if Campo = 'ref' then Valor := Params.Ref
    else if Campo = 'to' then Valor := Params.&To
    else if Campo = 'branch' then Valor := Params.Branch
    else if Campo = 'remote' then Valor := Params.Remote
    else if Campo = 'name' then Valor := Params.Name
    else if Cmd = 'config' then Valor := Params.Message;
    if Valor.Trim.StartsWith('-') then
      Exit(MsgFmt(SR_GIT_CAMPO_OPCION_FMT, [Campo, Valor.Trim]));
    // ...ni el ref de push con la forma que fuerza o borra en el remoto
    if (Cmd = 'push') and (Campo = 'ref') and RefspecQueDestruye(Valor.Trim) then
      Exit(MsgFmt(SR_GIT_PUSH_NOMBRE_FMT, [Valor.Trim]));
  end;
  if MatchText(Cmd, ['clone', 'pull', 'fetch', 'push', 'ls-remote']) then
    TLogger.Warning(MsgFmt(SL_GIT_NETWORK_FMT,
      [Cmd, Repo, Params.Message]));

  // Lo que REESCRIBE el arbol en local (switch, merge, stash, reset,
  // restore, worktree...) toma el cerrojo de escritura, como todo escritor:
  // un delphi_edit entre medias se perdia con OK. Las de RED no: clone crea
  // una carpeta nueva, fetch y push no tocan el arbol, y pull -que si lo
  // toca- tarda lo que tarde la red y pararia toda edicion del servidor:
  // es la excepcion, y esta escrita (septima revision). Las consultas no
  // escriben.
  var ConCerrojo := not GitCommandIsQuery(Params.Command, Params.Action, Params.Name, Params.Message) and
    not MatchText(Cmd, ['clone', 'pull', 'fetch', 'push']);
  // Lo que REESCRIBE el arbol puede QUITAR carpetas: una rama sin la carpeta
  // de un proyecto, y git borraba sus ficheros, no podia con la carpeta -el
  // motor de ese proyecto la tiene de directorio de trabajo- y la dejaba
  // vacia, con exit=0 (medido el 29-sep-2026). Los motores de lo que se
  // reescribe se paran antes (SeQuitan: lo apunta cada comando, arriba,
  // donde sabe lo que hace - una consulta como stash list, o switch con
  // create, no paran a nadie); vuelven a arrancar en la siguiente peticion.
  //
  // pull es red Y arbol. Lo de la red se hace ANTES, con un fetch: sin
  // marca, porque dura lo que dure la red y en ese rato nadie podria
  // arrancar un motor en el repo. El pull de despues encuentra lo suyo ya
  // bajado y es casi todo local: ese va con la marca, como los demas. (Se
  // soltaba y se quitaba la marca antes de empezar: el motor que arrancaba
  // durante la red volvia a retener su carpeta.) El fetch baja lo MISMO que
  // el pull (su remoto y su rama: RedDelPull); el juez de abajo solo lee el
  // destino de un pull si este fetch corrio Y acabo bien: sin el,
  // FETCH_HEAD no es el destino o es de un fetch viejo
  var FetchHecho := False;
  if SameText(Cmd, 'pull') and (Raiz <> '') then
  begin
    var Previo: Cardinal;
    GitCorre(Repo, Fijado, 'fetch' + RedDelPull, 600000, Previo);
    FetchHecho := Previo = 0;
    // si falla, el pull lo dira con sus palabras
  end;
  // Lo que git REESCRIBIRIA del arbol, preguntado a git (el juez) antes de
  // tocar nada: un fichero de solo lectura dentro del repo (ReadOnlyPaths /
  // ReadOnlyRoots) se reescribia al cambiar de rama (2x de la 1.18.2, medido).
  // Para pull va DESPUES del fetch de arriba, con FETCH_HEAD ya bajado; sin
  // el (si fallo), en un repo con algo protegido se niega.
  Result := GitReescribeProtegido(Repo, Fijado, Raiz, Cmd, Params.Action, Params.Branch,
    Params.Create, FetchHecho);
  if Result <> '' then
  begin
    ExitCode := 1;
    Exit;
  end;
  // (el try de fuera no sangra lo de dentro, como el de RunCore: es solo la
  // regla del clone que no ocurrio, abajo)
  var GitCorrio := False;
  var HayMasEnElLog := False;
  try
  if ConCerrojo then
    EnterFileEdit;
  try
    for Sitio in SeQuitan do
      if Sitio <> '' then
        SueltaLoNuestroBajo(Sitio);
    try
      try
        Output := GitCorre(Repo, Fijado, GitArgs,
          IfThen(MatchText(Cmd, ['push', 'clone', 'pull', 'fetch', 'ls-remote']), 600000, 60000),
          ExitCode);
        GitCorrio := True;
        // V66 de la 1.23.1: el estado que git imprime por su cuenta no pasa
        // por LoNuestroFuera. Tras un stash pop (ya --quiet), el NUESTRO; y un
        // commit que no hizo nada porque no habia nada preparado - lo dice
        // git, diff --cached --quiet; su "nada que confirmar" sale con 1 -
        // contesta con el nuestro en vez del suyo
        if (Cmd = 'stash') and SameText(Params.Action.Trim, 'pop') then
        begin
          var CodigoEstado: Cardinal;
          var Estado := GitCorre(Repo, Fijado, OrdenDeEstado(' --'), 60000, CodigoEstado);
          Output := Output.TrimRight;
          if Output <> '' then
            Output := Output + #10;
          Output := Output + MsgFmt(SN_GIT_ESTADO_TRAS_POP_FMT, [Estado.TrimRight]);
        end
        else if (Cmd = 'commit') and (ExitCode = 1) then
        begin
          var CodigoPreparado, CodigoEstado: Cardinal;
          GitCorre(Repo, Fijado, 'diff --cached --quiet', 60000, CodigoPreparado);
          if CodigoPreparado = 0 then
            Output := MsgFmt(SN_GIT_COMMIT_SIN_NADA_FMT,
              [GitCorre(Repo, Fijado, OrdenDeEstado(' --'), 60000, CodigoEstado).TrimRight]);
        end;
        // log sin count se queda en LOG_POR_DEFECTO commits y no se decia: 20
        // de 30, y offset=20 daba GIT-054 (D7 de los revisores de cierre de la
        // 1.18.2). Si hay MAS lo dice git: la misma orden con un commit mas de
        // tope contesta otra cosa. Con el count del agente, lo que pidio es lo
        // que hay. Con menos lineas que el tope no puede haberlo alcanzado
        if (Cmd = 'log') and (ExitCode = 0) and (Params.Count = 0) and
           (Length(Output.Split([#10], TStringSplitOptions.ExcludeEmpty)) >= LOG_POR_DEFECTO) then
        begin
          var CodigoMas: Cardinal;
          var ConUnoMas := GitCorre(Repo, Fijado, OrdenDeLog(LOG_POR_DEFECTO + 1, RestoDelLog), 60000, CodigoMas);
          HayMasEnElLog := (CodigoMas = 0) and (ConUnoMas <> Output);
        end;
        if (Cmd = 'clone') and (ExitCode = 0) then
        begin
          // El repo ya existe, pero su arbol todavia no se ha materializado.
          if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
            Exit(GitFallo(ExitCode, Output));
          Fijado := ' --git-dir=' + EnComillas(GitDir);
          if Raiz <> '' then Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
          else Fijado := Fijado + ' --bare';
          Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Action), Fijado);
          if Result <> '' then
          begin
            ExitCode := 1;
            Exit;
          end;
          // Un bare no pide arbol. Un clone vacio tampoco.
          if Raiz <> '' then
          begin
            GitCorre(Repo, Fijado, 'rev-parse --verify --quiet HEAD', 60000, ExitCode);
            if ExitCode = 0 then
              Output := GitCorre(Repo, Fijado, 'checkout --force', 600000, ExitCode)
            else if ExitCode = 1 then
            begin
              ExitCode := 0;
              Output := '';
            end;
          end;
        end;
      finally
        if (MsgFile <> '') and TFile.Exists(MsgFile) then
          BorraFichero(MsgFile, ltTemporal); // por la puerta de borrar, con su lugar
      end;
    finally
      for Sitio in SeQuitan do
        if Sitio <> '' then
          YaNoSeQuita(Sitio);
    end;
  finally
    if ConCerrojo then
      LeaveFileEdit;
  end;
  finally
    // A clone that did not happen must not leave its empty destination lying
    // around for the caller to clean up by hand (field round 10).
    // Todas las que creo (n1\n2\n3 dejaba n1\n2), vacias y por la puerta de
    // escritura: la regla de la foto (septima revision). Y el que no llego
    // ni a lanzar git - un servidor sin git, GIT-050 - tampoco ocurrio: se
    // iba por la excepcion y dejaba sus carpetas (medido el 30-sep-2026).
    if (not GitCorrio or (ExitCode <> 0)) and SameText(Cmd, 'clone') and CreadaPorElClone then
      QuitaCarpetasCreadas(Repo, AncestroDelClone);
  end;
  // Una pagina de la respuesta: la de una orden que solo LEE se puede pedir
  // entera, por lineas (offset); se cortaba a 30000 caracteres y no habia
  // forma de ver el resto (muro de la lista del 4-oct-2026). La de una que
  // escribe, no: repetirla con offset la volveria a ejecutar
  if GitCommandIsQuery(Cmd, Params.Action, Params.Name, Params.Message) then
    Output := PaginaDeSalidaGit(Output, Params.Offset)
  else if Length(Output) > TOPE_SALIDA_GIT then
    Output := PrincipioDeTexto(Output, TOPE_SALIDA_GIT) + #10 + MsgText(SF_GIT_TRUNCATED);
  // Un git que dice que no (exit<>0) es un fallo: salia como exito y el
  // agente no lo distinguia de uno que funciono (revision 27-sep-2026). Su
  // salida va detras, que es la que explica que paso. (diff --quiet, que
  // contesta 1 cuando HAY diferencias, se fue con los args en la 1.19.0)
  if ExitCode <> 0 then
    Result := GitFallo(ExitCode, Output)
  else
    Result := GitExito(Output.Trim, 0);
  // config --get de una clave que no esta sale con 1 y sin decir nada: es la
  // forma de git de contestar "no esta fijada", no un fallo (GIT-079)
  if (ExitCode = 1) and (Output.Trim = '') and (Cmd = 'config') and (Params.Message.Trim = '') then
    Result := GitExito(MsgFmt(SN_GIT_CONFIG_SIN_VALOR_FMT,
      [SinMayusculas(Params.Name.Trim), SinMayusculas(Params.Name.Trim)]), 1);
  // Una respuesta que es solo "exit=0" no se distingue de una que se ha roto
  // por el camino, y lo primero que hace quien la recibe es repetirla. El
  // silencio de git SIGNIFICA cosas distintas segun la orden, asi que se
  // dice cual (medido 2026-09-20 pidiendo el diff de un arbol limpio).
  if (ExitCode = 0) and (Output.Trim = '') then
  begin
    if SameText(Cmd, 'diff') then
      Result := GitExito(MsgText(SN_GIT_DIFF_CLEAN), 0)
    else if GitCommandIsQuery(Cmd, Params.Action, Params.Name, Params.Message) then
    begin
      // Una consulta vacia dice LO QUE RECIBIO git (sin la -C del repo ni la
      // configuracion de la casa): "log -S<texto>" vacio parecia que el texto
      // se perdia por el camino, y era que el fichero decia otra cosa (Hermes,
      // validacion de la 1.16.0). Solo en las que leen: en las que escriben,
      // callar ya es el exito y el eco repetiria URLs y valores.
      Result := GitExito(MsgFmt(SN_GIT_CONSULTA_VACIA_FMT, [GitArgs.Trim]), 0);
      if SameText(Cmd, 'log') and (Params.Search <> '') then
        Result := Result + #10 + MsgText(SN_GIT_PICKAXE_VACIO);
    end
    else
      Result := GitExito(MsgFmt(SN_GIT_SILENT_OK_FMT, [Cmd]), 0);
  end;
  // Un worktree nuevo es de quien lo pidio: se lo dice, con como quitarlo.
  if (ExitCode = 0) and (Cmd = 'worktree') and SameText(Params.Action.Trim, 'add') then
    Result := Result + #10 + MsgFmt(SN_GIT_WORKTREE_ADDED_FMT, [Destino]);
  // restore no toca el arbol: se dice, con la via que si descarta (GIT-077)
  if (ExitCode = 0) and (Cmd = 'restore') then
    Result := Result + #10 + MsgText(SN_GIT_RESTORE_SOLO_INDICE);
  // untrack tampoco: se dice que hizo y que viene despues (GIT-081)
  if (ExitCode = 0) and (Cmd = 'untrack') then
    Result := Result + #10 + MsgText(SN_GIT_UNTRACK_SOLO_INDICE);
  // add que no pudo por un ignorado: cual y por que regla (GIT-078)
  if (ExitCode <> 0) and (Cmd = 'add') then
    Result := Result + IgnoradosDeGit(Repo, Fijado, Raiz, Relativas);
  // git's own hints recommend exactly what this tool refuses (--no-ff,
  // rebase, "specify the URL from the command-line"): say so, or the reader
  // follows the advice printed last (field round 10). Desde la 1.19.3 git
  // no escribe sus consejos (GIT_ADVICE=0, en GitCorre); esto se queda de
  // segunda barrera para un git anterior a la 2.46 y para "specify the
  // URL", que es su error y no un consejo.
  // Un merge que no puede ir en fast-forward muere con exit 128 y "Not
  // possible to fast-forward": git no sugiere nada y la respuesta era el
  // codigo a pelo (abierto menor del 22-sep). Se dice que significa.
  if HayMasEnElLog then
    Result := Result + #10 + MsgFmt(SN_GIT_LOG_HAY_MAS_FMT, [LOG_POR_DEFECTO]);
  if (ExitCode <> 0) and MatchText(Cmd, ['merge', 'pull']) and Output.Contains('fast-forward') then
    Result := Result + #10 + MsgText(SN_GIT_MERGE_DIVERGED);
  if (ExitCode <> 0) and (Output.Contains('--no-ff') or Output.Contains('rebase') or
     Output.Contains('specify the URL')) then
    Result := Result + #10 + MsgText(SN_GIT_HINT_OVERRIDE);
  // El CONTENIDO de un diff, de un show o de un log - las lineas de un
  // fichero o de un mensaje de commit, que empiezan por +, - o espacio -
  // viaja como esta en el disco: el barrido de unidades las reescribia
  // (Lsp.Mascara.EnmascaraSalvoContenido). Lo que dice git - cabeceras,
  // avisos, que si pueden nombrar una ruta del servidor - sigue enmascarado.
  if (ExitCode = 0) and MatchText(Cmd, ['diff', 'show', 'log']) then
    Result := EnmascaraSalvoContenido(Result, '+- ');
end;

{ La respuesta de git que acabo bien: "exit=0" y lo que dijo. El formato que
  leen los agentes y las baterias, compuesto en UN sitio (estaba a mano tres
  veces). La que acabo mal es SR_GIT_EXIT_FMT. }
function GitExito(const ACuerpo: string; AExit: Integer): string;
begin
  Result := 'exit=' + IntToStr(AExit) + #10 + ACuerpo;
end;

{ La que acabo MAL: GIT-036, lo que dijo git y las pistas que salen de lo que
  dijo - lo que el agente SI puede hacer, o de quien es el arreglo cuando no
  es suyo. Las tres salidas que acaban en GIT-036 (la carpeta de un remoto,
  la jaula del repo y la orden misma) pasan por aqui: las pistas iban solo en
  la ultima, y el "dubious ownership" de un NAS sale en la jaula, antes de la
  orden (Hermes, 5-oct-2026). Las pistas que dependen de la orden (merge,
  pull) se quedan con la orden. }
function GitFallo(ACodigo: Cardinal; const ASalida: string): string;
begin
  Result := MsgFmt(SR_GIT_EXIT_FMT, [ACodigo, ASalida.Trim]);
  // A fresh repo has no author identity and commit dies with exit 128:
  // the fix is already whitelisted, say so (measured 2026-08-24).
  if ASalida.Contains('Author identity unknown') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_CONFIGURA_IDENTIDAD);
  if ASalida.Contains('dubious ownership') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_PROPIEDAD_DUDOSA);
end;

initialization
  GCacheGitDirLock := TCriticalSection.Create;
  GCacheGitDir := TDictionary<string, string>.Create;
  // la puerta de escritura (baja) pregunta a git por aqui (9.A)
  Lsp.Guard.DameGitDirDeCarpeta := GitDirDeCarpeta;
  Lsp.Guard.DameRepoDeCarpeta := RepoDeCarpeta;
  TMCPRegistry.RegisterTool('delphi_git',
    function: IMCPTool begin Result := TDelphiGitTool.Create; end);

finalization
  Lsp.Guard.DameGitDirDeCarpeta := nil;
  Lsp.Guard.DameRepoDeCarpeta := nil;
  GCacheGitDir.Free;
  GCacheGitDirLock.Free;

end.
