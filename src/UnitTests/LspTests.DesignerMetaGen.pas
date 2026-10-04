unit LspTests.DesignerMetaGen;

// Las tablas del disenador sacadas del FUENTE (1.12.0): el preprocesador con
// los simbolos derivados de la version (Lsp.Preproceso), el lector de
// declaraciones (Lsp.PascalDecl), el generador sobre un fuente de mentira
// escrito aqui (Lsp.DesignerMetaGen) y la herencia que usa el lint para no
// negar lo que publica un descendiente (Lsp.DesignerMeta). Lo que se mide
// contra el fuente real de RAD Studio (100 % de las tablas de la RTTI de la
// 1.11.3) lo dice la nota designer-meta-por-version del vault: aqui va lo
// que cada regla tiene que seguir haciendo.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPreprocesoTests = class
  public
    [Test] procedure LosSimbolosSalenDeLaVersion;
    [Test] procedure SeTomaLaRamaQueToca;
    [Test] procedure UnDefineSoloCuentaEnLoActivo;
    [Test] procedure LoComentadoNoEsDirectiva;
    [Test] procedure UnIncludeSeMeteEnSuSitio;
    [Test] procedure LasExpresionesDeUnIf;
  end;

  [TestFixture]
  TPascalDeclTests = class
  public
    [Test] procedure UnaClaseConSusSecciones;
    [Test] procedure LosTiposSimples;
    [Test] procedure LosAnidadosDeUnRecord;
    [Test] procedure ElImplementationYSusRutinas;
    [Test] procedure LasConstantesDelInterface;
    [Test] procedure LoQueCortabaLaUnidad;
  end;

  [TestFixture]
  TDesignerMetaGenTests = class
  private
    FDir: string;
    procedure Escribe(const ANombre, ATexto: string);
    function Hechos(const ALista: TArray<string>; const AHecho: string): Boolean;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure LasTablasDeUnFuenteDeMentira;
    [Test] procedure LasReglasQueSalieronDeMedir;
    [Test] procedure ElNombradorYSuLector;
    [Test] procedure LaHuellaCambiaConElFuente;
    [Test] procedure LoQuePublicaUnDescendiente;
    [Test] procedure LasClasesPorSuIdentidad;
    [Test] procedure LoQueSeGuardaPorCodigo;
    [Test] procedure ElLintConUnaTabla;
    [Test] procedure LosAncestrosRaros;
    [Test] procedure LosAyudantesDeUnDefineProperties;
    [Test]
    procedure LoPublicadoAntesQueLoGuardado;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.IOUtils,
  System.Generics.Collections,
  Lsp.Preproceso,
  Lsp.PascalDecl,
  Lsp.DesignerMetaGen,
  Lsp.DesignerMeta;

