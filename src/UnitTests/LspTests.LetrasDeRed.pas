unit LspTests.LetrasDeRed;

// Las letras de RED de los sitios declarados, al arrancar (Lsp.NetDrives).
// Un servicio no ve las letras de red del escritorio aunque corra con la
// misma cuenta (medido el 1-oct-2026): una raiz en una letra asi fallaba en
// cada llamada y el arranque no decia nada. La regla - que letra se conecta,
// desde que mapeo, a que se entra y que se dice de cada paso - va aqui sin
// la maquina: lo que pregunta (la tabla de unidades, el registro, la red) se
// le da hecho, con nombres que no son de ninguna maquina de la casa. Que
// Windows conecte de verdad desde un servicio lo dice el log de arranque de
// un servidor instalado asi.

interface

uses
  DUnitX.TestFramework,
  Lsp.NetDrives,
  System.SyncObjs;

type
  { Una maquina de mentira: que es cada letra, que mapeos persistentes hay,
    que contesta la red, y el registro de lo que la regla pidio y de lo que
    dijo por el otro camino (las notas que ya no caben en el arranque). }
  TMaquina = class
  public
    DeRed: string;                 // letras que la sesion ya ve como de red
    Ausentes: string;              // letras que la sesion no ve
    Mapeos: TArray<string>;        // 'N=\\nas\Fuentes'
    ErroresAlConectar: TArray<Cardinal>; // lo que contesta cada intento; agotados, conecta
    OtroLaConecta: Boolean;        // Conecta contesta 85 y la letra queda de red
    NoSeEntra: TArray<string>;     // sitios que no se abren
    EntraLanza: Boolean;           // la red lanza en vez de contestar
    TardaMs: Integer;              // lo que tarda cada pregunta a la red
    Compuerta: TEvent;             // si la hay, la red no contesta hasta que se abre
    Pedido: TArray<string>;        // lo que la regla pidio, en orden
    Dichas: TArray<string>;        // las notas que llegaron por TDiceNota
    Hilo: Cardinal;                // el hilo de la prueba
    OtroHilo: Boolean;             // alguien pregunto desde otro
    function Manos: TManosDeUnidades;
    procedure Dice(const ANota: string);
    function Cuantos(const AEmpieza: string): Integer;
    function Movimiento: Integer;
    function EsperaDichas(ACuantas: Integer): Boolean;
    procedure EsperaQuieta;
    destructor Destroy; override;
  end;

  [TestFixture]
  TLetrasDeRedTests = class
  private
    FM: TMaquina;
    FPend: string;
    function Revisa(const ASitios: TArray<string>): TArray<string>;
    function Vigila(const ASitios: TArray<string>; APlazoMs: Cardinal): TArray<string>;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Recoge;
    [Test] procedure LasLetrasLocalesNoSeTocan;
    [Test] procedure LaAusenteConMapeoSeConectaYSeEntra;
    [Test] procedure LaAusenteSinMapeoAvisaYNoIntentaNada;
    [Test] procedure SiNoConectaAvisaConElErrorYQuedaPendiente;
    [Test] procedure UnErrorDeCredencialesNoSeReintenta;
    [Test] procedure SiOtroLaConectoALaVezNoEsUnAviso;
    [Test] procedure LaQueYaEsDeRedSoloSeComprueba;
    [Test] procedure ElSitioAlQueNoSeEntraEsUnAviso;
    [Test] procedure CadaLetraYCadaSitioUnaVez;
    [Test] procedure LoQueNoLlevaLetraNoEsDeAqui;
    [Test] procedure LaRaizDeLaUnidadLlevaSuBarra;
    [Test] procedure ElReintentoCallaHastaQueConecta;
    [Test] procedure ElReintentoVeLaQueConectoOtro;
    [Test] procedure ElReintentoSinMapeoDejaDeInsistir;
    [Test] procedure ElReintentoQueTopaConOtroErrorLoDiceYLoDeja;
    [Test] procedure SinLetrasDeRedNiUnHilo;
    [Test] procedure ElArranqueRecibeLasNotasDelPrimerRepaso;
    [Test] procedure LaQueNoConectaSeReintentaSolaYSeDice;
    [Test] procedure ConPlazoVencidoUnAvisoYLasNotasNoSePierden;
    [Test] procedure UnaManoQueLanzaEsUnAviso;
  end;

  { La barra final de una ruta, y la raiz que es la unidad entera: "N:" a
    secas es para Windows la carpeta ACTUAL de N:, no su raiz (medido el
    1-oct-2026: con el servidor instalado en la unidad que tenia entera por
    raiz, la raiz pasaba a ser la carpeta desde la que corria). }
  [TestFixture]
  TBarraFinalTests = class
  public
    [Test] procedure LasDosFormasDeQuitarla;
    [Test] procedure LaRutaRealDeUnaUnidadEsLaDeSuRaiz;
    [Test] procedure LaFormaLargaDeUnaUnidadEsSuRaiz;
  end;

  { La purga de una temporal con CORTE - la de una raiz en una unidad de red,
    donde el servidor de otra maquina puede estar usandola y no hay cerrojo
    que cruce -: se va lo anterior al corte y se queda lo que tenga algo
    reciente, entero. Sin corte, todo, como siempre. }
  [TestFixture]
  TPurgaConCorteTests = class
  private
    FBase, FTemp: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Recoge;
    [Test] procedure ConCorteSeQuedaLoReciente;
    [Test] procedure SinCorteSeVaTodo;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Lsp.Guard,
  Lsp.Texts;

