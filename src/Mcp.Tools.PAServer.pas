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
    FExe: string;
    FProject: string;
    FArgs: string;
    FTimeoutMs: Integer;
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
    [SchemaDescription(SP_PASERVER_PROJECT)]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_PASERVER_EXE)]
    property Exe: string read FExe write FExe;
    [SchemaDescription(SP_PASERVER_ARGS)]
    property Args: string read FArgs write FArgs;
    [SchemaDescription(SP_PASERVER_TIMEOUT)]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
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
  Lsp.RemoteRun,
  Lsp.Guard,
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
    // Both warnings are field-measured (2026-08-21). (1) A headless paserver
    // whose stdin hits EOF spins its ">>>" prompt in a tight loop - 99.8%
    // CPU and a log growing 295 MB in 20 min; the sleep pipe keeps stdin
    // open. (2) -passfile with the password in PLAIN TEXT made the server
    // reject that exact string on login, while -password=<pwd> inline
    // authenticated first try - the passfile does not seem to be read as
    // plain text, so prefer -password for ad-hoc runs (mind `ps` shows it).
    Result := 'Linux: fetch, then `tar xzf ' + TPath.GetFileName(AFile) +
      ' && cd PAServer-*` and run it KEEPING STDIN OPEN if headless: ' +
      '`sh -c ''sleep infinity | ./paserver -port=64211 -password=<pwd>''` ' +
      '(listens on 64211). Warnings: `./paserver &` with stdin at EOF spins ' +
      'its prompt at 100% CPU (keep the sleep pipe); and -passfile with a ' +
      'plain-text password was rejected on login in the field - pass ' +
      '-password inline instead, and keep the process supervised.'
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

{ Profiles + SDKs live in %APPDATA%\Embarcadero\BDS\<ver> - the shared
  definition is Lsp.Discovery.IdeProfilesDir (the build runner reads it too). }
function ProfilesDir(const AVersion: string): string;
begin
  Result := IdeProfilesDir(AVersion);
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

{ One pull of get-sdk: a remote directory mirrored under the local sysroot.
  Optional entries cover layout differences between distros (Ubuntu vs
  RedHat vs /lib symlinked) - a missing one is normal, not a failure. }
type
  TSdkPull = record
    RemoteBase: string;   // POSIX dir on the target
    Recursive: Boolean;   // whole subtree (**) vs direct files (*)
    Optional: Boolean;
  end;

const
  { What the LINKER needs, from $(BDS)\bin\Linux64.defaultsdkpaths - the
    ProfileLibrary entries plus the gcc tree (crt*/libgcc live there). The
    ProfileInclude entries (C++ headers, tens of thousands of small files)
    are deliberately NOT pulled: this server links Delphi. }
  LINUX64_PULLS: array[0..5] of TSdkPull = (
    (RemoteBase: '/usr/lib/gcc/x86_64-linux-gnu'; Recursive: True; Optional: False),
    (RemoteBase: '/usr/lib/x86_64-linux-gnu'; Recursive: False; Optional: False),
    (RemoteBase: '/lib/x86_64-linux-gnu'; Recursive: False; Optional: True),
    (RemoteBase: '/usr/lib/gcc/x86_64-redhat-linux'; Recursive: True; Optional: True),
    (RemoteBase: '/usr/lib64'; Recursive: False; Optional: True),
    (RemoteBase: '/lib64'; Recursive: False; Optional: True));

{ "Total file(s) copied: 196 file(s)  62.099.159 bytes" -> 196 and 62099159.
  The byte count carries locale thousands separators - digits only. }
procedure ParseCopied(const AOutput: string; out AFiles: Integer; out ABytes: Int64);
var
  L, Digits: string;
  C: Char;
  Parts: TArray<string>;
