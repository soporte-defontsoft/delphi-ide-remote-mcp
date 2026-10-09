unit LspTests.DesignerEdit;

{ delphi_designer insert / set / delete (1.17.0): lo que se mide sobre
  TEXTOS, sin disco ni tabla del IDE - el analizador de impacto (comun a
  delete y set de Name), los planes de borrado y de renombrado, los cuerpos
  que apunta el lector de Pascal, el rango de una propiedad en TStyleDoc y
  los escritores del formato. Lo que pasa por la tabla del Delphi activo y
  por el disco (insert, set de una propiedad, el todo o nada) lo mide
  tests/test_designer_edit.py contra el servidor, con preview de oraculo. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDesignerEditTests = class
  public
    [Test] procedure CuerposDelImplementation;
    [Test] procedure MiembrosConSuFin;
    [Test] procedure ImpactoDeUnContenedor;
    [Test] procedure BorradoSeNiegaConCuerpo;
    [Test] procedure BorradoQuitaLoVacioYLoSuyo;
    [Test] procedure CampoCompartidoSoloSuNombre;
    [Test] procedure NombreNoSeConfundeConOtro;
    [Test] procedure RenombreCabeceraReferenciasYCampo;
    [Test] procedure PropiedadNoEntraEnColecciones;
    [Test] procedure PropiedadPartidaSeReescribeEntera;
    [Test] procedure LiteralComoElIde;
    [Test] procedure LiteralContraLaRtl;
    [Test] procedure DesciendeYJuez;
    [Test] procedure LaMasParecida;
    [Test] procedure TextoSigueAlNombreDelFuente;
    [Test] procedure LineaCompartidaNoSeBorra;
    [Test] procedure DosCamposDeUnaLinea;
    [Test] procedure ConstantesDelFuente;
    [Test] procedure ValorPorLaBaseDeSuTipo;
    [Test] procedure LineasDelFormComoLasEscribeElIde;
    [Test] procedure ReferenciaSoloSiGuardaUnComponente;
    [Test] procedure NombresDelFrameEnLinea;
    [Test] procedure MetodoPorSusBordes;
    [Test] procedure ComentarioAntesDelBeginEsCuerpo;
    [Test] procedure CampoConDirectivaSeNiega;
    [Test] procedure EnumeradoYConjuntoComoLosLee;
    [Test] procedure EstilosDelConstructor;
    [Test]
    procedure HechosDelFuenteDeLaInstalacion;
    [Test]
    procedure RenombreConservaElOrden;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Lsp.Styles,
  Lsp.Patch,
  Lsp.Pascal,
  Lsp.PascalDecl,
  Lsp.DesignerBin,
  Lsp.DesignerForma,
  Lsp.DesignerMeta,
  Lsp.DesignerMetaGen,
  Lsp.DesignerEdit,
  System.IOUtils,
  Lsp.Discovery;

type
  // un componente con una cadena publicada: lo que la RTL escribe de el
  // (WriteComponent y ObjectBinaryToText, los escritores del IDE) es la
  // referencia de TrozosDeLiteral y LineasDePropiedad
  TConLiteral = class(TComponent)
  private
    FTexto: string;
  published
    property Texto: string read FTexto write FTexto;
  end;

const
  CRLF = #13#10;
  // el form: un panel con dos botones, un edit que comparte manejador con
  // el segundo, y una etiqueta que apunta a el
  FORM_DFM =
    'object Form1: TForm1' + CRLF +
    '  Caption = ''Form1''' + CRLF +
    '  ClientHeight = 300' + CRLF +
    '  ClientWidth = 400' + CRLF +
    '  object Panel1: TPanel' + CRLF +
    '    Left = 8' + CRLF +
    '    Top = 8' + CRLF +
    '    Width = 200' + CRLF +
    '    Height = 100' + CRLF +
    '    Caption = ''Panel1''' + CRLF +
    '    TabOrder = 0' + CRLF +
    '    object Button1: TButton' + CRLF +
    '      Left = 10' + CRLF +
    '      Top = 10' + CRLF +
    '      Caption = ''Button1''' + CRLF +
    '      TabOrder = 0' + CRLF +
    '      OnClick = Button1Click' + CRLF +
    '    end' + CRLF +
    '    object Button2: TButton' + CRLF +
    '      Left = 10' + CRLF +
    '      Top = 40' + CRLF +
    '      Caption = ''Button2''' + CRLF +
    '      TabOrder = 1' + CRLF +
    '      OnClick = Compartido' + CRLF +
    '    end' + CRLF +
    '  end' + CRLF +
    '  object Edit1: TEdit' + CRLF +
    '    Left = 220' + CRLF +
    '    Top = 8' + CRLF +
    '    TabOrder = 1' + CRLF +
    '    Text = ''Edit1''' + CRLF +
    '    OnChange = Compartido' + CRLF +
    '  end' + CRLF +
    '  object Label1: TLabel' + CRLF +
    '    Left = 220' + CRLF +
    '    Top = 40' + CRLF +
    '    Caption = ''Label1''' + CRLF +
    '    FocusControl = Button2' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
  // su unidad: un manejador con cuerpo, uno compartido, uno vacio y un
  // metodo que no es manejador pero lleva el nombre del panel
  FORM_PAS =
    'unit Unit1;' + CRLF +
    '' + CRLF +
    'interface' + CRLF +
    '' + CRLF +
    'uses' + CRLF +
    '  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, System.Classes, Vcl.Controls;' + CRLF +
    '' + CRLF +
    'type' + CRLF +
    '  TForm1 = class(TForm)' + CRLF +
    '    Panel1: TPanel;' + CRLF +
    '    Button1: TButton;' + CRLF +
    '    Button2: TButton;' + CRLF +
    '    Edit1: TEdit;' + CRLF +
    '    Label1: TLabel;' + CRLF +
    '    procedure Button1Click(Sender: TObject);' + CRLF +
    '    procedure Compartido(Sender: TObject);' + CRLF +
    '    procedure Button2Vacio(Sender: TObject);' + CRLF +
    '  private' + CRLF +
    '    procedure RefrescaPanel1;' + CRLF +
    '  end;' + CRLF +
    '' + CRLF +
    'var' + CRLF +
    '  Form1: TForm1;' + CRLF +
    '' + CRLF +
    'implementation' + CRLF +
    '' + CRLF +
    '{$R *.dfm}' + CRLF +
    '' + CRLF +
    'procedure TForm1.Button1Click(Sender: TObject);' + CRLF +
    'begin' + CRLF +
    '  Panel1.Caption := ''hola'';' + CRLF +
    'end;' + CRLF +
    '' + CRLF +
    'procedure TForm1.Compartido(Sender: TObject);' + CRLF +
    'begin' + CRLF +
    '  Edit1.Text := '''';' + CRLF +
    'end;' + CRLF +
    '' + CRLF +
    'procedure TForm1.Button2Vacio(Sender: TObject);' + CRLF +
    'begin' + CRLF +
    '' + CRLF +
    'end;' + CRLF +
    '' + CRLF +
    'procedure TForm1.RefrescaPanel1;' + CRLF +
    'begin' + CRLF +
    '  Button2.Enabled := True;' + CRLF +
    'end;' + CRLF +
    '' + CRLF +
    'end.' + CRLF;

function Metodo(const AImp: TImpacto; const ANombre: string; out AM: TMetodoPropio): Boolean;
begin
  for var M in AImp.Metodos do
    if M.Nombre = ANombre then
    begin
      AM := M;
      Exit(True);
    end;
  Result := False;
end;

function Nombres(const AImp: TImpacto): string;
begin
  Result := '';
  for var M in AImp.Metodos do
    Result := Result + M.Nombre + ';';
end;

procedure TDesignerEditTests.CuerposDelImplementation;
var
  U: TUnidadPas;
  L: TArray<string>;
begin
  L := SplitToLines(FORM_PAS);
  U := LeeFuentePascal(FORM_PAS);
  try
    Assert.AreEqual<Integer>(4, Length(U.Cuerpos), 'las cuatro rutinas con cuerpo');
    Assert.AreEqual('TForm1.Button1Click', U.Cuerpos[0].Nombre);
    Assert.AreEqual('procedure TForm1.Button1Click(Sender: TObject);', L[U.Cuerpos[0].Linea]);
    Assert.AreEqual('end;', L[U.Cuerpos[0].LineaFin]);
    Assert.AreEqual('Panel1.Caption := ''hola'';',
      Trim(Copy(FORM_PAS, U.Cuerpos[0].CuerpoIni, U.Cuerpos[0].CuerpoFin - U.Cuerpos[0].CuerpoIni + 1)));
    // el vacio no tiene nada entre begin y end; el ';' de detras es suyo
    Assert.AreEqual('TForm1.Button2Vacio', U.Cuerpos[2].Nombre);
    Assert.AreEqual('', Trim(Copy(FORM_PAS, U.Cuerpos[2].CuerpoIni, U.Cuerpos[2].CuerpoFin - U.Cuerpos[2].CuerpoIni + 1)));
    Assert.AreEqual(';', FORM_PAS[U.Cuerpos[2].PosFin]);
    Assert.AreEqual('p', FORM_PAS[U.Cuerpos[2].PosIni]);
    Assert.IsFalse(U.Cuerpos[2].ConLocales);
  finally
    U.Free;
  end;
end;

procedure TDesignerEditTests.MiembrosConSuFin;
var
  U: TUnidadPas;
  L: TArray<string>;
  T: TTipoPas;
begin
  L := SplitToLines(FORM_PAS);
  U := LeeFuentePascal(FORM_PAS);
  try
    T := U.Clase('TForm1');
    Assert.IsNotNull(T);
    for var C in T.Campos do
      Assert.AreEqual(C.LineaIni, C.LineaFin, C.Nombre + ': una linea');
    for var R in T.Rutinas do
    begin
      Assert.AreEqual(R.LineaIni, R.LineaFin, R.Nombre);
      Assert.IsTrue(L[R.LineaIni].Contains('procedure ' + R.Nombre), L[R.LineaIni]);
    end;
  finally
    U.Free;
  end;
end;

procedure TDesignerEditTests.ImpactoDeUnContenedor;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  M: TMetodoPropio;
begin
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    Imp := AnalizaImpacto(Doc, Doc.ObjetoDeNombre('Panel1'), False, FORM_PAS, 'Unit1.pas');
  finally
    Doc.Free;
  end;
  Assert.AreEqual('Panel1,Button1,Button2', string.Join(',', Imp.Nombres));
  // la etiqueta de FUERA del panel que apunta a uno de dentro
  Assert.AreEqual<Integer>(1, Length(Imp.Referencias));
  Assert.AreEqual<Integer>(37, Imp.Referencias[0]);
  Assert.AreEqual<Integer>(3, Length(Imp.Campos));
  Assert.AreEqual('Button1Click;Compartido;Button2Vacio;RefrescaPanel1;', Nombres(Imp));
  Assert.IsTrue(Metodo(Imp, 'Button1Click', M));
  Assert.AreEqual('Button1.OnClick', M.Atado);
  Assert.AreEqual('', M.Compartido, 'exclusivo');
  Assert.IsTrue(M.ConCuerpo);
  Assert.AreEqual<Integer>(29, M.Linea);
  Assert.IsTrue(Metodo(Imp, 'Compartido', M));
  Assert.Contains(M.Compartido, 'Edit1.OnChange', 'lo ata uno de fuera: compartido');
  Assert.IsTrue(Metodo(Imp, 'Button2Vacio', M));
  Assert.IsTrue(M.PorNombre);
  Assert.IsFalse(M.ConCuerpo);
  Assert.IsTrue(Metodo(Imp, 'RefrescaPanel1', M));
  Assert.AreEqual('', M.Atado, 'no lo ata nadie: va por su nombre');
  Assert.IsTrue(M.ConCuerpo);
  // lo que usa el codigo se lista (los campos no)
  Assert.AreEqual('Unit1.pas:31: Panel1.Caption := ''hola'';|Unit1.pas:46: Button2.Enabled := True;',
    string.Join('|', Imp.Usos));
end;

procedure TDesignerEditTests.BorradoSeNiegaConCuerpo;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R: string;
begin
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Panel1'), FORM_PAS, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.StartsWith('[DSGN-086 DENIED]', R);
  Assert.Contains(R, 'Button1Click (Unit1.pas:29, Button1.OnClick)');
  Assert.Contains(R, 'RefrescaPanel1 (Unit1.pas:44, named after it)');
  Assert.DoesNotContain(R, 'Button2Vacio', 'el vacio no bloquea');
  Assert.DoesNotContain(R, 'Compartido', 'el compartido no bloquea');
  Assert.AreEqual(FORM_PAS, Pas, 'nada escrito');
end;

procedure TDesignerEditTests.BorradoQuitaLoVacioYLoSuyo;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R: string;
begin
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'), FORM_PAS, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  // el form: su bloque y la linea que lo nombraba
  Assert.DoesNotContain(Dfm, 'Button2');
  Assert.Contains(Dfm, '    object Button1: TButton');
  Assert.Contains(Dfm, '    Caption = ''Label1''' + CRLF + '  end');
  // la unidad: su campo y su manejador vacio (declaracion, cuerpo y la linea
  // en blanco de delante); el compartido se queda, y el uso tambien
  Assert.Contains(Pas, '    Button1: TButton;' + CRLF + '    Edit1: TEdit;');
  Assert.DoesNotContain(Pas, 'Button2Vacio');
  Assert.Contains(Pas, '    procedure Compartido(Sender: TObject);' + CRLF + '  private');
  Assert.Contains(Pas, '  Edit1.Text := '''';' + CRLF + 'end;' + CRLF + CRLF +
    'procedure TForm1.RefrescaPanel1;');
  Assert.Contains(Pas, 'Button2.Enabled');
  Assert.AreEqual('Unit1.pas:46: Button2.Enabled := True;', string.Join('|', Imp.Usos));
  for var M in Imp.Metodos do
    Assert.AreEqual(M.Nombre = 'Button2Vacio', M.SeBorra, M.Nombre);
end;

procedure TDesignerEditTests.CampoCompartidoSoloSuNombre;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R, Junto: string;
begin
  Junto := StringReplace(FORM_PAS, '    Button1: TButton;' + CRLF + '    Button2: TButton;',
    '    Button1, Button2: TButton;', []);
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'), Junto, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  Assert.Contains(Pas, '    Button1: TButton;' + CRLF + '    Edit1: TEdit;');
end;

procedure TDesignerEditTests.NombreNoSeConfundeConOtro;
const
  DFM2 =
    'object Form2: TForm2' + CRLF +
    '  object Edit1: TEdit' + CRLF +
    '  end' + CRLF +
    '  object Edit10: TEdit' + CRLF +
    '    OnChange = Edit10Change' + CRLF +
    '  end' + CRLF +
    '  object CreditEdit1: TEdit' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
  PAS2 =
    'unit Unit2;' + CRLF + 'interface' + CRLF + 'uses Vcl.Forms, Vcl.StdCtrls;' + CRLF +
    'type' + CRLF +
    '  TForm2 = class(TForm)' + CRLF +
    '    Edit1: TEdit;' + CRLF +
    '    Edit10: TEdit;' + CRLF +
    '    CreditEdit1: TEdit;' + CRLF +
    '    procedure Edit10Change(Sender: TObject);' + CRLF +
    '    procedure Edit1Exit(Sender: TObject);' + CRLF +
    '    procedure CreditEdit1Click(Sender: TObject);' + CRLF +
    '    procedure Edit12Exit(Sender: TObject);' + CRLF +
    '  end;' + CRLF +
    'implementation' + CRLF +
    'procedure TForm2.Edit10Change(Sender: TObject);' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'procedure TForm2.Edit1Exit(Sender: TObject);' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'procedure TForm2.CreditEdit1Click(Sender: TObject);' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'procedure TForm2.Edit12Exit(Sender: TObject);' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'end.' + CRLF;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
begin
  Doc := TStyleDoc.DeTexto(DFM2);
  try
    Imp := AnalizaImpacto(Doc, Doc.ObjetoDeNombre('Edit1'), False, PAS2, 'Unit2.pas');
  finally
    Doc.Free;
  end;
  // Edit10Change es de Edit10 y CreditEdit1Click de CreditEdit1 (trozos de
  // otro nombre del form); Edit12Exit no es de Edit1 aunque no haya Edit12
  // (el digito pegado detras)
  Assert.AreEqual('Edit1Exit;', Nombres(Imp));
end;

procedure TDesignerEditTests.RenombreCabeceraReferenciasYCampo;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R: string;
  M: TMetodoPropio;
begin
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeRenombre(Doc, Doc.ObjetoDeNombre('Button2'), 'BtnDos', FORM_PAS, 'Unit1.pas', ['Caption', 'Text'],
      Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  Assert.Contains(Dfm, '    object BtnDos: TButton');
  Assert.Contains(Dfm, '    FocusControl = BtnDos');
  Assert.DoesNotContain(Dfm, 'object Button2');
  // su Caption era su nombre y lo sigue, como en el IDE; el de otro no
  Assert.Contains(Dfm, '      Caption = ''BtnDos''');
  Assert.Contains(Dfm, '      Caption = ''Button1''');
  Assert.Contains(Pas, '    BtnDos: TButton;');
  // el codigo que lo usa y sus metodos no se tocan: se listan
  Assert.Contains(Pas, '  Button2.Enabled := True;');
  Assert.Contains(Pas, 'procedure Button2Vacio');
  Assert.AreEqual<Integer>(1, Length(Imp.Referencias));
  Assert.IsTrue(Metodo(Imp, 'Button2Vacio', M));
  Assert.IsTrue(M.PorNombre);
  Assert.AreEqual('Unit1.pas:46: Button2.Enabled := True;', string.Join('|', Imp.Usos));
