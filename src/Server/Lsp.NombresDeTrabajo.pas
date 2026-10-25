unit Lsp.NombresDeTrabajo;

{ LOS nombres de los ficheros de un trabajo de remote-run, en UN sitio: los
  compone el servidor (Lsp.RemoteRun), los lee el lanzador del destino
  (src\RunJob\McpRunJob.dpr, en Linux y en Windows) y la nota de un deploy
  bloqueado (Lsp.BuildRunner) busca el del vigia. Estaban compuestos a mano en
  siete sitios y leidos de tres formas, y el id de un trabajo lo validaban dos
  gemelos con reglas distintas (el del lanzador limitaba el largo; V38-P5 de
  la 1.23). Cada nombre con su inversa. Solo System.SysUtils: lo compila
  tambien el lanzador de Linux.

  En la carpeta del proyecto en el destino (el scratch-dir de PAServer):
    run-<job>[.exe]        el lanzador (McpRunJob con el nombre del trabajo)
    run-<job>.job          el trabajo: binario, salida, un argumento por linea
    <job>.out              la salida del programa (y las marcas ___ENV, ___RC)
    <job>.pid              el pid mientras vive (lo escribe y lo borra el vigia)
    <job>.wait.<pid>.exe   el vigia de Windows (el pid va en su nombre) }

interface

const
  { Los vigias de TODOS los trabajos de una carpeta, como mascara (lo que barre
    el --Remove de un trabajo que acabo; tambien la forma vieja,
    <job>.wait.exe)... }
  MASCARA_DE_LOS_VIGIAS = '*.wait*.exe';
  { ...y como patron detras del de un id (la nota del deploy bloqueado lo
    busca en lo que contesta msbuild, Lsp.Casa.SELLO_UNICO_PATRON delante). }
  PATRON_DEL_VIGIA_TRAS_EL_ID = '\.wait(?:\.[0-9]+)?\.exe';

{ Si AId tiene la forma de un id de trabajo, el que compone el servidor
  (Lsp.Casa.SelloUnico: fecha-hora-fragmento): solo [0-9a-f-] y 64 como
  mucho. Otra cosa no es un id y nadie la usa para nombrar un fichero. }
function EsIdDeTrabajo(const AId: string): Boolean;
{ El lanzador del trabajo AJob en el destino: run-<job>.exe en Windows,
  run-<job> en Linux (PAServer arranca un PE con flag 5 y un ELF con flag 3). }
function NombreDelLanzador(const AJob: string; AWindows: Boolean): string;
{ La inversa: el trabajo del lanzador ANombre (un nombre o una ruta, con su
  .exe o sin el), o '' si no es el de un lanzador. }
function TrabajoDelLanzador(const ANombre: string): string;
{ El fichero del trabajo AJob: run-<job>.job. }
function NombreDelTrabajo(const AJob: string): string;
{ La salida del trabajo AJob: <job>.out. }
function NombreDeLaSalida(const AJob: string): string;
{ La inversa: el trabajo de una salida (un nombre o una ruta), o ''. }
function TrabajoDeLaSalida(const ASalida: string): string;
{ El pid del trabajo AJob mientras vive: <job>.pid. }
function NombreDelPid(const AJob: string): string;
{ El vigia de Windows del trabajo AJob, con el pid del programa en el nombre:
  <job>.wait.<pid>.exe (un deploy fallido borra el .pid, pero no el vigia
  mientras vive). }
function NombreDelVigia(const AJob: string; APid: Int64): string;
{ Los vigias del trabajo AJob, como mascara: <job>.wait.*.exe. }
function MascaraDeLosVigiasDe(const AJob: string): string;
{ La inversa de NombreDelVigia: el pid de un vigia de AJob por su nombre, o 0
  si ANombre no lo es. }
function PidDelNombreDeVigia(const AJob, ANombre: string): Int64;

implementation

uses
  System.SysUtils;

const
  PREFIJO_LANZADOR = 'run-';
  EXT_TRABAJO = '.job';
  EXT_SALIDA = '.out';
  EXT_PID = '.pid';
  EXT_EXE = '.exe';
  MARCA_VIGIA = '.wait.';

function EsIdDeTrabajo(const AId: string): Boolean;
var
  C: Char;
begin
  Result := (AId <> '') and (Length(AId) <= 64);
  if Result then
    for C in AId do
      if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F', '-']) then
        Exit(False);
end;

function NombreDelLanzador(const AJob: string; AWindows: Boolean): string;
begin
  Result := PREFIJO_LANZADOR + AJob;
  if AWindows then
    Result := Result + EXT_EXE;
end;

function TrabajoDelLanzador(const ANombre: string): string;
var
  N: string;
begin
  Result := '';
  N := ExtractFileName(ANombre);
  if SameText(ExtractFileExt(N), EXT_EXE) then
    N := ChangeFileExt(N, '');
  if SameText(Copy(N, 1, Length(PREFIJO_LANZADOR)), PREFIJO_LANZADOR) then
    Result := Copy(N, Length(PREFIJO_LANZADOR) + 1, MaxInt);
end;

function NombreDelTrabajo(const AJob: string): string;
begin
  Result := PREFIJO_LANZADOR + AJob + EXT_TRABAJO;
end;

function NombreDeLaSalida(const AJob: string): string;
begin
  Result := AJob + EXT_SALIDA;
end;

function TrabajoDeLaSalida(const ASalida: string): string;
var
  N: string;
begin
  Result := '';
  N := ExtractFileName(ASalida);
  if SameText(ExtractFileExt(N), EXT_SALIDA) then
    Result := ChangeFileExt(N, '');
end;

function NombreDelPid(const AJob: string): string;
begin
  Result := AJob + EXT_PID;
end;

function NombreDelVigia(const AJob: string; APid: Int64): string;
begin
  Result := AJob + MARCA_VIGIA + IntToStr(APid) + EXT_EXE;
end;

function MascaraDeLosVigiasDe(const AJob: string): string;
begin
  Result := AJob + MARCA_VIGIA + '*' + EXT_EXE;
end;

function PidDelNombreDeVigia(const AJob, ANombre: string): Int64;
var
  N, Prefijo: string;
begin
  Result := 0;
  N := ExtractFileName(ANombre);
  Prefijo := AJob + MARCA_VIGIA;
  if SameText(Copy(N, 1, Length(Prefijo)), Prefijo) and SameText(ExtractFileExt(N), EXT_EXE) then
    Result := StrToInt64Def(ChangeFileExt(Copy(N, Length(Prefijo) + 1, MaxInt), ''), 0);
end;

end.
