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

{ Ancho y alto de un PNG por su cabecera IHDR (los 24 primeros bytes): sin
  decodificar la imagen, que para saber su tamano sobra. False si no es un
  PNG. }
function TamanoPngBytes(const ABytes: TArray<Byte>; out W, H: Integer): Boolean;

{ Escala un PNG EN MEMORIA a un ancho maximo (proporcion intacta, HALFTONE)
  sin tocar ningun fichero: una captura pedida con out= es del agente y no
  se modifica. La de un escritorio de 3440 puntos pesa 5 MB y en base64
  casi 7: no cabe en la respuesta de una tool para un modelo pequeno.
  AEscala sale con el factor aplicado (1.0 = ya cabia, ASalida = AEntrada)
  y AW/AH con el tamano final. '' si todo fue bien; el motivo si no. }
function EscalaPngBytes(const AEntrada: TArray<Byte>; AMaxAncho: Integer;
  out ASalida: TArray<Byte>; out AEscala: Double; out AW, AH: Integer): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  // SetStretchBltMode(HALFTONE): escalar sin dientes de sierra
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Lsp.Texts;

function TamanoPngBytes(const ABytes: TArray<Byte>; out W, H: Integer): Boolean;
const
  FIRMA: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
var
  I: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  if Length(ABytes) < 24 then
    Exit;
  for I := 0 to 7 do
    if ABytes[I] <> FIRMA[I] then
      Exit;
  { bytes 16..23: ancho y alto, big-endian, dentro del trozo IHDR }
  W := (ABytes[16] shl 24) or (ABytes[17] shl 16) or (ABytes[18] shl 8) or ABytes[19];
  H := (ABytes[20] shl 24) or (ABytes[21] shl 16) or (ABytes[22] shl 8) or ABytes[23];
  Result := (W > 0) and (H > 0);
end;

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

end.
