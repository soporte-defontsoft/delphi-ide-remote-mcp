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

{ Like RunCapturedIn but launches the process at LOW integrity (filesystem
  write confinement for delphi_run). AWorkDir is labelled Low so the program
  can write its own output there and nowhere else on the system. ASandboxed
  reports whether the low-integrity launch actually took effect. }
function RunCapturedSandboxed(const ACmdLine, AWorkDir: string;
  ATimeoutMs: Integer; out AExitCode: Cardinal; out ASandboxed: Boolean): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  MCPServer.Logger,
  Lsp.Discovery,
  Lsp.Guard,
  Lsp.Dproj,
  Lsp.Texts,
  Lsp.Sandbox;

function RunCaptured(const ACmdLine: string; ATimeoutMs: Integer;
  out AExitCode: DWORD): string;
begin
  Result := RunCapturedIn(ACmdLine, '', ATimeoutMs, AExitCode);
end;

{ A Job Object that confines a launched process TREE. What it guarantees:
  - kill-on-close: when we close the job, the whole tree dies - no orphaned
    compiler/child processes survive a timeout or the server shutdown
    (measured concern B0b: build spawns cmd->msbuild->dcc);
  - a process count cap (fork-bomb protection) and a per-process memory cap
    (runaway protection);
  - UI restrictions: the tree cannot change system-wide settings, exit
    Windows, or touch the display.
  It does NOT sandbox the filesystem - a compiled program can still write
  wherever the service account can. True per-directory confinement
  (AppContainer / a restricted token) is a separate, larger step; the jail
  plus this Job Object bound the DAMAGE, not the file access. }
{$IF not declared(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)}
const
  JOB_OBJECT_LIMIT_ACTIVE_PROCESS = $00000008;
  JOB_OBJECT_LIMIT_PROCESS_MEMORY = $00000100;
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;
  JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION = $00000400;
  JOB_OBJECT_UILIMIT_EXITWINDOWS = $00000080;
  JOB_OBJECT_UILIMIT_SYSTEMPARAMETERS = $00000004;
  JOB_OBJECT_UILIMIT_DISPLAYSETTINGS = $00000010;
  JobObjectExtendedLimitInformation = 9;
  JobObjectBasicUIRestrictions = 4;
{$ENDIF}

function CreateConfinedJob: THandle;
type
  TIoCounters = record
    ReadOperationCount, WriteOperationCount, OtherOperationCount: UInt64;
    ReadTransferCount, WriteTransferCount, OtherTransferCount: UInt64;
  end;
  TBasicLimit = record
    PerProcessUserTimeLimit, PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize, MaximumWorkingSetSize: NativeUInt;
    ActiveProcessLimit: DWORD;
    Affinity: NativeUInt;
    PriorityClass, SchedulingClass: DWORD;
  end;
  TExtLimit = record
    BasicLimitInformation: TBasicLimit;
    IoInfo: TIoCounters;
    ProcessMemoryLimit, JobMemoryLimit: NativeUInt;
    PeakProcessMemoryUsed, PeakJobMemoryUsed: NativeUInt;
  end;
  TUiRestrictions = record
    UIRestrictionsClass: DWORD;
  end;
var
  Ext: TExtLimit;
  Ui: TUiRestrictions;
begin
  Result := CreateJobObject(nil, nil);
  if Result = 0 then
    Exit;
  FillChar(Ext, SizeOf(Ext), 0);
  Ext.BasicLimitInformation.LimitFlags :=
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE or
    JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION or
    JOB_OBJECT_LIMIT_ACTIVE_PROCESS or
    JOB_OBJECT_LIMIT_PROCESS_MEMORY;
  Ext.BasicLimitInformation.ActiveProcessLimit := 128;
  Ext.ProcessMemoryLimit := NativeUInt(3) * 1024 * 1024 * 1024; // 3 GB/process
  SetInformationJobObject(Result, JobObjectExtendedLimitInformation, @Ext, SizeOf(Ext));
  Ui.UIRestrictionsClass := JOB_OBJECT_UILIMIT_EXITWINDOWS or
    JOB_OBJECT_UILIMIT_SYSTEMPARAMETERS or JOB_OBJECT_UILIMIT_DISPLAYSETTINGS;
  SetInformationJobObject(Result, JobObjectBasicUIRestrictions, @Ui, SizeOf(Ui));
end;

{ Strict UTF-8 scanner over the captured bytes: only well-formed multi-byte
  sequences count, and pure ASCII answers False (the ANSI default is fine
  there). An ANSI accent almost never forms a valid UTF-8 sequence, so a
  positive here is reliable. }
function LooksUtf8(const B: TBytes): Boolean;
var
  I, J, N: Integer;
  HasHigh: Boolean;
begin
  HasHigh := False;
  I := 0;
  while I < Length(B) do
  begin
    if B[I] < $80 then
    begin
      Inc(I);
      Continue;
    end;
    HasHigh := True;
    if (B[I] and $E0) = $C0 then
      N := 1
    else if (B[I] and $F0) = $E0 then
      N := 2
    else if (B[I] and $F8) = $F0 then
      N := 3
    else
      Exit(False);
    if I + N >= Length(B) then
      Exit(False);
    for J := 1 to N do
      if (B[I + J] and $C0) <> $80 then
        Exit(False);
    Inc(I, N + 1);
  end;
  Result := HasHigh;
end;

function RunCore(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  ALowIntegrity: Boolean; out AExitCode: Cardinal; out ASandboxed: Boolean): string;
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
  Launched: Boolean;
