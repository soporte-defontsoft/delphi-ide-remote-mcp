unit Lsp.Client;

{ LSP client over TLspProcessTransport, tailored to DelphiLSP.exe behavior
  (all of it measured against DelphiLSP 37.0 - see docs/DELPHILSP-NOTES.md):

  - Blocking Request with id correlation and timeout.
  - RequestWithRetry: DelphiLSP answers -32800 "Request removed" while it is
    still indexing a freshly opened document; retry with escalating delays.
  - Server->client requests are answered with a null result so the server
    never stalls waiting on us.
  - didOpen loads source files encoding-safely: BOM wins, otherwise a
    configurable fallback (default: system ANSI, which is what legacy
    Windows-1252 Delphi sources need). LSP mandates UTF-8 on the wire.
  - Notifications (e.g. textDocument/publishDiagnostics) are queued and can
    be awaited with WaitForNotification. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Winapi.Windows,
  Lsp.Transport.Process;

type
  ELspClient = class(Exception);

  TLspServerType = (lstAgent, lstLinter, lstController);

  TLspClient = class
  private type
    TPendingCall = class
      Event: TEvent;
      ResponseJson: string;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FTransport: TLspProcessTransport;
    FOwnsTransport: Boolean;
    FNextId: Integer;
    FLock: TCriticalSection;
    FPending: TObjectDictionary<Integer, TPendingCall>;
    FNotifications: TObjectList<TJSONObject>;
    FNotifyEvent: TEvent;
    procedure HandleRawMessage(const AJson: string);
    function NextId: Integer;
  public
    constructor Create(ATransport: TLspProcessTransport; AOwnsTransport: Boolean = True);
    destructor Destroy; override;

    // Raw JSON-RPC. AParamsJson is an already-serialized JSON value; pass
    // "{}" when there are no params. Returns the full response object;
    // caller frees. Raises on timeout.
    function Request(const AMethod, AParamsJson: string; ATimeoutMs: Integer): TJSONObject;
    function RequestWithRetry(const AMethod, AParamsJson: string;
      ATimeoutMs: Integer; ARetries: Integer = 2): TJSONObject;
    procedure Notify(const AMethod, AParamsJson: string);

    { Handshake and configuration }
    function Initialize(const ARootUri: string; AServerType: TLspServerType;
      AAgentCount: Integer = 2; ATimeoutMs: Integer = 30000): TJSONObject;
    procedure SendInitialized;
    procedure SetSettingsFile(const ASettingsFilePath: string);

    { Document sync }
    procedure DidOpenText(const AUri, AText: string; AVersion: Integer = 1);
    procedure DidOpenFile(const AFilePath: string);
    { Full-document change (DelphiLSP announces textDocumentSync=1 = full). }
    procedure DidChangeText(const AUri, AText: string; AVersion: Integer);

    { Language features (positions are 0-based, LSP style) }
    function Hover(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
    function Definition(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
    { Definition con hover de oraculo (calentamiento del motor): ver la
      implementacion. APending = True cuando hover conoce el simbolo y
      definition sigue vacia tras los reintentos. }
    function DefinitionResolved(const AUri: string; ALine, ACharacter: Integer;
      out APending: Boolean): TJSONObject;
    function Declaration(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
    function Implementation_(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
    function SignatureHelp(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
    function DocumentSymbols(const AUri: string): TJSONObject;
    function Completion(const AUri: string; ALine, ACharacter: Integer;
      const ATriggerCharacter: string = ''): TJSONObject;

    { Notifications: returns the params object of the first queued notification
      with AMethod (caller frees), or nil on timeout. When AUriFilter is not
      empty, only a notification whose params.uri equals it (case-insensitive)
      is taken - others stay queued. }
    function WaitForNotification(const AMethod: string; ATimeoutMs: Integer;
      const AUriFilter: string = ''): TJSONObject;

    { Helpers }
    class function PathToUri(const APath: string): string;
    class function UriToPath(const AUri: string): string;
    class function LoadSourceText(const AFilePath: string): string;
  end;

implementation

uses
  Lsp.Patch; // DecodeSourceBytes: el detector de encoding de delphi_read

const
  RETRY_DELAYS_MS: array [0 .. 1] of Integer = (2000, 5000);
  LSP_REQUEST_REMOVED = -32800;

{ TLspClient.TPendingCall }

constructor TLspClient.TPendingCall.Create;
begin
  inherited;
  Event := TEvent.Create(nil, True, False, '');
end;

destructor TLspClient.TPendingCall.Destroy;
begin
  Event.Free;
  inherited;
end;

{ TLspClient }

constructor TLspClient.Create(ATransport: TLspProcessTransport; AOwnsTransport: Boolean);
begin
  inherited Create;
  FTransport := ATransport;
  FOwnsTransport := AOwnsTransport;
  FLock := TCriticalSection.Create;
  FPending := TObjectDictionary<Integer, TPendingCall>.Create([doOwnsValues]);
  FNotifications := TObjectList<TJSONObject>.Create(True);
  FNotifyEvent := TEvent.Create(nil, False, False, '');
  FTransport.OnMessage := HandleRawMessage;
end;

destructor TLspClient.Destroy;
begin
  if FOwnsTransport then
    FTransport.Free;
  FNotifyEvent.Free;
  FNotifications.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

function TLspClient.NextId: Integer;
begin
  Result := TInterlocked.Increment(FNextId);
end;

procedure TLspClient.HandleRawMessage(const AJson: string);
var
  Msg: TJSONObject;
  IdVal: TJSONValue;
  Id: Integer;
  Call: TPendingCall;
begin
  Msg := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Msg = nil then
    Exit;
  try
    IdVal := Msg.GetValue('id');
    if (IdVal <> nil) and not (IdVal is TJSONNull) then
    begin
      if Msg.GetValue('method') <> nil then
      begin
        // Server->client request: answer null so the server never blocks on us.
        FTransport.SendJson(Format('{"jsonrpc":"2.0","id":%s,"result":null}',
          [IdVal.ToJSON]));
        Exit;
      end;
      // Response to one of our requests.
      Id := StrToIntDef(IdVal.Value, -1);
      FLock.Enter;
      try
        if FPending.TryGetValue(Id, Call) then
        begin
          Call.ResponseJson := AJson;
          Call.Event.SetEvent;
        end;
      finally
        FLock.Leave;
      end;
      Exit;
    end;
    // Notification.
    FLock.Enter;
    try
      // Bounded: diagnostics nobody ever collects used to pile up for
      // the life of the client (hermes, release audit 2026-08-26, P1.6).
      // 200 is far above any real burst; the oldest go first.
      while FNotifications.Count >= 200 do
        FNotifications.Delete(0);
      FNotifications.Add(Msg.Clone as TJSONObject);
    finally
      FLock.Leave;
    end;
    FNotifyEvent.SetEvent;
  finally
    Msg.Free;
  end;
end;

function TLspClient.Request(const AMethod, AParamsJson: string;
  ATimeoutMs: Integer): TJSONObject;
var
  Id: Integer;
  Call: TPendingCall;
  Raw: string;
begin
  Id := NextId;
  Call := TPendingCall.Create;
  FLock.Enter;
  try
    FPending.Add(Id, Call); // dictionary owns Call
  finally
    FLock.Leave;
  end;

  FTransport.SendJson(Format('{"jsonrpc":"2.0","id":%d,"method":"%s","params":%s}',
    [Id, AMethod, AParamsJson]));

  if Call.Event.WaitFor(ATimeoutMs) <> wrSignaled then
  begin
    FLock.Enter;
    try
      FPending.Remove(Id);
    finally
      FLock.Leave;
    end;
    raise ELspClient.CreateFmt('LSP request "%s" timed out after %d ms',
      [AMethod, ATimeoutMs]);
  end;

  FLock.Enter;
  try
    Raw := Call.ResponseJson;
    FPending.Remove(Id);
  finally
    FLock.Leave;
  end;
  Result := TJSONObject.ParseJSONValue(Raw) as TJSONObject;
  if Result = nil then
    raise ELspClient.CreateFmt('LSP response to "%s" is not valid JSON', [AMethod]);
end;

function TLspClient.RequestWithRetry(const AMethod, AParamsJson: string;
  ATimeoutMs, ARetries: Integer): TJSONObject;
var
  Attempt, Code: Integer;
  ErrObj: TJSONObject;
begin
  Attempt := 0;
  repeat
    Result := Request(AMethod, AParamsJson, ATimeoutMs);
    ErrObj := Result.GetValue('error') as TJSONObject;
    if ErrObj = nil then
      Exit;
    Code := StrToIntDef(ErrObj.GetValue('code').Value, 0);
    if (Code <> LSP_REQUEST_REMOVED) or (Attempt >= ARetries) then
      Exit; // a different error, or retries exhausted: caller inspects it
    Result.Free;
    Sleep(RETRY_DELAYS_MS[Attempt mod Length(RETRY_DELAYS_MS)]);
    Inc(Attempt);
  until False;
end;

procedure TLspClient.Notify(const AMethod, AParamsJson: string);
begin
  FTransport.SendJson(Format('{"jsonrpc":"2.0","method":"%s","params":%s}',
    [AMethod, AParamsJson]));
end;

function TLspClient.Initialize(const ARootUri: string;
  AServerType: TLspServerType; AAgentCount, ATimeoutMs: Integer): TJSONObject;
const
  TypeNames: array [TLspServerType] of string = ('agent', 'linter', 'controller');
var
  Params: string;
begin
  Params := Format(
    '{"processId":%d,"rootUri":"%s","initializationOptions":' +
    '{"serverType":"%s","agentCount":%d},"capabilities":{}}',
    [Integer(GetCurrentProcessId), ARootUri, TypeNames[AServerType], AAgentCount]);
  Result := Request('initialize', Params, ATimeoutMs);
end;

procedure TLspClient.SendInitialized;
begin
  Notify('initialized', '{}');
end;

procedure TLspClient.SetSettingsFile(const ASettingsFilePath: string);
begin
  Notify('workspace/didChangeConfiguration',
    Format('{"settings":{"settingsFile":"%s"}}', [PathToUri(ASettingsFilePath)]));
end;

procedure TLspClient.DidOpenText(const AUri, AText: string; AVersion: Integer);
var
  Doc: TJSONObject;
begin
  // Built with the JSON writer: source text needs real escaping.
  Doc := TJSONObject.Create;
  try
    Doc.AddPair('uri', AUri);
    Doc.AddPair('languageId', 'pascal');
    Doc.AddPair('version', TJSONNumber.Create(AVersion));
    Doc.AddPair('text', AText);
    Notify('textDocument/didOpen', Format('{"textDocument":%s}', [Doc.ToJSON]));
  finally
    Doc.Free;
  end;
end;

procedure TLspClient.DidOpenFile(const AFilePath: string);
begin
  DidOpenText(PathToUri(AFilePath), LoadSourceText(AFilePath));
end;

procedure TLspClient.DidChangeText(const AUri, AText: string; AVersion: Integer);
var
  Change: TJSONObject;
begin
  Change := TJSONObject.Create;
  try
    Change.AddPair('text', AText);
    Notify('textDocument/didChange', Format(
      '{"textDocument":{"uri":"%s","version":%d},"contentChanges":[%s]}',
      [AUri, AVersion, Change.ToJSON]));
  finally
    Change.Free;
  end;
end;

function TLspClient.Hover(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/hover', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}',
    [AUri, ALine, ACharacter]), 30000);
end;

function TLspClient.Definition(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/definition', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}',
    [AUri, ALine, ACharacter]), 30000);
end;

function TLspClient.Declaration(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/declaration', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}',
    [AUri, ALine, ACharacter]), 30000);
end;

function TLspClient.Implementation_(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/implementation', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}',
    [AUri, ALine, ACharacter]), 30000);
end;

function TLspClient.SignatureHelp(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/signatureHelp', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}',
    [AUri, ALine, ACharacter]), 30000);
end;

function TLspClient.DocumentSymbols(const AUri: string): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/documentSymbol',
    Format('{"textDocument":{"uri":"%s"}}', [AUri]), 60000);
