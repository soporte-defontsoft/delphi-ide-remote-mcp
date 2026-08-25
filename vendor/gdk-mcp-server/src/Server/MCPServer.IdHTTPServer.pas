unit MCPServer.IdHTTPServer;

interface

// TaurusTLS provides OpenSSL 3.x support with modern ECDHE cipher suites
// Install via GetIt Package Manager: Search for "TaurusTLS" or get from https://github.com/JPeterMugaas/TaurusTLS
{ $DEFINE USE_TAURUS_TLS}  // [local change] disabled: standard Indy SSL, no TaurusTLS dependency

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions, // [local change] Mcp-Session-Id on SSE initialize
  System.Classes,
  System.SyncObjs, // [local change] session registry lock
  System.JSON,
  System.Rtti,
  System.IOUtils,
  System.Generics.Collections,
  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,
  IdGlobal,
  IdGlobalProtocols,
  {$IFDEF USE_TAURUS_TLS}
  TaurusTLS,
  {$ELSE}
  IdSSLOpenSSL,
  {$ENDIF}
  IdServerIOHandler,
  MCPServer.Types,
  MCPServer.Settings,
  MCPServer.JsonRpcProcessor;

type
  // [local change] tells the host which access level the current request
  // authenticated at, so it can flag the worker thread (read-only vs full).
  TAccessLevelEvent = reference to procedure(AReadOnly: Boolean);
  // [local change] a second route next to the MCP endpoint (direct file
  // download): the host serves it; this class only authenticates and routes.
  TRouteEvent = reference to procedure(RequestInfo: TIdHTTPRequestInfo;
    ResponseInfo: TIdHTTPResponseInfo);

  TMCPIdHTTPServer = class(TComponent)
  private
    FHTTPServer: TIdHTTPServer;
    {$IFDEF USE_TAURUS_TLS}
    FSSLHandler: TTaurusTLSServerIOHandler;
    {$ELSE}
    FSSLHandler: TIdServerIOHandlerSSLOpenSSL;
    {$ENDIF}
    FManagerRegistry: IMCPManagerRegistry;
    FCoreManager: IMCPCapabilityManager;
    FJsonRpcProcessor: TMCPJsonRpcProcessor;
    FPort: Word;
    FActive: Boolean;
    FAuthToken: string; // [local change] optional Bearer token for remote use
    FReadOnlyToken: string;      // [local change] second token: read-only access
    FAnonymousReadOnly: Boolean; // [local change] no token = read-only access
    FOnAccessLevel: TAccessLevelEvent; // [local change] per-request RO/RW flag
    FBindIP: string; // [local change] bind to ONE interface ('' = all)
    FFilesRoute: string;        // [local change] '' = no download route
    FOnFileRequest: TRouteEvent; // [local change] GET handler for FFilesRoute
    FSettings: TMCPSettings;
    FEventIDCounter: Int64;
    procedure ConfigureSSL;
    procedure HandleQuerySSLPort(APort: Word; var VUseSSL: Boolean);
    procedure HandleHTTPRequest(Context: TIdContext; RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo);
    // [local change] accept the Bearer scheme (Indy rejects unknown schemes
    // with 401 "Unsupported authorization scheme" before our handler runs)
    procedure HandleParseAuthentication(AContext: TIdContext;
      const AAuthType, AAuthData: string; var VUsername, VPassword: string;
      var VHandled: Boolean);
    function VerifyAndSetCORSHeaders(RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo): Boolean;
    procedure HandleOptionsRequest(ResponseInfo: TIdHTTPResponseInfo);
    procedure HandleGetRequest(RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo);
    procedure HandlePostRequest(RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo);
    procedure HandlePostRequestSSE(RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo; const RequestBody: string; const SessionID: string);
    procedure HandlePostRequestJSON(RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo; const RequestBody: string; const SessionID: string);
    function GetNextEventID: string;
    function AcceptsSSE(const AcceptHeader: string): Boolean;
    function IsRequestOnlyNotificationsOrResponses(JSONRequest: TJSONValue): Boolean;
  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Port: Word read FPort write FPort;
    property Active: Boolean read FActive;
    // [local change] two-tier Bearer auth. AuthToken grants read-write;
    // ReadOnlyToken grants read-only; AnonymousReadOnly lets tokenless
    // requests in as read-only. With any token configured, everything else
    // is answered 401. With nothing configured: open, read-write (local
    // trusted mode). OnAccessLevel fires on every accepted request so the
    // host can flag the worker thread (threads are reused: always fired).
    property AuthToken: string read FAuthToken write FAuthToken;
    property ReadOnlyToken: string read FReadOnlyToken write FReadOnlyToken;
    property AnonymousReadOnly: Boolean read FAnonymousReadOnly write FAnonymousReadOnly;
    property OnAccessLevel: TAccessLevelEvent read FOnAccessLevel write FOnAccessLevel;
    // [local change] bind to a SINGLE interface (settings.ini [Server] BindIP).
    // Empty = listen on all interfaces (the default; also the source of the
    // duplicate IPv4+IPv6 firewall prompt). Set e.g. to a LAN/VPN address.
    property BindIP: string read FBindIP write FBindIP;
    // [local change] direct download route (e.g. '/files'): GET requests to
    // this document, once past the SAME Bearer gate as the MCP endpoint, go
    // to OnFileRequest. Other methods on it answer 405. Empty = not served.
    property FilesRoute: string read FFilesRoute write FFilesRoute;
    property OnFileRequest: TRouteEvent read FOnFileRequest write FOnFileRequest;
    property ManagerRegistry: IMCPManagerRegistry read FManagerRegistry write FManagerRegistry;
    property CoreManager: IMCPCapabilityManager read FCoreManager write FCoreManager;
    property Settings: TMCPSettings read FSettings write FSettings;
  end;

