unit LspTests.DesignerBin;

{ La forma de un designer (texto, flujo TPF0, recurso en disco) y la ida y
  vuelta binario <-> texto por la RTL, que es lo que hace el IDE en "Ver como
  texto" y al guardar. Un solo nombrador de la forma: antes habia cuatro. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDesignerBinTests = class
  public
    [Test] procedure TextoEsTexto;
    [Test] procedure TextoEnUtf16NoEsBinario;
    [Test] procedure Tpf0EsFlujo;
    [Test] procedure CabeceraDeRecursoEsElBinarioDeDisco;
    [Test] procedure IdaYVueltaPorLaRtl;
    [Test] procedure ElAcentoSaleComoNumeral;
    [Test] procedure FueraDeAnsiConBomEntraComoEnDcc;
    [Test] procedure SinBomSeLeeEnAnsiComoEnDcc;
    [Test] procedure BinarioDanadoDaMotivo;
    [Test] procedure CadaFormaLlegaATReader;
    [Test] procedure ElIdeNoTomaPorFormUnAncho;
    [Test]
    procedure LaLineaDeUnObjeto;
    [Test]
    procedure NombreConAcentoSoloConBom;
    [Test]
    procedure TrozosDeEstadoRespetaLasComillas;
    [Test]
    procedure ElJuezLeeEnLaCodificacionDelFichero;
    [Test]
    procedure ElJuezSinLineaYAlFinal;
  end;

implementation

uses
  Winapi.Windows, // GetACP: la ANSI con la que lee el parser de la RTL
  System.SysUtils,
  System.Classes,
  Lsp.DesignerBin,
  Lsp.DesignerForma,
  Lsp.Codificacion, // EncodeText: lo que cabe en la ANSI de ESTA maquina
  Lsp.Texts;

const
  FORM_TXT = 'object FormX: TFormX'#13#10 +
    '  Left = 0'#13#10 +
    '  Top = 0'#13#10 +
    '  Caption = ''Hola'''#13#10 +
    '  ClientHeight = 10'#13#10 +
    '  ClientWidth = 20'#13#10 +
    'end'#13#10;

// la ANSI de la maquina puede escribir ATexto? (EL codificador de la casa).
// Una prueba en 'cp1252' pide sus letras en la ANSI de ESTA maquina: en un
// Windows 1251 la o con tilde no cabe (revisor 3 de la noche, B-5)
function LaAnsiLaEscribe(const ATexto: string): Boolean;
begin
  try
    EncodeText(ATexto, ekAnsi);
    Result := True;
  except
    Result := False;
  end;
end;

function B(const A: array of Byte): TBytes;
begin
  SetLength(Result, Length(A));
  if Length(A) > 0 then
    Move(A[0], Result[0], Length(A));
end;

procedure TDesignerBinTests.TextoEsTexto;
begin
  Assert.IsTrue(DesignerShapeOf(TEncoding.ASCII.GetBytes(FORM_TXT)) = dsText);
  Assert.IsFalse(IsBinaryDesignerBytes(TEncoding.ASCII.GetBytes(FORM_TXT)));
end;

procedure TDesignerBinTests.TextoEnUtf16NoEsBinario;
begin
  // Empieza por FF FE, y "empieza por $FF" tomaba esto por binario (24-sep-2026)
  Assert.IsTrue(DesignerShapeOf(B([$FF, $FE, Ord('o'), 0, Ord('b'), 0])) = dsText);
  Assert.IsFalse(IsBinaryDesignerBytes(B([$FF, $FE, Ord('o'), 0, Ord('b'), 0])));
end;

procedure TDesignerBinTests.Tpf0EsFlujo;
begin
  Assert.IsTrue(DesignerShapeOf(B([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 5])) = dsTpf0);
  Assert.IsTrue(IsBinaryDesignerBytes(B([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 5])));
end;

procedure TDesignerBinTests.CabeceraDeRecursoEsElBinarioDeDisco;
begin
  Assert.IsTrue(DesignerShapeOf(B([$FF, $0A, $00, Ord('T'), Ord('X'), 0])) = dsResource);
  Assert.IsTrue(IsBinaryDesignerBytes(B([$FF, $0A, $00, Ord('T'), Ord('X'), 0])));
end;

procedure TDesignerBinTests.IdaYVueltaPorLaRtl;
var
  Bin: TBytes;
  Txt: string;
begin
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.ASCII.GetBytes(FORM_TXT), Bin), 'texto -> binario sin error');
  Assert.IsTrue(DesignerShapeOf(Bin) = dsResource, 'lo que escribe to-binary es la forma de disco del IDE');
  Assert.AreEqual('', DesignerBinaryToText(Bin, Txt), 'binario -> texto sin error');
  Assert.AreEqual(FORM_TXT, Txt, 'la ida y vuelta devuelve el mismo texto');
