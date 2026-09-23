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
  ATimeoutMs: Integer = 600000; const ASdk: string = '';
  const AVerbosity: string = ''): TJSONObject;

{ Runs a command line with stdout+stderr captured (no shell). }
{ Generates the deployment manifest (.deployproj + its import line in the
  .dproj) when the project has none - minimal for PAServer platforms, the full
  staging map for Android; never touches an existing one. Exposed for
  delphi_config add-deployfile, which needs a manifest to add entries to. }
procedure EnsureDeployManifest(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean);

{ Los <nombre>.sdk que el IDE tiene registrados para una plataforma. Expuesto
  porque delphi_config lo necesita para validar el SDK que se fija en un
  proyecto: una sola definicion de "que SDK hay", no dos que se desincronizan. }
function SdksDePlataforma(const AVersion, APlat: string): TArray<string>;

{ El SDK que fija EL PROYECTO para esa plataforma (PlatformSDK de su
  PropertyGroup), y el que el SDK Manager del IDE tiene por defecto para ella.
  Los usa delphi_config view para decir con que se compila y por que. }
function ProyectoDeclaraSdk(const ADproj, APlat: string; out ASdk: string): Boolean;
function SdkPorDefectoDelIde(const AVersion, APlat: string): string;

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
  System.Win.Registry,
  Winapi.Windows,
  MCPServer.Logger,
  Lsp.Discovery,
  Lsp.Guard,
  Lsp.Dproj,
  System.RegularExpressions,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SyncObjs,
  System.Diagnostics,
  Lsp.Patch,
  Lsp.Texts,
  Lsp.Sandbox;

var
  // Serializes every msbuild the server runs (see RunMsBuild).
  GBuildLock: TCriticalSection;

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
  // 3 GB/process as a plain hex constant: the arithmetic form
  // NativeUInt(3)*1024*1024*1024 overflowed dcc32's SIGNED 32-bit constant
  // evaluation (E2099) even though $C0000000 fits NativeUInt fine - the
  // first external user issue (GitHub #1, limelect, Delphi 13 Win32 Debug).
  Ext.ProcessMemoryLimit := NativeUInt($C0000000);
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
  // test: "AÃ±ade" for "Añade"); compilers emit OEM. Strictly valid UTF-8
  // with high bytes IS UTF-8; anything else is the console codepage.
  //
  // NOT TEncoding.ANSI: a child writing to a pipe is still a console program
  // and encodes in the console OUTPUT codepage (850 here), not in the ANSI
  // one (1252). They differ exactly on the accented letters, so decoding as
  // ANSI turned MSBuild's "raiz"/"linea"/"posicion" into "ra¡z"/"l¡nea"/
  // "posici¢n" - measured 2026-09-20. Asked to Windows, never hardcoded:
  // another machine has another codepage.
  if LooksUtf8(Bytes) then
    try
      Exit(TEncoding.UTF8.GetString(Bytes));
    except
      // LooksUtf8 mira la FORMA de los bytes, y hay secuencias bien
      // formadas que el decodificador estricto (MB_ERR_INVALID_CHARS)
      // rechaza igual: los surrogates CESU-8 y las sobrelargas del
      // "modified UTF-8" que emiten las herramientas Java/Android (adb,
      // gradle). La red de abajo se puso el 21-sep JUSTO por esta
      // excepcion... y esta rama quedo fuera de ella (auditoria del mismo
      // dia). Se cae a la rama del codepage, que decodifica distinto y
      // ademas tiene la red byte a byte que no puede fallar.
    end;
  begin
    var Cp: Cardinal := GetConsoleOutputCP;
    if Cp = 0 then
      Cp := GetOEMCP; // tray and service have no console: ask the machine
    var Enc := TEncoding.GetEncoding(Cp);
    try
      try
        Result := Enc.GetString(Bytes);
      except
        // DECODIFICAR NO PUEDE MATAR LA LLAMADA. Windows rechaza una
        // secuencia que esa pagina de codigos no sabe representar y Delphi la
        // convierte en "No mapping for the Unicode character exists in the
        // target multi-byte code page", que sale al agente como "Error
        // executing tool" - o sea, en las reglas de este servidor, "me he
        // roto por dentro". Y no se ha roto nada: solo que un programa hijo
        // escribio algo que no era ni UTF-8 valido ni de la consola (un
        // titulo de ventana con un emoji, por ejemplo).
        //
        // Medido el 2026-09-21: delphi_desktop dejo de funcionar ENTERO -
        // hasta command=status- segun lo que hubiera en la pantalla del
        // operador, y lo mismo le podia pasar a delphi_build, delphi_git,
        // delphi_test, delphi_adb y delphi_paserver, que capturan por aqui.
        // Perder un acento es un defecto; perder la salida de una
        // compilacion es otra cosa.
        //
        // La vuelta atras es byte a byte y no puede fallar: cada byte se lee
        // como su punto de codigo latin-1. Lo que no sea ASCII saldra raro,
        // pero saldra - y los errores del compilador, que es lo que importa,
        // son ASCII.
        Result := '';
        SetLength(Result, Length(Bytes));
        for var K := 0 to High(Bytes) do
          Result[K + 1] := Char(Bytes[K]);
      end;
    finally
      Enc.Free; // GetEncoding returns a new object, not a singleton
    end;
  end;
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
           ContainsText(Dir, '\backup') then
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

