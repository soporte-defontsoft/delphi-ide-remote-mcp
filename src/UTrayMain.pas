unit UTrayMain;

{ Tray host: the resident desktop face of the DelphiLSP MCP Service. Starts
  MINIMIZED TO TRAY - the tray icon itself is the "it's running" indicator.
  Hosts the Streamable HTTP transport (same core as the console --http mode);
  double-click or the menu opens the live log window. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.StrUtils, System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Clipbrd,
  MCPServer.Types, MCPServer.Settings, MCPServer.Logger,
  MCPServer.ManagerRegistry, MCPServer.CoreManager, MCPServer.ToolsManager,
  MCPServer.ResourcesManager, MCPServer.IdHTTPServer, MCPServer.Resource.Server,
  Lsp.Guard, Lsp.Host, Lsp.Session, Lsp.Texts, Mcp.Vault.Session, Mcp.Vault.Seed;

type
  TFormTray = class(TForm)
    MemoLog: TMemo;
    TrayIcon: TTrayIcon;
    PopupMenu: TPopupMenu;
    MiShow: TMenuItem;
    MiCopy: TMenuItem;
    MiSep: TMenuItem;
    MiExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure MiShowClick(Sender: TObject);
    procedure MiCopyClick(Sender: TObject);
    procedure MiExitClick(Sender: TObject);
  private
    FHost: TMcpHost;
    FServer: TMCPIdHTTPServer;
    FUrl: string;
    FExiting: Boolean;
    procedure AddLog(const S: string);
    procedure WMSysCommand(var Msg: TWMSysCommand); message WM_SYSCOMMAND;
  public
  end;

var
  FormTray: TFormTray;

implementation

{$R *.dfm}

procedure TFormTray.AddLog(const S: string);
begin
  if MemoLog.Lines.Count > 2000 then
    MemoLog.Lines.Clear;
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

procedure TFormTray.FormCreate(Sender: TObject);
var
  Form: TFormTray;
begin
  Form := Self;
  TLogger.LogToConsole := False;
  TLogger.MinLogLevel := TLogLevel.Info;
  TLogger.OnLogMessage := procedure(const Message: string)
    begin
      TThread.Queue(nil, procedure
        begin
          Form.AddLog(Message);
        end);
    end;

  // The wiring is NOT written out here: the terminal, the service and this
  // tray must build exactly the same server, and a policy added to one copy
  // and forgotten in another is a hole that exists on one host only. Lsp.Host
  // builds it once for all three.
  FHost := TMcpHost.Create;
  FHost.Wire;
  FServer := FHost.CreateHttpServer(0);

  FUrl := Format('http://%s:%d%s',
    [FHost.Settings.Host, FHost.Settings.Port, FHost.Settings.Endpoint]);
  Caption := 'DelphiLSP MCP Service v' + SERVER_VERSION + ' - ' + FUrl;
  TrayIcon.Hint := 'DelphiLSP MCP Service v' + SERVER_VERSION + sLineBreak + FUrl;
  // A TTrayIcon with an empty Icon draws NOTHING - not even a default one, so
  // the notification area just showed a blank slot. The application icon is
  // the project's own (Icon_MainIcon), so the tray and the taskbar agree.
  TrayIcon.Icon.Assign(Application.Icon);

  try
    FServer.Start;
    AddLog(Format('Servidor MCP escuchando en %s (%s v%s)',
      [FUrl, SERVER_NAME, SERVER_VERSION]));
    // The operational facts (jail, vault, credentials) come from the SAME
    // place the terminal and the service read them - one truth, three sinks.
    for var Note in FHost.StartupNotes do
      AddLog(Note);
    AddLog('Icono en la bandeja = servicio encendido. Doble clic para este log.');
  except
    on E: Exception do
    begin
      AddLog('ERROR arrancando el servidor: ' + E.Message);
      TrayIcon.Hint := 'DelphiLSP MCP Service - ERROR: ' + E.Message;
    end;
  end;
end;

{ Minimize = back to the tray. With MainFormOnTaskbar=False a VCL minimize
  targets the hidden Application window, so the form neither minimized nor
  returned to the tray (field report 2026-08-21: the window just stayed put).
  The tray IS this app's minimized state - same policy as close-to-tray in
  FormCloseQuery. }
procedure TFormTray.WMSysCommand(var Msg: TWMSysCommand);
begin
  if (Msg.CmdType and $FFF0) = SC_MINIMIZE then
    Hide
  else
    inherited;
end;

procedure TFormTray.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Closing the window hides it; the service lives in the tray. Real exit
  // only through the tray menu.
  if not FExiting then
  begin
    CanClose := False;
    Hide;
  end
  else
    CanClose := True;
end;

procedure TFormTray.MiShowClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
end;

procedure TFormTray.MiCopyClick(Sender: TObject);
begin
  Clipboard.AsText := FUrl;
  AddLog('URL copiada al portapapeles: ' + FUrl);
end;

procedure TFormTray.MiExitClick(Sender: TObject);
begin
  FExiting := True;
  TLogger.OnLogMessage := nil;
  try
    if Assigned(FServer) then
      FServer.Stop;
  except
  end;
  TLspSession.Shutdown; // stop every DelphiLSP child
  FreeAndNil(FServer);
  FreeAndNil(FHost); // frees the settings and the managers it built
  Application.Terminate;
end;

end.
