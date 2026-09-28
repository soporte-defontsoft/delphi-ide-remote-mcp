unit MCPServer.Serializer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.JSON;

type
  TMCPSerializer = class
  private
    class var FContext: TRttiContext;

    class procedure DeserializeObject(Instance: TObject; const Json: TJSONObject);
    class function DeserializeArray(RttiType: TRttiType; const JsonArray: TJSONArray): TValue;

    // Extracted type conversion methods
    class function ConvertJsonToValue(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
    class function ConvertJsonToEnum(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
    class function GetEnumValueNames(const EnumType: TRttiEnumerationType): string;
    class function ConvertValueToJson(const Value: TValue; const RttiType: TRttiType): TJSONValue;
    class function CreateInstanceFromType(const RttiType: TRttiType): TObject;

    // Array deserialization helpers
    class function DeserializeDynamicArray(const DynArrayType: TRttiDynamicArrayType; const JsonArray: TJSONArray): TValue;
    class function DeserializeGenericList(const ListType: TRttiInstanceType; const JsonArray: TJSONArray): TValue;
    class function FindAddMethod(const ListType: TRttiInstanceType): TRttiMethod;

    // Case-insensitive JSON value lookup
    class function GetJsonValueCaseInsensitive(const Json: TJSONObject; const PropName: string): TJSONValue;

  public
    // [local change] exposed: the host's single entry gate must match a
    // tools/call argument to its parameter with EXACTLY the rule this binder
    // uses, or a client can spell a parameter in a way only one of the two
    // recognizes - the gate then inspects one value while the tool receives
    // another. One rule, one place.
    // Single normalization rule shared by lookup and validation
    class function NormalizeKey(const Name: string): string; inline;

    // [local change 2026-09-27] La regla de un entero y de un booleano del
    // contrato, UNA: la usan este deserializador y lo que llega DENTRO de un
    // parametro (las entradas de "edits" de delphi_edit/delphi_textedit, que
    // no pasan por el: "delete":"yes" dejaba la linea en blanco y
    // "toline":-1 se ignoraba, contestando OK). '' si vale; si no, el motivo
    // sin etiqueta: quien llama lo envuelve con el nombre del campo.
    class function MotivoEntero(const JsonValue: TJSONValue; AMaximo: Int64;
      out AValor: Int64): string;
    class function MotivoBooleano(const JsonValue: TJSONValue;
      out AValor: Boolean): string;

    class constructor Create;
    class destructor Destroy;

    class function Deserialize<T: class, constructor>(const Json: TJSONObject): T;
    class procedure Serialize(Obj: TObject; Json: TJSONObject);

    class function SerializeToString(Obj: TObject): string;
  end;

implementation

uses
  MCPServer.Schema.Generator, // IsRequiredProperty: el lector de [Required]
  Lsp.Attributes, // [JsonComoTexto]: el texto que acepta un JSON como valor
  Lsp.Texts; // [local change 2026-09-27] los textos, del catalogo

{ TMCPSerializer }

class constructor TMCPSerializer.Create;
begin
  FContext := TRttiContext.Create;
end;

class destructor TMCPSerializer.Destroy;
begin
  FContext.Free;
end;

class function TMCPSerializer.Deserialize<T>(const Json: TJSONObject): T;
begin
  Result := T.Create;
  try
    DeserializeObject(Result, Json);
  except
    Result.Free;
    raise;
  end;
end;

class function TMCPSerializer.NormalizeKey(const Name: string): string;
begin
  Result := LowerCase(Name).Replace('_', '', [rfReplaceAll]);
end;

class function TMCPSerializer.GetJsonValueCaseInsensitive(const Json: TJSONObject; const PropName: string): TJSONValue;
var
  Pair: TJSONPair;
  PropNorm: string;
begin
  Result := Json.GetValue(PropName);
  if Assigned(Result) then
    Exit;

  PropNorm := NormalizeKey(PropName);
  for Pair in Json do
    if NormalizeKey(Pair.JsonString.Value) = PropNorm then
      Exit(Pair.JsonValue);
end;

class procedure TMCPSerializer.DeserializeObject(Instance: TObject; const Json: TJSONObject);
var
  JsonValue: TJSONValue;
  KeyName: string;
  KnownNorms: TStringList;
  Pair: TJSONPair;
  PropValue: TValue;
  RttiProp: TRttiProperty;
  RttiType: TRttiType;
begin
  RttiType := FContext.GetType(Instance.ClassType);

  // [local change 2026-09-28] casar por la clave normalizada, pero LISTAR
  // con el nombre publicado (GetPropertyJsonName, el del esquema y el de
  // SYS-016/019): se listaba "oldtext" donde el esquema dice "old_text"
  var Publicados := TStringList.Create;
  KnownNorms := TStringList.Create;
  try
    for RttiProp in RttiType.GetProperties do
      if RttiProp.IsWritable then
      begin
        KnownNorms.Add(NormalizeKey(RttiProp.Name));
        Publicados.Add(TMCPSchemaGenerator.GetPropertyJsonName(RttiProp, RttiType));
      end;

    for Pair in Json do
    begin
      KeyName := Pair.JsonString.Value;
      // una tool sin parametros decia "Valid parameters: ." (septima revision)
      if KnownNorms.IndexOf(NormalizeKey(KeyName)) < 0 then
      begin
        var Validos := String.Join(', ', Publicados.ToStringArray);
        if Validos = '' then
          Validos := MsgText(SF_NINGUNO);
        raise EArgumentException.Create(MsgFmt(SR_SYS_UNKNOWN_PARAM_FMT,
          [KeyName, Validos]));
      end;
    end;
  finally
    KnownNorms.Free;
    Publicados.Free;
  end;

  for RttiProp in RttiType.GetProperties do
  begin
    if not RttiProp.IsWritable then
      Continue;

    JsonValue := GetJsonValueCaseInsensitive(Json, RttiProp.Name);

    // [local change 2026-09-27] Un parametro OBLIGATORIO (el [Required] que
    // tools/list publica) que no viene es una llamada mal hecha: se saltaba
    // y la tool trabajaba con su valor por defecto - vault_patch sin new_text
    // BORRABA el fragmento, delphi_hover sin line miraba la linea 0. Venir
    // basta: un texto vacio puede ser legitimo (new_text '' borra a
    // proposito).
    // [local change 2026-09-27] el parametro se nombra como lo publica el
    // esquema: "create_" (el nombre Pascal) no lo reconoce nadie
    var NombreJson := TMCPSchemaGenerator.GetPropertyJsonName(RttiProp, RttiType);
    if ((not Assigned(JsonValue)) or (JsonValue is TJSONNull)) and
       TMCPSchemaGenerator.IsRequiredProperty(RttiProp) then
      raise EArgumentException.Create(MsgFmt(SR_SYS_MISSING_PARAM_FMT, [NombreJson]));

    if not Assigned(JsonValue) then
      Continue;

    // [local change 2026-09-27] Un array o un objeto donde va un TEXTO se
    // convertia en su texto JSON y se escribia tal cual (new=["a","b"] quedaba
    // en el .pas contestando OK; quinta revision). Solo lo acepta el
    // parametro que lo declara ([JsonComoTexto]: "edits").
    if ((JsonValue is TJSONObject) or (JsonValue is TJSONArray)) and
       (RttiProp.PropertyType.TypeKind in [tkString, tkLString, tkWString, tkUString]) then
    begin
      var AceptaJson := False;
      for var Attr in RttiProp.GetAttributes do
        if Attr is JsonComoTextoAttribute then
          AceptaJson := True;
      if not AceptaJson then
        raise EArgumentException.Create(MsgFmt(SR_SYS_PARAM_VALUE_FMT,
          [NombreJson, MsgText(SF_SYS_EXPECTED_TEXT)]));
    end;

    try
      PropValue := ConvertJsonToValue(JsonValue, RttiProp.PropertyType);
    except
      on E: EArgumentException do
        raise EArgumentException.Create(MsgFmt(SR_SYS_PARAM_VALUE_FMT, [NombreJson, E.Message]));
    end;

    if not PropValue.IsEmpty then
    begin
      {$WARN UNSAFE_CAST OFF}
      RttiProp.SetValue(Instance, PropValue);
      {$WARN UNSAFE_CAST ON}
    end;
  end;
end;

class procedure TMCPSerializer.Serialize(Obj: TObject; Json: TJSONObject);
var
  JsonValue: TJSONValue;
  PropName: string;
  PropValue: TValue;
  RttiProp: TRttiProperty;
  RttiType: TRttiType;
begin
  RttiType := FContext.GetType(Obj.ClassType);

  for RttiProp in RttiType.GetProperties do
  begin
    if not RttiProp.IsReadable then
      Continue;

    PropName := LowerCase(RttiProp.Name);
    {$WARN UNSAFE_CAST OFF}
    PropValue := RttiProp.GetValue(Obj);
    {$WARN UNSAFE_CAST ON}
    
    JsonValue := ConvertValueToJson(PropValue, RttiProp.PropertyType);
    
    if Assigned(JsonValue) then
      Json.AddPair(PropName, JsonValue);
  end;
end;

class function TMCPSerializer.SerializeToString(Obj: TObject): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Serialize(Obj, Json);
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

class function TMCPSerializer.MotivoEntero(const JsonValue: TJSONValue;
  AMaximo: Int64; out AValor: Int64): string;
var
  Txt: string;
begin
  Result := '';
  Txt := Trim(JsonValue.Value);
  if not TryStrToInt64(Txt, AValor) then
    Exit(MsgFmt(SF_SYS_EXPECTED_WHOLE_FMT, [JsonValue.Value]));
  // ningun entero del contrato es negativo (lineas, desplazamientos,
  // maximos, tiempos): se aceptaba en silencio como el valor por defecto en
  // unas tools y se rechazaba en otras, con cinco copias a mano
  if AValor < 0 then
    Exit(MsgFmt(SF_SYS_NO_NEGATIVO_FMT, [Txt]));
  if AValor > AMaximo then
    Exit(MsgFmt(SF_SYS_OUT_OF_RANGE_FMT, [Txt, 0, AMaximo]));
end;

class function TMCPSerializer.MotivoBooleano(const JsonValue: TJSONValue;
  out AValor: Boolean): string;
var
  Txt: string;
begin
  Result := '';
  AValor := False;
{$IF COMPILERVERSION <= 29}
  if (JsonValue is TJSONTrue) or (JsonValue is TJSONFalse) then
    AValor := JsonValue is TJSONTrue
{$ELSE}
  if JsonValue is TJSONBool then
    AValor := (JsonValue as TJSONBool).AsBoolean
{$ENDIF}
  else
  begin
    // anything but the two spellings is a mistake, not a False: "yes", "1"
    // or a typo used to switch the flag OFF in silence
    Txt := Trim(JsonValue.Value);
    if SameText(Txt, 'true') then
      AValor := True
    else if not SameText(Txt, 'false') then
      Result := MsgFmt(SF_SYS_EXPECTED_BOOL_FMT, [JsonValue.Value]);
  end;
end;

class function TMCPSerializer.ConvertJsonToValue(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
var
  NestedInstance: TObject;
  I64: Int64;
  Dbl: Double;
  Txt, Motivo: string;
  Bool: Boolean;
begin
  Result := TValue.Empty;

  if not Assigned(JsonValue) then
    Exit;

  // [local change] JSON null means "not provided", never a value. It used to
  // fall through to the branches below, where TJSONAncestor.Value hands back
  // the literal string 'null': a null number became 0 and a null string became
  // the four characters "null" (a path, a query, a file name...). Leaving the
  // result empty makes the caller skip the property, so the parameter keeps
  // its default exactly as if it had been omitted.
  if JsonValue is TJSONNull then
    Exit;

  // [local change] Numbers and booleans used to be coerced SILENTLY: a string
  // that is not a number became 0 (StrToIntDef) and a boolean spelled anything
  // other than "true" became False. The tool then worked on a value the client
  // never sent - a plausible WRONG answer instead of an error, which is the
  // worst failure mode for an agent that cannot see the server. Garbage now
  // raises EArgumentException, which DeserializeObject reports as
  // 'Parameter "<name>": <reason>'.
  // A value that PARSES cleanly is still accepted whatever its JSON type
  // ("5" for 5, "true" for true): many clients send everything as text, and
  // accepting what reads unambiguously costs nothing. Only the unreadable is
  // refused.
  Txt := Trim(JsonValue.Value);

  case RttiType.TypeKind of
    tkInteger:
      begin
        // [local change 2026-09-27] la regla del entero, UNA (MotivoEntero)
        Motivo := MotivoEntero(JsonValue, High(Integer), I64);
        if Motivo <> '' then
          raise EArgumentException.Create(Motivo);
        Result := Integer(I64);
      end;

    tkInt64:
      begin
        Motivo := MotivoEntero(JsonValue, High(Int64), I64);
        if Motivo <> '' then
          raise EArgumentException.Create(Motivo);
        Result := I64;
      end;

    tkFloat:
      begin
{$IF COMPILERVERSION <= 28}
        if not TryStrToFloat(Txt, Dbl, TFormatSettings.Create('en-US')) then
{$ELSE}
        if not TryStrToFloat(Txt, Dbl, FormatSettings.Invariant) then
{$ENDIF}
          raise EArgumentException.Create(MsgFmt(SF_SYS_EXPECTED_NUMBER_FMT, [JsonValue.Value]));
        Result := Dbl;
      end;

    tkString, tkLString, tkWString, tkUString:
      // A JSON object or array sent for a STRING parameter travels as its
      // JSON text: the RTL's Value is '' for both, so a client that sent
      // delphi_edit "edits" as a real array (the description says array)
      // got the batch silently ignored (hermes, 2026-09-25).
      if (JsonValue is TJSONObject) or (JsonValue is TJSONArray) then
        Result := JsonValue.ToJSON
      else
        Result := JsonValue.Value;
      
    tkEnumeration:
      if RttiType.Handle = TypeInfo(Boolean) then
      begin
        // [local change] la regla del booleano, UNA (MotivoBooleano): solo
        // las dos grafias; "yes", "1" o una errata apagaban la opcion en
        // silencio y el cliente creia haber pedido algo que nunca tuvo
        Motivo := MotivoBooleano(JsonValue, Bool);
        if Motivo <> '' then
          raise EArgumentException.Create(Motivo);
        Result := Bool;
      end
      else
      begin
        Result := ConvertJsonToEnum(JsonValue, RttiType);
      end;

    tkClass:
      if JsonValue is TJSONObject then
      begin
        NestedInstance := CreateInstanceFromType(RttiType);
        if Assigned(NestedInstance) then
        begin
          DeserializeObject(NestedInstance, JsonValue as TJSONObject);
          Result := NestedInstance;
        end;
      end
      else if JsonValue is TJSONArray then
        Result := DeserializeArray(RttiType, JsonValue as TJSONArray);
        
    tkDynArray:
      if JsonValue is TJSONArray then
        Result := DeserializeArray(RttiType, JsonValue as TJSONArray);
  end;
end;

class function TMCPSerializer.ConvertJsonToEnum(const JsonValue: TJSONValue; const RttiType: TRttiType): TValue;
var
  EnumType: TRttiEnumerationType;
  Ordinal: Integer;
begin
  Result := TValue.Empty;

  if not (RttiType is TRttiEnumerationType) then
    Exit;

  EnumType := TRttiEnumerationType(RttiType);

  if JsonValue is TJSONNumber then
    Ordinal := (JsonValue as TJSONNumber).AsInt
  else
  begin
    if JsonValue.Value = '' then
      Exit;

    Ordinal := GetEnumValue(RttiType.Handle, JsonValue.Value);
    if Ordinal < 0 then
      Ordinal := StrToIntDef(JsonValue.Value, -1);
  end;

  if (Ordinal < EnumType.MinValue) or (Ordinal > EnumType.MaxValue) then
    raise EArgumentException.Create(MsgFmt(SF_SYS_INVALID_VALUE_FMT,
      [JsonValue.Value, GetEnumValueNames(EnumType)]));

  Result := TValue.FromOrdinal(RttiType.Handle, Ordinal);
end;

class function TMCPSerializer.GetEnumValueNames(const EnumType: TRttiEnumerationType): string;
var
  Names: TArray<string>;
  Ordinal: Integer;
begin
  SetLength(Names, EnumType.MaxValue - EnumType.MinValue + 1);

  for Ordinal := EnumType.MinValue to EnumType.MaxValue do
    Names[Ordinal - EnumType.MinValue] := GetEnumName(EnumType.Handle, Ordinal);

  Result := String.Join(', ', Names);
end;

class function TMCPSerializer.CreateInstanceFromType(const RttiType: TRttiType): TObject;
var
  InstanceType: TRttiInstanceType;
  MetaClass: TClass;
begin
  Result := nil;
  
  if RttiType is TRttiInstanceType then
  begin
    InstanceType := TRttiInstanceType(RttiType);
    MetaClass := InstanceType.MetaclassType;
    
    if Assigned(MetaClass) then
      Result := MetaClass.Create;
  end;
end;

class function TMCPSerializer.ConvertValueToJson(const Value: TValue; const RttiType: TRttiType): TJSONValue;
var
  ChildJson: TJSONObject;
  Obj: TObject;
begin
  Result := nil;
  
  if Value.IsEmpty then
    Exit;
    
  case RttiType.TypeKind of
    tkInteger:
      Result := TJSONNumber.Create(Value.AsInteger);

    tkInt64:
      Result := TJSONNumber.Create(Value.AsInt64);
      
    tkFloat:
      Result := TJSONNumber.Create(Value.AsExtended);
      
    tkString, tkLString, tkWString, tkUString:
      Result := TJSONString.Create(Value.AsString);
      
    tkEnumeration:
      begin
{$IF COMPILERVERSION <= 29}
        if Value.AsBoolean then
          Result := TJSONTrue.Create
        else
          Result := TJSONFalse.Create;
{$ELSE}
        Result := TJSONBool.Create(Value.AsBoolean);
{$ENDIF}
      end;

    tkClass:
      if Value.IsObject and (Value.AsObject <> nil) then
      begin
        Obj := Value.AsObject;

        if Obj is TJSONValue then
        begin
          Result := TJSONValue(Obj).Clone as TJSONValue;
        end
        else
        begin
          ChildJson := TJSONObject.Create;
          Serialize(Obj, ChildJson);
          Result := ChildJson;
        end;
      end;
  end;
end;

class function TMCPSerializer.DeserializeArray(RttiType: TRttiType; const JsonArray: TJSONArray): TValue;
begin
  Result := TValue.Empty;
  
  if RttiType is TRttiDynamicArrayType then
    Result := DeserializeDynamicArray(TRttiDynamicArrayType(RttiType), JsonArray)
  else if (RttiType is TRttiInstanceType) and 
          (TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TList)) then
    Result := DeserializeGenericList(TRttiInstanceType(RttiType), JsonArray);
end;

class function TMCPSerializer.DeserializeDynamicArray(const DynArrayType: TRttiDynamicArrayType; const JsonArray: TJSONArray): TValue;
var
  ArrayLength: NativeInt;
  ElementType: TRttiType;
  ElementValue: TValue;
  I: NativeInt;
  JsonElement: TJSONValue;
begin
  ElementType := DynArrayType.ElementType;
  ArrayLength := JsonArray.Count;

  Result := TValue.Empty;
  TValue.Make(nil, DynArrayType.Handle, Result);
  DynArraySetLength(PPointer(Result.GetReferenceToRawData)^, Result.TypeInfo, 1, @ArrayLength);
  
  for I := 0 to ArrayLength - 1 do
  begin
    JsonElement := JsonArray.Items[Integer(I)];
    ElementValue := ConvertJsonToValue(JsonElement, ElementType);
    
    if not ElementValue.IsEmpty then
      Result.SetArrayElement(I, ElementValue);
  end;
end;

class function TMCPSerializer.DeserializeGenericList(const ListType: TRttiInstanceType; const JsonArray: TJSONArray): TValue;
var
  AddMethod: TRttiMethod;
  ElementValue: TValue;
  I: Integer;
  JsonElement: TJSONValue;
  ListInstance: TObject;
  ParamType: TRttiType;
begin
  ListInstance := ListType.MetaclassType.Create;
  
  AddMethod := FindAddMethod(ListType);
  if not Assigned(AddMethod) then
  begin
    ListInstance.Free;
    Exit(TValue.Empty);
  end;
  
  ParamType := AddMethod.GetParameters[0].ParamType;
  
  for I := 0 to JsonArray.Count - 1 do
  begin
    JsonElement := JsonArray.Items[I];
    ElementValue := ConvertJsonToValue(JsonElement, ParamType);
    
    if not ElementValue.IsEmpty then
      AddMethod.Invoke(ListInstance, [ElementValue]);
  end;
  
  Result := ListInstance;
end;

class function TMCPSerializer.FindAddMethod(const ListType: TRttiInstanceType): TRttiMethod;
var
  Method: TRttiMethod;
begin
  Result := nil;
  
  for Method in ListType.GetMethods do
  begin
    if SameText(Method.Name, 'Add') and (Length(Method.GetParameters) = 1) then
    begin
      Result := Method;
      Break;
    end;
  end;
end;

end.