unit Lsp.Service;

{ The Windows Service host.

  Same shape as the other two hosts and NOT a third copy of the wiring: it asks
  Lsp.Host for a built server exactly like the terminal and the tray do, and
  only adds what is specific to running under the SCM - answering start/stop,
  and logging where a service can log (there is no console and no window).

  Installed and removed with the switches TServiceApplication already gives us:
      DelphiLspMcp.exe /install      (elevated)
      DelphiLspMcp.exe /uninstall    (elevated)
  and started/stopped like any service, by name (see SERVICE_NAME below). }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.SvcMgr,
  MCPServer.IdHTTPServer,
  Lsp.Host;

type
  TDelphiLspMcpService = class(TService)
  private
    FHost: TMcpHost;
    FHttp: TMCPIdHTTPServer;
    procedure LogNotes;
  public
    function GetServiceController: TServiceController; override;
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure ServiceShutdown(Sender: TService);
    procedure ServiceAfterInstall(Sender: TService);
    constructor Create(AOwner: TComponent); override;
  end;

const
  SERVICE_NAME = 'DelphiLspMcp';
  SERVICE_DISPLAY = 'DelphiLSP MCP Service';
  SERVICE_DESCRIPTION = 'Remote control of Delphi over MCP: semantic ' +
    'navigation, safe editing, build and git for AI agents working from ' +
    'any platform.';
  { The switch that tells this exe to run under the SCM. Baked into the
    registered ImagePath by ServiceAfterInstall - see there for why. }
  SERVICE_SWITCH = '/service';

var
  DelphiLspMcpService: TDelphiLspMcpService;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  MCPServer.Logger,
  Lsp.Guard,
  Lsp.Session,
  Lsp.Texts;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  DelphiLspMcpService.Controller(CtrlCode);
end;

function TDelphiLspMcpService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

constructor TDelphiLspMcpService.Create(AOwner: TComponent);
begin
  // Built in code, not from a .dfm: this host has no visual designer surface
  // and the two names are the service's identity - they belong next to the
  // code that registers them, where they cannot silently drift from a form.
  // CreateNew, NOT the inherited Create: TService descends from TDataModule,
  // whose Create calls InitInheritedComponent and therefore REQUIRES a .dfm
  // resource - without one it raises, the service component is never added to
  // the application, and -install then finds nothing to register (measured).
  // CreateNew is the designer-less path and still applies every default.
  inherited CreateNew(AOwner);
  Name := SERVICE_NAME;
  DisplayName := SERVICE_DISPLAY;
  OnStart := ServiceStart;
  OnStop := ServiceStop;
  OnShutdown := ServiceShutdown;
  AfterInstall := ServiceAfterInstall;
end;

procedure TDelphiLspMcpService.ServiceAfterInstall(Sender: TService);
var
  Reg: TRegistry;
  Key, Image: string;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    Key := '\SYSTEM\CurrentControlSet\Services\' + Name;
    if not Reg.OpenKey(Key, False) then
      Exit;
    try
      Reg.WriteString('Description', SERVICE_DESCRIPTION);
      // The SCM launches whatever ImagePath says, and Delphi registers it
      // WITHOUT arguments. Running with no arguments is the terminal mode, so
      // the service would start itself as a console and never answer the SCM:
      // the switch has to be baked into the registered command line here.
      Image := Reg.ReadString('ImagePath');
      if (Image <> '') and (Pos(LowerCase(SERVICE_SWITCH), LowerCase(Image)) = 0) then
        Reg.WriteString('ImagePath', Image + ' ' + SERVICE_SWITCH);
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure TDelphiLspMcpService.LogNotes;
var
  S: string;
begin
  for S in FHost.StartupNotes do
    if S.StartsWith(NOTE_WARNING_PREFIX) then
      TLogger.Warning(S.Substring(Length(NOTE_WARNING_PREFIX)))
    else
      TLogger.Info(S);
end;

procedure TDelphiLspMcpService.ServiceStart(Sender: TService; var Started: Boolean);
begin
  Started := False;
  try
    // Under the SCM the working directory is NOT the exe's folder (it is
    // usually system32), and settings.ini is resolved next to the exe, so make
    // the two agree before anything reads configuration.
    SetCurrentDir(TPath.GetDirectoryName(ParamStr(0)));

    FHost := TMcpHost.Create;
    FHost.Wire;
    TLogger.Info(Format('%s v%s starting as a Windows Service',
      [SERVER_NAME, SERVER_VERSION]));
    LogNotes;

    FHttp := FHost.CreateHttpServer(0); // port from settings.ini / default
    FHttp.Start;
    TLogger.Info(Format('Listening on %s:%d%s',
      [IfThen(FHttp.BindIP = '', 'all interfaces', FHttp.BindIP),
       FHost.Settings.Port, FHost.Settings.Endpoint]));
    Started := True;
  except
    on E: Exception do
    begin
      // A service that dies silently is the worst kind: say why in the event
      // log, where an operator with no console will actually find it.
      LogMessage(Format('%s could not start: %s', [SERVICE_DISPLAY, E.Message]),
        EVENTLOG_ERROR_TYPE);
      TLogger.Error(E);
      Started := False;
    end;
  end;
end;

procedure TDelphiLspMcpService.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
  try
    if Assigned(FHttp) then
    begin
      FHttp.Stop;
      FreeAndNil(FHttp);
    end;
    TLspSession.Shutdown; // stop every DelphiLSP child before exiting
    FreeAndNil(FHost);
  except
    on E: Exception do
      LogMessage(Format('%s stopping: %s', [SERVICE_DISPLAY, E.Message]),
        EVENTLOG_WARNING_TYPE);
  end;
  Stopped := True;
end;

procedure TDelphiLspMcpService.ServiceShutdown(Sender: TService);
var
  Dummy: Boolean;
begin
  // Machine going down: same teardown as a stop, so the DelphiLSP children do
  // not outlive us.
  ServiceStop(Sender, Dummy);
end;

end.
