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
    [Test] procedure UnBooleanoComoLoLeeMsbuild;
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
    [Test] procedure LaPropiedadEfectivaComoMsbuild;
    [Test] procedure LaPropiedadEfectivaConLoDeAntesDentro;
    [Test] procedure LosSelectoresDelProyecto;
    [Test] procedure ElNombradorDeLosGruposConSuClave;
    [Test] procedure ElGrupoDeDespliegueDeLasDosFormas;
    [Test] procedure LosGruposVaciosSoloSiSePiden;
    [Test] procedure ElIncludeEnCualquierOrden;
    [Test] procedure LasCuatroFormasDeLaCondicion;
    [Test] procedure LaCondicionDelElementoYElVacioCuentan;
    [Test] procedure LaCondicionDeUnGrupoComoMsbuild;
    [Test] procedure ElGrupoDelBuildDondeLoEscribeElIde;
    [Test] procedure PonPropiedadDelBuildEnLasCuatroFormas;
    [Test] procedure LaPropiedadEfectivaNoSeHaceLenta;
    [Test] procedure DosGruposConLaMismaCondicionYLaClaveRara;
    [Test] procedure ElParserDelIdeJuzgaLoCompuesto;
    [Test] procedure LosValoresDelBuildSeExpandenEnSuPunto;
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
    [Test]
    procedure LaPlataformaDelMotorLaDiceLaTabla;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Lsp.Dproj, Lsp.Patch;

const
  RUTA = 'C:\Proyecto\App.dproj';
  CABECERA = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup>'#13#10;
  PIE = '</Project>'#13#10;

{ Lo que msbuild lee como verdad en una propiedad (A33 de la 1.23): se
  comparaba con 'true' a mano. }
procedure TDprojHazardTests.UnBooleanoComoLoLeeMsbuild;
begin
  Assert.IsTrue(EsVerdadDeMsbuild('true') and EsVerdadDeMsbuild('True') and EsVerdadDeMsbuild('yes') and
    EsVerdadDeMsbuild('ON') and EsVerdadDeMsbuild('!false'));
  Assert.IsFalse(EsVerdadDeMsbuild('false') or EsVerdadDeMsbuild('no') or EsVerdadDeMsbuild('!true'));
  Assert.IsFalse(EsVerdadDeMsbuild('1') or EsVerdadDeMsbuild(''), 'un numero o nada no es un booleano');
end;

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
  // el lector de un build (un grupo sin condicion se aplica a todos): con lo
  // de antes dentro, y desescapado
  Assert.AreEqual(VALOR.Replace(';$(DCC_UnitSearchPath)', ';'),
    EffectiveProperty(Xml, 'DCC_UnitSearchPath', 'Win64', 'Debug'), 'EffectiveProperty');
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
  // la que falta en la base tiene que caer en su sitio), y la de una
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
  // ...al FINAL del grupo base, como pone el IDE una propiedad nueva
  // (AnadeAlGrupo, 1.22.1; era al principio)
  Assert.IsTrue(Xml.Contains('<X>a</X>' + sLineBreak + '        ' + XmlElemento('DCC_ExeOutput', NUEVO) +
    '</PropertyGroup>'), 'en la base: ' + Xml);
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

{ Lo que el IDE escribe ANTES de los grupos de valores y sin lo cual msbuild
  no aplica ninguno (y el lector, que evalua como msbuild, tampoco):
  <Base>True</Base> en el primer grupo, el definidor de la configuracion Base,
  el de cada plataforma de APlataformas para Base, y por cada 'Nombre=Cfg_N'
  de AConfigs su definidor y los de sus plataformas. }
function CadenaDelIde(const APlataformas, AConfigs: TArray<string>): string;

  function DefinidorDeConfig(const ANombre, AClave: string): string;
  begin
    // EL escritor del definidor de una configuracion (Lsp.Dproj)
    Result := XmlGrupoDefinidorDeConfig(ANombre, AClave);
  end;

var
  P: Integer;
  Nombre, Clave: string;
begin
  Result := '<PropertyGroup>' + XmlElemento('Base', 'True') + '</PropertyGroup>' +
    DefinidorDeConfig('Base', 'Base');
  for var Plat in APlataformas do
    Result := Result + XmlGrupoDefinidor(Plat, 'Base');
  for var C in AConfigs do
  begin
    P := Pos('=', C);
    Nombre := Copy(C, 1, P - 1);
    Clave := Copy(C, P + 1, MaxInt);
    Result := Result + DefinidorDeConfig(Nombre, Clave);
    for var Plat in APlataformas do
      Result := Result + XmlGrupoDefinidor(Plat, Clave);
  end;
end;

procedure TXmlTextoTests.LaPropiedadEfectivaComoMsbuild;
var
  XML: string;
