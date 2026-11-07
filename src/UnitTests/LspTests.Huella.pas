unit LspTests.Huella;

// C30 de la 1.28: la huella de un fichero en disco (tamano y fecha de escritura)
// estaba escrita en cinco formas de texto y leida por dos lectores con la misma
// llamada (GetFileAttributesEx): DiskStamp en Lsp.ShaCache, que pregunta un enlace
// por lo de DETRAS, y HuellaDeFichero en Lsp.TodoONada, que da lo SUYO. Aqui se
// mide lo que el comentario de DiskStamp decia "leido en la RTL, no medido: esta
// cuenta no puede crear un enlace" - hoy si puede (Developer Mode), y donde no,
// se dice (NoSeMide). Crea un enlace simbolico: pasada DIRECTA de
// test_engine_dunitx (token completo), NO en PURAS.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THuellaDeFicheroTests = class
  private
    FBase, FDetras, FEnlace: string;
    // el enlace a FDetras; False (y NoSeMide) si esta cuenta no puede crearlo
    function PlantaEnlace: Boolean;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure UnEnlaceDaLaHuellaDeLoDeDetras;
    [Test] procedure LoDeDetrasRetenidoSinCompartirDaSuHuella;
    [Test] procedure UnEnlaceSigueALoDeDetrasCuandoCambia;
    [Test] procedure UnEnlaceRotoNoSeDejaPreguntar;
    [Test] procedure UnaCarpetaYLoQueNoEsta;
    [Test] procedure LoSuyoDeUnEnlaceNoSeMueveConLoDeDetras;
    [Test] procedure UnNombreDeHuellaEsCortoYDistingue;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Lsp.ShaCache,       // DiskStamp, HasStamp, STAMP_GONE, STAMP_UNKNOWN
  Lsp.Casa,           // FragmentoUnico
  LspTests.Comun;     // NoSeMide

const
  // CreateSymbolicLink sin privilegio de administrador (Developer Mode)
  SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = $2;

procedure THuellaDeFicheroTests.Prepara;
begin
  FBase := TPath.Combine(ExtractFileDir(ParamStr(0)), 'huella-' + FragmentoUnico);
  ForceDirectories(FBase);
  FDetras := TPath.Combine(FBase, 'detras.txt');
  FEnlace := TPath.Combine(FBase, 'enlace.txt');
  TFile.WriteAllBytes(FDetras, TEncoding.UTF8.GetBytes('lo de detras'));
end;

procedure THuellaDeFicheroTests.Limpia;
begin
  // el enlace, el SUYO (DeleteFile quita la entrada, no lo de detras), antes de
  // la carpeta: TDirectory.Delete recursivo no sabe quitar un enlace simbolico
  // ("The drive cannot be found", medido) y el test salia Errored por la limpieza
  if GetFileAttributes(PChar(FEnlace)) <> INVALID_FILE_ATTRIBUTES then
    Winapi.Windows.DeleteFile(PChar(FEnlace));
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

function THuellaDeFicheroTests.PlantaEnlace: Boolean;
begin
  Result := CreateSymbolicLink(PChar(FEnlace), PChar(FDetras), SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE);
  if not Result then
    NoSeMide('este proceso no puede crear un enlace simbolico en esta carpeta (' + SysErrorMessage(GetLastError) +
      '): no se mide aqui; test_engine_dunitx corre la suite desde una copia donde se mide');
end;

procedure THuellaDeFicheroTests.UnEnlaceDaLaHuellaDeLoDeDetras;
begin
  if not PlantaEnlace then
    Exit;
  Assert.IsTrue(HasStamp(DiskStamp(FDetras)), 'lo de detras tiene huella: ' + DiskStamp(FDetras));
  // la MISMA huella, en la misma forma: una huella es una, por donde se llegue
  Assert.AreEqual(DiskStamp(FDetras), DiskStamp(FEnlace), 'el enlace da la huella de lo de detras');
end;

procedure THuellaDeFicheroTests.LoDeDetrasRetenidoSinCompartirDaSuHuella;
begin
  if not PlantaEnlace then
    Exit;
  // otro proceso lo tiene abierto SIN compartir nada: la huella se pregunta
  // sin abrirlo (los atributos), y por el enlace tambien
  var Retenido := TFileStream.Create(FDetras, fmOpenRead or fmShareExclusive);
  try
    Assert.IsTrue(HasStamp(DiskStamp(FDetras)), 'retenido, lo de detras da su huella: ' + DiskStamp(FDetras));
    Assert.AreEqual(DiskStamp(FDetras), DiskStamp(FEnlace),
      'retenido sin compartir, el enlace da la huella de lo de detras');
  finally
    Retenido.Free;
  end;
