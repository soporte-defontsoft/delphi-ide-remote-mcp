unit LspTests.Motor;

// El cliente de un motor LSP cuando el servidor lo PARA (Lsp.Client.StopEngine):
// desde la 1.7.7 el servidor para los motores de una carpeta antes de quitarla,
// y otro agente puede tener una peticion en vuelo sobre ese motor. Se media
// por lectura que esa peticion esperaba su plazo ENTERO (30 s un hover, 60 s
// un documentSymbol) antes de dar error, y que una peticion que no llegaba a
// enviarse dejaba su entrada para siempre.
//
// El "motor" es sort.exe: lee su entrada hasta el final y no contesta nada
// mientras tanto, asi que una peticion sobre el queda en vuelo de verdad; y
// al cerrarle la entrada termina solo, que es el camino normal de la parada.
//
// Y la configuracion que el servidor FABRICA para un motor (Lsp.ConfigFabricator):
// varias primeras peticiones a la vez sobre un proyecto frio no encontraban
// cache y escribian todas el mismo fichero; las que perdian contestaban
// SYS-027, "Cannot create file" (medido una vez en el binario de la 1.7.6).
// Por HTTP el choque es demasiado raro para una bateria (dos mutaciones la
// dejaron verde): aqui los hilos salen EXACTAMENTE a la vez, ronda tras ronda.
//
// Segunda revision de la 1.7.7: el aviso de la parada despertaba a UNO de los
// que esperan una notificacion (el evento es de los que se apagan solos), y
// con dos agentes pasando el linter a dos ficheros del mismo proyecto el otro
// dormia su plazo entero y volvia con nil, que la tool lee como "sigue en
// ello, vuelve a llamar". Y una notificacion a un motor parado salia con el
// error del transporte.
//
// Y el cerrojo de lanzamiento (Lsp.Sandbox.EnterSpawn): dos hijos lanzados a
// la vez se llevaban las tuberias el uno del otro. La bateria de HTTP
// (test_lsp_paralelo) sigue verde sin el - la parada acotada basta para que el
// borrado vuelva, un segundo mas tarde -, asi que se mide AQUI, por lo que
// tarda en pararse un motor con el otro vivo.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMotorParadoTests = class
  public
    [Test] procedure LaPeticionEnVueloSeEnteraAlInstante;
    [Test] procedure TrasPararNoSeEnviaNada;
    [Test] procedure QuienEsperaUnaNotificacionTambienSeEntera;
    [Test] procedure DosQueEsperanSeEnteranLosDos;
    [Test] procedure UnaNotificacionAUnMotorParadoLoDice;
    [Test] procedure RetirarEsLaPalabraSinElProceso;
    [Test] procedure DosMotoresALaVezNoSeLlevanLasTuberias;
    [Test] procedure PararDosVecesNoHaceNada;
  end;

  [TestFixture]
  TFabricaTests = class
  private
    FDir, FLocalAppData: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure FabricarALaVezNoChoca;
    [Test] procedure ElFicheroDelIdeRechazadoSeVuelveAMirar;
    [Test] procedure BajoUnaCarpetaQueSeVaNoSeArrancaMotor;
    [Test] procedure ElPreguntadoIlegibleNoSeCallaYElOtroSeDejaParaLuego;
    [Test] procedure LosSinUsoYLosQueSeFueronSeCierran;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  Lsp.Texts,
  Lsp.Discovery,
  Lsp.ConfigFabricator,
  Lsp.Transport.Process,
  Lsp.Client,
  Lsp.Session;

const
  TOPE_MS = 5000;   // una parada sana tarda decimas; el plazo de la peticion es de 30 s
  PLAZO_MS = 30000;

function MotorMudo: TLspClient;
var
  T: TLspProcessTransport;
begin
  T := TLspProcessTransport.Create(
    IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'System32\sort.exe');
  T.Start;
  Result := TLspClient.Create(T, True);
end;

procedure TMotorParadoTests.LaPeticionEnVueloSeEnteraAlInstante;
var
  C: TLspClient;
  H: TThread;
  Dicho: string;
  T0: UInt64;
