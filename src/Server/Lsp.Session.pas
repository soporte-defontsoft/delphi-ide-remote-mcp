unit Lsp.Session;

{ Workspace/session manager: owns the DelphiLSP client processes behind the
  MCP tools. One agent-mode client per project settings file, created lazily
  on the first request that touches a file of that project, then kept warm.

  Project settings resolution: walk up from the requested file's directory
  looking for a *.delphilsp.json (the IDE-generated project settings). The
  first directory that has one wins; a single match is used directly, and
  with several the one whose name matches a .dpr in the directory wins,
  falling back to the first. Files with no settings anywhere still get
  documentSymbol (measured: it works unconfigured), but hover/definition
  will answer null - the tools say so in their output. }

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

type
  ELspSession = class(Exception);

  { What ResolveSettings answered for a directory, plus the file that
    justified the answer and its disk stamp: while that file is unchanged the
    walk (directory scans + settings fabrication) is skipped entirely
    (hermes, release audit 2026-08-26, P1.6). And the settings file of the
    IDE that was found and REJECTED on the way, with its stamp: the answer
    stands while that one does not change either. Rejected once - stale, or
    read half written -, it was not looked at again until the .dproj changed,
    fresh as the IDE might have left it since. }
  TSettingsEntry = record
    Settings, RootDir, SourceFile, SourceStamp: string;
    RejectedFile, RejectedStamp: string;
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
    // at the next folder that leaves: they used to pile up until the server
    // stopped. Under FTables, like the four tables around it.
    FRetired: TList<TRetiredClient>;
    // The folders being taken away right now, between the guard's two
    // notices: no engine is started or registered under one of them.
    FLeaving: TList<TLeavingFolder>;
    // The held folders of the engines being BUILT (the slow path of
    // GetClient runs unlocked, for seconds): whoever takes a folder away
    // waits for the ones under it, which are refused when they finish.
    FBuilding: TList<string>;
    FSettingsCache: TDictionary<string, TSettingsEntry>;
    function EnsureExe: string;
    function ResolveSettingsWalk(const AFilePath: string;
      out ARootDir, ASource, ASourceStamp, ARejected, ARejectedStamp: string): string;
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

    { Finds the project settings for a source file ('' if none). }
    function FindSettingsFile(const AFilePath: string): string;

    { Finds the .dproj that governs a source file ('' if none): walks up the
      directory tree; when a directory has several, prefers one whose text
      references the file's base name, then one matching the directory name,
      then the first. }
    function FindDproj(const AFilePath: string): string;

    { Full resolution: fresh IDE settings win; stale/missing settings are
      replaced by a fabricated one when a .dproj is available; '' otherwise.
      ARootDir is the workspace root to initialize the LSP with - always a
      PROJECT directory, never the settings cache. }
    function ResolveSettings(const AFilePath: string; out ARootDir: string): string;

    { Returns the warm agent client for the file's project (creating it if
      needed) plus the settings file it runs with (''= unconfigured). Also
      ensures the document is open on that client. Thread-safe. }
    function AcquireFor(const AFilePath: string; out ASettingsUsed: string): TLspClient;

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
  end;

implementation

uses
  Lsp.Texts,
  Lsp.ShaCache; // DiskStamp: one composer of the disk fingerprint

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
    function Refresh(const AExceptKey, AStrictKey: string): Boolean;
    procedure Close(const AKey: string; const AD: TDocState);
    procedure Touch(const AKey: string);
  public
    constructor Create(ATransport: TLspProcessTransport);
    destructor Destroy; override;
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

{ Frees clients that are in no table any more. Never raises. }
procedure FreeClients(const AClients: TArray<TLspClient>);
var
  C: TLspClient;
begin
  for C in AClients do
    try
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
  its bounds add up to 16 s for an engine that neither ends nor lets go of
  its pipes (see TLspProcessTransport.Stop); one engine after another, those
  16 s were multiplied by the engines of a whole repository, with the global
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

