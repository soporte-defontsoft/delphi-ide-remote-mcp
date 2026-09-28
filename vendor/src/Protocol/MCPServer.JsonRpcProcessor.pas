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
    class function ExtractRequestID(JSONRequest: TJSONObject): TValue;
    class function CreateJSONResponse(const RequestID: TValue): TJSONObject;
    class procedure AddRequestIDToResponse(Response: TJSONObject; const RequestID: TValue);
    class function ExecuteMethodCall(ManagerRegistry: IMCPManagerRegistry; const MethodName: string; Params: TJSONObject): TValue;
    class function CreateErrorResponse(const RequestID: TValue; ErrorCode: Integer; const ErrorMessage: string): string;
    class function IdValido(IdValue: TJSONValue): Boolean;
  public
    constructor Create(ManagerRegistry: IMCPManagerRegistry);
    function ProcessRequest(const RequestBody: string; const SessionID: string): string;
    { [local change 2026-09-28] EL error JSON-RPC de una peticion en crudo,
      con SU id (null si no se lee): el 404 de una sesion muerta y el de
      stdio lo componian a mano, con id null siempre (septima revision). }
    class function ErrorParaElCuerpo(const ARequestBody: string; ACodigo: Integer;
      const AMensaje: string): string;
    { [local change 2026-09-28] UNA regla para "esto no se contesta": una
      notificacion (method sin id) o una respuesta del cliente (result o
      error sin method), sueltas o en un lote no vacio de ellas. La usan
      ProcessRequest (stdio calla) y el HTTP (su 202): eran dos, y una
      respuesta del cliente oia 202 por HTTP y SYS-032 por stdio; un
      objeto vacio no oia nada y un lote vacio un 202 (octava revision). }
    class function NoSeContesta(AValor: TJSONValue): Boolean;
  end;

const
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;
  JSONRPC_RESOURCE_NOT_FOUND = -32002; // [local change] el de MCP

type
  { [local change 2026-09-27] Un metodo que no existe: su CLASE decide el
    codigo JSON-RPC (-32601), no su texto. }
  EMetodoNoExiste = class(Exception);
  { [local change 2026-09-28] Un recurso que no existe: -32002, el codigo
    de MCP (salia -32602; octava revision). Es un fallo del llamador. }
  ERecursoNoExiste = class(EArgumentException);

implementation

uses
  Lsp.Texts; // [local change 2026-09-27] los textos, del catalogo

{ TMCPJsonRpcProcessor }

constructor TMCPJsonRpcProcessor.Create(ManagerRegistry: IMCPManagerRegistry);
begin
  inherited Create;
  FManagerRegistry := ManagerRegistry;
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

  // [local change 2026-09-28] un numero que no es entero (1.5, 1e30) no se
  // convierte: AsInt64 lanzaba, y el manejador lo volvia a llamar
  var N: Int64;
  if (IdValue is TJSONNumber) and TryStrToInt64(IdValue.Value, N) then
    Result := TValue.From<Int64>(N)
  else if IdValue is TJSONString then
    Result := TValue.From<string>((IdValue as TJSONString).Value)
  else
    Result := TValue.Empty;
end;

class function TMCPJsonRpcProcessor.IdValido(IdValue: TJSONValue): Boolean;
var
  N: Int64;
begin
  Result := (IdValue is TJSONString) or
    ((IdValue is TJSONNumber) and TryStrToInt64(IdValue.Value, N));
end;

class function TMCPJsonRpcProcessor.ErrorParaElCuerpo(const ARequestBody: string;
  ACodigo: Integer; const AMensaje: string): string;
var
  V: TJSONValue;
  Id: TValue;
begin
  Id := TValue.Empty;
  V := nil;
  try
    try
      V := TJSONObject.ParseJSONValue(ARequestBody);
      if V is TJSONObject then
        Id := ExtractRequestID(TJSONObject(V));
    except
      Id := TValue.Empty; // un cuerpo que no se lee: id null
    end;
  finally
    V.Free;
  end;
  Result := CreateErrorResponse(Id, ACodigo, AMensaje);
end;

class function TMCPJsonRpcProcessor.NoSeContesta(AValor: TJSONValue): Boolean;
var
  O: TJSONObject;
  I: Integer;