begin
  C := MotorMudo;
  try
    Dicho := '(sin terminar)';
    H := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          C.Request('textDocument/hover', '{}', PLAZO_MS).Free;
          Dicho := '(contesto)';
        except
          on E: Exception do
            Dicho := E.Message;
        end;
      end);
    H.FreeOnTerminate := False;
    try
      H.Start;
      Sleep(400); // la peticion ya esta enviada y esperando
      T0 := GetTickCount64;
      C.StopEngine;
      Assert.IsTrue(WaitForSingleObject(H.Handle, TOPE_MS) = WAIT_OBJECT_0,
        'la peticion en vuelo sigue esperando ' + IntToStr(GetTickCount64 - T0) +
        ' ms despues de parar el motor');
      Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dicho,
        'y lo que recibe es que el motor se paro, no un plazo agotado');
    finally
      H.WaitFor;
      H.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TMotorParadoTests.TrasPararNoSeEnviaNada;
var
  C: TLspClient;
  Dicho: string;
  T0: UInt64;
begin
  C := MotorMudo;
  try
    C.StopEngine;
    Assert.IsTrue(C.Stopped, 'Stopped lo dice');
    T0 := GetTickCount64;
    Dicho := '(contesto)';
    try
      C.Request('textDocument/hover', '{}', PLAZO_MS).Free;
    except
      on E: Exception do
        Dicho := E.Message;
    end;
    Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dicho);
    Assert.IsTrue(GetTickCount64 - T0 < 1000, 'sin esperar: ' + IntToStr(GetTickCount64 - T0) + ' ms');
  finally
    C.Free;
  end;
end;

procedure TMotorParadoTests.QuienEsperaUnaNotificacionTambienSeEntera;
var
  C: TLspClient;
  H: TThread;
  Dicho: string;
begin
  C := MotorMudo;
  try
    Dicho := '(sin terminar)';
    H := TThread.CreateAnonymousThread(
      procedure
      var
        N: TJSONObject;
      begin
        try
          N := C.WaitForNotification('textDocument/publishDiagnostics', PLAZO_MS);
          N.Free;
          Dicho := '(volvio sin error)';
        except
          on E: Exception do
            Dicho := E.Message;
        end;
      end);
    H.FreeOnTerminate := False;
    try
      H.Start;
      Sleep(400);
      C.StopEngine;
      Assert.IsTrue(WaitForSingleObject(H.Handle, TOPE_MS) = WAIT_OBJECT_0,
        'quien espera la notificacion sigue esperando tras parar el motor');
      Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dicho);
    finally
      H.WaitFor;
      H.Free;
    end;
  finally
    C.Free;
  end;
end;

function HiloQueEspera(AClient: TLspClient; ADichos: TStrings; ACerrojo: TCriticalSection): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      N: TJSONObject;
      Dicho: string;
    begin
      try
        N := AClient.WaitForNotification('textDocument/publishDiagnostics', PLAZO_MS);
        N.Free;
        Dicho := '(volvio sin error)';
      except
        on E: Exception do
          Dicho := E.Message;
      end;
      ACerrojo.Enter;
      try
        ADichos.Add(Dicho);
      finally
        ACerrojo.Leave;
      end;
    end);
  Result.FreeOnTerminate := False;
end;

procedure TMotorParadoTests.DosQueEsperanSeEnteranLosDos;
var
  C: TLspClient;
  H1, H2: TThread;
  Dichos: TStringList;
  Cerrojo: TCriticalSection;
  T0: UInt64;
