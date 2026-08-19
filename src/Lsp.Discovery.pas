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

end.
