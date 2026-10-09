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
    { Las pruebas de bytes de este grupo son de la pagina 1252 (un F3 es una
      o acentuada): la fijan, para valer en cualquier Windows, y la de la
      maquina vuelve al acabar (r5 de la 1.18.0: la ANSI es la de la maquina). }
    [Setup] procedure FijaLaPagina1252;
    [TearDown] procedure VuelveALaDeLaMaquina;
    [Test] procedure AnsiEsLaPaginaDeLaMaquina;
    [Test] procedure AnsiSigueALaPaginaQueSeMide;
    [Test] procedure CodecDeCharsetPorElNombreDeLaRtl;
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
    [Test] procedure Cp1252LosDoscientosCincuentaYSeisBytesVuelven;
    [Test] procedure Utf8EstrictoComoRfc3629;
    [Test] procedure IdaYVueltaPorCodificacionYSusRotos;
    [Test] procedure Utf8TolerantePoneFffdSinExcepcion;
    [Test] procedure CabeEnCp1252YHayByteAlto;
    [Test] procedure EncAlEscribirLaTablaDeUnFuente;
    [Test] procedure EncAlEscribirDecidePorLaLlamadaNoPorLaEscritura;
    [Test] procedure ReescrituraDenegadaPorLaIdaYVuelta;
    [Test] procedure ColaIncompletaDeUtf16YUtf32SaleFffd;
    [Test] procedure Utf8MezcladoEsAnsiComoElJuez;
    [Test] procedure EncAlEscribirConservaLaCodificacionDelOrigen;
    [Test] procedure LecturaCambiadaDelLadoDeLaEscritura;
    [Test] procedure EncAlEscribirAnclaDeNuevoSiLaRutaCambiaDeContenido;
    [Test] procedure MeasureCuentaCrlfYAcentosEnUtf16;
    [Test] procedure LooksBinaryNulEsBinario;
    [Test] procedure LooksBinaryUtf16NoEsBinario;
    [Test] procedure LooksBinaryTextoYVacioNoSonBinario;
    [Test] procedure Utf32PorSuBomYNoComoUtf16;
    [Test] procedure Utf32FueraDelPlanoBasico;
    [Test] procedure Utf32NoEsBinarioYSeMide;
    [Test]
    procedure UnEmojiQueNoCabeSeNombraEntero;
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
  Winapi.Windows, // GetACP: la pagina de la maquina
  System.SysUtils,
  Lsp.Guard, // ParametroQueNoVa
  Lsp.Patch,
  Lsp.Codificacion,
  Lsp.Casa,
  System.Character;

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

procedure TEncodingTests.FijaLaPagina1252;
begin
  UsaPaginaAnsi(1252);
end;

procedure TEncodingTests.VuelveALaDeLaMaquina;
begin
  UsaPaginaAnsi(GetACP);
end;

{ LA ANSI de la casa, con la pagina de la maquina, lee como TEncoding.ANSI
  de la RTL - el mismo codec, sin banderas -: es la que usan el IDE y dcc
  para un fuente sin BOM (r5 de la 1.18.0: estaba clavada en 1252). }
procedure TEncodingTests.AnsiEsLaPaginaDeLaMaquina;
var
  I: Integer;
begin
  UsaPaginaAnsi(GetACP);
  Assert.AreEqual(Cardinal(TEncoding.ANSI.CodePage), PaginaAnsi, 'la de TEncoding.ANSI');
  Assert.AreEqual('cp' + IntToStr(GetACP), EncName(ekAnsi), 'y su nombre la dice');
  for I := 128 to 255 do
    Assert.AreEqual(TEncoding.ANSI.GetString(B([I])), DecodeBytes(B([I]), ekAnsi),
      'el byte ' + IntToHex(I, 2) + ' se lee como la RTL');
end;

{ Con otra pagina todo la sigue: el lector, el codificador y su negativa, el
  nombre, el detector y la eleccion del primer acento. Lo esperado es lo que
  contesta Windows (medido el 9-oct-2026, WideCharToMultiByte y
  MultiByteToWideChar): en 1251 la e acentuada no cabe (Windows la aproxima
  a una e; la vuelta lo delata), una Omega cabe en 1253 y una hiragana en
  932, en dos bytes. Con la 1252 clavada en el codigo esta prueba cae; en una
  maquina 1252, ninguna otra lo ve. }
