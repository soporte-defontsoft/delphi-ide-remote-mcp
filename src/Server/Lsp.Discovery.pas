unit Lsp.Discovery;

{ Locates the RAD Studio installation via the Windows registry - no hardcoded
  paths. Checks HKCU first (per-user data also lives there), then HKLM, in
  both 32-bit and 64-bit registry views. ONE server = ONE Delphi (David,
  5-oct-2026): the one [Server] DelphiVersion pins, or else the highest
  installed BDS version that actually ships a DelphiLSP.exe. }

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
      "Delphi 13") y el update instalado en InstalledUpdates, y bds.exe
      lleva la edicion y el build exacto en su informacion de version.
      '' = esa instalacion no lo dice. }
    ProductName: string;  // 'RAD Studio 13'   (Personalities, valor por defecto)
    DelphiName: string;   // 'Delphi 13'       (Personalities\Delphi.Win32)
    Edition: string;      // 'Enterprise/Architect' (bds.exe ProductName)
    Build: string;        // '37.0.59082.6021'     (bds.exe FileVersion)
    { El update que el instalador apunto: 'Delphi 13 and C++Builder 13
      Update 1' (InstalledUpdates\Main Product Update), lo que el IDE pone en
      su Acerca de. Embarcadero saca la 13 (BDS 37.0) y luego sus updates:
      Update 1 es la 13.1 y Update 2 la 13.2, la misma 37.0 con la misma
      carpeta - una sustituye a la otra. Es una ETIQUETA para el operador
      (el log de arranque, delphi_installs) y el codigo nunca la compara ni
      la trocea: es texto, y puede cambiar de redaccion o venir traducido.
      El update que cuenta lo declara el operador (ServerDelphiUpdate, David,
      5-oct-2026). Los parches de GetIt son otra cosa y no van aqui. }
    InstalledUpdate: string;
    { El sufijo de su compilador, LEIDO del disco: '370' de bin\dcc32370.dll.
      No sale del numero BDS: solo coinciden desde la 13 (la 12 es BDS 23.0 y
      su compilador dcc32290.dll; revision R1, 5-oct-2026). '' si no hay. }
    SufijoCompilador: string;
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

{ Los nombres de las subclaves de una clave de la configuracion del IDE de
  esa version, las del usuario (HKCU\...\BDS\<ver>\<ASubKey>): las
  plataformas de la biblioteca, los SDK asentados en el SDK Manager, los
  perfiles remotos. EL lector: estaba a mano en cuatro sitios de dos unidades
  (Fable, revision de la 1.22.2). Vacia si la clave no esta. }
function IdeSubclaves(const AVersion, ASubKey: string): TArray<string>;

{ Generic reader of the IDE's per-user configuration (HKCU\...\BDS\<ver>\...).
  ASubKey is relative to the version key (e.g. 'Editor', 'PlatformSDKs',
  'Environment Variables'); '' when the key or value does not exist. The
  building block for every future IDE setting we need (Android/macOS SDKs,
  deployment, etc.) - never compose registry paths by hand elsewhere. Un
  valor que no es texto tambien es '' (ReadString lanzaba; SdkPorDefectoDelIde
  lo leia aparte por eso, P7 de la revision de Opus 5.5). }
function IdeConfigValue(const AVersion, ASubKey, AValueName: string): string;
{ El nombre del valor de PlatformSDKs con el SDK que el SDK Manager tiene por
  defecto para APlat ('Default_' + APlat) y su inversa: el compositor y el
  lector (los Default_ que ensena delphi_paserver profiles). Estaba a mano en
  el build y en paserver. }
function ValorDeSdkPorDefecto(const APlat: string): string;
function PlataformaDeValorDeSdk(const AValor: string; out APlat: string): Boolean;

{ LA clave de la configuracion del IDE en el registro: la raiz
  (SOFTWARE\Embarcadero\BDS, con AVersion = ''), la de una version, o una
  subclave de ella. Nombrador UNICO (D9 de la auditoria de duplicados,
  1.21.4): se componia a mano unas 18 veces en cuatro unidades con dos
  grafias, y ya dio un bug medido el 9-oct-2026 (SysrootsRegistrados). Sin
  barra delante: TRegistry la toma relativa a su raiz, que es lo mismo con
  nada abierto; quien la quiera absoluta le pone la barra. test_paisaje
  vigila que nadie vuelva a escribir el formato. }
function ClaveDelIde(const AVersion, ASubKey: string): string;

{ VIGIA DE UNA CLAVE del registro: Windows senala su evento cuando alguien -
  cualquier proceso, el IDE incluido - escribe un valor o crea o borra una
  subclave debajo (RegNotifyChangeKeyValue sobre el arbol entero, atado a la
  clave y no al hilo que la vigila). Es EL juez de "cambio la configuracion
  del IDE" para lo que el servidor cachea de ella: la zona de biblioteca
  (Lsp.Lugares.LibraryRoots; medido el 21-oct-2026 en la VM: el operador
  registro 19 carpetas en el Library Path con el servidor en marcha y
  delphi_list las negaba con GUARD-002 mientras el IDE y msbuild ya
  compilaban con ellas). Clave = 0 es "sin vigia" (la clave no existe o no
  se deja abrir): CambioLaClave contesta siempre False y lo cacheado vive lo
  que el proceso, como hasta la 1.21.4. Medido con una clave de prueba
  (sonda del 21-oct-2026, y LspTests.Vigia): no se senala sola; un cambio en
  una clave hermana no la senala; dos cambios seguidos sin rearme entre
  medias dejan uno latente que sale al siguiente rearme (una recarga de mas,
  inofensiva); y sin REG_NOTIFY_THREAD_AGNOSTIC el evento se senalaba al
  morir el hilo que armo - aqui cada peticion es un hilo. }