end;

function TLspClient.Completion(const AUri: string; ALine, ACharacter: Integer;
  const ATriggerCharacter: string): TJSONObject;
var
  Ctx: string;
begin
  if ATriggerCharacter <> '' then
    Ctx := Format(',"context":{"triggerKind":2,"triggerCharacter":"%s"}', [ATriggerCharacter])
  else
    Ctx := ',"context":{"triggerKind":1}';
  Result := RequestWithRetry('textDocument/completion', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}%s}',
    [AUri, ALine, ACharacter, Ctx]), 30000);
end;

function TLspClient.WaitForNotification(const AMethod: string;
  ATimeoutMs: Integer; const AUriFilter: string): TJSONObject;
var
  Deadline: UInt64;
  I: Integer;
  MethodVal, ParamsVal, UriVal: TJSONValue;
  Remaining: Integer;
begin
  Result := nil;
  Deadline := GetTickCount64 + UInt64(ATimeoutMs);
  repeat
    FLock.Enter;
    try
      for I := 0 to FNotifications.Count - 1 do
      begin
        MethodVal := FNotifications[I].GetValue('method');
        if (MethodVal = nil) or (MethodVal.Value <> AMethod) then
          Continue;
        ParamsVal := FNotifications[I].GetValue('params');
        if AUriFilter <> '' then
        begin
          UriVal := nil;
          if ParamsVal is TJSONObject then
            UriVal := TJSONObject(ParamsVal).GetValue('uri');
          if (UriVal = nil) or not SameText(UriVal.Value, AUriFilter) then
            Continue;
        end;
        if ParamsVal <> nil then
          Result := ParamsVal.Clone as TJSONObject
        else
          Result := TJSONObject.Create;
        FNotifications.Delete(I);
        Exit;
      end;
    finally
      FLock.Leave;
    end;
    Remaining := Integer(Int64(Deadline) - Int64(GetTickCount64));
    if Remaining <= 0 then
      Exit(nil);
    FNotifyEvent.WaitFor(Remaining);
  until GetTickCount64 >= Deadline;
