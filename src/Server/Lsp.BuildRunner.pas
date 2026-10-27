unit Lsp.BuildRunner;

{ Real builds through MSBuild - the LSP has no build operation, so this runs
  on the machine that owns the compiler: rsvars.bat (located via registry
  discovery, never hardcoded) read for its environment, and msbuild.exe
  launched by its full path with no shell in between (2an of 1.18.2), output
  captured and distilled into errors/warnings for a remote agent. }

interface

uses
  System.JSON,
  System.SysUtils, // Exception: base de ETestNoConfinado
  Lsp.Sandbox; // TContenedor: la jaula de delphi_test

type
  { El test no se pudo confinar en su Job Object: fail-closed, no corre.
    CorreEnContenedor la distingue de un fallo de lanzamiento (TEST-032 vs
    TEST-027). }
  ETestNoConfinado = class(Exception);

  { En que pagina escribe un programa hijo lo que no es UTF-8 cuando escribe a
    una TUBERIA. phConsola: un programa de consola de Windows (msbuild, los
    compiladores) escribe en la de su consola aunque escriba a una tuberia
    (medido el 20-sep-2026: msbuild en la 850). phAnsi: uno de Delphi escribe
    con su RTL, y a lo que no es una consola la RTL escribe en
    DefaultSystemCodePage, la ANSI de la maquina (System.pas, TryOpenForOutput:
    la de la consola solo si GetFileType dice que lo es) - el test que compila
    un agente: delphi_test devolvia cada i con tilde como una Y con tilde (1252
    leido en 850; test completo de la 1.22.0, y medido en produccion el
    22-oct-2026 con cuatro letras). Nuestros programas de Delphi ponen la
    suya en UTF-8 (el nodo de escritorio, el renderizador). phPorLinea: git
    escribe su texto en UTF-8 y lo de los ficheros (un diff, un show) tal cual:
    cada LINEA, UTF-8 si lo es; si no, la ANSI de la maquina, la que leen dcc y
    el IDE en un fuente sin BOM - un fuente ANSI salia en el diff con cada letra
    cambiada (1252 leido en 850), y en una salida con un fuente UTF-8 y uno ANSI
    los dos (completo de Opus de la 1.22.1). }
  TPaginaDelHijo = (phConsola, phAnsi, phPorLinea);

function RunMsBuild(ADprojPath: string; const APlatform, AConfig, ATarget: string;
  const AProfile: string = ''; const ADeviceId: string = '';
  ATimeoutMs: Integer = 600000; const ASdk: string = '';
  const AVerbosity: string = ''): TJSONObject;

{ Runs a command line with stdout+stderr captured (no shell). }
{ Generates the deployment manifest (.deployproj + its import line in the
  .dproj) when the project has none - minimal for PAServer platforms, the full
  staging map for Android; never touches an existing one. Exposed for
  delphi_config add-deployfile, which needs a manifest to add entries to.
  AConfig: la del build que lo pide (delphi_build); un proyecto que no declara
  configuraciones compila cualquiera, y su manifiesto la tiene que llevar
  (A35 de la 1.23). }
procedure EnsureDeployManifest(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean; const AConfig: string = '');

{ Los <nombre>.sdk que el IDE tiene registrados para una plataforma. Expuesto
  porque delphi_config lo necesita para validar el SDK que se fija en un
  proyecto: una sola definicion de "que SDK hay", no dos que se desincronizan. }
function SdksDePlataforma(const AVersion, APlat: string): TArray<string>;

{ El SDK que fija EL PROYECTO para esa plataforma (PlatformSDK de su
  PropertyGroup), y el que el SDK Manager del IDE tiene por defecto para ella.
  El build lee el primero; delphi_config view, el segundo (y el del proyecto
  con el lector del build, EffectiveProperty). }
function ProyectoDeclaraSdk(const ADproj, APlat, AConfig: string; out ASdk: string): Boolean;
function SdkPorDefectoDelIde(const AVersion, APlat: string): string;
{ ...y el perfil que el IDE tiene para esa plataforma: UNO para todos sus
  proyectos (el IDE no guarda un perfil por proyecto) }
function PerfilPorDefectoDelIde(const AVersion, APlat: string): string;

{ Lanza ACmdLine FUERA del job object de la llamada y espera a que el proceso
  lanzado termine (hasta ATimeoutMs), sin capturar nada. Solo para demonios
  que deben sobrevivir a la llamada: el servidor de adb (`adb start-server`
  deja un demonio en el puerto 5037 y sale). Dentro del job, KILL_ON_JOB_CLOSE
  lo mataba al acabar la llamada y cada conexion wifi se perdia entre una
  llamada y la siguiente (medido 2026-09-23, G.23 de Hermes). True si el
  lanzador termino a tiempo. }
function RunDetached(const ACmdLine: string; ATimeoutMs: Integer): Boolean;

function RunCaptured(const ACmdLine: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;

{ Lo que hacer cuando paclient no reconoce el otro lado, leido de su propia
  salida: "Platform Assistant Server version mismatch - expecting version
  'X'" (el PAServer de ese host:puerto es el de otro Delphi: una maquina
  puede tener uno por Delphi, cada uno en su puerto - el Zorin de David, la
  13.1 y la 13.2) o "Profile platform (A) does not match remote/host machine
  platform (B)". '' si no dice ninguna. Los textos de paclient, leidos de
  paclient.exe (37.1.10.6). Lo usan el helper de paclient
  (Lsp.RemoteRun.Paclient) y el deploy, que lanza paclient por la tarea
  PAClient de msbuild. }
function AvisoDePaclient(const ASalida: string): string;

{ Same, with an explicit working directory ('' = inherit). APagina: en que
  pagina escribe el hijo lo que no es UTF-8 (TPaginaDelHijo). }
function RunCapturedIn(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal; const AEntorno: string = '';
  APagina: TPaginaDelHijo = phConsola): string;

{ Como RunCapturedIn, pero DENTRO del contenedor AC (Lsp.Sandbox), que ya
  tiene su carpeta preparada: AWorkDir. Falla cerrado: si Windows no lo lanza
  dentro, NO se lanza fuera - EOSError con el codigo de Windows (hasta la
  1.10 un lanzamiento a integridad baja que fallaba se repetia SIN jaula y
  solo lo avisaba sandboxed=false). ATimedOut dice si se le mato por tiempo:
  sin eso un proceso muerto era igual que uno que fallaba al instante, mismo
  exitCode 1 y salida vacia (medido 2026-08-25). }
function RunCapturedEnContenedor(const ACmdLine, AWorkDir: string;
  const AC: TContenedor; ATimeoutMs: Integer; out AExitCode: Cardinal;
  out ATimedOut: Boolean; APagina: TPaginaDelHijo = phConsola): string;

implementation

uses
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
  Lsp.ErrorMode,
  Lsp.PackageMap,
  Lsp.ProjectUnits,
  Lsp.ProcessLaunch,
  Lsp.Regex,
  Lsp.References, // SkipIdeArtifacts: lo que no es fuente de nadie (papelera, salidas)
  Lsp.Casa,
  Lsp.Settings,
  Lsp.Lugares,
  Lsp.Codificacion,
  Lsp.AtomosRtl,
  Lsp.Styles, // RcLecturasDenegadas: EL juez del .rc (el de delphi_styles build)
  Lsp.NetDrives,
  Lsp.Rutas,
  Lsp.NombresDeTrabajo,
  Lsp.Listas;

var
  // Serializes every msbuild the server runs (see RunMsBuild).
  GBuildLock: TCriticalSection;

function RunDetached(const ACmdLine: string; ATimeoutMs: Integer): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  Result := False;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  Cmd := ACmdLine;
  UniqueString(Cmd); // CreateProcessW puede modificar el buffer
  // Sin job: ese es el punto. BREAKAWAY por si el propio servidor corriera
  // dentro de uno (el SCM no lo hace); si el job padre no lo permite, sin el.
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False,
    CREATE_NO_WINDOW or CREATE_SUSPENDED or CREATE_BREAKAWAY_FROM_JOB, nil, nil, SI, PI) then
    if not CreateProcess(nil, PChar(Cmd), nil, nil, False,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, SI, PI) then
      Exit;
  // Suspendido hasta decirle que no abra nunca un cuadro de error
  // (Lsp.ErrorMode): lo que se lanza aqui vive mas que la peticion - el
  // demonio de adb, que hereda el modo - y nadie le contestaria
  NoErrorDialogs(PI.hProcess);
  ResumeThread(PI.hThread);
  try
    Result := WaitForSingleObject(PI.hProcess, ATimeoutMs) = WAIT_OBJECT_0;
  finally
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end;
end;

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
  Ui.UIRestrictionsClass := JOB_OBJECT_UILIMIT_EXITWINDOWS or
    JOB_OBJECT_UILIMIT_SYSTEMPARAMETERS or JOB_OBJECT_UILIMIT_DISPLAYSETTINGS;
  // Un job sin sus limites no confina nada (ni kill-on-close, ni el tope de
  // memoria, ni el de procesos): cuenta como un job que no se pudo crear. Un
  // test no corre (fail-closed, ETestNoConfinado); build y git siguen sin job,
  // como cuando CreateJobObject falla. Se ignoraba lo que devolvia (1.5 de la
  // lista de medidas, V51 de la 1.23; el fallo no se puede provocar sin
  // inyectarlo: el tope de 3 GiB SI se midio, negado dentro y libre fuera)
  if not SetInformationJobObject(Result, JobObjectExtendedLimitInformation, @Ext, SizeOf(Ext)) or
     not SetInformationJobObject(Result, JobObjectBasicUIRestrictions, @Ui, SizeOf(Ui)) then
  begin
    CloseHandle(Result);
    Result := 0;
  end;
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

// APIs de Job que la RTL de este Delphi no declara (como las constantes que
// CreateConfinedJob define a mano): con su nombre real en kernel32.
function QueryInformationJobObject_(hJob: THandle; InfoClass: DWORD;
  Info: Pointer; Len: DWORD; RetLen: PDWORD): BOOL; stdcall;
  external kernel32 name 'QueryInformationJobObject';

function TerminateJobObject_(hJob: THandle; ExitCode: UINT): BOOL; stdcall;
  external kernel32 name 'TerminateJobObject';

const
  JobObjectBasicAccountingInformation_ = 1;

type
  TJobAccounting_ = record
    TotalUserTime: Int64;
    TotalKernelTime: Int64;
    ThisPeriodTotalUserTime: Int64;
    ThisPeriodTotalKernelTime: Int64;
    TotalPageFaultCount: DWORD;
    TotalProcesses: DWORD;
    ActiveProcesses: DWORD;
    TotalTerminatedProcesses: DWORD;
  end;

{ Mata el arbol del job y NO vuelve hasta que no queda ninguno vivo (o se agota
  APlazoMs): la foto y el borrado de la copia del test no deben correr con un
  hijo del test aun escribiendo. Para el camino del contenedor. }
procedure EsperaJobVacio(AJob: THandle; APlazoMs: Cardinal);
var
  Info: TJobAccounting_;
  Fin: UInt64;
  RetLen: DWORD;
begin
  if not TerminateJobObject_(AJob, 1) then
  begin
    var ErrT := GetLastError; // antes de llamar al log, que lo cambiaria
    try TLogger.Warning(MsgFmt(SL_TEST_JOB_TERMINAR_FMT, [ErrT])); except end;
  end;
  Fin := GetTickCount64 + APlazoMs;
  repeat
    FillChar(Info, SizeOf(Info), 0);
    if not QueryInformationJobObject_(AJob,
      JobObjectBasicAccountingInformation_, @Info, SizeOf(Info), @RetLen) then
    begin
      var ErrQ := GetLastError;
      try TLogger.Warning(MsgFmt(SL_TEST_JOB_CONSULTAR_FMT, [ErrQ])); except end;
      Exit; // si no se puede preguntar, no colgar la limpieza por ello
    end;
    if Info.ActiveProcesses = 0 then
      Exit;
    Sleep(10);
  until GetTickCount64 >= Fin;
end;

{ El programa de una linea de mando, solo su nombre, para el log: la linea
  entera puede llevar lo que no se imprime (la URL de un clone con credenciales) }
function ProgramaDe(const ACmdLine: string): string;
var
  S: string;
  Fin: Integer;
begin
  S := ACmdLine.TrimLeft;
  if S.StartsWith('"') then
  begin
    Fin := S.IndexOf('"', 1);
    if Fin < 0 then
      Fin := S.Length;
    S := S.Substring(1, Fin - 1);
  end
  else
  begin
    Fin := S.IndexOf(' ');
    if Fin >= 0 then
      S := S.Substring(0, Fin);
  end;
  Result := TPath.GetFileName(S);
end;

{ Lo que escribio un hijo en su tuberia, como texto, segun en que pagina
  escribe lo que no es UTF-8 (TPaginaDelHijo). Sale de RunCore para que
  phPorLinea decodifique cada linea con la regla de phAnsi. }
function DecodificaHijo(const ABytes: TBytes; APagina: TPaginaDelHijo): string;
begin
  // phPorLinea: cada linea por su cuenta, con su salto. Una secuencia UTF-8
  // nunca lleva un byte 10, asi que partir por el no rompe ninguna
  if APagina = phPorLinea then
  begin
    var SB := TStringBuilder.Create;
    try
      var Ini := 0;
      while Ini <= High(ABytes) do
      begin
        var Fin := Ini;
        while (Fin < High(ABytes)) and (ABytes[Fin] <> 10) do
          Inc(Fin);
        SB.Append(DecodificaHijo(Copy(ABytes, Ini, Fin - Ini + 1), phAnsi));
        Ini := Fin + 1;
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
    Exit;
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
  if LooksUtf8(ABytes) then
    try
      Exit(TEncoding.UTF8.GetString(ABytes));
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
    var Cp: Cardinal;
    if APagina = phAnsi then
      // un programa de Delphi a una tuberia, o una linea de git
      // (TPaginaDelHijo): EL lector de la ANSI de la maquina
      Cp := PaginaAnsi
    else
    begin
      Cp := GetConsoleOutputCP;
      if Cp = 0 then
        Cp := GetOEMCP; // tray and service have no console: ask the machine
    end;
    var Enc := TEncoding.GetEncoding(Cp);
    try
      try
        Result := Enc.GetString(ABytes);
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
        SetLength(Result, Length(ABytes));
        for var K := 0 to High(ABytes) do
          Result[K + 1] := Char(ABytes[K]);
      end;
    finally
      Enc.Free; // GetEncoding returns a new object, not a singleton
    end;
  end;
end;

function RunCore(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  AContenedor: PContenedor; out AExitCode: Cardinal;
  out ATimedOut: Boolean; const AEntorno: string = '';
  APagina: TPaginaDelHijo = phConsola): string;
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
  Job: THandle; // declared here: it outlives the launch block below
  Matado: Boolean; // por plazo: sus atomos se limpian al cerrar sus handles

  // lo leido del tubo, al final de lo que lleva
  procedure Guarda(ALeidos: DWORD);
  begin
    var Prev := Length(Bytes);
    SetLength(Bytes, Prev + Integer(ALeidos));
    Move(Buffer[0], Bytes[Prev], ALeidos);
  end;

