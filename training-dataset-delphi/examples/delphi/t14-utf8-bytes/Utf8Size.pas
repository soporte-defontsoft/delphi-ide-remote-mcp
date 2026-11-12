unit Utf8Size;

interface

function Utf8ByteCount(const AText: string): Integer;

implementation

uses
  System.SysUtils;

function Utf8ByteCount(const AText: string): Integer;
begin
  // Length counts UTF-16 characters; the size in bytes depends on the encoding
  Result := TEncoding.UTF8.GetByteCount(AText);
end;

end.
