unit Lsp.Imagen;

{ Recorte de una captura PNG EN EL SERVIDOR.

  La captura del escritorio entero sigue siendo la verdad (una sola imagen,
  un solo espacio de coordenadas), pero un dialogo pequeno en una pantalla de
  3440 puntos llega ilegible a un agente: la API reduce toda imagen a un tope
  fijo de megapixeles, asi que lo que se pierde no son tokens sino nitidez.
  El recorte es una VISTA de ese mismo fotograma: se hace aqui, sobre la
  imagen que ya bajo, con un solo trozo de codigo para todos los destinos, y
  el que llama recibe el origen del recorte para seguir pulsando en
  coordenadas del escritorio. Decision de David, 22-sep-2026.

  Todo EN MEMORIA: aqui no se abre ningun fichero. Los bytes los lee y los
  escribe quien llama, por las puertas de Lsp.Patch (LeeBytes, EscribeBytes,
  ColocaContenido) - el recorte se releia y se reescribia en sitio sin
  ninguna (1.18.2, punto 2b). }

interface

{ Recorta un PNG: X, Y, W, H entran en coordenadas de la imagen y salen
  AJUSTADOS al lienzo (un recorte que se sale se recorta el); ASalida, el PNG
  del recorte. Devuelve '' si todo fue bien, y el motivo si no (ASalida
  vacia); AAnchoOrig/AAltoOrig dicen de que tamano era la captura entera. }
function RecortaPngBytes(const AEntrada: TArray<Byte>; var X, Y, W, H: Integer;
  out AAnchoOrig, AAltoOrig: Integer; out ASalida: TArray<Byte>): string;

{ (El tamano de un PNG por su cabecera es de Lsp.Png, TamanoPngBytes: el
  mismo lector para el servidor y el nodo.) }

{ Escala un PNG EN MEMORIA a un ancho maximo (proporcion intacta, HALFTONE)
  sin tocar ningun fichero: una captura pedida con out= es del agente y no
  se modifica. La de un escritorio de 3440 puntos pesa 5 MB y en base64
  casi 7: no cabe en la respuesta de una tool para un modelo pequeno.
  AEscala sale con el factor aplicado (1.0 = ya cabia, ASalida = AEntrada)
  y AW/AH con el tamano final. '' si todo fue bien; el motivo si no. }
function EscalaPngBytes(const AEntrada: TArray<Byte>; AMaxAncho: Integer;
  out ASalida: TArray<Byte>; out AEscala: Double; out AW, AH: Integer): string;

