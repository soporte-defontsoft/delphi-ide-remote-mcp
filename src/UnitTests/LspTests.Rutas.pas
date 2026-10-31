unit LspTests.Rutas;

// La forma DECLARADA de una ruta que llega resuelta, en sus dos usos
// (Lsp.Lugares): FormaDeclaradaDe sobre UNA ruta - lo que git contesta cuando
// se le pregunta donde vive un repo - y FormaDeclaradaEnTexto sobre un texto,
// que es lo que el enmascarador hace con la salida antes de su barrido.
// git dice la ruta real, y la de un sitio declarado en una letra de red es su
// UNC: la puerta, que juzga por la forma declarada, contestaba GIT-041
// (medido el 30-sep-2026 en una maquina con las raices en una letra de red).
// Aqui las dos reglas sin la maquina: las listas (lo declarado y su ruta de
// red) se dan a mano, con nombres que no son de ninguna maquina de la casa.
// Con git y una unidad conectada de verdad lo mide test_git_jaula (J17).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormaDeclaradaTests = class
  public
    [Test] procedure ElUncDeUnaLetraDeRedVuelveConLaLetra;
    [Test] procedure LaRaizMismaYConBarrasNormales;
    [Test] procedure LaRaizDeLaUnidadLlevaSuBarra;
    [Test] procedure UnUncDeNingunSitioNoSeToca;
    [Test] procedure UnaRutaConLetraNoSeToca;
    [Test] procedure ElSitioDeclaradoEnUncNoSeTraduce;
    [Test] procedure ElSitioLocalNoSeTraduce;
    [Test] procedure ElPrefijoNoEsLaCarpeta;
    [Test] procedure DeDosQueCasanElMasHondo;
  end;

  [TestFixture]
  TFormaDeclaradaEnTextoTests = class
  public
    [Test] procedure LoQueEscribeGit;
    [Test] procedure ConBarrasDeWindowsYDentroDeUnJson;
    [Test] procedure LaPistaParaElOperadorNoSeToca;
    [Test] procedure NiUnaUrlNiPegadaAUnaPalabra;
    [Test] procedure ElPrefijoNoEsLaCarpeta;
    [Test] procedure DondeAcabaLaRuta;
    [Test] procedure VariasEnUnTextoYLaMasHonda;
    [Test] procedure LaRaizDeLaUnidadLlevaSuBarra;
    [Test] procedure TrasUnSaltoDeLineaDeJson;
    [Test] procedure SinSitiosDeRedElTextoEsElMismo;
    [Test] procedure UnaCasaConLetraPorSuNombre;
    [Test] procedure LaCasaSoloComoRutaEntera;
    [Test] procedure UnaRaizQueEmpiezaComoLaCasaSeQueda;
  end;

  { El barrido del enmascarador de salida sobre un texto que ya es JSON: alli
    un salto de linea son los caracteres \ y n, y lo que abre la linea
    siguiente - una ruta con letra, una ruta de red - no esta pegado a una
    palabra. Y una barra ESCRITA (dos) delante de una n, una r o una t no es
    un salto: es una carpeta de una letra. Las dos reglas del salto estaban
    sin una prueba que saliese roja, y la de la ruta de red no se cumplia
    (apuntado en la 1.8.2). La unidad es la del ejecutable de pruebas: la de
    su raiz, que es la que este proceso sirve. }
  [TestFixture]
  TBarridoDeUnidadesTests = class
  public
    [Test] procedure LaRutaQueAbreLineaEnUnJsonSeEnmascara;
    [Test] procedure LaCacheDelServidorEnSusFormas;
    [Test] procedure LaCasaDentroDeSuRaizNoSeToca;
    [Test] procedure ElUncQueAbreLineaEnUnJsonSeEnmascara;
    [Test] procedure UnaCarpetaDeUnaLetraNoEsUnSaltoDeLinea;
    [Test] procedure ElUncDeUnaListaDeRutasSeEnmascara;
    [Test] procedure ElUncPegadoAUnaOpcionSeEnmascara;
    [Test] procedure ElUncDobladoDosVecesSeEnmascara;
    [Test] procedure ElUncExtendidoYElHostRaroSeEnmascaran;
    [Test] procedure LasClavesDeUnJsonTambienSeEnmascaran;
    [Test] procedure LaFilaDeUnaTandaDejaElDiscoComoEsta;
    [Test] procedure LasCitasDeUnJsonVanComoEstan;
    [Test] procedure LosControlesSonAnomaliasPorSiMismos;
    [Test]
    procedure UnaCitaConSuCrVaComoEsta;
    [Test]
    procedure LosNombresDeDispositivoDocumentadosSonAnomalias;
    [Test]
    procedure SoloLaEtiquetaConNombreEsUnEnlace;
  end;

  { LA clave de una carpeta (Lsp.Casa.ClaveDeCarpeta): la misma carpeta
    escrita con otras mayusculas, tambien fuera de A-Z, o con la barra final,
    da la misma clave - la marca de los contenedores de delphi_test y el
    cerrojo de la primera instancia salen de ella (revision de la 1.11.0:
    LowerCase solo plegaba A-Z). }
  [TestFixture]
  TClaveDeCarpetaTests = class
  public
    [Test] procedure OtrasMayusculasFueraDeAZDanLaMismaClave;
    [Test] procedure LaBarraFinalNoCambiaLaClave;
  end;

  { V204 de la 1.23.1: el Include de un proyecto se resuelve por EL resolutor
    (RutaDeInclude), desde la carpeta del proyecto. Tres sitios lo hacian con
    TPath.Combine, que deja 'X:Comun\U.pas' a la carpeta actual del PROCESO en
    esa unidad: ProyectoListaUnidad (el proyecto del motor, ProjectsUsingUnit)
    decia que el proyecto no lista una unidad que si lista. }
  [TestFixture]
  TIncludeDelProyectoTests = class
  public
    [Test] procedure UnIncludeRelativoALaUnidadSeLeeDesdeElProyecto;
  end;

  { EL sello de una operacion (Lsp.Casa.SelloUnico): su texto se ordena como
    nacio, tambien dentro de un tick del reloj (la purga de las copias del IDE
    se queda con las mas nuevas por el nombre; test_sdk fallaba "por azar"). }
  [TestFixture]
  TSelloUnicoTests = class
  public
    [Test] procedure CadaSelloVaDetrasDelAnterior;
    [Test] procedure ElTextoEsElQueLeeSuPatron;
    { EL nombrador de capturas: en nuestra casa (sin out=), solo un PNG - lo
      que viaja y se consume (2ai-B c de la 1.18.2) }
    [Test] procedure EnLaCasaSoloLoQueViaja;
  end;

  { LA PUERTA DE LEER (Lsp.Patch.LugarDeLecturaDenegado, LeeTexto, LeeBytes)
    en los lugares que no dependen de la maquina: el temporal y la casa del
    servidor, que son del ejecutor (su carpeta). La jaula y el IDE los mide la
    bateria a traves del servidor (test_build_imports: un Import de fuera).
    Un ENLACE se mide aqui solo en los lugares del servidor, que se juzgan
    por atributos (EnLugarSinEnlaces): en el contenedor de delphi_test
    GetFinalPathNameByHandle con letra o GUID da ACCESS_DENIED (solo la forma
    NT contesta, medido el 9-oct-2026) y RealPath se queda alli con el texto;
    los de la ruta real los mide la bateria (test_messages, la jaula). }
  [TestFixture]
  TPuertaDeLeerTests = class
  private
    FDir, FNota, FUnion: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure EnSuLugarSeLeeYEnOtroNo;
    [Test] procedure UnEnlaceNoSacaANadieDeSuSitio;
    [Test] procedure SettingsIniNoEsDeLaCasaYElBuzonSi;
    [Test] procedure UnaCasaRelativaNoEsLugar;
    [Test] procedure LaBibliotecaDelIdeSeLeeYNoSeEscribe;
    [Test] procedure ElComparadorDeLugaresVaPorLaRutaReal;
  end;

  { LA PUERTA DE ESCRIBIR (Lsp.Patch.LugarDeEscrituraDenegado, EscribeTexto)
    en los mismos lugares del ejecutor: entero o nada (ni un temporal de
    sustitucion al lado), con su codificacion, y un enlace en el camino no
    lleva la escritura detras. Del IDE, lo que no depende de lo que tenga
    registrado: su instalacion se lee y NUNCA se escribe. Lo que se pisa o
    se borra en el IDE con copia lo mide test_sdk (remove-sdk). }
  [TestFixture]
  TPuertaDeEscribirTests = class
  private
    FDir, FUnion, FVictima: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure EnSuLugarSeEscribeEnteroYConSuCodificacion;
    [Test] procedure UnEnlaceNoLlevaLaEscrituraDetras;
    [Test] procedure SettingsIniNoSeEscribe;
    [Test] procedure LaInstalacionDelIdeSeLeePeroNoSeEscribe;
    [Test] procedure SustituirConservaLaFechaDeCreacion;
    [Test] procedure EscribirLoMismoNoReescribe;
    [Test] procedure LaJaulaNoSeBorraPorAqui;
  end;

  { Una ruta en una letra LOCAL no esta en un lugar de RED - un UNC, una letra
    que no es local - y se dice sin mirar ese lugar en el disco (B-10: un
    vault en una letra de red caida eran 21 s por escritura, medido en bruto).
    La letra de las rutas locales es la del ejecutable de pruebas; la de red,
    una que esta maquina no tiene, o el UNC de TEST-NET, que nunca contesta. }
  [TestFixture]
  TLugarDeRedTests = class
  public
    [Test] procedure UnUncNoContieneUnaRutaLocal;
    [Test] procedure UnaLetraQueNoEstaNoContieneUnaRutaLocal;
    [Test] procedure LaMismaLetraSeMiraEnElDisco;
    [Test] procedure UnaRutaDeRedSeMiraSiempre;
    [Test] procedure EnAlgunLugarNoPreguntaAlRecursoDeRed;
  end;

  { EL resolutor de una ruta leida de un fichero (Lsp.Rutas.RutaDesde): la
    regla de Windows para un proceso cuya carpeta actual es la base, la de
    quien lee la ruta. "\x" y "X:y" se resolvian contra el PROCESO del
    servidor (A9 de la 1.23; en vivo lo mide test_rutas_a_medias_1230). Las
    letras no tienen que existir: nada de esto toca el disco. }
  [TestFixture]
  TRutaDesdeTests = class
  public
    [Test] procedure LaCompletaTalCual;
    [Test] procedure LaRelativaDesdeLaBase;
    [Test] procedure LaDeRaizEnLaUnidadDeLaBase;
    [Test] procedure LaDeUnidadSoloSiEsLaDeLaBase;
    [Test] procedure SinBaseSoloLaCompleta;
    [Test] procedure LoQueNoEsRutaNoSeResuelve;
    { lo relativo, desde la carpeta del fichero; "\x" y "X:y", desde la del
      lector (dcc abre un $I relativo desde el fuente y lo demas desde la
      carpeta del .dproj: A9b) }
    [Test] procedure LaCarpetaActualParaLoAMedias;
    [Test] procedure QueEsUnaRutaAMedias;
  end;

  { LA forma de texto de una ruta (A40 de la 1.23): las preguntas sobre una
    ruta que llega de cualquier sitio la miran con barras de Windows, y nadie
    que las llame puede olvidarse de normalizar. EnCopiaDelIde partia el texto
    con ExtractFileDir, que no ve la '/' (fallo de A10, visto al revisar el
    diff), y EsUnc solo miraba '\\'. }
  [TestFixture]
  TFormaDeTextoTests = class
  public
    [Test] procedure UnaCopiaDelIdeConBarrasNormales;
    [Test] procedure UnUncConBarrasNormales;
  end;

  { LA subida por carpetas (A11 de la 1.23): once bucles a mano, cada uno con
    su parada en la raiz, y tres topes distintos para la misma busqueda. }
  [TestFixture]
  TAncestrosTests = class
  public
    [Test] procedure HastaLaRaizDeLaUnidad;
    [Test] procedure HastaLaRaizDeUnRecurso;
    [Test] procedure ConTope;
    [Test] procedure LoQueNoEsRuta;
  end;

  { El fichero de un perfil (Lsp.Discovery.HostDePerfil, PlataformaDePerfil)
    solo se abre si el IDE lista ese perfil, por su nombre de la lista: con
    un '..' en el nombre se miraba cualquier .profile del disco, y la negativa
    distinguia "no existe" de "no se lee" (V8 de la 1.23, medido contra
    produccion por delphi_desktop). La puerta de la llamada, aparte: la mide
    test_perfil_por_lista_1230. }
  [TestFixture]
  TPerfilPorLaListaTests = class
  public
    [Test] procedure SoloElQueElIdeLista;
  end;

  { Lo de V19 de la 1.23 que se mide sin servidor: el sitio en disco antes de
    copiar o mover (EspacioDenegado, con su MARGEN_DISCO_LIBRE) y el comodin
    solo en el NOMBRE (TieneComodin, CarpetaDelComodin). El espacio se mide
    con lo que Windows dice libre en la casa del ejecutor, nunca escribiendo
    ni un fichero disperso: un mutante destructivo jamas llena un disco real. }
  [TestFixture]
  TMudanzaDeOperadorTests = class
  public
    [Test] procedure ElSitioPideSuMargen;
    [Test] procedure UnaCarpetaQueNoExisteMideLaDeArriba;
    [Test] procedure ElComodinSoloEnElNombre;
  end;

  // tres decisiones de jaula con UN lector (V174, V178, V171)
  [TestFixture]
  TLectoresDeJaulaTests = class
  public
    [Test] procedure LaRaizMasHondaNoDependeDelOrden;
    [Test] procedure LaRaizMasHondaPorLasDosFormas;
    [Test] procedure UnNombreSueltoLoJuzgaWindows;
    [Test] procedure UnaUnidadVirtualBajoSuLetra;
    [Test] procedure LasOperacionesDePaclient;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Lsp.Guard,
  Lsp.Casa,
  Lsp.Lugares,
  Lsp.Patch,          // las puertas de leer y de escribir
  Lsp.Codificacion,   // ekUtf8Bom
  Lsp.Discovery,      // la instalacion del IDE
  Lsp.Rutas,          // EsRutaAbsoluta, RutaDesde
  Lsp.Pascal,         // EsNombreSueltoEn
  Lsp.RemoteRun,      // los compositores de paclient
  Lsp.ProcessLaunch,  // ComillasSinEscape
  Lsp.ProjectUnits,   // ProyectoListaUnidad (V204)
  LspTests.FormRender, // CreaUnion
  Lsp.Mascara,
  System.RegularExpressions,
  System.JSON,
  Lsp.Reparse;

