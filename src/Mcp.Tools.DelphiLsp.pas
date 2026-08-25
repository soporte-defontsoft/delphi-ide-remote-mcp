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
  System.Math,
  System.RegularExpressions,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Defaults,
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
  Text, Enc, L, Cur, Owner: string;
  Lines: TArray<string>;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, J, Kept, Depth: Integer;

  // How many '(' are still open in AText.
  function Unbalanced(const AText: string): Integer;
  var
    C: Char;
  begin
    Result := 0;
    for C in AText do
      if C = '(' then
        Inc(Result)
      else if C = ')' then
        Dec(Result);
    if Result < 0 then
      Result := 0;
  end;

  // A declaration can span several lines; the reader needs the WHOLE thing.
  // "function Alta(const A, B: string; C: Integer;" told nobody what it
  // returns or that the last parameter has a default (field round 12).
  function WholeStatement(var AIdx: Integer): string;
  var
    K: Integer;
  begin
    Result := Lines[AIdx].Trim;
    K := AIdx;
    // A class/record/interface header OPENS a block; it is not an unfinished
    // statement, and joining what comes after it glued the first field onto
    // the class line (caught the same day it was written).
    if TRegEx.IsMatch(Result,
      '(?i)^[A-Za-z_]\w*[ ]*=[ ]*(packed[ ]+)?(class|record|interface)\b') and
       not Result.EndsWith(';') then
      Exit;
    // A ';' INSIDE a parameter list is a separator, not the end of anything:
    // "function Alta(const A, B: string; C: Integer;" looks finished and is
    // not, so the return type and the default value were being dropped -
    // exactly the signature somebody had to respect (field round 12). Count
    // the brackets: the statement ends at a ';' with none open.
    while (K < High(Lines)) and (K - AIdx < 8) and
          (not Result.EndsWith(';') or (Unbalanced(Result) > 0)) and
          not Result.EndsWith('=') do
    begin
      Inc(K);
      if Lines[K].Trim = '' then
        Break;
      Result := Result + ' ' + Lines[K].Trim;
    end;
    AIdx := K;
  end;

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
  Cur := '';
  Owner := '';
  Depth := 0;
  Kept := 0;
  I := 0;
  while I <= High(Lines) do
  begin
    L := Lines[I].Trim;
    if TRegEx.IsMatch(L, '(?i)^interface[ ]*$') then
    begin
      Cur := 'interface';
      Inc(I);
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^implementation[ ]*$') then
      Break;
    if Cur <> 'interface' then
    begin
      Inc(I);
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^uses\b') then
    begin
      J := I;
      Result.AddPair('uses', WholeStatement(J).Substring(4).Replace(';', '').Trim);
      I := J + 1;
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^(type|const|var|resourcestring)[ ]*$') then
    begin
      Inc(I);
      Continue;
    end;
    // which class we are inside, and where it ends: a flat list left the
    // reader guessing which member belonged to which class, and hid the
    // private fields entirely - one of them being the subject of a refactor.
    if TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*=[ ]*(class|record|interface)\b') then
    begin
      Owner := L.Split(['='])[0].Trim;
      Depth := 1;
    end
    else if (Owner <> '') and TRegEx.IsMatch(L, '(?i)^end;') then
    begin
      Owner := '';
      Depth := 0;
    end;
    J := I;
    if TRegEx.IsMatch(L, '(?i)^(class[ ]+)?(function|procedure|constructor|destructor|property)\b') or
       TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*=[ ]*(class|record|interface|packed|\()') or
       TRegEx.IsMatch(L, '(?i)^[A-Za-z_]\w*[ ]*=[ ]*') or
       ((Depth > 0) and TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*:[ ]*[A-Za-z_]')) then
    begin
      Inc(Kept);
      if Arr.Count < 300 then
      begin
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('decl', WholeStatement(J));
        if (Owner <> '') and not L.StartsWith(Owner) then
          Obj.AddPair('of', Owner);
        Obj.AddPair('line', TJSONNumber.Create(I + 1));
      end
      else
        J := I;
    end;
    if J > I then
      I := J;
    Inc(I);
  end;
  Result.AddPair('total', TJSONNumber.Create(Kept));
  if Kept > Arr.Count then
    Result.AddPair('truncated', TJSONBool.Create(True));
end;

function TDelphiSymbolsTool.ExecuteWithParams(const Params: TDelphiFileParams): string;
var
  Client: TLspClient;
  Settings, Folder: string;
begin
  // A FOLDER means "what is in here", answered from the interface sections of
  // every unit at once: the question somebody arriving at unfamiliar code
  // actually has, and it used to cost one call per file.
  // "...\dev4\" is the same folder as "...\dev4": answering "no es un fuente
  // Delphi ()" - with an empty extension - for a trailing separator cost a
  // call and read as "folders are not supported", which is the opposite of
  // what this now does (field round 12).
  Folder := ExcludeTrailingPathDelimiter(Params.Path.Trim);
  if TDirectory.Exists(Folder) then
  begin
    Result := ReadPathDenied(Folder);
    if Result <> '' then
      Exit;
    var Ret := TJSONObject.Create;
    try
      var Units := TJSONArray.Create;
      Ret.AddPair('folder', Folder);
      Ret.AddPair('units', Units);
      var N := 0;
      for var F in TDirectory.GetFiles(Folder, '*.pas',
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
  // The JAIL first, and the same refusal whether the file is there or not.
  // Checking existence first told a caller which Delphi files exist anywhere
  // on the disk: "outside the workspaces" for one that is there, "does not
  // exist" for one that is not - a map of the machine, one call at a time
  // (measured 2026-08-25). delphi_read has always answered the same either
  // way; this now does too.
  Result := ReadPathDenied(Params.Path);
  if Result = '' then
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
  Settings, AdjNote: string;
  Resp, Return, ItemObj: TJSONObject;
  Items, OutItems: TJSONArray;
  I, EffChar: Integer;
begin
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);

  // Member completion happens AFTER the dot, and "after ServicioEventos." is
  // the column past the dot, not the last letter of the name. An agent that
  // cannot see the cursor lands a column or two short and gets the whole global
  // scope (5157 symbols) with no hint it aimed at the wrong place - measured
  // 2026-08-25 by a frontier agent dogfooding a real FMX form. When the caller
  // says trigger='.', snap the position to just past the nearest dot and say so.
  EffChar := Params.Character;
  AdjNote := '';
  if Params.Trigger = '.' then
  begin
    var Enc: string;
    var Lines := PatchLoadText(Params.Path, Enc).Replace(#13#10, #10).Split([#10]);
    if (Params.Line >= 0) and (Params.Line <= High(Lines)) then
    begin
      var LineTxt := Lines[Params.Line];
      // already just after a dot? (char before the 0-based cursor is '.')
      var AfterDot := (EffChar >= 1) and (EffChar <= Length(LineTxt)) and
        (LineTxt[EffChar] = '.');
      if not AfterDot then
      begin
        var Best := -1;
        for var K := Max(1, EffChar - 3) to Min(Length(LineTxt), EffChar + 2) do
          if (LineTxt[K] = '.') and
             ((Best < 0) or (Abs(K - EffChar) < Abs(Best - EffChar))) then
            Best := K;
        if (Best >= 1) and (Best <> EffChar) then
        begin
          AdjNote := Format(SN_COMPLETION_SNAPPED_FMT, [Params.Character, Best]);
          EffChar := Best; // 0-based col past the dot = 1-based index of the dot
        end;
      end;
    end;
  end;

  Resp := Client.Completion(TLspClient.PathToUri(Params.Path), Params.Line,
    EffChar, Params.Trigger);
  try
    Items := Resp.FindValue('result.items') as TJSONArray;
    if Items = nil then
      Exit(RenderResult(Resp.Clone as TJSONObject, NoSettingsNote(Settings)));

    // Order by the LSP sortText (then label): DelphiLSP marks the relevant
    // candidates to sort first, and slicing the top 50 in raw order buried them.
    var Order := TList<Integer>.Create;
    try
      for I := 0 to Items.Count - 1 do Order.Add(I);
      Order.Sort(TComparer<Integer>.Construct(
        function(const L, R: Integer): Integer
        var LO, RO: TJSONObject; LS, RS: TJSONValue; LK, RK: string;
        begin
          LO := Items.Items[L] as TJSONObject; RO := Items.Items[R] as TJSONObject;
          LS := LO.GetValue('sortText'); if LS = nil then LS := LO.GetValue('label');
          RS := RO.GetValue('sortText'); if RS = nil then RS := RO.GetValue('label');
          LK := ''; if LS <> nil then LK := LS.Value;
          RK := ''; if RS <> nil then RK := RS.Value;
          Result := CompareStr(LK, RK);
          if Result = 0 then Result := CompareText(
            LO.GetValue('label').Value, RO.GetValue('label').Value);
        end));

    Return := TJSONObject.Create;
    try
      Return.AddPair('total', TJSONNumber.Create(Items.Count));
      if AdjNote <> '' then
        Return.AddPair('positionNote', AdjNote);
      OutItems := TJSONArray.Create;
      Return.AddPair('items', OutItems);
      for I := 0 to Items.Count - 1 do
      begin
        if I >= MAX_COMPLETION_ITEMS then
          Break;
        var Src := Items.Items[Order[I]] as TJSONObject;
        ItemObj := TJSONObject.Create;
        OutItems.Add(ItemObj);
        ItemObj.AddPair('label', Src.GetValue('label').Value);
        var Kind := Src.GetValue('kind');
        if Kind <> nil then
          ItemObj.AddPair('kind', Kind.Clone as TJSONValue);
        var Detail := Src.GetValue('detail');
        if (Detail <> nil) and (Detail.Value <> '') then
          ItemObj.AddPair('detail', Detail.Value);
      end;
      Result := Return.ToJSON + NoSettingsNote(Settings);
    finally
      Return.Free;
    end;
    finally
      Order.Free;
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
