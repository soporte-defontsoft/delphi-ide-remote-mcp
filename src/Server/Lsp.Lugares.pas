unit Lsp.Lugares;

{ LOS LUGARES DECLARADOS y sus formas: el mapa que leen la jaula y el
  enmascarador. Los sitios que el operador declaro, en UNA lista
  (LugaresDeclarados: raices, referencias, rutas de solo lectura, el vault y
  la zona de biblioteca); la zona de biblioteca del IDE (LibraryRoots, y la
  que se anuncia, LibraryReadRoots); que sitios estan en una letra de red y
  cual es su ruta de red (SitiosEnLetraDeRed, por la tabla de unidades de la
  sesion, sin abrir nada) y el host UNC que \\srvhost\ significa
  (HostUncDeclarado); la forma DECLARADA de una ruta o de un texto que llega
  resuelto (FormaDeclarada, FormaDeclaradaDe, FormaDeclaradaEnTexto); y las
  dos preguntas sobre donde empieza una ruta de red en un texto
  (CaracterPrevio, que se hace aqui y en el enmascarador, y DelimitadorDeRed,
  que hace el enmascarador).

  No decide ningun acceso: la jaula (JaulaDecide, UncFueraDeLugares,
  NegativaDeUnc, RootItselfDenied...) sigue en Lsp.Guard y LEE este mapa.
  Sale de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movido sin cambiar una linea: la tercera de las cuatro mudanzas que sacan
  de Guard la mascara de unidades. Debajo solo tiene a Lsp.Settings (las
  listas), Lsp.Rutas (las formas), Lsp.NetDrives (las letras) y
  Lsp.Discovery (el IDE). Las listas crudas de los sitios se recorren AQUI o
  en Lsp.Settings, que las lee: tests/test_paisaje.py lo vigila, con la
  deuda de hoy declarada. }

interface

{ The READ-ONLY library zone (RAD Studio installations, IDE library search
  paths, GetIt catalog repositories). Readable by reading tools, never
  writable - exposed so delphi_workspace can tell the agent what it may read
  besides the roots (field round 4, R4-B). }
function LibraryReadRoots: TArray<string>;

{ LOS LUGARES DEL IDE: donde el Delphi activo guarda lo suyo, medido por
  Discovery - su instalacion (RootDir: rsvars, sus fuentes, los .targets de
  MSBuild), su carpeta de datos del usuario (%APPDATA%\Embarcadero\BDS\<ver>:
  los .profile y los .sdk), la de sus SDK ($(BDSPLATFORMSDKSDIR)) y cada
  sysroot que su SDK Manager registra aunque viva en otro sitio (los de
  Android, en el CatalogRepository: Discovery.SysrootsRegistrados, leidos en
  cada llamada). Los sysroots que nombra un .sdk de la carpeta de perfiles los
  anade la puerta (Lsp.Patch.SysrootsDeLosSdk): saberlos pide leer, y aqui no
  se lee nada. Lo que el servidor lee o escribe del IDE FUERA de
  las raices va solo ahi, por las puertas de Lsp.Patch (David, 9-oct-2026:
  fuera de esto se niega; decisions/puertas-diseno-2026-10-09). NO las
  carpetas de Documentos (BdsUserDir, BdsCommonDir): de la de usuario cuelga
  Projects, donde el IDE crea los proyectos de la gente. NO su zona de
  biblioteca (LibraryRoots): es otro lugar de las puertas (ltBiblioteca),
  porque cargarla lee rsvars.bat por la puerta con el IDE como lugar, y
  dentro de aqui la puerta se preguntaba a si misma sin fin (medido el
  9-oct-2026: el servidor se caia en la primera llamada al motor). En la
  forma con la que se compara (FormaLarga). Sin Delphi, vacio.
  AParaEscribir: los que se pueden ESCRIBIR, que son los mismos SIN la
  instalacion (David, 9-oct-2026: solo BDS AppData y los sysroots de los SDK
  que el IDE registra; la instalacion se lee, no se toca). }
function LugaresDelIde(AParaEscribir: Boolean = False): TArray<string>;

{ LA ZONA DE BIBLIOTECA como lugar de las puertas (ltBiblioteca, Lsp.Patch):
  la de LibraryRoots, solo para LEER, este o no encendida LibraryZone - lo
  que el motor lee de la Library Path lo pide el IDE, no el agente (P2 de la
  1.18.0). Aparte de LugaresDelIde por lo que dice alli (cargarla pasa por la
  puerta con el IDE como lugar). En la forma con la que se compara
  (FormaLarga), rehecha cuando LibraryRoots se recarga. }
function LugaresDeLaBiblioteca: TArray<string>;

{ AReal (una ruta REAL: RealPath, RutaDelEnlace) cae DE VERDAD donde la
  jaula deja escribir: en una raiz, y no en una referencia, en una carpeta de
  solo lectura ni en un vault - cada sitio por SU ruta real (EnAlgunLugar),
  nunca un texto declarado contra una ruta resuelta (las dos formas de un
  sitio del CLAUDE.md: una raiz declarada por una union, o bajo el AppData
  que parte la virtualizacion, no casaria). Sin raices no hay jaula y vale.
  La pregunta del escritor de la jaula sobre DONDE nacen su temporal y su
  renombre (Lsp.Guard.SustitucionDenegada, P4-a de la 1.18.0). }
function EscribibleDeVerdad(const AReal: string): Boolean;

