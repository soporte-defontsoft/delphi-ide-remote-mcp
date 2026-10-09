unit Lsp.Codificacion;

{ LOS CODECS DE LA CASA: las clases de codificacion de un fuente (TEncKind),
  su nombre y su inversa (EncName / EncKindOf), los bytes de su BOM
  (PreambleLen, BomUtf8En), el UTF-8 estricto (ValidUtf8), el decodificador y
  el codificador (DecodeBytes / EncodeText, con ECaracterNoCabe: el caracter
  que no cabe en la pagina de codigos del fichero) y el codec CP1252 que
  comparten (GCp1252, y GHighMap para 0x80-0x9F, que lee ByteCp).

  Salen de Lsp.Patch el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidos sin cambiar una linea. Son PUROS: no saben nada del IDE ni de la
  jaula. DECIDIR la codificacion de unos bytes no es de aqui: EL detector
  (DetectEnc, que para el ASCII sin BOM pregunta al IDE) se queda en
  Lsp.Patch, y test_paisaje lo fija alli. }

interface

uses
  System.SysUtils; // Exception: ECaracterNoCabe es una de ellas

{ Las clases de codificacion de un fuente: las decide EL detector
  (Lsp.Patch.DetectEnc) y las leen y escriben sus dos inversas, DecodeBytes y
  EncodeText (aqui abajo). UTF-16 (LE y BE, siempre con BOM: es como lo
  escribe el IDE cuando se elige ese formato al ver un .dfm como texto) entro
  el 24-sep-2026. }
type
  TEncKind = (ekUtf8Bom, ekUtf8, ekCp1252, ekUtf16LE, ekUtf16BE);

{ Si hay un BOM de UTF-8 (EF BB BF) en B a partir de AIndice. El de un
  fichero va en el 0 (DetectEnc); Lsp.Settings busca tambien los de mitad de un
  settings.ini, que Windows no ve (LineaConBomAntesDeSeccion). }
function BomUtf8En(const B: TArray<Byte>; AIndice: Integer): Boolean;
{ El BOM con el que EMPIEZA B, si lleva uno de los que conoce la casa: el de
  UTF-8 (ekUtf8Bom) o el de UTF-16 little o big endian. Sin BOM, False. Lo
  preguntan EL detector (Lsp.Patch.DetectEnc) y el lector de settings.ini
  (Lsp.Settings, que no puede usar Patch): la pregunta de FE FF estaba
  escrita a mano en los dos (9.2 de la 1.18.0). }
function KindDeBom(const B: TArray<Byte>; out AKind: TEncKind): Boolean;
function DecodeBytes(const B: TArray<Byte>; K: TEncKind): string;
function EncodeText(const S: string; K: TEncKind): TArray<Byte>;
function EncName(K: TEncKind): string;
function EncKindOf(const AName: string): TEncKind;
function PreambleLen(K: TEncKind): Integer;
{ UTF-8 ESTRICTO desde AOffset: cada byte alto forma una secuencia valida.
  Lo preguntan EL detector (Lsp.Patch.DetectEnc), para decidir, y el que
  audita el cuerpo de un utf8-bom antes de escribirlo (ExecutePatch). }
function ValidUtf8(const B: TArray<Byte>; AOffset: Integer): Boolean;
{ El byte CP1252 de un caracter, -1 si no cabe: lo lee el que busca mojibake
  en un texto (Lsp.Patch.MojibakeLines). }
function ByteCp(C: Char): Integer;

type
  { Un caracter que no cabe en la pagina de codigos del fichero. Lleva SU
    codigo (el lector lo sacaba del texto con una regex) y su mensaje ya es
    la negativa entera, con su resultado: una tanda o un changeset que la
    reciben como excepcion dicen DENIED, no INTERNAL (revision 27-sep-2026). }
  ECaracterNoCabe = class(Exception)
  public
    Codigo: Integer;
    constructor Crea(ACaracter: Char; AK: TEncKind);
  end;

implementation

uses
  System.Generics.Collections,
  Lsp.Texts;

var
  GCp1252: TEncoding;
  GHighMap: TDictionary<Char, Byte>; // CP1252 0x80-0x9F, derived from the codec


