unit LspTests.Dproj;

{ El escaner de peligros de un .dproj antes de compilarlo: lo que delphi_build
  rechaza (tareas que ejecutan) y lo que SALTA en vez de rechazar (los eventos
  pre/post build de la build firmada, decision de David del 24-sep-2026). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDprojHazardTests = class
  public
    [Test] procedure ProyectoLimpioNoTienePeligro;
    [Test] procedure EventoDeBuildEsPeligro;
    [Test] procedure EventoDeBuildSeIgnoraSiSePide;
    [Test] procedure EventoVacioNoEsPeligro;
    [Test] procedure UnaTareaExecEsPeligroAunqueSeIgnorenEventos;
    [Test] procedure ImportConComillasSimplesSeComprueba;
    [Test] procedure ImportConEspaciosSeComprueba;
    [Test] procedure ImportConComillasDoblesSeComprueba;
    [Test] procedure ImportConEntidadesSeComprueba;
    [Test] procedure DeployprojLocalSeComprueba;
    [Test] procedure NombreParecidoAUserToolsSeComprueba;
  end;

  { UN escritor del texto de un elemento (XmlElemento) y sus lectores, que
    devuelven el valor de verdad: una ruta de una carpeta R&D rompia el
    .dproj o el .profile, o se leia con sus &amp; (26-sep-2026). }
  [TestFixture]
  TXmlTextoTests = class
  public
    [Test] procedure ElLectorEsLaInversaDelEscritor;
    [Test] procedure RutasDeBusquedaResueltasYDesescapadas;
    [Test] procedure TrozosEscritosNoPartenUnaEntidad;
    [Test] procedure TagValueNoDistingueMayusculas;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Lsp.Dproj;

const
  RUTA = 'C:\Proyecto\App.dproj';
  CABECERA = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup>'#13#10;
  PIE = '</Project>'#13#10;

procedure TDprojHazardTests.ProyectoLimpioNoTienePeligro;
begin
  Assert.AreEqual('', DprojBuildHazard(CABECERA + PIE, RUTA));
end;

procedure TDprojHazardTests.EventoDeBuildEsPeligro;
var
  R: string;
begin
  R := DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PostBuildEvent>signtool sign $(OUTPUTPATH)</PostBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA);
  Assert.AreNotEqual('', R);
  Assert.IsTrue(Pos('postbuildevent', R) > 0, 'nombra el evento: ' + R);
end;

procedure TDprojHazardTests.EventoDeBuildSeIgnoraSiSePide;
begin
  // delphi_build vacia los eventos en la linea de msbuild y avisa: la build
  // es para trabajar, la firmada es del operador fuera del servidor.
  Assert.AreEqual('', DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PreBuildEvent>copy a b</PreBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA, True));
end;

procedure TDprojHazardTests.EventoVacioNoEsPeligro;
begin
  Assert.AreEqual('', DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PreBuildEvent></PreBuildEvent><PostBuildEvent>  </PostBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA));
end;

procedure TDprojHazardTests.UnaTareaExecEsPeligroAunqueSeIgnorenEventos;
var
  R: string;
begin
  R := DprojBuildHazard(CABECERA +
    '  <Target Name="Rompe" BeforeTargets="Build"><Exec Command="cmd /c del *.*"/></Target>'#13#10 +
    PIE, RUTA, True);
  Assert.AreNotEqual('', R, 'ignorar eventos no abre la puerta a las tareas');
  Assert.IsTrue(Pos('exec', R) > 0, 'nombra la tarea: ' + R);
end;

procedure TXmlTextoTests.ElLectorEsLaInversaDelEscritor;
const
  // &lt; y comillas simples: con &amp; desescapado el primero, el &amp;lt;
  // que escribe XmlEscape volvia como '<' (revision 26-sep)
  VALOR = '..\R&D\lib;<x>"y";&lt;''z'';$(DCC_UnitSearchPath)';
var
  Xml: string;
begin
  Xml := '<Project><PropertyGroup>' + XmlElemento('DCC_UnitSearchPath', VALOR) +
    '</PropertyGroup></Project>';
  Assert.IsFalse(Xml.Contains('R&D') or Xml.Contains('<x>'), 'escrito sin escapar: ' + Xml);
  Assert.AreEqual(VALOR, TagValue(Xml, 'DCC_UnitSearchPath'), 'TagValue');
  Assert.AreEqual(VALOR, AllTagValues(Xml, 'DCC_UnitSearchPath')[0], 'AllTagValues');
  Assert.AreEqual(VALOR.Replace(';$(DCC_UnitSearchPath)', ';'),
    MergeProperty(Xml, 'DCC_UnitSearchPath'), 'MergeProperty');
