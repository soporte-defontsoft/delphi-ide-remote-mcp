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

type
  ELspSession = class(Exception);

  { What ResolveSettings answered for a directory, plus the file that
    justified the answer and its disk stamp: while that file is unchanged the
    walk (directory scans + settings fabrication) is skipped entirely
    (hermes, release audit 2026-08-26, P1.6). }
  TSettingsEntry = record
    Settings, RootDir, SourceFile, SourceStamp: string;
  end;

  TLspSession = class
  private
    class var FInstance: TLspSession;
  private
    FLock: TCriticalSection;
    FClients: TObjectDictionary<string, TLspClient>;
    FDocVersions: TDictionary<string, Integer>;
    // text the LSP is linting per doc: a retry with the same text must NOT
    // restart the lint, just wait for (or collect) the pending diagnostics
    FLintText: TDictionary<string, string>;
    // disk fingerprint (mtime|size) at the moment the LSP last saw the file:
    // when it changes, the buffer is refreshed with didChange (the LSP must
    // always see the CURRENT disk truth, e.g. after a delphi_edit).
    FDocStamps: TDictionary<string, string>;
    FLspExe: string;
    FSettingsCache: TDictionary<string, TSettingsEntry>;
    function EnsureExe: string;
    function ResolveSettingsWalk(const AFilePath: string;
      out ARootDir, ASource: string): string;
    function CreateClient(const ARootDir, ASettingsFile: string;
      AServerType: TLspServerType): TLspClient;
    function GetClient(const AFullPath: string; ALinter: Boolean;
      out ASettingsUsed, AClientKey, ARootDir: string): TLspClient;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TLspSession;
    class procedure Shutdown;

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
  end;

implementation

function TLspSession.EnsureExe: string;
var
  Info: TRadStudioInfo;
begin
  if FLspExe = '' then
  begin
    Info := DiscoverRadStudio;
    if not Info.Found then
      raise ELspSession.Create(
        'No RAD Studio installation with DelphiLSP.exe found in the registry.');
    FLspExe := Info.DelphiLspExe;
  end;
  Result := FLspExe;
end;

constructor TLspSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FSettingsCache := TDictionary<string, TSettingsEntry>.Create;
  FClients := TObjectDictionary<string, TLspClient>.Create([doOwnsValues]);
  FDocVersions := TDictionary<string, Integer>.Create;
  FDocStamps := TDictionary<string, string>.Create;
  FLintText := TDictionary<string, string>.Create;
end;

destructor TLspSession.Destroy;
begin
  FClients.Free; // frees clients, which stop their transports (and children)
  FDocVersions.Free;
  FDocStamps.Free;
  FLintText.Free;
  FSettingsCache.Free;
  FLock.Free;
  inherited;
end;

{ mtime ticks + size: cheap fingerprint of the file's disk state. }
function DiskStamp(const APath: string): string;
begin
  try
    Result := FloatToStr(TFile.GetLastWriteTimeUtc(APath)) + '|' +
      IntToStr(TFile.GetSize(APath));
  except
    Result := '?';
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
    if Dir = '' then
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
    if Dir = '' then
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
  out ARootDir, ASource: string): string;
var
  Info: TRadStudioInfo;
  Dproj: string;
begin
  ASource := '';
  Info := DiscoverRadStudio;
  Result := FindSettingsFile(AFilePath);
  if (Result <> '') and not IsSettingsStale(Result, Info) then
  begin
    ARootDir := TPath.GetDirectoryName(Result);
    ASource := Result;
    Exit; // fresh IDE-generated settings: best possible source
  end;
  Dproj := FindDproj(AFilePath);
  if Dproj <> '' then
  begin
    ARootDir := TPath.GetDirectoryName(TPath.GetFullPath(Dproj));
    ASource := TPath.GetFullPath(Dproj);
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
  Dir, Src: string;
  E: TSettingsEntry;
begin
  // Cached per directory, invalidated by the stamp of the file that decided
  // the answer (.delphilsp.json or .dproj): editing search paths touches the
  // .dproj, which changes the stamp, which re-fabricates. The no-source case
  // is never cached - a project file could appear at any moment.
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath)).ToLower;
  FLock.Enter;
  try
    if FSettingsCache.TryGetValue(Dir, E) and (E.SourceFile <> '') and
       (DiskStamp(E.SourceFile) = E.SourceStamp) then
    begin
      ARootDir := E.RootDir;
      Exit(E.Settings);
    end;
  finally
    FLock.Leave;
  end;
  Result := ResolveSettingsWalk(AFilePath, ARootDir, Src);
  if Src <> '' then
  begin
    E.Settings := Result;
    E.RootDir := ARootDir;
    E.SourceFile := Src;
    E.SourceStamp := DiskStamp(Src);
    FLock.Enter;
    try
      if FSettingsCache.Count > 256 then
        FSettingsCache.Clear; // tiny map of project dirs; a clear is fine
      FSettingsCache.AddOrSetValue(Dir, E);
    finally
      FLock.Leave;
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
  Result := TLspClient.Create(Transport, True);
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

