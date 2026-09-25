unit Lsp.Base64;

{ EL codificador y EL decodificador base64 de la casa, para bytes que viajan
  dentro de una respuesta o de un parametro (delphi_fetch, delphi_upload, y
  la captura inline del escritorio cuando llegue). David, 25-sep-2026: "file
  to base64 y base64 to file deberia ser un helper reutilizable". Antes fetch
  codificaba y upload validaba y decodificaba cada uno por su cuenta.

  El decodificador es ESTRICTO a proposito: el de Delphi se salta los
  caracteres que no son base64 y acepta longitudes que no van en grupos de 4,
  y las dos cosas escribian un fichero corrupto que solo el sha del final
  cazaba (hermes, 25-sep-2026: un modelo pequeno transcribiendo 9 KB de
  base64). Aqui se rechaza ANTES de decodificar, diciendo el motivo. }

interface

{ Bytes -> base64 en una sola linea (sin saltos): lo que viaja en JSON. }
function BytesToBase64(const ABytes: TArray<Byte>): string;

{ base64 -> bytes. '' = bien (ABytes cargado). Si no, el rechazo listo para
  devolver, nombrando el parametro (AParam) que lo traia: caracteres fuera
  del alfabeto, longitud util que no va en grupos de 4, o el decodificador. }
function Base64ToBytes(const ATexto, AParam: string; out ABytes: TArray<Byte>): string;

implementation

uses
  System.SysUtils,
  System.NetEncoding,
  Lsp.Texts;

function BytesToBase64(const ABytes: TArray<Byte>): string;
var
  B64: TBase64Encoding;
begin
  B64 := TBase64Encoding.Create(0); // 0 = sin saltos de linea
  try
    Result := B64.EncodeBytesToString(ABytes);
  finally
    B64.Free;
  end;
end;

function Base64ToBytes(const ATexto, AParam: string; out ABytes: TArray<Byte>): string;
var
  B64: TBase64Encoding;
  Ch: Char;
  Utiles: Integer;
begin
  Result := '';
  ABytes := nil;
  Utiles := 0;
  for Ch in ATexto do
    if CharInSet(Ch, [#13, #10, ' ']) then
      Continue
    else if CharInSet(Ch, ['A' .. 'Z', 'a' .. 'z', '0' .. '9', '+', '/', '=']) then
      Inc(Utiles)
    else
      Exit(Format(SR_B64_ALPHABET_FMT, [AParam]));
  if Utiles mod 4 <> 0 then
    Exit(Format(SR_B64_LEN_FMT, [AParam, Utiles]));
  B64 := TBase64Encoding.Create(0);
  try
    try
      ABytes := B64.DecodeStringToBytes(ATexto);
    except
      on E: Exception do
        Exit(Format(SR_B64_INVALID_FMT, [AParam, E.Message]));
    end;
  finally
    B64.Free;
  end;
end;

end.