function EncName(K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := 'utf8-bom';
    ekUtf8: Result := 'utf8';
    ekUtf16LE: Result := 'utf16-le';
    ekUtf16BE: Result := 'utf16-be';
  else
    Result := 'cp1252';
  end;
end;

{ La inversa de EncName: el nombre que sale de una lectura vuelve a entrar
  como clase al guardar. Un nombre desconocido es cp1252, como siempre. }
function EncKindOf(const AName: string): TEncKind;
begin
  if AName = 'utf8-bom' then
    Result := ekUtf8Bom
  else if AName = 'utf8' then
    Result := ekUtf8
  else if AName = 'utf16-le' then
    Result := ekUtf16LE
  else if AName = 'utf16-be' then
    Result := ekUtf16BE
  else
    Result := ekCp1252;
end;

{ Bytes de BOM que preceden al texto en esa clase. }
function PreambleLen(K: TEncKind): Integer;
begin
  case K of
    ekUtf8Bom: Result := 3;
    ekUtf16LE, ekUtf16BE: Result := 2;
  else
    Result := 0;
  end;
end;

function ValidUtf8(const B: TBytes; AOffset: Integer): Boolean;
var
  I, N, K: Integer;
begin
  I := AOffset;
  while I < Length(B) do
  begin
    if B[I] < $80 then
      Inc(I)
    else
    begin
      if (B[I] >= $C2) and (B[I] <= $DF) then
        N := 1
      else if (B[I] >= $E0) and (B[I] <= $EF) then
        N := 2
      else if (B[I] >= $F0) and (B[I] <= $F4) then
        N := 3
      else
        Exit(False);
      if I + N >= Length(B) then
        Exit(False);
      for K := 1 to N do
        if (B[I + K] < $80) or (B[I + K] > $BF) then
          Exit(False);
      Inc(I, N + 1);
    end;
  end;
  Result := True;
end;

function BomUtf8En(const B: TArray<Byte>; AIndice: Integer): Boolean;
begin
  Result := (AIndice >= 0) and (AIndice + 2 <= High(B)) and (B[AIndice] = $EF) and
    (B[AIndice + 1] = $BB) and (B[AIndice + 2] = $BF);
end;

function KindDeBom(const B: TArray<Byte>; out AKind: TEncKind): Boolean;
begin
  Result := True;
  if BomUtf8En(B, 0) then
    AKind := ekUtf8Bom
  else if (Length(B) >= 2) and (B[0] = $FF) and (B[1] = $FE) then
    AKind := ekUtf16LE
  else if (Length(B) >= 2) and (B[0] = $FE) and (B[1] = $FF) then
    AKind := ekUtf16BE
  else
    Result := False;
end;

function DecodeBytes(const B: TBytes; K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := TEncoding.UTF8.GetString(B, 3, Length(B) - 3);
    ekUtf8: Result := TEncoding.UTF8.GetString(B);
    ekUtf16LE: Result := TEncoding.Unicode.GetString(B, 2, Length(B) - 2);
    ekUtf16BE: Result := TEncoding.BigEndianUnicode.GetString(B, 2, Length(B) - 2);
  else
    Result := GCp1252.GetString(B);
  end;
end;

constructor ECaracterNoCabe.Crea(ACaracter: Char; AK: TEncKind);
var
  Hex: string;
begin
  Codigo := Ord(ACaracter);
  Hex := IntToHex(Codigo, 4);
  inherited Create(MsgFmt(SR_EDIT_CARACTERES_NO_CABEN_FMT,
    [MsgFmt(SF_EDIT_CARACTER_NO_EXISTE_FMT, [ACaracter, Hex, EncName(AK)]), EncName(AK)]));
end;

function EncodeText(const S: string; K: TEncKind): TBytes;
var
  I: Integer;
  C: Char;
  BB: Byte;
  Body: TBytes;
begin
  case K of
    ekUtf16LE: Exit(TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(S));
    ekUtf16BE: Exit(TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(S));
  end;
  if K <> ekCp1252 then
  begin
    Body := TEncoding.UTF8.GetBytes(S);
    if K = ekUtf8Bom then
    begin
      SetLength(Result, Length(Body) + 3);
      Result[0] := $EF; Result[1] := $BB; Result[2] := $BF;
      if Length(Body) > 0 then
        Move(Body[0], Result[3], Length(Body));
    end
    else
      Result := Body;
    Exit;
  end;
  SetLength(Result, Length(S));
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (Ord(C) <= $FF) and not ((Ord(C) >= $80) and (Ord(C) <= $9F)) then
      Result[I - 1] := Byte(Ord(C))
    else if GHighMap.TryGetValue(C, BB) then
      Result[I - 1] := BB
    else
      raise ECaracterNoCabe.Crea(C, K);
  end;
end;

function ByteCp(C: Char): Integer;
var
  B: Byte;
begin
  if GHighMap.TryGetValue(C, B) then
    Exit(B);
  if Ord(C) <= $FF then
    Exit(Ord(C));
  Result := -1;
end;

procedure InitHighMap;
var
  B: Byte;
  S: string;
begin
  GHighMap := TDictionary<Char, Byte>.Create;
  for B := $80 to $9F do
  begin
    S := GCp1252.GetString(TBytes.Create(B));
    if (Length(S) = 1) and (S[1] <> #$FFFD) and (Ord(S[1]) <> B) then
      GHighMap.AddOrSetValue(S[1], B);
  end;
end;

initialization
  GCp1252 := TEncoding.GetEncoding(1252);
  InitHighMap;

finalization
  GHighMap.Free;
  GCp1252.Free;

end.
