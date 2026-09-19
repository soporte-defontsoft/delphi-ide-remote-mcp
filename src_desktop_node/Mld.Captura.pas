unit Mld.Captura;

{ La otra mitad de los OJOS: capturar el contenido de una ventana y guardarlo
  en PNG, sin ImageMagick ni ninguna herramienta externa.

  El PNG se escribe a mano (firma + IHDR + IDAT + IEND) porque es un formato
  sencillo y la RTL ya trae el deflate que necesita (System.ZLib). Asi el
  binario sigue sin depender de nada instalado en la maquina destino.

  Captura en coordenadas FISICAS de X11 (5504x2304 en el equipo medido), que
  NO son las logicas del escritorio: ver el modelo de coordenadas en
  [Mld.X11]. }

interface

{$IFDEF LINUX}
uses
  Mld.X11;
{$ENDIF}

{ El escritor de PNG es COMUN a los dos sistemas: tanto X11 como un DIB de
  Windows entregan los canales en orden BGR, asi que la misma rutina sirve
  para el escritorio Linux y para el de Windows ([Mld.Win]).
  ADatos apunta al primer pixel de la primera fila; ABytesPorLinea es el
  salto real entre filas (puede llevar relleno). }
function GuardarPNG(const ARuta: string; ADatos: PByte;
  AAncho, AAlto, ABytesPorLinea, ABpp: Integer): Boolean;

{$IFDEF LINUX}
type
  TCamara = class
  private
    FOjos: TOjos;
    FError: string;
  public
    constructor Create(AOjos: TOjos);
    { Captura la ventana AVentana entera y la guarda como PNG en ARuta.
      False deja el motivo en Error. }
    function Capturar(AVentana: NativeUInt; const ARuta: string): Boolean;
    property Error: string read FError;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes, System.ZLib;

{ ------------------------------------------------------------------ CRC32 }
var
  GTabla: array[0..255] of Cardinal;
  GTablaLista: Boolean = False;

procedure PrepararTabla;
var
  I, J: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := Cardinal(I);
    for J := 1 to 8 do
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    GTabla[I] := C;
  end;
  GTablaLista := True;
end;

function Crc32(const ADatos: TBytes; ADesde, ALargo: Integer): Cardinal;
var
  I: Integer;