begin
  if AValor is TJSONObject then
  begin
    O := TJSONObject(AValor);
    // [local change 2026-09-28] una notificacion es un method de TEXTO sin
    // id: {"method":5} sin id no es una notificacion sino una peticion mal
    // formada, y se contesta (-32600 con id null); se callaba (202)
    if O.GetValue('method') <> nil then
      Exit((O.GetValue('id') = nil) and (O.GetValue('method') is TJSONString));
    Exit((O.GetValue('result') <> nil) or (O.GetValue('error') <> nil));
  end;
  // un lote (el protocolo 2025-03-26 los tenia): solo si todo lo que
  // trae son objetos que no se contestan; el vacio es -32600
  Result := (AValor is TJSONArray) and (TJSONArray(AValor).Count > 0);
  if Result then
    for I := 0 to TJSONArray(AValor).Count - 1 do
      if not (TJSONArray(AValor).Items[I] is TJSONObject) or
         not NoSeContesta(TJSONArray(AValor).Items[I]) then
        Exit(False);
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
  Valor: TJSONValue;
begin
  Result := '';
  JSONRequest := nil;
  JSONResponse := nil;
  Valor := nil;

  try
    try
      // [local change 2026-09-28] JSON que no se lee: -32700; lo que no se
      // contesta (NoSeContesta, la regla del HTTP tambien): nada; lo que no
      // es un objeto (un lote con peticiones, [], un valor suelto): -32600,
      // una peticion mal formada, no un JSON roto (octava revision)
      Valor := TJSONObject.ParseJSONValue(RequestBody);
      if not Assigned(Valor) then
        Exit(CreateErrorResponse(TValue.Empty, JSONRPC_PARSE_ERROR,
          MsgText(SR_SYS_JSON_INVALIDO)));
      if NoSeContesta(Valor) then
      begin
        if CampoDeTexto(Valor, 'method') = 'notifications/initialized' then
          TLogger.Info('MCP Initialized notification received')
        else
          TLogger.Info('Notification or client response received: ' +
            CampoDeTexto(Valor, 'method'));
        Exit;
      end;
      if not (Valor is TJSONObject) then
        Exit(CreateErrorResponse(TValue.Empty, JSONRPC_INVALID_REQUEST,
          MsgText(SR_SYS_JSON_NO_OBJETO)));
      JSONRequest := TJSONObject(Valor);

      RequestID := ExtractRequestID(JSONRequest);

      // [local change 2026-09-28] el lector de todos (CampoDeTexto): null o
      // un numero no son un nombre de metodo
      MethodName := CampoDeTexto(JSONRequest, 'method');

      // [local change 2026-09-28] sin method (un {} tambien: no es una
      // notificacion ni una respuesta) o con un id que no es texto ni
      // entero (null incluido: MCP no lo admite): una peticion mal
      // formada, -32600, con su etiqueta
      if MethodName = '' then
        Exit(CreateErrorResponse(RequestID, JSONRPC_INVALID_REQUEST,
          MsgText(SR_SYS_METODO_NO_TEXTO)));
      if not IdValido(JSONRequest.GetValue('id')) then
        Exit(CreateErrorResponse(TValue.Empty, JSONRPC_INVALID_REQUEST,
          MsgText(SR_SYS_ID_NO_VALIDO)));

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
      end
      else
        // [local change 2026-09-28] una PETICION siempre lleva result o
        // error (JSON-RPC 2.0): notifications/initialized con id contestaba
        // {"jsonrpc","id"} sin result (novena revision, M2)
        JSONResponse.AddPair('result', TJSONObject.Create);

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
        if not Assigned(Valor) then
          ErrorCode := JSONRPC_PARSE_ERROR
        else if E is EMetodoNoExiste then
          ErrorCode := JSONRPC_METHOD_NOT_FOUND
        else if E is ERecursoNoExiste then
          ErrorCode := JSONRPC_RESOURCE_NOT_FOUND
        else if EsFalloDelLlamador(E) then // la misma regla que ToolsManager
          ErrorCode := JSONRPC_INVALID_PARAMS;

        Result := CreateErrorResponse(ExtractRequestID(JSONRequest), ErrorCode, E.Message);
      end;
    end;
  finally
    Valor.Free; // JSONRequest es Valor visto como objeto
    JSONResponse.Free;
  end;
end;

end.