function TLspSession.GetClient(const AFullPath: string; ALinter: Boolean;
  out ASettingsUsed, AClientKey, ARootDir: string): TLspClient;
const
  Prefix: array [Boolean] of string = ('agent|', 'linter|');
begin
  ASettingsUsed := ResolveSettings(AFullPath, ARootDir);
  if ASettingsUsed <> '' then
    AClientKey := Prefix[ALinter] + ASettingsUsed.ToLower
  else
    AClientKey := Prefix[ALinter] + '(nosettings)' + ARootDir.ToLower;

  // Fast path under the lock; the SLOW path (spawn DelphiLSP + initialize +
  // settings load, seconds) runs UNLOCKED, so warming one project no longer
  // stalls every other agent's LSP call server-wide (hermes, release audit
  // 2026-08-26, P1.6 - the lock used to be held across those sleeps). Two
  // racers may both build a client for the same key; the loser's is retired.
  FLock.Enter;
  try
    if FClients.TryGetValue(AClientKey, Result) then
      Exit;
  finally
    FLock.Leave;
  end;
  var Fresh: TLspClient;
  if ALinter then
    Fresh := CreateClient(ARootDir, ASettingsUsed, lstLinter)
  else
    Fresh := CreateClient(ARootDir, ASettingsUsed, lstAgent);
  FLock.Enter;
  try
    if not FClients.TryGetValue(AClientKey, Result) then
    begin
      FClients.Add(AClientKey, Fresh);
      Exit(Fresh);
    end;
    // lost the race: the winner's client is already public
  finally
    FLock.Leave;
  end;
  Fresh.Free;
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
    raise ELspSession.CreateFmt('File not found: %s', [AFilePath]);

  Result := GetClient(FullPath, False, ASettingsUsed, Key, RootDir);
  DocKey := Key + '|' + FullPath.ToLower;
  var Stamp := DiskStamp(FullPath);
  var Old := '';
  var HeadStart := False;
  FLock.Enter;
  try
    if not FDocVersions.ContainsKey(DocKey) then
    begin
      Result.DidOpenFile(FullPath);
      FDocVersions.Add(DocKey, 1);
      FDocStamps.AddOrSetValue(DocKey, Stamp);
      HeadStart := True;
    end
    else if FDocStamps.TryGetValue(DocKey, Old) and (Old <> Stamp) then
    begin
      // The disk changed since the LSP last saw this file (delphi_edit,
      // scaffolding, an external editor...): refresh the buffer so every
      // answer reflects the CURRENT source, never a stale snapshot.
      var Version := FDocVersions[DocKey] + 1;
      FDocVersions[DocKey] := Version;
      Result.DidChangeText(TLspClient.PathToUri(FullPath),
        TLspClient.LoadSourceText(FullPath), Version);
      FDocStamps[DocKey] := Stamp;
      HeadStart := True;
    end;
  finally
    FLock.Leave;
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
  Version: Integer;
  Stale: TJSONObject;
  Prev: string;
  SameText_: Boolean;
begin
  FullPath := TPath.GetFullPath(AFilePath);
  var Denied := ReadPathDenied(FullPath); // linting never writes the file
  if Denied <> '' then
    raise ELspSession.Create(Denied);
  if not FileExists(FullPath) then
    raise ELspSession.CreateFmt('File not found: %s', [AFilePath]);

  Client := GetClient(FullPath, True, ASettingsUsed, Key, RootDir);
  Uri := TLspClient.PathToUri(FullPath);
  Text := TLspClient.LoadSourceText(FullPath);
  DocKey := Key + '|' + FullPath.ToLower;
  FLock.Enter;
  try

    // A retry on the SAME text (the client timed out before a slow lint
    // finished) must not restart the lint: the LSP is still working, or the
    // diagnostics are already queued - just wait for them below.
    SameText_ := FLintText.TryGetValue(DocKey, Prev) and (Prev = Text);
    if not SameText_ then
    begin
      // Drop any queued diagnostics for this uri from earlier lints.
      repeat
        Stale := Client.WaitForNotification('textDocument/publishDiagnostics', 1, Uri);
        Stale.Free;
      until Stale = nil;

      if FDocVersions.TryGetValue(DocKey, Version) then
      begin
        Inc(Version);
        FDocVersions[DocKey] := Version;
        Client.DidChangeText(Uri, Text, Version);
      end
      else
      begin
        FDocVersions.Add(DocKey, 1);
        Client.DidOpenText(Uri, Text);
      end;
      FLintText.AddOrSetValue(DocKey, Text);
    end;
  finally
    FLock.Leave;
  end;
  // Wait outside the lock: lints can take a while on big units.
  Result := Client.WaitForNotification('textDocument/publishDiagnostics',
    ATimeoutMs, Uri);
  // Delivered: the next call on the same text is a NEW lint, not a retry
  // (measured: without this, an identical second call waited forever for a
  // notification already consumed).
  if Result <> nil then
  begin
    FLock.Enter;
    try
      FLintText.Remove(DocKey);
    finally
      FLock.Leave;
    end;
  end;
end;

initialization

finalization
  TLspSession.Shutdown;

end.
