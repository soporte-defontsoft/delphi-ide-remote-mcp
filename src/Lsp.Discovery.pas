unit Lsp.Discovery;

{ Locates the RAD Studio installation via the Windows registry - no hardcoded
  paths. Checks HKCU first (per-user data also lives there), then HKLM, in
  both 32-bit and 64-bit registry views. Picks the highest installed BDS
  version that actually ships a DelphiLSP.exe. }

interface

uses
  System.Classes;

type
  TRadStudioInfo = record
    Version: string;   // e.g. '37.0'
    RootDir: string;   // e.g. 'C:\Program Files (x86)\Embarcadero\Studio\37.0\'
    DelphiLspExe: string; // '' when that install ships no DelphiLSP.exe
    RsVarsBat: string;    // '' when rsvars.bat is missing
    function Found: Boolean;
  end;

{ The IDE's macro table for an install: HKCU\...\BDS\<ver>\Environment
  Variables, filled into ADest as NAME=VALUE. This is the AUTHORITATIVE
  source for macros used in library paths - notably
  $(BDSCatalogRepositoryAllUsers), where every GetIt package lives (FmxLinux,
  Android SDKs, the PAServer installers). Never hardcode a macro list. }
procedure IdeEnvironmentVars(const AVersion: string; ADest: TStrings);

{ Platforms with a Library Search Path registered for that install (Win32,
  Win64, Linux64, OSX64, Android64, iOSDevice64...). Enumerated, never a
  fixed list: each installation exposes its own set. }
function IdeLibraryPlatforms(const AVersion: string): TArray<string>;

{ Generic reader of the IDE's per-user configuration (HKCU\...\BDS\<ver>\...).
  ASubKey is relative to the version key (e.g. 'Editor', 'PlatformSDKs',
  'Environment Variables'); '' when the key or value does not exist. The
  building block for every future IDE setting we need (Android/macOS SDKs,
  deployment, etc.) - never compose registry paths by hand elsewhere. }
function IdeConfigValue(const AVersion, ASubKey, AValueName: string): string;

{ The IDE's configured default encoding for new/saved files (Tools > Options
  > Editor), read from the Editor\DefaultFileFilter value of that install
  (e.g. 'Borland.FileFilter.UTF8ToUTF8'). True = UTF-8; False = the
  historical ANSI default (value absent or not UTF8-to-UTF8). }
function IdeDefaultUtf8(const AVersion: string): Boolean;

{ The per-user IDE data folder %APPDATA%\Embarcadero\BDS\<ver> - where the
  connection profiles (<name>.profile) and platform SDKs (<name>.sdk) live.
  ONE definition, shared by delphi_paserver and the build runner. }
function IdeProfilesDir(const AVersion: string): string;

{ ALL RAD Studio installations on the machine (a machine may host several
  Delphi versions side by side), newest first. Installs WITHOUT DelphiLSP
  are included too: they still build via msbuild. }
function DiscoverAllRadStudios: TArray<TRadStudioInfo>;

{ The ACTIVE install for the LSP engine: the highest version that ships a
  DelphiLSP.exe. }
function DiscoverRadStudio: TRadStudioInfo;

{ The IDE's global Library Search Path for a platform ('Win32'/'Win64'),
  raw, with its $() variables unexpanded. This is where INSTALLED COMPONENT
  packages (third-party) register their source/dcu paths - a project using
  them usually does not repeat those paths in its .dproj, so the Config
  Fabricator must merge this list to resolve their symbols. '' if absent. }
function IdeLibrarySearchPath(const AVersion, APlatform: string): string;

type
  TIdePackage = record
    Description: string;  // what the IDE shows ("Embarcadero FMX Standard Components")
    BplFile: string;      // file name only, macros and folders stripped
    Disabled: Boolean;    // present in Disabled Packages (registered but off)
  end;

{ The design packages REGISTERED in the IDE - the authoritative "what is
  installed to program with", whatever the install channel (GetIt, vendor
  installers, manual). Read from Known Packages + Known Packages x64
  (HKCU, plus HKLM in both registry views), deduplicated by file name;
  Known IDE Packages (IDE plumbing, no components) are deliberately NOT
  included; Disabled Packages mark their entry instead of hiding it.
  Measured 2026-08-21: 152 HKCU + 118 x64 + 83 HKLM on the reference
  machine, 3 disabled. }
function IdeKnownPackages(const AVersion: string): TArray<TIdePackage>;

{ $(BDSCOMMONDIR) as written by the installer in rsvars.bat - the
  AUTHORITATIVE value (no branding names composed by hand: Embarcadero
  renames its Documents folder between eras, e.g. "RAD Studio" ->
  "Embarcadero\Studio"; rsvars always carries the current one).
  '' when it cannot be read - callers must then DROP the entry. }
