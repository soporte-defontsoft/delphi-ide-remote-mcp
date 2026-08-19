unit Lsp.BuildRunner;

{ Real builds through MSBuild - the LSP has no build operation, so this runs
  on the machine that owns the compiler: rsvars.bat (located via registry
  discovery, never hardcoded) + msbuild in one cmd.exe process, output
  captured and distilled into errors/warnings for a remote agent. }

interface

uses
  System.JSON;

function RunMsBuild(const ADprojPath, APlatform, AConfig, ATarget: string;
  ATimeoutMs: Integer = 600000): TJSONObject;

{ Runs a command line with stdout+stderr captured (no shell). }
function RunCaptured(const ACmdLine: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;

{ Same, with an explicit working directory ('' = inherit). }
function RunCapturedIn(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Lsp.Discovery,
  Lsp.Guard;

function RunCaptured(const ACmdLine: string; ATimeoutMs: Integer;
  out AExitCode: DWORD): string;
begin
  Result := RunCapturedIn(ACmdLine, '', ATimeoutMs, AExitCode);
end;

function RunCapturedIn(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;
var
  SA: TSecurityAttributes;
  ReadH, WriteH: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  Buffer: array [0 .. 65535] of Byte;
  BytesRead, Avail: DWORD;
  Bytes: TBytes;
  Cmd: string;
  Deadline: UInt64;
begin
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  if not CreatePipe(ReadH, WriteH, @SA, 0) then
    raise Exception.Create('CreatePipe failed');
  SetHandleInformation(ReadH, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdOutput := WriteH;
  SI.hStdError := WriteH;
  SI.hStdInput := 0;

  Cmd := ACmdLine;
  UniqueString(Cmd);
  FillChar(PI, SizeOf(PI), 0);
  var WorkDirPtr: PChar := nil;
  if AWorkDir <> '' then
    WorkDirPtr := PChar(AWorkDir);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW,
    nil, WorkDirPtr, SI, PI) then
  begin
    CloseHandle(ReadH);
    CloseHandle(WriteH);
    raise Exception.CreateFmt('CreateProcess failed (%d)', [GetLastError]);
  end;
  CloseHandle(WriteH); // ours no more; EOF arrives when the child exits

  SetLength(Bytes, 0);
  Deadline := GetTickCount64 + UInt64(ATimeoutMs);
  try
    repeat
      if not ReadFile(ReadH, Buffer, SizeOf(Buffer), BytesRead, nil) then
        Break;
      if BytesRead = 0 then
        Break;
      var Prev := Length(Bytes);
      SetLength(Bytes, Prev + Integer(BytesRead));
      Move(Buffer[0], Bytes[Prev], BytesRead);
      if GetTickCount64 > Deadline then
      begin
        TerminateProcess(PI.hProcess, 1);
        Break;
      end;
    until False;
    WaitForSingleObject(PI.hProcess, 10000);
    if not GetExitCodeProcess(PI.hProcess, AExitCode) then
      AExitCode := DWORD(-1);
  finally
    CloseHandle(ReadH);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
  // Console output is in the ANSI/OEM codepage; ANSI is close enough for
  // compiler messages and never throws.
  Result := TEncoding.ANSI.GetString(Bytes);
end;

function RunMsBuild(const ADprojPath, APlatform, AConfig, ATarget: string;
  ATimeoutMs: Integer): TJSONObject;
var
  Info: TRadStudioInfo;
  Output, Line, Plat, Cfg, Target: string;
  ExitCode: DWORD;
  Errors, Warnings: TJSONArray;
  Tail: TStringBuilder;
  Lines: TArray<string>;
  I, TailFrom: Integer;
begin
  var Denied := PathDenied(ADprojPath);
  if Denied <> '' then
    raise Exception.Create(Denied);
  if not FileExists(ADprojPath) then
    raise Exception.CreateFmt('.dproj not found: %s', [ADprojPath]);
  Info := DiscoverRadStudio;
  if not Info.Found then
    raise Exception.Create('No RAD Studio installation discovered.');
  if not FileExists(Info.RsVarsBat) then
    raise Exception.CreateFmt('rsvars.bat not found: %s', [Info.RsVarsBat]);

  Plat := APlatform;
  if Plat = '' then
    Plat := 'Win32';
  Cfg := AConfig;
  if Cfg = '' then
    Cfg := 'Debug';
  Target := ATarget;
  if Target = '' then
    Target := 'Build';

  Output := RunCaptured(Format(
    'cmd.exe /c ""%s" && msbuild "%s" /t:%s /p:Config=%s /p:Platform=%s /v:minimal /nologo"',
    [Info.RsVarsBat, TPath.GetFullPath(ADprojPath), Target, Cfg, Plat]),
    ATimeoutMs, ExitCode);

  Errors := TJSONArray.Create;
  Warnings := TJSONArray.Create;
  Lines := Output.Split([#13#10, #10]);
  for Line in Lines do
  begin
    if Line.Contains(': error ') or Line.Contains(' error E') or
       Line.Contains(' error MSB') or Line.Contains('fatal error') or
       Line.Contains(': fatal ') then
      Errors.Add(Line.Trim)
    else if Line.Contains(': warning ') or Line.Contains(' warning W') then
      Warnings.Add(Line.Trim);
  end;

  // Keep the last ~25 lines as raw context (summary, timings).
  Tail := TStringBuilder.Create;
  try
    TailFrom := Length(Lines) - 25;
    if TailFrom < 0 then
      TailFrom := 0;
    for I := TailFrom to High(Lines) do
      if Lines[I].Trim <> '' then
        Tail.AppendLine(Lines[I].TrimRight);

    Result := TJSONObject.Create;
    Result.AddPair('success', TJSONBool.Create(ExitCode = 0));
    Result.AddPair('exitCode', TJSONNumber.Create(Integer(ExitCode)));
    Result.AddPair('project', TPath.GetFullPath(ADprojPath));
    Result.AddPair('platform', Plat);
    Result.AddPair('config', Cfg);
    Result.AddPair('target', Target);
    Result.AddPair('errors', Errors);
    Result.AddPair('warnings', Warnings);
    Result.AddPair('outputTail', Tail.ToString);
  finally
    Tail.Free;
  end;
end;

end.