begin
  C := MotorMudo;
  Dichos := TStringList.Create;
  Cerrojo := TCriticalSection.Create;
  try
    H1 := HiloQueEspera(C, Dichos, Cerrojo);
    H2 := HiloQueEspera(C, Dichos, Cerrojo);
    try
      H1.Start;
      H2.Start;
      Sleep(400); // los dos esperando
      T0 := GetTickCount64;
      C.StopEngine;
      Assert.IsTrue(WaitForSingleObject(H1.Handle, TOPE_MS) = WAIT_OBJECT_0,
        'el primero sigue esperando tras parar el motor');
      Assert.IsTrue(WaitForSingleObject(H2.Handle, TOPE_MS) = WAIT_OBJECT_0,
        'el segundo sigue esperando ' + IntToStr(GetTickCount64 - T0) +
        ' ms despues de parar el motor: el aviso desperto a uno solo');
      Assert.AreEqual(2, Dichos.Count);
      Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dichos[0]);
      Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dichos[1]);
    finally
      // sin el arreglo el segundo duerme su plazo: se le espera igual, que
      // corre sobre el cliente que se libera abajo
      H1.WaitFor;
      H2.WaitFor;
      H1.Free;
      H2.Free;
    end;
  finally
    Cerrojo.Free;
    Dichos.Free;
    C.Free;
  end;
end;

procedure TMotorParadoTests.UnaNotificacionAUnMotorParadoLoDice;
var
  C: TLspClient;
  Dicho: string;
begin
  C := MotorMudo;
  try
    C.StopEngine;
    Dicho := '(se envio)';
    try
      C.DidOpenText('file:///c:/nada/U.pas', 'unit U;');
    except
      on E: Exception do
        Dicho := E.Message;
    end;
    Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dicho,
      'una notificacion (didOpen) a un motor parado');
  finally
    C.Free;
  end;
end;

procedure TMotorParadoTests.RetirarEsLaPalabraSinElProceso;
var
  T: TLspProcessTransport;
  C: TLspClient;
  Dicho: string;
begin
  T := TLspProcessTransport.Create(
    IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'System32\sort.exe');
  T.Start;
  C := TLspClient.Create(T, True);
  try
    C.Retire;
    Assert.IsTrue(C.Stopped, 'retirado es parado, para quien pregunta');
    Assert.IsTrue(T.ProcessAlive, 'y el proceso sigue: pararlo tarda, y se hace despues');
    Dicho := '(contesto)';
    try
      C.Request('textDocument/hover', '{}', PLAZO_MS).Free;
    except
      on E: Exception do
        Dicho := E.Message;
    end;
    Assert.AreEqual(MsgText(SR_LSP_ENGINE_STOPPED), Dicho, 'nada mas se le envia');
    // (que la parada acaba con el proceso no se puede preguntar aqui: tras
    // CUALQUIER parada el transporte ya no tiene el proceso, y dice que no)
  finally
    C.Free;
  end;
end;

function HiloQueArranca(ATransport: TLspProcessTransport; ASalida: TEvent): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      ASalida.WaitFor(5000);
      try
        ATransport.Start;
      except
        // lo dice ProcessAlive, abajo
      end;
    end);
  Result.FreeOnTerminate := False;
end;

{ Dos motores lanzados A LA VEZ; se para uno con el otro vivo y se dice lo que
  tardo esa parada, en ms. AElSegundo: cual de los dos se para. }
function ParadaConElOtroVivo(const AMotor: string; AElSegundo: Boolean): UInt64;
var
  A, B: TLspProcessTransport;
  HA, HB: TThread;
  Salida: TEvent;
  T0: UInt64;
begin
  A := TLspProcessTransport.Create(AMotor);
  B := TLspProcessTransport.Create(AMotor);
  Salida := TEvent.Create(nil, True, False, '');
  try
    HA := HiloQueArranca(A, Salida);
    HB := HiloQueArranca(B, Salida);
    try
      HA.Start;
      HB.Start;
      Sleep(20); // los dos en la salida
      Salida.SetEvent;
    finally
      HA.WaitFor;
      HB.WaitFor;
      HA.Free;
      HB.Free;
    end;
    Assert.IsTrue(A.ProcessAlive and B.ProcessAlive, 'los dos motores arrancan');
    Sleep(100); // arrancados del todo: lo que se mide es la parada
    T0 := GetTickCount64;
    if AElSegundo then
      B.Stop
    else
      A.Stop;
    Result := GetTickCount64 - T0;
  finally
    Salida.Free;
    A.Free;
    B.Free;
  end;
