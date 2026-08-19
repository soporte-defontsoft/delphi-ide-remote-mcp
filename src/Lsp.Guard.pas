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

{ Credentials (env var first, then settings.ini [Security] next to the exe). }
function AuthToken: string;         // DELPHI_MCP_TOKEN         / AuthToken
function ReadOnlyToken: string;     // DELPHI_MCP_READONLY_TOKEN / ReadOnlyToken
function AnonymousReadOnly: Boolean;// DELPHI_MCP_ANON_READONLY  / AnonymousReadOnly=1

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
  mixed and resolved by its "command" argument (query commands pass). }
function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils,
  Lsp.Discovery;

var
  GLoaded: Boolean = False;
  GRoots: TArray<string>;
  GProcessReadOnly: Boolean = False;
  GSecLoaded: Boolean = False;
  GAuthToken: string;
  GReadOnlyToken: string;
  GAnonymousReadOnly: Boolean = False;

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

function WriteDenied(const AWhat: string): string;
begin
  Result := Format('RECHAZADO: acceso de SOLO LECTURA. La operacion "%s" ' +
    'modifica la maquina servidora y esta credencial no lo permite. ' +
    'Disponibles en este modo: leer, buscar, listar, navegar simbolos, ' +
    'diagnosticos, referencias, descargar y git de consulta.', [AWhat]);
end;

function ToolCallDenied(const AToolName: string;
  const AArguments: TJSONObject): string;
var
  Cmd, GitArgs: string;
begin
  Result := '';
  if not (GProcessReadOnly or GRequestReadOnly) then
    Exit;
  // Fully mutating tools: refused outright in read-only mode.
  if MatchText(AToolName, ['delphi_edit', 'delphi_textedit', 'delphi_create',
    'delphi_build', 'delphi_run', 'delphi_package', 'delphi_upload']) then
    Exit(WriteDenied(AToolName));
  // delphi_git is mixed: query commands pass, anything that can change the
  // repo or the remote is refused ("branch"/"tag" only LIST when called
  // without arguments; with arguments they create -> write).
  if SameText(AToolName, 'delphi_git') then
  begin
    Cmd := '';
    GitArgs := '';
    if Assigned(AArguments) then
    begin
      AArguments.TryGetValue<string>('command', Cmd);
      AArguments.TryGetValue<string>('args', GitArgs);
    end;
    if MatchText(Cmd, ['status', 'diff', 'log', 'show']) or
       (MatchText(Cmd, ['branch', 'tag']) and (Trim(GitArgs) = '')) then
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
        if R.Trim <> '' then
        try
          List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(R.Trim)));
        except
          // an unparseable root is ignored, never crashes the server
        end;
      GRoots := List.ToStringArray;
    finally
      List.Free;
    end;
    GLoaded := True;
  end;
  Result := GRoots;
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
  Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(APath));
  if Name = '' then
    Exit;
  if Name.TrimRight([' ', '.']) <> Name then
    Exit(Format('RECHAZADO: el nombre "%s" termina en punto o espacio; ' +
      'Windows los recorta al crear el fichero, asi que el nombre real seria ' +
      'otro ("%s"). Pide el nombre exacto, sin adornos.',
      [Name, Name.TrimRight([' ', '.'])]));
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
  Roots := WorkspaceRoots;
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
  Result := Format('RECHAZADO: "%s" esta FUERA de los workspaces permitidos. ' +
    'Este servidor solo opera dentro de: %s (configurado en DELPHI_MCP_ROOTS ' +
    'o settings.ini [Workspace] Roots).', [APath, string.Join(' | ', Roots)]);
end;

var
  GLibLoaded: Boolean = False;
  GLibRoots: TArray<string>;

{ The read-only library zone: RAD Studio installation + IDE Library Search
  Path directories (installed components), canonicalized. Cached. }
function LibraryRoots: TArray<string>;
var
  Info: TRadStudioInfo;
  List: TStringList;
  Plat, Raw, Item, UserDocs, CommonDocs, Expanded: string;
begin
  if not GLibLoaded then
  begin
    List := TStringList.Create;
    try
      Info := DiscoverRadStudio;
      if Info.Found then
      begin
        List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(Info.RootDir)));
        // Authoritative values (rsvars.bat), NEVER composed by hand: the
        // Documents branding changes between eras. Empty = entry dropped.
        UserDocs := BdsUserDir(Info);
        CommonDocs := BdsCommonDir(Info);
        for Plat in TArray<string>.Create('Win32', 'Win64') do
        begin
          Raw := IdeLibrarySearchPath(Info.Version, Plat);
          for Item in Raw.Split([';']) do
          begin
            Expanded := Item.Trim
              .Replace('$(BDS)', ExcludeTrailingPathDelimiter(Info.RootDir), [rfReplaceAll, rfIgnoreCase])
              .Replace('$(BDSLIB)', ExcludeTrailingPathDelimiter(Info.RootDir) + '\lib', [rfReplaceAll, rfIgnoreCase])
              .Replace('$(Platform)', Plat, [rfReplaceAll, rfIgnoreCase]);
            if UserDocs <> '' then
              Expanded := Expanded.Replace('$(BDSUSERDIR)', UserDocs, [rfReplaceAll, rfIgnoreCase]);
            if CommonDocs <> '' then
              Expanded := Expanded.Replace('$(BDSCOMMONDIR)', CommonDocs, [rfReplaceAll, rfIgnoreCase]);
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
      end;
      GLibRoots := List.ToStringArray;
    finally
      List.Free;
    end;
    GLibLoaded := True;
  end;
  Result := GLibRoots;
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

end.
