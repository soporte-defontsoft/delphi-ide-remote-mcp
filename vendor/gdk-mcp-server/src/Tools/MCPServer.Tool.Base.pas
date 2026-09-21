unit MCPServer.Tool.Base;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.JSON;

type
  IMCPTool = interface
    ['{F1E2D3C4-B5A6-4798-8901-234567890ABC}']
    function GetName: string;
    function GetTitle: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    function GetOutputSchema: TJSONObject;
    function Execute(const Arguments: TJSONObject): TValue;

    property Name: string read GetName;
    property Title: string read GetTitle;
    property Description: string read GetDescription;
    property InputSchema: TJSONObject read GetInputSchema;
    property OutputSchema: TJSONObject read GetOutputSchema;
  end;

  { LOCAL PATCH (Defontsoft, 2026-09-21): the class that carries a tool's
    parameters, reachable from an IMCPTool. GetParamsClass is protected in
    the generic base, so nothing outside could ask a tool which properties
    its arguments bind to - and the host's security gate needs exactly
    that, to read the attributes declared on them. A separate interface
    instead of a new IMCPTool method: non-generic tools owe nothing. }
  IMCPToolParams = interface
    ['{6B0D5C1E-2F3A-4E7B-9C41-8A5D7E90B312}']
    function ParamsClass: TClass;
  end;

  TMCPToolBase = class(TInterfacedObject, IMCPTool)
  protected
    FName: string;
    FTitle: string;
    FDescription: string;
    function BuildSchema: TJSONObject; virtual; abstract;
  public
    constructor Create; virtual;

    function GetName: string;
    function GetTitle: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    function GetOutputSchema: TJSONObject;
    function Execute(const Arguments: TJSONObject): TValue; virtual; abstract;
  end;

  TMCPToolBase<T : class, constructor> = class(TInterfacedObject, IMCPTool,
    IMCPToolParams)
  protected
    FName: string;
    FTitle: string;
    FDescription: string;
    function ExecuteWithParams(const Params: T): string;virtual; abstract;
    function GetParamsClass: TClass; virtual;
  public
    constructor Create; virtual;
    function ParamsClass: TClass; // IMCPToolParams: goes through the virtual

    function GetName: string;
    function GetTitle: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    function GetOutputSchema: TJSONObject;
    function Execute(const Arguments: TJSONObject): TValue;
  end;

  TMCPToolBase<T,R : class, constructor> = class(TInterfacedObject, IMCPTool)
  protected
    FName: string;
    FTitle: string;
    FDescription: string;
    function ExecuteWithParams(const Params: T): R;virtual; abstract;
  public
    constructor Create; virtual;

    function GetName: string;
    function GetTitle: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    function GetOutputSchema: TJSONObject;
    function Execute(const Arguments: TJSONObject): TValue;
  end;




implementation

uses
  MCPServer.Schema.Generator,
  MCPServer.Serializer;

{ TMCPToolBase }

constructor TMCPToolBase.Create;
begin
  inherited Create;
end;

function TMCPToolBase.GetName: string;
begin
  Result := FName;
end;

function TMCPToolBase.GetTitle: string;
begin
  if FTitle <> '' then
    Result := FTitle
  else
    Result := FName;
end;

function TMCPToolBase.GetOutputSchema: TJSONObject;
begin
  result := nil;
end;

function TMCPToolBase.GetDescription: string;
begin
  Result := FDescription;
end;

function TMCPToolBase.GetInputSchema: TJSONObject;
begin
  Result := BuildSchema;
end;

{ TMCPToolBase<T> }

constructor TMCPToolBase<T>.Create;
begin
  inherited Create;
end;

function TMCPToolBase<T>.GetName: string;
begin
  Result := FName;
end;

function TMCPToolBase<T>.GetTitle: string;
begin
  if FTitle <> '' then
    Result := FTitle
  else
    Result := FName;
end;

function TMCPToolBase<T>.GetOutputSchema: TJSONObject;
begin
  result := nil;
end;

function TMCPToolBase<T>.GetDescription: string;
begin
  Result := FDescription;
end;

function TMCPToolBase<T>.GetInputSchema: TJSONObject;
begin
  Result := TMCPSchemaGenerator.GenerateSchema(T);
end;

function TMCPToolBase<T>.Execute(const Arguments: TJSONObject): TValue;
var
  ParamsInstance: T;
begin
  ParamsInstance := TMCPSerializer.Deserialize<T>(Arguments);
  try
    Result := ExecuteWithParams(ParamsInstance);
  finally
    ParamsInstance.Free;
  end;
end;

function TMCPToolBase<T>.ParamsClass: TClass;
begin
  Result := GetParamsClass;
end;

function TMCPToolBase<T>.GetParamsClass: TClass;
begin
  Result := T;
end;


{ TMCPToolBase<T, R> }

constructor TMCPToolBase<T, R>.Create;
begin
  inherited Create;
end;

function TMCPToolBase<T, R>.Execute(const Arguments: TJSONObject): TValue;
var
  ParamsInstance: T;
  Response : R;
  JsonObj : TJSONObject;
begin
  ParamsInstance := TMCPSerializer.Deserialize<T>(Arguments);
  try
    Response := ExecuteWithParams(ParamsInstance);
    try
      JsonObj := TJSONObject.Create;
      TMCPSerializer.Serialize(Response, JsonObj);
      result := TValue.From(JsonObj);
    finally
      Response.Free;
    end;
  finally
    ParamsInstance.Free;
  end;
end;

function TMCPToolBase<T, R>.GetDescription: string;
begin
  result := FDescription;
end;

function TMCPToolBase<T, R>.GetInputSchema: TJSONObject;
begin
  Result := TMCPSchemaGenerator.GenerateSchema(T);
end;

function TMCPToolBase<T, R>.GetName: string;
begin
  Result := FName;
end;

function TMCPToolBase<T, R>.GetTitle: string;
begin
  if FTitle <> '' then
    Result := FTitle
  else
    Result := FName;
end;

function TMCPToolBase<T, R>.GetOutputSchema: TJSONObject;
begin
  Result := TMCPSchemaGenerator.GenerateSchema(R);
end;

end.