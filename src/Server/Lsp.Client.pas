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

const
  // How long StopEngine waits for the answer to `shutdown`. A busy engine
  // answers in 60 ms on a 60-unit project (measured 2026-09-30); one that
  // has not answered in this is not waited for. Public: a test tells by it
  // that the wait is there, and that it is bounded (LspTests.Motor).
  SHUTDOWN_WAIT_MS = 1000;

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
    FStopped: Boolean;
    FRootUri: string;  // what Initialize was given: the engine's name in the log
    FEndSaid: Boolean; // StopEngine has said how this engine ended
    // What is IN FLIGHT on the engine, and since when nothing has been heard
    // of it (see Hung). Under FLock.
    FInFlight: Integer;    // requests waiting for their answer + writes inside the transport
    FWaitingSince: UInt64; // when that wait began, or the engine's last sign of life since
    FSeenCpuMs, FSeenIoOps: UInt64; // the process's counters at the last look
    FWaiters: Integer;     // calls waiting for a notification right now (under FLock)
    procedure BeginWait;
    procedure EndWait;
    procedure HandleRawMessage(const AJson: string);
    function NextId: Integer;
    procedure Send(const AJson: string);
    function Ask(const AMethod: string; AWaitMs: Cardinal; AKeepThread: Boolean;
      out AAnswered: Boolean): TThread;
    function DoWaitForNotification(const AMethod: string; ATimeoutMs: Integer;
      const AUriFilter: string): TJSONObject;
    procedure SayHowItEnded(AAsked, AAnswered: Boolean);
  public
    constructor Create(ATransport: TLspProcessTransport; AOwnsTransport: Boolean = True);
    destructor Destroy; override;

    { Stops the engine process and keeps THIS object valid: whoever still
      holds it (another agent's request in flight) gets an error, never freed
      memory - and gets it AT ONCE: the requests waiting for an answer and
      whoever waits for a notification are woken, instead of waiting out
      their 30 or 60 seconds. For a client the session retires before it goes
      away itself. }
    procedure StopEngine;
    { The WORD alone, without the process: from here on the client is
      stopped for everybody - whoever waits on it is woken, and nothing else
      is sent. It takes no time, so the session gives it UNDER its own lock,
      at the moment it takes the client out of its table: "out of the table"
      and "stopped" are then one thing for whoever looks under that lock.
      The process is ended afterwards, outside (StopEngine). }
    procedure Retire;
    property Stopped: Boolean read FStopped;
    { Does the engine's process go on? The system answers at once (the
      transport's ProcessAlive). An engine may end by itself, or be ended
      from outside: the session asks before it hands a client out. }
    function EngineAlive: Boolean;
    { What the engine's process ended with (the transport's ExitCode). }
    function EngineExitCode: Cardinal;
    { Is the engine HUNG? Something has been in flight on it - a request
      waiting for its answer, a write inside the transport - for more than
      ALimitMs with NO sign of life in all that time: not one message from
      it, no CPU used, no I/O done. An engine that works uses CPU, one that
      reads a slow disk does I/O (not measured over a network), and one that answers anything at all is
      alive; an engine at rest shows none of the three, which is why they
      only count with something in flight (measured 2026-09-30: requests
      answer in 10 to 30 ms on a 60-unit project, and a suspended engine
      shows 0 CPU, 0 I/O and 0 messages). Each call is a LOOK: it keeps the
      counters it saw, for the next one. False for a stopped client. }
    function Hung(ALimitMs: UInt64): Boolean;
    { Does the engine ANSWER? It is asked something the protocol obliges a
      server to refuse - a request whose method starts with "$/" - and waited
      for AWaitMs. One that answers is alive and NOT WORKING on a request:
      DelphiLSP serves them one at a time (measured 2026-09-30: a probe sent
      behind a definition of 60 to 100 ms is answered right after it), and
      answers this in 0 to 2 ms when it has none (agent and linter, 10 of
      10; in 19 ms before `initialize`) - also while a request it could not
      parse stays unanswered for good: to one of those it says NOTHING, and
      goes on with the rest. So an engine with something in flight that
      answers this has dropped the request, and one that does not is working
      on it - or hung: that is told by its CPU and its I/O (Hung). Sent like
      `shutdown`, on a thread of its own: an engine that does not read does
      not hold whoever asks. }
    function AnswersProbe(AWaitMs: Cardinal): Boolean;
    { Is somebody using it right now? Something in flight, or a call waiting
      for a notification of it (a lint waits for its diagnostics that way). }
    function Busy: Boolean;
    { The engine's process id while there is one (0 otherwise). For the tests. }
    function EngineProcessId: Cardinal;
    { The transport left a writer behind inside its write (its WriterLeft):
      this object must not be freed under that thread. }
    function WriterLeft: Boolean;

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
    procedure DidClose(const AUri: string);

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
    { El texto de un fuente tal como se le da al motor y lo leen references y
      search, por EL detector. Pregunta ELLA a la puerta, con los lugares del
      motor (Lsp.Patch.LUGARES_DEL_MOTOR: la jaula, el IDE y su biblioteca):
      cargaba sin preguntar lo que le pasasen, tambien una ruta que daba el
      MOTOR (references, la definicion de un candidato: medida M1). Fuera de
      ahi lanza la negativa. Quien recorre carpetas pregunta ADEMAS la de la
      jaula por cada fichero: lo de detras de una union no es suyo. }
    class function LoadSourceText(const AFilePath: string): string;
  end;

implementation

uses
  Lsp.Patch,
  Lsp.DesignerBin,
  System.StrUtils,
  MCPServer.Logger,
  Lsp.Texts, // DecodeSourceBytes: el detector de encoding de delphi_read
  Lsp.Json;  // ObjetoJson: EL lector de un JSON que tiene que ser un objeto

const
  RETRY_DELAYS_MS: array [0 .. 1] of Integer = (2000, 5000);
  NOTIFY_SLICE_MS = 250; // the longest a waiter sleeps without looking
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
  // A client that comes here without StopEngine was never handed out - the
  // one that lost the race to be registered, the one whose folder was
  // leaving, the one that did not answer `initialize` - so nobody has a
  // question in flight on it, and its input is just closed (the transport's
  // Stop). Measured 2026-09-30 with the engine launched by hand: 0 crashes
  // of 8 with `initialize` in flight, 0 of 8 just built, 0 of 8 with its
  // settings just sent. If it ended badly all the same, it is said.
  if FOwnsTransport then
  begin
    FTransport.Stop;
    SayHowItEnded(False, False);
    FTransport.Free;
  end;
  FNotifyEvent.Free;
  FNotifications.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

procedure TLspClient.Retire;
var
  Call: TPendingCall;
begin
  FLock.Enter;
  try
    FStopped := True;
    for Call in FPending.Values do
      Call.Event.SetEvent;
  finally
    FLock.Leave;
  end;
  // one waiter is woken here; the others find out at their next look
  // (WaitForNotification never sleeps longer than NOTIFY_SLICE_MS)
  FNotifyEvent.SetEvent;
end;

function TLspClient.EngineAlive: Boolean;
begin
  Result := FTransport.ProcessAlive;
end;

function TLspClient.EngineExitCode: Cardinal;
begin
  Result := FTransport.ExitCode;
end;

procedure TLspClient.BeginWait;
var
  Cpu, Io: UInt64;
begin
  FTransport.Activity(Cpu, Io); // outside the lock: it asks the system
  FLock.Enter;
  try
    Inc(FInFlight);
    if FInFlight = 1 then
    begin
      // the clock of "nothing heard" starts with the wait, and so does what
      // the process's counters are compared with
      FWaitingSince := GetTickCount64;
      FSeenCpuMs := Cpu;
      FSeenIoOps := Io;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TLspClient.EndWait;
begin
  FLock.Enter;
  try
    Dec(FInFlight);
  finally
    FLock.Leave;
  end;
end;

function TLspClient.Hung(ALimitMs: UInt64): Boolean;
const
  CPU_ALIVE_MS = 15; // one tick of the scheduler: less than this is not work
var
  Cpu, Io, Tick: UInt64;
begin
  Result := False;
  if FStopped or (ALimitMs = 0) then
    Exit;
  FTransport.Activity(Cpu, Io); // outside the lock: it asks the system
  FLock.Enter;
  try
    if FInFlight = 0 then
      Exit;
    Tick := GetTickCount64; // under the lock, like the one it is compared with
    if (Io <> FSeenIoOps) or (Cpu >= FSeenCpuMs + CPU_ALIVE_MS) then
    begin
      // it has worked, or read or written, since the last look: alive
      FSeenCpuMs := Cpu;
      FSeenIoOps := Io;
      FWaitingSince := Tick;
    end;
    Result := Tick - FWaitingSince > ALimitMs;
  finally
    FLock.Leave;
  end;
end;

function TLspClient.AnswersProbe(AWaitMs: Cardinal): Boolean;
begin
  Result := False;
  try
    Ask('$/alive', AWaitMs, False, Result);
  except
    // it could not even be asked: not answered
  end;
end;

function TLspClient.Busy: Boolean;
begin
  FLock.Enter;
  try
    Result := (FInFlight > 0) or (FWaiters > 0);
  finally
    FLock.Leave;
  end;
end;

function TLspClient.WriterLeft: Boolean;
begin
  Result := FTransport.WriterLeft;
end;

function TLspClient.EngineProcessId: Cardinal;
begin
  Result := FTransport.ProcessId;
end;

procedure TLspClient.StopEngine;
var
  Asker: TThread;
  Asked, Answered: Boolean;
begin
  // First the word, then the process: stopping it takes seconds, and nobody
  // has to wait for that to know.
  Retire;
  // Then the engine is ASKED to shut down - the protocol's request - and
  // only after that is its input closed. Closed with a question IN FLIGHT
  // (how the server usually stops one: under another agent's request) it
  // died of an access violation inside the compiler. Measured 2026-09-30
  // with the engine launched by hand: closing alone, 8 of 8 with a
  // definition in flight, 0 of 8 twenty milliseconds after sending it, 0 of
  // 8 after a change alone and 0 of 25 idle; with `shutdown` answered
  // first, 0 of 48. The machine's event log had 1,645 of those crashes in
  // eight days, 1,358 of them the day the server began to stop its engines.
  Asker := nil;
  Answered := False;
  try
    Asker := Ask('shutdown', SHUTDOWN_WAIT_MS, True, Answered);
  except
    // no event, no thread to be had: stopped as it always was - never left
    // running - and said below
  end;
  Asked := Asker <> nil;
  FTransport.Stop;
  // the one that asked wrote on a thread of its own (Ask): with
  // the process gone its write has returned, whatever it was waiting for
  if Asker <> nil then
    if WaitForSingleObject(Asker.Handle, 3000) = WAIT_OBJECT_0 then
      Asker.Free;
    // else left behind, as the transport leaves a reader: a leaked thread,
    // never a server that does not come back. It waits for the transport's
    // write lock, or is inside the write: the transport, which has just
    // found that writer inside, keeps what it stands on (CloseHandles)
  SayHowItEnded(Asked, Answered);
end;

{ How the engine ended goes to the server's log, once per engine, from the
  two places that see it end (StopEngine and the destructor). An engine with
  the no-dialog mode (Lsp.ErrorMode.NoErrorDialogs) dies without a line in the
  system's event log (measured 2026-09-30: a crashing program leaves an
  Application Error event without the mode and nothing with it), and that
  log is where these crashes were found. Said when it did not end clean, and
  when it was asked and SHUTDOWN_WAIT_MS went by with no answer: that is its
  input closed on whatever it was doing, as before. After the transport's
  Stop, which is what keeps the code. }
