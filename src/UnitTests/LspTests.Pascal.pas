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
  end;

implementation

uses
  System.SysUtils,
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
end;

initialization
  TDUnitX.RegisterTestFixture(TDirectivasTests);

end.
