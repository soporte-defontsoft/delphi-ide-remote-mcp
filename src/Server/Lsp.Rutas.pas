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
  unidad del servidor salvo Lsp.NetDrives (las formas de una raiz).

  Y los predicados de la FORMA de una ruta, que tampoco usan nada de la
  jaula: EsRutaAbsoluta (la ruta completa), EsUnc y EsPrefijoDeDispositivo.
  Llegan de Lsp.Guard el mismo dia, sin cambiar una linea: la segunda de
  las cuatro mudanzas que sacan de Guard la mascara de unidades. }

interface

{ The SAME directory can be named more than one way, and a guard that matches a
  path segment literally is blind to every alias. NTFS keeps an 8.3 short name
  for each entry ("__delphi-patch" also answers to "__DELP~1"), and it resolves
  to the identical folder - so a path through "__DELP~1" walked straight past
  the trash guard and reopened writing into the recoverable copies (measured
  2026-08-25).

  This expands the longest existing prefix of a path back to its real names
  before any segment guard looks at it. It cannot blanket-reject "~": the
  server's own scratch and home paths legitimately contain one (DFONTA~1).
  Siempre con barras de Windows: quien la usa no las vuelve a cambiar. }
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
  de "esta en ese sitio". Un lugar vacio no contiene nada. Como RealPath,
  para COMPARAR, nunca para decidir un permiso por tu cuenta: con
  AResuelveAlias=False compara el texto tal cual (ni ..\ ni alias 8.3), y
  eso solo vale con dos rutas que ya llegan en la misma forma. }
function EnLugar(const APath, ALugar: string;
  AResuelveAlias: Boolean = True): Boolean;

{ AReal (una ruta REAL, RealPath) esta en alguno de ALugares, cada uno por
  SU ruta real: la comparacion de los lugares de las puertas (Lsp.Patch) y de
  la zona de biblioteca de la jaula (Lsp.Guard.JaulaDecide, que la juzgaba
  por el TEXTO: M1 de la 1.18.0). Estaba en Lsp.Patch, donde la jaula no la
  alcanza. Mismo aviso que RealPath: para comparar. }
function EnAlgunLugar(const AReal: string; const ALugares: TArray<string>): Boolean;

{ ARuta, en una letra LOCAL de esta sesion, no puede estar en ALugar si ese
  lugar es de RED: un UNC, o una letra que no es local (de red o que no
  esta). Se dice con la tabla de unidades (ClaseDeLetra), sin mirar el lugar
  en el disco: un recurso de red caido son 21 s por pregunta, y EnLugar y
  EnAlgunLugar lo preguntaban en cada escritura por cada vault (B-10; David,
  10-oct-2026: "una ruta local no puede estar en un vault de red"). }
function LugarDeRedParaRutaLocal(const ARuta, ALugar: string): Boolean;

{ LA regla de "ruta completa": <letra>:\ (o :/) o un UNC. "\x", "/x" y "C:x"
  NO lo son, y TPath.IsPathRooted si las da por buenas: se resolvian contra
  la unidad o la carpeta del PROCESO, que el agente no nombro. Toda tool que
  pregunte "me han dado una ruta completa?" pregunta esto. }
function EsRutaAbsoluta(const AValue: string): Boolean;

{ AValor, una ruta ESCRITA en un fichero (un .dproj, un .groupproj, un .rc,
  un form, un $I) o en un valor del IDE, resuelta como la resuelve Windows
  para un proceso cuya carpeta actual es ABase: la de quien la LEE - msbuild
  corre en la del .dproj (Lsp.BuildRunner), el motor en la de su fuente
  principal, el ayudante del render en la del form, Windows sigue un enlace
  relativo desde la suya (DestinoDeEnlace) -. Completa, tal cual (sin .. ni
  barras normales); relativa, desde ABase; "\x", en la raiz de la unidad de
  ABase; "X:y", desde ABase si X es su unidad. '' si no se resuelve: "X:y"
  de OTRA unidad (su carpeta actual es la del proceso que la lea, y no la
  nombra nadie), lo que no es completo sin una ABase completa (un valor del
  registro del IDE no tiene carpeta) o lo que GetFullPath no entiende. Quien
  juzga niega lo que no se resuelve; quien busca se lo salta.
  TPath.IsPathRooted da por completas "\x" y "X:y", y GetFullPath las
  resolvia contra el PROCESO del servidor: el juez de los literales del
  render miraba en una unidad lo que el ayudante lee en otra (A9 de la 1.23,
  medido por test_rutas_a_medias_1230). Era la tripleta IsPathRooted +
  Combine + GetFullPath, a mano en una docena de sitios, cuatro de ellos en la
  puerta del build (la puerta miraba en la unidad del proceso lo que msbuild
  lee en la del proyecto: A9b, medido).
  ACarpetaActual: la carpeta actual de quien lee cuando no es la del fichero
  que la escribe - dcc abre un $I relativo desde la carpeta del fuente, y
  "\x" o "X:y" desde la suya, la del .dproj; msbuild, un Import relativo
  desde la del fichero que lo escribe -. Vacia, ABase. }