type
  TVigiaDeClave = record
    Clave: NativeUInt;   // la clave abierta con KEY_NOTIFY (0 = sin vigia)
    Evento: NativeUInt;  // el evento (manual) que Windows senala
  end;
{ Vigila una clave de la configuracion del IDE de esa version (relativa a
  HKCU\...\BDS\<ver>, como IdeConfigValue), o cualquiera por su raiz y su
  ruta (VigilaClave: la prueba unitaria vigila una clave propia). Queda
  ARMADA: el primer cambio desde ahora la senala. }
function VigilaClaveDelIde(const AVersion, ASubKey: string): TVigiaDeClave;
function VigilaClave(ARaiz: NativeUInt; const ARuta: string): TVigiaDeClave;
{ Los vigias de lo que compone la ZONA DE BIBLIOTECA: las claves que leen
  IdeLibraryPlatforms e IdePlatformLibraryPaths (Library, con sus
  plataformas y el Search Path de cada una) e IdeEnvironmentVars (las macros
  con las que se expanden, y los catalogos). Junto a sus lectores, para que
  la clave se nombre aqui y no en quien cachea. }
function VigiasDeLaBiblioteca(const AVersion: string): TArray<TVigiaDeClave>;
{ Si Windows senalo el evento desde la ultima pregunta: True UNA vez por
  cambio, y REARMADA antes de contestar, para que un cambio que llegue
  mientras quien pregunta recarga salga en la siguiente pregunta. Sin vigia,
  False. CambioAlgunaClave pregunta (y rearma) a TODAS las de una lista. }
function CambioLaClave(var AVigia: TVigiaDeClave): Boolean;
function CambioAlgunaClave(var AVigias: TArray<TVigiaDeClave>): Boolean;
{ Cierra la clave y el evento; queda sin vigia (dos veces no hace nada). }
procedure SueltaVigia(var AVigia: TVigiaDeClave);

{ The IDE's configured default encoding for new/saved files (Tools > Options
  > Editor), read from the Editor\DefaultFileFilter value of that install
  (e.g. 'Borland.FileFilter.UTF8ToUTF8'). True = UTF-8; False = the
  historical ANSI default (value absent or not UTF8-to-UTF8). }
function IdeDefaultUtf8(const AVersion: string): Boolean;

{ The per-user IDE data folder %APPDATA%\Embarcadero\BDS\<ver> - where the
  connection profiles (<name>.profile) and platform SDKs (<name>.sdk) live.
  ONE definition, shared by delphi_paserver and the build runner. }
function IdeProfilesDir(const AVersion: string): string;

{ EL nombre del fichero de un perfil del IDE: IdeProfilesDir + nombre +
  '.profile'. Nombrador UNICO (se componia a mano en ~7 sitios), con Trim como
  la puerta, para que todos nombren el MISMO fichero. NombreDePerfil es su
  inversa, para quien lista con GetFiles('*.profile'). }
function RutaDePerfil(const AVersion, AName: string): string;
function NombreDePerfil(const APath: string): string;
{ Los perfiles de conexion del IDE de AVersion, por su NOMBRE (NombreDePerfil
  de cada .profile de IdeProfilesDir), ordenados; vacio si no hay carpeta. EL
  lector de la lista: la componian a mano set-profile (Mcp.Tools.Config) y
  profiles, add-profile y reseat (Mcp.Tools.PAServer), cada uno con su
  GetFiles('*.profile') (2an de la 1.18.2). }
function PerfilesDelIde(const AVersion: string): TArray<string>;
{ El perfil de esa lista que es APedido (sin mirar mayusculas), con SU nombre;
  '' si no esta. Lo que teclea el agente solo ELIGE uno de los que hay (2an de
  la 1.18.2: "el agente pide una operacion"): el build lo pasa asi a msbuild,
  sea el de la llamada o el que declara el proyecto. }
function PerfilDelIde(const AVersion, APedido: string): string;
{ El nombre con el que SIGUE un perfil que nombra el agente: el del IDE
  (PerfilDelIde: con las mayusculas de su .profile, el que usa el deploy) si
  esta en la lista, y si no lo tecleado, para que la puerta de despues diga
  que no existe. delphi_paserver y delphi_desktop seguian con lo tecleado,
  mientras el build despliega con el del IDE (R12 del censo de Fable). }
function PerfilConSuNombre(const AVersion, APedido: string): string;
{ Los ficheros .sdk del IDE de AVersion (junto a sus perfiles: RutaDeSdk es
  su nombrador), ordenados; vacio si no hay carpeta. EL lector de la lista:
  la recorrian a mano el build (SdksDePlataforma), adb (su adb), profiles,
  seat-sdk, HasProfileFor y los sysroots de la puerta - seis GetFiles('*.sdk')
  (punto 4 de la 1.18.2). }
function SdksDelIde(const AVersion: string): TArray<string>;

{ EL nombre de un SDK del IDE: '<nombre>.sdk'. Es UNO para todo: el fichero
  junto a los .profile, su clave en PlatformSDKs, los valores SDKName y
  Default_<Plataforma>, y la carpeta de su sysroot. Con o sin '.sdk' en
  ANombre, devuelve una sola. Nombrador UNICO (se componia a mano en 16
  sitios: lo encontro test_paisaje en su primera pasada, 1.16.0);
  NombreSinSdk es su inversa (lo que se ensena: 'zorin18'). }
function NombreDeSdk(const ANombre: string): string;
function NombreSinSdk(const ANombreSdk: string): string;
{ El fichero <nombre>.sdk del IDE (junto a los perfiles) y la carpeta de su
  sysroot ($(BDSPLATFORMSDKSDIR)\<nombre>.sdk), por el MISMO nombrador. }
function RutaDeSdk(const AVersion, ANombre: string): string;
function CarpetaDeSdk(const AVersion, ANombre: string): string;
{ EL sysroot que nombra el texto de un .sdk (Profile_sysroot), con la macro
  del IDE ($(BDSPLATFORMSDKSDIR)) resuelta para ESA version: '' si no lo
  nombra; con otra macro, vuelve con ella (quien mire el disco, que lo
  compruebe). Lo componian a mano el escaner de sysroots mezclados, la ficha
  de profiles y reseat-sdk, y la puerta de leer iba a por la cuarta. }
