unit Lsp.DesignerBin;

{ Un .dfm BINARIO, y el camino de ida y vuelta a texto que usa el propio IDE
  ("Ver como texto" y guardar): las funciones de System.Classes que Delphi
  trae de serie, sin procesos ni ficheros temporales. Los .fmx son siempre
  texto: esto es solo VCL.

  Dos formas binarias, medidas con convert.exe (2026-09-24):
    - el fichero REAL en disco envuelve el flujo en una cabecera de recurso de
      16 bits: FF 0A 00 (tipo RT_RCDATA) + NOMBRE EN MAYUSCULAS + 00 +
      flags/tamano + TPF0... Un texto guardado en UTF-16 empieza por FF FE:
      por eso se miran tres bytes, no uno.
    - un flujo a pelo empieza por TPF0 (lo que escribe un WriteComponent).
  Un designer de texto empieza siempre por object/inherited/inline: nunca por
  $FF ni por TPF0.

  UN NOMBRADOR para la forma del fichero: hasta hoy cuatro sitios (Lsp.Patch,
  Lsp.ProjectUnits, Mcp.Tools.Designer, delphi_upload) comparaban los bytes a
  mano, cada uno con su copia de la regla. Y un solo conversor, el de la RTL:
  lo que escribe to-binary es byte a byte lo que escribe el IDE, y lo que lee
  to-text es lo que ensena "Ver como texto". Decision de David (24-sep-2026)
  tras el reporte de Hermes: un form legacy binario dejaba ciego al agente. }

interface

uses
  System.SysUtils;

type
  TDesignerShape = (dsText, dsTpf0, dsResource);

{ La forma de un designer a partir de sus primeros bytes. }
function DesignerShapeOf(const ABytes: TBytes): TDesignerShape;
function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
{ Lo mismo leyendo del disco: False si no existe o no llega a 4 bytes. }
function IsBinaryDesignerFile(const APath: string): Boolean;
{ Binario (cualquiera de las dos formas) -> texto, como "Ver como texto" del
  IDE. Devuelve '' si bien; si no, el motivo (fichero danado, no es un
  designer). El texto sale ASCII con CRLF, que es lo que escribe convert.exe. }
function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
function DesignerFileToText(const APath: string; out AText: string): string;
{ Texto -> binario CON envoltorio de recurso (la forma en disco del IDE).
  Devuelve '' si bien; si no, el error del parser con su linea. }
function DesignerTextToBinary(const AText: string; out ABytes: TBytes): string;

{ LA linea que abre un objeto en un designer de texto: 'object Nombre: TClase',
  'inherited ...' o 'inline ...', con o sin nombre ('object TMemo') y con o
  sin indice ('[2]'). True si lo es: AClave en minusculas (object, inherited
  o inline), ANombre ('' sin el) y AClase. El nombre y la clase por lo que
  los rodea, no por \w, que en TRegEx es ASCII: 'object lblDireccion: TLabel'
  con su acento se leia como la clase 'lblDirecci', y su end descolocaba el
  anidamiento. La leian seis regex - el lint, el binding (dos), tree
  (Lsp.Styles), el renombrado (Lsp.ProjectUnits) y layout -, cada una con su
  parte de la regla; lo destapo la prueba en vivo de la 1.12.0. Una linea de
  propiedad ('Inline = True') no es una. }
function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase: string): Boolean;
{ Su inversa: 'object Nombre: TClase' (AClave object, inherited o inline;
  sin nombre, 'object TClase'). Sin sangria: la pone quien la coloca. }
function ComponeLineaDeObjeto(const AClave, ANombre, AClase: string): string;

