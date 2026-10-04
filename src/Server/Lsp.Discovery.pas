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
    { Como se llama a si misma, leido de la instalacion y NUNCA compuesto
      aqui (David, 22-sep-2026: "o los tenemos o no los tenemos"): el
      registro guarda el nombre en Personalities ("RAD Studio 13" /
      "Delphi 13") y bds.exe lleva la edicion y el build exacto en su
      informacion de version. '' = esa instalacion no lo dice. }
    ProductName: string;  // 'RAD Studio 13'   (Personalities, valor por defecto)
    DelphiName: string;   // 'Delphi 13'       (Personalities\Delphi.Win32)
    Edition: string;      // 'Enterprise/Architect' (bds.exe ProductName)
    Build: string;        // '37.0.59082.6021'     (bds.exe FileVersion)
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

{ Where THIS installation keeps the platform sysroots - the folder the IDE
  calls $(BDSPLATFORMSDKSDIR), with one <name>.sdk subfolder per SDK.

  It is asked to the install, never composed by hand, because a machine can
  host two or three Delphi versions side by side and each one answers for
  itself: (1) the IDE's own Environment Variables of that version, where an
  operator's override lives; (2) failing that, the SDK Manager entries of that
  version - the parent of any sysroot already registered IS the folder; (3)
  and only if neither exists, the documented default, whose literal lives HERE
  and nowhere else. }
function IdeSdksDir(const AVersion: string): string;

{ ALL RAD Studio installations on the machine (a machine may host several
  Delphi versions side by side), newest first. Installs WITHOUT DelphiLSP
  are included too: they still build via msbuild. }
function DiscoverAllRadStudios: TArray<TRadStudioInfo>;

{ The ACTIVE install - the ONE place that chooses one. The version the
  active workspace asks for (PreferredDelphiVersion: [Workspace.<x>]
  DelphiVersion=36.0) when it is installed; otherwise, and by default, the
  highest version that ships a DelphiLSP.exe. Every tool that needs an
  install (build, LSP engine, profiles, SDKs, components) asks here, so a
  workspace pinned to one version gets it everywhere at once. }
function DiscoverRadStudio: TRadStudioInfo;

{ '' when the active install is the one asked for (or none was asked for);
  otherwise the note that says which version was requested and which one
  answers instead - delphi_workspace and delphi_installs show it. }
function DiscoverRadStudioNote: string;

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

type
  TValorIde = record
    Nombre: string;   // el nombre del valor
    Dato: string;     // lo que guarda (solo los de texto)
  end;

{ Los valores de texto de una clave de la configuracion del IDE de esa
  version (SOFTWARE\Embarcadero\BDS\<ver>\<ASubKey>): los del usuario (HKCU)
  y, con AConMaquina, despues los de la maquina (HKLM, sus dos vistas), en
  ese orden y repetidos si estan en varias. EL lector de las listas que el
  IDE guarda asi: los paquetes registrados y los ficheros de ayuda. }
function IdeValoresDeClave(const AVersion, ASubKey: string;
  AConMaquina: Boolean): TArray<TValorIde>;

type
  TIdeAyuda = record
    Nombre: string;   // como la llama el IDE ("IDE Topics Help", "Indy Help")
    Fichero: string;  // el .chm, tal como esta registrado
  end;

{ Los ficheros de ayuda que el IDE de esa version abre con F1: los que
  registra en Help\HtmlHelp1Files (los suyos y los de los componentes
  instalados), del usuario y de la maquina, sin repetir el mismo fichero.
  Nunca una carpeta compuesta a mano: la lista es la del IDE. }
function IdeHelpFiles(const AVersion: string): TArray<TIdeAyuda>;

{ $(BDSCOMMONDIR) as written by the installer in rsvars.bat - the
  AUTHORITATIVE value (no branding names composed by hand: Embarcadero
  renames its Documents folder between eras, e.g. "RAD Studio" ->
  "Embarcadero\Studio"; rsvars always carries the current one).
  '' when it cannot be read - callers must then DROP the entry. }
function BdsCommonDir(const AInfo: TRadStudioInfo): string;

{ $(BDSUSERDIR): the user-documents twin of BDSCOMMONDIR (same branding
  suffix, user Documents instead of Public Documents). '' when underivable. }
function BdsUserDir(const AInfo: TRadStudioInfo): string;

{ La version de fichero de un exe de la instalacion ('37.0.59082.6021'),
  leida de su recurso de version como la de bds.exe (Build); '' si no la
  lleva. La de dcc32.exe es la del compilador. }
function VersionDeFichero(const AExe: string): string;

{ La plataforma del IDE de una instalacion (ARootDir, la de RootDir), la de
  la RTTI de su disenador: 'Win32' si trae el IDE de 32 bits (bin\bds.exe),
  'Win64' si solo el de 64 (bin64\bds.exe). Con los dos, Win32: es el que se
  usa normalmente (David, 4-oct-2026: los dos segun el proyecto, el de 32 lo
  normal; con los dos se tomaba el de 64). Lo publicado es casi lo mismo; lo
  que cambia es el tipo de lo que depende de la plataforma (NativeInt es
  Integer o Int64) y lo que va bajo un IFDEF de la CPU. }
