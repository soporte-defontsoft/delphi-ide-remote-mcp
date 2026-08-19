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

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Lsp.Client,
  Lsp.Session;

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

function SkipPath(const APath: string): Boolean;
const
  Bad: array [0 .. 7] of string = ('\__history\', '\__recovery\', '\win32\',
    '\win64\', '\debug\', '\release\', '\dcu\', '\.git\');
var
  B, Low: string;
begin
  Low := APath.ToLower;
  for B in Bad do
    if Low.Contains(B) then
      Exit(True);
  Result := False;
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
    for Ext in TArray<string>.Create('*.pas', '*.dpr', '*.inc') do
      for F in TDirectory.GetFiles(RootDir, Ext, TSearchOption.soAllDirectories) do
        if not SkipPath(F) then
          AllFiles.Add(F);
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
