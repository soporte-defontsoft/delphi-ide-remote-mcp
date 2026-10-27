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
function Sha256DeBytes(const ABytes: TArray<Byte>): string;

{ The disk fingerprint of a file - last write time and size - in ONE call
  (GetFileAttributesEx opens no handle: a file another process holds
  exclusively still gives its stamp, and a network share pays one round trip
  instead of two). STAMP_GONE when the file is not there; STAMP_UNKNOWN when
  it is there but cannot be asked (a folder, access denied...). One composer
  for its readers - this cache, and the LSP session's document tables and
  settings cache - which were two twins with two sentinels (first review of
  1.7.8). A LINK to a file is asked the way it always was, through the link:
  the one call answers with the link's own date and size 0, which do not
  move when the file it points to is edited (second review of 1.7.9; read in
  the RTL, not measured here: this account cannot create a link). }
const
  STAMP_GONE = '';
  STAMP_UNKNOWN = '?';
function DiskStamp(const APath: string): string;
function HasStamp(const AStamp: string): Boolean;

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
  System.Generics.Collections;

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

function DiskStamp(const APath: string): string;
var
  Data: TWin32FileAttributeData;
begin
  if GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Data) then
  begin
    if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
      Exit(STAMP_UNKNOWN); // a folder has a date, but it is not a file
    if (Data.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
      try
        Exit(FloatToStr(TFile.GetLastWriteTimeUtc(APath)) + '|' + IntToStr(TFile.GetSize(APath)));
      except
        Exit(STAMP_UNKNOWN);
      end;
    Result := UIntToStr((UInt64(Data.ftLastWriteTime.dwHighDateTime) shl 32) or Data.ftLastWriteTime.dwLowDateTime)
      + '|' + UIntToStr((UInt64(Data.nFileSizeHigh) shl 32) or Data.nFileSizeLow);
  end
  else
    Result := SelloSinAtributos;
end;

function FolderStamp(const APath: string): string;
var
  Data: TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Data) then
    Exit(SelloSinAtributos);
  if ((Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
     ((Data.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
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
  Result := THashSHA2.GetHashStringFromFile(Full, THashSHA2.TSHA2Version.SHA256);
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