begin
  Matado := False;
  // From the pipe to the closing of the child's end, nobody else launches:
  // another child would take this end with it (see Lsp.Sandbox, 2026-09-29).
  EnterSpawn;
  try
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  if not CreatePipe(ReadH, WriteH, @SA, 0) then
    raise Exception.Create(MsgText(SE_BUILD_CREATEPIPE_FAILED));
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
  Job := CreateConfinedJob;
  // Con contenedor el job es OBLIGATORIO: sin el no se corre (fail-closed).
  // Para build/git es best-effort (es el toolchain de confianza).
  if (AContenedor <> nil) and (Job = 0) then
  begin
    CloseHandle(ReadH);
    CloseHandle(WriteH);
    raise ETestNoConfinado.Create(MsgText(SR_TEST_SIN_JAULA));
  end;
  // Con contenedor, DENTRO o nada (Lsp.Sandbox): no hay vuelta a un
  // lanzamiento normal. Hasta la 1.10, si la jaula fallaba el test corria
  // sin ella y solo lo decia sandboxed=false.
  if AContenedor <> nil then
    Launched := CreateProcessEnContenedor(AContenedor^, Cmd, WorkDirPtr,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, SI, PI)
  else
  begin
    var Env: PChar := nil;
    var Flags: DWORD := CREATE_NO_WINDOW or CREATE_SUSPENDED;
    if AEntorno <> '' then
    begin
      Env := PChar(AEntorno);
      Flags := Flags or CREATE_UNICODE_ENVIRONMENT;
    end;
    Launched := CreateProcessConHandles(Cmd, WorkDirPtr, Flags, Env, SI, PI);
  end;
  if not Launched then
  begin
    // What Windows said, read before anything else is called, and CARRIED
    // by the exception: EOSError.ErrorCode is how a caller tells "the
    // program is not there" (2) from the rest - delphi_git on a server
    // with no git (GIT-050). Its message is the one it always had; where
    // a tool prints the class too (delphi_styles: SYS-009) it reads
    // EOSError, and delphi_test answers it with its own tag (TEST-027).
    var LaunchError := GetLastError;
    if Job <> 0 then CloseHandle(Job);
    CloseHandle(ReadH);
    CloseHandle(WriteH);
    var NotLaunched := EOSError.Create(MsgFmt(SE_BUILD_CREATEPROCESS_FAILED_FMT, [LaunchError]));
    NotLaunched.ErrorCode := LaunchError;
    raise NotLaunched;
  end;
  if AContenedor <> nil then
  begin
    // el proceso esta SUSPENDED: si no se puede confinar en el job, se mata
    // sin haber ejecutado nada y se falla cerrado - nunca corre fuera del job
    if not AssignProcessToJobObject(Job, PI.hProcess) then
    begin
      TerminateProcess(PI.hProcess, 1);
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
      CloseHandle(Job);
      CloseHandle(ReadH);
      CloseHandle(WriteH);
      raise ETestNoConfinado.Create(MsgText(SR_TEST_SIN_JAULA));
    end;
  end
  else if Job <> 0 then
    AssignProcessToJobObject(Job, PI.hProcess);
  NoErrorDialogs(PI.hProcess); // msbuild, git, a test exe: none may wait behind a dialog (Lsp.ErrorMode)
  ResumeThread(PI.hThread);
  CloseHandle(WriteH); // ours no more; EOF arrives when the child exits
  finally
    LeaveSpawn;
  end;

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
        Guarda(BytesRead);
      end
      else
      begin
        // no data right now: has the process finished, or timed out? Hasta el
        // plazo y no mas: con un sondeo fijo de 50 ms un plazo mas corto se
        // cumplia tarde, y un run de 55 ms pasaba con timeoutms=1 (medido)
        var Resta: UInt64 := 0;
        var Ahora := GetTickCount64;
        if Ahora < Deadline then
          Resta := Deadline - Ahora;
        if Resta > 50 then
          Resta := 50;
        if WaitForSingleObject(PI.hProcess, DWORD(Resta)) = WAIT_OBJECT_0 then
        begin
          // drain whatever is still buffered, then stop
          if PeekNamedPipe(ReadH, nil, 0, nil, @Avail, nil) and (Avail = 0) then
            Break;
        end;
      end;
      if GetTickCount64 >= Deadline then // (con >, en el tic justo el sondeo de 0 ms giraba en vacio)
      begin
        // cortado por tiempo es MATADO: lo que ya acabo solo (lo que queda en el
        // tubo es de antes, o de un nieto que el job matara) no se da por
        // cortado. Se marcaba igual, y delphi_test contestaba result=timeout con
        // el exitCode 0 de un run que habia acabado bien (medido el 23-oct-2026:
        // 10 de 10 con timeoutms=1 y un exe de 54 ms)
        // (y matado de verdad: uno que ya estaba saliendo no se deja matar, y
        // su exitCode es el suyo - medido, 1 de 10 con timeoutms=1)
        if (WaitForSingleObject(PI.hProcess, 0) = WAIT_TIMEOUT) and
           TerminateProcess(PI.hProcess, 1) then
        begin
          TimedOut := True;
          Matado := True;
          Break;
        end;
        // ...y lo que acabo solo se lee ENTERO: lo suyo cabe en el tubo (no pudo
        // acabar con una escritura esperando). Se dejaba de leer al vencer el
        // plazo, y su run salia no-tests (medido). Lo que hay AHORA, no lo que
        // un nieto siga escribiendo: a ese lo mata el job
        if PeekNamedPipe(ReadH, nil, 0, nil, @Avail, nil) then
          while Avail > 0 do
          begin
            if not ReadFile(ReadH, Buffer, SizeOf(Buffer), BytesRead, nil) or (BytesRead = 0) then
              Break;
            Guarda(BytesRead);
            if BytesRead >= Avail then
              Avail := 0
            else
              Dec(Avail, BytesRead);
          end;
        Break;
      end;
    until False;
    if not TimedOut then
    begin
      WaitForSingleObject(PI.hProcess, 10000);
      // y su hilo, como abajo: lo que dejo se juzga con el hilo terminado
      WaitForSingleObject(PI.hThread, 5000);
    end
    else
    begin
      // que muera, el hilo tambien: el proceso se senala antes de que su hilo
      // principal deje de contestar STILL_ACTIVE (medido el 19-oct-2026), y
      // la guarda de Lsp.AtomosRtl lo tomaria por vivo. Sus atomos, abajo
      WaitForSingleObject(PI.hProcess, 5000);
      WaitForSingleObject(PI.hThread, 5000);
    end;
    if not GetExitCodeProcess(PI.hProcess, AExitCode) then
      AExitCode := DWORD(-1);
    ATimedOut := TimedOut;
  finally
    CloseHandle(ReadH);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    // lo que matamos, lo limpiamos: un hijo VCL/FMX muerto sin finalizar deja
    // sus atomos globales y, llena la tabla de la sesion, Windows no arranca
    // ningun proceso mas (Lsp.AtomosRtl; la maquina se cayo el 18-oct-2026).
    // Con sus handles YA cerrados: un muerto con un handle abierto sigue
    // existiendo para OpenProcess y la guarda lo tomaba por vivo (medido)
    if Matado then
      BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId)
    else
    begin
      // ...y lo que acabo POR SU CUENTA sin finalizar: su Job lo mata por una
      // excepcion sin tratar (DIE_ON_UNHANDLED_EXCEPTION), un paquete de diseno
      // revienta dentro del renderizador. Dejaba sus atomos igual que un
      // matado, y aqui solo se limpiaba lo matado (medido el 20-oct-2026: un
      // juez del orden muerto solo, que set tolera, dejo sus tres). Barato
      // para el que finalizo. Queda en el log con su codigo
      var Dejados := BorraAtomosSiLosDejo(PI.dwProcessId, PI.dwThreadId);
      if (Dejados > 0) or (AExitCode >= $C0000000) then
        try TLogger.Warning(MsgFmt(SL_HIJO_SIN_FINALIZAR_FMT,
          [ProgramaDe(ACmdLine), AExitCode, Dejados])); except end;
    end;
    // Closing the job kills any process in the tree still alive (e.g. children
    // orphaned by a timeout): kill-on-close leaves nothing running behind us.
    if Job <> 0 then
    begin
      // Con contenedor no se vuelve hasta que el arbol del test este muerto:
      // la foto y el borrado de la copia no deben correr con un hijo vivo.
      if AContenedor <> nil then
      begin
        EsperaJobVacio(Job, 5000);
        // y si al test hubo que matarlo, lo que dejo (Lsp.AtomosRtl no toca
        // nada de un pid o un hilo que sigan vivos: si acabo solo, finalizo)
        BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId);
      end;
      CloseHandle(Job);
    end;
  end;
  // lo que escribio, como texto (DecodificaHijo)
  Result := DecodificaHijo(Bytes, APagina);
end;

function AvisoDePaclient(const ASalida: string): string;
var
  M: TMatch;
begin
  Result := '';
  M := TRegEx.Match(ASalida,
    'Platform Assistant Server version mismatch - expecting version ''([^'']*)''',
    [roIgnoreCase]);
  if M.Success then
    Exit(MsgFmt(SN_PACLIENT_OTRO_DELPHI_FMT, [GrupoDe(M, 1)]));
  M := TRegEx.Match(ASalida,
    'Profile platform \(([^)]*)\) does not match remote/host machine platform \(([^)]*)\)',
    [roIgnoreCase]);
  if M.Success then
    Result := MsgFmt(SN_PACLIENT_OTRA_PLATAFORMA_FMT, [GrupoDe(M, 1), GrupoDe(M, 2)]);
end;

function RunCapturedIn(const ACmdLine, AWorkDir: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal; const AEntorno: string; APagina: TPaginaDelHijo): string;
var
  Ignored: Boolean;
begin
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, nil, AExitCode, Ignored, AEntorno, APagina);
end;

function RunCapturedEnContenedor(const ACmdLine, AWorkDir: string;
  const AC: TContenedor; ATimeoutMs: Integer; out AExitCode: Cardinal;
  out ATimedOut: Boolean; APagina: TPaginaDelHijo): string;
var
  Copia: TContenedor;
begin
  Copia := AC; // RunCore lo quiere por puntero, y AC es const
  Result := RunCore(ACmdLine, AWorkDir, ATimeoutMs, @Copia, AExitCode,
    ATimedOut, '', APagina);
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
    '<PropertyGroup %s>' + sLineBreak +
    '%s    <VerInfo_Keys Condition="''$(VerInfo_Keys)''==''''">package=com.embarcadero.$(MSBuildProjectName);' +
    'label=$(MSBuildProjectName);versionCode=1;versionName=1.0.0;persistent=False;' +
    'restoreAnyVersion=False;installLocation=auto;largeHeap=False;theme=TitleBar;' +
    'hardwareAccelerated=true;apiKey=;minSdkVersion=23;targetSdkVersion=35</VerInfo_Keys>' + sLineBreak +
    '%s    <VerInfo_IncludeVerInfo Condition="''$(VerInfo_IncludeVerInfo)''==''''">true</VerInfo_IncludeVerInfo>' + sLineBreak +
    '%s    <EnabledSysJars Condition="''$(EnabledSysJars)''==''''">%s</EnabledSysJars>' + sLineBreak +
    '%s    <BT_BuildType Condition="''$(BT_BuildType)''==''''">Debug</BT_BuildType>' + sLineBreak +
    '%s</PropertyGroup>';

{ La cabecera del manifiesto que genera el servidor, la del IDE: el Import
  de CodeGear.Deployment.targets y su ProjectFileVersion (estaba escrita dos
  veces, en el de Android y en el de las demas plataformas). }
function CabeceraDeManifiesto: string;
begin
  Result := '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '    <Import Condition="Exists(''$(BDS)\bin\CodeGear.Deployment.targets'')" ' +
    'Project="$(BDS)\bin\CodeGear.Deployment.targets"/>' + sLineBreak +
    '    <ProjectExtensions>' + sLineBreak +
    '        <ProjectFileVersion>12</ProjectFileVersion>' + sLineBreak +
    '    </ProjectExtensions>' + sLineBreak;
end;

{ Las configuraciones con grupo en un manifiesto que genera el servidor: las
  que el proyecto compila (TDprojInfo.Compilables). Eran 'Debug','Release' a
  fuego en los tres generadores: con otra (Prod) el deploy no enviaba nada y
  msbuild decia exito tras limpiar la carpeta del destino (medido el
  20-oct-2026 contra el Zorin). Un .dproj que no declara ninguna (anterior a
  las configuraciones) se queda con las dos de siempre, y la del build que lo
  pide (AConfig): ConfigDelBuild le deja compilar cualquiera, y sin su grupo el
  deploy no enviaba nada (A35 de la 1.23). }
function ConfigsDelManifiesto(const ADprojXml: string; const AConfig: string = ''): TArray<string>;
begin
  Result := InfoDeDproj(ADprojXml).Compilables;
  if Length(Result) = 0 then
  begin
    Result := ['Debug', 'Release'];
    if (AConfig <> '') and (IndexText(AConfig, Result) < 0) then
      Result := Result + [AConfig];
  end;
end;