end;

procedure TDesignerEditTests.PropiedadNoEntraEnColecciones;
const
  TXT =
    'object Form1: TForm1' + CRLF +
    '  object StatusBar1: TStatusBar' + CRLF +
    '    Panels = <' + CRLF +
    '      item' + CRLF +
    '        Width = 50' + CRLF +
    '      end>' + CRLF +
    '    Width = 300' + CRLF +
    '    Caption = ''abc'' +' + CRLF +
    '      ''def''' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
var
  Doc: TStyleDoc;
  O: TStyleObj;
  Ini, Fin: Integer;
begin
  Doc := TStyleDoc.DeTexto(TXT);
  try
    O := Doc.ObjetoDeNombre('StatusBar1');
    // el Width del item de la coleccion no es el del objeto
    Assert.IsTrue(Doc.PropLines(O, 'Width', Ini, Fin));
    Assert.AreEqual<Integer>(6, Ini);
    Assert.AreEqual<Integer>(6, Fin);
    Assert.IsTrue(Doc.PropLines(O, 'Panels', Ini, Fin));
    Assert.AreEqual<Integer>(2, Ini);
    Assert.AreEqual<Integer>(5, Fin);
    Assert.IsTrue(Doc.PropLines(O, 'Caption', Ini, Fin));
    Assert.AreEqual<Integer>(7, Ini);
    Assert.AreEqual<Integer>(8, Fin);
  finally
    Doc.Free;
  end;
end;

procedure TDesignerEditTests.PropiedadPartidaSeReescribeEntera;
const
  TXT =
    'object Form1: TForm1' + CRLF +
    '  object Label1: TLabel' + CRLF +
    '    Caption = ''abc'' +' + CRLF +
    '      ''def''' + CRLF +
    '    Left = 8' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
