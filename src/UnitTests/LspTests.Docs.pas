unit LspTests.Docs;

{ La ayuda instalada de Delphi (delphi_docs, 1.10.0), contra los ficheros de
  esta maquina: los encuentra la lista del IDE (Help\HtmlHelp1Files) y se
  leen por dentro, sin extraer nada. Una maquina sin la ayuda instalada pasa
  diciendolo, y lo de "sin la ayuda" lo dice su sitio en la instalacion, no
  el codigo que se prueba: una regresion en la lista del IDE los ponia verdes
  sin medir nada (revision de la 1.10.0). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAyudaInstaladaTests = class
  public
    [Test]
    procedure LaListaDelIdeYUnaPaginaLeidaPorDentro;
    [Test]
    procedure CadaAyudaConSuNombreCorto;
    [Test]
    procedure UnChmCortadoNoTumbaLaLectura;
  end;

  { Lo puro de Lsp.Docs, sin disco: trozos de HTML con la forma de las paginas
    de la ayuda (mirada en system.chm, topics.chm y fmx.chm el 2-oct-2026). }
  [TestFixture]
  TDocsPurasTests = class
  public
    [Test]
    procedure ElJuegoDeCaracteresLoDiceLaPagina;
    [Test]
    procedure DelMapaSoloLosBloquesQueCasan;
    [Test]
    procedure LosPuntosOrdenanIgualEmpiezaContiene;
    [Test]
    procedure UnaPaginaComoTexto;
    [Test]
    procedure UnaSeccionSolaSinMirarMayusculas;
    [Test]
    procedure UnaSeccionQueNoEstaDaLaPaginaEntera;
    [Test]
    procedure LaQueSoloRedirigeDaSuDestino;
    [Test]
    procedure ElIdDeUnEnlace;
    [Test]
    procedure UnIdSoloNombraPaginasDeDentro;
    [Test]
    procedure ElPadrePorSuFormaNoPorSuFrase;
    [Test]
    procedure UnaPalabraDeLasEtiquetasNoSaltaBloques;
    [Test]
    procedure ElIdSeComponeYSeLeeIgual;
    [Test]
    procedure LaConsultaSinComillasNiSignos;
    [Test]
    procedure LasEntidadesYElMetaLejano;
    [Test]
    procedure UnaSeccionPorSuTituloComoSeLee;
    [Test]
    procedure LaQueEnvuelveLaPaginaAcabaEnSuPrimerSubtitulo;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Discovery,
  Lsp.Chm,
  Lsp.Docs,
  System.IOUtils;

const
  // un indice de palabras (.hhk): un bloque <OBJECT> por entrada
  MAPA =
    '<HTML><BODY><UL>'#13#10 +
    '<LI><OBJECT type="text/sitemap"><param name="Name" value="TStringList">' +
    '<param name="Local" value="System.Classes.TStringList.htm"></OBJECT>'#13#10 +
    '<LI><OBJECT type="text/sitemap"><param name="Name" value="TStringList.Sort">' +
    '<param name="Local" value="System.Classes.TStringList.Sort.htm#Sort">' +
    '</OBJECT>'#13#10 +
    '<LI><OBJECT type="text/sitemap"><param name="Name" value="Format &amp; co">' +
    '<param name="Local" value="F.htm"><param name="Local" value="G.htm">' +
    '</OBJECT>'#13#10 +
    '</UL></BODY></HTML>';

  // una pagina con todo lo que el texto tiene que dejar fuera o ordenar
  PAGINA =
    '<html><head><meta http-equiv="Content-Type" content="text/html; ' +
    'charset=windows-1252"><title>Declarations and Statements (Delphi) - ' +
    'RAD Studio</title></head><body><h1 id="firstHeading" ' +
    'class="firstHeading">Declarations and Statements (Delphi)</h1>' +
    '<div id="mw-content-text"><div id="lstfilter"><input ' +
    'id="inheritcheck" type="checkbox" />Inherited<input id="protectcheck" ' +
    'type="checkbox" />Protected</div>' +
    '<map name="Jerarquia"><area title="System.Classes.TComponent" ' +
    'href="System.Classes.TComponent.htm" /><area title="System.TObject" ' +
    'href="System.TObject.htm" /></map>' +
    '<p><i>Go Up to <a href="Guide.htm" title="Guide">Delphi Language Guide ' +
    'Index</a></i></p>' +
    '<p>Intro &amp; more.</p>' +
    '<div id="toc" class="toc"><ul><li><a href="#Declarations">' +
    '<span class="tocnumber">1</span> <span class="toctext">Declarations' +
    '</span></a><ul><li><a href="#Hinting_Directives"><span ' +
    'class="toctext">Hinting Directives</span></a></li></ul></li><li>' +
    '<a href="#For_Statements"><span class="toctext">For Statements</span>' +
    '</a></li></ul></div>' +
    '<h2><span class="mw-headline" id="Declarations">Declarations</span>' +
    '</h2><p>Decl text.</p><h3><span class="mw-headline" ' +
    'id="Hinting_Directives">Hinting Directives</span></h3><p>Hint text.</p>' +
    '<div class="cpp"><pre>int solo_cpp;</pre></div>' +
    '<p>Visible <span class="appmethod">oculto</span>y mas.</p>' +
    '<pre>for I := 0 to 9 do'#10'  Writeln(I &lt; 10);</pre>' +
    '<table><tr><th>Name</th><th>Meaning</th></tr><tr><td><p>Path1</p></td>' +
    '<td>The first path.</td></tr></table>' +
    '<h2><span class="mw-headline" id="For_Statements">For Statements</span>' +
    '</h2><p>For text.</p><ul id="childlinks"><li><a href="Guide.htm">' +
    'Up to Parent: Guide</a></li><li><a href="X_Methods.htm">Methods</a>' +
    '</li></ul></div><div id="catlinks">Categories: ignorar</div>' +
    '</body></html>';

  // una de la API: Properties (h4) arriba y Description (h2), de la que
  // cuelga todo en h3; la caja de contenidos con su h2 sin ancla; las anclas
  // como las escriben las ayudas (con comillas o sin ellas, '(' como '.28')
  API =
    '<html><body><h1 id="firstHeading">System.X.Y</h1>' +
    '<div id="mw-content-text"><div id="toc" class="toc"><div id="toctitle">' +
    '<h2>Contents</h2></div><ul><li><a href="#Description"><span ' +
    'class="toctext">Description</span></a></li></ul></div>' +
    '<h4><span class="mw-headline" id="Properties">Properties</span></h4>' +
    '<p>Props.</p>' +
    '<h2><span class="mw-headline" id="Description">Description</span></h2>' +
    '<p>Desc text.</p>' +
    '<h3><span class=mw-headline id=Code_Insight_.28LSP.29>Code Insight (LSP)' +
    '</span></h3><p>LSP text.</p>' +
    '<h3><span class="mw-headline" id="See_Also">See Also</span></h3>' +
    '<p>See text.</p></div><div id="catlinks">x</div></body></html>';

  // la que solo redirige (259 en topics.chm), aqui a otra ayuda
  REDIRIGE =
    '<html><head><title>FormatDateTime - RAD Studio</title></head><body>' +
    '<div id="mw-content-text"><span class="redirectText" id="softredirect">' +
    '<a href="ms-its:system.chm::/System.SysUtils.FormatDateTime.htm">' +
    'System.SysUtils.FormatDateTime</a></span></div></body></html>';

function BytesEn(const S: string; ACodigo: Integer): TArray<Byte>;
var
  E: TEncoding;
begin
  E := TEncoding.GetEncoding(ACodigo);
  try
    Result := E.GetBytes(S);
  finally
    E.Free;
  end;
end;

// Que esta maquina TIENE la ayuda, mirado sin el codigo que se prueba: su
// sitio de siempre en la instalacion
function HayAyudaEnElDisco: Boolean;
var
  Info: TRadStudioInfo;
begin
  Info := DiscoverRadStudio;
  Result := Info.Found and
    TFile.Exists(IncludeTrailingPathDelimiter(Info.RootDir) + 'Help\Doc\system.chm');
end;

function Cuenta(const AEn, AQue: string): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := AEn.IndexOf(AQue);
  while P >= 0 do
  begin
    Inc(Result);
    P := AEn.IndexOf(AQue, P + 1);
  end;
end;

{ ------------------------------------------------- la ayuda de esta maquina }

procedure TAyudaInstaladaTests.LaListaDelIdeYUnaPaginaLeidaPorDentro;
var
  Ayudas: TArray<TIdeAyuda>;
  Sistema: string;
  Chm: TChm;
  B: TArray<Byte>;
begin
  Ayudas := IdeHelpFiles(DiscoverRadStudio.Version);
  Sistema := '';
  for var A in Ayudas do
    if SameText(ExtractFileName(A.Fichero), 'system.chm') then
      Sistema := A.Fichero;
  if Sistema = '' then
  begin
    if HayAyudaEnElDisco then
      Assert.Fail('system.chm esta en la instalacion y la lista del IDE no lo da');
    Assert.Pass(Format('esta maquina no registra system.chm (%d ayudas)', [Length(Ayudas)]));
    Exit;
  end;
  Chm := TChm.Create(Sistema);
  try
    Assert.IsTrue(Chm.Lee('index.hhk', B), 'el indice de palabras, dentro');
    Assert.IsTrue(Length(B) > 1000000, Format('index.hhk de %d bytes', [Length(B)]));
    Assert.IsTrue(Chm.Lee('System.SysUtils.FormatDateTime.htm', B), 'la pagina, dentro');
    Assert.Contains(TEncoding.UTF8.GetString(B), 'Displays the minute');
    Assert.IsFalse(Chm.Lee('NoExiste.htm', B), 'una que no esta');
    Assert.IsFalse(Chm.Lee('../system.chm', B), 'subir no lleva a ninguna parte');
    Assert.IsTrue(Length(Chm.Raiz) > 10000, 'los ficheros de su raiz');
  finally
    Chm.Free;
  end;
end;

procedure TAyudaInstaladaTests.CadaAyudaConSuNombreCorto;
var
  Ayudas: TArray<TAyudaInstalada>;
  Vistos: TArray<string>;
begin
  Ayudas := AyudasInstaladas;
  if Length(Ayudas) = 0 then
  begin
    if HayAyudaEnElDisco then
      Assert.Fail('system.chm esta en la instalacion y no sale ninguna ayuda');
    Assert.Pass('esta maquina no tiene la ayuda instalada');
    Exit;
  end;
  Vistos := nil;
  for var A in Ayudas do
  begin
    Assert.IsTrue(A.Corto <> '', 'el nombre corto de ' + A.Fichero);
    Assert.IsFalse(A.Corto.Contains(':') or A.Corto.Contains('#'),
      'un nombre corto que no rompe el id: ' + A.Corto);
    for var V in Vistos do
      Assert.IsFalse(SameText(V, A.Corto), 'dos ayudas con el nombre ' + V);
    Vistos := Vistos + [A.Corto];
  end;
  Assert.Contains(',' + string.Join(',', Vistos) + ',', ',system,', 'la de la RTL');
end;

{ -------------------------------------------------------------- lo puro }

procedure TDocsPurasTests.ElJuegoDeCaracteresLoDiceLaPagina;
const
  CAFE = 'caf' + #$E9;
begin
  Assert.AreEqual(CAFE, TextoDeBytes(TArray<Byte>.Create($EF, $BB, $BF) +
    TEncoding.UTF8.GetBytes(CAFE)), 'UTF-8 con BOM');
  // sin BOM manda el meta: casi todas dicen Windows-1252, alguna UTF-8
  Assert.IsTrue(TextoDeBytes(BytesEn('<meta charset=windows-1252>' + CAFE,
    1252)).EndsWith(CAFE), 'Windows-1252');
  Assert.IsTrue(TextoDeBytes(TEncoding.UTF8.GetBytes(
    '<meta content="text/html; charset=utf-8">' + CAFE)).EndsWith(CAFE), 'UTF-8 por su meta');
  // el de HTML5, con comillas: solo se reconocia sin ellas (revision de la
  // 1.10.0)
  Assert.IsTrue(TextoDeBytes(TEncoding.UTF8.GetBytes(
    '<meta charset="utf-8">' + CAFE)).EndsWith(CAFE), 'UTF-8 con comillas');
  Assert.IsTrue(TextoDeBytes(TEncoding.UTF8.GetBytes(
    '<meta charset = ''UTF-8''>' + CAFE)).EndsWith(CAFE), 'con blancos, en mayusculas');
end;

procedure TDocsPurasTests.DelMapaSoloLosBloquesQueCasan;
var
  B: TArray<Byte>;
  E: TArray<TEntradaDeMapa>;
begin
  B := BytesEn(MAPA, 1252);
  E := EntradasQueCasan(B, 'TSTRINGLIST', []);
  Assert.AreEqual(2, Integer(Length(E)), 'las dos de TStringList, sin mirar mayusculas');
  Assert.AreEqual('TStringList', E[0].Nombre);
  Assert.AreEqual('System.Classes.TStringList.Sort.htm#Sort', E[1].Local,
    'la seccion viaja con la pagina');
  E := EntradasQueCasan(B, 'tstringlist', ['sort']);
  Assert.AreEqual(1, Integer(Length(E)), 'con todas las palabras');
  Assert.AreEqual('TStringList.Sort', E[0].Nombre);
  E := EntradasQueCasan(B, 'format', []);
  Assert.AreEqual(2, Integer(Length(E)), 'un nombre con dos paginas da dos entradas');
  Assert.AreEqual('Format & co', E[0].Nombre, 'las entidades, decodificadas');
  Assert.AreEqual('G.htm', E[1].Local);
  Assert.AreEqual(0, Integer(Length(EntradasQueCasan(B, 'nada', []))), 'lo que no esta');
  Assert.AreEqual(0, Integer(Length(EntradasQueCasan(B, 'html', []))), 'fuera de los bloques');
  Assert.AreEqual(0, Integer(Length(EntradasQueCasan(B, 'sitemap', ['zz']))), 'una palabra que falta');
end;

procedure TDocsPurasTests.LosPuntosOrdenanIgualEmpiezaContiene;
begin
  Assert.AreEqual(100, PuntosDePalabra('tstringlist', 'tstringlist'));
  Assert.AreEqual(55, PuntosDePalabra('tstringlist.sort', 'tstringlist'),
    'empieza por ella, menos lo que sobra');
  Assert.AreEqual(28, PuntosDePalabra('mytstringlist', 'tstringlist'), 'la contiene');
  Assert.AreEqual(35, PuntosDePalabra('tstringlist' + StringOfChar('x', 40), 'tstringlist'),
    'lo que sobra resta 25 como mucho');
  Assert.AreEqual(0, PuntosDePalabra('tlist', 'tstringlist'));
  Assert.AreEqual(0, PuntosDePalabra('', 'tstringlist'));
end;

procedure TDocsPurasTests.UnaPaginaComoTexto;
var
  P: TPaginaDoc;
begin
  P := PaginaComoTexto(PAGINA, '');
  Assert.AreEqual('Declarations and Statements (Delphi)', P.Titulo, 'el h1');
  Assert.Contains(P.Texto, 'Ancestors: System.Classes.TComponent > System.TObject',
    'la jerarquia, del mapa de la imagen');
  Assert.Contains(P.Texto, 'Intro & more.', 'las entidades');
  Assert.Contains(P.Texto, '## Declarations');
  Assert.Contains(P.Texto, '### Hinting Directives');
  Assert.Contains(P.Texto, '```'#10'for I := 0 to 9 do'#10'  Writeln(I < 10);'#10'```',
    'el codigo tal cual, con sus saltos y su sangria');
  Assert.Contains(P.Texto, 'Name | Meaning');
  Assert.Contains(P.Texto, 'Path1 | The first path.', 'un parrafo dentro de una celda no parte la fila');
  Assert.Contains(P.Texto, 'Visible y mas.');
  Assert.DoesNotContain(P.Texto, 'solo_cpp', 'lo de C++');
  Assert.DoesNotContain(P.Texto, 'oculto', 'lo que la pagina esconde');
  Assert.DoesNotContain(P.Texto, 'Inherited', 'las casillas del filtro de una lista de miembros');
  Assert.DoesNotContain(P.Texto, 'Go Up to', 'la navegacion de arriba');
  Assert.DoesNotContain(P.Texto, 'Categories', 'el pie');
  Assert.DoesNotContain(P.Texto, 'Up to Parent', 'la barra de la clase va a Enlaces');
  Assert.AreEqual(1, Cuenta(P.Texto, 'Hinting Directives'), 'la caja de secciones no sale en el texto');
  Assert.AreEqual(3, Integer(Length(P.Secciones)), 'las tres, tambien la de la lista de dentro');
  Assert.AreEqual('Hinting_Directives', P.Secciones[1].Ancla);
  Assert.AreEqual('For Statements', P.Secciones[2].Titulo);
  Assert.DoesNotContain(P.Texto, 'Delphi Language Guide Index', 'el padre va a Enlaces');
  Assert.AreEqual(3, Integer(Length(P.Enlaces)), 'el padre y la barra de la clase');
  Assert.AreEqual('Guide.htm', P.Enlaces[0].Href, 'el padre, el primero');
  Assert.AreEqual('Delphi Language Guide Index', P.Enlaces[0].Texto);
  Assert.AreEqual('X_Methods.htm', P.Enlaces[2].Href);
  Assert.AreEqual('Methods', P.Enlaces[2].Texto);
  Assert.AreEqual('', P.Redirige);
end;

procedure TDocsPurasTests.UnaSeccionSolaSinMirarMayusculas;
var
  P: TPaginaDoc;
begin
  // el indice enlaza ..._For_statements y la pagina dice ..._For_Statements (medido)
  P := PaginaComoTexto(PAGINA, 'for_statements');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.StartsWith('## For Statements', P.Texto);
  Assert.Contains(P.Texto, 'For text.');
  Assert.DoesNotContain(P.Texto, 'Decl text.', 'la seccion sola');
  // una de nivel 2 lleva dentro las de nivel 3 y acaba en la siguiente de su nivel
  P := PaginaComoTexto(PAGINA, 'Declarations');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.Contains(P.Texto, '### Hinting Directives');
  Assert.Contains(P.Texto, 'Hint text.');
  Assert.DoesNotContain(P.Texto, 'For text.');
  Assert.AreEqual(3, Integer(Length(P.Secciones)), 'la lista de secciones sigue entera');
end;

procedure TDocsPurasTests.UnaSeccionQueNoEstaDaLaPaginaEntera;
var
  P: TPaginaDoc;
begin
  P := PaginaComoTexto(PAGINA, 'NoEsta');
  Assert.IsFalse(P.AnclaEncontrada);
  Assert.Contains(P.Texto, 'Intro & more.');
  Assert.Contains(P.Texto, 'For text.');
end;

procedure TDocsPurasTests.LaQueSoloRedirigeDaSuDestino;
var
  P: TPaginaDoc;
begin
  P := PaginaComoTexto(REDIRIGE, '');
  Assert.AreEqual('ms-its:system.chm::/System.SysUtils.FormatDateTime.htm', P.Redirige);
  Assert.AreEqual('system:System.SysUtils.FormatDateTime.htm', IdDeEnlace(P.Redirige, 'topics'),
    'el destino, en otra ayuda');
end;

procedure TDocsPurasTests.ElIdDeUnEnlace;
begin
  Assert.AreEqual('vcl:Vcl.StdCtrls.TButton_Methods.htm',
    IdDeEnlace('Vcl.StdCtrls.TButton_Methods.htm', 'vcl'));
  Assert.AreEqual('vcl:X.htm#Sec', IdDeEnlace('X.htm#Sec', 'vcl'), 'con su seccion');
  Assert.AreEqual('fmx:Y.html', IdDeEnlace('./Y.html', 'fmx'));
  Assert.AreEqual('system:System.SysUtils.htm',
    IdDeEnlace('ms-its:system.chm::/System.SysUtils.htm', 'vcl'), 'ms-its: la ayuda del enlace');
  Assert.AreEqual('indy10:TIdHTTP.html', IdDeEnlace('ms-its:Indy10.chm::/TIdHTTP.html', 'vcl'));
  Assert.AreEqual('', IdDeEnlace('http://docwiki.embarcadero.com/X.htm', 'vcl'), 'la web');
  Assert.AreEqual('', IdDeEnlace('#Seccion', 'vcl'), 'un ancla de la misma pagina');
  Assert.AreEqual('', IdDeEnlace('imagen.png', 'vcl'), 'no es una pagina');
  Assert.AreEqual('', IdDeEnlace('mailto:x@y.htm', 'vcl'));
end;

procedure TDocsPurasTests.UnIdSoloNombraPaginasDeDentro;
var
  C, Pg, A: string;
begin
  Assert.IsTrue(PartesDeId('System:System.SysUtils.FormatDateTime.htm#Sec', C, Pg, A));
  Assert.AreEqual('system', C, 'la ayuda, en minusculas');
  Assert.AreEqual('System.SysUtils.FormatDateTime.htm', Pg);
  Assert.AreEqual('Sec', A);
  Assert.IsTrue(PartesDeId('teechart:Library/TRectF.html', C, Pg, A), 'una carpeta de dentro');
  Assert.IsFalse(PartesDeId('System.SysUtils.htm', C, Pg, A), 'sin la ayuda');
  Assert.IsFalse(PartesDeId('system:../x.htm', C, Pg, A), 'subir');
  Assert.IsFalse(PartesDeId('system:a/../../x.htm', C, Pg, A), 'subir por el medio');
  Assert.IsFalse(PartesDeId('system:a\..\x.htm', C, Pg, A), 'subir con barras de Windows');
  Assert.IsFalse(PartesDeId('system:C:\Windows\x.htm', C, Pg, A), 'una unidad');
  Assert.IsFalse(PartesDeId('C:\Windows\x.htm', C, Pg, A), 'una ruta entera');
  Assert.IsFalse(PartesDeId('system:/x.htm', C, Pg, A), 'la raiz');
  Assert.IsFalse(PartesDeId('system:./x.htm', C, Pg, A), 'el punto');
  Assert.IsFalse(PartesDeId('system:x.exe', C, Pg, A), 'no es una pagina');
end;

procedure TDocsPurasTests.ElPadrePorSuFormaNoPorSuFrase;
const
  // la ayuda en otro idioma, con la caja de contenidos (y su h2) delante
  OTRO_IDIOMA =
    '<div id="mw-content-text"><div id="toc"><div id="toctitle"><h2>Inhalt' +
    '</h2></div><ul><li><a href="#A"><span class="toctext">A</span></a></li>' +
    '</ul></div><p><i>Nach oben zu <a href="Index.htm" title="Index">' +
    'Sprachreferenz</a></i></p><h2><span class="mw-headline" id="A">A</span>' +
    '</h2><p>Text <i>mit <a href="X.htm">Link</a> und mehr</i>.</p></div>';
  // una cursiva de verdad: una frase larga con su enlace
  CURSIVA =
    '<div id="mw-content-text"><p><i>This italic sentence is much longer ' +
    'than thirty characters, see <a href="Y.htm">Y</a></i></p></div>';
var
  P: TPaginaDoc;
begin
  P := PaginaComoTexto(OTRO_IDIOMA, '');
  Assert.AreEqual(1, Integer(Length(P.Enlaces)), 'el padre, en cualquier idioma');
  Assert.AreEqual('Index.htm', P.Enlaces[0].Href);
  Assert.AreEqual('Sprachreferenz', P.Enlaces[0].Texto);
  Assert.DoesNotContain(P.Texto, 'Nach oben');
  Assert.Contains(P.Texto, 'Text mit Link und mehr', 'una cursiva tras el primer titulo es texto');
  P := PaginaComoTexto(CURSIVA, '');
  Assert.AreEqual(0, Integer(Length(P.Enlaces)), 'una frase en cursiva no es la navegacion');
  Assert.Contains(P.Texto, 'see Y');
end;

procedure TAyudaInstaladaTests.UnChmCortadoNoTumbaLaLectura;
var
  Ayudas: TArray<TIdeAyuda>;
  Sistema, Cortado: string;
  B: TArray<Byte>;
  Chm: TChm;
begin
  // una ayuda danada (un .chm a medias) no tumba nada: Lee dice False y no
  // lanza (antes, OleCheck: una sola ayuda rota dejaba TODA busqueda en
  // SYS-006; revision de la 1.10.0)
  Ayudas := IdeHelpFiles(DiscoverRadStudio.Version);
  Sistema := '';
  for var A in Ayudas do
    if SameText(ExtractFileName(A.Fichero), 'system.chm') then
      Sistema := A.Fichero;
  if Sistema = '' then
  begin
    if HayAyudaEnElDisco then
      Assert.Fail('system.chm esta en la instalacion y la lista del IDE no lo da');
    Assert.Pass('esta maquina no registra system.chm');
    Exit;
  end;
  // en la carpeta del ejecutor: la unica donde el sandbox escribe; con un
  // nombre de esta pasada, que dos a la vez se pisaban el fichero
  Cortado := ExtractFilePath(ParamStr(0)) + 'cortado-prueba-' +
    TGUID.NewGuid.ToString.Trim(['{', '}']) + '.chm';
  B := TFile.ReadAllBytes(Sistema);
  SetLength(B, Length(B) div 3);
  TFile.WriteAllBytes(Cortado, B);
  try
    try
      Chm := TChm.Create(Cortado);
    except
      Assert.Pass('Windows ni lo abre: quien abre una ayuda lo recoge');
      Exit;
    end;
    try
      // ninguna lectura lanza: o lo da, o dice que no
      for var N in TArray<string>.Create('index.hhk', 'System.SysUtils.FormatDateTime.htm',
        'System.Classes.TStringList.htm', 'NoExiste.htm') do
        Chm.Lee(N, B);
      Chm.Raiz;
      Assert.Pass('un .chm a medias se lee sin lanzar');
    finally
      Chm.Free;
    end;
  finally
    TFile.Delete(Cortado);
  end;
end;

procedure TDocsPurasTests.UnaPalabraDeLasEtiquetasNoSaltaBloques;
var
  B: TArray<Byte>;
begin
  // 'object' esta en cada <OBJECT> y en cada </OBJECT>: un acierto en un
  // cierre saltaba hasta el siguiente cierre y se comia el bloque de detras
  // (medido en la revision de la 1.10.0: 'object' no encontraba nada)
  B := BytesEn(MAPA, 1252);
  Assert.AreEqual(4, Integer(Length(EntradasQueCasan(B, 'object', []))), 'los tres bloques, cuatro paginas');
  Assert.AreEqual(4, Integer(Length(EntradasQueCasan(B, 'OBJECT', ['sitemap']))));
end;

procedure TDocsPurasTests.ElIdSeComponeYSeLeeIgual;
var
  C, Pg, A: string;
begin
  Assert.AreEqual('system:System.SysUtils.htm#Funcs', IdDePagina('system', 'System.SysUtils.htm', 'Funcs'));
  Assert.AreEqual('system:System.SysUtils.htm', IdDePagina('system', 'System.SysUtils.htm', ''));
  Assert.IsTrue(PartesDeId(IdDePagina('teechart', 'Library/TRectF.html', 'X'), C, Pg, A));
  Assert.AreEqual('teechart|Library/TRectF.html|X', C + '|' + Pg + '|' + A, 'la inversa');
  // un caracter de control no es de ningun id: el #0 cortaba el nombre al
  // abrirlo y 'index.hhk'#0'.htm' leia el indice entero
  Assert.IsFalse(PartesDeId('system:index.hhk'#0'.htm', C, Pg, A), 'el NUL');
  Assert.IsFalse(PartesDeId('system:x'#9'.htm', C, Pg, A), 'un tabulador');
  // el enlace y el id de una entrada salen del mismo compositor
  Assert.AreEqual('vcl:X.htm#S', IdDeEnlace('X.htm#S', 'vcl'));
end;

procedure TDocsPurasTests.LaConsultaSinComillasNiSignos;
var
  P: TArray<string>;
begin
  P := PalabrasDeConsulta('"class helpers"');
  Assert.AreEqual(2, Integer(Length(P)), 'las comillas no son de la palabra');
  Assert.AreEqual('class|helpers', string.Join('|', P));
  Assert.AreEqual('tstringlist.sort', string.Join('|', PalabrasDeConsulta(' TStringList.Sort ')),
    'el punto de dentro se queda');
  Assert.AreEqual(0, Integer(Length(PalabrasDeConsulta(' "" (), '))), 'solo signos: nada');
  // una firma busca su nombre, y los argumentos genericos no estan en los
  // titulos de la ayuda (dato de Hermes, revision de la 1.13.0)
  Assert.AreEqual('formatdatetime', string.Join('|',
    PalabrasDeConsulta('FormatDateTime(const Format: string; DateTime: TDateTime): string')));
  Assert.AreEqual('system.sysutils.formatdatetime', string.Join('|',
    PalabrasDeConsulta('System.SysUtils.FormatDateTime(const F: string)')));
  Assert.AreEqual('tlist.add', string.Join('|', PalabrasDeConsulta('TList<T>.Add')));
  Assert.AreEqual('tdictionary.trygetvalue', string.Join('|',
    PalabrasDeConsulta('TDictionary<TKey, TValue>.TryGetValue(const Key: TKey; out Value: TValue): Boolean')));
  Assert.AreEqual('class|helpers|delphi', string.Join('|', PalabrasDeConsulta('class helpers (Delphi)')),
    'un parentesis que no va pegado a un nombre no es una firma');
  Assert.AreEqual('<>|operator', string.Join('|', PalabrasDeConsulta('<> operator')),
    'un < suelto no abre argumentos');
end;

procedure TDocsPurasTests.LasEntidadesYElMetaLejano;
var
  P: TPaginaDoc;
  Cabeza: string;
begin
  P := PaginaComoTexto('<body><p>a &raquo; b &laquo; c &#x1F600; d &#xD800; e</p></body>', '');
  Assert.Contains(P.Texto, 'a ' + #$BB + ' b ' + #$AB + ' c', 'las dos con nombre medidas');
  Assert.Contains(P.Texto, #$D83D#$DE00, 'mas alla de $FFFF, su par');
  Assert.Contains(P.Texto, '&#xD800;', 'un sustituto suelto no es un caracter: se queda escrito');
  // el meta de una cabecera larga: pasado el primer KB
  Cabeza := '<html><head>' + StringOfChar(' ', 2000) + '<meta charset=utf-8></head><body>';
  Assert.IsTrue(TextoDeBytes(TEncoding.UTF8.GetBytes(Cabeza + 'caf' + #$E9)).EndsWith('caf' + #$E9),
    'UTF-8 dicho pasado el primer KB');
end;

procedure TDocsPurasTests.UnaSeccionPorSuTituloComoSeLee;
var
  P: TPaginaDoc;
begin
  // el agente ve "## For Statements": con espacios y en minusculas tambien
  P := PaginaComoTexto(PAGINA, 'for statements');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.AreEqual('For_Statements', P.Ancla, 'contesta con el ancla de la pagina');
  Assert.StartsWith('## For Statements', P.Texto);
  Assert.DoesNotContain(P.Texto, 'Decl text.');
  // un ancla que no es su titulo con '_' (826 en topics.chm, medido)
  P := PaginaComoTexto(API, 'Code Insight (LSP)');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.AreEqual('Code_Insight_.28LSP.29', P.Ancla);
  Assert.Contains(P.Texto, 'LSP text.');
  Assert.DoesNotContain(P.Texto, 'See text.', 'hasta el siguiente de su nivel');
  // por su ancla sin mirar mayusculas: contesta con la de la pagina, no con
  // la tecleada (el indice escribe ..._For_statements; revision)
  P := PaginaComoTexto(PAGINA, 'for_statements');
  Assert.AreEqual('For_Statements', P.Ancla);
  // copiado tal cual sale en el texto, con sus # y un espacio duro
  P := PaginaComoTexto(PAGINA, '## For'#$A0'Statements');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.AreEqual('For_Statements', P.Ancla);
  // un ancla que no es de un titulo, entre la caja de contenidos y el primer
  // titulo: el h2 de la caja no es su seccion (pintaba la caja como texto)
  P := PaginaComoTexto('<div id="mw-content-text"><div id="toc"><div ' +
    'id="toctitle"><h2>Contents</h2></div><ul><li>x</li></ul></div><p><span ' +
    'id="Suelta">s</span></p><h2><span class="mw-headline" id="A">A</span>' +
    '</h2><p>a</p></div>', 'Suelta');
  Assert.IsFalse(P.AnclaEncontrada);
end;

procedure TDocsPurasTests.LaQueEnvuelveLaPaginaAcabaEnSuPrimerSubtitulo;
var
  P: TPaginaDoc;
begin
  // Description es el unico titulo de su nivel: cortar por nivel era hasta
  // el final (10.806 paginas de system.chm, medido)
  P := PaginaComoTexto(API, 'Description');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.Contains(P.Texto, 'Desc text.');
  Assert.DoesNotContain(P.Texto, 'LSP text.', 'acaba en su primer subtitulo');
  Assert.DoesNotContain(P.Texto, 'See text.');
  Assert.AreEqual(2, Integer(Length(P.Subsecciones)), 'los que siguen, por su ancla');
  Assert.AreEqual('Code_Insight_.28LSP.29', P.Subsecciones[0]);
  Assert.AreEqual('See_Also', P.Subsecciones[1]);
  // la de nivel 4 de arriba acaba en Description, como antes
  P := PaginaComoTexto(API, 'Properties');
  Assert.Contains(P.Texto, 'Props.');
  Assert.DoesNotContain(P.Texto, 'Desc text.');
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
  // con otro titulo de su nivel no envuelve nada: la ultima de una pagina de
  // temas sigue hasta el final, y la primera lleva dentro las suyas
  P := PaginaComoTexto(PAGINA, 'For_Statements');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
  P := PaginaComoTexto(PAGINA, 'Declarations');
  Assert.Contains(P.Texto, 'Hint text.');
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
  // un subtitulo sin ancla se queda dentro (no se puede pedir aparte): corta
  // en el primero con ancla; sin ninguno, la seccion entera
  P := PaginaComoTexto('<div id="mw-content-text"><h2><span class="mw-headline" ' +
    'id="A">A</span></h2><p>a1</p><h3>Sin ancla</h3><p>p1</p><h3><span ' +
    'class="mw-headline" id="B">B</span></h3><p>b1</p></div>', 'A');
  Assert.IsTrue(P.AnclaEncontrada, 'un titulo que abre el contenido tambien es una seccion');
  Assert.Contains(P.Texto, 'p1', 'el subtitulo sin ancla, dentro');
  Assert.DoesNotContain(P.Texto, 'b1');
  Assert.AreEqual(1, Integer(Length(P.Subsecciones)));
  Assert.AreEqual('B', P.Subsecciones[0]);
  P := PaginaComoTexto('<div id="mw-content-text"><h2><span class="mw-headline" ' +
    'id="A">A</span></h2><p>a1</p><h3>Sin ancla</h3><p>p1</p></div>', 'A');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.Contains(P.Texto, 'p1', 'sin subtitulos con ancla, la seccion entera');
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
  // la ultima de su nivel con otra delante no envuelve nada: lleva dentro
  // las suyas, con ancla o sin ella la de delante (revision)
  P := PaginaComoTexto('<div id="mw-content-text"><h2><span class="mw-headline" ' +
    'id="A">A</span></h2><p>a</p><h2><span class="mw-headline" id="B">B</span>' +
    '</h2><p>b</p><h3><span class="mw-headline" id="B1">B1</span></h3><p>b1</p>' +
    '</div>', 'B');
  Assert.IsTrue(P.AnclaEncontrada);
  Assert.Contains(P.Texto, 'b1', 'la ultima de su nivel lleva dentro las suyas');
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
  P := PaginaComoTexto('<div id="mw-content-text"><h2>Sin ancla</h2><p>x</p>' +
    '<h2><span class="mw-headline" id="Y">Y</span></h2><p>y</p><h3><span ' +
    'class="mw-headline" id="Y1">Y1</span></h3><p>y1</p></div>', 'Y');
  Assert.Contains(P.Texto, 'y1', 'uno sin ancla delante tambien cuenta');
  Assert.AreEqual(0, Integer(Length(P.Subsecciones)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAyudaInstaladaTests);
  TDUnitX.RegisterTestFixture(TDocsPurasTests);

end.
