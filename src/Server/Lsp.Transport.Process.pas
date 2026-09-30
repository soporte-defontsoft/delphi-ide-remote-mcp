unit Lsp.Transport.Process;

{ Child-process transport for a Language Server speaking JSON-RPC over stdio
  with LSP Content-Length framing.

  - Spawns the LSP executable with redirected stdin/stdout (stderr -> NUL so
    stray log output can never corrupt the frame stream).
  - A dedicated reader thread parses frames and hands each complete JSON
    message (as UTF-8 decoded string) to OnMessage. The callback runs in the
    reader thread: consumers must do their own locking.
  - Writes are serialized with a critical section. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Winapi.Windows;

const
  // How long Stop waits for the reader to see the end of its pipe before it
  // cancels the read. Public: a stop that takes this long is how a test
  // tells that somebody else held the pipe (LspTests.Motor).
  READER_EOF_WAIT_MS = 1000;

type
  TLspMessageEvent = reference to procedure(const AJson: string);

  ELspTransport = class(Exception);

  TLspProcessTransport = class
  private
    FExePath: string;
    FProcInfo: TProcessInformation;
    FChildStdInWrite: THandle;
    FChildStdOutRead: THandle;
    FNulHandle: THandle;
    FReader: TThread;
    FOnMessage: TLspMessageEvent;
    FWriteLock: TCriticalSection;
    FRunning: Boolean;
    FAbandoned: Boolean; // the reader was left behind: see Stop and FreeInstance
    FWriterLeft: Boolean; // a writer was left behind inside SendJson: see CloseHandles
    FEnded: Boolean;      // Stop saw the process end, and kept what it ended with
    FExitCode: Cardinal;
    procedure ReaderLoop;
    procedure CloseHandles;
    function CloseStdIn(AWaitMs: Cardinal): Boolean;
  public
    constructor Create(const AExePath: string);
    destructor Destroy; override;
    { A transport whose reader was left behind (Stop) keeps its MEMORY: that
      thread runs on this object, and freed memory under a thread that may
      still wake is worse than a leaked object. }
    procedure FreeInstance; override;
    procedure Start;
    procedure Stop;
    procedure SendJson(const AJson: string);
    function ProcessAlive: Boolean;
    { What the process ended with: STILL_ACTIVE while it runs or when there
      never was one, 1 when Stop had to end it, otherwise the engine's own
      code - 0 for a clean exit, an exception code when it died (measured
      2026-09-30: $C0000005 when its input was closed while it was busy). }
    function ExitCode: Cardinal;
    property OnMessage: TLspMessageEvent read FOnMessage write FOnMessage;
    property Running: Boolean read FRunning;
    property ExePath: string read FExePath;
  end;

implementation

uses
  Lsp.Sandbox, // EnterSpawn / LeaveSpawn: one handle-inheriting launch at a time
  Lsp.ErrorMode, // NoErrorDialogs
  Lsp.Texts;

const
  READ_CHUNK = 65536;

{ TLspProcessTransport }

constructor TLspProcessTransport.Create(const AExePath: string);
begin
  inherited Create;
  FExePath := AExePath;
  FWriteLock := TCriticalSection.Create;
  FChildStdInWrite := INVALID_HANDLE_VALUE;
  FChildStdOutRead := INVALID_HANDLE_VALUE;
  FNulHandle := INVALID_HANDLE_VALUE;
end;

destructor TLspProcessTransport.Destroy;
begin
  Stop;
  if not FWriterLeft then
    FWriteLock.Free;
  inherited;
end;

procedure TLspProcessTransport.FreeInstance;
begin
  if FAbandoned then
    Exit;
  inherited;
end;

procedure TLspProcessTransport.Start;
var
  SA: TSecurityAttributes;
  ChildStdInRead, ChildStdOutWrite: THandle;
  SI: TStartupInfo;
  CmdLine: string;
begin
  if FRunning then
    Exit;
  if not FileExists(FExePath) then
    raise ELspTransport.Create(MsgFmt(SE_LSP_LSP_EXECUTABLE_FOUND_FMT, [FExePath]));

  // From the pipes to the closing of the child's ends, nobody else launches:
  // another child would take these ends with it (see Lsp.Sandbox).
  EnterSpawn;
  try
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;

  if not CreatePipe(FChildStdOutRead, ChildStdOutWrite, @SA, 0) then
    raise ELspTransport.Create(MsgText(SE_LSP_CREATEPIPE_STDOUT_FAILED));
  SetHandleInformation(FChildStdOutRead, HANDLE_FLAG_INHERIT, 0);

  if not CreatePipe(ChildStdInRead, FChildStdInWrite, @SA, 0) then
  begin
    CloseHandle(FChildStdOutRead);
    CloseHandle(ChildStdOutWrite);
    raise ELspTransport.Create(MsgText(SE_LSP_CREATEPIPE_STDIN_FAILED));
  end;
  SetHandleInformation(FChildStdInWrite, HANDLE_FLAG_INHERIT, 0);

  // stderr -> NUL: DelphiLSP must never pollute the framed stdout stream,
  // and inheriting our own stderr would mix its logs into the console.
  FNulHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_WRITE, @SA,
    OPEN_EXISTING, 0, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdInput := ChildStdInRead;
  SI.hStdOutput := ChildStdOutWrite;
  SI.hStdError := FNulHandle;

  FillChar(FProcInfo, SizeOf(FProcInfo), 0);
  CmdLine := '"' + FExePath + '"';
  UniqueString(CmdLine); // CreateProcessW may modify the buffer

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, SI, FProcInfo) then
  begin
    CloseHandle(ChildStdInRead);
    CloseHandle(ChildStdOutWrite);
    CloseHandles;
    raise ELspTransport.Create(MsgFmt(SE_LSP_CREATEPROCESS_FAILED_FMT,
      [GetLastError, FExePath]));
  end;

  // Suspended until it is told never to open an error dialog (Lsp.ErrorMode).
  NoErrorDialogs(FProcInfo.hProcess);
  ResumeThread(FProcInfo.hThread);

  // These ends now belong to the child.
  CloseHandle(ChildStdInRead);
  CloseHandle(ChildStdOutWrite);
  finally
    LeaveSpawn;
  end;

  FRunning := True;
  FReader := TThread.CreateAnonymousThread(ReaderLoop);
  FReader.FreeOnTerminate := False;
  FReader.Start;
