unit Mcp.Tools.PAServer;

{ delphi_paserver: the bridge for building/running on OTHER platforms. RAD
  Studio deploys to Linux/macOS through the Platform Assistant (PAServer)
  running on the target; the installers ship inside the Delphi installation.

  The READ half of that flow - discover the installers, see which platforms
  the server can compile and which connection profiles/SDKs already exist:
    - packages   : the PAServer installers (per install), to download with
                   delphi_fetch and run on the Linux/Mac target.
    - platforms  : platforms this server can target, and whether each already
                   has a connection profile + SDK ready.
    - profiles   : the connection profiles and platform SDKs registered.

  The NETWORK half (v0.32.0, built against the first live PAServer):
    - add-profile     : register a connection profile (name, host, password;
                        optional port, platform). The file is written by
                        paclient.exe --local itself so the format - password
                        encrypted included - is the IDE's own, never invented.
    - test-connection : dial the PAServer of an existing profile and report
                        whether it answers and accepts the credentials.
  Both are refused for read-only credentials; their arguments are vetted at
  the gate (PAServerArgDenied) like every other command-line sink. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiPAServerParams = class
  private
    FCommand: string;
    FName: string;
    FHost: string;
    FPort: string;
    FPassword: string;
    FPlatform: string;
  public
    [SchemaDescription(SP_PASERVER_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_PASERVER_NAME)]
    property Name: string read FName write FName;
    [SchemaDescription(SP_PASERVER_HOST)]
    property Host: string read FHost write FHost;
    [SchemaDescription(SP_PASERVER_PORT)]
    property Port: string read FPort write FPort;
    [SchemaDescription(SP_PASERVER_PASSWORD)]
    property Password: string read FPassword write FPassword;
    [SchemaDescription(SP_PASERVER_PLATFORM)]
    property Platform: string read FPlatform write FPlatform;
  end;

  TDelphiPAServerTool = class(TMCPToolBase<TDelphiPAServerParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPAServerParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.Diagnostics,
  IdTCPClient,
  MCPServer.Registration,
  Lsp.Discovery,
  Lsp.Dproj,
  Lsp.BuildRunner;

constructor TDelphiPAServerTool.Create;
begin
  inherited;
  FName := 'delphi_paserver';
  FDescription := SD_PASERVER;
end;

{ Human hint for how to install/run a given PAServer package on the target. }
function InstallHint(const AFile: string): string;
var
  N: string;
begin
  N := LowerCase(TPath.GetFileName(AFile));
  if N.EndsWith('.tar.gz') then
    Result := 'Linux: fetch, then `tar xzf ' + TPath.GetFileName(AFile) +
      ' && cd PAServer-* && ./paserver` (listens on 64211).'
  else if N.EndsWith('.pkg') then
    Result := 'macOS: fetch, then open the .pkg to install, and run PAServer (port 64211).'
  else if N.Contains('arm') then
    Result := 'Windows on ARM: fetch and run the setup, then start PAServer.'
  else
    Result := 'Windows: fetch and run the setup, then start PAServer.';
end;

function PlatformOfPackage(const AFile: string): string;
var
  N: string;
begin
  N := LowerCase(TPath.GetFileName(AFile));
  if N.Contains('linux') then Result := 'Linux64'
  else if N.EndsWith('.pkg') then Result := 'OSX64/OSXARM64'
  else if N.Contains('arm') then Result := 'WinARM'
  else Result := 'Win64';
end;

{ The directories where PAServer installers live for an install: $(BDS)\PAServer
  and every CatalogRepository\PAServer_for_* (GetIt). }
procedure CollectPackageDirs(const AInfo: TRadStudioInfo; ADirs: TStrings);
var
  Vars: TStringList;
  Cat, Sub: string;
begin
  ADirs.Add(TPath.Combine(ExcludeTrailingPathDelimiter(AInfo.RootDir), 'PAServer'));
  Vars := TStringList.Create;
  try
    IdeEnvironmentVars(AInfo.Version, Vars);
    for Cat in TArray<string>.Create(Vars.Values['BDSCatalogRepositoryAllUsers'],
      Vars.Values['BDSCatalogRepository']) do
      if (Cat <> '') and TDirectory.Exists(Cat) then
        for Sub in TDirectory.GetDirectories(Cat, 'PAServer_for_*') do
          ADirs.Add(Sub);
  finally
    Vars.Free;
  end;
end;

function ListPackages: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Dirs: TStringList;
  Return: TJSONObject;
  Arr: TJSONArray;
  D, F, Ext: string;
  Obj: TJSONObject;
  Seen: TStringList;
begin
  Return := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Return.AddPair('packages', Arr);
  Seen := TStringList.Create;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  try
    Installs := DiscoverAllRadStudios;
    for Info in Installs do
    begin
      if not Info.Found then Continue;
      Dirs := TStringList.Create;
      try
        CollectPackageDirs(Info, Dirs);
        for D in Dirs do
        begin
          if not TDirectory.Exists(D) then Continue;
          for F in TDirectory.GetFiles(D) do
          begin
            Ext := LowerCase(TPath.GetExtension(F));
            if not (F.ToLower.EndsWith('.tar.gz') or (Ext = '.pkg') or (Ext = '.exe')) then
              Continue;
            if not LowerCase(TPath.GetFileName(F)).Contains('paserver') then
              Continue;
            // the same installer ships in $(BDS)\PAServer AND in the catalog
            // repository - list it once (by name), not twice.
            if Seen.IndexOf(LowerCase(TPath.GetFileName(F))) >= 0 then Continue;
            Seen.Add(LowerCase(TPath.GetFileName(F)));
            Obj := TJSONObject.Create;
            Arr.AddElement(Obj);
            Obj.AddPair('delphiVersion', Info.Version);
            Obj.AddPair('platform', PlatformOfPackage(F));
            Obj.AddPair('path', F);
            try
              Obj.AddPair('sizeBytes', TJSONNumber.Create(TFile.GetSize(F)));
            except end;
            Obj.AddPair('install', InstallHint(F));
          end;
        end;
      finally
        Dirs.Free;
      end;
    end;
    Return.AddPair('note', 'Download a package with delphi_fetch (it returns ' +
      'a whole-file sha256 to verify), copy it to the target machine and run ' +
      'it there. The Platform Assistant then listens on port 64211 for this ' +
      'server to connect.');
    Result := Return.ToJSON;
  finally
    Return.Free;
    Seen.Free;
  end;
end;

{ Profiles + SDKs registered for an install, in %APPDATA%\Embarcadero\BDS\<ver>. }
function ProfilesDir(const AVersion: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('APPDATA'), 'Embarcadero'), 'BDS'), AVersion);
end;