function SysrootDeSdk(const AVersion, AXml: string): string;

{ Los campos de CONEXION de un perfil del IDE (Profile_host, Profile_port,
  Profile_platform y Profile_password, esta ya cifrada por paclient), leidos
  de su XML en UN sitio: quien necesita uno lo pide aqui, del texto que tenga
  en la mano (el .profile, o el .sdk, que repite host, puerto y plataforma).
  HostDePerfil, por nombre, lee con este. Estaban leidos a mano en doce
  sitios de tres unidades (2.4 de la 1.18.0). }
type
  TCamposDePerfil = record
    Host, Puerto, Plataforma, Password: string;
  end;
function CamposDePerfil(const AXml: string): TCamposDePerfil;

{ EL host (Profile_host) de un perfil, leido del MISMO fichero que compone
  RutaDePerfil. La version con AMotivo dice por que no hay host (no existe / no
  se lee / sin Profile_host): la puerta niega con ese motivo; quien solo quiere
  el host usa la otra. '' si no hay. }
function HostDePerfil(const AVersion, AName: string; out AMotivo: string): string; overload;
function HostDePerfil(const AVersion, AName: string): string; overload;

{ La plataforma para la que se creo un perfil del IDE (su Profile_platform:
  Linux64, Win64, OSX64...), leida del MISMO fichero que compone RutaDePerfil;
  '' si no existe o no se lee. El nombre del perfil no significa nada. }
function PlataformaDePerfil(const AVersion, AName: string): string;

{ Los perfiles del IDE que pueden desplegar APlatform: los de un PAServer del
  sistema que la despliega (Lsp.Dproj.SistemaDelPAServer: uno de un Mac sirve
  a OSX64, OSXARM64 e iOS). Ninguno para Android ni para una plataforma que no
  se conoce. La gemela de SdksDePlataforma (cada .sdk declara su plataforma). }
function PerfilesDePlataforma(const AVersion, APlatform: string): TArray<string>;

{ '' si el perfil AProfile despliega APlatform; si no, la negativa, con su
  plataforma y los que si sirven. La de set-profile y la del build: un
  perfil de Windows aceptado para un Linux64 (medido el 18-oct-2026). }
function PerfilQueNoSirve(const AVersion, AProfile, APlatform: string): string;

{ '' si este servidor PUEDE marcar el host del perfil AProfName: la puerta de
  RemoteHosts (ProbeHostDenied en Lsp.Settings) con el host leido del perfil.
  Falla CERRADO: sin Delphi, perfil que no existe, que no se lee o sin host ->
  niega con su motivo (hasta la 1.15 dejaba pasar los cuatro). La llaman
  delphi_paserver, remote-run y el deploy de delphi_build. }
function ProfileHostDenied(const AProfName: string): string;

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

{ LOS sysroots que ESA version tiene registrados en su SDK Manager
  (PlatformSDKs\<sdk>\SystemRoot del registro del usuario), tal cual estan
  escritos (puede venir la macro $(BDSPLATFORMSDKSDIR): quien la necesite
  resuelta la expande). EL lector de esos valores: IdeSdksDir saca de aqui la
  carpeta de los SDK, y los lugares del IDE (Lsp.Lugares) cada sysroot - los de
  Android viven en el CatalogRepository, fuera de esa carpeta (medido el
  9-oct-2026 en produccion). }
function SysrootsRegistrados(const AVersion: string): TArray<string>;

{ ALL RAD Studio installations on the machine (a machine may host several
  Delphi versions side by side), newest first. Installs WITHOUT DelphiLSP
  are listed too (delphi_installs, the startup log), but a server cannot
  use them: it needs DelphiLSP. }
function DiscoverAllRadStudios: TArray<TRadStudioInfo>;

{ THE Delphi of this server - the ONE place that chooses one, and ONCE: the
  first call fixes it for the life of the process (no registry walk per
  request, and no switching when a RAD Studio is installed or removed while
  it runs). The version settings.ini pins (ServerDelphiVersion: [Server]
  DelphiVersion=37.0); without one, the highest version that ships a
  DelphiLSP.exe - and the server writes it into settings.ini at startup
  (Lsp.Host.Wire). A pinned version that is not installed gives NONE
  (Found = False), and the server does not start (ExigeElDelphiDelServidor):
  it never uses another version instead (David, 5-oct-2026). Every tool
  that needs an install (build, LSP engine, profiles, SDKs, paclient, adb,
  components, the library zone, the designer tables) asks here and never
  walks DiscoverAllRadStudios looking for whichever has what it wants.
  The future landscape: what one release needs done differently (a path, a
  bug of that release, a table) hangs from HERE, keyed by what the install
  says of itself - Info.Version (the BDS number) - AND the update its
  operator declares (ServerDelphiUpdate, [Server] DelphiUpdate=13.2). 13.1
  and 13.2 are both BDS 37.0, and today the server works the same with
  both; the update is declared for what a given one will need, never
  deduced (the installer's text, Info.InstalledUpdate, is only a label for
  the operator). Never a table of names written by hand. }
function DiscoverRadStudio: TRadStudioInfo;