end;

procedure TLspProcessTransport.Stop;
begin
  // By what there IS, not by FRunning: the reader clears that flag when it
  // ends by itself, and a stop that left at once then neither ended a
  // process that was still alive nor collected the thread (2026-09-29).
  FRunning := False;

  if FProcInfo.hProcess <> 0 then
  begin
    // Closing the child's stdin signals EOF; give it a moment, then force.
    // A writer stuck in the pipe (an engine that stopped reading) holds the
    // lock: ending the process breaks the pipe and lets that writer go.
    if not CloseStdIn(2000) then
      TerminateProcess(FProcInfo.hProcess, 1);
    if WaitForSingleObject(FProcInfo.hProcess, 2000) = WAIT_TIMEOUT then
    begin
      TerminateProcess(FProcInfo.hProcess, 1);
      // TerminateProcess only ASKS. What the process held - its current
      // directory, the reason an engine is stopped before its folder moves -
      // is released when it has really ended.
      WaitForSingleObject(FProcInfo.hProcess, 3000);
    end;
    // what it ended with is kept: the handle is closed below
    FEnded := GetExitCodeProcess(FProcInfo.hProcess, FExitCode) and (FExitCode <> STILL_ACTIVE);
  end;

  if Assigned(FReader) then
  begin
    // The reader ends when the pipe breaks, and the pipe breaks when the
    // LAST write end closes. If somebody else holds one (measured
    // 2026-09-29: another child that inherited it) the read never returns:
    // it is cancelled, and the join is BOUNDED. Stop used to run only when
    // the server stopped; now it runs in a request thread that holds the
    // global write lock, and a wait with no end there hangs every writer.
    if WaitForSingleObject(FReader.Handle, READER_EOF_WAIT_MS) = WAIT_TIMEOUT then
    begin
      CancelIoEx(FChildStdOutRead, nil);
      if WaitForSingleObject(FReader.Handle, 3000) = WAIT_TIMEOUT then
      begin
        // Left behind, with the handle it reads from: a leaked thread and a
        // leaked handle, never a hung server. It delivers nothing more (the
        // client it delivered to may be freed), and this object is never
        // released under it (FreeInstance).
        FAbandoned := True;
        FOnMessage := nil;
        FReader := nil;
        FChildStdOutRead := INVALID_HANDLE_VALUE;
      end;
    end;
    if Assigned(FReader) then
    begin
      FReader.WaitFor;
      FreeAndNil(FReader);
    end;
  end;
  CloseHandles;
