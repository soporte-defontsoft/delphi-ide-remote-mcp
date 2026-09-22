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
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

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
    FJob: string;
    FSdk: string;
    FActive: string;
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
    // El .dproj es NUESTRO: vive aqui, aunque lo que se ejecuta este alla.
    [SchemaDescription(SP_PASERVER_PROJECT)]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    // SIN marca, y es la otra excepcion del contrato (con
    // delphi_config.remotedir): este fichero esta EN LA CARPETA DESPLEGADA
    // DEL TARGET. Nuestra jaula no tiene nada que decir sobre el.
    [SchemaDescription(SP_PASERVER_EXE)]
    property Exe: string read FExe write FExe;
    [SchemaDescription(SP_PASERVER_ARGS)]
    property Args: string read FArgs write FArgs;
    [SchemaDescription(SP_PASERVER_JOB)]
    property Job: string read FJob write FJob;
    [SchemaDescription(SP_PASERVER_SDK)]
    property Sdk: string read FSdk write FSdk;
    [SchemaDescription(SP_PASERVER_ACTIVE)]
    property Active: string read FActive write FActive;
    [SchemaDescription(SP_PASERVER_TIMEOUT)]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
  end;

  TDelphiPAServerTool = class(TMCPToolBase<TDelphiPAServerParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPAServerParams): string; override;
  public
    constructor Create; override;
  end;

{ '' si el workspace activo permite marcar al host del perfil AProfName; el
  motivo si no. Existe porque tener un perfil en el IDE NO es permiso del
  workspace (v0.98): el host del perfil pasa por la MISMA lista RemoteHosts
  que un host escrito a mano. Lo usa tambien delphi_adb_linux. }
function ProfileHostDenied(const AProfName: string): string;

implementation

uses
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  Winapi.Windows,
  System.RegularExpressions,
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

const
  { La ficha que cada sysroot lleva dentro: de que maquina salio y con que
    glibc/gcc. Nombre feo a proposito - no debe parecerse a nada del target. }
  SDK_FICHA = 'mcp-sdk.json';

{ ------------------------------------------------------------------ SDKs --

  UN SDK = UNA CARPETA, y el proyecto elige cual usar. Es el modelo del propio
  RAD Studio (el mismo de Android: AndroidAPI36.1_64bit.sdk y compania): el
  sysroot vive en <carpeta de SDKs de ESA instalacion>\<nombre>.sdk - que se
  pregunta con IdeSdksDir(version), NUNCA se escribe a mano: en una maquina
  puede haber dos o tres Delphi y cada uno contesta por si mismo -, su fichero
  <nombre>.sdk en el APPDATA del IDE lo describe, y msbuild lo elige con la
  propiedad PlatformSDK (medido en CodeGear.Profiles.Targets: PlatformSDK vacio
  toma DefaultPlatformSDK de EnvOptions.proj).

  Hasta 2026-09-20 get-sdk volcaba SIEMPRE en "Linux64.sdk", asi que traerse el
  sysroot de una segunda maquina lo superponia al de la primera. Medido en la
  maquina de David: esa carpeta tenia a la vez el arbol de Ubuntu/Zorin y el de
  Fedora, DOS libc.so.6 (2.39 y 2.43) y dos arboles de gcc (13 y 16), con las
  rutas de ambos en el Profile_LibraryPath que ve el linker. Funcionaba por el
  ORDEN de esa lista, no por diseno. }

