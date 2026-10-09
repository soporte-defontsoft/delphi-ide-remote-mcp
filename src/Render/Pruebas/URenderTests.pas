unit URenderTests;

{ La bateria MANUAL de los renderizadores (src\Render): cada test lanza un
  ayudante como lo hace el servidor (linea de comandos, stdout, codigo de
  salida) y comprueba el contrato de FormRenderProtocolo.inc y el PNG. Mide
  lo que ninguna bateria del repo puede: el rc 3 del vigia (--timeout 1), el
  rc 2 de uso y --fidelity print forzado en una sesion con escritorio.

  Fuera de run_all y de delphi_test: lanza los exes, y en el contenedor de
  delphi_test no se pueden crear ventanas (medido el 7-oct-2026: 1 de 20).
  Se pasa a mano desde la sesion del usuario tras tocar un ayudante y antes
  de una release (src\Render\README.md).

  Las cobayas hechas a mano viven aqui (src\Render\Pruebas) y sus tests
  pasan SIEMPRE. Las de Galatea (forms reales con paquetes de terceros) NO
  viajan en el repo, que es publico: su carpeta sale de RENDER_COBAYAS o de
  la primera linea de render_cobayas.txt junto al runner, y sin ella su
  fixture ni se registra (DUnitX no tiene "saltado" en marcha; ver la
  initialization). Los ayudantes se buscan junto al runner y, si no estan,
  en ..\Win32\Release (lo que se publica) o ..\Win32\Debug. }

interface

uses
  DUnitX.TestFramework, System.Classes;

type
  TRespuesta = record
    Rc: Cardinal;
    Lineas: TArray<string>;
    function Valor(const AClave: string): string;   // '' si no esta
    function Tiene(const AClave: string): Boolean;
    function Todas(const AClave: string): TArray<string>;
  end;

  { Con las cobayas hechas a mano: tienen que pasar siempre }
  [TestFixture]
  TRenderTests = class
  public
    [Test] procedure Vcl_Prueba_window_o_print;
    [Test] procedure Vcl_print_forzado;
    [Test] procedure Vcl_estado_de_vista;
    [Test] procedure Vcl_estado_invalido_rc1;
    [Test] procedure Vcl_rect_del_componente;
    [Test] procedure Vcl_form_heredada;
    [Test] procedure Vcl_frames_inline_con_cambios;
    [Test] procedure Vcl_frame_solo;
    [Test] procedure Vcl_estilo_vsf;
    [Test] procedure Vcl_no_visuales_on_off;
    [Test] procedure Vcl_timeout_rc3;
    [Test] procedure Vcl_uso_rc2;
    [Test] procedure Fmx_frames_inline_con_cambios;
  end;

  { Con las cobayas DUMMY: RENDER_COBAYAS apunta a Pruebas\DUMMY. }
  [TestFixture]
  TRenderDUMMYTests = class
  public
    [Test] procedure Vcl_eventos;
    [Test] procedure Vcl_referencias;
    [Test] procedure Fmx_referencias;
    [Test] procedure Vcl_blobs;
    [Test] procedure Fmx_blobs;
    [Test] procedure Vcl_coleccion;
    [Test] procedure Vcl_herencia_ciclica;
    [Test] procedure Vcl_inline_ciclico;
    [Test] procedure Fmx_inline_ciclico;
    [Test] procedure Vcl_archivo_avi;
  end;

  { Con las cobayas de Galatea: solo si su carpeta existe }
  [TestFixture]
  TRenderGalateaTests = class
  public
    [Test] procedure Vcl_Galatea_con_paquetes;
    [Test] procedure Fmx_Login_canvas;
    [Test] procedure Fmx_estilo_fichero_y_none;
    [Test] procedure Fmx_estilo_de_plataforma;
    [Test] procedure Fmx_estilo_desconocido_rc1;
    [Test] procedure Fmx_frame_solo_con_terceros;
    [Test] procedure Fmx_rect_del_componente;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.StrUtils, System.Generics.Collections,
  System.Win.Registry, Vcl.Graphics, Vcl.Imaging.pngimage;

