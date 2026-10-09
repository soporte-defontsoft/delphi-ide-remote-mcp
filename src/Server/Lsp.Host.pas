unit Lsp.Host;

{ Everything the HOSTS share.

  There are three ways to run this server - a Windows Service, a terminal
  (stdio for a local client, or --http), and the tray app - and all three need
  exactly the same thing built in exactly the same way: the manager registry,
  the SINGLE access gate, its outbound twin, and the knowledge vault.

  It used to be written out inline in DelphiLspMcp.dpr AND again in UTrayMain,
  which is how a policy drifts: a filter added to one host and forgotten in the
  other is a hole that only exists on one of them. A third copy for the service
  was not an option (project convention 1-bis: do not duplicate helpers), so
  the wiring lives here once and every host asks for it.

  This unit deliberately knows NOTHING about consoles, windows or the SCM: it
  builds the server, the host decides how to run and how to report.

  The log ON DISK is not "how to report" but part of the server, so it starts
  here too (Lsp.LogSink, from Create): until 2026-09-26 only the tray's window
  wrote it, and the service - production since 2026-09-20 - ran six days
  without one line. A host adds its own sink on top (stderr, the tray's
  window); it never has to remember the disk. }

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Settings,
  MCPServer.ManagerRegistry,
  MCPServer.CoreManager,
  MCPServer.IdHTTPServer;

type
  { Owns the objects a running server needs. Free it and everything it built
    goes with it, so a host never has to remember the teardown order. }
  TMcpHost = class
  private
    FSettings: TMCPSettings;
    FRegistry: TMCPManagerRegistry;
    // TMCPManagerRegistry is a TInterfacedObject: the HTTP server (and the
    // stdio transport) hold it as IMCPManagerRegistry, so the LAST interface
    // release destroys it. This field pins the host's own counted reference;
    // see Destroy for the double-free this replaces.
    FRegistryIntf: IMCPManagerRegistry;
    FCore: TMCPCoreManager;
    // lo que paso con [Server] DelphiVersion al arrancar ('' = ya estaba)
    FNotaDelphiIni: string;
  public
    constructor Create;
    destructor Destroy; override;

    { Builds the managers, wires the gate and the outbound filter, and declares
      the vault when one is configured. Call once, before starting anything.
      FIRST it makes sure this server has its Delphi: without it, it raises
      and the host reports it and does not start (a Delphi MCP server needs
      its Delphi); and with no [Server] DelphiVersion in settings.ini it
      writes the one it chose there. }
    procedure Wire;

    { Creates the HTTP server already configured: credentials, bind address,
      the fail-safe localhost bind when nothing is configured, and the
      per-request access-level hook. The caller owns the result. }
    function CreateHttpServer(APort: Integer): TMCPIdHTTPServer;

    { The operational facts a host should tell its operator at startup, in
      order: the write jail, the vault, the credential situation, and where
      the log goes. Each
      entry is prefixed 'AVISO: ' when it is a warning, so a host can colour
      or log it accordingly without re-deciding what is important. }
    function StartupNotes: TArray<string>;

    { Logs StartupNotes, warnings as warnings. The same for every host: it
      was written out in the terminal and again in the service, and the tray
      had a third way of its own. }
    procedure LogStartupNotes;

    property Settings: TMCPSettings read FSettings;
    property Registry: TMCPManagerRegistry read FRegistry;
    property Core: TMCPCoreManager read FCore;
  end;

const
  NOTE_WARNING_PREFIX = 'AVISO: ';

implementation

uses
  Winapi.Windows, // SetErrorMode
  System.StrUtils,
  MCPServer.Logger,
  MCPServer.ToolsManager,
  MCPServer.ResourcesManager,
  MCPServer.Resource.Server,
  Lsp.Guard,
  Lsp.Texts,
  Lsp.Files,
  Lsp.InlineImages, // ClearAttachedImages / WrapWithAttachedImages
  Mcp.Tools.Messages,
  Mcp.Vault.Session,
  Mcp.Vault.Seed,
  Lsp.LogSink,
  Mcp.Tools.Workspace, // NombreDeMaquina: the one reader of the host name
  Lsp.DesignerMetaGen, // CalientaTablasDelDisenador
  Lsp.Discovery, // NotasDeArranqueDelphi
  Lsp.Settings,
  Lsp.Mascara;

