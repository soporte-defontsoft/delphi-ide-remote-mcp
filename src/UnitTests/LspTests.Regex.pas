unit LspTests.Regex;

// Lo que el TRegEx del RTL hace con un grupo que no participa (Lsp.Regex):
// si va detras del ultimo que si participo, Groups ni lo cuenta, y leerlo es
// 'Index out of bounds (N)'. Asi caian delphi_designer lint y check-binding
// con un 'class of' en el .pas del form (Hermes, VM 13.2, 4-oct-2026).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGrupoTests = class
  public
    [Test] procedure ElGrupoDelFinalQueNoParticipaNiSeCuenta;
    [Test] procedure GrupoDeNoCaeYDiceVacio;
    [Test] procedure ElQueNoParticipaConOtroDetrasExisteVacio;
  end;

  { La expresion del AGENTE (delphi_search regex=true): TRegEx toma por "no
    casa" que el motor se rinda, y la busqueda daba cero en silencio. }
  [TestFixture]
  TExprDelAgenteTests = class
  public
    [Test] procedure ElRTLDiceNoCasaCuandoElMotorSeRinde;
    [Test] procedure CasaNoCasaYSeRinde;
    [Test] procedure LaQueNoCompilaDiceElMotivo;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Lsp.Regex;

procedure TGrupoTests.ElGrupoDelFinalQueNoParticipaNiSeCuenta;
var
  M: TMatch;
begin
  // la trampa medida: Groups llega solo hasta el ultimo grupo que participo
  M := TRegEx.Match('TX = class of TY;', '^(\w+)\s*=\s*class\b(?:\s*\(\s*(\w*))?');
  Assert.IsTrue(M.Success, 'casa');
  Assert.AreEqual(2, M.Groups.Count, 'el grupo 2 ni se cuenta');
end;

procedure TGrupoTests.GrupoDeNoCaeYDiceVacio;
var
  M: TMatch;
begin
  M := TRegEx.Match('TX = class of TY;', '^(\w+)\s*=\s*class\b(?:\s*\(\s*(\w*))?');
  Assert.AreEqual('', GrupoDe(M, 2), 'el que no se cuenta');
  Assert.AreEqual('TX', GrupoDe(M, 1), 'el que si');
  M := TRegEx.Match('TX = class(TForm)', '^(\w+)\s*=\s*class\b(?:\s*\(\s*(\w*))?');
  Assert.AreEqual('TForm', GrupoDe(M, 2), 'con parentesis');
  // y un match que no casa, o un indice que no es de nadie, tampoco caen
  M := TRegEx.Match('nada', '^(\w+)=(\w+)$');
  Assert.AreEqual('', GrupoDe(M, 1), 'sin coincidencia');
  Assert.AreEqual('', GrupoDe(TRegEx.Match('a', '(a)'), 7), 'un indice de nadie');
end;

procedure TGrupoTests.ElQueNoParticipaConOtroDetrasExisteVacio;
var
  M: TMatch;
begin
  M := TRegEx.Match('y', '(x)?(y)');
  Assert.AreEqual(3, M.Groups.Count, 'los dos se cuentan');
  Assert.AreEqual('', GrupoDe(M, 1), 'vacio');
  Assert.AreEqual('y', GrupoDe(M, 2), 'el 2');
  // y el RTL no deja saber que el 1 no participo (medido el 4-oct-2026): su
  // Success es el de la coincidencia y su Index, el de un grupo vacio al
  // principio. Por eso Lsp.Regex no ofrece un "participo"
  Assert.IsTrue(M.Groups[1].Success, 'Success es el de la coincidencia');
  Assert.AreEqual(1, M.Groups[1].Index, 'Index 1');
  Assert.AreEqual(0, M.Groups[1].Length, 'Length 0');
end;

const
  // treinta aes y un signo: (a*)*$ es exponencial sobre ella
  LINEA_QUE_DISPARA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!';

procedure TExprDelAgenteTests.ElRTLDiceNoCasaCuandoElMotorSeRinde;
begin
  // la trampa medida (el fuente de la RTL: 'Result := OffsetCount > 0'):
  // casa (vacia al final), pero el motor agota sus pasos antes de verlo
  Assert.IsFalse(TRegEx.IsMatch(LINEA_QUE_DISPARA, '(a*)*$'),
    'si esto casa, la RTL ya distingue un error del motor: revisar TExprDelAgente');
end;

procedure TExprDelAgenteTests.CasaNoCasaYSeRinde;
var
  E: TExprDelAgente;
  Err: string;
  P, L: Integer;
begin
  E := TExprDelAgente.Create('pinta\d+', Err);
  try
    Assert.AreEqual('', Err);
    // la posicion es la de la cadena, tambien detras de una enye
    Assert.IsTrue(E.Busca('Año := PINTA42 + Pinta7;', 1, P, L) = rbCasa, 'casa, sin distinguir mayusculas');
    Assert.AreEqual(Pos('PINTA42', 'Año := PINTA42 + Pinta7;'), P, 'su posicion');
    Assert.AreEqual(7, L, 'su largo');
    Assert.IsTrue(E.Busca('Año := PINTA42 + Pinta7;', P + L, P, L) = rbCasa, 'la siguiente, desde donde se pide');
    Assert.AreEqual(Pos('Pinta7', 'Año := PINTA42 + Pinta7;'), P);
    Assert.IsTrue(E.Busca('nada', 1, P, L) = rbNoCasa, 'no casa');
  finally
    E.Free;
  end;
  E := TExprDelAgente.Create('(a*)*$', Err);
  try
    Assert.IsTrue(E.Busca(LINEA_QUE_DISPARA, 1, P, L) = rbSeRinde, 'se rinde, y lo dice');
  finally
    E.Free;
  end;
end;

procedure TExprDelAgenteTests.LaQueNoCompilaDiceElMotivo;
var
  E: TExprDelAgente;
  Err: string;
begin
  E := TExprDelAgente.Create('(sin cerrar', Err);
  try
    Assert.IsTrue(Err.Contains('missing'), Err);
  finally
    E.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGrupoTests);
  TDUnitX.RegisterTestFixture(TExprDelAgenteTests);

end.
