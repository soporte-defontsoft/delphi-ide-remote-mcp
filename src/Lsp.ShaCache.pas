unit Lsp.ShaCache;

{ Whole-file SHA-256 with a small shared cache keyed by (path, mtime, size):
  delphi_fetch offset=0 hashes the file, the /files download hashes it AGAIN
  before streaming, and delphi_run hashes the exe for the audit log - a big
  zip was read end-to-end three times for one download (hermes, release audit
  2026-08-26, P1.7). The stamp invalidates an entry the moment the file
  changes, so the contract is untouched - only the repeated I/O goes away.

  If the file mutates WHILE it is being hashed, the recorded stamp no longer
  matches the file's next stamp, so the possibly-mixed hash is never served
  to anyone else - the same exposure the uncached code had, and no more. }

interface

function CachedFileSha256(const APath: string): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Hash,
  System.SyncObjs,
  System.Generics.Collections;

var
  GLock: TCriticalSection;
  // full path (lower) -> (stamp, sha)
  GCache: TDictionary<string, TPair<string, string>>;

function StampOf(const AFull: string): string;
begin
  try
    Result := FloatToStr(TFile.GetLastWriteTimeUtc(AFull)) + '|' +
      IntToStr(TFile.GetSize(AFull));
  except
    Result := '';
  end;
end;

function CachedFileSha256(const APath: string): string;
var
  Full, Key, Stamp: string;
  Hit: TPair<string, string>;
begin
  Full := TPath.GetFullPath(APath);
  Key := Full.ToLower;
  Stamp := StampOf(Full);
  if Stamp <> '' then
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
  if Stamp <> '' then
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