const
  {$I ..\FormRenderProtocolo.inc}

function Carpeta: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

{ Las cobayas hechas a mano: la carpeta del proyecto (el runner sale en
  Win64\Debug) }
function Pruebas: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(Carpeta, '..\..\'));
end;

{ La carpeta de las cobayas de Galatea: RENDER_COBAYAS, o la primera linea de
  render_cobayas.txt junto al runner; '' si no hay }
function CarpetaDeCobayas: string;
var
  F: string;
  L: TArray<string>;
begin
  Result := GetEnvironmentVariable('RENDER_COBAYAS').Trim;
  F := TPath.Combine(Carpeta, 'render_cobayas.txt');
  if (Result = '') and TFile.Exists(F) then
  begin
    L := TFile.ReadAllLines(F);
    if Length(L) > 0 then
      Result := L[0].Trim;
  end;
end;

function HayCobayas: Boolean;
begin
  Result := (CarpetaDeCobayas <> '') and TDirectory.Exists(CarpetaDeCobayas);
end;

function Cobaya(const ANombre: string): string;
begin
  Result := TPath.Combine(CarpetaDeCobayas, ANombre);
end;

function Ayudante(const ANombre: string): string;
begin
  Result := TPath.Combine(Carpeta, ANombre);
  if not TFile.Exists(Result) then
    Result := TPath.GetFullPath(TPath.Combine(Pruebas, '..\Win32\Release\' + ANombre));
  if not TFile.Exists(Result) then
    Result := TPath.GetFullPath(TPath.Combine(Pruebas, '..\Win32\Debug\' + ANombre));
  if not TFile.Exists(Result) then
    raise Exception.Create('no esta el ayudante ' + ANombre + ' (ni junto al runner ni en ..\Win32\Release|Debug)');
end;

{ La raiz del RAD Studio de los ayudantes (37.0), del registro del usuario:
  ninguna ruta de una maquina escrita aqui }
function RaizDelIde: string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS\37.0') then
      Result := IncludeTrailingPathDelimiter(Reg.ReadString('RootDir'));
  finally
    Reg.Free;
  end;
end;

function Salida(const ANombre: string): string;
begin
  Result := TPath.Combine(Carpeta, 'out_' + ANombre + '.png');
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

{ Lanza con stdout a un fichero (como RunCapturedIn en el servidor) }
function Lanza(const AExe, AArgs: string): TRespuesta;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd, Log: string;
begin
  Log := TPath.Combine(Carpeta, 'ultimo_stdout.txt');
  Cmd := Format('cmd.exe /c ""%s" %s > "%s" 2>&1"', [AExe, AArgs, Log]);
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  UniqueString(Cmd);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(Carpeta), SI, PI) then
    raise Exception.Create('CreateProcess: ' + SysErrorMessage(GetLastError));
  WaitForSingleObject(PI.hProcess, 120000);
  GetExitCodeProcess(PI.hProcess, Result.Rc);
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  if TFile.Exists(Log) then
    Result.Lineas := TFile.ReadAllLines(Log)
  else
    Result.Lineas := [];
end;

function TRespuesta.Valor(const AClave: string): string;
begin
  for var L in Lineas do
    if L.StartsWith(AClave) then
      Exit(L.Substring(Length(AClave)));
  Result := '';
end;

function TRespuesta.Tiene(const AClave: string): Boolean;
begin
  for var L in Lineas do
    if L.StartsWith(AClave) then
      Exit(True);
  Result := False;
end;

function TRespuesta.Todas(const AClave: string): TArray<string>;
begin
  Result := [];
  for var L in Lineas do
    if L.StartsWith(AClave) then
      Result := Result + [L.Substring(Length(AClave))];
end;

function Pixel(const APng: string; X, Y: Integer): TColor;
var
  Png: TPngImage;
  Bmp: TBitmap;
begin
  Png := TPngImage.Create;
  Bmp := TBitmap.Create;
  try
    Png.LoadFromFile(APng);
    Bmp.Assign(Png);
    Result := Bmp.Canvas.Pixels[X, Y];
  finally
    Bmp.Free;
    Png.Free;
  end;
end;

{ Colores distintos (muestreo): un PNG vacio tiene 1 }
function Colores(const APng: string): Integer;
var
  Png: TPngImage;
  Bmp: TBitmap;
  Vistos: TDictionary<TColor, Boolean>;
  X, Y: Integer;
begin
  Png := TPngImage.Create;
  Bmp := TBitmap.Create;
  Vistos := TDictionary<TColor, Boolean>.Create;
  try
    Png.LoadFromFile(APng);
    Bmp.Assign(Png);
    Y := 0;
    while Y < Bmp.Height do
    begin
      X := 0;
      while X < Bmp.Width do
      begin
        Vistos.AddOrSetValue(Bmp.Canvas.Pixels[X, Y], True);
        Inc(X, 2);
      end;
      Inc(Y, 2);
    end;
    Result := Vistos.Count;
  finally
    Vistos.Free;
    Bmp.Free;
    Png.Free;
  end;
end;

function Vcl(const AArgs: string): TRespuesta;
begin
  Result := Lanza(Ayudante('DelphiFormRenderVcl.exe'), AArgs);
end;

function Fmx(const AArgs: string): TRespuesta;
begin
  Result := Lanza(Ayudante('DelphiFormRenderFmx.exe'), AArgs);
end;

procedure CompruebaCaptura(const R: TRespuesta; const ATamano: string);
begin
  Assert.AreEqual<Cardinal>(FR_RC_OK, R.Rc, 'rc; salida: ' + string.Join(' | ', R.Lineas));
  Assert.IsFalse(R.Tiene(FR_ERROR), 'ERROR= con rc 0');
  Assert.IsTrue(TFile.Exists(R.Valor(FR_CAPTURE)), 'CAPTURE= apunta a un png que existe');
  if ATamano <> '' then
    Assert.AreEqual(ATamano, R.Valor(FR_SIZE), 'SIZE=');
  Assert.IsTrue(Colores(R.Valor(FR_CAPTURE)) > 8, 'el png no esta vacio');
  Assert.IsTrue(R.Tiene(FR_MS), 'MS=');
  Assert.AreEqual('96', R.Valor(FR_DPI), 'DPI=');
end;

{ ---- VCL ---- }

procedure TRenderTests.Vcl_Prueba_window_o_print;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s"', [Pruebas + 'Prueba.dfm', Salida('prueba')]));
  CompruebaCaptura(R, '400x200');
  Assert.AreEqual('FormPrueba:TFormPrueba:form', R.Valor(FR_ROOT));
  Assert.AreEqual('6', R.Valor(FR_COMPONENTS));
  Assert.AreEqual('0/0', R.Valor(FR_PACKAGES), 'una form estandar no carga paquetes');
  Assert.IsTrue(MatchStr(R.Valor(FR_FIDELITY), ['window', 'print']), 'FIDELITY=' + R.Valor(FR_FIDELITY));
  Assert.IsFalse(R.Tiene(FR_SUBSTITUTED));
  Assert.IsTrue(R.Tiene(FR_NONVISUALS), 'NONVISUALS= sale siempre, aunque no haya ninguno');
  Assert.AreEqual('', R.Valor(FR_NONVISUALS), 'Prueba.dfm no tiene no visuales');
end;

procedure TRenderTests.Vcl_print_forzado;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s" --fidelity print', [Pruebas + 'Prueba.dfm', Salida('prueba_print')]));
  CompruebaCaptura(R, '400x200');
  Assert.AreEqual('print', R.Valor(FR_FIDELITY));
end;

procedure TRenderTests.Vcl_estado_de_vista;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s" --state "Edit1.Text=cambiado" --state CheckBox1.Checked=False',
    [Pruebas + 'Prueba.dfm', Salida('prueba_state')]));
  CompruebaCaptura(R, '400x200');
end;

procedure TRenderTests.Vcl_estado_invalido_rc1;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s" --state Edit1.NoExiste=1', [Pruebas + 'Prueba.dfm', Salida('prueba_bad')]));
  Assert.AreEqual<Cardinal>(FR_RC_ERROR, R.Rc);
  Assert.IsTrue(R.Valor(FR_ERROR).StartsWith('[RENDER-012 NOT_FOUND]'), 'el rechazo del catalogo, sin la clase delante: ' + R.Valor(FR_ERROR));
  Assert.IsTrue(R.Valor(FR_ERROR).Contains('NoExiste'), R.Valor(FR_ERROR));
  R := Vcl(Format('--path "%s" --out "%s" --state Nadie.Text=1', [Pruebas + 'Prueba.dfm', Salida('prueba_bad2')]));
  Assert.AreEqual<Cardinal>(FR_RC_ERROR, R.Rc);
  Assert.IsTrue(R.Valor(FR_ERROR).StartsWith('[RENDER-011 NOT_FOUND]'), R.Valor(FR_ERROR));
  Assert.IsTrue(R.Valor(FR_ERROR).Contains('Nadie'), R.Valor(FR_ERROR));
end;

procedure TRenderTests.Vcl_rect_del_componente;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s" --component Panel1', [Pruebas + 'Prueba.dfm', Salida('prueba_rect')]));
  CompruebaCaptura(R, '400x200');
  Assert.AreEqual('Panel1=16,140,344,41', R.Valor(FR_RECT), 'el rect del dfm, en pixeles del png');
  R := Vcl(Format('--path "%s" --out "%s" --component Nadie', [Pruebas + 'Prueba.dfm', Salida('prueba_rect2')]));
  CompruebaCaptura(R, '400x200');
  Assert.IsFalse(R.Tiene(FR_RECT));
  Assert.IsTrue(R.Valor(FR_WARNING).Contains('Nadie'), 'un componente que no esta es un WARNING, no un error');
end;

procedure TRenderTests.Vcl_form_heredada;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s"', [Pruebas + 'UHija.dfm', Salida('hija')]));
  CompruebaCaptura(R, '420x300');
  Assert.AreEqual('FormHija:TFormHija:form', R.Valor(FR_ROOT));
  Assert.AreEqual('4', R.Valor(FR_COMPONENTS), 'los 3 de la base + el de la hija');
  Assert.IsFalse(R.Tiene(FR_IGNORED), string.Join(' | ', R.Todas(FR_IGNORED)));
  // la cabecera cambiada por la hija es clMoneyGreen ($C0DCC0): un pixel del panel
  Assert.AreEqual<TColor>($C0DCC0, Pixel(R.Valor(FR_CAPTURE), 10, 10), 'el panel lleva el color de la HIJA');
end;

procedure TRenderTests.Vcl_frames_inline_con_cambios;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s"', [Pruebas + 'UConFrame.dfm', Salida('conframe')]));
  CompruebaCaptura(R, '340x300');
  Assert.AreEqual('3', R.Valor(FR_COMPONENTS));
  Assert.IsFalse(R.Tiene(FR_IGNORED), 'los inherited del inline se resolvieron: ' + string.Join(' | ', R.Todas(FR_IGNORED)));
  Assert.IsFalse(R.Tiene(FR_SUBSTITUTED));
  // el panel del segundo frame lo cambia el inline a clYellow: (16+8+16, 168+64+20),
  // lejos del caption centrado (el ClearType del texto da pixeles de colores)
  Assert.AreEqual<TColor>(clYellow, Pixel(R.Valor(FR_CAPTURE), 40, 252), 'el cambio del inline se aplico sobre el frame');
  // y el del primero conserva el clInfoBk del frame
  Assert.AreEqual<TColor>(ColorToRGB(clInfoBk), Pixel(R.Valor(FR_CAPTURE), 40, 116), 'el primer frame es el del fichero');
end;

procedure TRenderTests.Vcl_frame_solo;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s"', [Pruebas + 'UFrameX.dfm', Salida('framex')]));
  CompruebaCaptura(R, '300x120');
  Assert.AreEqual('FrameX:TFrameX:frame', R.Valor(FR_ROOT), 'frame por su .pas, sin --root');
end;

procedure TRenderTests.Vcl_estilo_vsf;
var
  R: TRespuesta;
  Vsf: string;
begin
  Vsf := RaizDelIde + 'Redist\styles\vcl\Carbon.vsf';
  Assert.IsTrue(TFile.Exists(Vsf), 'el RAD Studio 37.0 trae Carbon.vsf: ' + Vsf);
  R := Vcl(Format('--path "%s" --out "%s" --style "%s"', [Pruebas + 'Prueba.dfm', Salida('vsf'), Vsf]));
  // sin tamano: fuera del modo diseno el borde con estilo cambia el cliente
  // (406x200 con Carbon, medido), como le pasa a la aplicacion
  CompruebaCaptura(R, '');
  Assert.IsTrue(R.Valor(FR_STYLE).StartsWith('Carbon'), R.Valor(FR_STYLE));
  Assert.AreNotEqual<TColor>(ColorToRGB(clBtnFace), Pixel(R.Valor(FR_CAPTURE), 380, 10), 'con Carbon el fondo no es clBtnFace');
end;

procedure TRenderTests.Vcl_no_visuales_on_off;
var
  R: TRespuesta;
begin
  // on hay que pedirlo: el defecto es off, el de la tool (3.4 de la 1.18.0)
  R := Vcl(Format('--path "%s" --out "%s" --nonvisual on', [Pruebas + 'UNoVisual.dfm', Salida('novisual_on')]));
  CompruebaCaptura(R, '400x200');
  Assert.AreEqual('2', R.Valor(FR_NONVISUAL), 'Timer1 y ActionList1');
  Assert.AreNotEqual<TColor>(ColorToRGB(clBtnFace), Pixel(R.Valor(FR_CAPTURE), 301, 101), 'el recuadro del Timer1 en su Left/Top');
  Assert.AreEqual('Timer1:TTimer,ActionList1:TActionList', R.Valor(FR_NONVISUALS), 'la lista, con los iconos dibujados');
  R := Vcl(Format('--path "%s" --out "%s" --nonvisual off', [Pruebas + 'UNoVisual.dfm', Salida('novisual_off')]));
  CompruebaCaptura(R, '400x200');
  Assert.IsFalse(R.Tiene(FR_NONVISUAL));
  Assert.AreEqual<TColor>(ColorToRGB(clBtnFace), Pixel(R.Valor(FR_CAPTURE), 301, 101), 'sin iconos el fondo queda limpio');
  Assert.AreEqual('Timer1:TTimer,ActionList1:TActionList', R.Valor(FR_NONVISUALS),
    'y la lista igual sin dibujarlos: el agente sabe que estan');
end;

procedure TRenderTests.Vcl_timeout_rc3;
var
  R: TRespuesta;
begin
  // con 1 ms cualquier form llega tarde: el vigia corta antes de pintar
  R := Vcl(Format('--path "%s" --out "%s" --timeout 1', [Pruebas + 'Prueba.dfm', Salida('timeout')]));
  Assert.AreEqual<Cardinal>(FR_RC_TIMEOUT, R.Rc, 'salida: ' + string.Join(' | ', R.Lineas));
  Assert.IsTrue(R.Valor(FR_ERROR).StartsWith('[RENDER-007 DENIED]'), R.Valor(FR_ERROR));
end;

procedure TRenderTests.Vcl_uso_rc2;
var
  R: TRespuesta;
begin
  R := Vcl('');
  Assert.AreEqual<Cardinal>(FR_RC_USAGE, R.Rc);
  Assert.IsTrue(R.Tiene(FR_ERROR));
  R := Vcl(Format('--path "%s" --out "%s"', [Pruebas + 'NoExiste.dfm', Salida('noexiste')]));
  Assert.AreEqual<Cardinal>(FR_RC_USAGE, R.Rc);
  R := Vcl(Format('--path "%s" --out "%s" --packages tal', [Pruebas + 'Prueba.dfm', Salida('badarg')]));
  Assert.AreEqual<Cardinal>(FR_RC_USAGE, R.Rc);
end;

{ ---- FMX ---- }

procedure TRenderTests.Fmx_frames_inline_con_cambios;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s"', [Pruebas + 'ConFrameF.fmx', Salida('confremef')]));
  CompruebaCaptura(R, '340x300');
  Assert.AreEqual('3', R.Valor(FR_COMPONENTS));
  Assert.IsFalse(R.Tiene(FR_IGNORED), string.Join(' | ', R.Todas(FR_IGNORED)));
  // el rectangulo del segundo frame lo cambia el inline a xFFFFFF80 (BGR $80FFFF)
  Assert.AreEqual<TColor>($80FFFF, Pixel(R.Valor(FR_CAPTURE), 40, 252), 'el cambio del inline se aplico');
  Assert.AreEqual<TColor>($FFE0C0, Pixel(R.Valor(FR_CAPTURE), 40, 116), 'el primero conserva el del frame');
end;

{ ---- con las cobayas de Galatea ---- }

procedure TRenderGalateaTests.Vcl_Galatea_con_paquetes;
var
  R: TRespuesta;
begin
  R := Vcl(Format('--path "%s" --out "%s" --state PageControlFicha.ActivePage=TabFacturacion --component TabFacturacion',
    [Cobaya('UFichaCliente.dfm'), Salida('galatea')]));
  CompruebaCaptura(R, '870x532');
  Assert.AreEqual('317', R.Valor(FR_COMPONENTS));
  Assert.IsFalse(R.Tiene(FR_SUBSTITUTED), 'todo lo de Galatea viene de los paquetes del IDE: ' + R.Valor(FR_SUBSTITUTED));
  Assert.IsTrue(R.Valor(FR_PACKAGES).StartsWith('1'), 'cargo los paquetes del IDE: ' + R.Valor(FR_PACKAGES));
  Assert.IsTrue(R.Valor(FR_RECT).StartsWith('TabFacturacion='), R.Valor(FR_RECT));
end;

procedure TRenderGalateaTests.Fmx_Login_canvas;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s"', [Cobaya('Galatea.View.Login.fmx'), Salida('login')]));
  CompruebaCaptura(R, '920x700');
  Assert.AreEqual('LoginForm:TLoginForm:form', R.Valor(FR_ROOT));
  Assert.AreEqual('65', R.Valor(FR_COMPONENTS));
  Assert.IsTrue(R.Valor(FR_FIDELITY).StartsWith('canvas'), R.Valor(FR_FIDELITY));
  Assert.IsTrue(R.Valor(FR_STYLE).Contains('StyleBook'), 'el estilo es el de la form: ' + R.Valor(FR_STYLE));
end;

procedure TRenderGalateaTests.Fmx_estilo_fichero_y_none;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s" --style "%s"', [Cobaya('Galatea.View.Login.fmx'), Salida('login_clasico'),
    Cobaya('Galatea.Clasico.style')]));
  CompruebaCaptura(R, '920x700');
  Assert.AreEqual('file Galatea.Clasico.style', R.Valor(FR_STYLE));
  R := Fmx(Format('--path "%s" --out "%s" --style none', [Cobaya('Galatea.View.Login.fmx'), Salida('login_none')]));
  CompruebaCaptura(R, '920x700');
  Assert.IsTrue(R.Valor(FR_STYLE).StartsWith('none'), R.Valor(FR_STYLE));
