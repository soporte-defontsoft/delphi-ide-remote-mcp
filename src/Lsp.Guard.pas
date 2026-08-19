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
  System.JSON;

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

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  System.Generics.Collections,
  Lsp.Discovery,
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
  GAllowBuildScripts: Boolean = False; // build scripts OFF unless explicitly opted in

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

procedure LoadSecurity;
var
  IniPath: string;
  Ini: TIniFile;
begin
  if GSecLoaded then
    Exit;
  GAuthToken := GetEnvironmentVariable('DELPHI_MCP_TOKEN');
  GReadOnlyToken := GetEnvironmentVariable('DELPHI_MCP_READONLY_TOKEN');
  GAnonymousReadOnly := GetEnvironmentVariable('DELPHI_MCP_ANON_READONLY') = '1';
  GAllowRun := GetEnvironmentVariable('DELPHI_MCP_ALLOW_RUN') = '1';
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
      if not GAllowBuildScripts then
        GAllowBuildScripts := Ini.ReadBool('Security', 'AllowBuildScripts', False);
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

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Cmd, GitArgs, GitMsg: string;
begin
  // Normalization first, unconditionally: virtual drive units in the
  // arguments become real server paths before any check or any tool.
  ExpandVirtualDrives(AArguments);
  Result := '';
  // Universal git-argument filter (BOTH access levels): a dangerous option
  // would let even a read-write client escape the jail. The single place git
  // freeform args are vetted.
  if SameText(AToolName, 'delphi_git') and Assigned(AArguments) then
  begin
    GitArgs := '';
    AArguments.TryGetValue<string>('args', GitArgs);
    Result := GitArgDenied(GitArgs);
    if Result <> '' then
      Exit;
  end;
  // Universal execution block (BOTH access levels): this is a compile-only
  // development server; running a program here is off by design. Refused for
  // every credential unless the operator explicitly opted in (AllowRun).
  if SameText(AToolName, 'delphi_run') and not AllowRun then
    Exit(SR_RUN_DISABLED);
  if not (GProcessReadOnly or GRequestReadOnly) then
    Exit;
  // Fully mutating tools: refused outright in read-only mode.
  if MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
    'delphi_build', 'delphi_run', 'delphi_package', 'delphi_upload',
    'delphi_delete', 'delphi_move',
    // The knowledge vault: reading is fine read-only, writing never is.
    'vault_append', 'vault_create', 'vault_patch']) then
    Exit(WriteDenied(AToolName));
  // delphi_config is mixed: "view" reads, "add-platform" writes the .dproj.
  if SameText(AToolName, 'delphi_config') then
  begin
    Cmd := '';
    if Assigned(AArguments) then
      AArguments.TryGetValue<string>('command', Cmd);
    if (Trim(Cmd) = '') or SameText(Trim(Cmd), 'view') then
      Exit;
    Exit(WriteDenied('delphi_config ' + Cmd));
  end;
  // delphi_git is mixed: query commands pass, anything that can change the
  // repo or the remote is refused ("branch"/"tag" only LIST when called
  // without arguments; with arguments they create -> write).
  if SameText(AToolName, 'delphi_git') then
  begin
    Cmd := '';
    GitArgs := '';
    GitMsg := '';
    if Assigned(AArguments) then
    begin
      AArguments.TryGetValue<string>('command', Cmd);
      AArguments.TryGetValue<string>('args', GitArgs);
      AArguments.TryGetValue<string>('message', GitMsg);
    end;
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
  Name, Rest: string;
begin
  Result := '';
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