begin
  // con la cadena del IDE delante (<Base>True</Base> y los definidores), que
  // es lo que msbuild evalua: sin ella no se aplica ningun grupo
  XML := '<Project>' + CadenaDelIde(['Linux64', 'OSX64'], []) +
    '<PropertyGroup Condition="''$(Cfg_2)''!=''''"><PlatformSDK>de-config</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base)''!=''''"><PlatformSDK>de-base</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Linux64)''!=''''"><PlatformSDK Label="x">suya</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_OSX64)''!=''''"><PlatformSDK Condition="''$(X)''==''''">rara</PlatformSDK></PropertyGroup>' +
    '</Project>';
  // la del grupo de la plataforma, aunque la etiqueta lleve atributos (Label)
  Assert.AreEqual('suya', EffectiveProperty(XML, 'PlatformSDK', 'Linux64', ''));
  // una Condition del elemento que no es de plataforma/config no se da por
  // aplicada: OSX64 se queda con la base
  Assert.AreEqual('de-base', EffectiveProperty(XML, 'PlatformSDK', 'OSX64', ''), 'condicion desconocida');
  // otra plataforma hereda la base; la de una CONFIG no es la base (el
  // lector propio la tomaba por reserva por ir primero)
  Assert.AreEqual('de-base', EffectiveProperty(XML, 'PlatformSDK', 'Win64', ''));
end;

// Los defines de cada configuracion como los escribe el IDE: un $(X) dentro
// del valor es lo que valia hasta ahi, y solo los grupos de ESA configuracion
// cuentan (los ajustes del motor encadenaban todos: DEBUG y RELEASE a la vez,
// medido el 17-oct-2026, T2/M9).
procedure TXmlTextoTests.LaPropiedadEfectivaConLoDeAntesDentro;
var
  XML: string;
begin
  XML := '<Project><ItemGroup>' +
    '<BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>' +
    '</ItemGroup>' + CadenaDelIde(['Win32'], ['Debug=Cfg_1', 'Release=Cfg_2']) +
    '<PropertyGroup Condition="''$(Base)''!=''''"><DCC_Define>BASE;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Win32)''!=''''"><DCC_Define>W32;$(dcc_define)</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Cfg_1)''!=''''"><DCC_Define>DEBUG;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Cfg_2)''!=''''"><DCC_Define>RELEASE;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    '</Project>';
  Assert.AreEqual('DEBUG;W32;BASE;', EffectiveProperty(XML, 'DCC_Define', 'Win32', 'Debug'));
  Assert.AreEqual('RELEASE;W32;BASE;', EffectiveProperty(XML, 'DCC_Define', 'Win32', 'Release'));
  Assert.AreEqual('DEBUG;BASE;', EffectiveProperty(XML, 'DCC_Define', 'Win64', 'Debug'),
    'el grupo de otra plataforma no cuenta');
end;

// La pareja que compilan el IDE y msbuild sin que nadie pida otra: los dos
// selectores, no las entradas del bloque <Platforms> (que llevan value).
procedure TXmlTextoTests.LosSelectoresDelProyecto;
const
  XML = '<Project><PropertyGroup>' +
    '<Config Condition="''$(Config)''==''''">Release</Config>' +
    '<Platform Condition="''$(Platform)''==''''">Win64</Platform>' +
    '</PropertyGroup><ItemGroup>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>' +
    '</ItemGroup><ProjectExtensions><BorlandProject><Platforms>' +
    '<Platform value="Win32">True</Platform><Platform value="Win64">True</Platform>' +
    '</Platforms></BorlandProject></ProjectExtensions></Project>';
var
  Info: TDprojInfo;
  T: TTramoXml;
begin
  Info := InfoDeDproj(XML);
  Assert.AreEqual('Release', Info.ConfigPorDefecto);
  Assert.AreEqual('Win64', Info.PlataformaPorDefecto);
  Assert.IsTrue(SelectorDe(XML, 'Platform', T));
  Assert.AreEqual('Win64', Copy(XML, T.Ini, T.Fin - T.Ini), 'el sitio del valor, para reescribirlo');
  // sin selector, Debug, como msbuild sin /p:Config
  Assert.AreEqual('Debug', InfoDeDproj('<Project></Project>').ConfigPorDefecto);
  Assert.IsFalse(SelectorDe('<Project></Project>', 'Config', T));
end;

// Las Condition de los grupos y el definidor entero, por EL nombrador: los de
// la base como siempre (add-platform), y los de una configuracion como los
// escribe el IDE al crear un proyecto (delphi_create, 1.20.2)
procedure TXmlTextoTests.ElNombradorDeLosGruposConSuClave;
begin
  Assert.AreEqual('''$(Base_Win32)''!=''''', GroupCondition('Win32'));
  Assert.AreEqual('''$(Cfg_1)''!=''''', GroupCondition('', 'Cfg_1'));
  Assert.AreEqual('''$(Cfg_1_Win64)''!=''''', GroupCondition('Win64', 'Cfg_1'));
  Assert.AreEqual('(''$(Platform)''==''Win32'' and ''$(Cfg_2)''==''true'') or ''$(Cfg_2_Win32)''!=''''',
    DefinerCondition('Win32', 'Cfg_2'));
  Assert.AreEqual('''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''', ConfigDefinerCondition('Debug', 'Cfg_1'));
  // el definidor de la base, byte a byte el que escribia add-platform
  Assert.AreEqual('    <PropertyGroup Condition="(''$(Platform)''==''Linux64'' and ''$(Base)''==''true'') or ' +
    '''$(Base_Linux64)''!=''''">' + sLineBreak +
    '        <Base_Linux64>true</Base_Linux64>' + sLineBreak +
    '        <CfgParent>Base</CfgParent>' + sLineBreak +
    '        <Base>true</Base>' + sLineBreak +
    '    </PropertyGroup>', XmlGrupoDefinidor('Linux64', 'Base'));
  // el de una configuracion lleva tambien la clave de la que hereda
  Assert.IsTrue(XmlGrupoDefinidor('Win32', 'Cfg_1').Contains(
    '<CfgParent>Cfg_1</CfgParent>' + sLineBreak + '        <Cfg_1>true</Cfg_1>' + sLineBreak +
    '        <Base>true</Base>'));
  // y la inversa no toma una de configuracion por una de plataforma
  Assert.AreEqual('', PlataformaDeGrupo(GroupCondition('Win32', 'Cfg_1'), False));
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
var
  XML: string;