implementation

uses
  MCPServer.Resource.Server,
  MCPServer.CoreManager,
  MCPServer.Logger;

// [local change] Issued session ids. The upstream server echoes whatever
// Mcp-Session-Id a client sends and never checks it, so a client that
// persists its session across a SERVER RESTART keeps using a dead id and is
// never told (field report 2026-08-25: a garbage id was accepted). Auth is
// the Bearer token, so this was never a security hole - but the streamable
// HTTP contract says an unknown session must answer 404 so the client
// re-initializes. Bounded ring: the last SESSION_KEEP ids of this process.
const
  SESSION_KEEP = 64;

var
  GSessLock: TCriticalSection;
  GSessions: TStringList;

procedure RememberSession(const AId: string);
begin
  if AId = '' then
    Exit;
  GSessLock.Enter;
  try
    if GSessions.IndexOf(AId) < 0 then
    begin
      GSessions.Add(AId);
      while GSessions.Count > SESSION_KEEP do
        GSessions.Delete(0);
    end;
  finally
    GSessLock.Leave;
  end;
end;

function KnownSession(const AId: string): Boolean;
begin
  GSessLock.Enter;
  try
    Result := GSessions.IndexOf(AId) >= 0;
  finally
    GSessLock.Leave;
  end;
end;

const
  KEEP_ALIVE_TIMEOUT = 300;
  DEFAULT_MCP_PORT = 3000;

  // HTTP Status Codes
  HTTP_OK = 200;
  HTTP_ACCEPTED = 202;
  HTTP_NO_CONTENT = 204;
  HTTP_NOT_FOUND = 404;
  HTTP_METHOD_NOT_ALLOWED = 405;
  HTTP_NOT_ACCEPTABLE = 406;
  HTTP_FORBIDDEN = 403;

  // CORS Max Age (24 hours in seconds)
  CORS_MAX_AGE = 86400;

  // JSON-RPC 2.0 Error Codes
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;

  // SSE Message Format
  SSE_EVENT_PREFIX = 'event: ';
  SSE_DATA_PREFIX = 'data: ';
  SSE_ID_PREFIX = 'id: ';
  SSE_MESSAGE_TERMINATOR = #10#10;

{ TMCPIdHTTPServer }

