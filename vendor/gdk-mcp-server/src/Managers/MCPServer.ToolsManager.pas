unit MCPServer.ToolsManager;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.Generics.Collections,
  MCPServer.Types,
  MCPServer.Logger,
  MCPServer.Tool.Base;

type
  // [local change] optional gate consulted before ANY tool executes.
  // Returns '' to allow, or the message returned to the client instead of
  // running the tool (access control lives host-side, in one single place).
  TToolGateFunc = reference to function(const ToolName: string;
    const Arguments: TJSONObject): string;

  // [local change] optional filter applied to every TEXTUAL tool result and
  // to gate denials, so the host can rewrite server-specific data (e.g.
  // virtual drive units) in one single place.
  TToolResultFilter = reference to function(const ToolName: string;
    const AText: string): string;

  TMCPToolsManager = class(TInterfacedObject, IMCPCapabilityManager)
  strict private
    function ExtractToolNameAndArguments(const Params: System.JSON.TJSONObject; out ToolName: string; out Arguments: TJSONObject): Boolean;
    function ExecuteTool(const Tool: IMCPTool; const Arguments: TJSONObject): TValue;
    function BuildToolCallResponse(const ResultValue: TValue): TJSONObject;
    function BuildToolListResponse: TJSONObject;
    function CreateToolJSON(const Tool: IMCPTool): TJSONObject;
  private
    FTools: TDictionary<string, IMCPTool>;
    procedure RegisterTool(const Tool: IMCPTool);
    procedure RegisterBuiltInTools;
  public
    constructor Create;
    destructor Destroy; override;
    
    function GetCapabilityName: string;
    function HandlesMethod(const Method: string): Boolean;
    function ExecuteMethod(const Method: string; const Params: System.JSON.TJSONObject): TValue;
    
    function ListTools: TValue;
    function CallTool(const Params: System.JSON.TJSONObject): TValue;

    // [local change] single entry gate for every tools/call (see TToolGateFunc)
    class var ToolGate: TToolGateFunc;
    // [local change] outbound filter for every textual result (see TToolResultFilter)
    class var ResultFilter: TToolResultFilter;
  end;

implementation

uses
  MCPServer.Registration;

{ TMCPToolsManager }

constructor TMCPToolsManager.Create;
begin
  inherited;
  FTools := TDictionary<string, IMCPTool>.Create;
  RegisterBuiltInTools;
end;

destructor TMCPToolsManager.Destroy;
begin
  FTools.Free;
  inherited;
end;

function TMCPToolsManager.GetCapabilityName: string;
begin
  Result := 'tools';
end;

function TMCPToolsManager.HandlesMethod(const Method: string): Boolean;
begin
  Result := (Method = 'tools/list') or (Method = 'tools/call');
end;

function TMCPToolsManager.ExecuteMethod(const Method: string; const Params: System.JSON.TJSONObject): TValue;
begin
  if Method = 'tools/list' then
    Result := ListTools
  else if Method = 'tools/call' then
    Result := CallTool(Params)
  else
    raise Exception.CreateFmt('Method %s not handled by %s', [Method, GetCapabilityName]);
end;

procedure TMCPToolsManager.RegisterTool(const Tool: IMCPTool);
begin
  FTools.Add(Tool.Name, Tool);
end;

procedure TMCPToolsManager.RegisterBuiltInTools;
var
  Tool: IMCPTool;
  ToolName: string;
begin
  for ToolName in TMCPRegistry.GetToolNames do
  begin
    Tool := TMCPRegistry.CreateTool(ToolName);
    RegisterTool(Tool);
  end;
end;

function TMCPToolsManager.ExtractToolNameAndArguments(const Params: System.JSON.TJSONObject; out ToolName: string; out Arguments: TJSONObject): Boolean;
var
  ArgsValue: TJSONValue;
  NameValue: TJSONValue;
begin
  Result := False;
  ToolName := '';
  Arguments := nil;
  
  if not Assigned(Params) then
    Exit;
    
  NameValue := Params.GetValue('name');
  if Assigned(NameValue) then
  begin
    ToolName := NameValue.Value;
    Result := ToolName <> '';
  end;
  
  ArgsValue := Params.GetValue('arguments');
  if Assigned(ArgsValue) and (ArgsValue is TJSONObject) then
    Arguments := ArgsValue as TJSONObject;
