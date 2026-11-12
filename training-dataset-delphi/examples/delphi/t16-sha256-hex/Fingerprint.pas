unit Fingerprint;

interface

function Sha256Hex(const AText: string): string;

implementation

uses
  System.Hash;

function Sha256Hex(const AText: string): string;
begin
  // THashSHA2 hashes with SHA-256 unless told otherwise; the string comes back in lowercase hex
  Result := THashSHA2.GetHashString(AText);
end;

end.
