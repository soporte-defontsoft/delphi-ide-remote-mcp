program McpRunJob;

{ EL LANZADOR: lo que PAServer ejecuta en el destino por cada trabajo remoto,
  en Linux y en Windows, con el MISMO comportamiento.

  paclient no tiene operacion "ejecuta con argumentos": sube ficheros, y un
  flag del --put hace que PAServer arranque el fichero subido SIN argumentos
  y ESPERE a que termine (paclient bloqueado mientras tanto). Medido el
  2026-09-22 en Zorin, Fedora y Windows: flag 3 arranca un ELF, flag 5 un PE
  (en Linux flag 5 es "/bin/sh fichero", que no sirve para un binario). Hasta
  esa fecha en Linux se subia un guion /bin/sh compuesto por el servidor y en
  Windows este programa: dos escritores, dos lectores, dos ramas. Decision de
  David: UNA rama. El servidor escribe run-<job>.job y sube este programa con
  el nombre run-<job> (Linux) o run-<job>.exe (Windows); lo demas es igual.

  run-<job>.job (UTF-8, una cosa por linea): el binario, el fichero de salida,
  y despues UN ARGUMENTO POR LINEA. Sin shell: los argumentos van de aqui al
  argv del programa tal cual, asi que no hay nada que blindar ni que escapar.

  Lo que hace, en este orden:
    1. lee y borra su .job;
    2. escribe ___ENV= : en Linux completa el entorno grafico que FALTE
       (XDG_RUNTIME_DIR, D-Bus, WAYLAND_DISPLAY, DISPLAY, XAUTHORITY) desde la
       sesion del usuario -un PAServer que corre como servicio nace sin el- y
       cuenta que anadio; en Windows dice en que SESION corre (la 0 es la de
       los servicios y no tiene escritorio);
    3. comprueba la FIRMA del binario (ELF o MZ): solo se ejecuta lo que ese
       proyecto desplego, y un guion que hubiera al lado no vale;
    4. lo arranca DESATENDIDO con la salida en <job>.out y se va, para que
       PAServer y paclient queden libres;
    5. deja un VIGIA que espera al programa y remata la salida con
       ___RC=<codigo>: en Linux un proceso hijo (fork + setsid), en Windows
       una copia de si mismo (<job>.wait.exe), porque PAServer borra
       run-<job>.exe en cuanto este proceso termina.

  Nada se instala en el destino. }

{$APPTYPE CONSOLE}
{$R *.res}

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
{$IFDEF LINUX}
  Posix.Base,
  Posix.SysTypes,
  Posix.Unistd,
  Posix.Stdlib,
  Posix.SysStat,
  Posix.SysWait,
  Posix.Fcntl,
{$ENDIF}
  System.SysUtils,
  System.IOUtils,
  System.Classes;

{$IFDEF MSWINDOWS}
const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000; // no esta en Winapi.Windows
{$ENDIF}

{ Anade texto (UTF-8) al final del fichero de salida, compartiendolo: el
  programa lanzado escribe en el mismo fichero y paclient lo lee mientras. }
procedure Anade(const AFichero, ATexto: string);
{$IFDEF MSWINDOWS}
var
  H: THandle;
  B: TBytes;
  Escritos: DWORD;