const
  REINTENTO_DE_PRUEBA_MS = 30;

{ TMaquina }

function TMaquina.Manos: TManosDeUnidades;
begin
  Result.Clase :=
    function(ALetra: Char): TClaseDeLetra
    begin
      if GetCurrentThreadId <> Hilo then
        OtroHilo := True;
      if Pos(ALetra, Ausentes) > 0 then
        Result := clAusente
      else if Pos(ALetra, DeRed) > 0 then
        Result := clDeRed
      else
        Result := clLocal;
    end;
  Result.Recurso :=
    function(ALetra: Char): string
    var
      M: string;
    begin
      Result := '';
      TMonitor.Enter(Self);
      try
        Pedido := Pedido + ['recurso ' + ALetra];
      finally
        TMonitor.Exit(Self);
      end;
      for M in Mapeos do
        if M.StartsWith(ALetra + '=') then
          Result := M.Substring(2);
    end;
  Result.Conecta :=
    function(ALetra: Char; const ARecurso: string): Cardinal
    begin
      TMonitor.Enter(Self);
      try
        Pedido := Pedido + ['conecta ' + ALetra + ' ' + ARecurso];
      finally
        TMonitor.Exit(Self);
      end;
      if TardaMs > 0 then
        TThread.Sleep(TardaMs);
      if Assigned(Compuerta) then
        Compuerta.WaitFor(30000);
      if OtroLaConecta then
        Result := ERROR_ALREADY_ASSIGNED
      else if Length(ErroresAlConectar) > 0 then
      begin
        Result := ErroresAlConectar[0];
        Delete(ErroresAlConectar, 0, 1);
      end
      else
        Result := 0;
      // conectada (por la regla o por otro): la sesion la ve como de red
      if (Result = 0) or OtroLaConecta then
      begin
        Ausentes := Ausentes.Replace(string(ALetra), '');
        DeRed := DeRed + ALetra;
      end;
    end;
  Result.Entra :=
    function(const ASitio: string): Cardinal
    var
      S: string;
    begin
      TMonitor.Enter(Self);
      try
        Pedido := Pedido + ['entra ' + ASitio];
      finally
        TMonitor.Exit(Self);
      end;
      if TardaMs > 0 then
        TThread.Sleep(TardaMs);
      if Assigned(Compuerta) then
        Compuerta.WaitFor(30000);
      if EntraLanza then
        raise EInOutError.Create('la red se cayo');
      Result := 0;
      for S in NoSeEntra do
        if SameText(S, ASitio) then
          Result := 53;
    end;
end;

destructor TMaquina.Destroy;
begin
  Compuerta.Free;
  inherited;
end;

{ Hasta que el hilo de la regla ha ACABADO (VigilantesVivos): despues ya no
  puede pedir ni decir nada. Una condicion, no un silencio. }
function EsperaSinVigilantes: Boolean;
var
  T0: UInt64;
begin
  T0 := GetTickCount64;
  while (VigilantesVivos > 0) and (GetTickCount64 - T0 < 30000) do
    TThread.Sleep(10);
  Result := VigilantesVivos = 0;
