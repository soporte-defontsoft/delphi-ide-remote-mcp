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
  builds the server, the host decides how to run and how to report. }

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
  public
    constructor Create;
    destructor Destroy; override;

    { Builds the managers, wires the gate and the outbound filter, and declares
      the vault when one is configured. Call once, before starting anything. }
    procedure Wire;

    { Creates the HTTP server already configured: credentials, bind address,
      the fail-safe localhost bind when nothing is configured, and the
      per-request access-level hook. The caller owns the result. }
    function CreateHttpServer(APort: Integer): TMCPIdHTTPServer;

    { The operational facts a host should tell its operator at startup, in
      order: the write jail, the vault, and the credential situation. Each
      entry is prefixed 'AVISO: ' when it is a warning, so a host can colour
      or log it accordingly without re-deciding what is important. }
    function StartupNotes: TArray<string>;

    property Settings: TMCPSettings read FSettings;
    property Registry: TMCPManagerRegistry read FRegistry;
    property Core: TMCPCoreManager read FCore;
  end;

const
  NOTE_WARNING_PREFIX = 'AVISO: ';

implementation

uses
  System.StrUtils,
  MCPServer.ToolsManager,
  MCPServer.ResourcesManager,
  MCPServer.Resource.Server,
  Lsp.Guard,
  Lsp.Texts,
  Lsp.Files,
  Mcp.Tools.Messages,
  Mcp.Vault.Session,
  Mcp.Vault.Seed;

constructor TMcpHost.Create;
begin
  inherited;
  FSettings := TMCPSettings.Create('', False); // no settings.ini side effects
  FSettings.ServerName := SERVER_NAME;
  FSettings.ServerVersion := SERVER_VERSION;
end;

destructor TMcpHost.Destroy;
begin
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
  inherited;
end;

{ Attach the mailbox notice WITHOUT breaking the answer. Half the tools reply
  with a JSON object, and gluing a line of prose behind it made that JSON
  unparseable for as long as a message sat waiting - a client doing the
  obvious json.loads() got a syntax error out of nowhere, and only while
  there was mail (measured 2026-08-25). Inside the object it goes, as one
  more field; only a prose answer gets it appended. }
function WithMailboxNote(const AText, ANote: string): string;
var
  Obj: TJSONObject;
  T: string;
begin
  Result := AText;
  if ANote = '' then
    Exit;
  T := AText.TrimRight;
  if T.StartsWith('{') and T.EndsWith('}') then
  begin
    Obj := TJSONObject.ParseJSONValue(T) as TJSONObject;
    if Assigned(Obj) then
      try
        Obj.AddPair('mailbox', ANote.Trim);
        Exit(Obj.ToJSON);
      finally
        Obj.Free;
      end;
  end;
  Result := AText + ANote;
end;

procedure TMcpHost.Wire;
begin
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
  if VaultConfigured then
  begin
    TMCPCoreManager.DeclarePrompts := True;
    FRegistry.RegisterManager(TMCPPromptsManager.Create);
  end;

  // THE single access gate: every tools/call is checked in Lsp.Guard before
  // executing (read-only mode refuses mutating tools there).
  TMCPToolsManager.ToolGate :=
    function(const ToolName: string; const Arguments: TJSONObject): string
    begin
      Result := ToolCallDenied(ToolName, Arguments);
    end;
  // Outbound twin of the gate: server drive letters leave as virtual units
  // (D:\x -> srvd:\x) in every textual result.
  TMCPToolsManager.ResultFilter :=
    function(const ToolName, AText: string): string
    begin
      Result := MaskDriveText(ToolName, AText);
      // the operator's mailbox: there is no push in MCP clients, so every
      // tool answer carries the notice while a message waits.
      if ToolName <> 'delphi_messages' then
        Result := WithMailboxNote(Result, PendingMessagesNote);
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
    Add(Format('Knowledge vault: %s (%s)',
      [VaultPath, IfThen(VaultWritable, 'read-write', 'read-only')]));
  if (AuthToken = '') and (ReadOnlyToken = '') then
    Add(NOTE_WARNING_PREFIX + 'No Bearer token configured (DELPHI_MCP_TOKEN ' +
      'or settings.ini [Security] AuthToken). Fine on localhost; do NOT ' +
      'expose to the network without one.')
  else
    Add('Bearer auth enabled.');
  if ReadOnlyToken <> '' then
    Add('Read-only token configured (second credential).');
  if AnonymousReadOnly then
    Add('AnonymousReadOnly: tokenless requests get read-only access.');
  Result := Notes;
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
  Result.AuthToken := Lsp.Guard.AuthToken;
  Result.ReadOnlyToken := Lsp.Guard.ReadOnlyToken;
  Result.AnonymousReadOnly := Lsp.Guard.AnonymousReadOnly;
  Result.BindIP := Lsp.Guard.BindIP;
  // Fail SAFE: with NO credential of any kind configured, never listen on
  // every interface - bind to localhost so an unconfigured server is not
  // silently open to the whole network. Remote access requires a token (or an
  // explicit AnonymousReadOnly opt-in).
  if (Result.AuthToken = '') and (Result.ReadOnlyToken = '') and
     (not Result.AnonymousReadOnly) and (Result.BindIP = '') then
    Result.BindIP := '127.0.0.1';
  Result.OnAccessLevel :=
    procedure(AReadOnly: Boolean)
    begin
      SetRequestReadOnly(AReadOnly);
    end;
  // Direct download route on the same host, behind the same gate: big
  // binaries travel as HTTP bytes, never as base64 through a model's context
  // (field 2026-08-21: the 72 MB PAServer installer through delphi_fetch).
  Result.FilesRoute := FILES_ROUTE;
  Result.OnFileRequest := ServeFile;
  GFilesServed := True; // delphi_fetch may now hand out the link
end;

end.
