unit TextBlob;

interface

function Utf8StreamSize(const AText: string): Int64;

implementation

uses
  System.SysUtils;

function Utf8StreamSize(const AText: string): Int64;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(AText, TEncoding.UTF8);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

end.
