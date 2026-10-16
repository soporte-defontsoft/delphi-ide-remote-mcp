unit LspTests.Images;

{ Captura en UN SOLO PASO (25-sep-2026): el escalado en memoria, el adjunto
  que viaja como item image y se lleva una sola vez, y el reconocedor de
  capturas del agente con sus dos subcarpetas (desktop y android). Y el
  tamano y el recorte EN MEMORIA, que leen y escriben por las puertas quienes
  los llaman (1.18.2, 2b). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TImageTests = class
  public
    [Test] procedure EscalaReduceAlAnchoMaximo;
    [Test] procedure EscalaNoTocaLoQueYaCabe;
    [Test] procedure AdjuntoViajaComoItemImage;
    [Test] procedure AdjuntoSeConsumeAlEnvolver;
    [Test] procedure LimpiarDescartaAdjuntos;
    [Test] procedure CapturaDelAgenteReconoceSusDosSubcarpetas;
    [Test] procedure FrameSinTokenDejaLosPixelesComoVienen;
    [Test] procedure FrameConvierteEscalaYOrigen;
    [Test] procedure FrameEsLaInversaDeSuNombrador;
    [Test] procedure FrameRechazaFormaYPuntoFuera;
    [Test] procedure CapturaConOutEnTemporalesSeRechaza;
    [Test] procedure BorradoSoloDentroDeLoDesechable;
    [Test] procedure BorradoNuncaUnidadNiSistema;
    [Test] procedure DescargaTemporalNombradorYLector;
    [Test] procedure SinCapturaDiceElMotivo;
    [Test] procedure TamanoSaleDeLaCabecera;
    [Test] procedure CabeceraPngLectorInversoDelEscritor;
    [Test] procedure EscritorDelNodoLoLeeElDecodificador;
    [Test] procedure RecorteEnMemoriaSeAjustaAlLienzo;
    [Test] procedure CasaDeEntregablesReconoceASuNombrador;
    [Test] procedure ColocarEnLaCasaLoJuzgaSuNombrador;
    [Test] procedure CapturaSinSalidaSeConsumeYLoDice;
    [Test] procedure EnLineaLoQueCabeSaleTalCual;
    [Test] procedure EnLineaLoQueNoCabePasaAJpegDelMismoTamano;
    [Test] procedure EnLineaLoQueNiAsiCabeLoDice;
    [Test] procedure EntregaEnLineaGrandeCabeConElMismoFrame;
    [Test] procedure GestoBienDejaSoloLaAccion;
    [Test] procedure GestoConAvisoLoConserva;
    [Test] procedure StatusYFalloSonDiagnosticoSinProtocoloNiUso;
    [Test] procedure NodoWindowsGestoBienDejaSoloLaAccion;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Types,
  System.JSON,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Lsp.Imagen,
  Lsp.Png,
  Mld.Captura,   // GuardarPNG: el escritor de PNG del nodo de escritorio
  Mld.Textos,    // el catalogo del nodo (ANTES de Lsp.Texts: su MsgFmt no tapa al de la casa)
  Lsp.InlineImages,
  Lsp.Base64,
  Lsp.Guard,
  Lsp.RemoteRun, // MotivoSinCaptura
  Lsp.Texts,
  Lsp.Patch,     // ColocaContenido con su lugar (2i)
  Lsp.Casa,
  Vcl.Imaging.jpeg, // las imagenes en linea que no caben en PNG
  System.StrUtils,
  System.Math;

function PngDe(W, H: Integer): TArray<Byte>;
var
  Bmp: TBitmap;
  Png: TPngImage;
  S: TBytesStream;
begin
  Bmp := TBitmap.Create;
  Png := TPngImage.Create;
  S := TBytesStream.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, W, H));
    Png.Assign(Bmp);
    Png.SaveToStream(S);
    Result := Copy(S.Bytes, 0, S.Size);
  finally
    S.Free;
    Png.Free;
    Bmp.Free;
  end;
end;

{ Un PNG que pesa como una captura de verdad: un degradado con ruido (el
  ruido es lo que no comprime en PNG - el fondo de foto del Zorin, 972 KB a
  1280, 16-oct-2026 - y un JPEG si lo aguanta). Determinista: su propio
  generador, no Random. }
function PngRuidoso(W, H: Integer): TArray<Byte>;
var
  Bmp: TBitmap;
  Png: TPngImage;
  S: TBytesStream;
  Fila: PByte;
  Semilla: Cardinal;

  function Canal(Base: Integer): Byte;
  begin
    Semilla := Semilla * 1103515245 + 12345;
    Result := Byte(Max(0, Min(255, Base + Integer((Semilla shr 16) mod 49) - 24)));
  end;

begin
  Bmp := TBitmap.Create;
  Png := TPngImage.Create;
  S := TBytesStream.Create;
  Semilla := 20261016;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(W, H);
    for var Y := 0 to H - 1 do
    begin
      Fila := Bmp.ScanLine[Y];
      for var X := 0 to W - 1 do
      begin
        Fila[X * 3] := Canal(X * 255 div W);
        Fila[X * 3 + 1] := Canal(Y * 255 div H);
        Fila[X * 3 + 2] := Canal(128);
      end;
    end;
    Png.Assign(Bmp);
    Png.SaveToStream(S);
    Result := Copy(S.Bytes, 0, S.Size);
  finally
    S.Free;
    Png.Free;
    Bmp.Free;
  end;
