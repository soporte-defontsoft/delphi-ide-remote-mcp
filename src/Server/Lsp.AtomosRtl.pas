unit Lsp.AtomosRtl;

{ Lo que matamos, lo limpiamos. Un proceso VCL o FMX registra al arrancar
  unos atomos GLOBALES (GlobalAddAtom: la tabla de la estacion de ventanas,
  16384 entradas para todos los procesos de la sesion): Vcl.Controls
  'Delphi<pid>' y 'ControlOfs<HInstance><tid>', Vcl.Dialogs
  'WndProcPtr<HInstance><tid>', FMX.Platform.Win 'FIREMONKEY<pid>_<tid>' y
  'ControlOfs<HInstance><tid>'; y cada bpl de ejecucion que cargue (vcl, fmx)
  registra los suyos con su HInstance. Solo los borra su finalizacion: un
  proceso muerto con TerminateProcess - el que matamos por plazo, el que mata
  el Job al cerrarse, el vigia del renderizador que se mata a si mismo - los
  deja para siempre, hasta reiniciar Windows. Con la tabla llena user32 no
  inicializa NINGUN proceso nuevo (0xC0000142), ni los nuestros ni los de
  nadie: medido el 18-oct-2026, la maquina de David se cayo entera (16320 de
  16384 atomos: 3.894 servidores de bateria matados por el arnes y ~1.000
  renderizadores muertos por plazo, acumulados en 63 h).

  Windows no sabe de quien es un atomo, asi que no hay juez al que preguntar:
  la FORMA es la del RTL (Vcl.Controls.InitControls, la initialization de
  Vcl.Dialogs, FMX.Platform.Win TPlatformWin.Create), gramatica nuestra con
  esta unidad como unica casa (test_paisaje la vigila). Se borran los que
  llevan el pid o el id del hilo principal del proceso muerto, y solo si ese
  proceso y ese hilo han terminado (existir no basta: un muerto existe
  mientras alguien tenga un handle): un id reutilizado por un vivo se respeta
  (borrarle un atomo a un vivo le rompe FindControl / ObjectFromHWnd). }

interface

uses
  Winapi.Windows;

{ Los atomos del RTL que dejo el proceso APid (hilo principal ATidPrincipal)
  al morir sin finalizar. Cuantos borro; 0 si el proceso o el hilo siguen
  vivos (aun no ha terminado, o el id ya es de otro). Para llamar tras el
  TerminateProcess nuestro y su WaitForSingleObject, con o sin sus handles
  abiertos. }
function BorraAtomosDeProceso(APid, ATidPrincipal: DWORD): Integer;

{ Los de ESTE proceso, que va a matarse sin finalizar (el vigia del
  renderizador): no comprueba que este muerto, porque no lo esta. }
function BorraAtomosPropios: Integer;

{ Lo que dejo un hijo que acabo POR SU CUENTA sin finalizar: una excepcion
  sin tratar (su Job lo mata, DIE_ON_UNHANDLED_EXCEPTION), un limite del Job,
  un paquete de diseno que revienta dentro del renderizador. Medido el
  20-oct-2026: RunCore solo limpiaba lo que mataba ella, y un renderizador VCL
  muerto solo - el juez del orden de un set, que lo tolera - dejaba sus tres
  atomos y nadie los veia. Barato para el que finalizo, que es casi todos: sin
  su atomo de proceso (Delphi<pid> o FIREMONKEY<pid>_) no se recorre la
  tabla. Para llamar cuando el hijo ha terminado. Cuantos borro. }
function BorraAtomosSiLosDejo(APid, ATidPrincipal: DWORD): Integer;

type
  { Un proceso tomado VIVO antes de que lo mate otro: su pid, los ids de todos
    sus hilos y un handle a cada uno. Con los handles abiertos ningun id se
    reutiliza, asi que un atomo que lleve uno de ellos es suyo }
  TProcesoTomado = record
    Pid: DWORD;
    Proceso: THandle;
    Tids: TArray<DWORD>;
    Hilos: TArray<THandle>;
  end;

{ Los procesos APids que sigan en el Job AJob, tomados vivos con todos sus
  hilos, ANTES de que el Job los mate al cerrarse: los nietos de RunCore, de
  los que no sabemos ni el pid ni el hilo principal (Windows no dice cual es:
  se borrara lo que lleve cualquiera de sus hilos). Medido el 8-nov-2026: el
  hijo que lanza un componente dentro del renderizador dejaba sus tres atomos
  en cada render cortado por plazo. Un pid que ya no esta en el Job se salta. }
function TomaProcesosDelJob(AJob: THandle; const APids: TArray<DWORD>): TArray<TProcesoTomado>;

{ Tras matarlos: espera a cada uno y a sus hilos (APlazoMs para todos), borra
  los atomos del RTL que dejaron - solo los de un proceso que termino del todo,
  y sin recorrer la tabla por el que finalizo - y cierra los handles. Cuantos
  borro. }
