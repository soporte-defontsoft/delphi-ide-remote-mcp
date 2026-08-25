unit Lsp.BuildRunner;

{ Real builds through MSBuild - the LSP has no build operation, so this runs
  on the machine that owns the compiler: rsvars.bat (located via registry
  discovery, never hardcoded) + msbuild in one cmd.exe process, output
  captured and distilled into errors/warnings for a remote agent. }

interface

uses
  System.JSON;

function RunMsBuild(const ADprojPath, APlatform, AConfig, ATarget: string;
  const AProfile: string = ''; const ADeviceId: string = '';
  ATimeoutMs: Integer = 600000): TJSONObject;

{ Runs a command line with stdout+stderr captured (no shell). }
{ Generates the deployment manifest (.deployproj + its import line in the
  .dproj) when the project has none - minimal for PAServer platforms, the full
  staging map for Android; never touches an existing one. Exposed for
  delphi_config add-deployfile, which needs a manifest to add entries to. }
procedure EnsureDeployManifest(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean);

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

{ Same, and says whether the process was KILLED for running out of time.
  Without this a killed process was indistinguishable from one that failed
  instantly: same exitCode 1, same empty output (measured 2026-08-25). }
function RunCapturedSandboxedT(const ACmdLine, AWorkDir: string;
  ATimeoutMs: Integer; out AExitCode: Cardinal; out ASandboxed: Boolean;
  out ATimedOut: Boolean): string;

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
  System.RegularExpressions,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Lsp.Patch,
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
  ALowIntegrity: Boolean; out AExitCode: Cardinal; out ASandboxed: Boolean;
  out ATimedOut: Boolean): string;
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
    ATimedOut := TimedOut;
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
  Ignored, IgnoredToo: Boolean;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, False, AExitCode, Ignored,
    IgnoredToo);
end;

function RunCapturedSandboxed(const ACmdLine, AWorkDir: string;
  ATimeoutMs: Integer; out AExitCode: Cardinal; out ASandboxed: Boolean): string;
var
  Ignored: Boolean;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, True, AExitCode, ASandboxed,
    Ignored);
end;

function RunCapturedSandboxedT(const ACmdLine, AWorkDir: string;
  ATimeoutMs: Integer; out AExitCode: Cardinal; out ASandboxed: Boolean;
  out ATimedOut: Boolean): string;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, True, AExitCode, ASandboxed,
    ATimedOut);
end;

{ The Android staging map, measured against an IDE-written .deployproj
  (GalateaFMX) and a live msbuild run: for Android the DeployFile list IS
  the apk layout - each file lands in APK_RootDir at RemoteDir - and the
  Embarcadero pipeline (CreateAndroidManifestFile, manifest merger, aapt2,
  dexer, packager, debug signing) does ALL the assembly itself; classes.dex
  never even appears in the list. Generated resources come out of the
  platform output dir, artwork and libnative stubs out of $(BDS). }
type
  TApkEntry = record
    Src, Dir, Name, Cls: string;
  end;