end;

{ El ancho y el alto de un JPEG, por el decodificador de la RTL. }
procedure TamanoJpeg(const B: TArray<Byte>; out W, H: Integer);
var
  Jpg: TJPEGImage;
  S: TBytesStream;
begin
  Jpg := TJPEGImage.Create;
  S := TBytesStream.Create(B);
  try
    Jpg.LoadFromStream(S);
    W := Jpg.Width;
    H := Jpg.Height;
  finally
    S.Free;
    Jpg.Free;
  end;
end;

function Iguales(const A, B: TArray<Byte>): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure TImageTests.EscalaReduceAlAnchoMaximo;
var
  Sal: TArray<Byte>;
  Esc: Double;
  W, H: Integer;
begin
  Assert.AreEqual('', EscalaPngBytes(PngDe(2000, 100), 1000, Sal, Esc, W, H));
  Assert.AreEqual(1000, W);
  Assert.AreEqual(50, H);
  Assert.AreEqual(0.5, Esc, 0.0001);
  Assert.IsTrue(Length(Sal) > 0, 'sin bytes de salida');
end;

procedure TImageTests.EscalaNoTocaLoQueYaCabe;
var
  Ent, Sal: TArray<Byte>;
  Esc: Double;
  W, H: Integer;
begin
  Ent := PngDe(500, 40);
  Assert.AreEqual('', EscalaPngBytes(Ent, 1000, Sal, Esc, W, H));
  Assert.AreEqual(1.0, Esc, 0.0001);
  Assert.AreEqual(500, W);
  Assert.IsTrue(Iguales(Sal, Ent), 'lo que ya cabe debe salir tal cual');
end;

procedure TImageTests.AdjuntoViajaComoItemImage;
var
  Arr: TJSONArray;
  B, Dec: TArray<Byte>;
begin
  ClearAttachedImages;
  B := PngDe(10, 10);
  AttachImage(B, 'image/png');
  Arr := WrapWithAttachedImages('{"ok":true}');
  try
    Assert.IsNotNull(Arr);
    Assert.AreEqual(2, Arr.Count);
    Assert.AreEqual('text', (Arr.Items[0] as TJSONObject).GetValue<string>('type'));
    Assert.AreEqual('{"ok":true}', (Arr.Items[0] as TJSONObject).GetValue<string>('text'));
    Assert.AreEqual('image', (Arr.Items[1] as TJSONObject).GetValue<string>('type'));
    Assert.AreEqual('image/png', (Arr.Items[1] as TJSONObject).GetValue<string>('mimeType'));
    Assert.AreEqual('', Base64ToBytes((Arr.Items[1] as TJSONObject).GetValue<string>('data'), 'data', Dec));
    Assert.IsTrue(Iguales(Dec, B), 'la imagen no vuelve byte a byte');
  finally
    Arr.Free;
  end;
end;

procedure TImageTests.AdjuntoSeConsumeAlEnvolver;
begin
  ClearAttachedImages;
  AttachImage(PngDe(4, 4), 'image/png');
  WrapWithAttachedImages('x').Free;
  Assert.IsNull(WrapWithAttachedImages('x'), 'el adjunto viajo dos veces');
end;

procedure TImageTests.LimpiarDescartaAdjuntos;
begin
  AttachImage(PngDe(4, 4), 'image/png');
  ClearAttachedImages;
  Assert.IsNull(WrapWithAttachedImages('x'), 'un adjunto sobrevivio a la limpieza');
end;

procedure TImageTests.CapturaDelAgenteReconoceSusDosSubcarpetas;
begin
  Assert.IsTrue(IsAgentCapture('C:\w\__delphi-temp\hermes\desktop\desktop-a.png'), 'desktop');
  Assert.IsTrue(IsAgentCapture('C:\w\__delphi-temp\hermes\android\android-a.png'), 'android');
  Assert.IsFalse(IsAgentCapture('C:\w\capturas\desktop\a.png'), 'un out= del agente no es temporal');
  Assert.IsFalse(IsAgentCapture('C:\w\__delphi-temp\hermes\desktop\a.txt'), 'solo png');
end;

procedure TImageTests.FrameSinTokenDejaLosPixelesComoVienen;
var
  X, Y: Integer;
begin
  Assert.AreEqual('', FramePoint('', '330', '288', X, Y));
  Assert.AreEqual(330, X);
  Assert.AreEqual(288, Y);
end;

procedure TImageTests.FrameConvierteEscalaYOrigen;
var
  X, Y: Integer;
begin
  // escritorio de 3440 servido a 1280: (640,268) de la imagen -> (1720,720)
  Assert.AreEqual('', FramePoint('1280x536@3440x1440+0+0', '640', '268', X, Y));
  Assert.AreEqual(1720, X);
  Assert.AreEqual(720, Y);
  // recorte de 400x300 en (1000,200) sin escalar: se suma el origen
  Assert.AreEqual('', FramePoint('400x300@400x300+1000+200', '10', '20', X, Y));
  Assert.AreEqual(1010, X);
  Assert.AreEqual(220, Y);
  // Android: PNG de 1080x2400 y pantalla en vigor 720x1600 (tapScale 2/3)
  Assert.AreEqual('', FramePoint('1080x2400@720x1600+0+0', '540', '1200', X, Y));
  Assert.AreEqual(360, X);
  Assert.AreEqual(800, Y);