// Compiler directives that pull a FILE into the build: {$I}/{$INCLUDE} for
// source, {$R}/{$RESOURCE} for resources. The compiler opens whatever they
// name with the SERVER's own access, and what comes in leaves again two ways:
// baked into the binary (which delphi_package + delphi_fetch hand over) and
// quoted word by word in the compiler's errors when the file is not Pascal -
// measured 2026-08-25 with a text file outside every root, whose words came
// back as "Undeclared identifier: 'esto'", "'secreto'"...
//
// Same hole as the .rc of delphi_styles, different door, same answer: every
// path they name is resolved and checked against the read jail BEFORE msbuild
// starts. Wildcards ({$R *.res}, {$R *.dfm}) and relative names that stay
// inside are untouched - that is what an ordinary project uses.
function IncludeDirectivesDenied(const ADprojPath: string): string;
var
  Dpr, Txt, Enc, Cand, Base: string;
  Files: TList<string>;
  M: TMatch;
begin
  Result := '';
  Dpr := TPath.ChangeExtension(ADprojPath, '.dpr');
  Files := TList<string>.Create;
  try
    if TFile.Exists(Dpr) then
      Files.Add(Dpr);
    // Everything the compiler could reach from the project's own folder. Not
    // the .dproj's unit list: a unit can be pulled in by a search path and
    // still carry a directive, and this check is cheap enough to be broad.
    Base := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
    if TDirectory.Exists(Base) then
      for var Ext in TArray<string>.Create('*.pas', '*.dpr', '*.inc', '*.dpk') do
        for var SF in TDirectory.GetFiles(Base, Ext, TSearchOption.soAllDirectories) do
          if not Files.Contains(SF) then
            Files.Add(SF);
    for var F in Files do
    begin
      try
        Txt := PatchLoadText(F, Enc);
      except
        Continue;
      end;
      Base := TPath.GetDirectoryName(F);
      for M in TRegEx.Matches(Txt, '(?i)\{\$(I|INCLUDE|R|RESOURCE|L|LINK)\s+([^}]+)\}') do
      begin
        Cand := M.Groups[2].Value.Trim.Trim(['''', '"']);
        // a wildcard is the IDE's own boilerplate ({$R *.res}, {$R *.dfm})
        if (Cand = '') or Cand.Contains('*') then
          Continue;
        // {$I+} / {$I-} and friends are switches, not files
        if (Length(Cand) <= 1) or CharInSet(Cand[1], ['+', '-']) then
          Continue;
        // {$R file.res name}: only the first token is a path
        Cand := Cand.Split([' ', #9])[0].Trim(['''', '"']);
        if Cand = '' then
          Continue;
        if not TPath.IsPathRooted(Cand) then
          Cand := TPath.Combine(Base, Cand);
        try
          Cand := TPath.GetFullPath(Cand);
        except
          Continue;
        end;
        if ReadPathDenied(Cand) <> '' then
          Exit(Format(SR_BUILD_INCLUDE_OUTSIDE_FMT,
            [M.Groups[0].Value.Trim, TPath.GetFileName(F)]));
      end;
    end;
  finally
    Files.Free;
  end;
end;

{ Los SDK que el IDE tiene registrados para una plataforma: los <nombre>.sdk
  de su APPDATA cuyo Profile_platform coincide. UN SDK = UNA CARPETA y aqui se
  decide con cual se compila - la misma idea que los SDK de Android. }
function SdksDePlataforma(const AVersion, APlat: string): TArray<string>;
var
  F, Xml, Dir: string;
  L: TStringList;
begin
  Result := nil;
  Dir := IdeProfilesDir(AVersion);
  if not TDirectory.Exists(Dir) then
    Exit;
  L := TStringList.Create;
  try
    L.Sorted := True;
    for F in TDirectory.GetFiles(Dir, '*.sdk') do
    begin
      Xml := '';
      try
        Xml := TFile.ReadAllText(F);
      except
        Continue;
      end;
      if TRegEx.IsMatch(Xml, '(?i)<Profile_platform>\s*' + APlat + '\s*<') then
        L.Add(TPath.GetFileName(F));
    end;
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

{ El SDK que el SDK MANAGER de esa version tiene por defecto para la
  plataforma (Default_<Plataforma> de PlatformSDKs). Es la eleccion explicita
  del operador en el IDE, asi que manda sobre cualquier adivinanza nuestra. }
function SdkPorDefectoDelIde(const AVersion, APlat: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\PlatformSDKs',
      [AVersion])) then
      try
        if Reg.ValueExists('Default_' + APlat) then
          Result := Reg.ReadString('Default_' + APlat).Trim;
      except
        Result := '';
      end;
  finally
    Reg.Free;
  end;
end;

{ El SDK que declara EL PROYECTO (propiedad PlatformSDK, que es la que lee
  CodeGear.Profiles.Targets). El modelo del IDE es que cada proyecto diga con
  cual se compila; si lo dice, no se le pisa. }
function ProyectoDeclaraSdk(const ADproj, APlat: string; out ASdk: string): Boolean;
var
  Xml: string;
begin
  ASdk := '';
  Result := False;
  try
    Xml := TFile.ReadAllText(ADproj);
  except
    Exit;
  end;
  // POR PLATAFORMA, que es como lo escriben el IDE y set-sdk: el primer
  // <PlatformSDK> del fichero le daba a un build OSX64 el SDK de Linux64.
  ASdk := PlatformProperty(Xml, APlat, 'PlatformSDK');
  Result := ASdk <> '';
end;

{ "cannot find -lz": el enlazador busca el nombre de DESARROLLO (libz.so), y
  un sysroot traido de una maquina sin el paquete -dev solo trae libz.so.1.
  Completar el sysroot entero al bajarlo no vale: en un Zorin son 2.117
  nombres y 2,2 GB de copias (medido 2026-09-22). Aqui se completa SOLO lo
  que un build pide, con una copia (Windows no tiene enlaces simbolicos sin
  privilegio) de la version con nombre mas corto que haya en las carpetas del
  Profile_librarypath del .sdk, y el build se repite una vez. Un libX.so que
  ya exista no se toca nunca (libc.so es un guion del enlazador, no una
  libreria). Devuelve cuantos completo; ANota explica lo hecho y, si de alguna
  no hay NINGUNA version, que a esa maquina le falta la libreria misma. }
function CompletaEnlacesDev(const AVersion, ASdkFile, AOutput: string;
  out ANota: string): Integer;
var
  Xml, Rutas, Nombre, Dir, Dev, Mejor, Hechos, Faltan: string;
  M: TMatch;
  Vistos: TStringList;
  Hecho: Boolean;
begin
  Result := 0;
  ANota := '';
  try
    Xml := TFile.ReadAllText(TPath.Combine(IdeProfilesDir(AVersion), ASdkFile));
  except
    Exit;
  end;
  M := TRegEx.Match(Xml, '(?i)<Profile_librarypath>([^<]+)</Profile_librarypath>');
  if not M.Success then
    Exit;
  Rutas := M.Groups[1].Value.Replace('$(BDSPLATFORMSDKSDIR)',
    IdeSdksDir(AVersion), [rfIgnoreCase]);
  Hechos := '';
  Faltan := '';
  Vistos := TStringList.Create;
  try
    for M in TRegEx.Matches(AOutput, 'cannot find -l([A-Za-z0-9_+.\-]+)') do
    begin
      Nombre := M.Groups[1].Value;
      if Vistos.IndexOf(Nombre) >= 0 then
        Continue;
      Vistos.Add(Nombre);
      Dev := 'lib' + Nombre + '.so';
      Hecho := False;
      for Dir in Rutas.Split([';'], TStringSplitOptions.ExcludeEmpty) do
      begin
        if Dir.Contains('$(') or not TDirectory.Exists(Dir) then
          Continue;
        if TFile.Exists(TPath.Combine(Dir, Dev)) then
          Continue; // existe y aun asi no lo encontro: no es este el problema
        // libX.so.1 gana a libX.so.1.3: el nombre mas corto es el soname
        Mejor := '';
        for var F in TDirectory.GetFiles(Dir, Dev + '.*') do
        begin
          var Cola := TPath.GetFileName(F).Substring(Length(Dev) + 1);
          if (Cola = '') or not CharInSet(Cola[1], ['0'..'9']) then
            Continue;
          if (Mejor = '') or (Length(TPath.GetFileName(F)) < Length(TPath.GetFileName(Mejor))) then
            Mejor := F;
        end;
        if Mejor = '' then
          Continue;
        try
          TFile.Copy(Mejor, TPath.Combine(Dir, Dev), False);
        except
          Continue;
        end;
        Inc(Result);
        Hecho := True;
        if Hechos <> '' then
          Hechos := Hechos + '; ';
        Hechos := Hechos + Format('%s <- %s (%s)', [Dev, TPath.GetFileName(Mejor), Dir]);
        Break;
      end;
      if not Hecho then
      begin
        if Faltan <> '' then
          Faltan := Faltan + ', ';
        Faltan := Faltan + Dev;
      end;
    end;
  finally
    Vistos.Free;
  end;
  if Hechos <> '' then
    ANota := Format(SN_BUILD_DEVLINK_DONE_FMT, [Hechos]);
  if Faltan <> '' then
  begin
    if ANota <> '' then
      ANota := ANota + ' ';
    ANota := ANota + Format(SN_BUILD_DEVLINK_MISSING_FMT, [Faltan]);
  end;
end;

{ Un sysroot con DOS distros dentro - el arbol de Debian y el de Red Hat a la
  vez -, que es lo que dejaba el get-sdk de antes de 2026-09-20 al volcar todos
  los targets en una carpeta unica. Devuelve la carpeta, o '' si esta limpio. }
function SysrootMezcladoDeSdk(const AVersion, ASdkFile: string): string;
var
  Xml, Raiz: string;
  M: TMatch;
begin
  Result := '';
  try
    Xml := TFile.ReadAllText(TPath.Combine(IdeProfilesDir(AVersion), ASdkFile));
  except
    Exit;
  end;
  M := TRegEx.Match(Xml, '(?i)<Profile_sysroot>([^<]+)</Profile_sysroot>');
  if not M.Success then
    Exit;
  Raiz := M.Groups[1].Value.Trim;
  if Raiz.Contains('$(BDSPLATFORMSDKSDIR)') then
    Raiz := Raiz.Replace('$(BDSPLATFORMSDKSDIR)', IdeSdksDir(AVersion),
      [rfIgnoreCase]);
  if Raiz.Contains('$(') then
    Exit; // con macros sin expandir no se puede mirar el disco
  // DOS libc.so.6, uno en cada arbol: la unica senal fiable de que dos
  // maquinas escribieron en la misma carpeta. Que existan a la vez /lib64 y
  // /usr/lib/x86_64-linux-gnu NO lo es - un Ubuntu trae /lib64 con el
  // cargador dentro y nada mas, y mirando carpetas se acusaba de mezcla a un
  // sysroot recien traido y perfectamente limpio (medido 2026-09-20).
  if (TFile.Exists(TPath.Combine(Raiz, 'lib\x86_64-linux-gnu\libc.so.6')) or
      TFile.Exists(TPath.Combine(Raiz, 'usr\lib\x86_64-linux-gnu\libc.so.6'))) and
     (TFile.Exists(TPath.Combine(Raiz, 'lib64\libc.so.6')) or
      TFile.Exists(TPath.Combine(Raiz, 'usr\lib64\libc.so.6'))) then
    Result := Raiz;
end;

function RunMsBuild(const ADprojPath, APlatform, AConfig, ATarget: string;
  const AProfile, ADeviceId: string; ATimeoutMs: Integer;
  const ASdk, AVerbosity: string): TJSONObject;
var
  Info: TRadStudioInfo;
  Output, Line, Plat, Cfg, Target: string;
  ExitCode: DWORD;
  Errors, Warnings: TJSONArray;
  YaDicho: TStringList; // lo que ya va en errors[]/warnings[]: la cola no lo repite
  Tail: TStringBuilder;
  Lines: TArray<string>;
  I, TailFrom: Integer;
begin
  var Denied := PathDenied(ADprojPath);
  if Denied <> '' then
    raise Exception.Create(Denied);
  if not FileExists(ADprojPath) then
    raise Exception.CreateFmt('.dproj not found: %s', [ADprojPath]);
  // A TYPE check, before anything reads the file or spawns anything. Without
  // it the hazard scan below was a substring search standing in for one, and
  // it failed in both directions at once (measured 2026-09-20): CHANGELOG.md
  // was refused for an <Exec> task it does not have - the word appears in
  // prose describing that very guard - while LICENSE, with no "exec"
  // anywhere, went straight through and MSBuild was spawned on the text of
  // an MIT licence. The refusal even named a real config key
  // (AllowBuildScripts) for a condition that was not happening, which is how
  // an agent ends up asking the operator to enable build scripts in order to
  // compile a markdown file.
  if not SameText(TPath.GetExtension(ADprojPath), '.dproj') then
    raise Exception.Create(Format(SR_BUILD_NOT_A_PROJECT_FMT,
      [TPath.GetFileName(ADprojPath)]));
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
  // Before a single line is compiled: what does this project pull in from
  // outside, and is it allowed to? Same shape as the hazard check above.
  var IncBad := IncludeDirectivesDenied(ADprojPath);
  if IncBad <> '' then
  begin
    TLogger.Warning(Format('delphi_build: REFUSED "%s" - %s',
      [TPath.GetFullPath(ADprojPath), IncBad]));
    raise Exception.Create(IncBad);
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
  // One msbuild at a time, server-wide: two concurrent builds (two agents,
  // or a build racing delphi_test's compile) share DCU/output dirs and the
  // .deployproj, and silently corrupt each other (hermes, release audit
  // 2026-08-26). A global queue is the safe shape; the wait is reported so
  // a queued caller can tell compiler time from queue time.
  var SdkUsado := '';         // el SDK con el que se compilo (si hubo)
  var SdkNota := '';          // por que ese y no otro
  var SdkAviso := '';         // sysroot con dos distros dentro
  var ReintentosBloqueo := 0; // builds repetidos por un .exe en uso (F2039)
  var EnlacesDev := 0;        // nombres -dev completados en el sysroot
  var EnlacesNota := '';      // lo hecho, y lo que no se pudo
  var QueueSW := TStopwatch.StartNew;
  GBuildLock.Enter;
  var QueuedMs := QueueSW.ElapsedMilliseconds;
  try
  // Un Windows REMOTO (perfil PAServer de Windows) despliega como un Linux:
  // sin manifiesto, msbuild "desplegaba" cero ficheros y decia exito. La
  // plataforma local solo lo es cuando no hay perfil (medido 2026-09-22 con
  // el primer deploy Win64 a windows-local: carpeta vacia en el destino).
  if Target.Contains('Deploy') and ((ProfileArg <> '') or not IsLocalPlatform(Plat)) then
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
  // SDK/sysroot, y desde 2026-09-20 puede haber VARIOS: un SDK = una carpeta,
  // como los de Android. Quien manda, por este orden: lo que pida la llamada
  // (sdk=), lo que declare el PROYECTO (PlatformSDK, que es lo que lee
  // CodeGear.Profiles.Targets), y si no, el unico que haya - o el
  // <Plataforma>.sdk historico, para no romper lo que ya compilaba. Con
  // varios y sin pistas NO se elige a ciegas: se dice y se para.
  var SdkArg := '';
  if not IsLocalPlatform(Plat) then
  begin
    var Dir := IdeProfilesDir(Info.Version);
    var Pedido := ASdk.Trim;
    if Pedido <> '' then
    begin
      if not Pedido.ToLower.EndsWith('.sdk') then
        Pedido := Pedido + '.sdk';
      if not TFile.Exists(TPath.Combine(Dir, Pedido)) then
        raise Exception.Create(Format(SR_BUILD_SDK_NOEXISTE_FMT,
          [Pedido, string.Join(', ', SdksDePlataforma(Info.Version, Plat))]));
      SdkArg := ' /p:PlatformSDK=' + Pedido;
      SdkUsado := Pedido;
    end
    else if ProyectoDeclaraSdk(TPath.GetFullPath(ADprojPath), Plat, SdkUsado) then
      // el proyecto lo dice: no se le pisa, y se cuenta cual es
      SdkNota := Format(SN_BUILD_SDK_PROYECTO_FMT, [SdkUsado])
    else
    begin
      var Cand := SdksDePlataforma(Info.Version, Plat);
      var Historico := CanonicalPlatform(Plat) + '.sdk';
      // El default del SDK Manager es la eleccion del operador EN EL IDE:
      // manda sobre el nombre historico y sobre cualquier adivinanza, y es lo
      // que evita negarse a compilar en una maquina que ya tenia respuesta a
      // esta pregunta (medido: al retirar el Linux64.sdk viejo, media bateria
      // se quedo sin poder compilar).
      var PorDefecto := SdkPorDefectoDelIde(Info.Version, Plat);
      if (PorDefecto <> '') and TFile.Exists(TPath.Combine(Dir, PorDefecto)) then
      begin
        SdkUsado := PorDefecto;
        if Length(Cand) > 1 then
          SdkNota := Format(SN_BUILD_SDK_DEFAULT_FMT,
            [SdkUsado, string.Join(', ', Cand)]);
      end
      else if (CanonicalPlatform(Plat) <> '') and
         TFile.Exists(TPath.Combine(Dir, Historico)) then
        SdkUsado := Historico
      else if Length(Cand) = 1 then
        SdkUsado := Cand[0]
      else if Length(Cand) > 1 then
        raise Exception.Create(Format(SR_BUILD_SDK_VARIOS_FMT,
          [Plat, string.Join(', ', Cand)]));
      if SdkUsado <> '' then
      begin
        SdkArg := ' /p:PlatformSDK=' + SdkUsado;
        // Solo si nadie ha explicado ya POR QUE es ese: la rama del default
        // del IDE deja su propia nota, y pisarla convertia "lo eligio tu SDK
        // Manager" en un "hay varios, mira a ver" que no decia nada.
        if (SdkNota = '') and (Length(Cand) > 1) then
          SdkNota := Format(SN_BUILD_SDK_ELEGIDO_FMT,
            [SdkUsado, string.Join(', ', Cand)]);
      end;
    end;
    // Compilar contra un sysroot con dos distros dentro no es un error del
    // compilador y no se ve en ningun sitio: se dice aqui.
    if SdkUsado <> '' then
    begin
      var Mezcla := SysrootMezcladoDeSdk(Info.Version, SdkUsado);
      if Mezcla <> '' then
        SdkAviso := Format(SN_BUILD_SDK_MEZCLA_FMT, [SdkUsado, Mezcla]);
    end;
  end;

  // Security audit trail: a build can run arbitrary pre/post-build steps
  // declared in the .dproj, so record every one.
  TLogger.Warning(Format('delphi_build: BUILD "%s" %s/%s target=%s%s',
    [TPath.GetFullPath(ADprojPath), Plat, Cfg, Target, SdkArg]));

  // Los MISMOS flags que BuildWithParams.bat, que es el contrato de la casa
  // para builds con agentes: quiet = solo errores y el resumen (unas pocas
  // lineas), normal = warnings e hitos, verbose = todo. Un bat por proyecto
  // existia sobre todo por esto; teniendolo aqui, un proyecto solo necesita
  // el suyo para SU ritual (numero de build, EurekaLog, firma, datos).
  // Vacio = normal, que es como se comportaba antes de tener el parametro:
  // los otros motores que llaman aqui no cambian de comportamiento.
  var Verb := '/v:minimal /nologo';
  if SameText(AVerbosity, 'quiet') then
    Verb := '/v:quiet /clp:ErrorsOnly;Summary;NoItemAndPropertyList /nologo'
  else if SameText(AVerbosity, 'verbose') then
    Verb := '/v:detailed';
  var Orden := Format(
    'cmd.exe /c ""%s" && msbuild "%s" /t:%s /p:Config=%s /p:Platform=%s%s%s%s %s"',
    [Info.RsVarsBat, TPath.GetFullPath(ADprojPath), Target, Cfg, Plat, SdkArg,
     ProfileArg, DeviceArg, Verb]);
  Output := RunCaptured(Orden, ATimeoutMs, ExitCode);
  // F2039 = el .exe que este build va a escribir esta ABIERTO, casi siempre
  // porque delphi_run o delphi_test lo estan ejecutando ahora mismo: el
  // cerrojo serializa msbuild contra msbuild, pero se suelta antes de que el
  // programa corra (medido 2026-09-20: build + run del mismo proyecto = build
  // rojo). Casi todas esas ejecuciones son cortas, asi que se reintenta unos
  // segundos antes de dar el diagnostico - encolar el build detras de una
  // ejecucion de cinco minutos seria peor.
  // La espera CRECE (1, 2, 4, 8 s): una ejecucion corta se despeja en el
  // primer reintento y una de varios segundos entra en el ultimo, sin
  // machacar a msbuild ni quedarse esperando para siempre. Medido 2026-09-20:
  // con esperas fijas de 1,5 s un programa de 8 s agotaba los reintentos.
  var EsperaBloqueo := 1000;
  while (ExitCode <> 0) and (ReintentosBloqueo < 4) and Output.Contains('F2039') do
  begin
    Inc(ReintentosBloqueo);
    Sleep(EsperaBloqueo);
    EsperaBloqueo := EsperaBloqueo * 2;
    Output := RunCaptured(Orden, ATimeoutMs, ExitCode);
  end;
  // "cannot find -lX" con un sysroot nuestro: el nombre -dev que falta se
  // completa en el SDK (ver CompletaEnlacesDev) y el build se repite UNA vez.
  // Medido 2026-09-21: GalateaFMX dejo de enlazar en zorin18 y fedora44 por
  // un libz.so que ninguno de los dos traia; con la copia enlaza en ambos.
  if (ExitCode <> 0) and (SdkUsado <> '') and Output.Contains('cannot find -l') then
  begin
    EnlacesDev := CompletaEnlacesDev(Info.Version, SdkUsado, Output, EnlacesNota);
    if EnlacesDev > 0 then
      Output := RunCaptured(Orden, ATimeoutMs, ExitCode);
  end;
  finally
    GBuildLock.Leave;
  end;

  Errors := TJSONArray.Create;
  Warnings := TJSONArray.Create;
  // Lo mismo que entra en errors[]/warnings[], apuntado aparte para que la
  // cola no lo repita.
  YaDicho := TStringList.Create;
  YaDicho.Sorted := True;
  YaDicho.Duplicates := dupIgnore;
  Lines := Output.Split([#13#10, #10]);
  for Line in Lines do
  begin
    if Line.Contains(': error ') or Line.Contains(' error E') or
       Line.Contains(' error MSB') or Line.Contains('fatal error') or
       Line.Contains(': fatal ') then
  begin
    Errors.Add(Line.Trim);
    YaDicho.Add(Line.Trim);
  end
  else if Line.Contains(': warning ') or Line.Contains(' warning W') then
  begin
    Warnings.Add(Line.Trim);
    YaDicho.Add(Line.Trim);
  end;
  end;

  // La linea del linker de Linux trae unos 2 KB de rutas -L en CADA build.
  // La primera vez es informativa; a partir de la segunda es ruido que se
  // come el contexto del agente (medido el 2026-09-20 usando este servidor
  // como agente). Se queda lo unico que se mira de ella -el --sysroot, que
  // dice con QUE SDK enlazo- y el recuento de las rutas.
  // Keep the last ~25 lines as raw context (summary, timings).
  Tail := TStringBuilder.Create;
  try
    TailFrom := Length(Lines) - 25;
    if SameText(AVerbosity, 'verbose') then
      TailFrom := Length(Lines) - 120;
    if TailFrom < 0 then
      TailFrom := 0;
    for I := TailFrom to High(Lines) do
      if Lines[I].Trim <> '' then
      begin
        // Lo que ya va en errors[] o warnings[] NO se repite aqui: la cola
        // los traia OTRA VEZ enteros, y en un proyecto con quince avisos eso
        // son 2-3 KB duplicados en CADA build, pagados por el contexto del
        // agente (visto el 2026-09-20 compilando este mismo repo por el MCP
        // una y otra vez). La cola es el resumen y los tiempos.
        if YaDicho.IndexOf(Lines[I].Trim) >= 0 then
          Continue;
        var Linea := Lines[I].TrimRight;
        if Linea.Contains('Linker command line:') and
           not SameText(AVerbosity, 'verbose') and
           (TRegEx.Matches(Linea, '(?:^|\s)-L\s*\S+').Count >= 4) then
        begin
          var MSys := TRegEx.Match(Linea, '--sysroot\s+(\S+)');
          Linea := Format('  Linker command line: --sysroot %s  (+%d rutas -L omitidas: ' +
            'son 2 KB identicos en cada build)',
            [IfThen(MSys.Success, MSys.Groups[1].Value, '(ninguno)'),
             TRegEx.Matches(Linea, '(?:^|\s)-L\s*\S+').Count]);
        end;
        Tail.AppendLine(Linea);
      end;

    Result := TJSONObject.Create;
    Result.AddPair('success', TJSONBool.Create(ExitCode = 0));
    Result.AddPair('exitCode', TJSONNumber.Create(Integer(ExitCode)));
    if QueuedMs >= 500 then
    begin
      Result.AddPair('queuedMs', TJSONNumber.Create(QueuedMs));
      Result.AddPair('queuedNote', SN_BUILD_QUEUED);
    end;
    Result.AddPair('project', TPath.GetFullPath(ADprojPath));
    // Con QUE instalacion se compilo: vital para un agente en una maquina
    // con varias (DelphiVersion= por workspace), y nada obvio sin decirlo.
    Result.AddPair('delphiVersion', Info.Version);
    if Info.ProductName <> '' then
      Result.AddPair('delphiName', Info.ProductName);
    if Info.Build <> '' then
      Result.AddPair('delphiBuild', Info.Build);
    Result.AddPair('platform', Plat);
    // Two tools, two defaults: this one builds Win32 when nobody says, and
    // delphi_test runs Win64. An agent that built by hand and then ran the
    // tests was looking at two different binaries and could not see why
    // (field round 10). Say which one this was, when nobody chose.
    if APlatform = '' then
      Result.AddPair('platformNote', SN_BUILD_DEFAULT_PLATFORM);
    Result.AddPair('config', Cfg);
    Result.AddPair('target', Target);
    if SdkUsado <> '' then
      Result.AddPair('sdk', SdkUsado);
    if SdkNota <> '' then
      Result.AddPair('sdkNote', SdkNota);
    if SdkAviso <> '' then
      Result.AddPair('sdkWarning', SdkAviso);
    Result.AddPair('errors', Errors);
    // En quiet NO va un warnings:[] vacio: se leeria como "no hay warnings" y
    // seria mentira - es que no se han pedido. Va la nota y punto.
    if SameText(AVerbosity, 'quiet') then
      Warnings.Free
    else
      Result.AddPair('warnings', Warnings);
    // ONE error can father a dozen. Measured in the field (2026-08-25): a
    // single E2009 - assigning a plain procedure to a TNotifyEvent - produced
    // seven E2250 "no overloaded version of Synchronize/Queue" in the same
    // file, and the pile made it look like a threading problem. The compiler
    // stops making sense after the first refusal, so name the first one and
    // say the rest may be its shadow.
    // firstError goes out whenever there IS an error - it was documented as
    // unconditional and then vanished on single-error builds, which is exactly
    // when a caller scanning for one key finds nothing. The "the rest may be
    // its shadow" note only makes sense when there IS a rest.
    if Errors.Count > 0 then
    begin
      Result.AddPair('firstError', Errors.Items[0].Value);
      if Errors.Count > 1 then
        Result.AddPair('firstErrorNote', SN_BUILD_FIRST_ERROR);
    end;
    // F2039 is almost never a code problem: the binary this build is about to
    // write is OPEN - the previous run still alive, the IDE holding it, a
    // debugger attached. It reads like a compiler error and it is not, so it
    // gets the one sentence that turns it into an action.
    if (ExitCode <> 0) and Output.Contains('F2039') then
    begin
      Result.AddPair('lockedOutputNote', SN_BUILD_LOCKED_OUTPUT);
    end;
    // Se reintento y salio: el agente merece saber que su build tardo mas
    // porque el binario estaba ocupado, no porque compilar sea lento.
    if ReintentosBloqueo > 0 then
    begin
      Result.AddPair('lockedRetries', TJSONNumber.Create(ReintentosBloqueo));
      Result.AddPair('lockedRetriesNote', SN_BUILD_LOCKED_RETRY);
    end;
    if EnlacesDev > 0 then
      Result.AddPair('sdkLinksCompleted', TJSONNumber.Create(EnlacesDev));
    if EnlacesNota <> '' then
      Result.AddPair('sdkLinkNote', EnlacesNota);
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
    // En quiet msbuild NI SIQUIERA imprime los warnings, asi que no se puede
    // dar un recuento: se dice que no se pidieron, en vez de inventar un 0.
    if SameText(AVerbosity, 'quiet') then
      Result.AddPair('warningsNote', SN_BUILD_QUIET_WARNINGS);
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
        // Lo que msbuild imprime de verdad en un Deploy por PAServer (medido
        // 2026-09-23, Windows, verbose): la orden paclient --put="a,b,1,c;..."
        // del target _DeployFiles, un fichero por cada tramo entre ';'.
        for var MP in TRegEx.Matches(Output, '--put="?([^"\r\n]+)', [roIgnoreCase]) do
          Shipped := Shipped + Length(MP.Groups[1].Value.Split([';']));
        Result.AddPair('deployNote', Format(SN_BUILD_DEPLOYED_FMT,
          [AProfile.Trim, GetEnvironmentVariable('USERNAME'), AProfile.Trim,
           TPath.GetFileNameWithoutExtension(ADprojPath)]));
        if Output.Contains('Local file "" not found') then
          Result.AddPair('deployWarning', SN_BUILD_DEPLOY_EMPTY_ENTRY);
        if Shipped > 0 then
          Result.AddPair('deployedFiles', TJSONNumber.Create(Shipped))
        else if SameText(AVerbosity, 'quiet') then
          // En quiet msbuild no imprime las copias: no se puede contar, y
          // decir "no se envio nada" era falso (medido 2026-09-23: deploy a
          // Windows correcto y sin deployedFiles).
          Result.AddPair('deployedFilesNote', SN_BUILD_QUIET_DEPLOYED);
      end;
    end;
    // Un Deploy que no pudo reescribir la carpeta del target porque el vigia
    // de un remote-run anterior (<job>.wait.exe) sigue vivo: ese programa
    // sigue corriendo alli. El E0017 crudo de msbuild no lo dice; el nombre
    // del fichero lleva el id del trabajo, asi que se le da la orden de kill.
    // Medido 2026-09-23 contra 192.168.1.10 con una GUI viva.
    if (ExitCode <> 0) and Target.Contains('Deploy') and Output.Contains('E0017') then
    begin
      var MLock := TRegEx.Match(Output, '([0-9]{8}-[0-9]{9}-[0-9a-f]{8})\.wait(?:\.[0-9]+)?\.exe', [roIgnoreCase]);
      if MLock.Success then
        Result.AddPair('deployLockedNote', Format(SN_BUILD_DEPLOY_LOCKED_FMT,
          [MLock.Groups[1].Value, AProfile.Trim, ADprojPath, MLock.Groups[1].Value]));
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
    YaDicho.Free;
    Tail.Free;
  end;
end;

initialization
  GBuildLock := TCriticalSection.Create;

finalization
  GBuildLock.Free;

end.
