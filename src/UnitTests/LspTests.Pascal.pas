unit LspTests.Pascal;

// El lector de directivas Pascal (DirectivasPascal) y el de las de fichero
// que usan la mudanza y la puerta del build: una directiva COMENTADA (con
// llaves, parentesis-asterisco o //) o dentro de una cadena no es una
// directiva; la forma parentesis-asterisco-dolar si (revision del
// 27-sep-2026, David: "incluso //").

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDirectivasTests = class
  public
    [Test] procedure SoloLasDeVerdad;
    [Test] procedure LasDeFicheroNoVenLasComentadas;
    [Test] procedure LlavesAnidadasSeVen;
    [Test] procedure LaDirectivaSinCerrarEntera;
  end;

  // EL lexico (Lsp.Pascal): que es codigo, cadena, comentario y directiva.
  // Censo del 2-oct-2026: una docena de lectores con su trozo de la regla, y
  // nueve fallos medidos en cuatro tools.
  [TestFixture]
  TLexicoTests = class
  public
    [Test] procedure DosBarrasComentanHastaElFinalHayaLoQueHaya;
    [Test] procedure DentroDeUnaLlaveNoHayComentarioDeLinea;
    [Test] procedure UnaCadenaNoPasaDeSuLinea;
    [Test] procedure ElComentarioDeLineaDetrasDeUnaCadenaConBarras;
    [Test] procedure LaCadenaDeVariasLineas;
    [Test] procedure ElEstadoViajaEntreLineas;
    [Test] procedure LaVistaConservaLargoYSaltos;
    [Test] procedure CadaClaseEnSuSitio;
    [Test] procedure LaLineaAcabaDondeCierraSuComentario;
  end;

  // EL identificador (Lsp.Pascal): una letra de cualquier alfabeto. El TRegEx
  // del RTL no la ve con \w ni con \b (medido el 4-oct-2026), y una sesentena
  // de regex del servidor la escribian asi.
  [TestFixture]
  TIdentificadorTests = class
  public
    [Test] procedure UnaLetraDeCualquierAlfabeto;
    [Test] procedure LoQueAceptaDcc;
    [Test] procedure LaPalabraEnteraConAcentos;
    [Test] procedure ElCaracterYElPatronDicenLoMismo;
    [Test] procedure ElMismoIdentificadorTambienConAcentos;
    [Test] procedure ElUltimoTrozoYLasReservadas;
    [Test] procedure LasPalabrasDeUnaRutina;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Lsp.Pascal,
  Lsp.ProjectUnits,
  System.RegularExpressions;

procedure TDirectivasTests.SoloLasDeVerdad;
var
  D: TArray<TDirectivaPascal>;
begin
  D := DirectivasPascal(
    '// {$I comentada.inc}'#13#10 +
    '{ en un comentario: {$I tampoco.inc} }'#13#10 +
    'S := ''{$I en una cadena}'';'#13#10 +
    '{$IFDEF MSWINDOWS}'#13#10 +
    '(*$I parentesis.inc*)'#13#10 +
    '{$ENDIF}');
  Assert.IsTrue(Length(D) = 3, 'directivas: ' + IntToStr(Length(D)));
  Assert.AreEqual('IFDEF', D[0].Nombre);
  Assert.AreEqual('MSWINDOWS', D[0].Argumento.Trim);
  Assert.AreEqual('I', D[1].Nombre);
  Assert.AreEqual('parentesis.inc', D[1].Argumento.Trim);
  Assert.AreEqual('ENDIF', D[2].Nombre);
end;

procedure TDirectivasTests.LasDeFicheroNoVenLasComentadas;
const
  T = '// {$I ..\viejo.inc}'#13#10 + '(*$I ..\b.inc*)'#13#10 + '{$R ..\a.res ..\a.rc}';
var
  F: TArray<TDirectivaFichero>;
begin
  F := DirectivasDeFichero(T);
  Assert.IsTrue(Length(F) = 3, 'rutas: ' + IntToStr(Length(F)));
  Assert.AreEqual('..\b.inc', F[0].Ruta);
  Assert.AreEqual('..\b.inc', Copy(T, F[0].Inicio, F[0].Largo), 'la posicion');
  Assert.AreEqual('..\a.res', F[1].Ruta);
  Assert.AreEqual('..\a.rc', F[2].Ruta);
  Assert.AreEqual('..\a.rc', Copy(T, F[2].Inicio, F[2].Largo), 'la segunda ruta de R');
