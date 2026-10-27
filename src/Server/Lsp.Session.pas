unit Lsp.Session;

{ Workspace/session manager: owns the DelphiLSP client processes behind the
  MCP tools. One agent-mode client per project settings file, created lazily
  on the first request that touches a file of that project, then kept warm.

  Project settings resolution: the .dproj that serves the requested file
  (FindDproj: the one in its folder or above, or the one that lists it or
  reaches its folder by search path), and the settings the server makes from
  it (Lsp.ConfigFabricator), made again on every request and given again to
  an engine that is running when they change. The IDE's *.delphilsp.json is
  never read (1.20.2: it was stale as soon as an agent touched the .dproj,
  measured). Files with no project anywhere still get documentSymbol
  (measured: it works unconfigured), but hover/definition will answer null -
  the tools say so in their output. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Lsp.Transport.Process,
  Lsp.Client,
  Lsp.Discovery,
  Lsp.ConfigFabricator,
  Lsp.Guard;

var
  { A document the engine has open that nobody has asked about for this long
    is closed on the next request of its engine (didClose): the engine then
    reads it from the disk when a question crosses it, fresh, and it is
    opened again when asked about. A variable, not a constant, so a unit
    test can shorten it; the operator's setting comes with the life of the
    engines. }
  LspDocIdleMs: UInt64 = 30 * 60 * 1000;
  { An engine nobody has used for this long, with nothing in flight, is
    stopped by the sweeper, and the next request of its project starts
    another: measured 2026-09-30 on a 60-unit project, 1.7 s to the first
    answer of a new engine, and 125 MB held by each one at rest. 0 = never.
    Both come from [Server] EngineIdleMinutes when the session is created
    (LspDocIdleMs only when it is not 0); variables, so a unit test can
    shorten them. }
  LspEngineIdleMs: UInt64 = 30 * 60 * 1000;
  { An engine with something in flight and no sign of life for this long is
    HUNG (TLspClient.Hung): the sweeper stops it, whoever waited on it is told
    LSP-033 and the next request starts another. Until now a request to an
    engine that had stopped reading waited with no bound once its pipe was
    full. BELOW the shortest request timeout (30 s): above it, an engine
    asked one request at a time would never be seen hung. 0 = never. }
  LspHungMs: UInt64 = 20 * 1000;
  { How often the sweeper looks. 0 = its thread does not sweep: the unit
    tests call Sweep themselves, and a pass of the thread in between would
    decide before theirs. }
  LspSweepMs: Cardinal = 2000;

type
  ELspSession = class(Exception);

  { The .dproj FindDproj found for a FILE, with the stamps of EVERYTHING the
    answer was decided on (HuellaDe): every folder walked - a .dproj that
    appears closer, beside it or in a folder walked below changes the answer
    - and every .dproj judged, with its main source. Only the chosen one's
    stamps were kept, and a second project that LISTS the unit, created
    beside the first, was not seen until the server restarted (measured
    18-oct-2026). While all of them are unchanged the walk (directory scans,
    the projects read on the way) is skipped (hermes, release audit
    2026-08-26, P1.6). Only an answer a JUDGE gave in the folders walked is
    kept (it lists the unit, it reaches its folder, it is the only one
    there): a fallback, one given while a candidate could not be read, one
    with a stamp that could not be asked, or the one found by search path
    BELOW when nobody lists the unit (a project listing it could appear
    anywhere down there) is looked for again. The settings are made again on
    every request - the .dproj is not all they depend on. Per file and not
    per folder: the judge of a unit's project is whether a project LISTS it,
    and two units of one shared folder may belong to two projects. }
  TSettingsEntry = record
    SourceFile: string;
    // lo sellado (PARTE_CARPETA / PARTE_PROYECTO + la ruta) y sus sellos, en
    // ese orden: la huella (HuellaDe)
    Partes: TArray<string>;
    Huella: string;
  end;

  { A client taken out of service, and when. }
  TRetiredClient = record
    Client: TLspClient;
    At: UInt64;
  end;

  { A folder that is being taken away, and since when. Folder as it was
    given (the second notice names it the same way); Real, resolved: what it
    is compared by. }
  TLeavingFolder = record
    Folder, Real: string;
    Since: UInt64;
  end;

  TLspSession = class
  private
    class var FInstance: TLspSession;
  private
    // The lock of the TABLES (clients, folders, the settings cache). Held
    // for moments, always: nothing is done under it that asks the disk or
    // waits for an engine - the paths it compares come resolved, and retiring
    // a client takes that client's own lock, under which nothing is written
    // to the engine. What is
    // known of a client's DOCUMENTS is the client's own, with a lock of its
    // own (TSessionClient), held while that engine is written to: an engine
    // that stops reading keeps the requests of ITS project, and no other.
    // With one lock for everything it kept every LSP request of the server,
    // and every delete and move of a tree waited for it.
    FTables: TCriticalSection;
    // (the values are TSessionClient)
    FClients: TObjectDictionary<string, TLspClient>;
    // The folder each client's engine HOLDS (FClients key -> folder): the
    // one of the main source its settings name, which the engine makes its
    // current directory when it loads them - not the project root, when the
    // .dpr lives in another folder than the .dproj (measured 2026-09-29).
    // The project root for a client with no settings. The key itself names
    // the SETTINGS file, which may sit in the server's own cache. RESOLVED
    // (Resolved), like the ones of FBuilding and FLeaving: they are compared
    // under the lock.
    FHeldFolders: TDictionary<string, string>;
    // Clients taken out of service while somebody may still hold them: the
    // process is stopped and whoever was waiting on it has been told. The
    // object is freed when no request can still be on it (RETIRED_KEEP_MS),
    // by the sweeper's next pass (and when a folder leaves, or a dead engine
    // is found): they used to pile up until the server stopped. Under
    // FTables, like the four tables around it.
    FRetired: TList<TRetiredClient>;
    // The folders being taken away right now, between the guard's two
    // notices: no engine is started or registered under one of them.
    FLeaving: TList<TLeavingFolder>;
    // The held folders of the engines being BUILT (the slow path of
    // GetClient runs unlocked, for seconds): whoever takes a folder away
    // waits for the ones under it, which are refused when they finish.
    FBuilding: TList<string>;
    FSettingsCache: TDictionary<string, TSettingsEntry>;
    FSweeper: TThread; // calls Sweep every LspSweepMs
    function EnsureExe: string;
    function BuscaDproj(const AFilePath: string; out ADecidido: Boolean;
      out APartes: TArray<string>; out AHuella: string): string;
    function CreateClient(const ARootDir, ASettingsFile: string;
      AServerType: TLspServerType): TLspClient;
    function ClientKey(const AFullPath: string; ALinter: Boolean;
      out ASettingsUsed, ARootDir: string): string;
    function GetClient(const AFullPath: string; ALinter: Boolean;
      out ASettingsUsed, AClientKey, ARootDir: string): TLspClient;
    function Leaving(const AHeldReal: string): Boolean;
    function TakeRetired(AAll: Boolean): TArray<TLspClient>;
    function TakeOut(const AKey: string): TLspClient;
    procedure DoFolderLeaves(const AFolder: string);
    procedure DoFolderLeft(const AFolder: string);
    function RutaParaAbrir(const AFilePath: string; ADelMotor: Boolean): string;
    procedure AbreDocumento(AClient: TLspClient; const AFullPath, ASettings: string);
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TLspSession;
    class procedure Shutdown;

    { Lets go of what THIS server holds under a folder that is about to be
      moved or deleted: the warm clients whose held folder is that folder or
      sits inside it. A LINK is judged by
      where it is, as the mover does: taking a junction away moves nothing
      behind it, and releases nothing there. The engine makes the folder of
      the project's main source its CURRENT
      DIRECTORY when it loads the project settings (measured with the engine
      launched by hand: free after initialize, held after
      workspace/didChangeConfiguration), Windows will not rename or delete
      the current directory of a live process, and nothing ever stopped an
      engine: after a single hover, deleting the project's folder answered
      FILE-036 and moving it SYS-027 (Hermes, in the field, 2026-09-29). Of
      our tools only the ones that start an engine leave the folder held
      (measured on ten). A subfolder of a warm project is not held
      (measured), so a client whose root is ABOVE the folder stays. The
      process is stopped and the object kept: a request of another agent in
      flight on it gets an error, not freed memory. Never raises, never
      WAITS without a bound and never waits for the health of an engine (the
      tables it needs have a lock of their own, which no writer stuck in an
      engine's pipe holds).

      TWO notices, always in a pair (the guard gives them): ABegins when the
      folder is about to go, and the other one when it is over, whatever
      happened. In between the folder is LEAVING: an engine that another
      agent's first request was building under it is waited for and refused,
      and none is started - releasing and taking away were not one thing, and
      the engine that started in the middle held the folder again. A notice
      that never gets its pair expires on its own. }
    class procedure FolderLeaves(const AFolder: string; ABegins: Boolean);

    { Finds the .dproj that governs a source file ('' if none), full path:
      walks up the directory tree; a .dproj in the file's folder or above
      governs it (with several, the one that LISTS it - by its path, or it is
      its main source -, then one that reaches its folder by search path, then
      one matching the directory name, then the first); from a folder with
      none, the first .dproj of the levels below that LISTS it (a
      SharedSource next to codigofuente), and only when no project lists it
      anywhere, the first of them that reaches its folder by search path. It
      was the first whose TEXT carried the unit's name: a unit reached by
      search path had no project, and with two copies side by side the unit
      of one went to the other's (measured 18-oct-2026); and the two judges
      at one level gave a demo below that reaches the folder over the project
      above that lists the unit (review of 18-oct-2026). Cached per file
      (TSettingsEntry). }
    function FindDproj(const AFilePath: string): string;

    { The folder an engine for this file starts with: the one of the .dproj
      that serves it (FindDproj), its own without one - for who needs the
      root and not the settings (the root of a rename or a references). }
    function RaizDelMotor(const AFilePath: string): string;

    { Full resolution: the settings made from the .dproj that serves the file
      (FindDproj), '' when there is none. ARootDir is the workspace root to
      initialize the LSP with (RaizDelMotor) - always a PROJECT directory,
      never the settings cache. Who only asks whether there IS a project asks
      FindDproj: this one makes the settings. }
    function ResolveSettings(const AFilePath: string; out ARootDir: string): string;

    { Returns the warm agent client for the file's project (creating it if
      needed) plus the settings file it runs with (''= unconfigured). Also
      ensures the document is open on that client. Thread-safe. }
    function AcquireFor(const AFilePath: string; out ASettingsUsed: string): TLspClient;

    { Lo mismo que AcquireFor sobre un motor DADO (uno que dio AcquireFor):
      el documento abierto y al dia en ESE motor, sin buscar el suyo. Lo
      que references abre de sus candidatos va al motor al que luego
      pregunta: con AcquireFor, una unidad compartida arrancaba el motor de
      OTRO proyecto -el primero cuyo .dproj la nombra- para calentarla, y la
      pregunta iba al de siempre (menor de la ronda 16, medido el
      4-oct-2026: dos motores donde hacia falta uno). Lo que abre lo dio el
      MOTOR (el destino de la cadena de declaration, un candidato), y se
      juzga con los lugares del motor, no con la jaula (RutaParaAbrir). }
    procedure AbreEn(AClient: TLspClient; const AFilePath: string);

    { Lints AFilePath (disk content) through a warm LINTER client of its
      project and returns the publishDiagnostics params (caller frees), or
      nil on timeout. Re-lints on every call via didChange. }
    function LintFile(const AFilePath: string; ATimeoutMs: Integer;
      out ASettingsUsed: string): TJSONObject;

    { How many documents the agent engine of AFilePath's project has open;
      -1 when there is no engine for it (none is started to answer). For
      the unit tests: it resolves the project's settings as a request does
      and does not go through the gate, so it is not for a path an agent
      gives. }
    function OpenDocuments(const AFilePath: string): Integer;

    { Stops the engines that are HUNG and the ones nobody has used for
      LspEngineIdleMs, and frees the retired clients nobody can be on any
      more. The session's own thread calls it every LspSweepMs; public for
      the unit tests, which call it themselves. Never raises. }
    procedure Sweep;
  end;

implementation

uses
  MCPServer.Logger,
  Lsp.Texts,
  Lsp.ShaCache, // DiskStamp: one composer of the disk fingerprint
  Lsp.Patch, // LeeTexto: la puerta de leer
  Lsp.Settings,
  Lsp.Dproj,         // BuscaEnCarpeta: que proyecto sirve a una unidad
  Lsp.ProjectUnits,  // ProyectoListaUnidad, la otra mitad
  Lsp.Rutas;

type
  { What the engine holds of one document. }
  TDocState = record
    Path: string;    // as the engine was given it: its uri is made from this
    Version: Integer;
    Stamp: string;   // DiskStamp taken just before the text the engine has
    LastUsed: UInt64; // GetTickCount64 of the last question about it
  end;

  { The session's client: a client, and what the session knows of ITS
    documents, under a lock of its own. They used to live in three tables of
    the session, keyed by the project, under the one lock that was held
    while ANY engine was written to. Two things came of that. An engine that
    stopped reading its pipe stopped every LSP request of the server, not
    only its own project's. And the client that came after one stopped by
    the server - same project, files untouched - read what had been written
    down for the dead one: measured 2026-09-29, a diagnostics that was in
    flight when git stopped its engine, repeated, sent nothing to the new
    engine, waited 40 s and answered "in progress", every time. Now they are
    born and die with their client. Keys: the file, lower case. }
  TSessionClient = class(TLspClient)
  private
    FDocLock: TCriticalSection;
    // every document the engine has open, and what it was last given. The
    // engine never looks at the disk of a document it has open: the CURRENT
    // disk truth reaches it only through didChange, from Refresh, and a
    // request that crosses a unit edited on disk must find it there already.
    FDocs: TDictionary<string, TDocState>;
    // text the LSP is linting per doc: a retry with the same text must NOT
    // restart the lint, just wait for (or collect) the pending diagnostics
    FLintText: TDictionary<string, string>;
    // GetTickCount64 of the last time the session handed this client out
    // (under the session's FTables): what the sweeper calls "not used"
    FLastUsed: UInt64;
    // the disk stamp of its settings file when it was last given to the
    // engine (under FDocLock, set at creation before the client is public)
    FSettingsStamp: string;
    function Refresh(const AExceptKey, AStrictKey: string): Boolean;
    { The engine with the settings of NOW: when their file changed since it
      was last given (its stamp), it is given again -
      workspace/didChangeConfiguration, which a running engine reloads
      (measured with the engine alone: 0.2 s the agent's, 0.6 s the linter's)
      - and the lints it remembers are forgotten, so the same text is linted
      again with them. They went to it once, when it started, and an
      add-searchpath was not seen until the server restarted (M5). Called
      with FDocLock held. True when they were given. }
    function AjustesAlDia(const ASettings: string): Boolean;
    procedure Close(const AKey: string; const AD: TDocState);
    procedure Touch(const AKey: string);
  public
    constructor Create(ATransport: TLspProcessTransport);
    destructor Destroy; override;
    { Tiene abierto en el motor algun documento BAJO esa carpeta (real): el
      motor guarda un handle del fichero y, en un recurso SMB, la carpeta
      borrada queda "borrandose" hasta que el motor se para (medido el
      19-oct-2026 en el NAS: una unidad gobernada por un .dproj de ARRIBA,
      cuya carpeta retenida no esta bajo la que se va). Bajo FDocLock. }
    function TieneDocumentoBajo(const AFolderReal: string): Boolean;
  end;

constructor TSessionClient.Create(ATransport: TLspProcessTransport);
begin
  inherited Create(ATransport, True);
  FDocLock := TCriticalSection.Create;
  FDocs := TDictionary<string, TDocState>.Create;
  FLintText := TDictionary<string, string>.Create;
end;

destructor TSessionClient.Destroy;
begin
  FLintText.Free;
  FDocs.Free;
  FDocLock.Free;
  inherited;
end;

type
  { The session's sweeper: a thread that calls Sweep every LspSweepMs. }
  TEngineSweeper = class(TThread)
  private
    FSession: TLspSession;
    FStop: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(ASession: TLspSession);
    destructor Destroy; override;
  end;

constructor TEngineSweeper.Create(ASession: TLspSession);
begin
  FSession := ASession;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TEngineSweeper.Destroy;
begin
  FStop.SetEvent;
  inherited; // waits for Execute to leave
  FStop.Free;
end;

procedure TEngineSweeper.Execute;
var
  Every: Cardinal;
begin
  NameThreadForDebugging('LspSweeper');
  repeat
    // 0 = no pass (see LspSweepMs): it only goes on looking at the variable
    Every := LspSweepMs;
    if Every = 0 then
      Every := 200;
    if FStop.WaitFor(Every) <> wrTimeout then
      Break;
    if LspSweepMs <> 0 then
      FSession.Sweep;
  until False;
end;

{ Frees clients that are in no table any more. Never raises. }
procedure FreeClients(const AClients: TArray<TLspClient>);
var
  C: TLspClient;
begin
  for C in AClients do
    try
      // one whose transport left a writer behind inside its write is KEPT:
      // that thread comes back to this object - its locks, its documents -
      // when whoever holds the engine's pipe lets go (the transport keeps
      // itself the same way)
      if not C.WriterLeft then
        C.Free;
    except
    end;
end;

function Stopper(AClient: TLspClient): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AClient.StopEngine;
      except
        // a process that will not stop leaves the move to fail, whole
      end;
    end);
  Result.FreeOnTerminate := False;
end;

{ Stops the engines ALL AT ONCE and waits for them. A stop is bounded, and
  its bounds add up to 20 s for an engine that neither answers, ends nor
  lets go of its pipes (1 s for its answer to `shutdown` and 3 s for the
  thread that asked, in TLspClient.StopEngine; 16 s in
  TLspProcessTransport.Stop); one engine after another, those seconds were
  multiplied by the engines of a whole repository, with the global
  write lock held by whoever was taking the folder away. Healthy engines go
  at once (measured 2026-09-29: a folder with two of them under it, stopped
  one after the other, was deleted in 0,7-0,9 s). Never raises. }
procedure StopAll(const AClients: TArray<TLspClient>);
var
  Threads: TArray<TThread>;
  I: Integer;
begin
  SetLength(Threads, Length(AClients));
  for I := 0 to High(AClients) do
  begin
    Threads[I] := nil;
    // the last one (the only one, most of the times) in this thread
    if I < High(AClients) then
      try
        Threads[I] := Stopper(AClients[I]);
        Threads[I].Start;
      except
        FreeAndNil(Threads[I]); // no thread to be had: here, then
      end;
    if Threads[I] = nil then
      try
        AClients[I].StopEngine;
      except
      end;
  end;
  for I := 0 to High(Threads) do
    if Threads[I] <> nil then
    begin
      Threads[I].WaitFor;
      Threads[I].Free;
    end;
end;

{ The sweeper's pass, in three steps. Under the tables' lock - where a
  request takes its client and renews its use, so a client handed out is
  never one being taken out - the engines nobody uses are taken out, and the
  ones that LOOK hung are set aside: looking at an engine asks the system
  for two counters and takes that client's own lock for a moment, and
  nothing waits. Those are stopped at once. Then each suspect is ASKED,
  outside the lock (that waits for an answer): an engine that answers is
  alive and not working - it serves one request at a time, and to one it
  cannot parse it never answers and goes on with the rest (both measured
  2026-09-30) -, and only the one that answers nothing is taken out, under
  the lock again, and stopped, always; what was done is said last. }
procedure TLspSession.Sweep;
const
  PROBE_WAIT_MS = 2000; // the engine answers a probe in 0 to 2 ms (measured)
var
  K: string;
  C: TSessionClient;
  Still: TLspClient;
  Gone, Old, Suspects: TArray<TLspClient>;
  SuspectKeys, Said: TArray<string>;
  Tick: UInt64;
  I: Integer;
begin
  Gone := nil;
  Said := nil;
  Old := nil;
  Suspects := nil;
  SuspectKeys := nil;
  try
    try
      FTables.Enter;
      try
        Tick := TThread.GetTickCount64;
        Old := TakeRetired(False);
        for K in FClients.Keys.ToArray do
        begin
          C := FClients[K] as TSessionClient;
          if C.Hung(LspHungMs) then
          begin
            Suspects := Suspects + [C];
            SuspectKeys := SuspectKeys + [K];
          end
          else if (LspEngineIdleMs > 0) and (Tick - C.FLastUsed > LspEngineIdleMs) and not C.Busy then
          begin
            Said := Said + [MsgFmt(SL_LSP_ENGINE_IDLE_FMT, [K,
              FormatFloat('0.##', LspEngineIdleMs / 60000, TFormatSettings.Invariant)])];
            TakeOut(K);
            Gone := Gone + [C];
          end;
        end;
      finally
        FTables.Leave;
      end;
      FreeClients(Old);
      // The ones nobody uses are stopped NOW, before anybody is asked
      // anything: asking takes up to two seconds per silent suspect, and a
      // client out of the tables with its engine alive is one a folder that
      // leaves does not find.
      StopAll(Gone);
      Gone := nil;
      for I := 0 to High(Suspects) do
        if not Suspects[I].AnswersProbe(PROBE_WAIT_MS) then
        begin
          FTables.Enter;
          try
            // still the client of its key: a folder that left meanwhile took it
            if FClients.TryGetValue(SuspectKeys[I], Still) and (Still = Suspects[I]) then
            begin
              Said := Said + [MsgFmt(SL_LSP_ENGINE_HUNG_FMT, [SuspectKeys[I], LspHungMs div 1000])];
              TakeOut(SuspectKeys[I]);
              Gone := Gone + [Suspects[I]];
            end;
          finally
            FTables.Leave;
          end;
        end;
    finally
      // whatever happened above, what was taken out is stopped: a client out
      // of the tables with its engine alive is one nobody can find any more
      StopAll(Gone);
    end;
    for I := 0 to High(Said) do
      TLogger.Info(Said[I]);
  except
    // a pass that fails is the next pass's work
  end;
end;

function TLspSession.EnsureExe: string;
var
  Info: TRadStudioInfo;
begin
  // La instalacion la elige DiscoverRadStudio: la del servidor ([Server]
  // DelphiVersion), una por proceso. Se llama solo al arrancar un motor.
  Info := DiscoverRadStudio;
  if not Info.Found or (Info.DelphiLspExe = '') then
    raise ELspSession.Create(
      MsgText(SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED));
  Result := Info.DelphiLspExe;
end;

constructor TLspSession.Create;
begin
  inherited;
  FTables := TCriticalSection.Create;
  FSettingsCache := TDictionary<string, TSettingsEntry>.Create;
  FClients := TObjectDictionary<string, TLspClient>.Create([doOwnsValues]);
  FHeldFolders := TDictionary<string, string>.Create;
  FRetired := TList<TRetiredClient>.Create;
  FLeaving := TList<TLeavingFolder>.Create;
  FBuilding := TList<string>.Create;
  // [Server] EngineIdleMinutes (Lsp.Settings): the engines nobody uses and the
  // documents nobody asks about, by one key. 0 leaves the engines alone (and
  // the documents with their half hour).
  var Min := EngineIdleMinutes;
  if Min > 0 then
  begin
    LspEngineIdleMs := Round(Min * 60000);
    if LspEngineIdleMs = 0 then
      LspEngineIdleMs := 1; // under a millisecond is still "at once", not "never"
    LspDocIdleMs := LspEngineIdleMs;
  end
  else
    LspEngineIdleMs := 0;
  FSweeper := TEngineSweeper.Create(Self);
end;

destructor TLspSession.Destroy;
begin
  // all at once first, like the ones of a folder that leaves: freed one
  // after another, the bounds of each stop added up while the server stopped
  FreeAndNil(FSweeper); // first: it walks the tables
  StopAll(FClients.Values.ToArray);
  // (one whose transport left a writer behind is not freed under it: see FreeClients)
  for var K in FClients.Keys.ToArray do
    if FClients[K].WriterLeft then
      FClients.ExtractPair(K);
  FClients.Free; // frees clients, which stop their transports (and children)
  FreeClients(TakeRetired(True)); // already stopped; nobody can hold one at this point
  FRetired.Free;
  FLeaving.Free;
  FBuilding.Free;
  FHeldFolders.Free;
  FSettingsCache.Free;
  FTables.Free;
  inherited;
end;

{ The three things the engine's copy of a document is known by, in one. }
function DocState(const APath: string; AVersion: Integer; const AStamp: string): TDocState;
begin
  Result.Path := APath;
  Result.Version := AVersion;
  Result.Stamp := AStamp;
  Result.LastUsed := TThread.GetTickCount64;
end;

{ Brings the engine up to date with the disk. Every document it has open
  whose file changed since it was last given its text is sent again
  (didChange), and a lint of it pending by text is forgotten (it would be
  compared with a text the engine no longer has); one nobody has asked about
  for LspDocIdleMs, and one whose file is gone, are closed (didClose).
  AExceptKey is left to its caller, who sends it by itself. AStrictKey is
  the document the request is about: it is never closed here, and what fails
  for it is raised, as it always was - the answer would be computed on the
  old text, in silence -; for the others a file that cannot be read right
  now is left for the next request (first review of 1.7.8). Called with
  FDocLock held. True when something was SENT (a close is not).
  Measured 2026-09-30 (Hermes, RENAME-017): only the document asked about
  used to be refreshed, so a unit edited on disk kept its old text in the
  engine for as long as nobody asked INSIDE it, and a definition from the
  .dpr answered the old line - 25 s measured, with no bound. The rename
  resolved its target before the unit was refreshed and validated the
  occurrences after it: two lines for one function, refused as lookalikes. }
function TSessionClient.Refresh(const AExceptKey, AStrictKey: string): Boolean;
var
  Key, Stamp: string;
  D: TDocState;
  Strict: Boolean;
  Tick: UInt64;
begin
  Result := False;
  Tick := TThread.GetTickCount64;
  for Key in FDocs.Keys.ToArray do
  begin
    if Key = AExceptKey then
      Continue;
    Strict := Key = AStrictKey;
    D := FDocs[Key];
    // Nobody has asked about it for a while: closed, without a look at the
    // disk. The engine reads a unit it does not have open from the disk,
    // fresh, whenever a question crosses it (measured 2026-09-30), so the
    // open set - and what every request pays to keep it in step, one stamp
    // per document, a round trip each on a network share - stays bounded.
    // Asked about again, it is opened again.
    if (not Strict) and (Tick - D.LastUsed > LspDocIdleMs) then
    begin
      Close(Key, D);
      Continue;
    end;
    // the stamp BEFORE the text: a write between the two is seen next time
    Stamp := DiskStamp(D.Path);
    // Its file is gone (deleted, renamed, a branch without it): closed too.
    // Kept open, the engine went on answering definitions INTO it, at its
    // last text (measured 2026-09-30: UCalc.pas:8 with no UCalc.pas on the
    // disk); closed, the engine has nothing there, and the file coming back
    // is opened anew. For the asked one, the read below says what is wrong.
    if (Stamp = STAMP_GONE) and not Strict then
    begin
      Close(Key, D);
      Continue;
    end;
    // a file there but not to be asked right now: for another document,
    // looked at again on the next request
    if (Stamp = D.Stamp) or ((Stamp = STAMP_UNKNOWN) and not Strict) then
      Continue;
    // uno que ya no se puede leer (las raices cambiaron, o en su camino hay
    // ahora un enlace a fuera: cambia lo de detras y con ello el sello), se
    // cierra: se releia sin volver a preguntar (la puerta rancia de M1)
    var Negativa := LugarDeLecturaDenegado(D.Path, LUGARES_DEL_MOTOR);
    if Negativa <> '' then
    begin
      Close(Key, D);
      if Strict then
        raise Exception.Create(Negativa); // el que se pide: se dice por que
      Continue;
    end;
    try
      Inc(D.Version);
      D.Stamp := Stamp;
      DidChangeText(PathToUri(D.Path), LoadSourceText(D.Path), D.Version);
      FDocs[Key] := D;
      FLintText.Remove(Key);
      Result := True;
    except
      // unreadable half way (a writer in the middle): left as it was
      if Strict then
        raise;
    end;
  end;
end;

function TSessionClient.AjustesAlDia(const ASettings: string): Boolean;
var
  Sello: string;
begin
  Result := False;
  if ASettings = '' then
    Exit;
  // el sello ANTES de darlos: una escritura entre los dos se ve la proxima vez
  Sello := DiskStamp(ASettings);
  if (Sello = FSettingsStamp) or not HasStamp(Sello) then
    Exit;
  SetSettingsFile(ASettings);
  FSettingsStamp := Sello;
  FLintText.Clear;
  Result := True;
end;

{ The engine forgets the document, and so do the tables. Called with
  FDocLock held. Never raises: an engine that cannot be told is one that is
  going, and its tables go with it. }
procedure TSessionClient.Close(const AKey: string; const AD: TDocState);
begin
  FDocs.Remove(AKey);
  FLintText.Remove(AKey);
  try
    DidClose(PathToUri(AD.Path));
  except
  end;
end;

{ The document was asked about now: not idle. Called with FDocLock held. }
procedure TSessionClient.Touch(const AKey: string);
var
  D: TDocState;
begin
  if FDocs.TryGetValue(AKey, D) then
  begin
    D.LastUsed := TThread.GetTickCount64;
    FDocs[AKey] := D;
  end;
end;

class function TLspSession.Instance: TLspSession;
var
  Fresh: TLspSession;
begin
  // Two FIRST requests arriving together (Indy serves each on its own
  // thread) used to both see nil and build two sessions - two sets of LSP
  // clients, one leaked (hermes, release audit 2026-08-26). Lock-free
  // publish: build a candidate, install it only if nobody won the race.
  if FInstance = nil then
  begin
    Fresh := TLspSession.Create;
    if TInterlocked.CompareExchange<TLspSession>(FInstance, Fresh, nil) <> nil then
      Fresh.Free; // lost the race: the winner's instance is already public
  end;
  Result := FInstance;
end;

class procedure TLspSession.Shutdown;
begin
  FreeAndNil(FInstance);
end;

{ "Is this folder that one, or inside it?", in the two halves the guard
  gives (its own reader, DentroDeSiMismo, is the two in a row). Resolved ASKS
  THE DISK for the real path and is called with no lock held; IsUnder
  compares two resolved paths and is what runs under the lock. On a network
  drive - the roots of a server may be on one - resolving takes what the
  network takes, and it was done with the lock of the tables held.

  AIsTheLink: the folder by where IT is, not by where it points. For the one
  that is about to be moved or deleted: what goes when it is a junction is
  the link, not what is behind it - resolved through the link, deleting a
  junction retired the engines of a project that was not moving (measured
  2026-09-29). '' when it cannot be told: it is under nothing, and nothing is
  under it. }
function Resolved(const APath: string; AIsTheLink: Boolean = False): string;
begin
  try
    Result := RutaParaComparar(APath, AIsTheLink);
  except
    Result := '';
  end;
end;

function IsUnder(const AFolderReal, ADirReal: string): Boolean;
begin
  Result := (AFolderReal <> '') and (ADirReal <> '') and
    CaeDentro(AFolderReal, ADirReal);
end;

function TSessionClient.TieneDocumentoBajo(const AFolderReal: string): Boolean;
var
  D: TDocState;
begin
  Result := False;
  if AFolderReal = '' then
    Exit;
  FDocLock.Enter;
  try
    for D in FDocs.Values do
      if IsUnder(AFolderReal, Resolved(TPath.GetDirectoryName(D.Path))) then
        Exit(True);
  finally
    FDocLock.Leave;
  end;
end;

const
  BUILD_WAIT_MS = 6000;     // an engine being built under the folder (it takes 2-3 s)
  // A folder still "leaving" after this was forgotten there. The net for a
  // notice that never got its pair, and nothing else: above the longest
  // thing done between the two (a git pull has ten minutes). At two minutes
  // a pull with a slow network lost its mark half way.
  LEAVING_MAX_MS = 900000;
  RETIRED_KEEP_MS = 300000; // no request lasts this long: the retired client is freed

{ Is that held folder (resolved) under a folder that is leaving? Called with
  FTables held. }
function TLspSession.Leaving(const AHeldReal: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := FLeaving.Count - 1 downto 0 do
    if TThread.GetTickCount64 - FLeaving[I].Since > LEAVING_MAX_MS then
      FLeaving.Delete(I)
    else if IsUnder(FLeaving[I].Real, AHeldReal) then
      Result := True;
end;

{ The retired clients nobody can still be on (all of them, from Destroy), out
  of the list: whoever asks frees them, OUTSIDE the lock. Called with FTables
  held (or with nobody else left). }
function TLspSession.TakeRetired(AAll: Boolean): TArray<TLspClient>;
var
  I: Integer;
begin
  Result := nil;
  for I := FRetired.Count - 1 downto 0 do
    if AAll or (TThread.GetTickCount64 - FRetired[I].At > RETIRED_KEEP_MS) then
    begin
      Result := Result + [FRetired[I].Client];
      FRetired.Delete(I);
    end;
end;

{ A client OUT of the table, without freeing it - somebody may be using it -
  and STOPPED for everybody from this moment, under this lock: the word came
  after the lock was left, and in between a client that was in no table any
  more still looked alive. nil if there was none under that key. Whoever
  asks ends its process afterwards, outside (StopAll). Called with FTables
  held. }
function TLspSession.TakeOut(const AKey: string): TLspClient;
var
  R: TRetiredClient;
begin
  Result := FClients.ExtractPair(AKey).Value;
  FHeldFolders.Remove(AKey);
  if Result = nil then
    Exit;
  Result.Retire;
  R.Client := Result;
  R.At := TThread.GetTickCount64;
  FRetired.Add(R);
end;

procedure TLspSession.DoFolderLeaves(const AFolder: string);
var
  Keys: TArray<string>;
  Gone, Old: TArray<TLspClient>;
  K, D: string;
  I: Integer;
  T0: UInt64;
  L: TLeavingFolder;
  C: TLspClient;
  Building: Boolean;

  function YaEsta(const AKey: string): Boolean;
  begin
    for var X in Keys do
      if SameText(X, AKey) then
        Exit(True);
    Result := False;
  end;

begin
  Keys := nil;
  Gone := nil;
  L.Folder := AFolder;
  L.Real := Resolved(AFolder, True); // before the lock: it asks the disk
  FTables.Enter;
  try
    L.Since := TThread.GetTickCount64;
    FLeaving.Add(L);
    Old := TakeRetired(False);
    for K in FHeldFolders.Keys.ToArray do
      if IsUnder(L.Real, FHeldFolders[K]) then
        Keys := Keys + [K];
    // ...y los que tienen un DOCUMENTO abierto bajo ella aunque su carpeta
    // retenida no lo este: una unidad gobernada por un .dproj de arriba
    // (medido el 19-oct-2026 en el NAS: el handle del motor dejaba la carpeta
    // "borrandose" hasta que se paraba solo). FTables y luego FDocLock, el
    // orden de siempre.
    for K in FClients.Keys.ToArray do
      if (not YaEsta(K)) and (FClients[K] as TSessionClient).TieneDocumentoBajo(L.Real) then
        Keys := Keys + [K];
    for K in Keys do
    begin
      C := TakeOut(K);
      if C <> nil then
        Gone := Gone + [C];
    end;
    // The settings cache is left alone: an entry invalidates itself by the
    // stamp of the file that decided it, which is gone with the folder.
  finally
    FTables.Leave;
  end;
  FreeClients(Old);
  // Stopping waits for the process: OUTSIDE the lock, so nobody else's LSP
  // call stalls behind a folder being moved, and ALL AT ONCE (StopAll).
  StopAll(Gone);
  // (what was known of their documents goes with them: see TSessionClient)
  // ...and the engines being BUILT under the folder: they are in no table
  // yet. Each one finds the folder leaving when it finishes, is stopped and
  // only then leaves FBuilding. Bounded, like everything here.
  T0 := TThread.GetTickCount64;
  repeat
    Building := False;
    FTables.Enter;
    try
      for D in FBuilding do
        if IsUnder(L.Real, D) then
          Building := True;
    finally
      FTables.Leave;
    end;
    if not Building then
      Break;
    Sleep(50);
  until TThread.GetTickCount64 - T0 >= BUILD_WAIT_MS;
  // The mark counts from NOW: it was stamped before the engines were
  // stopped, and its time has to cover the operation itself, not the
  // stopping.
  FTables.Enter;
  try
    for I := 0 to FLeaving.Count - 1 do
      if SameText(FLeaving[I].Folder, AFolder) then
      begin
        L := FLeaving[I];
        L.Since := TThread.GetTickCount64;
        FLeaving[I] := L;
      end;
  finally
    FTables.Leave;
  end;
end;

procedure TLspSession.DoFolderLeft(const AFolder: string);
var
  I: Integer;
begin
  FTables.Enter;
  try
    for I := FLeaving.Count - 1 downto 0 do
      if SameText(FLeaving[I].Folder, AFolder) then
      begin
        FLeaving.Delete(I);
        Break;
      end;
  finally
    FTables.Leave;
  end;
end;

class procedure TLspSession.FolderLeaves(const AFolder: string; ABegins: Boolean);
var
  Session: TLspSession;
begin
  // The notice that a folder LEAVES creates the session if there is none:
  // with no engine started there is nothing to release, but the mark has to
  // be somewhere - the first LSP request of the server's life, arriving
  // while git rewrote the tree, found no mark and started an engine there.
  // The other notice never creates it.
  if ABegins then
    Session := Instance
  else
    Session := FInstance;
  if Session = nil then
    Exit;
  try
    if ABegins then
      Session.DoFolderLeaves(AFolder)
    else
      Session.DoFolderLeft(AFolder);
  except
  end;
end;

{ The session's entry in the guard's list of folder releasers: whoever takes
  a folder away gives the two notices (MueveArbol: delphi_delete's trash and
  delphi_move; BorraArbol: the purge; the empty-folder branch of
  delphi_delete; and git, before it rewrites or removes a working tree). }
procedure SueltaLspBajo(const ACarpeta: string; AEmpieza: Boolean);
begin
  TLspSession.FolderLeaves(ACarpeta, AEmpieza);
end;

{ HASTA DONDE SE SUBE buscando la configuracion de un fuente.

  Las dos busquedas de abajo trepan NIVELES_DE_SUBIDA carpetas desde el
  fichero (Ancestros, Lsp.Rutas: eran ocho, y doce para delete y move), y hasta
  el 2026-09-21 lo hacian sin mirar la jaula: un .dproj cualquiera colocado
  POR ENCIMA de la raiz del workspace se adoptaba como el proyecto de esa
  unit. Medido: un fichero de 10 bytes llamado "fuera-de-la-jaula.dproj" que
  se habia quedado en %TEMP% hacia que el RootDir de una unit en
  %TEMP%\x\jail\u fuese %TEMP% ENTERO. delphi_references se lleva ese
  RootDir al ambito del barrido y acabo abriendo 168 fuentes de otros
  workspaces: la llamada moria con una negativa de jaula que ADEMAS
  publicaba las rutas ajenas.

  Se sube mientras la carpeta siga siendo territorio legible de este
  workspace. Se usa ReadPathDenied y no PathDenied a proposito: la zona de
  biblioteca (RTL/VCL, componentes instalados) es de solo lectura y es un
  sitio legitimo donde encontrar configuracion. Y sin jaula configurada
  ReadPathDenied dice que si a todo, asi que el comportamiento de siempre
  se queda igual. }
function PuedoSubirA(const ADir: string): Boolean;
begin
  Result := (ADir <> '') and (ReadPathDenied(ADir) = '');
end;

{ La raiz con la que arranca el motor de un fichero: la carpeta del .dproj que
  lo sirve, la del fichero sin el. EL nombrador (ResolveSettings,
  RaizDelMotor). }
function RaizDe(const AFilePath, ADproj: string): string;
begin
  if ADproj <> '' then
    Result := TPath.GetDirectoryName(TPath.GetFullPath(ADproj))
  else
    Result := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
end;

const
  // LO QUE se sella para el proyecto de una unidad (TSettingsEntry): una
  // carpeta (su FolderStamp) o un .dproj (su DiskStamp y el de su fuente
  // principal). Lo compone BuscaDproj y lo lee SelloDeParte, su inversa
  PARTE_CARPETA = 'd:';
  PARTE_PROYECTO = 'p:';

function SelloDeParte(const AParte: string): string;
var
  Ruta: string;
begin
  if AParte.StartsWith(PARTE_CARPETA) then
    Exit(FolderStamp(AParte.Substring(Length(PARTE_CARPETA))));
  Ruta := AParte.Substring(Length(PARTE_PROYECTO));
  Result := DiskStamp(Ruta) + '|' + DiskStamp(DprDe(Ruta));
end;

{ La huella de lo sellado, sello a sello en su orden: la compone BuscaDproj
  con los sellos tomados ANTES de mirar cada cosa, y FindDproj la vuelve a
  pedir al disco para saber si lo guardado sigue valiendo. }
function HuellaDe(const APartes: TArray<string>): string;
begin
  Result := '';
  for var P in APartes do
    Result := Result + SelloDeParte(P) + #10;
end;

function TLspSession.BuscaDproj(const AFilePath: string; out ADecidido: Boolean;
  out APartes: TArray<string>; out AHuella: string): string;
var
  Dir, Carpeta, C: string;
  Matches, Subida: TArray<string>;
  Depth: Integer;
  Abajo: TList<string>;
  Juzgados: TDictionary<string, Boolean>;
  Sellos: TDictionary<string, string>;
  Orden: TList<string>;
  NoLeido: Boolean;

  // los sellos de lo que se mira ANTES de mirarlo, como AcquireFor con un
  // fuente: una carpeta (lo que aparezca dentro mueve el suyo) y un .dproj con
  // su fuente principal. Lo que cambie despues invalida lo guardado
  procedure Marca(const AParte: string);
  begin
    if not Sellos.ContainsKey(AParte) then
    begin
      Sellos.Add(AParte, SelloDeParte(AParte));
      Orden.Add(AParte);
    end;
  end;

  procedure Sella(const ADproj: string);
  begin
    // por la clave del disco (ClaveDeRuta), como todas las de esta busqueda:
    // .ToLower junta lo que NTFS separa (V105 de la 1.23.1)
    Marca(PARTE_PROYECTO + ClaveDeRuta(ADproj));
  end;

  // Los dos jueces de que un proyecto sirve a la unidad. LA LISTA: su .dpr/.dpk
  // la nombra por su ruta o es ella (Lsp.ProjectUnits). Era el NOMBRE en el
  // texto del .dproj: casaba con la copia de al lado (medido el 18-oct-2026).
  // Un candidato que la puerta no deja leer no es de este workspace y no se
  // adopta; uno que no se deja leer no sirve, y lo que se decida sin el no se
  // guarda (NoLeido).
  function Lista(const ADproj: string): Boolean;
  begin
    if Juzgados.TryGetValue(ClaveDeRuta(ADproj), Result) then
      Exit;
    Result := False;
    if LugarDeLecturaDenegado(ADproj, [ltJaula]) = '' then
    try
      Sella(ADproj);
      Result := ProyectoListaUnidad(ADproj, AFilePath, True);
    except
      NoLeido := True;
    end;
    Juzgados.Add(ClaveDeRuta(ADproj), Result);
  end;

  // ...y LA ALCANZA: su search path es la carpeta de la unidad (Lsp.Dproj).
  // Solo cuando nadie la lista: una demo de debajo con '..' en su search path
  // le ganaba al proyecto de arriba que la lista (revision del 18-oct-2026).
  function Alcanza(const ADproj: string): Boolean;
  begin
    Result := False;
    if LugarDeLecturaDenegado(ADproj, [ltJaula]) = '' then
    try
      Sella(ADproj);
      Result := BuscaEnCarpeta(ADproj, LeeTexto(ADproj, [ltJaula]), Carpeta);
    except
      NoLeido := True;
    end;
  end;

  // la respuesta, la de un juez (se guarda) o la de un respaldo (no), con la
  // huella de todo lo que se miro para darla
  function Elige(const ADproj: string; APorJuez: Boolean): string;
  begin
    Result := ADproj;
    Sella(ADproj);
    APartes := Orden.ToArray;
    AHuella := '';
    for var P in APartes do
      AHuella := AHuella + Sellos[P] + #10;
    // un sello que no se pudo preguntar (una carpeta que es un enlace, un
    // permiso) no vigila nada: esa respuesta no se guarda
    ADecidido := APorJuez and not NoLeido and not AHuella.Contains(STAMP_UNKNOWN);
  end;

begin
  Result := '';
  ADecidido := False;
  APartes := nil;
  AHuella := '';
  NoLeido := False;
  Carpeta := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  Subida := Ancestros(Carpeta, NIVELES_DE_SUBIDA);
  Abajo := TList<string>.Create;
  Juzgados := TDictionary<string, Boolean>.Create;
  Sellos := TDictionary<string, string>.Create;
  Orden := TList<string>.Create;
  try
    for Depth := 1 to Length(Subida) do
    begin
      Dir := Subida[Depth - 1];
      if not PuedoSubirA(Dir) then
        Break;
      // la carpeta, sellada antes de listarla: un .dproj que aparezca en ella
      // cambia la respuesta
      Marca(PARTE_CARPETA + ClaveDeRuta(Dir));
      Matches := TDirectory.GetFiles(Dir, '*.dproj');
      if Length(Matches) = 1 then
        Exit(Elige(Matches[0], True));
      if Length(Matches) > 1 then
      begin
        for C in Matches do
          if Lista(C) then
            Exit(Elige(C, True));
        for C in Matches do
          if Alcanza(C) then
            Exit(Elige(C, True));
        for C in Matches do
          if SameFileName(TPath.GetFileNameWithoutExtension(C), TPath.GetFileName(Dir)) then
            Exit(Elige(C, False));
        Exit(Elige(Matches[0], False));
      end;
      // No .dproj here: a unit in a SIBLING folder of the project
      // (SharedSource next to codigofuente, the usual shared-units layout)
      // belongs to the .dproj of the levels below that LISTS it; the ones
      // that only reach its folder wait until nobody lists it (below).
      if Depth <= 3 then
        // por EL recorredor (WalkFiles): solo sigue los enlaces que esta sesion
        // puede leer (GetFiles con soAllDirectories cruzaba cualquier union y
        // cada candidato tenia que negarse uno a uno; 2h de la 1.18.4)
        // ...y cada carpeta de debajo, al entrar (un proyecto que la liste
        // puede aparecer en cualquiera)
        for C in WalkFiles(Dir, ['*.dproj'], False, True,
          procedure(const ACarpeta: string)
          begin
            var K := PARTE_CARPETA + ClaveDeRuta(ACarpeta);
            if not Sellos.ContainsKey(K) then
            begin
              Sellos.Add(K, SelloDeParte(K));
              Orden.Add(K);
            end;
          end) do
          if not Juzgados.ContainsKey(ClaveDeRuta(C)) then
          begin
            if Lista(C) then
              Exit(Elige(C, True));
            Abajo.Add(C);
          end;
    end;
    // nadie la lista, ni hay un .dproj en su carpeta o encima: el primero de
    // debajo, del nivel mas cercano, que la alcanza por search path. No se
    // guarda: uno que la liste podria aparecer en cualquier carpeta de abajo
    for C in Abajo do
      if Alcanza(C) then
        Exit(Elige(C, False));
  finally
    Orden.Free;
    Sellos.Free;
    Juzgados.Free;
    Abajo.Free;
  end;
end;

function TLspSession.FindDproj(const AFilePath: string): string;
var
  Key, Huella: string;
  Partes: TArray<string>;
  E: TSettingsEntry;
  Found, Decidido: Boolean;
begin
  // La clave lleva la JAULA ademas del fichero: el veredicto de la escalada
  // (PuedoSubirA, via ReadPathDenied) depende de los roots del token que
  // llama, y con workspaces solapados el primero que resolvia una carpeta
  // fijaba SU proyecto para todos los demas - el token ancho le regalaba al
  // estrecho una raiz que su jaula le prohibe (auditoria 2026-09-21). The
  // stamps are asked of the disk with no lock held.
  Key := ClaveDeRuta(string.Join(';', WorkspaceRoots)) + '|' + ClaveDeRuta(TPath.GetFullPath(AFilePath));
  FTables.Enter;
  try
    Found := FSettingsCache.TryGetValue(Key, E);
  finally
    FTables.Leave;
  end;
  if Found and (HuellaDe(E.Partes) = E.Huella) then
    Exit(E.SourceFile);
  Result := BuscaDproj(AFilePath, Decidido, Partes, Huella);
  if Result = '' then
    Exit; // no project: never cached - a project file could appear at any moment
  Result := TPath.GetFullPath(Result);
  if not Decidido then
    Exit;
  E.SourceFile := Result;
  E.Partes := Partes;
  E.Huella := Huella; // each stamp taken before its part was looked at (BuscaDproj)
  FTables.Enter;
  try
    if FSettingsCache.Count > 1024 then
      FSettingsCache.Clear; // small map of files asked about; a clear is fine
    FSettingsCache.AddOrSetValue(Key, E);
  finally
    FTables.Leave;
  end;
end;

function TLspSession.RaizDelMotor(const AFilePath: string): string;
begin
  Result := RaizDe(AFilePath, FindDproj(AFilePath));
end;

function TLspSession.ResolveSettings(const AFilePath: string;
  out ARootDir: string): string;
var
  Dproj: string;
begin
  // Los ajustes son SIEMPRE los nuestros, de su .dproj: el .delphilsp.json
  // del IDE no se lee (David, 17-oct-2026: "ese json lo mantiene el IDE y
  // nosotros no usamos el IDE"). Se preferia mientras nombrase un proyecto
  // que existiera, y el IDE solo lo reescribe al abrir el proyecto: lo que
  // un agente cambiaba en el .dproj no lo veia el motor (medido, M4), y el
  // de una copia nombraba el original (Fable 1). The project of a file is
  // cached (FindDproj); the settings are made AGAIN every time
  // (FabricateSettings, written only when they change): they depend on more
  // than the .dproj.
  Dproj := FindDproj(AFilePath);
  ARootDir := RaizDe(AFilePath, Dproj);
  if Dproj = '' then
    Exit(''); // No .dproj anywhere: unconfigured
  Result := FabricateSettings(Dproj, DiscoverRadStudio);
end;

function TLspSession.CreateClient(const ARootDir, ASettingsFile: string;
  AServerType: TLspServerType): TLspClient;
var
  Transport: TLspProcessTransport;
  Resp: TObject;
begin
  Transport := TLspProcessTransport.Create(EnsureExe);
  Transport.Start;
  Result := TSessionClient.Create(Transport);
  try
    Resp := Result.Initialize(TLspClient.PathToUri(ARootDir), AServerType);
    Resp.Free;
    Result.SendInitialized;
    if ASettingsFile <> '' then
    begin
      // el sello ANTES de darlos (AjustesAlDia): lo que cambie despues se le
      // da otra vez en la proxima peticion
      (Result as TSessionClient).FSettingsStamp := DiskStamp(ASettingsFile);
      Result.SetSettingsFile(ASettingsFile);
      Sleep(1500); // let the server load project settings before first use
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ The key of the client that serves a file: agent or linter, the RAD Studio
  version and the settings file (or the root when there is none). }
function TLspSession.ClientKey(const AFullPath: string; ALinter: Boolean;
  out ASettingsUsed, ARootDir: string): string;
const
  Prefix: array [Boolean] of string = ('agent|', 'linter|');
begin
  ASettingsUsed := ResolveSettings(AFullPath, ARootDir);
  // La VERSION entra en la clave: cada RAD Studio necesita SU DelphiLSP.
  // Hoy hay una por servidor, pero la clave no tiene que saberlo.
  var Ver := DiscoverRadStudio.Version;
  if ASettingsUsed <> '' then
    Result := Prefix[ALinter] + Ver + '|' + ClaveDeRuta(ASettingsUsed)
  else
    Result := Prefix[ALinter] + Ver + '|(nosettings)' + ClaveDeRuta(ARootDir);
end;

function TLspSession.OpenDocuments(const AFilePath: string): Integer;
var
  Settings, RootDir: string;
  C: TLspClient;
begin
  Result := -1;
  var Key := ClientKey(TPath.GetFullPath(AFilePath), False, Settings, RootDir);
  FTables.Enter;
  try
    if not FClients.TryGetValue(Key, C) then
      Exit;
  finally
    FTables.Leave;
  end;
  var Mine := C as TSessionClient;
  Mine.FDocLock.Enter;
  try
    Result := Mine.FDocs.Count;
  finally
    Mine.FDocLock.Leave;
  end;
end;

function TLspSession.GetClient(const AFullPath: string; ALinter: Boolean;
  out ASettingsUsed, AClientKey, ARootDir: string): TLspClient;
begin
  AClientKey := ClientKey(AFullPath, ALinter, ASettingsUsed, ARootDir);

  // Fast path under the lock; the SLOW path (spawn DelphiLSP + initialize +
  // settings load, seconds) runs UNLOCKED, so warming one project no longer
  // stalls every other agent's LSP call server-wide (hermes, release audit
  // 2026-08-26, P1.6 - the lock used to be held across those sleeps). Two
  // racers may both build a client for the same key; the loser's is stopped
  // and freed before it leaves FBuilding (nobody else ever had it).
  var Dead: TLspClient := nil;
  var Old: TArray<TLspClient> := nil;
  FTables.Enter;
  try
    if FClients.TryGetValue(AClientKey, Result) then
    begin
      if Result.EngineAlive then
      begin
        (Result as TSessionClient).FLastUsed := TThread.GetTickCount64;
        Exit;
      end;
      // Its process is GONE - it ended by itself, or somebody ended it from
      // outside: out of the table, like the one of a folder that leaves,
      // and another one is built below. It stayed in the table, and every
      // request of its project answered the transport's error until the
      // server stopped or the folder left (fourth review of 1.7.7; measured:
      // after the engine was killed, four hovers out of four).
      // (and the retired ones nobody can be on any more are freed here too:
      // they were only when a folder left)
      Old := TakeRetired(False);
      Dead := TakeOut(AClientKey);
      Result := nil;
    end;
  finally
    FTables.Leave;
  end;
  // (what is left of it - its pipes, its reader - is closed outside the lock)
  if Dead <> nil then
  begin
    FreeClients(Old);
    StopAll([Dead]);
  end;
  // The folder THIS engine will hold: see FHeldFolders. Read outside the
  // lock (it opens the settings file) and only HERE, for an engine that has
  // to be built: it was read and parsed on every request, warm or not.
  var Held := ARootDir;
  if ASettingsUsed <> '' then
  begin
    var Proj := ProjectOfSettings(ASettingsUsed);
    if Proj <> '' then
      Held := ExtractFileDir(Proj);
  end;
  // (settings that name a folder that was never there deny nothing)
  var HeldWasThere := DirectoryExists(Held);
  // ...and resolved HERE, with no lock held: it asks the disk
  var HeldReal := Resolved(Held);
  FTables.Enter;
  try
    if FClients.TryGetValue(AClientKey, Result) then
    begin
      (Result as TSessionClient).FLastUsed := TThread.GetTickCount64;
      Exit; // built by somebody else in the meantime
    end;
    // a folder that is leaving starts no engine: it would hold it again
    if Leaving(HeldReal) then
      raise ELspSession.Create(MsgFmt(SR_LSP_FOLDER_LEAVING_FMT, [AFullPath]));
    FBuilding.Add(HeldReal);
  finally
    FTables.Leave;
  end;
  var Fresh: TLspClient := nil;
  var Refused := False;
  var Gone := False;
  var Victima: TLspClient := nil;
  var VictimaKey := '';
  try
    if ALinter then
      Fresh := CreateClient(ARootDir, ASettingsUsed, lstLinter)
    else
      Fresh := CreateClient(ARootDir, ASettingsUsed, lstAgent);
    // The file this request is about was there when it came in (AcquireFor
    // and LintFile look before they ask for the client). Gone NOW, its
    // folder left between that look and the mark, or while the engine was
    // being built and nobody waited for it any longer (BUILD_WAIT_MS): the
    // engine would be registered for a folder that is not there, and stay.
    // A GUARD: the window is read in the code and a probe did not reach it
    // (2026-09-29, sixteen tries with the wait taken out: what happens then
    // is FILE-036, and the folder stays). The file, and the folder the
    // engine holds: a unit may live outside it (shared sources next to the
    // project), and then what left is the folder, not the file.
    Gone := not FileExists(AFullPath);
    var HeldGone := HeldWasThere and not DirectoryExists(Held);
    FTables.Enter;
    try
      // ...and the one that started leaving while this engine was being
      // built does not get it either
      Refused := Leaving(HeldReal) or HeldGone;
      if (not Refused) and (not Gone) and
         not FClients.TryGetValue(AClientKey, Result) then
      begin
        FClients.Add(AClientKey, Fresh);
        FHeldFolders.AddOrSetValue(AClientKey, HeldReal);
        Result := Fresh;
        Fresh := nil; // registered: it is the table's now
        // [Server] MaxEngines: pasado el tope, sale el menos usado de los que
        // no estan trabajando (nunca el que acaba de llegar); se para FUERA
        // del cerrojo, como en Sweep. Sin candidato (todos trabajando), el
        // tope se pasa: parar uno en vuelo seria tirar una respuesta
        if (MaxEngines > 0) and (FClients.Count > MaxEngines) then
        begin
          var Menor: UInt64 := High(UInt64);
          for var K in FClients.Keys.ToArray do
          begin
            var C := FClients[K] as TSessionClient;
            if (K <> AClientKey) and not C.Busy and (C.FLastUsed < Menor) then
            begin
              Menor := C.FLastUsed;
              VictimaKey := K;
            end;
          end;
          if VictimaKey <> '' then
            Victima := TakeOut(VictimaKey);
        end;
      end;
      // else: refused, gone, or lost the race (the winner's client is public)
      if Result <> nil then
        (Result as TSessionClient).FLastUsed := TThread.GetTickCount64;
    finally
      FTables.Leave;
    end;
  finally
    // The engine that is not kept is stopped BEFORE it leaves FBuilding:
    // whoever is taking the folder away waits for exactly that.
    try
      Fresh.Free;
    finally
      FTables.Enter;
      try
        FBuilding.Remove(HeldReal);
      finally
        FTables.Leave;
      end;
    end;
  end;
  if Victima <> nil then
  begin
    StopAll([Victima]);
    TLogger.Info(MsgFmt(SL_LSP_ENGINE_LRU_FMT, [VictimaKey, MaxEngines, AClientKey]));
  end;
  // (gone first: a file that is not there is not "in a folder that leaves")
  if Gone then
    raise ELspSession.Create(MsgFmt(SR_LSP_NO_FILE_FMT, [AFullPath]));
  if Refused then
    raise ELspSession.Create(MsgFmt(SR_LSP_FOLDER_LEAVING_FMT, [AFullPath]));
end;

function TLspSession.AcquireFor(const AFilePath: string;
  out ASettingsUsed: string): TLspClient;
var
  FullPath, Key, RootDir: string;
begin
  FullPath := RutaParaAbrir(AFilePath, False);
  Result := GetClient(FullPath, False, ASettingsUsed, Key, RootDir);
  AbreDocumento(Result, FullPath, ASettingsUsed);
end;

{ LA puerta de abrir un fichero en un motor (AcquireFor y AbreEn): abrir es
  leer (navigating RTL/components is reading), y lo que no existe no se abre.
  Su ruta completa. Estaba copiada en los dos (revision de la 1.13.0).
  ADelMotor: un fichero al que llevo el MOTOR (AbreEn) se juzga con los
  lugares del motor (Lsp.Patch.LUGARES_DEL_MOTOR: la jaula, el IDE y su
  biblioteca), como lo que se le da a leer (LoadSourceText); el del agente
  (AcquireFor), con la jaula. Con la zona de biblioteca apagada, kind=
  declaration de una rutina de la RTL contestaba GUARD-002 mientras
  definition daba esa misma ubicacion (medido el 9-oct-2026, tambien con
  el binario de antes de P2). }
function TLspSession.RutaParaAbrir(const AFilePath: string; ADelMotor: Boolean): string;
var
  Denied: string;
begin
  Result := TPath.GetFullPath(AFilePath);
  if ADelMotor then
    Denied := LugarDeLecturaDenegado(Result, LUGARES_DEL_MOTOR)
  else
    Denied := ReadPathDenied(Result);
  if Denied <> '' then
    raise ELspSession.Create(Denied);
  if not FileExists(Result) then
    raise ELspSession.Create(MsgFmt(SR_LSP_NO_FILE_FMT, [AFilePath]));
end;

{ El documento abierto y al dia en ESE motor (AcquireFor y AbreEn), con la
  ventaja de indexado si acaba de abrirse o de refrescarse. ASettings: los
  ajustes de ESA peticion, que el motor recibe otra vez si cambiaron
  (AjustesAlDia); '' cuando el motor ya los recibio en la misma peticion
  (AbreEn, tras el AcquireFor que lo dio). }
procedure TLspSession.AbreDocumento(AClient: TLspClient; const AFullPath, ASettings: string);
var
  DocKey: string;
  Nuevo: Boolean;
begin
  var Mine := AClient as TSessionClient;
  DocKey := ClaveDeRuta(AFullPath);
  // The lock of THIS client's documents: the engine is written to with it
  // held, and one that stops reading keeps whoever comes for ITS project.
  Mine.FDocLock.Enter;
  try
    // retired between GetClient and here (its folder is leaving): nothing of
    // its is written down, and the caller is told at once
    if AClient.Stopped then
      raise ELspSession.Create(MsgText(SR_LSP_ENGINE_STOPPED));
    // los ajustes de ahora antes que nada: lo que se le pregunte se contesta
    // con ellos (y la ventaja de indexado tambien les toca)
    Nuevo := Mine.AjustesAlDia(ASettings);
    // Every document this engine has open is brought up to date with the
    // disk FIRST - the one asked about and the others alike (delphi_edit,
    // scaffolding, git, an external editor...): an answer must reflect the
    // CURRENT source of every unit it crosses, never a stale snapshot. The
    // engine reads the disk itself only for units it does NOT have open.
    Nuevo := Mine.Refresh('', DocKey) or Nuevo;
    if not Mine.FDocs.ContainsKey(DocKey) then
    begin
      // the stamp BEFORE the text: a write between the two is seen next time
      var Stamp := DiskStamp(AFullPath);
      AClient.DidOpenFile(AFullPath);
      Mine.FDocs.Add(DocKey, DocState(AFullPath, 1, Stamp));
      Nuevo := True;
    end
    else
      Mine.Touch(DocKey);
  finally
    Mine.FDocLock.Leave;
  end;
  // The indexing head start sleeps OUTSIDE the lock: it buys answer quality
  // for THIS caller's first question and must not stall everyone else
  // (retries on -32800 cover whatever 500ms does not).
  if Nuevo then
    Sleep(500);
end;

procedure TLspSession.AbreEn(AClient: TLspClient; const AFilePath: string);
begin
  AbreDocumento(AClient, RutaParaAbrir(AFilePath, True), '');
end;

function TLspSession.LintFile(const AFilePath: string; ATimeoutMs: Integer;
  out ASettingsUsed: string): TJSONObject;
var
  FullPath, Key, DocKey, RootDir, Uri, Text: string;
  Client: TLspClient;
  Stale: TJSONObject;
  Prev: string;
  SameText_: Boolean;
begin
  FullPath := TPath.GetFullPath(AFilePath);
  var Denied := ReadPathDenied(FullPath); // linting never writes the file
  if Denied <> '' then
    raise ELspSession.Create(Denied);
  if not FileExists(FullPath) then
    raise ELspSession.Create(MsgFmt(SR_LSP_NO_FILE_FMT, [AFilePath]));
  // un .inc no es una unidad: el motor lo compila dentro de la que lo
  // incluye, y de el solo no publica nunca (medido el 24-oct-2026: tres
  // lineas junto a su .dproj, "in-progress" seis minutos)
  if SameText(TPath.GetExtension(FullPath), '.inc') then
    raise ELspSession.Create(MsgFmt(SR_LSP_LINT_INCLUDE_FMT, [AFilePath]));
  // Sin ajustes de proyecto el motor no publica NUNCA (medido 2026-10-06,
  // ver SR_LSP_LINT_SIN_AJUSTES_FMT): se dice aqui, antes de arrancar un
  // motor para nada, y no tras 40 s de "in-progress" en bucle. La misma
  // resolucion que hace GetClient (FindDproj, sin hacer los ajustes: los
  // hace GetClient, una vez por peticion).
  if FindDproj(FullPath) = '' then
    raise ELspSession.Create(MsgFmt(SR_LSP_LINT_SIN_AJUSTES_FMT, [AFilePath]));
  // Bajo una ruta con un caracter mas alla de U+FFFF el motor publica una
  // lista VACIA (medido el 14-oct con el motor solo): un "0 errors" falso. Se
  // dice tambien antes de arrancarlo (M3 de los revisores de cierre).
  if TLspClient.MotorPierdeLaRuta(FullPath) then
    raise ELspSession.Create(MsgFmt(SR_LSP_LINT_MOTOR_PIERDE_FMT, [AFilePath]));

  Client := GetClient(FullPath, True, ASettingsUsed, Key, RootDir);
  Uri := TLspClient.PathToUri(FullPath);
  // the stamp BEFORE the text: a write between the two is seen next time
  var Stamp := DiskStamp(FullPath);
  Text := TLspClient.LoadSourceText(FullPath);
  var Mine := Client as TSessionClient;
  DocKey := ClaveDeRuta(FullPath);
  Mine.FDocLock.Enter;
  try
    // retired between GetClient and here: see AcquireFor
    if Client.Stopped then
      raise ELspSession.Create(MsgText(SR_LSP_ENGINE_STOPPED));

    // A retry on the SAME text (the client timed out before a slow lint
    // finished) must not restart the lint: the LSP is still working, or the
    // diagnostics are already queued - just wait for them below.
    // Los ajustes de ahora (AjustesAlDia): si cambiaron, se le dan otra vez -
    // el motor vivo seguia con los de su arranque (M5) - y se olvida lo que
    // estaba lintando: un lint en curso era de los ajustes de antes, y el
    // reintento con el mismo texto lo esperaba en vez de lintar de nuevo.
    Mine.AjustesAlDia(ASettingsUsed);
    // The other units this engine has open first: a lint reads across them
    // (see AcquireFor). This one goes below, by its text, not by its stamp.
    Mine.Refresh(DocKey, '');
    SameText_ := Mine.FLintText.TryGetValue(DocKey, Prev) and (Prev = Text);
    if not SameText_ then
    begin
      // Drop any queued diagnostics for this uri from earlier lints.
      repeat
        Stale := Client.WaitForNotification('textDocument/publishDiagnostics', 1, Uri);
        Stale.Free;
      until Stale = nil;

      var D: TDocState;
      if Mine.FDocs.TryGetValue(DocKey, D) then
      begin
        Inc(D.Version);
        D.Stamp := Stamp;
        Client.DidChangeText(Uri, Text, D.Version);
        Mine.FDocs[DocKey] := D; // after the send, as Refresh: a send that fails writes nothing down
      end
      else
      begin
        Client.DidOpenText(Uri, Text);
        Mine.FDocs.Add(DocKey, DocState(FullPath, 1, Stamp));
      end;
      Mine.FLintText.AddOrSetValue(DocKey, Text);
    end;
    Mine.Touch(DocKey);
  finally
    Mine.FDocLock.Leave;
  end;
  // Wait outside the lock: lints can take a while on big units.
  Result := Client.WaitForNotification('textDocument/publishDiagnostics',
    ATimeoutMs, Uri);
  // Delivered: the next call on the same text is a NEW lint, not a retry
  // (measured: without this, an identical second call waited forever for a
  // notification already consumed).
  if Result <> nil then
  begin
    Mine.FDocLock.Enter;
    try
      Mine.FLintText.Remove(DocKey);
    finally
      Mine.FDocLock.Leave;
    end;
  end;
end;

initialization
  RegistraSoltadorDeCarpeta(SueltaLspBajo);

finalization
  TLspSession.Shutdown;

end.
