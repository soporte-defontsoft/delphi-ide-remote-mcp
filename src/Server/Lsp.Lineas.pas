unit Lsp.Lineas;

{ Las LINEAS de un texto y sus SALTOS, sin ficheros: partirlas y volverlas a
  unir byte a byte, el salto dominante y el que pide un create, la sangria, y
  cambiar unas lineas sin reescribir las demas. Vivian en Lsp.Patch, mezcladas
  con la deteccion de codificacion, los lugares, la papelera y el motor de
  edicion (V94 de la depuracion de la 1.23, B6 de la 1.28): se mudaron sin
  cambiar una linea. }

interface

{ La sangria (espacios y tabuladores) del principio de S. }
function LeadingWhite(const S: string): string;
{ La sangria de la linea de ATexto en la que esta la posicion APos (1-based):
  solo el blanco del principio de esa linea. Para meter una etiqueta al lado
  de otra en un .dproj: BuildRunner y Config copiaban TODO lo que habia
  delante del ancla en su linea, y con dos etiquetas en una linea (un .dproj
  editado a mano) duplicaban la de delante (revisor de la 1.15.0). }
function SangriaDeLaLineaEn(const ATexto: string; APos: Integer): string;
{ LA regla de la sangria que el agente deja fuera del ancla, para delphi_edit
  y delphi_textedit (6-oct-2026: estaba escrita dos veces, de dos formas, y
  delphi_edit la duplicaba). Si el ancla (AAncla, tal como llego) trae menos
  sangria que la linea real (ALinea) y la primera linea de ANuevas no trae
  ninguna, todas las lineas con texto de ANuevas toman la de ALinea; si no,
  van tal cual: nunca se duplica. }
function SangraComoLaLinea(const ALinea, AAncla: string;
  const ANuevas: TArray<string>): TArray<string>;

{ Las LINEAS de un texto, como las cuenta delphi_read: los tres saltos
  (CRLF, LF, CR) son uno, y el salto final CIERRA la ultima linea, no abre
  otra ("a\nb\n" son 2; "" son 0). Estaba escrito cuatro veces con dos
  condiciones distintas, y vault_read y LSP-004 no lo aplicaban: la nota de
  5 lineas salia de 6, y el LSP decia 21 donde delphi_read decia 20
  (sexta revision). CuantasLineasReales es la misma regla para quien
  necesita conservar la fantasma (para volver a unir el texto). }
function LineasDelTexto(const AText: string): TArray<string>;
function CuantasLineasReales(const ALines: TArray<string>): Integer;

{ El salto de linea DOMINANTE de un texto (CRLF, LF o CR suelto: el que mas
  aparece; CRLF si no hay ninguno, el de Windows), para quien vuelve a unir
  lineas. UNO: estaba en Lsp.TextEdit (DominantEol) y escrito a mano en otros
  ocho sitios como "CRLF si hay alguno", que no veia un CR suelto (septima
  revision). }
function SaltoDominante(const AText: string): string;
{ Las lineas de un texto CON la fantasma del salto final (un CR suelto es
  salto): para quien vuelve a unir el texto con su salto. LineasDelTexto es
  esta sin la fantasma. UN troceador: habia cinco a mano que no veian el CR
  suelto (octava revision). }
function SplitToLines(const T: string): TArray<string>;
{ Las mismas lineas que SplitToLines, y en ASaltos el salto con que acaba
  CADA una ('' la ultima): para quien reescribe unas lineas y tiene que
  dejar las demas byte a byte, un fichero mixto tambien. UneConSusSaltos
  es su inversa. El renombrado de una unit troceaba solo por LF: un
  fichero de CR sueltos era UNA linea y no se reescribia (novena revision). }