end;

class function TLspClient.PathToUri(const APath: string): string;
const
  Unreserved = ['A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '.', '_', '~', '/'];
var
  Normalized: string;
  Utf8: TBytes;
  B: Byte;
  Sb: TStringBuilder;
begin
  Normalized := APath.Replace('\', '/');
  Utf8 := TEncoding.UTF8.GetBytes(Normalized);
  Sb := TStringBuilder.Create('file:///');
  try
    for B in Utf8 do
      if (B < 128) and (AnsiChar(B) in Unreserved) then
        Sb.Append(Char(B))
      else
        Sb.Append('%').Append(IntToHex(B, 2));
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

class function TLspClient.UriToPath(const AUri: string): string;
var
  S: string;
  I: Integer;
  Bytes: TBytes;
  N: Integer;
begin
  S := AUri;
  if S.ToLower.StartsWith('file:///') then
    S := S.Substring(8)
  else if S.ToLower.StartsWith('file://') then
    S := S.Substring(7);

  // Percent-decode into UTF-8 bytes, then decode.
  SetLength(Bytes, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      Bytes[N] := StrToIntDef('$' + Copy(S, I + 1, 2), Ord('%'));
      Inc(I, 3);
    end
    else
    begin
      Bytes[N] := Byte(AnsiChar(S[I])); // URI is ASCII outside escapes
      Inc(I);
    end;
    Inc(N);
  end;
  SetLength(Bytes, N);
  Result := TEncoding.UTF8.GetString(Bytes).Replace('/', '\');
end;

class function TLspClient.LoadSourceText(const AFilePath: string): string;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFilePath);
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else if (Length(Bytes) >= 2) and (Bytes[0] = $FF) and (Bytes[1] = $FE) then
    Result := TEncoding.Unicode.GetString(Bytes, 2, Length(Bytes) - 2)
  else if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Result := TEncoding.BigEndianUnicode.GetString(Bytes, 2, Length(Bytes) - 2)
  else
    // Sin BOM NO significa CP1252. Darlo por hecho convertia en mojibake
    // TODO fichero UTF-8 sin BOM: delphi_search sobre los .md de este mismo
    // repo devolvia basura por cada raya (medido el 20-sep-2026 usando el
    // servidor como agente), y ese texto corrupto es el que un agente copia
    // para construir un ancla. Por aqui pasa ademas lo que se le manda al
    // linter y lo que lee delphi_references. Ahora decide el MISMO detector
    // que usa delphi_read: utf8 solo si CADA byte alto forma secuencia
    // valida, asi que los fuentes CP1252 de siempre siguen leyendose bien.
    Result := DecodeSourceBytes(Bytes);
end;

{ Definition con hover de oraculo. DelphiLSP contesta null a definition
  mientras todavia indexa una unit, y en ese MISMO instante hover si resuelve
  el simbolo (medido por Hermes el 2026-09-22: cinco definition/references
  seguidas rechazadas con "no resuelve", hover correcto, y la siguiente pasa).
  Si definition viene vacia pero hover no, es calentamiento y no un simbolo
  inexistente: se reintenta con pausa; si sigue vacia, APending = True para
  que la tool diga "todavia no" en vez de "no resuelve". Sin hover, ni
  reintento ni espera: ahi no hay simbolo. UN sitio para las tools que anclan
  en una definicion (delphi_definition, delphi_references, rename). }
function TLspClient.DefinitionResolved(const AUri: string; ALine, ACharacter: Integer;
  out APending: Boolean): TJSONObject;
const
  INTENTOS = 4;
  PAUSA_MS = 750;

  function TieneLocalizacion(AResp: TJSONObject): Boolean;
  var
    V: TJSONValue;
  begin
    V := AResp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit(False);
    if V is TJSONArray then
      Exit(TJSONArray(V).Count > 0);
    Result := (V is TJSONObject) and
      ((TJSONObject(V).GetValue('uri') <> nil) or (TJSONObject(V).GetValue('targetUri') <> nil));
  end;

var
  H: TJSONObject;
  V: TJSONValue;
  I: Integer;
begin
  APending := False;
  Result := Definition(AUri, ALine, ACharacter);
  if TieneLocalizacion(Result) then
    Exit;
  H := Hover(AUri, ALine, ACharacter);
  try
    V := H.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit; // ni hover lo conoce: no es un simbolo, no hay nada que esperar
  finally
    H.Free;
  end;
  for I := 1 to INTENTOS do
  begin
    Sleep(PAUSA_MS);
    Result.Free;
    Result := Definition(AUri, ALine, ACharacter);
    if TieneLocalizacion(Result) then
      Exit;
  end;
  APending := True;
end;

end.