end;

procedure TDirectivasTests.LlavesAnidadasSeVen;
var
  L, Fines: TArray<Integer>;
begin
  // la trampa: un comentario de llave que cita una directiva de llave-dolar
  L := LlavesAnidadas('x := 1;'#10'{ cita {$IFDEF X} aqui }'#10'y := 2;', Fines);
  Assert.IsTrue((Length(L) = 1) and (L[0] = 2), 'la linea 2');
  Assert.IsTrue((Length(Fines) = 1) and (Fines[0] = 2), 'lo cierra la primera llave, en la 2');
  // abierto en una linea y con la llave en OTRA: empieza en la 1 y lo cierra la
  // llave del {$I} de la 2 (lo que AvisosDeLlaves cruza con lo escrito)
  L := LlavesAnidadas('{ uno'#13#10'  la ruta de un {$I x.inc} dos'#13#10'  tres }', Fines);
  Assert.IsTrue((Length(L) = 1) and (L[0] = 1) and (Fines[0] = 2), 'de la 1 a la 2');
  // y lo que no lo es: //, parentesis-asterisco, una cadena, un comentario normal
  L := LlavesAnidadas('// {$IFDEF X}'#10'(* { dentro *)'#10'S := ''{ {'';'#10'{ normal }', Fines);
  Assert.IsTrue(Length(L) = 0, 'nada: ' + IntToStr(Length(L)));
  // con los saltos en CR sueltos, la misma linea (contaba solo los LF;
  // revision de la 1.10.0)
  L := LlavesAnidadas('x := 1;'#13'{ cita {$IFDEF X} aqui }'#13'y := 2;', Fines);
  Assert.IsTrue((Length(L) = 1) and (L[0] = 2), 'la linea 2, en CR');
end;

procedure TDirectivasTests.LaDirectivaSinCerrarEntera;
var
  D: TArray<TDirectivaPascal>;
begin
  // sin cerrar, hasta el final: la de parentesis-asterisco perdia su ultimo
  // caracter (revision de la 1.10.0)
  D := DirectivasPascal('(*$IFDEF DEBUG');
  Assert.AreEqual('DEBUG', D[0].Argumento.Trim, 'parentesis-asterisco');
  D := DirectivasPascal('{$IFDEF DEBUG');
  Assert.AreEqual('DEBUG', D[0].Argumento.Trim, 'llave');
  D := DirectivasPascal('(*$IFDEF DEBUG*)');
  Assert.AreEqual('DEBUG', D[0].Argumento.Trim, 'cerrada');
end;

function Lineas(const AComentarios: TArray<Integer>): string;
begin
  Result := '';
  for var C in AComentarios do
    Result := Result + IntToStr(C) + ' ';
  Result := Result.Trim;
end;

procedure TLexicoTests.DosBarrasComentanHastaElFinalHayaLoQueHaya;
begin
  // ni la llave, ni la comilla, ni la directiva, ni la coma de detras cuentan
  Assert.AreEqual('4 0', Lineas(ComentariosDeLinea(['A; // {$IFDEF X} it''s } ,', 'B;'])));
  Assert.AreEqual('A;' + StringOfChar(' ', 23) + #10'B;',
    VistaPascal('A; // {$IFDEF X} it''s } ,'#10'B;', [cpCodigo]), 'la segunda linea es codigo');
end;

procedure TLexicoTests.DentroDeUnaLlaveNoHayComentarioDeLinea;
begin
  // el caso de adduses (SYS-006): el // de https:// esta dentro de la llave
  Assert.AreEqual('0', Lineas(ComentariosDeLinea(['UA {ver https://docwiki}'])));
  Assert.AreEqual('0', Lineas(ComentariosDeLinea(['UA (* https://x *)'])));
end;

procedure TLexicoTests.UnaCadenaNoPasaDeSuLinea;
begin
  // una cadena sin cerrar acaba en su linea, como para el compilador: la
  // siguiente es codigo, y su // es un comentario
  Assert.AreEqual('0 4', Lineas(ComentariosDeLinea(['S := ''abc', 'X; // c'])));
end;

procedure TLexicoTests.ElComentarioDeLineaDetrasDeUnaCadenaConBarras;
begin
  // el caso de INSERT (EDIT-071): el // de 'http://x' es de la cadena
  Assert.AreEqual('0', Lineas(ComentariosDeLinea(
    ['procedure Abre(const U: string = ''http://x'');'])));
  Assert.AreEqual('17', Lineas(ComentariosDeLinea(['S := ''a//b''; X; // c'])));
end;

procedure TLexicoTests.LaCadenaDeVariasLineas;
begin
  // tres comillas solas al final de una linea: lo de dentro es cadena,
  // tambien lo que empieza por //, hasta la linea que empieza por tres
  Assert.AreEqual('0 0 0 1', Lineas(ComentariosDeLinea(
    ['S := ''''''', '  // no es un comentario', '  '''''';', '// este si'])));
  // y tres comillas que no van solas son una cadena de una linea
  Assert.AreEqual('15', Lineas(ComentariosDeLinea(['S := ''''''a''''''; // c'])));
  // ni con un blanco detras: dcc dice E2052 (cadena sin cerrar) y la linea
  // siguiente es codigo para el (medido en la revision de la 1.10.0)
  Assert.AreEqual('0 3', Lineas(ComentariosDeLinea(['S := '''''' ', '  // si es un comentario'])));
end;

procedure TLexicoTests.ElEstadoViajaEntreLineas;
begin
  // un // dentro de una llave que viene de antes no es un comentario de
  // linea, y la llave cierra en la primera }
  Assert.AreEqual('0 0 0 4', Lineas(ComentariosDeLinea(
    ['{ abre', '// dentro de la llave', '}', 'X; // si'])));
end;

procedure TLexicoTests.LaVistaConservaLargoYSaltos;
const
  T = 'unit U;'#13#10'{ lo de antes:'#13#10'end.'#13#10'}'#13#10'S := ''end.'';'#13#10'end.';
var
  V: string;
begin
  V := VistaPascal(T, [cpCodigo]);
  Assert.AreEqual(Length(T), Length(V), 'el largo');
  for var I := 1 to Length(T) do
    if CharInSet(T[I], [#10, #13]) then
      Assert.AreEqual(string(T[I]), string(V[I]), 'el salto en ' + IntToStr(I));
  // el caso de INSERT (EDIT-049): el end. comentado y el de la cadena no
  // estan en la vista del codigo; el de verdad si
  Assert.AreEqual(1, Integer(V.CountChar('.')), 'un solo end. de codigo: ' + V);
  Assert.IsTrue(V.EndsWith('end.'), 'el ultimo');
end;

procedure TLexicoTests.CadaClaseEnSuSitio;
const
  T = 'A {x} (*y*) {$IFDEF Z} (*$I w*) ''s'' // c';
var
  C: TArray<TClasePascal>;
begin
  C := ClasesPascal(T);
  Assert.IsTrue(C[1] = cpCodigo, 'A');
  Assert.IsTrue(C[Pos('{x}', T)] = cpComentario, 'la llave');
  Assert.IsTrue(C[Pos('(*y', T)] = cpComentario, 'parentesis-asterisco');
  Assert.IsTrue(C[Pos('{$IFDEF', T)] = cpDirectiva, 'llave-dolar');
  Assert.IsTrue(C[Pos('(*$I', T)] = cpDirectiva, 'parentesis-asterisco-dolar');
  Assert.IsTrue(C[Pos('''s''', T)] = cpCadena, 'la cadena');
  Assert.IsTrue(C[Pos('// c', T)] = cpLinea, 'la de //');
  Assert.IsTrue(C[Length(T)] = cpLinea, 'hasta el final');
end;

procedure TLexicoTests.LaLineaAcabaDondeCierraSuComentario;
begin
  // lo que se escribe detras de una linea va detras de donde ACABA: un INSERT
  // en un .dpr y un uses creado caian dentro del comentario abierto en ella
  // (revision de la 1.10.0, medido)
  Assert.AreEqual(1, LineaQueCierra(['uses A; { las units', '  de arriba }', 'begin'], 0), 'la llave');
  Assert.AreEqual(0, LineaQueCierra(['A;', 'B'], 0), 'sin comentario');
  Assert.AreEqual(0, LineaQueCierra(['A; // {', 'B'], 0), 'un // acaba en su linea');
  Assert.AreEqual(2, LineaQueCierra(['S := ''''''', 'x', '  '''''';', 'y'], 0), 'una cadena de varias lineas');
  Assert.AreEqual(17, FinDeLinea('interface { x'#13#10'}'#13#10'impl', 1), 'en el texto: el CR de detras del cierre');
  Assert.AreEqual(5, FinDeLinea('uses', 1), 'sin salto: el final');
end;

procedure TIdentificadorTests.UnaLetraDeCualquierAlfabeto;
begin
  Assert.IsTrue(EsIdentificador('AñadirLineaTexto'), 'AñadirLineaTexto');
  Assert.IsTrue(EsIdentificador('lblDirección'), 'lblDirección');
  Assert.IsTrue(EsIdentificador('Último'), 'Último');
  Assert.IsTrue(EsIdentificador('_x1'), '_x1');
  Assert.IsFalse(EsIdentificador('1x'), '1x');
  Assert.IsFalse(EsIdentificador(''), 'vacio');
  Assert.IsFalse(EsIdentificador('a b'), 'a b');
  // el $ de PCRE casa delante de un salto final: con su salto no lo es
  Assert.IsFalse(EsIdentificador('Foo'#10), 'con salto');
  Assert.IsFalse(EsIdentificador('Vcl.Forms'), 'puntos sin APuntos');
  Assert.IsTrue(EsIdentificador('Vcl.Forms', True), 'Vcl.Forms');
  Assert.IsTrue(EsIdentificador('Galatea.Año', True), 'Galatea.Año');
  Assert.IsFalse(EsIdentificador('Vcl..Forms', True), 'dos puntos');
  Assert.IsFalse(EsIdentificador('Vcl.', True), 'punto final');
end;

{ Lo que dcc compila como identificador y lo que no (medido el 4-oct-2026,
  una funcion con cada clase de caracter): cualquier caracter no ASCII del
  plano basico, tambien al principio; fuera del plano basico, E2038 }
procedure TIdentificadorTests.LoQueAceptaDcc;
begin
  Assert.IsTrue(EsIdentificador('Col·lecció'), 'el punto volado catalan');
  Assert.IsTrue(EsIdentificador('·Punto'), 'tambien al principio');
  Assert.IsTrue(EsIdentificador('Cafe' + #$0301), 'una marca combinante');
  Assert.IsTrue(EsIdentificador('Siglo' + #$216B), 'un numeral romano');
  Assert.IsTrue(EsIdentificador('Precio€') and EsIdentificador('€Precio'), 'el euro');
  Assert.IsTrue(EsIdentificador('Uno' + #$00A0 + 'Dos'), 'un espacio duro');
  Assert.IsFalse(EsIdentificador('Equis' + #$D835#$DC65), 'una letra fuera del plano basico');
  Assert.IsFalse(EsIdentificador('Uno Dos') or EsIdentificador('Uno-Dos'), 'el espacio y el guion ASCII no');
  Assert.AreEqual(1, TRegEx.Matches('x := Col·lecció + 1;', PatronIdentEntero('Col·lecció')).Count,
    'el patron lo lee entero');
  Assert.AreEqual(0, TRegEx.Matches('x := Col·lecció;', PatronIdentEntero('Col')).Count,
    'y Col no es una palabra entera dentro');
end;

procedure TIdentificadorTests.LaPalabraEnteraConAcentos;
const
  T = 'x := Añoñ + Año;';
begin
  // Pascal no distingue mayusculas, tampoco en la Ñ; ni AñoStr ni fAño son Año
  Assert.AreEqual(2, TRegEx.Matches('Año := AñoStr + fAño + AÑO;',
    '(?i)' + PatronIdentEntero('año')).Count, 'Año');
  // con un acento al principio, '\b' no casaba nunca
  Assert.AreEqual(1, TRegEx.Matches(' Último ', PatronIdentEntero('Último')).Count, 'al principio');
  Assert.AreEqual(0, TRegEx.Matches('PenÚltimo', PatronIdentEntero('Último')).Count, 'dentro de otro');
  // y con uno al final, '\b' casaba dentro de otro nombre (Caféx) y no en
  // Café: tambien contaba uno, el equivocado. La posicion lo dice (revision)
  Assert.AreEqual(1, TRegEx.Matches('Caféx := Café;', PatronIdentEntero('Café')).Count, 'al final');
  Assert.AreEqual(Pos('Café;', 'Caféx := Café;'),
    TRegEx.Match('Caféx := Café;', PatronIdentEntero('Café')).Index, 'al final, en su sitio');
  // la posicion es la del texto (la del rename): detras de una ñ, la suya
  Assert.AreEqual(Pos('Año;', T), TRegEx.Match(T, PatronIdentEntero('Año')).Index, 'la posicion');
end;

procedure TIdentificadorTests.ElCaracterYElPatronDicenLoMismo;
const
  MUESTRA = 'aZ_09ñÑáÜçßªº²µ·€-. ' + #$0301 + 'ЖλΣ中' + #$0663 + #$2163 + #9;
begin
  // los que recorren un texto y los que lo buscan con un patron: una regla
  for var C in MUESTRA do
  begin
    Assert.IsTrue(TRegEx.IsMatch(C, '\A' + PATRON_CAR_IDENT + '\z') = EsCaracterDeIdent(C),
      Format('de dentro: U+%.4x', [Ord(C)]));
    Assert.IsTrue(EsIdentificador(C) = EsLetraDeIdent(C), Format('el primero: U+%.4x', [Ord(C)]));
  end;
end;

procedure TIdentificadorTests.ElMismoIdentificadorTambienConAcentos;
begin
  // dcc pliega tambien la caja de una letra acentuada (medido el 4-oct-2026:
  // 'uses UáRBOL' compila contra 'unit UÁrbol'); SameText solo A-Z
  Assert.IsTrue(MismoIdentificador('UÁrbol', 'uáRBOL'), 'UÁrbol');
  Assert.IsTrue(MismoIdentificador('Tamaño', 'TAMAÑO'), 'Tamaño');
  Assert.IsFalse(MismoIdentificador('Tamaño', 'Tamano'), 'sin la enye es otro');
  Assert.IsFalse(MismoIdentificador('Año', 'Años'), 'otro largo');
  Assert.AreEqual(ClaveDeIdentificador('año'), ClaveDeIdentificador('AÑO'), 'la clave');
end;

procedure TIdentificadorTests.ElUltimoTrozoYLasReservadas;
begin
  Assert.AreEqual('TForm', UltimoTrozo('Vcl.Forms.TForm'));
  Assert.AreEqual('TForm', UltimoTrozo('TForm'));
  Assert.IsTrue(EsPalabraReservada('Begin'), 'Begin');
  Assert.IsTrue(EsPalabraReservada('string'), 'string');
  Assert.IsFalse(EsPalabraReservada('Beginning'), 'Beginning');
end;

procedure TIdentificadorTests.LasPalabrasDeUnaRutina;
begin
  for var S in ['procedure X;', 'function X: Integer;', 'constructor Create;',
                'destructor Destroy;', 'operator Add(A, B: T): T;'] do
    Assert.IsTrue(TRegEx.IsMatch(S, '(?i)^' + PatronPalabraDeRutina + '\s'), S);
  Assert.IsFalse(TRegEx.IsMatch('property X;', '(?i)^' + PatronPalabraDeRutina + '\s'), 'property no');
  // una sola lista de directivas, con las nuevas (insert=metodo no conocia estas)
  Assert.IsTrue(MatchText('noreturn', DIRECTIVAS_DE_RUTINA) and MatchText('unsafe', DIRECTIVAS_DE_RUTINA));
  Assert.IsTrue(MatchText('overload', DIRECTIVAS_DE_RUTINA) and MatchText('message', DIRECTIVAS_DE_RUTINA));
end;

initialization
  TDUnitX.RegisterTestFixture(TDirectivasTests);
  TDUnitX.RegisterTestFixture(TLexicoTests);
  TDUnitX.RegisterTestFixture(TIdentificadorTests);

end.