function TLspSession.EnsureExe: string;
var
  Info: TRadStudioInfo;
begin
  // Sin cache: la instalacion la elige DiscoverRadStudio por WORKSPACE
  // (DelphiVersion=), asi que dos workspaces pueden pedir motores
  // distintos en el mismo proceso. Se llama solo al arrancar un motor.
  Info := DiscoverRadStudio;
  if not Info.Found or (Info.DelphiLspExe = '') then
    raise ELspSession.Create(
      MsgText(SE_LSP_RAD_STUDIO_INSTALLATION_DELPHILSP));
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
end;

destructor TLspSession.Destroy;
begin
  // all at once first, like the ones of a folder that leaves: freed one
  // after another, the bounds of each stop added up while the server stopped
  StopAll(FClients.Values.ToArray);
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

  Las dos busquedas de abajo trepan ocho niveles desde el fichero, y hasta
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

function TLspSession.FindSettingsFile(const AFilePath: string): string;
var
  Dir, Candidate: string;
  Matches: TArray<string>;
  Depth: Integer;
begin
  Result := '';
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  for Depth := 1 to 8 do
  begin
    if not PuedoSubirA(Dir) then
      Exit;
    Matches := TDirectory.GetFiles(Dir, '*.delphilsp.json');
    if Length(Matches) > 0 then
    begin
      if Length(Matches) = 1 then
        Exit(Matches[0]);
      // Several: prefer the one that pairs with a .dpr of the same name.
      for Candidate in Matches do
        if FileExists(Candidate.Replace('.delphilsp.json', '.dpr',
          [rfIgnoreCase])) then
          Exit(Candidate);
      Exit(Matches[0]);
    end;
    var Parent := TPath.GetDirectoryName(Dir);
    if SameText(Parent, Dir) then
      Exit;
    Dir := Parent;
  end;
end;

function TLspSession.FindDproj(const AFilePath: string): string;
var
  Dir, BaseName, C: string;
  Matches: TArray<string>;
  Depth: Integer;
begin
  Result := '';
  BaseName := TPath.GetFileNameWithoutExtension(AFilePath);
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  for Depth := 1 to 8 do
  begin
    if not PuedoSubirA(Dir) then
      Exit;
    Matches := TDirectory.GetFiles(Dir, '*.dproj');
    if Length(Matches) > 0 then
    begin
      if Length(Matches) = 1 then
        Exit(Matches[0]);
      for C in Matches do
        if TFile.ReadAllText(C).ToLower.Contains(BaseName.ToLower) then
          Exit(C);
      for C in Matches do
        if SameText(TPath.GetFileNameWithoutExtension(C),
          TPath.GetFileName(Dir)) then
          Exit(C);
      Exit(Matches[0]);
    end;
    // No .dproj here: a unit in a SIBLING folder of the project (SharedSource
    // next to codigofuente, the usual shared-units layout) belongs to the
    // .dproj one level down that REFERENCES it (DCCReference or search path).
    if Depth <= 3 then
      for C in TDirectory.GetFiles(Dir, '*.dproj', TSearchOption.soAllDirectories) do
        if TFile.ReadAllText(C).ToLower.Contains(BaseName.ToLower) then
          Exit(C);
    var Parent := TPath.GetDirectoryName(Dir);
    if SameText(Parent, Dir) then
      Exit;
    Dir := Parent;
  end;
end;

function TLspSession.ResolveSettingsWalk(const AFilePath: string;
  out ARootDir, ASource, ASourceStamp, ARejected, ARejectedStamp: string): string;
var
  Info: TRadStudioInfo;
  Dproj, Stamp: string;