function Codigo(const S: string): string;
begin
  // el texto activo sin blancos de mas: lo que importa es que va y que no
  Result := ' ' + string.Join(' ', S.Split([' ', #13, #10, #9],
    TStringSplitOptions.ExcludeEmpty)) + ' ';
end;

{ TPreprocesoTests }

procedure TPreprocesoTests.LosSimbolosSalenDeLaVersion;
var
  S: TSimbolosPascal;
  V: Double;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    Assert.IsTrue(S.Definido('VER370'), 'VER370');
    Assert.IsTrue(S.Definido('win64') and S.Definido('CPUX64') and S.Definido('MSWINDOWS'));
    Assert.IsFalse(S.Definido('WIN32'), 'Win64 no es Win32');
    Assert.IsTrue(S.Constante('CompilerVersion', V) and SameValue(V, 37.0));
    Assert.AreEqual<Integer>(8, S.Tamano('Pointer'));
  finally
    S.Free;
  end;
  // otra version, otra cosa: derivado, no una lista
  S := SimbolosDeDelphi('36.0', 'Win32');
  try
    Assert.IsTrue(S.Definido('VER360') and not S.Definido('VER370'), 'VER360');
    Assert.IsTrue(S.Definido('WIN32') and not S.Definido('WIN64'));
    Assert.AreEqual<Integer>(4, S.Tamano('Pointer'));
  finally
    S.Free;
  end;
end;

procedure TPreprocesoTests.SeTomaLaRamaQueToca;
var
  S: TSimbolosPascal;
  T: string;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    T := Codigo(TextoActivo(
      'A {$IFDEF WIN64} B {$ELSE} C {$ENDIF} D'#13#10 +
      '{$IFNDEF LINUX} E {$ENDIF}'#13#10 +
      '{$IF CompilerVersion >= 38} F {$ELSEIF CompilerVersion >= 37} G {$ELSE} H {$IFEND}'#13#10 +
      '{$IFDEF LINUX} {$IFDEF WIN64} I {$ELSE} J {$ENDIF} {$ELSE} K {$ENDIF}', S));
    Assert.AreEqual(' A B D E G K ', T);
  finally
    S.Free;
  end;
end;

procedure TPreprocesoTests.UnDefineSoloCuentaEnLoActivo;
var
  S: TSimbolosPascal;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    Assert.AreEqual(' X Y ', Codigo(TextoActivo(
      '{$IFDEF LINUX}{$DEFINE MIO}{$ENDIF}{$DEFINE TUYO}'#13#10 +
      '{$IFDEF MIO} W {$ENDIF}{$IFDEF TUYO} X {$ENDIF}'#13#10 +
      '{$UNDEF TUYO}{$IFDEF TUYO} Z {$ELSE} Y {$ENDIF}', S)));
    Assert.IsFalse(S.Definido('MIO'));
  finally
    S.Free;
  end;
end;

procedure TPreprocesoTests.LoComentadoNoEsDirectiva;
var
  S: TSimbolosPascal;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    // un IFDEF dentro de un comentario o de una cadena no abre nada, y los
    // comentarios y las cadenas salen en blanco
    Assert.AreEqual(' A B C ', Codigo(TextoActivo(
      'A // {$IFDEF LINUX}'#13#10 + 'B (* {$IFDEF LINUX} *) ''{$IFDEF LINUX}'' C', S)));
  finally
    S.Free;
  end;
end;

procedure TPreprocesoTests.UnIncludeSeMeteEnSuSitio;
var
  S: TSimbolosPascal;
  Pedidos: string;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    Pedidos := '';
    Assert.AreEqual(' A INC B ', Codigo(TextoActivo('A {$I mio.inc} {$I+} {$I-} B', S,
      function(const N: string): string
      begin
        Pedidos := Pedidos + '[' + N + ']';
        Result := '{$DEFINE DELINC} {$IFDEF DELINC} INC {$ENDIF}';
      end)));
    Assert.AreEqual('[mio.inc]', Pedidos, 'el interruptor $I+/$I- no es un include');
    Assert.IsTrue(S.Definido('DELINC'), 'lo que define el include sigue definido');
  finally
    S.Free;
  end;
end;

procedure TPreprocesoTests.LasExpresionesDeUnIf;
var
  S: TSimbolosPascal;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    S.PonConstante('RTLVersion131', 1);
    Assert.IsTrue(EvaluaCondicion('Defined(MSWINDOWS) and not Defined(LINUX)', S));
    Assert.IsTrue(EvaluaCondicion('SizeOf(Pointer) = 8', S));
    Assert.IsTrue(EvaluaCondicion('Declared(RTLVersion131)', S));
    Assert.IsFalse(EvaluaCondicion('Declared(System.Embedded)', S));
    Assert.IsTrue(EvaluaCondicion('(CompilerVersion < 35) or ((CompilerVersion = 37) and not DECLARED(RTLVersion112))', S));
    Assert.IsFalse(EvaluaCondicion('FPC_FULLVERSION >= 30000', S), 'lo que no se conoce vale 0');
    Assert.IsTrue(EvaluaCondicion('not CompilerVersion >= 38', S), 'not de una comparacion');
    Assert.IsTrue(EvaluaCondicion('RTLVersion >= 14.5', S));
  finally
    S.Free;
  end;
end;

{ TPascalDeclTests }

function Tipo(AU: TUnidadPas; const ANombre: string): TTipoPas;
begin
  for var T in AU.Tipos do
    if SameText(T.NombreCompleto, ANombre) then
      Exit(T);
  Result := nil;
end;

function Prop(AT: TTipoPas; const ANombre: string; out AP: TPropiedadPas): Boolean;
begin
  for var P in AT.Propiedades do
    if SameText(P.Nombre, ANombre) then
    begin
      AP := P;
      Exit(True);
    end;
  Result := False;
end;

procedure TPascalDeclTests.UnaClaseConSusSecciones;
var
  U: TUnidadPas;
  T: TTipoPas;
  P: TPropiedadPas;
begin
  U := LeeUnidadPascal(
    'unit Uno; interface uses System.Classes, Otra in        ; type'#13#10 +
    'TFoo = class; '#13#10 +
    'TFoo = class(TBar<Integer>, IUno, IDos)'#13#10 +
    '  FA: Integer; Message: string;'#13#10 +
    '  property Nada: Integer read FA;'#13#10 +
    'strict private procedure X(var M: TMessage); message WM_X; virtual;'#13#10 +
    'public type TEstilo = (esUno, esDos);'#13#10 +
    '  property Items[I: Integer]: Integer read GetI; default;'#13#10 +
    '  class property Cuantos: Integer read GetC;'#13#10 +
    'published'#13#10 +
    '  property Caption;'#13#10 +
    '  property Color: System.UITypes.TColor read FC write FC default 0;'#13#10 +
    '  property Estilo: TEstilo read FE;'#13#10 +
    'end;'#13#10 +
    'implementation end.');
  try
    Assert.AreEqual('Uno', U.Nombre);
    Assert.AreEqual<Integer>(2, Length(U.UsesInterface));
    Assert.AreEqual('Otra', U.UsesInterface[1]);
    T := Tipo(U, 'TFoo');
    Assert.IsNotNull(T, 'la declaracion adelantada no tapa la de verdad');
    Assert.AreEqual('TBar', T.Ancestro, 'el ancestro sin sus <...> ni las interfaces');
    Assert.IsTrue(Prop(T, 'Nada', P) and (P.Visibilidad = vpDefecto));
    Assert.IsTrue(Prop(T, 'Items', P) and P.ConIndices and (P.Visibilidad = vpPublica));
    Assert.IsTrue(Prop(T, 'Cuantos', P) and P.DeClase);
    Assert.IsTrue(Prop(T, 'Caption', P) and (P.Tipo = '') and (P.Visibilidad = vpPublicada),
      'redeclarada sin tipo');
    Assert.IsTrue(Prop(T, 'Color', P) and (P.Tipo = 'System.UITypes.TColor'));
    Assert.IsTrue(Prop(T, 'Estilo', P) and (P.Tipo = 'TEstilo'));
    Assert.IsNotNull(Tipo(U, 'TFoo.TEstilo'), 'el anidado, con su clase');
    Assert.AreEqual<Integer>(6, Length(T.Propiedades), 'ni el campo Message ni el metodo con message cuentan');
  finally
    U.Free;
  end;
end;

procedure TPascalDeclTests.LosTiposSimples;
var
  U: TUnidadPas;
begin
  U := LeeUnidadPascal(
    'unit Dos; interface type'#13#10 +
    'TAlign = (alNone, alTop = 2, alBottom);'#13#10 +
    'TAligns = set of TAlign;'#13#10 +
    'TEnLinea = set of (elA, elB);'#13#10 +
    'TColor = -$7FFFFFFF-1..$7FFFFFFF;'#13#10 +
    'TCaption = type string;'#13#10 +
    'TOtro = System.UITypes.TColor deprecated;'#13#10 +
    'TEvento = procedure(Sender: TObject) of object; stdcall;'#13#10 +
    'TProc = reference to procedure;'#13#10 +
    'TClase = class of TFoo;'#13#10 +
    'PFoo = ^TFoo;'#13#10 +
    'implementation end.');
  try
    Assert.AreEqual(Ord(ctEnumerado), Ord(Tipo(U, 'TAlign').Clase));
    Assert.AreEqual('alNone,alTop,alBottom', string.Join(',', Tipo(U, 'TAlign').Miembros));
    Assert.AreEqual('TAlign', Tipo(U, 'TAligns').Base);
    Assert.AreEqual('elA,elB', string.Join(',', Tipo(U, 'TEnLinea').Miembros));
    Assert.AreEqual(Ord(ctSubrango), Ord(Tipo(U, 'TColor').Clase));
    Assert.IsTrue((Tipo(U, 'TCaption').Clase = ctAlias) and Tipo(U, 'TCaption').Fuerte);
    Assert.IsTrue((Tipo(U, 'TOtro').Clase = ctAlias) and not Tipo(U, 'TOtro').Fuerte);
    Assert.AreEqual('System.UITypes.TColor', Tipo(U, 'TOtro').Base);
    Assert.AreEqual(Ord(ctMetodo), Ord(Tipo(U, 'TEvento').Clase));
    Assert.AreEqual(Ord(ctProcedimiento), Ord(Tipo(U, 'TProc').Clase));
    Assert.AreEqual(Ord(ctReferenciaClase), Ord(Tipo(U, 'TClase').Clase));
    Assert.AreEqual(Ord(ctOtro), Ord(Tipo(U, 'PFoo').Clase));
  finally
    U.Free;
  end;
end;

procedure TPascalDeclTests.LosAnidadosDeUnRecord;
var
  U: TUnidadPas;
begin
  U := LeeUnidadPascal(
    'unit Tres; interface type'#13#10 +
    'TOSVersion = record'#13#10 +
    'public type TArch = (arX86, arX64); TPlat = (pfWin, pfMac);'#13#10 +
    'private class var FArch: TArch; '#13#10 +
    '  F: record A: Integer; end; '#13#10 +
    '  case Integer of 0: (X: Integer); 1: (Y: Byte);'#13#10 +
    'end;'#13#10 +
    'TArchs = set of TOSVersion.TArch;'#13#10 +
    'implementation end.');
  try
    Assert.IsNotNull(Tipo(U, 'TOSVersion.TArch'), 'el enumerado del record');
    Assert.IsNotNull(Tipo(U, 'TOSVersion.TPlat'));
    Assert.AreEqual('TOSVersion.TArch', Tipo(U, 'TArchs').Base, 'y lo de detras del record se sigue leyendo');
  finally
    U.Free;
  end;
end;

procedure TPascalDeclTests.ElImplementationYSusRutinas;
var
  U: TUnidadPas;
begin
  U := LeeUnidadPascal(
    'unit Cuatro; interface type TA = class(TPersistent) end;'#13#10 +
    'procedure Suelta; overload; external ''x'' name ''y'';'#13#10 +
    'implementation uses Vcl.Graphics;'#13#10 +
    'type TPrivada = class(TA) published property P: Integer; end;'#13#10 +
    'procedure TA.Metodo(const X: Integer); var L: record A: Integer; end;'#13#10 +
    '  procedure Dentro; begin case X of 1: begin end; end; end;'#13#10 +
    'begin try Dentro; finally end; end;'#13#10 +
    'type TOtra = class(TPrivada) end;'#13#10 +
    'initialization TA.Create; end.');
  try
    Assert.AreEqual('Vcl.Graphics', U.UsesImplementation[0]);
    Assert.IsTrue(Tipo(U, 'TPrivada').EnImplementation);
    Assert.IsFalse(Tipo(U, 'TA').EnImplementation);
    Assert.IsNotNull(Tipo(U, 'TOtra'), 'lo que va detras de una rutina con sus bloques se sigue leyendo');
  finally
    U.Free;
  end;
end;

procedure TPascalDeclTests.LasConstantesDelInterface;
var
  U: TUnidadPas;
begin
  U := LeeUnidadPascal(
    'unit System; interface const RTLVersion = 37.00; RTLVersion131 = True;'#13#10 +
    'CompilerVersion = 0.0; Raro: Integer = 3; MaxX = -1;'#13#10 +
    'implementation const Privada = 1; end.');
  try
    Assert.AreEqual('37.00', U.Constantes['RTLVersion']);
    Assert.AreEqual('True', U.Constantes['RTLVersion131']);
    Assert.IsFalse(U.Constantes.ContainsKey('Raro'), 'una con tipo no');
    Assert.IsFalse(U.Constantes.ContainsKey('Privada'), 'las del implementation no');
  finally
    U.Free;
  end;
end;

{ Lo que el revisor de la 1.12.0 vio cortar una unidad entera (o perder una
  clase), con el caso real de cada uno: un campo &Object (uMakerAi.Chat.
  Mistral), un array of record en una seccion type (JvProfilerForm, SynPdf),
  TFoo<T>=class sin espacio (Steema), las restricciones <T: class> y
  <T: record> en un record, un .&End en el implementation (FireDAC
  MongoDB), y la aridad de los genericos (REST.Backend.BindSource). }
procedure TPascalDeclTests.LoQueCortabaLaUnidad;
var
  U: TUnidadPas;
begin
  U := LeeUnidadPascal(
    'unit Cinco; interface type'#13#10 +
    'TMistralFile = record &Object: string; Id: string; end;'#13#10 +
    'TProf = array[0..1] of record A: Integer; B: Integer; end;'#13#10 +
    'TCelda<T>=class end;'#13#10 +
    'TReg = record procedure Uno<T: class>; procedure Dos<T: record, IFoo>;'#13#10 +
    '  procedure Tres<T: class, constructor>; end;'#13#10 +
    'TGen<A, B> = class(TBase) end;'#13#10 +
    'THija = class(TGen<Integer, string>) end;'#13#10 +
    'TUltima = class(TPersistent) published property P: Integer; end;'#13#10 +
    'implementation'#13#10 +
    'procedure X; begin Y.&End; end;'#13#10 +
    'type TImpl = class(TUltima) end;'#13#10 +
    'end.');
  try
    Assert.IsNotNull(Tipo(U, 'TMistralFile'), '&Object no es la palabra object');
    Assert.IsNotNull(Tipo(U, 'TCelda'), '>= sin espacio');
    Assert.IsNotNull(Tipo(U, 'TGen'), 'las restricciones <T: record> no se tragan lo que sigue');
    Assert.AreEqual<Integer>(2, Tipo(U, 'TGen').Aridad, 'TGen<A, B>');
    Assert.IsNotNull(Tipo(U, 'THija'));
    Assert.AreEqual<Integer>(2, Tipo(U, 'THija').AncestroAridad, 'su ancestro lleva dos');
    Assert.IsNotNull(Tipo(U, 'TUltima'), 'nada de lo de arriba corta la unidad');
    Assert.AreEqual<Integer>(0, Tipo(U, 'TUltima').Aridad);
    Assert.IsNotNull(Tipo(U, 'TImpl'), 'ni un .&End en el implementation');
  finally
    U.Free;
  end;
end;

{ TDesignerMetaGenTests }

procedure TDesignerMetaGenTests.Prepara;
begin
  FDir := TPath.Combine(ExtractFileDir(ParamStr(0)), 'metagen-prueba');
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  TDirectory.CreateDirectory(FDir);
end;

procedure TDesignerMetaGenTests.Limpia;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TDesignerMetaGenTests.Escribe(const ANombre, ATexto: string);
begin
  TFile.WriteAllText(TPath.Combine(FDir, ANombre), ATexto, TEncoding.UTF8);
end;

function TDesignerMetaGenTests.Hechos(const ALista: TArray<string>; const AHecho: string): Boolean;
begin
  for var H in ALista do
    if SameText(H, AHecho) then
      Exit(True);
  Result := False;
end;

procedure TDesignerMetaGenTests.LasTablasDeUnFuenteDeMentira;
var
  T: TTablasDeFuente;
  V, F: TArray<string>;
begin
  Escribe('System.pas', 'unit System; interface const RTLVersion = 37.00;'#13#10 +
    'type TObject = class end; TDateTime = type Double; implementation end.');
  Escribe('System.Classes.pas', 'unit System.Classes; interface type'#13#10 +
    'TComponentName = type string;'#13#10 +
    'TPersistent = class(TObject) end;'#13#10 +
    'TComponent = class(TPersistent) published property Name: TComponentName read FN;'#13#10 +
    '  property Tag: NativeInt read FT; end;'#13#10 +
    'TSuelta = class(TObject) published property NoVa: Integer; end;'#13#10 +
    'implementation end.');
  Escribe('Vcl.Controls.pas', 'unit Vcl.Controls; interface uses System.Classes; type'#13#10 +
    'TCaption = type string; TAlign = (alNone, alTop);'#13#10 +
    'TControl = class(TComponent) protected property Caption: TCaption read FC;'#13#10 +
    '  property Items[I: Integer]: Integer read GetI;'#13#10 +
    'published property Align: TAlign read FA; end;'#13#10 +
    'implementation end.');
  Escribe('Vcl.StdCtrls.pas', 'unit Vcl.StdCtrls; interface uses Vcl.Controls, System.Classes;'#13#10 +
    '{$I estilo.inc}'#13#10 +
    'type TTextSettings = class(TPersistent) published property Size: Integer; end;'#13#10 +
    'TButton = class(TControl) public type TButtonStyle = (bsPush, bsLink);'#13#10 +
    'published property Caption; property Items; property Style: TButtonStyle read FS;'#13#10 +
    '  {$IFDEF WIN64} property Solo64: Boolean; {$ENDIF}'#13#10 +
    '  {$IFDEF LINUX} property SoloLinux: Boolean; {$ENDIF}'#13#10 +
    '  property Texto: TTextSettings read FT; end;'#13#10 +
    'implementation'#13#10 +
    'type TButtonTextSettings = class(TTextSettings) published property Extra: Integer; end;'#13#10 +
    'end.');
  Escribe('estilo.inc', '{$DEFINE CONESTILO}');
  Escribe('FMX.Controls.pas', 'unit FMX.Controls; interface uses System.Classes; type'#13#10 +
    'TFmxCosa = class(TComponent) published property Opacity: Single; end;'#13#10 +
    'implementation end.');
  Escribe('Data.Neutra.pas', 'unit Data.Neutra; interface uses Classes; type'#13#10 +
    'TCosaDeDatos = class(TComponent) published property Activa: Boolean; end;'#13#10 +
    'implementation end.');
  T := GeneraTablasDeFuente([FDir], '37.0', 'Z:\no-es-bds');
  V := T.Hechos[mdVcl];
  F := T.Hechos[mdFmx];
  Assert.AreEqual<Integer>(6, T.Unidades);
  // la VCL
  // las clases, los enumerados y los conjuntos, por su IDENTIDAD con la unidad
  Assert.IsTrue(Hechos(V, 'C Vcl.StdCtrls:TButton'));
  Assert.IsTrue(Hechos(V, 'H Vcl.StdCtrls:TButton Vcl.Controls:TControl'));
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Name o TComponentName'), 'lo heredado, con su alias fuerte');
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Tag o Int64'), 'NativeInt, Int64: la plataforma es Win64');
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Caption o TCaption'), 'redeclarada: el tipo del ancestro');
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Style e Vcl.StdCtrls:TButton.TButtonStyle'),
    'el anidado con su clase');
  Assert.IsTrue(Hechos(V, 'E Vcl.StdCtrls:TButton.TButtonStyle bsPush,bsLink'));
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Align e Vcl.Controls:TAlign') and
    Hechos(V, 'E Vcl.Controls:TAlign alNone,alTop'));
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Solo64 e Boolean'), 'la rama de Win64; Boolean, del compilador');
  Assert.IsFalse(Hechos(V, 'P Vcl.StdCtrls:TButton SoloLinux e Boolean'), 'la de Linux no');
  Assert.IsFalse(Hechos(V, 'P Vcl.StdCtrls:TButton Items o Integer'), 'una con indices no va a un form');
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButton Texto c Vcl.StdCtrls:TTextSettings'));
  Assert.IsTrue(Hechos(V, 'H Vcl.StdCtrls:TButtonTextSettings Vcl.StdCtrls:TTextSettings'),
    'la del implementation y su padre');
  Assert.IsTrue(Hechos(V, 'P Vcl.StdCtrls:TButtonTextSettings Extra o Integer'));
  Assert.IsFalse(Hechos(V, 'C System.Classes:TSuelta'), 'una que no es persistente no va a un form');
  Assert.IsFalse(Hechos(V, 'C FMX.Controls:TFmxCosa'), 'lo de FMX no va a la VCL');
  Assert.IsTrue(Hechos(V, 'C Data.Neutra:TCosaDeDatos'), 'lo neutro, con un uses sin prefijo (Classes)');
  // la FMX
  Assert.IsTrue(Hechos(F, 'P FMX.Controls:TFmxCosa Opacity o Single'));
  Assert.IsTrue(Hechos(F, 'C Data.Neutra:TCosaDeDatos'), 'lo neutro va a las dos');
  Assert.IsFalse(Hechos(F, 'C Vcl.StdCtrls:TButton'), 'lo de Vcl no va a la FMX');
end;

{ Cada regla que hizo falta para que las tablas del fuente dieran lo mismo
  que las de la RTTI (100 % el 3-oct-2026), con el caso real que la pidio. }
procedure TDesignerMetaGenTests.LasReglasQueSalieronDeMedir;
var
  V: TArray<string>;
begin
  Escribe('System.pas', 'unit System; interface type TObject = class end; implementation end.');
  Escribe('System.SysUtils.pas', 'unit System.SysUtils; interface type'#13#10 +
    'TOSVersion = record public type TArch = (arX86, arX64); end;'#13#10 +
    'TArchs = set of TOSVersion.TArch;'#13#10 +
    'implementation end.');
  Escribe('System.Classes.pas', 'unit System.Classes; interface uses System.SysUtils; type'#13#10 +
    'TComponentName = type string; TColor = -$7FFFFFFF-1..$7FFFFFFF;'#13#10 +
    'TOverlayMode = (omNone, omAll);'#13#10 +
    'TPersistent = class(TObject) end;'#13#10 +
    'TComponent = class(TPersistent) published property Name: TComponentName read FN; end;'#13#10 +
    // la que tapa a la del ancestro (TCustomColorListBox.Selected)
    'TListaBase = class(TComponent) public property Selected[I: Integer]: Boolean read GetS; end;'#13#10 +
    'TListaColor = class(TListaBase) public property Selected: TColor read GetC; published property Selected; end;'#13#10 +
    // la publicada conserva su tipo (TInternetExplorer.Name)
    'TOleCosa = class(TComponent) public property Name: WideString read GetN; end;'#13#10 +
    // el alias anidado con el nombre de su destino (TOverlayMode)
    'TCapa = class(TComponent) public type TOverlayMode = TOverlayMode deprecated;'#13#10 +
    '  published property Mode: TOverlayMode read FM; property Visto: WordBool read FV; end;'#13#10 +
    // el conjunto de un enumerado de record (TArchitectures)
    'TAccion = class(TComponent) published property Archs: TArchs read FA;'#13#10 +
    // un tipo que el fuente no deja leer (su unidad no esta): '?', no 'o'
    '  property Conexion: TConexionDeFuera read FX; end;'#13#10 +
    'implementation end.');
  Escribe('Vcl.StdCtrls.pas', 'unit Vcl.StdCtrls; interface uses System.Classes; type'#13#10 +
    'TBoton = class(TComponent) public type TButtonStyle = (bsPush, bsLink); end;'#13#10 +
    'implementation end.');
  // los tipos de la unidad antes que el anidado heredado (TBitBtn.Style)
  Escribe('Vcl.Buttons.pas', 'unit Vcl.Buttons; interface uses System.Classes, Vcl.StdCtrls; type'#13#10 +
    'TButtonStyle = (bsAuto, bsNew);'#13#10 +
    'TBotonBit = class(TBoton) published property Style: TButtonStyle read FS; end;'#13#10 +
    'implementation end.');
  V := GeneraTablasDeFuente([FDir], '37.0', 'Z:\no-es-bds').Hechos[mdVcl];
  Assert.IsTrue(Hechos(V, 'P System.Classes:TListaColor Selected o TColor'),
    'una declaracion con tipo tapa a la del ancestro');
  Assert.IsTrue(Hechos(V, 'P System.Classes:TOleCosa Name o TComponentName'), 'la publicada conserva su tipo');
  Assert.IsTrue(Hechos(V, 'P System.Classes:TCapa Mode e System.Classes:TOverlayMode') and
    Hechos(V, 'E System.Classes:TOverlayMode omNone,omAll'), 'el alias anidado se resuelve fuera de su clase');
  Assert.IsTrue(Hechos(V, 'P System.Classes:TCapa Visto e WordBool'), 'WordBool es un enumerado');
  Assert.IsTrue(Hechos(V, 'P System.Classes:TAccion Archs s System.SysUtils:TArchs') and
    Hechos(V, 'S System.SysUtils:TArchs arX86,arX64'), 'el conjunto de un enumerado de record');
  Assert.IsTrue(Hechos(V, 'P Vcl.Buttons:TBotonBit Style e Vcl.Buttons:TButtonStyle'),
    'el de la unidad antes que el anidado heredado');
  Assert.IsTrue(Hechos(V, 'P System.Classes:TAccion Conexion ? TConexionDeFuera'),
    'lo que no se lee es ? (con o el lint decia que no tiene subpropiedades)');
end;

procedure TDesignerMetaGenTests.ElNombradorYSuLector;
var
  N, V, B, H: string;
  M: TMarcoDisenador;
  G: Integer;
begin
  N := NombreDeTabla('37.0', '37.0.59082.6021', mdFmx, 'a1b2c3d4e5f6');
  Assert.IsTrue(LeeNombreDeTabla('C:\x\' + N, V, B, M, H, G), N);
  Assert.AreEqual('37.0', V);
  Assert.AreEqual('37.0.59082.6021', B);
  Assert.AreEqual(Ord(mdFmx), Ord(M));
  Assert.AreEqual('a1b2c3d4e5f6', H);
  Assert.AreEqual(GENERACION_TABLAS, G);
  // la identidad de un tipo y sus tres lectores (el ':' se leia a mano)
  Assert.IsTrue(EsIdDeTipo(IdDeTipo('Vcl.Buttons', 'TButtonLayout')));
  Assert.AreEqual('Vcl.Buttons', UnidadDeIdDeTipo(IdDeTipo('Vcl.Buttons', 'TButtonLayout')));
  Assert.AreEqual('TButtonLayout', NombreDeIdDeTipo(IdDeTipo('Vcl.Buttons', 'TButtonLayout')));
  Assert.IsFalse(EsIdDeTipo(IdDeTipo('', 'Boolean')), 'los del compilador van sin unidad');
  Assert.AreEqual('', UnidadDeIdDeTipo('Boolean'));
  Assert.IsFalse(LeeNombreDeTabla('Proyecto-3F291B89-37_0-g2.delphilsp.json', V, B, M, H, G),
    'lo demas de la cache no es una tabla');
  Assert.IsFalse(LeeNombreDeTabla('tabla_37.0_x_otro_h_g1.txt', V, B, M, H, G), 'un marco que no existe');
end;

procedure TDesignerMetaGenTests.LaHuellaCambiaConElFuente;
var
  H1, H2: string;
begin
  Escribe('Uno.pas', 'unit Uno; interface implementation end.');
  H1 := HuellaDeCarpetas([FDir]);
  Assert.AreEqual(H1, HuellaDeCarpetas([FDir]), 'la misma carpeta, la misma huella');
  Escribe('nota.txt', 'esto no es fuente');
  Assert.AreEqual(H1, HuellaDeCarpetas([FDir]), 'lo que no es .pas ni .inc no cuenta');
  Escribe('Dos.pas', 'unit Dos; interface implementation end.');
  H2 := HuellaDeCarpetas([FDir]);
  Assert.AreNotEqual(H1, H2, 'una unidad nueva cambia la huella');
end;

procedure TDesignerMetaGenTests.LoQuePublicaUnDescendiente;
var
  M: TMetaTable;
  D: string;
begin
  M := TMetaTable.Create([
    'C TLabel', 'P TLabel TextSettings c TTextSettings',
    'C TTextSettings', 'H TTextSettings TPersistent', 'P TTextSettings Font c TFont',
    'C TLabelTextSettings', 'H TLabelTextSettings TTextSettings',
    'C TNietaTextSettings', 'H TNietaTextSettings TLabelTextSettings',
    'P TNietaTextSettings Trimming e TTextTrimming']);
  try
    Assert.IsTrue(M.PublicadaEnDescendiente('TTextSettings', 'Trimming', D), 'una nieta');
    Assert.AreEqual('tnietatextsettings', D);
    Assert.IsFalse(M.PublicadaEnDescendiente('TTextSettings', 'NoExiste', D));
    Assert.IsFalse(M.PublicadaEnDescendiente('TNietaTextSettings', 'Font', D),
      'hacia arriba no: lo del ancestro ya lo tiene la clase');
    // lo que publica la familia entera, para el aviso de lo que no publica nadie
    Assert.AreEqual('Font, Trimming', M.PublicadasDeLaFamilia('TTextSettings'));
    Assert.AreEqual('Trimming', M.PublicadasDeLaFamilia('TNietaTextSettings'));
  finally
    M.Free;
  end;
end;

{ Dos unidades con una clase del mismo nombre son dos clases (el TFont de la
  VCL y el de TeeChart: una propiedad sabe de cual es); el NOMBRE que escribe
  un form es de la de la instalacion si la hay, y entre iguales con otras
  publicadas es ambiguo (X). Revision de la 1.12.0. }
procedure TDesignerMetaGenTests.LasClasesPorSuIdentidad;
var
  Bds, Ter: string;
  V: TArray<string>;
  M: TMetaTable;
  Id: string;
begin
  Bds := TPath.Combine(FDir, 'bds');
  Ter := TPath.Combine(FDir, 'terceros');
  TDirectory.CreateDirectory(Bds);
  TDirectory.CreateDirectory(Ter);
  TFile.WriteAllText(TPath.Combine(Bds, 'System.pas'),
    'unit System; interface type TObject = class end; implementation end.');
  TFile.WriteAllText(TPath.Combine(Bds, 'System.Classes.pas'), 'unit System.Classes; interface type'#13#10 +
    'TPersistent = class(TObject) end; TComponent = class(TPersistent) end; implementation end.');
  TFile.WriteAllText(TPath.Combine(Bds, 'Vcl.Graphics.pas'), 'unit Vcl.Graphics; interface uses System.Classes;'#13#10 +
    'type TFont = class(TPersistent) published property Size: Integer; end;'#13#10 +
    'TBarra = class(TComponent) published property Min: Integer; property Font: TFont; end; implementation end.');
  TFile.WriteAllText(TPath.Combine(Ter, 'Tee.Format.pas'), 'unit Tee.Format; interface uses System.Classes;'#13#10 +
    'type TFont = class(TPersistent) published property Fill: Integer; end;'#13#10 +
    'TBarra = class(TComponent) published property Max: Integer; end;'#13#10 +
    'TGrafico = class(TComponent) published property Font: TFont; end; implementation end.');
  TFile.WriteAllText(TPath.Combine(Ter, 'UnoA.pas'), 'unit UnoA; interface uses System.Classes;'#13#10 +
    'type TDuplo = class(TComponent) published property A: Integer; end; implementation end.');
  TFile.WriteAllText(TPath.Combine(Ter, 'UnoB.pas'), 'unit UnoB; interface uses System.Classes;'#13#10 +
    'type TDuplo = class(TComponent) published property B: Integer; end; implementation end.');
  V := GeneraTablasDeFuente([Bds, Ter], '37.0', Bds).Hechos[mdVcl];
  Assert.IsTrue(Hechos(V, 'P Vcl.Graphics:TBarra Font c Vcl.Graphics:TFont'), 'la Font de la VCL es su TFont');
  Assert.IsTrue(Hechos(V, 'P Tee.Format:TGrafico Font c Tee.Format:TFont'), 'la de TeeChart, el suyo');
  Assert.IsTrue(Hechos(V, 'C Vcl.Graphics:TFont') and Hechos(V, 'C Tee.Format:TFont'), 'las dos estan');
  Assert.IsFalse(Hechos(V, 'X TBarra Vcl.Graphics:TBarra,Tee.Format:TBarra'),
    'la de la instalacion gana el nombre a la de terceros');
  Assert.IsTrue(Hechos(V, 'X TDuplo UnoA:TDuplo,UnoB:TDuplo'), 'entre iguales con otras publicadas, ambigua');
  M := TMetaTable.Create(V);
  try
    Assert.IsTrue(M.ClaseDeNombre('TBarra', Id) and (Id = 'vcl.graphics:tbarra'), 'el nombre, a la de la instalacion');
    Assert.IsTrue(M.ClaseDeNombre('Tee.Format:TBarra', Id) and (Id = 'tee.format:tbarra'), 'y por su identidad, la otra');
    Assert.IsFalse(M.ClaseDeNombre('TDuplo', Id), 'la ambigua no se resuelve');
    Assert.IsTrue(M.Ambiguas.ContainsKey('tduplo'));
  finally
    M.Free;
  end;
end;

{ Lo que una clase guarda en el form por codigo (Filer.DefineProperty): los
  literales, uno construido al vuelo ('*'), y la rutina local de dentro, que
  no corta el cuerpo. }
procedure TDesignerMetaGenTests.LoQueSeGuardaPorCodigo;
var
  D: TArray<string>;
  S: TSimbolosPascal;
begin
  S := SimbolosDeDelphi('37.0', 'Win64');
  try
    D := PropiedadesDefinidasPorCodigo(TextoActivo(
      'unit U; interface implementation'#13#10 +
      'procedure TForma.DefineProperties(Filer: TFiler);'#13#10 +
      '  function Escribe: Boolean; begin Result := True; end;'#13#10 +
      'begin'#13#10 +
      '  inherited; { Filer.DefineProperty(''Comentada'', nil, nil, False); }'#13#10 +
      '  Filer.DefineProperty(''TextHeight'', LeeT, EscribeT, Escribe);'#13#10 +
      '  Filer.DefineBinaryProperty(''Datos'', LeeD, EscribeD, True);'#13#10 +
      'end;'#13#10 +
      'procedure TCaja.TInterna.DefineProperties(Filer: TFiler);'#13#10 +
      'begin Filer.DefineProperty(''Viewport.Width'', L, E, True); end;'#13#10 +
      'procedure TRejilla.DefineProperties(Filer: TFiler);'#13#10 +
      'begin Filer.DefineProperty(VP + ''.Width'', L, E, True); end;'#13#10 +
      'procedure TOtra.Loaded; begin Filer.DefineProperty(''NoEsDeAqui'', L, E, True); end;'#13#10 +
      // una rutina suelta no es del metodo de antes (ReadBufferProperties)
      'procedure LeeSuelto(Filer: TFiler); begin Filer.DefineProperty(''Global'', L, E, True); end;'#13#10 +
      // una constante del cuerpo y una lista constante con indice (FMX
      // TCustomScrollBox, TColumn: revision de la 1.12.0)
      'procedure TScroll.DefineProperties(Filer: TFiler);'#13#10 +
      'const VP = ''Viewport''; Lista: array of string = [''Viejo.A'', ''Viejo.B''];'#13#10 +
      'var I: Integer;'#13#10 +
      'begin Filer.DefineProperty(VP + ''.Height'', L, E, True);'#13#10 +
      '  for I := 0 to 1 do Filer.DefineProperty(Lista[I], L, nil, False); end;'#13#10 +
      // un nombre que no se lee: en un ayudante, para quien lo nombre; suelto, nada
      'procedure TAyuda.Lee; begin Filer.DefineProperty(Prefijo + ''Rect'', L, E, True); end;'#13#10 +
      'procedure SueltoRaro; begin Filer.DefineProperty(Prefijo + ''X'', L, E, True); end;'#13#10 +
      'end.', S, nil, True));
  finally
    S.Free;
  end;
  var Todo := '|' + string.Join('|', D) + '|';
  Assert.Contains(Todo, '|TForma TextHeight|', 'despues de la rutina local');
  Assert.Contains(Todo, '|TForma Datos|', 'la binaria tambien');
  Assert.DoesNotContain(Todo, 'Comentada', 'lo comentado no');
  Assert.Contains(Todo, '|TCaja.TInterna Viewport.Width|', 'la anidada, y un nombre con punto');
  Assert.Contains(Todo, '|TRejilla *|', 'el nombre construido al vuelo no se adivina');
  Assert.Contains(Todo, '|~TOtra NoEsDeAqui|', 'fuera de un DefineProperties: lo lee un ayudante (su clase)');
  Assert.Contains(Todo, '|>TForma TFiler|', 'los tipos que nombra un DefineProperties (por si es un ayudante)');
  Assert.Contains(Todo, '|* Global|', 'una rutina suelta: de alguna clase, no del metodo de antes');
  Assert.DoesNotContain(Todo, '~TOtra Global');
  Assert.Contains(Todo, '|TScroll Viewport.Height|', 'una constante de su cuerpo');
  Assert.IsTrue(Todo.Contains('|TScroll Viejo.A|') and Todo.Contains('|TScroll Viejo.B|'),
    'una lista constante con indice: ' + Todo);
  Assert.DoesNotContain(Todo, '|TScroll *|', 'lo que se lee no es un *');
  Assert.Contains(Todo, '|~TAyuda *|', 'uno que no se lee en un ayudante: para quien lo nombre');
  Assert.DoesNotContain(Todo, '|* *|', 'suelto, para nadie');
end;

{ Lo que lee un AYUDANTE es de quien lo nombra en su DefineProperties (FMX:
  TTextControl usa un TTextPropLoader que lee Font.Size, y TText un
  TTextPropLoaderEx que hereda de el y anade Color): con 'D *' a secas, Color
  valia en cualquier control FMX. El que no nombra nadie, de alguna clase. }
procedure TDesignerMetaGenTests.LosAyudantesDeUnDefineProperties;
var
  F: TArray<string>;
begin
  Escribe('System.pas', 'unit System; interface type TObject = class end; implementation end.');
  Escribe('System.Classes.pas', 'unit System.Classes; interface type'#13#10 +
    'TPersistent = class(TObject) end; TComponent = class(TPersistent) end; implementation end.');
  Escribe('FMX.Controls.pas', 'unit FMX.Controls; interface uses System.Classes; type'#13#10 +
    'TInfo = class public type TCargador = class procedure Lee; virtual; end; end;'#13#10 +
    'TCargadorEx = class(TInfo.TCargador) procedure Lee; override; end;'#13#10 +
    'TSuelto = class procedure Lee; end;'#13#10 +
    'TTexto = class(TComponent) protected procedure DefineProperties(F: TFiler); override; end;'#13#10 +
    'TTextoEx = class(TComponent) protected procedure DefineProperties(F: TFiler); override; end;'#13#10 +
    'TCaja = class(TComponent) published property Ancho: Integer; end;'#13#10 +
    'TRaro = class procedure Lee; end; TSueltoRaro = class procedure Lee; end;'#13#10 +
    'TTextoRaro = class(TComponent) protected procedure DefineProperties(F: TFiler); override; end;'#13#10 +
    'implementation'#13#10 +
    'procedure TInfo.TCargador.Lee;'#13#10 +
    'begin Filer.DefineProperty(''Font.Size'', L, nil, False); end;'#13#10 +
    'procedure TCargadorEx.Lee;'#13#10 +
    'begin inherited; Filer.DefineProperty(''Color'', L, nil, False); end;'#13#10 +
    'procedure TSuelto.Lee;'#13#10 +
    'begin Filer.DefineProperty(''Huerfano'', L, nil, False); end;'#13#10 +
    'procedure TTexto.DefineProperties(F: TFiler);'#13#10 +
    'var C: TInfo.TCargador; begin C := TInfo.TCargador.Create; C.Lee; end;'#13#10 +
    'procedure TTextoEx.DefineProperties(F: TFiler);'#13#10 +
    'var C: TCargadorEx; begin C := TCargadorEx.Create; C.Lee; end;'#13#10 +
    // un nombre que no se lee en un ayudante (FMX TBitmapLinks.TPropertyLoader)
    'procedure TRaro.Lee;'#13#10 +
    'begin Filer.DefineProperty(Prefijo + ''Rect'', L, nil, False); end;'#13#10 +
    'procedure TSueltoRaro.Lee;'#13#10 +
    'begin Filer.DefineProperty(Prefijo + ''Rect'', L, nil, False); end;'#13#10 +
    'procedure TTextoRaro.DefineProperties(F: TFiler);'#13#10 +
    'var C: TRaro; begin C := TRaro.Create; C.Lee; end;'#13#10 +
    'end.');
  F := GeneraTablasDeFuente([FDir], '37.0', 'Z:\no-es-bds').Hechos[mdFmx];
  Assert.IsTrue(Hechos(F, 'D FMX.Controls:TTexto Font.Size'), 'lo del ayudante, de quien lo nombra');
  Assert.IsFalse(Hechos(F, 'D FMX.Controls:TTexto Color'), 'lo del ayudante derivado, no del base');
  Assert.IsTrue(Hechos(F, 'D FMX.Controls:TTextoEx Color') and Hechos(F, 'D FMX.Controls:TTextoEx Font.Size'),
    'el derivado: lo suyo y lo del ayudante del que hereda');
  Assert.IsFalse(Hechos(F, 'D * Color') or Hechos(F, 'D * Font.Size'), 'nada de eso vale en cualquier clase');
  Assert.IsTrue(Hechos(F, 'D * Huerfano'), 'el ayudante que no nombra nadie: de alguna clase');
  Assert.IsTrue(Hechos(F, 'D FMX.Controls:TTextoRaro *'), 'uno que no se lee: de quien nombra al ayudante');
  Assert.IsFalse(Hechos(F, 'D * *'), 'y si no lo nombra nadie, de nadie: el lint lo aceptaria todo');
end;

{ El lint contra una tabla dada (LintConTabla): la raiz no se juzga, lo
  guardado por codigo no se niega (subiendo por la herencia, con su punto),
  el enumerado se mira por su identidad, la clase ambigua se dice, y lo que
  no existe se avisa. }
procedure TDesignerMetaGenTests.ElLintConUnaTabla;
var
  M: TMetaTable;
  W, N: TArray<string>;
  Todo: string;
begin
  M := TMetaTable.Create([
    'C Vcl.Forms:TForm1', 'P Vcl.Forms:TForm1 Demo o Integer',
    'C System.Classes:TComponent', 'D System.Classes:TComponent Left',
    'C Vcl.Controls:TControl', 'H Vcl.Controls:TControl System.Classes:TComponent',
    'D Vcl.Controls:TControl Viewport.Width',
    'C Vcl.Buttons:TBoton', 'H Vcl.Buttons:TBoton Vcl.Controls:TControl',
    'P Vcl.Buttons:TBoton Layout e Mio:TButtonLayout',
    'P Vcl.Buttons:TBoton Caption o TCaption',
    'E Mio:TButtonLayout blLeft,blCenter', 'E Vcl.Buttons:TButtonLayout blLeft',
    'X TDuplo UnoA:TDuplo,UnoB:TDuplo', 'D * Font.Size',
    // TPosition publica algo (como el de verdad, X e Y): si no, el lint calla
    // por "sin datos" antes de mirar lo guardado por codigo (un mutante lo vio)
    'C FMX.Types:TPosition', 'P FMX.Types:TPosition X o Single', 'D FMX.Types:TPosition Point',
    'P Vcl.Buttons:TBoton Position c FMX.Types:TPosition']);
  try
    W := LintConTabla(M, False, [
      'object Form1: TForm1',      // 1: la raiz, aunque la tabla tenga un TForm1
      '  TextHeight = 13',         // 2: no se juzga
      '  object B1: TBoton',       // 3
      '    Left = 8',              // 4: guardada por TComponent (subiendo)
      '    Viewport.Width = 10',   // 5: con su punto
      '    Layout = blCenter',     // 6: del enumerado de SU unidad
      '    object TBoton',         // un objeto SIN nombre: lo suyo es suyo, y
      '      Font.Size = 9',       // su end no saca a B1; lo lee un ayudante (D *)
      '    end',
      '    Position.Point = ''(0,1)''', // lo guarda por codigo la clase de la propiedad
      '    Captoin = ''x''',       // 11: no existe, en B1
      '  end',
      '  object D1: TDuplo',       // 9: ambigua
      '  end',
      // un nombre con acento: \w de TRegEx es ASCII y leia 'lblDirecci' como
      // la clase (revision de la 1.12.0)
      '  object lblDirecci'#$F3'n: TBoton',
      '    Captoin2 = ''y''',
      '  end',
      'end'], N);
  finally
    M.Free;
  end;
  Todo := string.Join(#10, W);
  Assert.AreEqual<Integer>(2, Length(W), Todo);
  Assert.Contains(W[0], 'Captoin', 'lo que no existe se avisa');
  Assert.Contains(W[1], 'Captoin2', 'el objeto de nombre con acento se juzga con su clase');
  // la ambigua se dice, sin juzgar, y como NOTA: no es un aviso (iba bajo
  // "the app CRASHES" tras cada edicion; revision de la 1.12.0)
  Assert.AreEqual<Integer>(1, Length(N), string.Join(#10, N));
  Assert.Contains(N[0], 'DSGN-055');
  Assert.DoesNotContain(Todo, 'TextHeight', 'la raiz no se juzga');
  Assert.DoesNotContain(Todo, 'blCenter', 'el enumerado de su unidad, no el homonimo');
end;

{ Ancestros que la cadena no seguia: un alias de clase (JVCL:
  TJvGraphicControl = TJvExGraphicControl), un generico con el nombre de
  otro que no lo es (REST.Backend.BindSource), una unidad sin su namespace
  (StdCtrls.TEdit), y un include con subcarpeta (el $I jedi\jedi.inc) que
  esta en OTRA carpeta de las rutas. }
procedure TDesignerMetaGenTests.LosAncestrosRaros;
var
  Inc_: string;
  V: TArray<string>;
begin
  Inc_ := TPath.Combine(FDir, 'inc');
  TDirectory.CreateDirectory(TPath.Combine(Inc_, 'sub'));
  TFile.WriteAllText(TPath.Combine(TPath.Combine(Inc_, 'sub'), 'cfg.inc'), '{$DEFINE CONLABEL}');
  Escribe('System.pas', 'unit System; interface type TObject = class end; implementation end.');
  Escribe('System.Classes.pas', 'unit System.Classes; interface type'#13#10 +
    'TPersistent = class(TObject) end; TComponent = class(TPersistent) end; implementation end.');
  Escribe('JvComponent.pas', 'unit JvComponent; interface uses System.Classes; type'#13#10 +
    'TJvExControl = class(TComponent) published property A: Integer; end;'#13#10 +
    'TJvControl = TJvExControl;'#13#10 +
    'implementation end.');
  Escribe('JvLabel.pas', '{$I sub\cfg.inc}'#13#10 +
    'unit JvLabel; interface uses System.Classes, JvComponent; type'#13#10 +
    '{$IFDEF CONLABEL} TJvLabel = class(TJvControl) published property B: Integer; end; {$ENDIF}'#13#10 +
    'implementation end.');
  Escribe('REST.Backend.BindSource.pas', 'unit REST.Backend.BindSource; interface uses System.Classes; type'#13#10 +
    'TBackendBind = class(TComponent) published property C: Integer; end;'#13#10 +
    'TBackendBind<TI, T> = class(TBackendBind) end;'#13#10 +
    'TBackendAuth = class(TBackendBind<Integer, string>) published property D: Integer; end;'#13#10 +
    // un generico SIN homonimo no generico (TSensor<T>, System.Sensors.Components)
    'TSensor<T> = class(TComponent) end;'#13#10 +
    'TLocalizador = class(TSensor<Integer>) end;'#13#10 +
    'implementation end.');
  Escribe('Vcl.StdCtrls.pas', 'unit Vcl.StdCtrls; interface uses System.Classes; type'#13#10 +
    'TEdit = class(TComponent) published property Text: string; end; implementation end.');
  Escribe('Mia.pas', 'unit Mia; interface uses System.Classes, StdCtrls; type'#13#10 +
    'TMia = class(StdCtrls.TEdit) end; implementation end.');
  V := GeneraTablasDeFuente([FDir, Inc_], '37.0', 'Z:\no-es-bds').Hechos[mdVcl];
  Assert.IsTrue(Hechos(V, 'H JvLabel:TJvLabel JvComponent:TJvExControl'), 'el alias, a su destino');
  Assert.IsTrue(Hechos(V, 'P JvLabel:TJvLabel B o Integer'), 'y el include con subcarpeta, desde otra carpeta');
  Assert.IsTrue(Hechos(V, 'H REST.Backend.BindSource:TBackendAuth REST.Backend.BindSource:TBackendBind'),
    'el generico por su aridad, y el no generico por su nombre');
  Assert.IsTrue(Hechos(V, 'P REST.Backend.BindSource:TBackendAuth C o Integer'), 'lo del abuelo');
  Assert.IsTrue(Hechos(V, 'H Mia:TMia Vcl.StdCtrls:TEdit'), 'StdCtrls.TEdit es Vcl.StdCtrls.TEdit');
  Assert.IsTrue(Hechos(V, 'H REST.Backend.BindSource:TLocalizador System.Classes:TComponent'),
    'el padre en la tabla es el primer ancestro NO generico (el generico no esta en ella)');
end;

procedure TDesignerMetaGenTests.LoPublicadoAntesQueLoGuardado;
var
  M: TMetaTable;
  W, N: TArray<string>;
  Cuantas: Integer;
begin
  // Lo guardado por codigo se mira DESPUES de lo publicado: un nombre que no
  // se leia ('TCustomScrollBox *') callaba todo TListBox, valores incluidos
  // (Align = alClient). Y la clave de una clase no coge la de sus anidadas
  // (info TGridPanelLayout listaba lo de TCellItem). Revision de la 1.12.0.
  M := TMetaTable.Create([
    'C FMX.Layouts:TCustomScrollBox', 'D FMX.Layouts:TCustomScrollBox *',
    'P FMX.Layouts:TCustomScrollBox Align e FMX.Types:TAlignLayout',
    'C FMX.ListBox:TListBox', 'H FMX.ListBox:TListBox FMX.Layouts:TCustomScrollBox',
    'P FMX.ListBox:TListBox Align e FMX.Types:TAlignLayout',
    'E FMX.Types:TAlignLayout None,Top,Client',
    'C FMX.Layouts:TGrid', 'P FMX.Layouts:TGrid Uno o Integer',
    'C FMX.Layouts:TGrid.TCell', 'P FMX.Layouts:TGrid.TCell Dos o Integer',
    'D FMX.Layouts:TGrid.TCell Tres']);
  try
    W := LintConTabla(M, True, [
      'object Form1: TForm1',
      '  object L1: TListBox',
      '    Align = alClient',     // publicada: su valor se mira aunque guarde '*'
      '    Viewport.Width = 3',   // no publicada: la guarda por codigo ('*')
      '  end',
      'end'], N);
    Assert.AreEqual<Integer>(1, Length(W), string.Join(#10, W));
    Assert.Contains(W[0], 'alClient', 'el valor de una publicada se mira');
    Cuantas := 0;
    for var K in M.Props.Keys do
      if K.StartsWith(ClaveProp('FMX.Layouts:TGrid', '')) then
        Inc(Cuantas);
    Assert.AreEqual<Integer>(1, Cuantas, 'lo de TGrid, sin lo de TGrid.TCell');
    Assert.AreEqual<Integer>(0, Length(M.DefinidasDeLaCadena('FMX.Layouts:TGrid')),
      'ni lo que guarda la anidada');
  finally
    M.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPreprocesoTests);
  TDUnitX.RegisterTestFixture(TPascalDeclTests);
  TDUnitX.RegisterTestFixture(TDesignerMetaGenTests);

end.
