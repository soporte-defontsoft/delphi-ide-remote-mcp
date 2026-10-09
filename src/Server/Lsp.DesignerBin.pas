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

// La forma de un designer (TDesignerShape, DesignerShapeOf) vive en
// Lsp.DesignerForma: los renderizadores de src\Render la leen igual.
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

// La linea de objeto (LineaDeObjeto y su inversa ComponeLineaDeObjeto) vive
// en Lsp.DesignerForma, con la forma del fichero: la leen tambien los
// renderizadores.

{ Un texto como VALOR de cadena de un designer de texto, como lo escribe el
  IDE (ObjectBinaryToText de System.Classes; medido en su fuente de 13.1 y en
  los .dfm de ejemplo): los tramos ASCII imprimibles entre comillas y cada
  caracter de los demas - la comilla tambien - como #N: 'Conway'#39's Life',
  'Acci'#243'n'; el vacio, ''. En TROZOS: uno si el texto cabe en 64
  caracteres; si no, uno por cada 64 caracteres del texto, todos menos el
  ultimo acabados en ' +', que van en las lineas de debajo (LineasDePropiedad).
  En una sola linea no: una de 4.095 caracteres o mas no la lee el IDE
  (TParser, "Line too long"; revision de la 1.17.0). }
function TrozosDeLiteral(const S: string): TArray<string>;
{ Las lineas de una propiedad como las escribe el IDE: 'Prop = valor' con un
  trozo; con varios, 'Prop = ' y cada trozo una sangria (dos espacios) mas
  adentro. ASangria, la de la linea de la propiedad. }
function LineasDePropiedad(const ASangria, AProp: string; const ATrozos: TArray<string>): TArray<string>;
{ La sangria de un nivel de un designer de texto, como la escribe el IDE: dos
  espacios por nivel (las propiedades del objeto raiz van en el 1). La
  calculaban a mano cuatro sitios de Lsp.Styles y Lsp.DesignerEdit (2.3 de la
  1.18.0). }
function SangriaDeNivel(ANivel: Integer): string;
{ Su lector, el inverso: el texto de un valor de cadena de un form - tramos
  entre comillas (la comilla doblada dentro), #N y #$N pegados, y trozos
  unidos con '+', que el TParser une: lo que ReadString acepta. False si no
  lo es. }