{ La carpeta del binario de ESTE build relativa al proyecto, como la escribe
  el IDE en un DeployFile: EL compositor (Lsp.Dproj.SalidaDelBinario) sin el
  '.\' de delante. La de los tres manifiestos (A19 de la 1.23). }
function CarpetaDelDespliegue(const ADprojXml, ADir, AName, APlat, ACfg: string): string;
begin
  Result := SalidaDelBinario(ADprojXml, ADir, AName, APlat, ACfg);
  if Result.StartsWith('.\') then
    Result := Result.Substring(2);
end;

function AndroidDeployXml(const ADprojXml, ADir, AName, APlat, ABdsRoot: string;
  const AConfigs: TArray<string>): string;
var
  SB: TStringBuilder;
  Cfg, Libs, OutName, Entradas, Bin, Salida: string;
  E: TApkEntry;

  procedure Add(const AInclude, ADir, AFile, ACls: string; ARequired: Boolean);
  begin
    Entradas := Entradas + XmlDeployFile(AInclude, '', AName + '\' + ADir, AFile, ACls, 1, ARequired);
  end;

begin
  Libs := CarpetaDeLibreriasDelApk(APlat); // library\lib\<abi>\, por la tabla de Lsp.Dproj
  SB := TStringBuilder.Create;
  try
    SB.Append(CabeceraDeManifiesto);
    for Cfg in AConfigs do
    begin
      Entradas := '';
      // lo que deja el build por EL nombrador, como los otros manifiestos, y
      // dentro del apk con el nombre que carga (LibreriaDelApk). Todo en la
      // carpeta de salida de ESE build (CarpetaDelDespliegue): con
      // $(Platform)\$(Config) a mano, un set-output dejaba el Deploy sin
      // AndroidManifest.xml (A19 de la 1.23, medido)
      Bin := LibreriaDelApk(AName);
      Salida := CarpetaDelDespliegue(ADprojXml, ADir, AName, APlat, Cfg);
      Add(Salida + '\AndroidManifest.xml', '', 'AndroidManifest.xml',
        'ProjectAndroidManifest', True);
      Add(Salida + '\' + NombreDelBinario(ADprojXml, AName, APlat, Cfg), Libs, Bin,
        'ProjectOutput', True);
      for E in APK_RES do
        Add(Salida + '\' + E.Src, E.Dir, E.Name, E.Cls, False);
      for E in APK_BDS do
        if TFile.Exists(TPath.Combine(ABdsRoot, E.Src)) then
        begin
          if E.Name = '*' then
            OutName := Bin
          else
            OutName := E.Name;
          Add('$(BDS)\' + E.Src, E.Dir, OutName, E.Cls, False);
        end;
      // EL escritor del grupo de una plataforma y config del .deployproj (Lsp.Dproj)
      SB.AppendLine('    ' + XmlGrupoDeDespliegue(DeployGroupCondition(APlat, Cfg), Entradas));
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
function OutputDeployEntry(const ADprojXml, ADir, APlat, ACfg, AName: string): string;
var
  OutDir, Ext, Include: string;
begin
  // la carpeta de salida de ESTE build, por EL compositor (CarpetaDelDespliegue):
  // mezclaba los DCC_ExeOutput de TODOS los grupos (MergeProperty) y
  // expandia a mano, y un proyecto con carpeta propia en otra plataforma podia
  // desplegar desde esa (revisor del 21-oct-2026)
  OutDir := CarpetaDelDespliegue(ADprojXml, ADir, AName, APlat, ACfg);
  // el nombre del binario por EL nombrador (OutputExt de esa plataforma y
  // config, como lo escribe el IDE en el DeployFile: App.x64.exe)
  Ext := NombreDelBinario(ADprojXml, AName, APlat, ACfg);
  Include := IncludeTrailingPathDelimiter(OutDir) + Ext;
  Result := XmlDeployFile(Include, ACfg, AName + '\', Ext, 'ProjectOutput', 1, True);
end;

{ Adds the ProjectOutput entries for APlat to an existing manifest that has
  none for it (empty or missing platform group). True when it changed. }
function EnsurePlatformOutputEntries(const ADeployProj, ADprojPath, APlat,
  AName, AConfig: string): Boolean;
var
  Enc, Xml, DprojXml, Entries: string;
  Cfg: string;
begin
  Result := False;
  Xml := PatchLoadText(ADeployProj, Enc);
  // any DeployFile with ProjectOutput inside a group of this platform? Por EL
  // analisis del .deployproj: era una regex por grupos y un Contains del texto
  for var G in GruposDe(Xml, 'ItemGroup') do
    if SameText(PlataformaDeGrupoDeDespliegue(G.Condicion), APlat) then
      for var C in TramosEnGrupo(Xml, 'DeployClass', G) do
        if SameText(ValorDeTramo(Xml, C).Trim, 'ProjectOutput') then
          Exit;
  DprojXml := LeeTexto(ADprojPath, [ltJaula]);
  Entries := '';
  for Cfg in ConfigsDelManifiesto(DprojXml, AConfig) do
    Entries := Entries + OutputDeployEntry(DprojXml, ExtractFileDir(ADprojPath), APlat, Cfg, AName);
  // en el grupo de la plataforma, como lo deja el IDE (Lsp.Dproj)
  Xml := ConEntradasEnSuGrupo(Xml, APlat, Entries);
  if Xml = '' then
    Exit;
  PatchSaveConSuSalto(ADeployProj, Xml, Enc);
  Result := True;
end;

procedure EnsureDeployManifestNucleo(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean; const AConfig: string);
const
  // The exact line the IDE writes into every .dproj it saves. Projects
  // scaffolded by delphi_create (and some hand-written ones) lack it, and
  // without it the generated manifest is never imported - Deploy still
  // fails MSB4057 with the .deployproj sitting right there (measured).
  DEPLOY_IMPORT = '<Import Project="$(MSBuildProjectName)' + EXT_MANIFIESTO + '" ' +
    'Condition="Exists(''$(MSBuildProjectName)' + EXT_MANIFIESTO + ''')"/>';
  // el Import que hace de ancla, por su Project
  ANCHOR_PROJECT = '$(BDS)\Bin\CodeGear.Delphi.Targets';
var
  F, N, Xml: string;
  Cfg: string;
  Ancla: TTramoXml;
begin
  AGenerated := False;
  N := TPath.GetFileNameWithoutExtension(ADprojPath);
  // 1) the .dproj must import the manifest (PatchLoadText/SaveText keep the
  //    encoding and leave the __delphi-patch safety copy, same as the
  //    add-platform editor).
  var Enc := '';
  var Dproj := PatchLoadText(ADprojPath, Enc);
  var Changed := False;
  // los <Import> del .dproj por EL analisis: el ancla era un Pos del texto
  // con el Project el primero, y "ya importa el manifiesto" un Contains de
  // '.deployproj' en cualquier sitio, un comentario incluido
  var P := 0;
  var YaLoImporta := False;
  for var T in TramosDeEtiqueta(Dproj, 'Import', True) do
  begin
    var Proyecto := AtributoDeTramo(Dproj, T, 'Import', 'Project');
    if (P = 0) and SameText(Proyecto, ANCHOR_PROJECT) then
    begin
      P := T.Abre;
      Ancla := T;
    end;
    if EsManifiesto(Proyecto) then
      YaLoImporta := True;
  end;
  var Indent := '';
  // solo el blanco de la linea del ancla: se copiaba todo lo de delante, y
  // con otra etiqueta en esa linea se duplicaba (revisor de la 1.15.0)
  if P > 0 then
    Indent := SangriaDeLaLineaEn(Dproj, P);
  if (P > 0) and not YaLoImporta then
  begin
    Dproj := Copy(Dproj, 1, Ancla.Cierra - 1) + sLineBreak + Indent +
      DEPLOY_IMPORT + Copy(Dproj, Ancla.Cierra, MaxInt);
    Changed := True;
  end;
  // 1b) Android fallback version properties, only when the project has no
  //     Android version block at all (ours contains minSdkVersion too, so
  //     this also makes the insert idempotent). Placed before the anchor.
  var TieneMinSdk := False;
  for var C in ClavesDeVersion(Dproj) do
    TieneMinSdk := TieneMinSdk or SameText(C.Nombre, 'minSdkVersion');
  if (P > 0) and (SistemaDePlataforma(APlat) = spAndroid) and not TieneMinSdk then
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
    // justo delante del ancla (con el ancla lo primero de su linea, igual que
    // al principio de la linea; con algo delante, no se mete antes de ello)
    Dproj := Copy(Dproj, 1, P - 1) +
      Format(ANDROID_PROPS, [XmlAtributo('Condition', DeployGroupCondition(APlat)), Indent, Indent, Indent,
        XmlEscape(Jars), Indent,
        Indent]) + sLineBreak + Indent + Copy(Dproj, P, MaxInt);
    Changed := True;
  end;
  if Changed then
    PatchSaveConSuSalto(ADprojPath, Dproj, Enc);
  // 1c) Android: the AndroidManifest.template.xml seed the IDE would write,
  //     copied from the product's ObjRepos - never invented, never
  //     overwritten (an existing template is the project's own).
  if SistemaDePlataforma(APlat) = spAndroid then
  begin
    var Tpl := TPath.Combine(TPath.GetDirectoryName(ADprojPath),
      'AndroidManifest.template.xml');
    var Seed := TPath.Combine(ABdsRoot, 'ObjRepos\en\Android\AndroidManifest.xml');
    // por el escritor que pregunta a la puerta (AtomicWrite), no TFile.Copy:
    // en una raiz de solo lectura esto escribia igual (quinta revision)
    if (not TFile.Exists(Tpl)) and TFile.Exists(Seed) then
      AtomicWrite(Tpl, LeeBytes(Seed, [ltIde])); // la plantilla del IDE, por la puerta (M1)
  end;
  // 2) the manifest itself, only when the project has none - BUT an IDE
  //    manifest written before the platform was ever deployed from the IDE
  //    carries an EMPTY group for it (<ItemGroup Condition="'$(Platform)'==
  //    'Linux64'"/>, measured on GalateaFMX): msbuild then deploys nothing
  //    and still succeeds. The project output is added to such a group.
  F := ManifiestoDe(ADprojPath);
  if TFile.Exists(F) then
  begin
    if SistemaDePlataforma(APlat) <> spAndroid then
      AGenerated := EnsurePlatformOutputEntries(F, ADprojPath, APlat, N, AConfig);
    Exit;
  end;
  if SistemaDePlataforma(APlat) = spAndroid then
  begin
    // como lo escribe el IDE (el juez: UTF-8 con BOM, medido en sus
    // .deployproj): en ASCII un nombre de proyecto no ASCII salia con '?' en
    // el Include (P3-L1 de la 1.18.0)
    EscribeTexto(F, AndroidDeployXml(Dproj, ExtractFileDir(ADprojPath), N, APlat, ABdsRoot,
      ConfigsDelManifiesto(Dproj, AConfig)), ltJaula, ekUtf8Bom);
    AGenerated := True;
    Exit;
  end;
  Xml := CabeceraDeManifiesto;
  for Cfg in ConfigsDelManifiesto(Dproj, AConfig) do
    // EL escritor del grupo de una plataforma y config (Lsp.Dproj) con LA
    // entrada del binario (OutputDeployEntry: su carpeta de salida y su nombre
    // por sus compositores); se escribia aqui a mano en $(Platform)\$(Config)
    // y sin su Configuration (A19 de la 1.23)
    Xml := Xml + '    ' + XmlGrupoDeDespliegue(DeployGroupCondition(APlat, Cfg),
      OutputDeployEntry(Dproj, ExtractFileDir(ADprojPath), APlat, Cfg, N)) + #13#10;
  Xml := Xml + '</Project>'#13#10;
  EscribeTexto(F, Xml, ltJaula, ekUtf8Bom); // como el de Android, arriba
  AGenerated := True;
end;

{ El manifiesto se escribe con el cerrojo de escritura, como todo lo que
  escribe: el build lo tomaba solo con el suyo, y un delphi_edit del .dproj
  a la vez se pisaba con el import que se anade aqui (quinta revision). }
procedure EnsureDeployManifest(const ADprojPath, APlat, ABdsRoot: string;
  out AGenerated: Boolean; const AConfig: string);
begin
  EnterFileEdit;
  try
    EnsureDeployManifestNucleo(ADprojPath, APlat, ABdsRoot, AGenerated, AConfig);
  finally
    LeaveFileEdit;
  end;
end;

{ F2613 "Unit 'X' not found" / F1026 "File not found: 'X.dcu'": the unit
  names the compiler could not resolve, in order, without duplicates. Por el
  CODIGO y el primer '...' que lo sigue, no por la prosa inglesa: un dcc
  traducido (dcc32370.de/.fr/.ja) dejaba missingUnits vacio y en quiet ni
  senal (lote 4 del censo de jueces, 18-oct-2026; 1.21.4). }
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
        'F2613:?[^'']*''([^'']+)''|F1026:?[^'']*''([^'']+)\.dcu''',
        [roIgnoreCase]);
      if not M.Success then
        Continue;
      // una rama de la alternativa: su grupo, por GrupoDe (Lsp.Regex)
      Name := GrupoDe(M, 1);
      if Name = '' then
        Name := GrupoDe(M, 2);
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

{ Los .pas que casan con AMascaras bajo ARaices, por EL recorredor y con la
  puerta de lectura sobre cada uno; fuera los artefactos (compilacion, las
  copias muertas del IDE, la papelera), juzgados bajo cada raiz. EL paseo de
  las fuentes de una unit: el de sus carpetas y el de sus nombres
  cualificados (UnitSourceFolders). }
function FuentesBajo(const ARaices, AMascaras: TArray<string>): TArray<string>;
var
  L: TList<string>;
  Files: TArray<string>;
begin
  L := TList<string>.Create;
  try
    for var Root in ARaices do
    begin
      try
        // por EL recorredor (WalkFiles): solo sigue los enlaces que esta
        // sesion puede leer y tolera una rama ilegible; GetFiles con
        // soAllDirectories cruzaba cualquier union (2h de la 1.18.4)
        Files := WalkFiles(Root, AMascaras);
      except
        Continue; // an unreadable root is not the agent's problem
      end;
      for var F in Files do
      begin
        var Dir := TPath.GetDirectoryName(F);
        // y LA puerta de lectura sobre cada candidata: el paseo de la RTL
        // sigue los enlaces, y un junction de las raices a una carpeta de
        // fuera daba como candidata lo que la jaula no deja leer (medido el
        // 4-oct-2026, test_missing_units)
        // ...y los artefactos BAJO la raiz (SkipBajoLaRaiz): por la ruta
        // absoluta, una raiz que cuelga de una carpeta Release no daba ninguna
        // candidata. Se saltaba ademas toda carpeta con '\backup' en la ruta,
        // una gramatica sin juez (el IDE no escribe carpetas backup) que
        // casaba con \BackupService\ (A10 de la 1.23, medido)
        if SkipBajoLaRaiz(F, Root) or (ReadPathDenied(Dir) <> '') then
          Continue;
        if not L.Contains(F) then
          L.Add(F);
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Where a unit's .pas lives: in the session's own roots (its workspace and
  its references) first, then in the library zone (RAD Studio installs,
  registered components, GetIt catalog): the folders to add-searchpath.
  Field 2026-08-22: a Linux64 build needed 2 failed builds per component to
  locate OBR's and Steema's Source folders by hand. Shortest paths first in
  each group, at most 6; IDE artifacts, build output and this server's
  trash copies are skipped (SkipIdeArtifacts). Only the library zone was
  searched, and a unit of the workspace itself (a vendor folder of the
  project: MCPServer.Types) got no candidate (BUILD-042, 3-oct-2026). An
  unrestricted session (no roots) does not walk the whole disk.
  Y si no hay ninguna con ESE nombre, en ACualificadas los nombres
  CUALIFICADOS que si tienen fuente (Dialogs -> FMX.Dialogs, Vcl.Dialogs),
  en los mismos sitios, sin repetir, por orden y a lo sumo 6: la F2613 de
  una unit que el proyecto no resuelve con SUS ambitos (DCC_Namespace), que
  se arregla escribiendola cualificada y no con un search path (Hermes,
  punto 9 de la 1.18.2: uses Dialogs en FMX, y la pista mandaba a
  add-searchpath). El juez es lo que hay en disco, no una lista de ambitos.
  Vacio para una unit ya cualificada. }
function UnitSourceFolders(const AUnit: string; out ACualificadas: TArray<string>): TArray<string>;

  function Busca(const ARaices: TArray<string>): TArray<string>;
  var
    L: TList<string>;
  begin
    L := TList<string>.Create;
    try
      for var F in FuentesBajo(ARaices, [AUnit + '.pas']) do
      begin
        var Dir := TPath.GetDirectoryName(F);
        if not L.Contains(Dir) then
          L.Add(Dir);
      end;
      L.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := Length(A) - Length(B);
          if Result = 0 then
            Result := CompareText(A, B);
        end));
      Result := L.ToArray;
    finally
      L.Free;
    end;
  end;

begin
  ACualificadas := [];
  var Sesion: TArray<string> := [];
  if HayJaula then
    Sesion := WorkspaceRoots + WorkspaceReadOnlyRoots;
  Result := Busca(Sesion);
  for var D in Busca(LibraryReadRoots) do
    if not RutaEnLista(D, Result) then
      Result := Result + [D];
  if Length(Result) > 6 then
    SetLength(Result, 6);
  if (Length(Result) > 0) or AUnit.Contains('.') then
    Exit;
  for var F in FuentesBajo(Sesion + LibraryReadRoots, ['*.' + AUnit + '.pas']) do
  begin
    var N := TPath.GetFileNameWithoutExtension(F);
    if IndexText(N, ACualificadas) < 0 then
      ACualificadas := ACualificadas + [N];
  end;
  TArray.Sort<string>(ACualificadas, TIStringComparer.Ordinal);
  if Length(ACualificadas) > 6 then
    SetLength(ACualificadas, 6);
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
//
// And the main source's IN (uses X in '...' of a .dpr, contains of a .dpk): dcc
// opens it like an {$I}, and nobody judged it - a uses X in 'C:\outside\X.pas'
// compiled (V14 of 1.23, measured live). Nor were the directives of a unit it
// reaches outside the project's folder: they are judged now like the folder's.

// Las directivas de AFichero que meten un fichero en el build ($I, $R), cada
// una donde la abre dcc (lo relativo desde la carpeta del fuente; "\x" y "X:y"
// desde ACarpetaDelBuild, la de dcc) y por la puerta de leer: '' o la negativa
// (BUILD-028, o BUILD-057 si no se sabe que fichero es). Lo que no se deja leer
// no se juzga: tampoco lo abre dcc. La pregunta de cada fuente que el build
// lee: los de la carpeta del proyecto, los que alcanza su in y los de las
// carpetas de la jaula de sus search paths (V14 de la 1.23).
function DirectivasDenegadas(const AFichero, ACarpetaDelBuild: string): string;
var
  Txt, Enc, Cand, Base: string;
begin
  Result := '';
  try
    Txt := PatchLoadText(AFichero, Enc);
  except
    Exit;
  end;
  Base := TPath.GetDirectoryName(AFichero);
  // EL lector de estas directivas es Lsp.ProjectUnits.DirectivasDeFichero:
  // lo comparte con la mudanza de delphi_move, que las re-apunta.
  for var D in DirectivasDeFichero(Txt) do
  begin
    // como la abre dcc (EL resolutor): lo relativo desde la carpeta del
    // fuente, "\x" y "X:y" desde la suya. Se juzgaban en la unidad del
    // PROCESO del servidor (A9b de la 1.23, medido). Una "X:y" de otra
    // unidad dcc la abre desde una carpeta que no nombra nadie: se niega
    Cand := RutaDesde(Base, D.Ruta, ACarpetaDelBuild);
    if Cand = '' then
    begin
      if EsRutaAMedias(D.Ruta) then
        Exit(MsgFmt(SR_BUILD_INCLUDE_NO_VERIFICABLE_FMT,
          [D.Texto.Trim, TPath.GetFileName(AFichero)]));
      Continue; // no es una ruta: dcc tampoco la abre
    end;
    if ReadPathDenied(Cand) <> '' then
      Exit(MsgFmt(SR_BUILD_INCLUDE_OUTSIDE_FMT,
        [D.Texto.Trim, TPath.GetFileName(AFichero)]));
  end;
end;

function IncludeDirectivesDenied(const ADprojPath: string): string;
var
  Dpr, Base, CarpetaDelBuild: string;
  Files: TList<string>;
  Unidades, Escritas, Rutas: TArray<string>;
begin
  Result := '';
  Dpr := DprDe(ADprojPath);
  // la carpeta en la que corre dcc (msbuild arranca en la del .dproj)
  CarpetaDelBuild := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  Files := TList<string>.Create;
  try
    if TFile.Exists(Dpr) then
    begin
      // (1.21.2) un fichero con OTRO nombre que esta sesion no puede leer
      // (un enlace duro a uno de fuera) lo leeria el compilador por este
      if EnlaceDuroIlegible(Dpr) <> '' then
        Exit(MsgFmt(SR_BUILD_ENLACE_DURO_FMT, [TPath.GetFileName(Dpr)]));
      Files.Add(Dpr);
      // lo que nombra con IN, por EL lector de sus entradas y en todas sus
      // ramas: la ruta se juzga exista o no (decir "existe" de una de fuera
      // seria un oraculo), y la de dentro, ademas, por sus directivas. Una
      // clausula que no se lee no se aprueba (USES-026). La que no se deja
      // leer no la juzga nadie: tampoco el bucle de abajo, ni la abre dcc
      try
        Result := LecturasDelIn(Dpr, Unidades, Escritas, Rutas);
      except
        Result := '';
        Rutas := nil;
      end;
      if Result <> '' then
        Exit;
      for var I := 0 to High(Rutas) do
      begin
        if Rutas[I] = '' then
          Exit(MsgFmt(SR_BUILD_IN_NO_VERIFICABLE_FMT, [Unidades[I], Escritas[I], TPath.GetFileName(Dpr)]));
        if ReadPathDenied(Rutas[I]) <> '' then
          Exit(MsgFmt(SR_BUILD_IN_FUERA_FMT, [Unidades[I], Escritas[I], TPath.GetFileName(Dpr)]));
        if not Files.Contains(Rutas[I]) then
          Files.Add(Rutas[I]);
      end;
    end;
    // Everything the compiler could reach from the project's own folder. Not
    // the .dproj's unit list: a unit can be pulled in by a search path and
    // still carry a directive, and this check is cheap enough to be broad.
    Base := CarpetaDelBuild;
    // por EL recorredor (WalkFiles): solo sigue los enlaces que esta sesion
    // puede leer (TDirectory con soAllDirectories cruzaba una union y leia
    // lo de detras: medida M1). TODO el arbol, no solo los fuentes (1.21.2):
    // la pregunta del enlace duro es de cada fichero (.pas, .inc, .res,
    // .ico...), y de los fuentes, ademas, sus directivas
    if TDirectory.Exists(Base) then
      for var SF in WalkFiles(Base, ['*'], False, True, nil, True) do
      begin
        if EnlaceDuroIlegible(SF) <> '' then
          Exit(MsgFmt(SR_BUILD_ENLACE_DURO_FMT, [TPath.GetFileName(SF)]));
        // ...y un fichero del arbol que es un ENLACE cuyo destino REAL sale de
        // las raices (un symlink o una junction): dcc lo sigue y leeria el de
        // fuera. El gate de la ruta del proyecto no veia estos; los de IN ya
        // van por ReadPathDenied (V14), y uno a DENTRO (real en la jaula) no
        // cae aqui (V3 de la 1.23)
        // ReadPathDenied resuelve la ruta REAL (coste): solo hace falta para un
        // ENLACE, lo unico del arbol que puede salir -WalkFiles ya garantiza que
        // un fichero normal esta dentro de las raices, y el enlace duro lo vio la
        // linea de arriba-. Asi el gate no paga RealPath por cada .pas de un
        // arbol grande (revisor V3)
        if EsEnlace(SF) and (ReadPathDenied(SF) <> '') then
          Exit(MsgFmt(SR_BUILD_FUENTE_ENLACE_FUERA_FMT, [TPath.GetFileName(SF)]));
        if EsRutaDeFuente(SF) and not Files.Contains(SF) then
          Files.Add(SF);
      end;
    for var F in Files do
    begin
      Result := DirectivasDenegadas(F, CarpetaDelBuild);
      if Result <> '' then
        Exit;
    end;
  finally
    Files.Free;
  end;
end;

{ Donde deja este build lo que produce, y si esta sesion puede escribir
  alli: la pregunta de todo escritor (EscrituraDenegada), para CADA carpeta
  de salida que declaran el .dproj y sus .optset (BuildOutputDirs), ANTES de
  que msbuild arranque - un Clean borra en esas mismas carpetas. El gate de
  la ruta del proyecto no bastaba: un .dproj con DCC_ExeOutput absoluto
  fuera de las raices dejaba App.exe y App.rsm fuera de la jaula (medido en
  vivo, 25-sep-2026). Una salida que no se sabe resolver no se aprueba.
  Las que el proyecto NO declara y el build SUPLE (SALIDAS_QUE_SUPLE_EL_BUILD:
  la carpeta del binario de este build, dentro del proyecto,
  BuildOutputDefault) salen en ASuplidas, juzgadas por los MISMOS jueces que
  las declaradas; la que no se suple (la .hpp) se sigue pidiendo (BUILD-030).
  Lo que el proyecto declara, sea lo que sea, se respeta tal cual. }
function SalidaDenegada(const ADprojPath, APlat, ACfg: string;
  out ASuplidas: TArray<TBuildOutputDir>): string;
begin
  Result := '';
  ASuplidas := nil;
  // La que NO declara la pone el IDE fuera del proyecto (David, 25-sep-2026).
  // Hasta la 1.21.2 se rechazaba; desde la 1.21.3 el build la suple el mismo
  // sin tocar el .dproj (David, 21-oct-2026: un proyecto real de veinte anos
  // compilaba en el IDE y aqui no, y el IDE dejo 14 .dcu de un componente en
  // Program Files).
  for var Falta in BuildOutputUndeclared(ADprojPath, APlat, ACfg) do
  begin
    if not MatchText(Falta, SALIDAS_QUE_SUPLE_EL_BUILD) then
      Exit(MsgFmt(SR_BUILD_OUTPUT_UNDECLARED_FMT, [Falta]));
    var Suplida := BuildOutputDefault(ADprojPath, APlat, ACfg);
    Suplida.Tag := Falta;
    ASuplidas := ASuplidas + [Suplida];
  end;
  // ...y cada carpeta, declarada o suplida, por los mismos jueces
  var Salidas := BuildOutputDirs(ADprojPath, APlat, ACfg) + ASuplidas;
  for var S in Salidas do
  begin
    if S.Dir = '' then
      Exit(MsgFmt(SR_BUILD_OUTPUT_UNRESOLVED_FMT, [S.Tag, S.Value]));
    var Motivo := EscrituraDenegada(S.Dir);
    if Motivo <> '' then
      Exit(MsgFmt(SR_BUILD_OUTPUT_DENIED_FMT, [S.Tag, S.Value, Motivo]));
    // ...y lo protegido que CONTIENE: dcc escribe alli ficheros con el nombre
    // que pone el PROYECTO, y un P.exe que ReadOnlyPaths nombraba dentro se
    // reescribia (medido el 14-oct, teoria del revisor del 2s; la regla del
    // 2r: un destino que contiene un lugar protegido, como MOVE-020)
    var Dentro := ProtegidoDentroDe(S.Dir);
    if Dentro <> '' then
      Exit(MsgFmt(SR_BUILD_OUTPUT_DENIED_FMT, [S.Tag, S.Value,
        MsgFmt(SF_GUARD_CONTIENE_LUGAR_PROTEGIDO_FMT, [Dentro])]));
  end;
  // los recursos que los targets compilan junto al .dproj (BuildResourceFiles):
  // el .res de version se reescribe en cada build que la lleva
  for var F in BuildResourceFiles(ADprojPath) do
  begin
    var Motivo := EscrituraDenegada(F);
    if Motivo <> '' then
      Exit(MsgFmt(SR_BUILD_OUTPUT_DENIED_FMT, ['BRCC_OutputDir', TPath.GetFileName(F), Motivo]));
  end;
end;

{ Los SDK que el IDE tiene registrados para una plataforma: los <nombre>.sdk
  de su APPDATA cuyo Profile_platform coincide. UN SDK = UNA CARPETA y aqui se
  decide con cual se compila - la misma idea que los SDK de Android. }
function SdksDePlataforma(const AVersion, APlat: string): TArray<string>;
var
  F, Xml: string;
  L: TStringList;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Sorted := True;
    // por LOS lectores: la lista de los .sdk del IDE (SdksDelIde) y su
    // plataforma (CamposDePerfil); eran un GetFiles y una regex propios
    for F in SdksDelIde(AVersion) do
    begin
      Xml := '';
      try
        Xml := LeeTexto(F, [ltIde]);
      except
        Continue;
      end;
      if SameText(CamposDePerfil(Xml).Plataforma.Trim, APlat.Trim) then
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
begin
  // por EL lector de la configuracion del IDE y EL nombre del valor (Lsp.Discovery):
  // era el mismo lector reescrito, con el nombre compuesto a mano (P7)
  Result := IdeConfigValue(AVersion, 'PlatformSDKs', ValorPorDefectoDePlataforma(APlat)).Trim;
end;

{ El perfil que el IDE tiene para la plataforma (Default_<Plataforma> de
  RemoteProfiles): el que su Project Manager ensena y con el que despliega,
  UNO para todos sus proyectos - el IDE no guarda un perfil por proyecto
  (medido en el IDE con David el 24-oct-2026: cambiarlo no toca ni el .dproj
  ni el .dproj.local). El gemelo de SdkPorDefectoDelIde. }
function PerfilPorDefectoDelIde(const AVersion, APlat: string): string;
begin
  Result := IdeConfigValue(AVersion, 'RemoteProfiles', ValorPorDefectoDePlataforma(APlat)).Trim;
end;

{ Lo que EL PROYECTO declara para un build (PlatformSDK, Profile: las
  propiedades que CodeGear.Profiles.Targets lee del .dproj). '' si no lo
  declara o el .dproj no se lee. Un lector para el SDK y para el perfil. }
function PropiedadDelProyecto(const ADproj, APlat, AConfig, ATag: string): string;
var
  Xml: string;
begin
  Result := '';
  try
    Xml := LeeTexto(ADproj, [ltJaula]);
  except
    Exit;
  end;
  // lo que lee ESE build (plataforma Y config), con el lector del build, el
  // juez de la puerta: el primer <PlatformSDK> del fichero le daba a un build
  // OSX64 el SDK de Linux64, y el lector por plataforma no veia el grupo de
  // una config (revisor D, 21-oct-2026)
  Result := EffectiveProperty(Xml, ATag, APlat, AConfig);
end;

{ El SDK que declara EL PROYECTO (propiedad PlatformSDK, que es la que lee
  CodeGear.Profiles.Targets). El modelo del IDE es que cada proyecto diga con
  cual se compila; si lo dice, no se le pisa. }
function ProyectoDeclaraSdk(const ADproj, APlat, AConfig: string; out ASdk: string): Boolean;
begin
  ASdk := PropiedadDelProyecto(ADproj, APlat, AConfig, 'PlatformSDK');
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
  libreria): se mira antes, y si apareciese en ese instante la puerta de
  escribir lo copia antes de pisarlo. Devuelve cuantos completo; ANota explica
  lo hecho, si de alguna no hay NINGUNA version que a esa maquina le falta la
  libreria misma (BUILD-035), y si la puerta nego escribirla, por que
  (BUILD-047). }