{ Sin su Delphi NO hay servidor (David, 5-oct-2026: "siempre debe haber uno,
  por eso es un servidor MCP para Delphi"): lanza una excepcion con el
  motivo - la fijada que no esta, con las que sirven aqui y su clave, o que
  no hay ninguna con DelphiLSP. La llama TMcpHost.Wire antes que nada, y cada
  host lo cuenta a su manera. }
procedure ExigeElDelphiDelServidor;

{ Lo que el servidor escribe en su log al arrancar: CADA instalacion de la
  maquina con la clave que el operador copiaria a su settings.ini (la que no
  trae DelphiLSP, sin clave: no la puede usar), y cual usa este servidor y
  por que (David, 5-oct-2026). }
function NotasDeArranqueDelphi: TArray<string>;

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

{ Las variables que deja puestas rsvars.bat, 'NOMBRE=valor', en el orden en
  que las pone y con sus %VAR% expandidas: con lo ya puesto en el propio
  fichero, si no del entorno de este proceso, y vacia si no esta (lo que hace
  cmd en un .bat); %% es un %. EL lector de rsvars.bat: BdsCommonDir y el
  build, que lanza msbuild con este entorno y SIN cmd.exe (2an de la 1.18.2:
  con cmd, un msbuild.bat del agente en la carpeta del proyecto ganaba; David
  13-oct, "es el agente el que no debe poder" decidir que se ejecuta).
  GRAMATICA PROPIA, declarada: el juez seria cmd.exe y el build ya no lo
  lanza; rsvars.bat lo escribe el instalador y solo lleva lineas SET, y
  aqui se lee solo eso (una linea que no es SET se salta). nil si no se lee. }
function VariablesDeRsVars(const AInfo: TRadStudioInfo): TArray<string>;

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

{ The IDE's macro table for one installation ($(BDS), $(BDSLIB),
  $(BDSUSERDIR), $(BDSCOMMONDIR), $(BDSCatalogRepository)...), the same one
  the library zone is built from. ADest receives Name=Value pairs. }
procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);

{ The IDE's Library Search Path of ONE platform, every entry expanded to a
  real folder (macros resolved, no trailing delimiter), in registry order.
  Entries that still carry an unresolved macro or are not rooted are left
  out. What "delphi_components platform=X" shows and what the F2613 helper
  of delphi_build compares against. AValor es la lista del IDE que se lee:
  'Search Path' (la de siempre) o 'Browsing Path', la del fuente que el IDE
  ensena (las tablas del disenador leen las dos: Lsp.DesignerMetaGen). De
  ESA instalacion, la que se le da - la del servidor, DiscoverRadStudio:
  hasta el 5-oct-2026 la buscaba por su numero entre todas. AConfig: la
  configuracion de un build, para las entradas con $(Config) ('' = esas se
  quedan fuera). EL lector de esa lista: la zona de biblioteca
  (Lsp.Lugares), los ajustes del motor (Lsp.ConfigFabricator) y components
  la leian cada uno con su lectura del registro y su expansion (tres, regla
  del paisaje; medido el 18-oct-2026 que daban lo mismo en las 13
  plataformas de esta maquina). Es ahi, en una instalacion, donde los
  paquetes de COMPONENTES de terceros registran sus carpetas, que un
  proyecto no suele repetir en su .dproj. }
function IdePlatformLibraryPaths(const AInfo: TRadStudioInfo; const APlatform: string;
  const AValor: string = 'Search Path'; const AConfig: string = ''): TArray<string>;

{ La raiz de instalacion de una carpeta que registra una biblioteca: un nivel
  por encima (X\Source -> X, X\Lib\Linux64 -> X\Lib), nunca la raiz de una
  unidad ('' entonces). La zona de biblioteca (Lsp.Lugares) y delphi_components
  la escribian cada una (depuracion de la 1.23). }
function ComponentRootOf(const APath: string): string;

{ Expands $(NAME) macros with the IDE's environment table (AVars as
  NAME=VALUE, see Lsp.Discovery.IdeEnvironmentVars). Exposed for the search
  path vetting of delphi_config: a path with macros must resolve before the
  jail can judge it. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Win.Registry,
  Lsp.Texts,
  Lsp.Dproj, // TagValue: EL lector de los tags del .profile
  Winapi.Windows,
  Lsp.NetDrives,
  // LeeTexto: la puerta de leer. Sus lugares del IDE (Lsp.Lugares.LugaresDelIde)
  // salen de aqui, por el registro y lo descubierto, sin leer ningun fichero:
  // si los midiese leyendo por la puerta, se preguntaria a si misma
  Lsp.Patch,
  Lsp.Settings; // ServerDelphiVersion: la version que fija el settings.ini

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

{ El sufijo del compilador de una instalacion, del fichero que HAY en su
  bin: dcc32<3 digitos>.dll ('370'). '' si no hay ninguno. }
function SufijoDelCompilador(const ARootDir: string): string;
var
  F, N: string;
begin
  Result := '';
  if not TDirectory.Exists(ARootDir + 'bin') then
    Exit;
  for F in TDirectory.GetFiles(ARootDir + 'bin', 'dcc32*.dll') do
  begin
    N := LowerCase(TPath.GetFileName(F));
    if (Length(N) = 12) and CharInSet(N[6], ['0'..'9']) and
       CharInSet(N[7], ['0'..'9']) and CharInSet(N[8], ['0'..'9']) then
      Exit(Copy(N, 6, 3));
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
    if not Reg.OpenKeyReadOnly(ClaveDelIde('', '')) then
      Exit;
    Reg.GetKeyNames(Keys);
    Reg.CloseKey;

    for I := 0 to Keys.Count - 1 do
    begin
      Ver := Keys[I];
      if AMap.ContainsKey(Ver) then
        Continue; // an earlier (higher-priority) hive already provided it
      if not Reg.OpenKeyReadOnly(ClaveDelIde(Ver, '')) then
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
      if Reg.OpenKeyReadOnly(ClaveDelIde(Ver, 'Personalities')) then
      begin
        Info.ProductName := Reg.ReadString('').Trim;
        if Reg.ValueExists('Delphi.Win32') then
          Info.DelphiName := Reg.ReadString('Delphi.Win32').Trim;
        Reg.CloseKey;
      end;
      // el update instalado, lo que el IDE pone en su Acerca de (13.1 es
      // "Update 1", 13.2 "Update 2"); ausente = no lo dice
      if Reg.OpenKeyReadOnly(ClaveDelIde(Ver, 'InstalledUpdates')) then
      begin
        if Reg.ValueExists('Main Product Update') then
          Info.InstalledUpdate := Reg.ReadString('Main Product Update').Trim;
        Reg.CloseKey;
      end;
      InfoDelExe(Info.RootDir + 'bin\bds.exe', Info.Edition, Info.Build);
      Info.SufijoCompilador := SufijoDelCompilador(Info.RootDir);
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