end;

procedure TMotorParadoTests.DosMotoresALaVezNoSeLlevanLasTuberias;
const
  N_RONDAS = 40;
  // Una ronda suelta por encima del tope puede ser la maquina (las baterias
  // corren varias a la vez); tres, no. Sin el cerrojo de lanzamiento son
  // muchas: medido el 29-sep-2026, la tercera ronda ya era lenta.
  LENTAS_DE_MAS = 3;
var
  R, Lentas: Integer;
  Tarda, Tope, Peor: UInt64;
  Motor: string;
begin
  Motor := IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'System32\sort.exe';
  // Una parada sana tarda decimas. Con la salida del motor en manos del
  // otro, su lector no ve el final: la parada lo espera READER_EOF_WAIT_MS y
  // lo cancela. El tope sale de ESA constante: escrito a mano, el dia que
  // la espera bajase la prueba pasaria sin medir.
  Tope := READER_EOF_WAIT_MS - 100;
  Lentas := 0;
  Peor := 0;
  for R := 1 to N_RONDAS do
  begin
    // una ronda cada uno: el que arranco primero es el que pudo dejarle sus
    // extremos al otro, y no se sabe cual fue
    Tarda := ParadaConElOtroVivo(Motor, Odd(R));
    if Tarda > Peor then
      Peor := Tarda;
    if Tarda >= Tope then
      Inc(Lentas);
    Assert.IsTrue(Lentas < LENTAS_DE_MAS, Format(
      'ronda %d de %d: %d paradas de un motor con el otro vivo han tardado %d ms o mas ' +
      '(la peor, %d): el otro se llevo su tuberia', [R, N_RONDAS, Lentas, Tope, Peor]));
  end;
end;

procedure TMotorParadoTests.PararDosVecesNoHaceNada;
var
  C: TLspClient;
  T0: UInt64;
begin
  C := MotorMudo;
  try
    C.StopEngine;
    T0 := GetTickCount64;
    C.StopEngine; // la sesion lo para al retirarlo y el destructor otra vez
    Assert.IsTrue(GetTickCount64 - T0 < 1000, 'la segunda parada no espera a nada');
  finally
    C.Free;
  end;
end;

{ TFabricaTests }

procedure TFabricaTests.Prepara;
begin
  // junto al ejecutor: dentro de la jaula (y de la etiqueta de integridad
  // baja) con la que lo lanza el servidor de pruebas. La cache de
  // configuraciones cuelga de LOCALAPPDATA: para esta prueba, de aqui.
  FDir := ExtractFilePath(ParamStr(0)) + 'fabrica-prueba';
  ForceDirectories(FDir + '\proyecto');
  FLocalAppData := GetEnvironmentVariable('LOCALAPPDATA');
  SetEnvironmentVariable('LOCALAPPDATA', PChar(FDir));
  TFile.WriteAllText(FDir + '\proyecto\P.dproj',
    '<Project><PropertyGroup><MainSource>P.dpr</MainSource></PropertyGroup></Project>');
  TFile.WriteAllText(FDir + '\proyecto\P.dpr', 'program P;' + sLineBreak + 'begin' +
    sLineBreak + 'end.' + sLineBreak);
end;

procedure TFabricaTests.Limpia;
begin
  // si una prueba dejo un motor bajo la carpeta, se para (lo normal: ninguno)
  TLspSession.FolderLeaves(FDir, True);
  TLspSession.FolderLeaves(FDir, False);
  SetEnvironmentVariable('LOCALAPPDATA', PChar(FLocalAppData));
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True); // la carpeta de la prueba, que es suya
end;

function HiloQueFabrica(const ADproj: string; const AInfo: TRadStudioInfo;
  ASalida: TEvent; AErrores: TStrings; ACerrojo: TCriticalSection): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      ASalida.WaitFor(5000);
      try
        FabricateSettings(ADproj, AInfo);
      except
        on E: Exception do
        begin
          ACerrojo.Enter;
          try
            AErrores.Add(E.ClassName + ': ' + E.Message);
          finally
            ACerrojo.Leave;
          end;
        end;
      end;
    end);
  Result.FreeOnTerminate := False;
