unit Lsp.References;

{ Hybrid find-references. DelphiLSP does not implement textDocument/references
  (-32601, measured), so we combine a text scan with compiler-grade
  validation:

    1. resolve the target: definition() at the requested position;
    2. text-scan the project tree for word-boundary candidates of the
       identifier (case-insensitive - it's Pascal), skipping IDE artifacts;
    3. for each candidate, ask definition() at that exact spot: only the
       candidates that resolve to the SAME location as the target are
       confirmed - homonyms die here, killed by the compiler engine itself.

  Bounded: at most AMaxFiles files are opened for validation; candidates in
  files beyond that are reported as unverified rather than silently dropped. }

interface

uses
  System.JSON;

function FindDelphiReferences(const AFilePath: string;
  ALine, ACharacter: Integer; AMaxFiles: Integer = 40;
  AMaxCandidates: Integer = 400): TJSONObject;

{ True for IDE artifacts that must never be scanned/edited/reasoned about. }
function SkipIdeArtifacts(const APath: string): Boolean; overload;

{ WHY a path is skipped: 'artifacts' (build output, __history), 'git' (the
  repository's own plumbing), 'trash' (this tool's recoverable copies) or ''
  when it is not skipped at all. delphi_list used to count every one of them
  as "IDE build/artifact folders", so a listing that hid 42 files of .git
  sent the reader looking for build output that did not exist (2026-08-25). }
function SkipReason(const APath: string; AAllowTrash: Boolean): string;

{ Same, but when AAllowTrash the recoverable-trash folders (__delphi-patch /
  __pascal-patch) are NOT treated as skip reasons - so delphi_list can, on
  explicit request, show what was deleted for a restore (field round 6, R6-B).
  Every other artifact (__history, Win32/Win64, .git...) is still skipped. }
function SkipIdeArtifacts(const APath: string; AAllowTrash: Boolean): Boolean; overload;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  Lsp.Client,
  Lsp.Session,
  Lsp.Guard,
  Lsp.ProjectUnits;

type
  TCandidate = record
    Path: string;
    Line, Col: Integer;
    Text: string;
  end;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or
    ((C >= '0') and (C <= '9')) or (C = '_');
end;

function IdentifierAt(const ALineText: string; ACol: Integer): string;
var
  S, E: Integer;
begin
  // ACol is 0-based; string is 1-based.
  S := ACol + 1;
  if (S < 1) or (S > Length(ALineText)) or not IsIdentChar(ALineText[S]) then
    Exit('');
  while (S > 1) and IsIdentChar(ALineText[S - 1]) do
    Dec(S);
  E := ACol + 1;
  while (E < Length(ALineText)) and IsIdentChar(ALineText[E + 1]) do
    Inc(E);
  Result := Copy(ALineText, S, E - S + 1);
end;

function SkipIdeArtifacts(const APath: string; AAllowTrash: Boolean): Boolean;
const
  Bad: array [0 .. 7] of string = ('\__history\', '\__recovery\', '\win32\',
    '\win64\', '\debug\', '\release\', '\dcu\', '\.git\');
  Trash: array [0 .. 1] of string = ('\__pascal-patch\', '\__delphi-patch\');
var
  B, Low: string;
begin
  Low := APath.ToLower;
  for B in Bad do
    if Low.Contains(B) then
      Exit(True);
  if not AAllowTrash then
    for B in Trash do
      if Low.Contains(B) then
        Exit(True);
  Result := False;
end;

function SkipIdeArtifacts(const APath: string): Boolean;
begin
  Result := SkipIdeArtifacts(APath, False);
end;

function SkipReason(const APath: string; AAllowTrash: Boolean): string;
const
  Art: array [0 .. 6] of string = ('\__history\', '\__recovery\', '\win32\',
    '\win64\', '\debug\', '\release\', '\dcu\');
  Trash: array [0 .. 1] of string = ('\__pascal-patch\', '\__delphi-patch\');
var
  B, Low: string;
begin
  Result := '';
  Low := APath.ToLower;
  if Low.Contains('\.git\') then
    Exit('git');
  for B in Art do
    if Low.Contains(B) then
      Exit('artifacts');
  if not AAllowTrash then
    for B in Trash do
      if Low.Contains(B) then
        Exit('trash');
end;

function SkipPath(const APath: string): Boolean;
begin
  Result := SkipIdeArtifacts(APath);
end;

function DefinitionLocation(AResp: TJSONObject; out AUri: string;
  out ALine: Integer): Boolean;
var
  V: TJSONValue;
  Obj: TJSONObject;
begin
  Result := False;
  AUri := '';
  ALine := -1;
  V := AResp.GetValue('result');
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if V is TJSONArray then
  begin
    if TJSONArray(V).Count = 0 then
      Exit;
    V := TJSONArray(V).Items[0];
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  if Obj.GetValue('uri') = nil then
    Exit;
  AUri := Obj.GetValue('uri').Value;
  ALine := Obj.GetValue<Integer>('range.start.line');
  Result := True;
end;

function FindDelphiReferences(const AFilePath: string;
  ALine, ACharacter: Integer; AMaxFiles, AMaxCandidates: Integer): TJSONObject;
var
  Session: TLspSession;
  Client: TLspClient;
  Settings, RootDir, FullPath, Ident, TargetUri, CandUri: string;
  Lines: TStringList;
  Resp: TJSONObject;
  TargetLine, CandLine: Integer;
  Candidates: TList<TCandidate>;
  Cand: TCandidate;
  Files: TArray<string>;
  F, Ext, Text, LineText: string;
  AllFiles: TList<string>;
  I, P, ScanCol, FilesOpened: Integer;
  Confirmed, Unverified: TJSONArray;
  Rejected, Scanned: Integer;
  OpenedFiles: TDictionary<string, Boolean>;
  Entry: TJSONObject;

  function CandidateJson(const C: TCandidate): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('path', C.Path);
    Result.AddPair('line', TJSONNumber.Create(C.Line));
    Result.AddPair('character', TJSONNumber.Create(C.Col));
    Result.AddPair('text', C.Text.Trim);
  end;

begin
  Session := TLspSession.Instance;
  FullPath := TPath.GetFullPath(AFilePath);
  Client := Session.AcquireFor(FullPath, Settings);
  Session.ResolveSettings(FullPath, RootDir);

  // Identify the symbol under the cursor.
  Lines := TStringList.Create;
  try
    Lines.Text := TLspClient.LoadSourceText(FullPath);
    if (ALine < 0) or (ALine >= Lines.Count) then
      raise Exception.CreateFmt('Line %d out of range', [ALine]);
    Ident := IdentifierAt(Lines[ALine], ACharacter);
  finally
    Lines.Free;
  end;
  if Ident = '' then
    raise Exception.Create('No identifier at the given position');

  // Resolve the target location the compiler engine assigns to that symbol.
  Resp := Client.Definition(TLspClient.PathToUri(FullPath), ALine, ACharacter);
  try
    if not DefinitionLocation(Resp, TargetUri, TargetLine) then
      raise Exception.Create('definition() returned null for the target - ' +
        'cannot anchor references (are project settings available?)');
  finally
    Resp.Free;
  end;

  // Text scan for candidates.
  Candidates := TList<TCandidate>.Create;
  AllFiles := TList<string>.Create;
  try
    // The project folder is not the whole project: units living in sibling
    // folders (SharedSource\ next to codigofuente\, measured 2026-08-23 on a
    // real project) were never scanned, so a symbol used twice in its own
    // file reported zero references. Scan the project folder, the folder of
    // the file itself and the folder of every unit the .dpr lists.
    var Dirs := TList<string>.Create;
    try
      Dirs.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(RootDir)));
      var Extra: TArray<string> := [TPath.GetDirectoryName(FullPath)];
      var Dproj := Session.FindDproj(FullPath);
      if Dproj <> '' then
        for var PU in ProjectUnits(Dproj, False) do
          if TPath.IsPathRooted(PU.Include) then
            Extra := Extra + [TPath.GetDirectoryName(PU.Include)]
          else
            Extra := Extra + [TPath.GetDirectoryName(TPath.GetFullPath(
              TPath.Combine(TPath.GetDirectoryName(Dproj), PU.Include)))];
      for var D in Extra do
      begin
        if (D = '') or not TDirectory.Exists(D) then
          Continue;
        var DD := IncludeTrailingPathDelimiter(TPath.GetFullPath(D));
        var Covered := False;
        for var K in Dirs do
          if StartsText(K, DD) then
          begin
            Covered := True;
            Break;
          end;
        if not Covered and (ReadPathDenied(DD) = '') then
          Dirs.Add(DD);
      end;
      for var D in Dirs do
        for Ext in TArray<string>.Create('*.pas', '*.dpr', '*.inc') do
          for F in TDirectory.GetFiles(D, Ext, TSearchOption.soAllDirectories) do
            if not SkipPath(F) and not AllFiles.Contains(F) then
              AllFiles.Add(F);
    finally
      Dirs.Free;
    end;
    Scanned := AllFiles.Count;

    for F in AllFiles do
    begin
      if Candidates.Count >= AMaxCandidates then
        Break;
      Text := TLspClient.LoadSourceText(F);
      Lines := TStringList.Create;
      try
        Lines.Text := Text;
        for I := 0 to Lines.Count - 1 do
        begin
          LineText := Lines[I];
          ScanCol := 1;
          repeat
            P := Pos(Ident.ToLower, LineText.ToLower, ScanCol);
            if P = 0 then
              Break;
            // word boundaries
            if ((P = 1) or not IsIdentChar(LineText[P - 1])) and
               ((P + Length(Ident) > Length(LineText)) or
                not IsIdentChar(LineText[P + Length(Ident)])) then
            begin
              Cand.Path := F;
              Cand.Line := I;
              Cand.Col := P - 1;
              Cand.Text := LineText;
              Candidates.Add(Cand);
              if Candidates.Count >= AMaxCandidates then
                Break;
            end;
            ScanCol := P + Length(Ident);
          until False;
          if Candidates.Count >= AMaxCandidates then
            Break;
        end;
      finally
        Lines.Free;
      end;
    end;

    // Validate candidates with definition(), bounded by AMaxFiles.
    Confirmed := TJSONArray.Create;
    Unverified := TJSONArray.Create;
    Rejected := 0;
    FilesOpened := 0;
    OpenedFiles := TDictionary<string, Boolean>.Create;
    try
      for Cand in Candidates do
      begin
        if not OpenedFiles.ContainsKey(Cand.Path.ToLower) then
        begin
          if FilesOpened >= AMaxFiles then
          begin
            Unverified.Add(CandidateJson(Cand));
            Continue;
          end;
          Session.AcquireFor(Cand.Path, Settings); // didOpen + warm
          OpenedFiles.Add(Cand.Path.ToLower, True);
          Inc(FilesOpened);
        end;
        Resp := Client.Definition(TLspClient.PathToUri(Cand.Path),
          Cand.Line, Cand.Col + 1);
        try
          if DefinitionLocation(Resp, CandUri, CandLine) and
             SameText(CandUri, TargetUri) and (CandLine = TargetLine) then
            Confirmed.Add(CandidateJson(Cand))
          else if CandUri = '' then
            Unverified.Add(CandidateJson(Cand))
          else
            Inc(Rejected);
        finally
          Resp.Free;
        end;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('identifier', Ident);
      Entry := TJSONObject.Create;
      Result.AddPair('definition', Entry);
      Entry.AddPair('path', TLspClient.UriToPath(TargetUri));
      Entry.AddPair('line', TJSONNumber.Create(TargetLine));
      Result.AddPair('confirmed', Confirmed);
      Result.AddPair('unverified', Unverified);
      Result.AddPair('rejectedHomonyms', TJSONNumber.Create(Rejected));
      Result.AddPair('filesScanned', TJSONNumber.Create(Scanned));
      Result.AddPair('candidates', TJSONNumber.Create(Candidates.Count));
    finally
      OpenedFiles.Free;
    end;
  finally
    Candidates.Free;
    AllFiles.Free;
  end;
end;

end.
