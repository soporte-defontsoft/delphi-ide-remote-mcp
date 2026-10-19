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

implementation

uses
  System.SysUtils;

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

function Borra(APid, ATidPrincipal: DWORD): Integer;
var
  Nombre: array [0 .. 255] of Char;
begin
  Result := BorraTodasLas(Format(ATOMO_VENTANA_VCL, [APid])) +
    BorraTodasLas(Format(ATOMO_VENTANA_FMX, [APid, ATidPrincipal]));
  // ControlOfs/WndProcPtr llevan delante el HInstance, que no se sabe (el
  // exe y cada bpl cargado tienen el suyo): se buscan por el tid del final
  var Sufijo := Format('%.8X', [ATidPrincipal]);
  for var A: Integer := PRIMER_ATOMO to ULTIMO_ATOMO do
    if GlobalGetAtomName(ATOM(A), Nombre, Length(Nombre)) > 0 then
    begin
      var S := string(Nombre);
      if (S.StartsWith(ATOMO_CONTROL) or S.StartsWith(ATOMO_WNDPROC)) and
         (Length(S) > Length(ATOMO_CONTROL) + Length(Sufijo)) and S.EndsWith(Sufijo) then
        Inc(Result, BorraTodasLas(S));
    end;
end;

function BorraAtomosDeProceso(APid, ATidPrincipal: DWORD): Integer;
begin
  if ProcesoVivo(APid) or HiloVivo(ATidPrincipal) then
    Exit(0);
  Result := Borra(APid, ATidPrincipal);
end;

function BorraAtomosPropios: Integer;
begin
  Result := Borra(GetCurrentProcessId, MainThreadID);
end;

end.