function ListProfiles: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Dir, F: string;
  Return: TJSONObject;
  Profs, Sdks: TJSONArray;
begin
  Return := TJSONObject.Create;
  Profs := TJSONArray.Create;
  Sdks := TJSONArray.Create;
  Return.AddPair('profiles', Profs);
  Return.AddPair('sdks', Sdks);
  try
    Installs := DiscoverAllRadStudios;
    for Info in Installs do
    begin
      if not Info.Found then Continue;
      Dir := ProfilesDir(Info.Version);
      if not TDirectory.Exists(Dir) then Continue;
      for F in TDirectory.GetFiles(Dir, '*.profile') do
        Profs.Add(TPath.GetFileNameWithoutExtension(F));
      for F in TDirectory.GetFiles(Dir, '*.sdk') do
        Sdks.Add(TPath.GetFileNameWithoutExtension(F));
    end;
    if (Profs.Count = 0) and (Sdks.Count = 0) then
      Return.AddPair('note', 'No connection profiles or SDKs yet. They are ' +
        'created against a running PAServer on the target machine.');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

function HasProfileFor(const AVersion, APlatform: string): Boolean;
var
  Dir, F: string;
begin
  Result := False;
  Dir := ProfilesDir(AVersion);
  if not TDirectory.Exists(Dir) then Exit;
  // an SDK file is named after the platform's SDK; a profile is user-named.
  // Heuristic: a platform is "ready" if any .sdk mentions it (the SDK is what
  // a remote build actually needs).
  for F in TDirectory.GetFiles(Dir, '*.sdk') do
    if LowerCase(TFile.ReadAllText(F)).Contains(LowerCase(APlatform)) then
      Exit(True);