constructor TMCPIdHTTPServer.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FPort := DEFAULT_MCP_PORT;
  FActive := False;
  FEventIDCounter := 0;
  FJsonRpcProcessor := nil;

  FHTTPServer := TIdHTTPServer.Create(Self);
  FHTTPServer.KeepAlive := True;
  FHTTPServer.OnCommandGet := HandleHTTPRequest;
  FHTTPServer.OnCommandOther := HandleHTTPRequest;
  FHTTPServer.OnQuerySSLPort := HandleQuerySSLPort;
  FHTTPServer.OnParseAuthentication := HandleParseAuthentication; // [local change]
  FSSLHandler := nil;
end;

destructor TMCPIdHTTPServer.Destroy;
begin
  if FActive then
    Stop;
  FHTTPServer.Free;
  if Assigned(FSSLHandler) then
    FSSLHandler.Free;
  FJsonRpcProcessor.Free;
  inherited;
end;

procedure TMCPIdHTTPServer.Start;
begin
  if FActive then
    Exit;

  if not Assigned(FManagerRegistry) then
    raise Exception.Create('Manager registry not assigned');

  FJsonRpcProcessor := TMCPJsonRpcProcessor.Create(FManagerRegistry);

  if Assigned(FSettings) then
  begin
    FPort := Word(FSettings.Port);

    // Configure SSL if enabled
    if FSettings.SSLEnabled then
      ConfigureSSL;
  end;

  FHTTPServer.DefaultPort := FPort;
  // [local change] one explicit binding when BindIP is set: avoids listening
  // on every interface (and the double IPv4+IPv6 firewall prompt).
  if FBindIP.Trim <> '' then
  begin
    FHTTPServer.Bindings.Clear;
    with FHTTPServer.Bindings.Add do
    begin
      IP := FBindIP.Trim;
      Port := FPort;
    end;
  end;
  FHTTPServer.Active := True;
  FActive := True;

  TLogger.Info('MCP Server started on ' + FSettings.Protocol + '://' +
    IfThen(FBindIP.Trim <> '', FBindIP.Trim, FSettings.Host) + ':' + IntToStr(FPort));
end;

procedure TMCPIdHTTPServer.Stop;
begin
  if not FActive then
    Exit;
    
  FHTTPServer.Active := False;
  FActive := False;
  TLogger.Info('MCP Server stopped');
end;

// [local change]
procedure TMCPIdHTTPServer.HandleParseAuthentication(AContext: TIdContext;
  const AAuthType, AAuthData: string; var VUsername, VPassword: string;
  var VHandled: Boolean);
begin
  if SameText(AAuthType, 'Bearer') then
  begin
    VUsername := '';
    VPassword := AAuthData;
    VHandled := True; // the real check happens in HandleHTTPRequest
  end;
end;

procedure TMCPIdHTTPServer.HandleHTTPRequest(Context: TIdContext;
  RequestInfo: TIdHTTPRequestInfo; ResponseInfo: TIdHTTPResponseInfo);
var
  RequestPath: string;