begin
  // la forma de 5 Samples del IDE (ExploreDevicesLE, Notifications...): el
  // perfil de Win32 con SU condicion en el grupo sin condicion
  XML := '<Project>' + CadenaDelIde(['Linux64'], []) + '<PropertyGroup>' +
    '<Profile Condition="''$(Platform)''==''Win32''">win_desktop</Profile>' +
    '<PlatformSDK>de-base</PlatformSDK></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Linux64)''!=''''"><PlatformSDK/></PropertyGroup></Project>';
  Assert.AreEqual('win_desktop', EffectiveProperty(XML, 'Profile', 'Win32', ''), 'en Win32 si');
  Assert.AreEqual('', EffectiveProperty(XML, 'Profile', 'OSX64', ''), 'en OSX64 no: la condicion es del elemento');
  Assert.AreEqual('de-base', EffectiveProperty(XML, 'PlatformSDK', 'OSX64', ''), 'OSX64 hereda la base');
  Assert.AreEqual('', EffectiveProperty(XML, 'PlatformSDK', 'Linux64', ''), 'un <PlatformSDK/> la deja vacia, como msbuild');
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
  Carpeta, Proyecto, Cfg: string;
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
    Assert.IsTrue(ConfigDelBuild(ReadDproj(Proyecto), 'Debug;Release', Cfg).Contains('BUILD-015'),
      'sin configuraciones declaradas');
    Assert.AreEqual('', ConfigDelBuild(ReadDproj(Proyecto), ' Debug ', Cfg),
      'sin configuraciones declaradas, un nombre limpio vale');
    Assert.AreEqual('Debug', Cfg, 'tal cual, sin los blancos');
    TFile.WriteAllText(Proyecto, CABECERA +
      '  <ItemGroup><BuildConfiguration Include="Debug;Release"><Key>Cfg_1</Key>' +
      '</BuildConfiguration></ItemGroup>'#13#10 + PIE);
    Assert.IsTrue(ConfigDelBuild(ReadDproj(Proyecto), 'Debug;Release', Cfg).Contains('BUILD-015'),
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

{ Una tabla de propiedades para EvaluaCondicion: 'Nombre=Valor' sabida,
  'Nombre?' dudosa, lo que no esta desconocido. }
function Tabla(APares: TArray<string>): TBuscaBandera;
begin
  Result := function(const ANombre: string): TBanderaDelBuild
    begin
      Result.Valor := '';
      Result.Estado := eDesconocida;
      for var P in APares do
        if SameText(P, ANombre + '?') then
          Result.Estado := eDudosa
        else if SameText(Copy(P, 1, Pos('=', P) - 1), ANombre) then
        begin
          Result.Estado := eSabida;
          Result.Valor := Copy(P, Pos('=', P) + 1, MaxInt);
        end;
    end;
end;

procedure TXmlTextoTests.LaCondicionDeUnGrupoComoMsbuild;
const
  // la cadena del IDE (Base, definidores de config y plataforma, grupos de
  // valores), un grupo de Android, una config hija, una Condition que no se
  // sabe y una en el elemento
  XML = '<Project><PropertyGroup><Base>True</Base></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''"><Cfg_1>true</Cfg_1></PropertyGroup>' +
    '<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">' +
    '<Base_Win64>true</Base_Win64></PropertyGroup>' +
    '<PropertyGroup Condition="(''$(Platform)''==''Android64'' and ''$(Cfg_1)''==''true'') or ''$(Cfg_1_Android64)''!=''''">' +
    '<Cfg_1_Android64>true</Cfg_1_Android64></PropertyGroup>' +
    // el definidor de la config hija, como el IDE: antes de los grupos de valores
    '<PropertyGroup Condition="''$(Config)''==''Debug2'' or ''$(Cfg_3)''!=''''"><Cfg_3>true</Cfg_3><Cfg_1>true</Cfg_1></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Cfg_1_Android64)''!=''''"><PF_KeyStoreDebug>k</PF_KeyStoreDebug></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Base_Win64)''!=''''"><DCC_UnitSearchPath>a</DCC_UnitSearchPath></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Cfg_1)''!=''''"><DCC_Define>D</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="Exists(''x'')"><Icon_MainIcon>i</Icon_MainIcon></PropertyGroup>' +
    '<PropertyGroup><Manifest_File Condition="''$(Platform)''==''Win32''">m</Manifest_File></PropertyGroup>' +
    '</Project>';
  PLANTADA = '<Project><PropertyGroup><Cfg_1>true</Cfg_1></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Cfg_1)''!=''''"><DCC_Define>D</DCC_Define></PropertyGroup></Project>';
  EXTERNA = '<Project><PropertyGroup Condition="''$(Platform)''==''Android64''"><BDS>x</BDS></PropertyGroup>' +
    '<PropertyGroup Condition="''$(BDS)''!=''''"><DCC_Define>D</DCC_Define></PropertyGroup></Project>';
  // lo que el revisor E midio con el msbuild del IDE el 21-oct-2026: un valor
  // se fija EXPANDIDO (Tarde vale 'a'), un PropertyGroup dentro de
  // ProjectExtensions o de un Target no cuenta en la pasada, y una global
  // (/p:) gana al documento aunque este la ponga
  PEREZOSA = '<Project><PropertyGroup><Antes>a</Antes><Tarde>$(Antes)</Tarde><Antes>b</Antes></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Tarde)''==''a''"><DCC_Define>D</DCC_Define></PropertyGroup></Project>';
  ANIDADA = '<Project><PropertyGroup><Puerta>1</Puerta></PropertyGroup>' +
    '<ProjectExtensions><PropertyGroup><Puerta>0</Puerta></PropertyGroup></ProjectExtensions>' +
    '<Target Name="Nada"><PropertyGroup><Puerta>0</Puerta><DCC_ExeOutput>t</DCC_ExeOutput></PropertyGroup></Target>' +
    '<PropertyGroup Condition="''$(Puerta)''==''1''"><DCC_Define>D</DCC_Define><DCC_ExeOutput>r</DCC_ExeOutput></PropertyGroup></Project>';
  GLOBAL = '<Project><PropertyGroup><Profile>p</Profile></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Profile)''==''''"><DCC_Define>D</DCC_Define></PropertyGroup></Project>';
var
  Mal: string;
  E: TArray<TElementoXml>;
  Otro: TArray<Boolean>;

  function DeOtro(const ANombre: string): Boolean;
  begin
    for var I := 0 to High(E) do
      if SameText(E[I].Escrito, ANombre) then
        Exit(Otro[I]);
    raise Exception.Create('no esta ' + ANombre);
  end;

begin
  // la gramatica: lo que se sabe y lo que no (Tabla: Nombre=Valor sabida,
  // Nombre? dudosa, lo demas desconocido)
  Assert.IsTrue(EvaluaCondicion('', 'Win64', 'Release', Tabla([])) = vSi, 'sin condicion: cierta');
  Assert.IsTrue(EvaluaCondicion('''$(Base)''!=''''', 'Win64', 'Release', Tabla(['Base='])) = vNo, 'Base definida y sin poner: falsa');
  Assert.IsTrue(EvaluaCondicion('''$(Base)''!=''''', 'Win64', 'Release', Tabla(['Base=True'])) = vSi, 'Base puesta: cierta');
  Assert.IsTrue(EvaluaCondicion('''$(Base)''!=''''', 'Win64', 'Release', Tabla([])) = vNoSeSabe, 'un nombre que nadie define (puede venir de fuera): no se sabe');
  Assert.IsTrue(EvaluaCondicion('''$(config)''==''RELEASE''', 'Win64', 'Release', Tabla([])) = vSi, 'sin distinguir mayusculas');
  Assert.IsTrue(EvaluaCondicion('''$(Config)''==''Debug''', 'Win64', 'Release', Tabla([])) = vNo, 'otra config: falsa');
  Assert.IsTrue(EvaluaCondicion(DefinerCondition('Win64'), 'Win64', 'Release', Tabla(['Base=True', 'Base_Win64='])) = vSi, 'el definidor de Win64 con Base puesta');
  Assert.IsTrue(EvaluaCondicion(DefinerCondition('Win32'), 'Win64', 'Release', Tabla(['Base=True', 'Base_Win32='])) = vNo, 'el de Win32: falso');
  Assert.IsTrue(EvaluaCondicion(ConfigDefinerCondition('Release', 'Cfg_2'), 'Win64', 'Release', Tabla(['Cfg_2='])) = vSi, 'el definidor de Release');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''=='''' or ''$(LbB)''!=''''', 'Win64', 'Release', Tabla(['LbA=', 'LbB='])) = vSi, 'or con una cierta');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''!='''' and Exists(''b'')', 'Win64', 'Release', Tabla(['LbA='])) = vNo, 'falso and lo que sea: falso');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''!='''' and Exists(''b'')', 'Win64', 'Release', Tabla(['LbA=1'])) = vNoSeSabe, 'cierto and no se sabe: no se sabe');
  Assert.IsTrue(EvaluaCondicion('Exists(''a'')', 'Win64', 'Release', Tabla([])) = vNoSeSabe, 'una funcion: no se sabe');
  Assert.IsTrue(EvaluaCondicion('''$(LbA.Trim())''==''''', 'Win64', 'Release', Tabla(['LbA='])) = vNoSeSabe, 'una funcion de propiedad: no se sabe');
  Assert.IsTrue(EvaluaCondicion('"$(Base)"!=''''', 'Win64', 'Release', Tabla(['Base=True'])) = vNoSeSabe, 'otras comillas: no se sabe');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''==''1'' and', 'Win64', 'Release', Tabla(['LbA=1'])) = vNoSeSabe, 'una condicion a medias: no se sabe');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''!=''''', 'Win64', 'Release', Tabla(['LbA?'])) = vNoSeSabe, 'una bandera dudosa: no se sabe');
  Assert.IsTrue(EvaluaCondicion('''$(lbb)''==''x''', 'Win64', 'Release', Tabla(['LbB=X'])) = vSi, 'el valor, sin distinguir mayusculas');
  // msbuild compara numeros y booleanos antes que texto, y desescapa %XX
  // (medido el 21-oct-2026 con el msbuild del IDE)
  Assert.IsTrue(EvaluaCondicion('''yes''==''true''', 'Win64', 'Release', Tabla([])) = vSi, 'yes y true: booleanos');
  Assert.IsTrue(EvaluaCondicion('''!off''==''TRUE''', 'Win64', 'Release', Tabla([])) = vSi, '!off es cierto');
  Assert.IsTrue(EvaluaCondicion('''1.0''==''1''', 'Win64', 'Release', Tabla([])) = vSi, '1.0 y 1: numeros');
  Assert.IsTrue(EvaluaCondicion('''0x1''!=''1''', 'Win64', 'Release', Tabla([])) = vNo, '0x1 es 1');
  Assert.IsTrue(EvaluaCondicion('''.5''==''+0.5''', 'Win64', 'Release', Tabla([])) = vSi, '.5 y +0.5');
  Assert.IsTrue(EvaluaCondicion('''true''==''1''', 'Win64', 'Release', Tabla([])) = vNo, 'un booleano no es un numero');
  Assert.IsTrue(EvaluaCondicion(''' 1 ''==''1''', 'Win64', 'Release', Tabla([])) = vNo, 'con blancos no es un numero');
  Assert.IsTrue(EvaluaCondicion('''1e3''==''1000''', 'Win64', 'Release', Tabla([])) = vNo, 'sin exponente');
  Assert.IsTrue(EvaluaCondicion('''%74rue''==''true''', 'Win64', 'Release', Tabla([])) = vSi, '%74 es t');
  Assert.IsTrue(EvaluaCondicion('''$(LbA)''==''a''', 'Win64', 'Release', Tabla(['LbA=%61'])) = vSi, 'desescapado tras expandir');
  // los grupos de un .dproj, en orden de documento
  E := ElementosDe(XML, Mal);
  Otro := ElementosDeOtroBuild(XML, 'Win64', 'Release', E, [], []);
  Assert.IsTrue(DeOtro('PF_KeyStoreDebug'), 'Release/Win64: el grupo de Debug de Android64 es de otro');
  Assert.IsFalse(DeOtro('DCC_UnitSearchPath'), 'los valores de Win64 son de este');
  Assert.IsTrue(DeOtro('DCC_Define'), 'los valores de Debug son de otro en Release');
  Assert.IsFalse(DeOtro('Icon_MainIcon'), 'lo que no se sabe (Exists) se juzga');
  Assert.IsTrue(DeOtro('Manifest_File'), 'la Condition del elemento, de Win32, es de otro');
  Otro := ElementosDeOtroBuild(XML, 'Win64', 'Debug', E, [], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'en Debug, los valores de Debug son de este');
  Otro := ElementosDeOtroBuild(XML, 'Win64', 'Debug2', E, [], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'una config hija de Debug lee los valores de Debug');
  Assert.IsTrue(DeOtro('PF_KeyStoreDebug'), '...y no los de Android64');
  // una bandera plantada en un grupo sin condicion: msbuild lee el grupo
  E := ElementosDe(PLANTADA, Mal);
  Otro := ElementosDeOtroBuild(PLANTADA, 'Win64', 'Release', E, [], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'la bandera plantada: el grupo se lee en cualquier config');
  // un nombre que msbuild toma de fuera (la tabla del build) no se da por vacio
  E := ElementosDe(EXTERNA, Mal);
  Otro := ElementosDeOtroBuild(EXTERNA, 'Win64', 'Release', E, ['BDS'], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'un grupo sobre $(BDS), que viene de rsvars: no se sabe, se juzga');
  // un valor se fija expandido: Tarde vale 'a' aunque Antes cambie despues
  E := ElementosDe(PEREZOSA, Mal);
  Otro := ElementosDeOtroBuild(PEREZOSA, 'Win64', 'Release', E, [], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'Tarde vale a: el grupo se lee');
  // lo de ProjectExtensions y de un Target no cuenta en la pasada, ni para
  // las banderas ni para el lector
  E := ElementosDe(ANIDADA, Mal);
  Otro := ElementosDeOtroBuild(ANIDADA, 'Win64', 'Release', E, [], []);
  Assert.IsFalse(DeOtro('DCC_Define'), 'Puerta sigue a 1: el grupo se lee');
  Assert.AreEqual('r', EffectiveProperty(ANIDADA, 'DCC_ExeOutput', 'Win64', 'Release'), 'el lector no lee el grupo del Target');
  // una global del build: aunque el documento la ponga, no se sabe y se juzga
  E := ElementosDe(GLOBAL, Mal);
  Otro := ElementosDeOtroBuild(GLOBAL, 'Win64', 'Release', E, [], ['Profile']);
  Assert.IsFalse(DeOtro('DCC_Define'), 'Profile es global: no se sabe, se juzga');
  Otro := ElementosDeOtroBuild(GLOBAL, 'Win64', 'Release', E, [], []);
  Assert.IsTrue(DeOtro('DCC_Define'), 'sin globales, el documento manda: p no es vacio');
  Assert.IsTrue(Length(PropiedadesDefinidas(E)) = 2, 'Profile y DCC_Define: ' + IntToStr(Length(PropiedadesDefinidas(E))));
  // los trozos de una lista
  Assert.IsTrue(Length(TrozosDeLista(' a; ;b ;;c')) = 3, 'sin vacios ni blancos');
end;

{ Un .dproj con los grupos en el orden en que los escribe el IDE (medido el
  21-oct-2026 en uno suyo): los definidores por clave - Base y sus
  plataformas, Cfg_1 y las suyas, Cfg_2 - y luego los valores en el mismo
  orden; Win64 solo tiene grupos de Base, Release ninguno de plataforma, y
  Debug2 (Cfg_3) esta declarada SIN su definidor. }
function XmlDeIde: string;

  function Def(const APlat, AClave: string): string;
  begin
    Result := XmlGrupoDefinidor(APlat, AClave) + sLineBreak;
  end;

  function CfgDef(const ACfg, AClave: string): string;
  begin
    Result := XmlGrupoDefinidorDeConfig(ACfg, AClave) + sLineBreak;
  end;

  function Val(const APlat, AClave, AProps: string): string;
  begin
    Result := XmlGrupoDeValores(APlat, AClave, AProps) + sLineBreak;
  end;

begin
  Result := '<Project>' + sLineBreak +
    '    <ItemGroup>' +
    '<BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Debug"><Key>Cfg_1</Key><CfgParent>Base</CfgParent></BuildConfiguration>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key><CfgParent>Base</CfgParent></BuildConfiguration>' +
    '<BuildConfiguration Include="Debug2"><Key>Cfg_3</Key><CfgParent>Cfg_1</CfgParent></BuildConfiguration>' +
    '</ItemGroup>' + sLineBreak +
    '    <PropertyGroup>' + XmlElemento('Base', 'True') + '</PropertyGroup>' + sLineBreak +
    CfgDef('Base', 'Base') + Def('Win32', 'Base') + Def('Win64', 'Base') +
    CfgDef('Debug', 'Cfg_1') + Def('Win32', 'Cfg_1') +
    CfgDef('Release', 'Cfg_2') +
    Val('', 'Base', '        <DCC_E>false</DCC_E>' + sLineBreak) +
    Val('Win32', 'Base', '') + Val('Win64', 'Base', '') +
    Val('', 'Cfg_1', '        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>' + sLineBreak) +
    Val('Win32', 'Cfg_1', '') +
    Val('', 'Cfg_2', '') +
    '</Project>';
end;

{ Donde empieza el grupo con esa Condition; falla si no esta. }
function PosDe(const AXml, ACondicion: string): Integer;
var
  G: TGrupoXml;
begin
  Assert.IsTrue(GrupoConCondicion(AXml, ACondicion, G), 'no esta el grupo ' + ACondicion);
  Result := G.Abre;
end;

procedure TXmlTextoTests.ElGrupoDelBuildDondeLoEscribeElIde;
var
  Xml, X: string;
  G: TGrupoXml;
  Falta: TFaltaDeGrupo;
begin
  Xml := XmlDeIde;
  // lo que hay se encuentra, lo que no, no
  Assert.IsTrue(GrupoDelBuild(Xml, 'Win64', '', G), 'Base_Win64');
  Assert.IsTrue(GrupoDelBuild(Xml, '', 'Debug', G), 'Cfg_1');
  Assert.IsFalse(GrupoDelBuild(Xml, 'Win64', 'Debug', G), 'Cfg_1_Win64 no esta');
  Assert.IsFalse(GrupoDelBuild(Xml, '', 'Nope', G), 'una config que no declara');
  // una config que no declara, y una declarada sin su definidor
  Assert.IsFalse(AseguraGrupoDelBuild(Xml, 'Win64', 'Nope', G, Falta));
  Assert.IsTrue(Falta = fgConfigNoDeclarada, 'Nope: no declarada');
  Assert.IsFalse(AseguraGrupoDelBuild(Xml, '', 'Debug2', G, Falta));
  Assert.IsTrue(Falta = fgSinDefinidor, 'Debug2 (Cfg_3) sin su definidor');
  // lo que ya esta no cambia nada
  X := Xml;
  Assert.IsTrue(AseguraGrupoDelBuild(Xml, '', 'Release', G, Falta));
  Assert.AreEqual(X, Xml, 'Cfg_2 ya estaba');
  // Win64/Debug: el definidor de Cfg_1_Win64 tras el de Cfg_1_Win32 y antes
  // del de Cfg_2; los valores tras los de Cfg_1_Win32 y antes de los de Cfg_2
  Assert.IsTrue(AseguraGrupoDelBuild(Xml, 'Win64', 'Debug', G, Falta), 'crea Cfg_1_Win64');
  Assert.IsTrue(Xml.Contains(XmlGrupoDefinidor('Win64', 'Cfg_1')), 'EL definidor, el del IDE: ' + Xml);
  Assert.IsTrue(Xml.Contains(XmlGrupoDeValores('Win64', 'Cfg_1', '')), 'EL grupo de valores, el del IDE');
  Assert.IsTrue((PosDe(Xml, DefinerCondition('Win64', 'Cfg_1')) > PosDe(Xml, DefinerCondition('Win32', 'Cfg_1'))) and
    (PosDe(Xml, DefinerCondition('Win64', 'Cfg_1')) < PosDe(Xml, ConfigDefinerCondition('Release', 'Cfg_2'))),
    'el definidor, tras los de su clave: ' + Xml);
  Assert.IsTrue((PosDe(Xml, GroupCondition('Win64', 'Cfg_1')) > PosDe(Xml, GroupCondition('Win32', 'Cfg_1'))) and
    (PosDe(Xml, GroupCondition('Win64', 'Cfg_1')) < PosDe(Xml, GroupCondition('', 'Cfg_2'))),
    'los valores, tras los de su clave: ' + Xml);
  Assert.IsTrue(G.Abre = PosDe(Xml, GroupCondition('Win64', 'Cfg_1')), 'devuelve el grupo creado');
  // Linux64 (Base): el definidor tras el de Base_Win64 y antes del de Cfg_1;
  // los valores tras los de Base_Win64 y antes de los de Cfg_1
  Assert.IsTrue(AseguraGrupoDelBuild(Xml, 'Linux64', '', G, Falta), 'crea Base_Linux64');
  Assert.IsTrue((PosDe(Xml, DefinerCondition('Linux64')) > PosDe(Xml, DefinerCondition('Win64'))) and
    (PosDe(Xml, DefinerCondition('Linux64')) < PosDe(Xml, ConfigDefinerCondition('Debug', 'Cfg_1'))),
    'el definidor de Base_Linux64: ' + Xml);
  Assert.IsTrue((PosDe(Xml, GroupCondition('Linux64')) > PosDe(Xml, GroupCondition('Win64'))) and
    (PosDe(Xml, GroupCondition('Linux64')) < PosDe(Xml, GroupCondition('', 'Cfg_1'))),
    'los valores de Base_Linux64: ' + Xml);
  // Android64/Release: tras todo lo de Cfg_2, lo ultimo, y los definidores
  // siempre antes que los valores
  Assert.IsTrue(AseguraGrupoDelBuild(Xml, 'Android64', 'Release', G, Falta), 'crea Cfg_2_Android64');
  Assert.IsTrue(PosDe(Xml, DefinerCondition('Android64', 'Cfg_2')) > PosDe(Xml, ConfigDefinerCondition('Release', 'Cfg_2')),
    'el definidor de Cfg_2_Android64, tras el de Release');
  Assert.IsTrue(PosDe(Xml, DefinerCondition('Android64', 'Cfg_2')) < PosDe(Xml, GroupCondition('')),
    'los definidores van antes que los valores');
  Assert.IsTrue(PosDe(Xml, GroupCondition('Android64', 'Cfg_2')) > PosDe(Xml, GroupCondition('', 'Cfg_2')),
    'los valores de Cfg_2_Android64, tras los de Release');
end;

procedure TXmlTextoTests.PonPropiedadDelBuildEnLasCuatroFormas;
var
  Xml, X, Antes: string;
  Falta: TFaltaDeGrupo;
begin
  Xml := XmlDeIde;
  // la base, una plataforma, una config y la pareja (su grupo, creado): cada
  // una en SU grupo, y EffectiveProperty, el lector, lee cada una donde msbuild
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'base', '', '', False, Antes, Falta), 'la base');
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'w64', 'Win64', '', False, Antes, Falta), 'Win64');
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'dbg', '', 'Debug', False, Antes, Falta), 'Debug');
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'w64dbg', 'Win64', 'Debug', False, Antes, Falta), 'Win64 Debug, con su grupo creado');
  Assert.AreEqual('', Antes, 'no habia');
  Assert.IsTrue(Length(AllTagValues(Xml, 'PF_X')) = 4, Xml);
  Assert.AreEqual('w64dbg', EffectiveProperty(Xml, 'PF_X', 'Win64', 'Debug'));
  Assert.AreEqual('dbg', EffectiveProperty(Xml, 'PF_X', 'Win32', 'Debug'));
  Assert.AreEqual('w64', EffectiveProperty(Xml, 'PF_X', 'Win64', 'Release'));
  Assert.AreEqual('base', EffectiveProperty(Xml, 'PF_X', 'Win32', 'Release'));
  // la nueva al principio del grupo, escapada (XmlElemento), y lo que valia
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'R&D', 'Win64', '', False, Antes, Falta));
  Assert.AreEqual('w64', Antes, 'lo que valia');
  Assert.AreEqual('R&D', EffectiveProperty(Xml, 'PF_X', 'Win64', 'Release'));
  Assert.IsTrue(Xml.Contains('<PropertyGroup ' + XmlAtributo('Condition', GroupCondition('Win64')) + '>' +
    sLineBreak + '        ' + XmlElemento('PF_X', 'R&D')), 'al principio del grupo: ' + Xml);
  // el mismo valor una sola vez: no toca nada
  X := Xml;
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'R&D', 'Win64', '', False, Antes, Falta));
  Assert.AreEqual(X, Xml, 'ya estaba');
  Assert.AreEqual('R&D', Antes);
  // dos en el grupo (una vacia): se van las dos y queda la nueva
  Xml := Xml.Replace(XmlElemento('PF_X', 'base'), XmlElemento('PF_X', 'base') + '<PF_X/>');
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', 'b2', '', '', False, Antes, Falta));
  Assert.AreEqual('', Antes, 'la ultima, la vacia');
  Assert.IsTrue(Length(AllTagValues(Xml, 'PF_X')) = 4, 'una por grupo: ' + Xml);
  Assert.AreEqual('b2', EffectiveProperty(Xml, 'PF_X', 'Win32', 'Release'));
  // quitar: se va con su linea y el build toma lo que queda; de un grupo
  // que no existe, nada, y no se crea
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', '', 'Win64', 'Debug', True, Antes, Falta));
  Assert.AreEqual('w64dbg', Antes);
  Assert.AreEqual('dbg', EffectiveProperty(Xml, 'PF_X', 'Win64', 'Debug'), 'toma la de Debug');
  Assert.IsFalse(Xml.Contains('w64dbg'), 'se fue: ' + Xml);
  X := Xml;
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'PF_X', '', 'Linux64', 'Release', True, Antes, Falta));
  Assert.AreEqual(X, Xml, 'quitar de un grupo que no existe no lo crea');
  Assert.AreEqual('', Antes);
  // una config que no declara, al poner y al quitar
  Assert.IsFalse(PonPropiedadDelBuild(Xml, 'PF_X', 'x', '', 'Nope', False, Antes, Falta));
  Assert.IsTrue(Falta = fgConfigNoDeclarada, 'poner en Nope');
  Assert.IsFalse(PonPropiedadDelBuild(Xml, 'PF_X', '', '', 'Nope', True, Antes, Falta));
  Assert.IsTrue(Falta = fgConfigNoDeclarada, 'quitar de Nope');
end;

procedure TXmlTextoTests.DosGruposConLaMismaCondicionYLaClaveRara;
var
  Xml, Antes: string;
  G: TGrupoXml;
  Falta: TFaltaDeGrupo;
begin
  // dos grupos con la misma Condition: msbuild los aplica los dos y gana el
  // ULTIMO; el escritor escribe en ese y quita la copia del otro, y un
  // elemento con SU Condition se queda y sigue ganando donde se cumple
  // (revisores B y D, 21-oct-2026)
  Xml := '<Project><ItemGroup><BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key><CfgParent>Base</CfgParent></BuildConfiguration></ItemGroup>' +
    CadenaDelIde(['Win64'], ['Release=Cfg_2']) +
    XmlGrupoDeValores('', 'Cfg_2', '        <X>viejo</X>' + sLineBreak) +
    XmlGrupoDeValores('', 'Cfg_2', '        <X>ultimo</X>' + sLineBreak +
      '        <X Condition="''$(Platform)''==''Win32''">w32</X>' + sLineBreak) + '</Project>';
  Assert.AreEqual('ultimo', EffectiveProperty(Xml, 'X', 'Win64', 'Release'), 'el ultimo gana');
  Assert.AreEqual('w32', EffectiveProperty(Xml, 'X', 'Win32', 'Release'), 'el elemento con Condition, en Win32');
  Assert.IsTrue(GrupoDelBuild(Xml, '', 'Release', G) and (G.Abre > Pos('viejo', Xml)), 'el ultimo grupo');
  Assert.IsTrue(PonPropiedadDelBuild(Xml, 'X', 'nuevo', '', 'Release', False, Antes, Falta));
  Assert.AreEqual('ultimo', Antes, 'lo que valia en el ultimo');
  Assert.IsFalse(Xml.Contains('viejo'), 'la copia del primer grupo se fue: ' + Xml);
  Assert.IsTrue(Xml.Contains('w32'), 'el elemento con su Condition se queda: ' + Xml);
  Assert.IsTrue(Length(AllTagValues(Xml, 'X')) = 2, 'la nueva y la condicionada: ' + Xml);
  Assert.AreEqual('nuevo', EffectiveProperty(Xml, 'X', 'Win64', 'Release'));
  Assert.AreEqual('w32', EffectiveProperty(Xml, 'X', 'Win32', 'Release'), 'en Win32 sigue ganando la condicionada');
  // una clave que msbuild no admite como nombre de propiedad (medido el
  // 21-oct-2026: un '.' es MSB5016, un '-' compila): no se escribe un grupo
  // con ella, y el nombrador de nombres es el mismo que juzga name=
  Assert.IsFalse(EsNombreDeEtiqueta('Foo.Bar'), 'con punto');
  Assert.IsTrue(EsNombreDeEtiqueta('Foo-Bar'), 'con guion');
  Xml := XmlDeIde.Replace('<Key>Cfg_2</Key>', '<Key>Cfg 2</Key>');
  Assert.IsFalse(AseguraGrupoDelBuild(Xml, 'Win64', 'Release', G, Falta));
  Assert.IsTrue(Falta = fgClaveInvalida, 'Cfg 2: clave invalida');
end;

procedure TXmlTextoTests.ElParserDelIdeJuzgaLoCompuesto;
begin
  // el juez de "bien formado" de lo que el escaner compone en sitio: MSXML 6,
  // el parser con que el IDE carga un proyecto (David, 21-oct-2026)
  Assert.AreEqual('', XmlMalFormadoSegunElIde('<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project><PropertyGroup><A>R&amp;D</A><B/></PropertyGroup></Project>'), 'un .dproj como el del IDE');
  Assert.AreEqual('', XmlMalFormadoSegunElIde(#$FEFF'<Project/>'), 'con el BOM delante');
  Assert.IsTrue(XmlMalFormadoSegunElIde('<Project><A>x</Project>') <> '', 'una etiqueta sin cerrar');
  Assert.IsTrue(XmlMalFormadoSegunElIde('<Project><A>R&D</A></Project>') <> '', 'un & sin escapar');
  Assert.IsTrue(XmlMalFormadoSegunElIde('<Project/><Project/>') <> '', 'dos raices');
  Assert.IsTrue(XmlMalFormadoSegunElIde('<Project><A>x</A></Project>') = '', 'y la buena, en el mismo hilo tras las malas');
end;

procedure TXmlTextoTests.LosValoresDelBuildSeExpandenEnSuPunto;
const
  // lo que el build lee, expandido como msbuild lo tiene en cada punto: una
  // propiedad vale lo ultimo puesto ANTES de donde se lee (vacio si aun no
  // se puso, y lo del proyecto sobre lo de fuera), lo de fuera (la tabla)
  // queda escrito para quien lo sabe, un Include vale lo del final, y lo
  // que no se sabe si se aplica (Exists) o una global del build es duda (los
  // tres agujeros de la puerta medidos el 22-oct-2026)
  DOC = '<Project>' +
    '<PropertyGroup><Primera>..</Primera><S1>$(Primera)\x</S1><Primera>y</Primera><S2>$(Primera)\x</S2></PropertyGroup>' +
    '<PropertyGroup><Ide>$(BDS)\lib</Ide><S3>$(Ide)\s</S3><Vacia></Vacia><S4>$(Vacia)\v</S4></PropertyGroup>' +
    '<PropertyGroup Condition="Exists(''m'')"><Escondida>..</Escondida></PropertyGroup>' +
    '<PropertyGroup><S5>$(Escondida)\e</S5><S6>$(Despues)\z</S6><Despues>q</Despues><S7>$(Profile)\p</S7>' +
    '<DCC_UnitSearchPath>a;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    '<DCC_UnitSearchPath>b;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Debug''"><S8>$(Despues)\d</S8></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="$(Despues)\i.pas"/><DCCReference Include="$(Escondida)\j.pas"/></ItemGroup>' +
    '</Project>';
var
  Valores: TArray<TValorDelProyecto>;

  function De(const AElemento, AEscrito: string): TValorDelProyecto;
  begin
    for var V in Valores do
      if SameText(V.Elemento, AElemento) and ((AEscrito = '') or (V.Escrito = AEscrito)) then
        Exit(V);
    raise Exception.Create('no esta ' + AElemento);
  end;

  function Hay(const AElemento: string): Boolean;
  begin
    Result := False;
    for var V in Valores do
      if SameText(V.Elemento, AElemento) then
        Exit(True);
  end;

begin
  Valores := ValoresQueLeeElBuild(DOC, 'Win64', 'Release', ['BDS'], ['Profile']);
  Assert.AreEqual('..\x', De('S1', '').Expandido, 'Primera vale .. donde S1 la lee');
  Assert.AreEqual('y\x', De('S2', '').Expandido, '...y y donde S2 la lee: msbuild fija cada valor al definirlo');
  Assert.AreEqual('$(BDS)\lib\s', De('S3', '').Expandido, 'lo de la tabla queda escrito para quien lo sabe, dentro de lo que el documento si sabe');
  Assert.AreEqual('', De('S3', '').Dudoso, '...y no es duda');
  Assert.AreEqual('\v', De('S4', '').Expandido, 'una propiedad puesta vacia vale vacio');
  Assert.AreEqual('Escondida', De('S5', '').Dudoso, 'puesta bajo una Condition que no se sabe evaluar: duda');
  Assert.AreEqual('\z', De('S6', '').Expandido, 'aun no definida donde S6 la lee: vacio');
  Assert.AreEqual('Profile', De('S7', '').Dudoso, 'una global del build: duda');
  Assert.AreEqual('b;a;', De('DCC_UnitSearchPath', 'b;$(DCC_UnitSearchPath)').Expandido, 'la autorreferencia acumula lo de antes');
  Assert.IsFalse(Hay('S8'), 'el grupo de Debug no es de este build');
  Assert.AreEqual('q\i.pas', De('DCCReference', '$(Despues)\i.pas').Expandido, 'un Include, con lo que vale al final');
  Assert.AreEqual('Escondida', De('DCCReference', '$(Escondida)\j.pas').Dudoso, '...y con su duda');
  Assert.AreEqual('..', De('Escondida', '').Escrito, 'lo que no se sabe si se aplica se juzga tambien');
end;

procedure TXmlTextoTests.LaPropiedadEfectivaNoSeHaceLenta;
const
  CLAVES: array [0 .. 2] of string = ('Base', 'Cfg_1', 'Cfg_2');
var
  Xml, Props, V: string;
  Plats: TArray<string>;
  T0, Ms: Cardinal;
begin
  // el lector evalua como msbuild (ElementosDe + VeredictosDeElementos por
  // lectura) y los ajustes del motor piden cuatro o cinco por peticion: un
  // .dproj grande, como el de 117 KB que se midio el 18-oct-2026 (7 ms por
  // propiedad con el lector por nombre), con 21 grupos de 150 propiedades
  Props := '';
  for var I := 1 to 150 do
    Props := Props + '        ' + XmlElemento('Prop_' + IntToStr(I), 'valor ' + IntToStr(I)) + sLineBreak;
  Plats := ['Win32', 'Win64', 'Linux64', 'Android64', 'OSX64', 'iOSDevice64'];
  Xml := '<Project>' + CadenaDelIde(Plats, ['Debug=Cfg_1', 'Release=Cfg_2']);
  for var Clave in CLAVES do
  begin
    Xml := Xml + XmlGrupoDeValores('', Clave, Props);
    for var Plat in Plats do
      Xml := Xml + XmlGrupoDeValores(Plat, Clave, Props);
  end;
  Xml := Xml + '</Project>';
  Assert.IsTrue(Length(Xml) > 100000, 'el fixture es grande: ' + IntToStr(Length(Xml)));
  T0 := TThread.GetTickCount;
  for var I := 1 to 5 do
    V := EffectiveProperty(Xml, 'Prop_7', 'Win64', 'Debug');
  Ms := TThread.GetTickCount - T0;
  Assert.AreEqual('valor 7', V);
  TDUnitX.CurrentRunner.Status(Format('EffectiveProperty x5 en un .dproj de %d KB: %d ms', [Length(Xml) div 1024, Ms]));
  // el tope: una guarda contra una regresion patologica (segundos), no una
  // medida fina: GetTickCount tiene 16 ms de grano y una maquina cargada
  // (una regresion corriendo) multiplica lo medido (revisor C, 21-oct-2026)
  Assert.IsTrue(Ms < 2000, Format('%d ms para cinco lecturas', [Ms]));
end;

procedure TXmlNucleoTests.LaPlataformaDelMotorLaDiceLaTabla;
begin
  // P9 de la revision de la 1.22.0: Win32 y Win64 tal cual, con el nombre de
  // la tabla; el resto como Win32, tambien las de Windows que no se dan al
  // motor (era un SameText con dos literales en Lsp.ConfigFabricator)
  Assert.AreEqual('Win32', PlataformaParaElMotor('Win32'));
  Assert.AreEqual('Win64', PlataformaParaElMotor('win64'));
  Assert.AreEqual('Win32', PlataformaParaElMotor('WinARM64EC'));
  Assert.AreEqual('Win32', PlataformaParaElMotor('Linux64'));
  Assert.AreEqual('Win32', PlataformaParaElMotor('NoExiste'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojHazardTests);
  TDUnitX.RegisterTestFixture(TXmlTextoTests);
  TDUnitX.RegisterTestFixture(TXmlNucleoTests);

end.