function CompletaEnlacesDev(const AVersion, ASdkFile, AOutput: string;
  out ANota: string): Integer;
var
  Xml, Rutas, Nombre, Dir, Dev, Mejor, Hechos, Faltan, Negadas, Motivo: string;
  M: TMatch;
  Vistos: TStringList;
  Hecho: Boolean;
begin
  Result := 0;
  ANota := '';
  try
    Xml := LeeTexto(RutaDeSdk(AVersion, ASdkFile), [ltIde]);
  except
    Exit;
  end;
  Rutas := TagValue(Xml, 'Profile_LibraryPath');
  if Rutas = '' then
    Exit;
  Rutas := Rutas.Replace('$(BDSPLATFORMSDKSDIR)',
    IdeSdksDir(AVersion), [rfIgnoreCase]);
  Hechos := '';
  Faltan := '';
  Negadas := '';
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
      Motivo := '';
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
        // por las puertas, con el IDE como lugar: Dir es una carpeta de
        // bibliotecas del sysroot de un SDK registrado (se copiaba sin puerta)
        try
          EscribeBytes(TPath.Combine(Dir, Dev), LeeBytes(Mejor, [ltIde]), ltIde);
        except
          // la puerta (o la copia) dijo que no: la version ESTA, asi que no
          // es "le falta a la maquina" (BUILD-035 mandaba instalarla alli)
          on E: Exception do
          begin
            Motivo := E.Message;
            Continue;
          end;
        end;
        Inc(Result);
        Hecho := True;
        if Hechos <> '' then
          Hechos := Hechos + '; ';
        Hechos := Hechos + Format('%s <- %s (%s)', [Dev, TPath.GetFileName(Mejor), Dir]);
        Break;
      end;
      if not Hecho and (Motivo <> '') then
      begin
        if Negadas <> '' then
          Negadas := Negadas + '; ';
        Negadas := Negadas + Dev + ': ' + Motivo;
      end
      else if not Hecho then
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
    ANota := MsgFmt(SN_BUILD_DEVLINK_DONE_FMT, [Hechos]);
  if Faltan <> '' then
  begin
    if ANota <> '' then
      ANota := ANota + ' ';
    ANota := ANota + MsgFmt(SN_BUILD_DEVLINK_MISSING_FMT, [Faltan]);
  end;
  if Negadas <> '' then
  begin
    if ANota <> '' then
      ANota := ANota + ' ';
    ANota := ANota + MsgFmt(SN_BUILD_DEVLINK_DENIED_FMT, [Negadas]);
  end;
end;

{ Un sysroot con DOS distros dentro - el arbol de Debian y el de Red Hat a la
  vez -, que es lo que dejaba el get-sdk de antes de 2026-09-20 al volcar todos
  los targets en una carpeta unica. Devuelve la carpeta, o '' si esta limpio. }
function SysrootMezcladoDeSdk(const AVersion, ASdkFile: string): string;
var
  Xml, Raiz: string;
begin
  Result := '';
  try
    Xml := LeeTexto(RutaDeSdk(AVersion, ASdkFile), [ltIde]);
  except
    Exit;
  end;
  Raiz := SysrootDeSdk(AVersion, Xml);
  if Raiz = '' then
    Exit;
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

const
  { Las propiedades GLOBALES que este build pasa a msbuild por /p: (la orden
    de msbuild, mas abajo): ganan a lo que el .dproj ponga, aun definido
    despues (medido el 21-oct-2026), y la puerta no sabe su valor al evaluar
    las Condition, asi que una Condition que las compare no se sabe y se
    juzga. Config y Platform van aparte: son lo pedido. Cada /p: nuevo de la
    orden entra aqui; test_paisaje lo vigila. Las salidas que el build suple
    van aparte, por su lista (GlobalesDelBuild). }
  GLOBALES_DE_LA_ORDEN: TArray<string> = ['Profile', 'DeviceId', 'PlatformSDK',
    'PreBuildEvent', 'PostBuildEvent', 'PreLinkEvent', 'PostLinkEvent'];

{ Las globales del build: las de la orden y las salidas que el build suple
  (SALIDAS_QUE_SUPLE_EL_BUILD, que van por /p: como las otras). UNA lista: las
  salidas estaban copiadas a mano, y una suplida nueva no habria entrado aqui
  (revisor Opus de la 1.22.0, H6). }
function GlobalesDelBuild: TArray<string>;
begin
  Result := GLOBALES_DE_LA_ORDEN;
  for var S in SALIDAS_QUE_SUPLE_EL_BUILD do
    Result := Result + [S];
end;

{ Lo que este build LEE por lo que el proyecto escribe - el icono, el
  manifiesto, un search path, un .rc, un DeployFile, un keystore... - tiene
  que estar donde esta sesion puede leer: cada valor de cada propiedad - de
  los grupos de ESTE build, no de los que el IDE escribe para otra plataforma
  u otra configuracion (1.22.0) - y cada Include de cada item del .dproj y
  de lo que importa (ValoresQueLeeElBuild), con las macros expandidas como
  las expande NUESTRO msbuild: las propiedades del documento como las tiene
  msbuild DONDE las lee (el recorrido de Lsp.Dproj.VeredictosDeElementos: lo
  ultimo puesto antes en un grupo de este build, vacio hasta entonces, un
  Include con lo del final), y lo que el documento no sabe, aqui (Expande:
  la tabla del IDE, rsvars.bat, las de msbuild sobre este proyecto, el
  entorno del servidor sin las DELPHI_MCP_*, y lo que nadie define, vacio,
  como msbuild; negarlo tumbaba 175 proyectos del censo de 3.651 del
  22-oct-2026: ModuleName, $(Auto), TargetName, que definen los targets del
  IDE y no son rutas). Lo que no se sabe se niega, BUILD-056 (una propiedad
  puesta bajo una Condition que no se sabe evaluar, una global del build),
  y lo que define OTRO documento de la cadena queda sin expandir y se niega
  como no verificable (BUILD-051: msbuild lo evalua donde lo importa). Tres
  agujeros medidos el 22-oct-2026 expandian con otro valor que el que dcc
  lee: el ultimo del documento (un $(A)\..\fuera con A=.. y luego A=x), el
  de la tabla con la propiedad redefinida por el proyecto, el definido
  despues del uso. Resuelto contra la carpeta del proyecto, y juzgado por la
  puerta de leer con los lugares del motor (la jaula, el IDE y su
  biblioteca: lo mismo que dcc y brcc32 van a abrir). Se juzga exista o no:
  negar solo lo que existe seria un oraculo de fuera. Lo que no es una ruta
  (un define, una clave de version) no lo abre nadie y se salta. Y el .rc de
  un RcCompile, por EL lector del .rc. Medido en la 1.20.1: un RcCompile y
  un Manifest_File de fuera acababan en el .res y en el exe; censo del
  20-oct-2026 sobre los 122 proyectos de las raices de produccion: 0 valores
  de fuera. Parte 3 del gate del build (1.21.2). }
function LecturasDelBuildDenegadas(const ADprojPath, APlat, ACfg: string;
  const AInfo: TRadStudioInfo): string;
