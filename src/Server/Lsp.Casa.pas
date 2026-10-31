unit Lsp.Casa;

{ LA CASA DEL SERVIDOR: los nombradores de sus carpetas (ServerDir, la
  temporal, las caches de LOCALAPPDATA), de los nombres unicos que crea
  para una operacion (FragmentoUnico, SelloUnico, la carpeta de descarga) y
  de sus mutex, y el normalizador de lo que un cliente nombra (Slug). Nadie
  compone una de esas rutas o nombres a mano: se piden aqui.

  Salen de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidos sin cambiar una linea. Los nombradores no usan nada de la jaula,
  y los usan la jaula y el lector del settings.ini (SettingsIniPath). El
  escritor de la casa (EscribeEnCasaDelServidor) se fue el 9-oct-2026 a la
  puerta de escribir (Lsp.Patch), con la casa como lugar.
  Lo que se hace CON esas carpetas - los entregables del agente
  (AgentTempDir, CaptureTarget), la purga del arranque y la presencia de
  instancias - pregunta a las puertas y se queda en Lsp.Guard.

  Y los de la PAPELERA, la hermana de __delphi-temp, que llegan de Lsp.Patch
  el mismo dia y tambien sin cambiar una linea: el nombre de su carpeta
  (TrashFolderName) y la marca de dueno ENTERA - el escritor (MarcaDeDueno),
  su inversa (CopiaDeLaMarca), quien la reconoce (EsMarcaDeDueno) y el
  formato que los une (MARCA_DUENO_EXT): viajan juntos o no viaja ninguno.
  Lo que se hace CON la papelera (sellar, guardar) se queda en Lsp.Patch;
  purgarla, con la jaula (Lsp.Guard). El 9-oct-2026 (2.1f de la 1.18.0)
  llegan tambien la carpeta de la papelera de un fichero (CarpetaDePapelera)
  y la de su dia (TrashDayDir), el nombre de un dia y su lector (NombreDeDia,
  EsCarpetaDeDia) y la mascara de las marcas (MascaraDeMarcas): estaban
  compuestos a mano en Lsp.Patch y Mcp.Tools.FileOps, y las constantes de la
  carpeta y de la marca dejan de ser publicas. }

interface

{ EL NOMBRADOR DE LOS TEMPORALES, hermana de __delphi-patch y con la misma
  disciplina: el nombre de la carpeta se escribe en UN SITIO y nadie compone
  una ruta de temporales a mano.

  Por que existe: hasta el 2026-09-21 el servidor escribia sus temporales en
  el %TEMP% de la MAQUINA, en siete sitios distintos y a mano. Medido ese
  dia: 56,4 MB olvidados ahi fuera de toda jaula -33 capturas del escritorio
  del operador de dos dias antes y una salida de remoterun de 10,7 MB-, y un
  fichero de 10 bytes que una bateria se dejo suelto acabo siendo el
  "proyecto" de las units de otras tres. Un temporal repartido no se purga
  nunca.