end;

{ Under the write lock: a writer on another thread either finishes before the
  handle closes or finds it closed - never a closed handle VALUE, which
  Windows may already have handed to somebody else. Since 2026-09-29 a client
  can be stopped while another agent's request is in flight (the session
  retires the clients of a folder that is about to be moved).

  The wait is BOUNDED: WriteFile on a pipe blocks while the engine does not
  read, and a writer blocked there keeps the lock. False = not closed, a
  writer is still inside; the caller ends the process, which frees it. }
function TLspProcessTransport.CloseStdIn(AWaitMs: Cardinal): Boolean;
var
  T0: UInt64;
begin
  // nothing to close: never opened, closed already, or left to a writer that
  // is stuck inside (CloseHandles) - whose lock is not waited for again
  if FChildStdInWrite = INVALID_HANDLE_VALUE then
    Exit(True);
  T0 := GetTickCount64;
  Result := FWriteLock.TryEnter;
  while (not Result) and (GetTickCount64 - T0 < AWaitMs) do
  begin
    Sleep(10);
    Result := FWriteLock.TryEnter;
  end;
  if not Result then
    Exit;
  try
    if FChildStdInWrite <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(FChildStdInWrite);
      FChildStdInWrite := INVALID_HANDLE_VALUE;
    end;
  finally
    FWriteLock.Leave;
  end;
end;

procedure TLspProcessTransport.CloseHandles;
begin
  // By now the engine is gone (or never started). A writer that is STILL
  // inside its write - the process ended and the write did not return:
  // somebody else holds the other end of the pipe - is left behind WITH the
  // handle, as the reader is (Stop). Closing a handle under a blocked
  // synchronous write waits for that write (measured 2026-09-30 on a bare
  // pipe: CloseHandle still waiting at 4 s, 3 of 3; it came back when the
  // read end was closed), and a stop that does not come back holds whoever
  // asked for it - with the global write lock, when a folder is leaving.
  // This object then keeps its memory and its write lock, which that thread
  // holds (FreeInstance, Destroy).
  if not CloseStdIn(5000) then
  begin
    FWriterLeft := True;
    FAbandoned := True;
    FChildStdInWrite := INVALID_HANDLE_VALUE;
  end;
  if FChildStdOutRead <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FChildStdOutRead);
    FChildStdOutRead := INVALID_HANDLE_VALUE;
  end;
  if FNulHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FNulHandle);
    FNulHandle := INVALID_HANDLE_VALUE;
  end;
  if FProcInfo.hProcess <> 0 then
  begin
    CloseHandle(FProcInfo.hProcess);
    CloseHandle(FProcInfo.hThread);
    FillChar(FProcInfo, SizeOf(FProcInfo), 0);
  end;
end;

function TLspProcessTransport.ProcessAlive: Boolean;
var
  Code: DWORD;
begin
  Result := (FProcInfo.hProcess <> 0) and
    GetExitCodeProcess(FProcInfo.hProcess, Code) and (Code = STILL_ACTIVE);
end;