var
  // El Delphi del servidor, elegido UNA vez (DiscoverRadStudio)
  GDelphiCandado: TObject;
  GDelphiElegido: Boolean = False;
  GDelphiDelServidor: TRadStudioInfo;

{ La eleccion: la fijada si esta (y trae DelphiLSP), si no hay fijada la
  mas nueva con DelphiLSP; fijada y no instalada, NINGUNA. Hasta el
  5-oct-2026 se caia a la mas nueva y el "servidor del 12" compilaba con
  el 13. }
function EligeDelphi: TRadStudioInfo;
var
  Info: TRadStudioInfo;
  Pedida: string;
begin
  Pedida := ServerDelphiVersion;
  for Info in DiscoverAllRadStudios do // newest first
    if Info.Found and ((Pedida = '') or SameText(Info.Version, Pedida)) then
      Exit(Info);
  Result := Default(TRadStudioInfo);
end;

function DiscoverRadStudio: TRadStudioInfo;
begin
  TMonitor.Enter(GDelphiCandado);
  try
    if not GDelphiElegido then
    begin
      GDelphiDelServidor := EligeDelphi;
      GDelphiElegido := True;
    end;
    Result := GDelphiDelServidor;
  finally
    TMonitor.Exit(GDelphiCandado);
  end;
end;

{ Como se llama una instalacion, de lo que ella dice de si misma: '37.0
  (RAD Studio 13, Delphi 13 and C++Builder 13 Update 1)', o solo la version
  si no lo dice. }
function NombreConVersion(const AInfo: TRadStudioInfo): string;
var
  Dice: string;
begin
  Dice := AInfo.ProductName;
  if (Dice <> '') and (AInfo.InstalledUpdate <> '') then
    Dice := Dice + ', ';
  Dice := Dice + AInfo.InstalledUpdate;
  Result := AInfo.Version;
  if Dice <> '' then
    Result := Result + ' (' + Dice + ')';
end;

procedure ExigeElDelphiDelServidor;
var
  Info: TRadStudioInfo;
  Usables: TArray<string>;
  Lista: string;
begin
  if DiscoverRadStudio.Found then
    Exit;
  if ServerDelphiVersion = '' then
    raise Exception.Create(MsgText(SE_DISC_NINGUNA));
  Usables := nil;
  for Info in DiscoverAllRadStudios do
    if Info.Found then
      Usables := Usables + [MsgFmt(SF_DISC_USABLE_FMT, [NombreConVersion(Info), Info.Version])];
  if Length(Usables) = 0 then
    Lista := MsgText(SF_DISC_NINGUNA_USABLE)
  else
    Lista := string.Join('; ', Usables);
  raise Exception.Create(MsgFmt(SE_DISC_FIJADA_NO_ESTA_FMT,
    [ServerDelphiVersion, Lista]));
end;

function NotasDeArranqueDelphi: TArray<string>;
var
  Info, LaMia: TRadStudioInfo;
  Quien, Marca, Porque: string;
begin
  Result := nil;
  LaMia := DiscoverRadStudio;
  for Info in DiscoverAllRadStudios do
  begin
    // como se llama, de la instalacion misma; si no lo dice, la version
    Quien := Trim(Info.ProductName + ' ' + Info.Build);
    if Info.InstalledUpdate <> '' then
      if Quien = '' then
        Quien := Info.InstalledUpdate
      else
        Quien := Quien + ', ' + Info.InstalledUpdate;
    if Quien = '' then
      Quien := Info.Version;
    if not Info.Found then
    begin
      Result := Result + [MsgFmt(SL_DISC_SIN_DELPHILSP_FMT, [Quien, Info.Version])];
      Continue;
    end;
    Marca := '';
    if LaMia.Found and SameText(Info.Version, LaMia.Version) then
      Marca := MsgText(SL_DISC_LA_DEL_SERVIDOR);
    Result := Result + [MsgFmt(SL_DISC_INSTALACION_FMT, [Quien, Info.Version, Marca])];
  end;
  if not LaMia.Found then
    Exit; // no arranca: lo dice ExigeElDelphiDelServidor
  if ServerDelphiVersion <> '' then
    Porque := MsgText(SL_DISC_POR_CLAVE)
  else
    Porque := MsgText(SL_DISC_POR_DEFECTO);
  Result := Result + [MsgFmt(SL_DISC_USA_FMT, [NombreConVersion(LaMia), Porque])];
  // el update que declara el operador: hoy no decide nada (prevision)
  if ServerDelphiUpdate <> '' then
    Result := Result + [MsgFmt(SL_DISC_UPDATE_DECLARADO_FMT, [ServerDelphiUpdate])]
  else
    Result := Result + [MsgText(SL_DISC_UPDATE_SIN_DECLARAR)];
end;

function VariablesDeRsVars(const AInfo: TRadStudioInfo): TArray<string>;
var
  Puestas: TStringList; // NOMBRE=valor, en orden; la ultima de un nombre manda
  L, Nombre: string;
  P: Integer;

  // %VAR% como cmd en un .bat: lo puesto antes en el fichero, si no el
  // entorno del proceso, si no vacio; %% es un %
  function Expande(const S: string): string;
  var
    I, J, K: Integer;
    N: string;
  begin
    Result := '';
    I := 1;
    while I <= Length(S) do
    begin
      if S[I] <> '%' then
      begin
        Result := Result + S[I];
        Inc(I);
        Continue;
      end;
      J := PosEx('%', S, I + 1);
      if J = 0 then
      begin
        Result := Result + Copy(S, I, MaxInt);
        Break;
      end;
      N := Copy(S, I + 1, J - I - 1);
      if N = '' then
        Result := Result + '%'
      else
      begin
        K := Puestas.IndexOfName(N);
        if K >= 0 then
          Result := Result + Puestas.ValueFromIndex[K]
        else
          Result := Result + GetEnvironmentVariable(N);
      end;
      I := J + 1;
    end;
  end;

