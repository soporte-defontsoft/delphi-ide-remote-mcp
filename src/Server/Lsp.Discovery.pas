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

const
  { La plataforma de los paquetes del IDE que carga lo nuestro: los BPL de su bin
    (bin\, el IDE de 32 bits: el mapa de paquetes de Lsp.PackageMap) y los que
    cargan los ayudantes, de 32 bits como el (los de Lsp.FormRender). Se escribia
    a mano en los dos (D12b de la 1.29). }
  PLATAFORMA_DE_LOS_PAQUETES_DEL_IDE = 'Win32';

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
{ Si la clave ASubKey de la configuracion del IDE de esa version existe: lo
  contesta EL REGISTRO (KeyExists), que compara los nombres con la tabla de
  mayusculas del sistema. Buscar el nombre en IdeSubclaves con MatchText lo
  juzgaba el idioma del usuario, que junta nombres que el registro separa
  (V101 de la 1.23.1, de la pasada del paisaje del diff). }
function IdeExisteSubclave(const AVersion, ASubKey: string): Boolean;

{ Generic reader of the IDE's per-user configuration (HKCU\...\BDS\<ver>\...).
  ASubKey is relative to the version key (e.g. 'Editor', 'PlatformSDKs',
  'Environment Variables'); '' when the key or value does not exist. The
  building block for every future IDE setting we need (Android/macOS SDKs,
  deployment, etc.) - never compose registry paths by hand elsewhere. Un
  valor que no es texto tambien es '' (ReadString lanzaba; SdkPorDefectoDelIde
  lo leia aparte por eso, P7 de la revision de Opus 5.5). }
function IdeConfigValue(const AVersion, ASubKey, AValueName: string): string;
{ El nombre del valor con lo que el IDE tiene por defecto para APlat
  ('Default_' + APlat) y su inversa: el compositor y el lector. El mismo en
  dos claves: PlatformSDKs (el SDK del SDK Manager: los Default_ que ensena
  delphi_paserver profiles) y RemoteProfiles (el perfil que el Project
  Manager ensena y con el que despliega el IDE, UNO por plataforma para
  todos sus proyectos: medido en el IDE con David el 24-oct-2026). Estaba a
  mano en el build y en paserver. }
function ValorPorDefectoDePlataforma(const APlat: string): string;
function PlataformaDeValorPorDefecto(const AValor: string; out APlat: string): Boolean;

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
  compilaban con ellas). Una clave que NO existe (aun, o ya no) se vigila
  desde su primer ancestro que si: su nacimiento es un cambio, y desde ahi se
  vigila ella (la primera redefinicion de BDSPLATFORMSDKSDIR o el primer SDK
  no se veian hasta reiniciar: el vigia quedaba vacio para siempre; revisor
  de la 1.27). Clave = 0 es "sin vigia" (ni un ancestro se deja abrir):
  CambioLaClave contesta siempre False y lo cacheado vive lo que el proceso,
  como hasta la 1.21.4. Medido con una clave de prueba
  (sonda del 21-oct-2026, y LspTests.Vigia): no se senala sola; un cambio en
  una clave hermana no la senala; dos cambios seguidos sin rearme entre
  medias dejan uno latente que sale al siguiente rearme (una recarga de mas,
  inofensiva); y sin REG_NOTIFY_THREAD_AGNOSTIC el evento se senalaba al
  morir el hilo que armo - aqui cada peticion es un hilo. }
type
  TVigiaDeClave = record
    Clave: NativeUInt;   // la clave abierta con KEY_NOTIFY (0 = sin vigia): la
                         // vigilada o, si no existe, su primer ancestro
    Evento: NativeUInt;  // el evento (manual) que Windows senala
    Raiz: NativeUInt;    // la vigilada, por su raiz y su ruta: para abrirla
    Ruta: string;        // cuando nazca
    EnEspera: Boolean;   // Clave es el ancestro: se espera a que nazca
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
{ Los vigias de lo que compone la CARPETA DE LOS SDK (IdeSdksDir): las
  Environment Variables, donde el operador la redefine (paso 1), y
  PlatformSDKs, de donde sale cuando no (paso 2). Para quien la cachea (los
  lugares del IDE, Lsp.Lugares): vivia lo que el proceso (B9 del revisor del
  paisaje de la 1.27), como la biblioteca hasta la 1.21.4. }
function VigiasDeLaCarpetaDeSdks(const AVersion: string): TArray<TVigiaDeClave>;
{ El vigia de la clave Editor del IDE, donde vive su codificacion por defecto
  (IdeDefaultUtf8: lo cachea Lsp.Deteccion.IdeWantsUtf8). }
function VigiasDelEditor(const AVersion: string): TArray<TVigiaDeClave>;
{ Si Windows senalo el evento desde la ultima pregunta: True UNA vez por
  cambio, y REARMADA antes de contestar, para que un cambio que llegue
  mientras quien pregunta recarga salga en la siguiente pregunta. Sin vigia,
  False. CambioAlgunaClave pregunta (y rearma) a TODAS las de una lista. }
function CambioLaClave(var AVigia: TVigiaDeClave): Boolean;
function CambioAlgunaClave(var AVigias: TArray<TVigiaDeClave>): Boolean;
{ Cierra la clave y el evento; queda sin vigia (dos veces no hace nada). }
procedure SueltaVigia(var AVigia: TVigiaDeClave);

type
  { Los vigias de una cache, de la version de la instalacion activa: los de
    arriba (VigiasDeLaBiblioteca, VigiasDeLaCarpetaDeSdks, VigiasDelEditor). }
  TArmaVigias = reference to function(const AVersion: string): TArray<TVigiaDeClave>;

  { LA cache que vigila claves del IDE (C30 de la 1.28: el protocolo estaba
    escrito tres veces - la zona de biblioteca y los lugares del IDE en
    Lsp.Lugares, la codificacion por defecto en Lsp.Patch): los vigias se
    arman ANTES de la primera lectura, para que un cambio que llegue mientras
    se lee salga en la siguiente pregunta, y toca cargar si nunca se cargo o si
    Windows dijo que alguna clave cambio (consumida y rearmada). Quien la usa la
    pregunta bajo SU candado y pone Cargada al acabar de cargar. Sin instalacion
    no hay vigias: lo cargado vive lo que el proceso. }
  TCacheVigilada = record
    Cargada: Boolean;
    Vigias: TArray<TVigiaDeClave>;
    function TocaCargar(const AArma: TArmaVigias): Boolean;
    { Cierra los vigias (al acabar el proceso). }
    procedure Suelta;
  end;

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
{ EL sysroot que nombra el texto de un .sdk (Profile_sysroot), con las macros
  del IDE de ESA version resueltas (ConMacrosDelIde): '' si no lo nombra; con
  una macro que el IDE no conoce, vuelve con ella (quien mire el disco, que lo
  compruebe). Lo componian a mano el escaner de sysroots mezclados, la ficha
  de profiles y reseat-sdk, y la puerta de leer iba a por la cuarta. }