end;

procedure TImageTests.FrameEsLaInversaDeSuNombrador;
var
  X, Y: Integer;
begin
  Assert.AreEqual('1280x536@3440x1440+5+-7', FrameOf(1280, 536, 3440, 1440, 5, -7));
  Assert.AreEqual('', FramePoint(FrameOf(1280, 536, 3440, 1440, 5, -7), '0', '0', X, Y));
  Assert.AreEqual(5, X);
  Assert.AreEqual(-7, Y);
end;

procedure TImageTests.FrameRechazaFormaYPuntoFuera;
var
  X, Y: Integer;
begin
  Assert.IsTrue(EsRechazo(FramePoint('1280x536', '1', '1', X, Y)), 'un frame malo se rechaza');
  Assert.IsTrue(EsRechazo(FramePoint('0x536@3440x1440+0+0', '1', '1', X, Y)), 'un frame malo se rechaza');
  Assert.IsTrue(EsRechazo(FramePoint('1280x536@3440x1440+0+0', '1280', '10', X, Y)), 'un frame malo se rechaza');
  Assert.IsTrue(EsRechazo(FramePoint('1280x536@3440x1440+0+0', '-1', '10', X, Y)), 'un frame malo se rechaza');
end;

procedure TImageTests.CapturaConOutEnTemporalesSeRechaza;
var
  F, R: string;
begin
  // Junto al ejecutor: dentro del repo, o sea dentro de la jaula con la que
  // lo lance el servidor de pruebas (una ruta de fuera la rechaza la jaula y
  // nunca llega a la regla de temporales).
  R := CaptureTarget(ExtractFilePath(ParamStr(0)) + '__delphi-temp\cap.png',
    CAPTURE_SUB_DESKTOP, 'desktop', '.png', F);
  Assert.IsTrue(EsRechazo(R), 'una captura con out= en __delphi-temp se acumula: ' + R);
  Assert.IsTrue(HasMsg(R, SN_CAPTURE_OUT_TEMP_HINT), 'el rechazo dice que se omita out: ' + R);
  // (la jaula la pone el servidor que lanza el ejecutor: aqui solo la regla)
  Assert.AreEqual('', DeadCopyWriteDenied('C:\w\proyecto\capturas\cap.png'),
    'una carpeta del proyecto no es una carpeta muerta');
end;

procedure TImageTests.BorradoSoloDentroDeLoDesechable;
begin
  Assert.AreEqual('', BorradoDenegado('C:\w\proyecto\__delphi-temp\x'), 'dentro de la temporal');
  Assert.AreEqual('', BorradoDenegado('C:\w\proyecto\__delphi-temp\hermes\desktop'),
    'el __ se exige a la RAIZ de la zona; lo de dentro se llama como sea');
  Assert.AreEqual('', BorradoDenegado('C:\w\proyecto\__delphi-patch\20260918'), 'dentro de la papelera');
  Assert.AreEqual('', BorradoDenegado('C:\w\capturas\__tmp-abcd1234'), 'una descarga temporal');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\proyecto\__delphi-temp'), SR_BORRADO_DENEGADO_FMT), 'la temporal misma, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\proyecto\__delphi-patch'), SR_BORRADO_DENEGADO_FMT), 'la papelera misma, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\proyecto\src'), SR_BORRADO_DENEGADO_FMT), 'una carpeta de proyecto, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\capturas\__tmp-zz'), SR_BORRADO_DENEGADO_FMT), 'un __tmp- que no es del nombrador, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\capturas\.tmp-abcd1234'), SR_BORRADO_DENEGADO_FMT), 'el prefijo viejo, sin __, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\delphi-temp\x'), SR_BORRADO_DENEGADO_FMT), 'una carpeta que se llama casi igual pero sin __, no');
  // la negativa PROPIA ante los metadatos git, dentro de lo desechable: P4 de
  // test_purga_repo_118 la pide por la tool y la para antes la puerta de
  // entrada, asi que esta no la media nadie (2g de la 1.18.x)
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\proyecto\__delphi-patch\20260918\repo\.git'),
    SR_GUARD_GIT_METADATA_FMT), 'el .git de un repo de la papelera, no');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\w\proyecto\__delphi-temp\repo\.git\objects'),
    SR_GUARD_GIT_METADATA_FMT), 'dentro de un .git de la temporal, no');
end;

