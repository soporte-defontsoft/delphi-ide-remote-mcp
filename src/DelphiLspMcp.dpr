program DelphiLspMcp;

{ DelphiLSP MCP Service - ONE project, one executable, three ways to run it.

    (no switch)      TERMINAL. MCP over stdio, for a local client that spawns
                     this process. Add --http [port] for Streamable HTTP - the
                     REMOTE mode: this Windows machine (with RAD Studio) serves
                     agents running anywhere, Linux included.
    /service         WINDOWS SERVICE (what the SCM launches - the switch is
                     baked into the registered ImagePath at install time).
                     Install and remove it with:
                         DelphiLspMcp.exe /install     (elevated)
                         DelphiLspMcp.exe /uninstall   (elevated)
    /gui             TRAY APP. Starts iconized; double-click for the live log.

  Extra switches, any mode:
    --readonly       Whole process read-only, whatever the transport: mutating
                     tools (edit/create/build/run/package and git write
                     commands) are refused.

  Credentials and the workspace jail come from settings.ini next to the exe or
  from the environment - see settings.example.ini.

  WHY ONE PROJECT: the three hosts must expose exactly the same tools, and a
  tool is only registered if its unit is LINKED. Two projects meant two uses
  clauses to keep in sync by hand, and a unit added to one and forgotten in the
  other silently gave that host fewer tools. One project cannot drift. The
  wiring they share (managers, the single gate, its outbound filter, the vault)
  lives in Lsp.Host - never copied per host.

  WHY the console apptype below, even though two of the three modes have no
  console: the stdio transport reads and writes the Pascal Input/Output text
  files, and the RTL only binds those in a console application. The tray mode
  releases the console at startup instead; a service never gets one.

  Logging goes to stderr; stdout carries only protocol messages (stdio mode).
  MCP plumbing: vendored gdksoftware/delphi-mcp-server (MIT), see vendor/. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.SyncObjs,
  System.StrUtils,
  System.JSON,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.SvcMgr,
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
  // ONE list now: every mode links the same units, so no host can expose
  // fewer tools than another (that drift is why the two projects merged).
  Lsp.Texts in 'Lsp.Texts.pas',
  Lsp.Transport.Process in 'Lsp.Transport.Process.pas',
  Lsp.Client in 'Lsp.Client.pas',
  Lsp.Discovery in 'Lsp.Discovery.pas',
  Lsp.Guard in 'Lsp.Guard.pas',
  Lsp.Dproj in 'Lsp.Dproj.pas',
  Lsp.ConfigFabricator in 'Lsp.ConfigFabricator.pas',
  Lsp.Session in 'Lsp.Session.pas',
  Lsp.References in 'Lsp.References.pas',
  Lsp.Sandbox in 'Lsp.Sandbox.pas',
  Lsp.BuildRunner in 'Lsp.BuildRunner.pas',
  Lsp.Patch in 'Lsp.Patch.pas',
  Lsp.TextEdit in 'Lsp.TextEdit.pas',
  Mcp.Tools.DelphiLsp in 'Mcp.Tools.DelphiLsp.pas',
  Mcp.Tools.DelphiExtra in 'Mcp.Tools.DelphiExtra.pas',
  Mcp.Tools.Config in 'Mcp.Tools.Config.pas',
  Mcp.Tools.PAServer in 'Mcp.Tools.PAServer.pas',
  Mcp.Tools.Adb in 'Mcp.Tools.Adb.pas',
  Mcp.Tools.Components in 'Mcp.Tools.Components.pas',
  Mcp.Tools.FileOps in 'Mcp.Tools.FileOps.pas',
  Mcp.Tools.DelphiPatch in 'Mcp.Tools.DelphiPatch.pas',
  Mcp.Tools.TextEdit in 'Mcp.Tools.TextEdit.pas',
  Mcp.Tools.Workspace in 'Mcp.Tools.Workspace.pas',
  Mcp.Tools.Report in 'Mcp.Tools.Report.pas',
  Mcp.Vault.Seed in 'Mcp.Vault.Seed.pas',
  Mcp.Vault.Session in 'Mcp.Vault.Session.pas',
  Mcp.Tools.Vault in 'Mcp.Tools.Vault.pas',
  Lsp.Scaffold in 'Lsp.Scaffold.pas',
  Mcp.Tools.Scaffold in 'Mcp.Tools.Scaffold.pas',
  Lsp.Host in 'Lsp.Host.pas',
  Lsp.Files in 'Lsp.Files.pas',
  Lsp.ProjectUnits in 'Lsp.ProjectUnits.pas',
  Lsp.Styles in 'Lsp.Styles.pas',
  Mcp.Tools.Styles in 'Mcp.Tools.Styles.pas',
  Mcp.Tools.Messages in 'Mcp.Tools.Messages.pas',
  Mcp.Tools.Changeset in 'Mcp.Tools.Changeset.pas',
  Mcp.Tools.Designer in 'Mcp.Tools.Designer.pas',
  Mcp.Tools.Rename in 'Mcp.Tools.Rename.pas',
  Mcp.Tools.Test in 'Mcp.Tools.Test.pas',
  Lsp.TestRunner in 'Lsp.TestRunner.pas',
  Lsp.Rename in 'Lsp.Rename.pas',
  Lsp.Changeset in 'Lsp.Changeset.pas',
  Lsp.Service in 'Lsp.Service.pas',
  UTrayMain in 'UTrayMain.pas' {FormTray};

{$R *.res}

var
  Host: TMcpHost;
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

{ A mode switch is accepted as /x, -x or --x: the operator types it by hand and
  the three spellings are all reasonable. }
function HasMode(const AName: string): Boolean;
begin
  Result := HasFlag('/' + AName) or HasFlag('-' + AName) or
            HasFlag('--' + AName);
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

{ Says out loud what the operator most needs to know, in the order they need
  it. Shared by every mode; only the sink differs. }
procedure LogNotes(AHost: TMcpHost);
var
  S: string;
begin
  for S in AHost.StartupNotes do
    if S.StartsWith(NOTE_WARNING_PREFIX) then
      TLogger.Warning(S.Substring(Length(NOTE_WARNING_PREFIX)))
    else
      TLogger.Info(S);
end;

procedure RunTerminal;
begin
  // stdout is the MCP channel in stdio mode: every log line goes to stderr.
  TLogger.UseStdErr := True;
  TLogger.LogToConsole := True;
  TLogger.MinLogLevel := TLogLevel.Info;
  IsMultiThread := True;

  Host := TMcpHost.Create;
  try
    Host.Wire;
    if HasFlag('--readonly') then
    begin
      SetProcessReadOnly(True);
      TLogger.Info('Read-only mode (--readonly): mutating tools disabled.');
    end;
    LogNotes(Host);

    if HasFlag('--http') then
    begin
      TLogger.Info('DelphiLSP MCP Service v' + Host.Settings.ServerVersion +
        ' (HTTP :' + FlagValue('--http', Host.Settings.Port).ToString +
        Host.Settings.Endpoint + ')');
      ShutdownEvent := TEvent.Create(nil, True, False, '');
      try
        SetConsoleCtrlHandler(@ConsoleCtrl, True);
        HttpServer := Host.CreateHttpServer(FlagValue('--http', 0));
        try
          if HttpServer.BindIP = '127.0.0.1' then
            TLogger.Warning('No credential configured: binding to localhost ' +
              'only. Set [Security] AuthToken (and [Server] BindIP) to expose ' +
              'to the network.');
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
      TLogger.Info('DelphiLSP MCP Service v' + Host.Settings.ServerVersion +
        ' (stdio)');
      StdioTransport := TMCPStdioTransport.Create(Host.Registry, Host.Core);
      try
        StdioTransport.Run; // returns on stdin EOF (client disconnected)
      finally
        StdioTransport.Free;
      end;
    end;
  finally
    Host.Free;
  end;
  TLspSession.Shutdown; // stop every DelphiLSP child before exiting
end;

procedure RunTray;
begin
  // A console application that is about to become a window: let the console
  // go, or the tray app drags an empty black box around for its whole life.
  // (The apptype is CONSOLE because the stdio transport needs it - see the
  // header of this file.)
  FreeConsole;
  TLogger.LogToConsole := False;
  IsMultiThread := True;
  Vcl.Forms.Application.Initialize;
  Vcl.Forms.Application.MainFormOnTaskbar := False;
  Vcl.Forms.Application.ShowMainForm := False; // the tray icon IS the UI
  Vcl.Forms.Application.CreateForm(TFormTray, FormTray);
  Vcl.Forms.Application.Run;
end;

procedure RunService;
begin
  // No console and no window: the log sink is the event log plus whatever the
  // logger is configured to write. Never the console - under the SCM there is
  // none, and writing to it raises an I/O error that would kill the start.
  TLogger.LogToConsole := False;
  IsMultiThread := True;
  if not Vcl.SvcMgr.Application.DelayInitialize or
     Vcl.SvcMgr.Application.Installing then
    Vcl.SvcMgr.Application.Initialize;
  Vcl.SvcMgr.Application.CreateForm(TDelphiLspMcpService, DelphiLspMcpService);
  Vcl.SvcMgr.Application.Run;
end;

begin
  try
    // /install and /uninstall are TServiceApplication's own switches, so they
    // have to reach the service branch too - otherwise installing the service
    // would just start a terminal.
    if HasMode('service') or HasMode('install') or HasMode('uninstall') then
      RunService
    else if HasMode('gui') or HasMode('tray') then
      RunTray
    else
      RunTerminal;
  except
    on E: Exception do
    begin
      TLogger.Error(E);
      ExitCode := 1;
    end;
  end;
end.