end;

procedure TRenderGalateaTests.Fmx_estilo_de_plataforma;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s" --style android', [Cobaya('Galatea.View.Login.fmx'), Salida('login_android')]));
  CompruebaCaptura(R, '920x700');
  Assert.IsTrue(R.Valor(FR_STYLE).Contains('ANDROIDSTYLE'), R.Valor(FR_STYLE));
  R := Fmx(Format('--path "%s" --out "%s" --style win11', [Cobaya('Galatea.View.Login.fmx'), Salida('login_win11')]));
  CompruebaCaptura(R, '920x700');
  Assert.IsTrue(R.Valor(FR_STYLE).Contains('WIN11STYLE'), R.Valor(FR_STYLE));
end;

procedure TRenderGalateaTests.Fmx_estilo_desconocido_rc1;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s" --style marte', [Cobaya('Galatea.View.Login.fmx'), Salida('login_marte')]));
  Assert.AreEqual<Cardinal>(FR_RC_ERROR, R.Rc);
  Assert.IsTrue(R.Valor(FR_ERROR).Contains('android'), 'el error lista las plataformas: ' + R.Valor(FR_ERROR));
end;

procedure TRenderGalateaTests.Fmx_frame_solo_con_terceros;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s"', [Cobaya('Galatea.Frame.Maestro.fmx'), Salida('maestro')]));
  CompruebaCaptura(R, '1280x600');
  Assert.AreEqual('MaestroFrame:TMaestroFrame:frame', R.Valor(FR_ROOT), 'frame por su .pas');
  Assert.IsFalse(R.Tiene(FR_SUBSTITUTED), 'el TTeeGrid viene de los paquetes del IDE: ' + R.Valor(FR_SUBSTITUTED));
  Assert.IsTrue(R.Valor(FR_PACKAGES).StartsWith('1'), R.Valor(FR_PACKAGES));