  UNA CASA para lo nuestro: ServerTempDir, JUNTO AL EJECUTABLE, como
  reports\ y settings.ini - el fichero del mensaje de git, la descarga de un
  SDK, el guion que se manda a un target y las CAPTURAS que hacemos para
  devolverlas (CasaDeCapturas). Se puede borrar en cualquier momento: nada
  de lo que hay ahi sobrevive a la llamada que lo creo, o a su entrega. No
  pasa por la jaula porque no es una ruta que elija nadie de fuera: la jaula
  juzga lo que el AGENTE intenta, y esto es trabajo nuestro (David,
  12-oct-2026: "lo que intenta el agente pasa filtros; devolver una captura
  no"; CLAUDE.md, "What the agent attempts is not what the server does
  inside").

  Hasta la 1.18.2 habia una SEGUNDA casa, dentro del workspace (AgentTempDir:
  <raiz>\__delphi-temp\<agente>), con un criterio equivocado: "lo que el
  agente tiene que alcanzar va dentro, porque delphi_fetch comprueba la
  jaula" (21-sep-2026). La forma de ENTREGAR decidio donde vivia un trabajo
  nuestro, y desde el 25-sep la captura viaja en la respuesta y se consume.
  Costo el 2b y el 2i de la 1.18.2 y una captura dibujada DENTRO de una raiz
  de solo lectura. Hoy la captura viaja en la respuesta o por un enlace que
  la pide por su NOMBRE y resuelve su nombrador (Lsp.Guard.CapturaPorNombre):
  el agente no ve nuestra casa, y delphi_fetch es para sus ficheros (David,
  12-oct-2026: "nuestros procesos internos y nuestro temp, los agentes no
  deben ni olerlo").

  Componen la ruta y ya: crear la carpeta es de quien la use. }
const
  { Como ve el agente la casa del servidor en una respuesta (2ag de la
    1.18.2): el prefijo de su carpeta cambiado por su nombre, y lo de debajo
    tal cual (Lsp.Mascara.CasaEnTexto, en el filtro de salida). La carpeta
    del exe (ServerDir) y la cache (ServerCacheDir). }
  NOMBRE_CASA_SERVIDOR = '<server>';
  NOMBRE_CASA_CACHE = '<server-cache>';

function TempFolderName: string;
{ <carpeta del exe>\ASub: LA casa del servidor. Todo lo que el servidor
  guarda o busca junto a si mismo (settings.ini, __delphi-temp, logs,
  messages, reports, node, el conversor de estilos) se compone aqui; hasta
  el 26-sep lo componian a mano ocho sitios. Sin ASub, la carpeta. }
function ServerDir(const ASub: string = ''): string;
function ServerTempDir(const ASub: string = ''): string;
{ LA CASA DE LAS CAPTURAS que el servidor hace para devolverlas (sin out=):
  en su temporal, por workspace y por agente, con el compositor del buzon -
  <temporal>\captures\<carpeta del workspace>[\<agente>] -. Por workspace
  porque varios comparten el servidor: a cada uno se le entregan las suyas.
  Sin AAgente, la del workspace entera: la que reconoce quien entrega o
  consume una captura (Lsp.Guard.EnCasaDeEntregables). }
function CasaDeCapturas(const AAgente: string = ''): string;
{ <LOCALAPPDATA>\DelphiLspMcp\ASub: las caches del servidor que no van junto
  al exe (las configuraciones que se fabrican para el motor, los estilos por
  defecto de la plataforma). Las componian a mano dos sitios. Lee la
  variable en cada llamada: quien la redirige (una prueba) la ve. }
function ServerCacheDir(const ASub: string = ''): string;
{ El buzon de los agentes (<casa>\messages, delphi_messages) y la carpeta de
  los informes (<casa>\reports, delphi_report): eran una constante en cada
  tool, y las puertas de leer y escribir tienen que saber donde estan. Las
  tools no las usan: piden el buzon de la sesion (abajo). }
function CarpetaDeMensajes: string;
function CarpetaDeInformes: string;
{ EL BUZON de ESTA sesion: la carpeta de su workspace dentro de la de los
  mensajes o la de los informes y, con AAgente, la de ese agente debajo. La
  misma estructura de siempre separada por workspace (David, 10-oct-2026):
  quien entra con el token de un workspace no lista, no lee ni consume lo de
  otro. El workspace lo pone el token (CurrentWorkspaceName), nunca el
  cliente; el agente pasa por Slug aqui mismo. }
function BuzonDeMensajes(const AAgente: string = ''): string;
function BuzonDeInformes(const AAgente: string = ''): string;
{ La carpeta de AWorkspace dentro de un buzon: 'Workspace.' y su nombre por
  Slug cuando Slug lo dice entero y, si no (un acento, un signo, mas de 40),
  con los ocho primeros de su MD5 detras, para que dos workspaces no
  compartan nunca carpeta ('Hermes VM' y 'Hermes-VM'). Sin workspace - el
  proceso local, el unico que entra sin token - '_local'. Ninguna de las dos
  formas la puede dar Slug (el punto, el guion bajo): la carpeta de un agente
  del formato de antes (reports\<agente>\, todos los tokens juntos) nunca es
  el buzon de un workspace - un workspace 'hermes' leia como suyos los
  informes viejos de reports\hermes de todos (revisor de version de la
  1.18.0). }
function CarpetaDeWorkspace(const AWorkspace: string): string;
{ LA casa del servidor como LUGAR de las puertas de leer y escribir texto
  (ltCasa, Lsp.Patch): sus caches, el buzon y los informes. NO la carpeta del
  exe entera: ahi esta settings.ini, que tiene su propio lector (Lsp.Settings)
  y no lo lee ninguna puerta. Una casa que no es absoluta (LOCALAPPDATA vacia)
  no es lugar: se resolveria contra la carpeta de trabajo del proceso. }
function CarpetasDeLaCasa: TArray<string>;
{ EL nombre de la copia que se guarda de un fichero del IDE ANTES de pisarlo
  o borrarlo (David, 9-oct-2026: lo que el servidor escribe en el IDE fuera
  de las raices - un .sdk, la ficha de un sysroot - nunca pisa sin copia): en
  la cache del servidor, ide-copias\<carpeta>\<SelloUnico>-<nombre>, con
  <carpeta> la del original (37.0 para un .sdk o un .profile, <sdk>.sdk para
  la ficha de un sysroot): todas las fichas se llaman igual y la copia tiene
  que decir de donde viene (revisor de P3). El sello las ordena y no deja que
  dos se pisen. CopiasDelIde es su inversa: las copias guardadas de ESE
  fichero, de la mas vieja a la mas nueva. }
function CopiaDelIde(const APath: string): string;
function CopiasDelIde(const APath: string): TArray<string>;
{ El NOMBRE de una clave del registro del IDE en esas copias: la de
  SOFTWARE\Embarcadero\BDS\<AVersion>\<ASubclave> es <AVersion>\<ASubclave
  con '-' por '\'>.reg, como un fichero de la carpeta de esa version (la de
  los .sdk y los .profile): CopiaDelIde le pone su carpeta y su sello, y
  CopiasDelIde la purga, igual que a un fichero (V10, 24-oct-2026: el
  registro del IDE se tocaba sin copia). }
function FicheroDeClaveDelIde(const AVersion, ASubclave: string): string;

{ LA clave corta de una carpeta, por su ruta CANONICA (larga, sin barra
  final, en minusculas): la misma carpeta escrita en 8.3 o con otras
  mayusculas da la misma clave, el MD5 en hexadecimal (32). La usan quien
  reclama una carpeta mientras vive (SoyLaPrimeraInstancia, la presencia)
  y la marca de los contenedores de delphi_test (Lsp.Sandbox). Estaba
  compuesta de tres formas, dos sin canonizar (revision de la 1.11.0). }
function ClaveDeCarpeta(const ADir: string): string;
{ EL nombre del mutex de una clave del servidor ('Global\DelphiLspMcp-' +
  AClave), el que ven todas sus instancias, el servicio y las de stdio: lo
  usan quien reclama algo mientras vive (ReclamaNombre) y quien hace algo de
  uno en uno entre procesos (la generacion de las tablas del disenador). }
function NombreDeMutex(const AClave: string): string;
{ EL trozo unico de un nombre que el servidor crea para UNA operacion (una
  carpeta de su temporal, el intermedio de una escritura, un zip a medias):
  8 hexadecimales en minusculas de un GUID. Estaba escrito a mano en siete
  sitios (revision de la 1.11.0, 2-oct-2026); su lector es
  FRAGMENTO_UNICO_PATRON. }
function FragmentoUnico: string;

{ EL sello de UNA operacion que tiene que ordenarse por cuando nacio y no
  chocar con otra del mismo milisegundo: 'yyyymmdd-hhnnsszzz-' +
  FragmentoUnico. Lo llevan el id de un trabajo de remote-run y el nombre de
  una captura; su lector es SELLO_UNICO_PATRON (la nota del deploy
  bloqueado lo busca en lo que contesta msbuild). }
function SelloUnico: string;

const
  // las formas de los dos de arriba, para quien las BUSCA: la inversa del
  // nombrador, nunca otra copia escrita a mano
  FRAGMENTO_UNICO_PATRON = '[0-9a-f]{8}';
  SELLO_UNICO_PATRON = '[0-9]{8}-[0-9]{9}-' + FRAGMENTO_UNICO_PATRON;

{ EL nombrador de la carpeta de descarga temporal ('__tmp-' + 8 hex) que
  crea quien baja algo de un target, y su lector: la unica carpeta fuera de
  una desechable que BorraArbol acepta, porque la acaba de crear el servidor. }
function NuevaCarpetaDescarga(const ADentroDe: string): string;
function EsCarpetaDescarga(const ANombre: string): Boolean;

{ EL normalizador de lo que un CLIENTE nombra y acaba en el disco (el
  agente de un buzon o de un informe, el titulo de un informe): letras y
  cifras ASCII, el resto se junta en un guion, 40 como mucho, minusculas.
  Nada del valor crudo llega al sistema de ficheros. Uno solo: estaba
  copiado identico en Mcp.Tools.Messages y Mcp.Tools.Report (25-sep-2026). }
function Slug(const S: string; const AConservar: string = ''): string;
{ La carpeta de un agente: Slug, sin juntar lo que su nombre separa (SanitizeAgent
  admite '.' y '_'): con Slug a secas, a.b, a_b y a-b compartian buzon. }
function SlugDeAgente(const S: string): string;

{ El nombre de la carpeta de copias ('__delphi-patch'), para quien tenga que
  reconocerla. Estaba declarada DOS veces, en Lsp.Patch y en Mcp.Tools.FileOps. }
function TrashFolderName: string;
{ La papelera de APath (un fichero o una carpeta): la __delphi-patch de su
  carpeta. LA forma de componerla: la escribian a mano tres sitios de
  Lsp.Patch (TrashDayDir con SinBarraFinal, BackupFile y el restore sin el;
  2.1f de la 1.18.0). }
function CarpetaDePapelera(const APath: string): string;
{ La carpeta del dia dentro de la papelera de APath. ASub: '' = la raiz del
  dia, un cajon (los CAJON_* de Lsp.Patch) = su carpeta. }
function TrashDayDir(const APath, ASub: string): string;
{ El nombre de la carpeta de un dia ('yyyymmdd') y su lector (reconoce ocho
  cifras: '12345678' cuenta como dia, y se purga si va antes del limite): la purga y el
  restore la reconocian a mano con una regex de ocho cifras, y la purga
  componia el limite con su propio FormatDateTime. }
function NombreDeDia(AFecha: TDateTime): string;
function EsCarpetaDeDia(const ANombre: string): Boolean;

{ La marca de dueno: su nombrador, su inversa y quien la reconoce. Estaba
  escrita a mano en catorce sitios. }
function MarcaDeDueno(const ACopia: string): string;
function CopiaDeLaMarca(const AMarca: string): string;
function EsMarcaDeDueno(const ARuta: string): Boolean;
{ La mascara de las marcas de una carpeta, para recorrerlas: la componia a
  mano Mcp.Tools.FileOps ('*' + la extension). }
function MascaraDeMarcas: string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Hash,
  System.SyncObjs, // TInterlocked: el sello estrictamente creciente
  Lsp.NetDrives,        // SinBarraFinal
  Lsp.Rutas,            // LongCanonical: la clave de una carpeta, por su forma canonica
  Lsp.Settings,         // CurrentWorkspaceName: el workspace del buzon lo pone el token
  Lsp.Pascal,           // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Texts;

const
  // la carpeta de la papelera: la nombran TrashFolderName y CarpetaDePapelera,
  // y nadie de fuera compone con ella (era publica: quien la usaba escapaba a
  // la regla '__delphi-patch' de test_paisaje)
  BACKUP_SUB = '__delphi-patch';
  { La marca de DUENO de una copia sellada: "<copia>.by", con el agente que la
    dejo (la purga solo deja purgar lo propio). }
  MARCA_DUENO_EXT = '.by';
  // el buzon de quien entra sin workspace y el prefijo del de un workspace:
  // Slug solo da letras, cifras y guiones, asi que ni un agente ni otro
  // workspace tienen una carpeta que se llame asi
  BUZON_SIN_WORKSPACE = '_local';
  BUZON_PREFIJO_WORKSPACE = 'Workspace.';
  // la carpeta de las copias de lo que el servidor pisa en el IDE, en su cache
  // (las baterias la leen de aqui, no a mano: revisor de version de la 1.18.0)
  IDE_COPIAS_SUB = 'ide-copias';
  // la carpeta de las capturas en la temporal del servidor (CasaDeCapturas)
  CAPTURAS_SUB = 'captures';

function TempFolderName: string;
begin
  Result := '__delphi-temp';
end;

function ServerDir(const ASub: string): string;
begin
  Result := TPath.GetDirectoryName(ParamStr(0));
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function ServerTempDir(const ASub: string): string;
begin
  Result := ServerDir(TempFolderName);
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function ServerCacheDir(const ASub: string): string;
begin
  Result := TPath.Combine(DatosDelUsuario('LOCALAPPDATA'), 'DelphiLspMcp');
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function CarpetaDeMensajes: string;
begin
  Result := ServerDir('messages');
end;

function CarpetaDeInformes: string;
begin
  Result := ServerDir('reports');
end;

function CarpetaDeWorkspace(const AWorkspace: string): string;
begin
  if AWorkspace = '' then
    Exit(BUZON_SIN_WORKSPACE);
  Result := Slug(AWorkspace);
  // el MD5 del nombre en minusculas: [Workspace.Claude] y [Workspace.claude]
  // son la misma seccion para el lector del ini
  if Result <> AnsiLowerCase(AWorkspace) then
    Result := Result + IfThen(Result <> '', '-') + LowerCase(
      THashMD5.GetHashString(AnsiLowerCase(AWorkspace))).Substring(0, 8);
  Result := BUZON_PREFIJO_WORKSPACE + Result;
end;

{ <ARaiz>\<la carpeta del workspace de la sesion>[\<SlugDeAgente(AAgente)>] }
function Buzon(const ARaiz, AAgente: string): string;
begin
  Result := TPath.Combine(ARaiz, CarpetaDeWorkspace(CurrentWorkspaceName));
  if SlugDeAgente(AAgente) <> '' then
    Result := TPath.Combine(Result, SlugDeAgente(AAgente));
end;

function BuzonDeMensajes(const AAgente: string): string;
begin
  Result := Buzon(CarpetaDeMensajes, AAgente);
end;

function CasaDeCapturas(const AAgente: string): string;
begin
  Result := Buzon(ServerTempDir(CAPTURAS_SUB), AAgente);
end;

function BuzonDeInformes(const AAgente: string): string;
begin
  Result := Buzon(CarpetaDeInformes, AAgente);
end;

{ La carpeta de las copias de APath: ide-copias\<la carpeta del original>. }
function CarpetaDeCopiasDelIde(const APath: string): string;
var
  Origen: string;
begin
  Origen := TPath.GetFileName(SinBarraFinal(TPath.GetDirectoryName(APath)));
  if Origen = '' then
    Origen := '_'; // la raiz de una unidad
  Result := ServerCacheDir(TPath.Combine(IDE_COPIAS_SUB, Origen));
end;

function CopiaDelIde(const APath: string): string;
begin
  Result := TPath.Combine(CarpetaDeCopiasDelIde(APath),
    SelloUnico + '-' + TPath.GetFileName(APath));
end;

function FicheroDeClaveDelIde(const AVersion, ASubclave: string): string;
begin
  Result := TPath.Combine(AVersion, ASubclave.Replace('\', '-') + '.reg');
end;

function CopiasDelIde(const APath: string): TArray<string>;
var
  Dir, Patron: string;
begin
  Result := nil;
  Dir := CarpetaDeCopiasDelIde(APath);
  if not TDirectory.Exists(Dir) then
    Exit;
  Patron := '^' + SELLO_UNICO_PATRON + '-' + TRegEx.Escape(TPath.GetFileName(APath)) + '$';
  for var F in TDirectory.GetFiles(Dir) do
    if TRegEx.IsMatch(TPath.GetFileName(F), Patron, [roIgnoreCase]) then
      Result := Result + [F];
  // el sello empieza por la fecha y la hora: el orden del texto es el del tiempo
  TArray.Sort<string>(Result);
end;

function CarpetasDeLaCasa: TArray<string>;
begin
  Result := [CarpetaDeMensajes, CarpetaDeInformes];
  if EsRutaAbsoluta(ServerCacheDir) then
    Result := Result + [ServerCacheDir];
end;

function FragmentoUnico: string;
begin
  Result := LowerCase(TGUID.NewGuid.ToString.Substring(1, 8));
end;

var
  // el ultimo milisegundo sellado (el de TTimeStamp, desde el 1-1-1)
  GUltimoSello: Int64 = 0;

function SelloUnico: string;
var
  Visto, Ms: Int64;
  TS: TTimeStamp;
  A, M, D: Word;
begin
  // La hora de Windows avanza a saltos del tick (unos 15,6 ms): dos sellos del
  // mismo tick salian con la MISMA hora y los ordenaba el trozo aleatorio. La
  // purga de las copias del IDE se queda con las 10 mas nuevas POR EL NOMBRE
  // (CopiasDelIde) y podia borrar la ultima (test_sdk "por azar", 1.18.2). En
  // el proceso, estrictamente creciente: uno del mismo milisegundo que el
  // ultimo, o de antes, es el ultimo + 1. El texto, el de siempre
  // (SELLO_UNICO_PATRON lo sigue leyendo).
  repeat
    Visto := TInterlocked.Read(GUltimoSello);
    TS := DateTimeToTimeStamp(Now);
    Ms := Int64(TS.Date) * MSecsPerDay + TS.Time;
    if Ms <= Visto then
      Ms := Visto + 1;
  until TInterlocked.CompareExchange(GUltimoSello, Ms, Visto) = Visto;
  TS.Date := Ms div MSecsPerDay;
  TS.Time := Ms mod MSecsPerDay;
  DecodeDate(TimeStampToDateTime(TS), A, M, D);
  Result := Format('%.4d%.2d%.2d-%.2d%.2d%.2d%.3d-%s', [A, M, D, TS.Time div 3600000,
    TS.Time div 60000 mod 60, TS.Time div 1000 mod 60, TS.Time mod 1000, FragmentoUnico]);
end;

const
  DESCARGA_PREFIJO = '__tmp-'; // empieza por __, como toda zona borrable

function NuevaCarpetaDescarga(const ADentroDe: string): string;
begin
  Result := TPath.Combine(ADentroDe, DESCARGA_PREFIJO + FragmentoUnico);
end;

function EsCarpetaDescarga(const ANombre: string): Boolean;
begin
  // la inversa exacta del nombrador: el prefijo y 8 hexadecimales
  Result := TRegEx.IsMatch(ANombre, '^' + TRegEx.Escape(DESCARGA_PREFIJO) +
    FRAGMENTO_UNICO_PATRON + '$', [roIgnoreCase]);
end;

function SlugDeAgente(const S: string): string;
begin
  Result := Slug(S, '._');
end;

function Slug(const S: string; const AConservar: string): string;
var
  C, Prev: Char;
begin
  Result := '';
  Prev := '-';
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) or (Pos(C, AConservar) > 0) then
    begin
      Result := Result + C;
      Prev := C;
    end
    else if Prev <> '-' then
    begin
      Result := Result + '-';
      Prev := '-';
    end;
    if Length(Result) >= 40 then
      Break;
  end;
  // (un '.' de los extremos tampoco: Windows lo recorta, y '..' no es un nombre)
  Result := SinMayusculas(Result.Trim(['-', '.']));
end;

function NombreDeMutex(const AClave: string): string;
begin
  Result := 'Global\DelphiLspMcp-' + AClave;
end;

function ClaveDeCarpeta(const ADir: string): string;
begin
  // AnsiLowerCase y no LowerCase: la de la RTL solo pliega A-Z, y 'C:\Ñ' y
  // 'C:\ñ' son la misma carpeta (revision de la 1.11.0). Y NO ClaveDeRuta, a
  // proposito (V105 de la 1.23.1): esta clave NOMBRA cosas de fuera del
  // proceso - el mutex de la primera instancia y la marca de los contenedores
  // del sandbox (Lsp.Sandbox.MarcaDeEstaCasa), que la purga busca por ella -, y
  // cambiarla dejaria sin purgar los contenedores de la marca vieja. Lo que el
  // locale junta y NTFS separa solo cuenta con dos servidores en carpetas que
  // difieran en eso: compartirian la primera instancia (el segundo no purga la
  // temporal) y la marca de sus contenedores (WATCH)
  Result := LowerCase(THashMD5.GetHashString(
    AnsiLowerCase(SinBarraFinal(LongCanonical(ADir)))));
end;

function TrashFolderName: string;
begin
  Result := BACKUP_SUB;
end;

function CarpetaDePapelera(const APath: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(SinBarraFinal(APath)), BACKUP_SUB);
end;

function TrashDayDir(const APath, ASub: string): string;
begin
  Result := TPath.Combine(CarpetaDePapelera(APath), NombreDeDia(Now));
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function NombreDeDia(AFecha: TDateTime): string;
begin
  Result := FormatDateTime('yyyymmdd', AFecha);
end;

function EsCarpetaDeDia(const ANombre: string): Boolean;
begin
  Result := TRegEx.IsMatch(ANombre, '^\d{8}$');
end;

function MarcaDeDueno(const ACopia: string): string;
begin
  Result := ACopia + MARCA_DUENO_EXT;
end;

function EsMarcaDeDueno(const ARuta: string): Boolean;
begin
  Result := EndsText(MARCA_DUENO_EXT, ARuta);
end;

function MascaraDeMarcas: string;
begin
  Result := '*' + MARCA_DUENO_EXT;
end;

function CopiaDeLaMarca(const AMarca: string): string;
begin
  Result := AMarca;
  if EsMarcaDeDueno(AMarca) then
    SetLength(Result, Length(AMarca) - Length(MARCA_DUENO_EXT));
end;

end.