begin
  Result := nil;
  if not AInfo.Found or not FileExists(AInfo.RsVarsBat) then
    Exit;
  Puestas := TStringList.Create;
  try
    try
      for var Linea in LineasDelTexto(LeeTexto(AInfo.RsVarsBat, [ltIde])) do
      begin
        L := Linea.Trim.TrimLeft(['@']).Trim;
        if not StartsText('SET ', L) then
          Continue;
        L := L.Substring(4).Trim;
        P := L.IndexOf('=');
        if P <= 0 then
          Continue;
        Nombre := L.Substring(0, P).Trim;
        var Valor := Expande(L.Substring(P + 1));
        var K := Puestas.IndexOfName(Nombre);
        if K >= 0 then
          Puestas.Delete(K);
        Puestas.Add(Nombre + '=' + Valor);
      end;
    except
      Exit(nil); // un rsvars que no se lee: quien llama lo dice
    end;
    Result := Puestas.ToStringArray;
  finally
    Puestas.Free;
  end;
end;

function BdsCommonDir(const AInfo: TRadStudioInfo): string;
const
  NOMBRE = 'BDSCOMMONDIR=';
begin
  // de EL lector de rsvars.bat; '' si no se lee: quien llama quita la entrada
  Result := '';
  for var V in VariablesDeRsVars(AInfo) do
    if StartsText(NOMBRE, V) then
      Result := V.Substring(Length(NOMBRE)).Trim;
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

function ClaveDelIde(const AVersion, ASubKey: string): string;
begin
  Result := 'SOFTWARE\Embarcadero\BDS';
  if AVersion <> '' then
    Result := Result + '\' + AVersion;
  if ASubKey <> '' then
    Result := Result + '\' + ASubKey;
end;

function IdeLibraryPlatforms(const AVersion: string): TArray<string>;
begin
  Result := IdeSubclaves(AVersion, 'Library');
end;

function IdeSubclaves(const AVersion, ASubKey: string): TArray<string>;
var
  Reg: TRegistry;
  Keys: TStringList;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(ClaveDelIde(AVersion, ASubKey)) then
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
      if not Reg.OpenKeyReadOnly(ClaveDelIde(AVersion, ASubKey)) then
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
    Key := ClaveDelIde(AVersion, ASubKey);
    if Reg.OpenKeyReadOnly(Key) and Reg.ValueExists(AValueName) then
      try
        Result := Reg.ReadString(AValueName);
      except
        Result := ''; // un valor que no es texto: no es el dato que se pide
      end;
  finally
    Reg.Free;
  end;
end;

const
  PREFIJO_SDK_POR_DEFECTO = 'Default_';

function ValorDeSdkPorDefecto(const APlat: string): string;
begin
  Result := PREFIJO_SDK_POR_DEFECTO + APlat;
end;

function PlataformaDeValorDeSdk(const AValor: string; out APlat: string): Boolean;
begin
  Result := AValor.StartsWith(PREFIJO_SDK_POR_DEFECTO, True) and
    (Length(AValor) > Length(PREFIJO_SDK_POR_DEFECTO));
  APlat := '';
  if Result then
    APlat := AValor.Substring(Length(PREFIJO_SDK_POR_DEFECTO));
end;

const
  // la notificacion no muere con el hilo que la pidio (Windows 8+): aqui cada
  // peticion es un hilo, y sin esto el evento se senalaba al acabar el que
  // armo (medido el 21-oct-2026)
  REG_NOTIFY_THREAD_AGNOSTIC = $10000000;

{ Arma (o rearma) la vigilancia: Windows senalara el evento al siguiente
  cambio de un valor o de una subclave, en todo el arbol. LA llamada a
  RegNotifyChangeKeyValue de la casa (test_paisaje). }
function ArmaVigia(const AVigia: TVigiaDeClave): Boolean;
begin
  Result := RegNotifyChangeKeyValue(HKEY(AVigia.Clave), True,
    REG_NOTIFY_CHANGE_NAME or REG_NOTIFY_CHANGE_LAST_SET or REG_NOTIFY_THREAD_AGNOSTIC,
    THandle(AVigia.Evento), True) = ERROR_SUCCESS;
end;

function VigilaClave(ARaiz: NativeUInt; const ARuta: string): TVigiaDeClave;
var
  H: HKEY;
begin
  Result := Default(TVigiaDeClave);
  if RegOpenKeyEx(HKEY(ARaiz), PChar(ARuta), 0, KEY_NOTIFY, H) <> ERROR_SUCCESS then
    Exit;
  Result.Clave := H;
  Result.Evento := CreateEvent(nil, True, False, nil); // manual: se baja al leerlo
  if (Result.Evento = 0) or not ArmaVigia(Result) then
    SueltaVigia(Result);
end;

function VigilaClaveDelIde(const AVersion, ASubKey: string): TVigiaDeClave;
begin
  Result := VigilaClave(HKEY_CURRENT_USER, ClaveDelIde(AVersion, ASubKey));
end;

function VigiasDeLaBiblioteca(const AVersion: string): TArray<TVigiaDeClave>;
begin
  Result := [VigilaClaveDelIde(AVersion, 'Library'),
    VigilaClaveDelIde(AVersion, 'Environment Variables')];
end;

function CambioLaClave(var AVigia: TVigiaDeClave): Boolean;
begin
  Result := False;
  if AVigia.Clave = 0 then
    Exit;
  if WaitForSingleObject(THandle(AVigia.Evento), 0) <> WAIT_OBJECT_0 then
    Exit;
  ResetEvent(THandle(AVigia.Evento));
  // rearmada ANTES de contestar; una clave que ya no se deja vigilar
  // (borrada) se suelta, y este cambio se contesta igual
  if not ArmaVigia(AVigia) then
    SueltaVigia(AVigia);
  Result := True;
end;

function CambioAlgunaClave(var AVigias: TArray<TVigiaDeClave>): Boolean;
begin
  Result := False;
  // todas, no hasta la primera: cada una consume su senal y se rearma
  for var I := 0 to High(AVigias) do
    if CambioLaClave(AVigias[I]) then
      Result := True;
end;

