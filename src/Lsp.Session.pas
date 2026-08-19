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
  System.Generics.Collections,
  Lsp.Transport.Process,
  Lsp.Client,
  Lsp.Discovery;

type
  ELspSession = class(Exception);

  TLspSession = class
  private
    class var FInstance: TLspSession;
  private
    FLock: TCriticalSection;
    FClients: TObjectDictionary<string, TLspClient>;
    FOpenDocs: TDictionary<string, Boolean>;
    FLspExe: string;
    function EnsureExe: string;
    function CreateClient(const ARootDir, ASettingsFile: string): TLspClient;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TLspSession;
    class procedure Shutdown;

    { Finds the project settings for a source file ('' if none). }
    function FindSettingsFile(const AFilePath: string): string;

    { Returns the warm client for the file's project (creating it if needed)
      plus the settings file it runs with (''= unconfigured). Also ensures
      the document is open on that client. Thread-safe. }
    function AcquireFor(const AFilePath: string; out ASettingsUsed: string): TLspClient;
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
  FOpenDocs := TDictionary<string, Boolean>.Create;
end;

destructor TLspSession.Destroy;
begin
  FClients.Free; // frees clients, which stop their transports (and children)
  FOpenDocs.Free;
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

function TLspSession.CreateClient(const ARootDir, ASettingsFile: string): TLspClient;
var
  Transport: TLspProcessTransport;
  Resp: TObject;
begin
  Transport := TLspProcessTransport.Create(EnsureExe);
  Transport.Start;
  Result := TLspClient.Create(Transport, True);
  try
    Resp := Result.Initialize(TLspClient.PathToUri(ARootDir), lstAgent);
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

function TLspSession.AcquireFor(const AFilePath: string;
  out ASettingsUsed: string): TLspClient;
var
  FullPath, Key, DocKey, RootDir: string;
begin
  FullPath := TPath.GetFullPath(AFilePath);
  if not FileExists(FullPath) then
    raise ELspSession.CreateFmt('File not found: %s', [AFilePath]);

  FLock.Enter;
  try
    ASettingsUsed := FindSettingsFile(FullPath);
    if ASettingsUsed <> '' then
    begin
      Key := ASettingsUsed.ToLower;
      RootDir := TPath.GetDirectoryName(ASettingsUsed);
    end
    else
    begin
      RootDir := TPath.GetDirectoryName(FullPath);
      Key := '(nosettings)' + RootDir.ToLower;
    end;

    if not FClients.TryGetValue(Key, Result) then
    begin
      Result := CreateClient(RootDir, ASettingsUsed);
      FClients.Add(Key, Result);
    end;

    DocKey := Key + '|' + FullPath.ToLower;
    if not FOpenDocs.ContainsKey(DocKey) then
    begin
      Result.DidOpenFile(FullPath);
      FOpenDocs.Add(DocKey, True);
      Sleep(500); // brief head start for indexing; retries cover the rest
    end;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
  TLspSession.Shutdown;

end.
