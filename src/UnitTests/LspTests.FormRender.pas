unit LspTests.FormRender;

{ delphi_designer preview (1.17.0, RenderForm): las piezas que NO lanzan
  nada, pasadas de la bateria DUnitX del sandbox (RenderTests) a la suite del
  motor. El lector del protocolo de los renderizadores es la inversa de
  FormRenderProtocolo.inc, y aqui se le escribe con las MISMAS claves (las
  que exporta FormRender.Comun, el escritor); el compositor de la orden; y
  del ayudante, la cabecera de un .dfm, el ancestro del .pas y el criterio de
  los no visuales.

  Los renderizadores ENTEROS no caben aqui: este ejecutor corre en el
  contenedor de delphi_test, que no deja crear ventanas, y el VCL y el FMX
  mueren al crear la form (medido el 7-oct-2026: 1 de 20). Esos 20 casos los
  mide tests/test_designer_preview.py a traves del servidor, por pixel. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormRenderTests = class
  private
    FDir: string;
    function Escribe(const ANombre, ATexto: string): string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure LectorEsLaInversaDelProtocolo;
    [Test] procedure LectorNoConfundeNonvisualConNonvisuals;
    [Test] procedure LectorIgnoraTrazasYLineasAjenas;
    [Test] procedure LectorSinRespuestaNoInventa;
    [Test] procedure OrdenUnInterruptorPorValor;
    [Test] procedure OrdenNoPasaValoresVacios;
    [Test] procedure OrdenRechazaComillasYControles;
    [Test] procedure ExeDeCadaFramework;
    [Test] procedure CapturaDelDisenadorEsDelAgente;
    [Test] procedure CabeceraDeLasTresPalabras;
    [Test] procedure AncestroYFrameSalenDelPas;
    [Test] procedure NoVisualesUnCriterio;
    [Test] procedure EnlaceSoloElPuntoDeReparse;
    [Test]
    procedure RaizSoloSiLaCadenaLlega;
    [Test]
    procedure RutaDeComponenteConLaRaizDelante;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Lsp.DesignerBin,   // DesignerTextToBinary: el binario que escribe el IDE
  Lsp.FormRender,
  Lsp.Guard,
  Lsp.Texts,
  FormRender.Comun; // del ayudante (src\Render): el escritor del protocolo y lo que no crea ventanas

type
  // el "control" del framework para NoVisualesDe, sin VCL ni FMX
  TControlFalso = class(TComponent);

{ Una UNION de carpeta (punto de montaje): la crea cualquiera, sin el
  privilegio de los symlink, y tiene el atributo de punto de reparse que mira
  EsEnlace. Solo para la prueba: el servidor no crea enlaces. }
function CreaUnion(const AUnion, ADestino: string): Boolean;
const
  FSCTL_SET_REPARSE_POINT = $000900A4;
  IO_REPARSE_TAG_MOUNT_POINT = $A0000003;
var
  Sust, Impr: string;
  Buf: TBytes;
  H: THandle;
  NS, NP, Datos, Ret: DWORD;
begin
  Result := False;
  if not CreateDir(AUnion) then
    Exit;
  Sust := '\??\' + ExcludeTrailingPathDelimiter(ADestino);
  Impr := ExcludeTrailingPathDelimiter(ADestino);
  NS := Length(Sust) * SizeOf(Char);
  NP := Length(Impr) * SizeOf(Char);
  // REPARSE_DATA_BUFFER de un punto de montaje: cabecera (8), cuatro WORD
  // (8) y los dos nombres con su nulo
  Datos := 8 + NS + 2 + NP + 2;
  SetLength(Buf, 8 + Datos);
  FillChar(Buf[0], Length(Buf), 0);
  PDWORD(@Buf[0])^ := IO_REPARSE_TAG_MOUNT_POINT;
  PWord(@Buf[4])^ := Datos;
  PWord(@Buf[10])^ := NS;      // SubstituteNameLength (su Offset, 0)
  PWord(@Buf[12])^ := NS + 2;  // PrintNameOffset
  PWord(@Buf[14])^ := NP;      // PrintNameLength
  Move(PChar(Sust)^, Buf[16], NS);
  Move(PChar(Impr)^, Buf[16 + NS + 2], NP);
  H := CreateFile(PChar(AUnion), GENERIC_WRITE, 0, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    Result := DeviceIoControl(H, FSCTL_SET_REPARSE_POINT, @Buf[0], Length(Buf), nil, 0, Ret, nil);
  finally
    CloseHandle(H);
  end;
end;

procedure TFormRenderTests.Prepara;
begin
  // junto al ejecutor: dentro de la jaula con la que lo lanza el servidor
  FDir := ExtractFilePath(ParamStr(0)) + 'render-prueba';
  ForceDirectories(FDir);
end;

procedure TFormRenderTests.Limpia;
begin
  for var F in TDirectory.GetFiles(FDir) do
    TFile.Delete(F);
  RemoveDir(FDir);
end;

function TFormRenderTests.Escribe(const ANombre, ATexto: string): string;
begin
  Result := TPath.Combine(FDir, ANombre);
  TFile.WriteAllText(Result, ATexto, TEncoding.ASCII);
end;

procedure TFormRenderTests.LectorEsLaInversaDelProtocolo;
var
  R: TRespuestaRender;
begin
  // como lo escribe el ayudante (FormRender.Comun.Responde): CLAVE=valor por
  // linea, el fin de linea de la consola, las repetibles las veces que haga falta
  R := LeeRespuestaDeRender(
    FR_DPI + '96'#13#10 + FR_SESSION + '2'#13#10 +
    FR_STYLE + 'none (as the VCL designer)'#13#10 +
    FR_ROOT + 'FormPrueba:TFormPrueba:form'#13#10 + FR_PACKAGES + '112/153'#13#10 +
    FR_COMPONENTS + '5'#13#10 + FR_SUBSTITUTED + 'TRaro,TOtro'#13#10 +
    FR_IGNORED + 'Property Alineacion does not exist'#13#10 +
    FR_IGNORED + 'Invalid property value'#13#10 +
    FR_IGNORED + 'Error reading Panel1.Font.Size: Invalid property value'#13#10 +
    FR_WARNING + '[RENDER-016] component: there is no Z in FormPrueba.'#13#10 +
    FR_NONVISUALS + 'Timer1:TTimer,ActionList1:TActionList'#13#10 + FR_NONVISUAL + '2'#13#10 +
    FR_RECT + 'Panel1=16,140,344,41'#13#10 + FR_FIDELITY + 'print'#13#10 +
    FR_SIZE + '400x200'#13#10 + FR_CAPTURE + 'C:\w\a.png'#13#10 + FR_MS + '17,6'#13#10);
  Assert.AreEqual(96, R.Dpi);
  Assert.AreEqual(2, R.Sesion);
  Assert.AreEqual('none (as the VCL designer)', R.Estilo);
  Assert.AreEqual('FormPrueba', R.RaizNombre);
  Assert.AreEqual('TFormPrueba', R.RaizClase);
  Assert.AreEqual('form', R.RaizTipo);
  Assert.AreEqual('112/153', R.Paquetes);
  Assert.AreEqual(5, R.Componentes);
  Assert.AreEqual('TRaro|TOtro', string.Join('|', R.Sustituidas));
  Assert.AreEqual<NativeInt>(3, Length(R.Ignoradas), 'IGNORED es repetible');
  // la forma de TReader (SPropertyException) en sus partes, con la ruta de la
  // propiedad entera; lo que no casa, solo como texto (David, 7-oct-2026)
  Assert.AreEqual('', R.Ignoradas[0].Componente, 'otra forma: solo texto');
  Assert.AreEqual('Property Alineacion does not exist', R.Ignoradas[0].Texto);
  Assert.AreEqual('Panel1', R.Ignoradas[2].Componente);
  Assert.AreEqual('Font.Size', R.Ignoradas[2].Propiedad);
  Assert.AreEqual('Invalid property value', R.Ignoradas[2].Motivo);
  Assert.AreEqual<NativeInt>(1, Length(R.Avisos));
  Assert.AreEqual('Timer1:TTimer|ActionList1:TActionList', string.Join('|', R.NoVisuales));
  Assert.AreEqual(2, R.NoVisualesDibujados);
  Assert.IsTrue(R.HayRect, 'RECT=');
  Assert.AreEqual(16, R.RectX);
  Assert.AreEqual(140, R.RectY);
  Assert.AreEqual(344, R.RectW);
  Assert.AreEqual(41, R.RectH);
  Assert.AreEqual('print', R.Fidelidad);
  Assert.AreEqual(400, R.Ancho);
  Assert.AreEqual(200, R.Alto);
  Assert.AreEqual('C:\w\a.png', R.Captura);
  Assert.AreEqual(17, R.MsCarga);
  Assert.AreEqual(6, R.MsPintado);
  Assert.AreEqual('', R.Error);
end;

procedure TFormRenderTests.LectorNoConfundeNonvisualConNonvisuals;
var
  R: TRespuestaRender;
begin
  // NONVISUALS= empieza como NONVISUAL: una clave no se lee como la otra
  R := LeeRespuestaDeRender(FR_NONVISUALS + 'Timer1:TTimer');
  Assert.AreEqual(0, R.NoVisualesDibujados, 'la lista no es el recuento');
  Assert.AreEqual<NativeInt>(1, Length(R.NoVisuales));
  R := LeeRespuestaDeRender(FR_NONVISUAL + '3');
  Assert.AreEqual(3, R.NoVisualesDibujados);
  Assert.AreEqual<NativeInt>(0, Length(R.NoVisuales), 'el recuento no es la lista');
end;

procedure TFormRenderTests.LectorIgnoraTrazasYLineasAjenas;
var
  R: TRespuestaRender;
begin
  // la traza de --verbose, la linea de uso (stderr va al mismo tubo), un
  // RECT mal formado y el error que si es del protocolo
  R := LeeRespuestaDeRender('# clases sin registrar: TRaro'#10 +
    'DelphiFormRenderVcl.exe --path <dfm|fmx> --out <png>'#10 +
    FR_RECT + 'Panel1=16,140'#10 +
    FR_ERROR + '[RENDER-004 INVALID_PARAM] Missing --path.'#10);
  Assert.AreEqual('[RENDER-004 INVALID_PARAM] Missing --path.', R.Error);
  Assert.IsFalse(R.HayRect, 'un RECT sin sus cuatro numeros no es un RECT');
  Assert.AreEqual('', R.Captura);
  Assert.AreEqual<NativeInt>(0, Length(R.Avisos), 'la linea de uso no es un aviso');
end;

procedure TFormRenderTests.LectorSinRespuestaNoInventa;
var
  R: TRespuestaRender;
begin
  R := LeeRespuestaDeRender('');
  Assert.AreEqual(-1, R.Sesion, 'sin SESSION= no hay sesion 0 (la de un servicio)');
  Assert.AreEqual('', R.Captura);
  Assert.AreEqual('', R.Error);
  Assert.IsFalse(R.HayRect);
  Assert.AreEqual<NativeInt>(0, Length(R.NoVisuales));
end;

procedure TFormRenderTests.OrdenUnInterruptorPorValor;
var
  P: TPeticionRender;
  O: string;
begin
  P := Default(TPeticionRender);
  P.Path := 'C:\w\Form 1.dfm';
  P.Salida := 'C:\w\o.png';
  P.Estados := ['Edit1.Text=hola mundo', 'Panel1.Color=255'];
  P.Componente := 'Panel1';
  P.Estilo := 'android';
  P.NoVisuales := True;
  P.Bds := '37.0';
  Assert.AreEqual('', ComponeOrdenDeRender('C:\s\DelphiFormRenderVcl.exe', P, O));
  Assert.IsTrue(O.StartsWith('"C:\s\DelphiFormRenderVcl.exe" '), O);
  Assert.IsTrue(O.Contains(' --path "C:\w\Form 1.dfm"'), 'un valor con espacios va entero: ' + O);
  Assert.IsTrue(O.Contains(' --out "C:\w\o.png"'), O);
  Assert.IsTrue(O.Contains(' --state "Edit1.Text=hola mundo"'), O);
  Assert.IsTrue(O.Contains(' --state "Panel1.Color=255"'), 'un --state por estado: ' + O);
  Assert.IsTrue(O.Contains(' --component "Panel1"'), O);
  Assert.IsTrue(O.Contains(' --style "android"'), O);
  Assert.IsTrue(O.Contains(' --nonvisual on'), O);
  Assert.IsTrue(O.Contains(' --bds "37.0"'), O);
  Assert.IsTrue(O.Contains(' --timeout '), 'el vigia del ayudante va siempre: ' + O);
end;

procedure TFormRenderTests.OrdenNoPasaValoresVacios;
var
  P: TPeticionRender;
  O: string;
begin
  // el lector de Delphi se salta un "" y tomaria el interruptor siguiente
  // como su valor: un opcional vacio no viaja
  P := Default(TPeticionRender);
  P.Path := 'C:\w\F.dfm';
  P.Salida := 'C:\w\o.png';
  P.Estados := [''];
  Assert.AreEqual('', ComponeOrdenDeRender('C:\s\r.exe', P, O));
  Assert.IsFalse(O.Contains('--component'), O);
  Assert.IsFalse(O.Contains('--style'), O);
  Assert.IsFalse(O.Contains('--state'), O);
  Assert.IsFalse(O.Contains('--bds'), O);
  Assert.IsFalse(O.Contains('""'), 'ningun valor vacio: ' + O);
  Assert.IsTrue(O.Contains(' --nonvisual off'), 'apagado por defecto: ' + O);
end;

procedure TFormRenderTests.OrdenRechazaComillasYControles;
var
  P: TPeticionRender;
  O, R: string;
begin
  // una comilla partiria el valor y lo de detras seria OTRO interruptor: un
  // --out fuera de la jaula
  P := Default(TPeticionRender);
  P.Path := 'C:\w\F.dfm';
  P.Salida := 'C:\w\o.png';
  P.Estados := ['Edit1.Text=a" --out "C:\fuera\x.png'];
  R := ComponeOrdenDeRender('C:\s\r.exe', P, O);
  Assert.IsTrue(EsMsg(R, SR_DESIGNER_VALOR_CON_COMILLAS_FMT), R);
  Assert.AreEqual('', O, 'sin orden: nada que lanzar');
  P.Estados := [];
  P.Componente := 'Panel'#10'1';
  Assert.IsTrue(EsMsg(ComponeOrdenDeRender('C:\s\r.exe', P, O), SR_DESIGNER_VALOR_CON_COMILLAS_FMT),
    'un salto de linea tampoco viaja');
end;

procedure TFormRenderTests.ExeDeCadaFramework;
var
  N, E, Plantado: string;
begin
  // las DOS ramas cada vez: sin el exe al lado, vacio; con el, su ruta (la
  // prueba aceptaba las dos a la vez y no podia fallar: revision de la 1.17.0)
  E := FormRenderExe('fmx', N);
  Assert.AreEqual('DelphiFormRenderFmx.exe', N);
  Plantado := ServerDir(N);
  Assert.IsFalse(TFile.Exists(Plantado), 'el ejecutor de pruebas no lleva un renderizador al lado: ' + Plantado);
  Assert.AreEqual('', E, 'sin el exe al lado no hay renderizador');
  TFile.WriteAllText(Plantado, '');
  try
    Assert.AreEqual(Plantado, FormRenderExe('fmx', N), 'con el exe al lado, su ruta');
  finally
    TFile.Delete(Plantado);
  end;
  FormRenderExe('vcl', N);
  Assert.AreEqual('DelphiFormRenderVcl.exe', N);
  FormRenderExe('', N);
  Assert.AreEqual('DelphiFormRenderVcl.exe', N, 'sin framework, el de los .dfm');
end;

procedure TFormRenderTests.CapturaDelDisenadorEsDelAgente;
begin
  // la tercera subcarpeta de la lista: la imagen en linea se consume
  Assert.IsTrue(IsAgentCapture('C:\w\__delphi-temp\hermes\designer\designer-a.png'), 'designer');
  Assert.IsFalse(IsAgentCapture('C:\w\out\designer\a.png'), 'un out= del agente no es temporal');
end;

procedure TFormRenderTests.CabeceraDeLasTresPalabras;
var
  F: string;
  Bin: TBytes;
var
  C: TCabecera;
begin
  C := Cabecera(Escribe('Hija.dfm', 'inherited FormHija: TFormHija'#13#10'  Caption = ''Hija'''#13#10'end'#13#10));
  Assert.AreEqual('inherited', C.Palabra);
  Assert.AreEqual('FormHija', C.Nombre);
  Assert.AreEqual('TFormHija', C.Clase);
  Assert.IsFalse(C.Binario);
  C := Cabecera(Escribe('Frame.fmx', 'object FrameF: TFrameF'#13#10'end'#13#10));
  Assert.AreEqual('object', C.Palabra);
  Assert.AreEqual('TFrameF', C.Clase);
  C := Cabecera(Escribe('Marco.dfm', 'inline Marco1: TMarco'#13#10'end'#13#10));
  Assert.AreEqual('inline', C.Palabra);
  Assert.AreEqual('Marco1', C.Nombre);
  // un nombre con acento: con \w se cortaba en el acento (revision de la
  // 1.17.0: ahora lo lee EL lector de la linea de objeto)
  F := TPath.Combine(FDir, 'Acento.dfm');
  TFile.WriteAllText(F, 'object FichaDirecci'#$F3'n: TFichaDirecci'#$F3'n'#13#10'end'#13#10, TEncoding.UTF8);
  C := Cabecera(F);
  Assert.AreEqual('TFichaDirecci'#$F3'n', C.Clase, 'el nombre entero, con su acento');
  // el binario que escribe el IDE en disco: el recurso, con su cabecera
  Assert.AreEqual('', DesignerTextToBinary('object FormB: TFormB'#13#10'end'#13#10, Bin));
  F := TPath.Combine(FDir, 'Binario.dfm');
  TFile.WriteAllBytes(F, Bin);
  C := Cabecera(F);
  Assert.IsTrue(C.Binario, 'binario');
  Assert.AreEqual('TFormB', C.Clase, 'leido tras la cabecera del recurso');
end;

procedure TFormRenderTests.AncestroYFrameSalenDelPas;
var
  Dfm, FrameDfm: string;
begin
  Escribe('UHija.pas', 'unit UHija;'#13#10'interface'#13#10'type'#13#10 +
    '  TFormHija = class(TFormBase)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  Dfm := Escribe('UHija.dfm', 'inherited FormHija: TFormHija'#13#10'end'#13#10);
  Assert.AreEqual('TFormBase', AncestroDeClase(Dfm, 'TFormHija'));
  Assert.IsFalse(EsFrame(Dfm, 'TFormHija'), 'una form no es un frame');
  Escribe('UFrameX.pas', 'unit UFrameX;'#13#10'interface'#13#10'type'#13#10 +
    '  TFrameX = class(TFrame)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  FrameDfm := Escribe('UFrameX.dfm', 'object FrameX: TFrameX'#13#10'end'#13#10);
  Assert.IsTrue(EsFrame(FrameDfm, 'TFrameX'), 'un frame se reconoce por su .pas');
  Assert.AreEqual('', AncestroDeClase(Escribe('Suelto.dfm', 'object A: TA'#13#10'end'#13#10), 'TA'),
    'sin .pas al lado no hay ancestro');
  Escribe('UAbs.pas', 'unit UAbs;'#13#10'interface'#13#10'type'#13#10 +
    '  TFormAbs = class abstract(UBase.TFormBase)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  Assert.AreEqual('TFormBase', AncestroDeClase(Escribe('UAbs.dfm', 'inherited FormAbs: TFormAbs'#13#10'end'#13#10),
    'TFormAbs'), 'class abstract y con la unidad delante');
  // una declaracion vieja comentada encima de la buena no cuenta (segunda
  // revision de la 1.17.0)
  Escribe('UCom.pas', 'unit UCom;'#13#10'interface'#13#10'type'#13#10 +
    '  { TFormCom = class(TFormVieja) }'#13#10'  // TFormCom = class(TOtraVieja)'#13#10 +
    '  TFormCom = class(TFormBase)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  Assert.AreEqual('TFormBase', AncestroDeClase(Escribe('UCom.dfm', 'inherited FormCom: TFormCom'#13#10'end'#13#10),
    'TFormCom'), 'los comentarios no son codigo');
end;

procedure TFormRenderTests.NoVisualesUnCriterio;
var
  Raiz, Timer, SinPosicion, Boton: TComponent;
begin
  Raiz := TComponent.Create(nil);
  try
    // el PRIMERO sin posicion tampoco cuenta: el criterio era "(0,0) salvo el
    // indice 0" y no tenia sentido (revision de Fable, 7-oct-2026)
    TComponent.Create(Raiz).Name := 'Item0';
    Timer := TComponent.Create(Raiz);
    Timer.Name := 'Timer1';
    Timer.DesignInfo := (60 shl 16) or 300; // Left 300, Top 60, como el dfm
    SinPosicion := TComponent.Create(Raiz);
    SinPosicion.Name := 'Item1'; // un item de menu: sin posicion de diseno
    Boton := TControlFalso.Create(Raiz);
    Boton.Name := 'Boton1';
    Boton.DesignInfo := (10 shl 16) or 10;
    TComponent.Create(Timer).Name := 'DeOtro'; // de otro dueno: no es de la raiz
    Assert.AreEqual('Timer1:TComponent', ListaDeNoVisuales(NoVisualesDe(Raiz, TControlFalso)),
      'ni el control, ni los que no tienen posicion (tampoco el primero), ni el de otro dueno');
    Assert.AreEqual(300, PosicionDeNoVisual(Timer).X);
    Assert.AreEqual(60, PosicionDeNoVisual(Timer).Y);
  finally
    Raiz.Free;
  end;
end;

procedure TFormRenderTests.EnlaceSoloElPuntoDeReparse;
begin
  // el caso real (un FICHERO enlazado entre los hermanos) pide crear un
  // symlink, y esta cuenta no tiene el privilegio: el criterio es el de
  // Lsp.Guard.EsEnlace, que las baterias de la jaula miden con uniones
  Assert.IsFalse(EsEnlace(Escribe('Normal.dfm', 'object A: TA'#13#10'end'#13#10)), 'un fichero normal se lee');
  Assert.IsFalse(EsEnlace(TPath.Combine(FDir, 'NoEsta.dfm')), 'lo que no existe no es un enlace');
  // y el POSITIVO, con una union de carpeta, que no pide privilegio (la
  // prueba solo tenia negativos: revision de la 1.17.0). Su destino, dentro
  // de la misma carpeta de la prueba
  var Destino := TPath.Combine(FDir, 'destino');
  var Union := TPath.Combine(FDir, 'union');
  ForceDirectories(Destino);
  try
    Assert.IsTrue(CreaUnion(Union, Destino), 'la union se crea: ' + SysErrorMessage(GetLastError));
    Assert.IsTrue(EsEnlace(Union), 'una union es un enlace');
    Assert.IsFalse(EsEnlace(Destino), 'su destino no lo es');
  finally
    RemoveDir(Union); // quita la union, nunca lo que hay detras
    RemoveDir(Destino);
  end;
end;

procedure TFormRenderTests.RaizSoloSiLaCadenaLlega;

  function Unidad(const ANombre, AClase, AAncestro: string): string;
  begin
    Escribe(ANombre + '.pas', 'unit ' + ANombre + ';'#13#10'interface'#13#10'type'#13#10 +
      '  ' + AClase + ' = class' + AAncestro + #13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
    Result := Escribe(ANombre + '.dfm', 'object ' + Copy(AClase, 2, MaxInt) + ': ' + AClase + #13#10'end'#13#10);
  end;

begin
  // --root solo cuando la cadena LLEGA a la raiz del marco; un sufijo
  // adivinado (o una base de otra unidad) es '': que mire el ayudante
  // (segunda revision de la 1.17.0)
  Assert.AreEqual('frame', RaizParaElRender(Unidad('UMarcoA', 'TMarcoA', '(TFrame)')));
  Assert.AreEqual('frame', RaizParaElRender(Unidad('UMarcoB', 'TMarcoB', ' abstract(Vcl.Forms.TCustomFrame)')),
    'abstract y con la unidad delante');
  Assert.AreEqual('form', RaizParaElRender(Unidad('UFichaA', 'TFichaA', '(TForm)')));
  Assert.AreEqual('form', RaizParaElRender(Unidad('UDatosA', 'TDatosA', '(TDataModule)')));
  Assert.AreEqual('', RaizParaElRender(Unidad('UHijaA', 'THijaA', '(TBaseDeOtraUnidad)')),
    'la base vive en otra unidad: no se sabe');
  Assert.AreEqual('', RaizParaElRender(Unidad('UOtroFrame', 'TOtroFrame', '(TMiBaseFrame)')),
    'el sufijo es una adivinanza, no un hecho');
  // un X.fmx al lado de un X.dfm: la unidad es del .dfm, no del .fmx pedido
  Unidad('UDos', 'TDos', '(TFrame)');
  Assert.AreEqual('', RaizParaElRender(Escribe('UDos.fmx', 'object Dos: TDos'#13#10'end'#13#10)),
    'el designer de la unidad no es el pedido');
  Assert.AreEqual('', RaizParaElRender(Escribe('Suelto.dfm', 'object A: TA'#13#10'end'#13#10)), 'sin .pas');
end;

procedure TFormRenderTests.RutaDeComponenteConLaRaizDelante;
var
  Raiz, Panel, Marco, Lbl: TComponent;
begin
  // UN lector para component= y state=: como la RTL lee una referencia, y
  // tambien con el nombre de la raiz delante (un frame suelto: FrameX.Panel;
  // segunda revision de la 1.17.0)
  Raiz := TComponent.Create(nil);
  try
    Raiz.Name := 'FrameX';
    Panel := TComponent.Create(Raiz);
    Panel.Name := 'PanelFrame';
    Marco := TComponent.Create(Raiz);
    Marco.Name := 'Marco1';
    Lbl := TComponent.Create(Marco);
    Lbl.Name := 'LblAviso';
    Assert.AreSame(Panel, ComponenteDeRuta(Raiz, 'PanelFrame'));
    Assert.AreSame(Panel, ComponenteDeRuta(Raiz, 'FrameX.PanelFrame'), 'con la raiz delante');
    Assert.AreSame(Raiz, ComponenteDeRuta(Raiz, 'framex'), 'la raiz misma');
    Assert.AreSame(Lbl, ComponenteDeRuta(Raiz, 'Marco1.LblAviso'), 'dentro de un frame en linea');
    Assert.AreSame(Lbl, ComponenteDeRuta(Raiz, 'FrameX.Marco1.LblAviso'));
    Assert.IsNull(ComponenteDeRuta(Raiz, 'Otro.PanelFrame'), 'otra raiz no');
  finally
    Raiz.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormRenderTests);

end.