var
  Vars: TStringList;
  Xmls, Ficheros: TArray<string>;
  Docs: TArray<TArray<TElementoXml>>; // los elementos de cada documento de Xmls
  Dir, Base: string;

  // lo que el documento dejo escrito como $(X) en un valor (lo que el no
  // sabe: ValoresQueLeeElBuild), expandido como lo expande nuestro msbuild:
  // la tabla del build (el IDE, rsvars.bat, las de msbuild sobre este
  // proyecto), el entorno del servidor sin las DELPHI_MCP_*, y lo que nadie
  // define, vacio. Lo que define OTRO documento de la cadena (ADeOtros) no
  // se sabe que vale en este punto (msbuild lo evalua donde lo importa) y se
  // deja escrito: la puerta lo niega como no verificable. Lo que entra
  // expandido no se vuelve a expandir, como en msbuild
  function Expande(const AValor: string; const ADeOtros: TArray<string>): string;
  var
    P, Q: Integer;
    Nombre, V: string;
  begin
    Result := AValor;
    P := Pos('$(', Result);
    while P > 0 do
    begin
      Q := Pos(')', Result, P + 2);
      if Q = 0 then
        Exit; // sin cierre: se queda, y lo que queda con $( no se aprueba
      Nombre := Copy(Result, P + 2, Q - P - 2).Trim;
      // nunca se sustituye un contenido que no sea un nombre de propiedad
      // simple: se deja escrito (la puerta ya lo nego, BUILD-051) y se sigue
      // tras el, sin darle un valor que no es el que lee msbuild
      if not EsNombreDeMacro(Nombre) then
      begin
        P := Pos('$(', Result, Q + 1);
        Continue;
      end;
      if MatchText(Nombre, ADeOtros) then
      begin
        P := Pos('$(', Result, Q + 1);
        Continue;
      end;
      if Vars.IndexOfName(Nombre) >= 0 then
        V := Vars.Values[Nombre]
      else if (Nombre <> '') and not StartsText('DELPHI_MCP_', Nombre) then
        V := GetEnvironmentVariable(Nombre)
      else
        V := '';
      Result := Copy(Result, 1, P - 1) + V + Copy(Result, Q + 1, MaxInt);
      P := Pos('$(', Result, P + Length(V));
    end;
  end;

  // Gramatica propia (no hay juez de "URL o ruta"): el esquema de una URL
  // (http, https, ssh, git, file...) son 2+ letras al principio seguidas de
  // '://'; una UNIDAD de Windows es UNA sola letra (C:), que dcc abre como
  // ruta. Por eso no vale Contains('://') a secas: saltaba C://x -que dcc abre
  // como C:\x (medido el 22-oct-2026, leia fuera de la jaula)- por URL.
  function EsEsquemaDeUrl(const ACand: string): Boolean;
  var
    P, I: Integer;
  begin
    P := ACand.IndexOf('://');
    Result := P >= 2; // 2+ caracteres de esquema (una unidad es 1)
    if not Result then
      Exit;
    for I := 0 to P - 1 do
      if not CharInSet(ACand.Chars[I], ['A'..'Z', 'a'..'z']) then
        Exit(False); // el esquema son letras; C:\ o \\host\x no son URL
  end;

  // un trozo YA expandido: una ruta, o lo que no lo es
  function JuzgaTrozo(const ATrozo: string; const AValor: TValorDelProyecto;
    const AFichero: string): string;
  const
    // Las propiedades que el build lee como CLAVE=VALOR, no como rutas: la
    // version (VerInfo_Keys) y los alias de unidad (DCC_UnitAlias). Solo en
    // ellas un '=' o una ':' con barras detras no es una ruta y se salta; en una
    // propiedad de ruta se juzga siempre. Gramatica propia (no hay juez),
    // declarada aqui con nombre (H1, H2; W14 de test_build_lista_blanca_1212).
    PROPIEDADES_CLAVE_VALOR: array[0..1] of string = ('VerInfo_Keys', 'DCC_UnitAlias');
  var
    Cand: string;
  begin
    Result := '';
    Cand := ATrozo.Trim;
    if Cand = '' then
      Exit;
    if Cand.Contains('$(') or Cand.Contains('@(') or Cand.Contains('%(') then
      Exit(MsgFmt(SR_BUILD_LECTURA_NO_VERIFICABLE_FMT,
        [AValor.Elemento, TPath.GetFileName(AFichero), ATrozo]));
    // Un prefijo de ruta extendida o de dispositivo (\\?\C:\x, \\?\UNC\srv\x,
    // \\.\, \??\C:\x): dcc abre la carpeta por el; Win32 GetFullPath no lo
    // entiende, asi que se quita y se juzga la ruta real (Lsp.Rutas; H2, H2b)
    if EsPrefijoDeDispositivo(Cand) then
      Cand := SinPrefijoDeDispositivo(Cand);
    // El '=' de una clave=valor solo se salta en una propiedad que NO es de
    // ruta (PROPIEDADES_CLAVE_VALOR: la version, un alias; "Comments=D:\x"). En
    // una propiedad de RUTA se juzga la ruta entera: GetFullPath colapsa los ..
    // como Win32 y dcc (medido el 22-oct-2026), asi que a=b\..\..\fuera se
    // resuelve y se ve que sale (H1).
    var EsClaveValor := MatchText(AValor.Elemento, PROPIEDADES_CLAVE_VALOR);
    if EsClaveValor then
    begin
      var Sep := Cand.IndexOfAny(['\', '/']);
      var Igual := Cand.IndexOf('=');
      if (Igual >= 0) and ((Sep < 0) or (Igual < Sep)) then
        Exit;
    end;
    // una URL (esquema://...) no es un fichero local que dcc abra: no se juzga
    // como ruta (W14 de test_build_lista_blanca_1212: un LbUrl pasa); pero una
    // unidad con doble barra (C://x) SI es una ruta que dcc abre: EsEsquemaDeUrl
    // la distingue (un esquema son 2+ letras; una unidad, una sola).
    // Un ':' que no es el de la unidad ni de una URL es un flujo alternativo
    // (f.txt:stream): sin barras detras se recorta y se juzga el FICHERO; con
    // barras detras es una ruta disfrazada (a:b\..\..) y se juzga entera, que
    // GetFullPath resuelve igual que Win32/dcc y se ve que sale (H2, 22-oct-2026).
    if EsEsquemaDeUrl(Cand) then
      Exit;
    var DosPuntos := Cand.LastIndexOf(':');
    if (DosPuntos > 1) and (Cand.Substring(DosPuntos + 1).IndexOfAny(['\', '/']) < 0) then
      Cand := Cand.Substring(0, DosPuntos);
    // como la lee dcc, que corre en la carpeta del .dproj (EL resolutor): se
    // juzgaba en la unidad del PROCESO del servidor (A9b de la 1.23, medido).
    // Una "X:y" de otra unidad la lee desde una carpeta que no nombra nadie
    var Resuelta := RutaDesde(Dir, Cand);
    if Resuelta = '' then
    begin
      if EsRutaAMedias(Cand) then
        Exit(MsgFmt(SR_BUILD_LECTURA_NO_VERIFICABLE_FMT,
          [AValor.Elemento, TPath.GetFileName(AFichero), ATrozo]));
      Exit; // no es una ruta (un define, una clave de version): nadie la abre
    end;
    Cand := Resuelta;
    // el trozo como lo lee el build y, si es otro, como esta ESCRITO: la
    // entrada que toma remove-searchpath (un %2E%2E citado como .. no se
    // encontraba en el .dproj)
    if LugarDeLecturaDenegado(Cand, LUGARES_DEL_MOTOR) <> '' then
      Exit(MsgFmt(SR_BUILD_LECTURA_FUERA_FMT,
        [AValor.Elemento, TPath.GetFileName(AFichero), ATrozo,
         IfThen(SameText(ATrozo.Trim, AValor.Escrito.Trim), '',
           MsgFmt(SF_BUILD_LECTURA_ESCRITA_FMT, [AValor.Escrito]))]));
    // una carpeta de unidades o de includes de la JAULA (la biblioteca es la
    // instalacion): dcc lee sus fuentes, y sus directivas se juzgan como las
    // de la carpeta del proyecto. Una unidad de un search path de la jaula
    // traia un $I de fuera (V14 de la 1.23, medido): aqui el trozo ya va
    // expandido como lo lee msbuild, y un $(X) que lleva a ella tambien
    if MatchText(AValor.Elemento, ['DCC_UnitSearchPath', 'DCC_IncludePath']) and
       (LugarDeLecturaDenegado(Cand, [ltJaula]) = '') and TDirectory.Exists(Cand) then
      for var F in WalkFiles(Cand, MascarasDe(SOURCE_EXTS), False, False) do
      begin
        Result := DirectivasDenegadas(F, Dir);
        if Result <> '' then
          Exit;
      end;
    // el .rc que compila brcc32: cada fichero que nombra, por EL lector. Solo
    // el guion de un RcCompile: un RcItem es un FICHERO de recurso (el .gif o
    // .png que el IDE mete como RCDATA por el .rc que genera el mismo) y ya
    // esta juzgado por su ruta, arriba; leerlo como guion lo parseaba como
    // texto y citaba sus bytes en la negativa (un proyecto real, 21-oct-2026)
    if SameText(AValor.Elemento, 'RcCompile') and TFile.Exists(Cand) then
    begin
      var Rc := RcLecturasDenegadas(Cand);
      if Rc <> '' then
        Exit(MsgFmt(SR_BUILD_RC_FMT,
          [ATrozo, TPath.GetFileName(AFichero), Rc]));
    end;
  end;

  function Juzga(const AValor: TValorDelProyecto; const AFichero: string;
    const ADeOtros: TArray<string>): string;
  begin
    Result := '';
    // dentro de un valor que el build LEE, un $(...) solo vale si lo de dentro
    // es un nombre de propiedad simple (EsNombreDeMacro): una funcion de
    // propiedad, un item, un metadato o un nombre con puntos hacen el valor NO
    // verificable (msbuild lo evalua donde lo importa y la puerta no sabe a que
    // ruta lleva), BUILD-051 sobre lo ESCRITO, antes de expandir, exista o no
    // la ruta (David, 22-oct-2026; censo: 0 de 3.651 .dproj con algo asi)
    var Pm := Pos('$(', AValor.Escrito);
    while Pm > 0 do
    begin
      var Qm := Pos(')', AValor.Escrito, Pm + 2);
      if Qm = 0 then
        Break; // sin cerrar: no es un macro; lo juzga el trozo ya expandido
      // SIN recortar: msbuild no recorta el nombre, $( A ) es la propiedad " A "
      // (no "A"), que nadie define y vale vacio; la puerta lo niega como no
      // verificable en vez de expandirlo con el valor de A (H12, 22-oct-2026)
      if not EsNombreDeMacro(Copy(AValor.Escrito, Pm + 2, Qm - Pm - 2)) then
        Exit(MsgFmt(SR_BUILD_LECTURA_NO_VERIFICABLE_FMT,
          [AValor.Elemento, TPath.GetFileName(AFichero), AValor.Escrito]));
      Pm := Pos('$(', AValor.Escrito, Qm + 1);
    end;
    // un macro cuyo valor no se sabe donde el build lo lee (puesto bajo una
    // Condition que no se sabe evaluar, o una global del build): el valor no
    // se sabe leer, BUILD-056, exista o no la ruta a la que llevaria
    if AValor.Dudoso <> '' then
      Exit(MsgFmt(SR_BUILD_LECTURA_MACRO_FMT,
        [AValor.Elemento, TPath.GetFileName(AFichero), AValor.Escrito, AValor.Dudoso]));
    // el valor expandido se juzga trozo a trozo (es una lista, y lo que un
    // macro expande puede ser otra): el $(DCC_UsePackage) con que el IDE
    // cierra la lista de paquetes de todo proyecto expandia a la lista
    // entera y se juzgaba como UNA ruta, negada en cuanto carpeta + lista
    // pasaban de MAX_PATH (medido el 21-oct-2026: 217 caracteres pasaban,
    // 313 no; sin el macro, 1599 pasaban)
    // desescapado ANTES de partir, como msbuild: un %2E%2E es .. y un %3B es un
    // ';' que separa la lista (medido el 22-oct-2026, los dos leian fuera) (H3)
    for var Trozo in TrozosDeLista(DesescapaDeMsbuild(Expande(AValor.Expandido, ADeOtros))) do
    begin
      Result := JuzgaTrozo(Trozo, AValor, AFichero);
      if Result <> '' then
        Exit;
    end;
  end;

begin
  Result := '';
  Xmls := ProjectXmlChain(ADprojPath, Ficheros);
  if Xmls = nil then
    Exit;
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  Vars := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    // rsvars.bat manda sobre la tabla: es el entorno que recibe msbuild
    for var V in VariablesDeRsVars(AInfo) do
    begin
      var I := Pos('=', V);
      if I > 1 then
        Vars.Values[Copy(V, 1, I - 1)] := Copy(V, I + 1, MaxInt);
    end;
    Vars.Values['Platform'] := APlat;
    Vars.Values['Config'] := ACfg;
    // las de msbuild sobre este proyecto (las de ResolveImportPath y
    // ExpandOutputMacros, en una tabla)
    Vars.Values['MSBuildProjectDirectory'] := Dir;
    Vars.Values['MSBuildThisFileDirectory'] := IncludeTrailingPathDelimiter(Dir);
    Vars.Values['MSBuildProjectName'] := Base;
    Vars.Values['SanitizedProjectName'] := Base;
    Vars.Values['MSBuildProjectFile'] := TPath.GetFileName(ADprojPath);
    Vars.Values['MSBuildProjectFullPath'] := TPath.GetFullPath(ADprojPath);
    // ProjectDir NO va en la tabla: msbuild lo lee VACIO en el cuerpo del .dproj
    // (no es una propiedad reservada; medido el 22-oct-2026, $(ProjectDir)\fuera
    // compilaba leyendo fuera de la jaula), asi que la puerta lo expande vacio
    // como msbuild y no con Dir (H4). MSBuildProjectDirectory (reservada) y
    // SanitizedProjectName (= Base, medido) si valen y se quedan arriba.
    // los nombres que msbuild toma de fuera del documento (esta tabla): la
    // evaluacion de las Condition no los da por vacios
    var Externas: TArray<string> := [];
    for var I := 0 to Vars.Count - 1 do
      Externas := Externas + [Vars.Names[I]];
    // y lo que definen los OTROS documentos de la cadena (un .optset
    // importado pone una propiedad que este documento compara o usa):
    // msbuild lo evalua en su sitio y aqui cada documento va solo, asi que
    // esos nombres son de fuera - no se dan por vacios, la Condition no se
    // sabe y se juzga (revisor E, 21-oct-2026), y un valor que los lleve no
    // se verifica (Expande los deja escritos)
    var Definidos: TArray<TArray<string>> := [];
    SetLength(Docs, Length(Xmls));
    for var I := 0 to High(Xmls) do
    begin
      var Mal: string;
      Docs[I] := ElementosDe(Xmls[I], Mal);
      Definidos := Definidos + [PropiedadesDefinidas(Docs[I])];
    end;
    for var I := 0 to High(Xmls) do
    begin
      var DeOtros: TArray<string> := [];
      for var J := 0 to High(Xmls) do
        if J <> I then
          DeOtros := DeOtros + Definidos[J];
      for var V in ValoresQueLeeElBuild(Xmls[I], APlat, ACfg, Externas + DeOtros, GlobalesDelBuild) do
      begin
        Result := Juzga(V, Ficheros[I], DeOtros);
        if Result <> '' then
          Exit;
      end;
    end;
  finally
    Vars.Free;
  end;
end;

{ El escaneo compile-only del .dproj en UN solo sitio (hazard + propiedad de IDE
  redefinida + directivas/imports/enlaces duros + lo que el build lee), para
  correrlo BAJO el cerrojo y sobre los MISMOS bytes que compilara msbuild.
  APlat/ACfg/AInfo: el build que se va a lanzar (las macros de lo que lee).
  Devuelve si hay que vaciar los eventos de build; lanza con su motivo si el
  proyecto no pasa. }
function EscaneoCompileOnly(const ADprojPath, APlat, ACfg: string;
  const AInfo: TRadStudioInfo; AAllowScripts: Boolean): Boolean;
begin
  // Compile-only guarantee: a build must not EXECUTE code. Scan the project for
  // shell-running / file-planting MSBuild tasks (a planted <Target><Exec>, a
  // build-event, a foreign <Import>) and refuse unless build scripts were
  // explicitly enabled. This is the point-of-execution gate, so it holds however
  // the .dproj got there - upload, edit, or a pre-existing one (field round 7,
  // CRITICAL). AllowBuildScripts is the trusted-project
  // opt-in; an inert custom <Target> now builds without it (field round 9 FP).
  // Los EVENTOS pre/post build (la firma, una copia) ya no cierran la puerta:
  // se compila con ellos vaciados (/p:PreBuildEvent= ...) y se dice. Sin eso
  // Galatea no compilaba en el workspace de un agente, y "una cosa es compilar
  // la version final, otra poder trabajar y ejecutar mientras tanto" (David,
  // 24-sep-2026). Lo que ejecuta de verdad -un <Exec>/<Target> propio, un
  // <Import> ajeno- sigue rechazado: el MISMO escaner, primero sin contar los
  // eventos.
  Result := False;
  if not AAllowScripts then
  begin
    var ProjXml := '';
    // sin leerlo NO se compila: el escaner miraba un texto vacio y daba el
    // .dproj por limpio (fallaba ABIERTO; sexta revision)
    try
      ProjXml := LeeTexto(ADprojPath, [ltJaula]);
    except
      on E: Exception do
        raise Exception.Create(MsgFmt(SR_BUILD_DPROJ_ILEGIBLE_FMT,
          [TPath.GetFileName(ADprojPath), E.Message]));
    end;
    var Hazard := DprojBuildHazard(ProjXml, TPath.GetFullPath(ADprojPath), True);
    if Hazard <> '' then
    begin
      TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_REFUSED_FMT,
        [TPath.GetFullPath(ADprojPath), Hazard]));
      raise Exception.Create(MsgFmt(SR_BUILD_HAZARD_FMT, [Hazard]));
    end;
    // Parte 2 del mismo gate: una propiedad de entorno que el IDE reserva,
    // redefinida por el proyecto o por algo que importa, desvia uno de los
    // <Import> propios del IDE (que confiamos sin leer, IsStockImport) a un
    // fichero elegido por el proyecto - codigo cargado en el build sin un
    // <Import> visible. Mismo opt-in (AllowBuildScripts) que el hazard: un
    // proyecto de confianza ya puede ejecutar de todos modos.
    var ResProp := RedefinedIdeImportProperty(TPath.GetFullPath(ADprojPath));
    if ResProp <> '' then
    begin
      TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_REFUSED_REDEFINES_FMT,
        [TPath.GetFullPath(ADprojPath), ResProp]));
      raise Exception.Create(MsgFmt(SR_BUILD_RESERVED_PROP_FMT, [ResProp]));
    end;
    Result := DprojBuildHazard(ProjXml, TPath.GetFullPath(ADprojPath), False) <> '';
  end;
  // Before a single line is compiled: what does this project pull in from
  // outside, and is it allowed to? Same shape as the hazard check above.
  var IncBad := IncludeDirectivesDenied(ADprojPath);
  if IncBad <> '' then
  begin
    TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_REFUSED_FMT,
      [TPath.GetFullPath(ADprojPath), IncBad]));
    raise Exception.Create(IncBad);
  end;
  // Parte 3 del mismo gate (1.21.2): lo que el build LEE por lo que el
  // proyecto escribe (el icono, el manifiesto, los search paths, los .rc, los
  // DeployFile...), siempre: la jaula de leer no es un opt-in del operador.
  var LecturaMala := LecturasDelBuildDenegadas(ADprojPath, APlat, ACfg, AInfo);
  if LecturaMala <> '' then
  begin
    TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_REFUSED_FMT,
      [TPath.GetFullPath(ADprojPath), LecturaMala]));
    raise Exception.Create(LecturaMala);
  end;