const
  // Generated by BuildAndroidManifestList into <Platform>\<Config>\ BEFORE
  // _DeployFiles stages them (target order inside one Deploy - measured).
  APK_RES: array[0..6] of TApkEntry = (
    (Src: 'colors.xml'; Dir: 'res\values\'; Name: 'colors.xml'; Cls: 'Android_Colors'),
    (Src: 'colors-night-v21.xml'; Dir: 'res\values-night-v21\'; Name: 'colors.xml'; Cls: 'Android_ColorsDark'),
    (Src: 'strings.xml'; Dir: 'res\values\'; Name: 'strings.xml'; Cls: 'Android_Strings'),
    (Src: 'styles.xml'; Dir: 'res\values\'; Name: 'styles.xml'; Cls: 'AndroidSplashStyles'),
    (Src: 'styles-v21.xml'; Dir: 'res\values-v21\'; Name: 'styles.xml'; Cls: 'AndroidSplashStylesV21'),
    (Src: 'styles-v35.xml'; Dir: 'res\values-v35\'; Name: 'styles.xml'; Cls: 'AndroidSplashStylesV35'),
    (Src: 'splash_image_def.xml'; Dir: 'res\drawable\'; Name: 'splash_image_def.xml'; Cls: 'AndroidSplashImageDef'));
  // Static product files ($(BDS)\...): default icons, splash, notification
  // artwork and the legacy-ABI stub libraries - the same set the IDE lists.
  // Name '*' means lib<project>.so. Each is added only if it exists.
  APK_BDS: array[0..18] of TApkEntry = (
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_36x36.png'; Dir: 'res\drawable-ldpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon36'),
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_48x48.png'; Dir: 'res\drawable-mdpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon48'),
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_72x72.png'; Dir: 'res\drawable-hdpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon72'),
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_96x96.png'; Dir: 'res\drawable-xhdpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon96'),
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_144x144.png'; Dir: 'res\drawable-xxhdpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon144'),
    (Src: 'bin\Artwork\Android\FM_LauncherIcon_192x192.png'; Dir: 'res\drawable-xxxhdpi\'; Name: 'ic_launcher.png'; Cls: 'Android_LauncherIcon192'),
    (Src: 'bin\Artwork\Android\FM_NotificationIcon_24x24.png'; Dir: 'res\drawable-mdpi\'; Name: 'ic_notification.png'; Cls: 'Android_NotificationIcon24'),
    (Src: 'bin\Artwork\Android\FM_NotificationIcon_36x36.png'; Dir: 'res\drawable-hdpi\'; Name: 'ic_notification.png'; Cls: 'Android_NotificationIcon36'),
    (Src: 'bin\Artwork\Android\FM_NotificationIcon_48x48.png'; Dir: 'res\drawable-xhdpi\'; Name: 'ic_notification.png'; Cls: 'Android_NotificationIcon48'),
    (Src: 'bin\Artwork\Android\FM_NotificationIcon_72x72.png'; Dir: 'res\drawable-xxhdpi\'; Name: 'ic_notification.png'; Cls: 'Android_NotificationIcon72'),
    (Src: 'bin\Artwork\Android\FM_NotificationIcon_96x96.png'; Dir: 'res\drawable-xxxhdpi\'; Name: 'ic_notification.png'; Cls: 'Android_NotificationIcon96'),
    (Src: 'bin\Artwork\Android\FM_VectorizedNotificationIcon.xml'; Dir: 'res\drawable-anydpi-v24\'; Name: 'ic_notification.xml'; Cls: 'Android_VectorizedNotificationIcon'),
    (Src: 'bin\Artwork\Android\FM_SplashImage_426x320.png'; Dir: 'res\drawable-small\'; Name: 'splash_image.png'; Cls: 'Android_SplashImage426'),
    (Src: 'bin\Artwork\Android\FM_SplashImage_470x320.png'; Dir: 'res\drawable-normal\'; Name: 'splash_image.png'; Cls: 'Android_SplashImage470'),
    (Src: 'bin\Artwork\Android\FM_SplashImage_640x480.png'; Dir: 'res\drawable-large\'; Name: 'splash_image.png'; Cls: 'Android_SplashImage640'),
    (Src: 'bin\Artwork\Android\FM_SplashImage_960x720.png'; Dir: 'res\drawable-xlarge\'; Name: 'splash_image.png'; Cls: 'Android_SplashImage960'),
    (Src: 'lib\android\debug\armeabi\libnative-activity.so'; Dir: 'library\lib\armeabi\'; Name: '*'; Cls: 'AndroidLibnativeArmeabiFile'),
    (Src: 'lib\android\debug\armeabi-v7a\libnative-activity.so'; Dir: 'library\lib\armeabi-v7a\'; Name: '*'; Cls: 'AndroidLibnativeArmeabiv7aFile'),
    (Src: 'lib\android\debug\mips\libnative-activity.so'; Dir: 'library\lib\mips\'; Name: '*'; Cls: 'AndroidLibnativeMipsFile'));

  // The fallback properties an Android build needs: version keys to
  // generate a valid AndroidManifest (empty %package%/%minSdkVersion% kill
  // the manifest merger - measured) and the pre-dexed system jar list that
  // feeds BuildClassesDex (without it the apk assembles WITHOUT classes.dex
  // and the device refuses it with "code is missing" - measured on a real
  // Android 8.1). Every property is conditioned on being empty, so anything
  // the IDE ever writes into the project wins.
  ANDROID_PROPS =
    '<PropertyGroup Condition="''$(Platform)''==''%s''">' + sLineBreak +
    '%s    <VerInfo_Keys Condition="''$(VerInfo_Keys)''==''''">package=com.embarcadero.$(MSBuildProjectName);' +
    'label=$(MSBuildProjectName);versionCode=1;versionName=1.0.0;persistent=False;' +
    'restoreAnyVersion=False;installLocation=auto;largeHeap=False;theme=TitleBar;' +
    'hardwareAccelerated=true;apiKey=;minSdkVersion=23;targetSdkVersion=35</VerInfo_Keys>' + sLineBreak +
    '%s    <VerInfo_IncludeVerInfo Condition="''$(VerInfo_IncludeVerInfo)''==''''">true</VerInfo_IncludeVerInfo>' + sLineBreak +
    '%s    <EnabledSysJars Condition="''$(EnabledSysJars)''==''''">%s</EnabledSysJars>' + sLineBreak +
    '%s    <BT_BuildType Condition="''$(BT_BuildType)''==''''">Debug</BT_BuildType>' + sLineBreak +
    '%s</PropertyGroup>';

function AndroidDeployXml(const AName, APlat, ABdsRoot: string): string;
var
  SB: TStringBuilder;
  Cfg, Abi, OutName: string;
  E: TApkEntry;

  procedure Add(const AInclude, ADir, AFile, ACls: string; ARequired: Boolean);
  begin
    SB.AppendLine('        <DeployFile Include="' + AInclude + '">');
    SB.AppendLine('            <RemoteDir>' + AName + '\' + ADir + '</RemoteDir>');
    SB.AppendLine('            <RemoteName>' + AFile + '</RemoteName>');
    SB.AppendLine('            <DeployClass>' + ACls + '</DeployClass>');
    SB.AppendLine('            <Operation>1</Operation>');
    SB.AppendLine('            <LocalCommand/>');
    SB.AppendLine('            <RemoteCommand/>');
    SB.AppendLine('            <Overwrite>True</Overwrite>');
    if ARequired then
      SB.AppendLine('            <Required>True</Required>');
    SB.AppendLine('        </DeployFile>');
  end;

begin
  if SameText(APlat, 'Android64') then
    Abi := 'arm64-v8a'
  else
    Abi := 'armeabi-v7a';
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    SB.AppendLine('    <Import Condition="Exists(''$(BDS)\bin\CodeGear.Deployment.targets'')" ' +
      'Project="$(BDS)\bin\CodeGear.Deployment.targets"/>');
    SB.AppendLine('    <ProjectExtensions>');
    SB.AppendLine('        <ProjectFileVersion>12</ProjectFileVersion>');
    SB.AppendLine('    </ProjectExtensions>');
    for Cfg in TArray<string>.Create('Debug', 'Release') do
    begin
      SB.AppendLine('    <ItemGroup Condition="''$(Platform)''==''' + APlat +
        ''' And ''$(Config)''==''' + Cfg + '''">');
      Add(APlat + '\' + Cfg + '\AndroidManifest.xml', '', 'AndroidManifest.xml',
        'ProjectAndroidManifest', True);
      Add(APlat + '\' + Cfg + '\lib' + AName + '.so', 'library\lib\' + Abi + '\',
        'lib' + AName + '.so', 'ProjectOutput', True);
      for E in APK_RES do
        Add(APlat + '\' + Cfg + '\' + E.Src, E.Dir, E.Name, E.Cls, False);
      for E in APK_BDS do
        if TFile.Exists(TPath.Combine(ABdsRoot, E.Src)) then
        begin
          if E.Name = '*' then
            OutName := 'lib' + AName + '.so'
          else
            OutName := E.Name;
          Add('$(BDS)\' + E.Src, E.Dir, OutName, E.Cls, False);
        end;
      SB.AppendLine('    </ItemGroup>');
    end;
    SB.AppendLine('</Project>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Target=Deploy needs the project's deployment manifest (<name>.deployproj):
  the .dproj imports it when present, and IT is who imports
  CodeGear.Deployment.targets - without one, msbuild fails with MSB4057
  "Deploy does not exist" (measured on Linux AND Android). The IDE's
  Deployment Manager writes rich manifests; when none exists this generates
  one - minimal (the project output) for PAServer platforms, the full
  measured staging map for Android - and NEVER touches an existing file
  (that one is the IDE's). For Android it also seeds the
  AndroidManifest.template.xml the IDE would write (copied from the
  product's ObjRepos, not invented) and the fallback version properties. }
{ The IDE's DeployFile block for the project output of one config. The
  Include follows the project's real DCC_ExeOutput (Compiled\Linux64\Debug\X
  when delphi_config set-output was used), like the IDE writes it. }
function OutputDeployEntry(const ADprojXml, APlat, ACfg, AName: string): string;
var
  OutDir, Ext, Include: string;
begin
  OutDir := MergeProperty(ADprojXml, 'DCC_ExeOutput');
  if OutDir.Trim = '' then
    OutDir := '$(Platform)\$(Config)';
  OutDir := OutDir.Replace('$(Platform)', APlat, [rfReplaceAll, rfIgnoreCase])
    .Replace('$(Config)', ACfg, [rfReplaceAll, rfIgnoreCase]).Trim;
  if OutDir.StartsWith('.\') then
    OutDir := OutDir.Substring(2);
  Ext := '';
  if APlat.StartsWith('Win', True) then
    Ext := '.exe';
  Include := IncludeTrailingPathDelimiter(OutDir) + AName + Ext;
  Result :=
    '        <DeployFile Include="' + Include + '" Condition="''$(Config)''==''' + ACfg + '''">'#13#10 +
    '            <RemoteDir>' + AName + '\</RemoteDir>'#13#10 +
    '            <RemoteName>' + AName + Ext + '</RemoteName>'#13#10 +
    '            <DeployClass>ProjectOutput</DeployClass>'#13#10 +
    '            <Operation>1</Operation>'#13#10 +
    '            <LocalCommand/>'#13#10 +
    '            <RemoteCommand/>'#13#10 +
    '            <Overwrite>True</Overwrite>'#13#10 +
    '            <Required>True</Required>'#13#10 +
    '        </DeployFile>'#13#10;
end;

{ Adds the ProjectOutput entries for APlat to an existing manifest that has
  none for it (empty or missing platform group). True when it changed. }
function EnsurePlatformOutputEntries(const ADeployProj, ADprojPath, APlat,
  AName: string): Boolean;
var
  Enc, Xml, DprojXml, Cond, Entries: string;
  M: TMatch;
  Cfg: string;
begin
  Result := False;
  Xml := PatchLoadText(ADeployProj, Enc);
  Cond := '''$(Platform)''==''' + APlat + '''';
  // any DeployFile with ProjectOutput inside a group of this platform?
  for M in TRegEx.Matches(Xml, '<ItemGroup\s+Condition="([^"]*)"\s*>(.*?)</ItemGroup>',
    [roIgnoreCase, roSingleline]) do
    if M.Groups[1].Value.Contains(Cond) and
       M.Groups[2].Value.Contains('ProjectOutput') then
      Exit;
  DprojXml := TFile.ReadAllText(ADprojPath);
  Entries := '';
  for Cfg in TArray<string>.Create('Debug', 'Release') do
    Entries := Entries + OutputDeployEntry(DprojXml, APlat, Cfg, AName);
  // an empty self-closing group for the platform: fill it
  M := TRegEx.Match(Xml, '[ \t]*<ItemGroup\s+Condition="' + TRegEx.Escape(Cond) +
    '"\s*/>[ \t]*\r?\n?', [roIgnoreCase]);
  if M.Success then
    Xml := Copy(Xml, 1, M.Index - 1) +
      '    <ItemGroup Condition="' + Cond + '">'#13#10 + Entries +
      '    </ItemGroup>'#13#10 + Copy(Xml, M.Index + M.Length, MaxInt)
  else
  begin
    // a group with other files but no output, or no group at all
    M := TRegEx.Match(Xml, '<ItemGroup\s+Condition="' + TRegEx.Escape(Cond) + '"\s*>', [roIgnoreCase]);
    if M.Success then
      Xml := Copy(Xml, 1, M.Index + M.Length - 1) + #13#10 + Entries +
        Copy(Xml, M.Index + M.Length, MaxInt).TrimLeft([#13, #10])
    else
    begin
      var P := Xml.ToLower.LastIndexOf('</project>');
      if P < 0 then
        Exit;
      Xml := Copy(Xml, 1, P) + '    <ItemGroup Condition="' + Cond + '">'#13#10 +
        Entries + '    </ItemGroup>'#13#10 + Copy(Xml, P + 1, MaxInt);
    end;
  end;
  PatchSaveText(ADeployProj, Xml, Enc);
  Result := True;
end;

procedure EnsureDeployManifest(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean);
const
  // The exact line the IDE writes into every .dproj it saves. Projects
  // scaffolded by delphi_create (and some hand-written ones) lack it, and
  // without it the generated manifest is never imported - Deploy still
  // fails MSB4057 with the .deployproj sitting right there (measured).
  DEPLOY_IMPORT = '<Import Project="$(MSBuildProjectName).deployproj" ' +
    'Condition="Exists(''$(MSBuildProjectName).deployproj'')"/>';
  ANCHOR = '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"';
var
  F, N, Ext, Xml: string;
  Cfg: string;
begin
  AGenerated := False;
  N := TPath.GetFileNameWithoutExtension(ADprojPath);
  // 1) the .dproj must import the manifest (PatchLoadText/SaveText keep the
  //    encoding and leave the __delphi-patch safety copy, same as the
  //    add-platform editor).
  var Enc := '';
  var Dproj := PatchLoadText(ADprojPath, Enc);
  var Changed := False;
  var P := Pos(ANCHOR.ToLower, Dproj.ToLower);
  var LineStart := P;
  var Indent := '';
  if P > 0 then
  begin
    while (LineStart > 1) and not CharInSet(Dproj[LineStart - 1], [#10, #13]) do
      Dec(LineStart);
    Indent := Copy(Dproj, LineStart, P - LineStart);
  end;
  if (P > 0) and not Dproj.ToLower.Contains('.deployproj') then
  begin
    var AnchorEnd := Pos('/>', Dproj, P);
    if AnchorEnd > 0 then
    begin
      AnchorEnd := AnchorEnd + 2;
      Dproj := Copy(Dproj, 1, AnchorEnd - 1) + sLineBreak + Indent +
        DEPLOY_IMPORT + Copy(Dproj, AnchorEnd, MaxInt);
      Changed := True;
    end;
  end;
  // 1b) Android fallback version properties, only when the project has no
  //     Android version block at all (ours contains minSdkVersion too, so
  //     this also makes the insert idempotent). Placed before the anchor.
  if (P > 0) and APlat.StartsWith('Android', True) and
     not Dproj.Contains('minSdkVersion') then
  begin
    // The default system-jar list is exactly the product's pre-dexed jar
    // directory (measured: 88 of 88 identical to an IDE-written project) -
    // enumerated here, never hardcoded, so it tracks the installed version.
    var Jars := '';
    var JarDir := TPath.Combine(ABdsRoot, 'lib\android\debug');
    if TDirectory.Exists(JarDir) then
      for var J in TDirectory.GetFiles(JarDir, '*.dex.jar') do
      begin
        if Jars <> '' then
          Jars := Jars + ';';
        Jars := Jars + TPath.GetFileName(J);
      end;
    Dproj := Copy(Dproj, 1, LineStart - 1) + Indent +
      Format(ANDROID_PROPS, [APlat, Indent, Indent, Indent, Jars, Indent,
        Indent]) + sLineBreak + Copy(Dproj, LineStart, MaxInt);
    Changed := True;
  end;
  if Changed then
    PatchSaveText(ADprojPath, Dproj, Enc);
  // 1c) Android: the AndroidManifest.template.xml seed the IDE would write,
  //     copied from the product's ObjRepos - never invented, never
  //     overwritten (an existing template is the project's own).
  if APlat.StartsWith('Android', True) then
  begin
    var Tpl := TPath.Combine(TPath.GetDirectoryName(ADprojPath),
      'AndroidManifest.template.xml');
    var Seed := TPath.Combine(ABdsRoot, 'ObjRepos\en\Android\AndroidManifest.xml');
    if (not TFile.Exists(Tpl)) and TFile.Exists(Seed) then
      TFile.Copy(Seed, Tpl);
  end;
  // 2) the manifest itself, only when the project has none - BUT an IDE
  //    manifest written before the platform was ever deployed from the IDE
  //    carries an EMPTY group for it (<ItemGroup Condition="'$(Platform)'==
  //    'Linux64'"/>, measured on GalateaFMX): msbuild then deploys nothing
  //    and still succeeds. The project output is added to such a group.
  F := TPath.ChangeExtension(ADprojPath, '.deployproj');
  if TFile.Exists(F) then
  begin
    if not APlat.StartsWith('Android', True) then
      AGenerated := EnsurePlatformOutputEntries(F, ADprojPath, APlat, N);
    Exit;
  end;
  if APlat.StartsWith('Android', True) then
  begin
    TFile.WriteAllText(F, AndroidDeployXml(N, APlat, ABdsRoot), TEncoding.ASCII);
    AGenerated := True;
    Exit;
  end;
  Ext := '';
  if APlat.StartsWith('Win', True) then
    Ext := '.exe';
  Xml := '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <Import Condition="Exists(''$(BDS)\bin\CodeGear.Deployment.targets'')" ' +
    'Project="$(BDS)\bin\CodeGear.Deployment.targets"/>'#13#10 +
    '    <ProjectExtensions>'#13#10 +
    '        <ProjectFileVersion>12</ProjectFileVersion>'#13#10 +
    '    </ProjectExtensions>'#13#10;
  for Cfg in TArray<string>.Create('Debug', 'Release') do
    Xml := Xml +
      '    <ItemGroup Condition="''$(Platform)''==''' + APlat +
        ''' And ''$(Config)''==''' + Cfg + '''">'#13#10 +
      '        <DeployFile Include="' + APlat + '\' + Cfg + '\' + N + Ext + '">'#13#10 +
      '            <RemoteDir>' + N + '\</RemoteDir>'#13#10 +
      '            <RemoteName>' + N + Ext + '</RemoteName>'#13#10 +
      '            <DeployClass>ProjectOutput</DeployClass>'#13#10 +
      '            <Operation>1</Operation>'#13#10 +
      '            <LocalCommand/>'#13#10 +
      '            <RemoteCommand/>'#13#10 +
      '            <Overwrite>True</Overwrite>'#13#10 +
      '            <Required>True</Required>'#13#10 +
      '        </DeployFile>'#13#10 +
      '    </ItemGroup>'#13#10;
  Xml := Xml + '</Project>'#13#10;
  TFile.WriteAllText(F, Xml, TEncoding.ASCII);
  AGenerated := True;
end;

{ F2613 "Unit 'X' not found" / F1026 "File not found: 'X.dcu'": the unit
  names the compiler could not resolve, in order, without duplicates. }
function MissingUnitsOf(const AErrors: TJSONArray): TArray<string>;
var
  I: Integer;
  M: TMatch;
  L: TList<string>;
  Name: string;
begin
  L := TList<string>.Create;
  try
    for I := 0 to AErrors.Count - 1 do
    begin
      M := TRegEx.Match(AErrors.Items[I].Value,
        'F2613:? Unit ''([^'']+)'' not found|F1026:? File not found: ''([^'']+)\.dcu''',
        [roIgnoreCase]);
      if not M.Success then
        Continue;
      Name := M.Groups[1].Value;
      if Name = '' then
        Name := M.Groups[2].Value;
      if (Name <> '') and not L.Contains(Name) then
        L.Add(Name);
      if L.Count >= 10 then
        Break;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Where a unit's .pas lives inside the library zone (RAD Studio installs,
  registered components, GetIt catalog): the folders to add-searchpath.
  Field 2026-08-22: a Linux64 build needed 2 failed builds per component to
  locate OBR's and Steema's Source folders by hand. Shortest paths first,
  at most 6; __history/__recovery/backup copies are skipped. }
function UnitSourceFolders(const AUnit: string): TArray<string>;
var
  Root, F, Dir: string;
  L: TList<string>;
  Files: TArray<string>;
begin
  L := TList<string>.Create;
  try
    for Root in LibraryReadRoots do
    begin
      try
        Files := TDirectory.GetFiles(Root, AUnit + '.pas', TSearchOption.soAllDirectories);
      except
        Continue; // an unreadable root is not the agent's problem
      end;
      for F in Files do
      begin
        Dir := TPath.GetDirectoryName(F);
        if Dir.Contains('__history') or Dir.Contains('__recovery') or
           ContainsText(Dir, 'ackup') then
          Continue;
        if not L.Contains(Dir) then
          L.Add(Dir);
      end;
    end;
    L.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := Length(A) - Length(B);
        if Result = 0 then
          Result := CompareText(A, B);
      end));
    if L.Count > 6 then
      L.Count := 6;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function RunMsBuild(const ADprojPath, APlatform, AConfig, ATarget: string;
  const AProfile, ADeviceId: string; ATimeoutMs: Integer): TJSONObject;
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
  // shell-running / file-planting MSBuild tasks (a planted <Target><Exec>, a
  // build-event, a foreign <Import>) and refuse unless build scripts were
  // explicitly enabled. This is the point-of-execution gate, so it holds however
  // the .dproj got there - upload, edit, or a pre-existing one (field round 7,
  // CRITICAL). AllowBuildScripts (or the broader AllowRun) is the trusted-project
  // opt-in; an inert custom <Target> now builds without it (field round 9 FP).
  if not AllowBuildScripts then
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
  // Deploy ALWAYS builds first: a bare /t:Deploy repackages and ships the
  // PREVIOUS binary with today's date and zero warnings - the measured
  // half-a-session trap (vault: delphi-android-deploy-sin-build). The IDE
  // never deploys stale either.
  if SameText(Target, 'Deploy') then
    Target := 'Build;Deploy';
  // The deployment targets address the remote machine through $(Profile)
  // (their PAClient task takes ProfileName="$(Profile)"). Vetted at the gate
  // like every argument that lands on this command line.
  var ProfileArg := '';
  if AProfile.Trim <> '' then
    ProfileArg := ' /p:Profile=' + AProfile.Trim;
  // Remote platforms get a deployment manifest when the project has none:
  // minimal (the project output) for PAServer targets, the full measured
  // apk staging map for Android. An IDE-written .deployproj is used as-is.
  var ManifestNew := False;
  var ManifestFilled := False;
  if Target.Contains('Deploy') and not IsLocalPlatform(Plat) then
  begin
    ManifestFilled := TFile.Exists(TPath.ChangeExtension(TPath.GetFullPath(ADprojPath), '.deployproj'));
    EnsureDeployManifest(TPath.GetFullPath(ADprojPath), Plat, Info.RootDir,
      ManifestNew);
    ManifestFilled := ManifestFilled and ManifestNew;
  end;
  // /p:DeviceId= reaches the deployment targets, but measured they only
  // auto-install on iOS (_InstallIpa); an Android install is delphi_adb's
  // job with the built .apk. The param stays for the iOS day.
  var DeviceArg := '';
  if ADeviceId.Trim <> '' then
    DeviceArg := ' /p:DeviceId=' + ADeviceId.Trim;

  // Remote platforms (Linux64...) link against a locally provisioned
  // SDK/sysroot. The IDE keeps its default in EnvOptions.proj, but for a
  // platform the SDK Manager never configured that default is EMPTY - so
  // when delphi_paserver get-sdk has written <Platform>.sdk, pass it. A
  // command-line /p: overrides any imported default; when no such file
  // exists nothing changes (Android's SDK arrives via its own default).
  var SdkArg := '';
  if not IsLocalPlatform(Plat) then
  begin
    var SdkName := CanonicalPlatform(Plat) + '.sdk';
    if (CanonicalPlatform(Plat) <> '') and
       TFile.Exists(TPath.Combine(IdeProfilesDir(Info.Version), SdkName)) then
      SdkArg := ' /p:PlatformSDK=' + SdkName;
  end;

  // Security audit trail: a build can run arbitrary pre/post-build steps
  // declared in the .dproj, so record every one.
  TLogger.Warning(Format('delphi_build: BUILD "%s" %s/%s target=%s%s',
    [TPath.GetFullPath(ADprojPath), Plat, Cfg, Target, SdkArg]));

  Output := RunCaptured(Format(
    'cmd.exe /c ""%s" && msbuild "%s" /t:%s /p:Config=%s /p:Platform=%s%s%s%s /v:minimal /nologo"',
    [Info.RsVarsBat, TPath.GetFullPath(ADprojPath), Target, Cfg, Plat, SdkArg,
     ProfileArg, DeviceArg]), ATimeoutMs, ExitCode);

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
    // ONE error can father a dozen. Measured in the field (2026-08-25): a
    // single E2009 - assigning a plain procedure to a TNotifyEvent - produced
    // seven E2250 "no overloaded version of Synchronize/Queue" in the same
    // file, and the pile made it look like a threading problem. The compiler
    // stops making sense after the first refusal, so name the first one and
    // say the rest may be its shadow.
    if Errors.Count > 1 then
    begin
      Result.AddPair('firstError', Errors.Items[0].Value);
      Result.AddPair('firstErrorNote', SN_BUILD_FIRST_ERROR);
    end;
    // Units the compiler could not find: say where their source lives, so
    // the next call is the add-searchpath and not another failed build.
    if ExitCode <> 0 then
    begin
      var Missing := MissingUnitsOf(Errors);
      if Length(Missing) > 0 then
      begin
        var MArr := TJSONArray.Create;
        Result.AddPair('missingUnits', MArr);
        for var U in Missing do
        begin
          var MObj := TJSONObject.Create;
          MArr.AddElement(MObj);
          MObj.AddPair('unit', U);
          var CArr := TJSONArray.Create;
          MObj.AddPair('sourceFolders', CArr);
          for var D in UnitSourceFolders(U) do
            CArr.Add(D);
        end;
        Result.AddPair('missingUnitsNote', SN_BUILD_MISSING_UNITS_NOTE);
      end;
    end;
    Result.AddPair('outputTail', Tail.ToString);
    // A stateless protocol means the agent only knows what each result tells
    // it: say WHERE the artifact landed, or it has to hunt the disk for it
    // (measured in the field: 20 calls chasing a fresh exe that delphi_list
    // kept hidden as build output).
    if (ExitCode = 0) and not SameText(Target, 'Clean') then
    begin
      var Artifact := ResolveBuildOutput(TPath.GetFullPath(ADprojPath), Plat, Cfg);
      var Note := SN_BUILD_OUTPUT;
      // An Android Deploy's real product is the .apk the packager left in
      // <Platform>\<Config>\<name>\bin - declare THAT, not the .so.
      if Plat.StartsWith('Android', True) and Target.Contains('Deploy') then
      begin
        var ProjName := TPath.GetFileNameWithoutExtension(ADprojPath);
        var Apk := TPath.Combine(
          TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath)),
          Plat + '\' + Cfg + '\' + ProjName + '\bin\' + ProjName + '.apk');
        if TFile.Exists(Apk) then
        begin
          Artifact := Apk;
          Note := SN_BUILD_APK_NOTE;
        end;
      end;
      if Artifact <> '' then
      begin
        Result.AddPair('output', Artifact);
        try
          Result.AddPair('outputSize', TJSONNumber.Create(TFile.GetSize(Artifact)));
        except
          // size is a courtesy: the path alone is already the answer
        end;
        Result.AddPair('outputNote', Note);
      end;
      // Same statelessness rule for a remote deploy: say where the files
      // landed ON THE TARGET, or the agent has to guess PAServer's layout.
      if (ProfileArg <> '') and Target.Contains('Deploy') then
      begin
        var Shipped := TRegEx.Matches(Output, 'Deploying\s+"([^"]+)"', [roIgnoreCase]).Count +
          TRegEx.Matches(Output, 'Copying\s+"?([^"\r\n]+?)"?\s+to\s+remote', [roIgnoreCase]).Count;
        Result.AddPair('deployNote', Format(SN_BUILD_DEPLOYED_FMT,
          [AProfile.Trim, GetEnvironmentVariable('USERNAME'), AProfile.Trim,
           TPath.GetFileNameWithoutExtension(ADprojPath)]));
        if Output.Contains('Local file "" not found') then
          Result.AddPair('deployWarning', SN_BUILD_DEPLOY_EMPTY_ENTRY);
        if Shipped > 0 then
          Result.AddPair('deployedFiles', TJSONNumber.Create(Shipped));
      end;
    end;
    // The agent should know its project just gained a manifest whether or
    // not this particular msbuild run succeeded.
    if ManifestNew then
      if Plat.StartsWith('Android', True) then
        Result.AddPair('deployManifest', SN_BUILD_ANDROID_NEW)
      else if ManifestFilled then
        Result.AddPair('deployManifest', Format(SN_BUILD_MANIFEST_FILLED_FMT, [Plat]))
      else
        Result.AddPair('deployManifest', SN_BUILD_MANIFEST_NEW);
  finally
    Tail.Free;
  end;
end;

end.