{ La entrada de ReadOnlyPaths (tal como esta declarada) que cubre APath;
  '' si ninguna. EL lector de ReadOnlyPaths de las escrituras, el de la jaula
  (Lsp.Guard.PathDenied). Por el texto Y por la ruta REAL: un junction de la
  raiz que apunte a una carpeta de solo lectura no la vuelve escribible.
  Hasta la 1.18.2 habia otro, el de la casa de las capturas dentro del
  workspace, que las comparaba por su texto crudo: una raiz en 8.3 y su
  entrada en largo, o al reves, se colaban, y la captura caia DENTRO de la
  raiz de solo lectura (revisor del 2i, medido). Lanza con una ruta que no
  parsea: quien llama ya la tiene comprobada. }
function SoloLecturaDeclaradaEn(const APath: string): string;

{ La raiz de ESCRITURA del workspace que contiene APath por su texto, en la
  forma con la que se compara (FormaLarga) y sin separador final; la mas
  larga si casan varias, '' si ninguna. Para juzgar lo que hay DEBAJO de ella
  (Lsp.References.SkipBajoLaRaiz): una carpeta de encima que se llame Release
  no es un artefacto (M1b del revisor de cierre de la 1.18.2). Nunca lanza. }
function RaizQueContiene(const APath: string): string;

{ La forma DECLARADA de una ruta que llega RESUELTA. Un programa que el
  servidor lanza contesta con la ruta real (git: la raiz de un repo), y la
  real de un sitio declarado en una letra de red CONECTADA (L:\...) es su
  UNC (\\host\recurso\...). La puerta juzga por la forma declarada y negaba
  esa respuesta: en una maquina con las raices en una letra de red,
  delphi_git contestaba GIT-041 a todo lo que trabaja sobre un repo que ya
  existe (medido el 30-sep-2026: status, config, add, commit, log, branch,
  diff, stash, switch).
  Si ARuta es un UNC que cae bajo la ruta de red de una raiz o de una
  referencia DECLARADA CON LETRA, vuelve escrita con lo declarado; si no,
  vuelve como llego. No abre nada: lo que devuelve pasa despues por la
  puerta de siempre, una ruta con letra no se toca, y un UNC que no es de
  ningun sitio declarado tampoco. Y no toca el disco ni la red: la ruta de
  red de un sitio sale de la tabla de unidades de la sesion (GetDriveType,
  WNetGetConnection), que es local - medido el 1-oct-2026: 0,1 ms, y el
  mismo recurso que escribe git. Solo las letras que son unidades de red:
  un enlace local hacia un recurso se queda como estaba. }
// AReferencia: llamada ya admitida; devuelve tambien la forma de su raiz enlazada.
function FormaDeclarada(const ARuta: string; const AReferencia: string = ''): string;
{ Lo mismo sobre unas listas dadas (los sitios declarados y su ruta de red,
  por indice): la regla sin la maquina, para quien la prueba. }