end;

procedure TMaquina.Dice(const ANota: string);
begin
  TMonitor.Enter(Self);
  try
    Dichas := Dichas + [ANota];
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMaquina.Cuantos(const AEmpieza: string): Integer;
var
  P: string;
begin
  Result := 0;
  TMonitor.Enter(Self);
  try
    for P in Pedido do
      if P.StartsWith(AEmpieza) then
        Inc(Result);
  finally
    TMonitor.Exit(Self);
  end;
end;

{ Cuanto ha pedido y dicho la regla hasta ahora (con el candado: el hilo
  reasigna las listas). }
function TMaquina.Movimiento: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := Length(Pedido) + Length(Dichas);
  finally
    TMonitor.Exit(Self);
  end;
end;

{ Espera a que hayan llegado ACuantas notas por el otro camino: es la ultima
  cosa que hace el hilo de la regla cuando ya no le queda nada pendiente, asi
  que despues de ellas no vuelve a tocar la maquina. Una condicion, no un
  silencio: con la maquina cargada un silencio de 300 ms no decia nada. }
function TMaquina.EsperaDichas(ACuantas: Integer): Boolean;
var
  T0: UInt64;

  function Cuantas: Integer;
  begin
    TMonitor.Enter(Self);
    try
      Result := Length(Dichas);
    finally
      TMonitor.Exit(Self);
    end;
  end;

begin
  T0 := GetTickCount64;
  while (Cuantas < ACuantas) and (GetTickCount64 - T0 < 30000) do
    TThread.Sleep(20);
  Result := Cuantas >= ACuantas;
end;

{ El colchon de Recoge, para la prueba que fallo a medias: hasta que nadie
  pide ni dice nada durante un rato. }
procedure TMaquina.EsperaQuieta;
var
  N: Integer;
  T0: UInt64;
begin
  T0 := GetTickCount64;
  repeat
    N := Movimiento;
    TThread.Sleep(TardaMs + 10 * REINTENTO_DE_PRUEBA_MS);
  until (N = Movimiento) or (GetTickCount64 - T0 > 30000);
end;

function Pedidos(AM: TMaquina): string;
begin
  Result := string.Join(' | ', AM.Pedido);
end;

function EsAviso(const ANota: string): Boolean;
begin
  Result := ANota.StartsWith(SL_MARCA_AVISO);
end;

{ TLetrasDeRedTests }

procedure TLetrasDeRedTests.Prepara;
begin
  FM := TMaquina.Create;
  FM.Hilo := GetCurrentThreadId;
  FPend := '';
end;

procedure TLetrasDeRedTests.Recoge;
begin
  // (tambien si la prueba fallo a medias: el hilo no se queda sin maquina)
  if Assigned(FM.Compuerta) then
    FM.Compuerta.SetEvent;
  FM.EsperaQuieta;
  FM.Free;
end;

function TLetrasDeRedTests.Revisa(const ASitios: TArray<string>): TArray<string>;
begin
  Result := RevisaLetrasDeRed(ASitios, FM.Manos, FPend);
end;

function TLetrasDeRedTests.Vigila(const ASitios: TArray<string>;
  APlazoMs: Cardinal): TArray<string>;
begin
  Result := VigilaLetrasDeRed(ASitios, FM.Manos, APlazoMs,
    REINTENTO_DE_PRUEBA_MS, FM.Dice);
end;

procedure TLetrasDeRedTests.LasLetrasLocalesNoSeTocan;
var
  Notas: TArray<string>;