end;

{ Un .res SIN recursos: solo la entrada nula con que empieza todo fichero de
  recursos de Windows (DataSize 0 y nada detras de su cabecera, HeaderSize =
  el fichero), el formato que escriben rc y brcc32. Lo deja asi un build de
  Linux64 (32 bytes, medido el 24-oct-2026); uno de Windows siempre le deja
  algo (el RCDATA de las plataformas: 96 bytes en una consola sin icono ni
  version). False si no esta o no se lee. }
function ResSinRecursos(const APath: string): Boolean;
var
  B: TArray<Byte>;
begin
  Result := False;
  if (APath = '') or not TFile.Exists(APath) then
    Exit;
  try
    // por LA puerta de leer: es del proyecto, en la jaula que aprobo el build
    B := LeeBytes(APath, [ltJaula]);
  except
    Exit; // uno que no se lee no dice nada
  end;
  // DataSize y HeaderSize, los dos primeros DWORD de la primera entrada
  Result := (Length(B) >= 8) and (PCardinal(@B[0])^ = 0) and
    (PCardinal(@B[4])^ = Cardinal(Length(B)));
end;

function RunMsBuild(ADprojPath: string; const APlatform, AConfig, ATarget: string;
  const AProfile, ADeviceId: string; ATimeoutMs: Integer;
  const ASdk, AVerbosity: string): TJSONObject;
var
  Info: TRadStudioInfo;
  Output, Line, Plat, Cfg, Target: string;
  ExitCode: DWORD;
  Errors, Warnings: TJSONArray;
  EsPaquete: Boolean;
  EventosSaltados: Boolean; // eventos pre/post build vaciados en este build
  YaDicho: TStringList; // lo que ya va en errors[]/warnings[]: la cola no lo repite
  Cola: string;
  Lines: TArray<string>;
  LineasDeCola: Integer;