procedure TEncodingTests.AnsiSigueALaPaginaQueSeMide;
begin
  UsaPaginaAnsi(1251);
  Assert.AreEqual('cp1251', EncName(ekAnsi), 'el nombre de la pagina');
  Assert.AreEqual(Chr($0431) + Chr($0413) + Chr($040E), DecodeBytes(B([$E1, $C3, $A1]), ekAnsi),
    'E1 C3 A1 en 1251: lo que compilo dcc con DCC_CodePage=1251 (medido)');
  Assert.IsTrue(CabeEnAnsi(Chr($0416)), 'una Zhe cabe en 1251');
  Assert.AreEqual(1, Integer(Length(EncodeText(Chr($0416), ekAnsi))), 'en un byte');
  Assert.AreEqual($C6, Integer(EncodeText(Chr($0416), ekAnsi)[0]), 'el C6');
  Assert.AreEqual($C6, ByteCp(Chr($0416)), 'ByteCp dice lo mismo');
  Assert.IsFalse(CabeEnAnsi('caf' + Chr($E9)), 'la e acentuada no cabe en 1251');
  Assert.AreEqual(-1, ByteCp(Chr($E9)), 'ni tiene byte');
  try
    EncodeText('caf' + Chr($E9), ekAnsi);
    Assert.Fail('la e acentuada en 1251 se escribia');
  except
    on E: ECaracterNoCabe do
      Assert.AreEqual($E9, E.Codigo, 'la negativa nombra el caracter que no cabe');
  end;
  Assert.AreEqual('cp1251', EncName(DetectEnc(B([Ord('a'), $C6]))),
    'un byte alto que no es UTF-8: la ANSI de la pagina');
  Assert.AreEqual('cp1251', EncName(EncAlEscribir('C:\nada\UZ.pas', ekUtf8, B([Ord('a')]), True,
    'A = ''' + Chr($0416) + ''';')), 'el primer acento de un ASCII: la ANSI, si cabe');
  Assert.AreEqual('utf8-bom', EncName(EncAlEscribir('C:\nada\UZ.pas', ekUtf8, B([Ord('a')]), True,
    'A = ''caf' + Chr($E9) + ''';')), '...y si no cabe, UTF-8 con BOM');
  UsaPaginaAnsi(1253);
  Assert.IsTrue(CabeEnAnsi(Chr($03A9)), 'una Omega cabe en 1253');
  Assert.AreEqual($D9, Integer(EncodeText(Chr($03A9), ekAnsi)[0]), 'en D9');
  UsaPaginaAnsi(932);
  Assert.AreEqual(2, Integer(Length(EncodeText(Chr($3042), ekAnsi))), 'una hiragana: dos bytes en 932');
  Assert.AreEqual(Chr($3042), DecodeBytes(B([$82, $A0]), ekAnsi), '82 A0 se lee como ella');
  Assert.IsTrue(BytesVuelvenIgual(B([Ord('a'), $82, $A0]), ekAnsi), 'y vuelve igual');
  Assert.AreEqual(-1, ByteCp(Chr($3042)), 'ByteCp: no es de un byte');
  Assert.IsFalse(CabeEnAnsi(Chr($E9)), 'la e acentuada tampoco cabe en 932');
end;

{ El juego de caracteres que DECLARA un formato (la ayuda), por el nombre que
  entiende la RTL: no depende de la ANSI de la maquina. }
procedure TEncodingTests.CodecDeCharsetPorElNombreDeLaRtl;
var
  C: TEncoding;
begin
  UsaPaginaAnsi(1251);
  C := CodecDeCharset('windows-1252');
  try
    Assert.AreEqual(Chr($E9), C.GetString(B([$E9])), 'windows-1252 aunque la maquina fuera 1251');
  finally
    C.Free;
  end;
  C := CodecDeCharset('utf-8');
  try
    Assert.AreEqual('a' + Chr($FFFD) + 'b', C.GetString(B([Ord('a'), $F3, Ord('b')])),
      'utf-8 tolerante: un byte malo es U+FFFD, sin excepcion');
  finally
    C.Free;
  end;
  Assert.IsTrue(CodecDeCharset('property') = nil, 'un nombre que la RTL no conoce: nil');
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
  EsClase(Ord(ekAnsi), B([Ord('h'), $F3, Ord('a')]));
  Assert.AreEqual('h' + Chr(243) + 'a', DecodeBytes(B([Ord('h'), $F3, Ord('a')]), ekAnsi));
end;

procedure TEncodingTests.AsciiPuroLoDecideElIde;
var
  K: TEncKind;
begin
  // Sin byte alto no hay nada que detectar: manda la configuracion del IDE,
  // y sea cual sea, el texto se lee igual.
  K := DetectEnc(B([Ord('a'), Ord('b'), Ord('c')]));
  Assert.IsTrue(K in [ekUtf8, ekAnsi], 'ascii puro es utf8 o cp1252, nunca otra cosa: ' + EncName(K));
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
  Assert.AreEqual(EncName(ekAnsi), EncName(EncKindOf('rarito')), 'un nombre desconocido es la ANSI');
end;

procedure TEncodingTests.PreambleLenPorClase;
begin
  Assert.AreEqual(3, PreambleLen(ekUtf8Bom));
  Assert.AreEqual(0, PreambleLen(ekUtf8));
  Assert.AreEqual(0, PreambleLen(ekAnsi));
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
      EncodeText('ok ' + Chr($2714), ekAnsi);
    end, Exception, 'un caracter fuera de CP1252 no se cuela como mojibake (lanza su ECaracterNoCabe, que declara DENIED)');
end;

{ Lo que ya esta se escribe con los mismos bytes: los 256 de la pagina, los
  cinco que no define incluidos (81 8D 8F 90 9D: se leian como U+0081... y
  EncodeText los negaba; revisor propio, 9-oct-2026). ByteCp, la misma regla. }
procedure TEncodingTests.Cp1252LosDoscientosCincuentaYSeisBytesVuelven;
var
  I: Integer;
  S: string;
  Vuelta: TArray<Byte>;
begin
  for I := 0 to 255 do
  begin
    S := DecodeBytes(B([I]), ekAnsi);
    Assert.AreEqual(1, Length(S), 'un byte, un caracter: ' + IntToHex(I, 2));
    Vuelta := EncodeText(S, ekAnsi);
    Assert.IsTrue((Length(Vuelta) = 1) and (Vuelta[0] = I), 'el byte ' + IntToHex(I, 2) + ' vuelve a si mismo');
    Assert.AreEqual(I, ByteCp(S[1]), 'ByteCp dice lo mismo que EncodeText: ' + IntToHex(I, 2));
  end;
  // y lo que no da ningun byte no cabe, en los dos: el 80 es el euro
  Assert.AreEqual(-1, ByteCp(Chr($80)), 'U+0080 no lo da ningun byte');
  Assert.WillRaiseDescendant(
    procedure
    begin
      EncodeText(Chr($80), ekAnsi);
    end, Exception, 'U+0080 no se escribe como el euro');
end;

{ RFC 3629: tras E0, ED, F0 y F4 el segundo byte tiene su propio rango. Un
  CP1252 con E0 80 80 (forma larga) se tomaba por UTF-8 y su lectura
  reventaba (medido el 9-oct-2026). }
procedure TEncodingTests.Utf8EstrictoComoRfc3629;
begin
  Assert.IsFalse(ValidUtf8(B([$E0, $80, $80]), 0), 'E0 80 80: forma larga');
  Assert.IsTrue(ValidUtf8(B([$E0, $A0, $80]), 0), 'E0 A0 80: U+0800');
  Assert.IsFalse(ValidUtf8(B([$ED, $A0, $80]), 0), 'ED A0 80: un sustituto');
  Assert.IsTrue(ValidUtf8(B([$ED, $9F, $BF]), 0), 'ED 9F BF: U+D7FF');
  Assert.IsFalse(ValidUtf8(B([$F0, $80, $80, $80]), 0), 'F0 80 80 80: forma larga');
  Assert.IsTrue(ValidUtf8(B([$F0, $90, $80, $80]), 0), 'F0 90 80 80: U+10000');
  Assert.IsFalse(ValidUtf8(B([$F4, $90, $80, $80]), 0), 'F4 90 80 80: mas alla de U+10FFFF');
  Assert.IsTrue(ValidUtf8(B([$F4, $8F, $BF, $BF]), 0), 'F4 8F BF BF: U+10FFFF');
  Assert.AreEqual('cp1252', EncName(DetectEnc(B([Ord('x'), $E0, $80, $80]))),
    'un CP1252 con E0 80 80 es CP1252');
end;

{ La regla de ida y vuelta de los escritores (David, 9-oct-2026): lo bien
  formado vuelve igual en cada codificacion; lo roto, no. }
procedure TEncodingTests.IdaYVueltaPorCodificacionYSusRotos;
const
  TEXTO = 'uno ' + Chr(243) + #13#10'dos'#13#10;
var
  K: TEncKind;
begin
  for K := Low(TEncKind) to High(TEncKind) do
    Assert.IsTrue(BytesVuelvenIgual(EncodeText(TEXTO, K), K), 'bien formado vuelve en ' + EncName(K));
  Assert.IsFalse(BytesVuelvenIgual(B([$EF, $BB, $BF, Ord('a'), $F3, Ord('b')]), ekUtf8Bom),
    'un BOM de UTF-8 con un F3 suelto (el cuerpo en CP1252)');
  Assert.IsFalse(BytesVuelvenIgual(EncodeText('ab', ekUtf32LE) + B([$41, 0]), ekUtf32LE),
    'un UTF-32 al que le sobran dos bytes');
  Assert.IsFalse(BytesVuelvenIgual(EncodeText('ab', ekUtf16LE) + B([$41]), ekUtf16LE),
    'un UTF-16 de longitud impar');
  Assert.IsTrue(BytesVuelvenIgual(nil, ekUtf8), 'vacio');
end;

{ El UTF-8 TOLERANTE: un byte malo es U+FFFD, no una excepcion (la lectura de
  un BOM de UTF-8 con el cuerpo roto tumbaba delphi_read). }
procedure TEncodingTests.Utf8TolerantePoneFffdSinExcepcion;
var
  S: string;
begin
  S := DecodeBytes(B([$EF, $BB, $BF, Ord('a'), $F3, Ord('b')]), ekUtf8Bom);
  Assert.IsTrue(Pos(#$FFFD, S) > 0, 'el byte malo sale U+FFFD: ' + S);
  Assert.AreEqual('a', Copy(S, 1, 1), 'y lo bueno, tal cual');
end;

procedure TEncodingTests.CabeEnCp1252YHayByteAlto;
begin
  Assert.IsTrue(CabeEnAnsi('Acci' + Chr(243) + 'n ' + Chr($20AC)), 'una vocal acentuada y el euro caben');
  Assert.IsFalse(CabeEnAnsi('Omega ' + Chr($03A9)), 'una letra griega no');
  Assert.IsTrue(CabeEnAnsi(''), 'nada cabe');
  Assert.IsFalse(HayByteAlto(B([Ord('a'), 13, 10])), 'ASCII');
  Assert.IsTrue(HayByteAlto(B([$EF, $BB, $BF])), 'un BOM lleva bytes altos');
  Assert.IsTrue(HayByteAlto(B([0, 0, $FE, $FF])), 'tambien el de UTF-32 BE');
end;

{ La codificacion en que se ESCRIBE (4.1 de la 1.18.0): un fuente sin
  ninguna (solo ASCII) la elige con su primer caracter no ASCII; lo demas
  conserva la suya. Rutas que no existen: la decision no mira el disco. }
procedure TEncodingTests.EncAlEscribirLaTablaDeUnFuente;
const
  ACENTO = 'Acci' + Chr(243) + 'n';
  OMEGA = 'Omega ' + Chr($03A9);
var
  Ascii: TArray<Byte>;

  function Es(const APath: string; AK: TEncKind; const AAntes: TArray<Byte>;
    AExiste: Boolean; const ATexto: string): string;
  begin
    Result := EncName(EncAlEscribir(APath, AK, AAntes, AExiste, ATexto));
  end;

begin
  Ascii := B([Ord('u'), Ord('n'), Ord('i'), Ord('t'), 13, 10]);
  Assert.AreEqual('cp1252', Es('C:\nada\U1.pas', ekUtf8, Ascii, True, ACENTO),
    'un .pas ASCII y una vocal acentuada: CP1252, aunque el IDE prefiera UTF-8');
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.pas', ekAnsi, Ascii, True, OMEGA),
    'un .pas ASCII y una letra griega: UTF-8 con BOM');
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.inc', ekAnsi, Ascii, True, OMEGA),
    'un .inc tambien es un fuente');
  Assert.AreEqual(EncName(DetectEnc(Ascii)), Es('C:\nada\U1.pas', ekUtf8Bom, Ascii, True, 'solo ascii'),
    'un texto ASCII no elige nada: la del origen (para un ASCII, la preferencia del IDE), no la que llega');
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.pas', ekUtf8Bom, B([$EF, $BB, $BF, Ord('a')]), True, ACENTO),
    'un BOM ya es una codificacion: se conserva');
  Assert.AreEqual('cp1252', Es('C:\nada\U1.pas', ekAnsi, B([Ord('a'), $E9]), True, OMEGA),
    'un byte alto ya es una codificacion: se conserva (y el escritor niega la Omega)');
  Assert.AreEqual('utf8', Es('C:\nada\U1.pas', ekUtf8, B([Ord('a'), $C3, $A9]), True, ACENTO),
    'un UTF-8 sin BOM con acentos tambien la conserva');
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.pas', ekAnsi, nil, False, OMEGA),
    'uno nuevo en CP1252 (la del IDE) donde no cabe: UTF-8 con BOM');
  Assert.AreEqual('cp1252', Es('C:\nada\U1.pas', ekAnsi, nil, False, ACENTO),
    'uno nuevo en CP1252 donde cabe: CP1252');
  Assert.AreEqual('utf8', Es('C:\nada\leeme.md', ekUtf8, Ascii, True, OMEGA),
    'lo que no es un fuente, tal cual');
  Assert.AreEqual('cp1252', Es('C:\nada\F1.dfm', ekAnsi, Ascii, True, OMEGA),
    'un form no es un fuente: se queda en la suya (como fuente, la Omega lo pasaria a UTF-8 con BOM)');
  // una E acentuada seguida de una comilla tipografica: en CP1252 son C9 94, un
  // caracter UTF-8 valido; solas en el fichero, el IDE y el detector lo leerian
  // como UTF-8 (revisor propio de la 4.1)
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.pas', ekAnsi, Ascii, True, 'CAF' + Chr($C9) + Chr($201D)),
    'un .pas ASCII cuyos bytes CP1252 se leerian como UTF-8: UTF-8 con BOM, sin ambiguedad');
  Assert.AreEqual('cp1252', Es('C:\nada\U1.pas', ekUtf8, Ascii, True,
    Chr($201C) + 'CAF' + Chr($C9) + Chr($201D)), '...con la comilla de apertura ya no es UTF-8 valido: CP1252');
  Assert.AreEqual('utf8-bom', Es('C:\nada\U1.pas', ekUtf8, nil, False, ACENTO),
    'un fuente nuevo nunca va en UTF-8 sin BOM (el IDE no lo guarda asi; dcc lo leeria como ANSI)');
