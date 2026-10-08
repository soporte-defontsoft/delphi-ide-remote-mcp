unit LspTests.Encodings;

{ El detector UNICO de codificacion de Lsp.Patch, probado sobre bytes en
  memoria: lo que delphi_read, delphi_edit, delphi_textedit, delphi_search y
  la auditoria de escritura deciden de un fichero. Nacio el 24-sep-2026, el
  dia que se descubrio que habia DOS detectores y dos puertas de NUL. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEncodingTests = class
  private
    procedure EsClase(AEsperada: Integer; const ABytes: TArray<Byte>);
  public
    [Test] procedure Utf8ConBom;
    [Test] procedure Utf16LEPorBom;
    [Test] procedure Utf16BEPorBom;
    [Test] procedure Utf8EstrictoSinBom;
    [Test] procedure Cp1252CuandoElByteAltoNoEsSecuencia;
    [Test] procedure AsciiPuroLoDecideElIde;
    [Test] procedure IdaYVueltaPorCadaClase;
    [Test] procedure EncKindOfEsLaInversaDeEncName;
    [Test] procedure PreambleLenPorClase;
    [Test] procedure Cp1252RechazaLoQueNoCabe;
    [Test] procedure MeasureCuentaCrlfYAcentosEnUtf16;
    [Test] procedure LooksBinaryNulEsBinario;
    [Test] procedure LooksBinaryUtf16NoEsBinario;
    [Test] procedure LooksBinaryTextoYVacioNoSonBinario;
  end;

  { Los pares que COMPONEN y LEEN un formato, y la inversa de cada uno: la
    regla del nombrador unico, probada donde vive (septima revision: habia
    baterias, no tests de la funcion). }
  [TestFixture]
  TNombradorTests = class
  public
    [Test] procedure SelloYSuInversaTambienEncadenados;
    [Test] procedure MarcaDeDuenoYSuInversa;
    [Test] procedure LineasComoDelphiRead;
    [Test] procedure SaltoDominantePorClase;
    [Test] procedure ParametroQueNoVaConSuDefecto;
    [Test] procedure TroceadorConSaltoYSuInversa;
    [Test] procedure ConSaltoNormalizaLosTres;
    [Test] procedure MotorPascalPorExtension;
    [Test] procedure ZonaDelCambioMueveLoDeDebajo;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Guard, // ParametroQueNoVa
  Lsp.Patch,
  Lsp.Codificacion,
  Lsp.Casa;

function B(const A: array of Byte): TArray<Byte>;
begin
  SetLength(Result, Length(A));
  if Length(A) > 0 then
    Move(A[0], Result[0], Length(A));
end;

procedure TEncodingTests.EsClase(AEsperada: Integer; const ABytes: TArray<Byte>);
begin
  Assert.AreEqual(EncName(TEncKind(AEsperada)), EncName(DetectEnc(ABytes)));
end;

procedure TEncodingTests.Utf8ConBom;
begin
  EsClase(Ord(ekUtf8Bom), B([$EF, $BB, $BF, Ord('a')]));
  Assert.AreEqual('a', DecodeBytes(B([$EF, $BB, $BF, Ord('a')]), ekUtf8Bom));
end;

procedure TEncodingTests.Utf16LEPorBom;
begin
  EsClase(Ord(ekUtf16LE), B([$FF, $FE, Ord('a'), 0]));
  Assert.AreEqual('a', DecodeBytes(B([$FF, $FE, Ord('a'), 0]), ekUtf16LE));
end;

procedure TEncodingTests.Utf16BEPorBom;
begin
  EsClase(Ord(ekUtf16BE), B([$FE, $FF, 0, Ord('a')]));
  Assert.AreEqual('a', DecodeBytes(B([$FE, $FF, 0, Ord('a')]), ekUtf16BE));
end;

procedure TEncodingTests.Utf8EstrictoSinBom;
begin
  // 'o' con acento en UTF-8 es C3 B3: cada byte alto forma secuencia valida
  EsClase(Ord(ekUtf8), B([Ord('h'), $C3, $B3, Ord('a')]));
  Assert.AreEqual('h' + Chr(243) + 'a', DecodeBytes(B([Ord('h'), $C3, $B3, Ord('a')]), ekUtf8));
end;

procedure TEncodingTests.Cp1252CuandoElByteAltoNoEsSecuencia;
begin
  // F3 suelto: la 'o' con acento de toda la vida en un .pas legacy
  EsClase(Ord(ekCp1252), B([Ord('h'), $F3, Ord('a')]));
  Assert.AreEqual('h' + Chr(243) + 'a', DecodeBytes(B([Ord('h'), $F3, Ord('a')]), ekCp1252));
end;

procedure TEncodingTests.AsciiPuroLoDecideElIde;
var
  K: TEncKind;
begin
  // Sin byte alto no hay nada que detectar: manda la configuracion del IDE,
  // y sea cual sea, el texto se lee igual.
  K := DetectEnc(B([Ord('a'), Ord('b'), Ord('c')]));
  Assert.IsTrue(K in [ekUtf8, ekCp1252], 'ascii puro es utf8 o cp1252, nunca otra cosa: ' + EncName(K));
  Assert.AreEqual('abc', DecodeBytes(B([Ord('a'), Ord('b'), Ord('c')]), K));
end;

procedure TEncodingTests.IdaYVueltaPorCadaClase;
const
  TEXTO = 'hola ' + Chr(243) + ' mundo'#13#10'segunda'#13#10;
var
  K: TEncKind;
  Bytes: TArray<Byte>;
begin
  for K := Low(TEncKind) to High(TEncKind) do
  begin
    Bytes := EncodeText(TEXTO, K);
    Assert.AreEqual(EncName(K), EncName(DetectEnc(Bytes)), 'lo que escribe ' + EncName(K) + ' se detecta como tal');
    Assert.AreEqual(TEXTO, DecodeBytes(Bytes, K), 'ida y vuelta en ' + EncName(K));
  end;
end;

procedure TEncodingTests.EncKindOfEsLaInversaDeEncName;
var
  K: TEncKind;
begin
  for K := Low(TEncKind) to High(TEncKind) do
    Assert.AreEqual(EncName(K), EncName(EncKindOf(EncName(K))), 'EncKindOf(EncName(K)) = K');
  Assert.AreEqual('cp1252', EncName(EncKindOf('rarito')), 'un nombre desconocido es cp1252');
end;

procedure TEncodingTests.PreambleLenPorClase;
begin
  Assert.AreEqual(3, PreambleLen(ekUtf8Bom));
  Assert.AreEqual(0, PreambleLen(ekUtf8));
  Assert.AreEqual(0, PreambleLen(ekCp1252));
  Assert.AreEqual(2, PreambleLen(ekUtf16LE));
  Assert.AreEqual(2, PreambleLen(ekUtf16BE));
  Assert.AreEqual(3, Integer(Length(EncodeText('', ekUtf8Bom))), 'el BOM UTF-8 son 3 bytes');
  Assert.AreEqual(2, Integer(Length(EncodeText('', ekUtf16LE))), 'el BOM UTF-16 son 2 bytes');
end;

procedure TEncodingTests.Cp1252RechazaLoQueNoCabe;
begin
  Assert.WillRaiseDescendant(
    procedure
    begin
      EncodeText('ok ' + Chr($2714), ekCp1252);
    end, Exception, 'un caracter fuera de CP1252 no se cuela como mojibake (lanza su ECaracterNoCabe, que declara DENIED)');
end;

procedure TEncodingTests.MeasureCuentaCrlfYAcentosEnUtf16;
var
  Bytes: TArray<Byte>;
  M: TMetrics;
begin
  Bytes := EncodeText('a'#13#10 + Chr(243) + #13#10, ekUtf16LE);
  M := Measure(Bytes);
  Assert.AreEqual(Integer(Length(Bytes)), M.Bytes, 'bytes reales del fichero');
  Assert.AreEqual(2, M.CRLF, 'CRLF contados sobre el texto, no sobre 0D 00 0A 00');
  Assert.AreEqual(0, M.Loose);
  Assert.AreEqual(2, M.High, 'un acento = 2 bytes altos, como en un fichero utf8');
  Assert.AreEqual(0, M.Corruption);
end;

procedure TEncodingTests.LooksBinaryNulEsBinario;
begin
  Assert.IsTrue(LooksBinaryBytes(B([Ord('M'), Ord('Z'), $90, 0, 3, 0])), 'un exe');
end;

procedure TEncodingTests.LooksBinaryUtf16NoEsBinario;
begin
  Assert.IsFalse(LooksBinaryBytes(EncodeText('object Form1: TForm1'#13#10'end'#13#10, ekUtf16LE)), 'UTF-16 LE');
  Assert.IsFalse(LooksBinaryBytes(EncodeText('uno', ekUtf16BE)), 'UTF-16 BE');
end;

procedure TEncodingTests.LooksBinaryTextoYVacioNoSonBinario;
begin
  Assert.IsFalse(LooksBinaryBytes(B([Ord('a'), Ord('b'), 13, 10])));
  Assert.IsFalse(LooksBinaryBytes(nil), 'vacio');
end;

{ TNombradorTests }

procedure TNombradorTests.SelloYSuInversaTambienEncadenados;
begin
  Assert.AreEqual('U.pas', TrashOriginalName(TrashStampedName('U.pas')));
  // restaurar algo ya restaurado encadena sellos: la inversa los quita todos
  Assert.AreEqual('U.pas', TrashOriginalName(TrashStampedName(TrashStampedName('U.pas'))));
  Assert.AreEqual('', TrashOriginalName('U.pas'), 'un nombre sin sello no es una copia');
end;

procedure TNombradorTests.MarcaDeDuenoYSuInversa;
begin
  Assert.AreEqual('x-123456789', CopiaDeLaMarca(MarcaDeDueno('x-123456789')));
  Assert.IsTrue(EsMarcaDeDueno(MarcaDeDueno('x-123456789')));
  Assert.IsFalse(EsMarcaDeDueno('x-123456789'), 'la copia no es su marca');
end;

procedure TNombradorTests.LineasComoDelphiRead;
begin
  Assert.AreEqual<Integer>(2, Length(LineasDelTexto('a'#10'b'#10)), 'sin la fantasma del salto final');
  Assert.AreEqual<Integer>(2, Length(LineasDelTexto('a'#13'b')), 'un CR suelto es salto');
  Assert.AreEqual<Integer>(2, Length(LineasDelTexto('a'#13#10#13#10)), 'una linea vacia REAL cuenta');
  Assert.AreEqual<Integer>(0, Length(LineasDelTexto('')), 'vacio: ninguna');
end;

procedure TNombradorTests.SaltoDominantePorClase;
begin
  Assert.AreEqual(string(#13#10), SaltoDominante('a'#13#10'b'#13#10));
  Assert.AreEqual(string(#10), SaltoDominante('a'#10'b'#10'c'#13#10), 'el que mas aparece');
  Assert.AreEqual(string(#13), SaltoDominante('a'#13'b'#13), 'un CR suelto tambien');
  Assert.AreEqual(string(#13#10), SaltoDominante('sin saltos'), 'el de Windows si no hay');
end;

{ El troceador que conserva el salto de cada linea: con su inversa, byte a byte. }
procedure TNombradorTests.TroceadorConSaltoYSuInversa;
var
  L, S: TArray<string>;
  T: string;
begin
  T := 'a'#13'b'#13#10'c'#10'd';
  L := SplitToLinesConSalto(T, S);
  Assert.AreEqual<Integer>(Length(SplitToLines(T)), Length(L), 'los mismos cortes que SplitToLines');
  Assert.AreEqual(string(#13), S[0], 'el CR suelto es SU salto');
  Assert.AreEqual(string(#13#10), S[1]);
  Assert.AreEqual(string(#10), S[2]);
  Assert.AreEqual('', S[3], 'la ultima sin salto');
  Assert.AreEqual(T, UneConSusSaltos(L, S), 'la inversa, byte a byte');
  Assert.AreEqual('x'#13#10, UneConSusSaltos(SplitToLinesConSalto('x'#13#10, S), S),
    'con el salto final (la fantasma)');
end;

procedure TNombradorTests.ConSaltoNormalizaLosTres;
begin
  Assert.AreEqual('a'#13#10'b'#13#10'c'#13#10, ConSalto('a'#13'b'#10'c'#13#10, #13#10));
  Assert.AreEqual('a'#10'b'#10, ConSalto('a'#13#10'b'#13, #10));
  Assert.AreEqual('sin saltos', ConSalto('sin saltos', #13#10));
end;

procedure TNombradorTests.ZonaDelCambioMueveLoDeDebajo;
var
  Desde, Delta: Integer;
begin
  // una insercion cuya primera linea nueva es la vieja: la de debajo se mueve
  ZonaDelCambio(['a', 'b', 'c'], ['a', 'X', 'b', 'c'], Desde, Delta);
  Assert.AreEqual<Integer>(3, LineaTrasCambio(2, Desde, Delta), 'b baja una');
  Assert.AreEqual<Integer>(1, LineaTrasCambio(1, Desde, Delta), 'lo de encima no se mueve');
  // un borrado: lo de debajo sube, lo de encima se queda
  ZonaDelCambio(['a', 'b', 'c'], ['a', 'c'], Desde, Delta);
  Assert.AreEqual<Integer>(2, LineaTrasCambio(3, Desde, Delta));
  Assert.AreEqual<Integer>(1, LineaTrasCambio(1, Desde, Delta));
  // una linea por tres, y 0 (sin linea) se queda en 0
  ZonaDelCambio(['a', 'b', 'c'], ['a', 'X', 'Y', 'Z', 'c'], Desde, Delta);
  Assert.AreEqual<Integer>(5, LineaTrasCambio(3, Desde, Delta));
  Assert.AreEqual<Integer>(0, LineaTrasCambio(0, Desde, Delta));
end;

procedure TNombradorTests.MotorPascalPorExtension;
begin
  Assert.IsTrue(EsDelMotorPascal('X.pas') and EsDelMotorPascal('X.DPR') and
    EsDelMotorPascal('X.inc') and EsDelMotorPascal('X.dfm') and EsDelMotorPascal('X.fmx'));
  Assert.IsFalse(EsDelMotorPascal('X.txt') or EsDelMotorPascal('X.dproj'),
    'el texto y el proyecto no son del motor de Pascal');
end;

procedure TNombradorTests.ParametroQueNoVaConSuDefecto;
var
  Suyos: string;
begin
  Assert.AreEqual('path', ParametroQueNoVa('set-output', ['set-output', 'output'],
    ['output', 'bin', '', 'path', '.\bin', ''], Suyos));
  Assert.AreEqual('output', Suyos);
  // el valor por defecto que publica el esquema no cuenta como enviado
  Assert.AreEqual('', ParametroQueNoVa('set-output', ['set-output', 'output'],
    ['section', 'summary', 'summary'], Suyos));
  // un modo que no esta en la tabla no se mira: lo dice su propia negativa
  Assert.AreEqual('', ParametroQueNoVa('otro', ['set-output', 'output'],
    ['path', 'x', ''], Suyos));
end;

initialization
  TDUnitX.RegisterTestFixture(TEncodingTests);
  TDUnitX.RegisterTestFixture(TNombradorTests);

end.