begin
  AFiles := 0;
  ABytes := 0;
  for L in AOutput.Split([#13#10, #10]) do
    if L.Contains('Total file(s) copied:') then
    begin
      Parts := L.Split([' '], TStringSplitOptions.ExcludeEmpty);
      // "Total file(s) copied: <N> file(s) <bytes> bytes"
      if Length(Parts) >= 4 then
        AFiles := StrToIntDef(Parts[3], 0);
      if Length(Parts) >= 6 then
      begin
        Digits := '';
        for C in Parts[5] do
          if CharInSet(C, ['0'..'9']) then
            Digits := Digits + C;
        ABytes := StrToInt64Def(Digits, 0);
      end;
      Exit;
    end;
end;

{ get-sdk: provision the platform SDK/sysroot locally from the live PAServer
  of a profile, then register it so delphi_build links. Mirrors what the
  IDE's SDK Manager does, measured piece by piece (2026-08-21):
  - paclient --get=<base>/**/*,<dest> recreates the subtree under <dest>
    (verified against a live PAServer: the gcc version dir arrived intact);
  - the IDE-written .sdk file is fully RESOLVED MSBuild XML (no $(SDKROOT)/
    $(GCCVERSION) macros - the Android .sdk on this machine proves it), and
    CodeGear.Delphi.Targets feeds $(Profile_sysroot) to the compiler as its
    --syslibroot, so a sysroot mirror with standard layout is what links;
  - CodeGear.Profiles.Targets imports the .sdk via $(PlatformSDK), which the
    build runner now passes when <Platform>.sdk exists (EnvOptions.proj has
    no command-line default for platforms the SDK Manager never touched). }
function InstallRunnerCmd(const Params: TDelphiPAServerParams): string;
var
  Prof, Err, HowTo: string;
begin
  Prof := Params.Name.Trim;
  if Prof = '' then
    Exit(SR_PASERVER_RUN_NEEDS);
  Err := ShellArgDenied(Prof);
  if Err <> '' then
    Exit(Err);
  Err := InstallRunner(Prof, HowTo);
  if Err <> '' then
    Exit(Err);
  Result := HowTo;
end;

function RemoteRunCmd(const Params: TDelphiPAServerParams): string;
var
  Prof, Proj, ExeName, Denied: string;
  Res: TJSONObject;
begin
  if not AllowRemoteRun then
    Exit(SR_PASERVER_RUN_DISABLED);
  Prof := Params.Name.Trim;
  Proj := Params.Project.Trim;
  ExeName := Params.Exe.Trim;
  if (Prof = '') or (Proj = '') then
    Exit(SR_PASERVER_RUN_NEEDS);
  // the project must be one this server may touch, and must exist
  Denied := PathDenied(Proj);
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(Proj) then
    Exit(Format(SR_PASERVER_RUN_NOPROJ_FMT, [Proj]));
  Denied := RemoteRunProjectDenied(Proj);
  if Denied <> '' then
    Exit(Denied);
  // exe, when given, is a FILE NAME of the deploy folder - never a path
  if (ExeName <> '') and (ExeName.Contains('/') or ExeName.Contains(chr(92)) or
     ExeName.Contains('..')) then
    Exit(SR_PASERVER_RUN_EXENAME);
  Denied := ShellArgDenied(Prof + ' ' + ExeName + ' ' + Params.Args);
  if Denied <> '' then
    Exit(Denied);
  Res := RemoteRun(Prof, Proj, ExeName, Params.Args.Trim, Params.TimeoutMs);
  try
    Result := Res.ToJSON;
  finally
    Res.Free;
  end;
end;

function GetSdk(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  PaClient, ProfName, ProfileFile, ProfXml, Plat, SysRoot: string;
  Cmd, Output, Pattern, DestDir, GccVer, SdkFile, D: string;
  ExitCode: Cardinal;
  Pull: TSdkPull;
  Return, PullObj: TJSONObject;
  Pulls: TJSONArray;
  NFiles, TotalFiles: Integer;
  NBytes, TotalBytes: Int64;
  Sb: TStringBuilder;
  LibDirs: TStringList;
begin
  ProfName := Params.Name.Trim;
  if ProfName = '' then
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, ['(sin name)']));
  PaClient := FindPaClient(Info);
  if PaClient = '' then Exit(SR_PASERVER_NO_PACLIENT);
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if not TFile.Exists(ProfileFile) then
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, [ProfName]));
  ProfXml := TFile.ReadAllText(ProfileFile);
  Plat := TagValue(ProfXml, 'Profile_platform');
  if not SameText(Plat, 'Linux64') then
    Exit(Format(SR_PASERVER_SDK_PLATFORM_FMT, [ProfName, Plat]));

  // The IDE's default SDK root: Documents\Embarcadero\Studio\SDKs, with the
  // sysroot folder named <Platform>.sdk (the Linux64.defaultsdkpaths default).
  SysRoot := TPath.Combine(TPath.Combine(TPath.GetDocumentsPath,
    'Embarcadero\Studio\SDKs'), 'Linux64.sdk');
  TDirectory.CreateDirectory(SysRoot);

  Return := TJSONObject.Create;
  Pulls := TJSONArray.Create;
  Return.AddPair('pulls', Pulls);
  TotalFiles := 0;
  TotalBytes := 0;
  try
    for Pull in LINUX64_PULLS do
    begin
      if Pull.Recursive then
        Pattern := Pull.RemoteBase + '/**/*'
      else
        Pattern := Pull.RemoteBase + '/*';
      DestDir := TPath.Combine(SysRoot,
        Pull.RemoteBase.TrimLeft(['/']).Replace('/', '\'));
      TDirectory.CreateDirectory(DestDir);
      Cmd := '"' + PaClient + '" --timeout=30 "--get=' + Pattern + ',' +
        DestDir + '" "' + ProfName + '"';
      Output := RunCaptured(Cmd, 1200000, ExitCode);
      ParseCopied(Output, NFiles, NBytes);
      PullObj := TJSONObject.Create;
      Pulls.AddElement(PullObj);
      PullObj.AddPair('dir', Pull.RemoteBase);
      PullObj.AddPair('files', TJSONNumber.Create(NFiles));
      PullObj.AddPair('bytes', TJSONNumber.Create(NBytes));
      if ExitCode = 0 then
        PullObj.AddPair('status', 'ok')
      else if Pull.Optional then
        PullObj.AddPair('status', 'skipped (not on this target)')
      else
      begin
        PullObj.AddPair('status', 'FAILED');
        // last non-empty line carries paclient's error (the first is its banner)
        var ErrLine := '';
        for var L in Output.Split([#13#10, #10]) do
          if L.Trim <> '' then
            ErrLine := L.Trim;
        Return.AddPair('error', Format(SR_PASERVER_SDK_PULL_FMT,
          [Pull.RemoteBase, ExitCode, ErrLine]));
        Exit(Return.ToJSON);
      end;
      Inc(TotalFiles, NFiles);
      Inc(TotalBytes, NBytes);
    end;

    // GCC version = the version folder that arrived in the gcc tree.
    GccVer := '';
    for D in TArray<string>.Create('x86_64-linux-gnu', 'x86_64-redhat-linux') do
    begin
      DestDir := TPath.Combine(SysRoot, 'usr\lib\gcc\' + D);
      if TDirectory.Exists(DestDir) then
        for var Sub in TDirectory.GetDirectories(DestDir) do
          if GccVer = '' then
            GccVer := TPath.GetFileName(Sub);
    end;

    // Library search dirs for the .sdk: every pulled dir that exists locally,
    // plus the versioned gcc dir. Fully resolved paths - the IDE-written
    // .sdk files carry no macros and neither does this one.
    LibDirs := TStringList.Create;
    Sb := TStringBuilder.Create;
    try
      for D in TArray<string>.Create(
        'usr\lib\gcc\x86_64-linux-gnu\' + GccVer,
        'usr\lib\x86_64-linux-gnu',
        'lib\x86_64-linux-gnu',
        'usr\lib\gcc\x86_64-redhat-linux\' + GccVer,
        'usr\lib64', 'lib64') do
        if (GccVer <> '') or not D.Contains('\gcc\') then
          if TDirectory.Exists(TPath.Combine(SysRoot, D)) then
            LibDirs.Add(TPath.Combine(SysRoot, D));

      Sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>');
      Sb.AppendLine('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="">');
      Sb.AppendLine('  <PropertyGroup>');
      Sb.AppendLine('    <Profile_platform>Linux64</Profile_platform>');
      Sb.AppendLine('    <Profile_host>' + TagValue(ProfXml, 'Profile_host') + '</Profile_host>');
      Sb.AppendLine('    <Profile_port>' + TagValue(ProfXml, 'Profile_port') + '</Profile_port>');
      Sb.AppendLine('    <Profile_sdkname>Linux64.sdk</Profile_sdkname>');
      Sb.AppendLine('    <Profile_displayname>Linux64 (delphi_paserver get-sdk, profile ' + ProfName + ')</Profile_displayname>');
      Sb.AppendLine('    <Profile_sysroot>' + SysRoot + '</Profile_sysroot>');
      Sb.AppendLine('    <Profile_startupobj>crt1.o;crti.o;crtbegin.o</Profile_startupobj>');
      Sb.AppendLine('    <Profile_endcodeobj>crtend.o;crtn.o</Profile_endcodeobj>');
      Sb.AppendLine('    <Profile_startupobjS>crti.o;crtbeginS.o</Profile_startupobjS>');
      Sb.AppendLine('    <Profile_endcodeobjS>crtendS.o;crtn.o</Profile_endcodeobjS>');
      // The Delphi Linux64 block reads $(Profile_LibraryPath) - a PROPERTY,
      // resolved at project-load time - to build DCC_LibraryPath for the
      // linker. The ProfileLibrary ITEMS below only feed _CollapsePaths (a
      // build-time target, Cpp side). Without this property the link dies
      // with "cannot find -lgcc_s" even though the .sdk imports fine
      // (measured against the first live sysroot).
      Sb.AppendLine('    <Profile_LibraryPath>' + string.Join(';', LibDirs.ToStringArray) + '</Profile_LibraryPath>');
      if TagValue(ProfXml, 'Profile_password') <> '' then
        Sb.AppendLine('    <Profile_password>' + TagValue(ProfXml, 'Profile_password') + '</Profile_password>');
      Sb.AppendLine('  </PropertyGroup>');
      Sb.AppendLine('  <ItemGroup>');
      for D in LibDirs do
      begin
        Sb.AppendLine('    <ProfileLibrary Include="' + D + '">');
        Sb.AppendLine('      <FileMask>*</FileMask>');
        Sb.AppendLine('      <SubDirs>False</SubDirs>');
        Sb.AppendLine('    </ProfileLibrary>');
      end;
      Sb.AppendLine('  </ItemGroup>');
      Sb.AppendLine('</Project>');

      SdkFile := TPath.Combine(ProfilesDir(Info.Version), 'Linux64.sdk');
      TFile.WriteAllText(SdkFile, Sb.ToString, TEncoding.UTF8);
    finally
      Sb.Free;
      LibDirs.Free;
    end;

    Return.AddPair('sdkFile', SdkFile);
    Return.AddPair('sysroot', SysRoot);
    if GccVer <> '' then
      Return.AddPair('gccVersion', GccVer);
    Return.AddPair('totalFiles', TJSONNumber.Create(TotalFiles));
    Return.AddPair('totalBytes', TJSONNumber.Create(TotalBytes));
    Return.AddPair('note', SN_PASERVER_SDK_OK);
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
  else if Cmd = 'get-sdk' then
    Result := GetSdk(Params)
  else if Cmd = 'install-runner' then
    Result := InstallRunnerCmd(Params)
  else if Cmd = 'remote-run' then
    Result := RemoteRunCmd(Params)
  else
    Result := SR_PASERVER_CMD;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_paserver',
    function: IMCPTool begin Result := TDelphiPAServerTool.Create; end);

end.
