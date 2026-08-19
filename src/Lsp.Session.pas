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

  TLspSession = class
  private
    class var FInstance: TLspSession;
  private
    FLock: TCriticalSection;
    FClients: TObjectDictionary<string, TLspClient>;
    FDocVersions: TDictionary<string, Integer>;
    FLspExe: string;
    function EnsureExe: string;
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
  FClients := TObjectDictionary<string, TLspClient>.Create([doOwnsValues]);
  FDocVersions := TDictionary<string, Integer>.Create;
end;

destructor TLspSession.Destroy;
begin
  FClients.Free; // frees clients, which stop their transports (and children)
  FDocVersions.Free;
  FLock.Free;
  inherited;
end;

class function TLspSession.Instance: TLspSession;
begin
  if FInstance = nil then
    FInstance := TLspSession.Create;
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
    var Parent := TPath.GetDirectoryName(Dir);
    if SameText(Parent, Dir) then
      Exit;
    Dir := Parent;
  end;
end;

function TLspSession.ResolveSettings(const AFilePath: string;
  out ARootDir: string): string;
var
  Info: TRadStudioInfo;
  Dproj: string;
begin
  Info := DiscoverRadStudio;
  Result := FindSettingsFile(AFilePath);
  if (Result <> '') and not IsSettingsStale(Result, Info) then
  begin
    ARootDir := TPath.GetDirectoryName(Result);
    Exit; // fresh IDE-generated settings: best possible source
  end;
  Dproj := FindDproj(AFilePath);
  if Dproj <> '' then
  begin
    ARootDir := TPath.GetDirectoryName(TPath.GetFullPath(Dproj));
    Exit(FabricateSettings(Dproj, Info));
  end;
  // No .dproj anywhere: a stale settings file is worse than none (its paths
  // point at machines/drives gone by), so fall back to unconfigured.
  ARootDir := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  Result := '';
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

  if not FClients.TryGetValue(AClientKey, Result) then
  begin
    if ALinter then
      Result := CreateClient(ARootDir, ASettingsUsed, lstLinter)
    else
      Result := CreateClient(ARootDir, ASettingsUsed, lstAgent);
    FClients.Add(AClientKey, Result);
  end;
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

  FLock.Enter;
  try
    Result := GetClient(FullPath, False, ASettingsUsed, Key, RootDir);
    DocKey := Key + '|' + FullPath.ToLower;
    if not FDocVersions.ContainsKey(DocKey) then
    begin
      Result.DidOpenFile(FullPath);
      FDocVersions.Add(DocKey, 1);
      Sleep(500); // brief head start for indexing; retries cover the rest
    end;
  finally
    FLock.Leave;
  end;
end;

function TLspSession.LintFile(const AFilePath: string; ATimeoutMs: Integer;
  out ASettingsUsed: string): TJSONObject;
var
  FullPath, Key, DocKey, RootDir, Uri, Text: string;
  Client: TLspClient;
  Version: Integer;
  Stale: TJSONObject;
begin
  FullPath := TPath.GetFullPath(AFilePath);
  var Denied := ReadPathDenied(FullPath); // linting never writes the file
  if Denied <> '' then
    raise ELspSession.Create(Denied);
  if not FileExists(FullPath) then
    raise ELspSession.CreateFmt('File not found: %s', [AFilePath]);

  FLock.Enter;
  try
    Client := GetClient(FullPath, True, ASettingsUsed, Key, RootDir);
    Uri := TLspClient.PathToUri(FullPath);
    Text := TLspClient.LoadSourceText(FullPath);

    // Drop any queued diagnostics for this uri from earlier lints.
    repeat
      Stale := Client.WaitForNotification('textDocument/publishDiagnostics', 1, Uri);
      Stale.Free;
    until Stale = nil;

    DocKey := Key + '|' + FullPath.ToLower;
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
  finally
    FLock.Leave;
  end;
  // Wait outside the lock: lints can take a while on big units.
  Result := Client.WaitForNotification('textDocument/publishDiagnostics',
    ATimeoutMs, Uri);
end;

initialization

finalization
  TLspSession.Shutdown;

end.
