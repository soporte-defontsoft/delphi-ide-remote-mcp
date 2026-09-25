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
    FSessionID: string;
    FSettings: TMCPSettings;
  public
    class var Instructions: TMCPInstructionsFunc; // [local change]
    class var DeclarePrompts: Boolean;            // [local change]
    constructor Create(ASettings: TMCPSettings);
    
    function GetCapabilityName: string;
    function HandlesMethod(const Method: string): Boolean;
    function ExecuteMethod(const Method: string; const Params: TJSONObject): TValue;
    
    function Initialize(const Params: TJSONObject): TValue;
    function Ping: TValue;
    
    property SessionID: string read FSessionID;
  end;

implementation

uses
  Lsp.Guard; // [local change] per-session agent identity

{ TMCPCoreManager }

constructor TMCPCoreManager.Create(ASettings: TMCPSettings);
begin
  inherited Create;
  FSettings := ASettings;
  FSessionID := '';
end;

function TMCPCoreManager.GetCapabilityName: string;
begin
  Result := 'core';
end;

function TMCPCoreManager.HandlesMethod(const Method: string): Boolean;
begin
  Result := (Method = 'initialize') or 
            (Method = 'notifications/initialized') or
            (Method = 'ping');
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
  else
    raise Exception.CreateFmt('Method %s not handled by %s', [Method, GetCapabilityName]);
end;

function TMCPCoreManager.Initialize(const Params: TJSONObject): TValue;
var
  Capabilities: TJSONObject;
  ClientInfo: TJSONObject;
  ClientName: TJSONValue;
  ClientVersion: TJSONValue;
  ResourcesCap: TJSONObject;
  ResultJSON: TJSONObject;
  ServerInfo: TJSONObject;
  ToolsCap: TJSONObject;
begin
  TLogger.Info('MCP Initialize called');
  
  if Assigned(Params) then
  begin
    ClientInfo := Params.GetValue('clientInfo') as TJSONObject;

    if Assigned(ClientInfo) then
    begin
      ClientName := ClientInfo.GetValue('name');
      ClientVersion := ClientInfo.GetValue('version');

      if Assigned(ClientName) and Assigned(ClientVersion) then
        TLogger.Info(Format('Client: %s v%s', [ClientName.Value, ClientVersion.Value]));
    end;
  end;
  
  FSessionID := TGuid.NewGuid.ToString;
  // [local change] stdio is one process = one client: no session header ever
  // arrives, so bind the identity here and now, for the life of the process.
  // Over HTTP this thread's identity is reset per request anyway, and the
  // real binding is session id -> name in the HTTP layer.
  if Assigned(ClientName) then
  begin
    BindSessionIdentity(FSessionID, ClientName.Value);
    SetThreadIdentity(ClientName.Value);
  end;
  
  ResultJSON := TJSONObject.Create;
  try
    ResultJSON.AddPair('protocolVersion', MCP_PROTOCOL_VERSION);
    
    Capabilities := TJSONObject.Create;
    ResultJSON.AddPair('capabilities', Capabilities);
    
    ToolsCap := TJSONObject.Create;
    Capabilities.AddPair('tools', ToolsCap);
{$IF COMPILERVERSION <= 29}
    ToolsCap.AddPair('supportsProgress', TJSONFalse.Create);
    ToolsCap.AddPair('supportsCancellation', TJSONFalse.Create);
{$ELSE}
    ToolsCap.AddPair('supportsProgress', TJSONBool.Create(False));
    ToolsCap.AddPair('supportsCancellation', TJSONBool.Create(False));
{$ENDIF}
    
    ResourcesCap := TJSONObject.Create;
    Capabilities.AddPair('resources', ResourcesCap);
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
      Capabilities.AddPair('prompts', PromptsCap);
{$IF COMPILERVERSION <= 29}
      PromptsCap.AddPair('listChanged', TJSONFalse.Create);
{$ELSE}
      PromptsCap.AddPair('listChanged', TJSONBool.Create(False));
{$ENDIF}
    end;

    ResultJSON.AddPair('sessionId', FSessionID);

    ServerInfo := TJSONObject.Create;
    ResultJSON.AddPair('serverInfo', ServerInfo);
    ServerInfo.AddPair('name', FSettings.ServerName);
    ServerInfo.AddPair('version', FSettings.ServerVersion);

    // [local change] server instructions handed to the model at connect time
    if Assigned(Instructions) then
    begin
      var Text := Instructions();
      if Text <> '' then
        ResultJSON.AddPair('instructions', Text);
    end;
    
    TLogger.Info('Created new MCP session: ' + FSessionID);
    
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