begin
  ASource := '';
  ASourceStamp := '';
  ARejected := '';
  ARejectedStamp := '';
  Info := DiscoverRadStudio;
  Result := FindSettingsFile(AFilePath);
  // The stamp of a file is taken BEFORE the file is read, as AcquireFor does
  // with a source. Taken after, a file read half written and completed in
  // between got the stamp of the whole file, which nobody had looked at,
  // and the cache stood on it (fourth review of 1.7.7, read in the code).
  Stamp := '';
  if Result <> '' then
    Stamp := DiskStamp(Result);
  if (Result <> '') and not IsSettingsStale(Result, Info) then
  begin
    ARootDir := TPath.GetDirectoryName(Result);
    ASource := Result;
    ASourceStamp := Stamp;
    Exit; // fresh IDE-generated settings: best possible source
  end;
  ARejected := Result; // found, and not taken ('' if there was none)
  ARejectedStamp := Stamp;
  Dproj := FindDproj(AFilePath);
  if Dproj <> '' then
  begin
    ARootDir := TPath.GetDirectoryName(TPath.GetFullPath(Dproj));
    ASource := TPath.GetFullPath(Dproj);
    ASourceStamp := DiskStamp(ASource);
    Exit(FabricateSettings(Dproj, Info));
  end;
  // No .dproj anywhere: a stale settings file is worse than none (its paths
  // point at machines/drives gone by), so fall back to unconfigured.
  ARootDir := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  Result := '';
end;

function TLspSession.ResolveSettings(const AFilePath: string;
  out ARootDir: string): string;
var
  Dir, Src, SrcStamp, Rejected, RejectedStamp: string;
  E: TSettingsEntry;
  Found: Boolean;
begin
  // Cached per directory, invalidated by the stamp of the file that decided
  // the answer (.delphilsp.json or .dproj): editing search paths touches the
  // .dproj, which changes the stamp, which re-fabricates. And by the stamp
  // of the IDE's settings file that was rejected on the way, if there was
  // one (see TSettingsEntry). The no-source case is never cached - a project
  // file could appear at any moment. The stamps are asked of the disk with
  // no lock held.
  // La clave lleva la JAULA ademas del directorio: el veredicto de la
  // escalada (PuedoSubirA, via ReadPathDenied) depende de los roots del
  // token que llama, y con workspaces solapados el primero que resolvia
  // una carpeta fijaba SU RootDir para todos los demas - el token ancho
  // le regalaba al estrecho una raiz que su jaula le prohibe
  // (auditoria 2026-09-21).
  // ...y la VERSION de RAD Studio, porque los settings fabricados salen de
  // los paths de ESA instalacion (DelphiVersion= por workspace).
  Dir := DiscoverRadStudio.Version + '|' +
    string.Join(';', WorkspaceRoots).ToLower + '|' +
    TPath.GetDirectoryName(TPath.GetFullPath(AFilePath)).ToLower;
  FTables.Enter;
  try
    Found := FSettingsCache.TryGetValue(Dir, E);
  finally
    FTables.Leave;
  end;
  if Found and (E.SourceFile <> '') and
     (DiskStamp(E.SourceFile) = E.SourceStamp) and
     ((E.RejectedFile = '') or (DiskStamp(E.RejectedFile) = E.RejectedStamp)) then
  begin
    ARootDir := E.RootDir;
    Exit(E.Settings);
  end;
  Result := ResolveSettingsWalk(AFilePath, ARootDir, Src, SrcStamp, Rejected,
    RejectedStamp);
  if Src <> '' then
  begin
    E.Settings := Result;
    E.RootDir := ARootDir;
    E.SourceFile := Src;
    E.SourceStamp := SrcStamp; // taken before the file was read (the walk)
    E.RejectedFile := Rejected;
    E.RejectedStamp := RejectedStamp;
    FTables.Enter;
    try
      if FSettingsCache.Count > 256 then
        FSettingsCache.Clear; // tiny map of project dirs; a clear is fine
      FSettingsCache.AddOrSetValue(Dir, E);
    finally
      FTables.Leave;
    end;
  end;
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
  // La VERSION entra en la clave: un workspace fijado a otra RAD Studio
  // (DelphiVersion=) necesita SU DelphiLSP, no el que ya corre para otro.
  var Ver := DiscoverRadStudio.Version;
  if ASettingsUsed <> '' then
    Result := Prefix[ALinter] + Ver + '|' + ASettingsUsed.ToLower
  else
    Result := Prefix[ALinter] + Ver + '|(nosettings)' + ARootDir.ToLower;
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
        Exit;
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
      Exit; // built by somebody else in the meantime
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
      end;
      // else: refused, gone, or lost the race (the winner's client is public)
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
  // (gone first: a file that is not there is not "in a folder that leaves")
  if Gone then
    raise ELspSession.Create(MsgFmt(SR_LSP_NO_FILE_FMT, [AFullPath]));
  if Refused then
    raise ELspSession.Create(MsgFmt(SR_LSP_FOLDER_LEAVING_FMT, [AFullPath]));