function BorraAtomosDeLosTomados(var ATomados: TArray<TProcesoTomado>; APlazoMs: Cardinal): Integer;

implementation

uses
  System.SysUtils,
  Winapi.TlHelp32;

// Lo que Winapi.Windows de este Delphi no declara (como las APIs de Job en
// Lsp.BuildRunner): con su nombre real en kernel32
{$IF not declared(THREAD_QUERY_LIMITED_INFORMATION)}
const
  THREAD_QUERY_LIMITED_INFORMATION = $0800;
{$ENDIF}
{$IF not declared(PROCESS_QUERY_LIMITED_INFORMATION)}
const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;
{$ENDIF}

function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: DWORD): THandle; stdcall;
  external kernel32 name 'OpenThread';

const
  // La forma de los atomos del RTL (ver arriba): pid, pid_tid, y los dos
  // prefijos a los que siguen el HInstance (del exe o de un bpl) y el tid
  ATOMO_VENTANA_VCL = 'Delphi%.8X';
  ATOMO_VENTANA_FMX = 'FIREMONKEY%.8X_%.8X';
  ATOMO_CONTROL = 'ControlOfs';
  ATOMO_WNDPROC = 'WndProcPtr';
  // los atomos de cadena de la tabla global van de $C000 a $FFFF
  PRIMER_ATOMO = $C000;
  ULTIMO_ATOMO = $FFFF;
  // dos procesos muertos con la misma cadena = dos referencias; un tope por
  // si GlobalDeleteAtom contestara que si sin borrar
  TOPE_REFERENCIAS = 64;

{ Vivo = existe Y no ha terminado. Un proceso o un hilo muertos siguen
  EXISTIENDO para OpenProcess/OpenThread mientras alguien tenga un handle
  (nosotros, csrss, un Job): medido el 19-oct-2026, con la guarda por
  existencia el servidor no borraba nunca. Y mientras el objeto exista su id
  no se reutiliza: el que ha terminado no es de nadie. }
function HiloVivo(ATid: DWORD): Boolean;
var
  Codigo: DWORD;
begin
  var H := OpenThread(THREAD_QUERY_LIMITED_INFORMATION, False, ATid);
  if H <> 0 then
  begin
    Result := GetExitCodeThread(H, Codigo) and (Codigo = STILL_ACTIVE);
    CloseHandle(H);
    Exit;
  end;
  // 87 = no hay hilo con ese id; cualquier otro error (acceso denegado) = lo hay
  Result := GetLastError <> ERROR_INVALID_PARAMETER;
end;

function ProcesoVivo(APid: DWORD): Boolean;
var
  Codigo: DWORD;
begin
  var H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if H <> 0 then
  begin
    Result := GetExitCodeProcess(H, Codigo) and (Codigo = STILL_ACTIVE);
    CloseHandle(H);
    Exit;
  end;
  Result := GetLastError <> ERROR_INVALID_PARAMETER;
end;

function BorraTodasLas(const ANombre: string): Integer;
begin
  Result := 0;
  while Result < TOPE_REFERENCIAS do
  begin
    var A := GlobalFindAtom(PChar(ANombre));
    if A = 0 then
      Break;
    // GlobalDeleteAtom devuelve 0 si quito una referencia y el atomo si no
    if GlobalDeleteAtom(A) <> 0 then
      Break;
    Inc(Result);
  end;
end;

{ Los del proceso APid con uno de los hilos ATids: el principal cuando se sabe,
  todos los suyos cuando no (los tomados). Una sola pasada por la tabla }
function Borra(APid: DWORD; const ATids: array of DWORD): Integer;
var
  Nombre: array [0 .. 255] of Char;
  Sufijos: TArray<string>;
begin
  Result := BorraTodasLas(Format(ATOMO_VENTANA_VCL, [APid]));
  SetLength(Sufijos, Length(ATids));
  for var I := 0 to High(ATids) do
  begin
    Inc(Result, BorraTodasLas(Format(ATOMO_VENTANA_FMX, [APid, ATids[I]])));
    Sufijos[I] := Format('%.8X', [ATids[I]]);
  end;
  // ControlOfs/WndProcPtr llevan delante el HInstance, que no se sabe (el
  // exe y cada bpl cargado tienen el suyo): se buscan por el tid del final
  for var A: Integer := PRIMER_ATOMO to ULTIMO_ATOMO do
    if GlobalGetAtomName(ATOM(A), Nombre, Length(Nombre)) > 0 then
    begin
      var S := string(Nombre);
      if S.StartsWith(ATOMO_CONTROL) or S.StartsWith(ATOMO_WNDPROC) then
        for var Sufijo in Sufijos do
          if (Length(S) > Length(ATOMO_CONTROL) + Length(Sufijo)) and S.EndsWith(Sufijo) then
          begin
            Inc(Result, BorraTodasLas(S));
            Break;
          end;
    end;
