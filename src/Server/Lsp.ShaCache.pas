unit Lsp.ShaCache;

{ Whole-file SHA-256 with a small shared cache keyed by (path, mtime, size):
  delphi_fetch offset=0 hashes the file, the /files download hashes it AGAIN
  before streaming (and delphi_run, until 2026-09-23, hashed the exe) - a big
  zip was read end-to-end three times for one download (hermes, release audit
  2026-08-26, P1.7). The stamp invalidates an entry the moment the file
  changes, so the contract is untouched - only the repeated I/O goes away.

  If the file mutates WHILE it is being hashed, the recorded stamp no longer
  matches the file's next stamp, so the possibly-mixed hash is never served
  to anyone else - the same exposure the uncached code had, and no more. }

interface

function CachedFileSha256(const APath: string): string;
{ Sin la cache: para verificar lo recien escrito, que el sello (la hora) puede no
  distinguir de lo anterior (V129 de la 1.24). }
function FileSha256(const APath: string): string;
function Sha256DeBytes(const ABytes: TArray<Byte>): string;
{ ...y sus 32 bytes crudos, para quien la escribe en otro formato (el pin
  SPKI de delphi_api va en base64: Lsp.Conexiones.PinDeSpki). }
function Sha256CrudoDeBytes(const ABytes: TArray<Byte>): TArray<Byte>;
{ S tiene la forma de lo que dan FileSha256 y Sha256DeBytes: 64 hexadecimales,
  sin mirar mayusculas. Su lector: estaba a mano dos veces en delphi_upload
  (menores de A del revisor del paisaje de la 1.29). }
function EsSha256(const S: string): Boolean;

type
  { Que se mide de un ENLACE a un fichero: lo SUYO - su propia entrada, con su
    fecha y tamano 0, que no se mueven cuando se edita lo de detras - o lo de
    DETRAS, el fichero al que lleva. }
  TEnlaceEnLaHuella = (ehSuyo, ehDetras);

{ LA lectura de la huella de un fichero en disco: su tamano y su fecha de
  escritura (FILETIME, UTC, en ticks de 100 ns tal cual) SIN abrirlo
  (GetFileAttributesEx: un fichero que otro proceso tiene sin compartir da la
  suya, y un recurso de red paga una ida y vuelta en vez de dos). De un enlace,
  lo que diga AEnlace: lo de detras se pregunta por un handle que solo pide
  ATRIBUTOS, que ninguna comparticion niega. False si no esta, si es una
  carpeta o si no se deja preguntar (un enlace roto). La leen DiskStamp, que la
  compone en texto, y quien necesita el numero (la foto de los escritores, los
  topes de bytes). Eran dos lecturas de la misma llamada con el enlace al reves
  (esta vivia en Lsp.TodoONada), y la de DiskStamp preguntaba lo de detras por
  la RTL: la fecha de lo de detras con el tamano del ENLACE (0), y con lo de
  detras retenido sin compartir, 0|0 - medido en C30 de la 1.28 (LspTests.Huella),
  donde el comentario decia "leido en la RTL, no medido". }
function HuellaDeFichero(const ARuta: string; out ATam: Int64; out AFecha: UInt64;
  AEnlace: TEnlaceEnLaHuella = ehSuyo): Boolean;

{ The disk fingerprint of a file as TEXT - last write time and size, as
  HuellaDeFichero reads them - for whoever compares it with an earlier one or
  puts it in a name. STAMP_GONE when the file is not there; STAMP_UNKNOWN when
  it is there but cannot be asked (a folder, access denied, a broken link...).
  One composer for its readers - this cache, the LSP session's document tables
  and settings cache, the snapshot of the writers (Lsp.TodoONada), the folder
  of a test (Lsp.TestRunner), the names of the package box and of the default
  style cache - which were two twins with two sentinels (first review of
  1.7.8) and then five texts by hand (C30 de la 1.28). A LINK to a file gives,
  by default, the stamp of the file it points to (AEnlace = ehDetras). }
const
  STAMP_GONE = '';
  STAMP_UNKNOWN = '?';
function DiskStamp(const APath: string; AEnlace: TEnlaceEnLaHuella = ehDetras): string;
function HasStamp(const AStamp: string): Boolean;