var
  Doc: TStyleDoc;
  Era: Boolean;
  Texto: string;
begin
  Doc := TStyleDoc.DeTexto(TXT);
  try
    Doc.SetProp(Doc.ObjetoDeNombre('Label1'), 'Caption', '''x''', Era);
    Texto := Doc.TextoDe(Doc.Lines);
  finally
    Doc.Free;
  end;
  Assert.IsTrue(Era);
  Assert.Contains(Texto, '    Caption = ''x''' + CRLF + '    Left = 8');
  Assert.DoesNotContain(Texto, 'def', 'el trozo de detras se va con el valor');
end;

(* T8 de la segunda revision de la 1.17.0: los bordes contra la RTL y no
  contra cadenas deducidas a mano - 64 y 65 caracteres, la comilla, #13, un
  acento (>127) donde corta un trozo, y 5000. *)
procedure TDesignerEditTests.LiteralContraLaRtl;
var
  C: TConLiteral;
  Bin: TMemoryStream;
  Txt: TBytesStream;
  Lineas: TArray<string>;
begin
  for var S in [StringOfChar('x', 64), StringOfChar('x', 65), 'It''s', 'a' + #13 + 'b',
                'Acci' + #$F3 + 'n', StringOfChar('z', 63) + #$F3 + 'w', StringOfChar('y', 5000)] do
  begin
    C := TConLiteral.Create(nil);
    Bin := TMemoryStream.Create;
    Txt := TBytesStream.Create;
    try
      C.Texto := S;
      Bin.WriteComponent(C);
      Bin.Position := 0;
      ObjectBinaryToText(Bin, Txt);
      // 'object TConLiteral', las lineas de la propiedad, 'end'
      Lineas := TEncoding.ASCII.GetString(Txt.Bytes, 0, Txt.Size).TrimRight.Split([CRLF]);
      Assert.AreEqual(string.Join(CRLF, Copy(Lineas, 1, Length(Lineas) - 2)),
        string.Join(CRLF, LineasDePropiedad('  ', 'Texto', TrozosDeLiteral(S))),
        'un texto de ' + IntToStr(Length(S)) + ' caracteres');
    finally
      Txt.Free;
      Bin.Free;
      C.Free;
    end;
  end;
end;

procedure TDesignerEditTests.LiteralComoElIde;
var
  Clave, Nombre, Clase, Resto, Txt: string;
begin
  // como ObjectBinaryToText: la comilla tambien como #39 ('Conway'#39's
  // Life', en un .dfm de ejemplo de 13.1), nunca doblada
  Assert.AreEqual('''Acci''#243''n''', string.Join('|', TrozosDeLiteral('Acci' + #$F3 + 'n')));
  Assert.AreEqual('''It''#39''s''', string.Join('|', TrozosDeLiteral('It''s')));
  Assert.AreEqual('''''', string.Join('|', TrozosDeLiteral('')));
  Assert.AreEqual('#9''a''', string.Join('|', TrozosDeLiteral(#9'a')));
  // la larga, en trozos de 64 caracteres del texto: la del uCardPanel.dfm de
  // ejemplo de Delphi 13.1, letra por letra
  Assert.AreEqual('''Left and Right gestures are available. ''#13''Swipe left to go to the '' +|' +
    '''next card. Swipe right to go to previous card.''',
    string.Join('|', TrozosDeLiteral('Left and Right gestures are available. ' + #13 +
      'Swipe left to go to the next card. Swipe right to go to previous card.')));
  // su lector es el inverso; lee tambien la comilla doblada y los trozos
  // unidos con '+', y no lo que no es un literal
  for var S in ['', 'It''s', 'Acci' + #$F3 + 'n', #9'a', StringOfChar('x', 130) + #13 + 'y'] do
  begin
    Assert.IsTrue(LeeLiteralDeForm(string.Join(' ', TrozosDeLiteral(S)), Txt), S);
    Assert.AreEqual(S, Txt);
  end;
  Assert.IsTrue(LeeLiteralDeForm('''a'' + ''b''', Txt) and (Txt = 'ab'));
  Assert.IsTrue(LeeLiteralDeForm('''It''''s''', Txt) and (Txt = 'It''s'));
  Assert.IsFalse(LeeLiteralDeForm('''abc', Txt), 'sin cerrar');
  Assert.IsFalse(LeeLiteralDeForm('''a'' ''b''', Txt), 'dos sin el +');
  Assert.IsFalse(LeeLiteralDeForm('#hashtag', Txt));
  Assert.IsTrue(EsCaracterDeForm('#39') and not EsCaracterDeForm('''ab'''));
  Assert.IsTrue(EsNumeroDeForm('-2E3') and EsNumeroDeForm('1.5e-5') and EsNumeroDeForm('$FF') and
    not EsNumeroDeForm('1e') and not EsNumeroDeForm('12a'));
  // el signo solo delante de digitos: TParser no lee -$10 (segunda revision)
  Assert.IsFalse(EsNumeroDeForm('-$10') or EsEnteroDeForm('-$10'), '-$10 no lo lee el cargador');
  // y la gramatica de un valor (ValidStyleValue) por esas dos: un 1e3 es un
  // numero y un 'abc sin cerrar no es una cadena (revision de la 1.17.0, sin
  // prueba hasta la segunda)
  Assert.IsTrue(ValidStyleValue('1e3') and ValidStyleValue('''abc''') and ValidStyleValue('''a'' + ''b'''));
  Assert.IsFalse(ValidStyleValue('''abc'), 'una cadena sin cerrar');
  Assert.IsTrue(EsEnteroDeForm('-12') and EsEnteroDeForm('$7FFFFFFF') and not EsEnteroDeForm('1.5'));
  // bajo el decimal 18, redondeado en el; con mas de 16 cifras enteras, la
  // forma general (lo que hace FloatToStrF en el IDE de 32 bits)
  Assert.AreEqual('0.000000000000000001', FlotanteDeForm(6E-19, False));
  Assert.AreEqual('0.000000000000000000', FlotanteDeForm(3E-19, False));
  Assert.AreEqual('0.000000000000000000', FlotanteDeForm(-3E-19, False), 'cero, sin signo');
  Assert.AreEqual('1E20', FlotanteDeForm(1E20, False));
  Assert.AreEqual('1.000000020040877E20', FlotanteDeForm(1E20, True));
  // la cabecera con su orden detras
  Assert.IsTrue(LineaDeObjeto('    object Button1: TButton [2]', Clave, Nombre, Clase, Resto));
  Assert.AreEqual(' [2]', Resto);
  Assert.AreEqual('10.000000000000000000', FlotanteFmx(10));
  // como los .fmx de ejemplo de Delphi 13.1: una Single, redondeada a Single
  // (Duration = 0.400000005960464500, Opacity = 0.699999988079071000)
  Assert.AreEqual('0.400000005960464500', FlotanteDeForm(0.4, True));
  Assert.AreEqual('0.699999988079071000', FlotanteDeForm(0.7, True));
  Assert.AreEqual('0.400000000000000000', FlotanteDeForm(0.4, False), 'un Double no se redondea a Single');
  Assert.AreEqual('250.500000000000000000', FlotanteDeForm(250.5, True));
  Assert.AreEqual('-2000.000000000000000000', FlotanteDeForm(-2E3, False));
  // tres mas de esos ejemplos: un negativo, uno con 14 decimales suyos y uno
  // tan pequeno que lo corta el decimal 18, no la cifra 16
  Assert.AreEqual('-4.972735404968262000', FlotanteDeForm(-4.972735404968262, True));
  Assert.AreEqual('94.472366333007810000', FlotanteDeForm(94.47236633300781, True));
  Assert.AreEqual('0.000001339281197943', FlotanteDeForm(0.000001339281197943, True));
  // el compositor de la linea de objeto es la inversa del lector
  Assert.IsTrue(LineaDeObjeto('  ' + ComponeLineaDeObjeto('object', 'Button1', 'TButton'), Clave, Nombre, Clase));
  Assert.AreEqual('object|Button1|TButton', Clave + '|' + Nombre + '|' + Clase);
  Assert.IsTrue(LineaDeObjeto(ComponeLineaDeObjeto('inline', '', 'TFrame1'), Clave, Nombre, Clase));
  Assert.AreEqual('inline||TFrame1', Clave + '|' + Nombre + '|' + Clase);
end;

procedure TDesignerEditTests.DesciendeYJuez;
var
  M: TMetaTable;
  Id, W: string;
  Hoja: TPropRec;
  Hay: Boolean;
begin
  M := TMetaTable.Create([
    'C System.Classes:TComponent',
    'C Vcl.Controls:TControl', 'H Vcl.Controls:TControl System.Classes:TComponent',
    'C Vcl.Controls:TWinControl', 'H Vcl.Controls:TWinControl Vcl.Controls:TControl',
    'C Vcl.Buttons:TBoton', 'H Vcl.Buttons:TBoton Vcl.Controls:TWinControl',
    'P Vcl.Buttons:TBoton Caption o TCaption',
    'P Vcl.Buttons:TBoton TabOrder o TTabOrder',
    'C FMX.Controls:TControl']);
  try
    Assert.IsTrue(M.ClaseDeNombre('TBoton', Id));
    Assert.IsTrue(M.Desciende(Id, ID_VCL_WINCONTROL));
    Assert.IsTrue(M.Desciende(Id, ID_VCL_CONTROL));
    Assert.IsFalse(M.Desciende(Id, ID_FMX_CONTROL), 'el TControl de FMX es otro');
    Assert.IsTrue(M.ClaseDeNombre('TComponent', Id));
    Assert.IsFalse(M.Desciende(Id, ID_VCL_CONTROL), 'un componente no es un control');
    // el juez del lint, el que pregunta set antes de escribir
    Assert.IsTrue(M.ClaseDeNombre('TBoton', Id));
    W := JuzgaPropiedad(M, Id, 'Caption', '''x''', Hoja, Hay);
    Assert.AreEqual('', W);
    Assert.IsTrue(Hay);
    Assert.AreEqual('TCaption', Hoja.TypeName);
    W := JuzgaPropiedad(M, Id, 'Captoin', '''x''', Hoja, Hay);
    Assert.Contains(W, 'Captoin');
    Assert.IsFalse(Hay);
  finally
    M.Free;
  end;
end;

procedure TDesignerEditTests.LaMasParecida;
begin
  Assert.AreEqual('Caption', ElMasParecido('Captoin', ['Caption', 'Color', 'Cursor'], 2));
  Assert.AreEqual('', ElMasParecido('Zzzzzz', ['Caption', 'Color'], 2), 'demasiado lejos');
  Assert.AreEqual('', ElMasParecido('Cat', ['Bat', 'Hat'], 2), 'un empate no elige');
  Assert.AreEqual(3, EditDistance('kitten', 'sitting'));
  // un salto es CRLF, LF o un CR suelto
  Assert.AreEqual(2, LineaDePosicion('a'#13'b'#10'c'#13#10'd', 3));
  Assert.AreEqual(3, LineaDePosicion('a'#13'b'#10'c'#13#10'd', 5));
  Assert.AreEqual(4, LineaDePosicion('a'#13'b'#10'c'#13#10'd', 8));
end;

{ Si el Text de un control nuevo es su Name lo dice el SetName de su clase
  en el FUENTE (David, 7-oct-2026: un comportamiento de clases concretas no
  va en una lista). El caso medido: las cuatro formas del fuente de Delphi
  13.1 (FMX.Controls 7634, FMX.StdCtrls 2962, FMX.Skia 6052, FMX.Edit 1659),
  mas una que sobrescribe sin tocar el Text; y una clase hereda el del SetName
  mas cercano de su cadena. }
procedure TDesignerEditTests.TextoSigueAlNombreDelFuente;
const
  CAMBIA = '  ChangeText := not (csLoading in ComponentState) and (Name = Text);' + CRLF;
  FUENTE =
    'unit Medida;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'procedure TTextControl.SetName(const Value: TComponentName);' + CRLF +
    'var' + CRLF + '  ChangeText: Boolean;' + CRLF + 'begin' + CRLF + CAMBIA +
    '  inherited SetName(Value);' + CRLF + '  if ChangeText then' + CRLF +
    '    Text := Value;' + CRLF + 'end;' + CRLF +
    'procedure TPresentedTextControl.SetName(const Value: TComponentName);' + CRLF +
    'var' + CRLF + '  ChangeText: Boolean;' + CRLF + 'begin' + CRLF + CAMBIA +
    '  inherited SetName(Value);' + CRLF + '  if ChangeText then' + CRLF +
    '    Text := Value;' + CRLF + 'end;' + CRLF +
    'procedure TSkLabel.SetName(const AValue: TComponentName);' + CRLF +
    'var' + CRLF + '  LChangeText: Boolean;' + CRLF + 'begin' + CRLF +
    '  LChangeText := not (csLoading in ComponentState) and (Name = Text);' + CRLF +
    '  inherited SetName(AValue);' + CRLF + '  if LChangeText then' + CRLF +
    '    Text := AValue;' + CRLF + 'end;' + CRLF +
    'procedure TEditButton.SetName(const NewName: TComponentName);' + CRLF +
    'begin' + CRLF + '  inherited SetName(NewName);' + CRLF + '  if NewName = Text then' + CRLF +
    '    Text := string.Empty;' + CRLF + 'end;' + CRLF +
    // el de Vcl.ExtCtrls de 13.1, tal cual: el Caption que pone es el de SU
    // etiqueta, y su Text lo vacia (segunda revision de la 1.17.0)
    'procedure TCustomLabeledEdit.SetName(const Value: TComponentName);' + CRLF +
    'var' + CRLF + '  LClearText: Boolean;' + CRLF + 'begin' + CRLF +
    '  if (csDesigning in ComponentState) and not (csLoading in ComponentState) and' + CRLF +
    '     (FEditLabel <> nil) and SameText(FEditLabel.Caption, Name) then' + CRLF +
    '  begin' + CRLF + '    FEditLabel.Caption := Value;' + CRLF +
    '    FEditLabel.IsLabelModified := False;' + CRLF + '  end;' + CRLF +
    '  LClearText := (csDesigning in ComponentState) and (Text = '''');' + CRLF +
    '  inherited SetName(Value);' + CRLF + '  if LClearText then' + CRLF +
    '    Text := '''';' + CRLF + 'end;' + CRLF +
    'procedure TConSelf.SetName(const Value: TComponentName);' + CRLF +
    'begin' + CRLF + '  inherited SetName(Value);' + CRLF + '  Self.Caption := Value;' + CRLF + 'end;' + CRLF +
    'procedure TOtra.SetName(const Value: TComponentName);' + CRLF +
    'begin' + CRLF + '  inherited SetName(Value);' + CRLF + '  FEtiqueta := Value;' + CRLF + 'end;' + CRLF +
    // uno comentado no cuenta: la prueba lee el texto activo, como la tabla
    'procedure TComentada.SetName(const Value: TComponentName);' + CRLF +
    'begin' + CRLF + '  inherited SetName(Value);' + CRLF + '  // Text := Value;' + CRLF + 'end;' + CRLF +
    'end.' + CRLF;
var
  M: TMetaTable;
  Id: string;
begin
  Assert.AreEqual('TTextControl 1|TPresentedTextControl 1|TSkLabel 1|TEditButton 0|' +
    'TCustomLabeledEdit 0|TConSelf 1|TOtra 0|TComentada 0',
    string.Join('|', SetNamesDeTexto(FUENTE)));
  M := TMetaTable.Create([
    'C FMX.Controls:TControl',
    'C FMX.Controls:TTextControl', 'H FMX.Controls:TTextControl FMX.Controls:TControl',
    'T FMX.Controls:TTextControl 1',
    'C FMX.StdCtrls:TPresentedTextControl', 'H FMX.StdCtrls:TPresentedTextControl FMX.Controls:TControl',
    'T FMX.StdCtrls:TPresentedTextControl 1',
    'C FMX.StdCtrls:TCustomButton', 'H FMX.StdCtrls:TCustomButton FMX.StdCtrls:TPresentedTextControl',
    'C FMX.StdCtrls:TButton', 'H FMX.StdCtrls:TButton FMX.StdCtrls:TCustomButton',
    'C FMX.Edit:TEditButton', 'H FMX.Edit:TEditButton FMX.StdCtrls:TCustomButton',
    'T FMX.Edit:TEditButton 0',
    'C FMX.Edit:TClearEditButton', 'H FMX.Edit:TClearEditButton FMX.Edit:TEditButton',
    'C FMX.Objects:TRectangle', 'H FMX.Objects:TRectangle FMX.Controls:TControl']);
  try
    Assert.IsTrue(M.ClaseDeNombre('TButton', Id));
    Assert.IsTrue(M.TextoSigueAlNombre(Id), 'TButton hereda el de TPresentedTextControl');
    Assert.IsTrue(M.ClaseDeNombre('TEditButton', Id));
    Assert.IsFalse(M.TextoSigueAlNombre(Id), 'el suyo lo vacia');
    Assert.IsTrue(M.ClaseDeNombre('TClearEditButton', Id));
    Assert.IsFalse(M.TextoSigueAlNombre(Id), 'el mas cercano de su cadena es el de TEditButton');
    Assert.IsTrue(M.ClaseDeNombre('TRectangle', Id));
    Assert.IsFalse(M.TextoSigueAlNombre(Id), 'nadie en su cadena lo hace');
  finally
    M.Free;
  end;
end;

{ Quitar lineas enteras se llevaria lo que las comparte (revision del diff,
  7-oct-2026): un manejador vacio cuya declaracion va en la linea de otra se
  queda entero; un campo en la linea de otro miembro se niega. }
procedure TDesignerEditTests.LineaCompartidaNoSeBorra;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R, Junto: string;
  M: TMetodoPropio;
begin
  Junto := StringReplace(FORM_PAS, '    procedure Compartido(Sender: TObject);' + CRLF +
    '    procedure Button2Vacio(Sender: TObject);',
    '    procedure Compartido(Sender: TObject); procedure Button2Vacio(Sender: TObject);', []);
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'), Junto, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  Assert.Contains(Pas, '    procedure Compartido(Sender: TObject); procedure Button2Vacio(Sender: TObject);',
    'la linea se queda entera: lleva otra declaracion');
  Assert.Contains(Pas, 'procedure TForm1.Button2Vacio', 'y su implementacion con ella');
  Assert.IsTrue(Metodo(Imp, 'Button2Vacio', M));
  Assert.IsFalse(M.SeBorra);
  Assert.DoesNotContain(Pas, 'Button2: TButton', 'su campo, en su linea, si se va');
  Junto := StringReplace(FORM_PAS, '    Button2: TButton;', '    Button2: TButton; procedure Otro;', []);
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'), Junto, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.StartsWith('[DSGN-099', R, 'el campo comparte linea con un metodo: se niega');
end;

{ Dos campos que se van de la misma declaracion: el segundo se busca en la
  linea ya cortada (con la vista de codigo sin cortar, cortaba 'TButton'). }
procedure TDesignerEditTests.DosCamposDeUnaLinea;
const
  DFM3 =
    'object Form3: TForm3' + CRLF + '  object Panel1: TPanel' + CRLF +
    '    object Button1: TButton' + CRLF + '    end' + CRLF +
    '    object Button2: TButton' + CRLF + '    end' + CRLF + '  end' + CRLF +
    '  object Button3: TButton' + CRLF + '  end' + CRLF + 'end' + CRLF;
  PAS3 =
    'unit Unit3;' + CRLF + 'interface' + CRLF + 'uses Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;' + CRLF +
    'type' + CRLF + '  TForm3 = class(TForm)' + CRLF + '    Panel1: TPanel;' + CRLF +
    '    Button1, Button3, Button2: TButton;' + CRLF + '  end;' + CRLF +
    'implementation' + CRLF + 'end.' + CRLF;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, R: string;
begin
  Doc := TStyleDoc.DeTexto(DFM3);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Panel1'), PAS3, 'Unit3.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  Assert.Contains(Pas, '  TForm3 = class(TForm)' + CRLF + '    Button3: TButton;' + CRLF + '  end;',
    'los dos de dentro fuera de la misma linea; Button3 se queda');
end;

{ Las constantes con nombre de los enteros, leidas del fuente (David,
  7-oct-2026: comprobar tipos de verdad, no con listas): un IdentTo que
  solo busca en su mapa da sus nombres; uno que llama a otro, a quien; uno
  que hace mas (el de TAlphaColor acepta xFF00FF00) no sale. }
procedure TDesignerEditTests.ConstantesDelFuente;
const
  UICONSTS =
    'unit System.UIConsts;' + CRLF + 'interface' + CRLF + 'uses System.UITypes;' + CRLF +
    'function IdentToColor(const Ident: string; var Color: Integer): Boolean;' + CRLF +
    'implementation' + CRLF + 'uses System.Classes;' + CRLF + 'const' + CRLF +
    '  Colors: array[0..1] of TIdentMapEntry = (' + CRLF +
    '    (Value: TColors.Black; Name: ''clBlack''),' + CRLF +
    '    { un comentario con un parentesis ( suelto: no cuenta }' + CRLF +
    '    (Value: TColors.Red; Name: ''clRed''));' + CRLF +
    '  Cursors: array [0..1] of TIdentMapEntry = (' + CRLF +
    '    (Value: crDefault; Name: ''crDefault''),' + CRLF +
    '    (Value: crHandPoint; Name: ''crHandPoint''));' + CRLF +
    // el mapa y la funcion con la FORMA REAL de System.UIConsts de 13.1: el
    // valor con un molde, y una local (la 10 se saltaba las funciones con
    // locales y la tabla real salio '*' sin nombres: revision de la 1.17.0)
    '  AlphaColors: array [0..1] of TIdentMapEntry = (' + CRLF +
    '    (Value: Integer($FFF0F8FF); Name: ''claAliceblue''),' + CRLF +
    '    (Value: Integer($FFFF0000); Name: ''claRed''));' + CRLF +
    'function IdentToColor(const Ident: string; var Color: Integer): Boolean;' + CRLF +
    'begin' + CRLF + '  Result := IdentToInt(Ident, Color, Colors);' + CRLF + 'end;' + CRLF +
    'function IdentToCursor(const Ident: string; var Cursor: Integer): Boolean;' + CRLF +
    'begin' + CRLF + '  Result := IdentToInt(Ident, Cursor, Cursors);' + CRLF + 'end;' + CRLF +
    'function IdentToAlphaColor(const Ident: string; var Color: Integer): Boolean;' + CRLF +
    'var' + CRLF + '  LIdent: string;' + CRLF +
    'begin' + CRLF + '  LIdent := Ident;' + CRLF +
    '  if (LIdent.Length > 0) and (LIdent.Chars[0] = ''x'') then' + CRLF +
    '  begin' + CRLF + '    Color := Integer(StringToAlphaColor(LIdent));' + CRLF +
    '    Result := True;' + CRLF + '  end else' + CRLF +
    '    Result := IdentToInt(LIdent, Color, AlphaColors);' + CRLF +
    '  if not Result and (LIdent.Length > 3) then' + CRLF + '  begin' + CRLF +
    '    LIdent := LIdent.Insert(2, ''a'');' + CRLF +
    '    Result := IdentToInt(LIdent, Integer(Color), AlphaColors);' + CRLF + '  end;' + CRLF + 'end;' + CRLF +
    'procedure RegisterColorIntegerConsts;' + CRLF + 'begin' + CRLF +
    '  RegisterIntegerConsts(TypeInfo(TColor), IdentToColor, ColorToIdent);' + CRLF +
    '  RegisterIntegerConsts(TypeInfo(TCursor), IdentToCursor, CursorToIdent);' + CRLF +
    '  RegisterIntegerConsts(TypeInfo(TAlphaColor), IdentToAlphaColor, AlphaColorToIdent);' + CRLF +
    'end;' + CRLF + 'end.' + CRLF;
  CONTROLS =
    'unit Vcl.Controls;' + CRLF + 'interface' + CRLF + 'uses System.UITypes;' + CRLF +
    'implementation' + CRLF + 'uses System.UIConsts;' + CRLF +
    'function IdentToCursor(const Ident: string; var Cursor: Longint): Boolean;' + CRLF +
    'begin' + CRLF + '  Result := System.UIConsts.IdentToCursor(Ident, Cursor);' + CRLF + 'end;' + CRLF +
    'initialization' + CRLF +
    '  RegisterIntegerConsts(TypeInfo(TCursor), IdentToCursor, CursorToIdent);' + CRLF + 'end.' + CRLF;
begin
  Assert.AreEqual('R TColor IdentToColor|R TCursor IdentToCursor|R TAlphaColor IdentToAlphaColor|' +
    'L IdentToColor clBlack,clRed|L IdentToCursor crDefault,crHandPoint|' +
    // y lo que lee ademas, de su cuerpo: x y un hexadecimal, la 'a' en el 2
    'A IdentToAlphaColor claAliceblue,claRed;hex=x;ins=2a',
    string.Join('|', ConstantesDeTexto(UICONSTS)));
  Assert.AreEqual('R TCursor IdentToCursor|D IdentToCursor System.UIConsts.IdentToCursor',
    string.Join('|', ConstantesDeTexto(CONTROLS)));
end;

{ Lo que toma una propiedad por la base de su tipo (B) y las constantes de
  su entero (I), como lo lee TReader. Los tres casos medidos en vivo el
  7-oct-2026 que se escribian: un TColor 'hola', un TCursor 3.5, un TColor
  con una constante mal escrita. }
procedure TDesignerEditTests.ValorPorLaBaseDeSuTipo;
var
  M: TMetaTable;
  P, Aviso: string;

  function Juzga(const AProp, AValor: string): string;
  begin
    Result := BaseQueNoCasa(M, M.Props[ClaveProp('Vcl.Controls:TCosa', AProp)], AValor, Aviso, P);
  end;

begin
  M := TMetaTable.Create(['C Vcl.Controls:TCosa',
    'P Vcl.Controls:TCosa Color o TColor', 'P Vcl.Controls:TCosa Cursor o TCursor',
    'P Vcl.Controls:TCosa Fondo o TAlphaColor', 'P Vcl.Controls:TCosa Letra o Char',
    'P Vcl.Controls:TCosa Peso o Double', 'P Vcl.Controls:TCosa Titulo o TCaption',
    'P Vcl.Controls:TCosa Grande o Int64', 'P Vcl.Controls:TCosa Raro o TRaro',
    'P Vcl.Controls:TCosa Opacidad o Single', 'B Single single',
    'P Vcl.Controls:TCosa Dato o Variant', 'B Variant variant',
    'B TColor integer', 'B TCursor integer', 'B TAlphaColor integer', 'B Char char',
    'B Double float', 'B TCaption string', 'B Int64 int64',
    'I TColor clBlack,clRed', 'I TAlphaColor *claBlack,claRed',
    // la abierta CON sus formas, como sale del fuente real (generacion 12)
    'P Vcl.Controls:TCosa Relleno o TAlphaColor2', 'B TAlphaColor2 integer',
    'I TAlphaColor2 *claBlack,claRed;hex=x;ins=2a']);
  try
    Assert.AreEqual('', Juzga('Color', '255'));
    Assert.AreEqual('', Juzga('Color', '$00FF00'));
    Assert.AreEqual('', Juzga('Color', 'clred'), 'una de sus constantes, sin mirar mayusculas');
    Assert.Contains(Juzga('Color', 'clRedd'), 'clBlack, clRed', 'las que toma');
    Assert.Contains(P, 'clRed', 'y la que quiso decir');
    Assert.AreNotEqual('', Juzga('Color', '''hola'''), 'una cadena en un TColor');
    Assert.AreNotEqual('', Juzga('Color', '3.5'));
    Assert.AreEqual('', Juzga('Cursor', '3'));
    Assert.AreNotEqual('', Juzga('Cursor', 'crHandPoint'), 'sin constantes registradas, un identificador no');
    Assert.AreNotEqual('', Juzga('Cursor', '3.5'));
    // abierta SIN sus formas: no se sabe que mas lee; se escribe, con su
    // aviso siempre (callaba con lo que no se parecia: segunda revision)
    Assert.AreEqual('', Juzga('Fondo', 'xFFFF0000'), 'su IdentTo hace mas que buscar: abierta');
    Assert.IsTrue(Aviso.StartsWith('[DSGN-110'), 'sin sus formas, el aviso siempre: ' + Aviso);
    Assert.AreEqual('', Juzga('Fondo', 'claRedd'), 'abierta: no se niega...');
    Assert.Contains(Aviso, 'claRed', '...pero se avisa con la que se parece');
    // CON sus formas: exacta. Las tres que carga IdentToAlphaColor, sin aviso;
    // lo demas se niega, con la parecida
    Assert.AreEqual('', Juzga('Relleno', 'claRed'));
    Assert.AreEqual('', Juzga('Relleno', 'clRed'), 'la a insertada: claRed');
    Assert.AreEqual('', Aviso, 'carga: sin aviso');
    Assert.AreEqual('', Juzga('Relleno', 'xFF00FF00'), 'x y un hexadecimal');
    Assert.AreEqual('', Aviso);
    Assert.Contains(Juzga('Relleno', 'Rojo'), 'keeps the form from opening', 'no carga: se niega');
    Assert.AreNotEqual('', Juzga('Relleno', 'xZZ'), 'x y algo que no es hexadecimal');
    Assert.AreNotEqual('', Juzga('Relleno', 'XFF00FF00'), 'la X mayuscula no: su cuerpo compara la x');
    Assert.Contains(Juzga('Relleno', 'claRde'), 'clBlack for claBlack', 'las formas, con un ejemplo suyo');
    Assert.Contains(P, 'claRed', 'y la que quiso decir');
    Assert.AreNotEqual('', Juzga('Fondo', '''rojo'''));
    // lo que cabe donde lo lee el cargador: ReadInteger, 32 bits
    Assert.AreEqual('', Juzga('Color', '2147483647'));
    Assert.AreEqual('', Juzga('Color', '-2147483648'));
    Assert.AreNotEqual('', Juzga('Color', '2147483648'));
    Assert.AreNotEqual('', Juzga('Fondo', '$FFFF0000'), 'un hex de mas de 31 bits sale como Int64');
    Assert.AreNotEqual('', Juzga('Grande', '9223372036854775808'));
    Assert.AreEqual('', Juzga('Peso', '1e3'), 'con exponente');
    Assert.AreEqual('', Juzga('Peso', '$10'), 'un hex, que ReadFloat lee como entero');
    // un Variant: lo que lee ReadVariant
    Assert.AreEqual('', Juzga('Dato', '12'));
    Assert.AreEqual('', Juzga('Dato', '''x'''));
    Assert.AreEqual('', Juzga('Dato', 'Null'));
    Assert.AreNotEqual('', Juzga('Dato', 'Hola'));
    Assert.AreEqual('', Juzga('Letra', '''A'''));
    Assert.AreEqual('', Juzga('Letra', '#65'));
    Assert.AreNotEqual('', Juzga('Letra', '''AB'''), 'un caracter, no dos');
    Assert.AreEqual('', Juzga('Peso', '1.5'));
    Assert.AreEqual('', Juzga('Peso', '-2E3'));
    Assert.AreNotEqual('', Juzga('Peso', 'abc'));
    Assert.AreEqual('', Juzga('Titulo', '''Acci''#243''n'''));
    Assert.AreNotEqual('', Juzga('Titulo', 'Hola'), 'sin comillas (set se las pone antes)');
    Assert.AreEqual('', Juzga('Grande', '123'));
    Assert.AreNotEqual('', Juzga('Grande', 'clRed'), 'un Int64 no toma constantes');
    Assert.AreEqual('', Juzga('Raro', 'loquesea'), 'sin base no se sabe: se calla');
    Assert.AreEqual('', Juzga('Opacidad', '0.7'), 'una Single toma un numero');
    Assert.AreNotEqual('', Juzga('Opacidad', 'media'));
  finally
    M.Free;
  end;
end;

(* LA gramatica de las lineas (Lsp.DesignerBin.LineasDeForm), con lo que la
  revision de la 1.17.0 midio en vivo: la cadena larga que el IDE empieza en
  la linea de debajo (set la cortaba por la primera y el form no cargaba), un
  'Items = <>' en un item (cerraba la coleccion: el arbol salia descolocado y
  la raiz era otro) y un '= {' dentro de una cadena (un bloque binario hasta
  el final del fichero). *)
procedure TDesignerEditTests.LineasDelFormComoLasEscribeElIde;
const
  LARGO = 'Left and Right gestures are available. ' + #13 +
    'Swipe left to go to the next card. Swipe right to go to previous card.';
  TROZOS =
    '    Caption = ' + CRLF +
    '      ''Left and Right gestures are available. ''#13''Swipe left to go to the '' +' + CRLF +
    '      ''next card. Swipe right to go to previous card.''' + CRLF;
  TXT =
    'object Form1: TForm1' + CRLF +              // 0
    '  object Label1: TLabel' + CRLF +           // 1
    TROZOS +                                     // 2..4
    '    Hint = ''Total = {0}''' + CRLF +        // 5
    '    ShowHint = True' + CRLF +               // 6
    '  end' + CRLF +                             // 7
    '  object Cats: TCategoryButtons' + CRLF +   // 8
    '    Categories = <' + CRLF +                // 9
    '      item' + CRLF +                        // 10
    '        Caption = ''Uno''' + CRLF +         // 11
    '        Items = <>' + CRLF +                // 12
    '        OnClick = CatsUno' + CRLF +         // 13
    '      end' + CRLF +                         // 14
    '      item [1]' + CRLF +                    // 15
    '        Caption = ''Dos''' + CRLF +         // 16
    '      end>' + CRLF +                        // 17
    '    Width = 100' + CRLF +                   // 18
    '  end' + CRLF +                             // 19
    '  object Label2: TLabel' + CRLF +           // 20
    '    Caption = ''Label2''' + CRLF +          // 21
    '  end' + CRLF +                             // 22
    'end' + CRLF;                                // 23
var
  Doc: TStyleDoc;
  Form: TArray<TLineaForm>;
  Ini, Fin: Integer;
  Leido, Texto: string;
  Era: Boolean;
begin
  Doc := TStyleDoc.DeTexto(TXT);
  try
    Assert.AreEqual('Form1', Doc.Root.ObjName);
    Assert.AreEqual<Integer>(3, Doc.Root.Children.Count, 'Label1, Cats y Label2');
    Assert.AreEqual<Integer>(20, Doc.ObjetoDeNombre('Cats').EndLine, 'su end, no el de un item');
    Assert.AreEqual<Integer>(24, Doc.Root.EndLine);
    Assert.IsTrue(Doc.PropLines(Doc.ObjetoDeNombre('Label1'), 'Caption', Ini, Fin));
    Assert.AreEqual<Integer>(2, Ini);
    Assert.AreEqual<Integer>(4, Fin, 'la cadena larga del IDE, entera');
    Assert.IsTrue(Doc.PropLines(Doc.ObjetoDeNombre('Label1'), 'Hint', Ini, Fin));
    Assert.AreEqual<Integer>(5, Fin, 'un = { dentro de una cadena no es un bloque');
    Assert.IsTrue(Doc.PropLines(Doc.ObjetoDeNombre('Label1'), 'ShowHint', Ini, Fin), '...ni se come la de detras');
    Assert.AreEqual<Integer>(6, Ini);
    Assert.IsTrue(Doc.PropLines(Doc.ObjetoDeNombre('Cats'), 'Categories', Ini, Fin));
    Assert.AreEqual<Integer>(17, Fin, 'hasta su end>, con el <> de un item dentro');
    Assert.IsTrue(Doc.PropLines(Doc.ObjetoDeNombre('Cats'), 'Width', Ini, Fin));
    Assert.AreEqual<Integer>(18, Ini, 'el del objeto, no uno de un item');
    Form := LineasDeForm(Doc.Lines);
    Assert.IsTrue(Form[13].Clase = clfPropiedad, 'el evento de un item es una propiedad');
    Assert.AreEqual<Integer>(1, Form[13].Coleccion);
    Assert.IsTrue(Form[15].Clase = clfItem, 'item [1]');
    Assert.IsTrue(Form[3].Clase = clfValor, 'un trozo de la cadena');
    Assert.IsTrue(LeeLiteralDeForm(ValorEnteroDe(Doc.Lines, Form, 2), Leido));
    Assert.AreEqual(LARGO, Leido, 'el valor entero, leido');
    // set la reescribe entera, y una larga la escribe como el IDE
    Doc.SetProp(Doc.ObjetoDeNombre('Label1'), 'Caption', '''x''', Era);
    Texto := Doc.TextoDe(Doc.Lines);
    Assert.IsTrue(Era);
    Assert.Contains(Texto, '    Caption = ''x''' + CRLF + '    Hint = ');
    Assert.DoesNotContain(Texto, 'next card', 'los trozos de debajo se van con su valor');
    Doc.SetPropTrozos(Doc.ObjetoDeNombre('Label1'), 'Caption', TrozosDeLiteral(LARGO), Era);
    Assert.Contains(Doc.TextoDe(Doc.Lines), TROZOS + '    Hint = ', 'como la escribio el IDE en el ejemplo');
  finally
    Doc.Free;
  end;
end;

{ Una linea es una referencia si su propiedad guarda un componente (la
  tabla: AJuez). En FMX un enumerado va sin prefijo, y Align = Client no
  nombra a un componente Client: el delete la borraba y el renombrado la
  reescribia (revision de la 1.17.0). Y la ruta de un componente de un frame
  (Frame11.Edit1) sigue al frame cuando se renombra, tambien dentro de su
  bloque: el cargador resuelve el nombre desde el form. }
procedure TDesignerEditTests.ReferenciaSoloSiGuardaUnComponente;
const
  DFM =
    'object Form1: TForm1' + CRLF +            // 0
    '  object Client: TLayout' + CRLF +        // 1
    '    Align = Top' + CRLF +                 // 2
    '  end' + CRLF +                           // 3
    '  object Panel1: TPanel' + CRLF +         // 4
    '    Align = Client' + CRLF +              // 5
    '    PopupMenu = Client' + CRLF +          // 6
    '  end' + CRLF +                           // 7
    '  inline Frame11: TFrame1' + CRLF +       // 8
    '    FocusOn = Frame11.Edit1' + CRLF +     // 9
    '  end' + CRLF +                           // 10
    '  object Label1: TLabel' + CRLF +         // 11
    '    FocusControl = Frame11.Edit1' + CRLF + // 12
    '  end' + CRLF +                           // 13
    'end' + CRLF;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Nuevo, Pas, R: string;
  Juez: TJuezDeReferencia;
begin
  Juez :=
    function(AObj: TStyleObj; const AProp: string): Boolean
    begin
      Result := not SameText(AProp, 'Align'); // un enumerado, para la tabla
    end;
  Doc := TStyleDoc.DeTexto(DFM);
  try
    Imp := AnalizaImpacto(Doc, Doc.ObjetoDeNombre('Client'), False, '', '', Juez);
    Assert.AreEqual<Integer>(1, Length(Imp.Referencias));
    Assert.AreEqual<Integer>(6, Imp.Referencias[0], 'PopupMenu guarda un componente; Align no');
    Imp := AnalizaImpacto(Doc, Doc.ObjetoDeNombre('Client'), False, '', '');
    Assert.AreEqual<Integer>(2, Length(Imp.Referencias), 'sin tabla manda el nombre');
    R := PlanDeRenombre(Doc, Doc.ObjetoDeNombre('Frame11'), 'Marco', '', 'Unit1.pas', [],
      Imp, Nuevo, Pas, Juez);
    Assert.AreEqual('', R);
    Assert.Contains(Nuevo, '  inline Marco: TFrame1');
    Assert.Contains(Nuevo, '    FocusControl = Marco.Edit1');
    Assert.Contains(Nuevo, '    FocusOn = Marco.Edit1', 'dentro de su bloque tambien');
    Assert.Contains(Nuevo, '    Align = Client', 'el enumerado no se toca');
  finally
    Doc.Free;
  end;
end;

{ Lo de dentro de un frame en linea es del frame: el form puede tener su
  propio Edit1, y el delete del frame se llevaba el campo del Edit1 del form
  y la linea que lo nombra (revision de la 1.17.0). }
procedure TDesignerEditTests.NombresDelFrameEnLinea;
const
  DFM =
    'object Form1: TForm1' + CRLF +
    '  inline Frame11: TFrame1' + CRLF +
    '    inherited Edit1: TEdit' + CRLF +
    '      Width = 120' + CRLF +
    '    end' + CRLF +
    '  end' + CRLF +
    '  object Edit1: TEdit' + CRLF +
    '  end' + CRLF +
    '  object Label1: TLabel' + CRLF +
    '    FocusControl = Edit1' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
  PAS =
    'unit Unit1;' + CRLF + 'interface' + CRLF + 'uses Vcl.Forms, Vcl.StdCtrls, Unit2;' + CRLF +
    'type' + CRLF + '  TForm1 = class(TForm)' + CRLF + '    Frame11: TFrame1;' + CRLF +
    '    Edit1: TEdit;' + CRLF + '    Label1: TLabel;' + CRLF + '  end;' + CRLF +
    'implementation' + CRLF + 'end.' + CRLF;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  NuevoDfm, NuevoPas, R: string;
begin
  Doc := TStyleDoc.DeTexto(DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Frame11'), PAS, 'Unit1.pas', Imp, NuevoDfm, NuevoPas);
  finally
    Doc.Free;
  end;
  Assert.AreEqual('', R);
  Assert.AreEqual('Frame11', string.Join(',', Imp.Nombres), 'lo de dentro del frame es del frame');
  Assert.Contains(NuevoPas, '    Edit1: TEdit;', 'el campo del Edit1 del form se queda');
  Assert.DoesNotContain(NuevoPas, 'Frame11: TFrame1');
  Assert.Contains(NuevoDfm, '    FocusControl = Edit1', 'y la linea que nombra al del form');
end;

{ Un metodo lleva el nombre de un componente por sus bordes de palabra, como
  los escribe el IDE: Ok no es de Lookup, que se borraba vacio con el
  (revision de la 1.17.0). }
procedure TDesignerEditTests.MetodoPorSusBordes;
const
  DFM = 'object Form1: TForm1' + CRLF + '  object Ok: TButton' + CRLF + '  end' + CRLF + 'end' + CRLF;
  PAS =
    'unit Unit1;' + CRLF + 'interface' + CRLF + 'uses Vcl.Forms, Vcl.StdCtrls;' + CRLF + 'type' + CRLF +
    '  TForm1 = class(TForm)' + CRLF + '    Ok: TButton;' + CRLF +
    '    procedure OkClick(Sender: TObject);' + CRLF + '    procedure Lookup;' + CRLF +
    '    procedure ValidaOk;' + CRLF + '  end;' + CRLF + 'implementation' + CRLF +
    'procedure TForm1.OkClick(Sender: TObject);' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'procedure TForm1.Lookup;' + CRLF + 'begin' + CRLF + 'end;' + CRLF +
    'procedure TForm1.ValidaOk;' + CRLF + 'begin' + CRLF + 'end;' + CRLF + 'end.' + CRLF;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
begin
  Doc := TStyleDoc.DeTexto(DFM);
  try
    Imp := AnalizaImpacto(Doc, Doc.ObjetoDeNombre('Ok'), False, PAS, 'Unit1.pas');
  finally
    Doc.Free;
  end;
  Assert.AreEqual('OkClick;ValidaOk;', Nombres(Imp), 'Lookup lleva ok, pero no por sus bordes');
end;

{ Un comentario entre la cabecera de un manejador y su begin tambien es
  contenido: se borraba con el (revision de la 1.17.0). }
procedure TDesignerEditTests.ComentarioAntesDelBeginEsCuerpo;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Dfm, Pas, Con, R: string;
begin
  Con := StringReplace(FORM_PAS, 'procedure TForm1.Button2Vacio(Sender: TObject);' + CRLF + 'begin',
    'procedure TForm1.Button2Vacio(Sender: TObject);' + CRLF + '// TODO validar' + CRLF + 'begin', []);
  Doc := TStyleDoc.DeTexto(FORM_DFM);
  try
    R := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'), Con, 'Unit1.pas', Imp, Dfm, Pas);
  finally
    Doc.Free;
  end;
  Assert.StartsWith('[DSGN-086', R, 'su manejador tiene un comentario: se niega');
end;

{ Quitar la linea de un campo con una directiva, o con un comentario que
  sigue en la de debajo, dejaria la otra mitad: se niega (revision de la
  1.17.0). Uno cerrado en su linea se va con el. }
procedure TDesignerEditTests.CampoConDirectivaSeNiega;

  function Borra(const AQue: string; out APas: string): string;
  var
    Doc: TStyleDoc;
    Imp: TImpacto;
    Dfm: string;
  begin
    Doc := TStyleDoc.DeTexto(FORM_DFM);
    try
      Result := PlanDeBorrado(Doc, Doc.ObjetoDeNombre('Button2'),
        StringReplace(FORM_PAS, '    Button2: TButton;', AQue, []), 'Unit1.pas', Imp, Dfm, APas);
    finally
      Doc.Free;
    end;
  end;

var
  Pas: string;
begin
  Assert.StartsWith('[DSGN-108', Borra('    Button2: TButton; {$IFDEF DEBUG}' + CRLF +
    '    Extra: Integer; {$ENDIF}', Pas));
  Assert.StartsWith('[DSGN-108', Borra('    Button2: TButton; { empieza aqui' + CRLF +
    '      y acaba aqui }', Pas));
  Assert.AreEqual('', Borra('    Button2: TButton; // el segundo', Pas));
  Assert.DoesNotContain(Pas, 'el segundo', 'un comentario de su linea se va con el');
end;

{ Un enumerado es UN identificador (ReadIdent: el valor, o Tipo.valor, que
  GetEnumValue tambien lee) y un conjunto, nombres entre corchetes (ReadSet).
  Un numero o una cadena se escribian y el form no cargaba (revision de la
  1.17.0). }
procedure TDesignerEditTests.EnumeradoYConjuntoComoLosLee;
var
  M: TMetaTable;
  Id: string;
  H: TPropRec;
  Hay: Boolean;

  function Juzga(const AProp, AValor: string): string;
  begin
    Result := JuzgaPropiedad(M, Id, AProp, AValor, H, Hay);
  end;

begin
  M := TMetaTable.Create(['C Vcl.Controls:TCosa',
    'P Vcl.Controls:TCosa Align e Vcl.Controls:TAlign', 'E Vcl.Controls:TAlign alNone,alClient',
    'P Vcl.Controls:TCosa Visible e Boolean', 'E Boolean False,True',
    'P Vcl.Controls:TCosa Anchors s Vcl.Controls:TAnchors', 'S Vcl.Controls:TAnchors akLeft,akTop']);
  try
    Assert.IsTrue(M.ClaseDeNombre('TCosa', Id));
    Assert.AreEqual('', Juzga('Align', 'alClient'));
    Assert.AreEqual('', Juzga('Align', 'TAlign.alClient'), 'el nombre de su tipo delante');
    Assert.AreNotEqual('', Juzga('Align', 'Vcl.Controls.TAlign.alClient'), 'con la unidad no');
    Assert.AreNotEqual('', Juzga('Align', '2'), 'un numero no');
    Assert.AreNotEqual('', Juzga('Align', '''alClient'''), 'una cadena no');
    Assert.AreEqual('', Juzga('Visible', 'True'));
    Assert.AreNotEqual('', Juzga('Visible', '1'));
    Assert.AreEqual('', Juzga('Anchors', '[akLeft, akTop]'));
    Assert.AreEqual('', Juzga('Anchors', '[]'));
    Assert.AreNotEqual('', Juzga('Anchors', '[akLeft,]'), 'un elemento vacio');
    Assert.AreNotEqual('', Juzga('Anchors', '3'));
    Assert.AreNotEqual('', Juzga('Anchors', '''akLeft'''));
  finally
    M.Free;
  end;
end;

{ Quien recibe controles en el disenador lo dice el ControlStyle que pone su
  constructor (csAcceptsControls), y si el texto sigue al nombre en la VCL,
  csSetCaption (lo mira el SetName de TControl). Las formas del fuente de
  Delphi 13.1: un conjunto escrito, una constante suya con dos ramas que
  coinciden (TCustomEdit), uno que quita (TControlListButton). Lo que no se
  lee no se sabe, y no se niega por ello. }
procedure TDesignerEditTests.EstilosDelConstructor;
const
  FUENTE =
    'unit Medida;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'constructor TControl.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF + '  inherited;' + CRLF +
    '  FControlStyle := [csCaptureMouse, csClickEvents, csSetCaption, csDoubleClicks];' + CRLF + 'end;' + CRLF +
    // las de Vcl.ExtCtrls y Vcl.ComCtrls de 13.1 con su forma: el panel con su
    // segunda sentencia (no toca las dos banderas), y TCustomTabControl SI
    // recibe controles; el que no es TPageControl (la prueba llamaba
    // TCustomTabControl al cuerpo de TPageControl: segunda revision)
    'constructor TCustomPanel.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF + '  inherited Create(AOwner);' + CRLF +
    '  ControlStyle := [csAcceptsControls, csCaptureMouse, csClickEvents,' + CRLF +
    '    csSetCaption, csOpaque, csDoubleClicks, csReplicatable, csPannable, csGestures];' + CRLF +
    '  if StyleServices.Enabled then' + CRLF +
    '    ControlStyle := ControlStyle + [csParentBackground] - [csOpaque];' + CRLF +
    '  Width := 185;' + CRLF + 'end;' + CRLF +
    'constructor TCustomTabControl.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF +
    '  inherited Create(AOwner);' + CRLF + '  Width := 289;' + CRLF + '  TabStop := True;' + CRLF +
    '  ControlStyle := [csAcceptsControls, csDoubleClicks, csPannable, csGestures];' + CRLF + 'end;' + CRLF +
    'constructor TPageControl.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF + '  inherited Create(AOwner);' + CRLF +
    '  ControlStyle := [csDoubleClicks, csOpaque, csPannable, csGestures];' + CRLF + 'end;' + CRLF +
    'constructor TCustomEdit.Create(AOwner: TComponent);' + CRLF + 'const' + CRLF +
    '  EditStyle = [csClickEvents, csSetCaption, csDoubleClicks, csFixedHeight];' + CRLF +
    'begin' + CRLF + '  inherited;' + CRLF + '  if NewStyleControls then' + CRLF +
    '    ControlStyle := EditStyle else' + CRLF + '    ControlStyle := EditStyle + [csFramed];' + CRLF + 'end;' + CRLF +
    'constructor TControlListButton.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF + '  inherited;' + CRLF +
    '  ControlStyle := ControlStyle - [csSetCaption];' + CRLF + 'end;' + CRLF +
    'constructor TRara.Create(AOwner: TComponent);' + CRLF + 'begin' + CRLF + '  inherited;' + CRLF +
    '  ControlStyle := EstiloQueNoEsta;' + CRLF + '  Include(FControlStyle, csAcceptsControls);' + CRLF + 'end;' + CRLF +
    'end.' + CRLF;
var
  M: TMetaTable;
  Id: string;
begin
  Assert.AreEqual('TControl -+|TCustomPanel ++|TCustomTabControl +-|TPageControl --|TCustomEdit -+|' +
    'TControlListButton .-|TRara ??', string.Join('|', EstilosDeTexto(FUENTE)));
  M := TMetaTable.Create([
    'C Vcl.Controls:TControl', 'T Vcl.Controls:TControl 1', 'K Vcl.Controls:TControl -+',
    'C Vcl.Controls:TWinControl', 'H Vcl.Controls:TWinControl Vcl.Controls:TControl',
    'C Vcl.ExtCtrls:TPanel', 'H Vcl.ExtCtrls:TPanel Vcl.Controls:TWinControl', 'K Vcl.ExtCtrls:TPanel ++',
    'C Vcl.ComCtrls:TPageControl', 'H Vcl.ComCtrls:TPageControl Vcl.Controls:TWinControl',
    'K Vcl.ComCtrls:TPageControl --',
    'C Vcl.ComCtrls:TTabSheet', 'H Vcl.ComCtrls:TTabSheet Vcl.Controls:TWinControl', 'K Vcl.ComCtrls:TTabSheet +.',
    'C Vcl.StdCtrls:TButton', 'H Vcl.StdCtrls:TButton Vcl.Controls:TWinControl', 'K Vcl.StdCtrls:TButton -+',
    'C Vcl.ControlList:TControlListButton', 'H Vcl.ControlList:TControlListButton Vcl.StdCtrls:TButton',
    'K Vcl.ControlList:TControlListButton .-',
    'C Vcl.Rara:TRara', 'H Vcl.Rara:TRara Vcl.Controls:TWinControl', 'K Vcl.Rara:TRara ??']);
  try
    Assert.IsTrue(M.ClaseDeNombre('TPanel', Id) and M.AceptaControles(Id));
    Assert.IsTrue(M.ClaseDeNombre('TTabSheet', Id) and M.AceptaControles(Id));
    Assert.IsTrue(M.ClaseDeNombre('TPageControl', Id) and not M.AceptaControles(Id), 'sus paginas, no el');
    Assert.IsTrue(M.ClaseDeNombre('TButton', Id) and not M.AceptaControles(Id));
    Assert.IsTrue(M.ClaseDeNombre('TRara', Id) and M.AceptaControles(Id), 'no se sabe: no se niega');
    Assert.IsTrue(M.ClaseDeNombre('TButton', Id) and M.TextoSigueAlNombre(Id));
    Assert.IsTrue(M.ClaseDeNombre('TControlListButton', Id) and not M.TextoSigueAlNombre(Id),
      'quita csSetCaption: su Caption no sigue al nombre');
    Assert.IsTrue(M.ClaseDeNombre('TTabSheet', Id) and M.TextoSigueAlNombre(Id), 'hereda el csSetCaption de TControl');
  finally
    M.Free;
  end;
end;

procedure TDesignerEditTests.HechosDelFuenteDeLaInstalacion;
var
  Raiz, A: string;

  function Lee(const ARel: string): string;
  begin
    Result := TFile.ReadAllText(TPath.Combine(Raiz, ARel));
  end;

  function Tiene(const AHechos: TArray<string>; const AHecho: string): Boolean;
  begin
    Result := False;
    for var H in AHechos do
      if H = AHecho then
        Exit(True);
  end;

begin
  // los hechos medidos en el fuente REAL de la instalacion activa: un fixture
  // es una teoria (el IdentToAlphaColor inventado no tenia sus locales y la
  // tabla real salio sin nombres; el TCustomTabControl tenia la forma de un
  // TPageControl: segunda revision de la 1.17.0). Sin el fuente, no se mide.
  Raiz := DiscoverRadStudio.RootDir;
  if (Raiz = '') or not TDirectory.Exists(TPath.Combine(Raiz, 'source')) then
  begin
    Assert.Pass('sin el fuente de la instalacion: no se mide');
    Exit;
  end;
  Raiz := TPath.Combine(Raiz, 'source');
  Assert.IsTrue(Tiene(EstilosDeTexto(Lee('vcl\Vcl.Controls.pas')), 'TControl -+'), 'TControl');
  Assert.IsTrue(Tiene(EstilosDeTexto(Lee('vcl\Vcl.ExtCtrls.pas')), 'TCustomPanel ++'), 'TCustomPanel');
  var V := EstilosDeTexto(Lee('vcl\Vcl.ComCtrls.pas'));
  Assert.IsTrue(Tiene(V, 'TPageControl --') and Tiene(V, 'TTabSheet +.') and Tiene(V, 'TToolBar ++') and
    Tiene(V, 'TCustomTabControl +-'),
    'TPageControl no recibe controles, sus paginas si: ' + string.Join('|', V));
  V := EstilosDeTexto(Lee('vcl\Vcl.StdCtrls.pas'));
  Assert.IsTrue(Tiene(V, 'TCustomGroupBox ++') and Tiene(V, 'TCustomEdit -+'), string.Join('|', V));
  Assert.IsTrue(Tiene(SetNamesDeTexto(Lee('vcl\Vcl.ExtCtrls.pas')), 'TCustomLabeledEdit 0'),
    'el Caption que pone es el de su etiqueta, y su Text lo vacia');
  Assert.IsTrue(Tiene(SetNamesDeTexto(Lee('fmx\FMX.Controls.pas')), 'TTextControl 1'));
  Assert.IsTrue(Tiene(SetNamesDeTexto(Lee('fmx\FMX.Edit.pas')), 'TEditButton 0'));
  A := '';
  for var L in ConstantesDeTexto(Lee('rtl\common\System.UIConsts.pas')) do
    if L.StartsWith('A IdentToAlphaColor ') then
      A := L;
  Assert.IsTrue(A.Contains('claAliceblue') and A.Contains(',claRed,') and A.EndsWith(';hex=x;ins=2a'),
    'la lista abierta con sus nombres y sus formas: ' +
    Copy(A, 1, 80));
end;

procedure TDesignerEditTests.RenombreConservaElOrden;
var
  Doc: TStyleDoc;
  Imp: TImpacto;
  Nuevo, Pas: string;
begin
  // lo que va detras de la clase (' [2]', el orden de un hijo en una form
  // heredada) se queda al renombrar (revision de la 1.17.0, sin prueba hasta
  // la segunda)
  Doc := TStyleDoc.DeTexto('object Form1: TForm1' + CRLF + '  object Boton: TButton [2]' + CRLF +
    '    Caption = ''Boton''' + CRLF + '  end' + CRLF + 'end' + CRLF);
  try
    Assert.AreEqual('', PlanDeRenombre(Doc, Doc.ObjetoDeNombre('Boton'), 'BtnOk', '', 'Unit1.pas', [],
      Imp, Nuevo, Pas));
    Assert.Contains(Nuevo, '  object BtnOk: TButton [2]');
  finally
    Doc.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDesignerEditTests);

end.