function RutaDesde(const ABase, AValor: string; const ACarpetaActual: string = ''): string;

{ Una ruta A MEDIAS: "\x" (o "/x"), la raiz de la unidad ACTUAL de quien la
  lea, o "X:y", la carpeta actual de esa unidad. Ni completa ni relativa a
  una carpeta: TPath.IsPathRooted la da por completa. La regla de RutaDesde,
  y la de quien niega lo que escribe el agente (CFG-109) o la puerta del
  build que no la sabe resolver (otra unidad). }
function EsRutaAMedias(const AValor: string): Boolean;

{ Un prefijo de DISPOSITIVO o de ruta extendida (\\?\, \\.\, tambien con
  barras normales): la entrada lo niega (GUARD-022) y nadie lo resuelve en
  el disco. Estaba escrito dos veces, y NormPath resolvia un \\?\UNC\ leido
  de un .dpr: SMB hacia ese host, 21 s (novena revision). }
function EsPrefijoDeDispositivo(const APath: string): Boolean;
{ ...y la ruta sin el: \\?\C:\x -> C:\x, \\?\UNC\host\x -> \\host\x (lo que
  devuelve GetFinalPathNameByHandle, y lo que un .dproj puede traer en un
  search path: dcc abre una carpeta por ese prefijo, medido el 21-oct-2026, y
  la puerta del build lo juzga sin el). Sin prefijo, tal cual. }
function SinPrefijoDeDispositivo(const APath: string): string;

{ Un UNC de verdad (\\host\...), no un prefijo de dispositivo (\\?\, \\.\).
  Con cualquiera de las dos barras (//host/x tambien lo es: A40 de la 1.23,
  medido). LA pregunta de quien mira un UNC por su texto: estaba escrita en
  cuatro sitios (tercer revisor de la 1.8.2). }