function BdsCommonDir(const AInfo: TRadStudioInfo): string;

{ $(BDSUSERDIR): the user-documents twin of BDSCOMMONDIR (same branding
  suffix, user Documents instead of Public Documents). '' when underivable. }
function BdsUserDir(const AInfo: TRadStudioInfo): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Win.Registry,
  Winapi.Windows;

function TRadStudioInfo.Found: Boolean;
begin
  Result := DelphiLspExe <> '';
end;

procedure CollectRoot(ARootKey: HKEY; AAccess: LongWord;
  AMap: TDictionary<string, TRadStudioInfo>);
var
  Reg: TRegistry;
  Keys: TStringList;
  I: Integer;
  Ver, RootDir, Exe, Bat: string;
  Info: TRadStudioInfo;
begin
  Reg := TRegistry.Create(KEY_READ or AAccess);
  Keys := TStringList.Create;
  try
    Reg.RootKey := ARootKey;
    if not Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS') then
      Exit;
    Reg.GetKeyNames(Keys);
    Reg.CloseKey;

    for I := 0 to Keys.Count - 1 do
    begin
      Ver := Keys[I];
      if AMap.ContainsKey(Ver) then
        Continue; // an earlier (higher-priority) hive already provided it
      if not Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\' + Ver) then
        Continue;
      RootDir := Reg.ReadString('RootDir');
      Reg.CloseKey;
      if (RootDir = '') or not DirectoryExists(RootDir) then
        Continue;
      Info := Default(TRadStudioInfo);
      Info.Version := Ver;
      Info.RootDir := IncludeTrailingPathDelimiter(RootDir);
      Exe := Info.RootDir + 'bin\DelphiLSP.exe';
      if FileExists(Exe) then
        Info.DelphiLspExe := Exe;
      Bat := Info.RootDir + 'bin\rsvars.bat';
      if FileExists(Bat) then
        Info.RsVarsBat := Bat;
      AMap.Add(Ver, Info);
    end;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

function DiscoverAllRadStudios: TArray<TRadStudioInfo>;
var
  Map: TDictionary<string, TRadStudioInfo>;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Invariant;
  Map := TDictionary<string, TRadStudioInfo>.Create;
  try
    // Order matters: user hive first, then machine hive; each in both views.
    CollectRoot(HKEY_CURRENT_USER, 0, Map);
    CollectRoot(HKEY_CURRENT_USER, KEY_WOW64_32KEY, Map);
    CollectRoot(HKEY_LOCAL_MACHINE, 0, Map);
    CollectRoot(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, Map);
    Result := Map.Values.ToArray;
  finally
    Map.Free;
  end;
  TArray.Sort<TRadStudioInfo>(Result, TComparer<TRadStudioInfo>.Construct(
    function(const A, B: TRadStudioInfo): Integer
    begin
      // newest first
      Result := CompareValue(StrToFloatDef(B.Version, -1, Fmt),
        StrToFloatDef(A.Version, -1, Fmt));
    end));
end;

function DiscoverRadStudio: TRadStudioInfo;
var
  Info: TRadStudioInfo;
begin
  for Info in DiscoverAllRadStudios do // newest first
    if Info.DelphiLspExe <> '' then
      Exit(Info);
  Result := Default(TRadStudioInfo);
end;

function BdsCommonDir(const AInfo: TRadStudioInfo): string;
var
  Line: string;
const
  SETCMD = 'SET BDSCOMMONDIR=';
begin
  Result := '';
  if not AInfo.Found or not FileExists(AInfo.RsVarsBat) then
    Exit;
  try
    for Line in TFile.ReadAllLines(AInfo.RsVarsBat) do
    begin
      var L := Line.Trim.TrimLeft(['@']);
      if StartsText(SETCMD, L) then
        Exit(L.Substring(Length(SETCMD)).Trim);
    end;
  except
    // unreadable rsvars: return '' and let callers drop the entry
  end;
end;

function BdsUserDir(const AInfo: TRadStudioInfo): string;
var
  Common, Shared: string;
begin
  Result := '';
  Common := BdsCommonDir(AInfo);
  if Common = '' then
    Exit;
  Shared := ExcludeTrailingPathDelimiter(TPath.GetSharedDocumentsPath);
  if StartsText(IncludeTrailingPathDelimiter(Shared), Common) then
    Result := TPath.Combine(TPath.GetDocumentsPath,
      Common.Substring(Length(Shared) + 1));
end;

function IdeLibrarySearchPath(const AVersion, APlatform: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  // Library settings are per-user: HKCU only (both registry views).
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\Library\%s',
      [AVersion, APlatform])) and Reg.ValueExists('Search Path') then
      Result := Reg.ReadString('Search Path');
  finally
    Reg.Free;
  end;
