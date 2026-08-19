unit Mcp.Tools.PAServer;

{ delphi_paserver: the bridge for building/running on OTHER platforms. RAD
  Studio deploys to Linux/macOS through the Platform Assistant (PAServer)
  running on the target; the installers ship inside the Delphi installation.

  This tool covers the READ half of that flow - discover the installers, see
  which platforms the server can compile and which connection profiles/SDKs
  already exist:
    - packages   : the PAServer installers (per install), to download with
                   delphi_fetch and run on the Linux/Mac target.
    - platforms  : platforms this server can target, and whether each already
                   has a connection profile + SDK ready.
    - profiles   : the connection profiles and platform SDKs registered.

  The WRITE/network half (create a profile against the target's IP, pull its
  SDK, deploy+run remotely) needs a live PAServer on the target and is built
  on top of this once one is available. All read-only, so a review agent sees
  the lay of the land too. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types;

type
  TDelphiPAServerParams = class
  private
    FCommand: string;
  public
    [SchemaDescription('packages (PAServer installers to download and run on the target) | platforms (what this server can target + profile/SDK status) | profiles (registered connection profiles and SDKs). Default: platforms')]
    property Command: string read FCommand write FCommand;
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
  MCPServer.Registration,
  Lsp.Discovery;

constructor TDelphiPAServerTool.Create;
begin
  inherited;
  FName := 'delphi_paserver';
  FDescription := 'The bridge for building and running on OTHER platforms ' +
    '(Linux, macOS) through the Platform Assistant (PAServer). command=' +
    'packages lists the PAServer installers that ship with each Delphi ' +
    'install (download them with delphi_fetch and run them on the target ' +
    'machine); command=platforms shows which platforms this server can ' +
    'target and whether each already has a connection profile and SDK; ' +
    'command=profiles lists the registered connection profiles and platform ' +
    'SDKs. Read-only. Building for a platform is delphi_build once its ' +
    'profile exists; enabling a platform in a project is delphi_config.';
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
  else
    Result := 'error: command debe ser platforms | packages | profiles';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_paserver',
    function: IMCPTool begin Result := TDelphiPAServerTool.Create; end);

end.
