unit PersonJson;

interface

function PersonToJson(const AName: string; const AAge: Integer): string;

implementation

uses
  System.JSON;

function PersonToJson(const AName: string; const AAge: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('name', AName);
    Obj.AddPair('age', TJSONNumber.Create(AAge));
    Result := Obj.ToJSON;
  finally
    Obj.Free; // the object owns its pairs and frees them
  end;
end;

end.