end;

procedure IdeEnvironmentVars(const AVersion: string; ADest: TStrings);
var
  Reg: TRegistry;
  Names: TStringList;
  N: string;
begin
  if ADest = nil then
    Exit;
  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\Environment Variables',
      [AVersion])) then
      Exit;
    Reg.GetValueNames(Names);
    for N in Names do
      try
        ADest.Values[N] := Reg.ReadString(N);
      except
        // a non-string value is simply not a macro
      end;
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function IdeLibraryPlatforms(const AVersion: string): TArray<string>;
var
  Reg: TRegistry;
  Keys: TStringList;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\Library',
      [AVersion])) then
      Exit;
    Reg.GetKeyNames(Keys);
    Result := Keys.ToStringArray;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

function IdeKnownPackages(const AVersion: string): TArray<TIdePackage>;
var
  Map: TDictionary<string, TIdePackage>;
  Off: TDictionary<string, Boolean>; // a set: filename(lower) -> present
  List: TList<TIdePackage>;

  // One registry key's values into ADest as filename(lower) -> entry.
  // AsNames=True collects only the file names (the Disabled set).
  procedure Collect(ARoot: HKEY; AAccess: Cardinal; const ASubKey: string;
    AsNames: Boolean);
  var
    Reg: TRegistry;
    Names: TStringList;
    N, FileKey: string;
    P: TIdePackage;
  begin
    Reg := TRegistry.Create(KEY_READ or AAccess);
    Names := TStringList.Create;
    try
      Reg.RootKey := ARoot;
      if not Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\%s',
        [AVersion, ASubKey])) then
        Exit;
      Reg.GetValueNames(Names);
      for N in Names do
      begin
        // The value NAME is the bpl path ($(BDSBIN)\dclx370.bpl or absolute);
        // the DATA is the description the IDE shows.
        FileKey := TPath.GetFileName(
          N.Replace('/', '\'));
        if FileKey = '' then
          Continue;
        if AsNames then
          Off.AddOrSetValue(FileKey.ToLower, True)
        else if not Map.ContainsKey(FileKey.ToLower) then
        begin
          P.Description := Reg.ReadString(N).Trim;
          if P.Description = '' then
            P.Description := FileKey;
          P.BplFile := FileKey;
          P.Disabled := False;
          Map.Add(FileKey.ToLower, P);
        end;
      end;
    finally
      Names.Free;
      Reg.Free;
    end;
  end;

var
  P: TIdePackage;
  Key: string;
begin
  Result := nil;
  Map := TDictionary<string, TIdePackage>.Create;
  Off := TDictionary<string, Boolean>.Create;
  List := TList<TIdePackage>.Create;
  try
    for var SubKey in TArray<string>.Create('Known Packages',
      'Known Packages x64') do
    begin
      Collect(HKEY_CURRENT_USER, 0, SubKey, False);
      Collect(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, SubKey, False);
      Collect(HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY, SubKey, False);
    end;
    for var SubKey in TArray<string>.Create('Disabled Packages',
      'Disabled Packages x64') do
      Collect(HKEY_CURRENT_USER, 0, SubKey, True);
    for Key in Map.Keys do
    begin
      P := Map[Key];
      P.Disabled := Off.ContainsKey(Key);
      List.Add(P);
    end;
    List.Sort(TComparer<TIdePackage>.Construct(
      function(const L, R: TIdePackage): Integer
      begin
        Result := CompareText(L.Description, R.Description);
        if Result = 0 then
          Result := CompareText(L.BplFile, R.BplFile);
      end));
    Result := List.ToArray;
  finally
    List.Free;
    Off.Free;
    Map.Free;
  end;
end;

function IdeConfigValue(const AVersion, ASubKey, AValueName: string): string;
var
  Reg: TRegistry;
  Key: string;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Key := 'SOFTWARE\Embarcadero\BDS\' + AVersion;
    if ASubKey <> '' then
      Key := Key + '\' + ASubKey;
    if Reg.OpenKeyReadOnly(Key) and Reg.ValueExists(AValueName) then
      Result := Reg.ReadString(AValueName);
  finally
    Reg.Free;
  end;
end;

function IdeDefaultUtf8(const AVersion: string): Boolean;
begin
  Result := IdeConfigValue(AVersion, 'Editor', 'DefaultFileFilter')
    .ToUpper.Contains('UTF8TOUTF8');
end;

function IdeProfilesDir(const AVersion: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    GetEnvironmentVariable('APPDATA'), 'Embarcadero'), 'BDS'), AVersion);
end;

end.
