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

  DOS CASAS, y el criterio es el mismo que separa a __delphi-temp de
  __delphi-patch:

    ServerTempDir  lo que es del SERVIDOR y el agente no toca nunca (el
                   fichero del mensaje de git, la descarga de un SDK, el
                   guion que se manda a un target). Va JUNTO AL EJECUTABLE,
                   como reports\ y settings.ini, y se puede borrar en
                   cualquier momento: nada de lo que hay ahi sobrevive a la
                   llamada que lo creo. No pasa por la jaula porque no es
                   una ruta que elija nadie de fuera.

    AgentTempDir   lo que el agente tiene que ALCANZAR: una captura que se
                   baja con delphi_fetch, una salida que se lee. Va DENTRO
                   del workspace, porque delphi_fetch comprueba la jaula y
                   un entregable fuera de ella es un entregable que no se
                   puede entregar (medido: el flujo documentado de
                   delphi_desktop estaba roto de punta a punta). Y con la
                   carpeta del agente, porque una jaula puede estar
                   compartida por varios: la captura de uno no se le pone
                   delante a otro.

  Componen la ruta y ya: crear la carpeta es de quien la use. }
function TempFolderName: string;
{ <carpeta del exe>\ASub: LA casa del servidor. Todo lo que el servidor
  guarda o busca junto a si mismo (settings.ini, __delphi-temp, logs,
  messages, reports, node, el conversor de estilos) se compone aqui; hasta
  el 26-sep lo componian a mano ocho sitios. Sin ASub, la carpeta. }
function ServerDir(const ASub: string = ''): string;
function ServerTempDir(const ASub: string = ''): string;
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

{ LA clave corta de una carpeta, por su ruta CANONICA (larga, sin barra
  final, en minusculas): la misma carpeta escrita en 8.3 o con otras
  mayusculas da la misma clave, el MD5 en hexadecimal (32). La usan quien
  reclama una carpeta mientras vive (TemporalEsMia, SoyLaPrimeraInstancia)
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
function Slug(const S: string): string;

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
  Lsp.NetDrives,        // SinBarraFinal
  Lsp.Rutas,            // LongCanonical: la clave de una carpeta, por su forma canonica
  Lsp.Settings,         // CurrentWorkspaceName: el workspace del buzon lo pone el token
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
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'DelphiLspMcp');
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

{ <ARaiz>\<la carpeta del workspace de la sesion>[\<Slug(AAgente)>] }
function Buzon(const ARaiz, AAgente: string): string;
begin
  Result := TPath.Combine(ARaiz, CarpetaDeWorkspace(CurrentWorkspaceName));
  if Slug(AAgente) <> '' then
    Result := TPath.Combine(Result, Slug(AAgente));
end;

function BuzonDeMensajes(const AAgente: string): string;
begin
  Result := Buzon(CarpetaDeMensajes, AAgente);
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
  Result := ServerCacheDir(TPath.Combine('ide-copias', Origen));
end;

function CopiaDelIde(const APath: string): string;
begin
  Result := TPath.Combine(CarpetaDeCopiasDelIde(APath),
    SelloUnico + '-' + TPath.GetFileName(APath));
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

function SelloUnico: string;
begin
  Result := FormatDateTime('yyyymmdd"-"hhnnsszzz', Now) + '-' + FragmentoUnico;
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

function Slug(const S: string): string;
var
  C, Prev: Char;
begin
  Result := '';
  Prev := '-';
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
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
  Result := Result.Trim(['-']).ToLower;
end;

function NombreDeMutex(const AClave: string): string;
begin
  Result := 'Global\DelphiLspMcp-' + AClave;
end;

function ClaveDeCarpeta(const ADir: string): string;
begin
  // AnsiLowerCase y no LowerCase: la de la RTL solo pliega A-Z, y 'C:\Ñ' y
  // 'C:\ñ' son la misma carpeta (revision de la 1.11.0)
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