constructor TMcpHost.Create;
begin
  inherited;
  // A "there is no disk in the drive" dialog is never for a server: nobody
  // is there to answer it. NOT the crash dialog's bit, SEM_NOGPFAULTERRORBOX:
  // with it Windows writes nothing to the event log when the process dies
  // (measured 2026-09-30: a crashing program leaves an Application Error
  // event without the bit and nothing with it), and a server that dies has
  // to leave that trace. What this server LAUNCHES gets both bits, set on
  // each child (Lsp.ErrorMode.NoErrorDialogs): a child inherits its parent's
  // mode (measured: a server launched by a parent in mode 0 was in mode 0,
  // and so was its engine), and this process's does not stay put under
  // parallel load.
  SetErrorMode(GetErrorMode or SEM_FAILCRITICALERRORS);
  StartLogSink; // first: everything from here on reaches the disk
  // no settings.ini side effects; y EL nombre del fichero, el de Lsp.Settings: el
  // vendor componia el suyo (revision del 6-oct-2026)
  FSettings := TMCPSettings.Create(SettingsIniPath, False);
  FSettings.ServerName := SERVER_NAME;
  FSettings.ServerVersion := SERVER_VERSION;
  // serverInfo.host: two servers of the same name and version (a 13.1 and a
  // 13.2, same token) answered with nothing that told them apart (2026-09-28)
  FSettings.MachineName := NombreDeMaquina;
end;

destructor TMcpHost.Destroy;
begin
  TLogger.Info(MsgFmt(SL_SYS_PARADO_FMT, [SERVER_NAME, SERVER_VERSION]));
  // The manual FRegistry.Free that lived here double-freed the registry the
  // moment any interface reference existed: freeing the HTTP server released
  // the last IMCPManagerRegistry ref, the registry destroyed itself, and this
  // destructor then freed dead memory - the "Invalid pointer operation" every
  // tray close showed (field 2026-08-21; present for many versions, in all
  // three host modes). Reference counting owns the registry now: dropping the
  // pinned ref below destroys it here when no server outlives the host, or
  // lets the last holder do it otherwise. The managers inside it were always
  // interface-owned by its list - nothing else changes.
  FRegistry := nil;
  FRegistryIntf := nil;
  FSettings.Free;
  FlushLogSink; // the tail of a session is what a post-mortem needs most
  inherited;
end;

{ Attach the mailbox notice WITHOUT breaking the answer. Half the tools reply
  with a JSON object, and gluing a line of prose behind it made that JSON
  unparseable for as long as a message sat waiting - a client doing the
  obvious json.loads() got a syntax error out of nowhere, and only while
  there was mail (measured 2026-08-25). Inside the object it goes, as one
  more field; only a prose answer gets it appended. }
function WithMailboxNote(const AText, ANote: string): string;
begin
  // EL helper de Lsp.Guard; la nota del buzon ya trae su propio salto
  Result := ConNota(AText, 'mailbox', ANote, '');
end;

procedure TMcpHost.Wire;
var
  ErrorIni: string;