end;

{ ...y la decide lo que el fichero tenia ANTES DE LA LLAMADA: una tanda con la
  vocal acentuada y luego la Omega se negaba (la primera escritura fijaba
  CP1252) y al reves salia en UTF-8 con BOM (medido el 9-oct-2026). Fuera de
  una llamada (la puerta no paso) se decide escritura a escritura. }
procedure TEncodingTests.EncAlEscribirDecidePorLaLlamadaNoPorLaEscritura;
const
  P = 'C:\nada\UOrden.pas';
  TEXTO1 = 'A = ''Acci' + Chr(243) + 'n'';';
var
  Ascii, Tras1: TArray<Byte>;
  K1: TEncKind;
begin
  Ascii := B([Ord('A'), Ord(' '), Ord('='), Ord(' '), Ord('1'), Ord(';')]);
  OlvidaOrigenes(True);
  try
    K1 := EncAlEscribir(P, ekUtf8, Ascii, True, TEXTO1);
    Assert.AreEqual('cp1252', EncName(K1), 'la primera escritura: la vocal cabe');
    Tras1 := EncodeText(TEXTO1, K1);
    ApuntaEscritoEnLaLlamada(P, Tras1); // lo que hace AtomicWrite tras escribir
    Assert.AreEqual('utf8-bom', EncName(EncAlEscribir(P, ekAnsi, Tras1, True, TEXTO1 + Chr($03A9))),
      'la segunda, con la Omega: lo de antes de la llamada era ASCII, UTF-8 con BOM');
    Assert.AreEqual('cp1252', EncName(EncAlEscribir('C:\nada\UOtra.pas', ekAnsi, Tras1, True,
      TEXTO1 + Chr($03A9))), 'otra ruta tiene su propio origen (este tiene un byte alto)');
  finally
    OlvidaOrigenes(False);
  end;
  // fuera de una llamada, escritura a escritura: el byte alto de la primera
  // manda (otra ruta: si OlvidaOrigenes(False) dejara la llamada abierta, la
  // primera apuntaria el ASCII y la segunda saldria UTF-8 con BOM)
  Assert.AreEqual('cp1252', EncName(EncAlEscribir('C:\nada\UFuera.pas', ekUtf8, Ascii, True, TEXTO1)),
    'sin llamada, la primera');
  ApuntaEscritoEnLaLlamada('C:\nada\UFuera.pas', Tras1); // fuera de una llamada, nada
  Assert.AreEqual('cp1252', EncName(EncAlEscribir('C:\nada\UFuera.pas', ekAnsi, Tras1, True,
    TEXTO1 + Chr($03A9))), 'sin llamada, la segunda ve el CP1252 de la primera');