function PlataformaDelIde(const ARootDir: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Win.Registry,
  Lsp.Guard, // PreferredDelphiVersion: la version que pide el workspace activo
  Lsp.Texts,
  Winapi.Windows,
  Lsp.NetDrives;

function TRadStudioInfo.Found: Boolean;
begin
  Result := DelphiLspExe <> '';
end;

{ Edicion y version de fichero de un exe (bds.exe): lo que el instalador
  escribio en el recurso de version, sin tabla ninguna. }
procedure InfoDelExe(const AExe: string; out AEdicion, ABuild: string);
var
  Tam, Dummy: DWORD;
  Buf: TBytes;
  Len: UINT;
  P: Pointer;
  Fijo: PVSFixedFileInfo;
  Trad: PLongWord;
begin
  AEdicion := '';
  ABuild := '';
  if not FileExists(AExe) then
    Exit;
  Tam := GetFileVersionInfoSize(PChar(AExe), Dummy);
  if Tam = 0 then
    Exit;
  SetLength(Buf, Tam);
  if not GetFileVersionInfo(PChar(AExe), 0, Tam, @Buf[0]) then
    Exit;
  if VerQueryValue(@Buf[0], '\', P, Len) and (Len >= SizeOf(TVSFixedFileInfo)) then
  begin
    Fijo := P;
    ABuild := Format('%d.%d.%d.%d', [HiWord(Fijo.dwFileVersionMS),
      LoWord(Fijo.dwFileVersionMS), HiWord(Fijo.dwFileVersionLS),
      LoWord(Fijo.dwFileVersionLS)]);
  end;
  if VerQueryValue(@Buf[0], '\VarFileInfo\Translation', P, Len) and (Len >= 4) then
  begin
    Trad := P;
    if VerQueryValue(@Buf[0], PChar(Format('\StringFileInfo\%.4x%.4x\ProductName',
         [LoWord(Trad^), HiWord(Trad^)])), P, Len) and (Len > 1) then
      AEdicion := string(PChar(P)).Trim;
  end;
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
      // como se llama a si misma: Personalities (valor por defecto "RAD
      // Studio 13", Delphi.Win32 "Delphi 13"); ausente = no lo dice
      if Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\' + Ver + '\Personalities') then
      begin
        Info.ProductName := Reg.ReadString('').Trim;
        if Reg.ValueExists('Delphi.Win32') then
          Info.DelphiName := Reg.ReadString('Delphi.Win32').Trim;
        Reg.CloseKey;
      end;
      InfoDelExe(Info.RootDir + 'bin\bds.exe', Info.Edition, Info.Build);
      AMap.Add(Ver, Info);
    end;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

function VersionDeFichero(const AExe: string): string;
var
  Edicion: string;
begin
  InfoDelExe(AExe, Edicion, Result);
end;

function PlataformaDelIde(const ARootDir: string): string;
begin
  if not FileExists(TPath.Combine(TPath.Combine(ARootDir, 'bin'), 'bds.exe')) and
     FileExists(TPath.Combine(TPath.Combine(ARootDir, 'bin64'), 'bds.exe')) then
    Result := 'Win64'
  else
    Result := 'Win32';
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
  Pedida: string;
begin
  Pedida := PreferredDelphiVersion;
  if Pedida <> '' then
    for Info in DiscoverAllRadStudios do
      if SameText(Info.Version, Pedida) and (Info.DelphiLspExe <> '') then
        Exit(Info);
  // sin peticion, o pedida y no instalada (la nota lo cuenta): la de siempre
  for Info in DiscoverAllRadStudios do // newest first
    if Info.DelphiLspExe <> '' then
      Exit(Info);
  Result := Default(TRadStudioInfo);
end;

function DiscoverRadStudioNote: string;
var
  Pedida: string;
  Activa: TRadStudioInfo;
begin
  Result := '';
  Pedida := PreferredDelphiVersion;
  if Pedida = '' then
    Exit;
  Activa := DiscoverRadStudio;
  if not SameText(Activa.Version, Pedida) then
    Result := MsgFmt(SN_DELPHIVERSION_MISSING_FMT, [Pedida, Activa.Version]);
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
  Shared := PrefijoSinBarra(TPath.GetSharedDocumentsPath);
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
begin
  if ADest = nil then
    Exit;
  // EL lector de los valores de una clave del IDE (IdeValoresDeClave), solo
  // la del usuario, como el IDE: aqui habia otra copia del mismo bucle
  // (revision de la 1.10.0). Un valor que no es texto llega vacio, y vaciar
  // un Values lo quita: no es una macro
  for var V in IdeValoresDeClave(AVersion, 'Environment Variables', False) do
    ADest.Values[V.Nombre] := V.Dato;
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

  // One registry key's values into Map/Off as filename(lower) -> entry.
  // AsNames=True collects only the file names (the Disabled set).
  procedure Collect(const ASubKey: string; AConMaquina, AsNames: Boolean);
  var
    V: TValorIde;
    FileKey: string;
    P: TIdePackage;
  begin
    for V in IdeValoresDeClave(AVersion, ASubKey, AConMaquina) do
    begin
      // The value NAME is the bpl path ($(BDSBIN)\dclx370.bpl or absolute);
      // the DATA is the description the IDE shows.
      FileKey := TPath.GetFileName(V.Nombre.Replace('/', '\'));
      if FileKey = '' then
        Continue;
      if AsNames then
        Off.AddOrSetValue(FileKey.ToLower, True)
      else if not Map.ContainsKey(FileKey.ToLower) then
      begin
        P.Description := V.Dato.Trim;
        if P.Description = '' then
          P.Description := FileKey;
        P.BplFile := FileKey;
        P.Disabled := False;
        Map.Add(FileKey.ToLower, P);
      end;
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
      Collect(SubKey, True, False);
    for var SubKey in TArray<string>.Create('Disabled Packages',
      'Disabled Packages x64') do
      Collect(SubKey, False, True);
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

function IdeValoresDeClave(const AVersion, ASubKey: string;
  AConMaquina: Boolean): TArray<TValorIde>;

  procedure Lee(ARoot: HKEY; AAccess: Cardinal);
  var
    Reg: TRegistry;
    Names: TStringList;
    V: TValorIde;
  begin
    Reg := TRegistry.Create(KEY_READ or AAccess);
    Names := TStringList.Create;
    try
      Reg.RootKey := ARoot;
      if not Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\%s',
        [AVersion, ASubKey])) then
        Exit;
      Reg.GetValueNames(Names);
      for var N in Names do
      begin
        V.Nombre := N;
        try
          V.Dato := Reg.ReadString(N);
        except
          V.Dato := ''; // un valor que no es texto: queda su nombre
        end;
        Result := Result + [V];
      end;
    finally
      Names.Free;
      Reg.Free;
    end;
  end;

begin
  Result := nil;
  Lee(HKEY_CURRENT_USER, 0);
  if AConMaquina then
  begin
    Lee(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY);
    Lee(HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY);
  end;
end;

function IdeHelpFiles(const AVersion: string): TArray<TIdeAyuda>;
var
  V: TValorIde;
  A: TIdeAyuda;
  Vistos: TArray<string>;
begin
  Result := nil;
  Vistos := nil;
  for V in IdeValoresDeClave(AVersion, 'Help\HtmlHelp1Files', True) do
  begin
    A.Nombre := V.Nombre;
    A.Fichero := V.Dato.Trim;
    if (A.Fichero = '') or (IndexText(A.Fichero, Vistos) >= 0) then
      Continue;
    Vistos := Vistos + [A.Fichero];
    Result := Result + [A];
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

function IdeSdksDir(const AVersion: string): string;
var
  Vars: TStringList;
  Reg: TRegistry;
  Claves: TStringList;
  K, Raiz: string;
begin
  Result := '';
  // 1. lo que diga ESA version, si el operador lo redefinio
  Vars := TStringList.Create;
  try
    IdeEnvironmentVars(AVersion, Vars);
    Result := Vars.Values['BDSPLATFORMSDKSDIR'];
  finally
    Vars.Free;
  end;
  if (Result <> '') and not Result.Contains('$(') then
    Exit(SinBarraFinal(Result)); // (la raiz de una unidad, con su barra: se le unen nombres)
  // 2. donde estan los SDK que ESA version ya tiene registrados
  Reg := TRegistry.Create(KEY_READ);
  Claves := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\PlatformSDKs',
      [AVersion])) then
    begin
      Reg.GetKeyNames(Claves);
      for K in Claves do
        if Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\PlatformSDKs\%s',
          [AVersion, K])) then
        try
          Raiz := Reg.ReadString('SystemRoot');
          // solo sirve el que apunte a una carpeta <algo>.sdk: los SDK de
          // Android viven en el CatalogRepository, que es otra cosa
          if (Raiz <> '') and not Raiz.Contains('$(') and
             TPath.GetFileName(PrefijoSinBarra(Raiz)).ToLower.EndsWith('.sdk') then
            Exit(SinBarraFinal(TPath.GetDirectoryName(
              PrefijoSinBarra(Raiz))));
        except
          // una entrada sin SystemRoot no dice nada
        end;
    end;
  finally
    Claves.Free;
    Reg.Free;
  end;
  // 3. el default documentado. UNICO literal, y aqui.
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    TPath.GetDocumentsPath, 'Embarcadero'), 'Studio'), 'SDKs');
end;

end.
