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

implementation

uses
  System.SysUtils,
  Lsp.Pascal,
  Lsp.ProjectUnits;

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
  L: TArray<Integer>;
begin
  // la trampa: un comentario de llave que cita una directiva de llave-dolar
  L := LlavesAnidadas('x := 1;'#10'{ cita {$IFDEF X} aqui }'#10'y := 2;');
  Assert.IsTrue((Length(L) = 1) and (L[0] = 2), 'la linea 2');
  // y lo que no lo es: //, parentesis-asterisco, una cadena, un comentario normal
  L := LlavesAnidadas('// {$IFDEF X}'#10'(* { dentro *)'#10'S := ''{ {'';'#10'{ normal }');
  Assert.IsTrue(Length(L) = 0, 'nada: ' + IntToStr(Length(L)));
  // con los saltos en CR sueltos, la misma linea (contaba solo los LF;
  // revision de la 1.10.0)
  L := LlavesAnidadas('x := 1;'#13'{ cita {$IFDEF X} aqui }'#13'y := 2;');
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

initialization
  TDUnitX.RegisterTestFixture(TDirectivasTests);
  TDUnitX.RegisterTestFixture(TLexicoTests);

end.
