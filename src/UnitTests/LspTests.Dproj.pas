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
    [Test] procedure ConfigConCaracteresDeShellSeNiegaSiempre;
    [Test] procedure ElNombreDeUnEventoNoEsUnPrefijo;
    [Test] procedure UnEventoEnUnComentarioTambienCuenta;
    [Test] procedure UnaAperturaSinCierreNoEscondeLoQueSigue;
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
    [Test] procedure FijaPropiedadParaTodosReescribeCadaGrupo;
    [Test] procedure FijaPropiedadParaTodosSinGrupoBaseNoToca;
    [Test] procedure ElTramoSabeDondeEmpiezaYAcabaElElemento;
    [Test] procedure ElGrupoPorSuCondicionSinMirarBlancos;
    [Test] procedure QuitaConSuLineaSoloSiEstaSola;
    [Test] procedure PlatformPropertyComoMsbuild;
    [Test] procedure ElGrupoDeDespliegueDeLasDosFormas;
    [Test] procedure LosGruposVaciosSoloSiSePiden;
    [Test] procedure ElIncludeEnCualquierOrden;
    [Test] procedure LasCuatroFormasDeLaCondicion;
    [Test] procedure LaCondicionDelElementoYElVacioCuentan;
  end;

  { EL analisis del XML de proyecto (1.20.1), lo que el oraculo contra MSXML
    (tests/test_oraculo_xml.py) encontro y lo que la familia pide de el: un
    lector, sus escritores y las posiciones para reescribir en su sitio. }
  [TestFixture]
  TXmlNucleoTests = class
  public
    [Test] procedure ElCierreCuentaLosDelMismoNombre;
    [Test] procedure LoOcultoNoEsUnaEtiqueta;
    [Test] procedure ElValorComoLoDaXml;
    [Test] procedure LosAtributosConSuSitio;
    [Test] procedure ConSuLineaSoloSiNadaLaSigue;
    [Test] procedure ElCierreDelProyectoEsElDelRaiz;
    [Test] procedure LasPlataformasDelBloque;
    [Test] procedure LasClavesDeVersionConSuSitio;
    [Test] procedure LasRutasDeExists;
    [Test] procedure ElEscritorDelDeployFileEsElDelIde;
    [Test] procedure XmlEscapeEnSuComilla;
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

procedure TXmlTextoTests.FijaPropiedadParaTodosReescribeCadaGrupo;
const
  NUEVO = '.\C&D\$(Platform)\$(Config)';
var
  Xml: string;
  C: TArray<TValorReescrito>;
begin
  // la de una config ANTES del grupo base (el texto crece por delante de el y
  // la que falta en la base tiene que caer justo tras su '>'), y la de una
  // plataforma con mayusculas y blancos: las dos se reescriben (D4, 1.20.1)
  Xml := '<Project>' +
    '<PropertyGroup Condition="''$(Cfg_2)''!=''''"><DCC_ExeOutput>.\R&amp;D</DCC_ExeOutput></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base)''!=''''"><X>a</X></PropertyGroup>' +
    '<PropertyGroup Condition = "''$(Base_Win64)'' != ''''"><DCC_EXEOUTPUT >.\b</DCC_EXEOUTPUT ></PropertyGroup>' +
    '</Project>';
  Assert.IsTrue(FijaPropiedadParaTodos(Xml, 'DCC_ExeOutput', NUEVO, C), Xml);
  Assert.IsTrue(Length(C) = 2, 'cambios: ' + IntToStr(Length(C)));
  Assert.AreEqual('.\R&D', C[0].Antes, 'el valor de verdad');
  Assert.AreEqual('''$(Cfg_2)''!=''''', C[0].Grupo);
  Assert.IsFalse(C[0].EnBase or C[1].EnBase, 'ninguna estaba en la base');
  Assert.AreEqual('.\b', C[1].Antes);
  Assert.IsTrue(Length(AllTagValues(Xml, 'DCC_ExeOutput')) = 3, Xml);
  for var V in AllTagValues(Xml, 'DCC_ExeOutput') do
    Assert.AreEqual(NUEVO, V, Xml);
  Assert.IsTrue(Xml.Contains('<PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '        ' + XmlElemento('DCC_ExeOutput', NUEVO) + '<X>a</X>'), 'en la base: ' + Xml);
  // con la base ya puesta no se escribe otra
  Assert.IsTrue(FijaPropiedadParaTodos(Xml, 'DCC_ExeOutput', '.\x', C), Xml);
  Assert.IsTrue((Length(C) = 3) and C[1].EnBase, 'la segunda vez, la de la base cuenta');
  Assert.IsTrue(Length(AllTagValues(Xml, 'DCC_ExeOutput')) = 3, Xml);
end;

procedure TXmlTextoTests.FijaPropiedadParaTodosSinGrupoBaseNoToca;
const
  XML_SIN_BASE = '<Project><PropertyGroup Condition="''$(Cfg_1)''!=''''">' +
    '<DCC_ExeOutput>.\a</DCC_ExeOutput></PropertyGroup></Project>';
