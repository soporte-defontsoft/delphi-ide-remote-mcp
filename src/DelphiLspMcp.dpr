program DelphiLspMcp;

{ DelphiLSP MCP Service - console host.

  Modes:
    (default / --stdio)  MCP over stdio - for local MCP clients that spawn
                         the process (Claude Code, Claude Desktop...).
    --http [port]        MCP over Streamable HTTP - the REMOTE mode: this
                         Windows machine (with RAD Studio) serves agents
                         running anywhere, Linux included. Set a Bearer token
                         via the DELPHI_MCP_TOKEN environment variable or
                         settings.ini [Security] AuthToken; expose over
                         VPN/LAN only. A second [Security] ReadOnlyToken
                         grants read-only access (code review agents), and
                         AnonymousReadOnly=1 lets tokenless requests in as
                         read-only.
    --readonly           Whole process read-only, whatever the transport:
                         mutating tools (edit/create/build/run/package and
                         git write commands) are refused.

  Logging goes to stderr; stdout carries only protocol messages (stdio mode).
  MCP plumbing: vendored gdksoftware/delphi-mcp-server (MIT), see vendor/. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  Winapi.Windows,
  MCPServer.Types in '..\vendor\gdk-mcp-server\src\Protocol\MCPServer.Types.pas',
  MCPServer.Serializer in '..\vendor\gdk-mcp-server\src\Protocol\MCPServer.Serializer.pas',
  MCPServer.Schema.Generator in '..\vendor\gdk-mcp-server\src\Protocol\MCPServer.Schema.Generator.pas',
  MCPServer.JsonRpcProcessor in '..\vendor\gdk-mcp-server\src\Protocol\MCPServer.JsonRpcProcessor.pas',
  MCPServer.Logger in '..\vendor\gdk-mcp-server\src\Core\MCPServer.Logger.pas',
  MCPServer.Settings in '..\vendor\gdk-mcp-server\src\Core\MCPServer.Settings.pas',
  MCPServer.Registration in '..\vendor\gdk-mcp-server\src\Core\MCPServer.Registration.pas',
  MCPServer.ManagerRegistry in '..\vendor\gdk-mcp-server\src\Core\MCPServer.ManagerRegistry.pas',
  MCPServer.Tool.Base in '..\vendor\gdk-mcp-server\src\Tools\MCPServer.Tool.Base.pas',
  MCPServer.Resource.Base in '..\vendor\gdk-mcp-server\src\Resources\MCPServer.Resource.Base.pas',
  MCPServer.Resource.Server in '..\vendor\gdk-mcp-server\src\Resources\MCPServer.Resource.Server.pas',
  MCPServer.StdioTransport in '..\vendor\gdk-mcp-server\src\Server\MCPServer.StdioTransport.pas',
  MCPServer.IdHTTPServer in '..\vendor\gdk-mcp-server\src\Server\MCPServer.IdHTTPServer.pas',
  MCPServer.CoreManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.CoreManager.pas',
  MCPServer.ToolsManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.ToolsManager.pas',
  MCPServer.ResourcesManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.ResourcesManager.pas',
  Lsp.Transport.Process in 'Lsp.Transport.Process.pas',
  Lsp.Client in 'Lsp.Client.pas',
  Lsp.Discovery in 'Lsp.Discovery.pas',
  Lsp.Guard in 'Lsp.Guard.pas',
  Lsp.ConfigFabricator in 'Lsp.ConfigFabricator.pas',
  Lsp.Session in 'Lsp.Session.pas',
  Lsp.References in 'Lsp.References.pas',
  Lsp.BuildRunner in 'Lsp.BuildRunner.pas',
  Lsp.Patch in 'Lsp.Patch.pas',
  Lsp.TextEdit in 'Lsp.TextEdit.pas',
  Mcp.Tools.DelphiLsp in 'Mcp.Tools.DelphiLsp.pas',
  Mcp.Tools.DelphiExtra in 'Mcp.Tools.DelphiExtra.pas',
  Mcp.Tools.DelphiPatch in 'Mcp.Tools.DelphiPatch.pas',
  Mcp.Tools.TextEdit in 'Mcp.Tools.TextEdit.pas',
  Mcp.Tools.Workspace in 'Mcp.Tools.Workspace.pas',
  Lsp.Scaffold in 'Lsp.Scaffold.pas',
  Mcp.Tools.Scaffold in 'Mcp.Tools.Scaffold.pas';

var
  Settings: TMCPSettings;
  ManagerRegistry: IMCPManagerRegistry;
  CoreManager: IMCPCapabilityManager;
  ToolsManager: IMCPCapabilityManager;
  ResourcesManager: IMCPCapabilityManager;
  StdioTransport: TMCPStdioTransport;
  HttpServer: TMCPIdHTTPServer;
  ShutdownEvent: TEvent;

function HasFlag(const AFlag: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AFlag) then
      Exit(True);
end;

function FlagValue(const AFlag: string; ADefault: Integer): Integer;
var
  I: Integer;
begin
  Result := ADefault;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), AFlag) and (I < ParamCount) then
      Exit(StrToIntDef(ParamStr(I + 1), ADefault));