begin
  TServerStatusResource.ConnectionOpened;
  try
    TServerStatusResource.IncrementRequestCount;

    if not VerifyAndSetCORSHeaders(RequestInfo, ResponseInfo) then
      Exit; // CORS blocked the request

    // [local change] two-tier Bearer auth for remote exposure (OPTIONS
    // preflight is exempt: it carries no credentials by design).
    if RequestInfo.Command <> 'OPTIONS' then
    begin
      var Auth := RequestInfo.RawHeaders.Values['Authorization'];
      var ReadOnly := False;
      var Allowed := False;
      if (FAuthToken = '') and (FReadOnlyToken = '') then
      begin
        // no tokens configured: open access (local trusted mode); with
        // AnonymousReadOnly the whole open server is read-only instead.
        Allowed := True;
        ReadOnly := FAnonymousReadOnly;
      end
      else if (FAuthToken <> '') and (Auth = 'Bearer ' + FAuthToken) then
        Allowed := True // full read-write
      else if (FReadOnlyToken <> '') and (Auth = 'Bearer ' + FReadOnlyToken) then
      begin
        Allowed := True;
        ReadOnly := True;
      end
      else if FAnonymousReadOnly and (Auth = '') then
      begin
        Allowed := True; // no credentials presented: read-only access
        ReadOnly := True;
      end;
      if not Allowed then
      begin
        ResponseInfo.ResponseNo := 401;
        ResponseInfo.ResponseText := 'Unauthorized';
        ResponseInfo.ContentType := 'application/json';
        ResponseInfo.ContentText := '{"error":"missing or invalid bearer token"}';
        Exit;
      end;
      // Worker threads are reused: flag the access level on EVERY request.
      if Assigned(FOnAccessLevel) then
        FOnAccessLevel(ReadOnly);
    end;

    RequestPath := RequestInfo.Document;

    // [local change] direct download route: same Bearer gate (already passed
    // above), the host decides jail, existence and streaming.
    if (FFilesRoute <> '') and Assigned(FOnFileRequest) and
       SameText(RequestPath, FFilesRoute) then
    begin
      if RequestInfo.CommandType = hcGET then
        FOnFileRequest(RequestInfo, ResponseInfo)
      else
      begin
        ResponseInfo.ResponseNo := HTTP_METHOD_NOT_ALLOWED;
        ResponseInfo.ResponseText := 'Method Not Allowed';
      end;
      Exit;
    end;

    // Only handle requests to the configured MCP endpoint
    if (RequestPath <> FSettings.Endpoint) then
    begin
      ResponseInfo.ResponseNo := HTTP_NOT_FOUND;
      ResponseInfo.ResponseText := 'Not Found';
      Exit;
    end;
    
    if RequestInfo.Command = 'OPTIONS' then
      HandleOptionsRequest(ResponseInfo)
    else if RequestInfo.CommandType = hcGET then
      HandleGetRequest(RequestInfo, ResponseInfo)
    else if RequestInfo.CommandType = hcPOST then
      HandlePostRequest(RequestInfo, ResponseInfo)
    else
    begin
      ResponseInfo.ResponseNo := HTTP_METHOD_NOT_ALLOWED;
      ResponseInfo.ResponseText := 'Method Not Allowed';
    end;
  finally
    TServerStatusResource.ConnectionClosed;
  end;
end;

