program McpRunJob;

{ EL LANZADOR para un destino WINDOWS: lo que en Linux hace el guion /bin/sh
  que escribe Lsp.RemoteRun.GuionDeEjecucion.

  PAServer en Windows no tiene interprete: el flag 5 de paclient --put es un
  CreateProcess a pelo sobre el fichero subido (un .sh "no es una aplicacion
  Win32 valida"), paclient no pasa argumentos (la orden que PAServer ejecuta
  lleva el hueco de los argumentos VACIO) y PAServer ESPERA a que termine lo
  que lanza, con paclient bloqueado mientras tanto (medido 2026-09-22). Asi
  que lo que sube con flag 5 es ESTE programa, con el nombre run-<job>.exe, y
  al lado un fichero de trabajo run-<job>.job de tres lineas -binario,
  fichero de salida, argumentos- que este programa lee y borra. Luego:

    1. escribe ___ENV= (en que SESION corre: la 0 es la de los servicios y
       no tiene escritorio, gemela del "sin DISPLAY" de Linux);
    2. comprueba que el binario es un PE (firma MZ), como el guion comprueba
       el ELF: solo se ejecuta lo que ese proyecto desplego;
    3. lo arranca DESATENDIDO con la salida en <job>.out y se va, para que
       PAServer y paclient queden libres;
    4. deja un VIGIA -una copia de si mismo, <job>.wait.exe- que espera al
       programa y remata la salida con ___RC=<codigo>, que es lo que el
       servidor sondea. El servidor barre los vigias de trabajos acabados.

  Nada se instala en el destino: PAServer borra run-<job>.exe al terminar. }

{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000; // no esta en Winapi.Windows

{ Anade texto (UTF-8) al final del fichero de salida, compartiendolo: el
  programa lanzado escribe en el mismo fichero y paclient lo lee mientras. }
procedure Anade(const AFichero, ATexto: string);
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

function SesionPropia: DWORD;
begin
  if not ProcessIdToSessionId(GetCurrentProcessId, Result) then
    Result := 0;
end;

function EsPE(const AFichero: string): Boolean;
var
  F: TFileStream;
  Firma: array[0..1] of AnsiChar;
begin
  Result := False;
  try
    F := TFileStream.Create(AFichero, fmOpenRead or fmShareDenyNone);
    try
      Result := (F.Read(Firma, 2) = 2) and (Firma[0] = 'M') and (Firma[1] = 'Z');
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
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

var
  Propio, Carpeta, Nombre, JobId, JobFile, Exe, Salida, Args, Vigia, Err: string;
  Lineas: TStringList;
  Pid: DWORD;
begin
  try
    // ---- modo vigia: run --wait <pid> <fichero de salida>
    if (ParamCount >= 3) and SameText(ParamStr(1), '--wait') then
    begin
      Vigilar(StrToIntDef(ParamStr(2), 0), ParamStr(3));
      Exit;
    end;

    Propio := ParamStr(0);
    Carpeta := ExtractFileDir(Propio);
    Nombre := ChangeFileExt(ExtractFileName(Propio), '');
    if not Nombre.StartsWith('run-', True) then
    begin
      Writeln('McpRunJob: este programa no se usa a mano; lo sube el servidor ' +
        'MCP con el nombre run-<trabajo>.exe junto a su run-<trabajo>.job.');
      Exit;
    end;
    JobId := Nombre.Substring(4);
    JobFile := Carpeta + '\' + Nombre + '.job';
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
      Salida := Carpeta + '\' + Lineas[1].Trim;
      if Lineas.Count > 2 then
        Args := Lineas[2].Trim
      else
        Args := '';
    finally
      Lineas.Free;
    end;
    DeleteFile(JobFile);

    // 1. la sesion: la 0 no tiene escritorio
    if SesionPropia = 0 then
      Anade(Salida, '___ENV=0|win:0'#10)
    else
      Anade(Salida, '___ENV=1|win:' + IntToStr(SesionPropia) + #10);

    // 2. solo el binario que ese proyecto desplego, y solo si es un PE
    if not FileExists(Carpeta + '\' + Exe) then
    begin
      Anade(Salida, 'error: no existe ' + Exe + ' en la carpeta desplegada ' +
        'de este proyecto en el target.'#10'___RC=127'#10);
      Exit;
    end;
    if not EsPE(Carpeta + '\' + Exe) then
    begin
      Anade(Salida, 'RECHAZADO: ' + Exe + ' no es un ejecutable nativo (PE): ' +
        'solo se ejecuta el binario que produjo delphi_build.'#10'___RC=126'#10);
      Exit;
    end;

    // 3. arrancar desatendido, con la salida en el fichero
    Pid := Arrancar('"' + Carpeta + '\' + Exe + '" ' + Args, Carpeta, Salida,
      True, Err);
    if Pid = 0 then
    begin
      Anade(Salida, 'error: no pude arrancar ' + Exe + ': ' + Err + #10 +
        '___RC=-1'#10);
      Exit;
    end;

    // 4. el vigia: una copia de este programa, porque PAServer borra
    //    run-<job>.exe en cuanto este proceso termina
    Vigia := Carpeta + '\' + JobId + '.wait.exe';
    if not CopyFile(PChar(Propio), PChar(Vigia), False) then
    begin
      // sin copia posible (un vigia anterior aun vivo con ese nombre): se
      // espera aqui, bloqueando PAServer, antes que perder el ___RC
      Vigilar(Pid, Salida);
      Exit;
    end;
    if Arrancar('"' + Vigia + '" --wait ' + IntToStr(Pid) + ' "' + Salida + '"',
      Carpeta, Salida, False, Err) = 0 then
      Vigilar(Pid, Salida);
  except
    on E: Exception do
      Writeln('McpRunJob: ', E.ClassName, ': ', E.Message);
  end;
end.
