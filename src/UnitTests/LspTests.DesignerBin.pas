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
    [Test] procedure FueraDeAnsiSeRechaza;
    [Test] procedure BinarioDanadoDaMotivo;
    [Test]
    procedure LaLineaDeUnObjeto;
  end;

implementation

uses
  System.SysUtils,
  Lsp.DesignerBin;

const
  FORM_TXT = 'object FormX: TFormX'#13#10 +
    '  Left = 0'#13#10 +
    '  Top = 0'#13#10 +
    '  Caption = ''Hola'''#13#10 +
    '  ClientHeight = 10'#13#10 +
    '  ClientWidth = 20'#13#10 +
    'end'#13#10;

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
  Assert.AreEqual('', DesignerTextToBinary(FORM_TXT, Bin), 'texto -> binario sin error');
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
  Assert.AreEqual('', DesignerTextToBinary(
    'object FormA: TFormA'#13#10'  Caption = ''Configuraci''#243''n'''#13#10'end'#13#10, Bin));
  Assert.AreEqual('', DesignerBinaryToText(Bin, Txt));
  Assert.IsTrue(Pos('''Configuraci''#243''n''', Txt) > 0, 'el acento vuelve como #243: ' + Txt);
  for I := 1 to Length(Txt) do
    Assert.IsTrue(Ord(Txt[I]) < 128, 'el texto convertido es ASCII puro');
end;

procedure TDesignerBinTests.FueraDeAnsiSeRechaza;
var
  Bin: TBytes;
begin
  Assert.AreNotEqual('', DesignerTextToBinary(
    'object FormA: TFormA'#13#10'  Caption = ''ok ' + Chr($2714) + ''''#13#10'end'#13#10, Bin),
    'un caracter fuera de ANSI en crudo no entra en el binario');
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

initialization
  TDUnitX.RegisterTestFixture(TDesignerBinTests);

end.
