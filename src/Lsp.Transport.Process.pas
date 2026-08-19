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
    procedure ReaderLoop;
    procedure CloseHandles;
  public
    constructor Create(const AExePath: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure SendJson(const AJson: string);
    function ProcessAlive: Boolean;
    property OnMessage: TLspMessageEvent read FOnMessage write FOnMessage;
    property Running: Boolean read FRunning;
    property ExePath: string read FExePath;
  end;

implementation

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
  FWriteLock.Free;
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
    raise ELspTransport.CreateFmt('LSP executable not found: %s', [FExePath]);

  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;

  if not CreatePipe(FChildStdOutRead, ChildStdOutWrite, @SA, 0) then
    raise ELspTransport.Create('CreatePipe (stdout) failed');
  SetHandleInformation(FChildStdOutRead, HANDLE_FLAG_INHERIT, 0);

  if not CreatePipe(ChildStdInRead, FChildStdInWrite, @SA, 0) then
  begin
    CloseHandle(FChildStdOutRead);
    CloseHandle(ChildStdOutWrite);
    raise ELspTransport.Create('CreatePipe (stdin) failed');
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
    CREATE_NO_WINDOW, nil, nil, SI, FProcInfo) then
  begin
    CloseHandle(ChildStdInRead);
    CloseHandle(ChildStdOutWrite);
    CloseHandles;
    raise ELspTransport.CreateFmt('CreateProcess failed (%d) for %s',
      [GetLastError, FExePath]);
  end;

  // These ends now belong to the child.
  CloseHandle(ChildStdInRead);
  CloseHandle(ChildStdOutWrite);

  FRunning := True;
  FReader := TThread.CreateAnonymousThread(ReaderLoop);
  FReader.FreeOnTerminate := False;
  FReader.Start;
end;

procedure TLspProcessTransport.Stop;
begin
  if not FRunning then
  begin
    CloseHandles;
    Exit;
  end;
  FRunning := False;

  // Closing the child's stdin signals EOF; give it a moment, then force.
  if FChildStdInWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FChildStdInWrite);
    FChildStdInWrite := INVALID_HANDLE_VALUE;
  end;
  if WaitForSingleObject(FProcInfo.hProcess, 2000) = WAIT_TIMEOUT then
    TerminateProcess(FProcInfo.hProcess, 1);

  if Assigned(FReader) then
  begin
    FReader.WaitFor;
    FreeAndNil(FReader);
  end;
  CloseHandles;
end;

procedure TLspProcessTransport.CloseHandles;
begin
  if FChildStdInWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FChildStdInWrite);
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

procedure TLspProcessTransport.SendJson(const AJson: string);
var
  Body, Frame: TBytes;
  Header: AnsiString;
  Written: DWORD;
begin
  if FChildStdInWrite = INVALID_HANDLE_VALUE then
    raise ELspTransport.Create('Transport not started');

  Body := TEncoding.UTF8.GetBytes(AJson);
  Header := AnsiString(Format('Content-Length: %d'#13#10#13#10, [Length(Body)]));

  SetLength(Frame, Length(Header) + Length(Body));
  Move(PAnsiChar(Header)^, Frame[0], Length(Header));
  if Length(Body) > 0 then
    Move(Body[0], Frame[Length(Header)], Length(Body));

  FWriteLock.Enter;
  try
    if not WriteFile(FChildStdInWrite, Frame[0], Length(Frame), Written, nil) then
      raise ELspTransport.CreateFmt('WriteFile to LSP stdin failed (%d)', [GetLastError]);
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

      if Assigned(FOnMessage) then
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
