unit LspTests.Vigia;

// El vigia de una clave del registro (Lsp.Discovery: VigilaClave, CambioLaClave,
// CambioAlgunaClave, SueltaVigia): EL juez de "cambio la configuracion del IDE"
// para lo que el servidor cachea de ella (la zona de biblioteca, 1.21.4). Sobre
// una clave de PRUEBA propia (HKCU\Software\DelphiMcpTests\Vigia-<pid>), nunca
// la del IDE: nace en el Setup y se borra en el TearDown. Lo que midio la sonda
// del 21-oct-2026, aqui con nombre: no se senala sola; un valor escrito debajo
// o una subclave nueva senalan UNA vez y el rearme sigue vigilando; una clave
// hermana no senala; el evento sobrevive al hilo que armo
// (REG_NOTIFY_THREAD_AGNOSTIC: cada peticion del servidor es un hilo); y una
// lista pregunta y rearma a todas. No es "pura": escribe en el registro del
// usuario, asi que corre en la suite entera (test_engine_dunitx); y donde HKCU
// no se deja escribir desde el proceso (la capa virtual de un proceso MSIX: la
// bateria lanza la suite desde uno, medido el 21-oct-2026) cada prueba pasa
// diciendo que NO MIDE, como las de la ayuda o la forma 8.3 en LspTests.Docs
// y LspTests.Rutas. Lo de verdad lo mide el servicio con el IDE.

interface

uses
  DUnitX.TestFramework,
  Lsp.Discovery;

type
  [TestFixture]
  TVigiaDeClaveTests = class
  private
    FRuta: string; // la clave de prueba de ESTE proceso, relativa a HKCU
    FSinRegistro: Boolean; // HKCU no se dejo escribir en el Setup: no se mide
    procedure SiSePuede;
    procedure Escribe(const ASub, AValor, ADato: string);
    function Vigila(const ASub: string): TVigiaDeClave;
    function Senalada(var AVigia: TVigiaDeClave): Boolean;
    function Quieta(var AVigia: TVigiaDeClave): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure UnaClaveQueNoExisteNoTieneVigia;
    [Test] procedure SinCambiosNoSenala;
    [Test] procedure UnValorEscritoDebajoSenalaUnaVez;
    [Test] procedure UnaSubclaveNuevaSenala;
    [Test] procedure TrasElRearmeSigueVigilando;
    [Test] procedure UnaClaveHermanaNoSenala;
    [Test] procedure ElEventoSobreviveAlHiloQueArmo;
    [Test] procedure UnaListaPreguntaYRearmaATodas;
    [Test] procedure SueltaDejaSinVigia;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry;

const
  RAIZ = 'Software\DelphiMcpTests';
  // lo que se espera a Windows: la senal llega con la escritura, pero no se
  // le exige que sea en el mismo instante
  ESPERA_MS = 1000;
  // lo que se deja pasar para decir que NO se senalo
  REPOSO_MS = 150;

type
  // arma un vigia desde un hilo que muere en seguida
  TArmador = class(TThread)
  private
    FRuta: string;
    FVigia: TVigiaDeClave;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARuta: string);
    property Vigia: TVigiaDeClave read FVigia;
  end;

constructor TArmador.Create(const ARuta: string);
begin
  FRuta := ARuta;
  inherited Create(False);
end;

procedure TArmador.Execute;
begin
  FVigia := VigilaClave(HKEY_CURRENT_USER, FRuta);
end;

procedure TVigiaDeClaveTests.Setup;
var
  Reg: TRegistry;
