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

  // [local change] see ListFilter
  TToolListFilter = reference to function(const ToolName: string): Boolean;

  // [local change 2026-09-25] optional, applied AFTER ResultFilter: lets the
  // host turn a textual result into a content array (the text plus image
  // items a tool attached) - one place for every tool, so a screenshot
  // travels in the same answer. nil = leave the text as it is.
  TToolResultWrapper = reference to function(const ToolName: string;
    const AText: string): TJSONArray;

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
    // [local change 2026-09-25] see TToolResultWrapper
    class var ResultWrapper: TToolResultWrapper;
    // [local change] optional tools/list filter: True = omit the tool from
    // the listing (it stays CALLABLE - this trims token surface for small
    // models, it is not a permission; permissions live in ToolGate).
    class var ListFilter: TToolListFilter;
  end;

implementation

uses
  MCPServer.Registration,
  Lsp.Texts; // [local change 2026-09-27] el lector de las etiquetas de mensaje

{ [local change 2026-09-27] EL resultado de una respuesta: el que DECLARA la
  etiqueta con la que empieza (Lsp.Texts.MsgOutcome), puesta por quien
  escribe el mensaje. Antes se adivinaba leyendo el texto (RECHAZADO, no
  existe, Error:) en dos copias que ya no coincidian. AEsError: el texto
  viene del campo error de un objeto JSON, asi que es un fallo aunque no lo
  declare: la llamada estaba mal (lo de siempre para ese campo). }
function OutcomeDelTexto(const AText: string; AEsError: Boolean): string;
begin
  Result := MsgOutcome(AText);
  if (Result = '') and AEsError then
    Result := 'INVALID_PARAM';
end;

{ [local change 2026-09-27] El texto del campo "error" de un objeto: UNA
  lectura para las dos ramas. Un texto es el error; null, false o ausente es
  que no lo hay; cualquier otra cosa (un objeto, true) es un error sin
  texto. Antes "error": null salia INVALID_PARAM y un "error" objeto, ok:true. }
function ErrorDelObjeto(AObj: TJSONObject): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := AObj.GetValue('error');
  if (V = nil) or (V is TJSONNull) or ((V is TJSONBool) and not TJSONBool(V).AsBoolean) then
    Exit;
  if V is TJSONString then
    Result := V.Value.Trim
  else
    Result := V.ToJSON;
end;

{ [local change 2026-09-27] El resultado de una respuesta en TEXTO: la
  etiqueta que la abre o, si es un objeto JSON, la de su campo "error". UNA
  lectura para las dos ramas (texto suelto, y texto que acompana a una
  imagen: esa miraba solo la etiqueta y un JSON con "error" salia ok). }
function OutcomeDeLaRespuesta(const AText: string): string;
var
  V: TJSONValue;
  Err: string;
begin
  Result := OutcomeDelTexto(AText, False);
  if (Result <> '') or not AText.TrimLeft.StartsWith('{') then
    Exit;
  V := TJSONObject.ParseJSONValue(AText);
  try
    if V is TJSONObject then
    begin
      Err := ErrorDelObjeto(TJSONObject(V));
      if Err <> '' then
        Result := OutcomeDelTexto(Err, True);
    end;
  finally
    V.Free;
  end;
end;

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
      // [local change 2026-09-27] ...pero un indice fuera de rango DENTRO del
      // servidor tambien es un EArgumentException (la RTL lo hereda asi): eso
      // es lo inesperado, no una llamada mal hecha
      on E: EArgumentException do
        if EsFalloDelLlamador(E) then
          Result := MsgEnvuelve(SR_ERROR_FMT, E.Message)
        else
          Result := MsgExcepcion(E.ClassName, E.Message);
      // [local change 2026-09-26] ...and a REFUSAL that travelled as an
      // exception is a refusal too: a check deep inside (the jail in
      // Lsp.Session, "the compiler does not resolve X" in Lsp.References)
      // raises with the very RECHAZADO text a tool would have returned, and
      // wrapping it here told the agent the server had broken. Measured by
      // test_round48 while hardening it. One place, every tool.
      // [local change 2026-09-27] y un mensaje del catalogo con etiqueta de
      // resultado tambien: dice el mismo lo que es
      on E: Exception do
        Result := MsgEnvuelve(SR_SYS_TOOL_FAILED_FMT, E.Message);
    end;
  finally
    Owned.Free;
  end;