function FormaDeclaradaDe(const ARuta: string;
  const ADeclaradas, AReales: TArray<string>; AConLocales: Boolean = False): string;
{ La misma regla sobre un TEXTO, para la SALIDA: donde aparece la ruta de red
  de un sitio declarado en una letra - como la escribe git
  (//host/recurso/...), con las barras de Windows, o dobladas dentro de un
  JSON - se pone la forma declarada, con las barras con que venia. El
  enmascarador la llama antes de su barrido, que le pone su unidad virtual:
  lo que git ensenaba salia con el nombre real de la maquina y en una forma
  que el agente no puede devolver (worktree list). Reconoce SOLO esas
  rutas, por su texto: reconocer "//algo" por su forma se llevaria los
  comentarios de Pascal de un diff. }
function FormaDeclaradaEnTexto(const ATexto: string;
  const ADeclaradas, AReales: TArray<string>): string;
{ EL cambio de una ruta por otro texto DENTRO de un texto de salida: donde
  una de AAgujas (sin distinguir mayusculas) aparece como ruta - EMPIEZA ahi,
  no pegada a una palabra (y la que empieza por barra, tampoco detras de otra
  barra ni de dos puntos), y ACABA ahi o sigue por un separador -, se pone su
  ACambios (uno vacio la deja como venia: una ruta que tiene que ganar a una
  aguja mas corta y quedarse); ABarras (por indice; '' si no) se anade
  cuando la ruta acaba justo ahi. Las agujas mas largas primero. Sin ningun
  sitio en el texto, el mismo texto, sin copiarlo. Lo usan FormaDeclaradaEnTexto
  (las rutas de red de los sitios declarados) y el enmascarador de la casa
  del servidor (Lsp.Mascara, 2ag de la 1.18.2): eran el mismo bucle. }
function CambiaPrefijosEnTexto(const ATexto: string;
  AAgujas, ACambios, ABarras: TArray<string>): string;
{ La forma del proceso, la larga y la 8.3 de una ruta, sin la barra final y
  sin repetir; la que no se deja calcular no cuenta (nunca lanza). Una casa
  del servidor o una raiz puede salir en cualquiera de las tres. }
function FormasDeUnaRuta(const ARuta: string): TArray<string>;
{ La firma del juego de raices de la sesion (las de escribir y las de solo
  lectura): cambia cuando cambia alguna. Para quien guarda algo calculado
  de ellas sin recorrerlas (la cache de las agujas de la casa). }
function FirmaDeLasRaices: string;
{ Las raices de la sesion (las de escribir y las de solo lectura) frente a
  una casa del servidor, ACasa (2ag de la 1.18.2): True si esta DENTRO de
  una - es del agente, "si le das acceso, tu sabras", y no se enmascara -;
  si no, ADeSiMismas son las formas de las raices que EMPIEZAN como alguna
  forma de la casa (una vecina con un espacio, D:\Delphi Projects junto a
  D:\Delphi, o una de dentro), que el enmascarador deja como venian. Las
  recorria Lsp.Mascara.AgujasDeCasa por su cuenta (test_paisaje). }
function CasaDentroDeUnaRaiz(const ACasa: string; out ADeSiMismas: TArray<string>): Boolean;

{ La zona de biblioteca (la instalacion de este Delphi, sus catalogos de
  GetIt y el Library Search Path de todas sus plataformas), canonica, este o
  no encendida (eso lo pregunta quien la lee): la recorren la jaula
  (JaulaDecide) y las letras que se sirven (ServedDriveLetters). La que se
  anuncia es LibraryReadRoots. Cargada una vez y RECARGADA cuando el IDE
  cambia lo que la compone: Windows avisa (Lsp.Discovery.VigiasDeLaBiblioteca,
  sobre Library y Environment Variables), y preguntarlo por llamada cuesta lo
  que mirar un evento. Hasta la 1.21.4 vivia lo que el proceso: medido el
  21-oct-2026 en la VM, el operador registro 19 carpetas en el Library Path
  con el servidor en marcha y delphi_list las negaba con GUARD-002 mientras
  el IDE y msbuild ya compilaban con ellas (delphi_components, que lee el
  registro por llamada, si las veia). }
function LibraryRoots: TArray<string>;
{ Cuantas veces se ha cargado la zona (sube en cada recarga): lo que cachea
  algo DERIVADO de ella (las letras servidas, Lsp.Mascara) lo compara para
  rehacerse. Pregunta antes a LibraryRoots, asi que recarga si toca. }
function GeneracionDeLaBiblioteca: Integer;
{ Los lugares que el operador declaro, en UNA lista: la lee UncFueraDeLugares
  (Lsp.Guard). Sin blancos y con barras de Windows: quien la lee compara el
  texto tal cual. }
function LugaresDeclarados: TArray<string>;
{ La misma ruta bajo la letra de cada lugar declarado de OTRA unidad que la
  contiene por su ruta, sin repetir; nil si APath no lleva letra. Las
  candidatas de la negativa de leer que nombra la buena (V92 de la 1.23.1):
  Lsp.Guard.MismaRutaEnOtraUnidad las pasa por su puerta. }
function MismaRutaEnOtrasUnidades(const APath: string): TArray<string>;
{ El host UNC de los lugares declarados si es UNO solo: lo que \\srvhost\
  significa al volver del agente (ExpandDriveValue, Lsp.Mascara). }
function HostUncDeclarado: string;
{ HAY JAULA: el servidor tiene raices de escritura (las del workspace de la
  peticion o las del modo local). Sin ellas no hay reglas de escritura ni
  carpeta del agente: es el modo local de confianza, que es de solo lectura
  (IsReadOnlyNow). LA pregunta: se escribia a mano como
  Length(WorkspaceRoots) = 0 en seis sitios (14-oct-2026), y aun en ocho el
  25-oct (V30 de la 1.23): todos la preguntan; la regla de test_paisaje
  vigila que nadie la reescriba. IsReadOnlyNow (Lsp.Settings), de donde sale
  WorkspaceRoots, tiene la suya. }
function HayJaula: Boolean;
{ Las raices y referencias de una letra de red, con su ruta de red (por
  indice): las leen FormaDeclarada y el enmascarador (MaskDriveText). }
procedure SitiosEnLetraDeRed(out ADeclaradas, AReales: TArray<string>);
{ El caracter de antes de AI en un texto que puede ser un JSON (un \n escrito
  es un salto de linea): lo preguntan FormaDeclaradaEnTexto y el barrido del
  enmascarador (MaskDriveText). }
function CaracterPrevio(const ATexto: string; AI: Integer): Char;
{ Si en AI de un texto puede empezar una ruta de red, por lo que lleva
  delante: lo pregunta el barrido del enmascarador (MaskDriveText). }
function DelimitadorDeRed(const ATexto: string; AI: Integer): Boolean;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  Lsp.NetDrives,        // las letras de red de los sitios declarados
  Lsp.Rutas,
  Lsp.Settings,
  Lsp.Discovery,
  System.StrUtils;

var
  // la zona de biblioteca y lo derivado de ella, bajo UN cerrojo: la cargan
  // y la recargan los hilos de las peticiones (no se libera: como GDrvLock
  // en Lsp.Mascara, lo usan hilos que aun contestan y se va con el proceso)
  GLibCandado: TObject;
  GLibLoaded: Boolean = False;
  GLibRoots: TArray<string>;
  // los vigias de las claves del IDE que la componen: Windows senala su
  // evento cuando el IDE las escribe (se van con el proceso, como el cerrojo)
  GLibVigias: TArray<TVigiaDeClave>;
  GLibGeneracion: Integer = 0; // sube en cada carga
  // los lugares del IDE: se miden una vez (las puertas los preguntan por cada
  // fichero, y IdeSdksDir lee el registro); los sysroots, por llamada
  GIdeLoaded: Boolean = False;
  GIdeInstalacion: string;      // la instalacion: solo para leer
  GIdeLugares: TArray<string>;  // datos del usuario y SDK: leer y escribir
  GLibLugaresLoaded: Boolean = False;
  GLibLugares: TArray<string>;  // la zona de biblioteca, en FormaLarga

{ Lee la zona del IDE de este servidor: la instalacion, los catalogos y el
  Library Search Path de TODAS sus plataformas, canonica. Lo llama
  LibraryRoots bajo su cerrojo, la primera vez y en cada recarga. }
procedure CargaLaBiblioteca;
var
  Info: TRadStudioInfo;
  List, Vars: TStringList;
  Plat, Item, Expanded: string;
begin
  List := TStringList.Create;
  try
    // THE Delphi of this server, and no other (David, 5-oct-2026: "nos
    // centramos en el Delphi que usemos en el server"). Until then EVERY
    // installation was readable; another version's sources are no use
    // to a server that builds with this one.
    Info := DiscoverRadStudio;
    if Info.Found then
    begin
      List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(Info.RootDir)));
      Vars := TStringList.Create;
      try
        IdeMacroVars(Info, Vars);

        // The catalog repositories THEMSELVES, whole: every GetIt package
        // lives there (FmxLinux, LockBox...), and the Library Search Path
        // only points at its compiled Lib\ folder - what an agent actually
        // wants to read is the sibling source\. Also covers the Android
        // SDKs and the PAServer installers.
        for Item in TArray<string>.Create(Vars.Values['BDSCatalogRepositoryAllUsers'],
          Vars.Values['BDSCatalogRepository']) do
        begin
          // solo una completa (EL resolutor, sin carpeta): "\x" o "X:y" se
          // resolvian contra el PROCESO del servidor
          Expanded := RutaDesde('', Item);
          if Expanded = '' then
            Continue;
          Expanded := IncludeTrailingPathDelimiter(Expanded);
          if List.IndexOf(Expanded) < 0 then
            List.Add(Expanded);
        end;

        // ALL platforms registered for this install, never a fixed pair:
        // Linux64, OSX64, Android64, iOSDevice64... each has its own path.
        // Por EL lector de esa lista (IdePlatformLibraryPaths): aqui habia
        // otra lectura del registro y otra expansion (regla del paisaje,
        // 18-oct-2026; medido que daban lo mismo en las 13 plataformas)
        for Plat in IdeLibraryPlatforms(Info.Version) do
        begin
          for Item in IdePlatformLibraryPaths(Info, Plat) do
          begin
            try
              Expanded := IncludeTrailingPathDelimiter(Item);
              if List.IndexOf(Expanded) < 0 then
                List.Add(Expanded);
              // A component's INSTALL ROOT is library territory too: the IDE
              // registers its Source\ (or a per-platform Lib\), and next to
              // it live Library\, Redist\, Examples\ - the native runtime
              // libraries a deployment must ship (field 2026-08-22: OBR's
              // libzbar.so in Library\Linux64, unreadable because only
              // Source\ was registered). One level up, never a drive root,
              // never above the IDE's own documents trees.
              Expanded := ComponentRootOf(Expanded);
              if Expanded <> '' then
              begin
                Expanded := IncludeTrailingPathDelimiter(Expanded);
                if List.IndexOf(Expanded) < 0 then
                  List.Add(Expanded);
              end;
            except
              // an unparseable entry never breaks the server
            end;
          end;
        end;
      finally
        Vars.Free;
      end;
    end;
    GLibRoots := List.ToStringArray;
  finally
    List.Free;
  end;