end;

function TMCPToolsManager.ExecuteTool(const Tool: IMCPTool; const Arguments: TJSONObject): TValue;
var
  Args, Owned: TJSONObject; // [local change]
begin
  // [local change] The MCP spec marks "arguments" as optional, but an absent
  // or malformed value (array, string...) reached Tool.Execute as nil and
  // the parameter binder dereferenced it - an access violation on ANY tool,
  // measured with {"arguments":[]}. Normalize to an empty object here, the
  // single choke point, so every tool sees valid JSON and its parameter
  // defaults apply.
  Owned := nil;
  Args := Arguments;
  if not Assigned(Args) then
  begin
    Owned := TJSONObject.Create;
    Args := Owned;
  end;
  try
    try
      Result := Tool.Execute(Args);
    except
      // [local change] "Error executing tool:" is this server's word for "I
      // broke inside", and its own conventions tell agents to report one as a
      // bug. Argument validation is not that: a misspelled parameter is the
      // caller's, and dressing it as an internal failure sent agents chasing
      // ghosts (measured 2026-08-25). EArgumentException is the deserializer
      // saying the call was wrong, so it goes out as a plain refusal.
      on E: EArgumentException do
        Result := 'error: ' + E.Message;
      on E: Exception do
        Result := 'Error executing tool: ' + E.Message;
    end;
  finally
    Owned.Free;
  end;
end;

function TMCPToolsManager.BuildToolCallResponse(const ResultValue: TValue): TJSONObject;
var
  ContentArray: TJSONArray;
  ContentItem: TJSONObject;
  ErrorValue: TJSONValue;
  HasError: Boolean;
  JsonResult: TJSONObject;
  TextValue: string;
begin
  Result := TJSONObject.Create;

  if ResultValue.IsType<TJSONArray> then
  begin
    // The tool already produced a content array (e.g. text plus an image item);
    // take ownership so it is passed through verbatim and freed with the
    // response (no clone, no leak of the original array).
    Result.AddPair('content', ResultValue.AsType<TJSONArray>);
  end
  else if ResultValue.IsType<string> then
  begin
    TextValue := ResultValue.AsString;
    HasError := TextValue.StartsWith('Error:') or TextValue.StartsWith('Error executing tool:');

    ContentArray := TJSONArray.Create;
    Result.AddPair('content', ContentArray);

    ContentItem := TJSONObject.Create;
    ContentArray.AddElement(ContentItem);
    ContentItem.AddPair('type', 'text');
    ContentItem.AddPair('text', TextValue);

    // [local change] Programmatically distinguishable outcomes (hermes,
    // release audit 2026-08-26): the human text stays the contract verbatim,
    // but the result now ALSO carries structuredContent {ok, code} so a
    // client or a small model never has to parse Spanish prefixes.
    //   DENIED        refused by policy (jail, guard, ownership, read-only)
    //   NOT_FOUND     the named file/project/thing is not there
    //   INVALID_PARAM the call itself was wrong (bad command, bad value)
    //   INTERNAL      this server broke inside - worth a delphi_report
    // The jail's anti-probing property survives: outside-the-jail answers use
    // one fixed text whether the target exists or not, so they all map to
    // DENIED; NOT_FOUND only ever comes from in-jail "no existe" texts.
    var OutcomeCode := '';
    var LowText := TextValue.ToLower;
    if TextValue.StartsWith('RECHAZADO') then
    begin
      if LowText.Contains('no existe') then
        OutcomeCode := 'NOT_FOUND'
      else
        OutcomeCode := 'DENIED';
    end
    else if TextValue.StartsWith('error:') then
    begin
      if LowText.Contains('no existe') or LowText.Contains('not found') then
        OutcomeCode := 'NOT_FOUND'
      else
        OutcomeCode := 'INVALID_PARAM';
    end
    else if HasError or TextValue.StartsWith('LSP error:') then
      OutcomeCode := 'INTERNAL';
    var Structured := TJSONObject.Create;
    Result.AddPair('structuredContent', Structured);
    Structured.AddPair('ok', TJSONBool.Create(OutcomeCode = ''));
    if OutcomeCode <> '' then
    begin
      Structured.AddPair('code', OutcomeCode);
      HasError := True;
    end;

    if HasError then
{$IF COMPILERVERSION <= 29}
      Result.AddPair('isError', TJSONTrue.Create);
{$ELSE}
      Result.AddPair('isError', TJSONBool.Create(True));
{$ENDIF}
  end
  else if ResultValue.IsType<TJsonObject> then
  begin
    JsonResult := ResultValue.AsType<TJsonObject>;
    Result.AddPair('structuredContent', TJSONObject(JsonResult.Clone));

    ErrorValue := JsonResult.GetValue('error');
    HasError := Assigned(ErrorValue) and (ErrorValue.Value <> '');
    if HasError then
{$IF COMPILERVERSION <= 29}
      Result.AddPair('isError', TJSONTrue.Create);
{$ELSE}
      Result.AddPair('isError', TJSONBool.Create(True));
{$ENDIF}
  end;