end;

procedure TXmlTextoTests.RutasDeBusquedaResueltasYDesescapadas;
var
  R: TArray<TRutaDeBusqueda>;
begin
  // la macro sin resolver no cuenta; R&amp;D es R&D; lo relativo, contra el .dproj
  R := RutasDeBusqueda('C:\p\App.dproj',
    '<Project><PropertyGroup><DCC_UnitSearchPath>..\lib;$(BDS)\x;R&amp;D;' +
    '$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup></Project>');
  Assert.IsTrue(Length(R) = 2, 'entradas: ' + IntToStr(Length(R)));
  Assert.AreEqual('..\lib', R[0].Escrita);
  Assert.AreEqual('C:\lib', R[0].Carpeta);
  Assert.AreEqual('R&D', R[1].Escrita);
  Assert.AreEqual('C:\p\R&D', R[1].Carpeta);
end;

procedure TXmlTextoTests.TrozosEscritosNoPartenUnaEntidad;
var
  T: TArray<string>;
begin
  // el ';' de &amp; y el de &#38; no separan; el ultimo ';' deja un trozo vacio
  T := TrozosEscritos('a;R&amp;D;&#38;x;');
  Assert.IsTrue(Length(T) = 4, 'trozos: ' + IntToStr(Length(T)));
  Assert.AreEqual('a', T[0]);
  Assert.AreEqual('R&amp;D', T[1]);
  Assert.AreEqual('&#38;x', T[2]);
  Assert.AreEqual('', T[3]);
  Assert.AreEqual('&lt;', XmlUnescape(XmlEscape('&lt;')), 'la inversa');
end;

procedure TXmlTextoTests.TagValueNoDistingueMayusculas;
begin
  // el lector de la casa: el .sdk del IDE escribe Profile_sysroot, get-sdk
  // Profile_SysRoot; y el valor de verdad, desescapado
  Assert.AreEqual('C:\R&D\sysroot', TagValue(
    '<Project><PropertyGroup><Profile_SysRoot>C:\R&amp;D\sysroot</Profile_SysRoot>' +
    '</PropertyGroup></Project>', 'Profile_sysroot'));
  Assert.AreEqual('', TagValue('<Project/>', 'Profile_sysroot'));
end;

procedure CompruebaImport(const AForma: string;
  const AImportado: string = 'R&D.targets');
var
  Carpeta, Proyecto, Destino, Xml: string;
begin
  // Solo se analiza XML de una fixture propia; ninguna tarea se ejecuta.
  Carpeta := TPath.Combine(ExtractFilePath(ParamStr(0)),
    'import-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Carpeta);
  try
    Proyecto := TPath.Combine(Carpeta, 'App.dproj');
    Destino := TPath.Combine(Carpeta, AImportado);
    Xml := CABECERA + Format(AForma, [XmlEscape(AImportado)]) + PIE;
    TFile.WriteAllText(Destino, '<Project><Target Name="Fixture"><Message Text="fixture"/></Target></Project>');
    Assert.AreEqual('', DprojBuildHazard(Xml, Proyecto, True), 'import local sin tareas peligrosas');
    TFile.WriteAllText(Destino, '<Project><Target Name="Fixture"><Exec Command="fixture"/></Target></Project>');
    Assert.AreNotEqual('', DprojBuildHazard(Xml, Proyecto, True), 'el import se lee con esta sintaxis');
  finally
    if TFile.Exists(Destino) then TFile.Delete(Destino);
    TDirectory.Delete(Carpeta);
  end;
end;

procedure TDprojHazardTests.ImportConComillasSimplesSeComprueba;
begin
  CompruebaImport('<Import Project=''%s''/>');
end;

procedure TDprojHazardTests.ImportConEspaciosSeComprueba;
begin
  CompruebaImport('<Import Project = "%s"/>');
end;

procedure TDprojHazardTests.ImportConComillasDoblesSeComprueba;
begin
  CompruebaImport('<Import Project="%s"/>');
end;

procedure TDprojHazardTests.ImportConEntidadesSeComprueba;
begin
  CompruebaImport('<Import Project'#9'='#9'"%s"/>');
end;

procedure TDprojHazardTests.DeployprojLocalSeComprueba;
begin
  CompruebaImport('<Import Project="%s"/>', 'fixture.deployproj');
end;

procedure TDprojHazardTests.NombreParecidoAUserToolsSeComprueba;
begin
  CompruebaImport('<Import Project="%s"/>', 'fixture-usertools.proj.targets');
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojHazardTests);
  TDUnitX.RegisterTestFixture(TXmlTextoTests);

end.