end;

procedure TRenderGalateaTests.Fmx_rect_del_componente;
var
  R: TRespuesta;
begin
  R := Fmx(Format('--path "%s" --out "%s" --component pnlVelo', [Cobaya('Galatea.View.Login.fmx'), Salida('login_rect')]));
  CompruebaCaptura(R, '920x700');
  Assert.IsTrue(R.Valor(FR_RECT).StartsWith('pnlVelo='), R.Valor(FR_RECT));
end;


{ ---- cobayas DUMMY: solo datos propios, sin proyectos privados ---- }

function RenderDUMMY(const ANombre: string): TRespuesta;
var
  Args: string;
begin
  Args := Format('--path "%s" --out "%s" --root form --packages none --nonvisual off ' +
    '--fidelity print --style none --timeout 2500', [Cobaya(ANombre), Salida(ANombre)]);
  if SameText(ExtractFileExt(ANombre), '.fmx') then
    Result := Fmx(Args)
  else
    Result := Vcl(Args);
end;

procedure CompruebaDUMMY(const R: TRespuesta);
begin
  Assert.AreEqual<Cardinal>(FR_RC_OK, R.Rc, string.Join(' | ', R.Lineas));
  Assert.IsTrue(TFile.Exists(R.Valor(FR_CAPTURE)), 'PNG propio creado');
