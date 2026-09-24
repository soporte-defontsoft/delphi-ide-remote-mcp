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

implementation

uses
  System.SysUtils,
  Lsp.Patch;

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
  Assert.WillRaise(
    procedure
    begin
      EncodeText('ok ' + Chr($2714), ekCp1252);
    end, Exception, 'un caracter fuera de CP1252 no se cuela como mojibake');
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

initialization
  TDUnitX.RegisterTestFixture(TEncodingTests);

end.