begin
  FM.Mapeos := ['D=\\nas\Otra'];
  Notas := Revisa(['D:\Proyectos\', 'C:\Sandbox\']);
  Assert.AreEqual(0, Integer(Length(Notas)), 'una letra local no deja nota');
  Assert.AreEqual('', Pedidos(FM), 'ni se mira su mapeo ni se sale a la red');
end;

procedure TLetrasDeRedTests.LaAusenteConMapeoSeConectaYSeEntra;
var
  Notas: TArray<string>;
begin
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  Notas := Revisa(['D:\Local\', 'N:\Proyectos\']);
  Assert.AreEqual('recurso N | conecta N \\nas\Fuentes | entra N:\Proyectos\',
    Pedidos(FM));
  Assert.AreEqual(2, Integer(Length(Notas)));
  Assert.IsFalse(EsAviso(Notas[0]), 'conectar no es un aviso');
  Assert.Contains(Notas[0], 'N:');
  Assert.Contains(Notas[0], 'connected to \\nas\Fuentes');
  Assert.Contains(Notas[0], 'HKCU\Network\N');
  Assert.IsFalse(EsAviso(Notas[1]), 'entrar no es un aviso');
  Assert.Contains(Notas[1], 'N:\Proyectos is reachable');
  Assert.AreEqual('', FPend, 'conectada: nada que reintentar');
end;

procedure TLetrasDeRedTests.LaAusenteSinMapeoAvisaYNoIntentaNada;
var
  Notas: TArray<string>;
begin
  FM.Ausentes := 'Q';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  Notas := Revisa(['Q:\Nada\', 'Q:\Otra\']);
  Assert.AreEqual('recurso Q', Pedidos(FM), 'sin mapeo no se conecta ni se entra');
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'HKCU\Network\Q names no share');
  Assert.Contains(Notas[0], 'Q:\Nada, Q:\Otra');
  Assert.AreEqual('', FPend, 'sin mapeo no hay a que reintentar');
end;

procedure TLetrasDeRedTests.SiNoConectaAvisaConElErrorYQuedaPendiente;
var
  Notas: TArray<string>;
begin
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.ErroresAlConectar := [53]; // no se encontro la ruta de red
  Notas := Revisa(['N:\Proyectos\']);
  Assert.AreEqual('recurso N | conecta N \\nas\Fuentes', Pedidos(FM),
    'a una letra que no se conecto no se entra');
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'Windows error 53 ');
  Assert.Contains(Notas[0], '\\nas\Fuentes');
  Assert.Contains(Notas[0], 'Declared on it: N:\Proyectos.');
  Assert.Contains(Notas[0], 'keeps trying');
  Assert.AreEqual('N', FPend, 'tiene mapeo y no conecto: se reintenta');
end;

procedure TLetrasDeRedTests.UnErrorDeCredencialesNoSeReintenta;
var
  Notas: TArray<string>;
begin
  // insistir con unas credenciales que Windows rechaza serian dos inicios de
  // sesion fallidos por minuto contra el recurso, para siempre
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.ErroresAlConectar := [1326]; // error de inicio de sesion
  Notas := Revisa(['N:\Proyectos\']);
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'Windows error 1326 ');
  Assert.Contains(Notas[0], 'does not try again');
  Assert.AreEqual('', FPend, 'solo se reintenta el error de una red que no esta');
  FM.ErroresAlConectar := [5]; // acceso denegado
  Revisa(['N:\Proyectos\']);
  Assert.AreEqual('', FPend);
end;

procedure TLetrasDeRedTests.SiOtroLaConectoALaVezNoEsUnAviso;
var
  Notas: TArray<string>;
begin
  // dos procesos de la sesion arrancan a la vez: Windows contesta al segundo
  // que la letra ya esta asignada, y es verdad
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.OtroLaConecta := True;
  Notas := Revisa(['N:\Proyectos\']);
  Assert.AreEqual('recurso N | conecta N \\nas\Fuentes | entra N:\Proyectos\',
    Pedidos(FM));
  Assert.AreEqual(2, Integer(Length(Notas)));
  Assert.IsFalse(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'something else connected it');
  Assert.Contains(Notas[1], 'N:\Proyectos is reachable');
  Assert.AreEqual('', FPend);
end;

procedure TLetrasDeRedTests.LaQueYaEsDeRedSoloSeComprueba;
var
  Notas: TArray<string>;
begin
  FM.DeRed := 'L';
  FM.Mapeos := ['L=\\servidor\Recurso'];
  Notas := Revisa(['L:\Sandbox\tests\']);
  Assert.AreEqual('entra L:\Sandbox\tests\', Pedidos(FM),
    'la que ya esta conectada ni se busca ni se conecta');
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsFalse(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'L:\Sandbox\tests is reachable');
end;

procedure TLetrasDeRedTests.ElSitioAlQueNoSeEntraEsUnAviso;
var
  Notas: TArray<string>;
begin
  FM.DeRed := 'L';
  FM.NoSeEntra := ['L:\Borrada\'];
  Notas := Revisa(['L:\Sandbox\', 'L:\Borrada\']);
  Assert.AreEqual(2, Integer(Length(Notas)));
  Assert.IsFalse(EsAviso(Notas[0]), Notas[0]);
  Assert.IsTrue(EsAviso(Notas[1]), Notas[1]);
  Assert.Contains(Notas[1], 'L:\Borrada, on network drive L:');
  Assert.Contains(Notas[1], 'Windows error 53 ');
  Assert.AreEqual('', FPend, 'la letra esta: no hay nada que reconectar');
end;

procedure TLetrasDeRedTests.CadaLetraYCadaSitioUnaVez;
begin
  // la misma raiz en dos workspaces, con otras mayusculas y sin su barra; dos
  // letras ausentes mezcladas: una conexion por letra, una entrada por sitio
  FM.Ausentes := 'NM';
  FM.Mapeos := ['N=\\nas\Fuentes', 'M=\\nas\Otra'];
  Revisa(['N:\A\', 'M:\X\', 'n:\a', 'N:\B\', 'M:\X\']);
  Assert.AreEqual(
    'recurso N | conecta N \\nas\Fuentes | entra N:\A\ | entra N:\B\ | ' +
    'recurso M | conecta M \\nas\Otra | entra M:\X\', Pedidos(FM));
end;

procedure TLetrasDeRedTests.LoQueNoLlevaLetraNoEsDeAqui;
var
  Notas: TArray<string>;
begin
  Notas := Revisa(['\\nas\Fuentes\Proyectos\', 'relativa\', '', '  ']);
  Assert.AreEqual(0, Integer(Length(Notas)));
  Assert.AreEqual('', Pedidos(FM));
end;

procedure TLetrasDeRedTests.LaRaizDeLaUnidadLlevaSuBarra;
var
  Notas: TArray<string>;
begin
  // "N:" a secas es la carpeta actual de N:, no su raiz
  Assert.AreEqual('N:\', SinBarraFinal('N:\'));
  Assert.AreEqual('N:\a', SinBarraFinal('N:\a\'));
  Assert.AreEqual('N', string(LetraDeRuta('n:\a')));
  Assert.IsTrue(LetraDeRuta('\\nas\Fuentes') = #0, 'un UNC no lleva letra');
  FM.DeRed := 'N';
  Notas := Revisa(['N:\']);
  Assert.AreEqual('entra N:\', Pedidos(FM));
  Assert.Contains(Notas[0], 'N:\ is reachable');
end;

procedure TLetrasDeRedTests.ElReintentoCallaHastaQueConecta;
var
  Notas: TArray<string>;
begin
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.ErroresAlConectar := [53, 53];
  Revisa(['N:\Proyectos\']);
  Assert.AreEqual('N', FPend);
  // otra vuelta, y sigue sin red: ni una nota (su aviso ya se dio)
  Notas := ReintentaLetrasDeRed(['N:\Proyectos\'], FM.Manos, FPend);
  Assert.AreEqual(0, Integer(Length(Notas)), 'el reintento que falla no repite el aviso');
  Assert.AreEqual('N', FPend);
  // la red llega
  Notas := ReintentaLetrasDeRed(['N:\Proyectos\'], FM.Manos, FPend);
  Assert.AreEqual(2, Integer(Length(Notas)));
  Assert.Contains(Notas[0], 'connected to \\nas\Fuentes');
  Assert.Contains(Notas[1], 'N:\Proyectos is reachable');
  Assert.AreEqual('', FPend, 'conectada: sale de la lista');
  Assert.AreEqual(3, FM.Cuantos('conecta N'));
end;

procedure TLetrasDeRedTests.ElReintentoVeLaQueConectoOtro;
var
  Notas: TArray<string>;
begin
  FM.DeRed := 'N';
  FPend := 'N';
  Notas := ReintentaLetrasDeRed(['N:\Proyectos\'], FM.Manos, FPend);
  Assert.AreEqual('entra N:\Proyectos\', Pedidos(FM), 'ya es de red: no se conecta otra vez');
  Assert.AreEqual(2, Integer(Length(Notas)));
  Assert.Contains(Notas[0], 'something else connected it');
  Assert.Contains(Notas[1], 'N:\Proyectos is reachable');
  Assert.AreEqual('', FPend);
end;

procedure TLetrasDeRedTests.ElReintentoSinMapeoDejaDeInsistir;
var
  Notas: TArray<string>;
begin
  // el operador quito el mapeo mientras tanto: no hay a que conectarla
  FM.Ausentes := 'N';
  FPend := 'N';
  Notas := ReintentaLetrasDeRed(['N:\Proyectos\'], FM.Manos, FPend);
  Assert.AreEqual('recurso N', Pedidos(FM));
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'names no share');
  Assert.AreEqual('', FPend, 'sin mapeo no se insiste');
end;

procedure TLetrasDeRedTests.ElReintentoQueTopaConOtroErrorLoDiceYLoDeja;
var
  Notas: TArray<string>;
begin
  // la red llega, y entonces Windows rechaza las credenciales
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.ErroresAlConectar := [1326];
  FPend := 'N';
  Notas := ReintentaLetrasDeRed(['N:\Proyectos\'], FM.Manos, FPend);
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'Windows error 1326 ');
  Assert.Contains(Notas[0], 'does not try again');
  Assert.AreEqual('', FPend, 'ese error no se reintenta');
end;

procedure TLetrasDeRedTests.SinLetrasDeRedNiUnHilo;
var
  Notas: TArray<string>;
begin
  Notas := Vigila(['D:\Proyectos\', '\\nas\x\'], 1000);
  Assert.AreEqual(0, Integer(Length(Notas)));
  Assert.AreEqual('', Pedidos(FM));
  Assert.IsFalse(FM.OtroHilo, 'sin letras de red no se lanza ni un hilo');
end;

procedure TLetrasDeRedTests.ElArranqueRecibeLasNotasDelPrimerRepaso;
var
  Notas: TArray<string>;
begin
  FM.Ausentes := 'N';
  FM.DeRed := 'L';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  Notas := Vigila(['N:\Proyectos\', 'L:\Sandbox\'], 5000);
  Assert.AreEqual(3, Integer(Length(Notas)));
  Assert.Contains(Notas[0], 'connected to \\nas\Fuentes');
  Assert.Contains(Notas[1], 'N:\Proyectos is reachable');
  Assert.Contains(Notas[2], 'L:\Sandbox is reachable');
  // sin letras pendientes el hilo ACABA: despues ya no puede decir nada
  Assert.IsTrue(EsperaSinVigilantes, 'el hilo de la regla no acabo');
  // cuatro preguntas (el mapeo de N, conectarla, y entrar a los dos sitios)
  // y ni una nota por el otro camino
  Assert.AreEqual(4, FM.Movimiento, 'lo que recoge el arranque no se dice dos veces');
end;

procedure TLetrasDeRedTests.LaQueNoConectaSeReintentaSolaYSeDice;
var
  Notas: TArray<string>;
begin
  // el servicio arranca antes que la red: dos intentos fallan, el tercero no
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.ErroresAlConectar := [53, 53];
  Notas := Vigila(['N:\Proyectos\'], 5000);
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'Windows error 53 ');
  Assert.IsTrue(FM.EsperaDichas(2), 'el reintento no llego a decir que conecto');
  FM.EsperaQuieta;
  Assert.AreEqual(3, FM.Cuantos('conecta N'), 'reintenta hasta conectar, y ni una vez mas');
  Assert.AreEqual(2, Integer(Length(FM.Dichas)), 'el fallo repetido no se dice; conectar, si');
  Assert.Contains(FM.Dichas[0], 'connected to \\nas\Fuentes');
  Assert.Contains(FM.Dichas[1], 'N:\Proyectos is reachable');
end;

procedure TLetrasDeRedTests.ConPlazoVencidoUnAvisoYLasNotasNoSePierden;
var
  Notas: TArray<string>;
begin
  // un recurso que NO CONTESTA (la compuerta, cerrada): el arranque espera
  // su plazo y sigue. Sin reloj: si esperase a la red, lo que volveria
  // serian las tres notas de la regla y no el aviso del plazo
  FM.DeRed := 'L';
  FM.Ausentes := 'N';
  FM.Mapeos := ['N=\\nas\Fuentes'];
  FM.Compuerta := TEvent.Create(nil, True, False, '');
  Notas := Vigila(['D:\x\', 'L:\Sandbox\', 'N:\P\'], 100);
  Assert.AreEqual(1, Integer(Length(Notas)), 'no espero a la red');
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], '(L:, N:)');
  Assert.AreEqual(0, Integer(Length(FM.Dichas)), 'la red aun no ha contestado nada');
  FM.Compuerta.SetEvent;
  // la regla acaba por su cuenta, y lo que encontro llega por el otro camino
  Assert.IsTrue(FM.EsperaDichas(3), 'las notas tardias no llegaron');
  Assert.AreEqual('entra L:\Sandbox\ | recurso N | conecta N \\nas\Fuentes | entra N:\P\',
    Pedidos(FM), 'lo que estaba haciendo lo acaba');
  Assert.AreEqual(3, Integer(Length(FM.Dichas)), 'las notas tardias no se pierden');
  Assert.Contains(FM.Dichas[0], 'L:\Sandbox is reachable');
  Assert.Contains(FM.Dichas[1], 'connected to \\nas\Fuentes');
  Assert.Contains(FM.Dichas[2], 'N:\P is reachable');
end;

procedure TLetrasDeRedTests.UnaManoQueLanzaEsUnAviso;
var
  Notas: TArray<string>;
begin
  FM.DeRed := 'L';
  FM.EntraLanza := True;
  Notas := Vigila(['L:\Sandbox\'], 5000);
  Assert.AreEqual(1, Integer(Length(Notas)));
  Assert.IsTrue(EsAviso(Notas[0]), Notas[0]);
  Assert.Contains(Notas[0], 'EInOutError');
  Assert.Contains(Notas[0], 'la red se cayo');
end;

{ TBarraFinalTests }

procedure TBarraFinalTests.LasDosFormasDeQuitarla;
begin
  // para USAR o ENSENAR una ruta: la raiz de una unidad conserva su barra
  Assert.AreEqual('N:\', SinBarraFinal('N:\'));
  Assert.AreEqual('N:\', SinBarraFinal('N:'), 'la unidad a secas es su raiz');
  Assert.AreEqual('N:\a', SinBarraFinal('N:\a\'));
  Assert.AreEqual('N:\a', SinBarraFinal('N:\a'));
  Assert.AreEqual('\\h\r', SinBarraFinal('\\h\r\'));
  Assert.AreEqual('', SinBarraFinal(''));
  // para hacer CUENTAS con el texto: sin la barra siempre
  Assert.AreEqual('N:', PrefijoSinBarra('N:\'));
  Assert.AreEqual('N:\a', PrefijoSinBarra('N:\a\'));
  // la unidad a secas, con su barra; lo demas, como viene
  Assert.AreEqual('n:\', RaizSiUnidad('n:'));
  Assert.AreEqual('N:\a\', RaizSiUnidad('N:\a\'));
  Assert.AreEqual('ab', RaizSiUnidad('ab'));
  Assert.AreEqual('1:', RaizSiUnidad('1:'), 'eso no es una unidad');
end;

{ La unidad del ejecutable de pruebas, con la carpeta ACTUAL del proceso en
  una subcarpeta suya: el caso en que "X:" y "X:\" dejan de coincidir. }
procedure EnSuUnidad(const AHaz: TProc<string>);
var
  Antes, Aqui: string;
begin
  Antes := GetCurrentDir;
  Aqui := ExtractFileDir(ParamStr(0));
  Assert.IsTrue(Length(Aqui) > 3, 'el ejecutable no esta en una subcarpeta: ' + Aqui);
  Assert.IsTrue(SetCurrentDir(Aqui), 'no se puede entrar en ' + Aqui);
  try
    AHaz(Copy(Aqui, 1, 2));
  finally
    SetCurrentDir(Antes);
  end;
end;

procedure TBarraFinalTests.LaRutaRealDeUnaUnidadEsLaDeSuRaiz;
begin
  EnSuUnidad(
    procedure(AUnidad: string)
    begin
      Assert.AreEqual(RealPath(AUnidad + '\'), RealPath(AUnidad),
        'la unidad a secas es su raiz, no la carpeta actual');
      Assert.AreNotEqual(RealPath(GetCurrentDir), RealPath(AUnidad + '\'),
        'la raiz no es la carpeta actual');
      Assert.AreNotEqual(RealPath(GetCurrentDir), RealPath(AUnidad));
    end);
end;

procedure TBarraFinalTests.LaFormaLargaDeUnaUnidadEsSuRaiz;
begin
  EnSuUnidad(
    procedure(AUnidad: string)
    begin
      // (LongCanonical es de quien salen FormaLarga y EnLugar, los
      // comparadores de sitio de la jaula)
      Assert.AreEqual(AUnidad + '\', LongCanonical(AUnidad), 'la unidad a secas');
      Assert.AreEqual(AUnidad + '\', LongCanonical(AUnidad + '\'));
      Assert.AreNotEqual(LongCanonical(GetCurrentDir), LongCanonical(AUnidad),
        'la unidad no es la carpeta actual');
    end);
end;

{ TPurgaConCorteTests }

procedure Envejece(const ARuta: string);
var
  Antes: TDateTime;
begin
  Antes := IncHour(Now, -2);
  if TDirectory.Exists(ARuta) then
  begin
    TDirectory.SetCreationTime(ARuta, Antes);
    TDirectory.SetLastWriteTime(ARuta, Antes);
  end
  else
  begin
    TFile.SetCreationTime(ARuta, Antes);
    TFile.SetLastWriteTime(ARuta, Antes);
  end;
end;

procedure TPurgaConCorteTests.Prepara;
begin
  FBase := ExtractFilePath(ParamStr(0)) + 'purga-prueba';
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
  FTemp := TPath.Combine(FBase, TempFolderName);
  // de hace dos horas: un fichero, y una carpeta con todo lo suyo
  ForceDirectories(TPath.Combine(FTemp, 'vieja'));
  TFile.WriteAllText(TPath.Combine(FTemp, 'viejo.txt'), 'x');
  TFile.WriteAllText(TPath.Combine(FTemp, 'vieja\x.txt'), 'x');
  // de ahora: un fichero, y otro TRES niveles dentro de carpetas viejas
  ForceDirectories(TPath.Combine(FTemp, 'mixta\dentro\hondo'));
  TFile.WriteAllText(TPath.Combine(FTemp, 'nuevo.txt'), 'x');
  TFile.WriteAllText(TPath.Combine(FTemp, 'mixta\viejo.txt'), 'x');
  TFile.WriteAllText(TPath.Combine(FTemp, 'mixta\dentro\hondo\nuevo.txt'), 'x');
  Envejece(TPath.Combine(FTemp, 'viejo.txt'));
  Envejece(TPath.Combine(FTemp, 'vieja\x.txt'));
  Envejece(TPath.Combine(FTemp, 'vieja'));
  Envejece(TPath.Combine(FTemp, 'mixta\viejo.txt'));
  Envejece(TPath.Combine(FTemp, 'mixta\dentro\hondo'));
  Envejece(TPath.Combine(FTemp, 'mixta\dentro'));
  Envejece(TPath.Combine(FTemp, 'mixta'));
end;

procedure TPurgaConCorteTests.Recoge;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TPurgaConCorteTests.ConCorteSeQuedaLoReciente;
begin
  VaciaDesechable(FTemp, CorteDePurga(1));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FTemp, 'viejo.txt')), 'el fichero de hace dos horas se va');
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FTemp, 'vieja')), 'la carpeta de hace dos horas se va');
  Assert.IsTrue(TFile.Exists(TPath.Combine(FTemp, 'nuevo.txt')), 'el fichero de ahora se queda');
  Assert.IsTrue(TFile.Exists(TPath.Combine(FTemp, 'mixta\dentro\hondo\nuevo.txt')),
    'lo reciente de dentro de carpetas viejas se queda');
  Assert.IsTrue(TFile.Exists(TPath.Combine(FTemp, 'mixta\viejo.txt')),
    'la carpeta con algo reciente debajo se queda ENTERA');
end;

procedure TPurgaConCorteTests.SinCorteSeVaTodo;
begin
  VaciaDesechable(FTemp);
  Assert.IsTrue(TDirectory.Exists(FTemp), 'la temporal se vacia, no se borra');
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFileSystemEntries(FTemp))), 'sin corte, todo');
end;

initialization
  TDUnitX.RegisterTestFixture(TLetrasDeRedTests);
  TDUnitX.RegisterTestFixture(TBarraFinalTests);
  TDUnitX.RegisterTestFixture(TPurgaConCorteTests);

end.