end;

procedure TRenderDUMMYTests.Vcl_eventos;
begin
  CompruebaDUMMY(RenderDUMMY('DUMMY-events.dfm'));
end;

procedure TRenderDUMMYTests.Vcl_referencias;
begin
  CompruebaDUMMY(RenderDUMMY('DUMMY-references.dfm'));
end;

procedure TRenderDUMMYTests.Fmx_referencias;
begin
  CompruebaDUMMY(RenderDUMMY('DUMMY-references.fmx'));
end;

procedure TRenderDUMMYTests.Vcl_blobs;
var
  R: TRespuesta;
begin
  R := RenderDUMMY('DUMMY-blobs.dfm');
  CompruebaDUMMY(R);
  Assert.IsTrue(R.Tiene(FR_IGNORED), 'el blob invalido se ignora');
end;

procedure TRenderDUMMYTests.Fmx_blobs;
var
  R: TRespuesta;
begin
  R := RenderDUMMY('DUMMY-blobs.fmx');
  CompruebaDUMMY(R);
  Assert.IsTrue(R.Tiene(FR_IGNORED), 'el bitmap invalido se ignora');
end;

procedure TRenderDUMMYTests.Vcl_coleccion;
begin
  CompruebaDUMMY(RenderDUMMY('DUMMY-collection.dfm'));