var
  Xml: string;
  C: TArray<TValorReescrito>;
begin
  // sin grupo base no hay de donde lo hereden las demas: False y el texto
  // tal cual (set-output contesta CFG-087 y no guarda nada)
  Xml := XML_SIN_BASE;
  Assert.IsFalse(FijaPropiedadParaTodos(Xml, 'DCC_ExeOutput', '.\b', C));
  Assert.AreEqual(XML_SIN_BASE, Xml);
end;

procedure TXmlTextoTests.ElTramoSabeDondeEmpiezaYAcabaElElemento;
const
  XML = '<P><X a="1>2">v</X ><X/></P>';
var
  T: TArray<TTramoXml>;
begin
  // un '>' entre comillas no cierra; </X > con blanco; <X/> no tiene valor
  T := TramosDeEtiqueta(XML, 'X');
  Assert.IsTrue(Length(T) = 1, 'tramos: ' + IntToStr(Length(T)));
  Assert.AreEqual('<X a="1>2">v</X >', Copy(XML, T[0].Abre, T[0].Cierra - T[0].Abre));
  Assert.AreEqual('v', Copy(XML, T[0].Ini, T[0].Fin - T[0].Ini));
end;

procedure TXmlTextoTests.ElGrupoPorSuCondicionSinMirarBlancos;
const
  XML = '<Project>' +
    '<PropertyGroup Condition = "(''$(Platform)''==''Linux64'' and ''$(Base)''==''true'') or ''$(Base_Linux64)''!=''''"></PropertyGroup>' +
    '<PropertyGroup Condition="''$(BASE_LINUX64)'' != ''''"><PlatformSDK>z</PlatformSDK></PropertyGroup >' +
    '</Project>';
var
  G: TGrupoXml;
begin
  // el grupo que escribe a mano quien no es el IDE: mayusculas y blancos
  Assert.IsTrue(GrupoConCondicion(XML, GroupCondition('Linux64'), G), 'el de valores');
  Assert.AreEqual('Linux64', PlataformaDeGrupo(G.Condicion, False), 'su plataforma, con su grafia');
  Assert.AreEqual('</PropertyGroup >', Copy(XML, G.Fin, G.Cierra - G.Fin), 'su cierre entero');
  Assert.IsTrue(Length(TramosEnGrupo(XML, 'PlatformSDK', G)) = 1, 'su etiqueta');
  Assert.IsTrue(GrupoConCondicion(XML, DefinerCondition('Linux64'), G), 'el definidor');
  Assert.AreEqual('Linux64', PlataformaDeGrupo(G.Condicion, True), 'el definidor de Linux64');
  Assert.AreEqual('', PlataformaDeGrupo(G.Condicion, False), 'un definidor no es un grupo de valores');
  Assert.AreEqual('', PlataformaDeGrupo(GroupCondition(''), False), 'la base no es de ninguna plataforma');
  Assert.IsFalse(GrupoConCondicion(XML, GroupCondition('OSX64'), G), 'el de otra no esta');
end;

procedure TXmlTextoTests.QuitaConSuLineaSoloSiEstaSola;
var
  S: string;