procedure TLspClient.SayHowItEnded(AAsked, AAnswered: Boolean);
const
  YesNo: array [Boolean] of string = ('no', 'yes');
var
  Code: Cardinal;
begin
  if FEndSaid then
    Exit;
  FEndSaid := True;
  Code := FTransport.ExitCode;
  if ((Code <> 0) and (Code <> STILL_ACTIVE)) or (AAsked and not AAnswered) then
    TLogger.Warning(MsgFmt(SL_LSP_ENGINE_ENDED_FMT,
      [FRootUri, Code, YesNo[AAsked], YesNo[AAnswered]]));
end;

{ Asks the engine one thing that takes no parameters and waits for its
  answer, AWaitMs at most: `shutdown` before it is stopped (StopEngine), and
  the probe of an engine that looks hung (AnswersProbe). It goes straight to
  the transport, with an entry of its own for the answer - the client may be
  stopped already for everybody else. The WRITE runs on a thread of its own:
  a write to an engine that stopped reading does not return until the
  process ends, and whoever asks must not be held by it - ending the process
  is what frees that write. With AKeepThread the thread is returned, for the
  caller to collect once the process is gone; without it the thread frees
  itself. nil when there was no process to ask. AAnswered: the ANSWER came
  (not the time, and not the word of a Retire, which wakes every entry). May
  raise - no event, no thread to be had - and leaves no entry behind when it
  does. }
