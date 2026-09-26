unit UTrayMain;

{ Tray host: the resident desktop face of the DelphiLSP MCP Service. Starts
  MINIMIZED TO TRAY - the tray icon itself is the "it's running" indicator.
  Hosts the Streamable HTTP transport (same core as the console --http mode);
  double-click or the menu opens the live log window.

  The log on DISK is not this window's: it is the server's (Lsp.LogSink,
  started by TMcpHost in every mode). Until 2026-09-26 it was written here,
  so the service and the terminal had none; the window now only hangs on it
  (SetLogTap) and shows the latest lines. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.StrUtils, System.JSON, System.SyncObjs, System.IOUtils,
  System.IniFiles, System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Clipbrd,
  MCPServer.Types, MCPServer.Settings, MCPServer.Logger,
  MCPServer.ManagerRegistry, MCPServer.CoreManager, MCPServer.ToolsManager,
  MCPServer.ResourcesManager, MCPServer.IdHTTPServer, MCPServer.Resource.Server,
  Lsp.Guard, Lsp.Host, Lsp.Session, Lsp.Texts, Mcp.Vault.Session, Mcp.Vault.Seed,
  Lsp.LogSink;

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
    FLogBuf: TStringList;        // producer side: any thread appends under FLogLock
    FLogLock: TCriticalSection;
    FLogDropped: Integer;        // lines refused because the buffer hit its cap
    FLogTimer: TTimer;
    FLinesPerFile: Integer;
    procedure AddLog(const S: string);
    procedure DrainLog(Sender: TObject);
    procedure WMSysCommand(var Msg: TWMSysCommand); message WM_SYSCOMMAND;
  public
    destructor Destroy; override;
  end;

var
  FormTray: TFormTray;

implementation

{$R *.dfm}

{ Producer side - safe from any thread. The timestamp is taken HERE, so the
  log tells when things happened, not when the window got to paint them. }
procedure TFormTray.AddLog(const S: string);
begin
  FLogLock.Enter;
  try
    if FLogBuf.Count >= LOG_BUF_CAP then
      Inc(FLogDropped)
    else
      FLogBuf.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
  finally
    FLogLock.Leave;
  end;
end;

{ Timer drain on the main thread: buffer -> memo. The window keeps at most
  FLinesPerFile lines and then restarts at zero (David's design 2026-08-21:
  live view stays, memory stays bounded). Nothing is lost doing it: the disk
  is Lsp.LogSink's, for the three hosts. }
procedure TFormTray.DrainLog(Sender: TObject);
var
  Chunk: TStringList;
  Dropped: Integer;
begin
  FLogLock.Enter;
  try
    if (FLogBuf.Count = 0) and (FLogDropped = 0) then
      Exit;
    Chunk := FLogBuf;
    FLogBuf := TStringList.Create;
    Dropped := FLogDropped;
    FLogDropped := 0;
  finally
    FLogLock.Leave;
  end;
  try
    MemoLog.Lines.BeginUpdate;
    try
      MemoLog.Lines.AddStrings(Chunk);
      if Dropped > 0 then
        MemoLog.Lines.Add(Format(
          '... %d lineas de log descartadas (buffer lleno) ...', [Dropped]));
    finally
      MemoLog.Lines.EndUpdate;
    end;
  finally
    Chunk.Free;
  end;
  if MemoLog.Lines.Count >= FLinesPerFile then
    MemoLog.Lines.Clear;
end;

destructor TFormTray.Destroy;
begin
  // The window lets go of the log before its buffer goes (SetLogTap waits
  // for a line in flight). Exits that skip MiExit (Windows logoff/shutdown)
  // still get the disk flushed: Lsp.LogSink does it when the process ends.
  SetLogTap(nil);
  if Assigned(FLogTimer) then
    FLogTimer.Enabled := False;
  FreeAndNil(FLogBuf);
  FreeAndNil(FLogLock);
  inherited;
end;

procedure TFormTray.FormCreate(Sender: TObject);
var
  Form: TFormTray;
begin
  Form := Self;
  FLogLock := TCriticalSection.Create;
  FLogBuf := TStringList.Create;
  FLinesPerFile := LogLinesPerFile; // [Log] has ONE reader: Lsp.LogSink
  FLogTimer := TTimer.Create(Self);
  FLogTimer.Interval := 500;
  FLogTimer.OnTimer := DrainLog;

  TLogger.LogToConsole := False;
  TLogger.MinLogLevel := TLogLevel.Info;
  // Straight into the bounded buffer from whatever thread logs - the old
  // TThread.Queue detour piled up unbounded closures whenever the main
  // thread failed to drain them (measured: a 16-minute backlog). The disk
  // is Lsp.LogSink's; this window only hangs on it.
  SetLogTap(procedure(const ALine: string)
    begin
      Form.AddLog(ALine);
    end);

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
    TLogger.Info(Format('Servidor MCP escuchando en %s (%s v%s)',
      [FUrl, SERVER_NAME, SERVER_VERSION]));
    // The operational facts (jail, vault, credentials, the log) come from the
    // SAME place the terminal and the service read them - one truth, and one
    // way to log it.
    FHost.LogStartupNotes;
    TLogger.Info('Icono en la bandeja = servicio encendido. Doble clic para este log.');
  except
    on E: Exception do
    begin
      TLogger.Error('ERROR arrancando el servidor: ' + E.Message);
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
  TLogger.Info('URL copiada al portapapeles: ' + FUrl);
end;

procedure TFormTray.MiExitClick(Sender: TObject);
begin
  FExiting := True;
  FLogTimer.Enabled := False;
  try
    if Assigned(FServer) then
      FServer.Stop;
  except
  end;
  TLspSession.Shutdown; // stop every DelphiLSP child
  SetLogTap(nil); // the window is closing; the disk keeps listening
  FreeAndNil(FServer);
  // Frees the settings and the managers it built, and puts the tail of the
  // session on disk - the part a post-mortem needs most.
  FreeAndNil(FHost);
  Application.Terminate;
end;

end.