procedure SueltaVigia(var AVigia: TVigiaDeClave);
begin
  if AVigia.Clave <> 0 then
    RegCloseKey(HKEY(AVigia.Clave));
  if AVigia.Evento <> 0 then
    CloseHandle(THandle(AVigia.Evento));
  AVigia := Default(TVigiaDeClave);
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

function RutaDePerfil(const AVersion, AName: string): string;
begin
  Result := TPath.Combine(IdeProfilesDir(AVersion), AName.Trim + '.profile');
end;

function NombreDePerfil(const APath: string): string;
begin
  Result := TPath.GetFileNameWithoutExtension(APath);
end;

function PerfilesDelIde(const AVersion: string): TArray<string>;
var
  Dir: string;
  L: TStringList;
begin
  Result := nil;
  Dir := IdeProfilesDir(AVersion);
  if not TDirectory.Exists(Dir) then
    Exit;
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := False;
    for var F in TDirectory.GetFiles(Dir, '*.profile') do
      L.Add(NombreDePerfil(F));
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function PerfilDelIde(const AVersion, APedido: string): string;
begin
  Result := '';
  for var P in PerfilesDelIde(AVersion) do
    if SameText(P, APedido.Trim) then
      Exit(P);
end;

function PerfilConSuNombre(const AVersion, APedido: string): string;
begin
  Result := PerfilDelIde(AVersion, APedido);
  if Result = '' then
    Result := APedido.Trim;
end;

function SdksDelIde(const AVersion: string): TArray<string>;
var
  Dir: string;
  L: TStringList;
begin
  Result := nil;
  Dir := IdeProfilesDir(AVersion);
  if not TDirectory.Exists(Dir) then
    Exit;
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := False;
    for var F in TDirectory.GetFiles(Dir, '*.sdk') do
      L.Add(F);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function NombreDeSdk(const ANombre: string): string;
begin
  Result := ANombre.Trim;
  if not Result.ToLower.EndsWith('.sdk') then
    Result := Result + '.sdk';
end;

function NombreSinSdk(const ANombreSdk: string): string;
begin
  Result := ANombreSdk.Trim;
  if Result.ToLower.EndsWith('.sdk') then
    SetLength(Result, Length(Result) - Length('.sdk'));
end;

function RutaDeSdk(const AVersion, ANombre: string): string;
begin
  Result := TPath.Combine(IdeProfilesDir(AVersion), NombreDeSdk(ANombre));
end;

function CarpetaDeSdk(const AVersion, ANombre: string): string;
begin
  Result := TPath.Combine(IdeSdksDir(AVersion), NombreDeSdk(ANombre));
end;

function SysrootDeSdk(const AVersion, AXml: string): string;
begin
  Result := TagValue(AXml, 'Profile_sysroot');
  if Result.Contains('$(BDSPLATFORMSDKSDIR)') then
    Result := Result.Replace('$(BDSPLATFORMSDKSDIR)', IdeSdksDir(AVersion),
      [rfIgnoreCase]);
end;

function CamposDePerfil(const AXml: string): TCamposDePerfil;
begin
  Result.Host := TagValue(AXml, 'Profile_host');
  Result.Puerto := TagValue(AXml, 'Profile_port');
  Result.Plataforma := TagValue(AXml, 'Profile_platform');
  Result.Password := TagValue(AXml, 'Profile_password');
end;

function HostDePerfil(const AVersion, AName: string; out AMotivo: string): string;
var
  Ruta, Xml: string;
begin
  AMotivo := '';
  Result := '';
  Ruta := RutaDePerfil(AVersion, AName);
  if not TFile.Exists(Ruta) then
  begin
    AMotivo := MsgFmt(SR_PROFILE_NO_EXISTE_FMT, [AName.Trim]);
    Exit;
  end;
  try
    Xml := LeeTexto(Ruta, [ltIde]);
  except
    AMotivo := MsgFmt(SR_PROFILE_NO_LEIDO_FMT, [AName.Trim]);
    Exit;
  end;
  Result := CamposDePerfil(Xml).Host;
  if Result = '' then
    AMotivo := MsgFmt(SR_PROFILE_SIN_HOST_FMT, [AName.Trim]);
end;

function HostDePerfil(const AVersion, AName: string): string;
var
  Ignorado: string;
begin
  Result := HostDePerfil(AVersion, AName, Ignorado);
end;

function PlataformaDePerfil(const AVersion, AName: string): string;
var
  Ruta: string;
begin
  Result := '';
  Ruta := RutaDePerfil(AVersion, AName);
  if not TFile.Exists(Ruta) then
    Exit;
  try
    Result := CamposDePerfil(LeeTexto(Ruta, [ltIde])).Plataforma.Trim;
  except
    Result := ''; // un .profile que no se lee no es de ninguna plataforma
  end;
end;

function PerfilesDePlataforma(const AVersion, APlatform: string): TArray<string>;
var
  Sistema: TSistemaDePlataforma;
begin
  Result := nil;
  Sistema := SistemaDelPAServer(APlatform);
  if Sistema = spDesconocido then
    Exit;
  for var P in PerfilesDelIde(AVersion) do
    if SistemaDePlataforma(PlataformaDePerfil(AVersion, P)) = Sistema then
      Result := Result + [P];
end;

function PerfilQueNoSirve(const AVersion, AProfile, APlatform: string): string;
var
  Sirven: TArray<string>;
begin
  Sirven := PerfilesDePlataforma(AVersion, APlatform);
  if MatchText(AProfile.Trim, Sirven) then
    Exit('');
  Result := MsgFmt(SR_CONFIG_PROFILE_OTRO_SISTEMA_FMT, [AProfile.Trim,
    ONinguno(PlataformaDePerfil(AVersion, AProfile)), APlatform,
    ONinguno(string.Join(', ', Sirven))]);
end;

function ProfileHostDenied(const AProfName: string): string;
var
  Info: TRadStudioInfo;
  Host, Motivo: string;