function TLspClient.Ask(const AMethod: string; AWaitMs: Cardinal; AKeepThread: Boolean;
  out AAnswered: Boolean): TThread;
var
  Id: Integer;
  Call: TPendingCall;
  Json: string;
  Transport: TLspProcessTransport;
  T: TThread;
  T0: UInt64;
  Left: Int64;
begin
  Result := nil;
  AAnswered := False;
  if not FTransport.ProcessAlive then
    Exit;
  Id := NextId;
  Call := TPendingCall.Create;
  FLock.Enter;
  try
    FPending.Add(Id, Call); // dictionary owns Call
  finally
    FLock.Leave;
  end;
  try
    // Without "params": what JSON-RPC asks of a method that takes none. This
    // engine answers both forms alike (measured 2026-09-30: 8 of 8 each, in
    // 11 to 17 ms with a definition in flight); a stricter one might not.
    Json := Format('{"jsonrpc":"2.0","id":%d,"method":"%s"}', [Id, AMethod]);
    Transport := FTransport;
    T := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          Transport.SendJson(Json);
        except
          // an engine that is going, or gone: nothing to ask
        end;
      end);
    T.FreeOnTerminate := not AKeepThread;
    if AKeepThread then
      Result := T;
    T.Start; // (not touched after this: it may free itself)
    // Until the ANSWER or the time. A Retire wakes every entry, this one
    // too: woken with no answer - somebody retired the client again while
    // it was being stopped - it goes back to wait, or the engine would have
    // its input closed on a request in flight after all.
    T0 := GetTickCount64;
    repeat
      Left := Int64(AWaitMs) - Int64(GetTickCount64 - T0);
      if Left <= 0 then
        Break;
      Call.Event.WaitFor(Cardinal(Left));
      FLock.Enter;
      try
        AAnswered := Call.ResponseJson <> '';
        if not AAnswered then
          Call.Event.ResetEvent;
      finally
        FLock.Leave;
      end;
    until AAnswered;
  finally
    FLock.Enter;
    try
      AAnswered := Call.ResponseJson <> ''; // Call lives while it is in the table
      FPending.Remove(Id);
    finally
      FLock.Leave;
    end;
  end;
