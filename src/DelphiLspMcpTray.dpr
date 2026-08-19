program DelphiLspMcpTray;

{ Tray host for the DelphiLSP MCP Service: starts minimized to the Windows
  tray (the icon is the "it's running" indicator) and serves MCP over
  Streamable HTTP. Same core and tools as the console host. }

uses
  Vcl.Forms,
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
  Mcp.Tools.DelphiLsp in 'Mcp.Tools.DelphiLsp.pas',
  Mcp.Tools.DelphiExtra in 'Mcp.Tools.DelphiExtra.pas',
  Mcp.Tools.DelphiPatch in 'Mcp.Tools.DelphiPatch.pas',
  Mcp.Tools.Workspace in 'Mcp.Tools.Workspace.pas',
  Lsp.Scaffold in 'Lsp.Scaffold.pas',
  Mcp.Tools.Scaffold in 'Mcp.Tools.Scaffold.pas',
  UTrayMain in 'UTrayMain.pas' {FormTray};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := False;
  Application.ShowMainForm := False; // born iconized: the tray icon IS the UI
  Application.CreateForm(TFormTray, FormTray);
  Application.Run;
end.