end;

procedure THuellaDeFicheroTests.UnEnlaceSigueALoDeDetrasCuandoCambia;
begin
  if not PlantaEnlace then
    Exit;
  var Antes := DiskStamp(FEnlace);
  TFile.WriteAllBytes(FDetras, TEncoding.UTF8.GetBytes('lo de detras, mas largo que antes'));
  Assert.IsTrue(HasStamp(DiskStamp(FEnlace)), 'despues, tiene huella: ' + DiskStamp(FEnlace));
  Assert.AreNotEqual(Antes, DiskStamp(FEnlace), 'editar lo de detras mueve la huella del enlace');
end;

procedure THuellaDeFicheroTests.UnEnlaceRotoNoSeDejaPreguntar;
begin
  if not PlantaEnlace then
    Exit;
  TFile.Delete(FDetras);
  // el enlace ESTA (no es STAMP_GONE: quien guarda un documento por su huella
  // lo suelta con GONE y lo conserva con UNKNOWN, Lsp.Session)
  Assert.AreEqual(STAMP_UNKNOWN, DiskStamp(FEnlace), 'un enlace roto: esta y no se deja preguntar');
end;

procedure THuellaDeFicheroTests.UnaCarpetaYLoQueNoEsta;
begin
  Assert.AreEqual(STAMP_UNKNOWN, DiskStamp(FBase), 'una carpeta tiene fecha, pero no es un fichero');
  Assert.AreEqual(STAMP_GONE, DiskStamp(TPath.Combine(FBase, 'no-esta.txt')), 'lo que no esta');
end;

procedure THuellaDeFicheroTests.LoSuyoDeUnEnlaceNoSeMueveConLoDeDetras;
var
  Tam, TamDetras: Int64;
  Fecha, FechaAntes: UInt64;
begin
  if not PlantaEnlace then
    Exit;
  // lo SUYO: la entrada del enlace, tamano 0 (la foto de los escritores lo pide asi)
  Assert.IsTrue(HuellaDeFichero(FEnlace, Tam, FechaAntes, ehSuyo), 'lo suyo se lee');
  Assert.AreEqual<Int64>(0, Tam, 'lo suyo: el enlace no tiene bytes');
  // lo de DETRAS: el fichero al que lleva
  Assert.IsTrue(HuellaDeFichero(FEnlace, TamDetras, Fecha, ehDetras), 'lo de detras se lee');
  Assert.AreEqual<Int64>(Length(TEncoding.UTF8.GetBytes('lo de detras')), TamDetras, 'lo de detras: sus bytes');
  TFile.WriteAllBytes(FDetras, TEncoding.UTF8.GetBytes('lo de detras, mas largo que antes'));
  Assert.IsTrue(HuellaDeFichero(FEnlace, Tam, Fecha, ehSuyo), 'lo suyo, despues');
  Assert.AreEqual<UInt64>(FechaAntes, Fecha, 'editar lo de detras no mueve lo suyo');
  // el texto es el de la lectura (un componedor sobre un lector): fecha|tamano
  Assert.AreEqual(UIntToStr(Fecha) + '|0', DiskStamp(FEnlace, ehSuyo), 'el texto de lo suyo, de su lectura');
  Assert.AreNotEqual(DiskStamp(FDetras), DiskStamp(FEnlace, ehSuyo), 'lo suyo no es lo de detras');
end;

procedure THuellaDeFicheroTests.UnNombreDeHuellaEsCortoYDistingue;
begin
  var N := HuellaParaNombre('133000000000000000|12');
  Assert.AreEqual(16, Length(N), 'dieciseis caracteres: ' + N);
  for var C in N do
    Assert.IsTrue(CharInSet(C, ['0'..'9', 'a'..'f']), 'hex en minusculas, valido en un nombre: ' + N);
  Assert.AreEqual(N, HuellaParaNombre('133000000000000000|12'), 'la misma huella, el mismo nombre');
  Assert.AreNotEqual(N, HuellaParaNombre('133000000000000001|12'), 'otra huella, otro nombre');
end;

initialization

TDUnitX.RegisterTestFixture(THuellaDeFicheroTests);

end.
