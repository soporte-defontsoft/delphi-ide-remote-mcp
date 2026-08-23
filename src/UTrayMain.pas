unit UTrayMain;

{ Tray host: the resident desktop face of the DelphiLSP MCP Service. Starts
  MINIMIZED TO TRAY - the tray icon itself is the "it's running" indicator.
  Hosts the Streamable HTTP transport (same core as the console --http mode);
  double-click or the menu opens the live log window. }

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
    FLogBuf: TStringList;        // producer side: any thread appends under FLogLock
    FLogLock: TCriticalSection;
    FLogDropped: Integer;        // lines refused because the buffer hit its cap
    FLogTimer: TTimer;
    FLogDir: string;
    FLinesPerFile: Integer;
    FMaxLogFiles: Integer;
    procedure AddLog(const S: string);
    procedure DrainLog(Sender: TObject);
    procedure FlushMemoToDisk;
    procedure WMSysCommand(var Msg: TWMSysCommand); message WM_SYSCOMMAND;
  public
    destructor Destroy; override;
  end;

var
  FormTray: TFormTray;

implementation

{$R *.dfm}

const
  // Upper bound for the producer buffer. The old path queued one closure per
  // line via TThread.Queue with NO cap - field 2026-08-21: 16 minutes of
  // requests piled up unseen and landed in the memo in one burst, all stamped
  // with the drain time. Lines beyond the cap are counted, not stored.
  LOG_BUF_CAP = 5000;
  LIVE_LOG_NAME = 'actual.log'; // live tail of the block not yet persisted

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

{ Timer drain on the main thread: buffer -> memo, and every FLinesPerFile
  lines the memo persists to disk and restarts at zero (David's design
  2026-08-21: live view stays, memory stays bounded, nothing is lost). }
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
    // The live tail on disk: what the memo holds and has not persisted yet.
    // The memo only reaches a file every FLinesPerFile lines, so a server
    // stopped from outside (Stop-Process) lost hours of log (2026-08-23:
    // nothing after 11:54 for a 14:00 diagnosis). Appended per drain,
    // removed when the block is persisted - never a second copy.
    try
      TDirectory.CreateDirectory(FLogDir);
      TFile.AppendAllText(TPath.Combine(FLogDir, LIVE_LOG_NAME),
        Chunk.Text, TEncoding.UTF8);
    except
      // a disk problem must never take the tray down with it
    end;
  finally
    Chunk.Free;
  end;
  if MemoLog.Lines.Count >= FLinesPerFile then
    FlushMemoToDisk;
end;

procedure TFormTray.FlushMemoToDisk;
var
  Stamp, FileName: string;
  N: Integer;
  Files: TArray<string>;
begin
  if MemoLog.Lines.Count = 0 then
    Exit;
  try
    TDirectory.CreateDirectory(FLogDir);
    Stamp := FormatDateTime('yyyymmdd"-"hhnnss', Now);
    FileName := TPath.Combine(FLogDir, Stamp + '.log');
    N := 2;
    while TFile.Exists(FileName) do
    begin
      FileName := TPath.Combine(FLogDir, Stamp + '-' + IntToStr(N) + '.log');
      Inc(N);
    end;
    MemoLog.Lines.SaveToFile(FileName, TEncoding.UTF8);
    MemoLog.Lines.Clear;
    if TFile.Exists(TPath.Combine(FLogDir, LIVE_LOG_NAME)) then
      TFile.Delete(TPath.Combine(FLogDir, LIVE_LOG_NAME)); // now inside the block file
    // Names are timestamps, so lexicographic order IS chronological order.
    Files := TDirectory.GetFiles(FLogDir, '*.log');
    TArray.Sort<string>(Files);
    for var I := 0 to High(Files) - FMaxLogFiles do
      TFile.Delete(Files[I]);
  except
    // A disk problem must never take the tray down with it.
    on E: Exception do
      MemoLog.Lines.Add('AVISO: no se pudo persistir el log: ' + E.Message);
  end;
end;

destructor TFormTray.Destroy;
begin
  // Exits that skip MiExit (Windows logoff/shutdown) still get their flush.
  // After MiExit both calls find everything empty and do nothing.
  TLogger.OnLogMessage := nil;
  if Assigned(FLogTimer) then
    FLogTimer.Enabled := False;
  if Assigned(FLogBuf) and Assigned(FLogLock) then
  begin
    DrainLog(nil);
    FlushMemoToDisk;
  end;
  FreeAndNil(FLogBuf);
  FreeAndNil(FLogLock);
  inherited;
end;

procedure TFormTray.FormCreate(Sender: TObject);
var
  Form: TFormTray;
  Ini: TIniFile;
begin
  Form := Self;
  FLogLock := TCriticalSection.Create;
  FLogBuf := TStringList.Create;
  FLogDir := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'logs');
  Ini := TIniFile.Create(
    TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini'));
  try
    FLinesPerFile := Ini.ReadInteger('Log', 'LinesPerFile', 2000);
    FMaxLogFiles := Ini.ReadInteger('Log', 'MaxFiles', 10);
  finally
    Ini.Free;
  end;
  if FLinesPerFile < 100 then
    FLinesPerFile := 100;
  if FMaxLogFiles < 1 then
    FMaxLogFiles := 1;
  FLogTimer := TTimer.Create(Self);
  FLogTimer.Interval := 500;
  FLogTimer.OnTimer := DrainLog;

  TLogger.LogToConsole := False;
  TLogger.MinLogLevel := TLogLevel.Info;
  // Straight into the bounded buffer from whatever thread logs - the old
  // TThread.Queue detour piled up unbounded closures whenever the main
  // thread failed to drain them (measured: a 16-minute backlog).
  TLogger.OnLogMessage := procedure(const Message: string)
    begin
      Form.AddLog(Message);
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
    AddLog(Format('Log persistente: bloques de %d lineas a %s (max %d ficheros; ' +
      '[Log] LinesPerFile/MaxFiles en settings.ini).',
      [FLinesPerFile, FLogDir, FMaxLogFiles]));
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
  FLogTimer.Enabled := False;
  try
    if Assigned(FServer) then
      FServer.Stop;
  except
  end;
  TLspSession.Shutdown; // stop every DelphiLSP child
  TLogger.OnLogMessage := nil;
  // Whatever the shutdown just logged plus the partial block in the memo
  // goes to disk - the tail of a session is exactly the part a post-mortem
  // needs most.
  DrainLog(nil);
  FlushMemoToDisk;
  FreeAndNil(FServer);
  FreeAndNil(FHost); // frees the settings and the managers it built
  Application.Terminate;
end;

end.