{ Un texto - una huella, la lista de lo que lleva una caja - hecho trozo de un
  nombre de fichero: los 16 primeros hex del SHA-256 de su UTF-8. Lo usan los
  nombres que dependen de una huella (la caja de paquetes de los renderizadores
  y la cache del estilo por defecto, que escribia la suya a mano en otra forma:
  C30 de la 1.28). }
function HuellaParaNombre(const ATexto: string): string;

{ The stamp of a FOLDER: its last write time, which Windows moves when an
  entry is created, deleted or renamed inside it (not when a file inside is
  edited: that is the file's DiskStamp). For whoever cached an answer that a
  NEW file in that folder would change: the project of a unit (FindDproj) went
  stale when a second .dproj appeared beside it (measured 18-oct-2026). Same
  sentinels as DiskStamp; STAMP_UNKNOWN for a file, and for a folder that is a
  LINK (its own date does not move when its target's entries do). }
function FolderStamp(const APath: string): string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Hash,
  System.SyncObjs,
  System.Generics.Collections,
  Lsp.Reparse;

var
  GLock: TCriticalSection;
  // full path (la clave del disco, la de Lsp.Rutas.ClaveDeRuta) -> (stamp, sha)
  GCache: TDictionary<string, TPair<string, string>>;

// el sello de lo que GetFileAttributesEx no pudo preguntar, por su error: no
// esta (STAMP_GONE) o esta y no se deja (STAMP_UNKNOWN). Lo comparten el sello
// de un fichero y el de una carpeta
function SelloSinAtributos: string;
var
  Err: DWORD;
begin
  Err := GetLastError;
  if (Err = ERROR_FILE_NOT_FOUND) or (Err = ERROR_PATH_NOT_FOUND) or (Err = ERROR_INVALID_NAME) then
    Result := STAMP_GONE
  else
    Result := STAMP_UNKNOWN;
end;

type
  // lo que contesta la lectura: esta, no esta, o esta y no se deja (DiskStamp
  // los distingue: Lsp.Session suelta un documento que no esta y conserva uno
  // que no se deja preguntar)
  TLecturaDeHuella = (lhEsta, lhNoEsta, lhNoSeDeja);

function LeeHuella(const ARuta: string; AEnlace: TEnlaceEnLaHuella; out ATam: Int64;
  out AFecha: UInt64): TLecturaDeHuella;
var
  Data: TWin32FileAttributeData;
  Info: TByHandleFileInformation;
  H: THandle;
begin
  ATam := -1;
  AFecha := 0;
  if not GetFileAttributesEx(PChar(ARuta), GetFileExInfoStandard, @Data) then
    Exit(if SelloSinAtributos = STAMP_GONE then lhNoEsta else lhNoSeDeja);
  if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
    Exit(lhNoSeDeja); // a folder has a date, but it is not a file
  if (AEnlace = ehDetras) and ((Data.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
  begin
    // lo de detras: abrir un enlace lo sigue, y un handle que solo pide
    // ATRIBUTOS no choca con ninguna comparticion (lo de detras retenido da la
    // suya). Lo que no se abre (un enlace roto) o es una carpeta no se deja: el
    // enlace ESTA
    H := CreateFile(PChar(ARuta), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, 0);
    if H = INVALID_HANDLE_VALUE then
      Exit(lhNoSeDeja);
    try
      if not GetFileInformationByHandle(H, Info) or
         ((Info.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
        Exit(lhNoSeDeja);
      ATam := Int64((UInt64(Info.nFileSizeHigh) shl 32) or Info.nFileSizeLow);
      AFecha := (UInt64(Info.ftLastWriteTime.dwHighDateTime) shl 32) or Info.ftLastWriteTime.dwLowDateTime;
    finally
      CloseHandle(H);
    end;
    Exit(lhEsta);
  end;
  ATam := Int64((UInt64(Data.nFileSizeHigh) shl 32) or Data.nFileSizeLow);
  AFecha := (UInt64(Data.ftLastWriteTime.dwHighDateTime) shl 32) or Data.ftLastWriteTime.dwLowDateTime;
  Result := lhEsta;
end;

function HuellaDeFichero(const ARuta: string; out ATam: Int64; out AFecha: UInt64;
  AEnlace: TEnlaceEnLaHuella): Boolean;
begin
  Result := LeeHuella(ARuta, AEnlace, ATam, AFecha) = lhEsta;
end;

function DiskStamp(const APath: string; AEnlace: TEnlaceEnLaHuella): string;
var
  Tam: Int64;
  Fecha: UInt64;
begin
  case LeeHuella(APath, AEnlace, Tam, Fecha) of
    lhEsta: Result := UIntToStr(Fecha) + '|' + UIntToStr(UInt64(Tam));
    lhNoEsta: Result := STAMP_GONE;
  else
    Result := STAMP_UNKNOWN;
  end;
end;

function FolderStamp(const APath: string): string;
var
  Data: TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Data) then
    Exit(SelloSinAtributos);
  if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
    Exit(STAMP_UNKNOWN);
  // una carpeta ENLACE no tiene sello suyo (su fecha es la del enlace, no la de
  // lo de detras): por EL juez (EsEnlace, Lsp.Reparse) y no por el atributo,
  // que tambien lleva una carpeta de OneDrive sin ser enlace, y se quedaba sin
  // sello: su cache de proyecto no se guardaba nunca (F1-4 de la 1.29)
  if ((Data.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) and EsEnlace(APath) then
    Exit(STAMP_UNKNOWN);
  Result := UIntToStr((UInt64(Data.ftLastWriteTime.dwHighDateTime) shl 32) or Data.ftLastWriteTime.dwLowDateTime);
end;

function HasStamp(const AStamp: string): Boolean;
begin
  Result := (AStamp <> STAMP_GONE) and (AStamp <> STAMP_UNKNOWN);
end;

// El sha de un trozo en memoria (delphi_upload chunkSha256): mismo sitio
// que el de fichero, para que nadie monte otro THashSHA2 por su cuenta.
function Sha256DeBytes(const ABytes: TArray<Byte>): string;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(ABytes) > 0 then
    H.Update(ABytes[0], Length(ABytes));
  Result := H.HashAsString;
end;

function EsSha256(const S: string): Boolean;
begin
  Result := Length(S) = 64;
  if Result then
    for var C in S do
      if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

function Sha256CrudoDeBytes(const ABytes: TArray<Byte>): TArray<Byte>;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(ABytes) > 0 then
    H.Update(ABytes[0], Length(ABytes));
  Result := H.HashAsBytes;
end;

function HuellaParaNombre(const ATexto: string): string;
begin
  Result := Copy(Sha256DeBytes(TEncoding.UTF8.GetBytes(ATexto)), 1, 16);
end;

function FileSha256(const APath: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(TPath.GetFullPath(APath), THashSHA2.TSHA2Version.SHA256);
end;

function CachedFileSha256(const APath: string): string;
var
  Full, Key, Stamp: string;
  Hit: TPair<string, string>;
begin
  Full := TPath.GetFullPath(APath);
  // la clave de Lsp.Rutas.ClaveDeRuta (las mayusculas invariantes), escrita
  // aqui a proposito: esta unidad la comparten los renderizadores, que no
  // llevan Lsp.Rutas ni lo que arrastra; .ToLower juntaba lo que NTFS separa
  // y dos ficheros con el mismo sello daban el SHA del otro (V105)
  Key := Full.ToUpperInvariant;
  Stamp := DiskStamp(Full);
  if HasStamp(Stamp) then
  begin
    GLock.Enter;
    try
      if GCache.TryGetValue(Key, Hit) and (Hit.Key = Stamp) then
        Exit(Hit.Value);
    finally
      GLock.Leave;
    end;
  end;
  Result := FileSha256(Full);
  if HasStamp(Stamp) then
  begin
    GLock.Enter;
    try
      // tiny and disposable: a full clear beats LRU bookkeeping at this size
      if GCache.Count > 128 then
        GCache.Clear;
      GCache.AddOrSetValue(Key, TPair<string, string>.Create(Stamp, Result));
    finally
      GLock.Leave;
    end;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GCache := TDictionary<string, TPair<string, string>>.Create;

finalization
  GCache.Free;
  GLock.Free;

end.
