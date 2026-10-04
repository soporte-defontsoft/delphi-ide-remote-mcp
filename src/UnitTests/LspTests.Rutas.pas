unit LspTests.Rutas;

// La forma DECLARADA de una ruta que llega resuelta, en sus dos usos
// (Lsp.Guard): FormaDeclaradaDe sobre UNA ruta - lo que git contesta cuando
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
    [Test] procedure ElUncQueAbreLineaEnUnJsonSeEnmascara;
    [Test] procedure UnaCarpetaDeUnaLetraNoEsUnSaltoDeLinea;
    [Test] procedure ElUncDeUnaListaDeRutasSeEnmascara;
    [Test] procedure ElUncPegadoAUnaOpcionSeEnmascara;
    [Test] procedure ElUncDobladoDosVecesSeEnmascara;
    [Test] procedure ElUncExtendidoYElHostRaroSeEnmascaran;
    [Test] procedure LasClavesDeUnJsonTambienSeEnmascaran;
    [Test] procedure LaFilaDeUnaTandaDejaElDiscoComoEsta;
    [Test] procedure LosControlesSonAnomaliasPorSiMismos;
  end;

  { LA clave de una carpeta (Lsp.Guard.ClaveDeCarpeta): la misma carpeta
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

implementation

uses
  System.SysUtils,
  Lsp.Guard;

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

initialization
  TDUnitX.RegisterTestFixture(TFormaDeclaradaTests);
  TDUnitX.RegisterTestFixture(TFormaDeclaradaEnTextoTests);
  TDUnitX.RegisterTestFixture(TBarridoDeUnidadesTests);
  TDUnitX.RegisterTestFixture(TClaveDeCarpetaTests);

end.
