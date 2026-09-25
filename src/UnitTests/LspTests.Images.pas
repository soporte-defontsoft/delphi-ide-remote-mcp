unit LspTests.Images;

{ Captura en UN SOLO PASO (25-sep-2026): el escalado en memoria, el adjunto
  que viaja como item image y se lleva una sola vez, y el reconocedor de
  capturas del agente con sus dos subcarpetas (desktop y android). }

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.JSON,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Lsp.Imagen,
  Lsp.InlineImages,
  Lsp.Base64,
  Lsp.Guard;

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
  Assert.StartsWith('RECHAZADO', FramePoint('1280x536', '1', '1', X, Y));
  Assert.StartsWith('RECHAZADO', FramePoint('0x536@3440x1440+0+0', '1', '1', X, Y));
  Assert.StartsWith('RECHAZADO', FramePoint('1280x536@3440x1440+0+0', '1280', '10', X, Y));
  Assert.StartsWith('RECHAZADO', FramePoint('1280x536@3440x1440+0+0', '-1', '10', X, Y));
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
  Assert.StartsWith('RECHAZADO', R, 'una captura con out= en __delphi-temp se acumula');
  Assert.Contains(R, 'omitelo', 'el rechazo dice que se omita out');
  // (la jaula la pone el servidor que lanza el ejecutor: aqui solo la regla)
  Assert.AreEqual('', DeadCopyWriteDenied('C:\w\proyecto\capturas\cap.png'),
    'una carpeta del proyecto no es una carpeta muerta');
end;

initialization
  TDUnitX.RegisterTestFixture(TImageTests);

end.