end;

procedure TFabricaTests.FabricarALaVezNoChoca;
const
  N_HILOS = 8;
  N_RONDAS = 40;
var
  Info: TRadStudioInfo;
  Dproj, Cache, F: string;
  Salida: TEvent;
  Cerrojo: TCriticalSection;
  Errores: TStringList;
  Hilos: array [0 .. N_HILOS - 1] of TThread;
  R, I: Integer;
begin
  Info := DiscoverRadStudio;
  Assert.IsTrue(Info.Found, 'sin RAD Studio en la maquina no hay nada que fabricar');
  Dproj := FDir + '\proyecto\P.dproj';
  Cache := FDir + '\DelphiLspMcp\configs';
  Errores := TStringList.Create;
  Cerrojo := TCriticalSection.Create;
  try
    for R := 1 to N_RONDAS do
    begin
      // fuera la cache: todos la encuentran sin hacer, como en el primer toque
      if TDirectory.Exists(Cache) then
        for F in TDirectory.GetFiles(Cache) do
          TFile.Delete(F);
      Salida := TEvent.Create(nil, True, False, '');
      try
        for I := 0 to N_HILOS - 1 do
        begin
          Hilos[I] := HiloQueFabrica(Dproj, Info, Salida, Errores, Cerrojo);
          Hilos[I].Start;
        end;
        Sleep(30); // todos en la salida
        Salida.SetEvent;
        for I := 0 to N_HILOS - 1 do
        begin
          Hilos[I].WaitFor;
          Hilos[I].Free;
        end;
      finally
        Salida.Free;
      end;
      Assert.AreEqual(0, Errores.Count, Format('ronda %d de %d, %d hilos a la vez: %s',
        [R, N_RONDAS, N_HILOS, Errores.Text.Trim]));
      Assert.IsTrue(Length(TDirectory.GetFiles(Cache, '*.delphilsp.json')) = 1,
        'y queda UNA configuracion');
      Assert.IsTrue(Length(TDirectory.GetFiles(Cache)) = 1,
        'ni un temporal de la escritura se queda');
    end;
  finally
    Cerrojo.Free;
    Errores.Free;
  end;
end;

// La configuracion de un proyecto se resuelve una vez y se recuerda mientras
// no cambie el fichero que la decidio. Con un .delphilsp.json del IDE que se
// RECHAZA (caducado, o leido a medio escribir) decide el .dproj, y el del IDE
// no se volvia a mirar hasta que cambiase el .dproj: el IDE lo dejaba entero
// un momento despues y el servidor seguia con la fabricada (tercera revision
// de la 1.7.7, leido en el codigo; esta prueba lo mide).
procedure TFabricaTests.ElFicheroDelIdeRechazadoSeVuelveAMirar;
var
  Dpr, Ide, Raiz, Primera, Segunda: string;
begin
  Assert.IsTrue(DiscoverRadStudio.Found, 'sin RAD Studio en la maquina no hay nada que fabricar');
  Dpr := FDir + '\proyecto\P.dpr';
  Ide := FDir + '\proyecto\P.delphilsp.json';
  TFile.WriteAllText(Ide, '{"settings": {"project": "file:///'); // a medio escribir
  Primera := TLspSession.Instance.ResolveSettings(Dpr, Raiz);
  Assert.IsTrue(Primera <> '', 'con el del IDE a medias, se fabrica desde el .dproj');
  Assert.IsFalse(SameText(Primera, Ide), 'y el del IDE, a medias, no se usa');
  TFile.WriteAllText(Ide, Format('{"settings": {"project": "%s", "dllname": ""}}',
    [TLspClient.PathToUri(Dpr)]));
  Segunda := TLspSession.Instance.ResolveSettings(Dpr, Raiz);
  Assert.IsTrue(SameText(Segunda, Ide),
    'el del IDE, ya entero, es el que vale; y se sigue con: ' + Segunda);
