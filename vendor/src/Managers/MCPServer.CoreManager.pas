unit MCPServer.CoreManager;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Rtti,
  System.DateUtils,
  MCPServer.Types,
  MCPServer.Settings,
  MCPServer.Logger;

type
  // [local change] Hooks so the host can enrich the initialize response
  // without this vendored unit knowing anything about it:
  //  - Instructions: server-level guidance handed to the model at connect
  //    time (MCP "instructions" field). Empty/unassigned = omitted.
  //  - DeclarePrompts: advertise the prompts capability when the host
  //    registers a prompts manager.
  TMCPInstructionsFunc = reference to function: string;

  TMCPCoreManager = class(TInterfacedObject, IMCPCapabilityManager)
  private
    // [local change 2026-09-28] sin FSessionID: era UN campo del unico
    // manager, compartido por todos los hilos de Indy, y dos initialize a la
    // vez podian llevarse el MISMO id (medido: 10 de 150 rondas con 4) - un
    // agente leia y borraba el buzon del otro. El id vive en Initialize.
    FSettings: TMCPSettings;
    // [local change] quien es este servidor, para el serverInfo de cada resultado
    // de la era sin sesion, que se compone fuera de cualquier instancia
    class var FNombre, FVersion, FHost: string;
    class function Capacidades: TJSONObject;
    class procedure AnadeInstrucciones(AResultado: TJSONObject);
  public
    class var Instructions: TMCPInstructionsFunc; // [local change]
    class var DeclarePrompts: Boolean;            // [local change]
    constructor Create(ASettings: TMCPSettings);
    
    function GetCapabilityName: string;
    function HandlesMethod(const Method: string): Boolean;
    function ExecuteMethod(const Method: string; const Params: TJSONObject): TValue;
    
    function Initialize(const Params: TJSONObject): TValue;
    function Ping: TValue;
    function Discover: TValue; // [local change] server/discover (2026-07-28)
    class function ServerInfo: TJSONObject; // [local change] de quien lo pide
  end;

implementation

uses
  Lsp.Identidad,
  Lsp.Texts; // [local change] per-session agent identity

{ TMCPCoreManager }

constructor TMCPCoreManager.Create(ASettings: TMCPSettings);
begin
  inherited Create;
  FSettings := ASettings;
  FNombre := FSettings.ServerName;
  FVersion := FSettings.ServerVersion;
  FHost := FSettings.MachineName;
end;

function TMCPCoreManager.GetCapabilityName: string;
begin
  Result := 'core';
end;

function TMCPCoreManager.HandlesMethod(const Method: string): Boolean;
begin
  Result := (Method = 'initialize') or 
            (Method = 'notifications/initialized') or
            (Method = 'ping') or
            (Method = 'server/discover');
end;

function TMCPCoreManager.ExecuteMethod(const Method: string; const Params: TJSONObject): TValue;
begin
  if Method = 'initialize' then
    Result := Initialize(Params)
  else if Method = 'notifications/initialized' then
  begin
    TLogger.Info('MCP Initialized notification received');
    Result := TValue.Empty;
  end
  else if Method = 'ping' then
    Result := Ping
  else if Method = 'server/discover' then
    Result := Discover
  else
    raise Exception.Create(MsgFmt(SE_SYS_METODO_NO_ATENDIDO_FMT, [Method, GetCapabilityName]));
end;

class function TMCPCoreManager.ServerInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FNombre);
  Result.AddPair('version', FVersion);
  // [local change] the machine this server runs on: two servers of the same
  // name and version answer with nothing else that tells them apart
  if FHost <> '' then
    Result.AddPair('host', FHost);
end;

{ [local change] Lo que el servidor sabe hacer: lo dicen initialize y server/discover. }
class function TMCPCoreManager.Capacidades: TJSONObject;
var
  ResourcesCap: TJSONObject;
  ToolsCap: TJSONObject;
begin
  Result := TJSONObject.Create;
  ToolsCap := TJSONObject.Create;
  Result.AddPair('tools', ToolsCap);
{$IF COMPILERVERSION <= 29}
  ToolsCap.AddPair('supportsProgress', TJSONFalse.Create);
  ToolsCap.AddPair('supportsCancellation', TJSONFalse.Create);
{$ELSE}
  ToolsCap.AddPair('supportsProgress', TJSONBool.Create(False));
  ToolsCap.AddPair('supportsCancellation', TJSONBool.Create(False));
{$ENDIF}

  ResourcesCap := TJSONObject.Create;
  Result.AddPair('resources', ResourcesCap);
{$IF COMPILERVERSION <= 29}
  ResourcesCap.AddPair('subscribe', TJSONFalse.Create);
  ResourcesCap.AddPair('listChanged', TJSONFalse.Create);
{$ELSE}
  ResourcesCap.AddPair('subscribe', TJSONBool.Create(False));
  ResourcesCap.AddPair('listChanged', TJSONBool.Create(False));
{$ENDIF}

  // [local change] prompts capability, when the host registered a manager
  if DeclarePrompts then
  begin
    var PromptsCap := TJSONObject.Create;
    Result.AddPair('prompts', PromptsCap);
{$IF COMPILERVERSION <= 29}
    PromptsCap.AddPair('listChanged', TJSONFalse.Create);
{$ELSE}
    PromptsCap.AddPair('listChanged', TJSONBool.Create(False));
{$ENDIF}
  end;
