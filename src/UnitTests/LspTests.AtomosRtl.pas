unit LspTests.AtomosRtl;

// Lo que matamos, lo limpiamos (Lsp.AtomosRtl): los atomos globales que un
// proceso VCL/FMX muerto sin finalizar deja en la tabla de la sesion. Con un
// pid y un hilo que NO existen (plantados a mano con la forma del RTL) se
// borran todos y solo esos; con el hilo de este mismo proceso, vivo, no se
// toca ninguno (un id reutilizado por un vivo se respeta); y los propios se
// borran aunque el proceso viva (el vigia del renderizador, que va a matarse).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtomosRtlTests = class
  public
    [Test] procedure LosDeUnProcesoMuertoSeBorranTodosYSoloEsos;
    [Test] procedure LosDeUnPidOUnHiloVivosNoSeTocan;
    [Test] procedure LosPropiosSeBorranAunqueEsteVivo;
    [Test] procedure UnMuertoSeLimpiaAunConNuestroHandleAbierto;
    [Test] procedure UnMuertoDentroDeUnJobAbiertoSeLimpia;
    [Test] procedure LoQueDejoUnHijoAcabadoPorSuCuentaSeLimpia;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Lsp.AtomosRtl;

const
  // un pid y un id de hilo que no existen (por encima de todo lo que reparte Windows)
  PID_MUERTO = $7FFFFFF0;
  TID_MUERTO = $7FFFFFF4;

function Planta(const S: string): ATOM;
begin
  Result := GlobalAddAtom(PChar(S));
  Assert.IsTrue(Result <> 0, 'plantar ' + S);
end;

procedure TAtomosRtlTests.LosDeUnProcesoMuertoSeBorranTodosYSoloEsos;
var
  Nombres: TArray<string>;
  Otro: string;
  AOtro: ATOM;
begin
  // los cinco del RTL: VCL (pid), FMX (pid_tid), ControlOfs del exe y de un
  // bpl (dos HInstance distintos) y WndProcPtr de Vcl.Dialogs
  Nombres := [Format('Delphi%.8X', [PID_MUERTO]),
    Format('FIREMONKEY%.8X_%.8X', [PID_MUERTO, TID_MUERTO]),
    Format('ControlOfs%.8X%.8X', [$00400000, TID_MUERTO]),
    Format('ControlOfs%.8X%.8X', [$6C680000, TID_MUERTO]),
    Format('WndProcPtr%.8X%.8X', [$00400000, TID_MUERTO])];
  for var N in Nombres do
    Planta(N);
  // un vecino de otro hilo (tambien muerto) se queda: no es de este proceso
  Otro := Format('ControlOfs%.8X%.8X', [$00400000, TID_MUERTO + 4]);
  AOtro := Planta(Otro);
  try
    Assert.AreEqual(5, BorraAtomosDeProceso(PID_MUERTO, TID_MUERTO), 'los cinco del muerto');
    for var N in Nombres do
      Assert.IsTrue(GlobalFindAtom(PChar(N)) = 0, 'borrado: ' + N);
    Assert.IsTrue(GlobalFindAtom(PChar(Otro)) <> 0, 'el de otro hilo se queda');
    // ya no queda nada suyo: la segunda pasada no borra
    Assert.AreEqual(0, BorraAtomosDeProceso(PID_MUERTO, TID_MUERTO), 'segunda pasada');
  finally
    GlobalDeleteAtom(AOtro);
  end;
end;

procedure TAtomosRtlTests.LosDeUnPidOUnHiloVivosNoSeTocan;
var
  N: string;
  A: ATOM;
begin
  // el hilo principal de ESTE proceso existe: aunque el pid no, nada se toca
  N := Format('ControlOfs%.8X%.8X', [$00400000, MainThreadID]);
  A := Planta(N);
  try
    Assert.AreEqual(0, BorraAtomosDeProceso(PID_MUERTO, MainThreadID), 'hilo vivo: nada');
    Assert.IsTrue(GlobalFindAtom(PChar(N)) <> 0, 'sigue');
    // y un pid vivo con un hilo que no existe, tampoco
    Assert.AreEqual(0, BorraAtomosDeProceso(GetCurrentProcessId, TID_MUERTO), 'pid vivo: nada');
  finally
    GlobalDeleteAtom(A);
  end;
end;

procedure TAtomosRtlTests.LosPropiosSeBorranAunqueEsteVivo;
var
  N: string;
  A: ATOM;
begin
  // el vigia del renderizador: el proceso va a matarse y limpia lo suyo antes.
  // Este ejecutor (consola, sin VCL ni FMX) no registra atomos del RTL: se
  // planta uno con su pid y su hilo
  N := Format('FIREMONKEY%.8X_%.8X', [GetCurrentProcessId, MainThreadID]);
  A := Planta(N);
  try
    Assert.IsTrue(BorraAtomosPropios >= 1, 'borra los propios');
    Assert.IsTrue(GlobalFindAtom(PChar(N)) = 0, 'borrado');
  finally
    if GlobalFindAtom(PChar(N)) <> 0 then
      GlobalDeleteAtom(A);
  end;
end;

{ Un proceso de verdad que no llega a ejecutar nada (suspendido y matado): un
  cmd.exe parado, con sus atomos plantados a mano con su pid y su hilo }
function ArrancaParado(out API: TProcessInformation): Boolean;
var
  SI: TStartupInfo;
  Cmd: string;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  Cmd := GetEnvironmentVariable('ComSpec');
  UniqueString(Cmd);
  FillChar(API, SizeOf(API), 0);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_SUSPENDED or CREATE_NO_WINDOW,
    nil, nil, SI, API);
