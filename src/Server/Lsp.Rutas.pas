unit Lsp.Rutas;

{ LAS RUTAS CANONICAS: la forma con la que el servidor compara un sitio con
  otro. LongCanonical deshace los alias 8.3, RealPath sigue junctions y
  symlinks hasta el destino de verdad, FormaLarga es la forma de COMPARAR y
  EnLugar es EL comparador de "esta en ese sitio".

  Salen de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidas sin cambiar una linea. El grafo de dependencias de Guard dijo que
  estas siete piezas no usan nada de la jaula y que las usan la jaula, el
  lector del settings.ini y la casa del servidor: debajo de los tres,
  ninguno tiene que pasar por Guard para canonicalizar. No usa ninguna
  unidad del servidor salvo Lsp.NetDrives (las formas de una raiz). }

interface

{ The SAME directory can be named more than one way, and a guard that matches a
  path segment literally is blind to every alias. NTFS keeps an 8.3 short name
  for each entry ("__delphi-patch" also answers to "__DELP~1"), and it resolves
  to the identical folder - so a path through "__DELP~1" walked straight past
  the trash guard and reopened writing into the recoverable copies (measured
  2026-08-25).

  This expands the longest existing prefix of a path back to its real names
  before any segment guard looks at it. It cannot blanket-reject "~": the
  server's own scratch and home paths legitimately contain one (DFONTA~1). }
function LongCanonical(const APath: string): string;

{ LA ruta REAL: junctions y symlinks resueltos, nombres largos (la nota
  larga, en la implementacion). Publica para COMPARAR y reconocer - una
  clave de visitados que corta un ciclo de enlaces, un "esta dentro de" -,
  nunca para decidir un permiso por tu cuenta: eso es de las puertas. }
function RealPath(const APath: string): string;

{ La forma con la que se COMPARA un sitio con otro: la canonica LARGA, con
  separador final. Una raiz declarada con nombres cortos (DFONTA~1) y una
  ruta que llega con OTROS nombres cortos (DELPHI~1\RESULT~1) son el mismo
  sitio, y por el texto no casaban: la jaula decia "fuera" de una carpeta
  suya (28-sep, medido). Todas las comparaciones de sitio la usan A LA VEZ -
  contencion (PathDenied), identidad (RootItselfDenied), confinamiento,
  referencias, el vault, los lugares protegidos, lo protegido de la purga -:
  si solo la usase una, un sitio por su alias 8.3 seria "dentro" para una y
  "otro" para la de al lado, y se podria borrar (el incidente de las dos
  formas del CLAUDE.md; la sexta revision lo midio con la raiz de OTRO
  workspace, un ReadOnlyPaths, una referencia y el vault). La separacion
  final se conserva: quitarla antes convertia "D:\" en "D:", la carpeta
  actual. }
function FormaLarga(const APath: string): string;

{ APath ES ALugar o esta DENTRO, los dos en la forma larga: EL comparador
  de "esta en ese sitio". Un lugar vacio no contiene nada. }
function EnLugar(const APath, ALugar: string;
  AResuelveAlias: Boolean = True): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Lsp.NetDrives;        // RaizSiUnidad, SinBarraFinal, PrefijoSinBarra

{ El nombre FINAL de una ruta que existe: sigue junctions y symlinks hasta su
  destino de verdad. False si no se puede abrir (no existe, o no hay permiso
  ni para preguntar). Acceso 0 = solo consultar, y FILE_FLAG_BACKUP_SEMANTICS
  hace falta para poder abrir CARPETAS. }
{ EL paseo hacia arriba, escrito UNA vez. Dada una ruta, busca el antecesor
  existente mas cercano que AResuelve sepa traducir y le vuelve a pegar el
  resto: el ultimo tramo de un create o un upload todavia no existe, y aun asi
  hay que canonicalizar el camino ANTES de que ningun guarda lo mire.

  Estaba escrito DOS veces. LongCanonical lo tenia desde siempre (8.3 ->
  nombre largo), y el 20-sep-2026, para cerrar el escape por junctions, escribi
  RealPath con el MISMO bucle y otra llamada de Windows - sin mirar si habia
  algo aprovechable, teniendolo en esta misma unidad. Entre las dos cambia UNA
  linea, el resolutor; el paseo era identico. Ahora es uno. }
type
  TResuelveTramo = reference to function(const ADir: string;
    out ASalida: string): Boolean;

function CanonicalSubiendo(const AFull: string;
  const AResuelve: TResuelveTramo): string;
var
  Dir, Tail, Parent, Resuelto: string;
begin
  Dir := AFull;
  Tail := '';
  while Dir <> '' do
  begin
    if AResuelve(Dir, Resuelto) then
    begin
      Result := Resuelto;
      if Tail <> '' then
        Result := IncludeTrailingPathDelimiter(Result) + Tail;
      Exit;
    end;
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = '') or SameText(Parent, Dir) then
      Break;
    if Tail = '' then
      Tail := TPath.GetFileName(Dir)
    else
      Tail := TPath.GetFileName(Dir) + '\' + Tail;
    Dir := Parent;
  end;
  Result := AFull; // nada del camino existe: se queda la forma textual
end;