begin
  // Un .dpr/.dpk se compila por su .dproj, como lo resuelven delphi_config y
  // delphi_test (DprojDe): aqui contestaba BUILD-016 "no es un proyecto"
  // (Hermes, validacion de la 1.16.0). Antes de la puerta: juzga el fichero real.
  ADprojPath := DprojDe(ADprojPath);
  var Denied := WriteTargetDenied(ADprojPath); // compilar escribe junto al proyecto
  if Denied <> '' then
    raise Exception.Create(Denied);
  if not FileExists(ADprojPath) then
    raise Exception.Create(NoEsFichero(ADprojPath, MsgFmt(SR_BUILD_DPROJ_NO_EXISTE_FMT, [ADprojPath])));
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
    raise Exception.Create(MsgFmt(SR_BUILD_NOT_A_PROJECT_FMT,
      [TPath.GetFileName(ADprojPath)]));
  // Una configuracion que el proyecto no tiene, o una verbosidad inventada,
  // se aceptaban en silencio: "Relase" compilaba en Win64\Relase\ con los
  // ajustes de Base (segunda revision, 27-sep-2026). La configuracion, por
  // EL juez (Lsp.Dproj.ConfigDelBuild, el de delphi_test y delphi_config):
  // sin config, la SELECCIONADA en el proyecto, la que compilan el IDE y
  // msbuild mientras nadie pide otra (era Debug a fuego, como la plataforma
  // hasta la 1.15; delphi_config set-active la cambia), y con el nombre que
  // declara el proyecto: lo que teclea el agente solo elige (2an)
  Denied := ConfigDelBuild(ReadDproj(ADprojPath), AConfig, Cfg);
  if Denied <> '' then
    raise Exception.Create(Denied);
  if (AVerbosity <> '') and not MatchText(AVerbosity, ['quiet', 'normal', 'verbose']) then
    raise Exception.Create(MsgFmt(SR_BUILD_VERBOSITY_FMT, [AVerbosity]));
  // El escaneo compile-only (hazard, propiedad de IDE redefinida, directivas e
  // imports) se hace mas abajo, BAJO el cerrojo de escritura y pegado a msbuild
  // (EscaneoCompileOnly): se escanean y se compilan los MISMOS bytes del .dproj.
  Info := DiscoverRadStudio;
  if not Info.Found then
    raise Exception.Create(MsgText(SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED));
  if not FileExists(Info.RsVarsBat) then
    raise Exception.Create(MsgFmt(SE_BUILD_RSVARS_BAT_FOUND_FMT, [Info.RsVarsBat]));
  // msbuild SIN cmd.exe (2an de la 1.18.2; David 13-oct: "un agente pide una
  // operacion, nunca ejecuta nada"). Era cmd.exe /c "rsvars.bat && msbuild
  // ...": heredaba el entorno ENTERO del servidor (su configuracion incluida)
  // y cmd buscaba 'msbuild' PRIMERO en su cwd, la carpeta del proyecto: un
  // msbuild.bat plantado alli lo ejecutaba el servidor (medido el 13-oct
  // contra produccion). Ahora el entorno de rsvars.bat lo pone EL lector
  // (VariablesDeRsVars) sin las DELPHI_MCP_* (EntornoSinConfiguracion, el de
  // delphi_test y git), y msbuild.exe va por su RUTA, buscada solo en el PATH
  // de ese entorno (ProgramaEnPath). Antes del cerrojo: si falta, no se lanza
  // nada.
  var VarsRs := VariablesDeRsVars(Info);
  var PathRs := '';
  for var V in VarsRs do
    if StartsText('PATH=', V) then
      PathRs := V.Substring(Length('PATH='));
  // ...y en una carpeta donde el agente no escribe (ProgramaDelOperador, B1)
  var MsBuildExe := ProgramaDelOperador('msbuild.exe', PathRs);
  if MsBuildExe = '' then
    raise Exception.Create(MsgFmt(SR_BUILD_MSBUILD_NO_ENCONTRADO_FMT, [Info.RsVarsBat]));
  var EntornoMsBuild := EntornoSinConfiguracion(VarsRs);

  // La plataforma con SU nombre (un nombrador: CanonicalPlatform). La puerta
  // la valida sin mirar mayusculas y aqui llegaba tal cual: platform=win64
  // compilaba a una carpeta "win64" y msbuild caia con MSB4018 (quinta
  // revision).
  Plat := CanonicalPlatform(APlatform);
  if (Plat = '') and (APlatform.Trim <> '') then
    raise Exception.Create(NegativaDePlataforma(APlatform));
  // Sin plataforma, la del proyecto: la que compilan el IDE y msbuild
  // mientras nadie la cambia (hasta la 1.15 era Win32 a fuego, aunque el
  // proyecto tuviera Win64 por defecto, como los que crea delphi_create).
  var Proyecto := ReadDproj(ADprojPath);
  // un .dproj a medias (no cierra su <Project>) no se juzga ni se compila:
  // se decia "plataforma no habilitada", que es lo que un fichero cortado
  // por el final parece (Hermes, 21-oct-2026)
  if Proyecto.Incompleto then
    raise Exception.Create(MsgFmt(SR_BUILD_DPROJ_INCOMPLETO_FMT, [ADprojPath]));
  if Plat = '' then
    Plat := Proyecto.PlataformaPorDefecto;
  // Lo que el proyecto no puede ser en esa plataforma (VCL fuera de Windows)
  // se dice ANTES de compilar, con la regla de add-platform (CanTarget): el
  // build caia con F2613 Vcl.Forms y la pista mandaba a add-searchpath.
  var NoPuede := '';
  if not Proyecto.CanTarget(Plat, NoPuede) then
    raise Exception.Create(MsgEnvuelve(SR_RECHAZADO_FMT, NoPuede));
  // Y solo una plataforma que el proyecto declara activa: lo que se compila
  // aqui lo compila igual el operador en el IDE sin reconfigurar nada.
  NoPuede := PlataformaNoDeclarada(Proyecto, Plat);
  if NoPuede <> '' then
    raise Exception.Create(NoPuede);
  Target := ATarget.Trim;
  if Target = '' then
    Target := 'Build';
  // el target con SU nombre, uno del cuarteto que admite la puerta (lo que
  // teclea el agente solo elige; a /t: iba tal cual, con sus mayusculas)
  var IdxTarget := IndexText(Target, TARGETS_DE_BUILD);
  if IdxTarget < 0 then
    raise Exception.Create(MsgFmt(SR_BUILD_TARGET_FMT, [Target]));
  Target := TARGETS_DE_BUILD[IdxTarget];
  // Donde deja la salida, con la plataforma y la config de ESTE build, y las
  // carpetas que el build suple porque el proyecto no las declara (Suplidas:
  // van a la linea de msbuild y a la respuesta)
  var Suplidas: TArray<TBuildOutputDir>;
  var SalidaMala := SalidaDenegada(ADprojPath, Plat, Cfg, Suplidas);
  if SalidaMala <> '' then
  begin
    TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_REFUSED_FMT,
      [TPath.GetFullPath(ADprojPath), SalidaMala]));
    raise Exception.Create(SalidaMala);
  end;
  // Deploy ALWAYS builds first: a bare /t:Deploy repackages and ships the
  // PREVIOUS binary with today's date and zero warnings - the measured
  // half-a-session trap (vault: delphi-android-deploy-sin-build). The IDE
  // never deploys stale either.
  // Lo que corre msbuild va aparte de lo que se pidio: la respuesta dice
  // "target": "Deploy", lo que el agente puede volver a pedir (decia
  // "Build;Deploy", que BUILD-004 niega como entrada: Hermes lo copio de la
  // respuesta y se lo negamos, 17-oct-2026)
  var TargetsMsBuild := Target;
  if SameText(Target, 'Deploy') then
    TargetsMsBuild := 'Build;Deploy';
  // La puerta de RemoteHosts, tambien aqui: un deploy por perfil MARCA el host
  // del perfil (PAClient), igual que test-connection / remote-run, asi que pasa
  // por la MISMA puerta (ProfileHostDenied). Hasta la 1.15 el deploy la saltaba
  // (R1, medido 2026-10-06: llegaba a marcar un host fuera de RemoteHosts).
  // Falla cerrado: host no permitido, o perfil que no se puede comprobar, y no
  // compila ni despliega.
  // El perfil juzgado es el MISMO que usa msbuild: el de la llamada y, si no
  // viene, el que el proyecto declara para esa plataforma (set-profile, o el
  // IDE), que es lo que $(Profile) lee del .dproj. Juzgar solo el argumento
  // dejaba la puerta abierta por el proyecto (medido 2026-10-06: deploy sin
  // profile= y con <Profile> en el .dproj, E0003 contra un host fuera de
  // RemoteHosts). msbuild lo recibe EXPLICITO, tambien vacio: /p:Profile= es
  // una propiedad global, y ni el proyecto ni el $(DefaultProfile) de
  // EnvOptions.proj pueden ponerle otro que nadie juzgo. Sin perfil, se niega
  // antes de compilar (BUILD-058, abajo).
  var Perfil := AProfile.Trim;
  // Android no despliega por PAServer: en un Deploy, un profile= se niega, y
  // el <Profile> que el proyecto lleve (set-profile lo escribia hasta la
  // 1.20.2) no se lee - msbuild recibe /p:Profile= vacio. Con el, el primer
  // Deploy fallaba E8712 y los demas decian "Deployed through profile" con el
  // .apk aqui (medido el 18-oct-2026). Como la puerta de hosts, solo en un
  // Deploy: un Build no despliega, el perfil no hace nada en el
  var SinPAServer := SistemaDelPAServer(Plat) = spDesconocido;
  if Target.Contains('Deploy') and SinPAServer and (Perfil <> '') then
    raise Exception.Create(MsgFmt(SR_CONFIG_PROFILE_SIN_PASERVER_FMT, [Plat]));
  // de donde sale el que se usa: la llamada, el proyecto o el IDE (la respuesta lo dice)
  var FuenteDelPerfil := IfThen(Perfil <> '', 'call', '');
  if Target.Contains('Deploy') and not SinPAServer and (Perfil = '') then
  begin
    Perfil := PropiedadDelProyecto(ADprojPath, Plat, Cfg, 'Profile');
    if Perfil <> '' then
      FuenteDelPerfil := 'project';
  end;
  // ...y si el proyecto tampoco lo dice, el que el IDE tiene para la
  // plataforma, como despliega el IDE: UNO para todos sus proyectos
  // (RemoteProfiles\Default_<plataforma>; medido con David el 24-oct-2026, y
  // David: "hazlo como el IDE"). Paraba con "Missing profile name". Pasa por los
  // mismos jueces de abajo y va EXPLICITO a /p:Profile=: lo que EnvOptions.proj le
  // daria a msbuild (el IDE escribe alli el mismo, un <Profile> con condicion,
  // medido) sigue sin llegar sin juez
  if Target.Contains('Deploy') and not SinPAServer and (Perfil = '') then
  begin
    Perfil := PerfilPorDefectoDelIde(Info.Version, Plat);
    if Perfil <> '' then
      FuenteDelPerfil := 'ide-default';
  end;
  // ...y sin NINGUNO, se niega aqui: msbuild recibe /p:Profile= vacio y no
  // despliega nada; compilaba antes (41 s en Linux64) para parar en "Missing
  // profile name", y un Win64 igual con su manifiesto, o en MSB4057 sin el
  // (medido el 24-oct-2026). Con los perfiles que despliegan la plataforma.
  // La regla es la del juez, el target del IDE al que espera todo Deploy
  // (_VerifyProfile, CodeGear.Profiles.Targets): perfil para todo menos
  // Android y menos Windows con BT_BuildType=AppStore, el paquete de la Store,
  // que no va a ninguna maquina (David pregunto si Win32/Win64 lo necesitaban:
  // ese caso se negaba aqui y el IDE lo hace)
  if Target.Contains('Deploy') and not SinPAServer and (Perfil = '') and
     not ((SistemaDePlataforma(Plat) = spWindows) and
          SameText(PropiedadDelProyecto(ADprojPath, Plat, Cfg, 'BT_BuildType').Trim, 'AppStore')) then
    raise Exception.Create(MsgFmt(SR_BUILD_DEPLOY_SIN_PERFIL_FMT, [Plat, Plat,
      ONinguno(string.Join(', ', PerfilesDePlataforma(Info.Version, Plat)))]));
  // la negativa de un perfil que el agente no nombro dice de donde salio
  var DeDonde := '';
  if FuenteDelPerfil = 'ide-default' then
    DeDonde := MsgFmt(SF_BUILD_PERFIL_DEL_IDE_FMT, [Perfil, Plat])
  else if FuenteDelPerfil = 'project' then
    DeDonde := MsgFmt(SF_BUILD_PERFIL_DEL_PROYECTO_FMT, [Perfil, Plat]);
  // El perfil, venga de la llamada o del .dproj, es UNO de los que el IDE
  // declara (PerfilDelIde, el juez de set-profile), con su nombre, el de la
  // lista. El del .dproj llegaba a /p:Profile= sin juez; lo que teclea el
  // agente solo elige (punto 3 del build, 1.19.0)
  if Perfil <> '' then
  begin
    var PerfilIde := PerfilDelIde(Info.Version, Perfil);
    if PerfilIde = '' then
      // con el texto de la casa del deploy (PAS-053, el de ProfileHostDenied):
      // un hecho, un texto
      raise Exception.Create(MsgFmt(SR_PROFILE_NO_EXISTE_FMT, [Perfil]) + DeDonde);
    Perfil := PerfilIde;
  end;
  if Target.Contains('Deploy') and (Perfil <> '') then
  begin
    // ...uno que DESPLIEGA esta plataforma (el juez de set-profile: uno de
    // Windows no despliega un Linux64), antes de marcar su host
    var NoSirve := PerfilQueNoSirve(Info.Version, Perfil, Plat);
    if NoSirve <> '' then
      raise Exception.Create(NoSirve + DeDonde);
    var HostDenegado := ProfileHostDenied(Perfil);
    if HostDenegado <> '' then
      raise Exception.Create(HostDenegado + DeDonde);
    // ...y un proyecto que el operador deja ejecutar en un destino (SU lista,
    // RemoteRunProjects, por LA puerta de remote-run): el deploy lo deja en
    // <usuario>-<perfil>/<Nombre>/, donde remote-run ejecuta lo que haya, y
    // un homonimo de cualquier carpeta pisaba la del permitido (Fable,
    // revision de la 1.22.2; David: "si, tiene razon Fable")
    var NoEjecutable := RemoteRunProjectDenied(ADprojPath);
    if NoEjecutable <> '' then
      raise Exception.Create(NoEjecutable);
  end;
  // The deployment targets address the remote machine through $(Profile)
  // (their PAClient task takes ProfileName="$(Profile)"). Vetted at the gate
  // like every argument that lands on this command line.
  var ProfileArg := '';
  if Target.Contains('Deploy') or (Perfil <> '') then
    ProfileArg := ' /p:Profile="' + Perfil + '"'; // entre comillas, como Config: segunda barrera
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
  var ResVersion := '';       // el .res de version (ResDeVersion)...
  var ResVacioAntes := False; // ...y si ya estaba sin recursos
  var QueueSW := TStopwatch.StartNew;
  GBuildLock.Enter;
  var QueuedMs := QueueSW.ElapsedMilliseconds;
  // EscaneoCompileOnly y msbuild, bajo EL cerrojo de escritura (GLock): msbuild
  // compila los MISMOS bytes que se escanearon. Un delphi_edit del .dproj entre
  // el escaneo y msbuild colaba un <Exec> (TOCTOU, revisor 1.18.0). El orden es
  // GBuildLock -> GLock SIEMPRE (EnsureDeployManifest tambien toma GLock): al
  // reves, dos builds se bloquearian. Solo el camino no confiado escanea.
  var Confiado := AllowBuildScripts;
  if not Confiado then
    EnterFileEdit;
  try
  EventosSaltados := EscaneoCompileOnly(ADprojPath, Plat, Cfg, Info, Confiado);
  // Un Windows REMOTO (perfil PAServer de Windows) despliega como un Linux:
  // sin manifiesto, msbuild "desplegaba" cero ficheros y decia exito. La
  // plataforma local solo lo es cuando no hay perfil (medido 2026-09-22 con
  // el primer deploy Win64 a windows-local: carpeta vacia en el destino).
  if Target.Contains('Deploy') and ((Perfil <> '') or not IsLocalPlatform(Plat)) then
  begin
    ManifestFilled := TFile.Exists(ManifiestoDe(TPath.GetFullPath(ADprojPath)));
    EnsureDeployManifest(TPath.GetFullPath(ADprojPath), Plat, Info.RootDir,
      ManifestNew, Cfg); // la config del build (A35)
    ManifestFilled := ManifestFilled and ManifestNew;
  end;
  // /p:DeviceId= reaches the deployment targets, but measured they only
  // auto-install on iOS (_InstallIpa); an Android install is delphi_adb's
  // job with the built .apk. The param stays for the iOS day.
  var DeviceArg := '';
  if ADeviceId.Trim <> '' then
    DeviceArg := ' /p:DeviceId="' + ADeviceId.Trim + '"'; // la puerta ya lo juzgo (BadDeviceToken)

  // Remote platforms (Linux64...) link against a locally provisioned
  // SDK/sysroot, y desde 2026-09-20 puede haber VARIOS: un SDK = una carpeta,
  // como los de Android. Quien manda, por este orden: lo que pida la llamada
  // (sdk=), lo que declare el PROYECTO (PlatformSDK, que es lo que lee
  // CodeGear.Profiles.Targets), y si no, el unico que haya - o el
  // <Plataforma>.sdk historico, para no romper lo que ya compilaba. Con
  // varios y sin pistas NO se elige a ciegas: se dice y se para.
  // sdk= en una plataforma que se compila AQUI no significa nada: set-sdk ya lo
  // dice (CFG-108) y aqui se ignoraba en silencio (sexta revision)
  if IsLocalPlatform(Plat) and (ASdk.Trim <> '') then
    raise Exception.Create(MsgFmt(SR_CONFIG_SDK_LOCAL_FMT, [Plat]));
  var SdkArg := '';
  if not IsLocalPlatform(Plat) then
  begin
    var Pedido := ASdk.Trim;
    if Pedido <> '' then
    begin
      Pedido := NombreDeSdk(Pedido);
      // No basta con que exista un fichero con ese nombre: la lista de SDKs
      // de la plataforma, la MISMA que usa set-sdk (auditoria 25-sep-2026).
      var SdksMaquina := SdksDePlataforma(Info.Version, Plat);
      var IdxSdk := IndexText(Pedido, SdksMaquina);
      if IdxSdk < 0 then
        raise Exception.Create(MsgFmt(SR_BUILD_SDK_NOEXISTE_FMT,
          [Pedido, string.Join(', ', SdksMaquina)]));
      // con SU nombre, el de la lista de la maquina: el agente solo elige (2an)
      Pedido := SdksMaquina[IdxSdk];
      SdkArg := ' /p:PlatformSDK="' + Pedido + '"';
      SdkUsado := Pedido;
    end
    else if ProyectoDeclaraSdk(TPath.GetFullPath(ADprojPath), Plat, Cfg, SdkUsado) then
      // el proyecto lo dice: no se le pisa, y se cuenta cual es
      SdkNota := MsgFmt(SN_BUILD_SDK_PROYECTO_FMT, [SdkUsado])
    else
    begin
      var Cand := SdksDePlataforma(Info.Version, Plat);
      var Historico := NombreDeSdk(CanonicalPlatform(Plat));
      // El default del SDK Manager es la eleccion del operador EN EL IDE:
      // manda sobre el nombre historico y sobre cualquier adivinanza, y es lo
      // que evita negarse a compilar en una maquina que ya tenia respuesta a
      // esta pregunta (medido: al retirar el Linux64.sdk viejo, media bateria
      // se quedo sin poder compilar).
      var PorDefecto := SdkPorDefectoDelIde(Info.Version, Plat);
      if (PorDefecto <> '') and TFile.Exists(RutaDeSdk(Info.Version, PorDefecto)) then
      begin
        SdkUsado := PorDefecto;
        if Length(Cand) > 1 then
          SdkNota := MsgFmt(SN_BUILD_SDK_DEFAULT_FMT,
            [SdkUsado, string.Join(', ', Cand)]);
      end
      else if (CanonicalPlatform(Plat) <> '') and
         TFile.Exists(RutaDeSdk(Info.Version, Historico)) then
        SdkUsado := Historico
      else if Length(Cand) = 1 then
        SdkUsado := Cand[0]
      else if Length(Cand) > 1 then
        raise Exception.Create(MsgFmt(SR_BUILD_SDK_VARIOS_FMT,
          [Plat, string.Join(', ', Cand)]));
      if SdkUsado <> '' then
      begin
        SdkArg := ' /p:PlatformSDK="' + SdkUsado + '"';
        // Solo si nadie ha explicado ya POR QUE es ese: la rama del default
        // del IDE deja su propia nota, y pisarla convertia "lo eligio tu SDK
        // Manager" en un "hay varios, mira a ver" que no decia nada.
        if (SdkNota = '') and (Length(Cand) > 1) then
          SdkNota := MsgFmt(SN_BUILD_SDK_ELEGIDO_FMT,
            [SdkUsado, string.Join(', ', Cand)]);
      end;
    end;
    // Compilar contra un sysroot con dos distros dentro no es un error del
    // compilador y no se ve en ningun sitio: se dice aqui.
    if SdkUsado <> '' then
    begin
      var Mezcla := SysrootMezcladoDeSdk(Info.Version, SdkUsado);
      if Mezcla <> '' then
        SdkAviso := MsgFmt(SN_BUILD_SDK_MEZCLA_FMT, [SdkUsado, Mezcla]);
    end;
  end;

  // Las salidas que el proyecto no declara, suplidas por el build como
  // propiedad global de msbuild (BuildOutputDefault, ya juzgadas por
  // SalidaDenegada): msbuild la usa como si el .dproj la trajera y el .dproj
  // no se toca. Lo declarado nunca se pisa: solo va lo que falta. Sin barra
  // final (dcc no la quiere; EnComillas la escaparia bien de todos modos).
  var SalidaArg := '';
  for var Sup in Suplidas do
    SalidaArg := SalidaArg + Format(' /p:%s=%s',
      [Sup.Tag, EnComillas(SinBarraFinal(Sup.Dir))]); // EL quitabarras de la casa (Lsp.NetDrives)
  // Security audit trail: a build can run arbitrary pre/post-build steps
  // declared in the .dproj, so record every one - and what the build supplies.
  TLogger.Warning(MsgFmt(SL_BUILD_DELPHI_BUILD_TARGET_FMT,
    [TPath.GetFullPath(ADprojPath), Plat, Cfg, TargetsMsBuild, SdkArg, SalidaArg]));

  // Los MISMOS flags que BuildWithParams.bat, que es el contrato de la casa
  // para builds con agentes: quiet = solo errores y el resumen (unas pocas
  // lineas), normal = warnings e hitos, verbose = todo. Un bat por proyecto
  // existia sobre todo por esto; teniendolo aqui, un proyecto solo necesita
  // el suyo para SU ritual (numero de build, EurekaLog, firma, datos).
  // Vacio = normal, que es como se comportaba antes de tener el parametro:
  // los otros motores que llaman aqui no cambian de comportamiento.
  var Verb := '/v:minimal /nologo';
  // Un PAQUETE en quiet pide minimal: el W1033 ("unit de otro paquete
  // compilada dentro de este") es un warning, y en quiet msbuild no lo
  // imprime - el paquete salia en verde con la VCL entera dentro y el agente
  // no veia nada (medido 2026-09-23: 25 W1033, BPL de 4,6 MB en vez de 13 KB).
  // La respuesta sigue sin warnings[] en quiet; los W1033 van aparte.
  EsPaquete := SameText(ReadDproj(TPath.GetFullPath(ADprojPath)).AppType, 'Package');
  if SameText(AVerbosity, 'quiet') and not EsPaquete then
    Verb := '/v:quiet /clp:ErrorsOnly;Summary;NoItemAndPropertyList /nologo'
  else if SameText(AVerbosity, 'verbose') then
    Verb := '/v:detailed';
  // Propiedades globales de msbuild ganan a las del .dproj: vaciar los
  // eventos aqui es no ejecutarlos, sin tocar el proyecto.
  var EventArg := '';
  if EventosSaltados then
    EventArg := ' /p:PreBuildEvent= /p:PostBuildEvent= /p:PreLinkEvent= /p:PostLinkEvent=';
  // Config entre comillas: su nombre puede llevar un espacio ("Release Plus")
  // y msbuild lo partia en dos argumentos (MSB1008); las comillas no las
  // puede traer, NombreDeConfigNoValido ya lo ha dicho (ConfigDelBuild).
  // msbuild.exe por su ruta y sin shell (2an, arriba): un metacaracter en un
  // valor es solo un caracter, y los jueces de cada valor siguen como segunda
  // barrera (David, 11-oct)
  var Orden := Format('%s %s /t:%s /p:Config="%s" /p:Platform=%s%s%s%s%s%s %s',
    [EnComillas(MsBuildExe), EnComillas(TPath.GetFullPath(ADprojPath)), TargetsMsBuild, Cfg,
     Plat, SdkArg, ProfileArg, DeviceArg, EventArg, SalidaArg, Verb]);
  // la carpeta del proyecto como cwd: sin ella, msbuild hereda la del proceso
  // (el servicio: la casa del servidor) y lo que una tarea escribe RELATIVO -el
  // .vrc/.res de la info de version- cae FUERA de la jaula (2ak de la 1.18.2,
  // medido: Incl.res/Incl.vrc en la raiz del repo). La carpeta del .dproj ya
  // esta en las raices y la aprobo la puerta de salida. Ya no se busca nada en
  // ella: msbuild va por su ruta (con cmd, un msbuild.bat de ahi ganaba)
  var Cwd := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  // el .res de version de antes: si este build lo deja sin recursos, se dice
  // (resNote, abajo)
  ResVersion := ResDeVersion(ADprojPath, Plat, Cfg);
  ResVacioAntes := ResSinRecursos(ResVersion);
  Output := RunCapturedIn(Orden, Cwd, ATimeoutMs, ExitCode, EntornoMsBuild);
  // F2039 = el .exe que este build va a escribir esta ABIERTO, casi siempre
  // porque delphi_test lo esta ejecutando ahora mismo: el
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
    Output := RunCapturedIn(Orden, Cwd, ATimeoutMs, ExitCode, EntornoMsBuild);
  end;
  // "cannot find -lX" con un sysroot nuestro: el nombre -dev que falta se
  // completa en el SDK (ver CompletaEnlacesDev) y el build se repite UNA vez.
  // Medido 2026-09-21: GalateaFMX dejo de enlazar en zorin18 y fedora44 por
  // un libz.so que ninguno de los dos traia; con la copia enlaza en ambos.
  if (ExitCode <> 0) and (SdkUsado <> '') and Output.Contains('cannot find -l') then
  begin
    EnlacesDev := CompletaEnlacesDev(Info.Version, SdkUsado, Output, EnlacesNota);
    if EnlacesDev > 0 then
      Output := RunCapturedIn(Orden, Cwd, ATimeoutMs, ExitCode, EntornoMsBuild);
  end;
  finally
    if not Confiado then
      LeaveFileEdit;
    GBuildLock.Leave;
  end;

  Errors := TJSONArray.Create;
  Warnings := TJSONArray.Create;
  // Lo mismo que entra en errors[]/warnings[], apuntado aparte para que la
  // cola no lo repita.
  YaDicho := TStringList.Create;
  YaDicho.Sorted := True;
  YaDicho.Duplicates := dupIgnore;
  Lines := LineasDelTexto(Output);
  // msbuild cierra cada aviso y cada error con " [<ruta del .dproj>]": la
  // MISMA ruta en cada linea, cerca del 40% de un aviso (medido el
  // 6-oct-2026 compilando este repo). Fuera aqui, una vez, antes de
  // clasificar: errors[], warnings[] y la cola salen sin ella.
  for var K := 0 to High(Lines) do
    Lines[K] := TRegEx.Replace(Lines[K],
      '\s\[[^\[\]]+\.(?:dproj|groupproj)\]\s*$', '', [roIgnoreCase]);
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
  // La cola: las 25 ultimas lineas que dicen algo (120 en verbose), el
  // resumen y los tiempos, por EL recorte de la casa (ColaDeSalida, V80 de
  // la 1.23.1), sobre las lineas ya sin la ruta del .dproj.
  LineasDeCola := 25;
  if SameText(AVerbosity, 'verbose') then
    LineasDeCola := 120;
  try
    Cola := ColaDeSalida(string.Join(#10, Lines), LineasDeCola,
      function(var ALinea: string): Boolean
      begin
        // Lo que ya va en errors[] o warnings[] NO se repite aqui: la cola
        // los traia OTRA VEZ enteros, y en un proyecto con quince avisos eso
        // son 2-3 KB duplicados en CADA build, pagados por el contexto del
        // agente (visto el 2026-09-20 compilando este mismo repo por el MCP
        // una y otra vez). La cola es el resumen y los tiempos.
        if (ALinea.Trim = '') or (YaDicho.IndexOf(ALinea.Trim) >= 0) then
          Exit(False);
        if ALinea.Contains('Linker command line:') and
           not SameText(AVerbosity, 'verbose') and
           (TRegEx.Matches(ALinea, '(?:^|\s)-L\s*\S+').Count >= 4) then
        begin
          var MSys := TRegEx.Match(ALinea, '--sysroot\s+(\S+)');
          // IfThen evalua los DOS brazos: con un linker sin --sysroot (Android)
          // Groups[1] lanzaba "Index out of bounds (1)" y tumbaba la respuesta
          // entera del build con verbosity=normal (medido 2026-09-23, G.23).
          var Sysroot := MsgText(SF_NINGUNO);
          if MSys.Success then
            Sysroot := MSys.Groups[1].Value;
          ALinea := MsgFmt(SF_BUILD_LINKER_RESUMIDA_FMT,
            [Sysroot,
             TRegEx.Matches(ALinea, '(?:^|\s)-L\s*\S+').Count]);
        end;
        Result := True;
      end).Texto;

    Result := TJSONObject.Create;
    try
    Result.AddPair('success', TJSONBool.Create(ExitCode = 0));
    Result.AddPair('exitCode', TJSONNumber.Create(Integer(ExitCode)));
    // lo que tardo, sin la cola (queuedMs): el mismo nombre que delphi_test y
    // remote-run (Qwen en la regresion de GalateaFMX, 1.22.1)
    Result.AddPair('durationMs', TJSONNumber.Create(QueueSW.ElapsedMilliseconds - QueuedMs));
    if QueuedMs >= 500 then
    begin
      Result.AddPair('queuedMs', TJSONNumber.Create(QueuedMs));
      Result.AddPair('queuedNote', MsgText(SN_BUILD_QUEUED));
    end;
    // Con QUE instalacion se compilo: vital para un agente en una maquina
    // con varias (la del servidor, [Server] DelphiVersion), y nada obvio sin decirlo.
    // Con una sola, ruido en cada build; y el proyecto, el eco de lo que se
    // pidio (revisor de tokens, 4-oct-2026)
    if Length(DiscoverAllRadStudios) > 1 then
    begin
      Result.AddPair('delphiVersion', Info.Version);
      if Info.ProductName <> '' then
        Result.AddPair('delphiName', Info.ProductName);
      if Info.Build <> '' then
        Result.AddPair('delphiBuild', Info.Build);
    end;
    Result.AddPair('platform', Plat);
    // Hasta la 1.15 cada tool tenia su plataforma por defecto (aqui Win32,
    // delphi_test Win64) y una nota (BUILD-036) lo avisaba; ahora las dos
    // toman la del proyecto, como el IDE, y "platform" dice cual fue.
    Result.AddPair('config', Cfg);
    Result.AddPair('target', Target);
    if EventosSaltados then
    begin
      Result.AddPair('buildEventsSkipped', TJSONBool.Create(True));
      Result.AddPair('buildEventsNote', MsgText(SN_BUILD_EVENTS_SKIPPED));
    end;
    // las salidas que el proyecto no declara y este build puso dentro
    // (BuildOutputDefault): cual y donde, para que el agente sepa donde han
    // caido sus .dcu/.bpl/.dcp sin que nadie tocara el .dproj
    if Length(Suplidas) > 0 then
    begin
      var Suplido := TJSONArray.Create;
      for var Sup in Suplidas do
        Suplido.Add(TJSONObject.Create.AddPair('property', Sup.Tag).AddPair('dir', Sup.Dir));
      Result.AddPair('outputSupplied', Suplido);
      Result.AddPair('outputSuppliedNote', MsgText(SN_BUILD_OUTPUT_SUPPLIED));
    end;
    if SdkUsado <> '' then
      Result.AddPair('sdk', SdkUsado);
    if SdkNota <> '' then
      Result.AddPair('sdkNote', SdkNota);
    if SdkAviso <> '' then
      Result.AddPair('sdkWarning', SdkAviso);
    Result.AddPair('errors', Errors);
    // En quiet NO va un warnings:[] vacio: se leeria como "no hay warnings" y
    // seria mentira - es que no se han pedido. Y sin nota: lo dice la
    // descripcion de verbosity, una vez (no en cada build)
    if SameText(AVerbosity, 'quiet') then
      Warnings.Free
    else
      Result.AddPair('warnings', Warnings);
    // W1033 en un paquete: units de OTROS paquetes compiladas dentro del
    // nuestro. El IDE ensena la lista y pregunta si anadir esos paquetes al
    // requires (David, 2026-09-23); aqui va la lista, con el paquete de cada
    // unit leido de los BPL de la instalacion, y el agente decide con
    // delphi_config add-requires.
    if EsPaquete then
    begin
      var Implicitas := TStringList.Create;
      var Sugeridos := TStringList.Create;
      var SinPaquete := TStringList.Create;
      var DelWorkspace := TStringList.Create;
      var DeBpl := TStringList.Create; // solo los leidos de los BPL: la frase los nombra aparte
      try
        Implicitas.Sorted := True; Implicitas.Duplicates := dupIgnore;
        Sugeridos.Sorted := True; Sugeridos.Duplicates := dupIgnore;
        SinPaquete.Sorted := True; SinPaquete.Duplicates := dupIgnore;
        // la frase de BUILD-008 nombraba vcl una vez por cada unit suya (x20;
        // Fable sobre la 1.22.2, B3)
        DeBpl.Sorted := True; DeBpl.Duplicates := dupIgnore;
        // por el CODIGO y el primer '...' (un dcc traducido no dice "implicitly imported")
        for var MI in TRegEx.Matches(Output, 'W1033:?[^'']*''([^'']+)''', [roIgnoreCase]) do
        begin
          Implicitas.Add(MI.Groups[1].Value);
          var Pk := PaqueteDeUnit(Info.RootDir, MI.Groups[1].Value);
          if Pk <> '' then
          begin
            Sugeridos.Add(Pk);
            DeBpl.Add(Pk);
          end
          else
          begin
            // Punto 8 (Hermes 2026-09-23; David 24-sep): la unit puede ser de
            // un .dpk del PROPIO workspace, que no esta en ningun BPL de la
            // instalacion. Se sugiere ese paquete y se dice que hay que
            // compilarlo antes; nada mas. Si dos .dpk la contienen, van los dos.
            var Dpks := WorkspacePackagesWithUnit(
              DprDe(TPath.GetFullPath(ADprojPath)), MI.Groups[1].Value); // el propio .dpk no cuenta
            if Length(Dpks) = 0 then
              SinPaquete.Add(MI.Groups[1].Value)
            else
              for var Dk in Dpks do
              begin
                Sugeridos.Add(TPath.GetFileNameWithoutExtension(Dk));
                DelWorkspace.Add(MI.Groups[1].Value + ' -> ' + Dk);
              end;
          end;
        end;
        if Implicitas.Count > 0 then
        begin
          var ArrI := TJSONArray.Create;
          for var S in Implicitas do
            ArrI.Add(S);
          Result.AddPair('implicitImports', ArrI);
          if Sugeridos.Count > 0 then
          begin
            var ArrS := TJSONArray.Create;
            for var S in Sugeridos do
              ArrS.Add(S);
            Result.AddPair('requiresSuggested', ArrS);
          end;
          // La frase de los BPL solo si hay alguno: con la lista vacia decia
          // 'requires=""' (visto el 24-sep con un paquete del workspace).
          Result.AddPair('requiresNote', MsgFmt(SN_BUILD_REQUIRES_FMT,
            [Implicitas.Count,
             IfThen(DeBpl.Count > 0,
               MsgFmt(SN_BUILD_REQUIRES_KNOWN_FMT, [string.Join(', ', DeBpl.ToStringArray),
                 string.Join(';', DeBpl.ToStringArray)]), ''),
             IfThen(SinPaquete.Count > 0,
               MsgFmt(SN_BUILD_REQUIRES_UNKNOWN_FMT, [string.Join(', ', SinPaquete.ToStringArray)]), '')]));
          if DelWorkspace.Count > 0 then
            Result.AddPair('requiresWorkspaceNote', MsgFmt(SN_BUILD_REQUIRES_WORKSPACE_FMT,
              [string.Join('; ', DelWorkspace.ToStringArray)]));
        end;
      finally
        Implicitas.Free;
        Sugeridos.Free;
        SinPaquete.Free;
        DelWorkspace.Free;
        DeBpl.Free;
      end;
    end;
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
        Result.AddPair('firstErrorNote', MsgText(SN_BUILD_FIRST_ERROR));
    end;
    // F2039 is almost never a code problem: the binary this build is about to
    // write is OPEN - the previous run still alive, the IDE holding it, a
    // debugger attached. It reads like a compiler error and it is not, so it
    // gets the one sentence that turns it into an action.
    if (ExitCode <> 0) and Output.Contains('F2039') then
    begin
      Result.AddPair('lockedOutputNote', MsgText(SN_BUILD_LOCKED_OUTPUT));
    end;
    // Se reintento y salio: el agente merece saber que su build tardo mas
    // porque el binario estaba ocupado, no porque compilar sea lento.
    if ReintentosBloqueo > 0 then
    begin
      Result.AddPair('lockedRetries', TJSONNumber.Create(ReintentosBloqueo));
      Result.AddPair('lockedRetriesNote', MsgText(SN_BUILD_LOCKED_RETRY));
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
        var HayCualificadas := False;
        for var U in Missing do
        begin
          var MObj := TJSONObject.Create;
          MArr.AddElement(MObj);
          MObj.AddPair('unit', U);
          var CArr := TJSONArray.Create;
          MObj.AddPair('sourceFolders', CArr);
          var Cualificadas: TArray<string>;
          for var D in UnitSourceFolders(U, Cualificadas) do
            CArr.Add(D);
          // sin fuente con ESE nombre pero si bajo un ambito (Dialogs ->
          // FMX.Dialogs): lo que falta es cualificarla (BUILD-049)
          if Length(Cualificadas) > 0 then
          begin
            var QArr := TJSONArray.Create;
            MObj.AddPair('qualified', QArr);
            for var Q in Cualificadas do
              QArr.Add(Q);
            HayCualificadas := True;
          end;
        end;
        Result.AddPair('missingUnitsNote', MsgText(SN_BUILD_MISSING_UNITS_NOTE) +
          IfThen(HayCualificadas, MsgText(SN_BUILD_MISSING_UNITS_QUALIFY), '') +
          IfThen(EsPaquete, MsgText(SN_BUILD_MISSING_UNITS_PACKAGE), ''));
      end;
    end;
    // En quiet msbuild NI SIQUIERA imprime los warnings, asi que no se puede
    // dar un recuento: no va la clave (nunca un 0 inventado). Lo dice la
    // descripcion de verbosity; la nota BUILD-001 iba en CADA build quiet
    // (revisor de tokens, 4-oct-2026). La cola, solo si dice algo.
    if Cola <> '' then
      Result.AddPair('outputTail', Cola);
    // A stateless protocol means the agent only knows what each result tells
    // it: say WHERE the artifact landed, or it has to hunt the disk for it
    // (measured in the field: 20 calls chasing a fresh exe that delphi_list
    // kept hidden as build output).
    if (ExitCode = 0) and not SameText(Target, 'Clean') then
    begin
      var Artifact := ResolveBuildOutput(TPath.GetFullPath(ADprojPath), Plat, Cfg);
      // la nota de siempre (BUILD-002: recogerlo con delphi_package) iba en
      // cada build: lo dice delphi_package; queda la del .apk
      var Note := '';
      // An Android Deploy's real product is the .apk the packager left in
      // <Platform>\<Config>\<name>\bin - declare THAT, not the .so.
      if (SistemaDePlataforma(Plat) = spAndroid) and Target.Contains('Deploy') then
      begin
        var ProjName := TPath.GetFileNameWithoutExtension(ADprojPath);
        var Apk := TPath.Combine(
          TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath)),
          Plat + '\' + Cfg + '\' + ProjName + '\bin\' + ProjName + '.apk');
        if TFile.Exists(Apk) then
        begin
          Artifact := Apk;
          Note := MsgText(SN_BUILD_APK_NOTE);
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
        if Note <> '' then
          Result.AddPair('outputNote', Note);
      end;
      // Same statelessness rule for a remote deploy: say where the files
      // landed ON THE TARGET, or the agent has to guess PAServer's layout.
      if (Perfil <> '') and Target.Contains('Deploy') then
      begin
        var Shipped := TRegEx.Matches(Output, 'Deploying\s+"([^"]+)"', [roIgnoreCase]).Count +
          TRegEx.Matches(Output, 'Copying\s+"?([^"\r\n]+?)"?\s+to\s+remote', [roIgnoreCase]).Count;
        // Lo que msbuild imprime de verdad en un Deploy por PAServer (medido
        // 2026-09-23, Windows, verbose): la orden paclient --put="a,b,1,c;..."
        // del target _DeployFiles, un fichero por cada tramo entre ';'.
        for var MP in TRegEx.Matches(Output, '--put="?([^"\r\n]+)', [roIgnoreCase]) do
          Shipped := Shipped + Length(MP.Groups[1].Value.Split([';']));
        Result.AddPair('deployNote', MsgFmt(SN_BUILD_DEPLOYED_FMT,
          [Perfil, GetEnvironmentVariable('USERNAME'), Perfil,
           TPath.GetFileNameWithoutExtension(ADprojPath)]));
        // de donde salio: call | project | ide-default (los de delphi_config view)
        Result.AddPair('profileSource', FuenteDelPerfil);
        if Output.Contains('Local file "" not found') then
          Result.AddPair('deployWarning', MsgText(SN_BUILD_DEPLOY_EMPTY_ENTRY));
        if Shipped > 0 then
          Result.AddPair('deployedFiles', TJSONNumber.Create(Shipped))
        else if not SameText(AVerbosity, 'verbose') then
          // Solo en verbose imprime msbuild las copias (medido 2026-09-23:
          // en normal tampoco): no se puede contar, y
          // decir "no se envio nada" era falso (medido 2026-09-23: deploy a
          // Windows correcto y sin deployedFiles).
          Result.AddPair('deployedFilesNote', MsgText(SN_BUILD_QUIET_DEPLOYED));
      end;
      // El .res de version (ResDeVersion), uno para las plataformas que
      // comparten carpeta: un build de otra plataforma lo deja SIN recursos y
      // un Make de Windows no lo rehace mientras el .dproj sea mas viejo, asi
      // que el exe sale sin icono ni version (Hermes, 22-oct-2026; medido el
      // 24-oct: 154.792 -> 32 bytes con Linux64, y el Make de Win64, 155.136
      // bytes menos). Uno de Windows siempre le deja algo: sin recursos, lo
      // dejo otra plataforma
      if ResSinRecursos(ResVersion) then
      begin
        if SistemaDePlataforma(Plat) <> spWindows then
        begin
          if not ResVacioAntes then // el que lo deja asi, una vez
            Result.AddPair('resNote', MsgFmt(SN_BUILD_RES_SIN_RECURSOS_FMT,
              [TPath.GetFileName(ResVersion), Plat]));
        end
        else if SameText(Target, 'Make') then
          Result.AddPair('resNote', MsgFmt(SN_BUILD_RES_SIN_RECURSOS_MAKE_FMT,
            [TPath.GetFileName(ResVersion)]));
      end;
    end;
    // Un Deploy que no pudo reescribir la carpeta del target porque el vigia
    // de un remote-run anterior (<job>.wait.exe) sigue vivo: ese programa
    // sigue corriendo alli. El E0017 crudo de msbuild no lo dice; el nombre
    // del fichero lleva el id del trabajo, asi que se le da la orden de kill.
    // Medido 2026-09-23 contra 192.168.1.10 con una GUI viva.
    if (ExitCode <> 0) and Target.Contains('Deploy') and Output.Contains('E0017') then
    begin
      // el id del trabajo por el patron de su nombrador (Lsp.Casa.SelloUnico)
      // y el del vigia, por SU nombrador (Lsp.NombresDeTrabajo)
      var MLock := TRegEx.Match(Output, '(' + SELLO_UNICO_PATRON + ')' +
        PATRON_DEL_VIGIA_TRAS_EL_ID, [roIgnoreCase]);
      if MLock.Success then
        Result.AddPair('deployLockedNote', MsgFmt(SN_BUILD_DEPLOY_LOCKED_FMT,
          [MLock.Groups[1].Value, Perfil, ADprojPath, MLock.Groups[1].Value]));
    end;
    // El PAServer del perfil es de otro Delphi (u otra plataforma): la tarea
    // PAClient de msbuild lo dice en crudo; aqui, que hacer.
    if (ExitCode <> 0) and Target.Contains('Deploy') then
    begin
      var Aviso := AvisoDePaclient(Output);
      if Aviso <> '' then
        Result.AddPair('paserverNote', Aviso);
    end;
    // The agent should know its project just gained a manifest whether or
    // not this particular msbuild run succeeded.
    if ManifestNew then
      if SistemaDePlataforma(Plat) = spAndroid then
        Result.AddPair('deployManifest', MsgText(SN_BUILD_ANDROID_NEW))
      else if ManifestFilled then
        Result.AddPair('deployManifest', MsgFmt(SN_BUILD_MANIFEST_FILLED_FMT, [Plat]))
      else
        Result.AddPair('deployManifest', MsgText(SN_BUILD_MANIFEST_NEW));
    except
      // una excepcion a medio camino dejaba sin liberar lo que se devuelve
      // (el patron del Result de Rename, menor de la ronda 16)
      Result.Free;
      raise;
    end;
  finally
    YaDicho.Free;
  end;
end;

initialization
  GBuildLock := TCriticalSection.Create;

finalization
  GBuildLock.Free;

end.
