unit LspTests.RestauraEnlaceDuro;

// H2 de la 1.23: TFotoDeFicheros.Restaura (el "todo o nada") devuelve un
// fichero cambiado por SU puerta (EscribeBytes -> AtomicWrite: un temporal al
// lado y un renombre, que ROMPE un enlace duro y nunca escribe fuera). Pero una
// ruta tan larga que no cabe con su temporal (GUARD-028) se restauraba DIRECTA
// (TFile.WriteAllBytes, en sitio) sin preguntar por los OTROS nombres del
// fichero: un enlace duro cambiaria los bytes bajo TODOS, y uno puede estar
// fuera de la jaula (GUARD-043). Segunda barrera: el reclamo directo de una ruta
// larga ahora niega un enlace duro (EscrituraEnElFicheroDenegada) y lo dice, en
// vez de escribir en sitio.
//
// No llega por una tool -el escritor que acorta (AtomicWrite) ya niega la ruta
// larga con GUARD-028, asi que una larga no se modifica por una operacion, y un
// delete o un move rompen el enlace-, asi que se mide AQUI guiando la foto a
// mano: una ruta larga con un enlace duro, cambiada, al restaurar da GUARD-043 y
// los bytes NO se tocan; control: una larga SIN enlace SI se devuelve. La raiz
// es la carpeta del exe (DELPHI_MCP_ROOTS, LspUnitTests.dpr). Crea rutas largas
// que no caben en la carpeta -ya larga- del contenedor: pasada DIRECTA de
// test_engine_dunitx (token completo), NO en PURAS.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRestauraEnlaceDuroTests = class
  private
    FBase: string;
    function RutaLarga(const ANombre: string): string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure UnaLargaConEnlaceDuroNoSeEscribeEnSitio;
    [Test] procedure UnaLargaSinEnlaceSiSeDevuelve;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Lsp.TodoONada,   // TFotoDeFicheros
  Lsp.Guard,       // RutaLargaDenegada (el juez de la ruta larga, GUARD-028)
  Lsp.Casa;        // FragmentoUnico

function TRestauraEnlaceDuroTests.RutaLarga(const ANombre: string): string;
var
  Relleno: Integer;
begin
  // bajo la raiz, lo bastante larga para que RutaLargaDenegada salte y aun
  // creable (< MAX_PATH): se rellena el nombre hasta 250 caracteres
  Relleno := 250 - Length(FBase) - Length('\') - Length(ANombre) - Length('.txt');
  if Relleno < 1 then
    Relleno := 1;
  Result := TPath.Combine(FBase, ANombre + StringOfChar('a', Relleno) + '.txt');
end;

procedure TRestauraEnlaceDuroTests.Prepara;
begin
  FBase := TPath.Combine(ExtractFileDir(ParamStr(0)), 'h2-' + FragmentoUnico);
  ForceDirectories(FBase);
end;

procedure TRestauraEnlaceDuroTests.Limpia;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TRestauraEnlaceDuroTests.UnaLargaConEnlaceDuroNoSeEscribeEnSitio;
var
  A, Enlace, Motivo: string;
  Foto: TFotoDeFicheros;
begin
  A := RutaLarga('dura');
  Assert.IsTrue(RutaLargaDenegada(A) <> '', 'la ruta de prueba es larga (si no, no se mide la rama directa)');
  TFile.WriteAllBytes(A, TEncoding.UTF8.GetBytes('ORIGINAL'));
  // un SEGUNDO nombre del mismo fichero (el que podria caer fuera de la jaula)
  Enlace := TPath.Combine(FBase, 'otro-nombre');
  Assert.IsTrue(CreateHardLink(PChar(Enlace), PChar(A), nil),
    'el enlace duro se crea: ' + SysErrorMessage(GetLastError));
  Foto.Toma([A]);                                               // la foto: ORIGINAL
  TFile.WriteAllBytes(A, TEncoding.UTF8.GetBytes('CAMBIADO'));  // la operacion lo cambia
  Motivo := Foto.Restaura;                                      // deshacer
  Assert.IsTrue(Motivo.Contains('GUARD-043'),
    'el deshacer NIEGA el enlace duro (GUARD-043) en vez de escribir en sitio: ' + Motivo);
  Assert.AreEqual('CAMBIADO', TEncoding.UTF8.GetString(TFile.ReadAllBytes(A)),
    'los bytes NO se reescribieron en sitio (la barrera los dejo como estaban)');
end;

procedure TRestauraEnlaceDuroTests.UnaLargaSinEnlaceSiSeDevuelve;
var
  A: string;
  Foto: TFotoDeFicheros;
begin
  A := RutaLarga('sola');
  Assert.IsTrue(RutaLargaDenegada(A) <> '', 'la ruta de prueba es larga');
  TFile.WriteAllBytes(A, TEncoding.UTF8.GetBytes('ORIGINAL'));
  Foto.Toma([A]);
  TFile.WriteAllBytes(A, TEncoding.UTF8.GetBytes('CAMBIADO'));
  Assert.AreEqual('', Foto.Restaura, 'una larga SIN enlace se devuelve entera (la barrera no estorba)');
  Assert.AreEqual('ORIGINAL', TEncoding.UTF8.GetString(TFile.ReadAllBytes(A)),
    'y vuelve a la foto');
end;

initialization

TDUnitX.RegisterTestFixture(TRestauraEnlaceDuroTests);

end.
