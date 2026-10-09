unit Lsp.Codificacion;

{ LOS CODECS DE LA CASA: las clases de codificacion de un fuente (TEncKind),
  su nombre y su inversa (EncName / EncKindOf), los bytes de su BOM
  (PreambleLen, BomUtf8En), el UTF-8 estricto (ValidUtf8), el decodificador y
  el codificador (DecodeBytes / EncodeText, con ECaracterNoCabe: el caracter
  que no cabe en la pagina de codigos del fichero) y LA pagina ANSI que
  comparten (PaginaAnsi: la de la maquina, la que usan el IDE y dcc; su codec,
  y el mapa de sus caracteres de un byte que lee ByteCp).

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
  el 24-sep-2026. UTF-32 (LE y BE, con BOM) el 9-oct-2026: el IDE deja
  guardar un fuente asi (dcc no lo compila: F2438) y su BOM de LE empieza
  como el de UTF-16 LE - se leia como UTF-16, con un NUL entre letra y
  letra, y se reescribia en UTF-16 (4.1 de la 1.18.0, David). }
type
  TEncKind = (ekUtf8Bom, ekUtf8, ekAnsi, ekUtf16LE, ekUtf16BE, ekUtf32LE, ekUtf32BE);

const
  { Las de VARIOS bytes por caracter (siempre con BOM): su cuerpo lleva
    ceros y no es binario, y sus saltos y acentos se miden sobre el texto, no
    byte a byte. UNA lista: Measure, LooksBinaryBytes y el recuento de bytes
    altos de DoEdit la tenian escrita cada uno, sin UTF-32 (4.1 de la 1.18.0). }
  ENC_ANCHAS = [ekUtf16LE, ekUtf16BE, ekUtf32LE, ekUtf32BE];

{ Si hay un BOM de UTF-8 (EF BB BF) en B a partir de AIndice. El de un
  fichero va en el 0 (DetectEnc); Lsp.Settings busca tambien los de mitad de un
  settings.ini, que Windows no ve (LineaConBomAntesDeSeccion). }
function BomUtf8En(const B: TArray<Byte>; AIndice: Integer): Boolean;
{ El BOM con el que EMPIEZA B, si lleva uno de los que conoce la casa: el de
  UTF-8 (ekUtf8Bom), el de UTF-16 o el de UTF-32, little o big endian. Sin
  BOM, False. Lo
  preguntan EL detector (Lsp.Patch.DetectEnc) y el lector de settings.ini
  (Lsp.Settings, que no puede usar Patch): la pregunta de FE FF estaba
  escrita a mano en los dos (9.2 de la 1.18.0). }
function KindDeBom(const B: TArray<Byte>; out AKind: TEncKind): Boolean;
{ Si S es solo ASCII (ningun caracter por encima de 127): cabe en cualquier
  codificacion de la casa y en el parser de forms de la RTL. Estaba escrito
  en Lsp.TextEdit y en linea en Lsp.DesignerBin (4.1 de la 1.18.0). }
function IsAscii(const S: string): Boolean;
{ Si algun byte de B pasa de 127 (un BOM tambien: todos llevan uno). Sin
  ninguno, el fichero no tiene codificacion que respetar: lo preguntan EL
  detector (Lsp.Patch.DetectEnc) y el escritor que elige la del primer
  caracter no ASCII (Lsp.Patch.EncAlEscribir). }
function HayByteAlto(const B: TArray<Byte>): Boolean;
{ Si S cabe entero en la pagina ANSI: el codec lo escribe y, al leerlo, da
  el mismo texto (Windows APROXIMA lo que no cabe: una Omega sale 'O' en
  1252 y una e acentuada 'e' en 1251, medido el 9-oct-2026; la vuelta lo
  delata). Lo pregunta el escritor que elige la codificacion de un fuente
  que no tenia ninguna (Lsp.Patch.EncAlEscribir: el primer caracter no
  ASCII) y el conversor a binario de un form (to-binary). }