function SysrootDeSdk(const AVersion, AXml: string): string;
{ ATexto con las $(...) del IDE de AVersion expandidas por EL expansor
  (Lsp.Dproj.ExpandeMacros) con LA tabla (IdeMacroVars: la del IDE, sus Environment
  Variables, $(BDSPLATFORMSDKSDIR)...); lo que no conoce queda como esta, y
  sin esa instalacion, todo. Lo hacian a mano el sysroot de un .sdk, los
  enlaces de un SDK (una macro) y los paquetes del renderizador (tres): forma
  21 del revisor del paisaje de la 1.26. }
function ConMacrosDelIde(const AVersion, ATexto: string): string;
{ LA tabla de macros del IDE de AVersion (IdeMacroVars de esa instalacion) en
  ADest; vacia sin esa instalacion. La de ConMacrosDelIde, para quien parte una
  lista con CarpetasDeUnaLista: los enlaces de un SDK la partian a mano (C8 del
  revisor del paisaje del cierre de la 1.26). }
procedure TablaDeMacrosDelIde(const AVersion: string; ADest: TStrings);
{ LA carpeta de la biblioteca compilada del IDE para APlat, como la nombran su
  Library Path y msbuild: $(BDSLIB)\<plat>\release, con $(BDSLIB) de SU tabla
  (IdeMacroVars: el operador la puede redefinir en Environment Variables). La
  componian a mano con la raiz del IDE los ajustes del motor y el mapa de
  paquetes, y con BDSLIB redefinida eran otra carpeta (forma 20 del revisor del
  paisaje de la 1.26). }
function LibDelIde(const AInfo: TRadStudioInfo; const APlat: string): string;
{ Las carpetas de un sysroot donde vive su libc.so.6: las de la familia de
  Debian, las de la de Red Hat, juntas. Las tenian escritas VersionDeGlibc y los
  dos que miran si esta mezclado (P8 del revisor). }
function CarpetasDeLibc: TArray<string>;
{ Dos distros dentro del mismo sysroot: el arbol de Debian y el de Red Hat a la
  vez, que es lo que dejaba el get-sdk de antes de 2026-09-20. DOS libc.so.6, uno
  en cada arbol: la unica senal fiable de que dos maquinas escribieron en la
  misma carpeta. Que existan a la vez /lib64 y /usr/lib/x86_64-linux-gnu NO lo
  es: un Ubuntu trae /lib64 con el cargador dentro y nada mas, y mirando
  carpetas se acusaba de mezcla a un sysroot limpio (medido 2026-09-20). }
function SysrootMezclado(const ASysRoot: string): Boolean;

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

{ EL lector de los campos de un perfil QUE EL IDE LISTA, de su fichero (el que
  compone RutaDePerfil, por FicheroDePerfilListado) y por la puerta del IDE:
  lpLeido y ACampos; lpNoListado si el IDE no lo lista o su fichero no esta;
  lpIlegible si no se lee, con el porque en AFallo. Sin textos de nadie: cada
  llamador dice lo suyo (CamposDePerfilListado, los de la puerta de
  RemoteHosts; delphi_paserver, los suyos). add-profile, get-sdk y reseat lo
  leian cada uno a mano (la deuda de B12 de la 1.28). }
type
  TLecturaDePerfil = (lpLeido, lpNoListado, lpIlegible);
function LeeCamposDePerfil(const AVersion, AName: string; out ACampos: TCamposDePerfil;
  out AFallo: string): TLecturaDePerfil;

{ Los campos de un perfil QUE EL IDE LISTA (LeeCamposDePerfil) con los motivos
  de la puerta de RemoteHosts: True y ACampos, o False y AMotivo (PAS-053 no
  existe / PAS-054 no se lee). HostDePerfil y PlataformaDePerfil lo leian cada
  una a mano, y test-connection necesita el host y el puerto del perfil que no
  conecto (B12c de la 1.28). }
function CamposDePerfilListado(const AVersion, AName: string; out ACampos: TCamposDePerfil;
  out AMotivo: string): Boolean;

{ EL host (Profile_host) de un perfil, leido del MISMO fichero que compone
  RutaDePerfil, y solo de un perfil que el IDE LISTA (PerfilDelIde: lo que
  no esta en la lista no existe). La version con AMotivo dice por que no hay
  host (no existe / no se lee / sin Profile_host): la puerta niega con ese
  motivo; quien solo quiere el host usa la otra. '' si no hay. }
function HostDePerfil(const AVersion, AName: string; out AMotivo: string): string; overload;
function HostDePerfil(const AVersion, AName: string): string; overload;

{ La plataforma para la que se creo un perfil del IDE (su Profile_platform:
  Linux64, Win64, OSX64...), leida del MISMO fichero que compone RutaDePerfil,
  de un perfil que el IDE lista; '' si no esta, no existe o no se lee. El
  nombre del perfil no significa nada. }
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

{ '' si esta sesion puede ver (AActua=False) o actuar en el escritorio de la
  maquina del perfil AProfName: DesktopHostAllowed (Lsp.Settings) con el host
  leido del perfil. Falla CERRADO, como ProfileHostDenied. La llama delphi_desktop
  (V90 de la 1.25). }
function ProfileDesktopDenied(const AProfName: string; AActua: Boolean): string;

{ Where THIS installation keeps the platform sysroots - the folder the IDE
  calls $(BDSPLATFORMSDKSDIR), with one <name>.sdk subfolder per SDK.

  It is asked to the install, never composed by hand, because a machine can
  host two or three Delphi versions side by side and each one answers for
  itself: (1) the IDE's own Environment Variables of that version, where an
  operator's override lives, its macros expanded by the IDE's table; (2)
  failing that, the SDK Manager entries of that version - the parent of any
  sysroot already registered IS the folder; (3) and only if neither exists,
  the documented default, whose literal lives HERE and nowhere else.
  It READS the IDE's table (IdeMacroVars), which asks (2) and (3) when the
  operator did not redefine it, or redefined it with a macro the table does
  not resolve: the table kept that text and this function fell to another
  folder, two answers (A5 de la 1.27). }
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

{ Los .bpl (solo el nombre, como BplFile) que el IDE de 32 bits tiene
  desactivados: los de SU lista, sin la x64 que IdeKnownPackages junta para
  listar. Lo que no debe cargar quien hace de ese IDE (el renderizador). }
function IdeBplsDesactivados32(const AVersion: string): TArray<string>;
{ Si el valor de una clave de paquetes del IDE (la ruta de un .bpl) es uno de los
  de esa lista: por el nombre del fichero, que el registro no escribe igual la
  misma ruta, y por LA clave de una ruta (P22 del revisor: aqui se comparaba
  con el pliegue del idioma y en IdeKnownPackages con esta). }