begin
  if not GTablaLista then
    PrepararTabla;
  Result := $FFFFFFFF;
  for I := ADesde to ADesde + ALargo - 1 do
    Result := GTabla[(Result xor ADatos[I]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

{ ------------------------------------------------------------------- PNG }
procedure EscribirBE(AStream: TStream; AValor: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(AValor shr 24);
  B[1] := Byte(AValor shr 16);
  B[2] := Byte(AValor shr 8);
  B[3] := Byte(AValor);
  AStream.WriteBuffer(B, 4);
end;

procedure EscribirTrozo(AStream: TStream; const ATipo: AnsiString;
  const ADatos: TBytes);
var
  Buf: TBytes;
  I: Integer;
begin
  EscribirBE(AStream, Length(ADatos));
  SetLength(Buf, 4 + Length(ADatos));
  for I := 1 to 4 do
    Buf[I - 1] := Byte(ATipo[I]);
  if Length(ADatos) > 0 then
    Move(ADatos[0], Buf[4], Length(ADatos));
  AStream.WriteBuffer(Buf[0], Length(Buf));
  EscribirBE(AStream, Crc32(Buf, 0, Length(Buf)));
end;

{ ------------------------------------------------------- PNG desde pixeles }
function GuardarPNG(const ARuta: string; ADatos: PByte;
  AAncho, AAlto, ABytesPorLinea, ABpp: Integer): Boolean;
var
  Fila, Col, Destino: Integer;
  Crudo, Comprimido, Cab: TBytes;
  Origen: PByte;
  MS: TMemoryStream;
  Z: TZCompressionStream;
  Fich: TFileStream;
begin
  Result := False;
  if (ADatos = nil) or (AAncho <= 0) or (AAlto <= 0) then
    Exit;
  if (ABpp <> 32) and (ABpp <> 24) then
    Exit;

  { Lineas sin filtrar: un byte de filtro (0) y despues RGB. En memoria los
    canales llegan en orden BGR (little-endian), asi que se reordenan. }
  SetLength(Crudo, AAlto * (1 + AAncho * 3));
  Destino := 0;
  for Fila := 0 to AAlto - 1 do
  begin
    Crudo[Destino] := 0;
    Inc(Destino);
    Origen := ADatos + NativeInt(Fila) * ABytesPorLinea;
    for Col := 0 to AAncho - 1 do
    begin
      Crudo[Destino] := PByte(Origen + 2)^;      // R
      Crudo[Destino + 1] := PByte(Origen + 1)^;  // G
      Crudo[Destino + 2] := PByte(Origen)^;      // B
      Inc(Destino, 3);
      Inc(Origen, ABpp div 8);
    end;
  end;

  MS := TMemoryStream.Create;
  try
    Z := TZCompressionStream.Create(clDefault, MS);
    try
      Z.WriteBuffer(Crudo[0], Length(Crudo));
    finally
      Z.Free;
    end;
    SetLength(Comprimido, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.ReadBuffer(Comprimido[0], MS.Size);
    end;
  finally
    MS.Free;
  end;

  Fich := TFileStream.Create(ARuta, fmCreate);
  try
    SetLength(Cab, 8);
    Cab[0] := $89; Cab[1] := $50; Cab[2] := $4E; Cab[3] := $47;
    Cab[4] := $0D; Cab[5] := $0A; Cab[6] := $1A; Cab[7] := $0A;
    Fich.WriteBuffer(Cab[0], 8);

    SetLength(Cab, 13);
    Cab[0] := Byte(AAncho shr 24); Cab[1] := Byte(AAncho shr 16);
    Cab[2] := Byte(AAncho shr 8);  Cab[3] := Byte(AAncho);
    Cab[4] := Byte(AAlto shr 24);  Cab[5] := Byte(AAlto shr 16);
    Cab[6] := Byte(AAlto shr 8);   Cab[7] := Byte(AAlto);
    Cab[8] := 8;   // 8 bits por canal
    Cab[9] := 2;   // color verdadero RGB
    Cab[10] := 0;  // compresion deflate
    Cab[11] := 0;  // filtrado estandar
    Cab[12] := 0;  // sin entrelazado
    EscribirTrozo(Fich, 'IHDR', Cab);
    EscribirTrozo(Fich, 'IDAT', Comprimido);
    SetLength(Cab, 0);
    EscribirTrozo(Fich, 'IEND', Cab);
  finally
    Fich.Free;
  end;
  Result := True;
end;

{$IFDEF LINUX}
{ ---------------------------------------------------------------- camara }
constructor TCamara.Create(AOjos: TOjos);
begin
  inherited Create;
  FOjos := AOjos;
end;

function TCamara.Capturar(AVentana: NativeUInt; const ARuta: string): Boolean;
var
  Img: PXImage;
  Ancho, Alto, Bpp: Integer;
begin
  Result := False;
  FError := '';
  Img := FOjos.Imagen(AVentana);
  if Img = nil then
  begin
    FError := 'no pude leer la imagen de la ventana: ' + FOjos.Error;
    Exit;
  end;
  try
    Ancho := Img.Ancho;
    Alto := Img.Alto;
    Bpp := Img.BitsPerPixel;
    if (Ancho <= 0) or (Alto <= 0) or (Img.Datos = nil) then
    begin
      FError := 'la ventana no devolvio pixeles';
      Exit;
    end;
    if (Bpp <> 32) and (Bpp <> 24) then
    begin
      FError := Format('formato de pixel no contemplado: %d bits', [Bpp]);
      Exit;
    end;

    Result := GuardarPNG(ARuta, PByte(Img.Datos), Ancho, Alto,
      Img.BytesPerLine, Bpp);
    if not Result then
      FError := 'no pude escribir el PNG en ' + ARuta;
  finally
    FOjos.LiberarImagen(Img);
  end;
end;
{$ENDIF}

end.