function SplitToLinesConSalto(const T: string; out ASaltos: TArray<string>): TArray<string>;
function UneConSusSaltos(const ALineas, ASaltos: TArray<string>): string;
{ ATexto con ACuantas lineas desde ALinea (0-based, las de SplitToLines)
  cambiadas por ANuevas, y cada linea de fuera BYTE A BYTE, con su salto: una
  edicion no reescribe lo que no toca (1.18.2; medido el 10-oct-2026: textedit
  dejaba en CRLF una linea LF que no habia tocado, y asi los siete que unian
  todas las lineas con el salto dominante). Los saltos de ANuevas son ASalto
  (el dominante: es texto que se escribe), y la ultima se queda el salto con
  que acababa la ultima que se va. ANuevas vacio: las lineas se van con su
  salto (las ultimas de un texto sin salto final, con el de delante: sigue sin
  el). ACuantas = 0: ANuevas entran delante de ALinea. Lo que el tramo deja
  IGUAL al principio y al final no se toca. UN compositor para
  todo el que cambia lineas de un texto que ya existe. }
function CambiaLineasEnSuTexto(const ATexto: string; ALinea, ACuantas: Integer;
  const ANuevas: TArray<string>; const ASalto: string): string;
{ Lo mismo para un TRAMO de la vista en LF de ATexto (la de ConSalto(ATexto,
  #10): un salto, CRLF, LF o CR suelto, es un caracter): desde ADesde (0-based)
  ALargo caracteres cambiados por ANuevo (en LF). Las lineas que toca el tramo
  se reescriben enteras por CambiaLineasEnSuTexto; las demas, byte a byte. Para
  quien cambia un trozo y no lineas (vault_patch, vault_append). }
function EmpalmaEnSuTexto(const ATexto: string; ADesde, ALargo: Integer;
  const ANuevo, ASalto: string): string;
{ Que linea de AAntes es cada una de ADespues en el cambio mas corto (Myers,
  por contenido; lo igual delante y detras, sin buscar): su indice, o -1 si
  es nueva. Para quien recibe el texto ENTERO que compuso un escritor y tiene
  que saber que se quedo. Con mas de 1000 cambios en medio, el medio entero
  sale nuevo: eso ya es reescribir. }
function LineasQueSeQuedan(const AAntes, ADespues: TArray<string>): TArray<Integer>;
{ ANuevo, el texto ENTERO que un escritor compuso sobre AAntes, con la regla
  de quien cambia lineas: cada tramo que cambia (LineasQueSeQuedan), por
  CambiaLineasEnSuTexto con el salto dominante de AAntes; lo que se queda,
  byte a byte, y el final como lo deja ANuevo. Para PatchSaveConSuSalto, que
  pasaba lo nuevo al dominante solo si el fichero no tenia NINGUN CRLF: en
  uno mixto, un bloque insertado con sLineBreak dejaba en CRLF la linea LF de
  delante (V35 de la 1.23, medido el 24-oct-2026). }
function ReescribeConSusSaltos(const AAntes, ANuevo: string): string;
{ El texto con TODOS sus saltos (CRLF, LF o CR suelto) como ASalto: UN
  normalizador para quien crea o inserta texto. Estaba escrito seis veces,
  y el create del changeset solo miraba CRLF y LF: "uno\rdos\r" salia
  "uno\rdos\r\r\n" (novena revision). }
function ConSalto(const AText, ASalto: string): string;
{ El texto con que nace un fichero: ConSalto y, si no esta vacio, acabado en un
  salto. Estaba escrito cuatro veces: el create de un changeset, createunit
  (retirada de delphi_edit en la 1.28) y la
  unit y el .inc de delphi_create (V215). delphi_textedit no lo llama: escribe
  lo que le dan, sin anadirle el final. }
function TextoQueNace(const AText, ASalto: string): string;
{ Una unit vacia, la del IDE, con ese salto: createunit (retirada en la 1.28)
  y delphi_create la
  escribian cada uno (P9 del revisor). }
function EsqueletoDeUnit(const AUnitName, ASalto: string): string;

{ Si el texto lleva algun salto de linea (CR o LF): la pregunta "un ancla es
  UNA linea" de DoEdit, DoEditLine, FragmentoALinea y el stage de un changeset
  (decima revision: estaba escrita tres veces y al stage le faltaba). }
function TieneSalto(const AText: string): Boolean;
{ Donde cayo un cambio entre AAntes y ADespues, para mover los numeros de
  linea de lo que viene despues: ADesde es la primera linea (1-based) del
  texto de ANTES que queda POR DEBAJO de lo cambiado (prefijo y sufijo
  comunes), y ADelta cuanto se movio. Lo de encima no se mueve. UNA regla
  para la tanda (AplicaTanda) y el commit del changeset: el commit movia todo
  por el cambio del fichero ENTERO y editaba la linea equivocada con COMMIT
  COMPLETE (decima revision). LineaTrasCambio aplica el movimiento (0 = sin
  linea, se queda en 0). }
procedure ZonaDelCambio(const AAntes, ADespues: TArray<string>; out ADesde, ADelta: Integer);
function LineaTrasCambio(ALinea, ADesde, ADelta: Integer): Integer;
{ El texto acaba en un salto de linea (LF, CRLF o un CR suelto). Se miraba
  de dos formas (solo LF en delphi_textedit; octava revision). }
function TieneSaltoFinal(const AText: string): Boolean;
{ El NOMBRE de un salto, el que dicen las respuestas: 'CRLF', 'LF' o 'CR'. }
function NombreDelSalto(const ASalto: string): string;


{ El "eol" de quien crea un fichero: '' si vale (crlf, lf, o vacio = crlf); si
  no, la negativa. UNA regla para delphi_textedit y delphi_create (antes para
  delphi_edit createunit, retirada en la 1.28, que aceptaba "mac" y creaba en
  CRLF: tercera revision, 27-sep-2026). }
function EolDesconocido(const AEol: string): string;
{ ...y su inversa: el salto que ese "eol" pide (#10 con lf; #13#10 con crlf o
  vacio). Los dos create lo traducian a mano en cinco sitios, cada uno con su
  SameText(..., 'lf') (S1, A38 de la 1.23); su nombre, NombreDelSalto. }
function SaltoPedido(const AEol: string): string;


implementation

uses
  System.SysUtils,
  System.StrUtils,
  Lsp.Texts;

function LeadingWhite(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

function SangriaDeLaLineaEn(const ATexto: string; APos: Integer): string;
var
  Ini: Integer;
begin
  Ini := APos;
  while (Ini > 1) and not CharInSet(ATexto[Ini - 1], [#10, #13]) do
    Dec(Ini);
  Result := LeadingWhite(Copy(ATexto, Ini, APos - Ini));
end;

function SangraComoLaLinea(const ALinea, AAncla: string;
  const ANuevas: TArray<string>): TArray<string>;
var
  Sangria: string;
  I: Integer;
begin
  Result := Copy(ANuevas);
  Sangria := LeadingWhite(ALinea);
  if (Length(Result) = 0) or (LeadingWhite(Result[0]) <> '') or
     (Length(LeadingWhite(AAncla)) >= Length(Sangria)) then
    Exit;
  for I := 0 to High(Result) do
    if Result[I] <> '' then
      Result[I] := Sangria + Result[I];
end;

function EolDesconocido(const AEol: string): string;
begin
  Result := '';
  if (AEol <> '') and not MatchText(AEol, ['crlf', 'lf']) then
    Result := MsgFmt(SR_TEXT_EOL_FMT, [AEol]);
end;

function SaltoPedido(const AEol: string): string;
begin
  if SameText(AEol.Trim, 'lf') then
    Result := #10
  else
    Result := #13#10;
end;

function CuantasLineasReales(const ALines: TArray<string>): Integer;
begin
  Result := Length(ALines);
  if (Result > 0) and (ALines[Result - 1] = '') then
    Dec(Result); // la fantasma que deja el salto final
end;

function SplitToLines(const T: string): TArray<string>;
begin
  Result := ConSalto(T, #10).Split([#10]); // el normalizador de todos
end;

function SplitToLinesConSalto(const T: string; out ASaltos: TArray<string>): TArray<string>;
var
  I, N, Ini, K: Integer;
begin
  // primera pasada: cuantas lineas (los mismos cortes que SplitToLines)
  N := 1;
  I := 1;
  while I <= Length(T) do
  begin
    if T[I] = #13 then
    begin
      Inc(N);
      if (I < Length(T)) and (T[I + 1] = #10) then
        Inc(I);
    end
    else if T[I] = #10 then
      Inc(N);
    Inc(I);
  end;
  SetLength(Result, N);
  SetLength(ASaltos, N);
  K := 0;
  Ini := 1;
  I := 1;
  while I <= Length(T) do
  begin
    if (T[I] = #13) or (T[I] = #10) then
    begin
      Result[K] := Copy(T, Ini, I - Ini);
      if (T[I] = #13) and (I < Length(T)) and (T[I + 1] = #10) then
      begin
        ASaltos[K] := #13#10;
        Inc(I);
      end
      else
        ASaltos[K] := T[I];
      Inc(K);
      Ini := I + 1;
    end;
    Inc(I);
  end;
  Result[K] := Copy(T, Ini, MaxInt);
  ASaltos[K] := '';
end;

function UneConSusSaltos(const ALineas, ASaltos: TArray<string>): string;
var
  Sb: TStringBuilder;
  I: Integer;
  Salto: string;
begin
  Sb := TStringBuilder.Create;
  try
    for I := 0 to High(ALineas) do
    begin
      Sb.Append(ALineas[I]);
      if I <= High(ASaltos) then
      begin
        Salto := ASaltos[I];
        // Un CR suelto delante de una linea VACIA que acaba en LF se leeria
        // como UN CRLF, y esa linea desapareceria: sale como CRLF. Un texto
        // troceado no tiene esa vecindad; la crea quien cambia lineas, y la
        // inversa tiene que volver a trocearse igual (revisor propio de la
        // 1.18.2, medido: "a\rX\n\nb" sin X perdia la linea en blanco)
        if (Salto = #13) and (I < High(ALineas)) and (ALineas[I + 1] = '') and
           (I + 1 <= High(ASaltos)) and (ASaltos[I + 1] = #10) then
          Salto := #13#10;
        Sb.Append(Salto);
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function CambiaLineasEnSuTexto(const ATexto: string; ALinea, ACuantas: Integer;
  const ANuevas: TArray<string>; const ASalto: string): string;
var
  L, S, NL, NS: TArray<string>;
  I, Ultima: Integer;
  Cierre: string;
begin
  // con la fantasma del salto final: la ultima, '' y sin salto
  L := SplitToLinesConSalto(ATexto, S);
  // un tramo fuera del texto es un fallo de quien llama, no algo que leer
  // fuera del array en silencio (el servidor no compila con range checking);
  // insertar detras de la fantasma tampoco es un sitio
  if (ALinea < 0) or (ACuantas < 0) or (ALinea + ACuantas > Length(L)) or
     ((ACuantas = 0) and (ALinea = Length(L)) and (L[High(L)] = '')) then
    raise EArgumentOutOfRangeException.CreateFmt('CambiaLineasEnSuTexto(%d, %d)',
      [ALinea, ACuantas]);
  // Lo que el tramo deja IGUAL al principio y al final no se toca: un bloque
  // con old == new no reescribe nada, e insertar detras de un ancla no le
  // cambia su salto (revisor propio de la 1.18.2). La ultima linea del texto
  // (salto '') no entra: es la que decide el salto final
  var Nuevas := ANuevas;
  while (ACuantas > 0) and (Length(Nuevas) > 0) and (S[ALinea] <> '') and
        (Nuevas[0] = L[ALinea]) do
  begin
    Inc(ALinea);
    Dec(ACuantas);
    Delete(Nuevas, 0, 1);
  end;
  while (ACuantas > 0) and (Length(Nuevas) > 0) and (S[ALinea + ACuantas - 1] <> '') and
        (Nuevas[High(Nuevas)] = L[ALinea + ACuantas - 1]) do
  begin
    Dec(ACuantas);
    SetLength(Nuevas, Length(Nuevas) - 1);
  end;
  if (ACuantas = 0) and (Length(Nuevas) = 0) then
    Exit(ATexto); // nada cambia
  Ultima := ALinea + ACuantas - 1;
  NL := Copy(L, 0, ALinea);
  NS := Copy(S, 0, ALinea);
  if Length(Nuevas) > 0 then
  begin
    // el salto con que acaba el tramo: el de la ultima que se va; si no se va
    // ninguna, las nuevas entran delante de ALinea con el dominante
    if ACuantas > 0 then
      Cierre := S[Ultima]
    else
      Cierre := ASalto;
    // detras de la ultima linea de un texto sin salto final: esa lo gana y
    // las nuevas acaban sin el (sigue sin salto final)
    if (ACuantas = 0) and (ALinea > 0) and (NS[ALinea - 1] = '') then
    begin
      NS[ALinea - 1] := ASalto;
      Cierre := '';
    end;
    for I := 0 to High(Nuevas) do
    begin
      NL := NL + [Nuevas[I]];
      if I < High(Nuevas) then
        NS := NS + [ASalto]
      else
        NS := NS + [Cierre];
    end;
  end
  else if (ACuantas > 0) and (S[Ultima] = '') and (ALinea > 0) then
    // se van las ultimas de un texto sin salto final: la de delante pierde el
    // suyo y el texto sigue sin salto final
    NS[ALinea - 1] := '';
  NL := NL + Copy(L, Ultima + 1, MaxInt);
  NS := NS + Copy(S, Ultima + 1, MaxInt);
  Result := UneConSusSaltos(NL, NS);
end;

function EmpalmaEnSuTexto(const ATexto: string; ADesde, ALargo: Integer;
  const ANuevo, ASalto: string): string;
var
  L, S, Nuevas: TArray<string>;
  I, Off, Ini, Fin, ColIni, ColFin: Integer;
  Trozo: string;
begin
  // las lineas de la vista en LF (los cortes de SplitToLines); este troceador
  // da UNA linea para un texto vacio, y SplitToLines ninguna: un vault_append
  // a una nota vacia daba SYS-009 (revisor propio de la 1.18.2)
  L := SplitToLinesConSalto(ATexto, S);
  // la linea y la columna de cada punta del tramo: la posicion de un salto es
  // el final de su linea (el salto se queda si el tramo no lo cruza)
  Off := 0;
  Ini := -1;
  Fin := -1;
  ColIni := 0;
  ColFin := 0;
  for I := 0 to High(L) do
  begin
    if (Ini < 0) and (ADesde <= Off + Length(L[I])) then
    begin
      Ini := I;
      ColIni := ADesde - Off;
    end;
    if (Fin < 0) and (ADesde + ALargo <= Off + Length(L[I])) then
    begin
      Fin := I;
      ColFin := ADesde + ALargo - Off;
    end;
    Inc(Off, Length(L[I]) + 1);
  end;
  if (Ini < 0) or (Fin < Ini) then
    raise EArgumentOutOfRangeException.CreateFmt('EmpalmaEnSuTexto(%d, %d)', [ADesde, ALargo]);
  Trozo := Copy(L[Ini], 1, ColIni) + ANuevo + Copy(L[Fin], ColFin + 1, MaxInt);
  // un trozo vacio es UNA linea en blanco, no ninguna (eso seria borrarla)
  if Trozo = '' then
    Nuevas := ['']
  else
    Nuevas := SplitToLines(Trozo);
  Result := CambiaLineasEnSuTexto(ATexto, Ini, Fin - Ini + 1, Nuevas, ASalto);
end;

{ Cuantas lineas iguales hay delante (APre) y, sin pisar esas, detras (ASuf)
  entre AAntes y ADespues. Estaba escrito en LineasQueSeQuedan y en
  ZonaDelCambio (WHEN SEEN de F1 de la 1.29). }
procedure ExtremosIguales(const AAntes, ADespues: TArray<string>; out APre, ASuf: Integer);
begin
  APre := 0;
  while (APre < Length(AAntes)) and (APre < Length(ADespues)) and (AAntes[APre] = ADespues[APre]) do
    Inc(APre);
  ASuf := 0;
  while (ASuf < Length(AAntes) - APre) and (ASuf < Length(ADespues) - APre) and
        (AAntes[High(AAntes) - ASuf] = ADespues[High(ADespues) - ASuf]) do
    Inc(ASuf);
end;

function LineasQueSeQuedan(const AAntes, ADespues: TArray<string>): TArray<Integer>;
const
  MAX_CAMBIOS = 1000; // mas que esto en medio es reescribir: el medio, nuevo
var
  N, M, Pre, Suf, NA, NB, MaxD, Off, D, DFin, K, X, Y, KAntes, XAntes, YAntes: Integer;
  V, Vd: TArray<Integer>;
  Trazas: TArray<TArray<Integer>>;
begin
  N := Length(AAntes);
  M := Length(ADespues);
  SetLength(Result, M);
  for var I := 0 to M - 1 do
    Result[I] := -1;
  // lo igual delante y detras, sin buscar
  ExtremosIguales(AAntes, ADespues, Pre, Suf);
  for var I := 0 to Pre - 1 do
    Result[I] := I;
  for var I := 0 to Suf - 1 do
    Result[M - 1 - I] := N - 1 - I;
  // el medio: AAntes[Pre .. Pre+NA-1] contra ADespues[Pre .. Pre+NB-1]
  NA := N - Pre - Suf;
  NB := M - Pre - Suf;
  if (NA = 0) or (NB = 0) then
    Exit; // solo entraron lineas, o solo se fueron
  // Myers (1986): V[K + Off] es la X mas lejana de la diagonal K con D cambios.
  // La de antes de cada paso se guarda, de -(D+1) a D+1, para volver por el camino
  MaxD := NA + NB;
  if MaxD > MAX_CAMBIOS then
    MaxD := MAX_CAMBIOS;
  Off := MaxD + 1;
  SetLength(V, 2 * MaxD + 3);
  Trazas := nil;
  DFin := -1;
  D := 0;
  while (DFin < 0) and (D <= MaxD) do
  begin
    Trazas := Trazas + [Copy(V, Off - D - 1, 2 * D + 3)];
    K := -D;
    while (DFin < 0) and (K <= D) do
    begin
      if (K = -D) or ((K <> D) and (V[K - 1 + Off] < V[K + 1 + Off])) then
        X := V[K + 1 + Off] // desde la diagonal de arriba: una linea que entra
      else
        X := V[K - 1 + Off] + 1; // desde la de abajo: una que se va
      Y := X - K;
      while (X < NA) and (Y < NB) and (AAntes[Pre + X] = ADespues[Pre + Y]) do
      begin
        Inc(X);
        Inc(Y);
      end;
      V[K + Off] := X;
      if (X >= NA) and (Y >= NB) then
        DFin := D;
      Inc(K, 2);
    end;
    Inc(D);
  end;
  if DFin < 0 then
    Exit; // demasiados cambios: el medio entero, nuevo
  // de vuelta, de (NA, NB) al principio: las diagonales son las que se quedan
  X := NA;
  Y := NB;
  for D := DFin downto 0 do
  begin
    Vd := Trazas[D]; // V[J] de antes del paso D en Vd[J + D + 1]
    K := X - Y;
    if (K = -D) or ((K <> D) and (Vd[K + D] < Vd[K + D + 2])) then
      KAntes := K + 1
    else
      KAntes := K - 1;
    XAntes := Vd[KAntes + D + 1];
    YAntes := XAntes - KAntes;
    while (X > XAntes) and (Y > YAntes) do
    begin
      Dec(X);
      Dec(Y);
      Result[Pre + Y] := Pre + X;
    end;
    X := XAntes;
    Y := YAntes;
  end;
end;

function ReescribeConSusSaltos(const AAntes, ANuevo: string): string;
var
  LA, LN, CA, CN: TArray<string>;
  Siguen: TArray<Integer>;
  Salto: string;
  I, J, IDebajo, JDebajo: Integer;
begin
  // un texto vacio no tiene lineas que conservar (y SplitToLines no le da
  // ninguna, donde el compositor ve una)
  if AAntes = '' then
    Exit(ANuevo);
  // las lineas de CambiaLineasEnSuTexto, con la fantasma del salto final
  LA := SplitToLines(AAntes);
  LN := SplitToLines(ANuevo);
  // la ultima de cada uno solo casa con la ultima del otro: es la que decide el
  // salto final, y un tramo detras de la fantasma no es un sitio
  CA := Copy(LA);
  CN := Copy(LN);
  if Length(CA) > 0 then
    CA[High(CA)] := #0 + CA[High(CA)];
  if Length(CN) > 0 then
    CN[High(CN)] := #0 + CN[High(CN)];
  Siguen := LineasQueSeQuedan(CA, CN);
  Salto := SaltoDominante(AAntes);
  Result := AAntes;
  // cada tramo entre dos que se quedan, de abajo arriba (lo de encima no se
  // mueve), por EL compositor de quien cambia lineas
  IDebajo := Length(LN);
  JDebajo := Length(LA);
  for I := High(LN) downto -1 do
  begin
    if I >= 0 then
    begin
      J := Siguen[I];
      if J < 0 then
        Continue;
    end
    else
      J := -1;
    if (IDebajo - I > 1) or (JDebajo - J > 1) then
      Result := CambiaLineasEnSuTexto(Result, J + 1, JDebajo - J - 1,
        Copy(LN, I + 1, IDebajo - I - 1), Salto);
    IDebajo := I;
    JDebajo := J;
  end;
end;

function TieneSalto(const AText: string): Boolean;
begin
  Result := (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0);
end;

function ConSalto(const AText, ASalto: string): string;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10);
  if ASalto <> #10 then
    Result := Result.Replace(#10, ASalto);
end;

function TextoQueNace(const AText, ASalto: string): string;
begin
  Result := ConSalto(AText, ASalto);
  if (Result <> '') and not TieneSaltoFinal(Result) then
    Result := Result + ASalto;
end;

function EsqueletoDeUnit(const AUnitName, ASalto: string): string;
begin
  Result := ConSalto(Format('unit %s;'#10#10'interface'#10#10'implementation'#10#10'end.'#10, [AUnitName]), ASalto);
end;

procedure ZonaDelCambio(const AAntes, ADespues: TArray<string>; out ADesde, ADelta: Integer);
var
  Pre, Suf: Integer;
begin
  ADelta := Length(ADespues) - Length(AAntes);
  ExtremosIguales(AAntes, ADespues, Pre, Suf);
  ADesde := Length(AAntes) - Suf + 1;
end;

function LineaTrasCambio(ALinea, ADesde, ADelta: Integer): Integer;
begin
  Result := ALinea;
  if (ALinea > 0) and (ALinea >= ADesde) then
    Result := ALinea + ADelta;
end;

function LineasDelTexto(const AText: string): TArray<string>;
begin
  Result := SplitToLines(AText);
  SetLength(Result, CuantasLineasReales(Result));
end;

function SaltoDominante(const AText: string): string;
var
  I, Crlf, Lf, Cr: Integer;
begin
  Crlf := 0;
  Lf := 0;
  Cr := 0;
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = #13 then
    begin
      if (I < Length(AText)) and (AText[I + 1] = #10) then
      begin
        Inc(Crlf);
        Inc(I);
      end
      else
        Inc(Cr);
    end
    else if AText[I] = #10 then
      Inc(Lf);
    Inc(I);
  end;
  if (Lf > Crlf) and (Lf >= Cr) then
    Result := #10
  else if (Cr > Crlf) and (Cr > Lf) then
    Result := #13
  else
    Result := #13#10; // el de Windows, tambien sin ningun salto aun
end;

function TieneSaltoFinal(const AText: string): Boolean;
begin
  Result := AText.EndsWith(#10) or AText.EndsWith(#13);
end;

function NombreDelSalto(const ASalto: string): string;
begin
  if ASalto = #13#10 then
    Result := 'CRLF'
  else if ASalto = #13 then
    Result := 'CR'
  else
    Result := 'LF';
end;

end.