procedure TImageTests.BorradoNuncaUnidadNiSistema;
begin
  Assert.IsTrue(EsMsg(BorradoDenegado(''), SR_BORRADO_DENEGADO_FMT), 'vacia');
  Assert.IsTrue(EsMsg(BorradoDenegado('relativo\__delphi-temp\x'), SR_BORRADO_DENEGADO_FMT), 'relativa');
  Assert.IsTrue(EsMsg(BorradoDenegado('C:\'), SR_BORRADO_DENEGADO_FMT), 'unidad');
  Assert.IsTrue(EsMsg(BorradoDenegado('\\servidor\recurso'), SR_BORRADO_DENEGADO_FMT), 'recurso compartido');
  Assert.IsTrue(EsMsg(BorradoDenegado(GetEnvironmentVariable('WINDIR')), SR_BORRADO_DENEGADO_FMT), 'Windows');
  // (en el contenedor de delphi_test el padre de esta carpeta no se deja abrir
  // y la carpeta misma si: las dos formas tienen que negar; medido el 14-oct)
  Assert.IsTrue(EsMsg(BorradoDenegado(ExtractFileDir(ParamStr(0))), SR_BORRADO_DENEGADO_FMT),
    'la carpeta del ejecutable: ' + ExtractFileDir(ParamStr(0)));
end;

procedure TImageTests.DescargaTemporalNombradorYLector;
begin
  Assert.IsTrue(EsCarpetaDescarga(ExtractFileName(NuevaCarpetaDescarga('C:\w'))), 'el lector reconoce al nombrador');
  Assert.IsFalse(EsCarpetaDescarga('__tmp-'), 'sin hex');
  Assert.IsFalse(EsCarpetaDescarga('tmp-abcd1234'), 'sin __');
  Assert.IsFalse(EsCarpetaDescarga('.tmp-abcd1234'), 'el prefijo viejo');
end;

procedure TImageTests.SinCapturaDiceElMotivo;
var
  R: string;
begin
  // Una respuesta sin captura dice POR QUE, nunca la fontaneria ("el nodo
  // no dijo donde dejo la captura", hasta la 1.5.2).
  R := MotivoSinCaptura('', SN_REMOTERUN_ENV_NONE);
  Assert.IsTrue(HasMsg(R, SN_DESKTOP_MOTIVO_SIN_SESION), 'sin sesion: ' + R);
  R := MotivoSinCaptura('  Error: Acceso denegado.', '');
  Assert.IsTrue(HasMsg(R, SN_DESKTOP_MOTIVO_DENEGADA), 'Windows bloqueado: ' + R);
  R := MotivoSinCaptura('-- 2. la pantalla'#10 +
    '  ' + NODO_NO_PUDE + ' org.freedesktop.DBus.Error.NoReply: no reply'#10,
    SN_REMOTERUN_ENV_INHERITED);
  Assert.IsTrue(R.Contains('NoReply'), 'el motivo del propio nodo: ' + R);
  // el NODO primero: el lanzador decia 'sin entorno' y tapaba lo que el nodo
  // habia mirado de verdad (revision 26-sep-2026)
  R := MotivoSinCaptura('  ' + NODO_NO_PUDE + ' no graphical session open for the operator user'#10,
    SN_REMOTERUN_ENV_NONE);
  Assert.IsTrue(R.Contains('operator user'), 'el motivo del nodo gana al del entorno: ' + R);
  R := MotivoSinCaptura('nodo listo', '');
  Assert.IsTrue(HasMsg(R, SN_DESKTOP_MOTIVO_NINGUNO), 'sin motivo: ' + R);
  Assert.IsTrue(EsMsg(R, SR_DESKTOP_SIN_CAPTURA_FMT), 'el motivo va en su mensaje: ' + R);
end;

procedure TImageTests.TamanoSaleDeLaCabecera;
var
  W, H: Integer;
  B: TArray<Byte>;
begin
  Assert.IsTrue(TamanoPngBytes(PngDe(37, 11), W, H), 'un PNG');
  Assert.AreEqual(37, W);
  Assert.AreEqual(11, H);
  Assert.IsFalse(TamanoPngBytes(TEncoding.ASCII.GetBytes('esto no es un png, aunque mida mas de 24'), W, H),
    'sin la firma no es un PNG');
  Assert.AreEqual(0, W, 'lo que no es un PNG no mide nada');
  B := Copy(PngDe(37, 11), 0, 23);
  Assert.IsFalse(TamanoPngBytes(B, W, H), 'una cabecera cortada (23 bytes) no se lee fuera de su sitio');
  Assert.IsFalse(TamanoPngBytes(nil, W, H), 'nada no es un PNG');
end;

procedure TImageTests.CabeceraPngLectorInversoDelEscritor;
var
  B, D: TArray<Byte>;
  W, H: Integer;
begin
  // lo que escribe el nodo (Mld.Captura): la firma y un trozo IHDR con
  // DatosIhdr - su longitud, su tipo y sus datos; el CRC no lo mira el lector
  D := DatosIhdr(3440, 1440);
  SetLength(B, Length(FIRMA_PNG));
  Move(FIRMA_PNG[0], B[0], Length(FIRMA_PNG));
  B := B + [0, 0, 0, Byte(Length(D))] + TEncoding.ASCII.GetBytes(TROZO_IHDR) + D + [0, 0, 0, 0];
  Assert.IsTrue(TamanoPngBytes(B, W, H), 'el lector lee lo que compone el escritor');
  Assert.AreEqual(3440, W);
  Assert.AreEqual(1440, H);
  Assert.AreEqual(13, Integer(Length(D)), 'los datos del IHDR son 13 bytes');
  // otro trozo en el sitio del IHDR no es una cabecera
  B[12] := Ord('X');
  Assert.IsFalse(TamanoPngBytes(B, W, H), 'sin IHDR en su sitio no es un PNG');
  Assert.AreEqual(0, W);
end;

procedure TImageTests.EscritorDelNodoLoLeeElDecodificador;
var
  Pix: TArray<Byte>;
  F: string;
  Png: TPngImage;
  W, H: Integer;
begin
  // 3 x 2 en BGRA de 32 bits, como el DIB que captura el nodo: azul en (0,0)
  // y rojo en (2,1). El juez es el decodificador de la RTL, que comprueba los
  // CRC al cargar: la firma y el IHDR salen de Lsp.Png desde el 11-oct-2026
  SetLength(Pix, 3 * 2 * 4);
  FillChar(Pix[0], Length(Pix), 0);
  Pix[0] := 255;
  Pix[(1 * 3 + 2) * 4 + 2] := 255;
  F := TPath.Combine(ExtractFilePath(ParamStr(0)), 'nodo-escritor-prueba.png');
  try
    Assert.IsTrue(GuardarPNG(F, @Pix[0], 3, 2, 3 * 4, 32), 'el escritor del nodo');
    Assert.IsTrue(TamanoPngBytes(TFile.ReadAllBytes(F), W, H), 'el lector de la casa lo lee');
    Assert.AreEqual(3, W);
    Assert.AreEqual(2, H);
    Png := TPngImage.Create;
    try
      Png.LoadFromFile(F);
      Assert.AreEqual(3, Png.Width);
      Assert.AreEqual(2, Png.Height);
      Assert.AreEqual(Integer(clBlue), Integer(Png.Pixels[0, 0]), 'azul en (0,0)');
      Assert.AreEqual(Integer(clRed), Integer(Png.Pixels[2, 1]), 'rojo en (2,1)');
      Assert.AreEqual(Integer(clBlack), Integer(Png.Pixels[1, 0]), 'negro en (1,0)');
    finally
      Png.Free;
    end;
  finally
    System.SysUtils.DeleteFile(F);
  end;
end;

procedure TImageTests.RecorteEnMemoriaSeAjustaAlLienzo;
var
  X, Y, W, H, AO, HO, SW, SH: Integer;
  Sal: TArray<Byte>;
begin
  // se sale por la derecha y por abajo: se recorta el recorte
  X := 90;
  Y := 40;
  W := 30;
  H := 30;
  Assert.AreEqual('', RecortaPngBytes(PngDe(100, 50), X, Y, W, H, AO, HO, Sal));
  Assert.AreEqual(10, W, 'ancho ajustado al lienzo');
  Assert.AreEqual(10, H, 'alto ajustado al lienzo');
  Assert.AreEqual(100, AO);
  Assert.AreEqual(50, HO);
  Assert.IsTrue(TamanoPngBytes(Sal, SW, SH), 'la salida es un PNG');
  Assert.AreEqual(10, SW);
  Assert.AreEqual(10, SH);
  // y por la izquierda: el origen pasa a 0 y el ancho pierde lo de fuera
  X := -5;
  Y := 0;
  W := 20;
  H := 5;
  Assert.AreEqual('', RecortaPngBytes(PngDe(100, 50), X, Y, W, H, AO, HO, Sal));
  Assert.AreEqual(0, X);
  Assert.AreEqual(15, W);
  // entero fuera de la imagen: el motivo, y ninguna salida
  X := 200;
  Y := 0;
  W := 10;
  H := 10;
  Assert.IsTrue(HasMsg(RecortaPngBytes(PngDe(100, 50), X, Y, W, H, AO, HO, Sal),
    SN_CAPT_RECORTE_FUERA_CAPTURA_FMT), 'fuera de la captura');
  Assert.AreEqual(0, Integer(Length(Sal)), 'un recorte que no se hizo no deja bytes');
  // lo que no es un PNG: el motivo, y ninguna salida
  X := 0;
  Y := 0;
  W := 10;
  H := 10;
  Assert.IsTrue(HasMsg(RecortaPngBytes(TEncoding.ASCII.GetBytes('no es un png'), X, Y, W, H, AO, HO, Sal),
    SN_CAPT_NO_PUDE_RECORTAR_FMT), 'no es un PNG');
  Assert.AreEqual(0, Integer(Length(Sal)), 'un recorte que fallo no deja bytes');
end;

procedure TImageTests.CasaDeEntregablesReconoceASuNombrador;
begin
  // el lector reconoce lo que compone el nombrador (AgentTempDir); una carpeta
  // cualquiera no. La casa es NUESTRA: en la temporal del servidor, nunca en
  // un workspace (1.18.2, 2af), y el resto de esa temporal (el mensaje de un
  // commit, un contenedor de test) no es una captura que se entregue. Los
  // enlaces y los workspaces los mide test_captura_puertas_1182 (S3, E1-E4)
  Assert.IsTrue(EnCasaDeEntregables(AgentTempDir(CAPTURE_SUB_DESIGNER) + '\designer-x.png'),
    'lo que compone el nombrador');
  Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(ServerTempDir('')), AgentTempDir(CAPTURE_SUB_DESIGNER)),
    'la casa, en la temporal del servidor: ' + AgentTempDir(CAPTURE_SUB_DESIGNER));
  Assert.IsFalse(EnCasaDeEntregables(ServerTempDir('git') + '\designer\designer-x.png'),
    'el resto de la temporal del servidor no es la casa de capturas');
  Assert.IsFalse(EnCasaDeEntregables('C:\w\capturas\designer\designer-x.png'), 'una carpeta cualquiera');
end;

procedure TImageTests.ColocarEnLaCasaLoJuzgaSuNombrador;
var
  Dentro, Fuera, Motivo: string;
begin
  // con ltEntregables, Coloca pregunta la puerta de la casa (EscribeBytes) y
  // no la de la jaula (1.18.2, 2i): lo que compone el nombrador se coloca; una
  // ruta de la raiz del ejecutor fuera de su casa, que la jaula SI admitiria,
  // se niega antes de crear nada. La segunda barrera: por la tool, CaptureTarget
  // ya niega antes (CAPT-010) y esto no se ve
  Dentro := AgentTempDir(CAPTURE_SUB_DESKTOP) + '\desktop-dunit-casa.png';
  ColocaContenido(Dentro, PngDe(4, 4), ltEntregables);
  try
    Assert.IsTrue(TFile.Exists(Dentro), 'en la casa se coloca');
  finally
    TFile.Delete(Dentro);
  end;
  Fuera := ExtractFilePath(ParamStr(0)) + 'fuera-de-la-casa-dunit\x.png';
  Motivo := '';
  try
    ColocaContenido(Fuera, PngDe(4, 4), ltEntregables);
  except
    on E: Exception do
      Motivo := E.Message;
  end;
  Assert.IsTrue(HasMsg(Motivo, SR_GUARD_FUERA_DE_LUGARES_FMT), 'fuera de la casa: ' + Motivo);
  Assert.IsFalse(TDirectory.Exists(ExtractFileDir(Fuera)), 'y sin crear su carpeta');
end;

procedure TImageTests.CapturaSinSalidaSeConsumeYLoDice;
var
  F: string;
  Ret: TJSONObject;
begin
  // 2ai de la 1.18.2: sin la ruta /files (stdio; el ejecutor de pruebas no la
  // sirve) una captura NUESTRA con inline=false no tiene por donde salir. Las
  // que se piden asi se niegan antes de capturar; la que llega a
  // DeliverCapture (la de un gesto, que ya se hizo) se consume - no se queda
  // en nuestra casa sin nadie que la recoja - y se dice (CAPT-011)
  F := AgentTempDir(CAPTURE_SUB_DESKTOP) + '\desktop-dunit-sinsalida.png';
  ColocaContenido(F, PngDe(4, 4), ltEntregables);
  Ret := TJSONObject.Create;
  try
    DeliverCapture('delphi_desktop', F, False, 0, 0, 0, 1, 1, Ret);
    Assert.IsFalse(TFile.Exists(F), 'consumida: no se queda en nuestra casa');
    Assert.IsTrue(Ret.GetValue<Boolean>('consumed', False), 'y la respuesta lo dice (consumed)');
    Assert.IsTrue(HasMsg(Ret.GetValue<string>('downloadNote', ''), SN_CAPTURE_SIN_ENLACE),
      'con CAPT-011: ' + Ret.ToJSON);
    Assert.IsNull(Ret.GetValue('download'), 'sin enlace');
    Assert.IsNull(Ret.GetValue('frame'), 'ni frame: no queda imagen que medir (revisor del 2ai)');
  finally
    Ret.Free;
    if TFile.Exists(F) then
      TFile.Delete(F);
  end;
  // ...y la regla que la niega ANTES de capturar, la misma para las tres tools
  Assert.IsTrue(HasMsg(CapturaSinSalidaDenegada(False, ''), SR_CAPTURE_SIN_SALIDA),
    'inline=false sin out= y sin enlace: CAPT-012');
  Assert.AreEqual('', CapturaSinSalidaDenegada(True, ''), 'en linea sale por la respuesta');
  Assert.AreEqual('', CapturaSinSalidaDenegada(False, 'C:\x\y.png'), 'con out= es un fichero suyo');
end;

const
  // Salidas REALES del nodo Linux (el Zorin, 16-oct-2026), tal como las guardo
  // Hermes: un tap, y el arranque de un status con su uso de consola
  CAPTURA_ZORIN = 'CAPTURE=/home/dfontanet/PAServer-132/scratch-dir/dfontanet-zorin/McpDesktopNode/captura.png';
  ARRANQUE_ZORIN =
    '[NODE-026] McpDesktop - Linux desktop control node'#10#10 +
    '[NODE-027] -- 1. system libraries (nothing to install) --'#10 +
    '  [NODE-020] libdbus-1.so.3   open, symbols 6/6'#10 +
    '  [NODE-020] libei.so.1       open, symbols 6/6'#10 +
    '  cgroup: 0::/user.slice/user-1000.slice/user@1000.service/app.slice/paserver-132.service'#10#10 +
    '[NODE-029] -- 2. the screen: scale and screenshot --'#10 +
    '  [NODE-030] The desktop says its scale is 1,25'#10 +
    CAPTURA_ZORIN + #10 +
    '  1 visible windows:'#10 +
    '  [NODE-024] (X11/Xwayland windows: native Wayland windows do not appear in the list)'#10 +
    '  WINDOW 0 0 3440 1390 Galatea'#10#10 +
    '[NODE-032] -- 3. the hands --'#10 +
    '  [NODE-036] ready. logical screen 2752x1152, scale 1,25'#10;
  DESPUES_ZORIN =
    CAPTURA_ZORIN + #10 +
    '  1 visible windows:'#10 +
    '  [NODE-024] (X11/Xwayland windows: native Wayland windows do not appear in the list)'#10 +
    '  WINDOW 0 0 3440 1390 Galatea'#10#10 +
    '[NODE-017] node ready';

procedure TImageTests.GestoBienDejaSoloLaAccion;
var
  Tap, Escrito: string;
begin
  Tap := ARRANQUE_ZORIN + '  [NODE-014] CLICK at pixel (2733,239) of the screenshot'#10 + DESPUES_ZORIN;
  Assert.AreEqual('[NODE-014] CLICK at pixel (2733,239) of the screenshot', SalidaParaElAgente(Tap, True),
    'de un tap que salio queda la accion y nada mas');
  Escrito := '  [NODE-039] WRITTEN "tiquet" at pixel (3104,137)  [keyboard: the desktop''s own (Spanish, ' +
    '159 characters)] (typed; the focus is NOT verified: check it on the screenshot)';
  Assert.AreEqual(Escrito.Trim, SalidaParaElAgente(ARRANQUE_ZORIN + Escrito + #10 + DESPUES_ZORIN, True),
    'el aviso de que el foco no se comprueba va con la accion');
  // una captura que salio no tiene nada que decir: sin nodeOutput
  Assert.AreEqual('', SalidaParaElAgente(ARRANQUE_ZORIN + DESPUES_ZORIN, True));
  // y la salida en CRLF (un nodo Windows) se lee igual
  Assert.AreEqual('[NODE-014] CLICK at pixel (2733,239) of the screenshot',
    SalidaParaElAgente(Tap.Replace(#10, #13#10), True));
end;

procedure TImageTests.GestoConAvisoLoConserva;
var
  R: string;
begin
  // el canal de entrada no llego a estar listo: sale con captura y SIN error
  // (no lleva etiqueta de fallo), y es justo lo que dice que el gesto puede no
  // haberse hecho: se queda
  R := SalidaParaElAgente(ARRANQUE_ZORIN + '  [NODE-035] The channel never became ready: timeout'#10 +
    DESPUES_ZORIN, True);
  Assert.IsTrue(R.Contains('[NODE-035]'), 'el aviso se queda: ' + R);
  Assert.IsFalse(R.Contains('NODE-026') or R.Contains('cgroup') or R.Contains('CAPTURE='), 'el arranque no: ' + R);
end;

procedure TImageTests.StatusYFalloSonDiagnosticoSinProtocoloNiUso;
var
  Status, R: string;
begin
  Status := ARRANQUE_ZORIN +
    '  [NODE-041] usage: <x> <y>   click that pixel of the screenshot'#10 +
    '                  altab     switch window with the keyboard'#10 +
    '                  tecla <n> press a key (evdev: Escape 1, Enter 28)'#10 +
    '                  texto <t> type that text wherever the focus is'#10 +
    '                  escribe <x> <y> <t>  click there AND type: a single trip'#10 +
    '                  ventanas  show ALL the windows (Super key),'#10 +
    '                            for when they cover each other'#10 +
    '  (to give a window the focus, click its title bar)'#10#10 +
    '[NODE-017] node ready';
  R := SalidaParaElAgente(Status, False);
  Assert.IsTrue(R.Contains('[NODE-026]') and R.Contains('cgroup') and R.Contains('[NODE-036]') and
    R.Contains('[NODE-017]'), 'status es el diagnostico: el arranque se queda: ' + R);
  Assert.IsFalse(R.Contains('CAPTURE=') or R.Contains('/home/'), 'nunca la ruta nuestra del destino: ' + R);
  Assert.IsFalse(R.Contains('WINDOW ') or R.Contains('visible windows:'), 'ni el protocolo de ventanas: ' + R);
  Assert.IsFalse(R.Contains('usage') or R.Contains('tecla') or R.Contains('escribe') or R.Contains('title bar'),
    'ni el uso de consola con sus lineas: ' + R);
  // un fallo: va el diagnostico con el motivo del nodo
  R := SalidaParaElAgente('[NODE-026] McpDesktop - Linux desktop control node'#10 +
    '  ' + NODO_NO_PUDE + ' no graphical session open for the operator user'#10 + '[NODE-017] node ready', False);
  Assert.IsTrue(R.Contains(NODO_NO_PUDE) and R.Contains('[NODE-026]'), 'el fallo lleva su motivo: ' + R);
end;

procedure TImageTests.NodoWindowsGestoBienDejaSoloLaAccion;
var
  Salida, Clic: string;
begin
  // el arranque del nodo Windows compuesto con SU catalogo: si el nodo cambia
  // un texto, esta prueba lo sigue
  Clic := Format(Mld.Textos.SK_NODE_CLIC_EN_PIXEL_FMT, [10, 20]);
  Salida := Mld.Textos.SN_NODE_CONTROL_ESCRITORIO_WINDOWS + #13#10 +
    'Windows 11 (Version 24H2, OS Build 26100.4351, 64-bit Edition)'#13#10 +
    Format(Mld.Textos.SN_NODE_ESCRITORIO_PIXELES_ESCALA_FMT, [1920, 1080, '1.00']) + #13#10 +
    Format(Mld.Textos.SF_NODE_ESTADO_FMT, ['active']) + #13#10 +
    Clic + #13#10 +
    'CAPTURE=C:\Users\op\PAServer\scratch-dir\op-win\McpDesktopNode\captura.png'#13#10 +
    '  1 visible windows:'#13#10 +
    '  WINDOW 0 0 800 600 Proyecto1'#13#10 +
    Mld.Textos.SN_NODE_NODO_LISTO;
  Assert.AreEqual(Clic.Trim, SalidaParaElAgente(Salida, True), 'Windows: la accion y nada mas');
end;

procedure TImageTests.EnLineaLoQueCabeSaleTalCual;
var
  Ent, Sal: TArray<Byte>;
  Mime: string;
begin
  Ent := PngDe(500, 40);
  Assert.AreEqual('', CabeEnLineaBytes(Ent, INLINE_MAX_BYTES, Sal, Mime));
  Assert.AreEqual('image/png', Mime);
  Assert.IsTrue(Iguales(Sal, Ent), 'lo que cabe sale tal cual, sin perder nada');
end;

procedure TImageTests.EnLineaLoQueNoCabePasaAJpegDelMismoTamano;
var
  Ent, Sal: TArray<Byte>;
  Mime: string;
  W, H: Integer;
begin
  Ent := PngRuidoso(400, 300);
  // la premisa, medida: si el PNG cupiera, esto pasaria sin probar nada
  Assert.IsTrue(Length(Ent) > 60000, 'el PNG de prueba tiene que pasarse del tope: ' + IntToStr(Length(Ent)));
  Assert.AreEqual('', CabeEnLineaBytes(Ent, 60000, Sal, Mime));
  Assert.AreEqual('image/jpeg', Mime);
  Assert.IsTrue((Length(Sal) > 0) and (Length(Sal) <= 60000), 'cabe: ' + IntToStr(Length(Sal)));
  TamanoJpeg(Sal, W, H);
  Assert.AreEqual(400, W, 'el MISMO ancho: el frame no cambia');
  Assert.AreEqual(300, H, 'el MISMO alto');
end;

procedure TImageTests.EnLineaLoQueNiAsiCabeLoDice;
var
  Sal: TArray<Byte>;
  Mime: string;
begin
  Assert.IsTrue(HasMsg(CabeEnLineaBytes(PngRuidoso(400, 300), 100, Sal, Mime), SN_CAPT_NO_CABE_EN_LINEA_FMT),
    'ni en JPEG cabe: lo dice (CAPT-014)');
  Assert.AreEqual(0, Integer(Length(Sal)), 'y no entrega nada a medias');
end;

procedure TImageTests.EntregaEnLineaGrandeCabeConElMismoFrame;
var
  F: string;
  Png, Dec: TArray<Byte>;
  Ret: TJSONObject;
  Arr: TJSONArray;
  W, H, X, Y: Integer;
begin
  // el caso del Zorin por la entrega de verdad: una captura nuestra que en PNG
  // no cabe en una respuesta llega en JPEG, del MISMO tamano, con el MISMO
  // frame, y un toque medido sobre ella cae donde caia
  Png := PngRuidoso(1200, 700);
  Assert.IsTrue(Length(Png) > INLINE_MAX_BYTES, 'la premisa: el PNG no cabe: ' + IntToStr(Length(Png)));
  F := AgentTempDir(CAPTURE_SUB_DESKTOP) + '\desktop-dunit-grande.png';
  ColocaContenido(F, Png, ltEntregables);
  ClearAttachedImages;
  Ret := TJSONObject.Create;
  try
    Assert.IsTrue(DeliverCapture('delphi_desktop', F, True, 0, 0, 0, 1, 1, Ret), 'viajo en linea: ' + Ret.ToJSON);
    Assert.AreEqual(1200, Ret.GetValue<Integer>('inlineWidth'));
    Assert.AreEqual(700, Ret.GetValue<Integer>('inlineHeight'));
    Assert.AreEqual('1200x700@1200x700+0+0', Ret.GetValue<string>('frame'), 'el frame de siempre');
    Assert.IsTrue(Ret.GetValue<Integer>('inlineBytes') <= INLINE_MAX_BYTES, 'cabe: ' + Ret.ToJSON);
    Assert.AreEqual('', FramePoint(Ret.GetValue<string>('frame'), '600', '350', X, Y));
    Assert.AreEqual(600, X, 'un toque cae donde caia');
    Assert.AreEqual(350, Y);
    Arr := WrapWithAttachedImages('x');
    try
      Assert.IsNotNull(Arr, 'la imagen va adjunta');
      Assert.AreEqual('image/jpeg', (Arr.Items[1] as TJSONObject).GetValue<string>('mimeType'));
      Assert.AreEqual('', Base64ToBytes((Arr.Items[1] as TJSONObject).GetValue<string>('data'), 'data', Dec));
      TamanoJpeg(Dec, W, H);
      Assert.AreEqual(1200, W);
      Assert.AreEqual(700, H);
    finally
      Arr.Free;
    end;
  finally
    Ret.Free;
    ClearAttachedImages;
    if TFile.Exists(F) then
      TFile.Delete(F);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TImageTests);

end.
