unit Lsp.Png;

{ EL FORMATO de la cabecera de un PNG: la firma y los datos del trozo IHDR,
  con su escritor (DatosIhdr, lo que el nodo escribe) y su lector
  (TamanoPngBytes), uno inverso del otro. Lo usan el servidor (el tamano de
  una captura: Lsp.InlineImages, delphi_adb) y el nodo de escritorio (su
  escritor de PNG, Mld.Captura, y el tamano de lo que capturo), que corre
  tambien en Linux: aqui solo System, nada de VCL ni de Windows. Estaba
  escrito tres veces - el escritor del nodo y dos lectores, uno que miraba la
  firma entera y otro solo sus tres letras - (David, 11-oct-2026: "leer un
  png no lo vamos a desperdigar"). Vigilado por test_paisaje ("la cabecera de
  un PNG"). }

interface

const
  { los 8 bytes con que empieza todo PNG }
  FIRMA_PNG: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
  { el tipo del primer trozo, el de la cabecera }
  TROZO_IHDR = 'IHDR';

{ Los 13 bytes de datos del trozo IHDR de una imagen de AAncho x AAlto,
  color verdadero RGB de 8 bits por canal, sin entrelazar: lo que escribe el
  nodo detras de la firma (con su longitud, su tipo y su CRC). }
function DatosIhdr(AAncho, AAlto: Integer): TArray<Byte>;

{ Ancho y alto de un PNG por su cabecera, sin decodificar la imagen: la
  firma, el trozo IHDR en su sitio (bytes 12..15) y sus dos enteros
  big-endian (16..23). False, y 0 x 0, si no es un PNG. La inversa de
  FIRMA_PNG + un trozo TROZO_IHDR con DatosIhdr. }
function TamanoPngBytes(const ABytes: TArray<Byte>; out W, H: Integer): Boolean;

implementation

function DatosIhdr(AAncho, AAlto: Integer): TArray<Byte>;
begin
  SetLength(Result, 13);
  Result[0] := Byte(AAncho shr 24);
  Result[1] := Byte(AAncho shr 16);
  Result[2] := Byte(AAncho shr 8);
  Result[3] := Byte(AAncho);
  Result[4] := Byte(AAlto shr 24);
  Result[5] := Byte(AAlto shr 16);
  Result[6] := Byte(AAlto shr 8);
  Result[7] := Byte(AAlto);
  Result[8] := 8;   // 8 bits por canal
  Result[9] := 2;   // color verdadero RGB
  Result[10] := 0;  // compresion deflate
  Result[11] := 0;  // filtrado estandar
  Result[12] := 0;  // sin entrelazado
end;

function TamanoPngBytes(const ABytes: TArray<Byte>; out W, H: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  W := 0;
  H := 0;
  if Length(ABytes) < 24 then
    Exit;
  for I := 0 to High(FIRMA_PNG) do
    if ABytes[I] <> FIRMA_PNG[I] then
      Exit;
  // bytes 8..11, la longitud del trozo; 12..15, su tipo
  for I := 0 to 3 do
    if ABytes[12 + I] <> Ord(TROZO_IHDR[I + 1]) then
      Exit;
  W := (ABytes[16] shl 24) or (ABytes[17] shl 16) or (ABytes[18] shl 8) or ABytes[19];
  H := (ABytes[20] shl 24) or (ABytes[21] shl 16) or (ABytes[22] shl 8) or ABytes[23];
  if (W <= 0) or (H <= 0) then
  begin
    W := 0;
    H := 0;
    Exit;
  end;
  Result := True;
end;

end.