begin
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(MsgText(SR_PROFILE_NO_DELPHI));
  Host := HostDePerfil(Info.Version, AProfName, Motivo);
  if Motivo <> '' then
    Exit(Motivo); // falla cerrado: no existe / no se lee / sin host
  Result := ProbeHostDenied(Host);
end;

function SysrootsRegistrados(const AVersion: string): TArray<string>;
begin
  Result := nil;
  // por EL lector de las subclaves y el de un valor (IdeConfigValue: '' si no
  // esta o no es texto; una entrada sin SystemRoot no dice nada). Aqui habia
  // otra copia del bucle, y con PlatformSDKs abierta la clave de cada SDK
  // salia relativa a ella y no se encontraba nunca (medido en la RTL el
  // 9-oct-2026)
  for var K in IdeSubclaves(AVersion, 'PlatformSDKs') do
  begin
    var Raiz := IdeConfigValue(AVersion, 'PlatformSDKs\' + K, 'SystemRoot');
    if Raiz <> '' then
      Result := Result + [Raiz];
  end;
end;

function IdeSdksDir(const AVersion: string): string;
var
  Vars: TStringList;
  Raiz: string;
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
  for Raiz in SysrootsRegistrados(AVersion) do
    // solo sirve el que apunte a una carpeta <algo>.sdk: los SDK de
    // Android viven en el CatalogRepository, que es otra cosa
    if not Raiz.Contains('$(') and
       SameText(NombreDeSdk(TPath.GetFileName(PrefijoSinBarra(Raiz))),
         TPath.GetFileName(PrefijoSinBarra(Raiz))) then
      Exit(SinBarraFinal(TPath.GetDirectoryName(PrefijoSinBarra(Raiz))));
  // 3. el default documentado. UNICO literal, y aqui.
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    TPath.GetDocumentsPath, 'Embarcadero'), 'Studio'), 'SDKs');
end;

{ Expands $(MACRO) against the IDE's own macro table (plus the few values
  that live outside it), repeatedly, since macros nest. Case-insensitive. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;
var
  Pass, I: Integer;
  Name: string;
begin
  Result := AText;
  for Pass := 1 to 4 do
  begin
    if not Result.Contains('$(') then
      Break;
    for I := 0 to AVars.Count - 1 do
    begin
      Name := AVars.Names[I];
      if Name <> '' then
        Result := Result.Replace('$(' + Name + ')', AVars.ValueFromIndex[I],
          [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
end;

procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);
var
  UserDocs, CommonDocs: string;
begin
  // The IDE's own macro table is authoritative: it carries
  // $(BDSCatalogRepositoryAllUsers), where the GetIt packages live
  // (FmxLinux, Android SDKs, PAServer installers). Without it those
  // paths were silently dropped - measured 2026-08-19.
  IdeEnvironmentVars(AInfo.Version, ADest);
  // Values that are NOT in that key (authoritative from rsvars.bat /
  // the install itself), added without overwriting the IDE's own.
  if ADest.Values['BDS'] = '' then
    ADest.Values['BDS'] := PrefijoSinBarra(AInfo.RootDir);
  if ADest.Values['BDSLIB'] = '' then
    ADest.Values['BDSLIB'] := PrefijoSinBarra(AInfo.RootDir) + '\lib';
  UserDocs := BdsUserDir(AInfo);
  if (UserDocs <> '') and (ADest.Values['BDSUSERDIR'] = '') then
    ADest.Values['BDSUSERDIR'] := UserDocs;
  CommonDocs := BdsCommonDir(AInfo);
  if (CommonDocs <> '') and (ADest.Values['BDSCOMMONDIR'] = '') then
    ADest.Values['BDSCOMMONDIR'] := CommonDocs;
  // Per-user catalog repository: sibling of the common one, under the
  // user's own documents root (the IDE exposes only the AllUsers one).
  if (ADest.Values['BDSCatalogRepository'] = '') and (UserDocs <> '') then
    ADest.Values['BDSCatalogRepository'] :=
      IncludeTrailingPathDelimiter(UserDocs) + 'CatalogRepository';
  // ...y el de todos, por si el IDE no lo trae (lo tenia solo el lector de
  // los ajustes del motor: una tabla, no dos)
  if (ADest.Values['BDSCatalogRepositoryAllUsers'] = '') and (CommonDocs <> '') then
    ADest.Values['BDSCatalogRepositoryAllUsers'] :=
      IncludeTrailingPathDelimiter(CommonDocs) + 'CatalogRepository';
end;

function IdePlatformLibraryPaths(const AInfo: TRadStudioInfo; const APlatform: string;
  const AValor: string; const AConfig: string): TArray<string>;
var
  Vars, List: TStringList;
  Item, Expanded: string;
begin
  Result := nil;
  if not AInfo.Found then
    Exit;
  Vars := TStringList.Create;
  List := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    Vars.Values['Platform'] := APlatform;
    if AConfig <> '' then
      Vars.Values['Config'] := AConfig;
    // expandido ANTES de partir, como los ajustes del motor: un macro que
    // expande a una lista era UN trozo con ';' dentro (revisor C, 21-oct-2026);
    // EL troceador, el de la puerta del build (TrozosDeLista)
    for Item in TrozosDeLista(ExpandIdeMacros(IdeConfigValue(AInfo.Version, 'Library\' + APlatform, AValor), Vars)) do
    begin
      Expanded := Item;
      if (Expanded = '') or Expanded.Contains('$(') or
         not TPath.IsPathRooted(Expanded) then
        Continue;
      try
        Expanded := PrefijoSinBarra(TPath.GetFullPath(Expanded));
      except
        Continue;
      end;
      if List.IndexOf(Expanded) < 0 then
        List.Add(Expanded);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
    Vars.Free;
  end;
end;

function ComponentRootOf(const APath: string): string;
begin
  Result := TPath.GetDirectoryName(PrefijoSinBarra(APath));
  if (Length(Result) <= 3) or (TPath.GetDirectoryName(Result) = '') then
    Result := '';
end;

initialization
  GDelphiCandado := TObject.Create;

finalization
  GDelphiCandado.Free;

end.