end;

function TMCPToolsManager.BuildToolCallResponse(const ResultValue: TValue): TJSONObject;
var
  ContentArray: TJSONArray;
  ContentItem: TJSONObject;

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
    // [local change 2026-09-27] el texto que acompana a una imagen declara
    // su resultado igual que uno suelto: la proxima tool que adjunte en un
    // camino de fallo no puede salir como exito
    for var It in ResultValue.AsType<TJSONArray> do
      if (It is TJSONObject) and (TJSONObject(It).GetValue<string>('type', '') = 'text') then
      begin
        if OutcomeDeLaRespuesta(TJSONObject(It).GetValue<string>('text', '')) <> '' then
          Result.AddPair('isError', TJSONBool.Create(True));
        Break;
      end;
  end
  else if ResultValue.IsType<string> then
  begin
    TextValue := ResultValue.AsString;
    HasError := False;

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
    //   DENIED        a rule refuses it or something stands in the way (jail,
    //                 read-only, ownership, a file another process holds)
    //   NOT_FOUND     the named file/project/thing is not there
    //   INVALID_PARAM the call itself is malformed (missing or bad value)
    //   INTERNAL      this server broke inside - worth a delphi_report
    //   (la regla 11 de delphi_help conventions; la cabecera de Lsp.Texts)
    // The jail's anti-probing property survives: outside-the-jail answers use
    // one fixed text whether the target exists or not, so they all map to
    // DENIED; NOT_FOUND only ever comes from in-jail "no existe" texts.
    // [local change 2026-09-27] el resultado, de UNA funcion (OutcomeDelTexto)
    var OutcomeCode := OutcomeDeLaRespuesta(TextValue);
    // [local change 2026-09-19] structuredContent ES la salida de la tool para
    // el protocolo, asi que un cliente que lo entienda ENSEÑA ESO Y ESCONDE
    // 'content'. Publicando aqui solo {ok, code} el agente recibia
    // {"ok":true} en TODAS las llamadas y no veia el resultado: medido contra
    // el exe de produccion por stdio, y es lo que ve cualquier cliente MCP
    // (Claude Desktop, Claude Code). Casi todas las tools devuelven su JSON
    // como TEXTO, o sea que caen aqui, no en la rama TJsonObject de abajo.
    // Arreglo que conserva la intencion de la auditoria: si el texto ES un
    // objeto JSON, ese objeto va a structuredContent y el ok/code se le añade
    // dentro (sin pisar claves que ya traiga). Si no lo es, se queda el
    // {ok, code} de siempre y el texto viaja entero en 'content'.
    // [local change 2026-09-20] Y si el texto NO es JSON, no se publica
    // structuredContent EN ABSOLUTO. El arreglo anterior salvo a las tools
    // que responden JSON, pero dejo mudas a las que responden PROSA: un
    // cliente que ensena structuredContent (Claude Code, Claude Desktop)
    // recibia {"ok":true} y ningun contenido en delphi_read, delphi_help o
    // delphi_git status (medido 2026-09-20 contra el exe de produccion por
    // HTTP). structuredContent solo tiene sentido cuando la tool declara
    // outputSchema, y ninguna de estas lo hace: sin el campo, el cliente
    // ensena 'content', que es la respuesta de verdad.
    // El fallo en prosa SI lo publica - es corto y el agente necesita el
    // code - y se lleva el texto dentro para que tampoco desaparezca.
    var Structured: TJSONObject := nil;
    if TextValue.TrimLeft.StartsWith('{') then
      Structured := TJSONObject.ParseJSONValue(TextValue) as TJSONObject;
    if (Structured = nil) and (OutcomeCode <> '') then
    begin
      Structured := TJSONObject.Create;
      Structured.AddPair('text', TextValue);
    end;
    // [local change 2026-09-20] Una tool que contesta un OBJETO JSON con un
    // campo "error" dentro viajaba con "ok": true. El codigo de arriba se
    // deduce del PREFIJO del texto, y ese texto empieza por '{', asi que no
    // se le sacaba ninguno; y el "ok": true que el propio objeto trae dentro
    // no se pisaba por el guard de mas abajo. Resultado: un cliente que
    // ramifica por "ok" leia una NEGATIVA como un exito - exactamente la
    // familia del structuredContent de v1.0.0. Medido 2026-09-20 en
    // delphi_test (proyecto que no existe) y delphi_build (build fallido).
    // El campo "error" del objeto manda sobre lo que el objeto diga de si
    // mismo: si hay error, no hay ok.
    if Assigned(Structured) and (OutcomeCode <> '') and (ErrorDelObjeto(Structured) <> '') then
      Structured.RemovePair('ok').Free; // el suyo mentia; abajo se pone el bueno
    if Assigned(Structured) then
    begin
      Result.AddPair('structuredContent', Structured);
      if Structured.GetValue('ok') = nil then
        Structured.AddPair('ok', TJSONBool.Create(OutcomeCode = ''));
      if (OutcomeCode <> '') and (Structured.GetValue('code') = nil) then
        Structured.AddPair('code', OutcomeCode);
    end;
    if OutcomeCode <> '' then
      HasError := True;

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

    HasError := ErrorDelObjeto(JsonResult) <> '';
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
    // [local change] profile/allowlist surface trim (see ListFilter)
    if Assigned(ListFilter) and ListFilter(Tool.Name) then
      Continue;
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
    Result := TValue.From<TJSONObject>(BuildToolCallResponse(MsgText(SR_SYS_INVALID_TOOL_PARAMS)));
    Exit;
  end;

  TLogger.Info('MCP CallTool called for tool: ' + ToolName);

  // [local change 2026-09-28] "arguments" que no es un objeto se dice: se
  // cambiaba en silencio por {} y el agente leia "falta path" habiendolo
  // mandado dentro de un texto JSON. null y una lista VACIA siguen siendo
  // "sin argumentos" (clientes que los mandan asi).
  var ArgsCrudos := Params.GetValue('arguments');
  if Assigned(ArgsCrudos) and not (ArgsCrudos is TJSONObject) and
     not (ArgsCrudos is TJSONNull) and
     not ((ArgsCrudos is TJSONArray) and (TJSONArray(ArgsCrudos).Count = 0)) then
  begin
    var Llego := MsgText(SF_SYS_ARGS_OTRO);
    if ArgsCrudos is TJSONString then
      Llego := MsgText(SF_SYS_ARGS_TEXTO)
    else if ArgsCrudos is TJSONArray then
      Llego := MsgText(SF_SYS_ARGS_LISTA);
    Exit(TValue.From<TJSONObject>(BuildToolCallResponse(
      MsgFmt(SR_SYS_ARGUMENTOS_NO_OBJETO_FMT, [Llego]))));
  end;

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
    ResultValue := TValue.From(MsgFmt(SR_SYS_TOOL_NOT_FOUND_FMT, [ToolName]));

  // [local change] outbound filter: one place to rewrite textual results.
  if Assigned(ResultFilter) and ResultValue.IsType<string> then
    ResultValue := TValue.From<string>(ResultFilter(ToolName, ResultValue.AsString));
  // [local change 2026-09-25] ...and then, the attachments: the text is
  // already filtered, so nothing leaves unmasked by taking the array shape.
  if Assigned(ResultWrapper) and ResultValue.IsType<string> then
  begin
    var Wrapped := ResultWrapper(ToolName, ResultValue.AsString);
    if Wrapped <> nil then
      ResultValue := TValue.From<TJSONArray>(Wrapped);
  end;

  Result := TValue.From<TJSONObject>(BuildToolCallResponse(ResultValue));
end;

function TMCPToolsManager.ListTools: TValue;
begin
  TLogger.Info('MCP ListTools called');
  Result := TValue.From<TJSONObject>(BuildToolListResponse);
end;

end.