function LibraryRoots: TArray<string>;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  List, Vars: TStringList;
  Plat, Raw, Item, Expanded, UserDocs, CommonDocs: string;
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
          // The IDE's own macro table is authoritative: it carries
          // $(BDSCatalogRepositoryAllUsers), where the GetIt packages live
          // (FmxLinux, Android SDKs, PAServer installers). Without it those
          // paths were silently dropped - measured 2026-08-19.
          IdeEnvironmentVars(Info.Version, Vars);
          // Values that are NOT in that key (authoritative from rsvars.bat /
          // the install itself), added without overwriting the IDE's own.
          if Vars.Values['BDS'] = '' then
            Vars.Values['BDS'] := ExcludeTrailingPathDelimiter(Info.RootDir);
          if Vars.Values['BDSLIB'] = '' then
            Vars.Values['BDSLIB'] := ExcludeTrailingPathDelimiter(Info.RootDir) + '\lib';
          UserDocs := BdsUserDir(Info);
          if (UserDocs <> '') and (Vars.Values['BDSUSERDIR'] = '') then
            Vars.Values['BDSUSERDIR'] := UserDocs;
          CommonDocs := BdsCommonDir(Info);
          if (CommonDocs <> '') and (Vars.Values['BDSCOMMONDIR'] = '') then
            Vars.Values['BDSCOMMONDIR'] := CommonDocs;
          // Per-user catalog repository: sibling of the common one, under the
          // user's own documents root (the IDE exposes only the AllUsers one).
          if (Vars.Values['BDSCatalogRepository'] = '') and (UserDocs <> '') then
            Vars.Values['BDSCatalogRepository'] :=
              IncludeTrailingPathDelimiter(UserDocs) + 'CatalogRepository';

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
  for R in LibraryRoots do
    if StartsText(R, Full) then
      Exit('');
end;

// ---------------------------------------------------------------------------
// Virtual drive units (srvd:, srvc:, ...)
// ---------------------------------------------------------------------------

var
  GDrvLoaded: Boolean = False;
  GDrvLetters: string; // uppercase letters of every served drive, e.g. 'DC'

{ The drives that can legitimately appear in tool output: those hosting the
  workspace roots and the library zone (RAD Studio + components). Cached. }
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
    GDrvLoaded := True;
  end;
  Result := GDrvLetters;
end;

{ 'srvd:\x' / 'srvd:/x' / bare 'srvd:' -> 'D:\x' ... Whole-value prefix match
  only; anything else comes back untouched (real paths keep working). }
function ExpandDriveValue(const AValue: string): string;
begin
  Result := AValue;
  if (Length(AValue) >= 5) and StartsText('srv', AValue) and
     CharInSet(AValue[4], ['A'..'Z', 'a'..'z']) and (AValue[5] = ':') then
    if (Length(AValue) = 5) or CharInSet(AValue[6], ['\', '/']) then
      Result := UpCase(AValue[4]) + Copy(AValue, 5, MaxInt);
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
  if MatchText(AToolName, ['delphi_read', 'vault_read', 'vault_search']) and
     not (AText.StartsWith('RECHAZADO') or AText.StartsWith('error')) then
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
      if (Pos(UpCase(C), Letters) > 0) then
      begin
        if I = 1 then
          PrevC := #0
        else
          PrevC := AText[I - 1];
        // A drive prefix only starts where the previous char is not a
        // letter/digit (keeps git's "HEAD:" and words intact).
        if not CharInSet(PrevC, ['A'..'Z', 'a'..'z', '0'..'9']) then
        begin
          // form A - plain path: <letter>:<separator> (D:\ or D:/)
          if (I + 2 <= L) and (AText[I + 1] = ':') and
             CharInSet(AText[I + 2], ['\', '/']) then
          begin
            Sb.Append('srv').Append(Char(Ord(UpCase(C)) + 32)).Append(':');
            Inc(I, 2);
            Continue;
          end;
          // form B - percent-encoded colon in a file URI: <letter>%3A/ ...
          // (DelphiLSP answers with file:///D%3A/... - measured, R3-1).
          if (I + 4 <= L) and (AText[I + 1] = '%') and (AText[I + 2] = '3') and
             ((AText[I + 3] = 'A') or (AText[I + 3] = 'a')) and (AText[I + 4] = '/') then
          begin
            Sb.Append('srv').Append(Char(Ord(UpCase(C)) + 32))
              .Append(AText[I + 1]).Append(AText[I + 2]).Append(AText[I + 3]);
            Inc(I, 4);
            Continue;
          end;
        end;
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
