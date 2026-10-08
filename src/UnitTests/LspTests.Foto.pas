unit LspTests.Foto;

{ El deshacer del "todo o nada" (Lsp.TodoONada.TFotoDeFicheros): devuelve lo que
  la operacion escribio y NO pisa lo que otro cambio despues (verificacion de
  la tercera revision, 27-sep-2026: perder una edicion ajena con OK es peor
  que un deshacer que lo dice). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFotoTests = class
  private
    FDir: string;
    function Ruta(const ANombre: string): string;
    procedure Escribe(const ANombre, ATexto: string);
    function Lee(const ANombre: string): string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure DeshaceLoQueEscribioLaOperacion;
    [Test] procedure NoPisaLoQueOtroCambioDespues;
    [Test] procedure BorraElQueCreoLaOperacion;
    [Test] procedure NoBorraElQueOtroCambioDespues;
    [Test] procedure SinAnotarDeshaceComoSiempre;
    [Test] procedure VigilaVeLoQueOtroCambioEntrePasos;
    [Test] procedure VigilaSinCambiosDeshaceComoSiempre;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Lsp.Texts,
  Lsp.TodoONada;

procedure TFotoTests.Prepara;
begin
  // junto al ejecutor: dentro de la jaula con la que lo lanza el servidor
  // de pruebas (el deshacer escribe por la puerta de escritura)
  FDir := ExtractFilePath(ParamStr(0)) + 'foto-prueba';
  ForceDirectories(FDir);
end;

procedure TFotoTests.Limpia;
begin
  for var F in TDirectory.GetFiles(FDir) do
    TFile.Delete(F);
  RemoveDir(FDir);
end;

function TFotoTests.Ruta(const ANombre: string): string;
begin
  Result := TPath.Combine(FDir, ANombre);
end;

procedure TFotoTests.Escribe(const ANombre, ATexto: string);
begin
  TFile.WriteAllText(Ruta(ANombre), ATexto, TEncoding.ASCII);
end;

function TFotoTests.Lee(const ANombre: string): string;
begin
  Result := TFile.ReadAllText(Ruta(ANombre), TEncoding.ASCII);
end;

procedure TFotoTests.DeshaceLoQueEscribioLaOperacion;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Escribe('a.txt', 'antes');
  Foto.Toma([Ruta('a.txt')]);
  Escribe('a.txt', 'la operacion');
  Foto.Anota(Ruta('a.txt'));
  R := Foto.Restaura;
  Assert.AreEqual('', R, 'todo volvio');
  Assert.AreEqual('antes', Lee('a.txt'));
end;

procedure TFotoTests.NoPisaLoQueOtroCambioDespues;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Escribe('a.txt', 'antes');
  Foto.Toma([Ruta('a.txt')]);
  Escribe('a.txt', 'la operacion');
  Foto.Anota(Ruta('a.txt'));
  Escribe('a.txt', 'otro agente');
  R := Foto.Restaura;
  Assert.AreEqual('otro agente', Lee('a.txt'), 'lo del otro se queda');
  Assert.IsTrue(R.Contains(MsgText(SF_FOTO_CAMBIADO_POR_OTRO)), 'y se dice: ' + R);
end;

procedure TFotoTests.BorraElQueCreoLaOperacion;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Foto.Toma([Ruta('b.txt')]);
  Escribe('b.txt', 'nuevo');
  Foto.Anota(Ruta('b.txt'));
  R := Foto.Restaura;
  Assert.AreEqual('', R, 'todo volvio');
  Assert.IsFalse(TFile.Exists(Ruta('b.txt')), 'el que creo la operacion se va');
end;

procedure TFotoTests.NoBorraElQueOtroCambioDespues;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Foto.Toma([Ruta('b.txt')]);
  Escribe('b.txt', 'nuevo');
  Foto.Anota(Ruta('b.txt'));
  Escribe('b.txt', 'otro agente');
  R := Foto.Restaura;
  Assert.IsTrue(TFile.Exists(Ruta('b.txt')), 'el del otro no se borra');
  Assert.AreEqual('otro agente', Lee('b.txt'));
  Assert.IsTrue(R.Contains(MsgText(SF_FOTO_CAMBIADO_POR_OTRO)), 'y se dice: ' + R);
end;

procedure TFotoTests.SinAnotarDeshaceComoSiempre;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Escribe('a.txt', 'antes');
  Foto.Toma([Ruta('a.txt')]);
  Escribe('a.txt', 'la operacion');
  R := Foto.Restaura;
  Assert.AreEqual('', R, 'todo volvio');
  Assert.AreEqual('antes', Lee('a.txt'));
end;

{ Otro escribe ENTRE dos pasos de la operacion y el segundo paso escribe
  encima: devolver la foto se llevaria lo del otro, asi que el deshacer lo
  deja y lo dice (quinta revision: Vigila antes de cada paso). }
procedure TFotoTests.VigilaVeLoQueOtroCambioEntrePasos;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Escribe('a.txt', 'antes');
  Foto.Toma([Ruta('a.txt')]);
  Escribe('a.txt', 'paso 1');
  Foto.Anota(Ruta('a.txt'));
  Escribe('a.txt', 'otro agente');
  Foto.Vigila(Ruta('a.txt'));
  Escribe('a.txt', 'paso 2 sobre lo del otro');
  Foto.Anota(Ruta('a.txt'));
  R := Foto.Restaura;
  Assert.AreEqual('paso 2 sobre lo del otro', Lee('a.txt'), 'lo del otro no se pierde');
  Assert.IsTrue(R.Contains(MsgText(SF_FOTO_CAMBIADO_DURANTE)), 'y se dice: ' + R);
end;

procedure TFotoTests.VigilaSinCambiosDeshaceComoSiempre;
var
  Foto: TFotoDeFicheros;
  R: string;
begin
  Escribe('a.txt', 'antes');
  Foto.Toma([Ruta('a.txt')]);
  Escribe('a.txt', 'paso 1');
  Foto.Anota(Ruta('a.txt'));
  Foto.Vigila(Ruta('a.txt'));
  Escribe('a.txt', 'paso 2');
  Foto.Anota(Ruta('a.txt'));
  R := Foto.Restaura;
  Assert.AreEqual('', R, 'todo volvio');
  Assert.AreEqual('antes', Lee('a.txt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFotoTests);

end.