end;

// Entre los dos avisos de una carpeta que se va no se arranca ningun motor
// debajo: la primera peticion de otro agente recibe LSP-032 y no llega a
// lanzar nada (el motor que arrancaba en ese rato volvia a retener la
// carpeta). La bateria de HTTP (P4, test_lsp_paralelo) lo mide si alguna
// ronda pilla el momento, y si no deja una NOTA: aqui el momento es fijo.
// Que no se construyo un motor se sabe por el tiempo: uno con configuracion
// tarda mas de segundo y medio en estar (cuarta revision de la 1.7.7).
procedure TFabricaTests.BajoUnaCarpetaQueSeVaNoSeArrancaMotor;
var
  Dpr, Usado, Dicho, Raiz: string;
  T0, Tardo: UInt64;
begin
  Assert.IsTrue(DiscoverRadStudio.Found, 'sin RAD Studio en la maquina no hay nada que fabricar');
  Dpr := FDir + '\proyecto\P.dpr';
  Dicho := 'no se nego';
  // la configuracion, fabricada ANTES de poner el reloj: es de la primera
  // peticion de un proyecto, no de la negativa que se mide
  Assert.IsTrue(TLspSession.Instance.ResolveSettings(Dpr, Raiz) <> '',
    'el proyecto tiene su configuracion: con ella, construir un motor pasa del segundo y medio');
  TLspSession.FolderLeaves(FDir + '\proyecto', True);
  try
    T0 := GetTickCount64;
    try
      TLspSession.Instance.AcquireFor(Dpr, Usado);
    except
      on E: Exception do
        Dicho := E.Message;
    end;
    Tardo := GetTickCount64 - T0;
  finally
    TLspSession.FolderLeaves(FDir + '\proyecto', False);
  end;
  Assert.IsTrue(Dicho.StartsWith('[LSP-032'), 'con la carpeta saliendo, LSP-032; y dijo: ' + Dicho);
  Assert.IsTrue(Tardo < 1000,
    Format('y se niega ANTES de construir ningun motor (tardo %d ms)', [Tardo]));
end;

// El fichero por el que se pregunta, editado en disco y ademas ilegible en
// ese instante (otro proceso lo tiene abierto en exclusiva): antes de la
// 1.7.8 AcquireFor lo decia y la tool contestaba un error. Al poner al dia
// TODOS los documentos abiertos del motor, lo ilegible de los OTROS se deja
// para la siguiente peticion - la pregunta no es sobre ellos -, pero lo del
// preguntado se sigue diciendo: callarlo seria contestar sobre el texto
// viejo, en silencio (primer revisor de la 1.7.8). Se mide con el fichero
// abierto en exclusiva desde aqui.
procedure TFabricaTests.ElPreguntadoIlegibleNoSeCallaYElOtroSeDejaParaLuego;
var
  Dpr, Unidad, Usado, Dicho: string;
  H: THandle;