function EsBplDesactivado(const AValor: string; const ADesactivados: TArray<string>): Boolean;

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

{ LO QUE EL BUILD VE DE FUERA del .dproj, como en el IDE: las variables de
  rsvars.bat y, encima, las del IDE (IdeMacroVars: $(BDSLIB), $(BDSBIN),
  $(BDSUSERDIR), los catalogos, $(BDSPLATFORMSDKSDIR) y lo que el operador
  redefine en Tools > Options > Environment Variables). El IDE las pone en el
  entorno de su build y el cuerpo del .dproj las ve con los valores de esa
  tabla (medido el 3-nov-2026 con una sonda compilada en el IDE); nuestro
  msbuild solo tenia rsvars.bat y en su cuerpo valian vacio: add-searchpath
  aceptaba $(BDSLIB)\$(Platform)\release y el build lo negaba (A2 de la
  1.27). Una que se queda con una macro sin resolver no va (la redefinicion
  de PATH del IDE lleva $(PATH)): msbuild la leeria como texto, y queda la de
  rsvars.bat o la del entorno. Nombre=valor; las vacias de rsvars.bat
  (FrameworkSDKDir=) se quedan: msbuild la recibe quitada. EL lector de la
  tabla del build: el entorno de msbuild, la puerta y add-searchpath. }
function VariablesDelBuild(const AInfo: TRadStudioInfo): TArray<string>;

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

{ ...lo mismo a partir de lo que el IDE tiene en sus Environment Variables, que
  ADest ya trae (IdeMacroVars lo lee del registro): lo nuestro sin pisarlo y lo
  anidado resuelto. Aparte para que una prueba le de una redefinicion sin tocar
  el registro del IDE (A5 de la 1.27). }
procedure CompletaTablaDelIde(const AInfo: TRadStudioInfo; ADest: TStrings);

{ Las carpetas de los catalogos de GetIt de una instalacion, la de todos y la
  del usuario, de LA tabla (IdeMacroVars) y por EL resolutor: solo una
  completa (un "\x" o un "X:y" se resolvian contra el PROCESO del servidor),
  sin repetir. La zona de lectura (Lsp.Lugares) y los instaladores de PAServer
  componian cada uno la lista, y PAServer miraba el valor crudo (revisor del
  paisaje del cierre de la 1.26). }
function CatalogosDelIde(const AInfo: TRadStudioInfo): TArray<string>;

{ La tabla de macros con que se lee una ruta de UN proyecto: la del IDE, la
  plataforma y la configuracion del build cuando se saben ('' = sin ellas) y
  las reservadas de msbuild del .dproj (MacrosReservadasDeMsbuild). Los ajustes
  del motor y la puerta de add-searchpath la componian cada uno, y esa solo
  con la del IDE: $(Platform) o $(MSBuildProjectDirectory) eran CFG-017
  "unknown macro" con un search path que el build expande (V205 de la 1.23.1). }
procedure MacrosDelProyecto(const AInfo: TRadStudioInfo; const ADprojDir, ANombre,
  APlat, ACfg: string; ADest: TStrings);