end;

{ Un proceso VCL o FMX que finalizo ya quito su atomo de proceso: sin el, nada
  que mirar (ni se recorre la tabla) }
function DejoSuAtomo(APid: DWORD; const ATids: array of DWORD): Boolean;
begin
  Result := GlobalFindAtom(PChar(Format(ATOMO_VENTANA_VCL, [APid]))) <> 0;
  for var T in ATids do
    if not Result then
      Result := GlobalFindAtom(PChar(Format(ATOMO_VENTANA_FMX, [APid, T]))) <> 0;
end;

function BorraAtomosDeProceso(APid, ATidPrincipal: DWORD): Integer;
begin
  if ProcesoVivo(APid) or HiloVivo(ATidPrincipal) then
    Exit(0);
  Result := Borra(APid, [ATidPrincipal]);
end;

function BorraAtomosPropios: Integer;
begin
  Result := Borra(GetCurrentProcessId, [MainThreadID]);
end;

function BorraAtomosSiLosDejo(APid, ATidPrincipal: DWORD): Integer;
begin
  Result := 0;
  if not DejoSuAtomo(APid, [ATidPrincipal]) then
    Exit;
  Result := BorraAtomosDeProceso(APid, ATidPrincipal);
end;

function TomaProcesosDelJob(AJob: THandle; const APids: TArray<DWORD>): TArray<TProcesoTomado>;
var
  Foto: THandle;
  E: TThreadEntry32;
  EnElJob: ByteBool;
begin
  Result := [];
  for var Pid in APids do
  begin
    var H := OpenProcess(SYNCHRONIZE or PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
    if H = 0 then
      Continue;
    // el pid de la lista del Job, si entretanto murio y es de otro, fuera
    if IsProcessInJob(H, AJob, EnElJob) and EnElJob then
    begin
      var P := Default(TProcesoTomado);
      P.Pid := Pid;
      P.Proceso := H;
      Result := Result + [P];
    end
    else
      CloseHandle(H);
  end;
  if Length(Result) = 0 then
    Exit;
  // sus hilos: los que viven ahora, con el principal entre ellos (es el primero
  // que nace y no muere antes que el proceso)
  Foto := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if Foto = INVALID_HANDLE_VALUE then
    Exit;
  try
    E.dwSize := SizeOf(E);
    if Thread32First(Foto, E) then
      repeat
        for var I := 0 to High(Result) do
          if E.th32OwnerProcessID = Result[I].Pid then
          begin
            var Hilo := OpenThread(SYNCHRONIZE or THREAD_QUERY_LIMITED_INFORMATION, False, E.th32ThreadID);
            if Hilo <> 0 then
            begin
              Result[I].Tids := Result[I].Tids + [E.th32ThreadID];
              Result[I].Hilos := Result[I].Hilos + [Hilo];
            end;
            Break;
          end;
        E.dwSize := SizeOf(E);
      until not Thread32Next(Foto, E);
  finally
    CloseHandle(Foto);
  end;
end;

{ Espera a AHandle hasta AFin (GetTickCount64); True si termino }
function TerminoAntesDe(AHandle: THandle; AFin: UInt64): Boolean;
var
  Resta: UInt64;
begin
  Resta := 0;
  var Ahora := GetTickCount64;
  if Ahora < AFin then
    Resta := AFin - Ahora;
  Result := WaitForSingleObject(AHandle, DWORD(Resta)) = WAIT_OBJECT_0;
end;

function BorraAtomosDeLosTomados(var ATomados: TArray<TProcesoTomado>; APlazoMs: Cardinal): Integer;
var
  Codigo: DWORD;
begin
  Result := 0;
  var Fin := GetTickCount64 + APlazoMs;
  for var P in ATomados do
  begin
    // muerto del todo: el proceso Y sus hilos (el proceso se senala antes de
    // que su hilo principal deje de contestar STILL_ACTIVE, medido el
    // 19-oct-2026). Uno que sigue vivo no se toca
    var Muerto := TerminoAntesDe(P.Proceso, Fin) and GetExitCodeProcess(P.Proceso, Codigo) and
      (Codigo <> STILL_ACTIVE);
    for var H in P.Hilos do
      Muerto := Muerto and TerminoAntesDe(H, Fin) and GetExitCodeThread(H, Codigo) and
        (Codigo <> STILL_ACTIVE);
    // con los handles aun abiertos: ninguno de sus ids es de otro todavia
    if Muerto and DejoSuAtomo(P.Pid, P.Tids) then
      Inc(Result, Borra(P.Pid, P.Tids));
    for var H in P.Hilos do
      CloseHandle(H);
    CloseHandle(P.Proceso);
  end;
  ATomados := nil;
end;

end.
