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
  // el SymbolKind de LSP de un campo (Field), en el arbol de documentSymbol
  SYMBOL_KIND_FIELD = 8;

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
    // los caracteres de disparo de completion que anuncia el motor (Initialize)
    FTriggersDeCompletion: TArray<string>;
    // las LINEAS del texto que tiene el motor de cada documento que se le
    // abrio (lo ultimo que se le mando por didOpen o didChange), por su uri en
    // la forma que se compara (UriCanonica): con ellas se pasa una columna a
    // la cuenta del motor y de vuelta (ColumnaAlMotor). Bajo FLock
    FLineas: TDictionary<string, TArray<string>>;
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
    procedure GuardaLineas(const AUri, AText: string);
    { Las lineas que tiene el motor de AUri: las que se le mandaron o, si no
      lo tiene abierto, las del disco por EL lector (el motor lo lee y lo
      decodifica bien: medido en ANSI y en UTF-8, con BOM y sin el). Nil si no
      se deja leer: esa columna se queda en la cuenta del motor. Nunca lanza. }
    function LineasDelMotor(const AUri: string): TArray<string>;
    { EL compositor de los params de una peticion con posicion (hover,
      definition, declaration, implementation, signature, completion): la
      columna del agente, en la cuenta del motor. Estaba escrito seis veces. }
    function ParamsDePosicion(const AUri: string; ALine, ACharacter: Integer;
      const AMas: string = ''): string;
    { Cada Position (line, character) de lo que contesta o notifica el motor,
      a la columna del agente, con la linea de SU documento: la uri (o
      targetUri) del objeto que la contiene o, si no hay, AUri (el documento
      preguntado). En su sitio; AValor nil no hace nada. }
    procedure PosicionesDelMotor(AValor: TJSONValue; const AUri: string);
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
    { Los caracteres con los que el motor dice que completa: los de su
      respuesta a initialize (capabilities.completionProvider.
      triggerCharacters; el agente de la 37.0 anuncia . ( < [, medido el
      20-oct-2026). Vacio si no anuncio nada - el linter no anuncia
      completion. Se llena en Initialize, antes de que nadie use el cliente. }
    property TriggersDeCompletion: TArray<string> read FTriggersDeCompletion;

    { Document sync }
    procedure DidOpenText(const AUri, AText: string; AVersion: Integer = 1);
    procedure DidOpenFile(const AFilePath: string);
    { Full-document change (DelphiLSP announces textDocumentSync=1 = full). }
    procedure DidChangeText(const AUri, AText: string; AVersion: Integer);
    procedure DidClose(const AUri: string);

    { Language features (positions are 0-based, LSP style). La columna, en lo
      que toman y en lo que devuelven, es la del AGENTE (UTF-16, como cuentan
      delphi_read y delphi_search): el cliente la pasa a la cuenta del motor y
      de vuelta (ColumnaAlMotor), tambien en los diagnosticos que notifica. }
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
    { LA negativa de una ruta que no se le puede NOMBRAR al motor (LSP-044):
      medio caracter -un sustituto suelto, por EL lector- no cabe en una uri
      UTF-8, y GetBytes lo escribia como U+FFFD en silencio: el motor
      contestaba de otra ruta. '' si se puede. La lanza PathToUri a todo el
      que le pida esa uri y la dicen antes, con su texto, la regla de las
      tools del motor (NoEsFuenteDelphi) y references por cada candidato
      (W5 del revisor de cierre: solo el borde la decia). }
    class function RutaSinUri(const APath: string): string;
    class function PathToUri(const APath: string): string;
    class function UriToPath(const AUri: string): string;
    { Los bytes de la ruta de una uri file:// (sin el esquema): los %XX, el
      byte; lo demas, en UTF-8. Los decodifica UriToPath (laxa) y los juzga
      UriCanonica (la ida y vuelta): un solo lector de la forma. }
    class function UriABytes(const AUri: string): TArray<Byte>;
    { Una uri en la forma de EL nombrador (PathToUri de su inversa): la que
      se compara. DelphiLSP escribe TAL CUAL lo que no es ASCII (a<enye>o) y
      PathToUri lo escapa (%C3%B1): comparadas como texto, el mismo fichero
      eran dos - los diagnosticos de un proyecto bajo una carpeta con enye no
      llegaban nunca y su declaracion salia homonima de si misma (revisor de
      version de la 1.18.1, medido). }
    class function UriCanonica(const AUri: string): string;
    { True si la ruta lleva un caracter mas alla de U+FFFF (un par de
      sustitutos: un emoji). DelphiLSP la PIERDE: contesta la definicion SIN
      carpeta (LSP-043) y publica un lint VACIO (LSP-045) - medido en crudo
      el 14-oct con el motor solo, el de bin\ que lanza este servidor; con
      una enye hace las dos cosas bien. Lo que puede saberse ANTES de
      arrancar un motor para nada se pregunta aqui; la respuesta sin carpeta
      la sigue juzgando quien la recibe (UriSinCarpeta). }
    class function MotorPierdeLaRuta(const APath: string): Boolean;
    { El texto de un fuente tal como se le da al motor y lo leen references y
      search, por EL detector. Pregunta ELLA a la puerta, con los lugares del
      motor (Lsp.Patch.LUGARES_DEL_MOTOR: la jaula, el IDE y su biblioteca):
      cargaba sin preguntar lo que le pasasen, tambien una ruta que daba el
      MOTOR (references, la definicion de un candidato: medida M1). Fuera de
      ahi lanza la negativa. Quien recorre carpetas pregunta ADEMAS la de la
      jaula por cada fichero: lo de detras de una union no es suyo. }
    class function LoadSourceText(const AFilePath: string): string;
    { LA columna del motor y su inversa. DelphiLSP cuenta la columna de una
      linea en BYTES UTF-8 del texto que tiene de ella, a la ida y a la vuelta
      (medido el 22-oct-2026 con el motor solo: una enye +1, un euro +2 y un
      emoji +2 sobre UTF-16, en hover, definition, documentSymbol y
      publishDiagnostics, con la unidad abierta por didOpen o leida por el del
      disco, en ANSI o en UTF-8; y no declara positionEncoding, ni ofreciendole
      utf-16 ni utf-8). El agente, delphi_read y delphi_search cuentan en
      UTF-16, la de LSP: con un acento delante en la linea, cada tool por
      posicion apuntaba al simbolo de al lado (test completo de la 1.22.0 en
      Hermes). ColumnaAlMotor pasa la columna UTF-16 ACol de ALinea a bytes y
      ColumnaDelMotor la de bytes a UTF-16, las dos con EL codificador UTF-8 de
      la RTL. Un caracter partido (medio par de sustitutos, un byte de en medio
      de una secuencia) cuenta desde donde empieza; lo que pasa del final de la
      linea sigue pasando lo mismo, y 0 o menos va tal cual. }
    class function ColumnaAlMotor(const ALinea: string; ACol: Integer): Integer;
    class function ColumnaDelMotor(const ALinea: string; ACol: Integer): Integer;
  end;

{ Los hijos de un nodo del arbol de documentSymbol (nil si no tiene): EL
  lector de ese arbol, de delphi_symbols y de references (vivia en
  Mcp.Tools.DelphiLsp; references lo necesito para V181 de la 1.23.1). }
function SymChildren(const ANode: TJSONObject): TJSONArray;

implementation

uses
  Lsp.Patch,
  Lsp.DesignerBin,
  System.StrUtils,
  MCPServer.Logger,
  Lsp.Texts, // DecodeSourceBytes: el detector de encoding de delphi_read
  Lsp.Json,  // ObjetoJson: EL lector de un JSON que tiene que ser un objeto
  Lsp.Codificacion,
  System.Character,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.NetDrives;

function SymChildren(const ANode: TJSONObject): TJSONArray;
var
  C: TJSONValue;
begin
  C := ANode.GetValue('children');
  if C is TJSONArray then
    Result := TJSONArray(C)
  else
    Result := nil;
end;

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
  FLineas := TDictionary<string, TArray<string>>.Create;
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
  FLineas.Free;
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
  // lo que el motor anuncia para completion: el juez de un trigger
  // (delphi_completion lo dice cuando el que le dan no es de estos)
  FTriggersDeCompletion := [];
  var Lista := Result.FindValue('result.capabilities.completionProvider.triggerCharacters');
  if Lista is TJSONArray then
    for var V in TJSONArray(Lista) do
      FTriggersDeCompletion := FTriggersDeCompletion + [V.Value];
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
    GuardaLineas(AUri, AText); // tras el envio: lo que no llego no lo tiene el motor
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
    GuardaLineas(AUri, AText);
  finally
    Change.Free;
  end;
end;

{ The engine forgets the document: from here on it reads that unit from the
  disk when a question crosses it, as it does with one never opened. }
procedure TLspClient.DidClose(const AUri: string);
begin
  Notify('textDocument/didClose', Format('{"textDocument":{"uri":"%s"}}', [AUri]));
  // desde aqui el motor lo lee del disco, y su columna se cuenta con el disco
  var K := UriCanonica(AUri);
  FLock.Enter;
  try
    FLineas.Remove(K);
  finally
    FLock.Leave;
  end;
end;

function TLspClient.Hover(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/hover', ParamsDePosicion(AUri, ALine, ACharacter), 30000);
  PosicionesDelMotor(Result, AUri);
end;

function TLspClient.Definition(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/definition', ParamsDePosicion(AUri, ALine, ACharacter), 30000);
  PosicionesDelMotor(Result, AUri);
end;

function TLspClient.Declaration(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/declaration', ParamsDePosicion(AUri, ALine, ACharacter), 30000);
  PosicionesDelMotor(Result, AUri);
end;

function TLspClient.Implementation_(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/implementation', ParamsDePosicion(AUri, ALine, ACharacter), 30000);
  PosicionesDelMotor(Result, AUri);
end;

function TLspClient.SignatureHelp(const AUri: string; ALine, ACharacter: Integer): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/signatureHelp', ParamsDePosicion(AUri, ALine, ACharacter), 30000);
  PosicionesDelMotor(Result, AUri);
end;

function TLspClient.DocumentSymbols(const AUri: string): TJSONObject;
begin
  Result := RequestWithRetry('textDocument/documentSymbol',
    Format('{"textDocument":{"uri":"%s"}}', [AUri]), 60000);
  PosicionesDelMotor(Result, AUri);
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
  Result := RequestWithRetry('textDocument/completion', ParamsDePosicion(AUri, ALine, ACharacter, Ctx), 30000);
  PosicionesDelMotor(Result, AUri);
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
    // los rangos de un diagnostico, en la columna del agente (la uri, la suya)
    PosicionesDelMotor(Result, '');
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
  // la forma que se compara, una vez y fuera del cerrojo
  var Filtro := '';
  if AUriFilter <> '' then
    Filtro := UriCanonica(AUriFilter);
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
          if (UriVal = nil) or
             not SameText(UriCanonica(UriVal.Value), Filtro) then
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
  // lo que no se puede nombrar no se escribe a medias (W5 del revisor de
  // cierre: el nombrador lo escribia como U+FFFD en silencio para los
  // candidatos de references, el proyecto y los search paths de los ajustes,
  // la raiz del Initialize y didChange/didClose)
  var Negativa := RutaSinUri(APath);
  if Negativa <> '' then
    raise ELspClient.Create(Negativa);
  Normalized := ConBarrasNormales(APath);
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

class function TLspClient.UriCanonica(const AUri: string): string;
begin
  // nunca lanza: corre bajo el cerrojo de las notificaciones, y una uri con
  // escapes que no son UTF-8 (%C3 solo) dejaba la cola atascada en ella
  // (revisor de version de la 1.18.1); asi, tal cual, no casa con nada.
  // UriToPath es LAXA (el byte malo, U+FFFD): dos uris rotas distintas serian
  // la MISMA al compararlas, y la de un fichero con U+FFFD en su nombre. Lo
  // dice EL juez de la ida y vuelta (BytesVuelvenIgual), no una lista
  // ...y medio caracter suelto en la uri tampoco: UriABytes lo volvia U+FFFD
  // ANTES del juez, y dos uris rotas distintas (o la de un fichero real con
  // U+FFFD) eran la misma (M6 de los revisores de cierre); tal cual, no casa
  var I := 1;
  if SiguienteSuelto(AUri, I) <> #0 then
    Exit(AUri);
  if not BytesVuelvenIgual(UriABytes(AUri), ekUtf8) then
    Exit(AUri);
  try
    Result := PathToUri(UriToPath(AUri));
  except
    on EEncodingError do
      Result := AUri;
  end;
end;

class function TLspClient.RutaSinUri(const APath: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  var Suelto := SiguienteSuelto(APath, I);
  if Suelto <> #0 then
    Result := MsgFmt(SR_LSP_RUTA_SIN_URI_FMT, [ExtractFileName(APath),
      MsgFmt(SF_EDIT_SUSTITUTO_SUELTO_FMT, [IntToHex(Ord(Suelto), 4)])]);
end;

class function TLspClient.MotorPierdeLaRuta(const APath: string): Boolean;
begin
  // un par de sustitutos lo reconoce la RTL: ni lista de emojis ni rangos
  for var I := 1 to Length(APath) - 1 do
    if APath[I].IsHighSurrogate and APath[I + 1].IsLowSurrogate then
      Exit(True);
  Result := False;
end;

class function TLspClient.UriToPath(const AUri: string): string;
begin
  // LAXO, por EL decodificador de la casa (DecodeBytes, ekUtf8): una uri rota
  // (%FF, medio caracter) LANZABA EEncodingError - el UTF-8 de la RTL es
  // estricto - y salia un SYS-006 que no decia nada (punto 5 de la 1.18.2);
  // ahora el byte malo es U+FFFD en una ruta que se ve, y lo de despues dice
  // que no existe
  Result := ConBarrasDeWindows(DecodeBytes(UriABytes(AUri), ekUtf8));
end;

class function TLspClient.UriABytes(const AUri: string): TArray<Byte>;
var
  S: string;
  I, J: Integer;
  Bytes: TBytes;
begin
  S := AUri;
  if SinMayusculas(S).StartsWith('file:///') then
    S := S.Substring(8)
  else if SinMayusculas(S).StartsWith('file://') then
    S := S.Substring(7);

  // Percent-decode into UTF-8 bytes, then decode. Lo que NO viene escapado,
  // en sus bytes UTF-8, por tramos (un par de sustitutos va junto): DelphiLSP
  // manda los caracteres que no son ASCII TAL CUAL (file:///.../a<enye>o/...;
  // los ASCII reservados si los escapa, %28 %20 - medido el 10-oct-2026), y
  // Byte(AnsiChar(S[I])) los pasaba por la pagina ANSI: un $F1 suelto que el
  // UTF-8 estricto no lee, SYS-006 en definition, references y hover de todo
  // proyecto bajo una carpeta con una enye (revisor de version de la 1.18.1)
  Bytes := nil;
  I := 1;
  while I <= Length(S) do
  begin
    // %XX solo con DOS cifras hexadecimales: StrToIntDef de '%zz' se comia
    // los dos caracteres detras del '%' (revisor de version de la 1.18.1)
    if (S[I] = '%') and (I + 2 <= Length(S)) and
       CharInSet(S[I + 1], ['0'..'9', 'A'..'F', 'a'..'f']) and
       CharInSet(S[I + 2], ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      Bytes := Bytes + [Byte(StrToInt('$' + Copy(S, I + 1, 2)))];
      Inc(I, 3);
    end
    else
    begin
      J := I;
      while (J <= Length(S)) and (S[J] <> '%') do
        Inc(J);
      if J = I then
        Inc(J); // un '%' sin sus dos cifras hexadecimales, como un caracter mas
      Bytes := Bytes + TEncoding.UTF8.GetBytes(Copy(S, I, J - I));
      I := J;
    end;
  end;
  Result := Bytes;
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

class function TLspClient.ColumnaAlMotor(const ALinea: string; ACol: Integer): Integer;
var
  N, Exceso: Integer;
begin
  if ACol <= 0 then
    Exit(ACol);
  N := ACol;
  Exceso := 0;
  if N > Length(ALinea) then
  begin
    Exceso := N - Length(ALinea);
    N := Length(ALinea);
  end
  else if (N < Length(ALinea)) and ALinea[N].IsHighSurrogate and ALinea[N + 1].IsLowSurrogate then
    Dec(N); // en medio de un par de sustitutos: desde donde empieza el caracter
  Result := TEncoding.UTF8.GetByteCount(Copy(ALinea, 1, N)) + Exceso;
end;

class function TLspClient.ColumnaDelMotor(const ALinea: string; ACol: Integer): Integer;
var
  I, Ancho, Bytes, Cuenta: Integer;
begin
  if ACol <= 0 then
    Exit(ACol);
  I := 1;
  Cuenta := 0;
  while I <= Length(ALinea) do
  begin
    Ancho := 1;
    if (I < Length(ALinea)) and ALinea[I].IsHighSurrogate and ALinea[I + 1].IsLowSurrogate then
      Ancho := 2;
    Bytes := TEncoding.UTF8.GetByteCount(Copy(ALinea, I, Ancho));
    if Cuenta + Bytes > ACol then
      Exit(I - 1); // un byte de en medio del caracter: desde donde empieza
    Inc(Cuenta, Bytes);
    Inc(I, Ancho);
    if Cuenta = ACol then
      Exit(I - 1);
  end;
  Result := Length(ALinea) + (ACol - Cuenta); // pasa del final: lo mismo que pasaba
end;

procedure TLspClient.GuardaLineas(const AUri, AText: string);
var
  K: string;
  Lineas: TArray<string>;
begin
  K := UriCanonica(AUri);
  Lineas := LineasDelTexto(AText); // como las cuenta delphi_read
  FLock.Enter;
  try
    FLineas.AddOrSetValue(K, Lineas);
  finally
    FLock.Leave;
  end;
end;

function TLspClient.LineasDelMotor(const AUri: string): TArray<string>;
var
  K: string;
  Hay: Boolean;
begin
  K := UriCanonica(AUri);
  FLock.Enter;
  try
    Hay := FLineas.TryGetValue(K, Result);
  finally
    FLock.Leave;
  end;
  if Hay then
    Exit;
  try
    Result := LineasDelTexto(LoadSourceText(UriToPath(AUri)));
  except
    Result := nil;
  end;
end;

function TLspClient.ParamsDePosicion(const AUri: string; ALine, ACharacter: Integer;
  const AMas: string): string;
var
  Lineas: TArray<string>;
  Col: Integer;
begin
  Col := ACharacter;
  if Col > 0 then
  begin
    Lineas := LineasDelMotor(AUri);
    if (ALine >= 0) and (ALine < Length(Lineas)) then
      Col := ColumnaAlMotor(Lineas[ALine], Col);
  end;
  Result := Format('{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}%s}',
    [AUri, ALine, Col, AMas]);
end;

procedure TLspClient.PosicionesDelMotor(AValor: TJSONValue; const AUri: string);
var
  Lineas: TDictionary<string, TArray<string>>;

  function LineaDe(const ADoc: string; ALinea: Integer): string;
  var
    Ls: TArray<string>;
  begin
    if not Lineas.TryGetValue(ADoc, Ls) then
    begin
      Ls := LineasDelMotor(ADoc);
      Lineas.Add(ADoc, Ls);
    end;
    if (ALinea >= 0) and (ALinea < Length(Ls)) then
      Result := Ls[ALinea]
    else
      Result := '';
  end;

  procedure Recorre(V: TJSONValue; const ADoc: string);
  var
    O: TJSONObject;
    VL, VC, VU: TJSONValue;
    Doc: string;
    Par: TJSONPair;
  begin
    if V is TJSONArray then
    begin
      for var Item in TJSONArray(V) do
        Recorre(Item, ADoc);
      Exit;
    end;
    if not (V is TJSONObject) then
      Exit;
    O := TJSONObject(V);
    VL := O.GetValue('line');
    VC := O.GetValue('character');
    if (O.Count = 2) and (VL is TJSONNumber) and (VC is TJSONNumber) then
    begin
      var C := TJSONNumber(VC).AsInt;
      if (C > 0) and (ADoc <> '') then
      begin
        var Nueva := ColumnaDelMotor(LineaDe(ADoc, TJSONNumber(VL).AsInt), C);
        O.RemovePair('character').Free;
        O.AddPair('character', TJSONNumber.Create(Nueva));
      end;
      Exit;
    end;
    // un Location (uri), un LocationLink (targetUri) o los diagnosticos de un
    // documento (uri): sus rangos son de ESE documento; el
    // originSelectionRange de un LocationLink, del que se pregunto
    Doc := ADoc;
    VU := O.GetValue('uri');
    if VU = nil then
      VU := O.GetValue('targetUri');
    if VU is TJSONString then
      Doc := VU.Value;
    for Par in O do
      if Par.JsonString.Value = 'originSelectionRange' then
        Recorre(Par.JsonValue, AUri)
      else
        Recorre(Par.JsonValue, Doc);
  end;

begin
  if AValor = nil then
    Exit;
  // una por documento y respuesta: un documentSymbol trae cientos
  Lineas := TDictionary<string, TArray<string>>.Create;
  try
    Recorre(AValor, AUri);
  finally
    Lineas.Free;
  end;
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