end;

function ListPlatforms: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Plat: string;
  Return: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Local: Boolean;
begin
  Return := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Return.AddPair('platforms', Arr);
  try
    Installs := DiscoverAllRadStudios;
    for Info in Installs do
    begin
      if not Info.Found then Continue;
      for Plat in IdeLibraryPlatforms(Info.Version) do
      begin
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('platform', Plat);
        Obj.AddPair('delphiVersion', Info.Version);
        Local := MatchText(Plat, ['Win32', 'Win64', 'Win64x', 'WinARM64EC']);
        Obj.AddPair('buildsLocally', TJSONBool.Create(Local));
        if Local then
          Obj.AddPair('status', 'ready (native Windows target, no PAServer needed)')
        else if HasProfileFor(Info.Version, Plat) then
          Obj.AddPair('status', 'ready (SDK present)')
        else
          Obj.AddPair('status', 'needs a PAServer profile + SDK (see command=packages)');
      end;
    end;
    Return.AddPair('note', 'Windows platforms build natively here. The rest ' +
      'need PAServer on the target: get the installer with command=packages, ' +
      'run it there, then a profile/SDK links this server to it.');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ The newest install that ships bin\paclient.exe. Profiles are managed with
  the IDE's own client so the on-disk format is always the IDE's. }
function FindPaClient(out AInfo: TRadStudioInfo): string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  P: string;
begin
  Result := '';
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found then Continue;
    P := TPath.Combine(TPath.Combine(
      ExcludeTrailingPathDelimiter(Info.RootDir), 'bin'), 'paclient.exe');
    if TFile.Exists(P) then
    begin
      AInfo := Info;
      Exit(P);
    end;
  end;
end;

{ add-profile: paclient --local writes <name>.profile in %APPDATA% with the
  password ENCRYPTED inside (measured; --passfile instead stores the plain
  passfile's PATH - worse, so not used). --local never touches the network:
  the link is verified separately with test-connection. The command line runs
  with no shell and is never logged, so the password only lives in this one
  process argument. }
function AddProfile(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  PaClient, ProfName, Host, Port, Plat, P, Cmd, Output, ProfileFile: string;
  ExitCode: Cardinal;
  Return: TJSONObject;
begin
  ProfName := Params.Name.Trim;
  Host := Params.Host.Trim;
  if ProfName = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['name']));
  if Host = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['host']));
  if Params.Password = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['password']));
  Port := Params.Port.Trim;
  if Port = '' then Port := '64211';
  // the gate already refused anything outside PACLIENT_PLATFORMS; this loop
  // just restores paclient's exact casing (and applies the default).
  Plat := 'Linux64';
  for P in PACLIENT_PLATFORMS do
    if SameText(P, Params.Platform.Trim) then Plat := P;
  PaClient := FindPaClient(Info);
  if PaClient = '' then Exit(SR_PASERVER_NO_PACLIENT);
  Cmd := '"' + PaClient + '" --local "--host=' + Host + '" --port=' + Port +
    ' "--password=' + Params.Password + '" "--platform=' + Plat + '" "' +
    ProfName + '"';
  Output := RunCaptured(Cmd, 30000, ExitCode);
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if (ExitCode = 0) and TFile.Exists(ProfileFile) then
  begin
    Return := TJSONObject.Create;
    try
      Return.AddPair('profile', ProfName);
      Return.AddPair('file', ProfileFile);
      Return.AddPair('host', Host);
      Return.AddPair('port', Port);
      Return.AddPair('platform', Plat);
      Return.AddPair('delphiVersion', Info.Version);
      Return.AddPair('note', SN_PASERVER_PROFILE_OK);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  end
  else
    // paclient's output never carries the password (it echoes it encrypted).
    Result := 'error: paclient exit ' + IntToStr(ExitCode) + ': ' + Output.Trim;
