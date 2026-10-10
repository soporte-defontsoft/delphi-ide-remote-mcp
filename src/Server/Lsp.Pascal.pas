unit Lsp.Pascal;

{ EL LEXICO PASCAL de la casa: que es codigo, que es cadena, que es comentario
  y que es directiva en un texto Pascal. Todo lo que lee texto Pascal se lo
  pregunta a esta unidad y no lleva su propia regla.

  La regla, entera:
  - un // fuera de una cadena y de otro comentario comenta hasta el final de
    su linea, haya lo que haya detras (una llave, una comilla, una directiva);
  - una llave abre un comentario hasta la PRIMERA llave que cierra (no se
    anidan), y parentesis-asterisco hasta el primer asterisco-parentesis; los
    dos son una directiva si lo primero de dentro es un dolar;
  - una comilla abre una cadena hasta la comilla que la cierra en la MISMA
    linea (dos seguidas son una comilla dentro): una cadena no pasa de su
    linea, y la que no se cierra acaba ahi, como para el compilador;
  - tres o mas comillas (en numero impar) con el salto de linea JUSTO detras
    abren una cadena de varias lineas (Delphi 12), que acaba en la primera
    linea que empieza por las mismas comillas; con un blanco detras no la
    abren, que dcc dice E2052 (cadena sin cerrar; medido en la revision de
    la 1.10.0);
  - dentro de un comentario o de una cadena no hay nada mas: ni otro
    comentario, ni una cadena, ni una directiva.

  Por que una unidad: el 2-oct-2026 el censo por lo que HACE el codigo dio una
  docena de lectores de texto Pascal, cada uno con su trozo de la regla, y una
  sonda midio nueve fallos en cuatro tools: adduses caia con un indice fuera de
  rango tras un comentario de llave con 'https://' dentro, un rename dejaba
  sin renombrar la referencia que iba detras de un comentario de llave con un
  apostrofo, INSERT negaba una firma con 'http://' en un valor por defecto y
  otra con un parentesis en un comentario, un end.
  comentado negaba INSERT, y dos escrituras caian DENTRO de un comentario
  diciendo que se habian hecho (INSERT en un .dpr, add-unit), y el digest
  listaba una declaracion comentada y perdia otra. Antes, el 27-sep, cuatro
  lectores de directivas con su regex veian las comentadas. Y dos revisores,
  antes del tag, los sitios que el censo no vio: el CreateForm de un .dpr,
  la directiva de detras de una entrada, lo que se escribe detras de una
  linea que abre un comentario, el rename de un simbolo.
  David: "El paisaje querido, el paisaje, es la parte mas importante de la
  programacion sana". }

interface

type
  // Lo que es cada caracter de un texto Pascal. cpComentario es el de llave
  // o de parentesis-asterisco; cpLinea, el de //.
  TClasePascal = (cpCodigo, cpCadena, cpComentario, cpLinea, cpDirectiva);
  TClasesPascal = set of TClasePascal;

  // Una directiva de compilacion DE VERDAD de un texto Pascal, en sus dos
  // formas (llave-dolar y parentesis-asterisco-dolar): nunca la que va dentro
  // de un comentario (llaves, parentesis-asterisco o //) ni de una cadena.
  TDirectivaPascal = record
    Nombre: string;         // en mayusculas: I, INCLUDE, IFDEF, APPTYPE...
    Argumento: string;      // lo que va detras del nombre, tal cual
    Inicio, Largo: Integer; // la directiva entera en el texto (1-based)
    InicioArg: Integer;     // donde empieza Argumento en el texto
  end;

// Largo del comentario o directiva que empieza en S[I] (0 si no empieza uno)
function CommentLen(const S: string; I: Integer): Integer;
// Largo de la cadena que empieza en S[I] (0 si no empieza una)
function QuoteLen(const S: string; I: Integer): Integer;

// El salto de linea que de verdad ACABA la linea en la que esta APos: el
// primero desde APos que es codigo. Uno de dentro de un comentario de bloque
// o de una cadena de varias lineas que se abrio en ella no la acaba, y lo
// que se escribe "detras de la linea" caia ahi, DENTRO del comentario: un
// INSERT en un .dpr detras de 'System.SysUtils; { las units', un uses creado
// detras de 'interface { la parte' (revision de la 1.10.0, medido).
// Length(ATexto) + 1 si no hay ninguno.
function FinDeLinea(const ATexto: string; APos: Integer): Integer;
// Lo mismo por lineas (sin sus saltos): la linea donde acaba la ALinea
// (0-based) de ALineas.
function LineaQueCierra(const ALineas: TArray<string>; ALinea: Integer): Integer;

// La clase de cada caracter de ATexto: Result[I] es la de ATexto[I] (1-based;
// Result[0] no se usa). EL recorrido: lo demas de esta unidad sale de aqui.
function ClasesPascal(const ATexto: string): TArray<TClasePascal>;

// ATexto con lo que NO es de AConserva en blancos: el mismo largo y los
// saltos en su sitio, asi que una posicion o un numero de linea de la vista
// vale en el texto. [cpCodigo] = solo el codigo; [cpCadena] = solo las cadenas.
function VistaPascal(const ATexto: string; AConserva: TClasesPascal): string;

// El codigo y las cadenas; comentarios y directivas, en blanco (la vista de
// los que buscan codigo sin leer el comentado: un StyleLookup mencionado en
// un comentario fue un "hallazgo" del lint, 2026-08-23)
function BlankComments(const S: string): string;

// El CODIGO solo: cadenas, comentarios y directivas en blanco. La vista de
// los que buscan estructura (end., uses, program, una clase, una firma, el
// ';' que la cierra): un end. comentado negaba INSERT, y un 'program viejo;
// uses X;' comentado se tomaba por la cabecera (sonda del 2-oct-2026)
function CodigoPascal(const S: string): string;

// Donde empieza, 1-based en su linea, el comentario // de cada una de
// ALineas (0 si no lleva), con el estado que traen las de antes: un // dentro
// de una llave o de una cadena no es un comentario de linea. Las lineas, sin
// sus saltos.
function ComentariosDeLinea(const ALineas: TArray<string>): TArray<Integer>;

// LAS directivas reales de ATexto, en orden: el UNICO lector de directivas
// (las de fichero I/R/L de la mudanza y de la puerta del build, los
// condicionales de un uses partido en ramas, el detector de tests, lo que una
// entrada quitada de un uses deja detras). Cuatro lectores con su regex sobre
// el texto crudo veian una directiva COMENTADA -tambien con //- o dentro de
// una cadena, y no la forma parentesis-asterisco (revision del 27-sep-2026,
// David: "incluso //").
function DirectivasPascal(const ATexto: string): TArray<TDirectivaPascal>;

// Las lineas (1-based) de ATexto donde empieza un comentario de LLAVE que
// lleva otra llave abierta dentro. Pascal no anida llaves: el primer cierre
// acaba el comentario y lo que sigue es codigo, o una directiva de verdad
// si citaba una de llave-dolar (la trampa en la que se cayo cuatro veces
// entre el 25 y el 27-sep-2026). Solo lo mira; quien lo usa decide. AFines:
// la linea de cada uno donde lo cierra la primera llave de cierre (la que
// toma dcc), para saber si TOCA unas lineas dadas: un comentario abierto en
// otra linea no se ve mirando solo el texto nuevo (medido el 9-oct-2026).
function LlavesAnidadas(const ATexto: string; out AFines: TArray<Integer>): TArray<Integer>;

// UN IDENTIFICADOR Pascal, como lo lee dcc: una letra ASCII, '_' o CUALQUIER
// caracter no ASCII del plano basico, y detras tambien los digitos. Medido el
// 4-oct-2026 compilando una funcion con cada clase de caracter: AñadirLinea,
// lblDirección, Col·lecció (el punto volado catalan), una marca combinante,
// un numeral romano, Precio€, Marca©, un espacio duro y hasta un BOM dentro
// del nombre compilan, tambien al principio; una letra fuera del plano basico
// (un par sustituto) no (E2038). La primera version de esta regla fue \p{L}
// y no se habia medido: el punto volado partia el nombre en dos. El TRegEx
// del RTL compila sin PCRE_UCP y su \w, su \b y [A-Za-z] solo ven ASCII
// (medido: '\w' no casa con 'ñ', '\bÚltimo\b' no casa en ' Último '). Nadie
// escribe su propio patron ni su propio bucle de identificador: se compone
// con estos (censo del 4-oct: una sesentena de regex con \w ASCII y tres
// clasificadores de caracter, cada uno con su regla, en catorce unidades).
const
  // un caracter de dentro: el \w de un identificador (los sustitutos fuera)
  PATRON_CAR_IDENT = '[A-Za-z0-9_\x{80}-\x{D7FF}\x{E000}-\x{FFFF}]';
  PATRON_LETRA_IDENT = '[A-Za-z_\x{80}-\x{D7FF}\x{E000}-\x{FFFF}]'; // el primero: sin digitos
  PATRON_IDENT = PATRON_LETRA_IDENT + PATRON_CAR_IDENT + '*';
  // varios unidos por puntos: Vcl.Forms, Font.Name, TForm1.Button1Click
  PATRON_IDENT_PUNTOS = PATRON_IDENT + '(?:\.' + PATRON_IDENT + ')*';
  // el \b de delante y el de detras de un identificador
  PATRON_NO_IDENT_ANTES = '(?<!' + PATRON_CAR_IDENT + ')';
  PATRON_NO_IDENT_DESPUES = '(?!' + PATRON_CAR_IDENT + ')';
  // el nombre de un TIPO por la convencion de Delphi: T y una mayuscula (con
  // T[A-Za-z_] entraban True o TextHeight)
  PATRON_NOMBRE_TIPO = 'T\p{Lu}';
  // LAS palabras que abren la cabecera de una rutina: las de una clase o
  // global, y operator (el de un record). Y las directivas que pueden ir
  // detras de su firma (virtual; overload; message WM_X;...; no las del
  // compilador, {$...}, que son DirectivasPascal). Las palabras estaban
  // escritas a mano en once sitios, unos con operator y otros sin el, y las
  // directivas dos veces con listas distintas: la de insert=metodo no conocia
  // noreturn ni unsafe (censo del 4-oct-2026). Su patron: PatronPalabraDeRutina
  PALABRAS_DE_RUTINA: array [0 .. 4] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator');
  DIRECTIVAS_DE_RUTINA: array [0 .. 30] of string = ('virtual', 'override',
    'overload', 'reintroduce', 'abstract', 'dynamic', 'static', 'inline',
    'final', 'message', 'stdcall', 'cdecl', 'safecall', 'register', 'pascal',
    'winapi', 'deprecated', 'platform', 'experimental', 'library', 'dispid',
    'varargs', 'export', 'far', 'near', 'assembler', 'unsafe', 'forward',
    'external', 'local', 'noreturn');

// PALABRAS_DE_RUTINA como patron, sin grupo: (?:procedure|function|...)
function PatronPalabraDeRutina: string;

// La misma regla caracter a caracter, para los que recorren un texto: el
// primero (letra ASCII, '_' o no ASCII) y los demas (tambien un digito)
function EsLetraDeIdent(C: Char): Boolean;
function EsCaracterDeIdent(C: Char): Boolean;
// S entero es UN identificador; con APuntos, uno o varios unidos por puntos
// (el nombre de una unit con su espacio de nombres)
function EsIdentificador(const S: string; APuntos: Boolean = False): Boolean;
// El patron de AIdent como PALABRA entera, escapado: ni delante ni detras
// puede seguir el identificador. Es el '\b' + Escape + '\b' de antes, que no
// casaba con un acento al principio o al final del nombre.
function PatronIdentEntero(const AIdent: string): string;
// El ultimo trozo de un nombre con puntos (Vcl.Forms.TForm -> TForm): el
// lector de PATRON_IDENT_PUNTOS. Estaba dos veces con este cuerpo y en linea
// en otros siete sitios (revision de paisaje del 4-oct-2026)
function UltimoTrozo(const ANombre: string): string;
// Una palabra reservada de Delphi (begin, unit, string...): no vale de
// identificador ni de nombre de unit. La lista estaba dos veces
function EsPalabraReservada(const S: string): Boolean;
// Los dos son el MISMO identificador. Pascal no distingue mayusculas, y dcc
// tampoco en las letras acentuadas (medido el 4-oct-2026: 'uses UaRBOL' con
// su a acentuada compila contra 'unit UArbol' con su A acentuada, y TAMANO
// en mayusculas llama a Tamano); SameText, CompareText y LowerCase solo
// pliegan A-Z. Para nombres de unit, de clase, de metodo: esta.
function MismoIdentificador(const A, B: string): Boolean;
// La CLAVE de un identificador para un diccionario o un conjunto: dos tienen
// la misma clave si son el mismo (MismoIdentificador es su lector)
function ClaveDeIdentificador(const S: string): string;
// La distancia de edicion (Levenshtein) entre dos textos, tal cual: quien la
// quiera sin mayusculas los pliega antes. Vivia dentro de delphi_help (el
// nombre de una tool casi bien escrito); delphi_designer set es su segundo
// usuario (la propiedad casi bien escrita, 1.17.0)
function EditDistance(const A, B: string): Integer;
// El candidato MAS parecido a A, sin mayusculas: el UNICO a la menor
// distancia, si esa distancia no pasa de ATope; '' si no lo hay (empate,
// demasiado lejos, o A ya esta entre ellos)
function ElMasParecido(const A: string; const ACandidatos: array of string;
  ATope: Integer): string;
// La linea (1-based) de la posicion APos (1-based) de ATexto: un salto es
// CRLF, LF o un CR suelto, como en el troceador (Lsp.Patch.SplitToLines).
// Estaba a mano en LlavesAnidadas; el analizador de impacto de
// delphi_designer (los usos de un componente en su unidad) es el segundo
function LineaDePosicion(const ATexto: string; APos: Integer): Integer;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Character,
  System.RegularExpressions;

function PatronPalabraDeRutina: string;
begin
  Result := '(?:' + string.Join('|', PALABRAS_DE_RUTINA) + ')';
end;

function EsLetraDeIdent(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or ((Ord(C) >= $80) and not C.IsSurrogate);
end;

function EsCaracterDeIdent(C: Char): Boolean;
begin
  Result := EsLetraDeIdent(C) or CharInSet(C, ['0'..'9']);
end;

function EsIdentificador(const S: string; APuntos: Boolean): Boolean;
begin
  // \A y \z, no ^ y $: el $ de PCRE casa tambien delante de un salto final
  if APuntos then
    Result := TRegEx.IsMatch(S, '\A' + PATRON_IDENT_PUNTOS + '\z')
  else
    Result := TRegEx.IsMatch(S, '\A' + PATRON_IDENT + '\z');
end;

function PatronIdentEntero(const AIdent: string): string;
begin
  Result := PATRON_NO_IDENT_ANTES + TRegEx.Escape(AIdent) + PATRON_NO_IDENT_DESPUES;
end;

function UltimoTrozo(const ANombre: string): string;
begin
  Result := ANombre;
  if Result.LastIndexOf('.') >= 0 then
    Result := Result.Substring(Result.LastIndexOf('.') + 1);
end;

function ClaveDeIdentificador(const S: string): string;
begin
  // en minusculas e invariante (sin el idioma del usuario: con el turco, la I
  // no plegaba a i): en ASCII da lo mismo que LowerCase, y las claves que ya
  // estaban escritas en minusculas (las tablas del disenador) no cambian
  Result := S.ToLowerInvariant;
end;

function EditDistance(const A, B: string): Integer;
var
  I, J, Cost, Prev, Cur: Integer;
  Row: TArray<Integer>;
begin
  if A = B then
    Exit(0);
  if (A = '') or (B = '') then
    Exit(Max(Length(A), Length(B)));
  SetLength(Row, Length(B) + 1);
  for J := 0 to Length(B) do
    Row[J] := J;
  for I := 1 to Length(A) do
  begin
    Prev := Row[0];
    Row[0] := I;
    for J := 1 to Length(B) do
    begin
      Cost := IfThen(A[I] = B[J], 0, 1);
      Cur := Row[J];
      Row[J] := Min(Min(Row[J] + 1, Row[J - 1] + 1), Prev + Cost);
      Prev := Cur;
    end;
  end;
  Result := Row[Length(B)];
end;

function ElMasParecido(const A: string; const ACandidatos: array of string;
  ATope: Integer): string;
var
  Mejor, Empates, D: Integer;
begin
  Result := '';
  Mejor := MaxInt;
  Empates := 0;
  for var C in ACandidatos do
  begin
    D := EditDistance(ClaveDeIdentificador(A), ClaveDeIdentificador(C));
    if D < Mejor then
    begin
      Mejor := D;
      Result := C;
      Empates := 0;
    end
    else if (D = Mejor) and not MismoIdentificador(C, Result) then
      Inc(Empates);
  end;
  if (Mejor = 0) or (Mejor > ATope) or (Empates > 0) then
    Result := '';
end;

function MismoIdentificador(const A, B: string): Boolean;
begin
  Result := (Length(A) = Length(B)) and (ClaveDeIdentificador(A) = ClaveDeIdentificador(B));
end;

function EsPalabraReservada(const S: string): Boolean;
const
  RESERVADAS: array [0 .. 64] of string = ('and', 'array', 'as', 'asm', 'begin',
    'case', 'class', 'const', 'constructor', 'destructor', 'dispinterface',
    'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline',
    'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object',
    'of', 'or', 'out', 'packed', 'procedure', 'program', 'property',
    'raise', 'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr',
    'string', 'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until',
    'uses', 'var', 'while', 'with', 'xor');
begin
  Result := False;
  for var W in RESERVADAS do
    if SameText(S, W) then
      Exit(True);
end;

function CommentLen(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if I > Length(S) then
    Exit;
  if (S[I] = '/') and (I < Length(S)) and (S[I + 1] = '/') then
  begin
    J := I;
    while (J <= Length(S)) and (S[J] <> #10) and (S[J] <> #13) do
      Inc(J);
    Exit(J - I);
  end;
  if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = '*') then
  begin
    J := Pos('*)', S, I + 2);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 2 - I);
  end;
  if S[I] = '{' then
  begin
    J := Pos('}', S, I + 1);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 1 - I);
  end;
end;

function QuoteLen(const S: string; I: Integer): Integer;
var
  J, K, N: Integer;
  Cierre: string;
begin
  Result := 0;
  if (I > Length(S)) or (S[I] <> '''') then
    Exit;
  // tres o mas comillas, en numero impar, y el salto JUSTO detras: la cadena
  // de varias lineas, hasta la linea que empieza por las mismas. Con un
  // blanco detras es una de una linea, la de '' y lo que siga: dcc dice
  // E2052 (revision de la 1.10.0: el lexico la abria y escondia a quien lo
  // mira las lineas que el compilador lee como codigo)
  N := 0;
  while (I + N <= Length(S)) and (S[I + N] = '''') do
    Inc(N);
  if (N >= 3) and Odd(N) then
  begin
    J := I + N;
    if (J > Length(S)) or CharInSet(S[J], [#10, #13]) then
    begin
      Cierre := StringOfChar('''', N);
      while J <= Length(S) do
      begin
        while (J <= Length(S)) and CharInSet(S[J], [#10, #13]) do
          Inc(J);
        K := J;
        while (K <= Length(S)) and CharInSet(S[K], [' ', #9]) do
          Inc(K);
        if Copy(S, K, N) = Cierre then
          Exit(K + N - I);
        while (J <= Length(S)) and not CharInSet(S[J], [#10, #13]) do
          Inc(J);
      end;
      Exit(Length(S) - I + 1);
    end;
  end;
  J := I + 1;
  while J <= Length(S) do
  begin
    if S[J] = '''' then
    begin
      if (J < Length(S)) and (S[J + 1] = '''') then
        Inc(J, 2)
      else
        Exit(J + 1 - I);
    end
    else if CharInSet(S[J], [#10, #13]) then
      Exit(J - I) // una cadena no pasa de su linea
    else
      Inc(J);
  end;
  Result := Length(S) - I + 1;
end;

function ClasesPascal(const ATexto: string): TArray<TClasePascal>;
var
  I, N: Integer;
  Clase: TClasePascal;
begin
  SetLength(Result, Length(ATexto) + 1);
  Result[0] := cpCodigo;
  I := 1;
  while I <= Length(ATexto) do
  begin
    N := QuoteLen(ATexto, I);
    if N > 0 then
      Clase := cpCadena
    else
    begin
      N := CommentLen(ATexto, I);
      if N = 0 then
      begin
        Result[I] := cpCodigo;
        Inc(I);
        Continue;
      end;
      if ATexto[I] = '/' then
        Clase := cpLinea
      else if ((ATexto[I] = '{') and (I < Length(ATexto)) and (ATexto[I + 1] = '$')) or
              ((ATexto[I] = '(') and (I + 2 <= Length(ATexto)) and (ATexto[I + 2] = '$')) then
        Clase := cpDirectiva
      else
        Clase := cpComentario;
    end;
    for var K := I to I + N - 1 do
      Result[K] := Clase;
    Inc(I, N);
  end;
end;

function VistaPascal(const ATexto: string; AConserva: TClasesPascal): string;
var
  Clases: TArray<TClasePascal>;
begin
  Clases := ClasesPascal(ATexto);
  Result := ATexto;
  for var I := 1 to Length(Result) do
    if not (Clases[I] in AConserva) and not CharInSet(Result[I], [#10, #13]) then
      Result[I] := ' ';
end;

function BlankComments(const S: string): string;
begin
  Result := VistaPascal(S, [cpCodigo, cpCadena]);
end;

function CodigoPascal(const S: string): string;
begin
  Result := VistaPascal(S, [cpCodigo]);
end;

function ComentariosDeLinea(const ALineas: TArray<string>): TArray<Integer>;
var
  Clases: TArray<TClasePascal>;
  Ini: Integer;
begin
  SetLength(Result, Length(ALineas));
  Clases := ClasesPascal(string.Join(#10, ALineas));
  Ini := 1; // donde empieza la linea en el texto unido
  for var L := 0 to High(ALineas) do
  begin
    Result[L] := 0;
    for var K := 1 to Length(ALineas[L]) do
      if Clases[Ini + K - 1] = cpLinea then
      begin
        Result[L] := K;
        Break;
      end;
    Inc(Ini, Length(ALineas[L]) + 1);
  end;
end;

function DirectivasPascal(const ATexto: string): TArray<TDirectivaPascal>;
var
  I, N, P, Q, Fin: Integer;
  D: TDirectivaPascal;
begin
  Result := [];
  I := 1;
  while I <= Length(ATexto) do
  begin
    N := QuoteLen(ATexto, I);
    if N > 0 then
    begin
      Inc(I, N); // una cadena: nada de dentro es una directiva
      Continue;
    end;
    N := CommentLen(ATexto, I);
    if N = 0 then
    begin
      Inc(I);
      Continue;
    end;
    // un comentario de llave o de parentesis-asterisco que empieza por $ es
    // una directiva; uno de // nunca lo es, y lo de dentro de un comentario
    // tampoco
    P := 0;
    if (ATexto[I] = '{') and (I < Length(ATexto)) and (ATexto[I + 1] = '$') then
      P := I + 2
    else if (ATexto[I] = '(') and (I + 2 <= Length(ATexto)) and (ATexto[I + 2] = '$') then
      P := I + 3;
    if P > 0 then
    begin
      Q := P;
      while (Q <= Length(ATexto)) and
            CharInSet(ATexto[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Q);
      // el contenido acaba antes del cierre: la llave, o el '*' de '*)'; sin
      // cerrar, hasta el final (la de parentesis-asterisco sin cerrar perdia
      // su ultimo caracter; revision de la 1.10.0)
      Fin := I + N - 1;
      if ATexto[I] = '(' then
      begin
        if (N >= 5) and (Copy(ATexto, Fin - 1, 2) = '*)') then
          Dec(Fin)
        else
          Inc(Fin);
      end
      else if ATexto[Fin] <> '}' then
        Inc(Fin);
      D.Nombre := UpperCase(Copy(ATexto, P, Q - P));
      D.InicioArg := Q;
      D.Argumento := Copy(ATexto, Q, Fin - Q);
      D.Inicio := I;
      D.Largo := N;
      Result := Result + [D];
    end;
    Inc(I, N);
  end;
end;

function FinDeLinea(const ATexto: string; APos: Integer): Integer;
var
  Clases: TArray<TClasePascal>;
begin
  Clases := ClasesPascal(ATexto);
  Result := Max(APos, 1);
  while Result <= Length(ATexto) do
  begin
    if CharInSet(ATexto[Result], [#10, #13]) and (Clases[Result] = cpCodigo) then
      Exit;
    Inc(Result);
  end;
end;

function LineaQueCierra(const ALineas: TArray<string>; ALinea: Integer): Integer;
var
  Unido: string;
  Ini, Fin: Integer;
begin
  Result := ALinea;
  if (ALinea < 0) or (ALinea >= High(ALineas)) then
    Exit;
  Unido := string.Join(#10, ALineas);
  Ini := 1;
  for var L := 0 to ALinea - 1 do
    Inc(Ini, Length(ALineas[L]) + 1);
  Fin := FinDeLinea(Unido, Ini);
  for var K := Ini to Min(Fin, Length(Unido)) - 1 do
    if Unido[K] = #10 then
      Inc(Result);
end;

function LineaDePosicion(const ATexto: string; APos: Integer): Integer;
begin
  Result := 1;
  for var K := 1 to Min(APos, Length(ATexto) + 1) - 1 do
    if (ATexto[K] = #10) or ((ATexto[K] = #13) and ((K = Length(ATexto)) or (ATexto[K + 1] <> #10))) then
      Inc(Result);
end;

function LlavesAnidadas(const ATexto: string; out AFines: TArray<Integer>): TArray<Integer>;
var
  I, N, Dentro, Linea: Integer;
begin
  Result := [];
  AFines := [];
  I := 1;
  while I <= Length(ATexto) do
  begin
    N := QuoteLen(ATexto, I);
    if N = 0 then
      N := CommentLen(ATexto, I);
    if N = 0 then
    begin
      Inc(I);
      Continue;
    end;
    if ATexto[I] = '{' then
    begin
      // otra llave abierta ANTES del cierre de esta
      Dentro := Pos('{', ATexto, I + 1);
      if (Dentro > 0) and (Dentro < I + N - 1) then
      begin
        // un salto es CRLF, LF o un CR suelto, como en el troceador (contaba
        // solo los LF: un texto en CR daba la linea 1 a todo)
        Linea := LineaDePosicion(ATexto, I);
        Result := Result + [Linea];
        AFines := AFines + [LineaDePosicion(ATexto, I + N - 1)];
      end;
    end;
    Inc(I, N);
  end;
end;

end.
