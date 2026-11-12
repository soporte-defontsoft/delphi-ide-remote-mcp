unit TextBlob;

interface

function Utf8StreamSize(const AText: string): Int64;

implementation

uses
  System.Classes, System.SysUtils;

function Utf8StreamSize(const AText: string): Int64;
var
  Stream: TStringStream;
begin
  // the streams (TStringStream, TMemoryStream, TFileStream) live in System.Classes;
  // TEncoding in System.SysUtils
  Stream := TStringStream.Create(AText, TEncoding.UTF8);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

end.
