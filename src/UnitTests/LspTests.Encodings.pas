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
    [Test]
    procedure UnSustitutoSueltoNoSeEscribeEnNinguna;
    [Test]
    procedure UnFormBinarioNoVuelveComoAnsiEnDobleByte;
    [Test]
    procedure UnSustitutoSueltoQueYaEstabaSeEscribeComoEstaba;
    [Test]
    procedure UbicacionDeLspLeeLasFormasDelMotor;
    [Test]
    procedure ElMojibakeDeLatin1SeVeEnCualquierPagina;
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
    [Test] procedure LaLineaDeUnAnclaUnaRegla;
    [Test] procedure LaLineaElegidaUnaNegativa;
    [Test] procedure ZonaDelCambioMueveLoDeDebajo;
    [Test] procedure UriDelMotorYSuInversa;
    [Test] procedure CompositorConservaLosSaltosDeFuera;
    [Test] procedure ElTextoEnteroConLaReglaDeQuienCambiaLineas;
    [Test]
    procedure ColumnaDelMotorYSuInversa;
  end;

implementation

uses
  Winapi.Windows, // GetACP: la pagina de la maquina
  System.SysUtils,
  Lsp.Guard, // ParametroQueNoVa
  Lsp.Patch,
  Lsp.Texts, // EsMsg y las negativas de un ancla
  Lsp.Codificacion,
  Lsp.Casa,
  System.Character,
  Lsp.DesignerBin,
  Lsp.Client,
  System.JSON,
  Lsp.References;

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
  // una etiqueta que la base MIME de Windows lleva a una pagina sin codec
  // (x-user-defined, 50000): nil, no una excepcion (R3, revisor del punto 4)
  Assert.IsTrue(CodecDeCharset('x-user-defined') = nil, 'una pagina que Windows no tiene: nil');
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

{ Que una linea ES la de un ancla, LA regla de los motores, sus bloques y
  occurrence (A15 de la 1.23): los blancos de los dos extremos no cuentan. }
procedure TNombradorTests.LaLineaDeUnAnclaUnaRegla;
var
  Hits: TArray<Integer>;