end;

procedure TDesignerBinTests.ElAcentoSaleComoNumeral;
var
  Bin: TBytes;
  Txt: string;
  I: Integer;
begin
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.ASCII.GetBytes(
    'object FormA: TFormA'#13#10'  Caption = ''Configuraci''#243''n'''#13#10'end'#13#10), Bin));
  Assert.AreEqual('', DesignerBinaryToText(Bin, Txt));
  Assert.IsTrue(Pos('''Configuraci''#243''n''', Txt) > 0, 'el acento vuelve como #243: ' + Txt);
  for I := 1 to Length(Txt) do
    Assert.IsTrue(Ord(Txt[I]) < 128, 'el texto convertido es ASCII puro');
end;

procedure TDesignerBinTests.FueraDeAnsiConBomEntraComoEnDcc;
var
  Bin: TBytes;
  Txt: string;
begin
  // M2 (punto 4 de la 1.18.2): un form en UTF-8 con BOM con caracteres fuera
  // de la ANSI en crudo. dcc lo compila entero (medido el 13-oct: el exe lleva
  // 'ok ✔ Ж' como vaUTF8String) y lint lo da por limpio; to-binary lo negaba
  // (DSGN-045) porque lo recodificaba a ANSI. Ahora entra, y vuelve como lo
  // escribe el IDE: #10004 y #1046
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(
    'object FormA: TFormA'#13#10'  Caption = ''ok ' + Chr($2714) + ' ' + Chr($0416) + ''''#13#10'end'#13#10), Bin),
    'un UTF-8 con BOM fuera de la ANSI entra en el binario, como en dcc');
  Assert.AreEqual('', DesignerBinaryToText(Bin, Txt));
  Assert.IsTrue(Pos('''ok ''#10004'' ''#1046', Txt) > 0, 'el texto entero, como #N: ' + Txt);
end;

procedure TDesignerBinTests.SinBomSeLeeEnAnsiComoEnDcc;
var
  Bin: TBytes;
  Txt: string;
begin
  // ...y uno en UTF-8 SIN BOM: dcc lo lee en la ANSI de la maquina (medido el
  // 13-oct: 'Configuración' -C3 B3- sale con la ó partida en dos letras en el
  // exe). Por el servidor ya salia asi (el llamador lo decodificaba en ANSI);
  // ahora lo decide el parser y no como decodifique quien llama: una guarda.
  // Solo se mide en 1252: en otra ANSI las dos letras son otras, y en 65001 la
  // ANSI es UTF-8
  if GetACP <> 1252 then
  begin
    Assert.Pass('la ANSI de esta maquina no es 1252');
    Exit;
  end;
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.UTF8.GetBytes(
    'object FormA: TFormA'#13#10'  Caption = ''Configuraci' + Chr($F3) + 'n'''#13#10'end'#13#10), Bin));
  Assert.AreEqual('', DesignerBinaryToText(Bin, Txt));
  Assert.IsTrue(Pos('''Configuraci''#195#179''n''', Txt) > 0, 'los dos bytes, como ANSI (como dcc): ' + Txt);
end;

procedure TDesignerBinTests.BinarioDanadoDaMotivo;
var
  Txt: string;
begin
  Assert.AreNotEqual('', DesignerBinaryToText(
    B([$FF, $0A, $00, Ord('T'), Ord('R'), Ord('O'), Ord('T'), Ord('O'), 0, $30, $10, $10, 0, 0, 0,
       Ord('T'), Ord('P'), Ord('F'), Ord('0'), Ord('b'), Ord('a'), Ord('s'), Ord('u'), Ord('r'), Ord('a')]), Txt),
    'un binario roto devuelve el motivo, no una excepcion');
end;

// el texto que sale de DesignerAFlujo leido como lo leeria TReader
function TextoDelFlujo(const AFichero: TBytes): string;
var
  Entrada, Flujo, Txt: TMemoryStream;
  Bytes: TBytes;
begin
  Entrada := TMemoryStream.Create;
  Flujo := TMemoryStream.Create;
  Txt := TMemoryStream.Create;
  try
    Entrada.WriteBuffer(AFichero[0], Length(AFichero));
    DesignerAFlujo(Entrada, Flujo);
    Flujo.Position := 0;
    ObjectBinaryToText(Flujo, Txt);
    SetLength(Bytes, Txt.Size);
    Move(Txt.Memory^, Bytes[0], Txt.Size);
    Result := TEncoding.UTF8.GetString(Bytes);
  finally
    Txt.Free;
    Flujo.Free;
    Entrada.Free;
  end;
end;

procedure TDesignerBinTests.CadaFormaLlegaATReader;
var
  Bin, Tpf0: TBytes;
  S: TMemoryStream;
begin
  // El renderizador le daba a TReader el binario del IDE tal cual:
  // TestStreamFormat lo llama binario y nadie se saltaba la cabecera del
  // recurso ("Invalid stream format" en preview, 7-oct-2026)
  Assert.AreEqual('', DesignerTextToBinary(TEncoding.ASCII.GetBytes(FORM_TXT), Bin));
  S := TMemoryStream.Create;
  try
    S.WriteBuffer(Bin[0], Length(Bin));
    S.Position := 0;
    S.ReadResHeader;
    SetLength(Tpf0, S.Size - S.Position);
    S.ReadBuffer(Tpf0[0], Length(Tpf0));
  finally
    S.Free;
  end;
  Assert.IsTrue(DesignerShapeOf(Tpf0) = dsTpf0, 'tras la cabecera, el flujo a pelo');
  Assert.AreEqual(FORM_TXT, TextoDelFlujo(TEncoding.ASCII.GetBytes(FORM_TXT)), 'el texto');
  Assert.AreEqual(FORM_TXT, TextoDelFlujo(Tpf0), 'el flujo TPF0');
  Assert.AreEqual(FORM_TXT, TextoDelFlujo(Bin), 'el recurso que escribe el IDE en disco');
  // un texto que el editor del IDE guardo en UTF-16 NO lo carga el IDE: su
  // disenador dice "Invalid stream format" (medido el 24-oct-2026). TParser lo
  // niega tal cual (SAnsiUTF8Expected); se le daba convertido a UTF-8 (segunda
  // revision de la 1.17.0), y lint y preview decian lo contrario que el IDE
  // (A28 de la 1.23)
  Assert.WillRaise(
    procedure
    begin
      TextoDelFlujo(TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(FORM_TXT));
    end, EParserError, 'el texto en UTF-16 LE');
  Assert.WillRaise(
    procedure
    begin
      TextoDelFlujo(TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(FORM_TXT));
    end, EParserError, 'el texto en UTF-16 BE');
end;

procedure TDesignerBinTests.ElIdeNoTomaPorFormUnAncho;
begin
  // el juez de la casa (TestStreamFormat): un texto en UTF-16 o UTF-32 no lo
  // toma por un form de texto, como el disenador del IDE (A28 de la 1.23)
  Assert.IsTrue(ElIdeNoLoTomaPorForm(TEncoding.Unicode.GetPreamble +
    TEncoding.Unicode.GetBytes(FORM_TXT)), 'UTF-16 LE');
  Assert.IsTrue(ElIdeNoLoTomaPorForm(TEncoding.BigEndianUnicode.GetPreamble +
    TEncoding.BigEndianUnicode.GetBytes(FORM_TXT)), 'UTF-16 BE');
  Assert.IsTrue(ElIdeNoLoTomaPorForm(B([$FF, $FE, 0, 0, Ord('o'), 0, 0, 0])), 'UTF-32 LE');
  Assert.IsTrue(ElIdeNoLoTomaPorForm(B([0, 0, $FE, $FF, 0, 0, 0, Ord('o')])), 'UTF-32 BE');
  // ...y lo que si carga, o no es de texto, no
  Assert.IsFalse(ElIdeNoLoTomaPorForm(TEncoding.ASCII.GetBytes(FORM_TXT)), 'ASCII');
  Assert.IsFalse(ElIdeNoLoTomaPorForm(TEncoding.UTF8.GetPreamble +
    TEncoding.UTF8.GetBytes(FORM_TXT)), 'UTF-8 con BOM');
  Assert.IsFalse(ElIdeNoLoTomaPorForm(B([$FF, $0A, $00, Ord('T')])), 'el binario del IDE (recurso)');
  Assert.IsFalse(ElIdeNoLoTomaPorForm(B([Ord('T'), Ord('P'), Ord('F'), Ord('0')])), 'el flujo TPF0');
  Assert.IsFalse(ElIdeNoLoTomaPorForm(B([$FF, $FE])), 'menos de cuatro bytes');
end;

procedure TDesignerBinTests.LaLineaDeUnObjeto;
var
  K, N, C: string;
begin
  // LA lectura de 'object Nombre: TClase' (antes seis regex con \w ASCII:
  // un nombre con acento o un objeto sin nombre descolocaban el anidamiento)
  Assert.IsTrue(LineaDeObjeto('object Form1: TForm1', K, N, C));
  Assert.AreEqual('object', K);
  Assert.AreEqual('Form1', N);
  Assert.AreEqual('TForm1', C);
  Assert.IsTrue(LineaDeObjeto('  inherited Marco2: TMarco2 [0]', K, N, C), 'con su indice');
  Assert.AreEqual('inherited', K);
  Assert.AreEqual('Marco2', N);
  Assert.AreEqual('TMarco2', C);
  Assert.IsTrue(LineaDeObjeto('object TMemo', K, N, C), 'sin nombre');
  Assert.AreEqual('', N);
  Assert.AreEqual('TMemo', C);
  Assert.IsTrue(LineaDeObjeto('object lblDirecci'#$F3'n: TLabel', K, N, C), 'con acento');
  Assert.AreEqual('lblDirecci'#$F3'n', N);
  Assert.AreEqual('TLabel', C);
  Assert.IsTrue(LineaDeObjeto('inline Marco1: TMarco', K, N, C));
  Assert.AreEqual('inline', K);
  Assert.IsFalse(LineaDeObjeto('Inline = True', K, N, C), 'una propiedad no es un objeto');
  Assert.IsFalse(LineaDeObjeto('objects = 3', K, N, C));
  Assert.IsFalse(LineaDeObjeto('Caption = ''object x: y''', K, N, C));
end;

procedure TDesignerBinTests.NombreConAcentoSoloConBom;
var
  R: string;
begin
  // un nombre ASCII entra siempre; uno con acento, solo con el form en UTF-8
  // con BOM (TParser) y la unidad con BOM o en CP1252 (dcc): medido el
  // 7-oct-2026, sin eso el proyecto no compilaba o el campo no casaba con su
  // componente, y las dos cosas decian OK
  Assert.AreEqual('', NombreQueElFicheroNoLee('LblCalle', 'U.dfm', 'utf8', 'U.pas', 'utf8'), 'ASCII');
  R := NombreQueElFicheroNoLee('LblDirecci'#$F3'n', 'U.dfm', 'utf8', 'U.pas', 'utf8-bom');
  Assert.IsTrue(R.StartsWith('[DSGN-111') and R.Contains('U.dfm'), 'el form sin BOM: ' + R);
  if LaAnsiLaEscribe(#$F3) then
  begin
    R := NombreQueElFicheroNoLee('LblDirecci'#$F3'n', 'U.dfm', 'cp1252', 'U.pas', 'utf8-bom');
    Assert.IsTrue(R.Contains('U.dfm'), 'en CP1252 TParser tampoco lo lee: ' + R);
  end;
  R := NombreQueElFicheroNoLee('LblDirecci'#$F3'n', 'U.dfm', 'utf8-bom', 'U.pas', 'utf8');
  Assert.IsTrue(R.Contains('U.pas') and not R.Contains('U.dfm'), 'la unidad en UTF-8 sin BOM: ' + R);
  if LaAnsiLaEscribe(#$F3) then
    Assert.AreEqual('', NombreQueElFicheroNoLee('LblDirecci'#$F3'n', 'U.dfm', 'utf8-bom', 'U.pas', 'cp1252'),
      'una unidad CP1252 la lee dcc');
  Assert.AreEqual('', NombreQueElFicheroNoLee('LblDirecci'#$F3'n', 'U.dfm', 'utf8-bom', 'U.pas', 'utf8-bom'),
    'los dos con BOM');
end;

{ LA sintaxis de una lista de props/state (revisor 2 de la noche, M-A): un ';'
  dentro de un literal no parte, y una comilla que no EMPIEZA el valor es una
  letra - se tragaba el resto de la lista sin decirlo. }
procedure TDesignerBinTests.TrozosDeEstadoRespetaLasComillas;
var
  T: TArray<string>;
  R: string;
begin
  Assert.AreEqual('', TrozosDeEstado('Caption=''a;b'';Width=10', T));
  Assert.AreEqual(2, Integer(Length(T)), 'un ; dentro del literal no parte');
  Assert.AreEqual('Caption=''a;b''', T[0]);
  Assert.AreEqual('', TrozosDeEstado('Caption=Don''t save;Width=100', T));
  Assert.AreEqual(2, Integer(Length(T)), 'una comilla que no empieza el valor es una letra');
  Assert.AreEqual('Caption=Don''t save', T[0]);
  Assert.AreEqual('Width=100', T[1]);
  Assert.AreEqual('', TrozosDeEstado('Label1.Caption=It''s;CheckBox1.IsChecked=True', T));
  Assert.AreEqual(2, Integer(Length(T)), 'el state de la 1.17.0: dos estados');
  Assert.AreEqual('', TrozosDeEstado('Caption=  ''it''''s;x'';W=1', T));
  Assert.AreEqual(2, Integer(Length(T)), 'blancos antes de la comilla y una comilla doblada dentro');
  Assert.AreEqual('Caption=  ''it''''s;x''', T[0]);
  Assert.AreEqual('', TrozosDeEstado(' ; ;A=1;', T));
  Assert.AreEqual(1, Integer(Length(T)), 'sin los vacios');
  Assert.AreEqual('', TrozosDeEstado('Caption=#39''a;b'';W=1', T));
  Assert.AreEqual(2, Integer(Length(T)), 'un literal que empieza por #N tampoco parte (B-4)');
  R := TrozosDeEstado('Caption=''abierta;W=1', T);
  Assert.IsTrue(R.StartsWith('[DSGN-134'), 'un literal sin cerrar: ' + R);
  Assert.AreEqual(0, Integer(Length(T)), 'y ningun trozo');
end;

{ El juez juzga los bytes en la codificacion DEL FICHERO: un identificador no
  ASCII lo lee TParser solo en UTF-8 con BOM (medido el 7-oct). Con la
  codificacion ignorada todo pasaba (revisor 2 de la noche, B-11: la parte
  critica, los acentos, sin una sola prueba). }
procedure TDesignerBinTests.ElJuezLeeEnLaCodificacionDelFichero;
const
  FORM_ACENTO = 'object FormX: TFormX'#13#10 +
    '  object LblDirecci'#$F3'n: TLabel'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  Linea: Integer;
  Cita: string;
begin
  Assert.AreEqual('', ParserDeForm(FORM_ACENTO, 'utf8-bom', Linea, Cita), 'con BOM se lee');
  if LaAnsiLaEscribe(#$F3) then
  begin
    Assert.AreNotEqual('', ParserDeForm(FORM_ACENTO, 'cp1252', Linea, Cita), 'en ANSI no');
    Assert.AreEqual(2, Linea, 'y nombra la linea del objeto');
  end;
  Assert.AreNotEqual('', ParserDeForm(FORM_ACENTO, 'utf8', Linea, Cita), 'ni en UTF-8 sin BOM');
end;

{ Las citas del juez (revisor 2 de la noche, B-1/B-2/B-4) }
procedure TDesignerBinTests.ElJuezSinLineaYAlFinal;
var
  Linea: Integer;
  Cita, SinEnd, SoloCR: string;
begin
  // un numero que no cabe: TokenInt lanza EConvertError, sin linea
  Assert.AreNotEqual('', ParserDeForm('object FormX: TFormX'#13#10 +
    '  Tag = 99999999999999999999'#13#10'end'#13#10, 'utf8-bom', Linea, Cita));
  Assert.AreEqual(MsgText(SF_DSGN_PARSER_SIN_LINEA), Cita, 'sin linea no es el fin del fichero');
  // le falta el end final: con el salto de la ultima linea, el parser nombra la
  // de despues (fin del fichero, venga de un texto o de unas lineas unidas: B-2);
  // sin el salto nombra la ultima, y esa es la cita (medido)
  SinEnd := 'object FormX: TFormX'#13#10'  Left = 0'#13#10;
  Assert.AreNotEqual('', ParserDeForm(SinEnd, 'utf8-bom', Linea, Cita));
  Assert.AreEqual(MsgText(SF_DSGN_PARSER_FIN_DE_FICHERO), Cita, 'con el salto final');
  Assert.AreNotEqual('', ParserDeForm(SinEnd.TrimRight, 'utf8-bom', Linea, Cita));
  Assert.AreEqual('Left = 0', Cita, 'sin el salto final: la ultima linea, la que nombra');
  // los bytes del disco: un form de solo CR es UNA linea para TParser, y de
  // mas de 4 KB no la lee (SLineTooLong); unido con CRLF pasaba
  SoloCR := 'object FormX: TFormX'#13;
  for var I := 1 to 500 do
    SoloCR := SoloCR + '  Tag = 1'#13;
  SoloCR := SoloCR + 'end'#13;
  Assert.AreNotEqual('', ParserDeForm(SoloCR, 'utf8-bom', Linea, Cita), 'solo CR, mas de 4 KB');
  Assert.AreEqual('', ParserDeForm(SoloCR.Replace(#13, #13#10), 'utf8-bom', Linea, Cita),
    'el mismo con CRLF se lee');
end;

initialization
  TDUnitX.RegisterTestFixture(TDesignerBinTests);

end.