{ The IDE's Library Search Path of ONE platform, every entry expanded to a
  real folder (macros resolved, no trailing delimiter), in registry order.
  Entries that still carry an unresolved macro or are not rooted are left
  out. What "delphi_components platform=X" shows and what the F2613 helper
  of delphi_build compares against. APlatform: la plataforma (Android) o su
  clave Library del registro (Android32): se lee la clave del IDE y
  $(Platform) vale la PLATAFORMA, la de msbuild (lib\android; V198 de la
  1.23.1: con el nombre se leia una clave que no existe, y con la clave
  salia lib\Android32). AValor es la lista del IDE que se lee:
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

{ Las carpetas de una lista (a;b;c) como las ve quien la usa: los macros
  expandidos con AVars (la tabla del IDE, IdeMacroVars) ANTES de partir - uno que
  expande a una lista son varias carpetas -, sin lo que no expande ni lo vacio,
  lo relativo contra ABaseDir ('' = solo las completas), y cada carpeta una vez,
  como las compara Windows: sin distinguir mayusculas ni la barra final. Los
  ajustes del motor y la biblioteca del IDE lo hacian cada uno, y cada uno quitaba
  repetidos a su manera (revisor del paisaje, 1-nov-2026). }
function CarpetasDeUnaLista(const ARaw, ABaseDir: string; AVars: TStrings): TArray<string>;

{ La raiz de instalacion de una carpeta que registra una biblioteca: un nivel
  por encima (X\Source -> X, X\Lib\Linux64 -> X\Lib), nunca la raiz de una
  unidad ('' entonces). La zona de biblioteca (Lsp.Lugares) y delphi_components
  la escribian cada una (depuracion de la 1.23). }
function ComponentRootOf(const APath: string): string;

{ LAS UNIDADES DE LA BIBLIOTECA que resuelve dcc: las CLAVES de sus nombres
  (ClaveDeIdentificador, sin extension, ordenadas) de los .dcu y .pas de las carpetas de la Search
  Path de Win32 y Win64 del Delphi del servidor - donde las busca el
  compilador, sin bajar a subcarpetas (FuentesBajo baja: no es la misma
  pregunta): la RTL, la VCL, FMX y los componentes registrados. EL juez de
  "ese nombre ya es de la biblioteca" (Lsp.Scaffold.BadUnitName: hasta el
  25-oct-2026 dos listas a mano, 28 unidades y 14 espacios de nombres, sin
  los componentes y con Generics.Collections colandose; V33 de la 1.23).
  Medido: 1900 .dcu en 2 ms. Se mide de nuevo cada minuto (un componente
  que se instala entra en el siguiente). Sin Delphi, vacio. }
function UnidadesDeLaBiblioteca: TArray<string>;
{ Las CLAVES de las unidades (ClaveDeIdentificador del nombre sin extension,
  ordenadas, cada una una vez) de los .dcu y .pas que hay EN cada carpeta de
  ACarpetas, sin bajar a subcarpetas: lo que dcc encuentra por su nombre en
  una carpeta que mira. EL listador: de la biblioteca (UnidadesDeLaBiblioteca)
  y de la carpeta y el search path de un proyecto (Lsp.ProjectUnits.
  ResolutorDeUnidades, V107 de la 1.23.1). Lo que no se lista no cuenta. }
function UnidadesEnCarpetas(const ACarpetas: TArray<string>): TArray<string>;
{ Si ANombre (una unidad, con sus puntos) es de AUnidades - lo que dio
  UnidadesDeLaBiblioteca -, por la MISMA clave con la que se escribieron
  (ClaveDeIdentificador: sin el idioma del usuario). EL lector: cuatro
  montaban la clave con .ToLower, que lleva el casing del idioma (con el
  turco, 'IOUtils' es 'ioutils' con la i sin punto) frente al LowerCase del
  escritor, y una unidad no ASCII no se encontraba (V98 de la 1.23.1, de la
  pasada del paisaje del diff). }
function EnLaBiblioteca(const AUnidades: TArray<string>; const ANombre: string): Boolean;

{ El anidado de la tabla de macros del IDE (IdeMacroVars), en la tabla y no en
  el texto: los valores de ANombres en AVars (las Environment Variables del IDE,
  que el operador escribe con macros dentro) con sus $(X) expandidos. }
procedure ResuelveAnidadas(AVars: TStrings; const ANombres: TArray<string>);

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
  Lsp.Puertas,
  Lsp.Settings, // ServerDelphiVersion: la version que fija el settings.ini
  Lsp.Rutas,    // RutaDesde: EL resolutor de una ruta leida
  Lsp.Pascal,
  Lsp.Lineas;

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
  if not TDirectory.Exists(BinDelIde(ARootDir)) then
    Exit;
  for F in TDirectory.GetFiles(BinDelIde(ARootDir), 'dcc32*.dll') do
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
      Exe := TPath.Combine(BinDelIde(Info.RootDir), 'DelphiLSP.exe');
      if FileExists(Exe) then
        Info.DelphiLspExe := Exe;
      Bat := TPath.Combine(BinDelIde(Info.RootDir), 'rsvars.bat');
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
      InfoDelExe(TPath.Combine(BinDelIde(Info.RootDir), 'bds.exe'), Info.Edition, Info.Build);
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
  if not FileExists(TPath.Combine(BinDelIde(ARootDir), 'bds.exe')) and
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

function VariablesDelBuild(const AInfo: TRadStudioInfo): TArray<string>;
var
  Tabla: TStringList;
begin
  Result := VariablesDeRsVars(AInfo);
  if not AInfo.Found then
    Exit;
  Tabla := TStringList.Create;
  try
    IdeMacroVars(AInfo, Tabla);
    for var I := 0 to Tabla.Count - 1 do
    begin
      var Nombre := Tabla.Names[I];
      var Valor := Tabla.ValueFromIndex[I];
      if (Nombre = '') or (Valor = '') or Valor.Contains('$(') then
        Continue;
      // la del IDE manda sobre la de rsvars.bat, como en el IDE
      for var J := High(Result) downto 0 do
        if StartsText(Nombre + '=', Result[J]) then
          Delete(Result, J, 1);
      Result := Result + [Nombre + '=' + Valor];
    end;
  finally
    Tabla.Free;
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
  // EL juez de rutas (H1 de la 1.23) y su corte: '' si no cuelga de ahi
  Result := RutaTrasladada(Common, Shared, TPath.GetDocumentsPath);
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

function IdeExisteSubclave(const AVersion, ASubKey: string): Boolean;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Result := Reg.KeyExists(ClaveDelIde(AVersion, ASubKey));
  finally
    Reg.Free;
  end;
end;

function NombreDeBpl(const AValor: string): string;
begin
  Result := TPath.GetFileName(ConBarrasDeWindows(AValor));
end;

function IdeKnownPackages(const AVersion: string): TArray<TIdePackage>;
var
  Map: TDictionary<string, TIdePackage>;
  Off: TDictionary<string, Boolean>; // a set: ClaveDeRuta(filename) -> present
  List: TList<TIdePackage>;

  // One registry key's values into Map/Off as ClaveDeRuta(filename) -> entry.
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
      FileKey := NombreDeBpl(V.Nombre);
      if FileKey = '' then
        Continue;
      if AsNames then
        Off.AddOrSetValue(ClaveDeRuta(FileKey), True)
      else if not Map.ContainsKey(ClaveDeRuta(FileKey)) then
      begin
        P.Description := V.Dato.Trim;
        if P.Description = '' then
          P.Description := FileKey;
        P.BplFile := FileKey;
        P.Disabled := False;
        Map.Add(ClaveDeRuta(FileKey), P);
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

function IdeBplsDesactivados32(const AVersion: string): TArray<string>;
begin
  Result := nil;
  for var V in IdeValoresDeClave(AVersion, 'Disabled Packages', False) do
    Result := Result + [ClaveDeRuta(NombreDeBpl(V.Nombre))];
end;

function EsBplDesactivado(const AValor: string; const ADesactivados: TArray<string>): Boolean;
begin
  Result := MatchStr(ClaveDeRuta(NombreDeBpl(AValor)), ADesactivados);
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
    if (A.Fichero = '') or RutaEnLista(A.Fichero, Vistos) then
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
  PREFIJO_POR_DEFECTO = 'Default_';

function ValorPorDefectoDePlataforma(const APlat: string): string;
begin
  Result := PREFIJO_POR_DEFECTO + APlat;
end;

function PlataformaDeValorPorDefecto(const AValor: string; out APlat: string): Boolean;
begin
  Result := AValor.StartsWith(PREFIJO_POR_DEFECTO, True) and
    (Length(AValor) > Length(PREFIJO_POR_DEFECTO));
  APlat := '';
  if Result then
    APlat := AValor.Substring(Length(PREFIJO_POR_DEFECTO));
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
var
  Filtro: DWORD;
begin
  // en espera, solo el nacimiento de una subclave del ancestro, sin su arbol:
  // lo que el IDE escribe en otras no la despierta
  if AVigia.EnEspera then
    Filtro := REG_NOTIFY_CHANGE_NAME
  else
    Filtro := REG_NOTIFY_CHANGE_NAME or REG_NOTIFY_CHANGE_LAST_SET;
  Result := RegNotifyChangeKeyValue(HKEY(AVigia.Clave), not AVigia.EnEspera,
    Filtro or REG_NOTIFY_THREAD_AGNOSTIC, THandle(AVigia.Evento), True) = ERROR_SUCCESS;
end;

// cierra la clave del vigia, no su evento
procedure SueltaClave(var AVigia: TVigiaDeClave);
begin
  if AVigia.Clave <> 0 then
    RegCloseKey(HKEY(AVigia.Clave));
  AVigia.Clave := 0;
  AVigia.EnEspera := False;
end;

{ Abre la vigilada y la arma; si no existe (aun, o ya no), arma su primer
  ancestro que exista, por el nacimiento de una subclave suya. True si quedo
  vigilando a la vigilada misma. Medido el 4-nov-2026 con una clave de prueba:
  el ancestro sin su arbol y con REG_NOTIFY_CHANGE_NAME se senala cuando nace
  una subclave suya (tambien dos tramos de una vez), y no por un valor suyo ni
  por una nieta; borrar la vigilada la senala, y rearmarla da
  ERROR_KEY_DELETED. }
function AnclaVigia(var AVigia: TVigiaDeClave): Boolean;

  function Abre(const ARuta: string; out AH: HKEY): Boolean;
  begin
    Result := RegOpenKeyEx(HKEY(AVigia.Raiz), PChar(ARuta), 0, KEY_NOTIFY, AH) = ERROR_SUCCESS;
  end;

  function Existe(const ARuta: string): Boolean;
  var
    H: HKEY;
  begin
    Result := Abre(ARuta, H);
    if Result then
      RegCloseKey(H);
  end;

var
  H: HKEY;
  R: string;
begin
  Result := False;
  SueltaClave(AVigia);
  if Abre(AVigia.Ruta, H) then
  begin
    AVigia.Clave := H;
    if ArmaVigia(AVigia) then
      Exit(True);
    SueltaClave(AVigia); // borrada entre abrirla y armarla: a su ancestro
  end;
  // el primer ancestro que existe ('' es la raiz misma)
  R := AVigia.Ruta;
  repeat
    if R = '' then
      Exit; // ni la raiz: sin vigia
    R := Copy(R, 1, LastDelimiter('\', R) - 1);
  until Abre(R, H);
  AVigia.Clave := H;
  AVigia.EnEspera := True;
  if not ArmaVigia(AVigia) then
    SueltaClave(AVigia) // no se deja vigilar: sin vigia
  // nacida entre la primera mirada y el armado: su nacimiento ya no se
  // senalara, asi que se senala aqui y la siguiente pregunta la abre
  else if Existe(AVigia.Ruta) then
    SetEvent(THandle(AVigia.Evento));
end;

function VigilaClave(ARaiz: NativeUInt; const ARuta: string): TVigiaDeClave;
begin
  Result := Default(TVigiaDeClave);
  Result.Raiz := ARaiz;
  Result.Ruta := ARuta;
  Result.Evento := CreateEvent(nil, True, False, nil); // manual: se baja al leerlo
  if Result.Evento <> 0 then
    AnclaVigia(Result);
  if Result.Clave = 0 then
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

function VigiasDeLaCarpetaDeSdks(const AVersion: string): TArray<TVigiaDeClave>;
begin
  Result := [VigilaClaveDelIde(AVersion, 'Environment Variables'),
    VigilaClaveDelIde(AVersion, 'PlatformSDKs')];
end;

function CambioLaClave(var AVigia: TVigiaDeClave): Boolean;
begin
  Result := False;
  if AVigia.Clave = 0 then
    Exit;
  if WaitForSingleObject(THandle(AVigia.Evento), 0) <> WAIT_OBJECT_0 then
    Exit;
  ResetEvent(THandle(AVigia.Evento));
  // en espera, lo que cambio es una subclave del ancestro: es un cambio solo
  // si nacio la vigilada (AnclaVigia la abre y la arma; si no, sigue esperando)
  if AVigia.EnEspera then
    Exit(AnclaVigia(AVigia));
  // rearmada ANTES de contestar; una clave que ya no se deja vigilar
  // (borrada) vuelve a esperar en su ancestro, y este cambio se contesta igual
  if not ArmaVigia(AVigia) then
    AnclaVigia(AVigia);
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

function TCacheVigilada.TocaCargar(const AArma: TArmaVigias): Boolean;
begin
  if not Cargada and (Vigias = nil) then
  begin
    var Info := DiscoverRadStudio;
    if Info.Found then
      Vigias := AArma(Info.Version);
  end;
  Result := (not Cargada) or CambioAlgunaClave(Vigias);
end;

procedure TCacheVigilada.Suelta;
begin
  for var I := 0 to High(Vigias) do
    SueltaVigia(Vigias[I]);
  Vigias := nil;
end;

function VigiasDelEditor(const AVersion: string): TArray<TVigiaDeClave>;
begin
  Result := [VigilaClaveDelIde(AVersion, 'Editor')];
end;

procedure SueltaVigia(var AVigia: TVigiaDeClave);
begin
  SueltaClave(AVigia);
  if AVigia.Evento <> 0 then
    CloseHandle(THandle(AVigia.Evento));
  AVigia := Default(TVigiaDeClave);
end;

function IdeDefaultUtf8(const AVersion: string): Boolean;
begin
  Result := SinMayusculas(IdeConfigValue(AVersion, 'Editor', 'DefaultFileFilter'))
    .Contains('utf8toutf8');
end;

function IdeProfilesDir(const AVersion: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(
    DatosDelUsuario('APPDATA'), 'Embarcadero'), 'BDS'), AVersion);
end;

function RutaDePerfil(const AVersion, AName: string): string;
begin
  Result := TPath.Combine(IdeProfilesDir(AVersion), AName.Trim + '.profile');
end;

function NombreDePerfil(const APath: string): string;
begin
  Result := TPath.GetFileNameWithoutExtension(APath);
end;

{ Los ficheros AMascara de la carpeta de perfiles del IDE, ordenados y sin
  repetidos (como los compara NTFS); vacio si no hay carpeta. LA lista de esa
  carpeta: PerfilesDelIde y SdksDelIde eran el mismo cuerpo dos veces (W2 de
  la auditoria de duplicados del 16-oct; V34 de la 1.23). }
function FicherosDePerfilesDelIde(const AVersion, AMascara: string): TArray<string>;
var
  L: TStringList;
begin
  Result := nil;
  if not TDirectory.Exists(IdeProfilesDir(AVersion)) then
    Exit;
  // como los compara NTFS (Lsp.Rutas): con el locale juntaba dos ficheros que
  // el disco separa (V105), y con CaseSensitive tambien (la eszett y "ss")
  L := TListaDeRutas.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    for var F in TDirectory.GetFiles(IdeProfilesDir(AVersion), AMascara) do
      L.Add(F);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function PerfilesDelIde(const AVersion: string): TArray<string>;
begin
  Result := FicherosDePerfilesDelIde(AVersion, '*.profile');
  for var I := 0 to High(Result) do
    Result[I] := NombreDePerfil(Result[I]);
end;

function PerfilDelIde(const AVersion, APedido: string): string;
begin
  Result := '';
  for var P in PerfilesDelIde(AVersion) do
    if SameFileName(P, APedido.Trim) then // el nombre de su fichero, como NTFS
      Exit(P);
end;

function PerfilConSuNombre(const AVersion, APedido: string): string;
begin
  Result := PerfilDelIde(AVersion, APedido);
  if Result = '' then
    Result := APedido.Trim;
end;

function SdksDelIde(const AVersion: string): TArray<string>;
begin
  Result := FicherosDePerfilesDelIde(AVersion, '*.sdk');
end;

function NombreDeSdk(const ANombre: string): string;
begin
  Result := ANombre.Trim;
  if not SinMayusculas(Result).EndsWith('.sdk') then
    Result := Result + '.sdk';
end;

function NombreSinSdk(const ANombreSdk: string): string;
begin
  Result := ANombreSdk.Trim;
  if SinMayusculas(Result).EndsWith('.sdk') then
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
  Result := ConMacrosDelIde(AVersion, TagValue(AXml, 'Profile_sysroot'));
end;

const
  LIBC_DEBIAN: array[0..1] of string = ('lib\x86_64-linux-gnu', 'usr\lib\x86_64-linux-gnu');
  LIBC_REDHAT: array[0..1] of string = ('lib64', 'usr\lib64');

function CarpetasDeLibc: TArray<string>;
begin
  Result := [LIBC_DEBIAN[0], LIBC_DEBIAN[1], LIBC_REDHAT[0], LIBC_REDHAT[1]];
end;

function SysrootMezclado(const ASysRoot: string): Boolean;

  function HayLibc(const ACarpetas: array of string): Boolean;
  begin
    Result := False;
    for var C in ACarpetas do
      if TFile.Exists(TPath.Combine(TPath.Combine(ASysRoot, C), 'libc.so.6')) then
        Exit(True);
  end;

begin
  Result := HayLibc(LIBC_DEBIAN) and HayLibc(LIBC_REDHAT);
end;

function CamposDePerfil(const AXml: string): TCamposDePerfil;
begin
  Result.Host := TagValue(AXml, 'Profile_host');
  Result.Puerto := TagValue(AXml, 'Profile_port');
  Result.Plataforma := TagValue(AXml, 'Profile_platform');
  Result.Password := TagValue(AXml, 'Profile_password');
end;

{ El fichero de un perfil QUE EL IDE LISTA, por su nombre de la lista
  (PerfilDelIde); '' si no esta. Lo que teclea el agente solo ELIGE: la ruta
  no se compone con su texto. Con un '..' en el nombre, TFile.Exists miraba
  cualquier .profile del disco, fuera de la jaula, y la negativa distinguia
  "no existe" (PAS-053) de "no se lee" (PAS-054): un oraculo de existencia
  (V8 de la 1.23, medido contra produccion con delphi_desktop). }
function FicheroDePerfilListado(const AVersion, AName: string): string;
var
  Nombre: string;
begin
  Nombre := PerfilDelIde(AVersion, AName);
  if Nombre = '' then
    Exit('');
  Result := RutaDePerfil(AVersion, Nombre);
end;

function LeeCamposDePerfil(const AVersion, AName: string; out ACampos: TCamposDePerfil;
  out AFallo: string): TLecturaDePerfil;
var
  Ruta: string;
begin
  ACampos := Default(TCamposDePerfil);
  AFallo := '';
  Ruta := FicheroDePerfilListado(AVersion, AName);
  if (Ruta = '') or not TFile.Exists(Ruta) then
    Exit(lpNoListado);
  try
    ACampos := CamposDePerfil(LeeTexto(Ruta, [ltIde]));
  except
    on E: Exception do
    begin
      AFallo := E.Message;
      Exit(lpIlegible);
    end;
  end;
  Result := lpLeido;
end;

function CamposDePerfilListado(const AVersion, AName: string; out ACampos: TCamposDePerfil;
  out AMotivo: string): Boolean;
var
  Fallo: string;
begin
  AMotivo := '';
  case LeeCamposDePerfil(AVersion, AName, ACampos, Fallo) of
    lpLeido:
      Exit(True);
    lpNoListado:
      AMotivo := MsgFmt(SR_PROFILE_NO_EXISTE_FMT, [AName.Trim]);
  else
    AMotivo := MsgFmt(SR_PROFILE_NO_LEIDO_FMT, [AName.Trim]);
  end;
  Result := False;
end;

function HostDePerfil(const AVersion, AName: string; out AMotivo: string): string;
var
  Campos: TCamposDePerfil;
begin
  Result := '';
  if not CamposDePerfilListado(AVersion, AName, Campos, AMotivo) then
    Exit;
  Result := Campos.Host;
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
  Campos: TCamposDePerfil;
  Motivo: string;
begin
  // un .profile que no existe o no se lee no es de ninguna plataforma
  if CamposDePerfilListado(AVersion, AName, Campos, Motivo) then
    Result := Campos.Plataforma.Trim
  else
    Result := '';
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
  if RutaEnLista(AProfile.Trim, Sirven) then // como NTFS, el juez de la lista
    Exit('');
  Result := MsgFmt(SR_CONFIG_PROFILE_OTRO_SISTEMA_FMT, [AProfile.Trim,
    ONinguno(PlataformaDePerfil(AVersion, AProfile)), APlatform,
    ONinguno(string.Join(', ', Sirven))]);
end;

{ El host del perfil pedido, para una puerta: '' y AHost, o la negativa. Falla
  cerrado: sin Delphi, no existe, no se lee o sin host }
function HostDelPerfilPedido(const AProfName: string; out AHost: string): string;
begin
  var Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(MsgText(SR_PROFILE_NO_DELPHI));
  AHost := HostDePerfil(Info.Version, AProfName, Result);
end;

function ProfileHostDenied(const AProfName: string): string;
var
  Host: string;
begin
  Result := HostDelPerfilPedido(AProfName, Host);
  if Result = '' then
    Result := ProbeHostDenied(Host);
end;

function ProfileDesktopDenied(const AProfName: string; AActua: Boolean): string;
var
  Host: string;
begin
  Result := HostDelPerfilPedido(AProfName, Host);
  if Result <> '' then
    Exit;
  if DesktopHostAllowed(Host, AActua) then
    Exit('');
  Result := MsgFmt(SR_DESKTOP_HOST_DENIED_FMT,
    [IfThen(AActua, MsgText(SF_DESKTOP_ACTUAR), MsgText(SF_DESKTOP_VER)), Host.Trim]);
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

{ Los pasos (2) y (3) de IdeSdksDir: los SDK que ESA version ya tiene
  registrados, o el default documentado. Los pregunta la tabla del IDE
  (CompletaTablaDelIde) cuando el operador no redefinio la carpeta, o la
  redefinio con una macro que la tabla no resuelve; IdeSdksDir lee la tabla. }
function SdksSinRedefinir(const AVersion: string): string;
var
  Raiz: string;
begin
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

function IdeSdksDir(const AVersion: string): string;
var
  Vars: TStringList;
begin
  // 1. EL lector: la tabla del IDE de ESA version, que ya resolvio lo que el
  // operador redefinio y, si no lo hizo o no se resuelve, pregunto los pasos 2
  // y 3 (SdksSinRedefinir). Leia la redefinicion aparte y caia a otra carpeta
  // que la tabla (C6 del cierre de la 1.26; A5 de la 1.27)
  Vars := TStringList.Create;
  try
    TablaDeMacrosDelIde(AVersion, Vars);
    Result := Vars.Values['BDSPLATFORMSDKSDIR'];
  finally
    Vars.Free;
  end;
  // sin esa instalacion la tabla queda vacia
  if (Result = '') or Result.Contains('$(') then
    Exit(SdksSinRedefinir(AVersion));
  Result := SinBarraFinal(Result); // (la raiz de una unidad, con su barra: se le unen nombres)
end;

{ Por NOMBRE y con memoria: un $(X) de uno de ANombres que es otro de ANombres
  se resuelve primero (recursivo), y lo demas de la tabla entra tal cual (lo
  nuestro, carpetas, como lo deja msbuild), por EL expansor y sin volver a
  mirar lo puesto; su propio nombre se queda escrito (PATH=...;$(PATH)), y en
  un ciclo el que esta en curso entra como esta. Se resuelven todos desde lo
  que dice el IDE y despues se escriben. Daba vueltas a la tabla entera, y la
  segunda volvia a mirar lo que la primera habia puesto de una carpeta nuestra
  con $( en su nombre (C19 del cierre de la 1.26). }
procedure ResuelveAnidadas(AVars: TStrings; const ANombres: TArray<string>);
var
  Hechos: TStringList;
  EnCurso: TArray<string>;

  function Resuelto(const ANombre: string): string;
  var
    LosDelIde, Usados, Pares: TArray<string>;
    Parado: Boolean;
  begin
    var K := Hechos.IndexOfName(ANombre);
    if K >= 0 then
      Exit(Hechos.ValueFromIndex[K]);
    Result := AVars.Values[ANombre];
    if not Result.Contains('$(') then
      Exit;
    // los otros nombres del IDE que usa, por EL recorrido
    LosDelIde := ANombres;
    Usados := [];
    RecorreMacros(Result,
      function(const AN: string; out AV: string): TAccionDeMacro
      begin
        if MatchText(AN, LosDelIde) and not MatchText(AN, Usados) then
          Usados := Usados + [AN];
        Result := amDeja;
      end, Parado);
    EnCurso := EnCurso + [ANombre];
    Pares := [];
    for var N in Usados do
      if not SameText(N, ANombre) and not MatchText(N, EnCurso) then
        Pares := Pares + [N + '=' + Resuelto(N)];
    SetLength(EnCurso, Length(EnCurso) - 1);
    Result := ExpandeMacros(Result, Pares + AVars.ToStringArray, ANombre);
    Hechos.Values[ANombre] := Result;
  end;

var
  Nuevos: TArray<string>;
begin
  Hechos := TStringList.Create;
  try
    EnCurso := [];
    Nuevos := [];
    for var N in ANombres do
      Nuevos := Nuevos + [Resuelto(N)];
    for var I := 0 to High(ANombres) do
      AVars.Values[ANombres[I]] := Nuevos[I];
  finally
    Hechos.Free;
  end;
end;

procedure MacrosDelProyecto(const AInfo: TRadStudioInfo; const ADprojDir, ANombre,
  APlat, ACfg: string; ADest: TStrings);
begin
  // LA tabla del build (VariablesDelBuild), la que recibe msbuild: con solo
  // la del IDE, add-searchpath aceptaba lo que el build leia de otra forma
  for var V in VariablesDelBuild(AInfo) do
    ADest.Add(V); // 'Nombre=valor', como lo lee ExpandeMacros
  // la plataforma y la configuracion, las del build; '' = no se saben: la
  // entrada se quita (rsvars.bat deja PLATFORM vacia) y la macro queda escrita
  ADest.Values['Platform'] := APlat;
  ADest.Values['Config'] := ACfg;
  for var M in MacrosReservadasDeMsbuild(ADprojDir, ANombre, ADprojDir) do
    ADest.Add(M); // 'Nombre=valor', como lo lee ExpandeMacros
end;

procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);
begin
  // The IDE's own macro table is authoritative: it carries
  // $(BDSCatalogRepositoryAllUsers), where the GetIt packages live
  // (FmxLinux, Android SDKs, PAServer installers). Without it those
  // paths were silently dropped - measured 2026-08-19.
  IdeEnvironmentVars(AInfo.Version, ADest);
  CompletaTablaDelIde(AInfo, ADest);
end;

procedure CompletaTablaDelIde(const AInfo: TRadStudioInfo; ADest: TStrings);
var
  UserDocs, CommonDocs: string;
  DelIde: TArray<string>;
begin
  // los nombres que da el IDE: sus valores los escribe el operador, con
  // macros dentro si quiere (abajo, ResuelveAnidadas)
  DelIde := [];
  for var I := 0 to ADest.Count - 1 do
    DelIde := DelIde + [ADest.Names[I]];
  // Values that are NOT in that key (authoritative from rsvars.bat /
  // the install itself), added without overwriting the IDE's own.
  if ADest.Values['BDS'] = '' then
    ADest.Values['BDS'] := PrefijoSinBarra(AInfo.RootDir);
  if ADest.Values['BDSLIB'] = '' then
    ADest.Values['BDSLIB'] := PrefijoSinBarra(AInfo.RootDir) + '\lib';
  if ADest.Values['BDSBIN'] = '' then
    ADest.Values['BDSBIN'] := BinDelIde(AInfo.RootDir); // la de Known Packages (P4)
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
  // ...y donde guarda los sysroots de sus SDK, si el operador no la redefinio
  // (una redefinida con macros dentro se resuelve abajo)
  if ADest.Values['BDSPLATFORMSDKSDIR'] = '' then
    ADest.Values['BDSPLATFORMSDKSDIR'] := SdksSinRedefinir(AInfo.Version);
  // el anidado, en la tabla y no en el texto: lo que el operador redefinio en
  // el IDE con macros dentro ($(BDSUSERDIR)\SDKs) se resuelve con la tabla
  // entera, y lo que ponemos nosotros (carpetas) se queda tal cual, como lo
  // deja msbuild. ExpandIdeMacros daba cuatro pasadas al TEXTO y volvia a
  // mirar lo insertado (C17 del cierre de la 1.26)
  ResuelveAnidadas(ADest, DelIde);
  // una redefinicion que la tabla no resuelve ($(USERPROFILE)\SDKs: una variable
  // del sistema, no del IDE) se quedaba escrita, e IdeSdksDir caia a otra
  // carpeta: dos respuestas (A5 de la 1.27). Lo que hace el IDE con ella esta SIN
  // MEDIR; la tabla da la de los pasos 2 y 3, y IdeSdksDir la lee de aqui
  if ADest.Values['BDSPLATFORMSDKSDIR'].Contains('$(') then
    ADest.Values['BDSPLATFORMSDKSDIR'] := SdksSinRedefinir(AInfo.Version);
end;

function CatalogosDelIde(const AInfo: TRadStudioInfo): TArray<string>;
var
  Vars: TStringList;
begin
  Result := [];
  Vars := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    for var Item in TArray<string>.Create(Vars.Values['BDSCatalogRepositoryAllUsers'],
      Vars.Values['BDSCatalogRepository']) do
    begin
      var Ruta := RutaDesde('', Item);
      if (Ruta <> '') and (IndiceDeRuta(Ruta, Result) < 0) then
        Result := Result + [Ruta];
    end;
  finally
    Vars.Free;
  end;
end;

function LibDelIde(const AInfo: TRadStudioInfo; const APlat: string): string;
var
  Vars: TStringList;
begin
  Vars := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    Result := ExpandeMacros('$(BDSLIB)\' + APlat + '\release', Vars.ToStringArray);
  finally
    Vars.Free;
  end;
end;

procedure TablaDeMacrosDelIde(const AVersion: string; ADest: TStrings);
var
  Info: TRadStudioInfo;
begin
  // la instalacion de ESA version: la del servidor sin volver al registro
  Info := DiscoverRadStudio;
  if not SameText(Info.Version, AVersion) then
  begin
    Info := Default(TRadStudioInfo);
    for var I in DiscoverAllRadStudios do
      if I.Found and SameText(I.Version, AVersion) then
        Info := I;
  end;
  if Info.Found then
    IdeMacroVars(Info, ADest);
end;

function ConMacrosDelIde(const AVersion, ATexto: string): string;
var
  Vars: TStringList;
begin
  Result := ATexto;
  if not Result.Contains('$(') then
    Exit;
  // sin esa instalacion la tabla queda vacia, y el texto como esta
  Vars := TStringList.Create;
  try
    TablaDeMacrosDelIde(AVersion, Vars);
    Result := ExpandeMacros(Result, Vars.ToStringArray);
  finally
    Vars.Free;
  end;
end;

{ La clave Library del IDE de una plataforma: la inversa de
  PlataformaDeClaveLibrary, entre las claves que el IDE TIENE (su registro es
  el juez); sin ninguna que case, la plataforma misma. }
function ClaveLibraryDePlataforma(const AVersion, APlatform: string): string;
begin
  for var K in IdeLibraryPlatforms(AVersion) do
    if SameText(NombreDeClaveLibrary(K), APlatform) then
      Exit(K);
  Result := APlatform;
end;

function IdePlatformLibraryPaths(const AInfo: TRadStudioInfo; const APlatform: string;
  const AValor: string; const AConfig: string): TArray<string>;
var
  Vars: TStringList;
begin
  Result := nil;
  if not AInfo.Found then
    Exit;
  Vars := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    var Plat := NombreDeClaveLibrary(APlatform);
    Vars.Values['Platform'] := Plat;
    if AConfig <> '' then
      Vars.Values['Config'] := AConfig;
    // solo las completas: un valor del registro no tiene carpeta, y "\x" o
    // "X:y" se resolvian contra el PROCESO del servidor (EL resolutor)
    for var Carpeta in CarpetasDeUnaLista(IdeConfigValue(AInfo.Version,
      'Library\' + ClaveLibraryDePlataforma(AInfo.Version, Plat), AValor), '', Vars) do
      Result := Result + [PrefijoSinBarra(Carpeta)];
  finally
    Vars.Free;
  end;
end;

function CarpetasDeUnaLista(const ARaw, ABaseDir: string; AVars: TStrings): TArray<string>;
var
  // por ClaveDeRuta, como Windows: un TStringList sin mayusculas compara con el
  // idioma y junta ss y la eszett (V82), dos carpetas para NTFS (revisor del
  // paisaje de la 1.26)
  Vistas: TDictionary<string, Boolean>;
begin
  Result := nil;
  Vistas := TDictionary<string, Boolean>.Create;
  try
    // expandido ANTES de partir: un macro que expande a una lista ($(Path), una
    // variable del entorno con dos carpetas) era UN trozo con ';' dentro, y no se
    // veian las que nombraba (revisor C, 21-oct-2026). EL troceador, el de la
    // puerta del build (TrozosDeLista)
    for var Item in TrozosDeLista(ExpandeMacros(ARaw, AVars.ToStringArray)) do
    begin
      if (Item = '') or Item.Contains('$(') then
        Continue;
      var Carpeta := RutaDesde(ABaseDir, Item);
      if Carpeta = '' then
        Continue;
      if not Vistas.ContainsKey(ClaveDeRuta(PrefijoSinBarra(Carpeta))) then
      begin
        Vistas.Add(ClaveDeRuta(PrefijoSinBarra(Carpeta)), True);
        Result := Result + [Carpeta];
      end;
    end;
  finally
    Vistas.Free;
  end;
end;

function ComponentRootOf(const APath: string): string;
begin
  Result := TPath.GetDirectoryName(PrefijoSinBarra(APath));
  if (Length(Result) <= 3) or (TPath.GetDirectoryName(Result) = '') then
    Result := '';
end;

var
  GUnidades: TArray<string>;
  GUnidadesTick: UInt64;

function UnidadesEnCarpetas(const ACarpetas: TArray<string>): TArray<string>;
var
  Vistas: TDictionary<string, Boolean>;
  Sr: TSearchRec;
  Ext: string;
begin
  Vistas := TDictionary<string, Boolean>.Create;
  try
    for var C in ACarpetas do
      if FindFirst(TPath.Combine(C, '*'), faAnyFile, Sr) = 0 then
      try
        repeat
          if (Sr.Attr and faDirectory) <> 0 then
            Continue;
          Ext := LowerCase(ExtractFileExt(Sr.Name));
          if (Ext = '.dcu') or (Ext = '.pas') then
            Vistas.AddOrSetValue(ClaveDeIdentificador(ChangeFileExt(Sr.Name, '')), True);
        until FindNext(Sr) <> 0;
      finally
        System.SysUtils.FindClose(Sr); // el de Winapi.Windows, detras en los uses, toma un THandle
      end;
    Result := Vistas.Keys.ToArray;
    TArray.Sort<string>(Result);
  finally
    Vistas.Free;
  end;
end;

function UnidadesDeLaBiblioteca: TArray<string>;
const
  VIDA_MS = 60000;
var
  Carpetas: TArray<string>;
begin
  TMonitor.Enter(GDelphiCandado);
  try
    if (GUnidadesTick <> 0) and (GetTickCount64 - GUnidadesTick < VIDA_MS) then
      Exit(GUnidades);
  finally
    TMonitor.Exit(GDelphiCandado);
  end;
  Carpetas := nil;
  for var Plat in ['Win32', 'Win64'] do
    Carpetas := Carpetas + IdePlatformLibraryPaths(DiscoverRadStudio, Plat);
  Result := UnidadesEnCarpetas(Carpetas);
  TMonitor.Enter(GDelphiCandado);
  try
    GUnidades := Result;
    GUnidadesTick := GetTickCount64;
  finally
    TMonitor.Exit(GDelphiCandado);
  end;
end;

function EnLaBiblioteca(const AUnidades: TArray<string>; const ANombre: string): Boolean;
var
  Ix: Integer;
begin
  Result := TArray.BinarySearch<string>(AUnidades, ClaveDeIdentificador(ANombre), Ix);
end;

initialization
  GDelphiCandado := TObject.Create;

finalization
  GDelphiCandado.Free;

end.
