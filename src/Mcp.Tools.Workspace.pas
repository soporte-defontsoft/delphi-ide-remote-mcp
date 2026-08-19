unit Mcp.Tools.Workspace;

{ Remote-work toolset: delphi_search, delphi_list, delphi_git. Together with
  delphi_read/delphi_edit/delphi_build they give an agent on ANOTHER machine
  (e.g. Linux) full control of the Delphi projects living on this Windows box
  - no file share, no shell access. Paths in results are 1-based lines to
  match delphi_read numbering. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  System.IOUtils,
  System.JSON,
  MCPServer.Tool.Base,
  MCPServer.Types;

type
  TDelphiSearchParams = class
  private
    FRoot: string;
    FQuery: string;
    FMaxResults: Integer;
    FWholeWord: Boolean;
  public
    [SchemaDescription('Directory to search recursively (project root)')]
    property Root: string read FRoot write FRoot;
    [SchemaDescription('Literal text to find (case-insensitive - it is Pascal)')]
    property Query: string read FQuery write FQuery;
    [SchemaDescription('Maximum hits to return (default 100, cap 500)')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
    [SchemaDescription('true = match whole identifiers only (word boundaries)')]
    property WholeWord: Boolean read FWholeWord write FWholeWord;
  end;

  TDelphiListParams = class
  private
    FRoot: string;
    FPattern: string;
    FDirs: Boolean;
  public
    [SchemaDescription('Directory to list recursively')]
    property Root: string read FRoot write FRoot;
    [SchemaDescription('Filename mask, e.g. *.pas (default: Delphi source and project files)')]
    property Pattern: string read FPattern write FPattern;
    [SchemaDescription('true = list SUBDIRECTORIES of root (one level, explorer-style) instead of files')]
    property Dirs: Boolean read FDirs write FDirs;
  end;

  TDelphiProjectsParams = class
  private
    FRoot: string;
    FName: string;
  public
    [SchemaDescription('Directory to search under. Empty = the roots configured in settings.ini [Workspace] Roots (semicolon-separated)')]
    property Root: string read FRoot write FRoot;
    [SchemaDescription('Optional name filter (substring, case-insensitive), e.g. "comunicador"')]
    property Name: string read FName write FName;
  end;

  TDelphiGitParams = class
  private
    FRepo: string;
    FCommand: string;
    FArgs: string;
    FMessage: string;
  public
    [SchemaDescription('Path of the git repository (or any path inside it)')]
    property Repo: string read FRepo write FRepo;
    [SchemaDescription('One of: status | diff | log | show | branch | add | commit')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('Optional extra arguments (paths, --staged, a commit hash...). Shell metacharacters are rejected')]
    property Args: string read FArgs write FArgs;
    [SchemaDescription('commit only: the commit message')]
    property Message: string read FMessage write FMessage;
  end;

  TDelphiSearchTool = class(TMCPToolBase<TDelphiSearchParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiSearchParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiListTool = class(TMCPToolBase<TDelphiListParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiListParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiGitTool = class(TMCPToolBase<TDelphiGitParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiGitParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiProjectsTool = class(TMCPToolBase<TDelphiProjectsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiProjectsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiRunParams = class
  private
    FPath: string;
    FArgs: string;
    FWorkDir: string;
    FTimeoutMs: Integer;
  public
    [SchemaDescription('Absolute path of the .exe to run (must be inside the workspace roots)')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Optional command-line arguments (shell metacharacters rejected)')]
    property Args: string read FArgs write FArgs;
    [SchemaDescription('Optional working directory (default: the exe directory; must be inside the roots)')]
    property WorkDir: string read FWorkDir write FWorkDir;
    [SchemaDescription('Timeout in milliseconds (default 30000, max 300000); the process is killed on expiry')]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
  end;

  TDelphiRunTool = class(TMCPToolBase<TDelphiRunParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiRunParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  Lsp.Client,
  Lsp.References,
  Lsp.BuildRunner,
  Lsp.Guard;

const
  DEFAULT_MASKS: array [0 .. 7] of string =
    ('*.pas', '*.dpr', '*.dpk', '*.inc', '*.dfm', '*.fmx', '*.dproj', '*.groupproj');

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or
    ((C >= '0') and (C <= '9')) or (C = '_');
end;

{ TDelphiSearchTool }

constructor TDelphiSearchTool.Create;
begin
  inherited;
  FName := 'delphi_search';
  FDescription := 'Search Delphi sources recursively for a literal text ' +
    '(case-insensitive), skipping IDE artifacts (__history, Win32/Win64, ' +
    'dcu, .git...). Files are decoded with their real encoding, so accented ' +
    'text matches correctly. Returns path, 1-based line and the line text ' +
    '(same numbering as delphi_read).';
end;

function TDelphiSearchTool.ExecuteWithParams(const Params: TDelphiSearchParams): string;
var
  Return: TJSONObject;
  Hits: TJSONArray;
  Max, I, P, ScanFrom, Total, FilesScanned: Integer;
  F, Text, Q, LineText: string;
  Lines: TArray<string>;
  Mask: string;
  Entry: TJSONObject;
begin
  Result := PathDenied(Params.Root);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Params.Root) then
    Exit('error: directory not found: ' + Params.Root);
  if Params.Query = '' then
    Exit('error: empty query');
  Max := Params.MaxResults;
  if Max <= 0 then Max := 100;
  if Max > 500 then Max := 500;
  Q := Params.Query.ToLower;

  Return := TJSONObject.Create;
  Hits := TJSONArray.Create;
  Total := 0;
  FilesScanned := 0;
  try
    for Mask in DEFAULT_MASKS do
      for F in TDirectory.GetFiles(Params.Root, Mask, TSearchOption.soAllDirectories) do
      begin
        if SkipIdeArtifacts(F) then
          Continue;
        Inc(FilesScanned);
        Text := TLspClient.LoadSourceText(F);
        if not Text.ToLower.Contains(Q) then
          Continue;
        Lines := Text.Replace(#13#10, #10).Split([#10]);
        for I := 0 to High(Lines) do
        begin
          LineText := Lines[I];
          ScanFrom := 1;
          repeat
            P := Pos(Q, LineText.ToLower, ScanFrom);
            if P = 0 then
              Break;
            if (not Params.WholeWord) or
               (((P = 1) or not IsIdentChar(LineText[P - 1])) and
                ((P + Length(Q) > Length(LineText)) or
                 not IsIdentChar(LineText[P + Length(Q)]))) then
            begin
              Inc(Total);
              if Hits.Count < Max then
              begin
                Entry := TJSONObject.Create;
                Hits.Add(Entry);
                Entry.AddPair('path', F);
                Entry.AddPair('line', TJSONNumber.Create(I + 1));
                Entry.AddPair('text', LineText.Trim);
              end;
              Break; // one hit per line is enough
            end;
            ScanFrom := P + Length(Q);
          until False;
        end;
      end;
    Return.AddPair('total', TJSONNumber.Create(Total));
    Return.AddPair('shown', TJSONNumber.Create(Hits.Count));
    Return.AddPair('filesScanned', TJSONNumber.Create(FilesScanned));
    Return.AddPair('hits', Hits);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiListTool }

constructor TDelphiListTool.Create;
begin
  inherited;
  FName := 'delphi_list';
  FDescription := 'List Delphi files under a directory recursively (sources ' +
    'and project files by default, or a custom mask), skipping IDE ' +
    'artifacts. Returns path, size and last-write time. Capped at 500 ' +
    'entries. With dirs=true it lists the SUBDIRECTORIES of root instead ' +
    '(one level, explorer-style) - use that to browse the machine and ' +
    'decide where to create or look for projects.';
end;

function TDelphiListTool.ExecuteWithParams(const Params: TDelphiListParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  F, Mask: string;
  Masks: TArray<string>;
  Entry: TJSONObject;
  Total: Integer;
begin
  Result := PathDenied(Params.Root);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Params.Root) then
    Exit('error: directory not found: ' + Params.Root);

  if Params.Dirs then
  begin
    Return := TJSONObject.Create;
    Arr := TJSONArray.Create;
    Total := 0;
    try
      for F in TDirectory.GetDirectories(Params.Root) do
      begin
        if SkipIdeArtifacts(F + '\') or
           TPath.GetFileName(F).StartsWith('.') or
           TPath.GetFileName(F).StartsWith('__') then
          Continue;
        Inc(Total);
        if Arr.Count < 500 then
          Arr.Add(F);
      end;
      Return.AddPair('total', TJSONNumber.Create(Total));
      Return.AddPair('dirs', Arr);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
    Exit;
  end;
  if Params.Pattern <> '' then
    Masks := Params.Pattern.Split([';'])
  else
  begin
    SetLength(Masks, Length(DEFAULT_MASKS));
    for var I := 0 to High(DEFAULT_MASKS) do
      Masks[I] := DEFAULT_MASKS[I];
  end;

  Return := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Total := 0;
  try
    for Mask in Masks do
      for F in TDirectory.GetFiles(Params.Root, Mask.Trim, TSearchOption.soAllDirectories) do
      begin
        if SkipIdeArtifacts(F) then
          Continue;
        Inc(Total);
        if Arr.Count < 500 then
        begin
          Entry := TJSONObject.Create;
          Arr.Add(Entry);
          Entry.AddPair('path', F);
          Entry.AddPair('size', TJSONNumber.Create(TFile.GetSize(F)));
          Entry.AddPair('modified',
            FormatDateTime('yyyy-mm-dd hh:nn:ss', TFile.GetLastWriteTime(F)));
        end;
      end;
    Return.AddPair('total', TJSONNumber.Create(Total));
    Return.AddPair('shown', TJSONNumber.Create(Arr.Count));
    Return.AddPair('files', Arr);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiGitTool }

constructor TDelphiGitTool.Create;
begin
  inherited;
  FName := 'delphi_git';
  FDescription := 'Whitelisted git operations on a repository of this ' +
    'machine, so a remote agent can inspect and version its work: status, ' +
    'diff, log, show, branch, add, commit (message goes in the "message" ' +
    'parameter). No arbitrary git commands, no shell.';
end;

function TDelphiGitTool.ExecuteWithParams(const Params: TDelphiGitParams): string;
const
  BadChars: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  Cmd, GitArgs, Repo, Output: string;
  ExitCode: Cardinal;
  B: string;
begin
  Repo := Params.Repo;
  if Repo = '' then
    Exit('error: missing repo');
  Result := PathDenied(Repo);
  if Result <> '' then
    Exit;
  if TFile.Exists(Repo) then
    Repo := TPath.GetDirectoryName(Repo);
  if not TDirectory.Exists(Repo) then
    Exit('error: directory not found: ' + Repo);

  for B in BadChars do
    if Params.Args.Contains(B) or Params.Message.Contains(B) then
      Exit('error: shell metacharacters are not allowed in args/message');
  if Params.Args.Contains('--upload-pack') or Params.Args.Contains('--exec') or
     Params.Args.StartsWith('-c') or Params.Args.Contains(' -c ') then
    Exit('error: that git option is not allowed here');

  Cmd := Params.Command.Trim.ToLower;
  if Cmd = 'status' then
    GitArgs := 'status --porcelain=v1 -b ' + Params.Args
  else if Cmd = 'diff' then
    GitArgs := 'diff ' + Params.Args
  else if Cmd = 'log' then
  begin
    GitArgs := 'log --oneline -20 ' + Params.Args;
  end
  else if Cmd = 'show' then
    GitArgs := 'show --stat --format=medium ' + Params.Args
  else if Cmd = 'branch' then
    GitArgs := 'branch -vv ' + Params.Args
  else if Cmd = 'add' then
  begin
    if Params.Args.Trim = '' then
      Exit('error: add needs args (paths, or -A for everything)');
    GitArgs := 'add ' + Params.Args;
  end
  else if Cmd = 'commit' then
  begin
    if Params.Message.Trim = '' then
      Exit('error: commit needs the "message" parameter');
    GitArgs := Format('commit -m "%s" %s',
      [Params.Message.Replace('"', ''''''), Params.Args]);
  end
  else
    Exit('error: unknown command "' + Params.Command +
      '". Allowed: status | diff | log | show | branch | add | commit');

  Output := RunCaptured(Format('git.exe -C "%s" %s', [Repo, GitArgs]), 60000, ExitCode);
  if Length(Output) > 30000 then
    Output := Copy(Output, 1, 30000) + #10'... (truncated)';
  Result := Format('exit=%d'#10'%s', [ExitCode, Output.Trim]);
end;

{ TDelphiProjectsTool }

constructor TDelphiProjectsTool.Create;
begin
  inherited;
  FName := 'delphi_projects';
  FDescription := 'Locate Delphi projects (.dproj/.groupproj) under a ' +
    'directory - or under the workspace roots configured in settings.ini ' +
    '[Workspace] Roots when root is empty. Optional name filter. Use this ' +
    'to answer "open project X" without knowing the disk layout.';
end;

function TDelphiProjectsTool.ExecuteWithParams(const Params: TDelphiProjectsParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  Roots: TArray<string>;
  RootDir, F, Filt, IniPath: string;
  Entry: TJSONObject;
  Total: Integer;
  Ini: TIniFile;
  Mask: string;
begin
  if Params.Root <> '' then
  begin
    Result := PathDenied(Params.Root);
    if Result <> '' then
      Exit;
    Roots := TArray<string>.Create(Params.Root);
  end
  else
  begin
    IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
    if TFile.Exists(IniPath) then
    begin
      Ini := TIniFile.Create(IniPath);
      try
        Roots := Ini.ReadString('Workspace', 'Roots', '').Split([';']);
      finally
        Ini.Free;
      end;
    end;
    if (Length(Roots) = 0) or ((Length(Roots) = 1) and (Roots[0].Trim = '')) then
      Exit('error: no root given and no workspace roots configured. Pass ' +
        '"root", or configure settings.ini next to the server exe: ' +
        '[Workspace] Roots=D:\Proyectos;E:\Otros (semicolon-separated).');
  end;

  Filt := Params.Name.Trim.ToLower;
  Return := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Total := 0;
  try
    for RootDir in Roots do
    begin
      if (RootDir.Trim = '') or not TDirectory.Exists(RootDir.Trim) then
        Continue;
      for Mask in TArray<string>.Create('*.dproj', '*.groupproj') do
        for F in TDirectory.GetFiles(RootDir.Trim, Mask, TSearchOption.soAllDirectories) do
        begin
          if SkipIdeArtifacts(F) then
            Continue;
          if (Filt <> '') and not TPath.GetFileName(F).ToLower.Contains(Filt) then
            Continue;
          Inc(Total);
          if Arr.Count < 300 then
          begin
            Entry := TJSONObject.Create;
            Arr.Add(Entry);
            Entry.AddPair('name', TPath.GetFileNameWithoutExtension(F));
            Entry.AddPair('project', F);
            Entry.AddPair('dir', TPath.GetDirectoryName(F));
            Entry.AddPair('kind', LowerCase(TPath.GetExtension(F)).Substring(1));
          end;
        end;
    end;
    Return.AddPair('total', TJSONNumber.Create(Total));
    Return.AddPair('shown', TJSONNumber.Create(Arr.Count));
    Return.AddPair('projects', Arr);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiRunTool }

constructor TDelphiRunTool.Create;
begin
  inherited;
  FName := 'delphi_run';
  FDescription := 'Run a built executable ON THIS MACHINE (the one that ' +
    'compiled it) and capture its output - the closing step after ' +
    'delphi_build for console apps and test runners. Jailed to the ' +
    'workspace roots, no shell, hard timeout (default 30 s, max 5 min), ' +
    'process killed on expiry. GUI apps will open on the server desktop.';
end;

function TDelphiRunTool.ExecuteWithParams(const Params: TDelphiRunParams): string;
const
  BadChars: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  ExePath, WorkDir, Output, B: string;
  TimeoutMs: Integer;
  ExitCode: Cardinal;
begin
  ExePath := TPath.GetFullPath(Params.Path);
  Result := PathDenied(ExePath);
  if Result <> '' then
    Exit;
  if Length(WorkspaceRoots) = 0 then
    Exit('error: delphi_run requiere workspace roots configurados ' +
      '(DELPHI_MCP_ROOTS o settings.ini [Workspace] Roots) - ejecutar ' +
      'binarios sin jaula no esta permitido.');
  if not TFile.Exists(ExePath) then
    Exit('error: no existe ' + ExePath);
  if not SameText(TPath.GetExtension(ExePath), '.exe') then
    Exit('error: solo ejecutables .exe');
  for B in BadChars do
    if Params.Args.Contains(B) then
      Exit('error: shell metacharacters are not allowed in args');

  WorkDir := Params.WorkDir;
  if WorkDir = '' then
    WorkDir := TPath.GetDirectoryName(ExePath)
  else
  begin
    Result := PathDenied(WorkDir);
    if Result <> '' then
      Exit;
  end;

  TimeoutMs := Params.TimeoutMs;
  if TimeoutMs <= 0 then
    TimeoutMs := 30000;
  if TimeoutMs > 300000 then
    TimeoutMs := 300000;

  Output := RunCapturedIn(Format('"%s" %s', [ExePath, Params.Args]).Trim,
    WorkDir, TimeoutMs, ExitCode);
  if Length(Output) > 30000 then
    Output := Copy(Output, 1, 30000) + #10'... (truncated)';
  Result := Format('exit=%d'#10'%s', [ExitCode, Output.TrimRight]);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_search',
    function: IMCPTool begin Result := TDelphiSearchTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_projects',
    function: IMCPTool begin Result := TDelphiProjectsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_run',
    function: IMCPTool begin Result := TDelphiRunTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_list',
    function: IMCPTool begin Result := TDelphiListTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_git',
    function: IMCPTool begin Result := TDelphiGitTool.Create; end);

end.
