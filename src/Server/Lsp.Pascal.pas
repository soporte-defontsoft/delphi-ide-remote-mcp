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
// entre el 25 y el 27-sep-2026). Solo lo mira; quien lo usa decide.
function LlavesAnidadas(const ATexto: string): TArray<Integer>;

implementation

uses
  System.SysUtils,
  System.Math;

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

function LlavesAnidadas(const ATexto: string): TArray<Integer>;
var
  I, N, Dentro, Linea: Integer;
begin
  Result := [];
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
        Linea := 1;
        for var K := 1 to I - 1 do
          if (ATexto[K] = #10) or ((ATexto[K] = #13) and (ATexto[K + 1] <> #10)) then
            Inc(Linea);
        Result := Result + [Linea];
      end;
    end;
    Inc(I, N);
  end;
end;

end.