end;

{ test-connection WITHOUT a profile: a raw TCP dial of host:port - the quick
  "does the server reach my PAServer at all?" answer an agent needs before
  chasing credentials (field request from the first live PAServer session:
  the agent had no way to ask whether we reached it). Route only, no
  credentials involved, so a failure here is ALWAYS network/NAT/firewall. }
function TcpProbe(const AHost, APort: string): string;
var
  Client: TIdTCPClient;
  Return: TJSONObject;
  SW: TStopwatch;
  Ok: Boolean;
  Err: string;
begin
  Ok := False;
  Err := '';
  SW := TStopwatch.StartNew;
  Client := TIdTCPClient.Create(nil);
  try
    Client.Host := AHost;
    Client.Port := StrToIntDef(APort, 64211);
    Client.ConnectTimeout := 5000;
    try
      Client.Connect;
      Ok := True;
      Client.Disconnect;
    except
      on E: Exception do
        Err := E.Message;
    end;
  finally
    Client.Free;
  end;
  SW.Stop;
  Return := TJSONObject.Create;
  try
    Return.AddPair('host', AHost);
    Return.AddPair('port', APort);
    Return.AddPair('tcpReachable', TJSONBool.Create(Ok));
    Return.AddPair('elapsedMs', TJSONNumber.Create(SW.ElapsedMilliseconds));
    if Ok then
      Return.AddPair('note', SN_PASERVER_TCP_OK)
    else
    begin
      Return.AddPair('error', Err);
      Return.AddPair('note', SN_PASERVER_TCP_FAIL);
    end;
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ test-connection: paclient with ONLY the profile name connects, authenticates
  and exits - exit 0 = the PAServer answered and took the credentials. }
function TestConnection(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  PaClient, ProfName, ProfileFile, Cmd, Output: string;
  ExitCode: Cardinal;
  Return: TJSONObject;
begin
  ProfName := Params.Name.Trim;
  if ProfName = '' then
  begin
    // no profile named: with a host this is the raw reachability probe
    if Params.Host.Trim <> '' then
      Exit(TcpProbe(Params.Host.Trim,
        IfThen(Params.Port.Trim <> '', Params.Port.Trim, '64211')));
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, ['(sin name)']));
  end;
  PaClient := FindPaClient(Info);
  if PaClient = '' then Exit(SR_PASERVER_NO_PACLIENT);
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if not TFile.Exists(ProfileFile) then
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, [ProfName]));
  Cmd := '"' + PaClient + '" --timeout=20 "' + ProfName + '"';
  Output := RunCaptured(Cmd, 45000, ExitCode);
  Return := TJSONObject.Create;
  try
    Return.AddPair('profile', ProfName);
    Return.AddPair('connected', TJSONBool.Create(ExitCode = 0));
    Return.AddPair('paclientOutput', Output.Trim);
    if ExitCode = 0 then
      Return.AddPair('note', SN_PASERVER_CONNECTED);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

function TDelphiPAServerTool.ExecuteWithParams(const Params: TDelphiPAServerParams): string;
var
  Cmd: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if (Cmd = '') or (Cmd = 'platforms') then
    Result := ListPlatforms
  else if Cmd = 'packages' then
    Result := ListPackages
  else if Cmd = 'profiles' then
    Result := ListProfiles
  else if Cmd = 'add-profile' then
    Result := AddProfile(Params)
  else if Cmd = 'test-connection' then
    Result := TestConnection(Params)
  else
    Result := SR_PASERVER_CMD;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_paserver',
    function: IMCPTool begin Result := TDelphiPAServerTool.Create; end);

end.