// dos raices en una letra de red (L: conectada a \\servidor\Recurso)
function D: TArray<string>;
begin
  Result := TArray<string>.Create('L:\Proyectos\', 'L:\Sandbox\tests\');
end;

function R: TArray<string>;
begin
  Result := TArray<string>.Create('\\servidor\Recurso\Proyectos', '\\servidor\Recurso\Sandbox\tests');
end;

// la unidad entera como raiz, y otra letra conectada mas adentro del recurso
function DRaiz: TArray<string>;
begin
  Result := TArray<string>.Create('L:\', 'M:\tests\');
end;

function RRaiz: TArray<string>;
begin
  Result := TArray<string>.Create('\\h\r', '\\h\r\Sandbox\tests');
end;

{ TFormaDeclaradaTests }

procedure TFormaDeclaradaTests.ElUncDeUnaLetraDeRedVuelveConLaLetra;
begin
  // lo que git contesta (con el host en mayusculas: Windows no las distingue)
  Assert.AreEqual('L:\Sandbox\tests\repo',
    FormaDeclaradaDe('\\SERVIDOR\Recurso\Sandbox\tests\repo', D, R));
  Assert.AreEqual('L:\Sandbox\tests\repo\.git',
    FormaDeclaradaDe('\\servidor\Recurso\Sandbox\tests\repo\.git', D, R));
  Assert.AreEqual('L:\Proyectos\a\b',
    FormaDeclaradaDe('\\servidor\Recurso\Proyectos\a\b', D, R));
end;

procedure TFormaDeclaradaTests.LaRaizMismaYConBarrasNormales;
begin
  Assert.AreEqual('L:\Sandbox\tests',
    FormaDeclaradaDe('//servidor/Recurso/Sandbox/tests', D, R));
  Assert.AreEqual('L:\Sandbox\tests',
    FormaDeclaradaDe('\\servidor\Recurso\Sandbox\tests\', D, R));
  Assert.AreEqual('L:\Sandbox\tests\x',
    FormaDeclaradaDe('//servidor/Recurso/Sandbox/tests/x', D, R));
end;

procedure TFormaDeclaradaTests.LaRaizDeLaUnidadLlevaSuBarra;
begin
  // "L:" a secas es la carpeta actual de L:, no su raiz
  Assert.AreEqual('L:\', FormaDeclaradaDe('\\h\r', DRaiz, RRaiz));
  Assert.AreEqual('L:\repo', FormaDeclaradaDe('\\h\r\repo', DRaiz, RRaiz));
end;

procedure TFormaDeclaradaTests.UnUncDeNingunSitioNoSeToca;
const
  OTRO_HOST = '\\otro\Recurso\Sandbox\tests\x';
  FUERA = '\\servidor\Recurso\Fuera\x';
  OTRO_RECURSO = '\\servidor\Otro\Sandbox\tests\x';
begin
  // lo que no cae bajo un sitio declarado sale IGUAL: la puerta lo negara
  Assert.AreEqual(OTRO_HOST, FormaDeclaradaDe(OTRO_HOST, D, R));
  Assert.AreEqual(FUERA, FormaDeclaradaDe(FUERA, D, R));
  Assert.AreEqual(OTRO_RECURSO, FormaDeclaradaDe(OTRO_RECURSO, D, R));
  Assert.AreEqual('\\?\UNC\servidor\Recurso\Sandbox\tests\x',
    FormaDeclaradaDe('\\?\UNC\servidor\Recurso\Sandbox\tests\x', D, R),
    'un prefijo de dispositivo no es un UNC que traducir');
  Assert.AreEqual(FUERA, FormaDeclaradaDe(FUERA, nil, nil), 'sin sitios declarados');
end;

procedure TFormaDeclaradaTests.UnaRutaConLetraNoSeToca;
begin
  // (guarda: una ruta con letra no cae bajo ningun UNC, con la salida
  // temprana o sin ella)
  Assert.AreEqual('L:\Sandbox\tests\x', FormaDeclaradaDe('L:\Sandbox\tests\x', D, R));
  Assert.AreEqual('D:\otra\x', FormaDeclaradaDe('D:\otra\x', D, R));
  Assert.AreEqual('L:/Sandbox/tests/x', FormaDeclaradaDe('L:/Sandbox/tests/x', D, R),
    'ni sus barras: no es de aqui');
end;

procedure TFormaDeclaradaTests.ElSitioDeclaradoEnUncNoSeTraduce;
const
  U = '\\servidor\Recurso\Sandbox\tests\x';
begin
  // declarado EN UNC por otro nombre del host (su IP): vale en la forma en
  // que se escribio, y esta regla no lo reescribe - es solo para las letras
  Assert.AreEqual(U, FormaDeclaradaDe(U,
    TArray<string>.Create('\\10.0.0.5\Recurso\Sandbox\'),
    TArray<string>.Create('\\servidor\Recurso\Sandbox')));
end;

procedure TFormaDeclaradaTests.ElSitioLocalNoSeTraduce;
const
  U = '\\servidor\Recurso\ws\x';
begin
  // un sitio cuya ruta de red no es un UNC (uno local) no cuenta, aunque
  // venga en la lista
  Assert.AreEqual(U, FormaDeclaradaDe(U,
    TArray<string>.Create('C:\ws\'), TArray<string>.Create('C:\ws')));
  Assert.AreEqual(U, FormaDeclaradaDe(U,
    TArray<string>.Create('C:\ws\'), TArray<string>.Create('')));
end;

procedure TFormaDeclaradaTests.ElPrefijoNoEsLaCarpeta;
const
  VECINA = '\\h\r\Sandbox\x';
begin
  // \\h\r\Sandbox no esta bajo \\h\r\Sand
  Assert.AreEqual(VECINA, FormaDeclaradaDe(VECINA,
    TArray<string>.Create('L:\Sand\'), TArray<string>.Create('\\h\r\Sand')));
end;

procedure TFormaDeclaradaTests.DeDosQueCasanElMasHondo;
begin
  Assert.AreEqual('M:\tests\x', FormaDeclaradaDe('\\h\r\Sandbox\tests\x', DRaiz, RRaiz));
  Assert.AreEqual('M:\tests\x', FormaDeclaradaDe('\\h\r\Sandbox\tests\x',
    TArray<string>.Create('M:\tests\', 'L:\'),
    TArray<string>.Create('\\h\r\Sandbox\tests', '\\h\r')), 'en cualquier orden');
  Assert.AreEqual('L:\Sandbox\otra', FormaDeclaradaDe('\\h\r\Sandbox\otra', DRaiz, RRaiz));
end;

{ TFormaDeclaradaEnTextoTests }

procedure TFormaDeclaradaEnTextoTests.LoQueEscribeGit;
begin
  Assert.AreEqual('Initialized empty Git repository in L:/Sandbox/tests/repo/.git/',
    FormaDeclaradaEnTexto('Initialized empty Git repository in //SERVIDOR/Recurso/Sandbox/tests/repo/.git/', D, R));
  Assert.AreEqual('worktree L:/Sandbox/tests/wt'#10'HEAD abc',
    FormaDeclaradaEnTexto('worktree //servidor/Recurso/Sandbox/tests/wt'#10'HEAD abc', D, R));
end;

procedure TFormaDeclaradaEnTextoTests.ConBarrasDeWindowsYDentroDeUnJson;
begin
  Assert.AreEqual('lives at "L:\Sandbox\tests\repo", outside',
    FormaDeclaradaEnTexto('lives at "\\servidor\Recurso\Sandbox\tests\repo", outside', D, R));
  // dentro de un JSON cada barra viaja doblada: vuelve doblada
  Assert.AreEqual('{"path":"L:\\Sandbox\\tests\\a.pas"}',
    FormaDeclaradaEnTexto('{"path":"\\\\servidor\\Recurso\\Sandbox\\tests\\a.pas"}', D, R));
end;

procedure TFormaDeclaradaEnTextoTests.LaPistaParaElOperadorNoSeToca;
const
  PISTA = 'git config --global --add safe.directory ''%(prefix)///SERVIDOR/Recurso/Sandbox/tests/repo''';
begin
  // lo que git le propone al OPERADOR lleva la ruta de red de verdad, y la
  // necesita tal cual: detras de otra barra no empieza una ruta
  Assert.AreEqual(PISTA, FormaDeclaradaEnTexto(PISTA, D, R));
end;

procedure TFormaDeclaradaEnTextoTests.NiUnaUrlNiPegadaAUnaPalabra;
const
  URL = 'origin https://servidor/Recurso/Sandbox/tests/x.git (fetch)';
  PEGADA = 'abc//servidor/Recurso/Sandbox/tests/x y 9//servidor/Recurso/Sandbox/tests/x';
  OTRO = 'en //otro/Recurso/Sandbox/tests/x y en //servidor/Otro/Sandbox/tests/x';
begin
  Assert.AreEqual(URL, FormaDeclaradaEnTexto(URL, D, R), 'detras de dos puntos');
  Assert.AreEqual(PEGADA, FormaDeclaradaEnTexto(PEGADA, D, R), 'pegada a una letra o a una cifra');
  Assert.AreEqual(OTRO, FormaDeclaradaEnTexto(OTRO, D, R), 'otro host, otro recurso');
end;

procedure TFormaDeclaradaEnTextoTests.ElPrefijoNoEsLaCarpeta;
const
  VECINA = 'in //servidor/Recurso/Sandbox/testsuite/x';
  CON_PUNTO = 'in //servidor/Recurso/Sandbox/tests.old/x';
begin
  Assert.AreEqual(VECINA, FormaDeclaradaEnTexto(VECINA, D, R));
  Assert.AreEqual(CON_PUNTO, FormaDeclaradaEnTexto(CON_PUNTO, D, R));
end;

procedure TFormaDeclaradaEnTextoTests.DondeAcabaLaRuta;
begin
  // el sitio MISMO, sin nada debajo: acaba en el fin del texto, en un salto
  // de linea, en un espacio, en una comilla
  Assert.AreEqual('L:/Sandbox/tests', FormaDeclaradaEnTexto('//servidor/Recurso/Sandbox/tests', D, R));
  Assert.AreEqual('worktree L:/Sandbox/tests'#10'HEAD abc',
    FormaDeclaradaEnTexto('worktree //servidor/Recurso/Sandbox/tests'#10'HEAD abc', D, R));
  Assert.AreEqual('L:/Sandbox/tests  abc123 [main]',
    FormaDeclaradaEnTexto('//servidor/Recurso/Sandbox/tests  abc123 [main]', D, R));
  Assert.AreEqual('fatal: in ''L:/Sandbox/tests''',
    FormaDeclaradaEnTexto('fatal: in ''//servidor/Recurso/Sandbox/tests''', D, R));
end;

procedure TFormaDeclaradaEnTextoTests.VariasEnUnTextoYLaMasHonda;
begin
  Assert.AreEqual('L:/Proyectos/a y L:\Sandbox\tests\b',
    FormaDeclaradaEnTexto('//servidor/Recurso/Proyectos/a y \\servidor\Recurso\Sandbox\tests\b', D, R));
  Assert.AreEqual('M:/tests/x y L:/Sandbox/otra',
    FormaDeclaradaEnTexto('//h/r/Sandbox/tests/x y //h/r/Sandbox/otra', DRaiz, RRaiz));
end;

procedure TFormaDeclaradaEnTextoTests.LaRaizDeLaUnidadLlevaSuBarra;
begin
  // la unidad entera como raiz, y git nombra la raiz misma: "L:" a secas no
  // es una ruta, y el barrido del enmascarador la dejaba con su letra
  Assert.AreEqual('L:/  abc123 [main]', FormaDeclaradaEnTexto('//h/r  abc123 [main]', DRaiz, RRaiz));
  Assert.AreEqual('worktree L:/'#10'HEAD abc',
    FormaDeclaradaEnTexto('worktree //h/r'#10'HEAD abc', DRaiz, RRaiz));
  Assert.AreEqual('"L:\\"', FormaDeclaradaEnTexto('"\\\\h\\r"', DRaiz, RRaiz), 'dentro de un JSON');
  Assert.AreEqual('en L:\', FormaDeclaradaEnTexto('en \\h\r', DRaiz, RRaiz));
  // ...y con algo debajo, la barra es la que ya trae
  Assert.AreEqual('L:/repo/.git', FormaDeclaradaEnTexto('//h/r/repo/.git', DRaiz, RRaiz));
  Assert.AreEqual('"L:\\repo"', FormaDeclaradaEnTexto('"\\\\h\\r\\repo"', DRaiz, RRaiz));
  // dentro de un JSON, lo que sigue puede ser un escape (\n, \"): no es la
  // barra de esa escritura, y la ruta acaba ahi
  Assert.AreEqual('"worktree L:/\nHEAD"',
    FormaDeclaradaEnTexto('"worktree //h/r\nHEAD"', DRaiz, RRaiz));
  Assert.AreEqual('"en L:\\\n"', FormaDeclaradaEnTexto('"en \\\\h\\r\n"', DRaiz, RRaiz));
end;

procedure TFormaDeclaradaEnTextoTests.TrasUnSaltoDeLineaDeJson;
begin
  // en un JSON el salto de linea son los caracteres \ y n: la ruta que abre
  // la linea siguiente no esta pegada a una palabra
  Assert.AreEqual('"uno\nL:/Sandbox/tests/x"',
    FormaDeclaradaEnTexto('"uno\n//servidor/Recurso/Sandbox/tests/x"', D, R));
end;

procedure TFormaDeclaradaEnTextoTests.SinSitiosDeRedElTextoEsElMismo;
const
  T = 'Initialized empty Git repository in //servidor/Recurso/Sandbox/tests/repo/.git/';
begin
  Assert.AreEqual(T, FormaDeclaradaEnTexto(T, nil, nil));
  // un sitio declarado en UNC, o uno cuya ruta de red no es un UNC, no cuenta
  Assert.AreEqual(T, FormaDeclaradaEnTexto(T,
    TArray<string>.Create('\\10.0.0.5\Recurso\Sandbox\'),
    TArray<string>.Create('\\servidor\Recurso\Sandbox')));
  Assert.AreEqual(T, FormaDeclaradaEnTexto(T,
    TArray<string>.Create('C:\ws\'), TArray<string>.Create('C:\ws')));
end;

// la casa de un servidor de mentira en las tres escrituras que compone
// Lsp.Mascara (AgujasDeCasa), por su nombre: el mismo cambio que las rutas de
// red, con agujas que empiezan por una letra (2ag de la 1.18.2)
function EnCasa(const ATexto: string): string;
begin
  Result := CambiaPrefijosEnTexto(ATexto,
    TArray<string>.Create('C:\\Srv\\Mcp', 'C:/Srv/Mcp', 'C:\Srv\Mcp'),
    TArray<string>.Create('<server>', '<server>', '<server>'),
    TArray<string>.Create('', '', ''));
end;

procedure TFormaDeclaradaEnTextoTests.UnaCasaConLetraPorSuNombre;
begin
  // el prefijo por su nombre y lo de debajo tal cual, en las tres escrituras
  // y sin distinguir mayusculas
  Assert.AreEqual('exe <server>\DelphiLspMcp.exe', EnCasa('exe C:\Srv\Mcp\DelphiLspMcp.exe'));
  Assert.AreEqual('{"exe":"<server>\\a.exe"}', EnCasa('{"exe":"C:\\Srv\\Mcp\\a.exe"}'), 'dentro de un JSON');
  Assert.AreEqual('in <server>/x', EnCasa('in C:/Srv/Mcp/x'), 'con las barras de git');
  Assert.AreEqual('(<server>\x)', EnCasa('(c:\srv\MCP\x)'), 'sin distinguir mayusculas');
  Assert.AreEqual('<server>', EnCasa('C:\Srv\Mcp'), 'la casa entera');
  // abriendo una linea de un JSON (el \n escrito no es una letra pegada)
  Assert.AreEqual('a\n<server>\b', EnCasa('a\nC:\Srv\Mcp\b'), 'tras un salto de linea de JSON');
  // una con letra no es una url: detras de dos puntos tambien es ella
  Assert.AreEqual('exe:<server>\x', EnCasa('exe:C:\Srv\Mcp\x'), 'detras de dos puntos');
end;

procedure TFormaDeclaradaEnTextoTests.LaCasaSoloComoRutaEntera;
begin
  Assert.AreEqual('C:\Srv\McpOtra\x', EnCasa('C:\Srv\McpOtra\x'), 'una vecina que empieza igual');
  Assert.AreEqual('XC:\Srv\Mcp\x', EnCasa('XC:\Srv\Mcp\x'), 'pegada a una palabra');
  Assert.AreEqual('D:\Srv\Mcp\x', EnCasa('D:\Srv\Mcp\x'), 'en otra unidad');
  Assert.AreEqual('C:\Srv\Mc', EnCasa('C:\Srv\Mc'), 'un trozo de ella');
end;

procedure TFormaDeclaradaEnTextoTests.UnaRaizQueEmpiezaComoLaCasaSeQueda;
begin
  // una raiz del agente que empieza como la casa (una vecina con un espacio)
  // es una aguja de si misma, con el cambio vacio: gana por mas larga y se
  // queda como venia, y la casa de al lado si cambia (revisor del 2ag:
  // salia "<server> x", que el agente no podia devolver)
  Assert.AreEqual('c:\srv\mcp x\a y <server>\b',
    CambiaPrefijosEnTexto('c:\srv\mcp x\a y C:\Srv\Mcp\b',
      TArray<string>.Create('C:\Srv\Mcp', 'C:\Srv\Mcp x'),
      TArray<string>.Create('<server>', ''), TArray<string>.Create('', '')));
end;

{ TBarridoDeUnidadesTests }

function Letra: string;
begin
  Result := Copy(ParamStr(0), 1, 1);
end;

function Virtual: string;
begin
  Result := 'srv' + Letra.ToLower + ':';
end;

procedure TBarridoDeUnidadesTests.LaRutaQueAbreLineaEnUnJsonSeEnmascara;
begin
  Assert.AreEqual('{"t":"uno\n' + Virtual + '\\dir\\f.pas(3)"}',
    MaskDriveText('', '{"t":"uno\n' + Letra + ':\\dir\\f.pas(3)"}'));
  // (control) la misma, pegada a una palabra, no es una unidad
  Assert.AreEqual('{"t":"uno' + Letra + ':\\dir"}',
    MaskDriveText('', '{"t":"uno' + Letra + ':\\dir"}'));
end;

procedure TBarridoDeUnidadesTests.LaCacheDelServidorEnSusFormas;
var
  Cache, Larga, Corta: string;
begin
  // la cache del servidor (LOCALAPPDATA\DelphiLspMcp) sale por su nombre en
  // su forma larga y en la 8.3 (revisor del 2ag: la 8.3 no la media nadie;
  // las baterias alargan las rutas a la entrada)
  Cache := ServerCacheDir;
  ForceDirectories(Cache);
  Larga := ExcludeTrailingPathDelimiter(FormaLarga(Cache));
  Assert.AreEqual('<server-cache>\x.txt', MaskDriveText('', Larga + '\x.txt'), 'la larga');
  Corta := ExtractShortPathName(Cache);
  if (Corta = '') or SameText(Corta, Larga) then
    Assert.Pass('esta maquina no da forma 8.3 de ' + Cache + ': la corta no se mide')
  else
    Assert.AreEqual('<server-cache>\x.txt', MaskDriveText('', Corta + '\x.txt'), 'la 8.3: ' + Corta);
end;

procedure TBarridoDeUnidadesTests.LaCasaDentroDeSuRaizNoSeToca;
begin
  // la carpeta de este ejecutor ES su raiz (DELPHI_MCP_ROOTS, LspUnitTests.dpr):
  // la casa que el operador pone dentro de una raiz es del agente, y sale
  // con su unidad virtual, que puede devolver
  Assert.AreEqual(Virtual + Copy(ServerDir, 3, MaxInt) + '\x.txt',
    MaskDriveText('', ServerDir + '\x.txt'));
end;

procedure TBarridoDeUnidadesTests.ElUncQueAbreLineaEnUnJsonSeEnmascara;
begin
  Assert.AreEqual('{"t":"uno\n\\\\srvhost\\rec\\f"}',
    MaskDriveText('', '{"t":"uno\n\\\\equipo\\rec\\f"}'));
end;

procedure TBarridoDeUnidadesTests.UnaCarpetaDeUnaLetraNoEsUnSaltoDeLinea;
begin
  // "X:\\t\\\\resto": detras de la carpeta t, un separador doblado otra vez
  // (lo que escribe el enlazador de Linux64). No es un UNC que abra linea
  Assert.AreEqual('{"t":"' + Virtual + '\\t\\\\resto\\x"}',
    MaskDriveText('', '{"t":"' + Letra + ':\\t\\\\resto\\x"}'));
  // ...ni una unidad: "\\n" + letra + ":" va pegada a la carpeta n
  Assert.AreEqual('{"t":"' + Virtual + '\\n' + Letra + ':"}',
    MaskDriveText('', '{"t":"' + Letra + ':\\n' + Letra + ':"}'));
end;

{ Los UNC que se escapaban (revision de la 1.10.0, leidos por un revisor y
  medidos aqui): detras de un ';', pegados a una opcion del compilador, el eco
  del enlazador doblado otra vez dentro de un JSON, el \\?\UNC\ y un host que
  no empieza por letra o digito. En todos, el nombre de la maquina salia. }

procedure TBarridoDeUnidadesTests.ElUncDeUnaListaDeRutasSeEnmascara;
var
  S: string;
begin
  S := MaskDriveText('', '{"t":"' + Letra + ':\\a;\\\\nas\\s"}');
  Assert.DoesNotContain(S, 'nas', S);
  Assert.Contains(S, ';\\\\srvhost\\s', S);
end;

procedure TBarridoDeUnidadesTests.ElUncPegadoAUnaOpcionSeEnmascara;
var
  S: string;
begin
  S := MaskDriveText('', '{"t":"dcc64 -U\\\\nas\\lib x.dpr"}');
  Assert.DoesNotContain(S, 'nas', S);
  S := MaskDriveText('', 'dcc64 -U\\nas\lib -NU.\dcu x.dpr');
  Assert.DoesNotContain(S, 'nas', S);
  // (control) un separador doblado pegado a una carpeta no es un UNC
  Assert.AreEqual('{"t":".\\\\Linux64\\\\\\\\Debug"}',
    MaskDriveText('', '{"t":".\\\\Linux64\\\\\\\\Debug"}'));
end;

procedure TBarridoDeUnidadesTests.ElUncDobladoDosVecesSeEnmascara;
var
  S: string;
begin
  // el enlazador de Linux64 dobla sus barras y el JSON las vuelve a doblar
  S := MaskDriveText('', '{"t":"-L \\\\\\\\nas\\\\s\\\\lib"}');
  Assert.DoesNotContain(S, 'nas', S);
end;

procedure TBarridoDeUnidadesTests.ElUncExtendidoYElHostRaroSeEnmascaran;
var
  S: string;
begin
  S := MaskDriveText('', 'copia en \\?\UNC\nas\s\x.dcu');
  Assert.DoesNotContain(S, 'nas', S);
  S := MaskDriveText('', '{"t":"\\\\?\\UNC\\nas\\s"}');
  Assert.DoesNotContain(S, 'nas', S);
  S := MaskDriveText('', 'copia en \\_nas\s\x.dcu');
  Assert.DoesNotContain(S, '_nas', S);
end;

{ EnmascaraJsonSalvo enmascara las cadenas una a una: las claves se copiaban
  tal cual, y antes el texto entero pasaba por la mascara y las cubria
  (revision de la 1.13.0). Lo de un campo de contenido sigue tal cual. }
procedure TBarridoDeUnidadesTests.LasClavesDeUnJsonTambienSeEnmascaran;
var
  S: string;
begin
  S := EnmascaraJsonSalvo('{"changes":{"' + Letra + ':\\x.pas":[1]},"text":"' +
    Letra + ':\\y"}', ['text']);
  Assert.Contains(S, '"' + Virtual + '\\x.pas"', S);
  Assert.Contains(S, '"text":"' + Letra + ':\\y"', S + ' (el contenido, tal cual)');
end;

{ La negativa de una tanda de delphi_edit (un ROLLBACK), en la forma que la
  escribe la tanda (Lsp.Patch): lo que PIDIO el agente se enmascara; la linea
  releida del disco y la cita de la entrada que fallo van tal cual, como en
  delphi_read. Iban en la misma fila y se enmascaraba entera: '[^\s:]' volvia
  '[^\srv0:]' (4-oct-2026). Y van tal cual porque las compuso CitaDeLinea en
  esta llamada, no por su forma: una linea que solo PARECE una cita se
  enmascara (antes pasaba toda la que empezara por 'N|'), y las citas pasan
  tambien en la respuesta de una tool que no es de eco (una pista de
  delphi_changeset; revision del 4-oct-2026). }
procedure TBarridoDeUnidadesTests.LaFilaDeUnaTandaDejaElDiscoComoEsta;
var
  S, Cita1, Cita2: string;
begin
  OlvidaSalidaHecha; // nada de otra prueba de este hilo
  Cita1 := CitaDeLinea(12, 'R := ''[^\s:]'' + ''' + Letra + ':\disco'';');
  Cita2 := CitaDeLinea(15, '  S := ''' + Letra + ':\otra'';');
  S := MaskDriveText('delphi_edit', '[EDIT-099 INVALID_PARAM] ROLLBACK: edit 2 of 2 failed'#10 +
    '  1 OK: R := ''' + Letra + ':\pedido''  ->'#10 +
    '     ' + Cita1 + #10 +
    '  2: [EDIT-007 NOT_FOUND] no esta: |x  ->  1|' + Letra + ':\tecleado|. La linea real:'#10 +
    '       ' + Cita2 + #10 +
    '     3|' + Letra + ':\parece una cita');
  Assert.Contains(S, '1 OK: R := ''' + Virtual + '\pedido''', 'lo del agente, enmascarado: ' + S);
  Assert.Contains(S, '     ' + Cita1, 'la linea del disco, tal cual: ' + S);
  Assert.Contains(S, '       ' + Cita2, 'la cita del disco, tal cual: ' + S);
  Assert.Contains(S, '1|' + Virtual + '\tecleado', 'un N| en medio de una linea no la exime: ' + S);
  Assert.Contains(S, '3|' + Virtual + '\parece una cita', 'lo que solo PARECE una cita se enmascara: ' + S);
  // las citas son de UNA llamada: la siguiente las enmascara
  S := MaskDriveText('delphi_edit', '[EDIT-099 INVALID_PARAM] x'#10'     ' + Cita1);
  Assert.Contains(S, Virtual + '\disco', 'una cita de la llamada anterior ya no exime: ' + S);
  // ...y pasan en la respuesta de cualquier tool, no solo en las de eco
  Cita1 := CitaDeLinea(7, 'X := ''' + Letra + ':\pista'';');
  S := MaskDriveText('delphi_changeset', '[CHSET-0 NOT_FOUND] ' + Letra + ':\f.pas'#10'  ' + Cita1);
  Assert.Contains(S, '  ' + Cita1, 'la pista de changeset, tal cual: ' + S);
  Assert.Contains(S, Virtual + '\f.pas', 'su ruta, enmascarada: ' + S);
end;

{ V70 (27-oct-2026): una respuesta JSON es UNA linea y el filtro miraba las
  citas linea a linea: el block de un insert de delphi_designer, sus value y
  previous y la linea citada del preview de delphi_changeset salian
  enmascarados ('Contrase'#241'a:' volvia 'Contrase'#241'srv0:'). Ante un JSON
  que la tool escribio con ToJSON, cadena a cadena: lo que compuso esta
  llamada (CitaDeLinea, ContenidoTalCual) va tal cual, tambien como una linea
  de un mensaje, y lo demas - las claves tambien - se enmascara. Uno con algo
  pegado detras no se reescribe (se perderia): va por lineas, como iba - lo
  niega ParseJSONValue, y esta prueba mide que lo siga negando. }
procedure TBarridoDeUnidadesTests.LasCitasDeUnJsonVanComoEstan;
var
  O, R: TJSONObject;
  A: TJSONArray;
  J, S, Cita, Cita9, Valor: string;
begin
  OlvidaSalidaHecha; // nada de otra prueba de este hilo
  O := TJSONObject.Create;
  try
    A := TJSONArray.Create;
    Cita := CitaDeLinea(26, '    Caption = ''Ruta ' + Letra + ':\x''');
    A.Add(Cita);
    A.Add('27|' + Letra + ':\parece una cita');
    O.AddPair('block', A);
    Valor := ContenidoTalCual('''Ruta ' + Letra + ':\x''');
    O.AddPair('value', Valor);
    Cita9 := CitaDeLinea(9, '  R := ''' + Letra + ':\y'';');
    O.AddPair('anchor', 'line 9 is not the expected one; it is:'#10'  ' + Cita9);
    O.AddPair('note', 'en ' + Letra + ':\nota');
    O.AddPair(Letra + ':\clave', 'x');
    J := O.ToJSON;
  finally
    O.Free;
  end;
  S := MaskDriveText('delphi_designer', J);
  R := TJSONObject.ParseJSONValue(S) as TJSONObject;
  Assert.IsNotNull(R, 'sigue siendo JSON: ' + S);
  try
    A := R.GetValue('block') as TJSONArray;
    Assert.AreEqual(Cita, A.Items[0].Value, 'la cita del block, tal cual');
    Assert.AreEqual('27|' + Virtual + '\parece una cita', A.Items[1].Value,
      'lo que solo PARECE una cita se enmascara');
    Assert.AreEqual(Valor, R.GetValue('value').Value, 'el valor del form, tal cual');
    Assert.AreEqual('line 9 is not the expected one; it is:'#10'  ' + Cita9,
      R.GetValue('anchor').Value, 'la cita como linea de un mensaje, tal cual');
    Assert.AreEqual('en ' + Virtual + '\nota', R.GetValue('note').Value, 'lo nuestro, enmascarado');
    Assert.IsNotNull(R.GetValue(Virtual + '\clave'), 'la clave, enmascarada: ' + S);
  finally
    R.Free;
  end;
  // un JSON con una nota pegada detras no se reescribe: no se pierde nada
  Cita := CitaDeLinea(3, 'X := 1;');
  S := MaskDriveText('delphi_designer', '{"block":["' + Cita + '"]} nota');
  Assert.EndsWith(' nota', S, 'lo de detras sigue: ' + S);
end;

procedure TBarridoDeUnidadesTests.LosControlesSonAnomaliasPorSiMismos;
begin
  for var N := 0 to 31 do
    for var P in TArray<string>.Create('C:\antes' + Char(N) + 'despues.pas',
      'C:\carpeta' + Char(N), Char(N) + 'C:\carpeta') do
      Assert.IsNotEmpty(PathAnomaly(P), 'Control ' + IntToStr(N));
  Assert.AreEqual('', PathAnomaly('C:\carpeta\unidad.pas'));
end;

{ TClaveDeCarpetaTests }

procedure TClaveDeCarpetaTests.OtrasMayusculasFueraDeAZDanLaMismaClave;
var
  A, B: string;
begin
  // C:\Nandu\Servidor con la enye y la u acentuada, en mayusculas y en minusculas
  A := ClaveDeCarpeta('C:\' + #$00D1 + 'and' + #$00DA + '\Servidor');
  B := ClaveDeCarpeta('C:\' + #$00F1 + 'AND' + #$00FA + '\servidor');
  Assert.AreEqual(A, B);
  Assert.AreEqual(32, Length(A), A);
end;

procedure TClaveDeCarpetaTests.LaBarraFinalNoCambiaLaClave;
begin
  Assert.AreEqual(ClaveDeCarpeta('C:\Casa\Servidor'),
    ClaveDeCarpeta('C:\Casa\Servidor\'));
end;

{ TSelloUnicoTests }

procedure TSelloUnicoTests.CadaSelloVaDetrasDelAnterior;
var
  Antes, Ahora: string;
begin
  // dos mil seguidos caben en pocos ticks: con la hora sola, muchos salian
  // iguales hasta el trozo aleatorio, y este los ordenaba al azar
  Antes := SelloUnico;
  for var I := 1 to 2000 do
  begin
    Ahora := SelloUnico;
    if CompareStr(Antes, Ahora) >= 0 then
      Assert.Fail(Format('sello %d: %s no va detras de %s', [I, Ahora, Antes]));
    Antes := Ahora;
  end;
end;

procedure TSelloUnicoTests.ElTextoEsElQueLeeSuPatron;
begin
  Assert.IsTrue(TRegEx.IsMatch(SelloUnico, '\A' + SELLO_UNICO_PATRON + '\z'), SelloUnico);
end;

procedure TSelloUnicoTests.EnLaCasaSoloLoQueViaja;
var
  F: string;
  EnCasa: Boolean;
begin
  var R := CaptureTarget('', CAPTURE_SUB_DESKTOP, 'x', '.bmp', F, EnCasa);
  Assert.IsTrue(R.Contains('CAPT-013') and (F = ''), R);
  // con out= es del agente: su formato, si su fichero lo dice
  R := CaptureTarget(TPath.Combine(ServerTempDir(''), 'mia.bmp'), CAPTURE_SUB_DESKTOP, 'x', '.bmp', F, EnCasa);
  Assert.IsFalse(R.Contains('CAPT-013'), R);
end;

{ TPuertaDeLeerTests }

procedure TPuertaDeLeerTests.Prepara;
begin
  // en el temporal del ejecutor, que es su casa (ServerTempDir: junto al exe)
  FDir := ServerTempDir('puerta-' + FragmentoUnico);
  ForceDirectories(FDir);
  FNota := TPath.Combine(FDir, 'nota.txt');
  TFile.WriteAllText(FNota, 'hola', TEncoding.UTF8);
  FUnion := TPath.Combine(FDir, 'fuera');
end;

procedure TPuertaDeLeerTests.Limpia;
begin
  // la union se quita como union (RemoveDir): lo de detras no se toca
  if TDirectory.Exists(FUnion) then
    RemoveDir(FUnion);
  if TFile.Exists(FNota) then
    TFile.Delete(FNota);
  RemoveDir(FDir);
end;

procedure TPuertaDeLeerTests.EnSuLugarSeLeeYEnOtroNo;
var
  R: string;
begin
  Assert.AreEqual('', LugarDeLecturaDenegado(FNota, [ltTemporal]));
  Assert.AreEqual('hola', LeeTexto(FNota, [ltTemporal]));
  // el mismo fichero, preguntado por otro lugar: GUARD-034, y no se lee
  R := LugarDeLecturaDenegado(FNota, [ltCasa, ltVault]);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
  Assert.WillRaise(
    procedure
    begin
      LeeTexto(FNota, [ltCasa]);
    end);
  Assert.WillRaise(
    procedure
    begin
      LeeBytes(FNota, [ltCasa]);
    end);
end;

procedure TPuertaDeLeerTests.UnEnlaceNoSacaANadieDeSuSitio;
var
  Exe, R: string;
begin
  // <temporal>\puerta-x\fuera -> la carpeta del ejecutor, que NO es el
  // temporal: por el TEXTO la ruta esta dentro, pero hay un enlace en medio
  Assert.IsTrue(CreaUnion(FUnion, ExtractFileDir(ParamStr(0))),
    'la union se crea: ' + SysErrorMessage(GetLastError));
  Exe := TPath.Combine(FUnion, ExtractFileName(ParamStr(0)));
  Assert.IsTrue(TFile.Exists(Exe), 'por la union se llega: ' + Exe);
  R := LugarDeLecturaDenegado(Exe, [ltTemporal]);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), 'la puerta niega: [' + R + ']');
  Assert.WillRaise(
    procedure
    begin
      LeeBytes(Exe, [ltTemporal]);
    end);
  // ...y lo que esta de verdad dentro, al lado de la union, si
  Assert.AreEqual('', LugarDeLecturaDenegado(FNota, [ltTemporal]));
end;

procedure TPuertaDeLeerTests.SettingsIniNoEsDeLaCasaYElBuzonSi;
var
  R: string;
begin
  // la casa son sus carpetas, no la del exe entera: settings.ini no es lugar
  // de ninguna puerta (no hace falta que exista: se pregunta el sitio)
  R := LugarDeLecturaDenegado(ServerDir('settings.ini'), [ltCasa, ltTemporal]);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
  Assert.AreEqual('', LugarDeLecturaDenegado(
    TPath.Combine(TPath.Combine(CarpetaDeMensajes, 'agente'), 'aviso.md'), [ltCasa]));
  Assert.AreEqual('', LugarDeLecturaDenegado(
    TPath.Combine(CarpetaDeInformes, 'informe.md'), [ltCasa]));
end;

procedure TPuertaDeLeerTests.UnaCasaRelativaNoEsLugar;
var
  Antes: string;
begin
  Antes := GetEnvironmentVariable('LOCALAPPDATA');
  try
    // sin LOCALAPPDATA (o relativa) la cache se resolveria contra la carpeta
    // de trabajo del proceso: no es lugar
    for var V in TArray<string>.Create('', 'relativa', '\sin-unidad') do
    begin
      SetEnvironmentVariable('LOCALAPPDATA', PChar(V));
      Assert.AreEqual(2, Integer(Length(CarpetasDeLaCasa)), V);
      for var C in CarpetasDeLaCasa do
        Assert.IsTrue(EsRutaAbsoluta(C), C);
    end;
    // con una absoluta (la carpeta del ejecutor: la del contenedor puede no
    // traer LOCALAPPDATA), si
    SetEnvironmentVariable('LOCALAPPDATA', PChar(ExtractFileDir(ParamStr(0))));
    Assert.AreEqual(3, Integer(Length(CarpetasDeLaCasa)));
  finally
    SetEnvironmentVariable('LOCALAPPDATA', PChar(Antes));
  end;
end;

procedure TPuertaDeLeerTests.LaBibliotecaDelIdeSeLeeYNoSeEscribe;
var
  Info: TRadStudioInfo;
  F, R: string;
begin
  // una carpeta de su Library Search Path FUERA de la instalacion (componentes,
  // GetIt): la instalacion ya es del IDE, y lo que se mide aqui es la biblioteca
  // como lugar propio (ltBiblioteca: lo que el motor dice de alli se ensena).
  // GUARDA en el contenedor de delphi_test, que no ve esa parte del registro
  // (su mutante siguio verde aqui, 9-oct-2026): lo MIDE test_motor_fuera F8b
  Info := DiscoverRadStudio;
  Assert.IsTrue(Info.Found, 'el ejecutor ve su Delphi');
  F := '';
  for var L in LibraryRoots do
    if not L.StartsWith(IncludeTrailingPathDelimiter(Info.RootDir), True) then
    begin
      F := TPath.Combine(L, 'UnaUnidad.pas');
      Break;
    end;
  if F = '' then
  begin
    Assert.Pass('sin carpeta de la Library Search Path fuera de la instalacion: no se mide');
    Exit;
  end;
  Assert.AreEqual('', LugarDeLecturaDenegado(F, [ltBiblioteca]), F);
  // ...y no por ser del IDE: el lugar IDE no la tiene (cargarla lee rsvars.bat
  // por la puerta con el IDE como lugar, y la puerta se preguntaba a si misma)
  R := LugarDeLecturaDenegado(F, [ltIde]);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
  // ...y no se escribe
  R := LugarDeEscrituraDenegado(F, ltBiblioteca);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
end;

procedure TPuertaDeLeerTests.ElComparadorDeLugaresVaPorLaRutaReal;
var
  Lib, Vict, Fuga, Normal: string;
  Buf: array [0 .. MAX_PATH] of Char;
begin
  // EL comparador de los lugares (Lsp.Rutas.EnAlgunLugar), el que pregunta
  // tambien la jaula por su zona de biblioteca (M1 de la 1.18.0: la juzgaba
  // por el TEXTO y un enlace plantado en una carpeta de la Library Path que
  // apuntase fuera se leia): lo de detras de un enlace que sale no es del
  // lugar, lo de al lado si, y el lugar escrito en 8.3 es el mismo lugar
  Lib := TPath.Combine(FDir, 'lib');
  Vict := TPath.Combine(FDir, 'vict');
  Fuga := TPath.Combine(Lib, 'fuga');
  Normal := TPath.Combine(Lib, 'normal.pas');
  ForceDirectories(Lib);
  ForceDirectories(Vict);
  try
    TFile.WriteAllText(Normal, 'unit normal;');
    TFile.WriteAllText(TPath.Combine(Vict, 'secreto.pas'), 'unit secreto;');
    Assert.IsTrue(CreaUnion(Fuga, Vict), 'la union se crea: ' + SysErrorMessage(GetLastError));
    Assert.IsTrue(EnAlgunLugar(RealPath(Normal), [Lib]), Normal);
    // lo de detras de la union, solo donde RealPath resuelve uniones: en el
    // contenedor de delphi_test se queda con el texto (la nota de la clase);
    // fuera de el (LspUnitTests a pelo) si se mide, y de extremo a extremo la
    // sonda de M1 con la HKCU virtual (m1_medir.ps1, scratchpad del 9-oct)
    if not SameText(RealPath(Fuga), Fuga) then
      Assert.IsFalse(EnAlgunLugar(RealPath(TPath.Combine(Fuga, 'secreto.pas')), [Lib]),
        'lo de detras de la union es de la victima');
    Assert.IsTrue(EnAlgunLugar(RealPath(TPath.Combine(Vict, 'secreto.pas')), [Lib, Vict]),
      'y lo es de un lugar que la tiene');
    var N := GetShortPathName(PChar(Lib), @Buf[0], Length(Buf));
    if (N > 0) and (N < DWORD(Length(Buf))) and not SameText(string(PChar(@Buf[0])), Lib) then
      Assert.IsTrue(EnAlgunLugar(RealPath(Normal), [string(PChar(@Buf[0]))]),
        'el lugar en 8.3: ' + string(PChar(@Buf[0])));
  finally
    // la union se quita como union (RemoveDir): lo de detras no se toca
    if TDirectory.Exists(Fuga) then
      RemoveDir(Fuga);
    if TFile.Exists(Normal) then
      TFile.Delete(Normal);
    if TFile.Exists(TPath.Combine(Vict, 'secreto.pas')) then
      TFile.Delete(TPath.Combine(Vict, 'secreto.pas'));
    RemoveDir(Lib);
    RemoveDir(Vict);
  end;
end;

{ TPuertaDeEscribirTests }

procedure TPuertaDeEscribirTests.Prepara;
begin
  FDir := ServerTempDir('escribir-' + FragmentoUnico);
  ForceDirectories(FDir);
  FUnion := TPath.Combine(FDir, 'fuera');
  // la victima, FUERA del temporal: en la carpeta del ejecutor, a su lado
  FVictima := TPath.Combine(ExtractFileDir(ParamStr(0)), 'victima-' + FragmentoUnico);
  ForceDirectories(FVictima);
end;

procedure TPuertaDeEscribirTests.Limpia;
begin
  // la union se quita como union (RemoveDir): lo de detras no se toca
  if TDirectory.Exists(FUnion) then
    RemoveDir(FUnion);
  for var D in TArray<string>.Create(FDir, FVictima) do
    if TDirectory.Exists(D) then
    begin
      for var F in TDirectory.GetFiles(D) do
        TFile.Delete(F);
      RemoveDir(D);
    end;
end;

procedure TPuertaDeEscribirTests.EnSuLugarSeEscribeEnteroYConSuCodificacion;
var
  F: string;
  B: TBytes;
begin
  F := TPath.Combine(FDir, 'nota.md');
  Assert.AreEqual('', LugarDeEscrituraDenegado(F, ltTemporal));
  EscribeTexto(F, 'acentuación', ltTemporal, ekUtf8Bom);
  B := TFile.ReadAllBytes(F);
  Assert.IsTrue((Length(B) > 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF),
    'con su BOM');
  Assert.AreEqual('acentuación', TEncoding.UTF8.GetString(B, 3, Length(B) - 3));
  // pisar lo que hay: entero, en la codificacion que se pide
  EscribeTexto(F, 'otra', ltTemporal, ekUtf8);
  Assert.AreEqual('otra', TEncoding.ASCII.GetString(TFile.ReadAllBytes(F)));
  // y ni un temporal de sustitucion al lado
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FDir))));
end;

procedure TPuertaDeEscribirTests.UnEnlaceNoLlevaLaEscrituraDetras;
var
  F, R: string;
begin
  // <temporal>\escribir-x\fuera -> una carpeta FUERA del temporal: por el
  // TEXTO la ruta esta dentro, pero hay un enlace en medio
  Assert.IsTrue(CreaUnion(FUnion, FVictima),
    'la union se crea: ' + SysErrorMessage(GetLastError));
  F := TPath.Combine(FUnion, 'x.md');
  R := LugarDeEscrituraDenegado(F, ltTemporal);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), 'la puerta niega: [' + R + ']');
  Assert.WillRaise(
    procedure
    begin
      EscribeTexto(F, 'detras', ltTemporal, ekUtf8);
    end);
  // la victima, intacta: ni el fichero ni un temporal de sustitucion
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FVictima))));
end;

procedure TPuertaDeEscribirTests.SettingsIniNoSeEscribe;
var
  R: string;
begin
  // la casa son sus carpetas, no la del exe entera (se pregunta el sitio:
  // no hace falta que exista)
  for var L in TArray<TLugarDeTexto>.Create(ltCasa, ltTemporal) do
  begin
    R := LugarDeEscrituraDenegado(ServerDir('settings.ini'), L);
    Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
  end;
end;

procedure TPuertaDeEscribirTests.LaInstalacionDelIdeSeLeePeroNoSeEscribe;
var
  Info: TRadStudioInfo;
  F, R: string;
begin
  Info := DiscoverRadStudio;
  Assert.IsTrue(Info.Found, 'el ejecutor ve su Delphi');
  F := TPath.Combine(TPath.Combine(Info.RootDir, 'bin'), 'rsvars.bat');
  // para LEER es del IDE: lo afirma la lectura, asi que la negativa de
  // abajo no sale de una lista de lugares vacia
  Assert.AreEqual('', LugarDeLecturaDenegado(F, [ltIde]));
  R := LugarDeEscrituraDenegado(F, ltIde);
  Assert.IsTrue(R.StartsWith('[GUARD-034'), R);
end;

procedure TPuertaDeEscribirTests.SustituirConservaLaFechaDeCreacion;
var
  F: string;
begin
  // el renombre del temporal dejaba SU fecha de creacion (revisor de P3):
  // el vault (file.ctime de Obsidian) veia la nota recien nacida
  F := TPath.Combine(FDir, 'fecha.md');
  EscribeTexto(F, 'uno', ltTemporal, ekUtf8);
  TFile.SetCreationTime(F, EncodeDate(2001, 1, 1));
  EscribeTexto(F, 'dos', ltTemporal, ekUtf8);
  Assert.AreEqual('dos', TEncoding.ASCII.GetString(TFile.ReadAllBytes(F)));
  Assert.IsTrue(TFile.GetCreationTime(F) < EncodeDate(2002, 1, 1),
    DateTimeToStr(TFile.GetCreationTime(F)));
end;

procedure TPuertaDeEscribirTests.EscribirLoMismoNoReescribe;
var
  F: string;
begin
  // los mismos bytes no se escriben (ni, en el IDE, se copian): repetir
  // get-sdk dejaba un .sdk identico y una copia en la casa en cada llamada
  // (A4 de la 1.18.4). La fecha de escritura es el testigo
  F := TPath.Combine(FDir, 'mismo.md');
  EscribeTexto(F, 'uno', ltTemporal, ekUtf8);
  TFile.SetLastWriteTime(F, EncodeDate(2001, 1, 1));
  EscribeTexto(F, 'uno', ltTemporal, ekUtf8);
  Assert.IsTrue(TFile.GetLastWriteTime(F) < EncodeDate(2002, 1, 1), 'lo mismo no se reescribe');
  EscribeTexto(F, 'dos', ltTemporal, ekUtf8);
  Assert.IsTrue(TFile.GetLastWriteTime(F) > EncodeDate(2002, 1, 1), 'lo distinto si');
  Assert.AreEqual('dos', TEncoding.ASCII.GetString(TFile.ReadAllBytes(F)));
end;

procedure TPuertaDeEscribirTests.LaJaulaNoSeBorraPorAqui;
var
  F, M: string;
begin
  // en la jaula se borra a su papelera (delphi_delete): GUARD-035, y nada.
  // El motivo se mira: aqui no hay raices y la puerta de la jaula negaria
  // igual, asi que una excepcion cualquiera no prueba nada
  F := TPath.Combine(FDir, 'jaula.md');
  EscribeTexto(F, 'x', ltTemporal, ekUtf8);
  M := '';
  try
    BorraFichero(F, ltJaula);
  except
    on E: Exception do
      M := E.Message;
  end;
  Assert.IsTrue(M.StartsWith('[GUARD-035'), M);
  Assert.IsTrue(TFile.Exists(F), 'sigue ahi');
end;

{ TLugarDeRedTests }

function LetraAusente: Char;
begin
  for var C := 'Z' downto 'D' do
    if GetDriveType(PChar(C + ':\')) = DRIVE_NO_ROOT_DIR then
      Exit(C);
  Result := #0;
end;

procedure TLugarDeRedTests.UnUncNoContieneUnaRutaLocal;
begin
  Assert.IsTrue(LugarDeRedParaRutaLocal(Letra + ':\ws\x.pas', '\\192.0.2.1\x'));
end;

procedure TLugarDeRedTests.UnaLetraQueNoEstaNoContieneUnaRutaLocal;
begin
  var L := LetraAusente;
  if L = #0 then
    Assert.Pass('esta maquina no tiene ninguna letra libre');
  Assert.IsTrue(LugarDeRedParaRutaLocal(Letra + ':\ws\x.pas', L + ':\vault'));
end;

procedure TLugarDeRedTests.LaMismaLetraSeMiraEnElDisco;
begin
  Assert.IsFalse(LugarDeRedParaRutaLocal(Letra + ':\ws\x.pas', Letra + ':\otra'));
end;

procedure TLugarDeRedTests.UnaRutaDeRedSeMiraSiempre;
begin
  Assert.IsFalse(LugarDeRedParaRutaLocal('\\192.0.2.1\x\y.pas', '\\192.0.2.1\x'));
  var L := LetraAusente;
  if L <> #0 then
    Assert.IsFalse(LugarDeRedParaRutaLocal(L + ':\y.pas', Letra + ':\ws'));
end;

procedure TLugarDeRedTests.EnAlgunLugarNoPreguntaAlRecursoDeRed;
begin
  var T0 := GetTickCount64;
  Assert.IsFalse(EnAlgunLugar(Letra + ':\ws\x.pas', TArray<string>.Create('\\192.0.2.1\x\')));
  Assert.IsTrue(GetTickCount64 - T0 < 2000, 'no sale a la red');
end;

{ TRutaDesdeTests }

procedure TRutaDesdeTests.LaCompletaTalCual;
begin
  Assert.AreEqual('E:\r', RutaDesde('D:\p', 'E:\q\..\r'));
  Assert.AreEqual('E:\q\r', RutaDesde('D:\p', 'E:/q/r'));
  Assert.AreEqual('\\h\s\x', RutaDesde('D:\p', '\\h\s\x'));
end;

procedure TRutaDesdeTests.LaRelativaDesdeLaBase;
begin
  Assert.AreEqual('D:\p\sub\x.pas', RutaDesde('D:\p', 'sub\x.pas'));
  Assert.AreEqual('D:\x.pas', RutaDesde('D:\p', '..\x.pas'));
  Assert.AreEqual('\\h\s\p\x', RutaDesde('\\h\s\p', 'x'));
end;

procedure TRutaDesdeTests.LaDeRaizEnLaUnidadDeLaBase;
begin
  // la raiz de la unidad de la base, no la del proceso
  Assert.AreEqual('D:\x', RutaDesde('D:\p\q', '\x'));
  Assert.AreEqual('D:\x\y', RutaDesde('D:\p\q', '/x/y'));
  Assert.AreEqual('\\h\s\x', RutaDesde('\\h\s\p', '\x'));
end;

procedure TRutaDesdeTests.LaDeUnidadSoloSiEsLaDeLaBase;
begin
  // "X:y" es la carpeta actual de X: la base si X es su unidad
  Assert.AreEqual('D:\p\x', RutaDesde('D:\p', 'D:x'));
  Assert.AreEqual('D:\p\x', RutaDesde('D:\p', 'd:x'));
  Assert.AreEqual('D:\p', RutaDesde('D:\p', 'D:'));
  // ...y la de otra unidad es del proceso que la lea: no se resuelve
  Assert.AreEqual('', RutaDesde('D:\p', 'E:x'));
  Assert.AreEqual('', RutaDesde('\\h\s\p', 'D:x'));
end;

procedure TRutaDesdeTests.SinBaseSoloLaCompleta;
begin
  Assert.AreEqual('D:\x', RutaDesde('', 'D:\x'));
  for var V in TArray<string>.Create('x', '\x', 'D:x', '..\x') do
    Assert.AreEqual('', RutaDesde('', V), V);
  // una base que no es completa tampoco es base
  Assert.AreEqual('', RutaDesde('relativa', 'x'));
  Assert.AreEqual('', RutaDesde('\sin-unidad', 'x'));
end;

procedure TRutaDesdeTests.LoQueNoEsRutaNoSeResuelve;
begin
  Assert.AreEqual('', RutaDesde('D:\p', ''));
  Assert.AreEqual('', RutaDesde('D:\p', 'a|b'));
  Assert.AreEqual('', RutaDesde('D:\p', 'a<b'));
end;

procedure TRutaDesdeTests.LaCarpetaActualParaLoAMedias;
begin
  Assert.AreEqual('D:\fuentes\x.inc', RutaDesde('D:\fuentes', 'x.inc', 'E:\proy'));
  Assert.AreEqual('E:\x.inc', RutaDesde('D:\fuentes', '\x.inc', 'E:\proy'));
  Assert.AreEqual('E:\proy\x.inc', RutaDesde('D:\fuentes', 'E:x.inc', 'E:\proy'));
  // la unidad del fichero no es la del lector
  Assert.AreEqual('', RutaDesde('D:\fuentes', 'D:x.inc', 'E:\proy'));
  // una carpeta actual que no es completa no es carpeta
  Assert.AreEqual('', RutaDesde('D:\fuentes', '\x.inc', 'relativa'));
end;

procedure TRutaDesdeTests.QueEsUnaRutaAMedias;
begin
  for var V in TArray<string>.Create('\x', '/x', 'C:x', 'c:', 'C:..\x') do
    Assert.IsTrue(EsRutaAMedias(V), V);
  for var V in TArray<string>.Create('', 'x', '..\x', 'C:\x', 'C:/x', '\\h\s', '//h/s', '\\?\C:\x') do
    Assert.IsFalse(EsRutaAMedias(V), V);
end;

{ TFormaDeTextoTests }

procedure TFormaDeTextoTests.UnaCopiaDelIdeConBarrasNormales;
begin
  Assert.IsTrue(EnCopiaDelIde('C:\x\__history\U.pas'));
  Assert.IsTrue(EnCopiaDelIde('C:/x/__history/U.pas'), 'con barras normales');
  Assert.IsTrue(EnCopiaDelIde('C:/x/__recovery/sub/U.pas'), 'con barras normales, mas abajo');
  // la carpeta misma no es una copia: se crea y se quita
  Assert.IsFalse(EnCopiaDelIde('C:/x/__history'));
  Assert.IsFalse(EnCopiaDelIde('C:/x/historia/U.pas'));
end;

procedure TFormaDeTextoTests.UnUncConBarrasNormales;
begin
  Assert.IsTrue(EsUnc('\\h\s\x'));
  Assert.IsTrue(EsUnc('//h/s/x'), 'con barras normales');
  Assert.IsFalse(EsUnc('\\?\C:\x'), 'un prefijo de dispositivo no es un UNC');
  Assert.IsFalse(EsUnc('//?/C:/x'), 'tampoco con barras normales');
  Assert.IsFalse(EsUnc('C:/x'));
end;

{ TAncestrosTests }

procedure TAncestrosTests.HastaLaRaizDeLaUnidad;
begin
  Assert.AreEqual('C:\a\b|C:\a|C:\', string.Join('|', Ancestros('C:\a\b')));
  Assert.AreEqual('C:\', string.Join('|', Ancestros('C:\')), 'la raiz sola');
  // con barra final, la primera de encima es ella sin la barra (lo que hace
  // GetDirectoryName, y lo que el canonizador espera)
  Assert.AreEqual('C:\a\|C:\a|C:\', string.Join('|', Ancestros('C:\a\')), 'con barra final');
end;

procedure TAncestrosTests.HastaLaRaizDeUnRecurso;
begin
  // de \\host\recurso no se sube a \\host: no es una carpeta
  Assert.AreEqual('\\h\s\x|\\h\s', string.Join('|', Ancestros('\\h\s\x')));
end;

procedure TAncestrosTests.ConTope;
begin
  Assert.AreEqual('C:\a\b|C:\a', string.Join('|', Ancestros('C:\a\b', 2)));
  Assert.AreEqual('C:\a\b|C:\a|C:\', string.Join('|', Ancestros('C:\a\b', NIVELES_DE_SUBIDA)),
    'un tope mas alto que la ruta no anade nada');
end;

procedure TAncestrosTests.LoQueNoEsRuta;
begin
  Assert.AreEqual('', string.Join('|', Ancestros('')));
  // un caracter que Windows no admite: ella, y de ahi no se sube
  Assert.AreEqual('C:\a|b\c', string.Join('|', Ancestros('C:\a|b\c')));
end;

{ TPerfilPorLaListaTests }

procedure TPerfilPorLaListaTests.SoloElQueElIdeLista;
const
  VER = '99.0'; // una version que no es de nadie: la carpeta es la de prueba
var
  Base, AppData, Perfiles, Fuera, Antes, Motivo: string;
begin
  // en el temporal del ejecutor, que es su casa (como las puertas de arriba)
  Base := ServerTempDir('perfil-' + FragmentoUnico);
  AppData := TPath.Combine(Base, 'ad');
  Perfiles := TPath.Combine(TPath.Combine(TPath.Combine(AppData, 'Embarcadero'), 'BDS'), VER);
  Fuera := TPath.Combine(Base, 'fuera');
  ForceDirectories(Perfiles);
  ForceDirectories(Fuera);
  TFile.WriteAllText(TPath.Combine(Fuera, 'sonda.profile'),
    '<Profile_host>192.0.2.1</Profile_host><Profile_platform>Linux64</Profile_platform>');
  TFile.WriteAllText(TPath.Combine(Perfiles, 'Listado.profile'),
    '<Profile_host>192.0.2.2</Profile_host><Profile_platform>Win64</Profile_platform>');
  Antes := GetEnvironmentVariable('APPDATA');
  SetEnvironmentVariable('APPDATA', PChar(AppData));
  try
    // de la carpeta de perfiles a Base: 99.0, BDS, Embarcadero, ad
    HostDePerfil(VER, '..\..\..\..\fuera\sonda', Motivo);
    Assert.IsTrue(Motivo.StartsWith('[PAS-053'), 'un .profile de fuera no existe: ' + Motivo);
    HostDePerfil(VER, '..\..\..\..\fuera\nada', Motivo);
    Assert.IsTrue(Motivo.StartsWith('[PAS-053'), 'y uno que no hay, lo mismo: ' + Motivo);
    Assert.AreEqual('', PlataformaDePerfil(VER, '..\..\..\..\fuera\sonda'));
    // el control: el que lista el IDE se ve, con otras mayusculas, por su
    // nombre. Que su fichero SI se lee no se mide aqui: la puerta de leer
    // (ltIde) no sigue a un APPDATA cambiado en caliente (medido); lo mide P4
    // de test_perfil_por_lista_1230, con el APPDATA de prueba desde el arranque
    Assert.AreEqual('Listado', PerfilDelIde(VER, 'LISTADO'));
  finally
    SetEnvironmentVariable('APPDATA', PChar(Antes));
    for var F in [TPath.Combine(Fuera, 'sonda.profile'), TPath.Combine(Perfiles, 'Listado.profile')] do
      if TFile.Exists(F) then
        TFile.Delete(F);
    for var D in [Perfiles, TPath.GetDirectoryName(Perfiles),
      TPath.GetDirectoryName(TPath.GetDirectoryName(Perfiles)), AppData, Fuera, Base] do
      RemoveDir(D);
  end;
end;

{ TMudanzaDeOperadorTests }

// lo que Windows dice libre para esta cuenta en la unidad de ACarpeta; -1 si no
function LibreEn(const ACarpeta: string): Int64;
var
  Total: Int64;
begin
  if not GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(ACarpeta)), Result, Total, nil) then
    Result := -1;
end;

procedure TMudanzaDeOperadorTests.ElSitioPideSuMargen;
begin
  var Casa := ServerTempDir('espacio-' + FragmentoUnico);
  ForceDirectories(Casa);
  try
    var Libre := LibreEn(Casa);
    Assert.IsTrue(Libre > 0, 'Windows dice cuanto hay libre en la casa del ejecutor');
    Assert.AreEqual('', EspacioDenegado(Casa, 0), 'nada que escribir, nada que pedir');
    // cabe en el disco, pero no deja el margen: se niega (el mutante sin
    // margen lo daria por bueno)
    var R := EspacioDenegado(Casa, Libre - MARGEN_DISCO_LIBRE div 2);
    Assert.IsTrue(R.StartsWith('[GUARD-044'), 'dentro del margen se niega: ' + R);
    Assert.IsTrue(EspacioDenegado(Casa, Libre).StartsWith('[GUARD-044'), 'todo lo libre se niega');
    if Libre > 2 * MARGEN_DISCO_LIBRE then
      Assert.AreEqual('', EspacioDenegado(Casa, 1024 * 1024), 'un mega con el margen de sobra cabe')
    else
      Assert.Pass('la unidad de la casa tiene menos de dos margenes libres: lo que cabe no se mide');
  finally
    RemoveDir(Casa);
  end;
end;

procedure TMudanzaDeOperadorTests.UnaCarpetaQueNoExisteMideLaDeArriba;
begin
  var Casa := ServerTempDir('espacio-' + FragmentoUnico);
  ForceDirectories(Casa);
  try
    // la que se va a crear la juzga la unidad donde caera: su primer
    // antepasado que existe; y preguntar no crea nada
    var Honda := TPath.Combine(TPath.Combine(Casa, 'no'), 'existe');
    Assert.IsTrue(EspacioDenegado(Honda, LibreEn(Casa)).StartsWith('[GUARD-044'),
      'todo lo libre, tambien desde una carpeta que no existe');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(Casa, 'no')), 'preguntar no crea la carpeta');
  finally
    RemoveDir(Casa);
  end;
end;

procedure TMudanzaDeOperadorTests.ElComodinSoloEnElNombre;
begin
  Assert.IsTrue(TieneComodin('C:\p\UFicha.*'));
  Assert.IsTrue(TieneComodin('C:\p\U?.pas'));
  Assert.IsFalse(TieneComodin('C:\p\UFicha.pas'));
  // en una CARPETA no es del nombre: lo niega el suelo de la jaula (GUARD-024)
  Assert.IsFalse(TieneComodin('C:\p*\UFicha.pas'));
  Assert.AreEqual('C:\p', CarpetaDelComodin('C:\p\*.pas'));
  Assert.AreEqual('C:\p', CarpetaDelComodin('C:\p\*\'), 'la barra final no cuenta');
end;

{ V106 de la 1.23.1: la clave de una cita es UNA - sin su sangria ni su CR -
  para quien la apunta y para quien la busca. CitaDeLinea la apuntaba tal cual
  y la busqueda le quita el CR a la linea: una cita de un texto que acaba en CR
  salia enmascarada }
procedure TBarridoDeUnidadesTests.UnaCitaConSuCrVaComoEsta;
var
  S, Cita: string;
begin
  OlvidaSalidaHecha; // nada de otra prueba de este hilo
  Cita := CitaDeLinea(5, 'X := ''' + Letra + ':\cr'';'#13);
  S := MaskDriveText('delphi_edit', '[EDIT-099 INVALID_PARAM] x'#13#10'  ' + Cita + #10);
  Assert.Contains(S, Letra + ':\cr', 'la cita del disco, tal cual: ' + S);
end;

procedure TIncludeDelProyectoTests.UnIncludeRelativoALaUnidadSeLeeDesdeElProyecto;
var
  Base, Dpr, Pas: string;
begin
  Base := TPath.Combine(ExtractFileDir(ParamStr(0)), 'inc-' + FragmentoUnico);
  ForceDirectories(TPath.Combine(Base, 'Comun'));
  try
    Pas := TPath.Combine(Base, 'Comun\U.pas');
    TFile.WriteAllText(Pas, 'unit U;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10);
    Dpr := TPath.Combine(Base, 'P.dpr');
    // 'D:Comun\U.pas': relativa a la carpeta actual de ESA unidad, que para dcc
    // es la del proyecto; la del proceso de la prueba es otra
    TFile.WriteAllText(Dpr, 'program P;'#13#10'uses'#13#10'  U in ''' + ExtractFileDrive(Base) +
      'Comun\U.pas'';'#13#10'begin'#13#10'end.'#13#10);
    Assert.IsFalse(SameFileName(ExcludeTrailingPathDelimiter(GetCurrentDir), Base),
      'la carpeta actual del proceso no es la del proyecto');
    Assert.IsTrue(ProyectoListaUnidad(Dpr, Pas), 'el proyecto lista Comun\U.pas');
  finally
    TDirectory.Delete(Base, True);
  end;
end;

procedure TBarridoDeUnidadesTests.LosNombresDeDispositivoDocumentadosSonAnomalias;
begin
  // V131 de la 1.24: los que faltaban en la lista, con y sin extension, en
  // cualquier punto del camino y sin distinguir mayusculas
  for var N in TArray<string>.Create('COM0', 'LPT0', 'COM'#$00B9, 'COM'#$00B2, 'COM'#$00B3,
    'LPT'#$00B9, 'LPT'#$00B2, 'LPT'#$00B3, 'CONIN$', 'CONOUT$', 'com0', 'conin$') do
  begin
    Assert.IsNotEmpty(PathAnomaly('C:\carpeta\' + N), N);
    Assert.IsNotEmpty(PathAnomaly('C:\carpeta\' + N + '.pas'), N + '.pas');
    Assert.IsNotEmpty(PathAnomaly('C:\carpeta\' + N + '\unidad.pas'), N + ' como carpeta');
  end;
  // control: lo que solo se les parece sigue siendo un nombre
  for var N in TArray<string>.Create('COM10', 'LPT10', 'COMA', 'CONIN', 'CONOUT', 'COM'#$00B4, 'COM'#$2074) do
    Assert.AreEqual('', PathAnomaly('C:\carpeta\' + N + '.pas'), N);
end;

procedure TBarridoDeUnidadesTests.SoloLaEtiquetaConNombreEsUnEnlace;
var
  Carpeta, Alias: string;
begin
  // V126 de la 1.24: junction, symlink, symlink de WSL...
  for var T in TArray<Cardinal>.Create($A0000003, $A000000C, $A000001D) do
    Assert.IsTrue(EtiquetaDeEnlace(T), IntToHex(T, 8));
  // ...y OneDrive, dedup, alias de WindowsApps, socket y ProjFS no apuntan a otro nombre
  for var T in TArray<Cardinal>.Create($9000601A, $80000013, $8000001B, $80000023, $9000001C) do
    Assert.IsFalse(EtiquetaDeEnlace(T), IntToHex(T, 8));
  // uno de verdad, si la maquina tiene: un punto de reparse que no es un enlace
  Carpeta := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Microsoft\WindowsApps');
  Alias := '';
  if TDirectory.Exists(Carpeta) then
    for var F in TDirectory.GetFiles(Carpeta, '*.exe') do
      if (GetFileAttributes(PChar(F)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
      begin
        Alias := F;
        Break;
      end;
  if Alias <> '' then
    Assert.IsFalse(Lsp.Reparse.EsEnlace(Alias), Alias);
end;

function SinTocarLaRaiz(const ARaiz: string): string;
begin
  Result := ARaiz;
end;

procedure TLectoresDeJaulaTests.LaRaizMasHondaNoDependeDelOrden;
const
  ARRIBA = 'C:\Nadie\W\';
  HONDA = 'C:\Nadie\W\agentes\';
  RUTA = 'C:\Nadie\W\agentes\uno\a.pas';
begin
  Assert.AreEqual(HONDA, RaizMasHonda([ARRIBA, HONDA], RUTA, SinTocarLaRaiz));
  Assert.AreEqual(HONDA, RaizMasHonda([HONDA, ARRIBA], RUTA, SinTocarLaRaiz));
  Assert.AreEqual(ARRIBA, RaizMasHonda([HONDA, ARRIBA], 'C:\Nadie\W\b.pas', SinTocarLaRaiz));
  Assert.AreEqual('', RaizMasHonda([HONDA, ARRIBA], 'C:\Nadie\Wotra\b.pas', SinTocarLaRaiz));
end;

procedure TLectoresDeJaulaTests.LaRaizMasHondaPorLasDosFormas;
var
  Larga: TFormaDeRaiz;
begin
  Larga :=
    function(const ARaiz: string): string
    begin
      Result := StringReplace(ARaiz, 'CORTA~1', 'Larguisima', []);
    end;
  // en su forma, o por el texto con que se declaro; devuelve la forma
  Assert.AreEqual('C:\Larguisima\', RaizMasHonda(['C:\CORTA~1\'], 'C:\Larguisima\a', Larga));
  Assert.AreEqual('C:\Larguisima\', RaizMasHonda(['C:\CORTA~1\'], 'C:\Otra\a', Larga, 'C:\CORTA~1\a'));
  Assert.AreEqual('', RaizMasHonda(['C:\CORTA~1\'], 'C:\Otra\a', Larga));
end;

procedure TLectoresDeJaulaTests.UnNombreSueltoLoJuzgaWindows;
const
  CASA = 'C:\Nadie\Casa';
begin
  Assert.IsTrue(EsNombreSueltoEn(CASA, 'a.png'));
  Assert.IsTrue(EsNombreSueltoEn(CASA + '\', 'a b.png'));
  for var Malo in TArray<string>.Create('', '..\a.png', 'x\a.png', 'x/a.png', '../a.png',
    'a.png:s', 'C:\a.png', 'C:a.png', '\a.png', 'a.png.', 'a.png ', '.') do
    Assert.IsFalse(EsNombreSueltoEn(CASA, Malo), Malo);
end;

procedure TLectoresDeJaulaTests.UnaUnidadVirtualBajoSuLetra;
begin
  Assert.AreEqual('D:\x', RutaBajoSuLetra('srvd:\x'));
  Assert.AreEqual('Z:/x', RutaBajoSuLetra('srvz:/x'));
  Assert.AreEqual('D:', RutaBajoSuLetra('srvd:'));
  Assert.AreEqual('', RutaBajoSuLetra('srvd:x'));
  Assert.AreEqual('', RutaBajoSuLetra('D:\x'));
end;

// lo que paclient recibia cuando cada sitio lo escribia a mano, letra por letra (V222);
// una barra final se queda: su lector es la RTL de Delphi y no la lee como escape (V115)
procedure TLectoresDeJaulaTests.LasOperacionesDePaclient;
begin
  Assert.AreEqual('"C:\a b\"', ComillasSinEscape('C:\a b\'));
  Assert.AreEqual('"--get=P/s.txt,C:\t"', PaclientGet('P/s.txt', 'C:\t'));
  Assert.AreEqual('"--put=C:\a b,P,3,n"', PaclientPut('C:\a b', 'P', 3, 'n'));
  Assert.AreEqual('"--Remove=P/a;P/b"', PaclientRemove(['P/a', 'P/b']));
  Assert.AreEqual('"--Remove=P/a"', PaclientRemove(['P/a']));
  Assert.AreEqual('--local "--host=h" --port=64211 "--password=p\" "--platform=Linux64"',
    PaclientPerfilNuevo('h', '64211', 'p\', 'Linux64'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLectoresDeJaulaTests);
  TDUnitX.RegisterTestFixture(TFormaDeclaradaTests);
  TDUnitX.RegisterTestFixture(TIncludeDelProyectoTests);
  TDUnitX.RegisterTestFixture(TFormaDeclaradaEnTextoTests);
  TDUnitX.RegisterTestFixture(TBarridoDeUnidadesTests);
  TDUnitX.RegisterTestFixture(TClaveDeCarpetaTests);
  TDUnitX.RegisterTestFixture(TSelloUnicoTests);
  TDUnitX.RegisterTestFixture(TPuertaDeLeerTests);
  TDUnitX.RegisterTestFixture(TPuertaDeEscribirTests);
  TDUnitX.RegisterTestFixture(TLugarDeRedTests);
  TDUnitX.RegisterTestFixture(TRutaDesdeTests);
  TDUnitX.RegisterTestFixture(TFormaDeTextoTests);
  TDUnitX.RegisterTestFixture(TAncestrosTests);
  TDUnitX.RegisterTestFixture(TPerfilPorLaListaTests);
  TDUnitX.RegisterTestFixture(TMudanzaDeOperadorTests);

end.