{ Que una imagen en linea quepa en UNA respuesta: un cliente lee cada evento
  entero de una vez y alguno le pone tope (medido el 16-oct-2026: el cliente
  MCP de Python 2.x lee con httpx2, 1 MiB por evento SSE; la captura del
  Zorin a 1280 en PNG pesaba 972 KB, en base64 1,3 MB, y llegaba "SSE stream
  ended without a response"). Si el PNG cabe en AMaxBytes sale tal cual; si
  no, la MISMA imagen -mismo ancho y alto: el frame y los toques no cambian-
  en JPEG, bajando la calidad de 85 a 55. Un modelo cobra la imagen por
  pixeles, no por bytes: esto no ahorra tokens, la hace llegar. '' si cabe
  (AMime, su tipo); el motivo si ni asi (ASalida vacia). }
function CabeEnLineaBytes(const APng: TArray<Byte>; AMaxBytes: Integer;
  out ASalida: TArray<Byte>; out AMime: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  // SetStretchBltMode(HALFTONE): escalar sin dientes de sierra
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.Imaging.jpeg, // CabeEnLineaBytes: la misma imagen en JPEG
  Lsp.Texts;

function RecortaPngBytes(const AEntrada: TArray<Byte>; var X, Y, W, H: Integer;
  out AAnchoOrig, AAltoOrig: Integer; out ASalida: TArray<Byte>): string;
var
  Png, Nuevo: TPngImage;
  Entera, Trozo: TBitmap;
  Ent, Sal: TBytesStream;
begin
  Result := '';
  AAnchoOrig := 0;
  AAltoOrig := 0;
  ASalida := nil;
  try
    Ent := TBytesStream.Create(AEntrada);
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(Ent);
      AAnchoOrig := Png.Width;
      AAltoOrig := Png.Height;
      // al lienzo: lo que se sale por un lado se pierde, no se inventa
      if X < 0 then
      begin
        Inc(W, X);
        X := 0;
      end;
      if Y < 0 then
      begin
        Inc(H, Y);
        Y := 0;
      end;
      if X + W > Png.Width then
        W := Png.Width - X;
      if Y + H > Png.Height then
        H := Png.Height - Y;
      if (W <= 0) or (H <= 0) then
        Exit(MsgFmt(SN_CAPT_RECORTE_FUERA_CAPTURA_FMT,
          [Png.Width, Png.Height]));
      Entera := TBitmap.Create;
      Trozo := TBitmap.Create;
      Nuevo := TPngImage.Create;
      Sal := TBytesStream.Create;
      try
        Entera.Assign(Png);
        Trozo.PixelFormat := pf24bit;
        Trozo.SetSize(W, H);
        Trozo.Canvas.CopyRect(Rect(0, 0, W, H), Entera.Canvas,
          Rect(X, Y, X + W, Y + H));
        Nuevo.Assign(Trozo);
        Nuevo.CompressionLevel := 6; // el recorte pesaba mas que la captura entera
        Nuevo.SaveToStream(Sal);
        ASalida := Copy(Sal.Bytes, 0, Sal.Size);
      finally
        Sal.Free;
        Nuevo.Free;
        Trozo.Free;
        Entera.Free;
      end;
    finally
      Png.Free;
      Ent.Free;
    end;
  except
    on E: Exception do
    begin
      ASalida := nil;
      Result := MsgFmt(SN_CAPT_NO_PUDE_RECORTAR_FMT, [E.Message]);
    end;
  end;
end;

function EscalaPngBytes(const AEntrada: TArray<Byte>; AMaxAncho: Integer;
  out ASalida: TArray<Byte>; out AEscala: Double; out AW, AH: Integer): string;
var
  Png, Nuevo: TPngImage;
  Entera, Chica: TBitmap;
  Ent, Sal: TBytesStream;
begin
  Result := '';
  ASalida := AEntrada;
  AEscala := 1.0;
  AW := 0;
  AH := 0;
  try
    Ent := TBytesStream.Create(AEntrada);
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(Ent);
      AW := Png.Width;
      AH := Png.Height;
      if (AMaxAncho <= 0) or (Png.Width <= AMaxAncho) then
        Exit; // ya cabe: sale tal cual
      AEscala := AMaxAncho / Png.Width;
      AW := AMaxAncho;
      AH := Round(Png.Height * AEscala);
      if AH < 1 then
        AH := 1;
      Entera := TBitmap.Create;
      Chica := TBitmap.Create;
      Nuevo := TPngImage.Create;
      Sal := TBytesStream.Create;
      try
        Entera.Assign(Png);
        Chica.PixelFormat := pf24bit;
        Chica.SetSize(AW, AH);
        SetStretchBltMode(Chica.Canvas.Handle, HALFTONE);
        Chica.Canvas.StretchDraw(Rect(0, 0, AW, AH), Entera);
        Nuevo.Assign(Chica);
        Nuevo.CompressionLevel := 6;
        Nuevo.SaveToStream(Sal);
        ASalida := Copy(Sal.Bytes, 0, Sal.Size);
      finally
        Sal.Free;
        Nuevo.Free;
        Chica.Free;
        Entera.Free;
      end;
    finally
      Png.Free;
      Ent.Free;
    end;
  except
    on E: Exception do
    begin
      ASalida := nil;
      Result := MsgFmt(SN_CAPT_NO_PUDE_ESCALAR_FMT, [E.Message]);
    end;
  end;
end;

function CabeEnLineaBytes(const APng: TArray<Byte>; AMaxBytes: Integer;
  out ASalida: TArray<Byte>; out AMime: string): string;
const
  CALIDADES: array[0..2] of Integer = (85, 70, 55);
var
  Png: TPngImage;
  Bmp: TBitmap;
  Jpg: TJPEGImage;
  Ent, Sal: TBytesStream;
begin
  Result := '';
  ASalida := APng;
  AMime := 'image/png';
  if Length(APng) <= AMaxBytes then
    Exit; // cabe: sale tal cual, sin perder nada
  try
    Ent := TBytesStream.Create(APng);
    Png := TPngImage.Create;
    Bmp := TBitmap.Create;
    try
      Png.LoadFromStream(Ent);
      Bmp.Assign(Png);
      Bmp.PixelFormat := pf24bit; // un JPEG no lleva alfa; una captura no la usa
      for var Calidad in CALIDADES do
      begin
        Jpg := TJPEGImage.Create;
        Sal := TBytesStream.Create;
        try
          Jpg.Assign(Bmp);
          Jpg.CompressionQuality := Calidad;
          Jpg.Compress;
          Jpg.SaveToStream(Sal);
          if Sal.Size <= AMaxBytes then
          begin
            ASalida := Copy(Sal.Bytes, 0, Sal.Size);
            AMime := 'image/jpeg';
            Exit;
          end;
        finally
          Sal.Free;
          Jpg.Free;
        end;
      end;
    finally
      Bmp.Free;
      Png.Free;
      Ent.Free;
    end;
    ASalida := nil;
    Result := MsgFmt(SN_CAPT_NO_CABE_EN_LINEA_FMT, [Length(APng), AMaxBytes]);
  except
    on E: Exception do
    begin
      ASalida := nil;
      Result := MsgFmt(SN_CAPT_NO_PUDE_RECODIFICAR_FMT, [E.Message]);
    end;
  end;
end;

end.
