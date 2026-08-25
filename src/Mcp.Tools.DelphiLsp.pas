unit Mcp.Tools.DelphiLsp;

{ MCP tools backed by DelphiLSP: delphi_symbols, delphi_definition,
  delphi_hover, delphi_completion. All positions are 0-based (LSP style).
  Property names surface lowercased in the JSON schema (path, line, ...). }

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts: attributes live in the interface
  Lsp.Client,
  Lsp.Session;

type
  TDelphiFileParams = class
  private
    FPath: string;
  public
    [SchemaDescription(SP_SYMBOLS_PATH)]
    [Required]
    property Path: string read FPath write FPath;
  end;

  TDelphiPositionParams = class(TDelphiFileParams)
  private
    FLine: Integer;
    FCharacter: Integer;
  public
    [SchemaDescription('Zero-based line number of the identifier')]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription('Zero-based character (column) inside the identifier')]
    [Required]
    property Character: Integer read FCharacter write FCharacter;
  end;

  TDelphiCompletionParams = class(TDelphiPositionParams)
  private
    FTrigger: string;
  public
    [SchemaDescription('Optional trigger character, e.g. "." (empty = manual invocation)')]
    property Trigger: string read FTrigger write FTrigger;
  end;

  TDelphiDefinitionParams = class(TDelphiPositionParams)
  private
    FKind: string;
  public
    [SchemaDescription('Optional: definition (default) | declaration (jump to the interface declaration) | implementation (jump to the method body)')]
    property Kind: string read FKind write FKind;
  end;

  TDelphiSymbolsTool = class(TMCPToolBase<TDelphiFileParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiFileParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiDefinitionTool = class(TMCPToolBase<TDelphiDefinitionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDefinitionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiSignatureTool = class(TMCPToolBase<TDelphiPositionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPositionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiHoverTool = class(TMCPToolBase<TDelphiPositionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPositionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiCompletionTool = class(TMCPToolBase<TDelphiCompletionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiCompletionParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.RegularExpressions,
  System.StrUtils,
  System.IOUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.References,
  Lsp.Patch;

const
  MAX_COMPLETION_ITEMS = 50;

type
  TLoc = record
    Uri: string;
    Line, Ch: Integer;
  end;

{ Pulls the first Location (or LocationLink) out of a textDocument/* result,
  which DelphiLSP returns either as a single object OR as a one-item array
  (measured: definition answers a bare object). False = nothing usable. }
function ParseLoc(AResult: TJSONValue; out ALoc: TLoc): Boolean;
var
  Obj, Rng, St: TJSONValue;
begin
  ALoc.Uri := '';
  ALoc.Line := -1;
  ALoc.Ch := 0;
  Result := False;
  Obj := AResult;
  if Obj is TJSONArray then
  begin
    if TJSONArray(Obj).Count = 0 then
      Exit;
    Obj := TJSONArray(Obj).Items[0];
  end;
  if not (Obj is TJSONObject) then
    Exit;
  if not TJSONObject(Obj).TryGetValue<string>('uri', ALoc.Uri) then
    TJSONObject(Obj).TryGetValue<string>('targetUri', ALoc.Uri);
  Rng := TJSONObject(Obj).GetValue('range');
  if Rng = nil then
    Rng := TJSONObject(Obj).GetValue('targetSelectionRange');
  if Rng = nil then
    Rng := TJSONObject(Obj).GetValue('targetRange');
  if Rng is TJSONObject then
  begin
    St := TJSONObject(Rng).GetValue('start');
    if St is TJSONObject then
    begin
      TJSONObject(St).TryGetValue<Integer>('line', ALoc.Line);
      TJSONObject(St).TryGetValue<Integer>('character', ALoc.Ch);
    end;
  end;
  Result := (ALoc.Uri <> '') and (ALoc.Line >= 0);
end;

{ 0-based column of the routine name on a header line ("procedure
  TClass.Name(...)" -> the column of Name). DelphiLSP's definition range
  starts at column 0 (the keyword), so to chain a second lookup we must aim
  at the identifier ourselves. Falls back to the first identifier. }
function RoutineIdentCol(const APath: string; ALine: Integer): Integer;
var
  Enc, L: string;
  Lines: TArray<string>;
  M: TMatch;
begin
  Result := 0;
  try
    L := PatchLoadText(APath, Enc);
  except
    Exit;
  end;
  Lines := L.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  L := Lines[ALine];
  M := TRegEx.Match(L, '^\s*(?:procedure|function|constructor|destructor|property)\s+(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)', [roIgnoreCase]);
  if M.Success then
    Result := M.Groups[1].Index - 1 // TMatch is 1-based; LSP columns 0-based
  else
  begin
    M := TRegEx.Match(L, '[A-Za-z_]\w*');
    if M.Success then
      Result := M.Groups[0].Index - 1;
  end;
end;

{ Shared helpers }

function NoSettingsNote(const ASettings: string): string;
begin
  if ASettings = '' then
    Result := ' [warning: no .delphilsp.json project settings found for this ' +
      'file - semantic answers may be null. Generate one in the IDE ' +
      '(Code Insight > Generate LSP config + Reload LSP Server).]'
  else
    Result := '';
end;

{ Every object carrying a "uri" also gets the path in the format the rest of
  this server speaks, and the 1-based line next to the LSP 0-based one.
  Field 2026-08-25: definition was the ONE tool answering
  file:///srvd%3A/... with forward slashes, so an agent had to un-escape and
  re-slash by hand before it could chain the next call; and hover printed
  1-based lines while definition printed 0-based ones, in the same session. }
procedure DecorateLocations(V: TJSONValue);
var
  Obj: TJSONObject;
  Pair: TJSONPair;
  Item: TJSONValue;
  Rng, Start: TJSONObject;
  L: TJSONValue;
begin
  if V is TJSONArray then
  begin
    for Item in TJSONArray(V) do
      DecorateLocations(Item);
    Exit;
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  if (Obj.GetValue('uri') <> nil) and (Obj.GetValue('path') = nil) then
  begin
    Obj.AddPair('path', TLspClient.UriToPath(Obj.GetValue('uri').Value));
    Rng := Obj.GetValue('range') as TJSONObject;
    if Rng <> nil then
    begin
      Start := Rng.GetValue('start') as TJSONObject;
      if Start <> nil then
      begin
        L := Start.GetValue('line');
        if L <> nil then
          Obj.AddPair('line1', TJSONNumber.Create(L.GetValue<Integer> + 1));
      end;
    end;
  end;
  for Pair in Obj do
    DecorateLocations(Pair.JsonValue);
end;

{ Extracts "result" from a full JSON-RPC response and renders it, adding a
  filesystem path next to any "uri" for agent convenience. Frees AResp. }
function RenderResult(AResp: TJSONObject; const ANote: string): string;
var
  V: TJSONValue;
  Err: TJSONValue;
begin
  try
    Err := AResp.GetValue('error');
    if Err <> nil then
      Exit('LSP error: ' + Err.ToJSON + ANote);
    V := AResp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit('null' + ANote);
    DecorateLocations(V);
    Result := V.ToJSON + ANote;
  finally
    AResp.Free;
  end;
end;

{ TDelphiSymbolsTool }

constructor TDelphiSymbolsTool.Create;
begin
  inherited;
  FName := 'delphi_symbols';
  FDescription := 'Document symbol tree of a Delphi unit (classes, methods, ' +
    'properties, sections) with 0-based ranges, straight from the official ' +
    'DelphiLSP engine. Works even without project settings.';
end;

{ A position nobody could point at. delphi_references said "Line 9999 out of
  range"; hover answered `null [hint: hover only answers on usages]` and
  definition answered a bare `null` - two canned answers that hid a typo and
  sent the reader looking for the wrong thing (measured 2026-08-25). '' when
  the position is real. }
function PositionOutOfRange(const APath: string; ALine, AChar: Integer): string;
var
  Lines: TArray<string>;
  Enc: string;
begin
  Result := '';
  if (ALine < 0) or (AChar < 0) then
    Exit(Format(SR_LSP_NEGATIVE_FMT, [ALine, AChar]));
  // A path that is not there reached the language server and came back as
  // "Error executing tool: File not found", which this server's own rules
  // define as an internal failure worth reporting as a bug (2026-08-25).
  if not TFile.Exists(APath) then
    Exit(Format(SR_LSP_NO_FILE_FMT, [APath]));
  try
    Lines := PatchLoadText(APath, Enc).Replace(#13#10, #10).Split([#10]);
  except
    Exit;
  end;
  if ALine >= Length(Lines) then
    Exit(Format(SR_LSP_LINE_RANGE_FMT,
      [ALine, TPath.GetFileName(APath), Length(Lines), Length(Lines) - 1]))
  else if AChar > Length(Lines[ALine]) then
    Exit(Format(SR_LSP_CHAR_RANGE_FMT,
      [AChar, ALine, Length(Lines[ALine]), Lines[ALine].Trim]));
end;

{ Whether this is a file DelphiLSP can say anything about at all. Answering
  `[]` for a .txt reads as "this unit has no symbols" (measured 2026-08-25). }
function NotDelphiSource(const APath: string): string;
begin
  Result := '';
  if not MatchText(TPath.GetExtension(APath), ['.pas', '.dpr', '.dpk', '.inc']) then
    Result := Format(SR_LSP_NOT_SOURCE_FMT,
      [TPath.GetFileName(APath), TPath.GetExtension(APath)]);
end;

{ What a unit OFFERS, from its interface section alone: the declarations a
  caller can use, without a single body. Read as text, no language server
  involved - it has to stay cheap enough to run over a whole folder.

  Why: orienting yourself in somebody else's code cost one delphi_read per
  file, and 90% of what you need is in the interface sections (measured
  2026-08-25, a maintenance job on another agent's project: 12 calls to get
  the picture, 7 of them reads). }
function InterfaceDigest(const APath: string): TJSONObject;
var
  Text, Enc, L, Section: string;
  Lines: TArray<string>;
  Arr: TJSONArray;
  I, Kept: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('unit', TPath.GetFileNameWithoutExtension(APath));
  Result.AddPair('path', APath);
  try
    Text := PatchLoadText(APath, Enc);
  except
    Result.AddPair('error', 'no se puede leer');
    Exit;
  end;
  Lines := Text.Replace(#13#10, #10).Split([#10]);
  Arr := TJSONArray.Create;
  Result.AddPair('declares', Arr);
  Section := '';
  Kept := 0;
  for I := 0 to High(Lines) do
  begin
    L := Lines[I].Trim;
    if TRegEx.IsMatch(L, '(?i)^interface\s*$') then
    begin
      Section := 'interface';
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^implementation\s*$') then
      Break;
    if Section <> 'interface' then
      Continue;
    // uses clause of the interface: the unit's own dependencies, worth one line
    if TRegEx.IsMatch(L, '(?i)^uses\b') then
    begin
      var U := L;
      var J := I;
      while (J < High(Lines)) and not U.Contains(';') do
      begin
        Inc(J);
        U := U + ' ' + Lines[J].Trim;
      end;
      Result.AddPair('uses', U.Substring(4).Replace(';', '').Trim);
      Continue;
    end;
    // what a reader is looking for: types, routines, constants
    if TRegEx.IsMatch(L, '(?i)^(type|const|var|resourcestring)\s*$') then
      Continue;
    if TRegEx.IsMatch(L,
      '(?i)^(class\s+)?(function|procedure|constructor|destructor|property)\b') or
       TRegEx.IsMatch(L, '^[A-Za-z_]\w*\s*=\s*(class|record|interface|packed|\()') or
       TRegEx.IsMatch(L, '(?i)^[A-Za-z_]\w*\s*=\s*(type\s+)?[A-Za-z_][\w.<>, ]*;\s*(//.*)?$') then
    begin
      Inc(Kept);
      if Arr.Count < 200 then
        Arr.Add(L);
    end;
  end;
  Result.AddPair('total', TJSONNumber.Create(Kept));
  if Kept > Arr.Count then
    Result.AddPair('truncated', TJSONBool.Create(True));
end;

function TDelphiSymbolsTool.ExecuteWithParams(const Params: TDelphiFileParams): string;
var
  Client: TLspClient;
  Settings: string;
begin
  // A FOLDER means "what is in here", answered from the interface sections of
  // every unit at once: the question somebody arriving at unfamiliar code
  // actually has, and it used to cost one call per file.
  if TDirectory.Exists(Params.Path) then
  begin
    Result := ReadPathDenied(Params.Path);
    if Result <> '' then
      Exit;
    var Ret := TJSONObject.Create;
    try
      var Units := TJSONArray.Create;
      Ret.AddPair('folder', Params.Path);
      Ret.AddPair('units', Units);
      var N := 0;
      for var F in TDirectory.GetFiles(Params.Path, '*.pas',
        TSearchOption.soAllDirectories) do
      begin
        if SkipIdeArtifacts(F) then
          Continue;
        Inc(N);
        if Units.Count < 60 then
          Units.AddElement(InterfaceDigest(F));
      end;
      Ret.AddPair('total', TJSONNumber.Create(N));
      if N > Units.Count then
        Ret.AddPair('truncated', TJSONBool.Create(True));
      Ret.AddPair('note', SN_SYMBOLS_DIGEST_NOTE);
      Exit(Ret.ToJSON);
    finally
      Ret.Free;
    end;
  end;
  Result := NotDelphiSource(Params.Path);
  if (Result = '') and not TFile.Exists(Params.Path) then
    Result := Format(SR_LSP_NO_FILE_FMT, [Params.Path]);
  if Result <> '' then
    Exit;
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Result := RenderResult(
    Client.DocumentSymbols(TLspClient.PathToUri(Params.Path)),
    NoSettingsNote(Settings));
end;

{ TDelphiDefinitionTool }

constructor TDelphiDefinitionTool.Create;
begin
  inherited;
  FName := 'delphi_definition';
  FDescription := 'Resolve the identifier at a 0-based line:character ' +
    'position in a Delphi source file, using the official DelphiLSP engine ' +
    '(compiler-grade, cross-unit, including RTL/VCL sources). Point INSIDE ' +
    'the identifier. kind selects the half of the unit (a Delphi method ' +
    'exists in BOTH): definition (default) = the BODY in the ' +
    'implementation section; declaration = the interface declaration OF THE ' +
    'TARGET SYMBOL (on a call site the tool chains definition->declaration, ' +
    'so you get the callee, never the enclosing method). ' +
    '(kind=implementation is accepted but DelphiLSP answers it like ' +
    'declaration - measured.) Requires project settings for full answers.';
end;

function TDelphiDefinitionTool.ExecuteWithParams(const Params: TDelphiDefinitionParams): string;
var
  Client: TLspClient;
  Settings, Kind: string;
  Resp: TJSONObject;
begin
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Kind := Params.Kind.Trim.ToLower;
  if (Kind <> '') and (Kind <> 'definition') and (Kind <> 'declaration') and
     (Kind <> 'implementation') then
    Exit('RECHAZADO: kind debe ser definition | declaration | implementation.');
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  if Kind = 'declaration' then
  begin
    // Measured (field rounds 2-3, B5): declaration straight on a CALL SITE
    // answers with the ENCLOSING method's declaration, not the target's, and
    // definition answers a bare Location object with column 0. Chain: run
    // definition (correct at a call site) to reach the body, then declaration
    // AT the body's identifier column to reach the interface declaration.
    var DefResp := Client.Definition(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
    var DefLoc: TLoc;
    if ParseLoc(DefResp.GetValue('result'), DefLoc) then
    begin
      var TgtPath := TLspClient.UriToPath(DefLoc.Uri);
      var Col := RoutineIdentCol(TgtPath, DefLoc.Line);
      var C2 := TLspSession.Instance.AcquireFor(TgtPath, Settings);
      var DeclResp := C2.Declaration(DefLoc.Uri, DefLoc.Line, Col);
      var DeclLoc: TLoc;
      if ParseLoc(DeclResp.GetValue('result'), DeclLoc) and
         not ((DeclLoc.Line = DefLoc.Line) and SameText(DeclLoc.Uri, DefLoc.Uri)) then
      begin
        // declaration moved elsewhere = the interface declaration we want
        DefResp.Free;
        Resp := DeclResp;
      end
      else
      begin
        // declaration stayed on the body (or failed): return the body - far
        // more useful than the enclosing-scope answer of a direct call
        DeclResp.Free;
        Resp := DefResp;
      end;
    end
    else
    begin
      // no definition to chain from: fall back to a direct declaration
      DefResp.Free;
      Resp := Client.Declaration(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
    end;
  end
  else if Kind = 'implementation' then
    Resp := Client.Implementation_(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character)
  else
    Resp := Client.Definition(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
  Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiSignatureTool }

constructor TDelphiSignatureTool.Create;
begin
  inherited;
  FName := 'delphi_signature';
  FDescription := 'Signature help (parameter completion) for the call under ' +
    'a 0-based line:character position: the routine signatures with their ' +
    'parameter list, from the official DelphiLSP engine - the IDE''s ' +
    'Ctrl+Shift+Space. Point INSIDE the parentheses of the call (right ' +
    'after "(" or a ","). Requires project settings for full answers.';
end;

function TDelphiSignatureTool.ExecuteWithParams(const Params: TDelphiPositionParams): string;
var
  Client: TLspClient;
  Settings: string;
  Resp: TJSONObject;
  V: TJSONValue;
begin
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Resp := Client.SignatureHelp(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
  V := Resp.GetValue('result');
  if (V = nil) or (V is TJSONNull) then
    Result := RenderResult(Resp, NoSettingsNote(Settings) +
      ' [hint: the position must be INSIDE the call parentheses, right after ( or ,]')
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiHoverTool }

constructor TDelphiHoverTool.Create;
begin
  inherited;
  FName := 'delphi_hover';
  FDescription := 'Type/signature information for the identifier at a 0-based ' +
    'line:character position (official DelphiLSP engine). IMPORTANT: hover ' +
    'answers on identifier USAGES (call sites, type references); hovering a ' +
    'declaration itself returns null. Requires project settings for full answers.';
end;

function TDelphiHoverTool.ExecuteWithParams(const Params: TDelphiPositionParams): string;
var
  Client: TLspClient;
  Settings: string;
  Resp: TJSONObject;
  V: TJSONValue;
begin
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Resp := Client.Hover(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
  // Prefer the markdown payload alone: it is what an agent wants to read.
  V := Resp.FindValue('result.contents.value');
  if V <> nil then
  begin
    Result := V.Value + NoSettingsNote(Settings);
    Resp.Free;
  end
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings) +
      ' [hint: hover only answers on usages, not on declarations]');
end;

{ TDelphiCompletionTool }

constructor TDelphiCompletionTool.Create;
begin
  inherited;
  FName := 'delphi_completion';
  FDescription := 'Code completion candidates at a 0-based line:character ' +
    'position (official DelphiLSP engine). Returns at most 50 items ' +
    '(label/kind/detail) plus the total count.';
end;

function TDelphiCompletionTool.ExecuteWithParams(const Params: TDelphiCompletionParams): string;
var
  Client: TLspClient;
  Settings: string;
  Resp, Return, ItemObj: TJSONObject;
  Items, OutItems: TJSONArray;
  I: Integer;
begin
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Resp := Client.Completion(TLspClient.PathToUri(Params.Path), Params.Line,
    Params.Character, Params.Trigger);
  try
    Items := Resp.FindValue('result.items') as TJSONArray;
    if Items = nil then
      Exit(RenderResult(Resp.Clone as TJSONObject, NoSettingsNote(Settings)));

    Return := TJSONObject.Create;
    try
      Return.AddPair('total', TJSONNumber.Create(Items.Count));
      OutItems := TJSONArray.Create;
      Return.AddPair('items', OutItems);
      for I := 0 to Items.Count - 1 do
      begin
        if I >= MAX_COMPLETION_ITEMS then
          Break;
        ItemObj := TJSONObject.Create;
        OutItems.Add(ItemObj);
        ItemObj.AddPair('label', (Items.Items[I] as TJSONObject).GetValue('label').Value);
        var Kind := (Items.Items[I] as TJSONObject).GetValue('kind');
        if Kind <> nil then
          ItemObj.AddPair('kind', Kind.Clone as TJSONValue);
        var Detail := (Items.Items[I] as TJSONObject).GetValue('detail');
        if (Detail <> nil) and (Detail.Value <> '') then
          ItemObj.AddPair('detail', Detail.Value);
      end;
      Result := Return.ToJSON + NoSettingsNote(Settings);
    finally
      Return.Free;
    end;
  finally
    Resp.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_symbols',
    function: IMCPTool begin Result := TDelphiSymbolsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_definition',
    function: IMCPTool begin Result := TDelphiDefinitionTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_hover',
    function: IMCPTool begin Result := TDelphiHoverTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_completion',
    function: IMCPTool begin Result := TDelphiCompletionTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_signature',
    function: IMCPTool begin Result := TDelphiSignatureTool.Create; end);

end.