function TMCPIdHTTPServer.VerifyAndSetCORSHeaders(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  AllowedOrigin: string;
  CurrentOrigin: string;
  Found: Boolean;
  Origin: string;
  OriginsList: TStringList;
begin
  Result := True;

  if not Assigned(FSettings) or not FSettings.CorsEnabled then
    Exit;

  Origin := RequestInfo.RawHeaders.Values['Origin'];
  AllowedOrigin := '*';

  if (FSettings.CorsAllowedOrigins <> '*') and (Origin <> '') then
  begin
    OriginsList := TStringList.Create;
    try
      OriginsList.CommaText := FSettings.CorsAllowedOrigins;
      Found := False;

      for CurrentOrigin in OriginsList do
      begin
        if SameText(Trim(CurrentOrigin), Origin) then
        begin
          AllowedOrigin := Origin;
          Found := True;
          Break;
        end;
      end;

      if not Found then
      begin
        Result := False;
        ResponseInfo.ResponseNo := HTTP_FORBIDDEN;
        ResponseInfo.ResponseText := 'Forbidden - Origin not allowed';
        TLogger.Info('CORS blocked origin: ' + Origin);
        Exit;
      end;
    finally
      OriginsList.Free;
    end;
  end;

  ResponseInfo.CustomHeaders.Values['Access-Control-Allow-Origin'] := AllowedOrigin;
  ResponseInfo.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'POST, GET, OPTIONS';
  ResponseInfo.CustomHeaders.Values['Access-Control-Allow-Headers'] :=
    'Accept, Content-Type, Last-Event-ID, Mcp-Protocol-Version, Mcp-Session-Id';
  ResponseInfo.CustomHeaders.Values['Access-Control-Expose-Headers'] := 'Mcp-Session-Id';
  ResponseInfo.CustomHeaders.Values['Access-Control-Max-Age'] := CORS_MAX_AGE.ToString;
end;

procedure TMCPIdHTTPServer.HandleOptionsRequest(ResponseInfo: TIdHTTPResponseInfo);
begin
  ResponseInfo.ResponseNo := HTTP_OK;
  ResponseInfo.ResponseText := 'OK';
end;

procedure TMCPIdHTTPServer.HandleGetRequest(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo);
var
  AcceptHeader: string;
  SessionID: string;
begin
  AcceptHeader := RequestInfo.RawHeaders.Values['Accept'];

  if AcceptsSSE(AcceptHeader) then
  begin
    TLogger.Debug('Received GET request - opening SSE stream for server-initiated messages');

    ResponseInfo.ContentType := 'text/event-stream';
    ResponseInfo.CharSet := 'utf-8';
    ResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-cache';
    ResponseInfo.CustomHeaders.Values['Connection'] := 'keep-alive';
    ResponseInfo.CustomHeaders.Values['X-Accel-Buffering'] := 'no';

    SessionID := RequestInfo.RawHeaders.Values['Mcp-Session-Id'];
    if SessionID <> '' then
      ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := SessionID;

    ResponseInfo.ResponseNo := HTTP_OK;
    ResponseInfo.ContentText := ''; // Empty SSE stream, close immediately

    // Note: GET endpoint for SSE streams is optional per MCP spec 2025-03-26
    // Server MAY keep connection open to send server-initiated notifications/requests
    // Current implementation: basic support, closes stream immediately (no persistent connection)
    TLogger.Debug('SSE stream opened (no server-initiated messages to send)');
  end
  else
  begin
    TLogger.Info('Received GET request - returning endpoint info');

    ResponseInfo.ContentType := 'application/json';
    ResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-cache';
    ResponseInfo.CustomHeaders.Values['Connection'] := 'keep-alive';

    ResponseInfo.ContentText := '{"url": "' + FSettings.Protocol + '://' + FSettings.Host + ':' + IntToStr(FPort) +
                    FSettings.Endpoint + '", "transport": "' + FSettings.Protocol + '"}';

    ResponseInfo.ResponseNo := HTTP_OK;
  end;
end;

procedure TMCPIdHTTPServer.HandlePostRequest(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo);
var
  AcceptHeader: string;
  JSONRequest: TJSONValue;
  RequestBody: string;
  SessionID: string;
begin
  RequestBody := '';
  if Assigned(RequestInfo.PostStream) and (RequestInfo.PostStream.Size > 0) then
  begin
    RequestInfo.PostStream.Position := 0;
    RequestBody := ReadStringFromStream(RequestInfo.PostStream, -1, IndyTextEncoding_UTF8);
  end;

  // [local change] secrets in arguments (PAServer password) never reach the log
  TLogger.Info('Request: ' + MaskSecretValues(RequestBody));

  SessionID := RequestInfo.RawHeaders.Values['Mcp-Session-Id'];
  if SessionID <> '' then
    TLogger.Info('Session ID from header: ' + SessionID);
  // [local change] an id this process never issued is a DEAD session (most
  // often: the client persisted it and the server was restarted). Say so
  // with 404, the answer the streamable-HTTP contract defines, so the
  // client re-initializes instead of working against a ghost. An
  // initialize request carrying a stale id is welcome: it is the fix.
  if (SessionID <> '') and not KnownSession(SessionID) and
     (Pos('"initialize"', RequestBody) = 0) then
  begin
    ResponseInfo.ResponseNo := 404;
    ResponseInfo.ContentType := 'application/json';
    ResponseInfo.ContentText :=
      '{"jsonrpc":"2.0","error":{"code":-32001,"message":"Session not found: ' +
      'this server never issued that Mcp-Session-Id (it was probably ' +
      'restarted). Send initialize again and use the new session id."}}';
    TLogger.Info('Refused unknown session id: ' + SessionID);
    Exit;
  end;

  AcceptHeader := RequestInfo.RawHeaders.Values['Accept'];

  JSONRequest := nil;
  try
    JSONRequest := TJSONObject.ParseJSONValue(RequestBody);

    if Assigned(JSONRequest) and IsRequestOnlyNotificationsOrResponses(JSONRequest) then
    begin
      TLogger.Info('Request contains only notifications/responses, returning 202 Accepted');
      ResponseInfo.ResponseNo := HTTP_ACCEPTED;

      if SessionID <> '' then
        ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := SessionID;

      Exit;
    end;

    if AcceptsSSE(AcceptHeader) then
      HandlePostRequestSSE(RequestInfo, ResponseInfo, RequestBody, SessionID)
    else
      HandlePostRequestJSON(RequestInfo, ResponseInfo, RequestBody, SessionID);

  finally
    JSONRequest.Free;
  end;
end;

procedure TMCPIdHTTPServer.ConfigureSSL;
begin
  // Check if certificate files exist
  if not TFile.Exists(FSettings.SSLCertFile) then
  begin
    TLogger.Error('SSL Certificate file not found: ' + FSettings.SSLCertFile);
    raise Exception.Create('SSL Certificate file not found: ' + FSettings.SSLCertFile);
  end;
  
  if not TFile.Exists(FSettings.SSLKeyFile) then
  begin
    TLogger.Error('SSL Key file not found: ' + FSettings.SSLKeyFile);
    raise Exception.Create('SSL Key file not found: ' + FSettings.SSLKeyFile);
  end;
  
  // Create and configure SSL handler
  {$IFDEF USE_TAURUS_TLS}
  // TaurusTLS with OpenSSL 3.x support
  FSSLHandler := TTaurusTLSServerIOHandler.Create(Self);
  FSSLHandler.DefaultCert.PublicKey := FSettings.SSLCertFile;
  FSSLHandler.DefaultCert.PrivateKey := FSettings.SSLKeyFile;
  {$ELSE}
  // Standard Indy SSL with OpenSSL 1.0.2
  FSSLHandler := TIdServerIOHandlerSSLOpenSSL.Create(Self);
  FSSLHandler.SSLOptions.CertFile := FSettings.SSLCertFile;
  FSSLHandler.SSLOptions.KeyFile := FSettings.SSLKeyFile;
  
  if (FSettings.SSLRootCertFile <> '') and TFile.Exists(FSettings.SSLRootCertFile) then
    FSSLHandler.SSLOptions.RootCertFile := FSettings.SSLRootCertFile;
  
  // Configure SSL options
  FSSLHandler.SSLOptions.Method := sslvTLSv1_2;
  FSSLHandler.SSLOptions.SSLVersions := [sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2];
  FSSLHandler.SSLOptions.Mode := sslmServer;
  {$ENDIF}
  
  // Assign handler to HTTP server
  FHTTPServer.IOHandler := FSSLHandler;
  
  TLogger.Info('SSL configured successfully');
  TLogger.Info('Certificate: ' + FSettings.SSLCertFile);
  TLogger.Info('Private Key: ' + FSettings.SSLKeyFile);
  if FSettings.SSLRootCertFile <> '' then
    TLogger.Info('Root Certificate: ' + FSettings.SSLRootCertFile);
end;

procedure TMCPIdHTTPServer.HandleQuerySSLPort(APort: Word; var VUseSSL: Boolean);
begin
  // Enable SSL for our configured port when SSL is enabled
  VUseSSL := FSettings.SSLEnabled and (APort = FPort);
end;

function TMCPIdHTTPServer.GetNextEventID: string;
begin
  Inc(FEventIDCounter);
  Result := IntToStr(FEventIDCounter);
end;

function TMCPIdHTTPServer.AcceptsSSE(const AcceptHeader: string): Boolean;
begin
  Result := Pos('text/event-stream', AcceptHeader) > 0;
end;

function TMCPIdHTTPServer.IsRequestOnlyNotificationsOrResponses(JSONRequest: TJSONValue): Boolean;
var
  Arr: TJSONArray;
  ErrorValue: TJSONValue;
  I: Integer;
  IdValue: TJSONValue;
  MethodValue: TJSONValue;
  Obj: TJSONObject;
  ResultValue: TJSONValue;
begin
  if JSONRequest is TJSONObject then
  begin
    Obj := JSONRequest as TJSONObject;
    MethodValue := Obj.GetValue('method');
    IdValue := Obj.GetValue('id');
    ResultValue := Obj.GetValue('result');
    ErrorValue := Obj.GetValue('error');

    if Assigned(MethodValue) and not Assigned(IdValue) then
      Exit(True);

    if Assigned(ResultValue) or Assigned(ErrorValue) then
      Exit(True);

    Result := False;
  end
  else if JSONRequest is TJSONArray then
  begin
    Arr := JSONRequest as TJSONArray;
    Result := True;
    for I := 0 to Arr.Count - 1 do
    begin
      if not IsRequestOnlyNotificationsOrResponses(Arr.Items[I]) then
      begin
        Result := False;
        Break;
      end;
    end;
  end
  else
    Result := False;
end;

procedure TMCPIdHTTPServer.HandlePostRequestSSE(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo; const RequestBody: string; const SessionID: string);
var
  EventID: string;
  JSONResponse: string;
  SSEMessage: string;
begin
  TLogger.Info('Handling POST request with SSE stream');

  ResponseInfo.ContentType := 'text/event-stream';
  ResponseInfo.CharSet := 'utf-8';
  ResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-cache';
  ResponseInfo.CustomHeaders.Values['Connection'] := 'keep-alive';
  ResponseInfo.CustomHeaders.Values['X-Accel-Buffering'] := 'no';

  if SessionID <> '' then
    ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := SessionID;

  JSONResponse := FJsonRpcProcessor.ProcessRequest(RequestBody, SessionID);

  // [local change] initialize over SSE must ALSO announce the session in the
  // Mcp-Session-Id header (the JSON path already did): a client strict with
  // the streamable-HTTP spec never reads result.sessionId (field 2026-08-23).
  if (SessionID = '') and (Pos('"sessionId"', JSONResponse) > 0) then
  begin
    var M := TRegEx.Match(JSONResponse, '"sessionId"\s*:\s*"([^"]+)"');
    if M.Success then
    begin
      ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := M.Groups[1].Value;
      RememberSession(M.Groups[1].Value); // [local change]
    end;
  end;

  if JSONResponse <> '' then
  begin
    EventID := GetNextEventID;
    SSEMessage := '';

    if EventID <> '' then
      SSEMessage := SSEMessage + SSE_ID_PREFIX + EventID + #10;

    SSEMessage := SSEMessage + SSE_EVENT_PREFIX + 'message' + #10;
    SSEMessage := SSEMessage + SSE_DATA_PREFIX + JSONResponse + SSE_MESSAGE_TERMINATOR;

    ResponseInfo.ContentText := SSEMessage;
    TLogger.Info('SSE response prepared with event ID: ' + EventID);
  end
  else
  begin
    ResponseInfo.ContentText := '';
  end;

  ResponseInfo.ResponseNo := HTTP_OK;
end;

procedure TMCPIdHTTPServer.HandlePostRequestJSON(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo; const RequestBody: string; const SessionID: string);
var
  ResponseBody: string;
  ResponseJSON: TJSONObject;
  ResultObj: TJSONObject;
  SessionValue: TJSONValue;
begin
  TLogger.Info('Handling POST request with JSON response');

  ResponseBody := FJsonRpcProcessor.ProcessRequest(RequestBody, SessionID);

  if ResponseBody = '' then
  begin
    ResponseInfo.ResponseNo := HTTP_NO_CONTENT;
    Exit;
  end;

  ResponseInfo.ContentType := 'application/json';
  ResponseInfo.CustomHeaders.Values['Connection'] := 'keep-alive';

  if (SessionID = '') and (Pos('"sessionId"', ResponseBody) > 0) then
  begin
    ResponseJSON := TJSONObject.ParseJSONValue(ResponseBody) as TJSONObject;
    try
      ResultObj := ResponseJSON.GetValue('result') as TJSONObject;
      if Assigned(ResultObj) then
      begin
        SessionValue := ResultObj.GetValue('sessionId');
        if Assigned(SessionValue) then
        begin
          ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := SessionValue.Value;
          RememberSession(SessionValue.Value); // [local change]
        end;
      end;
    finally
      ResponseJSON.Free;
    end;
  end
  else if SessionID <> '' then
    ResponseInfo.CustomHeaders.Values['Mcp-Session-Id'] := SessionID;

  ResponseInfo.ContentStream := TStringStream.Create(ResponseBody, TEncoding.UTF8);
  ResponseInfo.FreeContentStream := True;
  ResponseInfo.ResponseNo := HTTP_OK;

  TLogger.Info('Response: ' + ResponseBody);
end;


initialization
  GSessLock := TCriticalSection.Create;  // [local change]
  GSessions := TStringList.Create;

finalization
  GSessions.Free;
  GSessLock.Free;

end.