begin
  Assert.IsTrue(LineaEsLaDelAncla('  foo;  ', 'foo;'), 'ni la sangria ni los de detras');
  Assert.IsTrue(LineaEsLaDelAncla(#9'foo;', '    foo;'), 'ni la sangria del ancla');
  Assert.IsFalse(LineaEsLaDelAncla('  foo; // x', 'foo;'), 'un trozo no es la linea');
  Assert.IsTrue(LineaEsLaDelAncla('   ', ''), 'una en blanco casa con el ancla vacia');
  Hits := LineasDondeCasaElAncla(['a', '  foo;  ', 'foo;'], 'foo;');
  Assert.AreEqual<Integer>(2, Length(Hits));
  Assert.AreEqual<Integer>(1, Hits[0], 'la de los blancos de detras es la primera');
  Hits := IniciosDelAncla(['x', '  a  ', 'b', 'a', ' b '], 'a'#10'b');
  Assert.AreEqual<Integer>(2, Length(Hits), 'un bloque, por la misma regla');
  Assert.AreEqual<Integer>(3, Hits[1]);
end;

{ LA eleccion de la linea de un ancla entre las que casan, y LAS negativas,
  de las dos tools (A15: delphi_textedit tenia otros dos codigos). }
procedure TNombradorTests.LaLineaElegidaUnaNegativa;
var
  Idx: Integer;
begin
  Assert.AreEqual('', LineaElegida([3], 0, Idx));
  Assert.AreEqual<Integer>(3, Idx);
  Assert.AreEqual('', LineaElegida([3, 5], 6, Idx), 'atline desempata (1-based)');
  Assert.AreEqual<Integer>(5, Idx);
  Assert.IsTrue(EsMsg(LineaElegida([3, 5], 0, Idx), SR_EDIT_ANCLA_NO_UNICA_FMT), 'repetida sin atline');
  Assert.IsTrue(EsMsg(LineaElegida([3, 5], 5, Idx), SR_EDIT_LINEA_ESTA_ESE_ANCLA_FMT),
    'un atline que no es ninguna');
  Assert.IsTrue(EsMsg(LineaElegida([3], 2, Idx), SR_EDIT_LINEA_ESTA_ESE_ANCLA_FMT),
    'tampoco con una sola');
  Assert.IsTrue(Pos('4, 6', LineaElegida([3, 5], 0, Idx)) > 0, 'sus lineas, 1-based');
end;

procedure TNombradorTests.ParametroQueNoVaConSuDefecto;
var
  Suyos, VaCon: string;
const
  TABLA: array [0 .. 5] of string = ('info', 'classname', 'tree', 'path maxdepth', 'lint', 'path');
begin
  Assert.AreEqual('path', ParametroQueNoVa('set-output', ['set-output', 'output'],
    ['output', 'bin', '', 'path', '.\bin', ''], Suyos, VaCon));
  Assert.AreEqual('output', Suyos);
  Assert.AreEqual('', VaCon, 'path no va con ningun modo de esa tabla');
  // el valor por defecto que publica el esquema no cuenta como enviado
  Assert.AreEqual('', ParametroQueNoVa('set-output', ['set-output', 'output'],
    ['section', 'summary', 'summary'], Suyos, VaCon));
  // un modo que no esta en la tabla no se mira: lo dice su propia negativa
  Assert.AreEqual('', ParametroQueNoVa('otro', ['set-output', 'output'],
    ['path', 'x', ''], Suyos, VaCon));
  // con que modos SI va, de la misma tabla (DSGN-047 de la 1.20): todo lo
  // enviado si un modo lo lleva entero (el command olvidado: tree)...
  Assert.AreEqual('path', ParametroQueNoVa('info', TABLA,
    ['path', 'U.fmx', '', 'maxdepth', '3', ''], Suyos, VaCon));
  Assert.AreEqual(' What you sent (path, maxdepth) goes with: tree.', VaCon);
  // ...y si no, los que llevan el que sobra
  Assert.AreEqual('path', ParametroQueNoVa('info', TABLA,
    ['path', 'U.fmx', ''], Suyos, VaCon));
  Assert.AreEqual(' "path" goes with: tree, lint.', VaCon);
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

procedure TEncodingTests.UnSustitutoSueltoNoSeEscribeEnNinguna;
const
  TODAS: array [0 .. 6] of TEncKind = (ekUtf8, ekUtf8Bom, ekUtf16LE, ekUtf16BE, ekUtf32LE, ekUtf32BE, ekAnsi);
var
  K: TEncKind;
  Suelto: string;
begin
  // codificacion M1 del revisor de version de la 1.18.0: UTF-8 lo escribia
  // EF BF BD, UTF-32 U+FFFD y UTF-16 crudo; solo la ANSI lo negaba
  for Suelto in TArray<string>.Create(#$D83D, #$DE00) do
    for K in TODAS do
      try
        EncodeText('a' + Suelto + 'b', K);
        Assert.Fail('un sustituto suelto se escribia en ' + EncName(K));
      except
        on E: ECaracterNoCabe do
        begin
          Assert.AreEqual(Integer(Ord(Suelto[1])), E.Codigo, 'su codigo, en ' + EncName(K));
          Assert.IsFalse(E.Message.Contains(Suelto), 'el mensaje no lo lleva crudo, en ' + EncName(K));
        end;
      end;
  // el par entero sigue siendo un caracter, y quien mide lo pide laxo
  Assert.AreEqual(4, Integer(Length(EncodeText(#$D83D#$DE00, ekUtf8))), 'el emoji en UTF-8, cuatro bytes');
  Assert.AreEqual(3, Integer(Length(EncodeText(#$D83D, ekUtf8, False))), 'laxo: EF BF BD, como antes');
end;

procedure TEncodingTests.UnFormBinarioNoVuelveComoAnsiEnDobleByte;
var
  Bin: TBytes;
  K: TEncKind;
begin
  // la CAUSA de la codificacion M3 del revisor de version de la 1.18.0: to-text
  // pasaba los bytes del binario por la ida y vuelta de los escritores, que los
  // lee como un texto ANSI. En 1252 cada byte vuelve igual (por eso aqui no se
  // veia); en 932 no, y to-text se negaba. El arreglo (ANuevo en
  // ConvertDesigner, Mcp.Tools.Designer) no lo alcanza una prueba unitaria: es
  // una guarda declarada. Left = 129 se guarda como 03 81 00: en 932 el 81
  // abre un par de dos bytes y el 00 no lo cierra (medido: con un form sin un
  // byte asi, el binario SI vuelve en 932); una posicion o un tamano entre 129
  // y 159, o entre 224 y 252, es lo normal en un form de verdad
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.ASCII.GetBytes('object FormX: TFormX'#13#10 +
    '  Left = 129'#13#10'  Caption = ''Hola'''#13#10'end'#13#10), Bin), 'el binario del form');
  UsaPaginaAnsi(1252);
  Assert.AreEqual('', ReescrituraDenegada('C:\nada\UX.dfm', Bin, K), 'en 1252 los bytes del binario vuelven');
  UsaPaginaAnsi(932);
  Assert.IsTrue(Pos('EDIT-038', ReescrituraDenegada('C:\nada\UX.dfm', Bin, K)) > 0,
    'en 932 no vuelven: EDIT-038');
end;

procedure TEncodingTests.UnSustitutoSueltoQueYaEstabaSeEscribeComoEstaba;
var
  Antes: string;

  function Niega(const S: string; K: TEncKind): Boolean;
  begin
    Result := False;
    try
      EncodeText(S, K, True, Antes);
    except
      on ECaracterNoCabe do
        Result := True;
    end;
  end;

begin
  // revisor de version de la 1.18.1: un UTF-16 con un suelto en una linea que
  // nadie tocaba dejo de editarse por ningun escritor. Lo que ya estaba se
  // escribe como estaba; lo nuevo, no
  Antes := 'uno ' + #$D800 + ' dos';
  Assert.IsFalse(Niega('uno ' + #$D800 + ' tres', ekUtf16LE), 'el que ya estaba, en UTF-16 LE');
  Assert.IsFalse(Niega('uno ' + #$D800 + ' tres', ekUtf16BE), 'el que ya estaba, en UTF-16 BE');
  var Bytes := EncodeText(#$D800, ekUtf16LE, True, Antes);
  Assert.AreEqual(4, Integer(Length(Bytes)), 'el BOM y una unidad');
  Assert.AreEqual(Integer($D800), Integer(Bytes[2] or (Bytes[3] shl 8)), 'y se escribe tal cual, el mismo codigo');
  Assert.IsTrue(Niega(#$D800 + ' y otro ' + #$D800, ekUtf16LE), 'dos donde habia uno: el segundo es nuevo');
  Assert.IsTrue(Niega('uno ' + #$DC00, ekUtf16LE), 'uno distinto es nuevo');
  // quien decide si K lo escribe tal cual es el codec: UTF-8 y UTF-32 lo
  // escribirian U+FFFD, la ANSI no lo tiene
  Assert.IsTrue(Niega('uno ' + #$D800, ekUtf8), 'en UTF-8 no se escribe aunque estuviera');
  Assert.IsTrue(Niega('uno ' + #$D800, ekUtf32LE), 'en UTF-32 tampoco');
  Assert.IsTrue(Niega('uno ' + #$D800, ekAnsi), 'ni en la ANSI');
  Antes := '';
  Assert.IsTrue(Niega('uno ' + #$D800, ekUtf16LE), 'sin texto de antes, todo suelto es nuevo');
end;

procedure TNombradorTests.UriDelMotorYSuInversa;
var
  P: string;
begin
  // el lector es la inversa del que compone, tambien con lo que no es ASCII
  for P in TArray<string>.Create('C:\a\a' + #$00F1 + 'o\x.pas', 'C:\(x) & y+1\u.pas',
    'D:\con espacios\' + #$00F1 + 'and' + #$00FA + ' ' + #$D83D#$DE00 + '\x.pas', 'C:\100%\x.pas') do
    Assert.AreEqual(P, TLspClient.UriToPath(TLspClient.PathToUri(P)), 'ida y vuelta de ' + P);
  // ...y lee la forma en que CONTESTA el motor: lo que no es ASCII, sin
  // escapar (medido el 10-oct-2026; daba SYS-006 con una carpeta con enye)
  Assert.AreEqual('C:\a\a' + #$00F1 + 'o\x.pas',
    TLspClient.UriToPath('file:///C%3A/a/a' + #$00F1 + 'o/x.pas'), 'la enye sin escapar');
  Assert.AreEqual('C:\' + #$D83D#$DE00 + '\x.pas',
    TLspClient.UriToPath('file:///C%3A/' + #$D83D#$DE00 + '/x.pas'), 'un par de sustitutos sin escapar');
  // ...y las dos formas de la misma uri son UNA al compararlas (UriCanonica)
  Assert.AreEqual(TLspClient.PathToUri('C:\a\a' + #$00F1 + 'o\x.pas'),
    TLspClient.UriCanonica('file:///C%3A/a/a' + #$00F1 + 'o/x.pas'), 'la del motor, en la forma del nombrador');
  Assert.AreEqual(TLspClient.PathToUri('C:\a\x.pas'),
    TLspClient.UriCanonica(TLspClient.PathToUri('C:\a\x.pas')), 'la del nombrador no cambia');
  // un '%' sin dos cifras hexadecimales es un caracter mas: se comia las dos
  // de detras (revisor de version de la 1.18.1)
  Assert.AreEqual('C:\a%zzb\x.pas', TLspClient.UriToPath('file:///C%3A/a%zzb/x.pas'), '%zz en medio');
  Assert.AreEqual('C:\end%', TLspClient.UriToPath('file:///C%3A/end%'), '% al final');
  // ...y un escape que no es UTF-8 no LANZA (EEncodingError, salia SYS-006): el
  // byte malo es U+FFFD, en una ruta que se ve (punto 5 de la 1.18.2)
  Assert.AreEqual('C:\a' + #$FFFD + 'b\x.pas', TLspClient.UriToPath('file:///C%3A/a%FFb/x.pas'),
    'escape que no es UTF-8: U+FFFD, sin excepcion');
  // ...y UriCanonica NO lanza con escapes que no son UTF-8: corre bajo el
  // cerrojo de las notificaciones; devuelve la uri tal cual
  Assert.AreEqual('file:///C%3A/a%C3', TLspClient.UriCanonica('file:///C%3A/a%C3'), 'escape roto, tal cual');
  // ...ni con medio caracter suelto: se volvia U+FFFD antes del juez, y la
  // uri de un fichero real con U+FFFD era la misma (M6 del revisor de cierre)
  Assert.AreEqual('file:///C%3A/a' + #$D800 + '/x.pas', TLspClient.UriCanonica('file:///C%3A/a' + #$D800 + '/x.pas'),
    'medio caracter suelto: tal cual');
  Assert.AreNotEqual(TLspClient.UriCanonica('file:///C%3A/a' + #$FFFD + '/x.pas'),
    TLspClient.UriCanonica('file:///C%3A/a' + #$D800 + '/x.pas'), 'y no es la del fichero con U+FFFD');
  // ...y el NOMBRADOR no escribe medio caracter como U+FFFD en silencio: lo
  // dice (LSP-044) a todo el que le pida la uri de esa ruta (W5 del revisor
  // de cierre; antes solo un borde, NoEsFuenteDelphi)
  Assert.WillRaise(
    procedure
    begin
      TLspClient.PathToUri('C:\a' + #$D800 + 'b\x.pas');
    end, ELspClient, 'medio caracter en la ruta: el nombrador no la escribe');
  Assert.AreEqual('file:///C%3A/' + '%F0%9F%98%80' + '/x.pas', TLspClient.PathToUri('C:\' + #$D83D#$DE00 + '\x.pas'),
    'un par de sustitutos entero si: el emoji en UTF-8');
end;

procedure TNombradorTests.CompositorConservaLosSaltosDeFuera;
const
  MIXTO = 'a'#13#10'b'#10'c'#13#10;
begin
  // CambiaLineasEnSuTexto (1.18.2): lo de fuera byte a byte, cada rama
  Assert.AreEqual('a'#13#10'b'#10'C'#13#10, CambiaLineasEnSuTexto(MIXTO, 2, 1, ['C'], #13#10),
    'otra linea cambiada: la LF de "b" sigue LF');
  Assert.AreEqual('a'#13#10'B'#10'c'#13#10, CambiaLineasEnSuTexto(MIXTO, 1, 1, ['B'], #13#10),
    'la linea cambiada conserva su salto');
  Assert.AreEqual('a'#13#10'b1'#13#10'b2'#10'c'#13#10,
    CambiaLineasEnSuTexto(MIXTO, 1, 1, ['b1', 'b2'], #13#10),
    'dentro de lo nuevo el dominante, al final el salto de lo que se va');
  Assert.AreEqual('a'#13#10'c'#13#10, CambiaLineasEnSuTexto(MIXTO, 1, 1, nil, #13#10),
    'borrar: la linea se va con su salto');
  Assert.AreEqual('a'#10'b', CambiaLineasEnSuTexto('a'#10'b'#13#10'c', 2, 1, nil, #13#10),
    'borrar la ultima de un texto sin salto final: sigue sin el');
  Assert.AreEqual('', CambiaLineasEnSuTexto('a', 0, 1, nil, #13#10), 'borrar todo');
  Assert.AreEqual('a'#13#10'x'#13#10'b'#10, CambiaLineasEnSuTexto('a'#13#10'b'#10, 1, 0, ['x'], #13#10),
    'insertar delante de una linea: lo nuevo con el dominante');
  Assert.AreEqual('a'#10'b'#13#10'x', CambiaLineasEnSuTexto('a'#10'b', 2, 0, ['x'], #13#10),
    'insertar detras de la ultima de un texto sin salto final: sigue sin el');
  Assert.AreEqual('a'#13'b'#13#10'C', CambiaLineasEnSuTexto('a'#13'b'#13#10'c', 2, 1, ['C'], #13#10),
    'un CR suelto tambien es un salto que se conserva');
  // EmpalmaEnSuTexto: un tramo de la vista en LF
  Assert.AreEqual('# T'#13#10'uno'#10'DOS'#13#10,
    EmpalmaEnSuTexto('# T'#13#10'uno'#10'dos'#13#10, 8, 3, 'DOS', #13#10), 'un trozo de una linea');
  Assert.AreEqual('a'#13#10#10'c', EmpalmaEnSuTexto('a'#13#10'b'#10'c', 2, 1, '', #13#10),
    'un trozo vacio deja la linea EN BLANCO, no la borra');
  Assert.AreEqual('a'#10'x'#13#10, EmpalmaEnSuTexto('a'#10, 2, 0, 'x'#10, #13#10),
    'anadir al final de un texto con salto final');
  Assert.AreEqual('aZc', EmpalmaEnSuTexto('a'#13#10'b'#10'c', 1, 3, 'Z', #13#10),
    'un tramo que cruza saltos se los lleva');
  // del revisor propio: lo que la edicion junta no se funde, lo igual de los
  // bordes no se toca, la nota vacia y un tramo fuera del texto
  Assert.AreEqual('a'#13#10#10'b'#10, CambiaLineasEnSuTexto('a'#13'X'#10#10'b'#10, 1, 1, nil, #10),
    'un CR suelto no se funde con el LF de la linea vacia de debajo');
  Assert.AreEqual('a'#13#10#10, UneConSusSaltos(['a', '', ''], [#13, #10, '']),
    'la inversa del troceador vuelve a trocearse igual');
  Assert.AreEqual(MIXTO, CambiaLineasEnSuTexto(MIXTO, 0, 2, ['a', 'b'], #13#10),
    'old == new no reescribe nada');
  Assert.AreEqual('a'#13#10'b'#10'x'#13#10'c'#13#10, CambiaLineasEnSuTexto(MIXTO, 1, 1, ['b', 'x'], #13#10),
    'anadir detras de una linea le deja su salto');
  Assert.AreEqual('A'#13#10'b'#10'c'#13#10, CambiaLineasEnSuTexto(MIXTO, 0, 3, ['A', 'b', 'c'], #13#10),
    'lo igual del FINAL del tramo tampoco se toca');
  Assert.AreEqual(#13#10'hola'#13#10, EmpalmaEnSuTexto('', 0, 0, #10'hola'#10, #13#10),
    'un texto vacio tiene una linea');
  Assert.WillRaise(
    procedure
    begin
      CambiaLineasEnSuTexto('a', 2, 0, ['x'], #13#10);
    end, EArgumentOutOfRangeException, 'un tramo fuera del texto');
  Assert.WillRaise(
    procedure
    begin
      CambiaLineasEnSuTexto('a'#10, 2, 0, ['x'], #13#10);
    end, EArgumentOutOfRangeException, 'detras de la fantasma no es un sitio');
end;

procedure TNombradorTests.ElTextoEnteroConLaReglaDeQuienCambiaLineas;
const
  MIXTO = 'a'#13#10'b'#10'c'#13#10;

  function Lista(const A: TArray<Integer>): string;
  begin
    Result := '';
    for var I in A do
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + I.ToString;
    end;
  end;

begin
  // LineasQueSeQuedan: el cambio mas corto, por contenido
  Assert.AreEqual('0,-1,2,3,-1', Lista(LineasQueSeQuedan(['a', 'b', 'c', 'd'], ['a', 'x', 'c', 'd', 'y'])),
    'una cambiada en medio y una al final');
  Assert.AreEqual('-1,0,1', Lista(LineasQueSeQuedan(['a', 'b', 'c'], ['c', 'a', 'b'])),
    'una que se mueve: se quedan las dos que siguen en orden');
  // ReescribeConSusSaltos (V35 de la 1.23), lo medido: un .dproj LF con una
  // linea CRLF y un bloque insertado con sLineBreak detras de "c"
  Assert.AreEqual('a'#10'B'#13#10'c'#10'x'#10'd'#10,
    ReescribeConSusSaltos('a'#10'B'#13#10'c'#10'd'#10, 'a'#10'B'#13#10'c'#13#10'x'#10'd'#10),
    'la de delante del bloque conserva su LF y lo nuevo toma el dominante');
  Assert.AreEqual('a'#10'X'#10'b'#13#10'c'#10'd'#10'Y'#10'e'#10,
    ReescribeConSusSaltos('a'#10'b'#13#10'c'#10'd'#10'e'#10,
      'a'#13#10'X'#10'b'#13#10'c'#10'd'#13#10'Y'#10'e'#10),
    'dos bloques lejos: lo de entre ellos, byte a byte (la CRLF de b sigue)');
  Assert.AreEqual(MIXTO, ReescribeConSusSaltos(MIXTO, 'a'#13#10'b'#13#10'c'#13#10),
    'las mismas lineas con otro salto: nada cambia');
  Assert.AreEqual('a'#13#10'B'#10'c'#13#10, ReescribeConSusSaltos(MIXTO, 'a'#13#10'B'#13#10'c'#13#10),
    'la linea cambiada conserva su salto, como en CambiaLineasEnSuTexto');
  Assert.AreEqual('a'#13#10'x'#13#10'b'#13#10, ReescribeConSusSaltos('a'#13#10'b'#13#10, 'a'#13#10'x'#13#10'b'#13#10),
    'un fichero CRLF, como siempre');
  Assert.AreEqual('a'#10'b'#10, ReescribeConSusSaltos('a'#10'b', 'a'#10'b'#13#10),
    'el salto final, como lo deja el nuevo: lo gana con el del fichero');
  Assert.AreEqual('a'#10'b', ReescribeConSusSaltos('a'#10'b'#10, 'a'#10'b'), '...y lo pierde');
  Assert.AreEqual('x'#13#10, ReescribeConSusSaltos('', 'x'#13#10), 'un fichero vacio, el nuevo tal cual');
  Assert.AreEqual('', ReescribeConSusSaltos(MIXTO, ''), 'todo fuera');
end;

procedure TEncodingTests.UbicacionDeLspLeeLasFormasDelMotor;
begin
  // EL lector de la primera ubicacion (Lsp.References.UbicacionDeLsp, punto
  // 6 de la 1.18.2): un objeto suelto, un array, un LocationLink, y la uri
  // canonica; sus dos gemelos leian cada uno la mitad
  var Uri: string;
  var Linea, Col: Integer;
  var V := TJSONObject.ParseJSONValue(
    '{"uri":"file:///C%3A/a/x.pas","range":{"start":{"line":4,"character":2}}}');
  try
    Assert.IsTrue(UbicacionDeLsp(V, Uri, Linea, Col), 'objeto suelto');
    Assert.AreEqual(4, Linea);
    Assert.AreEqual(2, Col);
    Assert.AreEqual(TLspClient.PathToUri('C:\a\x.pas'), Uri, 'la uri, canonica');
  finally
    V.Free;
  end;
  V := TJSONObject.ParseJSONValue(
    '[{"targetUri":"file:///C%3A/a/y.pas","targetSelectionRange":{"start":{"line":7,"character":0}}}]');
  try
    Assert.IsTrue(UbicacionDeLsp(V, Uri, Linea, Col), 'LocationLink en un array');
    Assert.AreEqual(7, Linea);
    Assert.AreEqual(TLspClient.PathToUri('C:\a\y.pas'), Uri);
  finally
    V.Free;
  end;
  V := TJSONObject.ParseJSONValue('{"uri":"file:///C%3A/a/z.pas"}');
  try
    Assert.IsFalse(UbicacionDeLsp(V, Uri, Linea, Col), 'sin linea: nada usable (lanzaba)');
  finally
    V.Free;
  end;
  V := TJSONObject.ParseJSONValue('[]');
  try
    Assert.IsFalse(UbicacionDeLsp(V, Uri, Linea, Col), 'array vacio');
  finally
    V.Free;
  end;
end;

{ El mojibake de un texto nuevo (Lsp.Patch.MojibakeLines): UTF-8 leido en la
  ANSI de la maquina, o en Latin-1, como lo lee la herramienta de un agente.
  Fuera de la 1252 la o con tilde leida en Latin-1 (C3 B3: U+00C3 U+00B3) no
  tiene byte ANSI y no se veia (medido el 24-oct-2026 con el servidor en la
  1251). }
procedure TEncodingTests.ElMojibakeDeLatin1SeVeEnCualquierPagina;
const
  LATIN1 = 'S := ''gestor' + #$00C3#$00B3 + 'n'';';
  EN_1251 = 'S := ''gestor' + #$0413#$0456 + 'n'';'; // C3 B3 leidos en la 1251
  RUSO = 'S := ''' + #$043F#$0440#$0438#$0432#$0435#$0442 + ''';';
begin
  for var P in [1252, 1251, 1253] do
  begin
    UsaPaginaAnsi(P);
    Assert.IsTrue(Length(MojibakeLines(LATIN1)) = 1, 'el de Latin-1 en la ' + IntToStr(P));
  end;
  UsaPaginaAnsi(1251);
  Assert.IsTrue(Length(MojibakeLines(EN_1251)) = 1, 'el de la propia 1251');
  Assert.IsTrue(Length(MojibakeLines(RUSO)) = 0, 'un texto ruso no lo es');
  Assert.IsTrue(Length(MojibakeLines('S := ''gesti' + #$00F3 + 'n'';')) = 0, 'una o con tilde no lo es');
end;

procedure TNombradorTests.ColumnaDelMotorYSuInversa;
const
  // a, enye, b, euro, c, un emoji (un par de sustitutos), d: la columna
  // UTF-16 y la del motor (bytes UTF-8); el 6 parte el emoji, y el 10 y el
  // 15 pasan del final
  COLS16: array [0 .. 9] of Integer = (0, 1, 2, 3, 4, 5, 6, 7, 8, 10);
  COLS8: array [0 .. 9] of Integer = (0, 1, 3, 4, 7, 8, 8, 12, 13, 15);
var
  L: string;
  I: Integer;
begin
  // la cuenta del motor es la de los BYTES UTF-8 de la linea (medido el
  // 22-oct-2026 con el motor solo: una enye +1, un euro +2, un emoji +2)
  L := 'a' + #$00F1 + 'b' + #$20AC + 'c' + #$D83D#$DE00 + 'd';
  for I := 0 to High(COLS16) do
    Assert.AreEqual(COLS8[I], TLspClient.ColumnaAlMotor(L, COLS16[I]), 'al motor desde ' + IntToStr(COLS16[I]));
  // ...y la inversa: cada columna que no parte un caracter vuelve a ser ella
  for I := 0 to High(COLS16) do
    if COLS16[I] <> 6 then
      Assert.AreEqual(COLS16[I], TLspClient.ColumnaDelMotor(L, COLS8[I]), 'del motor desde ' + IntToStr(COLS8[I]));
  // un byte de en medio de un caracter cuenta desde donde empieza
  Assert.AreEqual(1, TLspClient.ColumnaDelMotor(L, 2), 'en medio de la enye');
  Assert.AreEqual(3, TLspClient.ColumnaDelMotor(L, 6), 'en medio del euro');
  Assert.AreEqual(5, TLspClient.ColumnaDelMotor(L, 11), 'en medio del emoji');
  // en ASCII las dos cuentas son la misma; 0 o menos, tal cual; y sin linea,
  // lo que pasa del final sigue pasando lo mismo
  Assert.AreEqual(5, TLspClient.ColumnaAlMotor('abcdefg', 5), 'ASCII');
  Assert.AreEqual(5, TLspClient.ColumnaDelMotor('abcdefg', 5), 'ASCII de vuelta');
  Assert.AreEqual(-1, TLspClient.ColumnaAlMotor(L, -1), 'negativa');
  Assert.AreEqual(0, TLspClient.ColumnaDelMotor('', 0), 'linea vacia');
  Assert.AreEqual(4, TLspClient.ColumnaDelMotor('', 4), 'sin linea');
end;

initialization
  TDUnitX.RegisterTestFixture(TEncodingTests);
  TDUnitX.RegisterTestFixture(TNombradorTests);

end.
