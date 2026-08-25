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
  System.IOUtils,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.Hash,
  System.NetEncoding,
  System.Zip,
  System.Generics.Collections,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;   // SchemaDescription texts live there, and attributes are interface-level

type
  TDelphiSearchParams = class
  private
    FRoot: string;
    FQuery: string;
    FMaxResults: Integer;
    FWholeWord: Boolean;
    FPattern: string;
  public
    [SchemaDescription('Directory to search recursively (project root) - or ONE file (a .dproj, .dpr, .inc, .xml...) to search inside it in a single call')]
    [Required]
    property Root: string read FRoot write FRoot;
    [SchemaDescription('Literal text to find (case-insensitive - it is Pascal)')]
    [Required]
    property Query: string read FQuery write FQuery;
    [SchemaDescription('Maximum hits to return (default 100, cap 500)')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
    [SchemaDescription('true = match whole identifiers only (word boundaries)')]
    property WholeWord: Boolean read FWholeWord write FWholeWord;
    [SchemaDescription('Optional file mask to search instead of the Delphi set, e.g. *.style, *.ini, *.md, *.rc (one mask)')]
    property Pattern: string read FPattern write FPattern;
  end;

  TDelphiListParams = class
  private
    FRoot: string;
    FPattern: string;
    FDirs: Boolean;
    FIncludeTrash: Boolean;
  public
    [SchemaDescription('Directory to list recursively')]
    [Required]
    property Root: string read FRoot write FRoot;
    [SchemaDescription('Filename mask, e.g. *.pas (default: Delphi source and project files)')]
    property Pattern: string read FPattern write FPattern;
    [SchemaDescription('true = list SUBDIRECTORIES of root (one level, explorer-style) instead of files')]
    property Dirs: Boolean read FDirs write FDirs;
    [SchemaDescription('true = also show the recoverable trash (__delphi-patch, where delphi_delete moves files) so you can find and restore a deleted file with delphi_move. Default false (trash hidden).')]
    property IncludeTrash: Boolean read FIncludeTrash write FIncludeTrash;
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
    FCreate: Boolean;
    FMessage: string;
  public
    [SchemaDescription('Path of the git repository (or any path inside it). For clone: the DESTINATION directory (created if needed, must be inside the workspace roots)')]
    [Required]
    property Repo: string read FRepo write FRepo;
    [SchemaDescription('One of: status | diff | log | show | branch | switch | merge | stash | add | commit | init | push | tag | config | clone | pull | fetch. switch: args=<branch> (create=true for a new one). merge: args=<branch>, always --ff-only (a merge needing a commit is refused, not left half-done). stash: args=push|pop|list (never drop). config: args=user.name|user.email + value in message. clone: URL in message, destination in repo')]
    [Required]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('Optional extra arguments (paths, --staged, a commit hash...). Shell metacharacters are rejected')]
    property Args: string read FArgs write FArgs;
    [SchemaDescription('switch: true = create the branch and move to it (git switch -c). Ignored by every other command')]
    property Create: Boolean read FCreate write FCreate;
    [SchemaDescription('commit: the commit message. tag: makes the tag annotated. config: the value. clone: the repository URL')]
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

  TDelphiInstallsParams = class
  end;

  TDelphiInstallsTool = class(TMCPToolBase<TDelphiInstallsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiInstallsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiWorkspaceParams = class
  end;

  TDelphiWorkspaceTool = class(TMCPToolBase<TDelphiWorkspaceParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiWorkspaceParams): string; override;
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
    [Required]
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

  TDelphiFetchParams = class
  private
    FPath: string;
    FOffset: Integer;
    FMaxBytes: Integer;
  public
    [SchemaDescription('Absolute path of the file to download from the server')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('Byte offset to start from (0 = beginning). Loop increasing it until eof=true and reassemble')]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_FETCH_MAXBYTES)]
    property MaxBytes: Integer read FMaxBytes write FMaxBytes;
  end;

  TDelphiFetchTool = class(TMCPToolBase<TDelphiFetchParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiFetchParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiUploadParams = class
  private
    FPath: string;
    FChunkBase64: string;
    FOffset: Integer;
    FSha256: string;
  public
    [SchemaDescription('Absolute path of the file to write ON the server (inside the workspace roots)')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('One chunk of the file, base64-encoded. offset=0 truncates/creates; later offsets append')]
    property ChunkBase64: string read FChunkBase64 write FChunkBase64;
    [SchemaDescription('Byte offset this chunk starts at (0 = beginning). Send chunks in order, increasing offset by the bytes written')]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription('Optional: on the LAST chunk, the whole-file SHA-256; the server verifies the assembled file and reports verified true/false')]
    property Sha256: string read FSha256 write FSha256;
  end;

  TDelphiUploadTool = class(TMCPToolBase<TDelphiUploadParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiUploadParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiPackageParams = class
  private
    FDir: string;
    FOutFile: string;
  public
    [SchemaDescription('Directory to package (e.g. the build output Win64\Debug). Recursive; *.dcu and dcu\ intermediates excluded')]
    property Dir: string read FDir write FDir;
    [SchemaDescription('Optional zip path (default: sibling of dir, named <dirname>-deploy.zip). Must be inside the workspace roots')]
    property OutFile: string read FOutFile write FOutFile;
  end;

  TDelphiPackageTool = class(TMCPToolBase<TDelphiPackageParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPackageParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.RegularExpressions,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.Client,
  Lsp.Discovery,
  Lsp.References,
  Lsp.BuildRunner,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.Files;

const
  DEFAULT_MASKS: array [0 .. 7] of string =
    ('*.pas', '*.dpr', '*.dpk', '*.inc', '*.dfm', '*.fmx', '*.dproj', '*.groupproj');

{ Recursive file walk that TOLERATES unreadable subdirectories. Delphi's
  TDirectory.GetFiles(soAllDirectories) aborts the WHOLE enumeration on the
  first failure - measured on the Android NDK, whose deep paths exceed the
  classic limit and killed an entire delphi_list. One bad folder must never
  hide the rest of the tree. }
function WalkFiles(const ADir, AMask: string): TArray<string>;
var
  Acc: TStringList;

  procedure Recurse(const D: string);
  var
    F, Sub: string;
  begin
    try
      for F in TDirectory.GetFiles(D, AMask, TSearchOption.soTopDirectoryOnly) do
        Acc.Add(F);
    except
      // unreadable folder: skip its files, still try its children
    end;
    try
      for Sub in TDirectory.GetDirectories(D) do
        Recurse(Sub);
    except
      // cannot enumerate children: nothing else to do here
    end;
  end;

begin
  Acc := TStringList.Create;
  try
    Recurse(ADir);
    Result := Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

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
  Result := ReadPathDenied(Params.Root); // searching may enter the library zone
  if Result <> '' then
    Exit;
  // A single FILE as root: "find X in this .dproj" used to cost 3-6
  // delphi_read calls of 400 lines (field 2026-08-22, a 1909-line .dproj).
  var SingleFile := TFile.Exists(Params.Root) and not TDirectory.Exists(Params.Root);
  if not SingleFile and not TDirectory.Exists(Params.Root) then
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
    var Masks: TArray<string> := [];
    for Mask in DEFAULT_MASKS do
      Masks := Masks + [Mask];
    if Params.Pattern.Trim <> '' then
    begin
      if not TRegEx.IsMatch(Params.Pattern.Trim, '^[\w*?.\-]+$') then
        Exit('RECHAZADO: pattern debe ser UNA mascara simple (*.style, *.ini, Galatea*.rc).');
      Masks := [Params.Pattern.Trim];
    end;
    var Targets: TArray<string> := [];
    if SingleFile then
      Targets := [Params.Root]
    else
      for Mask in Masks do
        Targets := Targets + WalkFiles(Params.Root, Mask);
    for F in Targets do
      begin
        if not SingleFile and (SkipIdeArtifacts(F) or InVault(F)) then
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
                // The LSP tools want a 0-based line:character, and the hit
                // used to arrive Trim'ed - so the column could not be derived
                // and every navigation cost an extra delphi_read just to
                // count spaces (field 2026-08-25). Now the line travels
                // VERBATIM and the position of the match comes with it.
                Entry.AddPair('line0', TJSONNumber.Create(I));
                Entry.AddPair('character0', TJSONNumber.Create(P - 1));
                Entry.AddPair('text', LineText);
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
    'artifacts BELOW the root: naming a build-output folder (Win32/Win64/' +
    'Debug/Release...) as root lists inside it, and when entries are ' +
    'hidden the result says how many. Returns path, size and last-write ' +
    'time. Capped at 500 entries. With dirs=true it lists the ' +
    'SUBDIRECTORIES of root instead (one level, explorer-style) - use that ' +
    'to browse the machine and decide where to create or look for ' +
    'projects. With includeTrash=true it also shows the recoverable trash ' +
    '(__delphi-patch) so you can find a file deleted by delphi_delete and ' +
    'restore it with delphi_move.';
end;

{ Path relative to the listing root, in the '\seg\' shape SkipIdeArtifacts
  expects. Artifact filtering for delphi_list happens on THIS, not on the
  absolute path: naming a build-output folder as root is explicit consent to
  see inside it (field: an agent chased a freshly built exe for 20 calls
  because Compiled\Win32\Release answered empty), while listings from above
  still hide build output - and now say how much they hid. }
function RelToRoot(const AFull, ARoot: string): string;
var
  R: string;
begin
  R := IncludeTrailingPathDelimiter(ARoot);
  if AFull.ToLower.StartsWith(R.ToLower) then
    Result := '\' + Copy(AFull, Length(R) + 1, MaxInt)
  else
    Result := AFull;
end;

function TDelphiListTool.ExecuteWithParams(const Params: TDelphiListParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  F, Mask, Root: string;
  Masks: TArray<string>;
  Entry: TJSONObject;
  Total, Hidden: Integer;
begin
  Result := ReadPathDenied(Params.Root); // listing may enter the library zone
  if Result <> '' then
    Exit;
  // Canonicalize before walking: otherwise a root carrying "..\" segments is
  // echoed literally in every returned path (field round 4, R4-C).
  try
    Root := TPath.GetFullPath(Params.Root);
  except
    Root := Params.Root;
  end;
  if not TDirectory.Exists(Root) then
    Exit('error: directory not found: ' + Root);
  // Shell-style brace expansion is NOT a mask: *.{pas,dfm} matched nothing
  // silently (field 2026-08-22). Say so instead of returning an empty list.
  if Params.Pattern.Contains('{') or Params.Pattern.Contains('}') then
    Exit('RECHAZADO: pattern no admite llaves {a,b} (expansion de shell). Usa UNA ' +
      'mascara (*.pas) o varias separadas por ";" (*.pas;*.dfm).');

  if Params.Dirs then
  begin
    Return := TJSONObject.Create;
    Arr := TJSONArray.Create;
    Total := 0;
    Hidden := 0;
    try
      // A root already inside artifact territory was asked for by name:
      // hiding its Debug/Release children would recreate the trap.
      var RootInArtifacts := SkipIdeArtifacts(IncludeTrailingPathDelimiter(Root));
      for F in TDirectory.GetDirectories(Root) do
      begin
        var IsTrash := SameText(TPath.GetFileName(F), '__delphi-patch') or
                       SameText(TPath.GetFileName(F), '__pascal-patch');
        if InVault(F) or
           TPath.GetFileName(F).StartsWith('.') or
           (TPath.GetFileName(F).StartsWith('__') and
            not (Params.IncludeTrash and IsTrash)) then
          Continue;
        if (not RootInArtifacts) and
           SkipIdeArtifacts(RelToRoot(F, Root) + '\', Params.IncludeTrash) then
        begin
          Inc(Hidden);
          Continue;
        end;
        Inc(Total);
        if Arr.Count < 500 then
          Arr.Add(F);
      end;
      Return.AddPair('total', TJSONNumber.Create(Total));
      if Hidden > 0 then
      begin
        Return.AddPair('hidden', TJSONNumber.Create(Hidden));
        Return.AddPair('note', Format(SN_LIST_HIDDEN_FMT, [Hidden]));
      end;
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
  Hidden := 0;
  try
    for Mask in Masks do
      for F in WalkFiles(Root, Mask.Trim) do
      begin
        // The vault is the vault_* tools' business, even when it sits inside a
        // root: listing its notes would invite edits behind its back.
        if InVault(F) then
          Continue;
        if SkipIdeArtifacts(RelToRoot(F, Root), Params.IncludeTrash) then
        begin
          Inc(Hidden);
          Continue;
        end;
        Inc(Total);
        if Arr.Count < 500 then
        begin
          Entry := TJSONObject.Create;
          Arr.Add(Entry);
          Entry.AddPair('path', F);
          // Size/date can fail on paths past the classic length limit (the
          // Android NDK is full of them) - measured: one such file aborted
          // the whole listing. The entry still goes out, just without them.
          try
            Entry.AddPair('size', TJSONNumber.Create(TFile.GetSize(F)));
            Entry.AddPair('modified',
              FormatDateTime('yyyy-mm-dd hh:nn:ss', TFile.GetLastWriteTime(F)));
          except
            Entry.AddPair('note', 'size/date unavailable (path too long?)');
          end;
        end;
      end;
    Return.AddPair('total', TJSONNumber.Create(Total));
    Return.AddPair('shown', TJSONNumber.Create(Arr.Count));
    if Hidden > 0 then
    begin
      Return.AddPair('hidden', TJSONNumber.Create(Hidden));
      Return.AddPair('note', Format(SN_LIST_HIDDEN_FMT, [Hidden]));
    end;
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
    'machine, so a remote agent can bring in code and version its work: ' +
    'status, diff, log, show, branch, add, commit, init, push, tag, config, ' +
    'clone, pull, fetch. **clone** is the fast way to get a whole repo onto ' +
    'the server (URL in "message", destination directory in "repo", jailed ' +
    'to the workspace roots) - far better than recreating files one by one. ' +
    'commit/tag messages and config values also travel in "message"; push/' +
    'pull use the credentials and remotes stored on the server. No arbitrary ' +
    'git commands, no shell.';
end;

function TDelphiGitTool.ExecuteWithParams(const Params: TDelphiGitParams): string;
const
  BadChars: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  Cmd, GitArgs, Repo, Output, MsgFile: string;
  ExitCode: Cardinal;
  B: string;
begin
  MsgFile := '';
  Repo := Params.Repo;
  if Repo = '' then
    Exit('error: missing repo');
  Result := PathDenied(Repo);
  if Result <> '' then
    Exit;
  if TFile.Exists(Repo) then
    Repo := TPath.GetDirectoryName(Repo);
  // clone is the one command whose target directory does not exist yet: it
  // is created (inside the jail, already checked above).
  if SameText(Params.Command.Trim, 'clone') then
  begin
    if not TDirectory.Exists(Repo) then
      TDirectory.CreateDirectory(Repo);
  end
  else if not TDirectory.Exists(Repo) then
    Exit('error: directory not found: ' + Repo);

  for B in BadChars do
    if Params.Args.Contains(B) then
      Exit('error: shell metacharacters are not allowed in args');
  // The message never goes through a shell (git is spawned with a direct
  // command line): normal punctuation is welcome. Line breaks are refused
  // ONLY for the commands that embed the message in the command line -
  // commit and tag write it to a file and pass -F, so there a multi-line
  // message is exactly what you want: subject, blank line, body with the
  // WHY. Refusing it left every agent-made history as one-line subjects
  // (field report 2026-08-25).
  if (Params.Message.Contains(#13) or Params.Message.Contains(#10)) and
     not MatchText(Params.Command.Trim, ['commit', 'tag']) then
    Exit(SR_GIT_MESSAGE_LINES);
  // Dangerous git options (--output, --no-index, -c, ...) are filtered at the
  // single gate (Lsp.Guard.ToolCallDenied), before this handler runs.

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
    // -F <file>: the message reaches git byte-exact. Embedding it in the
    // command line mangled double quotes (measured in the field: " -> '').
    MsgFile := TPath.Combine(TPath.GetTempPath,
      'delphi-mcp-msg-' + TGUID.NewGuid.ToString + '.txt');
    TFile.WriteAllBytes(MsgFile, TEncoding.UTF8.GetBytes(Params.Message));
    GitArgs := Format('commit -F "%s" %s', [MsgFile, Params.Args]);
  end
  else if Cmd = 'clone' then
  begin
    // The URL travels in "message" (args screens metacharacters, and a URL
    // legitimately carries ':' '/' '@'). Destination = repo (jailed).
    var Url := Params.Message.Trim;
    if Url = '' then
      Exit('error: clone needs the repository URL in the "message" parameter ' +
        '(the destination directory is "repo")');
    if not (Url.StartsWith('https://') or Url.StartsWith('http://') or
            Url.StartsWith('git://') or Url.StartsWith('ssh://')) then
      Exit('error: only https/http/git/ssh URLs are accepted for clone');
    for B in BadChars do
      if Url.Contains(B) then
        Exit('error: shell metacharacters are not allowed in the URL');
    if Url.Contains('--upload-pack') or Url.Contains('--config') or
       Url.StartsWith('-') then
      Exit('error: that URL is not allowed');
    if TDirectory.Exists(TPath.Combine(Repo, '.git')) then
      Exit('error: "' + Repo + '" ya es un repositorio git. Usa pull para ' +
        'actualizarlo, o clona en otra carpeta.');
    // clone into "." of the (jailed, existing) destination directory. The "--"
    // separator guarantees the URL is a POSITIONAL, never parsed as an option,
    // whatever it contains - defence in depth over the leading-"-" check above
    // (field round 9: git network args travel fairly verbatim). User args go
    // BEFORE "--" so legitimate options (--depth, --branch) still apply; they
    // were already vetted for dangerous flags at the single gate (GitArgDenied).
    GitArgs := Format('clone %s -- "%s" .', [Params.Args, Url]);
  end
  else if Cmd = 'pull' then
    GitArgs := 'pull ' + Params.Args
  else if Cmd = 'fetch' then
    GitArgs := 'fetch ' + Params.Args
  else if Cmd = 'init' then
    GitArgs := 'init ' + Params.Args
  else if Cmd = 'config' then
  begin
    // Only the commit identity, so a remote agent can commit on a fresh
    // repo/machine. Anything else in git config stays off-limits.
    if not (SameText(Params.Args.Trim, 'user.name') or
            SameText(Params.Args.Trim, 'user.email')) then
      Exit('error: config only accepts user.name or user.email in args ' +
        '(the value goes in the "message" parameter)');
    if Params.Message.Trim = '' then
      Exit('error: config needs the value in the "message" parameter');
    GitArgs := Format('config %s "%s"',
      [Params.Args.Trim.ToLower, Params.Message.Replace('"', '''''')]);
  end
  else if Cmd = 'switch' then
  begin
    // Changing branch is what a real workflow needs and what was missing:
    // an agent could CREATE a branch and never move to it (review
    // 2026-08-25). Only the branch form: "switch <branch>" or, with
    // create=true, "switch -c <branch>". The file-restoring forms of
    // checkout (checkout -- <path>) are NOT here on purpose - those DISCARD
    // work, and discarding has its own command with its own words.
    if Params.Args.Trim = '' then
      Exit(SR_GIT_SWITCH_NEEDS);
    if Params.Create then
      GitArgs := 'switch -c ' + Params.Args
    else
      GitArgs := 'switch ' + Params.Args;
  end
  else if Cmd = 'merge' then
  begin
    if Params.Args.Trim = '' then
      Exit(SR_GIT_MERGE_NEEDS);
    // --ff-only: a merge that would need a commit (and could conflict half
    // way) is refused rather than left half-done. Real conflicts are a
    // human's business, not an agent's guess.
    GitArgs := 'merge --ff-only ' + Params.Args;
  end
  else if Cmd = 'stash' then
  begin
    // push (default) / pop / list: park work to change branch and get it
    // back. Never "stash drop" - that destroys.
    if Params.Args.Trim = '' then
      GitArgs := 'stash push'
    else if MatchText(Params.Args.Trim.ToLower, ['push', 'pop', 'list']) then
      GitArgs := 'stash ' + Params.Args.Trim.ToLower
    else
      Exit(SR_GIT_STASH_ARGS);
  end
  else if Cmd = 'push' then
    // uses the SERVER's stored credentials/remotes - consistent with the
    // centralized model (the repo lives next to the compiler)
    GitArgs := 'push ' + Params.Args
  else if Cmd = 'tag' then
  begin
    if Params.Message.Trim <> '' then
    begin
      // -F makes it annotated (like -m) and keeps quotes byte-exact;
      // args = tag name (and options)
      MsgFile := TPath.Combine(TPath.GetTempPath,
        'delphi-mcp-msg-' + TGUID.NewGuid.ToString + '.txt');
      TFile.WriteAllBytes(MsgFile, TEncoding.UTF8.GetBytes(Params.Message));
      GitArgs := Format('tag -F "%s" %s', [MsgFile, Params.Args]);
    end
    else
      GitArgs := 'tag ' + Params.Args; // no args = list tags
  end
  else
    Exit('error: unknown command "' + Params.Command +
      '". Allowed: status | diff | log | show | branch | add | commit | init | ' +
      'push | tag | config | clone | pull | fetch');

  if MatchText(Cmd, ['clone', 'pull', 'fetch', 'push']) then
    TLogger.Warning(Format('delphi_git: NETWORK %s repo=%s %s',
      [Cmd, Repo, Params.Message]));

  try
    Output := RunCaptured(Format('git.exe -C "%s" %s', [Repo, GitArgs]),
      IfThen(MatchText(Cmd, ['push', 'clone', 'pull', 'fetch']), 600000, 60000),
      ExitCode);
  finally
    if (MsgFile <> '') and TFile.Exists(MsgFile) then
      TFile.Delete(MsgFile);
  end;
  if Length(Output) > 30000 then
    Output := Copy(Output, 1, 30000) + #10'... (truncated)';
  Result := Format('exit=%d'#10'%s', [ExitCode, Output.Trim]);
  // A fresh repo has no author identity and commit dies with exit 128:
  // the fix is already whitelisted, say so (measured 2026-08-24).
  if (ExitCode <> 0) and Output.Contains('Author identity unknown') then
    Result := Result + #10 +
      'Pista: configura la identidad del repo y repite: delphi_git ' +
      'command=config args=user.name message=<nombre> y despues ' +
      'command=config args=user.email message=<email>.';
end;

{ TDelphiInstallsTool }

constructor TDelphiInstallsTool.Create;
begin
  inherited;
  FName := 'delphi_installs';
  FDescription := 'List EVERY RAD Studio / Delphi installation discovered on ' +
    'this machine (a machine may host several versions side by side): ' +
    'version, root directory, whether it ships DelphiLSP.exe (semantic ' +
    'engine) and rsvars.bat (msbuild). Also reports which one is ACTIVE for ' +
    'the LSP tools (the newest with DelphiLSP). Read-only, no parameters.';
end;

function TDelphiInstallsTool.ExecuteWithParams(const Params: TDelphiInstallsParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  Entry: TJSONObject;
  Info, Active: TRadStudioInfo;
  All: TArray<TRadStudioInfo>;
begin
  All := DiscoverAllRadStudios;
  Active := DiscoverRadStudio;
  Return := TJSONObject.Create;
  try
    Return.AddPair('total', TJSONNumber.Create(Length(All)));
    Return.AddPair('activeForLsp', Active.Version); // '' = none has DelphiLSP
    Arr := TJSONArray.Create;
    Return.AddPair('installs', Arr);
    for Info in All do
    begin
      Entry := TJSONObject.Create;
      Arr.AddElement(Entry);
      Entry.AddPair('version', Info.Version);
      Entry.AddPair('rootdir', Info.RootDir);
      Entry.AddPair('delphilsp', TJSONBool.Create(Info.DelphiLspExe <> ''));
      Entry.AddPair('msbuild', TJSONBool.Create(Info.RsVarsBat <> ''));
      Entry.AddPair('active', TJSONBool.Create(
        (Info.Version = Active.Version) and (Info.Version <> '')));
    end;
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiWorkspaceTool }

constructor TDelphiWorkspaceTool.Create;
begin
  inherited;
  FName := 'delphi_workspace';
  FDescription := 'The lay of the land on the SERVER: the workspace roots ' +
    'this server operates within (your entire allowed universe here), the ' +
    'access level (read-write / read-only), and the active RAD Studio. ' +
    SN_VIRTUAL_DRIVES + ' Call this FIRST. Read-only, no parameters.';
end;

function TDelphiWorkspaceTool.ExecuteWithParams(const Params: TDelphiWorkspaceParams): string;
var
  Return: TJSONObject;
  RootsArr: TJSONArray;
  R: string;
  Roots: TArray<string>;
  Info: TRadStudioInfo;
begin
  Return := TJSONObject.Create;
  try
    Return.AddPair('note', SN_WORKSPACE_NOTE);
    Roots := WorkspaceRoots;
    RootsArr := TJSONArray.Create;
    Return.AddPair('roots', RootsArr);
    for R in Roots do
      RootsArr.Add(ExcludeTrailingPathDelimiter(R));
    if Length(Roots) = 0 then
      Return.AddPair('jail', 'none (unrestricted local mode - no [Workspace] ' +
        'Roots configured)')
    else
      Return.AddPair('jail', 'active');
    // What may be READ beyond the roots: the RAD Studio installations, the
    // IDE library search paths and the GetIt catalog repositories. Announced
    // because "anything outside is refused" was not the whole truth for
    // reading tools (field round 4, R4-B).
    // COMPRESSED to the unique top-level trees: the raw list is ~145
    // registered folders and cost every agent ~3.5k tokens on its FIRST
    // call of every session (measured 2026-08-24 while hunting what filled
    // a local model's context). Subfolders of an announced tree add a
    // counter, not a line.
    var ExtraArr := TJSONArray.Create;
    Return.AddPair('readableExtra', ExtraArr);
    var Tops := TList<string>.Create;
    var Counts := TList<Integer>.Create;
    try
      for R in LibraryReadRoots do
      begin
        var Full := IncludeTrailingPathDelimiter(R);
        var Found := -1;
        for var I := 0 to Tops.Count - 1 do
          if StartsText(Tops[I], Full) then
          begin
            Found := I;
            Break;
          end;
        if Found >= 0 then
          Counts[Found] := Counts[Found] + 1
        else
        begin
          // a new candidate may itself be the parent of already-listed ones
          for var I := Tops.Count - 1 downto 0 do
            if StartsText(Full, Tops[I]) then
            begin
              Counts[Tops.Count - 1] := 0; // placeholder, fixed below
              Tops.Delete(I);
              Counts.Delete(I);
            end;
          Tops.Add(Full);
          Counts.Add(0);
        end;
      end;
      for var I := 0 to Tops.Count - 1 do
        if Counts[I] > 0 then
          ExtraArr.Add(Format('%s  (+%d subcarpetas registradas)',
            [ExcludeTrailingPathDelimiter(Tops[I]), Counts[I]]))
        else
          ExtraArr.Add(ExcludeTrailingPathDelimiter(Tops[I]));
    finally
      Counts.Free;
      Tops.Free;
    end;
    if LibraryZoneEnabled then
      Return.AddPair('readableExtraNote', 'Read-only territory: RTL/VCL/FMX ' +
        'sources, installed components and SDKs. Reading tools may enter it; ' +
        'writing tools never can.')
    else
      Return.AddPair('readableExtraNote', SN_WORKSPACE_LIBZONE_OFF);
    if IsReadOnlyNow then
      Return.AddPair('access', 'read-only')
    else
      Return.AddPair('access', 'read-write');
    Info := DiscoverRadStudio;
    if Info.Found then
      Return.AddPair('activeDelphi', Info.Version)
    else
      Return.AddPair('activeDelphi', '');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
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

{ The git repository a path belongs to (the folder holding .git), '' when
  none, plus the branch checked out there. An agent arriving cold has to know
  whether what it is about to edit is under version control and on which
  branch BEFORE it edits: asking for it cost a call and some guessing (field
  round 7). Read straight from .git/HEAD - no git process, no shell. }
function RepoOf(const APath: string; out ABranch: string): string;
var
  Dir, Head: string;
begin
  Result := '';
  ABranch := '';
  Dir := APath;
  if TFile.Exists(Dir) then
    Dir := TPath.GetDirectoryName(Dir);
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.git')) or
       TFile.Exists(TPath.Combine(Dir, '.git')) then
    begin
      Result := Dir;
      Head := TPath.Combine(Dir, '.git\HEAD');
      if TFile.Exists(Head) then
        try
          ABranch := TFile.ReadAllText(Head).Trim;
          if ABranch.StartsWith('ref:') then
            ABranch := ABranch.Substring(ABranch.LastIndexOf('/') + 1)
          else
            ABranch := ABranch.Substring(0, 8) + ' (detached)';
        except
          ABranch := '';
        end;
      Exit;
    end;
    if TPath.GetDirectoryName(Dir) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(Dir);
  end;
end;

function TDelphiProjectsTool.ExecuteWithParams(const Params: TDelphiProjectsParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  Roots: TArray<string>;
  RootDir, F, Filt: string;
  Entry: TJSONObject;
  Total: Integer;
  Mask, Repo, Branch: string;
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
    // The jail's own list (env DELPHI_MCP_ROOTS or settings.ini) - the ONE
    // source of truth. This tool used to re-read the ini itself and a server
    // configured by environment variable answered "no roots configured"
    // while every other tool was correctly jailed (measured 2026-08-24).
    Roots := WorkspaceRoots;
    if Length(Roots) = 0 then
      Exit('error: no root given and no workspace roots configured. Pass ' +
        '"root", or configure [Workspace] Roots in settings.ini next to the ' +
        'server exe (or the DELPHI_MCP_ROOTS environment variable).');
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
        for F in WalkFiles(RootDir.Trim, Mask) do
        begin
          if SkipIdeArtifacts(F) or InVault(F) then
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
            Repo := RepoOf(F, Branch);
            if Repo <> '' then
            begin
              Entry.AddPair('repo', Repo);
              if Branch <> '' then
                Entry.AddPair('branch', Branch);
            end;
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
  FDescription := 'DISABLED BY DEFAULT. This is a compile-only development ' +
    'server: it does NOT execute programs. To test a binary, download it ' +
    '(delphi_package + delphi_fetch) and run it on YOUR machine, or deploy ' +
    'to a real target (PAServer on Linux/macOS, or Android). The operator ' +
    'can opt in with [Security] AllowRun=1; only then does this run a built ' +
    'executable on the server (jailed to the roots, low-integrity sandbox, ' +
    'no shell, hard timeout, killed on expiry) - intended for console test ' +
    'runners in CI, never for GUI apps.';
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

  // Security audit trail (delphi_run is arbitrary execution by design):
  // log WHAT ran with the binary's hash, so every execution is accountable.
  try
    TLogger.Warning(Format('delphi_run: EXEC "%s" sha256=%s args=[%s] workdir=%s',
      [ExePath, THashSHA2.GetHashStringFromFile(ExePath),
       Params.Args, WorkDir]));
  except
    TLogger.Warning('delphi_run: EXEC "' + ExePath + '" (hash n/d)');
  end;

  var Sandboxed: Boolean;
  Output := RunCapturedSandboxed(Format('"%s" %s', [ExePath, Params.Args]).Trim,
    WorkDir, TimeoutMs, ExitCode, Sandboxed);
  if Length(Output) > 30000 then
    Output := Copy(Output, 1, 30000) + #10'... (truncated)';
  var SbNote: string;
  if Sandboxed then
    SbNote := 'sandbox=low-integrity (el programa solo pudo escribir en su ' +
      'carpeta de trabajo; el resto del disco es de solo lectura para el)'
  else
    SbNote := 'sandbox=NO (el SO rechazo el lanzamiento confinado; el programa ' +
      'corrio con integridad normal - avisa en delphi_report)';
  Result := Format('exit=%d  %s'#10'%s', [ExitCode, SbNote, Output.TrimRight]);
end;

{ TDelphiFetchTool }

constructor TDelphiFetchTool.Create;
begin
  inherited;
  FName := 'delphi_fetch';
  FDescription := SD_FETCH;
end;

function TDelphiFetchTool.ExecuteWithParams(const Params: TDelphiFetchParams): string;
const
  MAX_CHUNK = 8 * 1024 * 1024;
  // Above BIG_FILE the offset=0 answer carries the download link and NO
  // chunk (field 2026-08-21: a 72 MB installer pulled as base64 through a
  // 262K-token context). An explicit maxbytes <= SMALL_CHUNK is the opt-in
  // for inline chunks anyway (a client without a shell) - the parameter that
  // already exists doubles as the switch; nothing new to learn.
  BIG_FILE = 4 * 1024 * 1024;
  SMALL_CHUNK = 1024 * 1024;
var
  FullPath, Sha: string;
  Stream: TFileStream;
  Size, ChunkLen: Int64;
  MaxB: Integer;
  Buf: TBytes;
  Return: TJSONObject;
  B64: TBase64Encoding;
  Hasher: THashSHA2;
  LinkOnly: Boolean;
begin
  FullPath := TPath.GetFullPath(Params.Path);
  Result := ReadPathDenied(FullPath); // downloading is reading
  if Result <> '' then
    Exit;
  if not TFile.Exists(FullPath) then
    Exit('error: no existe ' + FullPath);
  MaxB := Params.MaxBytes;
  if (MaxB <= 0) or (MaxB > MAX_CHUNK) then
    MaxB := MAX_CHUNK;
  if Params.Offset < 0 then
    Exit('error: offset negativo');

  Stream := TFileStream.Create(FullPath, fmOpenRead or fmShareDenyWrite);
  try
    Size := Stream.Size;
    Sha := '';
    if Params.Offset = 0 then
    begin
      // Whole-file hash so the client can verify the reassembly.
      Hasher := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
      SetLength(Buf, 1024 * 1024);
      while True do
      begin
        ChunkLen := Stream.Read(Buf[0], Length(Buf));
        if ChunkLen <= 0 then
          Break;
        Hasher.Update(Buf, ChunkLen);
      end;
      Sha := Hasher.HashAsString;
      Stream.Position := 0;
    end;

    if Params.Offset > Size then
      Exit('error: offset mas alla del final (size=' + IntToStr(Size) + ')');
    LinkOnly := GFilesServed and (Size > BIG_FILE) and (Params.Offset = 0) and
      ((Params.MaxBytes <= 0) or (Params.MaxBytes > SMALL_CHUNK));
    Stream.Position := Params.Offset;
    ChunkLen := Size - Params.Offset;
    if ChunkLen > MaxB then
      ChunkLen := MaxB;
    if LinkOnly then
      ChunkLen := 0;
    SetLength(Buf, ChunkLen);
    if ChunkLen > 0 then
      Stream.ReadBuffer(Buf[0], ChunkLen);

    Return := TJSONObject.Create;
    B64 := TBase64Encoding.Create(0); // no line breaks
    try
      Return.AddPair('path', FullPath);
      Return.AddPair('size', TJSONNumber.Create(Size));
      Return.AddPair('offset', TJSONNumber.Create(Params.Offset));
      Return.AddPair('bytes', TJSONNumber.Create(ChunkLen));
      Return.AddPair('eof', TJSONBool.Create(Params.Offset + ChunkLen >= Size));
      if Sha <> '' then
        Return.AddPair('sha256', Sha);
      if GFilesServed then
      begin
        // Relative on purpose: the client already knows the host:port it
        // talks to, and the server never guesses its own public address.
        // The path travels in its VIRTUAL form, URL-encoded (no real drive
        // letter ever leaves, encoded or not).
        Return.AddPair('download', FILES_ROUTE + '?path=' +
          TNetEncoding.URL.Encode(MaskDriveText(FName, FullPath)));
        Return.AddPair('downloadNote', SN_FETCH_DOWNLOAD);
      end;
      if LinkOnly then
        Return.AddPair('inline', TJSONBool.Create(False));
      if LinkOnly then
        Return.AddPair('note', Format(SN_FETCH_BIG_FMT,
          [FormatFloat('0.0', Size / (1024 * 1024), TFormatSettings.Invariant) + ' MB']))
      else
        Return.AddPair('chunkBase64', B64.EncodeBytesToString(Buf));
      Result := Return.ToJSON;
    finally
      B64.Free;
      Return.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{ TDelphiUploadTool }

constructor TDelphiUploadTool.Create;
begin
  inherited;
  FName := 'delphi_upload';
  FDescription := 'Upload a file TO the server in base64 chunks - the mirror ' +
    'of delphi_fetch, for material you cannot recreate by editing: binaries ' +
    '(.res, icons, images), binary designer files, archives, reference ' +
    'material. Send chunks in order: offset=0 creates/truncates, later ' +
    'offsets append and must match the current size. Pass sha256 on the LAST ' +
    'chunk to have the server verify the assembled file. Jailed to the ' +
    'workspace roots; parent directories are created. A fresh upload over an ' +
    'existing file backs the old one up to the recoverable trash first. For ' +
    'SOURCE CODE prefer delphi_edit / delphi_textedit (they audit encoding and ' +
    'keep backups).';
end;

function TDelphiUploadTool.ExecuteWithParams(const Params: TDelphiUploadParams): string;
var
  FullPath, Dir, Sha, Backup, Quarantine: string;
  Bytes: TBytes;
  Stream: TFileStream;
  Return: TJSONObject;
  B64: TBase64Encoding;
  Size, OldSize: Int64;
  Replaced: Boolean;
begin
  FullPath := TPath.GetFullPath(Params.Path);
  Result := PathDenied(FullPath); // writing: the strict jail, never the library zone
  if Result <> '' then
    Exit;
  if Params.Offset < 0 then
    Exit('error: offset negativo');
  if SkipIdeArtifacts(FullPath) then
    Exit('error: ruta de artefactos del IDE (__history, __recovery, Win32, ' +
      'dcu...): no se sube ahi.');
  // An upload with no bytes is not an upload: the schema only demanded "path",
  // so a half-typed call landed here, opened the file with fmCreate and left
  // it at 0 bytes reporting success (field round 8). Nothing destructive may
  // ride on a call that carries no content.
  if Params.ChunkBase64.Trim = '' then
  begin
    if TFile.Exists(FullPath) then
      Exit(Format(SR_UPLOAD_NO_CHUNK_FMT, [TFile.GetSize(FullPath)]));
    Exit(SR_UPLOAD_NO_CHUNK_NEW);
  end;

  // Delphi's decoder SKIPS invalid characters instead of failing, which would
  // silently write a corrupt file: validate the alphabet ourselves first.
  for var Ch in Params.ChunkBase64 do
    if not (CharInSet(Ch, ['A' .. 'Z', 'a' .. 'z', '0' .. '9', '+', '/', '=',
      #13, #10, ' '])) then
      Exit('error: chunkBase64 contiene caracteres que no son base64');
  B64 := TBase64Encoding.Create(0);
  try
    try
      Bytes := B64.DecodeStringToBytes(Params.ChunkBase64);
    except
      on E: Exception do
        Exit('error: chunkBase64 no es base64 valido (' + E.Message + ')');
    end;
  finally
    B64.Free;
  end;

  Dir := TPath.GetDirectoryName(FullPath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);

  // Non-destructive: a fresh upload (offset 0) TRUNCATES the target. If a file
  // is already there, copy it to the recoverable trash first - upload was the
  // only writer that could overwrite with no undo (field round 7). Skip the
  // trash's own tree so a backup never triggers another backup.
  Backup := '';
  if (Params.Offset = 0) and TFile.Exists(FullPath) then
  begin
    Replaced := True;
    OldSize := 0;
    try
      OldSize := TFile.GetSize(FullPath);
    except
    end;
    if not SkipIdeArtifacts(FullPath, False) then
      try
        Backup := BackupFile(FullPath);
      except
        on E: Exception do
          Backup := 'FALLO la copia de seguridad: ' + E.Message;
      end;
  end;

  if Params.Offset = 0 then
    Stream := TFileStream.Create(FullPath, fmCreate)
  else
  begin
    if not TFile.Exists(FullPath) then
      Exit('error: offset>0 pero el fichero no existe todavia; empieza por offset=0');
    Stream := TFileStream.Create(FullPath, fmOpenReadWrite or fmShareDenyWrite);
  end;
  try
    if Params.Offset > Stream.Size then
      Exit(Format('error: offset %d mas alla del final actual (size=%d); ' +
        'envia los trozos EN ORDEN', [Params.Offset, Stream.Size]));
    Stream.Position := Params.Offset;
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Stream.Size := Stream.Position; // truncate any leftover from a previous file
    Size := Stream.Size;
  finally
    Stream.Free;
  end;

  Return := TJSONObject.Create;
  try
    Return.AddPair('path', FullPath);
    Return.AddPair('written', TJSONNumber.Create(Length(Bytes)));
    Return.AddPair('size', TJSONNumber.Create(Size));
    Return.AddPair('nextOffset', TJSONNumber.Create(Size));
    // A fresh upload over an existing file REPLACES it. Say so, and say where
    // the previous content went: an agent that cannot see the copy assumes
    // there is none (measured, field round 8).
    if Replaced then
    begin
      Return.AddPair('replaced', TJSONBool.Create(True));
      Return.AddPair('previousSize', TJSONNumber.Create(OldSize));
      if Backup <> '' then
        Return.AddPair('backup', Backup);
      Return.AddPair('note', Format(SN_UPLOAD_REPLACED_FMT, [OldSize]));
    end;
    if Params.Sha256.Trim <> '' then
    begin
      Sha := THashSHA2.GetHashStringFromFile(FullPath);
      Return.AddPair('sha256', Sha);
      Return.AddPair('verified', TJSONBool.Create(
        SameText(Sha, Params.Sha256.Trim)));
      if not SameText(Sha, Params.Sha256.Trim) then
      begin
        // The file on disk is now KNOWN to be wrong. Leaving it in place under
        // its real name means the next reader takes corruption for content:
        // park it aside and say where (field round 8).
        Quarantine := FullPath + '.corrupto';
        try
          if TFile.Exists(Quarantine) then
            TFile.Delete(Quarantine);
          TFile.Move(FullPath, Quarantine);
          Return.AddPair('quarantined', Quarantine);
        except
          Quarantine := '';
        end;
        if Quarantine = '' then
          Quarantine := FullPath;
        Return.AddPair('warning', Format(SR_UPLOAD_SHA_MISMATCH_FMT, [Quarantine]));
      end;
    end;
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiPackageTool }

constructor TDelphiPackageTool.Create;
begin
  inherited;
  FName := 'delphi_package';
  FDescription := 'Zip a build-output directory ON the server into a single ' +
    'deploy artifact (recursive, *.dcu intermediates excluded), ready to ' +
    'download with ONE delphi_fetch. The standard way to bring a GUI app to ' +
    'the client machine: delphi_build -> delphi_package -> delphi_fetch.';
end;

function TDelphiPackageTool.ExecuteWithParams(const Params: TDelphiPackageParams): string;
var
  Dir, OutZip, F, Rel: string;
  Zip: TZipFile;
  Return: TJSONObject;
  Count: Integer;
  TotalBytes: Int64;
begin
  // Without this the empty string reached TPath.GetFullPath and the dispatcher
  // wrapped an EArgumentException as "Error executing tool: Invalid characters
  // in path" - a crash where a missing parameter belonged (field round 8).
  if Params.Dir.Trim = '' then
    Exit(SR_PACKAGE_NEED_DIR);
  Dir := TPath.GetFullPath(Params.Dir);
  Result := PathDenied(Dir);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Dir) then
    Exit('error: directory not found: ' + Dir);

  if Params.OutFile <> '' then
    OutZip := TPath.GetFullPath(Params.OutFile)
  else
    OutZip := TPath.Combine(TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir)),
      TPath.GetFileName(ExcludeTrailingPathDelimiter(Dir)) + '-deploy.zip');
  Result := PathDenied(OutZip);
  if Result <> '' then
    Exit;
  if TFile.Exists(OutZip) then
    TFile.Delete(OutZip); // packages are disposable artifacts, always fresh

  Count := 0;
  TotalBytes := 0;
  Zip := TZipFile.Create;
  try
    Zip.Open(OutZip, zmWrite);
    for F in WalkFiles(Dir, '*') do
    begin
      if SameText(TPath.GetExtension(F), '.dcu') then
        Continue;
      if F.ToLower.Contains('\dcu\') then
        Continue;
      if SameText(TPath.GetFullPath(F), OutZip) then
        Continue;
      Rel := F.Substring(Length(IncludeTrailingPathDelimiter(Dir))).Replace('\', '/');
      Zip.Add(F, Rel);
      Inc(Count);
      Inc(TotalBytes, TFile.GetSize(F));
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;

  Return := TJSONObject.Create;
  try
    Return.AddPair('zip', OutZip);
    Return.AddPair('files', TJSONNumber.Create(Count));
    Return.AddPair('uncompressedBytes', TJSONNumber.Create(TotalBytes));
    Return.AddPair('zipBytes', TJSONNumber.Create(TFile.GetSize(OutZip)));
    Return.AddPair('next', 'download it with delphi_fetch (chunked, sha256-verified)');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_package',
    function: IMCPTool begin Result := TDelphiPackageTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_fetch',
    function: IMCPTool begin Result := TDelphiFetchTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_upload',
    function: IMCPTool begin Result := TDelphiUploadTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_search',
    function: IMCPTool begin Result := TDelphiSearchTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_projects',
    function: IMCPTool begin Result := TDelphiProjectsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_installs',
    function: IMCPTool begin Result := TDelphiInstallsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_workspace',
    function: IMCPTool begin Result := TDelphiWorkspaceTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_run',
    function: IMCPTool begin Result := TDelphiRunTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_list',
    function: IMCPTool begin Result := TDelphiListTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_git',
    function: IMCPTool begin Result := TDelphiGitTool.Create; end);

end.
