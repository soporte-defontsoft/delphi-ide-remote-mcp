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
    [Test] procedure DesciendeYJuez;
    [Test] procedure LaMasParecida;
    [Test] procedure TextoSigueAlNombreDelFuente;
    [Test] procedure LineaCompartidaNoSeBorra;
    [Test] procedure DosCamposDeUnaLinea;
    [Test] procedure ConstantesDelFuente;
    [Test] procedure ValorPorLaBaseDeSuTipo;
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
  Lsp.DesignerMeta,
  Lsp.DesignerMetaGen,
  Lsp.DesignerEdit;

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
    R := PlanDeRenombre(Doc, Doc.ObjetoDeNombre('Button2'), 'BtnDos', FORM_PAS, 'Unit1.pas', True, Imp, Dfm, Pas);
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

procedure TDesignerEditTests.LiteralComoElIde;
var
  Clave, Nombre, Clase: string;
begin
  Assert.AreEqual('''Acci''#243''n''', LiteralDeForm('Acci' + #$F3 + 'n'));
  Assert.AreEqual('''It''''s''', LiteralDeForm('It''s'));
  Assert.AreEqual('''''', LiteralDeForm(''));
  Assert.AreEqual('#9''a''', LiteralDeForm(#9'a'));
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
    'procedure TOtra.SetName(const Value: TComponentName);' + CRLF +
    'begin' + CRLF + '  inherited SetName(Value);' + CRLF + '  FEtiqueta := Value;' + CRLF + 'end;' + CRLF +
    'end.' + CRLF;
var
  M: TMetaTable;
  Id: string;
begin
  Assert.AreEqual('TTextControl 1|TPresentedTextControl 1|TSkLabel 1|TEditButton 0|TOtra 0',
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
    '  AlphaColors: array [0..0] of TIdentMapEntry = (' + CRLF +
    '    (Value: TAlphaColors.Red; Name: ''claRed''));' + CRLF +
    'function IdentToColor(const Ident: string; var Color: Integer): Boolean;' + CRLF +
    'begin' + CRLF + '  Result := IdentToInt(Ident, Color, Colors);' + CRLF + 'end;' + CRLF +
    'function IdentToCursor(const Ident: string; var Cursor: Integer): Boolean;' + CRLF +
    'begin' + CRLF + '  Result := IdentToInt(Ident, Cursor, Cursors);' + CRLF + 'end;' + CRLF +
    'function IdentToAlphaColor(const Ident: string; var Color: Integer): Boolean;' + CRLF +
    'begin' + CRLF + '  if (Ident <> '''') and (Ident[1] = ''x'') then' + CRLF +
    '    Result := True' + CRLF + '  else' + CRLF +
    '    Result := IdentToInt(Ident, Integer(Color), AlphaColors);' + CRLF + 'end;' + CRLF +
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
    'L IdentToColor clBlack,clRed|L IdentToCursor crDefault,crHandPoint',
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
  P: string;

  function Juzga(const AProp, AValor: string): string;
  begin
    Result := BaseQueNoCasa(M, M.Props[ClaveProp('Vcl.Controls:TCosa', AProp)], AValor, P);
  end;

begin
  M := TMetaTable.Create(['C Vcl.Controls:TCosa',
    'P Vcl.Controls:TCosa Color o TColor', 'P Vcl.Controls:TCosa Cursor o TCursor',
    'P Vcl.Controls:TCosa Fondo o TAlphaColor', 'P Vcl.Controls:TCosa Letra o Char',
    'P Vcl.Controls:TCosa Peso o Double', 'P Vcl.Controls:TCosa Titulo o TCaption',
    'P Vcl.Controls:TCosa Grande o Int64', 'P Vcl.Controls:TCosa Raro o TRaro',
    'P Vcl.Controls:TCosa Opacidad o Single', 'B Single single',
    'B TColor integer', 'B TCursor integer', 'B TAlphaColor integer', 'B Char char',
    'B Double float', 'B TCaption string', 'B Int64 int64',
    'I TColor clBlack,clRed', 'I TAlphaColor *']);
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
    Assert.AreEqual('', Juzga('Fondo', 'xFFFF0000'), 'su IdentTo hace mas que buscar: cualquiera');
    Assert.AreNotEqual('', Juzga('Fondo', '''rojo'''));
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

initialization
  TDUnitX.RegisterTestFixture(TDesignerEditTests);

end.