end;

{ LA REGLA DE IDA Y VUELTA de los escritores, con EL detector: '' si se
  puede reescribir; si no, la negativa (EDIT-038). Un U+FFFD que esta de
  verdad en el fichero (EF BF BD en un UTF-8 valido) vuelve igual. }
procedure TEncodingTests.ReescrituraDenegadaPorLaIdaYVuelta;
var
  K: TEncKind;
begin
  Assert.AreEqual('', ReescrituraDenegada('C:\nada\n.md', B([$EF, $BB, $BF, Ord('a'), $C3, $B3]), K),
    'un UTF-8 con BOM bien formado');
  Assert.AreEqual('utf8-bom', EncName(K));
  Assert.IsTrue(Pos('EDIT-038', ReescrituraDenegada('C:\nada\n.md',
    B([$EF, $BB, $BF, Ord('a'), $F3, Ord('b')]), K)) > 0, 'un BOM de UTF-8 con el cuerpo en CP1252');
  Assert.AreEqual('', ReescrituraDenegada('C:\nada\n.md', B([Ord('a'), $EF, $BF, $BD, Ord('b')]), K),
    'un U+FFFD legitimo en un UTF-8 sin BOM vuelve igual');
  Assert.AreEqual('utf8', EncName(K));
  Assert.IsTrue(Pos('EDIT-038', ReescrituraDenegada('C:\nada\n.pas',
    EncodeText('ab', ekUtf16LE) + B([$41]), K)) > 0, 'un UTF-16 con un byte de mas');