begin
  ASandboxed := False;
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
  // Create SUSPENDED so we can put the process into a confining Job Object
  // BEFORE it runs (otherwise a fast child could spawn a grandchild that
  // escapes the job). Then resume.
  var Job: THandle := CreateConfinedJob;
  Launched := False;
  if ALowIntegrity then
  begin
    // Label the working directory Low so the confined program can write its
    // OWN output there (and nowhere else on the system), then launch at Low
    // integrity. Relabel EXISTING entries too, so a file created earlier at
    // Medium (a log/csv/ini next to the exe) stays writable by the confined
    // run instead of an unexplained "Acceso denegado" (field round 6, R6-C).
    // If the OS refuses the lowered launch, fall back to a normal launch and
    // report ASandboxed=False - never leave the caller thinking a confinement
    // is in place when it is not.
    if AWorkDir <> '' then
      LabelDirTreeLowIntegrity(AWorkDir);
    if CreateProcessLowIntegrity(Cmd, WorkDirPtr,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, True, SI, PI) then
    begin
      Launched := True;
      ASandboxed := True;
    end;
  end;
  if not Launched then
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, WorkDirPtr, SI, PI) then
    begin
      if Job <> 0 then CloseHandle(Job);
      CloseHandle(ReadH);
      CloseHandle(WriteH);
      raise Exception.CreateFmt('CreateProcess failed (%d)', [GetLastError]);
    end;
  if Job <> 0 then
    AssignProcessToJobObject(Job, PI.hProcess);
  ResumeThread(PI.hThread);
  CloseHandle(WriteH); // ours no more; EOF arrives when the child exits

  SetLength(Bytes, 0);
  Deadline := GetTickCount64 + UInt64(ATimeoutMs);
  try
    // Drain the pipe by POLLING, never a blocking ReadFile: a child that
    // hangs WITHOUT producing output would block ReadFile forever and the
    // deadline check would never run (measured concern in third-party
    // review). PeekNamedPipe tells us if there is data before we read, so the
    // timeout is honoured even on a silent hang.
    var TimedOut := False;
    repeat
      Avail := 0;
      if not PeekNamedPipe(ReadH, nil, 0, nil, @Avail, nil) then
        Break; // write end closed -> child exited, EOF
      if Avail > 0 then
      begin
        if not ReadFile(ReadH, Buffer, SizeOf(Buffer), BytesRead, nil) then
          Break;
        if BytesRead = 0 then
          Break;
        var Prev := Length(Bytes);
        SetLength(Bytes, Prev + Integer(BytesRead));
        Move(Buffer[0], Bytes[Prev], BytesRead);
      end
      else
      begin
        // no data right now: has the process finished, or timed out?
        if WaitForSingleObject(PI.hProcess, 50) = WAIT_OBJECT_0 then
        begin
          // drain whatever is still buffered, then stop
          if PeekNamedPipe(ReadH, nil, 0, nil, @Avail, nil) and (Avail = 0) then
            Break;
        end;
      end;
      if GetTickCount64 > Deadline then
      begin
        TimedOut := True;
        TerminateProcess(PI.hProcess, 1);
        Break;
      end;
    until False;
    if not TimedOut then
      WaitForSingleObject(PI.hProcess, 10000);
    if not GetExitCodeProcess(PI.hProcess, AExitCode) then
      AExitCode := DWORD(-1);
  finally
    CloseHandle(ReadH);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    // Closing the job kills any process in the tree still alive (e.g. children
    // orphaned by a timeout): kill-on-close leaves nothing running behind us.
    if Job <> 0 then
      CloseHandle(Job);
  end;
  // git and modern tools emit UTF-8 (measured mojibake in remote field
  // test: "AÃ±ade" for "Añade"); compilers emit ANSI/OEM. Strictly valid
  // UTF-8 with high bytes IS UTF-8; anything else stays ANSI, which is
  // close enough for compiler messages and never throws.
  if LooksUtf8(Bytes) then
    Result := TEncoding.UTF8.GetString(Bytes)
  else
    Result := TEncoding.ANSI.GetString(Bytes);
end;

function RunCapturedIn(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;
var
  Ignored: Boolean;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, False, AExitCode, Ignored);
end;

function RunCapturedSandboxed(const ACmdLine, AWorkDir: string;
  ATimeoutMs: Integer; out AExitCode: Cardinal; out ASandboxed: Boolean): string;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, True, AExitCode, ASandboxed);
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
  // Compile-only guarantee: a build must not EXECUTE code. Scan the project for
  // shell-running MSBuild constructs (a planted <Target><Exec>, a build-event,
  // a foreign <Import>) and refuse unless execution was explicitly enabled.
  // This is the point-of-execution gate, so it holds however the .dproj got
  // there - upload, edit, or a pre-existing one (field round 7, CRITICAL).
  if not AllowRun then
  begin
    var ProjXml := '';
    try ProjXml := TFile.ReadAllText(ADprojPath); except end;
    var Hazard := DprojBuildHazard(ProjXml, TPath.GetFullPath(ADprojPath));
    if Hazard <> '' then
    begin
      TLogger.Warning(Format('delphi_build: REFUSED "%s" - %s',
        [TPath.GetFullPath(ADprojPath), Hazard]));
      raise Exception.Create(Format(SR_BUILD_HAZARD_FMT, [Hazard]));
    end;
  end;
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

  // Security audit trail: a build can run arbitrary pre/post-build steps
  // declared in the .dproj, so record every one.
  TLogger.Warning(Format('delphi_build: BUILD "%s" %s/%s target=%s',
    [TPath.GetFullPath(ADprojPath), Plat, Cfg, Target]));

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
