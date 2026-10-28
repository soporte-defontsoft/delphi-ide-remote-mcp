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
    [Test] procedure LectorLeeLoLeidoConSuHuella;
    [Test] procedure LoLeidoSeVuelveAMirarPorSusBytes;
    [Test] procedure AncestroAnotaSuPasConLaHuella;
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
    procedure LaRaizDeDisenoPorLaTabla;
    [Test]
    procedure RutaDeComponenteConLaRaizDelante;
    [Test]
    procedure LaCabezaYSusPartesTienenUnLector;
  end;

{ Una UNION de carpeta (punto de montaje) AUnion -> ADestino, para las pruebas
  que miden un enlace: esta y las de la puerta de leer (LspTests.Rutas). }
function CreaUnion(const AUnion, ADestino: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Lsp.DesignerForma, // DesignerTextoARecurso: el binario que escribe el IDE
  Lsp.FormRender,
  Lsp.Guard,
  Lsp.Texts,
  FormRender.Comun, // del ayudante (src\Render): el escritor del protocolo y lo que no crea ventanas
  Lsp.ShaCache,     // Sha256DeBytes: la huella de READ=
  Lsp.Casa,
  Lsp.DesignerMeta; // RaizDeDiseno: lo que es la raiz para el IDE, con una tabla dada

type
  // el "control" del framework para NoVisualesDe, sin VCL ni FMX
  TControlFalso = class(TComponent);
  // el frame del marco para EsFrame, sin VCL ni FMX: lo que el ayudante
  // tiene cargado y registrado
  TMarcoDePrueba = class(TComponent);
  // uno que vive DENTRO de otro componente (un item de menu, una accion, un
  // campo): su contenedor lo devuelve GetParentComponent, como en TMenuItem
  TItemDentro = class(TComponent)
  public
    Contenedor: TComponent;
    function GetParentComponent: TComponent; override;
    function HasParent: Boolean; override;
  end;

function TItemDentro.GetParentComponent: TComponent;
begin
  Result := Contenedor;
end;

function TItemDentro.HasParent: Boolean;
begin
  Result := Contenedor <> nil;
end;

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
    // IGNORED=<de quien>|<partes> desde la 1.20.2: FR_ORIGEN_LECTOR si la
    // excepcion era del lector, la clase si la lanzo el codigo de un componente
    FR_IGNORED + FR_ORIGEN_LECTOR + '||||Property Alineacion does not exist'#13#10 +
    FR_IGNORED + FR_ORIGEN_LECTOR + '||||Invalid property value'#13#10 +
    FR_IGNORED + FR_ORIGEN_LECTOR + '|Panel1|Font.Size|Invalid property value|Error reading Panel1.Font.Size: Invalid property value'#13#10 +
    FR_IGNORED + FR_ORIGEN_LECTOR + '|Edit1|FontColor|Ungültiger Eigenschaftswert|Fehler beim Lesen von Edit1.FontColor: ' +
      'Ungültiger Eigenschaftswert'#13#10 +
    FR_IGNORED + 'EIBClientError||||a|b'#13#10 +
    FR_NOT_LOADED + 'EReadError|EditRight|FontColor|Invalid property value|Error reading EditRight.FontColor: ' +
      'Invalid property value'#13#10 +
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
  Assert.AreEqual<NativeInt>(5, Length(R.Ignoradas), 'IGNORED es repetible');
  // en sus partes, como las da el ayudante con el formato que compuso el
  // mensaje (en SU idioma), y el texto tal cual; sin partes, solo el texto
  // (David, 7-oct-2026)
  Assert.AreEqual('', R.Ignoradas[0].Componente, 'otra forma: solo texto');
  Assert.AreEqual('Property Alineacion does not exist', R.Ignoradas[0].Texto);
  Assert.AreEqual('Panel1', R.Ignoradas[2].Componente);
  Assert.AreEqual('Font.Size', R.Ignoradas[2].Propiedad);
  Assert.AreEqual('Invalid property value', R.Ignoradas[2].Motivo);
  Assert.AreEqual('Error reading Panel1.Font.Size: Invalid property value', R.Ignoradas[2].Texto);
  // un lector aleman: el servidor ya no parte el texto con el ingles
  Assert.AreEqual('Edit1', R.Ignoradas[3].Componente);
  Assert.AreEqual('FontColor', R.Ignoradas[3].Propiedad);
  Assert.AreEqual('Ungültiger Eigenschaftswert', R.Ignoradas[3].Motivo);
  // el texto puede llevar el separador: es lo ultimo
  Assert.AreEqual('a|b', R.Ignoradas[4].Texto);
  Assert.AreEqual('', R.Ignoradas[4].Componente);
  // el origen: '' si era del lector, la clase si no (DelCodigoDeUnComponente)
  Assert.AreEqual('', R.Ignoradas[0].Origen, 'del lector');
  Assert.IsFalse(DelCodigoDeUnComponente(R.Ignoradas[2]));
  Assert.AreEqual('EIBClientError', R.Ignoradas[4].Origen, 'el codigo de un componente');
  Assert.IsTrue(DelCodigoDeUnComponente(R.Ignoradas[4]));
  Assert.AreEqual('EIBClientError: a|b', TextoDeIgnorada(R.Ignoradas[4]));
  // NOTLOADED=<clase>|<partes>: el error que paro al lector
  Assert.IsTrue(R.NoCarga, 'NOTLOADED=');
  Assert.AreEqual('EditRight', R.Parada.Componente);
  Assert.AreEqual('FontColor', R.Parada.Propiedad);
  Assert.AreEqual('Error reading EditRight.FontColor: Invalid property value', R.Parada.Texto);
  Assert.AreEqual<NativeInt>(1, Length(R.Avisos));
  // cada item en sus partes: lo lee el lector, no la tool
  Assert.AreEqual<NativeInt>(2, Length(R.NoVisuales));
  Assert.AreEqual('Timer1', R.NoVisuales[0].Nombre);
  Assert.AreEqual('TTimer', R.NoVisuales[0].Clase);
  Assert.AreEqual('ActionList1', R.NoVisuales[1].Nombre);
  Assert.AreEqual('TActionList', R.NoVisuales[1].Clase);
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

procedure TFormRenderTests.LectorLeeLoLeidoConSuHuella;
var
  R: TRespuestaRender;
begin
  // READ=<sha256>|<ruta>, repetible; la ruta entera, con espacios y acentos;
  // una linea sin la barra no es una lectura (B5 rev6 de la 1.18.2)
  R := LeeRespuestaDeRender(FR_READ + 'AB12|C:\w\Base Comun'#$F3'n.dfm'#13#10 +
    FR_READ + 'sin barra'#13#10 + FR_READ + 'CD34|C:\w\UHija.pas'#13#10);
  Assert.AreEqual<NativeInt>(2, Length(R.Leidos));
  Assert.AreEqual('AB12', R.Leidos[0].Huella);
  Assert.AreEqual('C:\w\Base Comun'#$F3'n.dfm', R.Leidos[0].Ruta);
  Assert.AreEqual('CD34', R.Leidos[1].Huella);
  Assert.AreEqual('C:\w\UHija.pas', R.Leidos[1].Ruta);
end;

procedure TFormRenderTests.LoLeidoSeVuelveAMirarPorSusBytes;
var
  Leido: TLeidoPorElJuez;
begin
  // lo que leyo el juez, con la huella que compone el ayudante (AnotaLeido,
  // por Sha256DeBytes): igual, nada; cambiado o borrado, su nombre, y quien
  // iba a escribir lo juzgado no escribe (B5 rev6 de la 1.18.2)
  Leido.Ruta := Escribe('UBase.dfm', 'object FormBase: TFormBase'#13#10'end'#13#10);
  Leido.Huella := Sha256DeBytes(TFile.ReadAllBytes(Leido.Ruta));
  Assert.AreEqual('', CambioEnLoLeido([Leido]), 'los mismos bytes');
  Assert.AreEqual('', CambioEnLoLeido([]), 'nada leido, nada cambiado');
  Escribe('UBase.dfm', 'object FormBase: TFormBase'#13#10'  Caption = ''X'''#13#10'end'#13#10);
  Assert.AreEqual('UBase.dfm', CambioEnLoLeido([Leido]), 'cambiado: su nombre');
  TFile.Delete(Leido.Ruta);
  Assert.AreEqual('UBase.dfm', CambioEnLoLeido([Leido]), 'borrado: su nombre, sin lanzar');
end;

procedure TFormRenderTests.AncestroAnotaSuPasConLaHuella;
var
  Leidos: TStringList;
  Dfm, Pas, Pedido: string;
begin
  // el .pas que decide la cadena se anota con la huella de sus bytes (READ=);
  // y el fichero PEDIDO no se anota nunca: con --folder es la propuesta del
  // servidor (B5 rev6 de la 1.18.2)
  Pas := Escribe('UHija.pas', 'unit UHija;'#13#10'interface'#13#10'type'#13#10 +
    '  TFormHija = class(TFormBase)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  Dfm := Escribe('UHija.dfm', 'inherited FormHija: TFormHija'#13#10'end'#13#10);
  Leidos := TStringList.Create;
  try
    Assert.AreEqual('TFormBase', AncestroDeClase(Dfm, 'TFormHija', Leidos));
    Assert.AreEqual(Sha256DeBytes(TFile.ReadAllBytes(Pas)) + '|' + Pas, Leidos.Text.Trim);
    Pedido := GPeticion.Path;
    GPeticion.Path := Pas;
    try
      Leidos.Clear;
      AncestroDeClase(Dfm, 'TFormHija', Leidos);
      Assert.AreEqual(0, Leidos.Count, 'el pedido no se anota');
    finally
      GPeticion.Path := Pedido;
    end;
  finally
    Leidos.Free;
  end;
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
  Bin := DesignerTextoARecurso(TEncoding.ASCII.GetBytes('object FormB: TFormB'#13#10'end'#13#10));
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
  Assert.IsFalse(EsFrame(Dfm, 'TFormHija', TMarcoDePrueba), 'una form no es un frame');
  Escribe('UFrameX.pas', 'unit UFrameX;'#13#10'interface'#13#10'type'#13#10 +
    '  TFrameX = class(TMarcoDePrueba)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
  FrameDfm := Escribe('UFrameX.dfm', 'object FrameX: TFrameX'#13#10'end'#13#10);
  // sin --root, lo dice la clase CARGADA del ancestro que escribe el .pas, no
  // su nombre
  System.Classes.RegisterClass(TMarcoDePrueba); // no el de Winapi.Windows
  try
    Assert.IsTrue(EsFrame(FrameDfm, 'TFrameX', TMarcoDePrueba), 'un frame: su ancestro cargado es el frame del marco');
    Escribe('UHost.pas', 'unit UHost;'#13#10'interface'#13#10'type'#13#10 +
      '  TFormHost = class(TMainframeForm)'#13#10'  end;'#13#10'implementation'#13#10'end.'#13#10);
    Assert.IsFalse(EsFrame(Escribe('UHost.dfm', 'object FormHost: TFormHost'#13#10'end'#13#10), 'TFormHost',
      TMarcoDePrueba), 'frame en el nombre del ancestro no lo hace frame (la regla vieja decia que si)');
  finally
    System.Classes.UnRegisterClass(TMarcoDePrueba);
  end;
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
  Raiz, SinSitio, Timer, Menu, Boton: TComponent;
  Item: TItemDentro;
begin
  Raiz := TComponent.Create(nil);
  try
    // uno de la raiz SIN posicion SI cuenta, y va en 0,0 como en el IDE: un
    // no visual sin Left/Top ni se dibujaba ni se listaba (3.6 de la 1.18.0,
    // Hermes). El criterio viejo, "sin posicion no", era para lo de abajo
    SinSitio := TComponent.Create(Raiz);
    SinSitio.Name := 'Item0';
    Timer := TComponent.Create(Raiz);
    Timer.Name := 'Timer1';
    Timer.DesignInfo := (60 shl 16) or 300; // Left 300, Top 60, como el dfm
    Menu := TComponent.Create(Raiz);
    Menu.Name := 'Menu1';
    Menu.DesignInfo := (50 shl 16) or 100;
    Item := TItemDentro.Create(Raiz);
    Item.Name := 'Item1'; // un item de menu: vive DENTRO del menu, sin posicion
    Item.Contenedor := Menu;
    Boton := TControlFalso.Create(Raiz);
    Boton.Name := 'Boton1';
    Boton.DesignInfo := (10 shl 16) or 10;
    TComponent.Create(Timer).Name := 'DeOtro'; // de otro dueno: no es de la raiz
    Assert.AreEqual('Item0:TComponent,Timer1:TComponent,Menu1:TComponent',
      ListaDeNoVisuales(NoVisualesDe(Raiz, TControlFalso)),
      'el de la raiz sin posicion si; ni el control, ni el que vive dentro de otro sin posicion, ni el de otro dueno');
    Assert.AreEqual(300, PosicionDeNoVisual(Timer).X);
    Assert.AreEqual(60, PosicionDeNoVisual(Timer).Y);
    Assert.AreEqual(0, PosicionDeNoVisual(SinSitio).X, 'sin posicion, en 0,0');
    Assert.AreEqual(0, PosicionDeNoVisual(SinSitio).Y);
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
  // --root solo si el designer pedido es el de la unidad; lo que es su raiz
  // lo juzga Lsp.DesignerMeta.RaizDeDiseno (LaRaizDeDisenoPorLaTabla, con una
  // tabla dada; con la de la instalacion y el motor, el registro del IDE y
  // add-unit, tests/test_raiz_de_diseno_1202.py). Aqui, lo que no llega al
  // juez
  // un X.fmx al lado de un X.dfm: la unidad es del .dfm, no del .fmx pedido
  Unidad('UDos', 'TDos', '(TFrame)');
  Assert.AreEqual('', RaizParaElRender(Escribe('UDos.fmx', 'object Dos: TDos'#13#10'end'#13#10)),
    'el designer de la unidad no es el pedido');
  Assert.AreEqual('', RaizParaElRender(Escribe('Suelto.dfm', 'object A: TA'#13#10'end'#13#10)), 'sin .pas');
end;

procedure TFormRenderTests.LaRaizDeDisenoPorLaTabla;
var
  M: TMetaTable;
  DC, Corte: string;

  function Raiz(const ANombre, ATipos, AClase: string): TRaizDeDiseno;
  begin
    Result := RaizDeDiseno(M, Escribe(ANombre + '.pas', 'unit ' + ANombre + ';'#13#10'interface'#13#10 +
      'type'#13#10 + ATipos + 'implementation'#13#10'end.'#13#10), '', AClase, DC, Corte);
  end;

begin
  // lo que es la raiz para el IDE: la clase juez (la primera de la cadena que
  // la tabla conoce) y su categoria por la JERARQUIA de la tabla, no por su
  // nombre. Era una lista (TFrame, TDataModule, TForm, TForm3D...) y un
  // sufijo; un TWebModule era una form. Sin bases de otra unidad: esas las
  // sigue el motor
  M := TMetaTable.Create([
    'C System.Classes:TComponent',
    'C System.Classes:TStringList',
    'C System.Classes:TDataModule', 'H System.Classes:TDataModule System.Classes:TComponent',
    'C Vcl.Forms:TScrollingWinControl', 'H Vcl.Forms:TScrollingWinControl System.Classes:TComponent',
    'C Vcl.Forms:TCustomFrame', 'H Vcl.Forms:TCustomFrame Vcl.Forms:TScrollingWinControl',
    'C Vcl.Forms:TFrame', 'H Vcl.Forms:TFrame Vcl.Forms:TCustomFrame',
    'C Vcl.Forms:TCustomForm', 'H Vcl.Forms:TCustomForm Vcl.Forms:TScrollingWinControl',
    'C Vcl.Forms:TForm', 'H Vcl.Forms:TForm Vcl.Forms:TCustomForm',
    'C Web.HTTPApp:TWebModule', 'H Web.HTTPApp:TWebModule System.Classes:TDataModule']);
  try
    Assert.AreEqual(Ord(rdFrame), Ord(Raiz('URA', '  TMarcoA = class(TFrame)'#13#10'  end;'#13#10, 'TMarcoA')), 'frame');
    Assert.AreEqual('TFrame', DC, 'lo que escribe el IDE en un frame');
    Assert.AreEqual(Ord(rdFrame), Ord(Raiz('URB', '  TMarcoB = class abstract(Vcl.Forms.TCustomFrame)'#13#10 +
      '  end;'#13#10, 'TMarcoB')), 'abstract y con la unidad delante');
    Assert.AreEqual('TFrame', DC, 'el frame del marco, no su base');
    Assert.AreEqual(Ord(rdForm), Ord(Raiz('URC', '  TFichaA = class(TForm)'#13#10'  end;'#13#10, 'TFichaA')), 'form');
    Assert.AreEqual('', DC, 'una form no lleva DesignClass');
    Assert.AreEqual(Ord(rdModulo), Ord(Raiz('URD', '  TDatosA = class(TDataModule)'#13#10'  end;'#13#10, 'TDatosA')),
      'data module');
    Assert.AreEqual('TDataModule', DC);
    Assert.AreEqual(Ord(rdModulo), Ord(Raiz('URE', '  TWebA = class(TWebModule)'#13#10'  end;'#13#10, 'TWebA')),
      'un modulo que no es TDataModule (la lista decia form)');
    Assert.AreEqual('TWebModule', DC, 'su clase, la que escribe el IDE');
    // una base del MISMO fichero, declarada antes: sin motor
    Assert.AreEqual(Ord(rdFrame), Ord(Raiz('URF', '  TBaseLocal = class(TFrame)'#13#10'  end;'#13#10 +
      '  TMarcoF = class(TBaseLocal)'#13#10'  end;'#13#10, 'TMarcoF')), 'la base de la propia unidad');
    // frame en el nombre no lo hace frame
    Assert.AreEqual(Ord(rdForm), Ord(Raiz('URG', '  TMainframeForm = class(TForm)'#13#10'  end;'#13#10 +
      '  TFormHost = class(TMainframeForm)'#13#10'  end;'#13#10, 'TFormHost')), 'una form con frame en el nombre');
    // la que llega a una clase que no es un componente no es una raiz
    Assert.AreEqual(Ord(rdDesconocida), Ord(Raiz('URH', '  TListaRara = class(TStringList)'#13#10'  end;'#13#10,
      'TListaRara')), 'un TStringList no es un modulo');
    Assert.AreEqual('TStringList', Corte, 'donde se acaba lo que se sabe');
  finally
    M.Free;
  end;
  // y su lector, lo que el IDE ya escribio en un <DesignClass>
  Assert.AreEqual(Ord(rdForm), Ord(RaizDeDesignClass('')), 'sin DesignClass, una form');
  Assert.AreEqual(Ord(rdFrame), Ord(RaizDeDesignClass(DesignClassDeFrame(False))), 'el inverso del escritor');
  Assert.AreEqual(Ord(rdModulo), Ord(RaizDeDesignClass('TdmlMainComp')), 'la base del usuario que nombra el IDE');
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

{ V106 de la 1.23.1: IGNORED= y NOTLOADED= son la MISMA forma,
  <cabeza>|<partes>, con UN lector: el de NOTLOADED= no leia nada sin cabeza o
  sin separador, y el de IGNORED= se quedaba el valor entero como texto }
procedure TFormRenderTests.LaCabezaYSusPartesTienenUnLector;
var
  R: TRespuestaRender;
begin
  R := LeeRespuestaDeRender(FR_NOT_LOADED + 'mensaje sin partes'#13#10);
  Assert.IsTrue(R.NoCarga, 'NOTLOADED=');
  Assert.AreEqual('mensaje sin partes', R.Parada.Texto, 'sin separador, todo es el texto');
  Assert.AreEqual('', R.ClaseDeLaParada, 'y no hay cabeza');
  R := LeeRespuestaDeRender(FR_NOT_LOADED + '|||motivo|el texto'#13#10);
  Assert.AreEqual('motivo', R.Parada.Motivo, 'sin cabeza, sus partes');
  Assert.AreEqual('el texto', R.Parada.Texto);
  R := LeeRespuestaDeRender(FR_IGNORED + 'mensaje sin partes'#13#10);
  Assert.AreEqual('mensaje sin partes', R.Ignoradas[0].Texto, 'IGNORED=, igual');
end;

initialization
  TDUnitX.RegisterTestFixture(TFormRenderTests);

end.
