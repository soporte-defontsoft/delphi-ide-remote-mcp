unit Base64Text;

interface

function ToBase64(const AText: string): string;

implementation

uses
  System.NetEncoding;

function ToBase64(const AText: string): string;
begin
  // TNetEncoding.Base64 breaks long output into lines (MIME style);
  // Base64String gives one single line, which is what a JSON field or a URL wants
  Result := TNetEncoding.Base64String.Encode(AText);
end;

end.
