unit Lsp.Imagen;

{ Recorte de una captura PNG EN EL SERVIDOR.

  La captura del escritorio entero sigue siendo la verdad (una sola imagen,
  un solo espacio de coordenadas), pero un dialogo pequeno en una pantalla de
  3440 puntos llega ilegible a un agente: la API reduce toda imagen a un tope
  fijo de megapixeles, asi que lo que se pierde no son tokens sino nitidez.
  El recorte es una VISTA de ese mismo fotograma: se hace aqui, sobre la
  imagen que ya bajo, con un solo trozo de codigo para todos los destinos, y
  el que llama recibe el origen del recorte para seguir pulsando en
  coordenadas del escritorio. Decision de David, 22-sep-2026. }

interface

{ Recorta el PNG en sitio. X, Y, W, H entran en coordenadas de la imagen y
  salen AJUSTADOS al lienzo (un recorte que se sale se recorta el). Devuelve
  '' si todo fue bien, y el motivo si no; AAnchoOrig/AAltoOrig dicen de que
  tamano era la captura entera. }
function RecortaPng(const AFichero: string; var X, Y, W, H: Integer;
  out AAnchoOrig, AAltoOrig: Integer): string;

{ Ancho y alto de un PNG leyendo solo su cabecera IHDR (los 24 primeros
  bytes): sin decodificar la imagen, que para saber su tamano sobra. False
  si el fichero no es un PNG. }
function TamanoPng(const AFichero: string; out W, H: Integer): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Imaging.pngimage;

function TamanoPng(const AFichero: string; out W, H: Integer): Boolean;
const
  FIRMA: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
var
  F: TFileStream;
  Cab: array[0..23] of Byte;
  I: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  try
    F := TFileStream.Create(AFichero, fmOpenRead or fmShareDenyWrite);
    try
      if F.Read(Cab, SizeOf(Cab)) <> SizeOf(Cab) then
        Exit;
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  for I := 0 to 7 do
    if Cab[I] <> FIRMA[I] then
      Exit;
  { bytes 16..23: ancho y alto, big-endian, dentro del trozo IHDR }
  W := (Cab[16] shl 24) or (Cab[17] shl 16) or (Cab[18] shl 8) or Cab[19];
  H := (Cab[20] shl 24) or (Cab[21] shl 16) or (Cab[22] shl 8) or Cab[23];
  Result := (W > 0) and (H > 0);
end;

function RecortaPng(const AFichero: string; var X, Y, W, H: Integer;
  out AAnchoOrig, AAltoOrig: Integer): string;
var
  Png, Nuevo: TPngImage;
  Entera, Trozo: TBitmap;
begin
  Result := '';
  AAnchoOrig := 0;
  AAltoOrig := 0;
  try
    Png := TPngImage.Create;
    try
      Png.LoadFromFile(AFichero);
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
        Exit(Format('el recorte cae fuera de la captura (%dx%d)',
          [Png.Width, Png.Height]));
      Entera := TBitmap.Create;
      Trozo := TBitmap.Create;
      Nuevo := TPngImage.Create;
      try
        Entera.Assign(Png);
        Trozo.PixelFormat := pf24bit;
        Trozo.SetSize(W, H);
        Trozo.Canvas.CopyRect(Rect(0, 0, W, H), Entera.Canvas,
          Rect(X, Y, X + W, Y + H));
        Nuevo.Assign(Trozo);
        Nuevo.CompressionLevel := 6; // el recorte pesaba mas que la captura entera
        Nuevo.SaveToFile(AFichero);
      finally
        Nuevo.Free;
        Trozo.Free;
        Entera.Free;
      end;
    finally
      Png.Free;
    end;
  except
    on E: Exception do
      Result := 'no pude recortar la captura: ' + E.Message;
  end;
end;

end.