function NombreFinal(const APath: string; out AReal: string): Boolean;
var
  H: THandle;
  Len: DWORD;
  Buf: array [0 .. 32767] of Char;
begin
  Result := False;
  AReal := '';
  H := CreateFile(PChar(APath), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    // flags 0 = FILE_NAME_NORMALIZED + VOLUME_NAME_DOS, que es lo que
    // queremos: la ruta con letra de unidad, normalizada.
    Len := GetFinalPathNameByHandle(H, Buf, Length(Buf) - 1, 0);
    if (Len = 0) or (Len >= DWORD(Length(Buf))) then
      Exit;
    SetString(AReal, PChar(@Buf[0]), Len);
    // GetFinalPathNameByHandle devuelve la forma extendida.
    if AReal.StartsWith('\\?\UNC\') then
      AReal := '\\' + AReal.Substring(8)
    else if AReal.StartsWith('\\?\') then
      AReal := AReal.Substring(4);
    Result := AReal <> '';
  finally
    CloseHandle(H);
  end;
end;

{ LA RUTA REAL, que es contra la que hay que medir la jaula.

  TPath.GetFullPath normaliza el TEXTO y no sigue reparse points, asi que un
  junction o un symlink creado DENTRO del root apuntando fuera pasaba el
  control y el sistema de ficheros servia el destino de verdad. Medido el
  2026-09-20 por un agente auditor: un junction a
  C:\Windows\System32\drivers\etc dentro del root hizo que delphi_list y
  delphi_read devolvieran el hosts de la maquina. Y no hace falta consola para
  plantarlo: un git clone con core.symlinks=true mete el enlace sin salir del
  MCP, o sea que era alcanzable por el propio agente.

  Si la ruta NO existe todavia (crear un fichero nuevo, por ejemplo), se
  resuelve el ANTECESOR existente mas cercano y se le vuelve a pegar el resto:
  lo que importa es que ningun tramo del camino salte fuera. Si no existe
  nada del camino, se queda la normalizacion textual, que es lo que habia. }
function RealPath(const APath: string): string;
var
  Base: string;
begin
  Result := APath;
  try
    // (la raiz de una unidad, con su barra: una unidad a secas es para
    // Windows su carpeta ACTUAL, y de ahi salia la ruta real de la carpeta
    // desde la que corre el servidor en vez de la de la raiz. Lsp.NetDrives)
    Base := SinBarraFinal(TPath.GetFullPath(RaizSiUnidad(APath)));
  except
    Exit;
  end;
  Result := CanonicalSubiendo(Base,
    function(const ADir: string; out ASalida: string): Boolean
    var
      A: Cardinal;
    begin
      // Un fichero NORMAL no se abre: solo un enlace redirige, y su ruta real
      // es la real de su carpeta mas su nombre largo (LongCanonical no abre
      // el fichero). Abrirlo para pedirle el nombre final le quitaba el
      // rename a otro escritor en ese instante: con un handle abierto, aunque
      // comparta el borrado, MoveFileEx no puede reemplazarlo - "rename
      // atomico fallido" y una edicion perdida en test_concurrencia (A y C,
      // 25-sep-2026, al crecer las comparaciones por ruta real).
      A := GetFileAttributes(PChar(ADir));
      if (A <> INVALID_FILE_ATTRIBUTES) and
         ((A and (FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_REPARSE_POINT)) = 0) then
      begin
        Result := NombreFinal(TPath.GetDirectoryName(ADir), ASalida);
        if Result then
          ASalida := IncludeTrailingPathDelimiter(PrefijoSinBarra(ASalida)) +
            TPath.GetFileName(LongCanonical(ADir));
        Exit;
      end;
      Result := NombreFinal(ADir, ASalida);
      if Result then
        ASalida := SinBarraFinal(ASalida);
    end);
end;

function LongCanonical(const APath: string): string;
var
  Full: string;
begin
  Full := TPath.GetFullPath(RaizSiUnidad(APath)).Replace('/', '\');
  if Full.IndexOf('~') < 0 then
    Exit(Full); // sin 8.3 que deshacer, no se paga el paseo
  Result := CanonicalSubiendo(Full,
    function(const ADir: string; out ASalida: string): Boolean
    var
      Buf: array [0 .. 2047] of Char;
      N: DWORD;
    begin
      N := GetLongPathName(PChar(ADir), @Buf[0], Length(Buf));
      Result := (N > 0) and (N < DWORD(Length(Buf)));
      if Result then
        SetString(ASalida, PChar(@Buf[0]), N);
    end);
end;

function FormaLarga(const APath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(LongCanonical(APath));
end;

function EnLugar(const APath, ALugar: string; AResuelveAlias: Boolean): Boolean;
begin
  Result := False;
  if (APath.Trim = '') or (ALugar.Trim = '') then
    Exit;
  try
    var Ruta := IncludeTrailingPathDelimiter(APath.Trim);
    var Lugar := IncludeTrailingPathDelimiter(ALugar.Trim);
    if AResuelveAlias then
    begin
      Ruta := FormaLarga(APath.Trim);
      Lugar := FormaLarga(ALugar.Trim);
    end;
    Result := StartsText(Lugar, Ruta);
  except
    Result := False; // una ruta que no parsea no esta en ningun sitio
  end;
end;

end.
