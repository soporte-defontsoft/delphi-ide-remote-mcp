unit CustomerJson;

interface

function CustomerToJson(const AName: string; const AAge: Integer): string;

implementation

uses
  System.SysUtils;

function CustomerToJson(const AName: string; const AAge: Integer): string;
begin
  Result := '{"name":"' + AName + '","age":' + IntToStr(AAge) + '}';
end;

end.