end;

function ConsoleCtrl(dwCtrlType: DWORD): BOOL; stdcall;
begin
  Result := True;
  if Assigned(ShutdownEvent) then
    ShutdownEvent.SetEvent;
end;

begin
  // stdout is the MCP channel in stdio mode: every log line goes to stderr.
  TLogger.UseStdErr := True;
  TLogger.LogToConsole := True;
  TLogger.MinLogLevel := TLogLevel.Info;

  IsMultiThread := True;

  try
    Settings := TMCPSettings.Create('', False); // no settings.ini side effects
    try
      Settings.ServerName := 'delphi-lsp-mcp-service';
      Settings.ServerVersion := '0.9.0-beta';

      ManagerRegistry := TMCPManagerRegistry.Create;
      CoreManager := TMCPCoreManager.Create(Settings);
      ToolsManager := TMCPToolsManager.Create;
      ResourcesManager := TMCPResourcesManager.Create;

      ManagerRegistry.RegisterManager(CoreManager);
      ManagerRegistry.RegisterManager(ToolsManager);
      ManagerRegistry.RegisterManager(ResourcesManager);

      // THE single access gate: every tools/call is checked in Lsp.Guard
      // before executing (read-only mode refuses mutating tools there).
      TMCPToolsManager.ToolGate :=
        function(const ToolName: string; const Arguments: TJSONObject): string
        begin
          Result := ToolCallDenied(ToolName, Arguments);
        end;
      if HasFlag('--readonly') then
      begin
        SetProcessReadOnly(True);
        TLogger.Info('Read-only mode (--readonly): mutating tools disabled.');
      end;

      if HasFlag('--http') then
      begin
        TServerStatusResource.Initialize;
        Settings.Port := FlagValue('--http', Settings.Port);
        TLogger.Info('DelphiLSP MCP Service v' + Settings.ServerVersion +
          ' (HTTP :' + Settings.Port.ToString + Settings.Endpoint + ')');
        ShutdownEvent := TEvent.Create(nil, True, False, '');
        try
          SetConsoleCtrlHandler(@ConsoleCtrl, True);
          HttpServer := TMCPIdHTTPServer.Create(nil);
          try
            HttpServer.Settings := Settings;
            HttpServer.ManagerRegistry := ManagerRegistry;
            HttpServer.CoreManager := CoreManager;
            HttpServer.AuthToken := AuthToken;
            HttpServer.ReadOnlyToken := ReadOnlyToken;
            HttpServer.AnonymousReadOnly := AnonymousReadOnly;
            HttpServer.OnAccessLevel :=
              procedure(AReadOnly: Boolean)
              begin
                SetRequestReadOnly(AReadOnly);
              end;
            if (HttpServer.AuthToken = '') and (HttpServer.ReadOnlyToken = '') then
              TLogger.Warning('No Bearer token configured (DELPHI_MCP_TOKEN or ' +
                'settings.ini [Security] AuthToken). Fine on localhost; do NOT ' +
                'expose to the network without one.')
            else
              TLogger.Info('Bearer auth enabled.');
            if HttpServer.ReadOnlyToken <> '' then
              TLogger.Info('Read-only token configured (second credential).');
            if HttpServer.AnonymousReadOnly then
              TLogger.Info('AnonymousReadOnly: tokenless requests get read-only access.');
            HttpServer.Start;
            TLogger.Info('Ready. Ctrl+C to stop.');
            ShutdownEvent.WaitFor(INFINITE);
            HttpServer.Stop;
          finally
            HttpServer.Free;
          end;
        finally
          ShutdownEvent.Free;
        end;
      end
      else
      begin
        TLogger.Info('DelphiLSP MCP Service v' + Settings.ServerVersion + ' (stdio)');
        StdioTransport := TMCPStdioTransport.Create(ManagerRegistry, CoreManager);
        try
          StdioTransport.Run; // returns on stdin EOF (client disconnected)
        finally
          StdioTransport.Free;
        end;
      end;
    finally
      Settings.Free;
    end;
    TLspSession.Shutdown; // stop every DelphiLSP child before exiting
  except
    on E: Exception do
    begin
      TLogger.Error(E);
      ExitCode := 1;
    end;
  end;
end.
