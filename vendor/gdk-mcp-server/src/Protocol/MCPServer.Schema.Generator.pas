unit MCPServer.Schema.Generator;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.JSON;

type
  TMCPSchemaGenerator = class
  private
    class function GetJsonTypeFromRttiType(RttiType: TRttiType): string;
    class function GetPropertyJsonName(Prop: TRttiProperty; RType: TRttiType): string;
    class function IsRequiredProperty(Prop: TRttiProperty): Boolean;
    class function CreateEnumValuesArray(RttiType: TRttiType): TJSONArray;
  public
    class function GenerateSchema(Cls: TClass): TJSONObject;
    class function GenerateSchemaFromInstance(Instance: TObject): TJSONObject;
  end;

implementation

uses
  System.Generics.Collections,
  MCPServer.Types;

{ TMCPSchemaGenerator }

class function TMCPSchemaGenerator.GenerateSchema(Cls: TClass): TJSONObject;
var
  Attr: TCustomAttribute;
  EnumArray: TJSONArray;
  JsonName: string;
  JsonType: string;
  Properties: TJSONObject;
  PropSchema: TJSONObject;
  RequiredArray: TJSONArray;
  RttiContext: TRttiContext;
  RttiProp: TRttiProperty;
  RttiType: TRttiType;
  Value: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');

  Properties := TJSONObject.Create;
  Result.AddPair('properties', Properties);
  RequiredArray := TJSONArray.Create;

  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.GetType(Cls);

    for RttiProp in RttiType.GetProperties do
    begin
      if RttiProp.IsReadable and RttiProp.IsWritable then
      begin
        JsonName := GetPropertyJsonName(RttiProp, RttiType);

        PropSchema := TJSONObject.Create;
        Properties.AddPair(JsonName, PropSchema);

        JsonType := GetJsonTypeFromRttiType(RttiProp.PropertyType);
        PropSchema.AddPair('type', JsonType);

        if JsonType = 'array' then
          PropSchema.AddPair('items', TJSONObject.Create);

        EnumArray := nil;

        for Attr in RttiProp.GetAttributes do
        begin
          if Attr is SchemaDescriptionAttribute then
          begin
            PropSchema.AddPair('description', SchemaDescriptionAttribute(Attr).Description);
          end
          else if Attr is SchemaEnumAttribute then
          begin
            EnumArray := TJSONArray.Create;
            for Value in SchemaEnumAttribute(Attr).Values do
              EnumArray.Add(Value);
          end;
        end;

        if not Assigned(EnumArray) then
          EnumArray := CreateEnumValuesArray(RttiProp.PropertyType);

        if Assigned(EnumArray) then
          PropSchema.AddPair('enum', EnumArray);

        if IsRequiredProperty(RttiProp) then
          RequiredArray.Add(JsonName);
      end;
    end;

    if RequiredArray.Count > 0 then
      Result.AddPair('required', RequiredArray)
    else
      RequiredArray.Free;
  finally
    RttiContext.Free;
  end;
end;

class function TMCPSchemaGenerator.GenerateSchemaFromInstance(Instance: TObject): TJSONObject;
begin
  Result := GenerateSchema(Instance.ClassType);
end;

class function TMCPSchemaGenerator.GetJsonTypeFromRttiType(RttiType: TRttiType): string;
begin
  case RttiType.TypeKind of
    tkInteger, tkInt64: Result := 'number';
    tkFloat: Result := 'number';
    tkString, tkLString, tkWString, tkUString: Result := 'string';
    tkEnumeration:
      if RttiType.Name = 'Boolean' then
        Result := 'boolean'
      else
        Result := 'string';
    tkSet: Result := 'array';
    tkClass:
      if RttiType.Name = 'TJSONArray' then
        Result := 'array'
      else
        Result := 'object';
    tkArray, tkDynArray: Result := 'array';
  else
    Result := 'string';
  end;
end;

class function TMCPSchemaGenerator.GetPropertyJsonName(Prop: TRttiProperty; RType: TRttiType): string;
begin
  Result := LowerCase(Prop.Name);
  // [local change] A trailing underscore is a PASCAL problem, not part of the
  // parameter's name: `ClassName_` and `Create_` exist only because ClassName
  // and Create are taken in Delphi. Advertising them with the underscore made
  // the schema contradict every description, which says class= and
  // create=true (measured 2026-08-25: a client reading only the schema writes
  // classname_, one reading only the prose writes class). Deserialization
  // ignores underscores anyway - NormalizeKey strips them - so all spellings
  // keep working; this only stops the schema from teaching the ugly one.
  while Result.EndsWith('_') do
    Result := Result.Substring(0, Result.Length - 1);
end;

class function TMCPSchemaGenerator.IsRequiredProperty(Prop: TRttiProperty): Boolean;
var
  Attr: TCustomAttribute;
begin
  // [local change] Required only when it says so. Upstream had it the other
  // way round (required unless [Optional]), which published every parameter
  // of every tool as mandatory while the server happily accepted partial
  // calls - clients that validate the schema could not call anything.
  for Attr in Prop.GetAttributes do
    if Attr is RequiredAttribute then
      Exit(True);
  Result := False;
end;

class function TMCPSchemaGenerator.CreateEnumValuesArray(RttiType: TRttiType): TJSONArray;
var
  EnumType: TRttiEnumerationType;
  Ordinal: Integer;
begin
  Result := nil;

  if not (RttiType is TRttiEnumerationType) then
    Exit;

  if RttiType.Handle = TypeInfo(Boolean) then
    Exit;

  EnumType := TRttiEnumerationType(RttiType);

  Result := TJSONArray.Create;
  for Ordinal := EnumType.MinValue to EnumType.MaxValue do
    Result.Add(GetEnumName(RttiType.Handle, Ordinal));
end;

end.