function LeeLiteralDeForm(const AValor: string; out ATexto: string): Boolean;
function EsLiteralDeForm(const AValor: string): Boolean;
{ Un NOMBRE dado como valor (el Name de un componente, el StyleName de un
  estilo): si es un literal de form ('BtnOk', 'Bot'#243'n', 'a' + 'b'), su
  texto; si no, el valor tal cual. Sin espacios alrededor. Lo leian de tres
  maneras el renombrado y el insert del disenador (quitaban las comillas a
  mano), styles set y styles clone (tal cual): el mismo nombre valia en uno
  y no en otro (P5 de la segunda revision de la 1.17.0). }
function NombreDeValor(const AValor: string): string;
// UN caracter, lo que ReadChar acepta: 'A', #39, #65
function EsCaracterDeForm(const AValor: string): Boolean;
{ Un numero como lo lee el cargador (TParser): entero, $hex, o con decimales
  y exponente (1.5, -2E3, 1.5e-5), con su signo. }
function EsNumeroDeForm(const AValor: string): Boolean;
// y uno ENTERO (decimal con su signo, o $hex sin el: TParser no lee -$FF)
function EsEnteroDeForm(const AValor: string): Boolean;

(* LA gramatica de las lineas de un designer de texto, la que escribe
  ObjectBinaryToText: cada linea, que es. Un objeto (LineaDeObjeto) y su end;
  una propiedad 'Prop = valor' con la ultima linea de su valor - una cadena
  partida con ' +' (o la que el IDE empieza en la linea de debajo: 'Caption = '
  y los trozos), una lista ( ... ), un bloque binario { ... } o una coleccion
  < item ... end ... end> -; y dentro de una coleccion sus items, que llevan
  propiedades (un OnClick, un Action = Action1) y otras colecciones. La leian
  cuatro lectores a mano, cada uno con su parte: el arbol de tree y de las
  ediciones cerraba una coleccion con cualquier linea acabada en '>' (un
  'Items = <>' de un item) y tomaba por binario un 'Caption = 'Total = {0}''
  hasta el final del fichero; check-binding contaba como objetos los end de
  los items; set cortaba la cadena larga del IDE por su primera linea
  (revision de la 1.17.0, medido en vivo). *)
type
  TClaseLineaForm = (clfOtra, clfObjeto, clfFin, clfPropiedad, clfValor, clfItem, clfFinItem);
  TLineaForm = record
    Clase: TClaseLineaForm;
    Coleccion: Integer;  // colecciones abiertas alrededor: 0 = el nivel del objeto
    Prop, Valor: string; // clfPropiedad: el nombre (con puntos) y lo de detras del '='
    Fin: Integer;        // clfPropiedad: la ultima linea (0-based) de su valor; la del '>' de una coleccion
    Clave, Nombre, ClaseObj: string; // clfObjeto: lo que da LineaDeObjeto
  end;

function LineasDeForm(const ALineas: TArray<string>): TArray<TLineaForm>;
// una linea 'Prop = valor' (Prop con puntos; AValor sin espacios alrededor)
function LineaDePropiedad(const ALinea: string; out AProp, AValor: string): Boolean;
(* El valor entero de la propiedad de la linea AIni (clfPropiedad): el de su
  linea, o si es una cadena partida, sus trozos en una ('a' + 'b': lo que lee
  LeeLiteralDeForm). De una lista, un bloque o una coleccion, su primera linea
  ('(', '{', '<'). *)
function ValorEnteroDe(const ALineas: TArray<string>; const AForm: TArray<TLineaForm>;
  AIni: Integer): string;
(* Si el valor de una propiedad (lo de detras del '=', o lo que da
  ValorEnteroDe) es de BLOQUE: una lista '(', un bloque binario '{' o una
  coleccion '<' - lo que no es un valor de una linea, ni se juzga ni se
  reescribe como uno. Se preguntaba a mano en tres sitios del disenador y
  del juez de los forms (2.3 de la 1.18.0). *)
function EsValorDeBloque(const AValor: string): Boolean;

{ Un numero como lo escribe el IDE Win32 en una propiedad de coma flotante de
  un form, VCL o FMX: TWriter.WriteFloat y ObjectBinaryToText lo dejan con
  FloatToStrF(V, ffFixed, 16, 18), y V es lo que guarda la propiedad - en una
  Single (ASimple), redondeado a Single: 0.4 se escribe 0.400000005960464500,
  como en los .fmx de ejemplo de 13.1. 10 -> 10.000000000000000000 (un IDE
  Win64 escribe 17 decimales; medido el 4-oct-2026). }
function FlotanteDeForm(const AValor: Extended; ASimple: Boolean): string;
// el de un entero (el Position.X de un control FMX nuevo)
function FlotanteFmx(N: Integer): string;

{ Si un NOMBRE (de componente) puede entrar en un form y en su unidad con
  las codificaciones que tienen, sin cambiarlas - la codificacion de un
  fichero no se cambia de paso (contrato de edicion de la casa, puntos 7 y
  8) -. Un nombre ASCII, siempre. Uno con una letra que no lo es necesita:
  - el form en UTF-8 con BOM: sin el, TParser (el del IDE, el del build y el
    del renderizador) lee el fichero en ANSI, y en ANSI ningun byte alto es
    letra de un identificador (System.Classes, TParser.CharType). El IDE le
    pone el BOM al guardar (ObjectBinaryToText);
  - la unidad con BOM o en CP1252: dcc lee en ANSI un fuente sin BOM, y en
    UTF-8 sin BOM el campo queda con otro nombre que su componente.
  Medido el 7-oct-2026 (segunda revision de la 1.17.0): insert con un nombre
  con acento en un .dfm sin BOM dejaba el proyecto sin compilar (RLINK32), y
  con la unidad en UTF-8 sin BOM el campo salia en la RTTI del exe leido en
  ANSI (otros bytes que su componente); las dos diciendo OK. Devuelve '' o
  la negativa (DSGN-111) con el fichero que no puede. Las codificaciones,
  con los nombres de EncName. }
function NombreQueElFicheroNoLee(const ANombre, ADfm, ADfmEnc, APas, APasEnc: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Lsp.Pascal, // EL identificador: la linea de una propiedad
  Lsp.DesignerForma, // la forma del fichero: texto, TPF0 o recurso
  Lsp.Codificacion, // EncName / EncKindOf: los nombres de las codificaciones
  Lsp.Texts;

function SangriaDeNivel(ANivel: Integer): string;
begin
  Result := StringOfChar(' ', ANivel * 2);
end;

function TrozosDeLiteral(const S: string): TArray<string>;
const
  LARGO_DE_LINEA = 64; // el LineLength de ObjectBinaryToText
var
  I, J, K, L: Integer;
  Trozo: string;
  Corta: Boolean;
begin
  Result := [''''''];
  L := Length(S);
  if L = 0 then
    Exit;
  Result := [];
  // el bucle de ObjectBinaryToText (vaWString): K, donde empieza la linea,
  // en caracteres del TEXTO, no de lo escrito
  Trozo := '';
  I := 1;
  K := 1;
  repeat
    Corta := False;
    if (S[I] >= ' ') and (S[I] <> '''') and (Ord(S[I]) <= 127) then
    begin
      J := I;
      repeat
        Inc(I);
      until (I > L) or (S[I] < ' ') or (S[I] = '''') or (I - K >= LARGO_DE_LINEA) or
        (Ord(S[I]) > 127);
      if I - K >= LARGO_DE_LINEA then
        Corta := True;
      Trozo := Trozo + '''' + Copy(S, J, I - J) + '''';
    end
    else
    begin
      Trozo := Trozo + '#' + IntToStr(Ord(S[I]));
      Inc(I);
      if I - K >= LARGO_DE_LINEA then
        Corta := True;
    end;
    if Corta and (I <= L) then
    begin
      Result := Result + [Trozo + ' +'];
      Trozo := '';
      K := I;
    end;
  until I > L;
  Result := Result + [Trozo];
end;

function LineasDePropiedad(const ASangria, AProp: string; const ATrozos: TArray<string>): TArray<string>;
begin
  // el IDE escribe ' = ' y, si hay varios trozos, salta de linea: la de la
  // propiedad acaba en blanco
  Result := [ASangria + AProp + ' = '];
  if Length(ATrozos) = 1 then
    Result[0] := Result[0] + ATrozos[0];
  if Length(ATrozos) <= 1 then
    Exit;
  for var T in ATrozos do
    Result := Result + [ASangria + '  ' + T];
end;

function LeeLiteralDeForm(const AValor: string; out ATexto: string): Boolean;
var
  S, Codigo: string;
  I, N, J, V: Integer;

  procedure Blancos;
  begin
    while (I <= N) and CharInSet(S[I], [' ', #9]) do
      Inc(I);
  end;

  // tramos entre comillas y #N pegados, sin nada entre ellos: UN token del
  // TParser
  function Pieza: Boolean;
  begin
    Result := False;
    while (I <= N) and CharInSet(S[I], ['''', '#']) do
    begin
      if S[I] = '''' then
      begin
        Inc(I);
        while True do
        begin
          if I > N then
            Exit(False); // sin cerrar
          if S[I] = '''' then
          begin
            if (I < N) and (S[I + 1] = '''') then
            begin
              ATexto := ATexto + '''';
              Inc(I, 2);
              Continue;
            end;
            Inc(I);
            Break;
          end;
          ATexto := ATexto + S[I];
          Inc(I);
        end;
      end
      else
      begin
        Inc(I);
        J := I;
        if (I <= N) and (S[I] = '$') then
        begin
          Inc(I);
          while (I <= N) and CharInSet(S[I], ['0'..'9', 'A'..'F', 'a'..'f']) do
            Inc(I);
        end
        else
          while (I <= N) and CharInSet(S[I], ['0'..'9']) do
            Inc(I);
        Codigo := Copy(S, J, I - J);
        if not TryStrToInt(Codigo, V) or (V < 0) or (V > $FFFF) then
          Exit(False);
        ATexto := ATexto + Char(V);
      end;
      Result := True;
    end;
  end;

begin
  ATexto := '';
  S := AValor.Trim;
  N := Length(S);
  I := 1;
  if not Pieza then
    Exit(False);
  // y trozos unidos con '+', que el TParser une (CombineString)
  while True do
  begin
    Blancos;
    if I > N then
      Exit(True);
    if S[I] <> '+' then
      Exit(False);
    Inc(I);
    Blancos;
    if not Pieza then
      Exit(False);
  end;
end;

function EsLiteralDeForm(const AValor: string): Boolean;
var
  T: string;
begin
  Result := LeeLiteralDeForm(AValor, T);
end;

function NombreDeValor(const AValor: string): string;
var
  T: string;
begin
  Result := AValor.Trim;
  if LeeLiteralDeForm(Result, T) then
    Result := T;
end;

function EsCaracterDeForm(const AValor: string): Boolean;
var
  T: string;
begin
  Result := LeeLiteralDeForm(AValor, T) and (Length(T) = 1);
end;

function EsNumeroDeForm(const AValor: string): Boolean;
begin
  Result := TRegEx.IsMatch(AValor.Trim,
    // el signo solo delante de los digitos: TParser.NextToken (ctDash) no lee
    // -$FF (segunda revision de la 1.17.0)
    '^(?:\$[0-9A-Fa-f]+|-?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?)$');
end;

function EsEnteroDeForm(const AValor: string): Boolean;
begin
  Result := TRegEx.IsMatch(AValor.Trim, '^(?:-?\d+|\$[0-9A-Fa-f]+)$');
end;

// una linea que sigue una cadena: un trozo empieza por comilla o por #
function EsTrozoDeCadena(const ALinea: string): Boolean;
var
  T: string;
begin
  T := ALinea.TrimLeft;
  Result := T.StartsWith('''') or T.StartsWith('#');
end;

{ La ultima linea (0-based) del valor que empieza en la linea AIni con el
  texto AValor (lo de detras del '='): una lista entre parentesis, un bloque
  binario entre llaves, una cadena partida en trozos que acaban en '+' - o
  la larga que el IDE empieza en la linea de debajo, con la de la propiedad
  en blanco. Una coleccion la lleva LineasDeForm, que ve sus items. }
function FinDeValor(const ALineas: TArray<string>; AIni: Integer; const AValor: string): Integer;
var
  T, Cierre: string;
  Tope: Integer;
begin
  Result := AIni;
  Tope := High(ALineas);
  if (AValor = '(') or ((AValor <> '') and (AValor[1] = '{') and not AValor.EndsWith('}')) then
  begin
    Cierre := IfThen(AValor = '(', ')', '}');
    while Result < Tope do
    begin
      // uno sin cerrar no se lleva el end de su objeto
      if SameText(ALineas[Result + 1].Trim, 'end') then
        Exit;
      Inc(Result);
      if ALineas[Result].Trim.EndsWith(Cierre) then
        Exit;
    end;
    Exit;
  end;
  T := AValor;
  if T = '' then
  begin
    if (Result >= Tope) or not EsTrozoDeCadena(ALineas[Result + 1]) then
      Exit;
    Inc(Result);
    T := ALineas[Result].Trim;
  end;
  while T.EndsWith('+') and (Result < Tope) and EsTrozoDeCadena(ALineas[Result + 1]) do
  begin
    Inc(Result);
    T := ALineas[Result].Trim;
  end;
end;

function LineaDePropiedad(const ALinea: string; out AProp, AValor: string): Boolean;
var
  M: TMatch;
begin
  AProp := '';
  AValor := '';
  M := TRegEx.Match(ALinea.Trim, '^(' + PATRON_IDENT_PUNTOS + ')\s*=\s*(.*)$');
  Result := M.Success;
  if Result then
  begin
    AProp := M.Groups[1].Value;
    AValor := M.Groups[2].Value.Trim;
  end;
end;

function LineasDeForm(const ALineas: TArray<string>): TArray<TLineaForm>;
var
  I, K, Fin: Integer;
  T: string;
  Pila: TStack<Integer>; // la linea de la propiedad de cada coleccion abierta
  R: TLineaForm;
begin
  SetLength(Result, Length(ALineas));
  Pila := TStack<Integer>.Create;
  try
    I := 0;
    while I <= High(ALineas) do
    begin
      T := ALineas[I].Trim;
      R := Default(TLineaForm);
      R.Coleccion := Pila.Count;
      R.Fin := I;
      if T = '' then
        R.Clase := clfOtra
      else if Pila.Count > 0 then
      begin
        // dentro de una coleccion: 'item' (o 'item [2]'), sus propiedades,
        // 'end' y, el ultimo, 'end>', que la cierra
        if TRegEx.IsMatch(T, '^item(?:\s*\[[^\]]*\])?$', [roIgnoreCase]) then
          R.Clase := clfItem
        else if SameText(T, 'end') then
          R.Clase := clfFinItem
        else if SameText(T, 'end>') then
        begin
          R.Clase := clfFinItem;
          Result[Pila.Pop].Fin := I;
        end
        else if LineaDePropiedad(T, R.Prop, R.Valor) then
          R.Clase := clfPropiedad;
      end
      else if LineaDeObjeto(T, R.Clave, R.Nombre, R.ClaseObj) then
        R.Clase := clfObjeto
      else if SameText(T, 'end') then
        R.Clase := clfFin
      else if LineaDePropiedad(T, R.Prop, R.Valor) then
        R.Clase := clfPropiedad;
      Result[I] := R;
      if R.Clase = clfPropiedad then
        if R.Valor = '<' then
          Pila.Push(I) // su Fin, en su '>'
        else if R.Valor <> '<>' then
        begin
          Fin := FinDeValor(ALineas, I, R.Valor);
          Result[I].Fin := Fin;
          for K := I + 1 to Fin do
          begin
            Result[K] := Default(TLineaForm);
            Result[K].Clase := clfValor;
            Result[K].Coleccion := Pila.Count;
            Result[K].Fin := K;
          end;
          I := Fin;
        end;
      Inc(I);
    end;
  finally
    Pila.Free;
  end;
end;

function ValorEnteroDe(const ALineas: TArray<string>; const AForm: TArray<TLineaForm>;
  AIni: Integer): string;
begin
  Result := AForm[AIni].Valor;
  // solo una cadena partida: lo demas de varias lineas se queda en su marca
  if (AForm[AIni].Fin = AIni) or ((Result <> '') and not Result.EndsWith('+')) then
    Exit;
  for var K := AIni + 1 to AForm[AIni].Fin do
    Result := Trim(Result + ' ' + ALineas[K].Trim);
end;

function EsValorDeBloque(const AValor: string): Boolean;
begin
  Result := (AValor <> '') and CharInSet(AValor[1], ['(', '<', '{']);
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
  // bajo el decimal 18 se redondea EN el: de 5E-19 sale el ultimo
  // (0.000000000000000001), y de menos, cero y sin signo (lo decia el
  // revisor de la 1.17.0 leyendo la RTL de 32 bits: aqui salia cero)
  if N < 0 then
    Exit('0.' + StringOfChar('0', 18));
  RedondeaCifras(Digitos, X, N);
  if Digitos = '' then
    Exit('0.' + StringOfChar('0', 18));
  // con mas de 16 cifras enteras FloatToStrF pasa a la forma general:
  // 1E20, 1.000000020040877E20
  if X > 16 then
  begin
    while (Length(Digitos) > 1) and (Digitos[Length(Digitos)] = '0') do
      Delete(Digitos, Length(Digitos), 1);
    Result := Digitos[1];
    if Length(Digitos) > 1 then
      Result := Result + '.' + Copy(Digitos, 2, MaxInt);
    Result := Result + 'E' + IntToStr(X - 1);
    if V < 0 then
      Result := '-' + Result;
    Exit;
  end;
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

function NombreQueElFicheroNoLee(const ANombre, ADfm, ADfmEnc, APas, APasEnc: string): string;
var
  Ascii: Boolean;
begin
  Result := '';
  Ascii := True;
  for var C in ANombre do
    if Ord(C) > 127 then
      Ascii := False;
  if Ascii then
    Exit;
  if EncKindOf(ADfmEnc) <> ekUtf8Bom then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_SIN_BOM_FMT, [ANombre, ExtractFileName(ADfm),
      MsgText(SF_DESIGNER_SIN_BOM_FORM)]));
  if EncKindOf(APasEnc) = ekUtf8 then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_SIN_BOM_FMT, [ANombre, ExtractFileName(APas),
      MsgText(SF_DESIGNER_SIN_BOM_UNIDAD)]));
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
begin
  Result := '';
  AText := '';
  if DesignerShapeOf(ABytes) = dsText then
    Exit(MsgText(SR_DSGN_NO_ES_DESIGNER_BINARIO));
  // EL conversor de la casa (Lsp.DesignerForma), el del renderizador tambien;
  // aqui, sus mensajes
  try
    AText := DesignerBinarioATexto(ABytes);
  except
    on E: Exception do
      Exit(MsgFmt(SR_DSGN_BINARIO_DANADO_FMT, [E.ClassName, E.Message]));
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