begin
  // sola en su linea: se va la linea con su salto de delante
  S := 'a'#13#10'    <X>1</X>'#13#10'b';
  QuitaConSuLinea(S, Pos('<X>', S), Pos('</X>', S) + 4);
  Assert.AreEqual('a'#13#10'b', S);
  // con algo delante en la linea: solo el elemento
  S := 'a<X>1</X>b';
  QuitaConSuLinea(S, 2, 10);
  Assert.AreEqual('ab', S);
  // en la primera linea del texto, sin salto delante
  S := '  <X>1</X>'#10'b';
  QuitaConSuLinea(S, 3, 11);
  Assert.AreEqual(#10'b', S);
end;

procedure TXmlTextoTests.PlatformPropertyComoMsbuild;
const
  XML = '<Project>' +
    '<PropertyGroup Condition="''$(Cfg_2)''!=''''"><PlatformSDK>de-config</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base)''!=''''"><PlatformSDK>de-base</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Linux64)''!=''''"><PlatformSDK Label="x">suya</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_OSX64)''!=''''"><PlatformSDK Condition="''$(X)''==''''">rara</PlatformSDK></PropertyGroup>' +
    '</Project>';
begin
  // la del grupo de la plataforma, aunque la etiqueta lleve atributos (Label)
  Assert.AreEqual('suya', PlatformProperty(XML, 'Linux64', 'PlatformSDK'));
  // una Condition del elemento que no es de plataforma/config no se da por
  // aplicada: OSX64 se queda con la base
  Assert.AreEqual('de-base', PlatformProperty(XML, 'OSX64', 'PlatformSDK'), 'condicion desconocida');
  // otra plataforma hereda la base; la de una CONFIG no es la base (el
  // lector propio la tomaba por reserva por ir primero)
  Assert.AreEqual('de-base', PlatformProperty(XML, 'Win64', 'PlatformSDK'));
end;

procedure TXmlTextoTests.ElGrupoDeDespliegueDeLasDosFormas;
begin
  // la que escribe el IDE y la que escribe el manifiesto del servidor
  Assert.AreEqual('Linux64', PlataformaDeGrupoDeDespliegue(DeployGroupCondition('Linux64')));
  Assert.AreEqual('Win64x', PlataformaDeGrupoDeDespliegue(DeployGroupCondition('Win64x', 'Debug')),
    'Win64x no es Win64');
  Assert.AreEqual('Android64', PlataformaDeGrupoDeDespliegue('''$(Platform)'' == ''ANDROID64'''),
    'blancos y mayusculas; Android64 no es Android');
  Assert.AreEqual('''$(Platform)''==''OSX64'' And ''$(Config)''==''Release''',
    DeployGroupCondition('OSX64', 'Release'), 'la que escribia a mano el generador');
  Assert.AreEqual('', PlataformaDeGrupoDeDespliegue('''$(Config)''==''Debug'''), 'sin plataforma');
  // una que ya no esta entre las conocidas (un .deployproj del IDE de los
  // Samples lleva OSX32): tal cual esta escrita, no fuera
  Assert.AreEqual('OSX32', PlataformaDeGrupoDeDespliegue('''$(Platform)''==''OSX32'''), 'OSX32');
  Assert.AreEqual('OSX32', PlataformaDeGrupo('''$(Base_OSX32)''!=''''', False), 'el grupo de valores de OSX32');
  Assert.AreEqual('', PlataformaDeGrupoDeDespliegue('''$(Platform)''==''Linux64'' or ''$(X)''=='''''),
    'otra forma de Condition no es la de un grupo de despliegue');
end;

procedure TXmlTextoTests.LosGruposVaciosSoloSiSePiden;
const
  XML = '<P><ItemGroup Condition="''$(Platform)''==''Linux64''"/>' +
    '<ItemGroup Condition="''$(Platform)''==''OSX64''"><DeployFile Include="a"/></ItemGroup></P>';
var
  G: TArray<TGrupoXml>;
begin
  G := GruposDe(XML, 'ItemGroup');
  Assert.IsTrue((Length(G) = 1) and not G[0].Vacio, 'sin pedirlos, solo el que tiene contenido');
  G := GruposDe(XML, 'ItemGroup', True);
  Assert.IsTrue((Length(G) = 2) and G[0].Vacio, 'pidiendolos, el vacio tambien');
  Assert.AreEqual('Linux64', PlataformaDeGrupoDeDespliegue(G[0].Condicion));
  Assert.AreEqual('<ItemGroup Condition="''$(Platform)''==''Linux64''"/>',
    Copy(XML, G[0].Abre, G[0].Cierra - G[0].Abre), 'el elemento entero');
  Assert.IsTrue(Length(TramosEnGrupo(XML, 'DeployFile', G[1])) = 0, 'un <DeployFile/> no tiene valor');
  Assert.IsTrue(Length(TramosEnGrupo(XML, 'DeployFile', G[1], True)) = 1, '...pero esta');
end;

procedure TXmlTextoTests.ElIncludeEnCualquierOrden;
const
  XML = '<DeployFile Condition=''x'' Include=''lib&amp;uno.so''><RemoteDir>P\</RemoteDir></DeployFile>';
var
  T: TArray<TTramoXml>;
begin
  T := TramosDeEtiqueta(XML, 'DeployFile');
  Assert.IsTrue(Length(T) = 1);
  Assert.AreEqual('lib&uno.so', AtributoDeTramo(XML, T[0], 'DeployFile', 'Include'),
    'detras de otro atributo, con comillas simples, desescapado');
  Assert.AreEqual('', AtributoDeTramo(XML, T[0], 'DeployFile', 'LocalName'), 'el que no lleva');
end;

procedure TXmlTextoTests.LasCuatroFormasDeLaCondicion;
var
  X, C: string;
begin
  Assert.IsTrue(CondicionDePlataformaYConfig('''$(Platform)''==''Win32''', X, C) and (X = 'Win32') and (C = ''));
  Assert.IsTrue(CondicionDePlataformaYConfig('''$(Config)''==''Debug''', X, C) and (X = '') and (C = 'Debug'));
  Assert.IsTrue(CondicionDePlataformaYConfig(DeployGroupCondition('Linux64', 'Release'), X, C) and
    (X = 'Linux64') and (C = 'Release'), 'la del manifiesto del servidor');
  // como la escribe el IDE en un grupo de eventos (TetherDatabase de los Samples)
  Assert.IsTrue(CondicionDePlataformaYConfig('''$(Config)''==''Debug'' And ''$(Platform)''==''Win32''', X, C) and
    (X = 'Win32') and (C = 'Debug'), 'config delante');
  Assert.IsFalse(CondicionDePlataformaYConfig('''$(Platform)''==''Win32'' or ''$(X)''==''''', X, C), 'otra forma');
  Assert.IsFalse(CondicionDePlataformaYConfig('Exists(''a.optset'')', X, C), 'una funcion');
  Assert.IsTrue((X = '') and (C = ''), 'sin forma, nada leido');
end;

procedure TXmlTextoTests.LaCondicionDelElementoYElVacioCuentan;
const
  // la forma de 5 Samples del IDE (ExploreDevicesLE, Notifications...): el
  // perfil de Win32 con SU condicion en el grupo sin condicion
  XML = '<Project><PropertyGroup>' +
    '<Profile Condition="''$(Platform)''==''Win32''">win_desktop</Profile>' +
    '<PlatformSDK>de-base</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Linux64)''!=''''"><PlatformSDK/></PropertyGroup></Project>';
begin
  Assert.AreEqual('win_desktop', PlatformProperty(XML, 'Win32', 'Profile'), 'en Win32 si');
  Assert.AreEqual('', PlatformProperty(XML, 'OSX64', 'Profile'), 'en OSX64 no: la condicion es del elemento');
  Assert.AreEqual('de-base', PlatformProperty(XML, 'OSX64', 'PlatformSDK'), 'OSX64 hereda la base');
  Assert.AreEqual('', PlatformProperty(XML, 'Linux64', 'PlatformSDK'), 'un <PlatformSDK/> la deja vacia, como msbuild');
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

procedure TDprojHazardTests.ConfigConCaracteresDeShellSeNiegaSiempre;
var
  Carpeta, Proyecto: string;
begin
  // El nombre de la config va a la linea de cmd.exe del build: el fondo lo
  // juzga antes que la lista del proyecto - con la lista vacia se aceptaba
  // todo, y un nombre declarado no es por eso limpio (4.8, revision de la
  // 1.18.1). Solo se lee XML de una fixture propia; no se compila nada.
  Assert.IsTrue(NombreDeConfigNoValido('Debug;Release'), ';');
  Assert.IsTrue(NombreDeConfigNoValido('Debug&x'), '&');
  Assert.IsFalse(NombreDeConfigNoValido('Release Plus'), 'un espacio vale');
  Assert.IsFalse(NombreDeConfigNoValido(''), 'vacio = la de por defecto');
  Carpeta := TPath.Combine(ExtractFilePath(ParamStr(0)),
    'config-' + TGUID.NewGuid.ToString);
  Proyecto := TPath.Combine(Carpeta, 'App.dproj');
  TDirectory.CreateDirectory(Carpeta);
  try
    TFile.WriteAllText(Proyecto, CABECERA + PIE);
    Assert.IsTrue(ConfigDesconocida(Proyecto, 'Debug;Release').Contains('BUILD-015'),
      'sin configuraciones declaradas');
    Assert.AreEqual('', ConfigDesconocida(Proyecto, 'Debug'),
      'sin configuraciones declaradas, un nombre limpio vale');
    TFile.WriteAllText(Proyecto, CABECERA +
      '  <ItemGroup><BuildConfiguration Include="Debug;Release"><Key>Cfg_1</Key>' +
      '</BuildConfiguration></ItemGroup>'#13#10 + PIE);
    Assert.IsTrue(ConfigDesconocida(Proyecto, 'Debug;Release').Contains('BUILD-015'),
      'declarado por el proyecto');
  finally
    if TFile.Exists(Proyecto) then TFile.Delete(Proyecto);
    TDirectory.Delete(Carpeta);
  end;
end;

procedure TDprojHazardTests.ElNombreDeUnEventoNoEsUnPrefijo;
begin
  // '<prebuildevent' como prefijo casaba con <PreBuildEventIgnoreExitCode>,
  // que no ejecuta nada (lo vio el oraculo, 17-oct-2026)
  Assert.AreEqual('', DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PreBuildEventIgnoreExitCode>False</PreBuildEventIgnoreExitCode></PropertyGroup>'#13#10 +
    PIE, RUTA));
end;

procedure TDprojHazardTests.UnEventoEnUnComentarioTambienCuenta;
begin
  // el escaner es MAS estricto que el juez: mira tambien lo comentado
  Assert.AreNotEqual('', DprojBuildHazard(CABECERA +
    '  <!-- <PropertyGroup><PostBuildEvent>x</PostBuildEvent></PropertyGroup> -->'#13#10 +
    PIE, RUTA));
end;

procedure TDprojHazardTests.UnaAperturaSinCierreNoEscondeLoQueSigue;
begin
  // en un comentario cabe una etiqueta sin cerrar y el XML sigue bien formado:
  // msbuild ejecuta el evento de verdad, y el escaner, que tambien mira lo
  // comentado, dejaba de leer en la que no tenia cierre (revision del diff de
  // la familia, 17-oct-2026)
  Assert.AreNotEqual('', DprojBuildHazard(CABECERA +
    '  <!-- <PostBuildEvent> -->'#13#10 +
    '  <PropertyGroup><PostBuildEvent>calc.exe</PostBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA));
end;

procedure TXmlNucleoTests.ElCierreCuentaLosDelMismoNombre;
const
  XML = '<P><VersionInfo><VersionInfo Name="a">1</VersionInfo></VersionInfo><X/></P>';
var
  T: TArray<TTramoXml>;
begin
  // el IDE escribe <VersionInfo><VersionInfo Name=...> en ProjectExtensions
  T := TramosDeEtiqueta(XML, 'VersionInfo');
  Assert.AreEqual(2, Integer(Length(T)));
  Assert.AreEqual('<VersionInfo><VersionInfo Name="a">1</VersionInfo></VersionInfo>',
    Copy(XML, T[0].Abre, T[0].Cierra - T[0].Abre), 'el de fuera, con el de dentro');
  Assert.AreEqual('1', ValorDeTramo(XML, T[1]));
end;

procedure TXmlNucleoTests.LoOcultoNoEsUnaEtiqueta;
const
  XML = '<P><!-- <X>1</X> --><X>2</X><![CDATA[<X>3</X>]]><?pi <X>4</X>?></P>';
begin
  Assert.AreEqual(1, Integer(Length(TramosDeEtiqueta(XML, 'X'))), 'el juez solo ve una');
  Assert.AreEqual(4, Integer(Length(TramosDeEtiqueta(XML, 'X', False, True))),
    'el escaner de peligros, todas');
end;

procedure TXmlNucleoTests.ElValorComoLoDaXml;
const
  XML = '<E>a<![CDATA[<b>&amp;]]><!-- c -->d&amp;'#13#10'e</E>';
begin
  // el CDATA tal cual, el comentario fuera, las entidades y los saltos como XML
  Assert.AreEqual('a<b>&amp;d&'#10'e', ValorDeTramo(XML, TramosDeEtiqueta(XML, 'E')[0]));
end;

procedure TXmlNucleoTests.LosAtributosConSuSitio;
const
  XML = '<X a=''1'' b = "2&amp;"'#13#10#9'c="x'#13#10#9'y"/>';
var
  A: TArray<TAtributoXml>;
begin
  A := AtributosDeTramo(XML, TramosDeEtiqueta(XML, 'X', True)[0]);
  Assert.AreEqual(3, Integer(Length(A)));
  Assert.AreEqual('a', A[0].Nombre);
  Assert.AreEqual('1', Copy(XML, A[0].Ini, A[0].Fin - A[0].Ini));
  Assert.AreEqual('''', XML[A[0].Ini - 1], 'la comilla, delante del valor');
  Assert.AreEqual('b', Copy(XML, A[1].Abre, 1), 'Abre: donde empieza el nombre');
  Assert.AreEqual('2&', ValorDeAtributo(XML, A[1]));
  Assert.AreEqual('x'#10#9'y', ValorDeAtributo(XML, A[2]),
    'como MSXML: el salto en LF y el tabulador se quedan');
end;

procedure TXmlNucleoTests.ConSuLineaSoloSiNadaLaSigue;
const
  S = 'a'#13#10'    <X/>  '#13#10'b <Y/> c';
var
  P, D, H: Integer;
begin
  P := Pos('<X/>', S);
  ConSuLinea(S, P, P + 4, D, H);
  Assert.AreEqual('    <X/>  '#13#10, Copy(S, D, H - D), 'sola: con sus blancos y su salto');
  P := Pos('<Y/>', S);
  ConSuLinea(S, P, P + 4, D, H);
  Assert.AreEqual(' <Y/>', Copy(S, D, H - D), 'con algo detras: sus blancos de delante y ella');
end;

procedure TXmlNucleoTests.ElCierreDelProyectoEsElDelRaiz;
const
  XML = '<Project><ProjectExtensions></ProjectExtensions><ItemGroup><Projects Include="a"/>' +
    '</ItemGroup></Project >';
begin
  Assert.AreEqual(Pos('</Project >', XML), CierreDelProyecto(XML));
  Assert.AreEqual(0, CierreDelProyecto('<P/>'));
end;

procedure TXmlNucleoTests.LasPlataformasDelBloque;
const
  XML = '<Project><PropertyGroup><Platform Condition="''$(Platform)''==''''">Win64</Platform>' +
    '</PropertyGroup><!-- <Platforms><Platform value="Linux64">True</Platform></Platforms> -->' +
    '<ProjectExtensions><BorlandProject><Platforms><Platform value=''Win32''>False</Platform>' +
    '<Platform value="Win64"> True </Platform></Platforms></BorlandProject></ProjectExtensions></Project>';
var
  P: TArray<TPlataformaDelBloque>;
begin
  P := PlataformasDelBloque(XML);
  Assert.AreEqual(2, Integer(Length(P)), 'ni el selector ni lo comentado');
  Assert.AreEqual('Win32', P[0].Nombre);
  Assert.IsFalse(P[0].Activa);
  Assert.AreEqual('Win64', P[1].Nombre);
  Assert.IsTrue(P[1].Activa, 'el nombre y si esta activa, del mismo elemento');
  Assert.AreEqual(' True ', Copy(XML, P[1].Tramo.Ini, P[1].Tramo.Fin - P[1].Tramo.Ini));
  Assert.AreEqual('<Platform value="OSX64">True</Platform>', XmlPlataformaDelBloque('OSX64', True));
  Assert.AreEqual('OSX64', PlataformasDelBloque('<Platforms>' +
    XmlPlataformaDelBloque('OSX64', False) + '</Platforms>')[0].Nombre, 'el lector lee al escritor');
end;

procedure TXmlNucleoTests.LasClavesDeVersionConSuSitio;
const
  XML = '<P><VerInfo_Keys>CompanyName=R&amp;D;FileVersion=1.2.3.4;X</VerInfo_Keys>' +
    '<!-- <VerInfo_Keys>FileVersion=9</VerInfo_Keys> --><PreBuildEvent>echo FileVersion=7</PreBuildEvent></P>';
var
  C: TArray<TClaveDeVersion>;
begin
  C := ClavesDeVersion(XML);
  Assert.AreEqual(2, Integer(Length(C)), 'X no es una clave; ni lo comentado ni el evento son claves');
  Assert.AreEqual('CompanyName', C[0].Nombre);
  Assert.AreEqual('R&amp;D', Copy(XML, C[0].Ini, C[0].Fin - C[0].Ini), 'escrito, con su entidad');
  Assert.AreEqual('FileVersion', C[1].Nombre);
  Assert.AreEqual('1.2.3.4', Copy(XML, C[1].Ini, C[1].Fin - C[1].Ini));
end;

procedure TXmlNucleoTests.LasRutasDeExists;
const
  COND = '''$(Base)''!='''' And Exists(''..\Comun.optset'') and !exists( ''b.optset'')';
var
  R: TArray<TTrozoEscrito>;
begin
  R := RutasDeExists(COND);
  Assert.AreEqual(2, Integer(Length(R)));
  Assert.AreEqual('..\Comun.optset', Copy(COND, R[0].Ini, R[0].Fin - R[0].Ini));
  Assert.AreEqual('b.optset', Copy(COND, R[1].Ini, R[1].Fin - R[1].Ini));
end;

procedure TXmlNucleoTests.ElEscritorDelDeployFileEsElDelIde;
var
  X: string;
  T: TArray<TTramoXml>;
begin
  // los bytes de los cuatro compositores que habia, uno a uno
  Assert.AreEqual(
    '        <DeployFile Include="Linux64\Debug\App" Condition="''$(Config)''==''Debug''">' + sLineBreak +
    '            <RemoteDir>App\</RemoteDir>' + sLineBreak +
    '            <RemoteName>App</RemoteName>' + sLineBreak +
    '            <DeployClass>ProjectOutput</DeployClass>' + sLineBreak +
    '            <Operation>1</Operation>' + sLineBreak +
    '            <LocalCommand/>' + sLineBreak +
    '            <RemoteCommand/>' + sLineBreak +
    '            <Overwrite>True</Overwrite>' + sLineBreak +
    '            <Required>True</Required>' + sLineBreak +
    '        </DeployFile>' + sLineBreak,
    XmlDeployFile('Linux64\Debug\App', 'Debug', 'App\', 'App', 'ProjectOutput', 1, True));
  // ...y su lector lo lee
  X := '<ItemGroup>' + XmlDeployFile('R&D.so', '', 'x\', 'R&D.so', 'File', 0, False) + '</ItemGroup>';
  T := TramosDeEtiqueta(X, 'DeployFile');
  Assert.AreEqual('R&D.so', AtributoDeTramo(X, T[0], 'DeployFile', 'Include'));
  Assert.AreEqual('', AtributoDeTramo(X, T[0], 'DeployFile', 'Condition'), 'sin config, sin Condition');
  Assert.AreEqual(0, Integer(Length(TramosDeEtiqueta(X, 'Required'))), 'sin Required si no lo es');
end;

procedure TXmlNucleoTests.XmlEscapeEnSuComilla;
begin
  Assert.AreEqual('O''Brien &amp; co', XmlEscapeEn('O''Brien & co', '"'));
  Assert.AreEqual('O&apos;Brien &amp; co', XmlEscapeEn('O''Brien & co', ''''));
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojHazardTests);
  TDUnitX.RegisterTestFixture(TXmlTextoTests);
  TDUnitX.RegisterTestFixture(TXmlNucleoTests);

end.