begin
  // Antes que nada, que su settings.ini se lea entero: con el BOM de UTF-8
  // delante de la primera seccion, Windows la pierde (Port, BindIP...), y en
  // UTF-16 big endian no ve ninguna
  ExigeSettingsIniLegible;
  // Lo primero: el Delphi de este servidor. Sin el no hay servidor - es un
  // servidor MCP para Delphi (David, 5-oct-2026) -, y la excepcion la cuenta
  // cada host: el log y un codigo de salida, el visor de eventos, la bandeja.
  ExigeElDelphiDelServidor;
  // Sin [Server] DelphiVersion en su settings.ini, la que eligio (la mas
  // nueva) se escribe alli: desde ahi manda la clave, y no cambia sola el
  // dia que se instale otro Delphi. Si no puede, sigue y lo dice.
  FNotaDelphiIni := '';
  if ServerDelphiVersion = '' then
    if FijaDelphiVersionEnElIni(DiscoverRadStudio.Version, ErrorIni) then
      FNotaDelphiIni := MsgFmt(SL_DISC_ESCRITA_FMT, [DiscoverRadStudio.Version])
    else if ErrorIni <> '' then
      FNotaDelphiIni := MsgFmt(SL_DISC_NO_ESCRITA_FMT, [DiscoverRadStudio.Version, ErrorIni]);
  // Vaciar los temporales del servidor. Lo que quede ahi es de una
  // ejecucion anterior, y un temporal que nadie recoge son 56 MB dentro de
  // dos dias (medido 2026-09-21, cuando vivian en el %TEMP% de la maquina).
  // Declarar la carpeta borrable no vale de nada si no la borra nadie.
  PurgeServerTemp;
  // Las tablas del disenador del Delphi de este servidor, sacadas de su
  // fuente: en un hilo, y solo si falta (la primera vez tras instalar,
  // actualizar o tocar las rutas del IDE). Nadie espera a esto.
  CalientaTablasDelDisenador;
  FRegistry := TMCPManagerRegistry.Create;
  FRegistryIntf := FRegistry; // pin: from here, reference counting owns it
  FCore := TMCPCoreManager.Create(FSettings);
  FRegistry.RegisterManager(FCore);
  FRegistry.RegisterManager(TMCPToolsManager.Create);
  FRegistry.RegisterManager(TMCPResourcesManager.Create);

  // Knowledge vault (optional): tell the model it exists and how to start
  // (MCP "instructions"), and expose the invocable /vault prompt. Both are
  // inert - and the prompts capability is not advertised - with no vault.
  TMCPCoreManager.Instructions :=
    function: string
    begin
      Result := VaultInstructions;
    end;
  if VaultConfiguredAnywhere then
  begin
    TMCPCoreManager.DeclarePrompts := True;
    FRegistry.RegisterManager(TMCPPromptsManager.Create);
  end;

  // THE single access gate: every tools/call is checked in Lsp.Guard before
  // executing (read-only mode refuses mutating tools there).
  TMCPToolsManager.ToolGate :=
    function(const ToolName: string; const Arguments: TJSONObject): string
    begin
      ClearAttachedImages; // nada de una llamada anterior en este hilo
      OlvidaSalidaHecha;   // ...ni lo que otra dejo dicho al filtro de salida
      Result := ToolCallDenied(ToolName, Arguments);
      // Una negativa de la PUERTA nunca trae contenido de un fichero: sale
      // enmascarada entera aqui, antes del filtro de salida, que en las tools
      // de eco deja tal cual las lineas 'N|texto'. Una ruta con un salto y
      // '1|' dentro sacaba las raices del servidor sin enmascarar (revision
      // del 4-oct-2026; medido tambien en la 1.12.1)
      if Result <> '' then
        Result := MaskDriveText('', Result);
    end;
  // Outbound twin of the gate: server drive letters leave as virtual units
  // (D:\x -> srvd:\x) in every textual result.
  // Surface trim, not a permission: a [Tools] profile or allowlist hides
  // tools from tools/list so a small model is not buried under 41 schemas
  // (hermes, release audit 2026-08-26, P1.4). Hidden tools stay callable.
  TMCPToolsManager.ListFilter :=
    function(const ToolName: string): Boolean
    begin
      Result := ToolHiddenFromList(ToolName);
    end;
  // Lo que tools/list anuncia de cada tool ademas de su esquema:
  // annotations.readOnlyHint (MCP) y _meta.access / readOnlyCommands, desde
  // LA tabla de accesos de la puerta (Lsp.Guard.AnunciaAcceso). TOOLS.md
  // saca de ahi su linea Access y test_http_auth mide el anuncio contra la
  // puerta (28-sep-2026).
  TMCPToolsManager.ToolDecorator :=
    procedure(const ToolName: string; const Entry: TJSONObject)
    begin
      AnunciaAcceso(ToolName, Entry);
    end;
  TMCPToolsManager.ResultFilter :=
    function(const ToolName, AText: string): string
    begin
      Result := MaskDriveText(ToolName, AText);
      // the operator's mailbox: there is no push in MCP clients, so every
      // tool answer carries the notice while a message waits.
      if ToolName <> 'delphi_messages' then
        Result := WithMailboxNote(Result, PendingMessagesNote);
    end;
  // ...y lo que una tool adjunto (una captura, Lsp.InlineImages): viaja EN
  // la misma respuesta. Un punto para todas las tools, junto al filtro.
  TMCPToolsManager.ResultWrapper :=
    function(const ToolName, AText: string): TJSONArray
    begin
      Result := WrapWithAttachedImages(AText);
    end;
end;

function TMcpHost.StartupNotes: TArray<string>;
var
  Notes: TArray<string>;

  procedure Add(const S: string);
  begin
    if S <> '' then
      Notes := Notes + [S];
  end;

  // las notas de otra unidad: las que empiezan por SL_MARCA_AVISO son avisos
  procedure AddNota(const S: string);
  begin
    if S.StartsWith(SL_MARCA_AVISO) then
      Add(NOTE_WARNING_PREFIX + S)
    else
      Add(S);
  end;

var
  JailWarn: Boolean;
  Jail: string;