end;

{ THE sender: what goes to a stopped engine is refused with the words of a
  stopped engine, before and after trying. A notification sent while the
  engine was being stopped came out as the transport's own error. }
procedure TLspClient.Send(const AJson: string);
begin
  if FStopped then
    raise ELspClient.Create(MsgText(SR_LSP_ENGINE_STOPPED));
  // a write is something in flight: an engine that stopped reading keeps it
  // inside the transport for as long as the pipe is full (see Hung)
  BeginWait;
  try
    try
      FTransport.SendJson(AJson);
    except
      if FStopped then
        raise ELspClient.Create(MsgText(SR_LSP_ENGINE_STOPPED));
      raise;
    end;
  finally
    EndWait;
  end;
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
  // whatever the engine says is a sign of life (see Hung)
  FLock.Enter;
  try
    FWaitingSince := GetTickCount64;
  finally
    FLock.Leave;
  end;
  Msg := ObjetoJson(AJson);
  if Msg = nil then
    Exit;
  try
    IdVal := Msg.GetValue('id');
    if (IdVal <> nil) and not (IdVal is TJSONNull) then
    begin
      if Msg.GetValue('method') <> nil then
      begin
        // Server->client request: answer null so the server never blocks on us.
        Send(Format('{"jsonrpc":"2.0","id":%s,"result":null}',
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
  Signaled: Boolean;
begin
  Id := NextId;
  Call := TPendingCall.Create;
  FLock.Enter;
  try
    if FStopped then
    begin
      Call.Free;
      raise ELspClient.Create(MsgText(SR_LSP_ENGINE_STOPPED));
    end;
    FPending.Add(Id, Call); // dictionary owns Call
  finally
    FLock.Leave;
  end;

  try
    Send(Format('{"jsonrpc":"2.0","id":%d,"method":"%s","params":%s}',
      [Id, AMethod, AParamsJson]));
  except
    // what was not sent waits for nothing: its entry stayed for the life of
    // the client
    FLock.Enter;
    try
      FPending.Remove(Id);
    finally
      FLock.Leave;
    end;
    raise;
  end;

  // the wait for the answer is something in flight (see Hung)
  BeginWait;
  try
    Signaled := Call.Event.WaitFor(ATimeoutMs) = wrSignaled;
  finally
    EndWait;
  end;
  if not Signaled then
  begin
    FLock.Enter;
    try
      FPending.Remove(Id);
    finally
      FLock.Leave;
    end;
    raise ELspClient.Create(MsgFmt(SE_LSP_LSP_REQUEST_TIMED_OUT_FMT,
      [AMethod, ATimeoutMs]));
  end;

  FLock.Enter;
  try
    Raw := Call.ResponseJson;
    FPending.Remove(Id);
  finally
    FLock.Leave;
  end;
  // woken with no answer: the engine was stopped under this request
  if (Raw = '') and FStopped then
    raise ELspClient.Create(MsgText(SR_LSP_ENGINE_STOPPED));
  Result := ObjetoJson(Raw);
  if Result = nil then
    raise ELspClient.Create(MsgFmt(SE_LSP_LSP_RESPONSE_VALID_JSON_FMT, [AMethod]));
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
  Send(Format('{"jsonrpc":"2.0","method":"%s","params":%s}',
    [AMethod, AParamsJson]));
end;

function TLspClient.Initialize(const ARootUri: string;
  AServerType: TLspServerType; AAgentCount, ATimeoutMs: Integer): TJSONObject;
const
  TypeNames: array [TLspServerType] of string = ('agent', 'linter', 'controller');
var
  Params: string;
begin
  FRootUri := ARootUri;
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

{ The engine forgets the document: from here on it reads that unit from the
  disk when a question crosses it, as it does with one never opened. }
procedure TLspClient.DidClose(const AUri: string);
begin
  Notify('textDocument/didClose', Format('{"textDocument":{"uri":"%s"}}', [AUri]));
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
  begin
    // As JSON, not as it comes: a quote or a backslash in it made the whole
    // request unparseable, and the engine answers NOTHING to a request it
    // cannot parse (measured 2026-09-30: not one message in 6 s) - the
    // caller waited out its 30 s.
    var Quoted := TJSONString.Create(ATriggerCharacter);
    try
      Ctx := Format(',"context":{"triggerKind":2,"triggerCharacter":%s}', [Quoted.ToJSON]);
    finally
      Quoted.Free;
    end;
  end
  else
    Ctx := ',"context":{"triggerKind":1}';
  Result := RequestWithRetry('textDocument/completion', Format(
    '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}%s}',
    [AUri, ALine, ACharacter, Ctx]), 30000);
end;

{ Whoever waits for a notification is USING the engine (Busy): a lint waits
  for its diagnostics here, and an engine "nobody uses" must not be stopped
  under it. }
function TLspClient.WaitForNotification(const AMethod: string;
  ATimeoutMs: Integer; const AUriFilter: string): TJSONObject;
begin
  FLock.Enter;
  try
    Inc(FWaiters);
  finally
    FLock.Leave;
  end;
  try
    Result := DoWaitForNotification(AMethod, ATimeoutMs, AUriFilter);
  finally
    FLock.Enter;
    try
      Dec(FWaiters);
    finally
      FLock.Leave;
    end;
  end;
end;

function TLspClient.DoWaitForNotification(const AMethod: string;
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
    // a stopped engine notifies nothing: nil here would read as "it took too
    // long", and it is not that
    if FStopped then
      raise ELspClient.Create(MsgText(SR_LSP_ENGINE_STOPPED));
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
    // In SLICES, and one more look after the last one: the event wakes ONE
    // waiter. With two on the same client (two agents linting two files of
    // one project) the other one slept out its whole wait - told nothing of
    // an engine that had been stopped, and with its own notification in the
    // queue if the one woken was not the one it was for.
    if Remaining > NOTIFY_SLICE_MS then
      Remaining := NOTIFY_SLICE_MS;
    FNotifyEvent.WaitFor(Remaining);
  until False;
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
  Bytes := LeeBytes(AFilePath, LUGARES_DEL_MOTOR);
  // Un .dfm BINARIO se sirve como texto (Lsp.DesignerBin): delphi_search no
  // encontraba ni el nombre del form en uno legacy (Hermes, 2026-09-24). Si
  // esta danado, se devuelve vacio: nada que buscar ahi.
  if EsRutaDeDesigner(AFilePath) and IsBinaryDesignerBytes(Bytes) then
  begin
    if DesignerBinaryToText(Bytes, Result) <> '' then
      Result := '';
    Exit;
  end;
  // Sin BOM NO significa CP1252. Darlo por hecho convertia en mojibake
  // TODO fichero UTF-8 sin BOM: delphi_search sobre los .md de este mismo
  // repo devolvia basura por cada raya (medido el 20-sep-2026 usando el
  // servidor como agente), y ese texto corrupto es el que un agente copia
  // para construir un ancla. Por aqui pasa ademas lo que se le manda al
  // linter y lo que lee delphi_references. Decide el MISMO detector que usa
  // delphi_read, y SOLO el: el 20-sep se le delego el caso sin BOM y aqui
  // se quedaron tres ramas propias para los BOM (UTF-8 y UTF-16), asi que
  // search leia un .dfm en UTF-16 y delphi_read no (24-sep-2026). Ahora los
  // BOM los conoce Lsp.Patch.DetectEnc y aqui no se decide nada (tampoco
  // que un form de texto sin BOM es ANSI: se le dice que es un form).
  Result := DecodeSourceBytes(Bytes, EsRutaDeDesigner(AFilePath));
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