{ Un texto como VALOR de cadena de un designer de texto, como lo escribe el
  IDE (TWriter, ObjectBinaryToText): los tramos ASCII imprimibles entre
  comillas, la comilla doblada, y cada caracter de los demas como #N:
  'Acci'#243'n'. El vacio, ''. }
function LiteralDeForm(const S: string): string;
{ Sus lectores: AValor es un valor de cadena de un form (tramos entre
  comillas y #N, #$N pegados: lo que ReadString acepta), o UN caracter
  ('A', '''', #65: lo que ReadChar acepta). }
function EsLiteralDeForm(const AValor: string): Boolean;
function EsCaracterDeForm(const AValor: string): Boolean;

{ Un numero como lo escribe el IDE Win32 en una propiedad de coma flotante de
  un form, VCL o FMX: TWriter.WriteFloat y ObjectBinaryToText lo dejan con
  FloatToStrF(V, ffFixed, 16, 18), y V es lo que guarda la propiedad - en una
  Single (ASimple), redondeado a Single: 0.4 se escribe 0.400000005960464500,
  como en los .fmx de ejemplo de 13.1. 10 -> 10.000000000000000000 (un IDE
  Win64 escribe 17 decimales; medido el 4-oct-2026). }
function FlotanteDeForm(const AValor: Extended; ASimple: Boolean): string;
// el de un entero (el Position.X de un control FMX nuevo)
function FlotanteFmx(N: Integer): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  Lsp.Texts;

function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase: string): Boolean;
var
  M: TMatch;
begin
  AClave := '';
  ANombre := '';
  AClase := '';
  M := TRegEx.Match(ALinea.Trim,
    '(?i)^(object|inherited|inline)\s+(?:([^\s:=]+)\s*:\s*)?([^\s\[=:]+)');
  Result := M.Success;
  if Result then
  begin
    AClave := M.Groups[1].Value.ToLower;
    ANombre := M.Groups[2].Value;
    AClase := M.Groups[3].Value;
  end;
end;

function ComponeLineaDeObjeto(const AClave, ANombre, AClase: string): string;
begin
  if ANombre = '' then
    Result := AClave + ' ' + AClase
  else
    Result := AClave + ' ' + ANombre + ': ' + AClase;
end;

function LiteralDeForm(const S: string): string;
var
  Dentro: Boolean;
  C: Char;
begin
  Result := '';
  Dentro := False;
  for C in S do
    if (C >= ' ') and (C <= '~') then
    begin
      if not Dentro then
      begin
        Result := Result + '''';
        Dentro := True;
      end;
      if C = '''' then
        Result := Result + ''''''
      else
        Result := Result + C;
    end
    else
    begin
      if Dentro then
      begin
        Result := Result + '''';
        Dentro := False;
      end;
      Result := Result + '#' + IntToStr(Ord(C));
    end;
  if Dentro then
    Result := Result + ''''
  else if Result = '' then
    Result := '''''';
end;

const
  PATRON_CODIGO_DE_CARACTER = '#(?:\d+|\$[0-9A-Fa-f]+)';

function EsLiteralDeForm(const AValor: string): Boolean;
begin
  Result := TRegEx.IsMatch(AValor, '^(?:''(?:[^'']|'''')*''|' + PATRON_CODIGO_DE_CARACTER + ')+$');
end;

function EsCaracterDeForm(const AValor: string): Boolean;
begin
  Result := TRegEx.IsMatch(AValor, '^(?:''(?:[^'']|'''')''|' + PATRON_CODIGO_DE_CARACTER + ')$');
end;

{ Las cifras EXACTAS de un Double positivo, sin ceros delante ni detras, y
  AX con V = 0,ACifras x 10^AX: su mantisa por su potencia de 2, en decimal
  (por 2, o por 5 con la coma AX sitios a la izquierda). Este servidor es de
  64 bits y su FloatToStrF no sirve para esto: con 16 cifras trunca (0.4 en
  Single daba ...4644) y con 17 se equivoca (0.7 en Single, ...7105, y es
  ...710449; medido el 7-oct-2026). }
procedure CifrasExactas(const V: Double; out ACifras: string; out AX: Integer);
var
  Bits, M: UInt64;
  Exp, K, I: Integer;
  Cif: TArray<Byte>; // al reves: Cif[0] son las unidades

  procedure Multiplica(F: Integer);
  var
    J, P, Lleva: Integer;
  begin
    Lleva := 0;
    for J := 0 to High(Cif) do
    begin
      P := Cif[J] * F + Lleva;
      Cif[J] := P mod 10;
      Lleva := P div 10;
    end;
    while Lleva > 0 do
    begin
      SetLength(Cif, Length(Cif) + 1);
      Cif[High(Cif)] := Lleva mod 10;
      Lleva := Lleva div 10;
    end;
  end;

begin
  Move(V, Bits, SizeOf(Bits));
  Exp := (Bits shr 52) and $7FF;
  M := Bits and $FFFFFFFFFFFFF;
  if Exp = 0 then
    Exp := -1074
  else
  begin
    M := M or (UInt64(1) shl 52);
    Exp := Exp - 1075;
  end;
  Cif := [];
  repeat
    SetLength(Cif, Length(Cif) + 1);
    Cif[High(Cif)] := M mod 10;
    M := M div 10;
  until M = 0;
  K := 0;
  if Exp >= 0 then
    for I := 1 to Exp do
      Multiplica(2)
  else
  begin
    K := -Exp;
    for I := 1 to K do
      Multiplica(5);
  end;
  SetLength(ACifras, Length(Cif));
  for I := 0 to High(Cif) do
    ACifras[Length(Cif) - I] := Chr(Ord('0') + Cif[I]);
  AX := Length(ACifras) - K;
  while (Length(ACifras) > 1) and (ACifras[Length(ACifras)] = '0') do
    Delete(ACifras, Length(ACifras), 1);
end;

// ACifras a ANum cifras: la siguiente decide, hacia arriba desde 5
procedure RedondeaCifras(var ACifras: string; var AX: Integer; ANum: Integer);
var
  K: Integer;
  Sube: Boolean;
begin
  if Length(ACifras) <= ANum then
    Exit;
  Sube := ACifras[ANum + 1] >= '5';
  ACifras := Copy(ACifras, 1, ANum);
  if not Sube then
    Exit;
  K := ANum;
  while (K >= 1) and (ACifras[K] = '9') do
  begin
    ACifras[K] := '0';
    Dec(K);
  end;
  if K >= 1 then
    ACifras[K] := Chr(Ord(ACifras[K]) + 1)
  else
  begin
    ACifras := '1' + Copy(ACifras, 1, ANum - 1);
    Inc(AX);
  end;
end;

function FlotanteDeForm(const AValor: Extended; ASimple: Boolean): string;
var
  V: Double;
  Digitos, Ent, Frac: string;
  X, N: Integer;
begin
  V := AValor;
  if ASimple then
    V := Single(AValor);
  if V = 0 then
    Exit('0.' + StringOfChar('0', 18));
  CifrasExactas(Abs(V), Digitos, X);
  // como el IDE de 32 bits (el que manda; David, 7-oct-2026): las 18 cifras
  // que da su FPU (FBSTP) y de ahi FloatToStrF(V, ffFixed, 16, 18) - 16
  // cifras, sin pasar del decimal 18 (el 0.000001339281197943 de un .fmx de
  // ejemplo se corta en el decimal, no en la cifra). Medido contra los 80
  // valores distintos de los .fmx de ejemplo de 13.1: salen todos; el paso
  // de 18 cifras es como las saca la RTL de 32 bits, y ninguno de esos 80 lo
  // distingue (una guarda, no una medida)
  RedondeaCifras(Digitos, X, 18);
  N := 18 + X;
  if N > 16 then
    N := 16;
  if N < 1 then
    Exit('0.' + StringOfChar('0', 18));
  RedondeaCifras(Digitos, X, N);
  if X > 0 then
  begin
    while Length(Digitos) < X do
      Digitos := Digitos + '0';
    Ent := Copy(Digitos, 1, X);
    Frac := Copy(Digitos, X + 1, MaxInt);
  end
  else
  begin
    Ent := '0';
    Frac := StringOfChar('0', -X) + Digitos;
  end;
  Result := Ent + '.' + Frac + StringOfChar('0', 18 - Length(Frac));
  if V < 0 then
    Result := '-' + Result;
end;

function FlotanteFmx(N: Integer): string;
begin
  Result := FlotanteDeForm(N, True);
end;

function DesignerShapeOf(const ABytes: TBytes): TDesignerShape;
begin
  Result := dsText;
  if Length(ABytes) < 4 then
    Exit;
  // La cabecera de recurso de 16 bits: $FF y el TIPO 10 (RT_RCDATA) en dos
  // bytes, FF 0A 00. Solo $FF no vale: un .dfm de TEXTO guardado en UTF-16 LE
  // desde el IDE (el selector de codificacion del editor) empieza por FF FE,
  // y las cuatro comprobaciones antiguas lo tomaban por binario (David,
  // 24-sep-2026).
  if (ABytes[0] = $FF) and (ABytes[1] = $0A) and (ABytes[2] = $00) then
    Exit(dsResource);
  if (ABytes[0] = $54) and (ABytes[1] = $50) and (ABytes[2] = $46) and (ABytes[3] = $30) then
    Exit(dsTpf0);
end;

function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
begin
  Result := DesignerShapeOf(ABytes) <> dsText;
end;

function IsBinaryDesignerFile(const APath: string): Boolean;
var
  S: TFileStream;
  B: TBytes;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < 4 then
      Exit;
    SetLength(B, 4);
    S.ReadBuffer(B[0], 4);
  finally
    S.Free;
  end;
  Result := IsBinaryDesignerBytes(B);
end;

function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
var
  Entrada, Salida: TMemoryStream;
  Bytes: TBytes;
begin
  Result := '';
  AText := '';
  Entrada := TMemoryStream.Create;
  Salida := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      Entrada.WriteBuffer(ABytes[0], Length(ABytes));
    Entrada.Position := 0;
    try
      case DesignerShapeOf(ABytes) of
        dsResource: ObjectResourceToText(Entrada, Salida);
        dsTpf0: ObjectBinaryToText(Entrada, Salida);
      else
        Exit(MsgText(SR_DSGN_NO_ES_DESIGNER_BINARIO));
      end;
    except
      on E: Exception do
        Exit(MsgFmt(SR_DSGN_BINARIO_DANADO_FMT, [E.ClassName, E.Message]));
    end;
    SetLength(Bytes, Salida.Size);
    if Salida.Size > 0 then
      Move(Salida.Memory^, Bytes[0], Salida.Size);
    // El texto de un .dfm es ASCII: lo que no cabe va como #NNN. UTF-8 lo lee
    // tal cual y no inventa nada.
    AText := TEncoding.UTF8.GetString(Bytes);
  finally
    Entrada.Free;
    Salida.Free;
  end;
end;

function DesignerFileToText(const APath: string; out AText: string): string;
begin
  AText := '';
  if not TFile.Exists(APath) then
    Exit(MsgFmt(SR_NO_EXISTE_FMT, [APath]));
  Result := DesignerBinaryToText(TFile.ReadAllBytes(APath), AText);
end;

function DesignerTextToBinary(const AText: string; out ABytes: TBytes): string;
var
  Entrada, Salida: TMemoryStream;
  Bytes: TBytes;
begin
  Result := '';
  ABytes := nil;
  Entrada := TMemoryStream.Create;
  Salida := TMemoryStream.Create;
  try
    // El parser de la RTL (el mismo que usa el IDE al cargar un .dfm de
    // texto) lee los bytes como ANSI: darle UTF-8 convertia una 'o' con
    // acento en #195#179 (medido 24-sep-2026). Lo normal en un .dfm de
    // texto es que lo no-ASCII vaya como #NNN, que es como lo escribe el IDE
    // y como lo escribe to-text; una 'o' en crudo se le da en ANSI, y lo que
    // ANSI no puede representar se rechaza en vez de escribir '?'.
    Bytes := TEncoding.ANSI.GetBytes(AText);
    if TEncoding.ANSI.GetString(Bytes) <> AText then
      Exit(MsgText(SR_DSGN_CARACTERES_NO_CABEN_ANSI));
    if Length(Bytes) > 0 then
      Entrada.WriteBuffer(Bytes[0], Length(Bytes));
    Entrada.Position := 0;
    try
      ObjectTextToResource(Entrada, Salida);
    except
      on E: Exception do
        Exit(MsgFmt(SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT, [E.ClassName, E.Message]));
    end;
    SetLength(ABytes, Salida.Size);
    if Salida.Size > 0 then
      Move(Salida.Memory^, ABytes[0], Salida.Size);
  finally
    Entrada.Free;
    Salida.Free;
  end;
end;

end.