end;

function TMCPToolsManager.CreateToolJSON(const Tool: IMCPTool): TJSONObject;
var
  Schema: TJSONObject;
  SchemaClone: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Tool.Name);
  if Tool.Title <> Tool.Name then
    Result.AddPair('title', Tool.Title);
  Result.AddPair('description', Tool.Description);

  Schema := Tool.InputSchema;
  if Assigned(Schema) then
  begin
    SchemaClone := TJSONObject.ParseJSONValue(Schema.ToJSON) as TJSONObject;
    Result.AddPair('inputSchema', SchemaClone);
    Schema.Free;
  end;
  Schema := Tool.OutputSchema;
  if Assigned(Schema) then
  begin
    SchemaClone := TJSONObject.ParseJSONValue(Schema.ToJSON) as TJSONObject;
    Result.AddPair('outputSchema', SchemaClone);
    Schema.Free;
  end;

end;

function TMCPToolsManager.BuildToolListResponse: TJSONObject;
var
  Tool: IMCPTool;
  ToolsArray: TJSONArray;
  ToolJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  ToolsArray := TJSONArray.Create;
  Result.AddPair('tools', ToolsArray);

  for Tool in FTools.Values do
  begin
    ToolJSON := CreateToolJSON(Tool);
    ToolsArray.AddElement(ToolJSON);
  end;
end;

function TMCPToolsManager.CallTool(const Params: System.JSON.TJSONObject): TValue;
var
  Arguments: TJSONObject;
  ResultValue: TValue;
  Tool: IMCPTool;
  ToolName: string;
begin
  if not ExtractToolNameAndArguments(Params, ToolName, Arguments) then
  begin
    Result := TValue.From<TJSONObject>(BuildToolCallResponse('Error: Invalid tool parameters'));
    Exit;
  end;

  TLogger.Info('MCP CallTool called for tool: ' + ToolName);

  // [local change] the host's access-control gate runs before ANY tool.
  if Assigned(ToolGate) then
  begin
    var GateMsg := ToolGate(ToolName, Arguments);
    if GateMsg <> '' then
    begin
      if Assigned(ResultFilter) then
        GateMsg := ResultFilter(ToolName, GateMsg);
      Exit(TValue.From<TJSONObject>(BuildToolCallResponse(GateMsg)));
    end;
  end;

  if FTools.TryGetValue(ToolName, Tool) then
    resultValue := ExecuteTool(Tool, Arguments)
  else
    ResultValue := TValue.From('Error: Tool not found: ' + ToolName);

  // [local change] outbound filter: one place to rewrite textual results.
  if Assigned(ResultFilter) and ResultValue.IsType<string> then
    ResultValue := TValue.From<string>(ResultFilter(ToolName, ResultValue.AsString));

  Result := TValue.From<TJSONObject>(BuildToolCallResponse(ResultValue));
end;

function TMCPToolsManager.ListTools: TValue;
begin
  TLogger.Info('MCP ListTools called');
  Result := TValue.From<TJSONObject>(BuildToolListResponse);
end;

end.