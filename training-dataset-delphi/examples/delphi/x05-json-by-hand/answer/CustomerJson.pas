unit CustomerJson;

interface

function CustomerToJson(const AName: string; const AAge: Integer): string;

implementation

uses
  System.JSON;

function CustomerToJson(const AName: string; const AAge: Integer): string;
var
  Obj: TJSONObject;
begin
  // TJSONObject escapes what JSON needs escaped (quotes, backslashes, control characters)
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('name', AName);
    Obj.AddPair('age', TJSONNumber.Create(AAge));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