end;

{ The read-only library zone: RAD Studio installation + IDE Library Search
  Path directories (installed components), canonicalized. Cached, and
  reloaded when Windows says the IDE's keys changed (GLibVigias). }
function LibraryRoots: TArray<string>;
var
  Info: TRadStudioInfo;
begin
  TMonitor.Enter(GLibCandado);
  try
    if not GLibLoaded then
    begin
      // los vigias ANTES de la primera lectura: un cambio que llegue
      // mientras se lee sale en la siguiente pregunta
      Info := DiscoverRadStudio;
      if Info.Found then
        GLibVigias := VigiasDeLaBiblioteca(Info.Version);
    end;
    if (not GLibLoaded) or CambioAlgunaClave(GLibVigias) then
    begin
      CargaLaBiblioteca;
      GLibLoaded := True;
      GLibLugaresLoaded := False; // la forma larga se rehace de esta carga
      Inc(GLibGeneracion);
    end;
    Result := GLibRoots;
  finally
    TMonitor.Exit(GLibCandado);
  end;
end;

function GeneracionDeLaBiblioteca: Integer;
begin
  TMonitor.Enter(GLibCandado);
  try
    LibraryRoots; // recarga si el IDE cambio
    Result := GLibGeneracion;
  finally
    TMonitor.Exit(GLibCandado);
  end;
end;

{ Los lugares que el operador declaro (raices, referencias, solo lectura, el
  vault, la zona de biblioteca): UNA lista para quien pregunta por un UNC
  (UncFueraDeLugares) y para el host que vuelve de srvhost (HostUncDeclarado).
  Desde la 1.9.0 las raices, las referencias, lo de solo lectura y el vault
  son SIEMPRE de letra (el cargador no carga otra cosa): lo unico de esta
  lista que puede ser un UNC es una carpeta de la zona de biblioteca - un
  Library Path del IDE en un recurso. Lo que en HostUncDeclarado (abajo) y
  en UncFueraDeLugares (Lsp.Guard, que lee esta lista)
  trata un sitio declarado en UNC queda solo para eso, y SIN check propio:
  lo media una raiz UNC (A13 y A14 de test_alias83), que ya no existe. }
function LugaresDeclarados: TArray<string>;
var
  Todos: TArray<string>;
  I: Integer;
begin
  Todos := WorkspaceRoots + WorkspaceReadOnlyRoots + WorkspaceReadOnlyPaths;
  if VaultPath <> '' then
    Todos := Todos + [VaultPath];
  if LibraryZoneEnabled then
    Todos := Todos + LibraryRoots;
  // UNA forma aqui, y no en cada uno que la lee (eran seis re-normalizaciones
  // a mano en Lsp.Guard y aqui: A40 de la 1.23)
  SetLength(Result, Length(Todos));
  for I := 0 to High(Todos) do
    Result[I] := ConBarrasDeWindows(Todos[I].Trim);
end;

function MismaRutaEnOtrasUnidades(const APath: string): TArray<string>;
var
  Letra: Char;
  Cola: string;
begin
  Result := nil;
  Letra := LetraDeRuta(APath);
  if Letra = #0 then
    Exit; // un UNC o algo sin letra: no hay "otra unidad"
  Cola := Copy(APath, 3, MaxInt);
  for var S in LugaresDeclarados do
  begin
    var L := LetraDeRuta(S);
    if (L = #0) or (L = Letra) then
      Continue;
    var Candidata := Copy(S, 1, 2) + Cola;
    if RutaDentroDe(S, Candidata) and not MatchText(Candidata, Result) then
      Result := Result + [Candidata];
  end;
end;

function HayJaula: Boolean;
begin
  Result := Length(WorkspaceRoots) > 0;
end;

{ El host UNC de los lugares declarados, si es UNO solo ('' si ninguno o
  varios): lo que \\srvhost\ significa al volver del agente. }
function HostUncDeclarado: string;
var
  L, H: string;
  I: Integer;
begin
  Result := '';
  if not HayJaula then
    Exit;
  for L in LugaresDeclarados do
  begin
    H := L;
    if not EsUnc(H) then
      Continue;
    H := H.Substring(2);
    I := H.IndexOf('\');
    if I > 0 then
      H := H.Substring(0, I);
    if H = '' then
      Continue;
    if Result = '' then
      Result := H
    else if not SameText(Result, H) then
      Exit(''); // dos hosts: no se adivina
  end;
end;

{ UN sitio de letra de red: declarado con letra y con un UNC por ruta de red.
  LA pregunta de las tres funciones de abajo (eran tres condiciones, y no la
  misma; segundo revisor de la 1.8.2). Con las dos rutas ya sin separador
  final y con barras de Windows. }
function EsSitioDeLetraDeRed(const ADecl, AReal: string): Boolean;
begin
  Result := (ADecl <> '') and not EsUnc(ADecl) and
    EsUnc(AReal);
end;

{ El caracter de ANTES de la posicion AI de un texto que puede ser un JSON:
  alli un salto de linea son los dos caracteres \ y n, y lo que abre una
  linea no esta pegado a la letra n. Lo preguntan el barrido del enmascarador
  y la regla de las rutas de red (estaba escrito en los dos).
  Un escape es UNA barra - un numero impar de ellas -: con dos, es una barra
  ESCRITA y la letra es la de una carpeta ("C:\\t\\x" es C:\t\x, no un
  tabulador). Sin contarlas, la carpeta de una letra n, r o t hacia de salto
  de linea (1.9.0, al dar a la forma de red esta misma pregunta). }
function CaracterPrevio(const ATexto: string; AI: Integer): Char;
var
  K, Barras: Integer;
begin
  if AI <= 1 then
    Exit(#0);
  Result := ATexto[AI - 1];
  if (AI >= 3) and CharInSet(Result, ['n', 'r', 't']) and (ATexto[AI - 2] = '\') then
  begin
    Barras := 0;
    K := AI - 2;
    while (K >= 1) and (ATexto[K] = '\') do
    begin
      Inc(Barras);
      Dec(K);
    end;
    if Odd(Barras) then
      Result := #10;
  end;
end;

{ Lo que puede ir delante de una ruta de red: el principio, un blanco, una
  comilla, un parentesis, una coma, un igual, un ';' (una lista de rutas),
  <, >, |, [ o un salto de linea - o una opcion de una linea de ordenes
  pegada a ella (-U\nas\lib, -NU, /I) detras de un blanco o una comilla.
  Pegada a una carpeta NO: es el separador doblado del eco del enlazador
  (Linux64\\Debug), y tomarlo por una ruta de red se comia la cola entera
  (227 srvhost en una salida, 2026-08-26). }
function DelimitadorDeRed(const ATexto: string; AI: Integer): Boolean;
const
  ANTES: TSysCharSet = [' ', #9, '"', '''', '(', ',', '=', ';', '<', '>', '|', '[', #10, #13];
var
  K, Letras: Integer;
begin
  if AI <= 1 then
    Exit(True);
  if CharInSet(CaracterPrevio(ATexto, AI), ANTES) then
    Exit(True);
  K := AI - 1;
  Letras := 0;
  while (K >= 1) and CharInSet(ATexto[K], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Letras);
    Dec(K);
  end;
  Result := (Letras >= 1) and (Letras <= 2) and (K >= 1) and
    CharInSet(ATexto[K], ['-', '/']) and
    ((K = 1) or CharInSet(CaracterPrevio(ATexto, K), [' ', #9, '"', '''', #10, #13]));
end;

function FormaDeclaradaDe(const ARuta: string;
  const ADeclaradas, AReales: TArray<string>; AConLocales: Boolean): string;
var
  P, Decl, Real, Mejor, MejorReal: string;
  I: Integer;
begin
  Result := ARuta;
  P := PrefijoSinBarra(ConBarrasDeWindows(ARuta.Trim));
  // El prefijo y el sufijo se cuentan en la misma forma larga, tambien
  // cuando Git devuelve larga la ruta de un destino escrito en 8.3.
  if AConLocales and not EsUnc(P) then
    P := PrefijoSinBarra(FormaLarga(RaizSiUnidad(P)));
  // Por defecto solo UNC; los enlaces locales se traducen cuando lo piden.
  if not AConLocales and not EsUnc(P) then
    Exit;
  Mejor := '';
  MejorReal := '';
  for I := 0 to High(ADeclaradas) do
  begin
    if I > High(AReales) then
      Break;
    Decl := PrefijoSinBarra(ConBarrasDeWindows(ADeclaradas[I].Trim));
    Real := PrefijoSinBarra(ConBarrasDeWindows(AReales[I].Trim));
    // solo un sitio de letra de red. Uno en UNC (desde la 1.9.0 solo puede
    // serlo una carpeta de la zona de biblioteca) se queda con la
    // regla de siempre: vale en la forma en que se escribio
    if not EsSitioDeLetraDeRed(Decl, Real) and
       not (AConLocales and EsSitioConLetra(RaizSiUnidad(Decl)) and
         EsRutaAbsoluta(RaizSiUnidad(Real))) then
      Continue;
    if AConLocales and not EsUnc(Real) then
      Real := PrefijoSinBarra(FormaLarga(RaizSiUnidad(Real)));
    // bajo ESE sitio: el mismo, o lo que sigue a su separador (\\h\r\ab
    // no esta bajo \\h\r\a). De dos que casan, el mas hondo
    if EnLugar(RaizSiUnidad(P), RaizSiUnidad(Real), False) and
       (Length(Real) > Length(MejorReal)) then
    begin
      Mejor := Decl;
      MejorReal := Real;
    end;
  end;
  if Mejor <> '' then
  begin
    Result := Mejor + P.Substring(Length(MejorReal));
    // la raiz de la unidad misma: "L:" a secas es la carpeta ACTUAL de L:
    if (Length(Result) = 2) and (Result[2] = ':') then
      Result := Result + '\';
  end;
end;

{ La ruta de RED de un sitio declarado con letra, por la tabla de unidades de
  ESTA sesion y sin abrir nada: si la letra es una unidad de red conectada,
  su recurso mas el resto de la ruta; '' si no lo es. (Abrir el sitio para
  pedirle su ruta real daba lo mismo, y con el recurso caido dejaba
  esperando a quien lo pidiese: el enmascarador lo pide en cada respuesta.
  Segundo revisor de la 1.8.2.) }
function RutaDeRedDe(const ASitio: string): string;
var
  Unidad: string;
  Buf: array [0 .. 1023] of Char;
  N: DWORD;
begin
  Result := '';
  // (la letra y lo que es para esta sesion, por sus lectores: Lsp.NetDrives)
  if LetraDeRuta(ASitio) = #0 then
    Exit;
  Unidad := LetraDeRuta(ASitio) + ':';
  if ClaseDeLetra(Unidad[1]) <> clDeRed then
    Exit;
  N := Length(Buf);
  if WNetGetConnection(PChar(Unidad), Buf, N) <> NO_ERROR then
    Exit;
  Result := PrefijoSinBarra(string(PChar(@Buf[0]))) + ASitio.Substring(2);
end;

{ Los sitios de la sesion (raices y referencias) que son de una letra de red,
  con su ruta de red. UNA lista para quien traduce lo que contesta git y para
  el enmascarador. }
procedure SitiosEnLetraDeRed(out ADeclaradas, AReales: TArray<string>);
var
  L, Sitio, Real: string;
begin
  ADeclaradas := nil;
  AReales := nil;
  for L in WorkspaceRoots + WorkspaceReadOnlyRoots do
  begin
    // (canonicas desde su cargador, Lsp.Settings.EntradaAbsolutaDeSitio)
    Sitio := PrefijoSinBarra(L);
    Real := RutaDeRedDe(Sitio);
    if EsSitioDeLetraDeRed(Sitio, Real) then
    begin
      ADeclaradas := ADeclaradas + [Sitio];
      AReales := AReales + [Real];
    end;
  end;
end;

function FormaDeclarada(const ARuta: string; const AReferencia: string): string;
var
  Declaradas, Reales: TArray<string>;
begin
  // (lo que no es un UNC lo devuelve tal cual FormaDeclaradaDe; la lista
  // sale de la tabla de unidades, sin abrir nada)
  SitiosEnLetraDeRed(Declaradas, Reales);
  // Solo las raices que contienen el argumento ya admitido: no abrir las demas.
  if AReferencia <> '' then
    for var R in WorkspaceRoots + WorkspaceReadOnlyRoots do
      if EnLugar(AReferencia, R,
        (ClaseDeLetra(LetraDeRuta(R)) = clLocal) and
        (ClaseDeLetra(LetraDeRuta(AReferencia)) = clLocal)) then
      begin
        Declaradas := Declaradas + [R];
        Reales := Reales + [RealPath(R)];
      end;
  Result := FormaDeclaradaDe(ARuta, Declaradas, Reales, AReferencia <> '');
end;

function FormaDeclaradaEnTexto(const ATexto: string;
  const ADeclaradas, AReales: TArray<string>): string;
var
  Agujas, Cambios, Barras: TArray<string>;
  Decl, Real: string;
  K: Integer;

  // ABarra: con que se separa en esa escritura. Solo se guarda para la raiz de
  // la unidad ("L:"), que la necesita cuando la ruta acaba ahi
  procedure Anade(const AReal, ADecl, ABarra: string);
  begin
    Agujas := Agujas + [AReal];
    Cambios := Cambios + [ADecl];
    if (Length(Decl) = 2) and (Decl[2] = ':') then
      Barras := Barras + [ABarra]
    else
      Barras := Barras + [''];
  end;

begin
  Agujas := nil;
  Cambios := nil;
  Barras := nil;
  for K := 0 to High(ADeclaradas) do
  begin
    if K > High(AReales) then
      Break;
    Decl := PrefijoSinBarra(ConBarrasDeWindows(ADeclaradas[K].Trim));
    Real := PrefijoSinBarra(ConBarrasDeWindows(AReales[K].Trim));
    if not EsSitioDeLetraDeRed(Decl, Real) then
      Continue;
    // las tres escrituras de la misma ruta: dobladas dentro de un JSON, las
    // de git y las de Windows. Cada una vuelve con SUS barras
    Anade(Real.Replace('\', '\\'), Decl.Replace('\', '\\'), '\\');
    Anade(ConBarrasNormales(Real), ConBarrasNormales(Decl), '/');
    Anade(Real, Decl, '\');
  end;
  Result := CambiaPrefijosEnTexto(ATexto, Agujas, Cambios, Barras);
end;

function CambiaPrefijosEnTexto(const ATexto: string;
  AAgujas, ACambios, ABarras: TArray<string>): string;
var
  Agujas, Cambios, Barras: TArray<string>;
  Tmp, Primeras: string;
  Sb: TStringBuilder;
  I, J, K, L: Integer;

  // la aguja que casa en AI como ruta, o -1. Una ruta EMPIEZA ahi: no pegada
  // a una palabra; la de red (empieza por barra) tampoco detras de otra barra
  // (la mitad de una doblada, o el %(prefix)///host que git propone al
  // operador) ni de dos puntos (https://host); la de una letra (la casa) pide
  // solo eso, como el barrido de las letras del enmascarador. Y ACABA ahi o
  // sigue por un separador: \\h\r\ab no es \\h\r\a
  function CasaEn(AI: Integer): Integer;
  var
    M, N: Integer;
    Previo: Char;
  begin
    Result := -1;
    if Pos(UpCase(ATexto[AI]), Primeras) = 0 then
      Exit;
    Previo := CaracterPrevio(ATexto, AI);
    if CharInSet(Previo, ['A' .. 'Z', 'a' .. 'z', '0' .. '9']) then
      Exit;
    for M := 0 to High(Agujas) do
    begin
      N := Length(Agujas[M]);
      if (N = 0) or (CharInSet(Agujas[M][1], ['\', '/']) and CharInSet(Previo, ['\', '/', ':'])) then
        Continue;
      if (AI + N - 1 <= L) and
         (StrLIComp(PChar(ATexto) + AI - 1, PChar(Agujas[M]), N) = 0) and
         ((AI + N > L) or CharInSet(ATexto[AI + N],
            ['\', '/', '"', '''', ' ', #9, #10, #13, ')', ',', ';', '<', '>', '|'])) then
        Exit(M);
    end;
  end;

begin
  Result := ATexto;
  if Length(AAgujas) = 0 then
    Exit;
  // copias: se ordenan aqui, y las de quien llama pueden ser compartidas
  // (las de la casa se guardan una vez para todos los hilos)
  Agujas := Copy(AAgujas);
  Cambios := Copy(ACambios);
  Barras := Copy(ABarras);
  // la mas larga primero: de dos sitios anidados, el mas hondo
  for I := 1 to High(Agujas) do
    for J := I downto 1 do
      if Length(Agujas[J]) > Length(Agujas[J - 1]) then
      begin
        Tmp := Agujas[J]; Agujas[J] := Agujas[J - 1]; Agujas[J - 1] := Tmp;
        Tmp := Cambios[J]; Cambios[J] := Cambios[J - 1]; Cambios[J - 1] := Tmp;
        Tmp := Barras[J]; Barras[J] := Barras[J - 1]; Barras[J - 1] := Tmp;
      end;
  // con que puede empezar una: lo demas no se mira
  Primeras := '';
  for K := 0 to High(Agujas) do
    if Agujas[K] <> '' then
      Primeras := Primeras + UpCase(Agujas[K][1]);
  L := Length(ATexto);
  // sin ningun sitio en el texto, el texto, sin copiarlo: el filtro de salida
  // pasa por aqui con cada respuesta, y un delphi_fetch de 6 MB pagaba medio
  // segundo por una copia que salia igual (revisor del 2ag)
  I := 1;
  while (I <= L) and (CasaEn(I) < 0) do
    Inc(I);
  if I > L then
    Exit;
  Sb := TStringBuilder.Create(L + 16);
  try
    Sb.Append(ATexto, 0, I - 1);
    while I <= L do
    begin
      K := CasaEn(I);
      if K < 0 then
      begin
        Sb.Append(ATexto[I]);
        Inc(I);
        Continue;
      end;
      // un cambio vacio deja la ruta como venia: una raiz del agente que
      // empieza como la casa del servidor (Lsp.Mascara.AgujasDeCasa) gana a
      // la casa por ser mas larga, y se queda
      if Cambios[K] = '' then
        Sb.Append(ATexto, I - 1, Length(Agujas[K]))
      else
        Sb.Append(Cambios[K]);
      // la raiz de la unidad, cuando la ruta acaba ahi: "L:" a secas no
      // es una ruta, y el barrido la dejaba con su letra de verdad.
      // Acaba ahi si NO sigue por la barra de su escritura: detras de
      // //h/r, el \n de un JSON no es un separador (tercer revisor)
      if (Barras[K] <> '') and
         (StrLComp(PChar(ATexto) + I + Length(Agujas[K]) - 1, PChar(Barras[K]), Length(Barras[K])) <> 0) then
        Sb.Append(Barras[K]);
      Inc(I, Length(Agujas[K]));
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function FormasDeUnaRuta(const ARuta: string): TArray<string>;
var
  F: string;
begin
  Result := [SinBarraFinal(ARuta)];
  for var K := 0 to 1 do
  begin
    try
      if K = 0 then
        F := SinBarraFinal(FormaLarga(ARuta))
      else
        F := SinBarraFinal(ExtractShortPathName(ARuta));
    except
      F := '';
    end;
    if (F <> '') and not MatchText(F, Result) then
      Result := Result + [F];
  end;
end;

function FirmaDeLasRaices: string;
begin
  Result := string.Join(#0, WorkspaceRoots + WorkspaceReadOnlyRoots);
end;

function CasaDentroDeUnaRaiz(const ACasa: string; out ADeSiMismas: TArray<string>): Boolean;
var
  Raices, Casa: TArray<string>;
begin
  ADeSiMismas := nil;
  Raices := WorkspaceRoots + WorkspaceReadOnlyRoots;
  for var R in Raices do
    if EnLugar(ACasa, R) then
      Exit(True);
  Casa := FormasDeUnaRuta(ACasa);
  for var R in Raices do
    for var FR in FormasDeUnaRuta(R) do
      for var F in Casa do
        // un prefijo de TEXTO, a proposito: el enmascarador cambia prefijos de
        // texto, y una raiz que EMPIEZA como la casa ('srvv x' junto a 'srvv') es
        // aguja de si misma. Comparado como el sistema de ficheros (SameFileName
        // sobre el trozo), no con la barra de RutaDentroDe, que la dejaba fuera
        // y la raiz vecina salia '<server> x' (C6 de test_mascara_casa_1182)
        if (Length(FR) > Length(F)) and SameFileName(Copy(FR, 1, Length(F)), F) then
        begin
          ADeSiMismas := ADeSiMismas + [FR];
          Break;
        end;
  Result := False;
end;

function LibraryReadRoots: TArray<string>;
begin
  if not LibraryZoneEnabled then
    Exit(nil); // announced as it is enforced: no zone, nothing to announce
  Result := LibraryRoots;
end;

function LugaresDelIde(AParaEscribir: Boolean): TArray<string>;
var
  Info: TRadStudioInfo;
  Lugares: TArray<string>;
  Instalacion: string;
begin
  // (no lee ningun fichero por las puertas: las puertas la preguntan a ELLA)
  Info := DiscoverRadStudio;
  if not GIdeLoaded then
  begin
    // en locales, y las globales al final: otro hilo que ya viese GIdeLoaded
    // no se encuentra la instalacion a medio calcular (revisor de P3)
    Lugares := nil;
    Instalacion := '';
    // solo lo ABSOLUTO: con APPDATA vacia la carpeta de perfiles saldria
    // relativa a la carpeta de trabajo del proceso (medida M3), y eso no es
    // un lugar del IDE
    if Info.Found then
    begin
      if EsRutaAbsoluta(Info.RootDir.Trim) then
        Instalacion := FormaLarga(Info.RootDir);
      for var L in TArray<string>.Create(IdeProfilesDir(Info.Version),
        IdeSdksDir(Info.Version)) do
        if EsRutaAbsoluta(L.Trim) then
          Lugares := Lugares + [FormaLarga(L)];
    end;
    GIdeInstalacion := Instalacion;
    GIdeLugares := Lugares;
    GIdeLoaded := True;
  end;
  Result := GIdeLugares;
  if not AParaEscribir and (GIdeInstalacion <> '') then
    Result := [GIdeInstalacion] + Result;
  // los sysroots registrados, EN CADA llamada: get-sdk, remove-sdk o el SDK
  // Manager los cambian con el servidor en marcha. Los que llevan la macro
  // viven en IdeSdksDir, que ya esta
  if Info.Found then
    for var S in SysrootsRegistrados(Info.Version) do
      if EsRutaAbsoluta(S.Trim) and not S.Contains('$(') then
        Result := Result + [FormaLarga(S)];
end;

function LugaresDeLaBiblioteca: TArray<string>;
var
  Raices, Lugares: TArray<string>;
begin
  TMonitor.Enter(GLibCandado);
  try
    // recarga si el IDE cambio, y entonces la forma larga se rehace de ella
    Raices := LibraryRoots;
    if not GLibLugaresLoaded then
    begin
      // en locales, y las globales al final, como LugaresDelIde
      Lugares := nil;
      for var L in Raices do
        if EsRutaAbsoluta(L.Trim) then
          Lugares := Lugares + [FormaLarga(L)];
      GLibLugares := Lugares;
      GLibLugaresLoaded := True;
    end;
    Result := GLibLugares;
  finally
    TMonitor.Exit(GLibCandado);
  end;
end;

function EscribibleDeVerdad(const AReal: string): Boolean;
begin
  if not HayJaula then
    Exit(True);
  // TODOS los vaults, como InVault (Lsp.Guard): el de otro workspace que caiga
  // en esta raiz tampoco se escribe por aqui (revisor de la noche, M-2: uno
  // solo eran dos lectores de "el vault")
  Result := EnAlgunLugar(AReal, WorkspaceRoots) and
    not EnAlgunLugar(AReal, WorkspaceReadOnlyRoots) and
    not EnAlgunLugar(AReal, WorkspaceReadOnlyPaths) and
    not EnAlgunLugar(AReal, TodosLosVaults);
end;

function SoloLecturaDeclaradaEn(const APath: string): string;
var
  Full, Verdad: string;
begin
  Result := '';
  Full := TPath.GetFullPath(APath);
  Verdad := IncludeTrailingPathDelimiter(RealPath(APath));
  for var Ro in WorkspaceReadOnlyPaths do
    if EnLugar(Full, Ro) or
       EnLugar(Verdad, RealPath(SinBarraFinal(Ro))) then
      Exit(SinBarraFinal(Ro));
end;

function RaizQueContiene(const APath: string): string;
var
  Full: string;
begin
  Result := '';
  try
    Full := FormaLarga(APath);
  except
    Exit;
  end;
  for var R in WorkspaceRoots do
  begin
    var Larga := FormaLarga(R);
    if RutaDentroDe(Larga, Full) and (Length(Larga) > Length(Result) + 1) then
      Result := SinBarraFinal(Larga);
  end;
end;

initialization
  GLibCandado := TObject.Create;

end.