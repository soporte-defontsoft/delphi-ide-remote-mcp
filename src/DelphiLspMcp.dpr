program DelphiLspMcp;

{ DelphiLSP MCP Service - stdio host (Phase 2).

  MCP server over stdio (newline-delimited JSON-RPC, MCP 2025-06-18) exposing
  semantic Delphi tools backed by the official DelphiLSP.exe:
    delphi_symbols, delphi_definition, delphi_hover, delphi_completion.

  Logging goes to stderr; stdout carries only protocol messages.
  MCP plumbing: vendored gdksoftware/delphi-mcp-server (MIT), see vendor/. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
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
  MCPServer.StdioTransport in '..\vendor\gdk-mcp-server\src\Server\MCPServer.StdioTransport.pas',
  MCPServer.CoreManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.CoreManager.pas',
  MCPServer.ToolsManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.ToolsManager.pas',
  MCPServer.ResourcesManager in '..\vendor\gdk-mcp-server\src\Managers\MCPServer.ResourcesManager.pas',
  Lsp.Transport.Process in 'Lsp.Transport.Process.pas',
  Lsp.Client in 'Lsp.Client.pas',
  Lsp.Discovery in 'Lsp.Discovery.pas',
  Lsp.Session in 'Lsp.Session.pas',
  Mcp.Tools.DelphiLsp in 'Mcp.Tools.DelphiLsp.pas';

var
  Settings: TMCPSettings;
  ManagerRegistry: IMCPManagerRegistry;
  CoreManager: IMCPCapabilityManager;
  ToolsManager: IMCPCapabilityManager;
  ResourcesManager: IMCPCapabilityManager;
  StdioTransport: TMCPStdioTransport;

begin
  // stdout is the MCP channel: every log line must go to stderr.
  TLogger.UseStdErr := True;
  TLogger.LogToConsole := True;
  TLogger.MinLogLevel := TLogLevel.Info;

  IsMultiThread := True;

  try
    Settings := TMCPSettings.Create('', False); // no settings.ini side effects
    try
      Settings.ServerName := 'delphi-lsp-mcp-service';
      Settings.ServerVersion := '0.2.0';

      TLogger.Info('DelphiLSP MCP Service v' + Settings.ServerVersion + ' (stdio)');

      ManagerRegistry := TMCPManagerRegistry.Create;
      CoreManager := TMCPCoreManager.Create(Settings);
      ToolsManager := TMCPToolsManager.Create;
      ResourcesManager := TMCPResourcesManager.Create;

      ManagerRegistry.RegisterManager(CoreManager);
      ManagerRegistry.RegisterManager(ToolsManager);
      ManagerRegistry.RegisterManager(ResourcesManager);

      StdioTransport := TMCPStdioTransport.Create(ManagerRegistry, CoreManager);
      try
        StdioTransport.Run; // returns on stdin EOF (client disconnected)
      finally
        StdioTransport.Free;
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