begin
  Assert.IsTrue(DiscoverRadStudio.Found, 'sin RAD Studio en la maquina no hay motor que abrir');
  Dpr := FDir + '\proyecto\P.dpr';
  Unidad := FDir + '\proyecto\U.pas';
  TFile.WriteAllText(Unidad, 'unit U;' + sLineBreak + 'interface' + sLineBreak +
    'implementation' + sLineBreak + 'end.' + sLineBreak);
  // los dos abiertos en el motor (el primero lo arranca)
  TLspSession.Instance.AcquireFor(Dpr, Usado);
  TLspSession.Instance.AcquireFor(Unidad, Usado);
  // los dos cambian en disco, y la unidad queda ilegible para todos
  TFile.AppendAllText(Dpr, '// cambio' + sLineBreak);
  TFile.AppendAllText(Unidad, '// cambio' + sLineBreak);
  H := CreateFile(PChar(Unidad), GENERIC_READ, 0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Assert.IsTrue(H <> INVALID_HANDLE_VALUE, 'la unidad se abre en exclusiva desde la prueba');
  try
    // preguntar por el .dpr: la unidad ilegible es de los OTROS y se deja
    TLspSession.Instance.AcquireFor(Dpr, Usado);
    // preguntar por la unidad: es la preguntada, y se dice
    Dicho := 'no se dijo';
    try
      TLspSession.Instance.AcquireFor(Unidad, Usado);
    except
      on E: Exception do
        Dicho := E.Message;
    end;
    Assert.AreNotEqual('no se dijo', Dicho, 'el preguntado ilegible se dice, no se contesta sobre lo viejo');
  finally
    CloseHandle(H);
  end;
  // legible otra vez: la siguiente peticion la pone al dia y pasa
  TLspSession.Instance.AcquireFor(Unidad, Usado);
end;

// Un documento del que nadie pregunta en un rato se cierra (el motor lee del
// disco, al dia, la unidad que no tiene abierta: medido 30-sep-2026), y uno
// cuyo fichero se fue tambien: abierto, el motor seguia contestando
// definitions HACIA el (UCalc.pas:8 sin UCalc.pas en el disco, medido el
// mismo dia). El preguntado no se cierra nunca. Se mide por lo que el motor
// tiene abierto (OpenDocuments), con el plazo acortado.
procedure TFabricaTests.LosSinUsoYLosQueSeFueronSeCierran;
var
  Dpr, Unidad, Usado: string;
  Antes: UInt64;
begin
  Assert.IsTrue(DiscoverRadStudio.Found, 'sin RAD Studio en la maquina no hay motor que abrir');
  Dpr := FDir + '\proyecto\P.dpr';
  Unidad := FDir + '\proyecto\U.pas';
  TFile.WriteAllText(Unidad, 'unit U;' + sLineBreak + 'interface' + sLineBreak +
    'implementation' + sLineBreak + 'end.' + sLineBreak);
  Antes := LspDocIdleMs;
  try
    TLspSession.Instance.AcquireFor(Dpr, Usado);
    TLspSession.Instance.AcquireFor(Unidad, Usado);
    Assert.AreEqual(2, TLspSession.Instance.OpenDocuments(Dpr), 'los dos abiertos');
    // El plazo corto SOLO para este paso, y lejos del medio segundo de
    // margen de indexado que lleva cada apertura (segundo revisor de la
    // 1.7.9: con 700 ms en toda la prueba habia 200 de margen a cada lado, y
    // el ultimo paso podia pasar por el cierre de inactivos sin el del
    // fichero que se fue).
    LspDocIdleMs := 1500;
    Sleep(2000);
    TLspSession.Instance.AcquireFor(Dpr, Usado);
    LspDocIdleMs := Antes;
    Assert.AreEqual(1, TLspSession.Instance.OpenDocuments(Dpr), 'la unidad sin uso se cerro; queda el preguntado');
    TLspSession.Instance.AcquireFor(Unidad, Usado);
    Assert.AreEqual(2, TLspSession.Instance.OpenDocuments(Dpr), 'preguntada otra vez, abierta otra vez');
    // Una CARPETA con su nombre: algo hay, pero no se le puede preguntar
    // (STAMP_UNKNOWN). Eso NO se cierra: se mira otra vez en la siguiente.
    TFile.Delete(Unidad);
    TDirectory.CreateDirectory(Unidad);
    TLspSession.Instance.AcquireFor(Dpr, Usado);
    Assert.AreEqual(2, TLspSession.Instance.OpenDocuments(Dpr), 'lo que no se puede preguntar no se cierra');
    TDirectory.Delete(Unidad);
    TLspSession.Instance.AcquireFor(Dpr, Usado);
    Assert.AreEqual(1, TLspSession.Instance.OpenDocuments(Dpr), 'la unidad cuyo fichero se fue se cerro');
  finally
    LspDocIdleMs := Antes;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMotorParadoTests);
  TDUnitX.RegisterTestFixture(TFabricaTests);

end.