end;

{ [local change] server instructions handed to the model at connect time }
class procedure TMCPCoreManager.AnadeInstrucciones(AResultado: TJSONObject);
begin
  if Assigned(Instructions) then
  begin
    var Text := Instructions();
    if Text <> '' then
      AResultado.AddPair('instructions', Text);
  end;
end;

{ [local change] Las versiones que se hablan, las capacidades y las instrucciones,
  sin sesion ni nada que recordar. resultType, serverInfo y las pistas de cache los
  pone quien anota cada resultado de esta era (TMCPJsonRpcProcessor.AnotaModerno). }
function TMCPCoreManager.Discover: TValue;
var
  ResultJSON: TJSONObject;
  Versiones: TJSONArray;
begin
  ResultJSON := TJSONObject.Create;
  try
    Versiones := TJSONArray.Create;
    ResultJSON.AddPair('supportedVersions', Versiones);
    Versiones.Add(MCP_PROTOCOLO_MODERNO);
    Versiones.Add(MCP_PROTOCOL_VERSION);
    ResultJSON.AddPair('capabilities', Capacidades);
    AnadeInstrucciones(ResultJSON);
    Result := TValue.From<TJSONObject>(ResultJSON);
  except
    ResultJSON.Free;
    raise;
  end;
end;

function TMCPCoreManager.Initialize(const Params: TJSONObject): TValue;
var
  ClientInfo: TJSONObject;
  ClientName: TJSONValue;
  ClientVersion: TJSONValue;
  ResultJSON: TJSONObject;
begin
  TLogger.Info('MCP Initialize called');
  // [local change 2026-09-26] Se asignaban solo si llegaba clientInfo, y
  // ClientName se lee mas abajo: un initialize SIN clientInfo contestaba un
  // Access violation (medido por test_http_auth al endurecerlo; el
  // compilador lo avisaba en cada build con W1036).
  ClientName := nil;
  ClientVersion := nil;
  
  // [local change 2026-09-28] clientInfo que no es un objeto era un
  // -32603 "Invalid class typecast" sin etiqueta, y un name null o 5 daba
  // la sesion "null" / "5" (compartida entre clientes): el lector de todos
  ClientName := nil;
  if Assigned(Params) and (Params.GetValue('clientInfo') is TJSONObject) then
  begin
    ClientInfo := TJSONObject(Params.GetValue('clientInfo'));
    if CampoDeTexto(ClientInfo, 'name') <> '' then
      ClientName := ClientInfo.GetValue('name');
    TLogger.Info(Format('Client: %s v%s', [CampoDeTexto(ClientInfo, 'name'),
      CampoDeTexto(ClientInfo, 'version')]));
  end;
  
  var SesionId := TGuid.NewGuid.ToString; // de ESTA llamada (ver la nota de la clase)
  // [local change] stdio is one process = one client: no session header ever
  // arrives, so bind the identity here and now, for the life of the process.
  // Over HTTP this thread's identity is reset per request anyway, and the
  // real binding is session id -> name in the HTTP layer.
  if Assigned(ClientName) then
  begin
    BindSessionIdentity(SesionId, ClientName.Value);
    SetThreadIdentity(ClientName.Value);
  end;
  
  ResultJSON := TJSONObject.Create;
  try
    ResultJSON.AddPair('protocolVersion', MCP_PROTOCOL_VERSION);
    
    ResultJSON.AddPair('capabilities', Capacidades);

    ResultJSON.AddPair('sessionId', SesionId);

    ResultJSON.AddPair('serverInfo', ServerInfo);

    AnadeInstrucciones(ResultJSON);
    
    TLogger.Info('Created new MCP session: ' + SesionId);
    
    Result := TValue.From<TJSONObject>(ResultJSON);
  except
    ResultJSON.Free;
    raise;
  end;
end;

function TMCPCoreManager.Ping: TValue;
var
  ResultJSON: TJSONObject;
begin
  TLogger.Info('MCP Ping called');
  
  ResultJSON := TJSONObject.Create;
  try
    Result := TValue.From<TJSONObject>(ResultJSON);
  except
    ResultJSON.Free;
    raise;
  end;
end;

end.