end;

procedure TRenderDUMMYTests.Vcl_herencia_ciclica;
begin
  CompruebaDUMMY(RenderDUMMY('DUMMY-inherited.dfm'));
end;

procedure TRenderDUMMYTests.Vcl_inline_ciclico;
var
  R: TRespuesta;
begin
  R := RenderDUMMY('DUMMY-inline.dfm');
  Assert.AreEqual<Cardinal>(FR_RC_TIMEOUT, R.Rc, string.Join(' | ', R.Lineas));
  Assert.IsTrue(R.Valor(FR_ERROR).Contains('RENDER-007'));
end;

procedure TRenderDUMMYTests.Fmx_inline_ciclico;
var
  R: TRespuesta;
begin
  R := RenderDUMMY('DUMMY-inline.fmx');
  Assert.AreEqual<Cardinal>(FR_RC_TIMEOUT, R.Rc, string.Join(' | ', R.Lineas));
  Assert.IsTrue(R.Valor(FR_ERROR).Contains('RENDER-007'));
end;

procedure TRenderDUMMYTests.Vcl_archivo_avi;
var
  Dfm, Avi: string;
  H: THandle;
  R: TRespuesta;
begin
  // Control positivo y negativo del MISMO dato: distingue un setter que
  // abre el fichero de una propiedad que solo conserva texto.
  Dfm := TPath.Combine(Carpeta, 'DUMMY-path-runtime.dfm');
  Avi := Cobaya('DUMMY.avi');
  TFile.WriteAllText(Dfm, TFile.ReadAllText(Cobaya('DUMMY-path.dfm')).Replace(
    'DUMMY.avi', Avi));
  try
    R := Vcl(Format('--path "%s" --out "%s" --root form --packages none ' +
      '--fidelity print --timeout 2500', [Dfm, Salida('DUMMY-avi')]));
    CompruebaDUMMY(R);
    H := CreateFile(PChar(Avi), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
    Assert.IsTrue(H <> INVALID_HANDLE_VALUE, 'la cobaya se bloquea en exclusiva');
    try
      R := Vcl(Format('--path "%s" --out "%s" --root form --packages none ' +
        '--fidelity print --timeout 2500', [Dfm, Salida('DUMMY-avi-locked')]));
      Assert.AreEqual<Cardinal>(FR_RC_ERROR, R.Rc, string.Join(' | ', R.Lineas));
      Assert.IsTrue(R.Tiene(FR_ERROR), 'el mismo archivo bloqueado no se abre');
    finally
      CloseHandle(H);
    end;
  finally
    TFile.Delete(Dfm);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRenderTests);
  // DUnitX no tiene "saltado" en marcha: un test sale Ignored solo por el
  // atributo [Ignore] (DUnitX.TestRunner: test.Ignored -> ExecuteIgnoredResult),
  // y Assert.Pass lanza ETestPass, que cuenta como SUPERADO
  // (ExecuteSuccessfulResult; fuente del IDE 37.0, leido el 7-oct-2026). Sin
  // las cobayas de Galatea su fixture ni se registra, y se dice.
  if HayCobayas then
  begin
    if TFile.Exists(Cobaya('DUMMY-events.dfm')) then
      TDUnitX.RegisterTestFixture(TRenderDUMMYTests)
    else
      TDUnitX.RegisterTestFixture(TRenderGalateaTests);
  end
  else
    Writeln('NO MEDIDO: sin las cobayas de Galatea (RENDER_COBAYAS, o render_cobayas.txt junto al ' +
      'runner): los 7 casos de paquetes de terceros y estilos reales no se pasan.');

end.
