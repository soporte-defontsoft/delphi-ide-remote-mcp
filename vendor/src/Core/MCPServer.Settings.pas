unit MCPServer.Settings;

interface

type
  // [local change] A holder of values, no longer a reader: the server's own
  // settings reader (Lsp.Settings, the ONE reader of settings.ini) fills the
  // transport fields before the HTTP server starts. This class opened the file
  // with its own TIniFile, composed its path from ParamStr(0) and could create
  // or overwrite it (V47 of 1.23: test_paisaje did not look into vendor).
  TMCPSettings = class
  private
    FPort: Integer;
    FHost: string;
    FServerName: string;
    FServerVersion: string;
    FMachineName: string; // [local change] the machine this server runs on
    FEndpoint: string;
    FCorsEnabled: Boolean;
    FCorsAllowedOrigins: string;
    FSSLEnabled: Boolean;
    FSSLCertFile: string;
    FSSLKeyFile: string;
    FSSLRootCertFile: string;
    function GetProtocol: string;
  public
    property Port: Integer read FPort write FPort;
    property Host: string read FHost write FHost;
    property Protocol: string read GetProtocol;
    property ServerName: string read FServerName write FServerName;
    property ServerVersion: string read FServerVersion write FServerVersion;
    // [local change] reported as serverInfo.host; a runtime fact, never read
    // from or written to the ini
    property MachineName: string read FMachineName write FMachineName;
    property Endpoint: string read FEndpoint write FEndpoint;
    property CorsEnabled: Boolean read FCorsEnabled write FCorsEnabled;
    property CorsAllowedOrigins: string read FCorsAllowedOrigins write FCorsAllowedOrigins;
    property SSLEnabled: Boolean read FSSLEnabled write FSSLEnabled;
    property SSLCertFile: string read FSSLCertFile write FSSLCertFile;
    property SSLKeyFile: string read FSSLKeyFile write FSSLKeyFile;
    property SSLRootCertFile: string read FSSLRootCertFile write FSSLRootCertFile;
  end;

implementation

{ TMCPSettings }

function TMCPSettings.GetProtocol: string;
begin
  if FSSLEnabled then
    Result := 'https'
  else
    Result := 'http';
end;

end.