end;

{ Lo que sobra al final de un UTF-16 (un byte) o de un UTF-32 (menos de
  cuatro) sale U+FFFD, como cualquier byte que no cuadra: la RTL lo dejaba
  fuera callado y delphi_edit reescribia el fichero sin el (revisor propio de
  la 4.1, medido). }
procedure TEncodingTests.ColaIncompletaDeUtf16YUtf32SaleFffd;
begin
  Assert.AreEqual('ab'#$FFFD, DecodeBytes(EncodeText('ab', ekUtf16LE) + B([$41]), ekUtf16LE), 'UTF-16 LE');
  Assert.AreEqual('ab'#$FFFD, DecodeBytes(EncodeText('ab', ekUtf16BE) + B([$41]), ekUtf16BE), 'UTF-16 BE');
  Assert.AreEqual('ab'#$FFFD, DecodeBytes(EncodeText('ab', ekUtf32LE) + B([$41, 0]), ekUtf32LE), 'UTF-32 LE');
  Assert.AreEqual('ab', DecodeBytes(EncodeText('ab', ekUtf16LE), ekUtf16LE), 'sin cola, nada de mas');
end;

{ Secuencias UTF-8 buenas junto a bytes que no lo son NO son UTF-8: el juez
  de la RTL (IsBufferValid) dice que no, y el IDE y dcc los leen en ANSI. Una
  regla propia de "UTF-8 danado" se probo y se quito: una E acentuada seguida
  de una comilla tipografica son, en CP1252, un caracter UTF-8 valido, y un
  CP1252 legitimo quedaba sin editar (revisor propio de la 4.1; David: "si
  hay juez lo seguimos"). }
procedure TEncodingTests.Utf8MezcladoEsAnsiComoElJuez;
var
  Cesu, Comillas: TArray<Byte>;
  K: TEncKind;
begin
  // 'a' + o con acento (C3 B3, valido) + un sustituto en CESU-8 (ED A0 BD ED B8 80)
  Cesu := B([Ord('a'), $C3, $B3, $ED, $A0, $BD, $ED, $B8, $80]);
  Assert.IsFalse(ValidUtf8(Cesu, 0), 'el juez estricto lo rechaza');
  Assert.AreEqual('cp1252', EncName(DetectEnc(Cesu)), 'acentos UTF-8 y una secuencia prohibida: ANSI, como el IDE');
  Comillas := EncodeText(Chr($201C) + 'CAF' + Chr($C9) + Chr($201D) + ' ' + Chr($AB) + 'S' + Chr($CD) +
    Chr($BB) + ' Acci' + Chr(243) + 'n', ekAnsi);
  Assert.AreEqual('cp1252', EncName(DetectEnc(Comillas)), 'un CP1252 con comillas tipograficas es CP1252');
  Assert.AreEqual('', ReescrituraDenegada('C:\nada\n.pas', Comillas, K), '...y se puede reescribir');
end;

{ La que tenia el fichero antes de la llamada se conserva aunque una entrada
  anterior le quite su ultimo acento: un CP1252 acababa en UTF-8 sin BOM (la
  preferencia del IDE para lo que parecia ASCII) segun el orden de la tanda
  (revisor propio de la 4.1, medido; tambien en la 1.17). }
procedure TEncodingTests.EncAlEscribirConservaLaCodificacionDelOrigen;
const
  P = 'C:\nada\UUnAcento.pas';
var
  Antes, SinAcento: TArray<Byte>;
begin
  Antes := EncodeText('A = ''' + Chr($E9) + ''';', ekAnsi);
  SinAcento := EncodeText('A = 1;', ekAnsi);
  OlvidaOrigenes(True);
  try
    Assert.AreEqual('cp1252', EncName(EncAlEscribir(P, ekAnsi, Antes, True, 'A = 1;')),
      'la entrada 1 quita el unico acento');
    ApuntaEscritoEnLaLlamada(P, SinAcento);
    Assert.AreEqual('cp1252', EncName(EncAlEscribir(P, ekUtf8, SinAcento, True,
      'A = ''Acci' + Chr(243) + 'n'';')), 'la entrada 2 pone otro: la del origen, CP1252, no la del IDE');
  finally
    OlvidaOrigenes(False);
  end;
end;

{ La ida y vuelta del lado de la ESCRITURA: lo que se escribe tiene que
  leerse en la codificacion escrita (EDIT-122). En un CP1252, una A con tilde
  y un superindice tres son los bytes de una o acentuada en UTF-8. }
procedure TEncodingTests.LecturaCambiadaDelLadoDeLaEscritura;
begin
  Assert.IsTrue(Pos('EDIT-122', LecturaCambiada('C:\nada\U.pas',
    EncodeText('gestor' + Chr($C3) + Chr($B3) + 'n', ekAnsi), ekAnsi)) > 0,
    'en CP1252 parece UTF-8: se leeria como otra cosa');
  Assert.AreEqual('', LecturaCambiada('C:\nada\U.pas',
    EncodeText('gestor' + Chr($C3) + Chr($B3) + 'n ' + Chr($E9), ekAnsi), ekAnsi),
    'junto a un acento CP1252 suelto ya no es UTF-8 valido: se lee igual, como el IDE');
  Assert.AreEqual('', LecturaCambiada('C:\nada\U.pas', EncodeText('gesti' + Chr(243) + 'n', ekAnsi), ekAnsi),
    'un acento CP1252 corriente se lee igual');
  Assert.AreEqual('', LecturaCambiada('C:\nada\U.pas', EncodeText('gestor' + Chr($C3) + Chr($B3) + 'n', ekUtf8), ekUtf8),
    'en un UTF-8 el mojibake se lee igual (lo avisa EDIT-083)');
  Assert.AreEqual('', LecturaCambiada('C:\nada\U.pas', EncodeText('solo ascii', ekAnsi), ekUtf8),
    'sin byte alto no hay codificacion que leer');
  Assert.AreEqual('', LecturaCambiada('C:\nada\F.dfm', EncodeText('gestor' + Chr($C3) + Chr($B3) + 'n', ekAnsi), ekAnsi),
    'un form sin BOM es ANSI para el detector: se lee igual');
end;

{ Si en la ruta hay OTRO contenido que el que la llamada dejo (un delete y un
  move del changeset, un deshacer, un proceso de fuera), lo apuntado ya no es
  el origen de ese fichero: se ancla de nuevo. Un changeset que editaba P, lo
  borraba y movia a P un fichero en UTF-8 con BOM lo dejaba en CP1252
  (revisor propio de la 4.1, medido). }
procedure TEncodingTests.EncAlEscribirAnclaDeNuevoSiLaRutaCambiaDeContenido;
const
  P = 'C:\nada\UMovido.pas';
  ACENTO = 'Acci' + Chr(243) + 'n';
var
  Ascii, ConBom: TArray<Byte>;
begin
  Ascii := B([Ord('u'), Ord('n'), Ord('i'), Ord('t')]);
  ConBom := B([$EF, $BB, $BF, Ord('a'), $C3, $B3]);
  OlvidaOrigenes(True);
  try
    Assert.AreEqual(EncName(DetectEnc(Ascii)), EncName(EncAlEscribir(P, ekUtf8, Ascii, True, 'solo ascii')),
      'la primera escritura apunta el ASCII');
    ApuntaEscritoEnLaLlamada(P, Ascii);
    // ...y otro (un move) deja en P un fichero en UTF-8 con BOM
    Assert.AreEqual('utf8-bom', EncName(EncAlEscribir(P, ekUtf8Bom, ConBom, True, ACENTO)),
      'lo que hay ya tiene codificacion: se conserva');
  finally
    OlvidaOrigenes(False);
  end;
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

{ UTF-32 (9-oct-2026): el IDE deja guardar un fuente asi y su BOM de LE
  (FF FE 00 00) empieza como el de UTF-16 LE: se leia como UTF-16, con un NUL
  entre letra y letra, y el de BE se daba por binario. }
procedure TEncodingTests.Utf32PorSuBomYNoComoUtf16;
begin
  EsClase(Ord(ekUtf32LE), B([$FF, $FE, 0, 0, Ord('a'), 0, 0, 0]));
  Assert.AreEqual('a', DecodeBytes(B([$FF, $FE, 0, 0, Ord('a'), 0, 0, 0]), ekUtf32LE));
  EsClase(Ord(ekUtf32BE), B([0, 0, $FE, $FF, 0, 0, 0, Ord('a')]));
  Assert.AreEqual('a', DecodeBytes(B([0, 0, $FE, $FF, 0, 0, 0, Ord('a')]), ekUtf32BE));
  Assert.AreEqual(4, PreambleLen(ekUtf32LE));
  Assert.AreEqual(4, Integer(Length(EncodeText('', ekUtf32BE))), 'el BOM UTF-32 son 4 bytes');
end;

procedure TEncodingTests.Utf32FueraDelPlanoBasico;
const
  CARA = #$D83D#$DE00; // U+1F600, un par de sustitutos en Delphi
var
  Bytes: TArray<Byte>;
begin
  Bytes := EncodeText('x' + CARA, ekUtf32LE);
  Assert.AreEqual(12, Integer(Length(Bytes)), 'BOM + dos caracteres, de cuatro bytes cada uno');
  Assert.AreEqual($01, Integer(Bytes[10]), 'U+1F600 en LE: 00 F6 01 00');
  Assert.AreEqual('x' + CARA, DecodeBytes(Bytes, ekUtf32LE), 'y de vuelta, el par entero');
  Assert.AreEqual(#$FFFD, DecodeBytes(B([$FF, $FE, 0, 0, 0, $D8, 0, 0]), ekUtf32LE),
    'un sustituto suelto no es un caracter: U+FFFD');
end;

procedure TEncodingTests.Utf32NoEsBinarioYSeMide;
var
  Bytes: TArray<Byte>;
  M: TMetrics;
begin
  Bytes := EncodeText('a'#13#10 + Chr(243) + #13#10, ekUtf32BE);
  Assert.IsFalse(LooksBinaryBytes(Bytes), 'UTF-32 BE con sus NUL no es binario');
  M := Measure(Bytes);
  Assert.AreEqual(2, M.CRLF, 'CRLF contados sobre el texto');
  Assert.AreEqual(2, M.High, 'un acento = 2 bytes altos, como en un fichero utf8');
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

procedure TEncodingTests.UnEmojiQueNoCabeSeNombraEntero;
var
  Emoji: string;
begin
  // el juez del literal es el compilador: dcc acepta el par y ES el emoji
  // (r5-L1 de la 1.18.0: la negativa nombraba U+D83D y proponia su literal)
  Emoji := #$D83D#$DE00;
  Assert.AreEqual(Char.ConvertFromUtf32($1F600), Emoji, 'el par que se propone es el emoji');
  try
    EncodeText('a' + Emoji + 'b', ekAnsi);
    Assert.Fail('un emoji se escribia en ANSI');
  except
    on E: ECaracterNoCabe do
    begin
      Assert.AreEqual($1F600, E.Codigo, 'su codigo de verdad, no el del sustituto alto');
      Assert.Contains(E.Message, 'U+1F600', 'la negativa lo nombra entero');
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEncodingTests);
  TDUnitX.RegisterTestFixture(TNombradorTests);

end.