end;

function TLspSession.AcquireFor(const AFilePath: string;
  out ASettingsUsed: string): TLspClient;
var
  FullPath, Key, DocKey, RootDir: string;
begin
  FullPath := TPath.GetFullPath(AFilePath);
  var Denied := ReadPathDenied(FullPath); // navigating RTL/components is reading
  if Denied <> '' then
    raise ELspSession.Create(Denied);
  if not FileExists(FullPath) then
    raise ELspSession.Create(MsgFmt(SR_LSP_NO_FILE_FMT, [AFilePath]));

  Result := GetClient(FullPath, False, ASettingsUsed, Key, RootDir);
  var Mine := Result as TSessionClient;
  DocKey := FullPath.ToLower;
  var HeadStart := False;
  // The lock of THIS client's documents: the engine is written to with it
  // held, and one that stops reading keeps whoever comes for ITS project.
  Mine.FDocLock.Enter;
  try
    // retired between GetClient and here (its folder is leaving): nothing of
    // its is written down, and the caller is told at once
    if Result.Stopped then
      raise ELspSession.Create(MsgText(SR_LSP_ENGINE_STOPPED));
    // Every document this engine has open is brought up to date with the
    // disk FIRST - the one asked about and the others alike (delphi_edit,
    // scaffolding, git, an external editor...): an answer must reflect the
    // CURRENT source of every unit it crosses, never a stale snapshot. The
    // engine reads the disk itself only for units it does NOT have open.
    HeadStart := Mine.Refresh('', DocKey);
    if not Mine.FDocs.ContainsKey(DocKey) then
    begin
      // the stamp BEFORE the text: a write between the two is seen next time
      var Stamp := DiskStamp(FullPath);
      Result.DidOpenFile(FullPath);
      Mine.FDocs.Add(DocKey, DocState(FullPath, 1, Stamp));
      HeadStart := True;
    end
    else
      Mine.Touch(DocKey);
  finally
    Mine.FDocLock.Leave;
  end;
  // The indexing head start sleeps OUTSIDE the lock: it buys answer quality
  // for THIS caller's first question and must not stall everyone else
  // (retries on -32800 cover whatever 500ms does not).
  if HeadStart then
    Sleep(500);
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

  Client := GetClient(FullPath, True, ASettingsUsed, Key, RootDir);
  Uri := TLspClient.PathToUri(FullPath);
  // the stamp BEFORE the text: a write between the two is seen next time
  var Stamp := DiskStamp(FullPath);
  Text := TLspClient.LoadSourceText(FullPath);
  var Mine := Client as TSessionClient;
  DocKey := FullPath.ToLower;
  Mine.FDocLock.Enter;
  try
    // retired between GetClient and here: see AcquireFor
    if Client.Stopped then
      raise ELspSession.Create(MsgText(SR_LSP_ENGINE_STOPPED));

    // A retry on the SAME text (the client timed out before a slow lint
    // finished) must not restart the lint: the LSP is still working, or the
    // diagnostics are already queued - just wait for them below.
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