function EsUnc(const APath: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Lsp.NetDrives;        // RaizSiUnidad, SinBarraFinal, PrefijoSinBarra, ConBarrasDeWindows

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

{ El nombre FINAL de una ruta que existe: sigue junctions y symlinks hasta su
  destino de verdad. False si no se puede abrir (no existe, o no hay permiso
  ni para preguntar). Acceso 0 = solo consultar, y FILE_FLAG_BACKUP_SEMANTICS
  hace falta para poder abrir CARPETAS. }
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
    // GetFinalPathNameByHandle devuelve la forma extendida (EL quitador del
    // prefijo, el de la puerta del build tambien)
    AReal := SinPrefijoDeDispositivo(AReal);
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
{ El DESTINO de un enlace (junction o symlink) por lo que guarda el propio
  enlace - lo que contesta Windows de su punto de reanalisis
  (FSCTL_GET_REPARSE_POINT) -, exista o no ese destino: NombreFinal tiene
  que abrirlo, y con un enlace COLGANTE no puede (TFile.GetSymLinkTarget
  tampoco: busca el destino con FindFirst). Una ruta completa con letra o
  UNC; un destino escrito de otra forma (un volumen por su GUID...) sale con
  prefijo de dispositivo (\\?\...): fuera de toda raiz, y RealPathHasta no lo
  pregunta al disco - con '' volvia el TEXTO del enlace. '' solo si no es un
  enlace que se sepa leer. Un symlink RELATIVO, contra la carpeta REAL del
  enlace, como Windows - contra la textual, con una junction de por medio,
  caia en otro sitio -, y uno que empieza por '\' contra la unidad del enlace,
  no la del proceso (2w de la 1.18.2; J3 y J4 del revisor de cierre: nunca
  lanza). }
function DestinoDeEnlace(const AEnlace: string): string;
const
  FSCTL_GET_REPARSE_POINT = $000900A8;
  IO_REPARSE_TAG_MOUNT_POINT = $A0000003;
  IO_REPARSE_TAG_SYMLINK = $A000000C;
  SYMLINK_FLAG_RELATIVE = 1;
var
  H: THandle;
  Buf: TBytes;
  Devuelto, Tag: Cardinal;
  Base, SubOff, SubLen: Integer;
  S: string;
begin
  Result := '';
  H := CreateFile(PChar(AEnlace), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
  try
    SetLength(Buf, 16 * 1024); // MAXIMUM_REPARSE_DATA_BUFFER_SIZE
    Devuelto := 0;
    if not DeviceIoControl(H, FSCTL_GET_REPARSE_POINT, nil, 0, @Buf[0], Length(Buf), Devuelto, nil) or
       (Devuelto < 16) then
      Exit;
    // REPARSE_DATA_BUFFER: etiqueta (4), largo (2), reservado (2), y luego
    // SubstituteName offset/largo y PrintName offset/largo (2 cada uno); el
    // de un symlink lleva ademas sus Flags (4) antes del texto
    Tag := PCardinal(@Buf[0])^;
    if Tag = IO_REPARSE_TAG_MOUNT_POINT then
      Base := 16
    else if Tag = IO_REPARSE_TAG_SYMLINK then
      Base := 20
    else
      Exit;
    SubOff := PWord(@Buf[8])^;
    SubLen := PWord(@Buf[10])^;
    if Base + SubOff + SubLen > Integer(Devuelto) then
      Exit;
    SetString(S, PChar(@Buf[Base + SubOff]), SubLen div SizeOf(Char));
    if (Tag = IO_REPARSE_TAG_SYMLINK) and ((PCardinal(@Buf[16])^ and SYMLINK_FLAG_RELATIVE) <> 0) then
    begin
      var Carpeta := TPath.GetDirectoryName(SinBarraFinal(AEnlace));
      var CarpetaReal: string;
      if NombreFinal(Carpeta, CarpetaReal) then
        Carpeta := CarpetaReal;
      // "\x" en la raiz de la unidad del enlace, lo demas desde su carpeta:
      // la regla de Windows, la de EL resolutor
      Exit(RutaDesde(Carpeta, S));
    end;
    // la forma NT: \??\C:\... o \??\UNC\host\...
    if S.StartsWith('\??\UNC\') then
      S := '\\' + S.Substring(8)
    else if S.StartsWith('\??\') then
      S := S.Substring(4);
    if EsRutaAbsoluta(S) then
      Result := S
    else
      Result := '\\?\' + S.TrimLeft(['\']);
  except
    Result := ''; // un relativo que no se deja componer: Windows tampoco lo sigue
  end;
  finally
    CloseHandle(H);
  end;
end;

const
  // los puntos de reanalisis que Windows sigue al abrir una ruta: MEDIDO el
  // 14-oct-2026 con una cadena de junctions vivas (sonda_tope_reparse.py del
  // scratchpad), 63 se abren y la de 64 no. Con un tope MENOR (habia 8) una
  // cadena de 9 colgantes que Windows si recorre se quedaba en su texto, y un
  // ReadOnlyPaths declarado a traves de ella no protegia nada (J1 del revisor
  // de cierre de la 1.18.2, medido); mas alla de este, Windows tampoco llega
  ENLACES_QUE_SIGUE_WINDOWS = 63;

{ RealPath con ANivel enlaces colgantes por seguir como mucho: una cadena
  de ellos (o un ciclo, que Windows no abre) no da vueltas para siempre. }
function RealPathHasta(const APath: string; ANivel: Integer): string;
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
        ASalida := SinBarraFinal(ASalida)
      else if (A <> INVALID_FILE_ATTRIBUTES) and ((A and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) and
         (ANivel > 0) then
      begin
        // un enlace COLGANTE (su destino no existe todavia): donde apunta, por
        // lo que guarda el propio enlace, y la ruta real de eso - que puede
        // pasar por otro enlace. Se quedaba el texto del enlace, y un move que
        // creaba el destino escribia DENTRO de un ReadOnlyPaths declarado a
        // traves de el (2w de la 1.18.2, medido en produccion)
        var Destino := DestinoDeEnlace(ADir);
        Result := Destino <> '';
        // un UNC o un prefijo de dispositivo se queda en su TEXTO: fuera de
        // toda raiz con letra, y preguntarlo en el disco era ir a la red con la
        // cuenta del servicio al host que escribe el enlace (J2 del revisor de
        // cierre: 21 s por una junction a \\192.0.2.1, que Windows ni sigue)
        if Result and (EsUnc(Destino) or EsPrefijoDeDispositivo(Destino)) then
          ASalida := SinBarraFinal(Destino)
        else if Result then
          ASalida := SinBarraFinal(RealPathHasta(Destino, ANivel - 1));
      end;
    end);
end;

function RealPath(const APath: string): string;
begin
  Result := RealPathHasta(APath, ENLACES_QUE_SIGUE_WINDOWS);
end;

function LongCanonical(const APath: string): string;
var
  Full: string;
begin
  Full := ConBarrasDeWindows(TPath.GetFullPath(RaizSiUnidad(APath)));
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

function LugarDeRedParaRutaLocal(const ARuta, ALugar: string): Boolean;
var
  LR, LL: Char;
begin
  LR := LetraDeRuta(ARuta.Trim);
  if (LR = #0) or (ClaseDeLetra(LR) <> clLocal) then
    Exit(False);
  if EsUnc(ALugar.Trim) then
    Exit(True);
  LL := LetraDeRuta(ALugar.Trim);
  Result := (LL <> #0) and (LL <> LR) and (ClaseDeLetra(LL) <> clLocal);
end;

function EnLugar(const APath, ALugar: string; AResuelveAlias: Boolean): Boolean;
begin
  Result := False;
  if (APath.Trim = '') or (ALugar.Trim = '') or LugarDeRedParaRutaLocal(APath, ALugar) then
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

function EnAlgunLugar(const AReal: string; const ALugares: TArray<string>): Boolean;
begin
  for var L in ALugares do
    if (L.Trim <> '') and not LugarDeRedParaRutaLocal(AReal, L) and EnLugar(AReal, RealPath(L)) then
      Exit(True);
  Result := False;
end;

{ Una ruta ABSOLUTA de verdad: <letra>:<separador> o un UNC. A proposito NO
  cuenta "D:" a secas ni nada relativo - el suelo de Guard solo puede morder
  donde esta seguro, porque muerde ANTES de que la tool mire sus argumentos y
  un falso positivo ahi rechaza una llamada legitima sin que nadie sepa por
  que. Las formas raras (la unidad sin separador, los nombres con punto o
  espacio al final) las sigue cazando PathAnomaly dentro de PathDenied. }
function EsRutaAbsoluta(const AValue: string): Boolean;
begin
  Result := ((Length(AValue) >= 3) and (AValue[2] = ':') and
             CharInSet(AValue[1], ['A' .. 'Z', 'a' .. 'z']) and
             CharInSet(AValue[3], ['\', '/'])) or
            ((Length(AValue) >= 2) and
             (((AValue[1] = '\') and (AValue[2] = '\')) or
              ((AValue[1] = '/') and (AValue[2] = '/'))));
end;

function EsRutaAMedias(const AValor: string): Boolean;
begin
  Result := (AValor <> '') and not EsRutaAbsoluta(AValor) and
    (CharInSet(AValor[1], ['\', '/']) or ((Length(AValor) >= 2) and (AValor[2] = ':')));
end;

function RutaDesde(const ABase, AValor, ACarpetaActual: string): string;
var
  Actual, Unidad: string;
begin
  Result := '';
  if AValor = '' then
    Exit;
  try
    if EsRutaAbsoluta(AValor) then
      Exit(TPath.GetFullPath(AValor));
    if EsRutaAMedias(AValor) then
    begin
      // de la unidad o de la carpeta actual de quien la lee: sin una completa,
      // las del proceso, que no son de nadie
      Actual := ACarpetaActual;
      if Actual = '' then
        Actual := ABase;
      if not EsRutaAbsoluta(Actual) then
        Exit;
      Unidad := ExtractFileDrive(Actual);
      if CharInSet(AValor[1], ['\', '/']) then
        Result := TPath.GetFullPath(Unidad + AValor)
      else if SameText(Copy(AValor, 1, 2), Unidad) then
        Result := TPath.GetFullPath(TPath.Combine(Actual, Copy(AValor, 3, MaxInt)));
      Exit;
    end;
    // relativa: desde la carpeta del fichero que la escribe
    if EsRutaAbsoluta(ABase) then
      Result := TPath.GetFullPath(TPath.Combine(ABase, AValor));
  except
    Result := ''; // un texto que no es ruta no se resuelve
  end;
end;

function EsPrefijoDeDispositivo(const APath: string): Boolean;
var
  P: string;
begin
  P := ConBarrasDeWindows(APath.Trim);
  // \??\ es la forma NT (del object manager) del mismo prefijo de dispositivo:
  // dcc abre una ruta asi igual que \\?\ (medido el 22-oct-2026: un search path
  // \??\C:\fuera compilaba leyendo fuera de la jaula), y Win32 GetFullPath no la
  // entiende, asi que hay que quitarla para juzgar la ruta real (H2b)
  Result := StartsText('\\?\', P) or StartsText('\\.\', P) or StartsText('\??\', P);
end;

function SinPrefijoDeDispositivo(const APath: string): string;
begin
  Result := APath;
  if not EsPrefijoDeDispositivo(Result) then
    Exit;
  Result := ConBarrasDeWindows(Result.Trim);
  // \\?\UNC\host\x es \\host\x; lo demas, la ruta tras las cuatro del prefijo
  if StartsText('\\?\UNC\', Result) or StartsText('\\.\UNC\', Result) or StartsText('\??\UNC\', Result) then
    Result := '\\' + Result.Substring(8)
  else
    Result := Result.Substring(4);
end;

function EsUnc(const APath: string): Boolean;
begin
  Result := ConBarrasDeWindows(APath).StartsWith('\\') and not EsPrefijoDeDispositivo(APath);
end;

end.
