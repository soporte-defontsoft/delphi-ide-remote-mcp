unit UTrayMain;

{ Tray host: the resident desktop face of the DelphiLSP MCP Service. Starts
  MINIMIZED TO TRAY - the tray icon itself is the "it's running" indicator.
  Hosts the Streamable HTTP transport (same core as the console --http mode);
  double-click or the menu opens the live log window. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Clipbrd,
  MCPServer.Types, MCPServer.Settings, MCPServer.Logger,
  MCPServer.ManagerRegistry, MCPServer.CoreManager, MCPServer.ToolsManager,
  MCPServer.ResourcesManager, MCPServer.IdHTTPServer, MCPServer.Resource.Server,
  Lsp.Guard, Lsp.Session;

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
    FSettings: TMCPSettings;
    FServer: TMCPIdHTTPServer;
    FRegistry: IMCPManagerRegistry;
    FCore, FTools, FResources: IMCPCapabilityManager;
    FUrl: string;
    FExiting: Boolean;
    procedure AddLog(const S: string);
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

  TServerStatusResource.Initialize;
  FSettings := TMCPSettings.Create('', False);
  FSettings.ServerName := 'delphi-lsp-mcp-service';
  FSettings.ServerVersion := '0.9.1-beta';

  FRegistry := TMCPManagerRegistry.Create;
  FCore := TMCPCoreManager.Create(FSettings);
  FTools := TMCPToolsManager.Create;
  FResources := TMCPResourcesManager.Create;
  FRegistry.RegisterManager(FCore);
  FRegistry.RegisterManager(FTools);
  FRegistry.RegisterManager(FResources);

  // THE single access gate: every tools/call is checked in Lsp.Guard.
  TMCPToolsManager.ToolGate :=
    function(const ToolName: string; const Arguments: TJSONObject): string
    begin
      Result := ToolCallDenied(ToolName, Arguments);
    end;

  FServer := TMCPIdHTTPServer.Create(Self);
  FServer.Settings := FSettings;
  FServer.ManagerRegistry := FRegistry;
  FServer.CoreManager := FCore;
  FServer.AuthToken := Lsp.Guard.AuthToken;
  FServer.ReadOnlyToken := Lsp.Guard.ReadOnlyToken;
  FServer.AnonymousReadOnly := Lsp.Guard.AnonymousReadOnly;
  FServer.OnAccessLevel :=
    procedure(AReadOnly: Boolean)
    begin
      SetRequestReadOnly(AReadOnly);
    end;

  FUrl := Format('http://%s:%d%s',
    [FSettings.Host, FSettings.Port, FSettings.Endpoint]);
  Caption := 'DelphiLSP MCP Service - ' + FUrl;
  TrayIcon.Hint := 'DelphiLSP MCP Service' + sLineBreak + FUrl;

  try
    FServer.Start;
    AddLog('Servidor MCP escuchando en ' + FUrl);
    if (FServer.AuthToken = '') and (FServer.ReadOnlyToken = '') then
      AddLog('AVISO: sin token Bearer (DELPHI_MCP_TOKEN o settings.ini ' +
        '[Security] AuthToken). Bien en localhost; NO exponer a la red asi.')
    else
      AddLog('Autenticacion Bearer activada.');
    if FServer.ReadOnlyToken <> '' then
      AddLog('Segunda credencial de SOLO LECTURA configurada (ReadOnlyToken).');
    if FServer.AnonymousReadOnly then
      AddLog('AnonymousReadOnly: peticiones sin token entran en solo lectura.');
    AddLog('Icono en la bandeja = servicio encendido. Doble clic para este log.');
  except
    on E: Exception do
    begin
      AddLog('ERROR arrancando el servidor: ' + E.Message);
      TrayIcon.Hint := 'DelphiLSP MCP Service - ERROR: ' + E.Message;
    end;
  end;
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
  FSettings.Free;
  Application.Terminate;
end;

end.