begin
  FRuta := Format('%s\Vigia-%d', [RAIZ, GetCurrentProcessId]);
  // la vigilada con una subclave ya hecha (un valor escrito en ella es UN
  // cambio), y una hermana fuera de la vigilada. Sin Assert: donde no se
  // puede, se apunta y cada prueba lo dice (SiSePuede)
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    FSinRegistro := not (Reg.OpenKey(FRuta + '\Library\Win32', True) and
      Reg.OpenKey('\' + FRuta + '\Otra', True));
  finally
    Reg.Free;
  end;
end;

procedure TVigiaDeClaveTests.SiSePuede;
begin
  if FSinRegistro then
    Assert.Pass('HKCU no se deja escribir desde este proceso (capa virtual): no se mide; ' +
      'lo mide el servicio con el IDE');
end;

procedure TVigiaDeClaveTests.TearDown;
var
  Reg: TRegistry;
  Quedan: Boolean;
begin
  Reg := TRegistry.Create(KEY_ALL_ACCESS);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Reg.DeleteKey(FRuta); // con sus subclaves
    // la carpeta comun, solo si no queda nada de otro proceso
    if Reg.OpenKey(RAIZ, False) then
    begin
      Quedan := Reg.HasSubKeys;
      Reg.CloseKey;
      if not Quedan then
        Reg.DeleteKey(RAIZ);
    end;
  finally
    Reg.Free;
  end;
end;

procedure TVigiaDeClaveTests.Escribe(const ASub, AValor, ADato: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Assert.IsTrue(Reg.OpenKey(FRuta + '\' + ASub, True), 'abrir o crear ' + ASub);
    if AValor <> '' then
      Reg.WriteString(AValor, ADato);
  finally
    Reg.Free;
  end;
end;

function TVigiaDeClaveTests.Vigila(const ASub: string): TVigiaDeClave;
begin
  Result := VigilaClave(HKEY_CURRENT_USER, FRuta + '\' + ASub);
  Assert.IsTrue(Result.Clave <> 0, 'vigia de ' + ASub);
end;

function TVigiaDeClaveTests.Senalada(var AVigia: TVigiaDeClave): Boolean;
var
  T0: Cardinal;
begin
  T0 := GetTickCount;
  repeat
    if CambioLaClave(AVigia) then
      Exit(True);
    Sleep(10);
  until GetTickCount - T0 > ESPERA_MS;
  Result := False;
end;

function TVigiaDeClaveTests.Quieta(var AVigia: TVigiaDeClave): Boolean;
begin
  Sleep(REPOSO_MS);
  Result := not CambioLaClave(AVigia);
end;

procedure TVigiaDeClaveTests.UnaClaveQueNoExisteNoTieneVigia;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := VigilaClave(HKEY_CURRENT_USER, FRuta + '\NoEsta');
  Assert.IsTrue((V.Clave = 0) and (V.Evento = 0), 'sin vigia');
  Assert.IsFalse(CambioLaClave(V), 'sin vigia nunca cambia');
end;

procedure TVigiaDeClaveTests.SinCambiosNoSenala;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  try
    Assert.IsTrue(Quieta(V), 'recien armada, sin cambios');
    Assert.IsTrue(Quieta(V), 'y sigue quieta');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.UnValorEscritoDebajoSenalaUnaVez;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  try
    Escribe('Library\Win32', 'Search Path', 'C:\Uno');
    Assert.IsTrue(Senalada(V), 'un valor escrito en una subclave senala');
    Assert.IsTrue(Quieta(V), 'una vez: consumida, no vuelve');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.UnaSubclaveNuevaSenala;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  try
    Escribe('Library\Win64', '', '');
    Assert.IsTrue(Senalada(V), 'una subclave nueva (una plataforma) senala');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.TrasElRearmeSigueVigilando;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  try
    Escribe('Library\Win32', 'Search Path', 'C:\Uno');
    Assert.IsTrue(Senalada(V), 'primer cambio');
    Assert.IsTrue(Quieta(V), 'consumido');
    Escribe('Library\Win32', 'Search Path', 'C:\Uno;C:\Dos');
    Assert.IsTrue(Senalada(V), 'segundo cambio, tras el rearme');
    Assert.IsTrue(Quieta(V), 'consumido tambien');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.UnaClaveHermanaNoSenala;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  try
    Escribe('Otra', 'x', 'y');
    Assert.IsTrue(Quieta(V), 'lo que pasa fuera de la vigilada no senala');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.ElEventoSobreviveAlHiloQueArmo;
var
  T: TArmador;
  V: TVigiaDeClave;
begin
  SiSePuede;
  T := TArmador.Create(FRuta + '\Library');
  try
    T.WaitFor;
    V := T.Vigia;
  finally
    T.Free;
  end;
  try
    Assert.IsTrue(V.Clave <> 0, 'armada desde el hilo');
    Assert.IsTrue(Quieta(V), 'el hilo murio y el evento no se senalo por eso');
    Escribe('Library\Win32', 'Search Path', 'C:\Uno');
    Assert.IsTrue(Senalada(V), 'y un cambio real si senala');
  finally
    SueltaVigia(V);
  end;
end;

procedure TVigiaDeClaveTests.UnaListaPreguntaYRearmaATodas;
var
  Vs: TArray<TVigiaDeClave>;
  T0: Cardinal;
  Alguna: Boolean;
begin
  SiSePuede;
  Vs := [Vigila('Library'), Vigila('Otra')];
  try
    Escribe('Otra', 'x', 'y');
    T0 := GetTickCount;
    repeat
      Alguna := CambioAlgunaClave(Vs);
    until Alguna or (GetTickCount - T0 > ESPERA_MS);
    Assert.IsTrue(Alguna, 'un cambio en la segunda lo ve la lista');
    Sleep(REPOSO_MS);
    Assert.IsFalse(CambioAlgunaClave(Vs), 'consumido');
    // las dos a la vez: se preguntan y rearman TODAS, no solo la primera
    Escribe('Library\Win32', 'Search Path', 'C:\Uno');
    Escribe('Otra', 'x', 'z');
    T0 := GetTickCount;
    repeat
      Alguna := CambioAlgunaClave(Vs);
    until Alguna or (GetTickCount - T0 > ESPERA_MS);
    Assert.IsTrue(Alguna, 'cambio en las dos');
    Sleep(REPOSO_MS);
    Assert.IsFalse(CambioAlgunaClave(Vs), 'las dos consumidas en la misma pregunta');
  finally
    for var I := 0 to High(Vs) do
      SueltaVigia(Vs[I]);
  end;
end;

procedure TVigiaDeClaveTests.SueltaDejaSinVigia;
var
  V: TVigiaDeClave;
begin
  SiSePuede;
  V := Vigila('Library');
  SueltaVigia(V);
  Assert.IsTrue((V.Clave = 0) and (V.Evento = 0), 'suelta');
  Assert.IsFalse(CambioLaClave(V), 'sin vigia, nunca cambia');
  SueltaVigia(V); // dos veces no hace nada
end;

initialization
  TDUnitX.RegisterTestFixture(TVigiaDeClaveTests);

end.