begin
  Jail := WorkspaceJailSummary(JailWarn);
  if JailWarn then
    Add(NOTE_WARNING_PREFIX + Jail)
  else
    Add(Jail);
  Add(VaultSeedNote);
  if VaultConfigured then
    Add(MsgFmt(SL_SYS_KNOWLEDGE_VAULT_FMT,
      [VaultPath, IfThen(VaultWritable, 'read-write', 'read-only')]));
  // v0.91: authentication is workspaces or nothing. The old note lied the
  // moment tokens moved into [Workspace.*] sections (measured 2026-09-11:
  // production fully migrated and the log still cried "no token").
  // Un settings.ini que esta y no se pudo leer: nada de el en vigor, y dicho
  // (David, 9-oct-2026: cerrado y nunca callado)
  if IniSinLeer <> '' then
    Add(NOTE_WARNING_PREFIX + IniSinLeer);
  if WorkspaceTokensConfigured then
    Add(MsgText(SL_SYS_BEARER_AUTH_ENABLED))
  else
  begin
    Add(NOTE_WARNING_PREFIX + MsgFmt(SL_SYS_NO_CREDENTIALS_FMT, [MsgText(SF_TOKEN_NEEDED)]));
    // CreateHttpServer's fail-safe, said here with ITS condition: the .dpr
    // used to say it, only in terminal mode, whenever the interface was
    // 127.0.0.1 - credentials or not - and pointing at [Security], a
    // section retired in v0.98 (found by test_round24 on 2026-09-26).
    if Lsp.Settings.BindIP = '' then
      Add(NOTE_WARNING_PREFIX + MsgText(SL_SYS_NO_BINDIP_LOCALHOST_ONLY));
  end;
  // One auth mechanism: workspaces. A legacy env pair shows up
  // here as the "default" workspace; misconfigured sections stop vanishing
  // silently (operator decision 2026-09-11).
  for var WsNote in WorkspaceStartupNotes do
    AddNota(WsNote);
  // Las instalaciones de Delphi de la maquina, cada una con la clave que el
  // operador copiaria a su settings.ini, y cual usa este servidor (David,
  // 5-oct-2026: un servidor es un Delphi).
  for var DelphiNote in NotasDeArranqueDelphi do
    AddNota(DelphiNote);
  AddNota(FNotaDelphiIni);
  Add(LogSinkNote);
  Result := Notes;
end;

procedure TMcpHost.LogStartupNotes;
var
  S: string;
begin
  for S in StartupNotes do
    if S.StartsWith(NOTE_WARNING_PREFIX) then
      TLogger.Warning(S.Substring(Length(NOTE_WARNING_PREFIX)))
    else
      TLogger.Info(S);
end;

function TMcpHost.CreateHttpServer(APort: Integer): TMCPIdHTTPServer;
begin
  TServerStatusResource.Initialize;
  if APort > 0 then
    FSettings.Port := APort;
  Result := TMCPIdHTTPServer.Create(nil);
  Result.Settings := FSettings;
  Result.ManagerRegistry := FRegistry;
  Result.CoreManager := FCore;
  Result.AuthToken := Lsp.Settings.AuthToken;
  Result.ReadOnlyToken := Lsp.Settings.ReadOnlyToken;
  Result.AnonymousReadOnly := False; // v0.98: sin acceso anonimo
  Result.BindIP := Lsp.Settings.BindIP;
  // Fail SAFE: with NO credential of any kind configured, never listen on
  // every interface - bind to localhost so an unconfigured server is not
  // silently open to the whole network. Remote access requires a workspace
  // token; a legacy-only env pair neither authenticates nor earns a wide
  // bind, and el anonimo ya no existe (v0.98).
  if (not WorkspaceTokensConfigured) and (Result.BindIP = '') then
    Result.BindIP := '127.0.0.1';
  Result.OnAccessLevel :=
    procedure(AReadOnly: Boolean)
    begin
      SetRequestReadOnly(AReadOnly);
    end;
  // Full bearer authorization lives in ONE place (Lsp.Settings, AuthorizeBearer): the
  // [Workspace.*] tokens - the secret
  // decides the jail (operator decision 2026-08-28, v0.88). Worker threads
  // are reused, so BOTH per-thread flags are set on every request.
  Result.OnAuthorize :=
    function(const AAuth: string): Boolean
    var
      RO: Boolean;
      WsIx: Integer;
    begin
      Result := AuthorizeBearer(AAuth, RO, WsIx);
      if Result then
      begin
        SetRequestReadOnly(RO);
        SetRequestWorkspace(WsIx);
      end;
    end;
  // Direct download route on the same host, behind the same gate: big
  // binaries travel as HTTP bytes, never as base64 through a model's context
  // (field 2026-08-21: the 72 MB PAServer installer through delphi_fetch).
  Result.FilesRoute := FILES_ROUTE;
  Result.OnFileRequest := ServeFile;
  GFilesServed := True; // delphi_fetch may now hand out the link
end;

end.