end;

procedure TAtomosRtlTests.UnMuertoSeLimpiaAunConNuestroHandleAbierto;
var
  PI: TProcessInformation;
  N1, N2: string;
begin
  Assert.IsTrue(ArrancaParado(PI), 'arranca parado');
  N1 := Format('Delphi%.8X', [PI.dwProcessId]);
  N2 := Format('ControlOfs%.8X%.8X', [$00400000, PI.dwThreadId]);
  Planta(N1);
  Planta(N2);
  // vivo (parado): nada se toca
  Assert.AreEqual(0, BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId), 'vivo: nada');
  TerminateProcess(PI.hProcess, 1);
  Assert.IsTrue(WaitForSingleObject(PI.hProcess, 5000) = WAIT_OBJECT_0, 'muerto');
  // ...y su hilo: el proceso se senala antes de que el hilo deje de contestar
  // STILL_ACTIVE (medido: una de dos pasadas daba 0 sin esta espera)
  Assert.IsTrue(WaitForSingleObject(PI.hThread, 5000) = WAIT_OBJECT_0, 'su hilo, muerto');
  // con nuestros handles abiertos el proceso y su hilo siguen EXISTIENDO para
  // OpenProcess/OpenThread (medido el 19-oct-2026: la guarda por existencia
  // no borraba nunca); lo que cuenta es que han terminado
  // al menos los dos plantados: con restos en la tabla (atomos de muertos de
  // antes cuyo id de hilo coincide con el de este), se lleva esos tambien
  Assert.IsTrue(BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId) >= 2, 'muerto con handles abiertos: los dos');
  Assert.IsTrue((GlobalFindAtom(PChar(N1)) = 0) and (GlobalFindAtom(PChar(N2)) = 0), 'borrados');
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Assert.AreEqual(0, BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId), 'segunda pasada: nada');
end;

procedure TAtomosRtlTests.UnMuertoDentroDeUnJobAbiertoSeLimpia;
var
  PI: TProcessInformation;
  Job: THandle;
  N1: string;
begin
  // el camino del plazo de RunCore: el hijo va en un Job que sigue abierto
  // cuando se limpia (se cierra despues, con kill-on-close)
  Job := CreateJobObject(nil, nil);
  Assert.IsTrue(Job <> 0, 'job');
  try
    Assert.IsTrue(ArrancaParado(PI), 'arranca parado');
    Assert.IsTrue(AssignProcessToJobObject(Job, PI.hProcess), 'en el job');
    N1 := Format('Delphi%.8X', [PI.dwProcessId]);
    Planta(N1);
    TerminateProcess(PI.hProcess, 1);
    Assert.IsTrue(WaitForSingleObject(PI.hProcess, 5000) = WAIT_OBJECT_0, 'muerto');
    Assert.IsTrue(WaitForSingleObject(PI.hThread, 5000) = WAIT_OBJECT_0, 'su hilo, muerto');
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
    // el job abierto no mantiene vivo al proceso muerto: se limpia igual
    Assert.IsTrue(BorraAtomosDeProceso(PI.dwProcessId, PI.dwThreadId) >= 1, 'con el job abierto: se limpia');
    Assert.IsTrue(GlobalFindAtom(PChar(N1)) = 0, 'borrado');
  finally
    CloseHandle(Job);
  end;
end;

{ El camino de RunCore para un hijo que acabo SOLO sin finalizar (su Job lo
  mato, revento): BorraAtomosSiLosDejo limpia lo que dejo; sin su atomo de
  proceso no recorre nada (0, y rapido); y a un vivo no lo toca }
procedure TAtomosRtlTests.LoQueDejoUnHijoAcabadoPorSuCuentaSeLimpia;
var
  PI: TProcessInformation;
  N1, N2: string;
  T0: UInt64;
begin
  // un muerto que no dejo nada: ni se recorre la tabla
  T0 := GetTickCount64;
  Assert.AreEqual(0, BorraAtomosSiLosDejo(PID_MUERTO, TID_MUERTO), 'sin nada que limpiar: 0');
  Assert.IsTrue(GetTickCount64 - T0 < 50, 'sin su atomo de proceso no recorre la tabla');
  Assert.IsTrue(ArrancaParado(PI), 'arranca parado');
  N1 := Format('Delphi%.8X', [PI.dwProcessId]);
  N2 := Format('ControlOfs%.8X%.8X', [$00400000, PI.dwThreadId]);
  Planta(N1);
  Planta(N2);
  Assert.AreEqual(0, BorraAtomosSiLosDejo(PI.dwProcessId, PI.dwThreadId), 'vivo: nada');
  // muere por su cuenta (aqui, matado desde fuera: para RunCore es lo mismo)
  TerminateProcess(PI.hProcess, 1);
  Assert.IsTrue(WaitForSingleObject(PI.hProcess, 5000) = WAIT_OBJECT_0, 'muerto');
  Assert.IsTrue(WaitForSingleObject(PI.hThread, 5000) = WAIT_OBJECT_0, 'su hilo, muerto');
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Assert.IsTrue(BorraAtomosSiLosDejo(PI.dwProcessId, PI.dwThreadId) >= 2, 'lo que dejo: los dos');
  Assert.IsTrue((GlobalFindAtom(PChar(N1)) = 0) and (GlobalFindAtom(PChar(N2)) = 0), 'borrados');
  Assert.AreEqual(0, BorraAtomosSiLosDejo(PI.dwProcessId, PI.dwThreadId), 'segunda pasada: nada');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtomosRtlTests);

end.