{ Solo letras y digitos, en minusculas: de aqui sale un nombre de carpeta. }
function SoloAlfanumerico(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
      Result := Result + C;
  Result := Result.ToLower;
end;

{ Que distro es el target, por su /etc/os-release y por el mismo transporte que
  el resto del SDK: 'zorin18', 'fedora44', 'ubuntu2404'. '' si no se puede leer
  (no es motivo para no traerse el sysroot: se cae al nombre del perfil). }
function EtiquetaDelTarget(const APaClient, AProfName: string): string;
var
  Tmp, F, L, Id, Ver: string;
  Rc: Cardinal;
begin
  Result := '';
  // Temporal DEL SERVIDOR: se baja el /etc/os-release del target, se lee y se
  // tira. El agente no lo ve nunca, asi que va junto al ejecutable y no en la
  // jaula de nadie (ver el nombrador en Lsp.Guard).
  Tmp := ServerTempDir('sdk-' +
    LowerCase(TGUID.NewGuid.ToString.Substring(1, 8)));
  try
    CrearCarpeta(Tmp);
    RunCaptured(Format('"%s" --timeout=30 "--get=/etc/os-release,%s" "%s"',
      [APaClient, Tmp, AProfName]), 120000, Rc);
    F := TPath.Combine(Tmp, 'os-release');
    if not TFile.Exists(F) then
      Exit;
    Id := '';
    Ver := '';
    for L in TFile.ReadAllText(F).Replace(#13#10, #10).Split([#10]) do
    begin
      if L.StartsWith('ID=') then
        Id := L.Substring(3).Trim(['"', ' ']);
      if L.StartsWith('VERSION_ID=') then
        Ver := L.Substring(11).Trim(['"', ' ']);
    end;
    Result := SoloAlfanumerico(Id) + SoloAlfanumerico(Ver);
  finally
    try
      BorraArbol(Tmp); // sin cruzar enlaces: ver Lsp.Guard
    except
      // un temporal huerfano no estropea un despliegue
    end;
  end;
end;

{ La version de glibc de un sysroot, leida de su propio libc.so.6 ("release
  version 2.39"). ES el dato que decide si un binario servira o no: enlazado
  con una glibc vieja corre en las nuevas, al reves no. }
function VersionDeGlibc(const ASysRoot: string): string;
var
  D, F: string;
  M: TMatch;
begin
  Result := '';
  for D in TArray<string>.Create('lib\x86_64-linux-gnu', 'lib64',
    'usr\lib\x86_64-linux-gnu', 'usr\lib64') do
  begin
    F := TPath.Combine(TPath.Combine(ASysRoot, D), 'libc.so.6');
    if not TFile.Exists(F) then
      Continue;
    try
      M := TRegEx.Match(TEncoding.ASCII.GetString(TFile.ReadAllBytes(F)),
        'release version (\d+\.\d+)');
      if M.Success then
        Exit(M.Groups[1].Value);
    except
      // un libc ilegible no es motivo para abortar: se queda sin dato
    end;
  end;
end;

{ Dos distros dentro del mismo sysroot: el arbol de Debian y el de Red Hat a la
  vez. Se detecta por las carpetas, que es lo que el linker acaba viendo. }
function SysrootMezclado(const ASysRoot: string): Boolean;

  function HayLibc(const ARel: string): Boolean;
  begin
    Result := TFile.Exists(TPath.Combine(TPath.Combine(ASysRoot, ARel),
      'libc.so.6'));
  end;

begin
  // DOS libc.so.6, uno en cada arbol. Mirar si EXISTEN las dos carpetas no
  // vale: un Ubuntu trae /lib64 y /usr/lib64 con el cargador dentro y nada
  // mas, asi que el primer sysroot limpio que bajo el get-sdk nuevo se acuso
  // a si mismo de estar mezclado (medido 2026-09-20 con el del Zorin).
  Result := (HayLibc('lib\x86_64-linux-gnu') or
             HayLibc('usr\lib\x86_64-linux-gnu')) and
            (HayLibc('lib64') or HayLibc('usr\lib64'));
end;

{ La ficha que queda DENTRO del sysroot: de donde salio y con que. Es lo que
  permite decir "esta carpeta es de Fedora" sin volver a preguntarle al target,
  y lo que impide superponerle otra distro encima. }
function FichaDeSysroot(const ASysRoot: string): TJSONObject;
var
  F: string;
begin
  Result := nil;
  F := TPath.Combine(ASysRoot, SDK_FICHA);
  if not TFile.Exists(F) then
    Exit;
  try
    Result := TJSONObject.ParseJSONValue(TFile.ReadAllText(F)) as TJSONObject;
  except
    Result := nil;
  end;
end;

procedure EscribirFicha(const ASysRoot, ASdk, ADistro, AGlibc, AGcc,
  AProfile: string);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('sdk', ASdk);
    O.AddPair('distro', ADistro);
    O.AddPair('glibc', AGlibc);
    O.AddPair('gcc', AGcc);
    O.AddPair('profile', AProfile);
    O.AddPair('pulled', FormatDateTime('yyyy-mm-dd hh:nn', Now));
    try
      TFile.WriteAllText(TPath.Combine(ASysRoot, SDK_FICHA), O.ToJSON,
        TEncoding.UTF8);
    except
      // sin ficha se sigue: solo se pierde el aviso de mezcla
    end;
  finally
    O.Free;
  end;
end;

{ Los SDK que el IDE tiene ASENTADOS en su registro (PlatformSDKs). El gemelo
  de ideRegistrySeats para perfiles: ver los ficheros .sdk y los asientos uno al
  lado del otro ES el diagnostico de "por que el SDK Manager ensena esto". }
function AsientosDeSdk(const AVersion: string): TArray<string>;
var
  R: TRegistry;
  L: TStringList;
begin
  Result := nil;
  R := TRegistry.Create(KEY_READ);
  L := TStringList.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(Format('Software\Embarcadero\BDS\%s\PlatformSDKs',
      [AVersion])) then
    begin
      R.GetKeyNames(L);
      Result := L.ToStringArray;
    end;
  finally
    L.Free;
    R.Free;
  end;
end;

{ Los Default_<Plataforma> de esa version: que SDK usa el IDE cuando el
  proyecto no dice nada. Es una eleccion del operador y se informa tal cual. }
function DefaultsDeSdk(const AVersion: string): TArray<string>;
var
  R: TRegistry;
  L, Nombres: TStringList;
  V: string;
begin
  Result := nil;
  R := TRegistry.Create(KEY_READ);
  L := TStringList.Create;
  Nombres := TStringList.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(Format('Software\Embarcadero\BDS\%s\PlatformSDKs',
      [AVersion])) then
    begin
      R.GetValueNames(Nombres);
      for V in Nombres do
        if V.StartsWith('Default_', True) then
          L.Add(V.Substring(8) + ' = ' + R.ReadString(V));
      Result := L.ToStringArray;
    end;
  finally
    Nombres.Free;
    L.Free;
    R.Free;
  end;
end;

function AsientoDeSdkExiste(const AVersion, ANombre: string): Boolean;
var
  S: string;
begin
  for S in AsientosDeSdk(AVersion) do
    if SameText(S, ANombre + '.sdk') then
      Exit(True);
  Result := False;
end;

{ Un SDK registrado, con lo que se sabe de el: nombre, sysroot, y -si lo
  trajo get-sdk- la distro y la glibc con la que se enlaza. Un SDK sin ficha es
  uno de antes o uno del IDE: se informa igual, sin inventarse nada. }
function FichaDeSdk(const AVersion, ASdkFile: string): TJSONObject;
var
  Xml, Raiz, Ficha: string;
  M: TMatch;
  O: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', TPath.GetFileNameWithoutExtension(ASdkFile));
  Xml := '';
  try
    Xml := TFile.ReadAllText(ASdkFile);
  except
    Exit;
  end;
  M := TRegEx.Match(Xml, '(?i)<Profile_sysroot>([^<]+)</Profile_sysroot>');
  if not M.Success then
    Exit;
  Raiz := M.Groups[1].Value.Trim;
  Result.AddPair('sysroot', Raiz);
  // Los .sdk que escribe el IDE usan su macro; aqui se sabe a que apunta, y
  // sin expandirla no se podria decir nada de los SDK del SDK Manager.
  if Raiz.Contains('$(BDSPLATFORMSDKSDIR)') then
    Raiz := Raiz.Replace('$(BDSPLATFORMSDKSDIR)', IdeSdksDir(AVersion),
      [rfIgnoreCase]);
  if Raiz.Contains('$(') or not TDirectory.Exists(Raiz) then
    Exit; // con macros sin expandir (o sin carpeta) no hay nada que mirar
  // La glibc SIEMPRE se lee del propio sysroot: es el dato que decide si un
  // binario correra en el destino, y lo tienen tambien los SDK del IDE.
  Ficha := VersionDeGlibc(Raiz);
  if Ficha <> '' then
    Result.AddPair('glibc', Ficha);
  Ficha := TPath.Combine(Raiz, SDK_FICHA);
  if not TFile.Exists(Ficha) then
  begin
    if SysrootMezclado(Raiz) then
      Result.AddPair('warning', 'dos distros dentro del mismo sysroot');
    Exit;
  end;
  O := nil;
  try
    O := TJSONObject.ParseJSONValue(TFile.ReadAllText(Ficha)) as TJSONObject;
  except
    O := nil;
  end;
  if not Assigned(O) then
    Exit;
  try
    for var Clave in TArray<string>.Create('distro', 'gcc', 'profile',
      'pulled') do
      if O.GetValue(Clave) <> nil then
        Result.AddPair(Clave, O.GetValue<string>(Clave));
  finally
    O.Free;
  end;
  if SysrootMezclado(Raiz) then
    Result.AddPair('warning', 'dos distros dentro del mismo sysroot');
end;

function ListProfiles: string;
var
  Asientos: TJSONArray;
  Reg: TRegistry;
  Claves: TStringList;
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
      { Cada SDK con SU ficha: de que distro salio y con que glibc. Es lo
        que permite elegir el generico con criterio - se compila con la
        glibc MAS VIEJA del parque - en vez de por el nombre. }
      for F in TDirectory.GetFiles(Dir, '*.sdk') do
        Sdks.AddElement(FichaDeSdk(Info.Version, F));
    end;
    { Lo que el IDE guarda POR SU CUENTA: la clave RemoteProfiles. Se
      informa aparte de los ficheros porque son dos cosas distintas y solo
      una manda para compilar: el FICHERO es lo que leen paclient, MSBuild y
      este servidor; la clave es de donde el IDE saca su lista. Verlas
      juntas es el diagnostico de "por que el IDE no me lo ensena". }
    Asientos := TJSONArray.Create;
    Return.AddPair('ideRegistrySeats', Asientos);
    var SdkSeats := TJSONArray.Create;
    Return.AddPair('ideSdkSeats', SdkSeats);
    var SdkDefs := TJSONArray.Create;
    Return.AddPair('ideSdkDefaults', SdkDefs);
    for Info in Installs do
      if Info.Found then
      begin
        for F in AsientosDeSdk(Info.Version) do
          SdkSeats.Add(F);
        for F in DefaultsDeSdk(Info.Version) do
          SdkDefs.Add(F);
      end;
    for Info in Installs do
    begin
      if not Info.Found then Continue;
      Reg := TRegistry.Create(KEY_READ);
      try
        Reg.RootKey := HKEY_CURRENT_USER;
        if Reg.OpenKeyReadOnly(Format('Software\\Embarcadero\\BDS\\%s\\RemoteProfiles',
             [Info.Version])) then
        begin
          Claves := TStringList.Create;
          try
            Reg.GetKeyNames(Claves);
            for F in Claves do
              Asientos.Add(F);
          finally
            Claves.Free;
          end;
        end;
      finally
        Reg.Free;
      end;
    end;
    Return.AddPair('note', 'profiles = los .profile en disco (lo que usan ' +
      'paclient, MSBuild y las tools de este servidor). ideRegistrySeats = ' +
      'las claves RemoteProfiles del registro, de donde el IDE saca SU ' +
      'lista. Si un nombre esta en una y no en la otra, ahi esta la ' +
      'explicacion de lo que el IDE ensena o deja de ensenar.');
    if (Profs.Count = 0) and (Sdks.Count = 0) then
      Return.AddPair('note2', 'No connection profiles or SDKs yet. They are ' +
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
function ProbeHostDenied(const AHost: string): string; forward;

{ Los asientos del IDE. Medido 2026-09-19, arqueologia con David delante:
  el Connection Profile Manager del IDE NO enumera los .profile del disco -
  lee HKCU\Software\Embarcadero\BDS\<ver>\RemoteProfiles\<nombre> al
  arrancar y lo reescribe al salir; el SDK Manager hace lo mismo con
  PlatformSDKs\<sdk>. paclient y msbuild solo miran ficheros, asi que los
  perfiles del MCP funcionaron un mes por linea de comandos siendo
  invisibles en el IDE. Estos helpers escriben el asiento gemelo: la
  contrasena va CIFRADA y es la misma cadena en fichero y registro
  (verificado byte a byte), o sea que se copia tal cual. }
procedure RegistrarPerfilEnIde(const AVersion, AName, APlat, AHost: string;
  APort: Integer; const APasswordCifrada: string);
var
  R: TRegistry;
begin
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKey('\Software\Embarcadero\BDS\' + AVersion +
       '\RemoteProfiles\' + AName, True) then
    begin
      R.WriteString('Platform', APlat);
      R.WriteString('HostName', AHost);
      R.WriteInteger('PortNumber', APort);
      R.WriteString('Password', APasswordCifrada);
      R.WriteString('LocalRoot', '');
      R.WriteInteger('PathCount', 0);
      R.CloseKey;
    end;
  finally
    R.Free;
  end;
end;

procedure BorrarPerfilDelIde(const AVersion, AName: string);
var
  R: TRegistry;
begin
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    R.DeleteKey('\Software\Embarcadero\BDS\' + AVersion +
      '\RemoteProfiles\' + AName);
  finally
    R.Free;
  end;
end;

{ El gemelo del SDK en el SDK Manager del IDE: PlatformSDKs\Linux64.sdk
  apuntando al sysroot que get-sdk acaba de aprovisionar. La tabla de rutas
  y los objetos crt NO van clavados aqui: se leen del
  bin\Linux64.defaultsdkpaths que trae CADA instalacion de Delphi (David,
  2026-09-19: cada Delphi tiene su lista), igual que hace el asistente.
  Devuelve True si escribio el asiento; el Default_Linux64 solo se pone si
  faltaba (la eleccion del operador no se roba). }
function RegistrarSdkEnIde(const AVersion, ARootDir, ASysRoot,
  ASdkName: string; AFijarDefault: Boolean): Boolean;
var
  R: TRegistry;
  Fichero, Xml, Clave: string;
  M: TMatch;
  I: Integer;
begin
  Result := False;
  Fichero := TPath.Combine(TPath.Combine(
    ExcludeTrailingPathDelimiter(ARootDir), 'bin'), 'Linux64.defaultsdkpaths');
  if not TFile.Exists(Fichero) then
    Exit;
  Xml := TFile.ReadAllText(Fichero);
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    // OJO con la barra: sin ella la clave sale "BDS37.0\PlatformSDKs", que no
    // la lee nadie. Estuvo asi desde que se escribio get-sdk (visto
    // 2026-09-20 al comparar con las otras cuatro claves de esta unidad, que
    // si la llevan): el SDK quedaba perfecto para msbuild - que solo mira el
    // fichero .sdk - y jamas aparecia en el SDK Manager del IDE.
    Clave := '\Software\Embarcadero\BDS\' + AVersion + '\PlatformSDKs';
    if not R.OpenKey(Clave + '\' + ASdkName + '.sdk', True) then
      Exit;
    R.WriteString('SDKName', ASdkName + '.sdk');
    R.WriteString('SDKDisplayName', 'Linux64 ' + ASdkName + ' (MCP get-sdk)');
    R.WriteString('PlatformName', 'Linux64');
    R.WriteString('Version', '');
    R.WriteString('SystemRoot', ExcludeTrailingPathDelimiter(ASysRoot));
    R.WriteString('SDKStartupObj', TagValue(Xml, 'Profile_startupobj'));
    R.WriteString('SDKEndCodeObj', TagValue(Xml, 'Profile_endcodeobj'));
    R.WriteString('SDKStartupObjS', TagValue(Xml, 'Profile_startupobjS'));
    R.WriteString('SDKEndCodeObjS', TagValue(Xml, 'Profile_endcodeobjS'));
    I := 0;
    for M in TRegEx.Matches(Xml,
      '(?is)<Profile(Include|Library)\s+Include="([^"]+)">.*?' +
      '<FileMask>([^<]*)</FileMask>.*?<SubDirs>([^<]*)</SubDirs>') do
    begin
      R.WriteString('Path' + IntToStr(I), M.Groups[2].Value);
      R.WriteString('Mask' + IntToStr(I), M.Groups[3].Value.Trim);
      if SameText(M.Groups[4].Value.Trim, 'True') then
        R.WriteString('IncludeSubDir' + IntToStr(I), '1')
      else
        R.WriteString('IncludeSubDir' + IntToStr(I), '0');
      R.WriteInteger('Type' + IntToStr(I),
        Ord(SameText(M.Groups[1].Value, 'Library')));
      Inc(I);
    end;
    R.WriteInteger('PathCount', I);
    R.CloseKey;
    if R.OpenKey(Clave, False) then
    begin
      // El SDK "activo" de la plataforma: la negrita de la lista del SDK
      // Manager, y lo que usa un proyecto que no diga nada. SOLO se toca si
      // lo piden (David, 20-sep): traerse un sysroot no es decidir con que
      // compila esta maquina, y un proyecto Windows no necesita ningun SDK.
      if AFijarDefault then
        R.WriteString('Default_Linux64', ASdkName + '.sdk');
      R.CloseKey;
    end;
    Result := I > 0;
  finally
    R.Free;
  end;
end;

function AddProfile(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  PaClient, ProfName, Host, Port, Plat, P, Cmd, Output, ProfileFile: string;
  AvisoDup, F: string;
  ExitCode: Cardinal;
  Return: TJSONObject;
begin
  ProfName := Params.Name.Trim;
  Host := Params.Host.Trim;
  if ProfName = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['name']));
  if Host = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['host']));
  if Params.Password = '' then Exit(Format(SR_PASERVER_NEED_FMT, ['password']));
  // Creating a profile IS declaring where this machine may connect, so it
  // goes through the same door as the raw probe. Without this the whitelist
  // was theatre: an agent wrote a profile pointing at any host:port and then
  // "tested the connection" to it - a port scanner with a reliable oracle
  // (measured 2026-08-25, on this very server, while it was being audited).
  Result := ProbeHostDenied(Host);
  if Result <> '' then
    Exit;
  Port := Params.Port.Trim;
  if Port = '' then Port := '64211';
  // the gate already refused anything outside PACLIENT_PLATFORMS; this loop
  // just restores paclient's exact casing (and applies the default).
  Plat := 'Linux64';
  for P in PACLIENT_PLATFORMS do
    if SameText(P, Params.Platform.Trim) then Plat := P;
  PaClient := FindPaClient(Info);
  if PaClient = '' then Exit(SR_PASERVER_NO_PACLIENT);
  // Un nombre existente NUNCA se pisa (lo pudo crear el IDE u otro agente
  // con una contrasena que este no conoce); y si otro perfil ya apunta al
  // mismo host:puerto, se crea pero avisando - contra los perfiles a lo
  // loco (David, 2026-09-19).
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if TFile.Exists(ProfileFile) then
    Exit(Format(SR_PASERVER_PROFILE_EXISTS_FMT,
      [ProfName, TagValue(TFile.ReadAllText(ProfileFile), 'Profile_host')]));
  AvisoDup := '';
  if TDirectory.Exists(ProfilesDir(Info.Version)) then
    for F in TDirectory.GetFiles(ProfilesDir(Info.Version), '*.profile') do
    try
      if SameText(TagValue(TFile.ReadAllText(F), 'Profile_host'), Host) and
         (TagValue(TFile.ReadAllText(F), 'Profile_port') = Port) then
        AvisoDup := Format(SN_PASERVER_DUP_HOST_FMT,
          [TPath.GetFileNameWithoutExtension(F)]);
    except
      // un perfil ilegible no impide crear el nuevo
    end;
  Cmd := '"' + PaClient + '" --local "--host=' + Host + '" --port=' + Port +
    ' "--password=' + Params.Password + '" "--platform=' + Plat + '" "' +
    ProfName + '"';
  Output := RunCaptured(Cmd, 30000, ExitCode);
  if (ExitCode = 0) and TFile.Exists(ProfileFile) then
  begin
    // el asiento gemelo del IDE, con la contrasena YA cifrada por paclient
    RegistrarPerfilEnIde(Info.Version, ProfName, Plat, Host,
      StrToIntDef(Port, 64211),
      TagValue(TFile.ReadAllText(ProfileFile), 'Profile_password'));
    Return := TJSONObject.Create;
    try
      Return.AddPair('profile', ProfName);
      Return.AddPair('file', ProfileFile);
      Return.AddPair('host', Host);
      Return.AddPair('port', Port);
      Return.AddPair('platform', Plat);
      Return.AddPair('delphiVersion', Info.Version);
      Return.AddPair('ideRegistered', TJSONBool.Create(True));
      if AvisoDup <> '' then
        Return.AddPair('aviso', AvisoDup);
      Return.AddPair('note', SN_PASERVER_PROFILE_OK);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  end
  else if Output.Contains('W0013') then
    // paclient LIES here: exit 0 + "Cannot save profile while bds.exe process
    // is running ... ignored" and no profile on disk. Measured live
    // 2026-08-28 (the operator had the IDE open): the caller believed the
    // profile existed and every later call chased a ghost. Name the real
    // cause and the real fix.
    Result := SR_PASERVER_IDE_OPEN
  else
    // paclient's output never carries the password (it echoes it encrypted).
    Result := 'error: paclient exit ' + IntToStr(ExitCode) + ': ' + Output.Trim;
end;

{ test-connection WITHOUT a profile: a raw TCP dial of host:port - the quick
  "does the server reach my PAServer at all?" answer an agent needs before
  chasing credentials (field request from the first live PAServer session:
  the agent had no way to ask whether we reached it). Route only, no
  credentials involved, so a failure here is ALWAYS network/NAT/firewall. }
{ El host de un perfil, pasado por la MISMA lista que un host escrito a
  mano. Todo comando que marca por perfil (test-connection name=, get-sdk,
  remote-run, delphi_adb_linux) pasa por aqui ANTES de tocar la red: medido
  2026-09-19 que el perfil de otra maquina marcaba desde un workspace cuya
  lista no lo incluia. El perfil dice COMO conectar; el workspace dice SI. }
function ProfileHostDenied(const AProfName: string): string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  ProfileFile, Xml: string;
  M: TMatch;
begin
  Result := '';
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found then
      Continue;
    ProfileFile := TPath.Combine(ProfilesDir(Info.Version),
      AProfName.Trim + '.profile');
    if not TFile.Exists(ProfileFile) then
      Continue; // el no-existe lo reporta cada comando con su propio texto
    try
      Xml := TFile.ReadAllText(ProfileFile);
    except
      Continue;
    end;
    M := TRegEx.Match(Xml, '(?i)<Profile_host>\s*([^<]+?)\s*</Profile_host>');
    if M.Success then
      Exit(ProbeHostDenied(M.Groups[1].Value));
  end;
end;

{ Whether this server may open a TCP connection to AHost. '' = it may.

  Measured 2026-08-25: the whitelist that closed the git hole left this door
  wide open. `test-connection host=127.0.0.1 port=3131` made the server dial
  its own MCP port, and any host:port answered "reachable / refused / timed
  out" - a port scanner run from inside this machine's network, behind its
  firewall, with no execution permission needed. Same primitive, same rule:
  SOLO lo que el operador escribio en RemoteHosts del workspace activo.
  Nada mas - desde v0.98 ni siquiera los hosts de los perfiles del IDE:
  el perfil dice COMO conectar, el workspace dice SI se puede. }
function ProbeHostDenied(const AHost: string): string;
var
  H, Allowed: string;
begin
  Result := '';
  H := AHost.Trim.ToLower;
  if H = '' then
    Exit;
  Allowed := RemoteProbeHosts;
  for var A in Allowed.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
    if SameText(A.Trim, H) or (A.Trim = '*') or (A.Trim = '0.0.0.0') then
      Exit; // '*' / 0.0.0.0: el operador declaro CUALQUIER host
  Result := Format(SR_PASERVER_HOST_DENIED_FMT, [AHost.Trim,
    IfThen(Allowed <> '', Allowed, '(ninguno)')]);
end;

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
{ Take a connection profile out again. It lives outside the workspace (the
  IDE keeps them under the user's profile), so no other tool here can remove
  it: an agent that created one for a test had no way to clean up after
  itself and left three behind for the operator (field round 11). }
function RemoveProfile(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  ProfName, ProfileFile: string;
begin
  ProfName := Params.Name.Trim;
  if ProfName = '' then
    Exit(Format(SR_PASERVER_NEED_FMT, ['name']));
  if not TRegEx.IsMatch(ProfName, '^[A-Za-z0-9_.-]+$') then
    Exit(SR_PASERVER_PROFILE_NAME);
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(SR_COMPONENTS_MISSING);
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if not TFile.Exists(ProfileFile) then
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, [ProfName]));
  try
    TFile.Delete(ProfileFile);
  except
    on E: Exception do
      Exit('error: no pude borrar el perfil: ' + E.Message);
  end;
  BorrarPerfilDelIde(Info.Version, ProfName);
  Result := Format(SN_PASERVER_PROFILE_REMOVED_FMT, [ProfName]);
end;

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
    begin
      Result := ProbeHostDenied(Params.Host.Trim);
      if Result <> '' then
        Exit;
      Exit(TcpProbe(Params.Host.Trim,
        IfThen(Params.Port.Trim <> '', Params.Port.Trim, '64211')));
    end;
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, ['(sin name)']));
  end;
  PaClient := FindPaClient(Info);
  if PaClient = '' then Exit(SR_PASERVER_NO_PACLIENT);
  ProfileFile := TPath.Combine(ProfilesDir(Info.Version), ProfName + '.profile');
  if not TFile.Exists(ProfileFile) then
    Exit(Format(SR_PASERVER_NO_PROFILE_FMT, [ProfName]));
  Result := ProfileHostDenied(ProfName);
  if Result <> '' then
    Exit;
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
    Group: string;        // 'gcc'/'libc': ONE of the group must land; '' = extra
  end;

const
  { What the LINKER needs, from $(BDS)\bin\Linux64.defaultsdkpaths - the
    ProfileLibrary entries plus the gcc tree (crt*/libgcc live there). The
    ProfileInclude entries (C++ headers, tens of thousands of small files)
    are deliberately NOT pulled: this server links Delphi.

    GROUP semantics, not per-entry requiredness: the GCC triplet path is the
    distro's choice - Debian/Ubuntu use x86_64-linux-gnu, Fedora/RHEL use
    x86_64-redhat-linux + /usr/lib64 - so every variant is TRIED and what is
    required is that at least one 'gcc' tree and one 'libc' dir actually
    landed. Marking the Debian path required aborted the whole pull on
    Fedora 44 even though the RedHat tree was there (openclaw, live Fedora
    target, 2026-09-11). }
  LINUX64_PULLS: array[0..5] of TSdkPull = (
    (RemoteBase: '/usr/lib/gcc/x86_64-linux-gnu'; Recursive: True; Group: 'gcc'),
    (RemoteBase: '/usr/lib/x86_64-linux-gnu'; Recursive: False; Group: 'libc'),
    (RemoteBase: '/lib/x86_64-linux-gnu'; Recursive: False; Group: ''),
    (RemoteBase: '/usr/lib/gcc/x86_64-redhat-linux'; Recursive: True; Group: 'gcc'),
    (RemoteBase: '/usr/lib64'; Recursive: False; Group: 'libc'),
    (RemoteBase: '/lib64'; Recursive: False; Group: ''));

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
  Denied := ProfileHostDenied(Prof);
  if Denied <> '' then
    Exit(Denied);
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
  Res := RemoteRun(Prof, Proj, ExeName, TrocearArgs(Params.Args.Trim),
    Params.TimeoutMs);
  try
    Result := Res.ToJSON;
  finally
    Res.Free;
  end;
end;

{ kill: matar un trabajo que remote-run dejo corriendo. Mismas puertas que
  remote-run (es ejecutar algo en el target, aunque sea para pararlo), y solo
  un trabajo de ESE proyecto en ESE perfil: el lanzador no mata otra cosa. }
function KillCmd(const Params: TDelphiPAServerParams): string;
var
  Prof, Proj, Job, Denied: string;
  Res: TJSONObject;
begin
  if not AllowRemoteRun then
    Exit(SR_PASERVER_RUN_DISABLED);
  Prof := Params.Name.Trim;
  Proj := Params.Project.Trim;
  Job := Params.Job.Trim;
  if (Prof = '') or (Proj = '') or (Job = '') then
    Exit(SR_PASERVER_KILL_NEEDS);
  Denied := ProfileHostDenied(Prof);
  if Denied <> '' then
    Exit(Denied);
  Denied := PathDenied(Proj);
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(Proj) then
    Exit(Format(SR_PASERVER_RUN_NOPROJ_FMT, [Proj]));
  Denied := RemoteRunProjectDenied(Proj);
  if Denied <> '' then
    Exit(Denied);
  Res := RemoteKill(Prof, Proj, Job);
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
  SdkName, Etiqueta, Otra, Glibc: string;
  Ficha: TJSONObject;
  ExitCode: Cardinal;
  Pull: TSdkPull;
  Return, PullObj: TJSONObject;
  Pulls: TJSONArray;
  NFiles, TotalFiles: Integer;
  GotGcc, GotLibc: Boolean;
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
  Result := ProfileHostDenied(ProfName);
  if Result <> '' then
    Exit;
  ProfXml := TFile.ReadAllText(ProfileFile);
  Plat := TagValue(ProfXml, 'Profile_platform');
  if not SameText(Plat, 'Linux64') then
    Exit(Format(SR_PASERVER_SDK_PLATFORM_FMT, [ProfName, Plat]));

  // UNA CARPETA POR SDK, igual que el IDE hace con los de Android: el nombre
  // sale de la DISTRO del target (zorin18, fedora44...), del parametro "sdk"
  // cuando el operador quiere imponerlo, o del perfil como ultimo recurso.
  Etiqueta := EtiquetaDelTarget(PaClient, ProfName);
  SdkName := SoloAlfanumerico(Params.Sdk);
  if SdkName = '' then
    SdkName := Etiqueta;
  if SdkName = '' then
    SdkName := SoloAlfanumerico(ProfName);
  SysRoot := TPath.Combine(IdeSdksDir(Info.Version), SdkName + '.sdk');
  // Una distro NO se superpone a otra. Eso es exactamente lo que dejaba dos
  // libc.so.6 y dos arboles de gcc en la misma carpeta, con las rutas de
  // ambos en el Profile_LibraryPath que ve el linker.
  Ficha := FichaDeSysroot(SysRoot);
  if Assigned(Ficha) then
    try
      Otra := '';
      if Ficha.GetValue('distro') <> nil then
        Otra := Ficha.GetValue<string>('distro');
      if (Otra <> '') and (Etiqueta <> '') and not SameText(Otra, Etiqueta) then
        Exit(Format(SR_PASERVER_SDK_OTRA_FMT,
          [SdkName + '.sdk', Otra, Etiqueta, Etiqueta]));
    finally
      Ficha.Free;
    end;
  CrearCarpeta(SysRoot);

  Return := TJSONObject.Create;
  Pulls := TJSONArray.Create;
  Return.AddPair('pulls', Pulls);
  TotalFiles := 0;
  TotalBytes := 0;
  GotGcc := False;
  GotLibc := False;
  try
    for Pull in LINUX64_PULLS do
    begin
      if Pull.Recursive then
        Pattern := Pull.RemoteBase + '/**/*'
      else
        Pattern := Pull.RemoteBase + '/*';
      DestDir := TPath.Combine(SysRoot,
        Pull.RemoteBase.TrimLeft(['/']).Replace('/', '\'));
      CrearCarpeta(DestDir);
      Cmd := '"' + PaClient + '" --timeout=30 "--get=' + Pattern + ',' +
        DestDir + '" "' + ProfName + '"';
      Output := RunCaptured(Cmd, 1200000, ExitCode);
      ParseCopied(Output, NFiles, NBytes);
      PullObj := TJSONObject.Create;
      Pulls.AddElement(PullObj);
      PullObj.AddPair('dir', Pull.RemoteBase);
      PullObj.AddPair('files', TJSONNumber.Create(NFiles));
      PullObj.AddPair('bytes', TJSONNumber.Create(NBytes));
      // paclient --get es INCREMENTAL: sobre un sysroot ya traido copia solo
      // lo que cambio, y muchas veces eso es CERO ficheros. Leer "0 copiados"
      // como "esta distro no tiene este arbol" hacia que REPETIR get-sdk -que
      // es lo que la descripcion manda hacer tras actualizar el sistema del
      // destino- acabase RECHAZADO con "no encaja con ninguna distribucion"
      // (medido contra el Fedora el 2026-09-21: gcc 0 ficheros, /usr/lib64 6).
      // Lo que decide es si el arbol ESTA aqui, no cuantos bajaron hoy. Dos
      // distros no se mezclan en una carpeta (la ficha de arriba lo impide),
      // asi que un arbol presente es de ESTA distro.
      var YaEstaba := (ExitCode = 0) and (NFiles = 0) and
        (Length(TDirectory.GetFiles(DestDir, '*',
          TSearchOption.soAllDirectories)) > 0);
      if ((ExitCode = 0) and (NFiles > 0)) or YaEstaba then
      begin
        if YaEstaba then
          PullObj.AddPair('status', 'already up to date')
        else
          PullObj.AddPair('status', 'ok');
        if Pull.Group = 'gcc' then
          GotGcc := True
        else if Pull.Group = 'libc' then
          GotLibc := True;
      end
      else
        // a distro simply does not have this variant: normal, keep going -
        // the GROUP check below decides whether the pull as a whole worked
        PullObj.AddPair('status', 'skipped (not on this target)');
      Inc(TotalFiles, NFiles);
      Inc(TotalBytes, NBytes);
    end;

    if not (GotGcc and GotLibc) then
    begin
      Return.AddPair('error', Format(SR_PASERVER_SDK_NOGROUP_FMT,
        [ProfName,
         '/usr/lib/gcc/x86_64-linux-gnu | /usr/lib/gcc/x86_64-redhat-linux',
         '/usr/lib/x86_64-linux-gnu | /usr/lib64']));
      Exit(Return.ToJSON);
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
      Sb.AppendLine('    <Profile_sdkname>' + SdkName + '.sdk</Profile_sdkname>');
      Sb.AppendLine('    <Profile_displayname>Linux64 ' + SdkName +
        ' (delphi_paserver get-sdk, profile ' + ProfName + ')</Profile_displayname>');
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

      SdkFile := TPath.Combine(ProfilesDir(Info.Version), SdkName + '.sdk');
      TFile.WriteAllText(SdkFile, Sb.ToString, TEncoding.UTF8);
      // y el asiento del SDK Manager del IDE, leyendo la tabla del
      // defaultsdkpaths de ESTA instalacion (nada clavado)
      if RegistrarSdkEnIde(Info.Version, Info.RootDir, SysRoot, SdkName,
        MatchText(Params.Active.Trim, ['si', 'yes', 'true', '1'])) then
        Return.AddPair('ideSdkRegistered', TJSONBool.Create(True));
    finally
      Sb.Free;
      LibDirs.Free;
    end;

    // La glibc del sysroot recien traido: ES el dato con el que se elige.
    Glibc := VersionDeGlibc(SysRoot);
    EscribirFicha(SysRoot, SdkName, Etiqueta, Glibc, GccVer, ProfName);

    Return.AddPair('sdk', SdkName + '.sdk');
    Return.AddPair('sdkFile', SdkFile);
    Return.AddPair('sysroot', SysRoot);
    if Etiqueta <> '' then
      Return.AddPair('distro', Etiqueta);
    if Glibc <> '' then
      Return.AddPair('glibc', Glibc);
    if GccVer <> '' then
      Return.AddPair('gccVersion', GccVer);
    Return.AddPair('totalFiles', TJSONNumber.Create(TotalFiles));
    Return.AddPair('totalBytes', TJSONNumber.Create(TotalBytes));
    // Pocos ficheros (o ninguno) en una segunda pasada NO es un SDK vacio:
    // a un agente de campo se lo parecio (2026-08-21).
    Return.AddPair('incremental',
      'totalFiles/totalBytes count what was copied in THIS run. The pull is ' +
      'incremental: over a sysroot already on disk it brings only what ' +
      'changed on the target, so a small number - or zero, "already up to ' +
      'date" - is the normal answer of a re-run, not an empty SDK.');
    Return.AddPair('note', SN_PASERVER_SDK_OK);
    if Glibc <> '' then
      Return.AddPair('genericNote', Format(SN_PASERVER_SDK_GENERIC_FMT, [Glibc]));
    // Una carpeta con dos distros dentro solo puede venir de antes de este
    // cambio: se dice, porque el linker las mezcla sin avisar.
    if SysrootMezclado(SysRoot) then
      Return.AddPair('warning', Format(SN_PASERVER_SDK_MEZCLA_FMT, [SysRoot]));
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ Repara la lista del IDE: por cada .profile en disco que no tenga su
  asiento en RemoteProfiles, lo crea leyendo el propio fichero. Nacio el
  19-sep-2026, cuando se vio que un perfil creado por las tools podia estar
  perfectamente en disco -y compilar y desplegar con el- y no aparecer en el
  Connection Profile Manager porque le faltaba el asiento. No toca los que ya
  lo tienen: no es una migracion, es un remiendo idempotente. }
function ReseatProfiles: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Dir, F, Nombre, Plat, Host, Pwd: string;
  Puerto: Integer;
  Texto: string;
  Reg: TRegistry;
  YaEstaba: Boolean;
  Return: TJSONObject;
  Sembrados, Intactos: TJSONArray;
  M: TMatch;
begin
  Return := TJSONObject.Create;
  Sembrados := TJSONArray.Create;
  Intactos := TJSONArray.Create;
  Return.AddPair('seated', Sembrados);
  Return.AddPair('alreadyThere', Intactos);
  try
    Installs := DiscoverAllRadStudios;
    for Info in Installs do
    begin
      if not Info.Found then
        Continue;
      Dir := ProfilesDir(Info.Version);
      if not TDirectory.Exists(Dir) then
        Continue;
      for F in TDirectory.GetFiles(Dir, '*.profile') do
      begin
        Nombre := TPath.GetFileNameWithoutExtension(F);
        Reg := TRegistry.Create(KEY_READ);
        try
          Reg.RootKey := HKEY_CURRENT_USER;
          YaEstaba := Reg.KeyExists('\Software\Embarcadero\BDS\' +
            Info.Version + '\RemoteProfiles\' + Nombre);
        finally
          Reg.Free;
        end;
        if YaEstaba then
        begin
          Intactos.Add(Nombre);
          Continue;
        end;
        try
          Texto := TFile.ReadAllText(F);
        except
          Continue;
        end;
        Plat := 'Linux64';
        M := TRegEx.Match(Texto, '<Profile_platform>([^<]*)</Profile_platform>');
        if M.Success then
          Plat := M.Groups[1].Value.Trim;
        Host := '';
        M := TRegEx.Match(Texto, '<Profile_host>([^<]*)</Profile_host>');
        if M.Success then
          Host := M.Groups[1].Value.Trim;
        Puerto := 64211;
        M := TRegEx.Match(Texto, '<Profile_port>([^<]*)</Profile_port>');
        if M.Success then
          Puerto := StrToIntDef(M.Groups[1].Value.Trim, 64211);
        Pwd := '';
        M := TRegEx.Match(Texto, '<Profile_password>([^<]*)</Profile_password>');
        if M.Success then
          Pwd := M.Groups[1].Value.Trim;   { ya viene cifrada: se copia tal cual }
        if Host = '' then
          Continue;
        RegistrarPerfilEnIde(Info.Version, Nombre, Plat, Host, Puerto, Pwd);
        Sembrados.Add(Nombre);
      end;
    end;
    Return.AddPair('note', 'El asiento es lo que el IDE lee para SU lista; el ' +
      '.profile es lo que usan paclient, MSBuild y este servidor. El IDE ' +
      'carga esa lista AL ARRANCAR, asi que cierralo y abrelo para verlos.');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ Vuelve a escribir el ASIENTO del IDE de un SDK que ya esta en disco, sin
  tocar la red ni el target. Es el gemelo de command=reseat para perfiles, y
  nace del mismo sitio: el asiento vive en el registro, asi que lo escribe con
  buen resultado el servidor que arranca el OPERADOR - si lo escribio otro
  proceso, el IDE no lo ve. Asi repararlo no cuesta volver a bajarse el
  sysroot entero. }
function ReseatSdk(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  Nombre, Fichero, Xml, Raiz: string;
  M: TMatch;
  Return: TJSONObject;
  Hechos: TJSONArray;
  Ficheros: TArray<string>;
begin
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(SR_PASERVER_NO_PACLIENT);
  Nombre := SoloAlfanumerico(Params.Sdk);
  if Nombre = '' then
    Nombre := SoloAlfanumerico(Params.Name);
  if Nombre <> '' then
    Ficheros := [TPath.Combine(ProfilesDir(Info.Version), Nombre + '.sdk')]
  else
    // sin nombre: todos los que haya, que es lo que hace falta despues de un
    // despliegue ("registra lo que tengas")
    Ficheros := TDirectory.GetFiles(ProfilesDir(Info.Version), '*.sdk');

  Return := TJSONObject.Create;
  Hechos := TJSONArray.Create;
  Return.AddPair('seated', Hechos);
  try
    for Fichero in Ficheros do
    begin
      if not TFile.Exists(Fichero) then
      begin
        Return.AddPair('error', Format(SR_PASERVER_SDK_NOFILE_FMT,
          [TPath.GetFileName(Fichero)]));
        Continue;
      end;
      Xml := '';
      try
        Xml := TFile.ReadAllText(Fichero);
      except
        Continue;
      end;
      // solo los de PAServer: los de Android los pone GetIt y no son cosa
      // nuestra
      if not TRegEx.IsMatch(Xml, '(?i)<Profile_platform>\s*Linux64\s*<') then
        Continue;
      M := TRegEx.Match(Xml, '(?i)<Profile_sysroot>([^<]+)</Profile_sysroot>');
      if not M.Success then
        Continue;
      Raiz := M.Groups[1].Value.Trim;
      // los .sdk que escribe el IDE usan su macro; aqui se sabe a que apunta
      if Raiz.Contains('$(BDSPLATFORMSDKSDIR)') then
        Raiz := Raiz.Replace('$(BDSPLATFORMSDKSDIR)',
          IdeSdksDir(Info.Version), [rfIgnoreCase]);
      if Raiz.Contains('$(') or not TDirectory.Exists(Raiz) then
        Continue;
      if RegistrarSdkEnIde(Info.Version, Info.RootDir, Raiz,
           TPath.GetFileNameWithoutExtension(Fichero), False) then
        Hechos.Add(TPath.GetFileNameWithoutExtension(Fichero));
    end;
    Return.AddPair('note', SN_PASERVER_SDK_RESEAT);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ Quita un SDK de en medio: su fichero <nombre>.sdk y su asiento en el SDK
  Manager del IDE, igual que remove-profile hace con un perfil. El SYSROOT (que
  son gigas) NO se borra aqui: se dice donde esta y lo borra quien quiera, que
  una tool que se lleva 11 GB por delante sin preguntar no deberia existir. }
function RemoveSdk(const Params: TDelphiPAServerParams): string;
var
  Info: TRadStudioInfo;
  Nombre, Fichero, Xml, Raiz: string;
  M: TMatch;
  R: TRegistry;
  Return: TJSONObject;
begin
  Nombre := SoloAlfanumerico(Params.Sdk);
  if Nombre = '' then
    Nombre := SoloAlfanumerico(Params.Name);
  if Nombre = '' then
    Exit(Format(SR_PASERVER_NEED_FMT, ['sdk']));
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(SR_COMPONENTS_MISSING);
  Fichero := TPath.Combine(ProfilesDir(Info.Version), Nombre + '.sdk');
  // El fichero puede no estar y el ASIENTO seguir ahi - pasa en cuanto alguien
  // borra el .sdk a mano, y entonces el IDE sigue ofreciendo un SDK que ya no
  // existe. Esta tool es la escoba: si no hay nada que limpiar, NI fichero ni
  // asiento, entonces si se protesta.
  Raiz := '';
  if TFile.Exists(Fichero) then
  begin
    try
      Xml := TFile.ReadAllText(Fichero);
      M := TRegEx.Match(Xml, '(?i)<Profile_sysroot>([^<]+)</Profile_sysroot>');
      if M.Success then
        Raiz := M.Groups[1].Value.Trim;
    except
      Raiz := '';
    end;
    try
      TFile.Delete(Fichero);
    except
      on E: Exception do
        Exit('error: no pude borrar ' + TPath.GetFileName(Fichero) + ': ' +
          E.Message);
    end;
  end
  else if not AsientoDeSdkExiste(Info.Version, Nombre) then
    Exit(Format(SR_PASERVER_SDK_NOFILE_FMT, [Nombre]));
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    R.DeleteKey('\Software\Embarcadero\BDS\' + Info.Version +
      '\PlatformSDKs\' + Nombre + '.sdk');
  finally
    R.Free;
  end;
  Return := TJSONObject.Create;
  try
    Return.AddPair('removed', Nombre + '.sdk');
    if Raiz <> '' then
    begin
      Return.AddPair('sysrootLeftBehind', Raiz);
      Return.AddPair('note', SN_PASERVER_SDK_REMOVED);
    end;
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
  else if Cmd = 'reseat' then
    Result := ReseatProfiles
  else if Cmd = 'add-profile' then
    Result := AddProfile(Params)
  else if Cmd = 'remove-profile' then
    Result := RemoveProfile(Params)
  else if Cmd = 'test-connection' then
    Result := TestConnection(Params)
  else if Cmd = 'remove-sdk' then
    Result := RemoveSdk(Params)
  else if Cmd = 'reseat-sdk' then
    Result := ReseatSdk(Params)
  else if Cmd = 'get-sdk' then
    Result := GetSdk(Params)
  else if Cmd = 'remote-run' then
    Result := RemoteRunCmd(Params)
  else if Cmd = 'kill' then
    Result := KillCmd(Params)
  else
    Result := SR_PASERVER_CMD;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_paserver',
    function: IMCPTool begin Result := TDelphiPAServerTool.Create; end);

end.