function CabeEnAnsi(const S: string): Boolean;
{ LA pagina ANSI: la que usan el IDE y dcc para leer un fuente sin BOM que
  no es UTF-8 (medido el 9-oct-2026, bytes del exe: E1 C3 A1 sale U+00E1
  U+00C3 U+00A1 con la 1252 de esta maquina), la de TEncoding.ANSI de la
  RTL: GetACP. UN lector (norma 6 del paisaje, "lo medible no se
  hardcodea"): hasta el 9-oct-2026 el servidor la tenia clavada en 1252, y
  otros dos sitios usaban la de la maquina - en un Windows ruso, griego o
  polaco se leian y escribian mal los acentos de todo fuente ANSI.
  El DCC_CodePage de un proyecto NO se lee, a proposito: la codificacion la
  decide cada FICHERO (con BOM manda el BOM, aunque DCC_CodePage diga otra;
  sin BOM, UTF-8 si lo es y ANSI si no), y la pagina del proyecto solo diria
  que ANSI usa dcc - el editor del IDE la ignora y lee en la de la maquina
  (captura de David). Ninguno de los 3.258 .dproj de David la pone (medido el
  9-oct-2026); si uno la pusiera distinta de la maquina, dcc leeria sus
  fuentes ANSI en otra pagina que el IDE y el servidor (limite declarado). }
function PaginaAnsi: Cardinal;
{ SOLO las pruebas: la casa con OTRA pagina ANSI (1251, 1253, 932...), para
  medir en esta maquina lo que haria otra - con la 1252 clavada en el codigo
  y una maquina 1252, ninguna prueba lo distingue. El servidor no la llama:
  su initialization la fija con la de la maquina. }
procedure UsaPaginaAnsi(APagina: Cardinal);
{ Un codec NUEVO (quien lo pide lo libera) de la pagina que DECLARA un
  formato por su nombre ('windows-1252', 'utf-8', 'shift_jis', 'cp1251'),
  por la tabla de nombres de la RTL (TEncoding.GetEncoding), y tolerante como
  los de la casa: un byte que no cuadra sale U+FFFD o el que da Windows,
  nunca una excepcion. nil si la RTL no conoce el nombre. Para lo que no es
  un fuente y dice su propio juego de caracteres (la ayuda: el meta de cada
  pagina, que no es la ANSI de la maquina); un fuente lo decide EL detector. }
function CodecDeCharset(const ANombre: string): TEncoding;
{ Si los bytes B vuelven IGUALES al leerlos en K y volver a escribirlos en K:
  lo que ya esta se escribe con los mismos bytes. Un UTF-32 mal formado, un
  UTF-8 con BOM y el cuerpo roto, un UTF-16 de longitud impar - cualquier
  byte que su codificacion no guarda - da False: reescribir el fichero
  cambiaria bytes que nadie toco. La pregunta de los escritores es
  Lsp.Patch.ReescrituraDenegada, que la compone con EL detector (David,
  9-oct-2026: la regla de ida y vuelta, en el escritor); delphi_read la
  pregunta para avisar (READ-007). }
function BytesVuelvenIgual(const B: TArray<Byte>; K: TEncKind): Boolean;
function DecodeBytes(const B: TArray<Byte>; K: TEncKind): string;
function EncodeText(const S: string; K: TEncKind): TArray<Byte>;
function EncName(K: TEncKind): string;
function EncKindOf(const AName: string): TEncKind;
function PreambleLen(K: TEncKind): Integer;
{ UTF-8 ESTRICTO desde AOffset: cada byte alto forma una secuencia valida,
  la de RFC 3629 (sin formas largas, sin sustitutos, nada por encima de
  U+10FFFF). Lo contesta el juez de la RTL, TEncoding.UTF8.IsBufferValid: el
  mismo con el que TFile.ReadAllText elige entre UTF-8 y ANSI. Lo pregunta
  EL detector (Lsp.Patch.DetectEnc), para decidir: UTF-8 valido entero es
  UTF-8, cualquier otra cosa es ANSI - como el IDE, que detecta un UTF-8 sin
  BOM (medido el 9-oct-2026), y como dcc. Una regla propia ("UTF-8 danado":
  secuencias buenas junto a bytes que no lo son) contradecia a los dos: una
  E acentuada seguida de una comilla tipografica son, en 1252, un caracter
  UTF-8 valido, y un ANSI legitimo se leia con U+FFFD y no se editaba
  (revisor propio de la 4.1; David: "si hay juez lo seguimos"). }
function ValidUtf8(const B: TArray<Byte>; AOffset: Integer): Boolean;
{ El byte ANSI de un caracter que la pagina escribe en UN byte, -1 si no lo
  hay (no cabe, o en una pagina de varios bytes va en dos): el mismo codec
  que EncodeText, leido y escrito byte a byte al fijar la pagina. Lo
  pregunta el que busca mojibake (Lsp.Patch.MojibakeLines), que para
  U+0080..U+009F mira ademas la lectura Latin-1. }
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
  Winapi.Windows, // GetACP: la pagina ANSI de la maquina
  System.Generics.Collections,
  Lsp.Texts;

var
  GPaginaAnsi: Cardinal;
  GAnsi: TEncoding; // el codec de esa pagina, como TEncoding.ANSI (sin banderas)
  GUtf8Laxo: TEncoding; // sin MB_ERR_INVALID_CHARS: lee U+FFFD donde el estricto lanza
  GHighMap: TDictionary<Char, Byte>; // los caracteres de un byte de 80 a FF, sacados del codec
  // el codec y el mapa de una pagina que se cambio (solo lo hacen las
  // pruebas): un hilo puede estar leyendo con ellos, y se liberan al acabar
  GRetirados: TObjectList<TObject>;


function EncName(K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := 'utf8-bom';
    ekUtf8: Result := 'utf8';
    ekUtf16LE: Result := 'utf16-le';
    ekUtf16BE: Result := 'utf16-be';
    ekUtf32LE: Result := 'utf32-le';
    ekUtf32BE: Result := 'utf32-be';
  else
    // la forma 'cpNNNN', la que entiende tambien TEncoding.GetEncoding
    Result := 'cp' + UIntToStr(GPaginaAnsi);
  end;
end;

{ La inversa de EncName: el nombre que sale de una lectura vuelve a entrar
  como clase al guardar. Un nombre desconocido es la ANSI, como siempre. }
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
  else if AName = 'utf32-le' then
    Result := ekUtf32LE
  else if AName = 'utf32-be' then
    Result := ekUtf32BE
  else
    Result := ekAnsi;
end;

{ Bytes de BOM que preceden al texto en esa clase. }
function PreambleLen(K: TEncKind): Integer;
begin
  case K of
    ekUtf8Bom: Result := 3;
    ekUtf16LE, ekUtf16BE: Result := 2;
    ekUtf32LE, ekUtf32BE: Result := 4;
  else
    Result := 0;
  end;
end;

function ValidUtf8(const B: TBytes; AOffset: Integer): Boolean;
begin
  // EL juez de la RTL (el automata de Bjoern Hoehrmann). Aqui habia una copia
  // a mano, que hasta el 9-oct-2026 aceptaba formas largas y sustitutos: un
  // CP1252 con E0 80 80 se tomaba por UTF-8 y su lectura reventaba (norma 6
  // del paisaje, "lo medible no se hardcodea")
  Result := (AOffset >= Length(B)) or
    TEncoding.UTF8.IsBufferValid(@B[AOffset], Length(B) - AOffset);
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
  // el de UTF-32 LE (FF FE 00 00) ANTES que el de UTF-16 LE, que es su principio
  else if (Length(B) >= 4) and (B[0] = $FF) and (B[1] = $FE) and (B[2] = 0) and (B[3] = 0) then
    AKind := ekUtf32LE
  else if (Length(B) >= 2) and (B[0] = $FF) and (B[1] = $FE) then
    AKind := ekUtf16LE
  else if (Length(B) >= 2) and (B[0] = $FE) and (B[1] = $FF) then
    AKind := ekUtf16BE
  else if (Length(B) >= 4) and (B[0] = 0) and (B[1] = 0) and (B[2] = $FE) and (B[3] = $FF) then
    AKind := ekUtf32BE
  else
    Result := False;
end;

function IsAscii(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if Ord(C) > 127 then
      Exit(False);
  Result := True;
end;

function HayByteAlto(const B: TArray<Byte>): Boolean;
var
  X: Byte;
begin
  for X in B do
    if X > 127 then
      Exit(True);
  Result := False;
end;

function CabeEnAnsi(const S: string): Boolean;
begin
  Result := GAnsi.GetString(GAnsi.GetBytes(S)) = S;
end;

{ El primer caracter de S que la pagina ANSI no devuelve igual (un par de
  sustitutos va junto); si ninguno suelto falla, el primero no ASCII. }
function PrimeroQueNoCabe(const S: string): Char;
var
  I, N: Integer;
  T: string;
begin
  I := 1;
  while I <= Length(S) do
  begin
    N := 1;
    if (Ord(S[I]) >= $D800) and (Ord(S[I]) <= $DBFF) and (I < Length(S)) and
       (Ord(S[I + 1]) >= $DC00) and (Ord(S[I + 1]) <= $DFFF) then
      N := 2;
    T := Copy(S, I, N);
    if GAnsi.GetString(GAnsi.GetBytes(T)) <> T then
      Exit(S[I]);
    Inc(I, N);
  end;
  for I := 1 to Length(S) do
    if Ord(S[I]) > 127 then
      Exit(S[I]);
  Result := S[1];
end;

function BytesVuelvenIgual(const B: TArray<Byte>; K: TEncKind): Boolean;
var
  Vuelta: TArray<Byte>;
  I: Integer;
begin
  try
    Vuelta := EncodeText(DecodeBytes(B, K), K);
  except
    // un caracter que no cabe, o un decodificador que se niega: no vuelve
    on ECaracterNoCabe do
      Exit(False);
    on EEncodingError do
      Exit(False);
  end;
  if Length(Vuelta) <> Length(B) then
    Exit(False);
  for I := 0 to High(B) do
    if Vuelta[I] <> B[I] then
      Exit(False);
  Result := True;
end;

{ UTF-32 a mano: la RTL no tiene su codec y Windows no convierte las paginas
  12000/12001. Desde AInicio, de cuatro en cuatro bytes; un valor que no es
  un caracter (un sustituto suelto, mas alla de U+10FFFF) y una cola de menos
  de cuatro bytes salen U+FFFD, como lee un byte malo el decodificador de
  UTF-8 de la RTL. }
function DecodeUtf32(const B: TArray<Byte>; AInicio: Integer; ABigEndian: Boolean): string;
var
  I: Integer;
  CP: Cardinal;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    I := AInicio;
    while I + 3 <= High(B) do
    begin
      if ABigEndian then
        CP := (Cardinal(B[I]) shl 24) or (Cardinal(B[I + 1]) shl 16) or (Cardinal(B[I + 2]) shl 8) or B[I + 3]
      else
        CP := B[I] or (Cardinal(B[I + 1]) shl 8) or (Cardinal(B[I + 2]) shl 16) or (Cardinal(B[I + 3]) shl 24);
      if (CP > $10FFFF) or ((CP >= $D800) and (CP <= $DFFF)) then
        SB.Append(#$FFFD)
      else if CP >= $10000 then
      begin
        Dec(CP, $10000);
        SB.Append(Char($D800 + (CP shr 10))).Append(Char($DC00 + (CP and $3FF)));
      end
      else
        SB.Append(Char(CP));
      Inc(I, 4);
    end;
    // lo que sobra al final (menos de cuatro bytes) no es un caracter: U+FFFD
    if I <= High(B) then
      SB.Append(#$FFFD);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ La inversa: cada caracter (un par de sustitutos, uno) en cuatro bytes; un
  sustituto suelto, U+FFFD. }
function EncodeUtf32(const S: string; ABigEndian: Boolean): TArray<Byte>;
var
  I, N: Integer;
  CP: Cardinal;
begin
  SetLength(Result, Length(S) * 4);
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    CP := Ord(S[I]);
    if (CP >= $D800) and (CP <= $DBFF) and (I < Length(S)) and
       (Ord(S[I + 1]) >= $DC00) and (Ord(S[I + 1]) <= $DFFF) then
    begin
      CP := $10000 + ((CP - $D800) shl 10) + (Cardinal(Ord(S[I + 1])) - $DC00);
      Inc(I);
    end
    else if (CP >= $D800) and (CP <= $DFFF) then
      CP := $FFFD;
    if ABigEndian then
    begin
      Result[N] := Byte(CP shr 24); Result[N + 1] := Byte(CP shr 16);
      Result[N + 2] := Byte(CP shr 8); Result[N + 3] := Byte(CP);
    end
    else
    begin
      Result[N] := Byte(CP); Result[N + 1] := Byte(CP shr 8);
      Result[N + 2] := Byte(CP shr 16); Result[N + 3] := Byte(CP shr 24);
    end;
    Inc(N, 4);
    Inc(I);
  end;
  SetLength(Result, N);
end;

function DecodeBytes(const B: TBytes; K: TEncKind): string;
begin
  case K of
    // el UTF-8 TOLERANTE: un byte malo sale U+FFFD, no una excepcion. El
    // estricto (TEncoding.UTF8) tumbaba delphi_read y delphi_search con un
    // SYS-006 en un fichero con BOM y el cuerpo roto (medido el 9-oct-2026);
    // lo estricto es del detector (ValidUtf8) y de los escritores
    // (BytesVuelvenIgual)
    ekUtf8Bom: Result := GUtf8Laxo.GetString(B, 3, Length(B) - 3);
    ekUtf8: Result := GUtf8Laxo.GetString(B);
    // los pares de bytes, y un byte suelto al final sale U+FFFD, como cualquier
    // byte que no cuadra: la RTL lo dejaba fuera callado (divide entre dos) y
    // delphi_edit reescribia el fichero sin el (revisor propio de la 4.1,
    // medido). La ida y vuelta lo ve: no vuelve igual, nadie lo reescribe
    ekUtf16LE, ekUtf16BE:
      begin
        if K = ekUtf16LE then
          Result := TEncoding.Unicode.GetString(B, 2, (Length(B) - 2) and not 1)
        else
          Result := TEncoding.BigEndianUnicode.GetString(B, 2, (Length(B) - 2) and not 1);
        if Odd(Length(B)) then
          Result := Result + #$FFFD;
      end;
    ekUtf32LE: Result := DecodeUtf32(B, 4, False);
    ekUtf32BE: Result := DecodeUtf32(B, 4, True);
  else
    Result := GAnsi.GetString(B);
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
  Body: TBytes;
begin
  case K of
    ekUtf16LE: Exit(TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(S));
    ekUtf16BE: Exit(TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(S));
    // el BOM es el caracter U+FEFF, por el mismo codificador
    ekUtf32LE: Exit(EncodeUtf32(#$FEFF + S, False));
    ekUtf32BE: Exit(EncodeUtf32(#$FEFF + S, True));
  end;
  if K <> ekAnsi then
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
  // la ANSI: lo que su codec escribe y, al leerlo, vuelve igual. Windows
  // APROXIMA lo que no cabe (una Omega sale 'O' en 1252, medido): la vuelta
  // lo delata, y el primer caracter que no vuelve se niega con su codigo, en
  // cualquier pagina, de un byte o de varios (una tabla propia de que cabe
  // era la de 1252)
  Result := GAnsi.GetBytes(S);
  if GAnsi.GetString(Result) <> S then
    raise ECaracterNoCabe.Crea(PrimeroQueNoCabe(S), K);
end;

function ByteCp(C: Char): Integer;
var
  B: Byte;
begin
  // el ASCII es el mismo en toda pagina ANSI de Windows; lo demas, lo que el
  // codec lee de cada byte y vuelve a escribir en el (UsaPaginaAnsi): un
  // U+0080 no lo da ningun byte de 1252 (el 80 es el euro) y no cabe
  if Ord(C) < $80 then
    Exit(Ord(C));
  if GHighMap.TryGetValue(C, B) then
    Exit(B);
  Result := -1;
end;

function PaginaAnsi: Cardinal;
begin
  Result := GPaginaAnsi;
end;

function CodecDeCharset(const ANombre: string): TEncoding;
var
  Rtl: TEncoding;
  Pagina: Integer;
begin
  try
    Rtl := TEncoding.GetEncoding(ANombre);
  except
    on EEncodingError do
      Exit(nil);
  end;
  Pagina := Rtl.CodePage;
  // UTF-16 no lo convierte MultiByteToWideChar: el de la RTL, que no lanza
  if (Pagina = 1200) or (Pagina = 1201) then
    Exit(Rtl);
  Rtl.Free;
  // sin banderas, como TEncoding.ANSI: el UTF-8 de la RTL lanza con un byte malo
  Result := TMBCSEncoding.Create(Pagina, 0, 0);
end;

procedure UsaPaginaAnsi(APagina: Cardinal);
var
  B: Byte;
  S: string;
  Uno: TBytes;
  Nuevo: TEncoding;
  Mapa: TDictionary<Char, Byte>;
begin
  // lo nuevo PRIMERO y el cambio despues: una pagina que no existe lanza aqui
  // y deja la de antes entera (revisor propio de r5). El codec de
  // TEncoding.ANSI, sin banderas: lee como la RTL y el IDE
  Nuevo := TMBCSEncoding.Create(APagina, 0, 0);
  Mapa := TDictionary<Char, Byte>.Create;
  try
    // los caracteres que la pagina escribe en UN byte y que vuelven a el. En
    // 1252 tambien los cinco que no define (81 8D 8F 90 9D): Windows los lee
    // como U+0081... y los vuelve a escribir en su byte (medido). En una
    // pagina de varios bytes, un byte de cabecera solo no vuelve a si mismo
    // y no entra
    for B := $80 to $FF do
    begin
      S := Nuevo.GetString(TBytes.Create(B));
      if (Length(S) = 1) and (S[1] <> #$FFFD) then
      begin
        Uno := Nuevo.GetBytes(S);
        if (Length(Uno) = 1) and (Uno[0] = B) then
          Mapa.AddOrSetValue(S[1], B);
      end;
    end;
  except
    Mapa.Free;
    Nuevo.Free;
    raise;
  end;
  // lo de antes no se libera aqui: otro hilo puede estar leyendo con ello
  if GAnsi <> nil then
    GRetirados.Add(GAnsi);
  if GHighMap <> nil then
    GRetirados.Add(GHighMap);
  GAnsi := Nuevo;
  GHighMap := Mapa;
  GPaginaAnsi := APagina;
end;

initialization
  GUtf8Laxo := TMBCSEncoding.Create(CP_UTF8, 0, 0);
  GRetirados := TObjectList<TObject>.Create(True);
  // la de la maquina: la de TEncoding.ANSI, TMBCSEncoding.Create(GetACP, 0, 0)
  UsaPaginaAnsi(GetACP);

finalization
  GHighMap.Free;
  GUtf8Laxo.Free;
  GAnsi.Free;
  GRetirados.Free;

end.
