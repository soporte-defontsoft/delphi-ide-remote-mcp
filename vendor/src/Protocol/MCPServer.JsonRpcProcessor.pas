unit MCPServer.JsonRpcProcessor;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Rtti,
  MCPServer.Types,
  MCPServer.Logger;

type
  TMCPJsonRpcProcessor = class
  private
    FManagerRegistry: IMCPManagerRegistry;
    class function ParseJSONRequest(const RequestBody: string): TJSONObject;
    class function ExtractRequestID(JSONRequest: TJSONObject): TValue;
    class function CreateJSONResponse(const RequestID: TValue): TJSONObject;
    class procedure AddRequestIDToResponse(Response: TJSONObject; const RequestID: TValue);
    class function ExecuteMethodCall(ManagerRegistry: IMCPManagerRegistry; const MethodName: string; Params: TJSONObject): TValue;
    class function CreateErrorResponse(const RequestID: TValue; ErrorCode: Integer; const ErrorMessage: string): string;
  public
    constructor Create(ManagerRegistry: IMCPManagerRegistry);
    function ProcessRequest(const RequestBody: string; const SessionID: string): string;
  end;

const
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;

type
  { [local change 2026-09-27] Un metodo que no existe: su CLASE decide el
    codigo JSON-RPC (-32601), no su texto. }
  EMetodoNoExiste = class(Exception);

implementation

uses
  Lsp.Texts; // [local change 2026-09-27] los textos, del catalogo

{ TMCPJsonRpcProcessor }

constructor TMCPJsonRpcProcessor.Create(ManagerRegistry: IMCPManagerRegistry);
begin
  inherited Create;
  FManagerRegistry := ManagerRegistry;
end;

class function TMCPJsonRpcProcessor.ParseJSONRequest(const RequestBody: string): TJSONObject;
var
  ParsedValue: TJSONValue;
begin
  ParsedValue := TJSONObject.ParseJSONValue(RequestBody);
  if not Assigned(ParsedValue) then
    raise EArgumentException.Create(MsgText(SR_SYS_JSON_INVALIDO));

  if not (ParsedValue is TJSONObject) then
  begin
    ParsedValue.Free;
    raise EArgumentException.Create(MsgText(SR_SYS_JSON_NO_OBJETO));
  end;

  Result := ParsedValue as TJSONObject;
end;

class function TMCPJsonRpcProcessor.ExtractRequestID(JSONRequest: TJSONObject): TValue;
var
  IdValue: TJSONValue;
begin
  // JSONRequest is nil when the request body failed to parse; there is no id
  // to extract. Without this guard the nil dereference surfaces as
  // "Access violation ... Read of address 0000000000000010" for any
  // syntactically invalid request.
  if not Assigned(JSONRequest) then
  begin
    Result := TValue.Empty;
    Exit;
  end;

  IdValue := JSONRequest.GetValue('id');
  if not Assigned(IdValue) then
  begin
    Result := TValue.Empty;
    Exit;
  end;

  if IdValue is TJSONNumber then
    Result := TValue.From<Int64>((IdValue as TJSONNumber).AsInt64)
  else if IdValue is TJSONString then
    Result := TValue.From<string>((IdValue as TJSONString).Value)
  else
    Result := TValue.Empty;
end;

