unit Lsp.Casa;

{ LA CASA DEL SERVIDOR: los nombradores de sus carpetas (ServerDir, la
  temporal, las caches de LOCALAPPDATA), de los nombres unicos que crea
  para una operacion (FragmentoUnico, SelloUnico, la carpeta de descarga) y
  de sus mutex, y el normalizador de lo que un cliente nombra (Slug). Nadie
  compone una de esas rutas o nombres a mano: se piden aqui.

  Salen de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidos sin cambiar una linea. Solo los nombradores: no usan nada de la
  jaula, y los usan la jaula y el lector del settings.ini (SettingsIniPath).
  Lo que se hace CON esas carpetas - los entregables del agente
  (AgentTempDir, CaptureTarget), la purga del arranque y la presencia de
  instancias - pregunta a las puertas y se queda en Lsp.Guard. }

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
{ Un fichero de una de las casas del servidor (sus caches: la configuracion
  fabricada para el motor, las tablas del disenador) ENTERO o nada: se
  escribe al lado y se renombra encima, porque otro hilo puede estar
  leyendolo en ese momento. Si el renombrado no puede (alguien lo tiene
  abierto) y el fichero ya esta, vale el que esta; sin ninguno, se lanza el
  error. Es casa del servidor: no pasa por la jaula. Las dos copias de esto
  (Lsp.ConfigFabricator y el generador de las tablas) eran la segunda vez. }
procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);

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

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Hash,
  Lsp.NetDrives,        // SinBarraFinal
  Lsp.Rutas,            // LongCanonical: la clave de una carpeta, por su forma canonica
  Lsp.Texts;

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

procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);
var
  Tmp: string;
  Err: DWORD;
begin
  // el escritor pregunta EL MISMO (revision de la 1.12.0): escribe solo DENTRO
  // de la casa de caches, y esa casa tiene que ser una ruta absoluta: con
  // LOCALAPPDATA vacia ServerCacheDir es relativa y caeria en la carpeta de
  // trabajo del proceso (System32 en el servicio). Por el TEXTO canonico, no
  // por la ruta real: lo que se guarda es un error de composicion (esa
  // carpeta no la toca ningun agente), y bajo la virtualizacion de un
  // paquete MSIX una subcarpeta recien creada tiene OTRA ruta real que su
  // padre (medido el 4-oct-2026 desde la app de escritorio de Claude:
  // ...\Packages\Claude_...\LocalCache\Local\DelphiLspMcp\designer)
  if not TPath.IsPathRooted(ServerCacheDir) or
     not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(ServerCacheDir)),
       TPath.GetFullPath(AFichero)) then
    raise EInOutError.Create(MsgFmt(SL_CASA_FUERA_FMT, [AFichero, ServerCacheDir]));
  Tmp := AFichero + '.' + IntToStr(GetCurrentThreadId) + '.tmp';
  try
    TFile.WriteAllText(Tmp, ATexto, TEncoding.UTF8);
  except
    // a medias no se queda: un .tmp suelto no lo ve nadie para borrarlo
    System.SysUtils.DeleteFile(Tmp);
    raise;
  end;
  if not MoveFileEx(PChar(Tmp), PChar(AFichero), MOVEFILE_REPLACE_EXISTING) then
  begin
    Err := GetLastError;
    System.SysUtils.DeleteFile(Tmp);
    if not FileExists(AFichero) then
      RaiseLastOSError(Err);
  end;
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

end.