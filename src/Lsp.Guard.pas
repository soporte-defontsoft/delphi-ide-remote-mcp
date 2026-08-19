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
       T.StartsWith('--config-env') or T.StartsWith('-c') or       // arbitrary config -> RCE
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
  // Byte-fidelity tools: file CONTENT travels verbatim. Their rejections
  // carry no content, only paths - those are masked like everything else.
  if MatchText(AToolName, ['delphi_read', 'delphi_fetch']) and
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