class function TMCPJsonRpcProcessor.CreateJSONResponse(const RequestID: TValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  AddRequestIDToResponse(Result, RequestID);
end;

class procedure TMCPJsonRpcProcessor.AddRequestIDToResponse(Response: TJSONObject; const RequestID: TValue);
begin
  if RequestID.IsEmpty then
  begin
    Response.AddPair('id', TJSONNull.Create);
    Exit;
  end;

  if RequestID.Kind in [tkString, tkUString, tkWString, tkLString] then
    Response.AddPair('id', RequestID.AsString)
  else if RequestID.Kind in [tkInteger, tkInt64] then
    Response.AddPair('id', TJSONNumber.Create(RequestID.AsInt64))
  else
    Response.AddPair('id', TJSONNull.Create);
end;

class function TMCPJsonRpcProcessor.ExecuteMethodCall(ManagerRegistry: IMCPManagerRegistry;
  const MethodName: string; Params: TJSONObject): TValue;
var
  Manager: IMCPCapabilityManager;
begin
  if not Assigned(ManagerRegistry) then
    raise Exception.Create(MsgText(SE_SYS_SIN_REGISTRO));

  Manager := ManagerRegistry.GetManagerForMethod(MethodName);
  if not Assigned(Manager) then
    raise EMetodoNoExiste.Create(MsgFmt(SR_SYS_METODO_NO_EXISTE_FMT, [MethodName]));

  Result := Manager.ExecuteMethod(MethodName, Params);
end;

class function TMCPJsonRpcProcessor.CreateErrorResponse(const RequestID: TValue;
  ErrorCode: Integer; const ErrorMessage: string): string;
var
  ErrorObj: TJSONObject;
  JSONResponse: TJSONObject;
begin
  JSONResponse := CreateJSONResponse(RequestID);
  try
    ErrorObj := TJSONObject.Create;
    JSONResponse.AddPair('error', ErrorObj);
    ErrorObj.AddPair('code', TJSONNumber.Create(ErrorCode));
    ErrorObj.AddPair('message', ErrorMessage);
    Result := JSONResponse.ToJSON;
  finally
    JSONResponse.Free;
  end;
end;

function TMCPJsonRpcProcessor.ProcessRequest(const RequestBody: string; const SessionID: string): string;
var
  ErrorCode: Integer;
  ExecuteResult: TValue;
  JSONRequest: TJSONObject;
  JSONResponse: TJSONObject;
  MethodName: string;
  MethodValue: TJSONValue;
  Params: TJSONObject;
  ParamsValue: TJSONValue;
  RequestID: TValue;
begin
  Result := '';
  JSONRequest := nil;
  JSONResponse := nil;

  try
    try
      JSONRequest := ParseJSONRequest(RequestBody);

      RequestID := ExtractRequestID(JSONRequest);

      MethodValue := JSONRequest.GetValue('method');
      MethodName := '';
      if Assigned(MethodValue) then
        MethodName := MethodValue.Value;

      // Notifications (requests without id) should not have a response
      if RequestID.IsEmpty then
      begin
        if MethodName = 'notifications/initialized' then
          TLogger.Info('MCP Initialized notification received')
        else
          TLogger.Info('Notification received: ' + MethodName);
        Exit;
      end;

      JSONResponse := CreateJSONResponse(RequestID);

      ParamsValue := JSONRequest.GetValue('params');
      Params := nil;
      if Assigned(ParamsValue) and (ParamsValue is TJSONObject) then
        Params := ParamsValue as TJSONObject;

      ExecuteResult := ExecuteMethodCall(FManagerRegistry, MethodName, Params);

      if not ExecuteResult.IsEmpty then
      begin
        if ExecuteResult.IsType<TJSONObject> then
          JSONResponse.AddPair('result', ExecuteResult.AsType<TJSONObject>)
        else if ExecuteResult.IsType<string> then
          JSONResponse.AddPair('result', ExecuteResult.AsString)
        else
          JSONResponse.AddPair('result', ExecuteResult.ToString);
      end;

      Result := JSONResponse.ToJSON;

    except
      on E: Exception do
      begin
        TLogger.Error('Error processing request: ' + E.Message);

        // If parsing failed, JSONRequest is still nil: report a JSON-RPC parse
        // error (-32700). ExtractRequestID is nil-safe and yields a null id.
        // [local change 2026-09-27] el codigo por la CLASE de la excepcion,
        // nunca por lo que diga su texto (se buscaba "not found" en el)
        ErrorCode := JSONRPC_INTERNAL_ERROR;
        if not Assigned(JSONRequest) then
          ErrorCode := JSONRPC_PARSE_ERROR
        else if E is EMetodoNoExiste then
          ErrorCode := JSONRPC_METHOD_NOT_FOUND
        else if EsFalloDelLlamador(E) then // la misma regla que ToolsManager
          ErrorCode := JSONRPC_INVALID_PARAMS;

        Result := CreateErrorResponse(ExtractRequestID(JSONRequest), ErrorCode, E.Message);
      end;
    end;
  finally
    JSONRequest.Free;
    JSONResponse.Free;
  end;
end;

end.