begin
  H := CreateFile(PChar(AFichero), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    B := TEncoding.UTF8.GetBytes(ATexto);
    if Length(B) > 0 then
      WriteFile(H, B[0], Length(B), Escritos, nil);
  finally
    CloseHandle(H);
  end;
end;
{$ELSE}
var
  Fd: Integer;
  B: TBytes;
begin
  Fd := Posix.Fcntl.open(PAnsiChar(UTF8String(AFichero)),
    O_WRONLY or O_APPEND or O_CREAT, S_IRUSR or S_IWUSR or S_IRGRP or S_IROTH);
  if Fd < 0 then
    Exit;
  try
    B := TEncoding.UTF8.GetBytes(ATexto);
    if Length(B) > 0 then
      __write(Fd, @B[0], Length(B));
  finally
    __close(Fd);
  end;
end;
{$ENDIF}

{ La firma: ELF (7F 45 4C 46) o PE (MZ). Lo mismo que comprobaba el guion. }
function EsBinarioNativo(const AFichero: string): Boolean;
var
  F: TFileStream;
  Firma: array[0..3] of Byte;
begin
  Result := False;
  try
    F := TFileStream.Create(AFichero, fmOpenRead or fmShareDenyNone);
    try
      if F.Read(Firma, 4) < 2 then
        Exit;
      Result := ((Firma[0] = $7F) and (Firma[1] = Ord('E')) and
                 (Firma[2] = Ord('L')) and (Firma[3] = Ord('F'))) or
                ((Firma[0] = Ord('M')) and (Firma[1] = Ord('Z')));
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

{$IFDEF LINUX}
function EsSocket(const APath: string): Boolean;
var
  St: _stat;
begin
  Result := (stat(PAnsiChar(UTF8String(APath)), St) = 0) and
    ((St.st_mode and S_IFMT) = S_IFSOCK);
end;

function Entorno(const ANombre: string): string;
var
  P: MarshaledAString;
begin
  P := getenv(PAnsiChar(UTF8String(ANombre)));
  if P = nil then
    Result := ''
  else
    Result := string(UTF8String(P));
end;

procedure PonEntorno(const ANombre, AValor: string);
begin
  setenv(PAnsiChar(UTF8String(ANombre)), PAnsiChar(UTF8String(AValor)), 1);
end;

{ El entorno grafico de la sesion del usuario, solo lo que FALTE. Es lo que
  hacia el guion /bin/sh hasta el 2026-09-22, en codigo. Devuelve la linea
  ___ENV= con el mismo formato que lee el servidor: <1|0>|<lo anadido>. }
function CompletaEntornoGrafico: string;
var
  Runtime, Anadido, A, Mejor: string;
  I: Integer;
  Mas: TDateTime;
begin
  Anadido := '';
  Runtime := Entorno('XDG_RUNTIME_DIR');
  if (Runtime = '') and TDirectory.Exists('/run/user/' + IntToStr(getuid)) then
  begin
    Runtime := '/run/user/' + IntToStr(getuid);
    PonEntorno('XDG_RUNTIME_DIR', Runtime);
    Anadido := Anadido + ' XDG_RUNTIME_DIR';
  end;
  if (Entorno('DBUS_SESSION_BUS_ADDRESS') = '') and (Runtime <> '') and
     EsSocket(Runtime + '/bus') then
  begin
    PonEntorno('DBUS_SESSION_BUS_ADDRESS', 'unix:path=' + Runtime + '/bus');
    Anadido := Anadido + ' DBUS_SESSION_BUS_ADDRESS';
  end;
  if (Entorno('WAYLAND_DISPLAY') = '') and (Runtime <> '') then
    for I := 0 to 9 do
      if EsSocket(Runtime + '/wayland-' + IntToStr(I)) then
      begin
        PonEntorno('WAYLAND_DISPLAY', 'wayland-' + IntToStr(I));
        Anadido := Anadido + ' WAYLAND_DISPLAY';
        Break;
      end;
  if (Entorno('DISPLAY') = '') and EsSocket('/tmp/.X11-unix/X0') then
  begin
    PonEntorno('DISPLAY', ':0');
    Anadido := Anadido + ' DISPLAY';
  end;
  if (Entorno('DISPLAY') <> '') and (Entorno('XAUTHORITY') = '') then
  begin
    // el de mutter cambia de sufijo en cada inicio de sesion: el mas reciente
    Mejor := '';
    Mas := 0;
    if Runtime <> '' then
      try
        for A in TDirectory.GetFiles(Runtime, '.mutter-Xwaylandauth.*') do
          if TFile.GetLastWriteTime(A) > Mas then
          begin
            Mas := TFile.GetLastWriteTime(A);
            Mejor := A;
          end;
      except
        Mejor := '';
      end;
    if (Mejor = '') and TFile.Exists(Entorno('HOME') + '/.Xauthority') then
      Mejor := Entorno('HOME') + '/.Xauthority';
    if Mejor <> '' then
    begin
      PonEntorno('XAUTHORITY', Mejor);
      Anadido := Anadido + ' XAUTHORITY';
    end;
  end;
  if (Entorno('DISPLAY') <> '') or (Entorno('WAYLAND_DISPLAY') <> '') then
    Result := '___ENV=1|' + Anadido.Trim + #10
  else
    Result := '___ENV=0|' + Anadido.Trim + #10;
end;

{ Arranca el programa desatendido y deja un vigia. El VIGIA es el primer hijo
  (fork + setsid, fuera de la sesion de PAServer): el es quien arranca el
  programa, espera su final y remata la salida con ___RC=. Este proceso -el
  que PAServer espera- vuelve en cuanto el vigia existe. }
procedure LanzarYVigilar(const AExe, ACarpeta, ASalida: string;
  const AArgs: TArray<string>);
var
  Vigia, Hijo: pid_t;
  Estado, Codigo, Fd, I: Integer;
  Strs: TArray<UTF8String>;
  Ptrs: TArray<MarshaledAString>;
begin
  Vigia := fork;
  if Vigia < 0 then
  begin
    Anade(ASalida, 'error: fork del vigia fallo'#10'___RC=-1'#10);
    Exit;
  end;
  if Vigia > 0 then
    Exit; // el lanzador se va: PAServer y paclient quedan libres
  // --- el vigia
  setsid;
  Hijo := fork;
  if Hijo < 0 then
  begin
    Anade(ASalida, 'error: fork del programa fallo'#10'___RC=-1'#10);
    _exit(1);
  end;
  if Hijo = 0 then
  begin
    // --- el programa: salida al fichero, entrada de /dev/null, y execv
    Fd := Posix.Fcntl.open(PAnsiChar(UTF8String(ASalida)),
      O_WRONLY or O_APPEND or O_CREAT, S_IRUSR or S_IWUSR or S_IRGRP or S_IROTH);
    if Fd >= 0 then
    begin
      dup2(Fd, 1);
      dup2(Fd, 2);
      if Fd > 2 then
        __close(Fd);
    end;
    Fd := Posix.Fcntl.open('/dev/null', O_RDONLY);
    if Fd >= 0 then
    begin
      dup2(Fd, 0);
      if Fd > 2 then
        __close(Fd);
    end;
    chdir(PAnsiChar(UTF8String(ACarpeta)));
    SetLength(Strs, Length(AArgs) + 1);
    SetLength(Ptrs, Length(AArgs) + 2);
    Strs[0] := UTF8String(AExe);
    Ptrs[0] := MarshaledAString(PAnsiChar(Strs[0]));
    for I := 0 to High(AArgs) do
    begin
      Strs[I + 1] := UTF8String(AArgs[I]);
      Ptrs[I + 1] := MarshaledAString(PAnsiChar(Strs[I + 1]));
    end;
    Ptrs[Length(AArgs) + 1] := nil;
    execv(MarshaledAString(PAnsiChar(Strs[0])), @Ptrs[0]);
    // solo se llega aqui si execv fallo
    Anade(ASalida, 'error: no pude arrancar ' + AExe + ': ' +
      SysErrorMessage(GetLastError) + #10);
    _exit(127);
  end;
  // --- el vigia espera y remata
  Estado := 0;
  if waitpid(Hijo, @Estado, 0) < 0 then
    Codigo := -1
  else if (Estado and $7F) = 0 then
    Codigo := (Estado shr 8) and $FF   // WEXITSTATUS
  else
    Codigo := 128 + (Estado and $7F);  // muerto por senal, como el shell
  Anade(ASalida, #10'___RC=' + IntToStr(Codigo) + #10);
  _exit(0);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
function SesionPropia: DWORD;
begin
  if not ProcessIdToSessionId(GetCurrentProcessId, Result) then
    Result := 0;
end;

{ El vigia: espera al proceso y remata la salida con el centinela. }
procedure Vigilar(APid: DWORD; const ASalida: string);
var
  H: THandle;
  Codigo: DWORD;
begin
  H := OpenProcess(SYNCHRONIZE or PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if H = 0 then
  begin
    Anade(ASalida, #10'___RC=-1'#10);
    Exit;
  end;
  try
    WaitForSingleObject(H, INFINITE);
    if not GetExitCodeProcess(H, Codigo) then
      Codigo := DWORD(-1);
  finally
    CloseHandle(H);
  end;
  Anade(ASalida, #10'___RC=' + IntToStr(Integer(Codigo)) + #10);
end;

{ Un argumento para la linea de comandos de Windows, con las reglas de
  CommandLineToArgvW: entre comillas, comilla interior como \", y las barras
  que preceden a una comilla (o al final) dobladas. Aqui no hay shell: es
  solo la forma en que Windows entrega argv al programa. }
function ComillasWin(const AArg: string): string;
var
  I, Barras: Integer;
begin
  Result := '"';
  Barras := 0;
  for I := 1 to Length(AArg) do
  begin
    if AArg[I] = '\' then
      Inc(Barras)
    else if AArg[I] = '"' then
    begin
      Result := Result + StringOfChar('\', Barras * 2 + 1) + '"';
      Barras := 0;
    end
    else
    begin
      Result := Result + StringOfChar('\', Barras) + AArg[I];
      Barras := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Barras * 2) + '"';
end;

{ Arranca un programa con la salida en el fichero y sin ventana de consola.
  Devuelve el PID (0 si no pudo; AError dice por que). }
function Arrancar(const ALinea, ACarpeta, ASalida: string; AHeredar: Boolean;
  out AError: string): DWORD;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  HOut, HNul: THandle;
  Linea: string;
begin
  Result := 0;
  AError := '';
  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle := True;
  HOut := INVALID_HANDLE_VALUE;
  HNul := INVALID_HANDLE_VALUE;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  if AHeredar then
  begin
    HOut := CreateFile(PChar(ASalida), FILE_APPEND_DATA,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, @SA,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    HNul := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ, @SA,
      OPEN_EXISTING, 0, 0);
    if HOut = INVALID_HANDLE_VALUE then
    begin
      AError := 'no pude abrir la salida ' + ASalida;
      Exit;
    end;
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := HOut;
    SI.hStdError := HOut;
    SI.hStdInput := HNul;
  end;
  Linea := ALinea; // CreateProcess puede modificar el buffer: copia propia
  UniqueString(Linea);
  try
    if not CreateProcess(nil, PChar(Linea), nil, nil, AHeredar,
      CREATE_NO_WINDOW, nil, PChar(ACarpeta), SI, PI) then
    begin
      AError := SysErrorMessage(GetLastError);
      Exit;
    end;
    Result := PI.dwProcessId;
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  finally
    if HOut <> INVALID_HANDLE_VALUE then
      CloseHandle(HOut);
    if HNul <> INVALID_HANDLE_VALUE then
      CloseHandle(HNul);
  end;
end;

procedure LanzarYVigilar(const AExe, ACarpeta, ASalida, APropio, AJobId: string;
  const AArgs: TArray<string>);
var
  Linea, Vigia, Err: string;
  A: string;
  Pid: DWORD;
begin
  Linea := ComillasWin(AExe);
  for A in AArgs do
    Linea := Linea + ' ' + ComillasWin(A);
  Pid := Arrancar(Linea, ACarpeta, ASalida, True, Err);
  if Pid = 0 then
  begin
    Anade(ASalida, 'error: no pude arrancar ' + ExtractFileName(AExe) + ': ' +
      Err + #10'___RC=-1'#10);
    Exit;
  end;
  // el vigia: una copia de este programa, porque PAServer borra run-<job>.exe
  // en cuanto este proceso termina
  Vigia := ACarpeta + '\' + AJobId + '.wait.exe';
  if not CopyFile(PChar(APropio), PChar(Vigia), False) then
  begin
    Vigilar(Pid, ASalida); // sin copia posible: se espera aqui, bloqueando
    Exit;
  end;
  if Arrancar('"' + Vigia + '" --wait ' + IntToStr(Pid) + ' "' + ASalida + '"',
    ACarpeta, ASalida, False, Err) = 0 then
    Vigilar(Pid, ASalida);
end;
{$ENDIF}

var
  Propio, Carpeta, Nombre, JobId, JobFile, Exe, Salida: string;
  Args: TArray<string>;
  Lineas: TStringList;
  I: Integer;
begin
  try
{$IFDEF MSWINDOWS}
    // ---- modo vigia: run --wait <pid> <fichero de salida>
    if (ParamCount >= 3) and SameText(ParamStr(1), '--wait') then
    begin
      Vigilar(StrToIntDef(ParamStr(2), 0), ParamStr(3));
      Exit;
    end;
{$ENDIF}
    Propio := ParamStr(0);
    Carpeta := ExtractFileDir(Propio);
    Nombre := ChangeFileExt(ExtractFileName(Propio), '');
    if not Nombre.StartsWith('run-', True) then
    begin
      Writeln('McpRunJob: este programa no se usa a mano; lo sube el servidor ' +
        'MCP con el nombre run-<trabajo> junto a su run-<trabajo>.job.');
      Exit;
    end;
    JobId := Nombre.Substring(4);
    JobFile := TPath.Combine(Carpeta, Nombre + '.job');
    if not FileExists(JobFile) then
    begin
      Writeln('McpRunJob: falta ', JobFile);
      Exit;
    end;
    Lineas := TStringList.Create;
    try
      Lineas.LoadFromFile(JobFile, TEncoding.UTF8);
      if Lineas.Count < 2 then
        Exit;
      Exe := Lineas[0].Trim;
      Salida := TPath.Combine(Carpeta, Lineas[1].Trim);
      // un argumento por linea, TAL CUAL (una linea vacia es un argumento
      // vacio; el servidor no manda lineas de mas)
      SetLength(Args, Lineas.Count - 2);
      for I := 2 to Lineas.Count - 1 do
        Args[I - 2] := Lineas[I];
    finally
      Lineas.Free;
    end;
    DeleteFile(JobFile);

    // 1. el entorno / la sesion
{$IFDEF MSWINDOWS}
    if SesionPropia = 0 then
      Anade(Salida, '___ENV=0|win:0'#10)
    else
      Anade(Salida, '___ENV=1|win:' + IntToStr(SesionPropia) + #10);
{$ELSE}
    Anade(Salida, CompletaEntornoGrafico);
{$ENDIF}

    // 2. solo el binario que ese proyecto desplego, y solo si es nativo.
    //    En Windows el proyecto desplego <Proyecto>.exe y el servidor pide
    //    <Proyecto>: se admite la extension implicita, y nada mas.
    Exe := TPath.Combine(Carpeta, Exe);
{$IFDEF MSWINDOWS}
    if (not FileExists(Exe)) and FileExists(Exe + '.exe') then
      Exe := Exe + '.exe';
{$ENDIF}
    if not FileExists(Exe) then
    begin
      Anade(Salida, 'error: no existe ' + ExtractFileName(Exe) + ' en la ' +
        'carpeta desplegada de este proyecto en el target.'#10'___RC=127'#10);
      Exit;
    end;
    if not EsBinarioNativo(Exe) then
    begin
      Anade(Salida, 'RECHAZADO: ' + ExtractFileName(Exe) + ' no es un ' +
        'ejecutable nativo (ELF/PE): solo se ejecuta el binario que produjo ' +
        'delphi_build.'#10'___RC=126'#10);
      Exit;
    end;

    // 3 y 4. arrancar desatendido y dejar el vigia
{$IFDEF MSWINDOWS}
    LanzarYVigilar(Exe, Carpeta, Salida, Propio, JobId, Args);
{$ELSE}
    LanzarYVigilar(Exe, Carpeta, Salida, Args);
{$ENDIF}
  except
    on E: Exception do
      Writeln('McpRunJob: ', E.ClassName, ': ', E.Message);
  end;
end.