function TLspProcessTransport.ExitCode: Cardinal;
begin
  if FEnded then
    Result := FExitCode
  else if (FProcInfo.hProcess = 0) or not GetExitCodeProcess(FProcInfo.hProcess, Result) then
    Result := STILL_ACTIVE;
end;

procedure TLspProcessTransport.SendJson(const AJson: string);
var
  Body, Frame: TBytes;
  Header: AnsiString;
  Written: DWORD;
begin
  if FChildStdInWrite = INVALID_HANDLE_VALUE then
    raise ELspTransport.Create(MsgText(SE_LSP_TRANSPORT_STARTED));

  Body := TEncoding.UTF8.GetBytes(AJson);
  Header := AnsiString(Format('Content-Length: %d'#13#10#13#10, [Length(Body)]));

  SetLength(Frame, Length(Header) + Length(Body));
  Move(PAnsiChar(Header)^, Frame[0], Length(Header));
  if Length(Body) > 0 then
    Move(Body[0], Frame[Length(Header)], Length(Body));

  FWriteLock.Enter;
  try
    // asked again HERE: Stop may have closed it since the check above
    if FChildStdInWrite = INVALID_HANDLE_VALUE then
      raise ELspTransport.Create(MsgText(SE_LSP_TRANSPORT_STARTED));
    if not WriteFile(FChildStdInWrite, Frame[0], Length(Frame), Written, nil) then
      raise ELspTransport.Create(MsgFmt(SE_LSP_WRITEFILE_LSP_STDIN_FAILED_FMT, [GetLastError]));
  finally
    FWriteLock.Leave;
  end;
end;

procedure TLspProcessTransport.ReaderLoop;
var
  Buffer: array [0 .. READ_CHUNK - 1] of Byte;
  Acc: TBytes;
  BytesRead: DWORD;

  function FindHeaderEnd: Integer; // index AFTER CRLFCRLF, or -1
  var
    I: Integer;
  begin
    Result := -1;
    for I := 0 to Length(Acc) - 4 do
      if (Acc[I] = 13) and (Acc[I + 1] = 10) and (Acc[I + 2] = 13) and (Acc[I + 3] = 10) then
        Exit(I + 4);
  end;

  function ParseContentLength(const AHeader: string): Integer;
  var
    Line: string;
  begin
    Result := -1;
    for Line in AHeader.Split([#13#10]) do
      if Line.ToLower.StartsWith('content-length:') then
        Exit(StrToIntDef(Line.Substring(15).Trim, -1));
  end;

var
  HeaderEnd, ContentLen, Total: Integer;
  HeaderText, BodyText: string;
begin
  SetLength(Acc, 0);
  while FRunning do
  begin
    if not ReadFile(FChildStdOutRead, Buffer, READ_CHUNK, BytesRead, nil) then
      Break; // broken pipe: child exited
    if BytesRead = 0 then
      Break;

    var Prev := Length(Acc);
    SetLength(Acc, Prev + Integer(BytesRead));
    Move(Buffer[0], Acc[Prev], BytesRead);

    // Extract every complete frame currently buffered.
    repeat
      HeaderEnd := FindHeaderEnd;
      if HeaderEnd < 0 then
        Break;
      HeaderText := TEncoding.ASCII.GetString(Acc, 0, HeaderEnd);
      ContentLen := ParseContentLength(HeaderText);
      if ContentLen < 0 then
      begin
        // Malformed header: drop it to resync rather than loop forever.
        Acc := Copy(Acc, HeaderEnd, Length(Acc) - HeaderEnd);
        Continue;
      end;
      Total := HeaderEnd + ContentLen;
      if Length(Acc) < Total then
        Break; // body incomplete, wait for more bytes

      BodyText := TEncoding.UTF8.GetString(Acc, HeaderEnd, ContentLen);
      Acc := Copy(Acc, Total, Length(Acc) - Total);

      // nothing is delivered once the stop has begun
      if FRunning and Assigned(FOnMessage) then
      try
        FOnMessage(BodyText);
      except
        // A consumer bug must not kill the reader thread.
      end;
    until False;
  end;
  FRunning := False;
end;

end.
