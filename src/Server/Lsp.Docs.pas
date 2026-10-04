unit Lsp.Docs;

{ La ayuda instalada de Delphi para delphi_docs (1.10.0): los .chm que el IDE
  registra en Help\HtmlHelp1Files - los que abre con F1 -, leidos por dentro
  con Lsp.Chm. Buscar un concepto o una clase en sus indices y leer una
  pagina como texto. Nada se extrae al disco y nada se guarda entre llamadas:
  cada busqueda lee los indices de nuevo (medido 2-oct-2026: abrir un .chm
  2 ms, su indice de 17,5 MB 21 ms, una pagina 1 ms).

  Lo puro - un indice, una pagina como texto, un enlace - va en funciones sin
  disco, que prueban las unitarias (LspTests.Docs). }

interface

uses
  System.SysUtils;

type
  { Una entrada de un mapa de la ayuda (.hhk, el indice de palabras; .hhc,
    el arbol de contenidos). }
  TEntradaDeMapa = record
    Nombre: string;   // la palabra o el titulo
    Local: string;    // la pagina, con su #ancla si la lleva
  end;

  TSeccion = record
    Ancla: string;
    Titulo: string;
  end;

  TEnlace = record
    Href: string;     // tal como lo escribe la pagina (IdDeEnlace lo hace id)
    Texto: string;
  end;

  TPaginaDoc = record
    Titulo: string;
    Texto: string;               // la pagina (o la seccion pedida) como texto
    Secciones: TArray<TSeccion>; // las de su caja de contenidos
    Redirige: string;            // el enlace de una pagina que solo redirige
    AnclaEncontrada: Boolean;    // pedida una seccion: si estaba
    Ancla: string;               // encontrada: su ancla (la pedida, o la de su titulo)
    { Una seccion que envuelve la pagina (ningun otro titulo de su nivel o mas
      alto: en las de la API, Description, de la que cuelga todo) acaba en su
      primer subtitulo; aqui las anclas de los que siguen, en orden. }
    Subsecciones: TArray<string>;
    { La barra de una clase o una unidad: su padre ("Up to Parent") y sus
      listas de miembros (Methods, Properties, Events...), heredados
      incluidos. Como texto no servia: eran enlaces sin id. En una pagina de
      temas, el enlace a su indice (EnlaceAlPadre), el primero. }
    Enlaces: TArray<TEnlace>;
  end;

  TResultadoDoc = record
    Id: string;       // '<ayuda>:<pagina>[#ancla]'
    Titulo: string;
    Puntos: Integer;
  end;

  TAyudaInstalada = record
    Corto: string;     // 'system', 'vcl', 'indy10'...: lo que va en los ids
    Fichero: string;   // el .chm
    Fecha: TDateTime;  // la del fichero: de cuando es esa ayuda
  end;

{ --- lo puro --- }

{ El texto de un fichero de la ayuda con su juego de caracteres: casi todos
  Windows-1252 (lo dice su meta), alguno UTF-8. }
function TextoDeBytes(const ABytes: TArray<Byte>): string;

{ Las entradas de un mapa (.hhk/.hhc, sus bytes) cuyo bloque contiene AAguja
  y TODAS las palabras de ATodas (minusculas, sin distinguir mayusculas
  ASCII). Solo se decodifican esos bloques: el mapa no se monta entero. }
function EntradasQueCasan(const ABytes: TArray<Byte>; const AAguja: string;
  const ATodas: TArray<string>): TArray<TEntradaDeMapa>;

{ Puntos de una palabra del indice contra la consulta (las dos en
  minusculas): igual 100, empieza por ella 60, la contiene 30, menos lo que
  sobra (hasta 25). 0 = no casa. }
function PuntosDePalabra(const APalabra, AConsulta: string): Integer;

{ Una pagina de la ayuda como texto: su contenido (sin la cabecera, el pie ni
  la caja de contenidos, de la que salen las Secciones), sin lo que es solo
  de C++, con titulos (##), listas, tablas (|) y codigo (```) legibles. Con
  AAncla, solo esa seccion (si no esta, la pagina entera). }
function PaginaComoTexto(const AHtml, AAncla: string): TPaginaDoc;

{ El id de un enlace de una pagina de la ayuda ACorto: 'X.htm#a' ->
  'corto:X.htm#a'; 'ms-its:system.chm::/X.htm' -> 'system:X.htm'. '' si no
  lleva a una pagina de la ayuda (http, mailto, un ancla de la misma). }
function IdDeEnlace(const AHref, ACorto: string): string;

{ El id partido: la ayuda, la pagina y el ancla. False si no tiene forma de
  id de pagina (sin ':', con '..', con unidad, con barra delante, con un
  caracter de control: un #0 cortaba el nombre al abrirlo y se leia
  'index.hhk'#0'.htm' como index.hhk; revision de la 1.10.0). }
function PartesDeId(const AId: string; out ACorto, APagina, AAncla: string): Boolean;

{ El id de una pagina, de sus partes: el UNICO que lo compone (IdDeEnlace y
  quien siga una redireccion pasan por aqui); PartesDeId es su inversa. }
function IdDePagina(const ACorto, APagina, AAncla: string): string;

{ Las palabras de una consulta, en minusculas, sin las comillas ni la
  puntuacion que las rodea: '"class helpers"' busca class y helpers (la
  descripcion de la tool lo escribe asi, y con las comillas no casaba nada;
  revision de la 1.10.0). El punto de dentro se queda: TStringList.Sort. Sin
  argumentos genericos (TList<T>.Add busca TList.Add), y de una firma solo
  su nombre (FormatDateTime(const Format: string) busca FormatDateTime). }
function PalabrasDeConsulta(const AConsulta: string): TArray<string>;

{ --- con la ayuda instalada --- }

type
  TLecturaDoc = (
    ldLeida,         // la pagina, en APagina
    ldIdMalFormado,  // no tiene forma de id
    ldSinPagina,     // la ayuda no es de las instaladas, o no tiene esa pagina
    ldNoAbre);       // la ayuda esta, pero Windows no la abre

{ Las ayudas del Delphi activo (la lista del IDE) que existen en disco, cada
  una con su nombre corto; [] si no hay ninguna instalada. Un fichero
  registrado dos veces (con $(BDS) y con su ruta) es una ayuda. }
function AyudasInstaladas: TArray<TAyudaInstalada>;

{ Hasta ALimite resultados de AAyudas, los mejores primero y uno por pagina;
  ATotal, cuantas paginas del indice casaron; AAbiertas, cuantas ayudas se
  dejaron abrir (0 con ayudas = ninguna abre). AFramework 'vcl' | 'fmx' pone
  primero la de ese framework. Las paginas que solo redirigen salen como su
  destino. }
function BuscaEnLaAyuda(const AAyudas: TArray<TAyudaInstalada>;
  const AConsulta, AFramework: string; ALimite: Integer;
  out ATotal, AAbiertas: Integer): TArray<TResultadoDoc>;

{ Una pagina de AAyudas por su id (el de una busqueda). Una que solo
  redirige da su destino -con la seccion pedida, si el destino no trae otra-
  y AId sale con el id de ese destino. }
function LeePaginaDeLaAyuda(const AAyudas: TArray<TAyudaInstalada>;
  var AId: string; out APagina: TPaginaDoc; out AAyuda: TAyudaInstalada): TLecturaDoc;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Lsp.Chm,
  Lsp.Discovery,
  Lsp.Guard,     // IdeMacroVars + ExpandIdeMacros: la lista del IDE trae $(BDS)
  Lsp.Patch,     // DecodeBytes: EL decodificador
  Lsp.Texts,     // SF_DOCS_ANCESTROS_FMT
  System.Character,
  Lsp.Pascal;

{ ---------------------------------------------------------------- bytes }

function MinAscii(B: Byte): Byte; inline;
begin
  if (B >= Ord('A')) and (B <= Ord('Z')) then
    Result := B + 32
  else
    Result := B;
end;

{ La siguiente aparicion de APatron (bytes en minusculas) en ABytes entre
  ADesde y AHasta (excluido), sin distinguir mayusculas ASCII; -1 si no. }
function BuscaBytes(const ABytes, APatron: TArray<Byte>; ADesde, AHasta: Integer): Integer;
var
  I, J, M: Integer;
  P0: Byte;
begin
  M := Length(APatron);
  if (M = 0) or (AHasta > Length(ABytes)) then
    AHasta := Length(ABytes);
  if M = 0 then
    Exit(-1);
  P0 := APatron[0];
  I := Max(ADesde, 0);
  while I <= AHasta - M do
  begin
    if MinAscii(ABytes[I]) = P0 then
    begin
      J := 1;
      while (J < M) and (MinAscii(ABytes[I + J]) = APatron[J]) do
        Inc(J);
      if J = M then
        Exit(I);
    end;
    Inc(I);
  end;
  Result := -1;
end;

{ La ultima aparicion de APatron que EMPIEZA en ADesde o antes; -1 si no. }
function BuscaBytesAtras(const ABytes, APatron: TArray<Byte>; ADesde: Integer): Integer;
var
  I, J, M: Integer;
begin
  M := Length(APatron);
  I := Min(ADesde, Length(ABytes) - M);
  while I >= 0 do
  begin
    J := 0;
    while (J < M) and (MinAscii(ABytes[I + J]) = APatron[J]) do
      Inc(J);
    if J = M then
      Exit(I);
    Dec(I);
  end;
  Result := -1;
end;

function BytesMin(const S: string): TArray<Byte>;
var
  E: TEncoding;
begin
  E := TEncoding.GetEncoding(1252);
  try
    Result := E.GetBytes(S.ToLower);
  finally
    E.Free;
  end;
end;

{ CUAL es el juego de caracteres de un fichero de la ayuda, por su senal: el
  BOM o el meta de su cabecera; si no, Windows-1252. Decodifica EL
  decodificador (Lsp.Patch.DecodeBytes, con su CP1252 compartido: crear uno
  por bloque del indice caia en el bucle de la busqueda; revision 1.10.0). }
function KindDeAyuda(const ABytes: TArray<Byte>): TEncKind;
var
  Cabeza: string;
  Fin, P, Q: Integer;
begin
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Exit(ekUtf8Bom);
  // el meta va en la cabecera: hasta 16 KB, en ASCII (con 1 KB se quedaba
  // fuera el de una cabecera larga)
  Cabeza := TEncoding.ASCII.GetString(ABytes, 0, Min(Length(ABytes), 16384)).ToLower;
  Fin := Cabeza.IndexOf('</head');
  if Fin >= 0 then
    Cabeza := Cabeza.Substring(0, Fin);
  // charset=utf-8 con comillas o sin ellas, y con blancos: el meta de HTML5
  // es <meta charset="utf-8">, y solo se reconocia sin comillas (revision
  // de la 1.10.0)
  P := Cabeza.IndexOf('charset');
  while P >= 0 do
  begin
    Q := P + Length('charset');
    while (Q < Length(Cabeza)) and CharInSet(Cabeza.Chars[Q], [' ', #9, '=', '"', '''']) do
      Inc(Q);
    if Cabeza.Substring(Q, 5).Equals('utf-8') or Cabeza.Substring(Q, 4).Equals('utf8') then
      Exit(ekUtf8);
    P := Cabeza.IndexOf('charset', Q);
  end;
  Result := ekCp1252;
end;

function TextoDeBytes(const ABytes: TArray<Byte>): string;
begin
  Result := DecodeBytes(ABytes, KindDeAyuda(ABytes));
end;

{ ------------------------------------------------------------ entidades }

function DecodificaEntidades(const S: string): string;
var
  I, J: Integer;
  Ent: string;
  Sb: TStringBuilder;
  Codigo: Integer;
begin
  if S.IndexOf('&') < 0 then
    Exit(S);
  Sb := TStringBuilder.Create(Length(S));
  try
    I := 1;
    while I <= Length(S) do
    begin
      if S[I] = '&' then
      begin
        J := I + 1;
        while (J <= Length(S)) and (J - I <= 10) and (S[J] <> ';') and (S[J] <> '&') do
          Inc(J);
        if (J <= Length(S)) and (S[J] = ';') then
        begin
          Ent := Copy(S, I + 1, J - I - 1);
          Codigo := -1;
          if SameText(Ent, 'amp') then Codigo := Ord('&')
          else if SameText(Ent, 'lt') then Codigo := Ord('<')
          else if SameText(Ent, 'gt') then Codigo := Ord('>')
          else if SameText(Ent, 'quot') then Codigo := Ord('"')
          else if SameText(Ent, 'apos') then Codigo := Ord('''')
          else if SameText(Ent, 'nbsp') then Codigo := Ord(' ')
          // las dos con nombre que quedaban en el texto de 397 paginas de
          // verdad (medido en la revision de la 1.10.0); las demas no salen
          else if SameText(Ent, 'laquo') then Codigo := $AB
          else if SameText(Ent, 'raquo') then Codigo := $BB
          else if Ent.StartsWith('#x', True) then
            Codigo := StrToIntDef('$' + Ent.Substring(2), -1)
          else if Ent.StartsWith('#') then
            Codigo := StrToIntDef(Ent.Substring(1), -1);
          // un sustituto suelto no es un caracter; uno de mas de $FFFF va como
          // su par (antes se quedaba el &#x...; escrito)
          if (Codigo > 0) and (Codigo <= $10FFFF) and
             not ((Codigo >= $D800) and (Codigo <= $DFFF)) then
          begin
            Sb.Append(Char.ConvertFromUtf32(Codigo));
            I := J + 1;
            Continue;
          end;
        end;
      end;
      Sb.Append(S[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ ------------------------------------------------------------- los mapas }

{ El valor de un atributo de un <param ...> o de una etiqueta (sin los < >):
  entre comillas o hasta el blanco. '' si no esta. }
function AtributoDe(const ATag, ANombre: string): string;
var
  Min: string;
  P, Q: Integer;
  C: Char;
begin
  Result := '';
  Min := ATag.ToLower;
  P := Pos(' ' + ANombre.ToLower + '=', ' ' + Min.Replace(#9, ' ').Replace(#10, ' ').Replace(#13, ' '));
  if P = 0 then
    Exit;
  P := P + Length(ANombre) + 1; // en ATag: justo detras del '='
  if P > Length(ATag) then
    Exit;
  C := ATag[P];
  if (C = '"') or (C = '''') then
  begin
    Q := PosEx(C, ATag, P + 1);
    if Q = 0 then
      Q := Length(ATag) + 1;
    Result := Copy(ATag, P + 1, Q - P - 1);
  end
  else
  begin
    Q := P;
    while (Q <= Length(ATag)) and not CharInSet(ATag[Q], [' ', #9, #10, #13, '>']) do
      Inc(Q);
    Result := Copy(ATag, P, Q - P);
  end;
end;

{ Los <param name=... value=...> de un bloque <object> ya en texto. }
procedure ParametrosDeBloque(const ABloque: string; out ANombres, ALocales: TArray<string>);
var
  P, Q: Integer;
  Tag, N, V, Min: string;
begin
  ANombres := nil;
  ALocales := nil;
  Min := ABloque.ToLower;
  P := Pos('<param', Min);
  while P > 0 do
  begin
    Q := PosEx('>', ABloque, P);
    if Q = 0 then
      Break;
    Tag := Copy(ABloque, P + 1, Q - P - 1);
    N := AtributoDe(Tag, 'name').ToLower;
    V := DecodificaEntidades(AtributoDe(Tag, 'value')).Trim;
    if V <> '' then
      if N = 'name' then
        ANombres := ANombres + [V]
      else if N = 'local' then
        ALocales := ALocales + [V];
    P := PosEx('<param', Min, Q);
  end;
end;

function EntradasQueCasan(const ABytes: TArray<Byte>; const AAguja: string;
  const ATodas: TArray<string>): TArray<TEntradaDeMapa>;
var
  Aguja, Abre, Cierra: TArray<Byte>;
  Todas: TArray<TArray<Byte>>;
  P, Ini, Fin, CierreAntes, UltimoFin: Integer;
  Bloque: TArray<Byte>;
  Nombres, Locales: TArray<string>;
  E: TEntradaDeMapa;
  Vale, Dentro: Boolean;
  Lista: TList<TEntradaDeMapa>;
  Kind: TEncKind;
begin
  Result := nil;
  Aguja := BytesMin(AAguja);
  if Length(Aguja) = 0 then
    Exit;
  // el juego del MAPA, una vez: un bloque no lleva el meta de la cabecera (se
  // decodificaba como Windows-1252 aunque el mapa dijera UTF-8), ni el BOM
  Kind := KindDeAyuda(ABytes);
  if Kind = ekUtf8Bom then
    Kind := ekUtf8;
  Abre := BytesMin('<object');
  Cierra := BytesMin('</object>');
  Todas := nil;
  for var T in ATodas do
    Todas := Todas + [BytesMin(T)];
  UltimoFin := -1;
  // una lista, no Result + [E]: una palabra corriente casa miles de bloques
  Lista := TList<TEntradaDeMapa>.Create;
  try
    P := BuscaBytes(ABytes, Aguja, 0, Length(ABytes));
    while P >= 0 do
    begin
      Ini := BuscaBytesAtras(ABytes, Abre, P);
      CierreAntes := BuscaBytesAtras(ABytes, Cierra, P);
      Fin := BuscaBytes(ABytes, Cierra, P, Length(ABytes));
      // dentro de un bloque, y uno que no se ha visto ya
      Dentro := (Ini >= 0) and (Fin > Ini) and (CierreAntes < Ini) and (Ini > UltimoFin);
      if Dentro then
      begin
        UltimoFin := Fin;
        Vale := True;
        for var T in Todas do
          if BuscaBytes(ABytes, T, Ini, Fin) < 0 then
          begin
            Vale := False;
            Break;
          end;
        if Vale then
        begin
          Bloque := Copy(ABytes, Ini, Fin + Length(Cierra) - Ini);
          ParametrosDeBloque(DecodeBytes(Bloque, Kind), Nombres, Locales);
          if (Length(Nombres) > 0) and (Length(Locales) > 0) then
            for var L in Locales do
            begin
              E.Nombre := Nombres[0];
              E.Local := L;
              Lista.Add(E);
            end;
        end;
      end;
      if Fin < 0 then
        Break;
      // un bloque visto se salta entero; un acierto fuera de bloque (en su
      // </object> o entre dos) se pasa y nada mas: saltar hasta el </object>
      // siguiente se comia el bloque de detras, y 'object' no encontraba
      // nada (medido en la revision de la 1.10.0)
      if Dentro then
        P := BuscaBytes(ABytes, Aguja, Fin + Length(Cierra), Length(ABytes))
      else
        P := BuscaBytes(ABytes, Aguja, P + 1, Length(ABytes));
    end;
    Result := Lista.ToArray;
  finally
    Lista.Free;
  end;
end;

function PuntosDePalabra(const APalabra, AConsulta: string): Integer;
begin
  if (APalabra = '') or (AConsulta = '') then
    Exit(0);
  if APalabra = AConsulta then
    Result := 100
  else if APalabra.StartsWith(AConsulta) then
    Result := 60
  else if APalabra.Contains(AConsulta) then
    Result := 30
  else
    Exit(0);
  Dec(Result, Min(Length(APalabra) - Length(AConsulta), 25));
end;

{ -------------------------------------------------------------- enlaces }

function SinAncla(const ALocal: string): string;
var
  K: Integer;
begin
  K := ALocal.IndexOf('#');
  if K < 0 then
    Result := ALocal
  else
    Result := ALocal.Substring(0, K);
end;

function NombreDePagina(const ALocal: string): string;
var
  S: string;
  K: Integer;
begin
  S := SinAncla(ALocal).Replace('\', '/');
  K := S.LastIndexOf('/');
  Result := S.Substring(K + 1);
end;

function EsPagina(const APagina: string): Boolean;
var
  P: string;
begin
  P := SinAncla(APagina).ToLower;
  Result := P.EndsWith('.htm') or P.EndsWith('.html');
end;

function IdDePagina(const ACorto, APagina, AAncla: string): string;
begin
  Result := ACorto + ':' + APagina;
  if AAncla <> '' then
    Result := Result + '#' + AAncla;
end;

{ La pagina y su ancla de un enlace ('X.htm#a' -> 'X.htm' y 'a'). }
procedure PaginaYAncla(const AEnlace: string; out APagina, AAncla: string);
var
  K: Integer;
begin
  K := AEnlace.IndexOf('#');
  if K < 0 then
  begin
    APagina := AEnlace;
    AAncla := '';
  end
  else
  begin
    APagina := AEnlace.Substring(0, K);
    AAncla := AEnlace.Substring(K + 1);
  end;
end;

function IdDeEnlace(const AHref, ACorto: string): string;
var
  H, Fichero, Pagina, Ancla: string;
  K: Integer;
begin
  Result := '';
  H := DecodificaEntidades(AHref.Trim);
  if StartsText('ms-its:', H) then
  begin
    H := H.Substring(7);
    K := H.IndexOf('::');
    if K < 0 then
      Exit;
    Fichero := H.Substring(0, K).Replace('/', '\');
    PaginaYAncla(H.Substring(K + 2).TrimLeft(['/']), Pagina, Ancla);
    if not EsPagina(Pagina) then
      Exit;
    // la ayuda por el nombre de su fichero: un enlace ms-its: no lleva carpeta
    Result := IdDePagina(LowerCase(ChangeFileExt(ExtractFileName(Fichero), '')),
      Pagina, Ancla);
    Exit;
  end;
  if (H = '') or H.StartsWith('#') or H.Contains(':') or not EsPagina(H) then
    Exit;
  if H.StartsWith('./') then
    H := H.Substring(2);
  PaginaYAncla(H.Replace('\', '/'), Pagina, Ancla);
  Result := IdDePagina(ACorto, Pagina, Ancla);
end;

function PartesDeId(const AId: string; out ACorto, APagina, AAncla: string): Boolean;
var
  K: Integer;
  Resto: string;
begin
  ACorto := '';
  APagina := '';
  AAncla := '';
  // un caracter de control no es de ningun id: un #0 cortaba el nombre al
  // abrirlo ('index.hhk'#0'.htm' leia el indice entero)
  for var C in AId do
    if C < #32 then
      Exit(False);
  K := AId.IndexOf(':');
  if K <= 0 then
    Exit(False);
  ACorto := AId.Substring(0, K).Trim.ToLower;
  // (la entrada no es la misma variable que la salida: un out se vacia al
  // entrar)
  PaginaYAncla(AId.Substring(K + 1).Trim, Resto, AAncla);
  APagina := Resto.Replace('\', '/');
  // una pagina DE DENTRO del .chm, y nada mas: ni unidad, ni subir, ni raiz
  Result := (ACorto <> '') and EsPagina(APagina) and not APagina.Contains(':') and
    not APagina.StartsWith('/') and not ('/' + APagina + '/').Contains('/../') and
    not ('/' + APagina + '/').Contains('/./');
end;

function PalabrasDeConsulta(const AConsulta: string): TArray<string>;
const
  // lo que rodea a una palabra sin ser de ella; el punto de dentro se queda
  BORDES: TSysCharSet = ['"', '''', '`', '(', ')', '[', ']', '{', '}', ',', ';', ':', '!', '?'];
var
  P, S: string;
  I, J, Prof: Integer;
begin
  Result := nil;
  // Los argumentos genericos fuera: la ayuda titula TList.Add, no
  // TList<T>.Add (solo los que van pegados a un nombre: '<>' suelto se queda).
  // Y una FIRMA, como la da delphi_hover (FormatDateTime(const Format:
  // string; ...): string), busca su NOMBRE: los tipos de sus parametros no
  // estan en el titulo de ninguna pagina y la consulta entera daba DOCS-006
  // (dato de Hermes, dogfooding de la 1.12.0; medido el 4-oct-2026)
  S := '';
  Prof := 0;
  for I := 1 to Length(AConsulta) do
    if (AConsulta[I] = '<') and ((Prof > 0) or ((I > 1) and EsCaracterDeIdent(AConsulta[I - 1]))) then
      Inc(Prof)
    else if (AConsulta[I] = '>') and (Prof > 0) then
      Dec(Prof)
    else if Prof = 0 then
      S := S + AConsulta[I];
  I := Pos('(', S);
  if (I > 1) and EsCaracterDeIdent(S[I - 1]) then
  begin
    J := I - 1;
    while (J > 1) and (EsCaracterDeIdent(S[J - 1]) or (S[J - 1] = '.')) do
      Dec(J);
    S := Copy(S, J, I - J);
  end;
  for var W in S.ToLower.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty) do
  begin
    P := W;
    while (P <> '') and CharInSet(P[1], BORDES) do
      Delete(P, 1, 1);
    while (P <> '') and CharInSet(P[Length(P)], BORDES) do
      SetLength(P, Length(P) - 1);
    if P <> '' then
      Result := Result + [P];
  end;
end;

{ ------------------------------------------------------- pagina a texto }

const
  // las etiquetas que no se cierran
  VACIAS: array [0 .. 9] of string = ('br', 'img', 'input', 'meta', 'link',
    'hr', 'wbr', 'col', 'area', 'param');

function NombreDeEtiqueta(const ATag: string): string;
var
  I: Integer;
  S: string;
begin
  S := ATag.TrimLeft(['/']);
  I := 1;
  while (I <= Length(S)) and CharInSet(S[I], ['a' .. 'z', 'A' .. 'Z', '0' .. '9']) do
    Inc(I);
  Result := Copy(S, 1, I - 1).ToLower;
end;

function ClaseTiene(const ATag, AToken: string): Boolean;
begin
  Result := MatchText(AToken, AtributoDe(ATag, 'class').Split([' ', #9],
    TStringSplitOptions.ExcludeEmpty));
end;

{ El HTML ya recortado al contenido, como texto. }
function HtmlATexto(const AHtml: string): string;
var
  Sb: TStringBuilder;
  I, Q, N, Profundidad, EnPre, Celdas, EnCelda: Integer;
  Tag, Nom, Saltando: string;
  Cierre: Boolean;
  Hueco: Boolean; // hay un blanco pendiente
  Ancestros: TArray<string>;

  procedure Salto(ACuantos: Integer);
  var
    Ya: Integer;
  begin
    // dentro de una celda, un bloque es un blanco: la fila sigue en su linea
    if EnCelda > 0 then
    begin
      Hueco := True;
      Exit;
    end;
    Hueco := False;
    Ya := 0;
    while (Ya < Sb.Length) and (Sb.Chars[Sb.Length - 1 - Ya] = #10) do
      Inc(Ya);
    if Sb.Length = 0 then
      Exit;
    while Ya < ACuantos do
    begin
      Sb.Append(#10);
      Inc(Ya);
    end;
  end;

  procedure Texto(const S: string);
  var
    C: Char;
  begin
    for C in DecodificaEntidades(S) do
      if EnPre > 0 then
        Sb.Append(C)
      else if CharInSet(C, [' ', #9, #10, #13]) then
        Hueco := True
      else
      begin
        if Hueco and (Sb.Length > 0) and (Sb.Chars[Sb.Length - 1] <> #10) then
          Sb.Append(' ');
        Hueco := False;
        Sb.Append(C);
      end;
  end;

begin
  Sb := TStringBuilder.Create;
  try
    I := 1;
    N := Length(AHtml);
    Saltando := '';
    Profundidad := 0;
    EnPre := 0;
    Celdas := 0;
    EnCelda := 0;
    Hueco := False;
    Ancestros := nil;
    while I <= N do
    begin
      if AHtml[I] <> '<' then
      begin
        Q := PosEx('<', AHtml, I);
        if Q = 0 then
          Q := N + 1;
        if Saltando = '' then
          Texto(Copy(AHtml, I, Q - I));
        I := Q;
        Continue;
      end;
      if Copy(AHtml, I, 4) = '<!--' then
      begin
        Q := PosEx('-->', AHtml, I + 4);
        if Q = 0 then
          Break;
        I := Q + 3;
        Continue;
      end;
      Q := PosEx('>', AHtml, I);
      if Q = 0 then
        Break;
      Tag := Copy(AHtml, I + 1, Q - I - 1);
      I := Q + 1;
      Cierre := Tag.StartsWith('/');
      Nom := NombreDeEtiqueta(Tag);
      if Nom = '' then
        Continue;
      // dentro de lo que se salta: solo cuenta abrir y cerrar la misma
      if Saltando <> '' then
      begin
        if Nom = Saltando then
          if Cierre then
          begin
            Dec(Profundidad);
            if Profundidad = 0 then
              Saltando := '';
          end
          else if not Tag.EndsWith('/') then
            Inc(Profundidad);
        Continue;
      end;
      if not Cierre and not MatchText(Nom, VACIAS) and not Tag.EndsWith('/') and
         (MatchText(Nom, ['script', 'style']) or ClaseTiene(Tag, 'cpp') or
          ClaseTiene(Tag, 'appmethod') or
          // la caja de secciones, la barra de la clase y las casillas del filtro
          // de una lista de miembros ("InheritedProtected" al principio)
          MatchText(AtributoDe(Tag, 'id'), ['toc', 'childlinks', 'lstfilter'])) then
      begin
        Saltando := Nom;
        Profundidad := 1;
        Continue;
      end;
      // la jerarquia de una clase: un mapa de imagen con sus ancestros, el
      // mas cercano primero
      if (Nom = 'area') and not Cierre then
      begin
        var T := AtributoDe(Tag, 'title');
        if T <> '' then
          Ancestros := Ancestros + [DecodificaEntidades(T)];
      end
      else if (Nom = 'map') and Cierre then
      begin
        if Length(Ancestros) > 0 then
        begin
          Salto(1);
          Sb.Append(MsgFmt(SF_DOCS_ANCESTROS_FMT, [string.Join(' > ', Ancestros)]));
          Salto(1);
        end;
        Ancestros := nil;
      end
      else if Nom = 'br' then
        Salto(1)
      else if (Length(Nom) = 2) and (Nom[1] = 'h') and CharInSet(Nom[2], ['1' .. '6']) then
      begin
        Salto(2);
        if not Cierre then
          Sb.Append(StringOfChar('#', Max(2, Ord(Nom[2]) - Ord('0'))) + ' ');
      end
      else if Nom = 'pre' then
      begin
        if Cierre then
        begin
          EnPre := Max(EnPre - 1, 0); // un </pre> suelto no deja el siguiente sin blancos
          Salto(1);
          Sb.Append('```');
          Salto(2);
        end
        else
        begin
          Salto(2);
          Sb.Append('```'#10);
          Inc(EnPre);
        end;
      end
      else if MatchText(Nom, ['p', 'table', 'ul', 'ol', 'dl', 'blockquote']) then
        Salto(2)
      else if MatchText(Nom, ['div', 'dt', 'dd']) then
        Salto(1)
      else if Nom = 'tr' then
      begin
        Salto(1);
        Celdas := 0;
      end
      else if MatchText(Nom, ['td', 'th']) and not Cierre then
      begin
        if Celdas > 0 then
          Sb.Append(' | ');
        Hueco := False;
        Inc(Celdas);
        Inc(EnCelda);
      end
      else if MatchText(Nom, ['td', 'th']) and Cierre then
        EnCelda := Max(EnCelda - 1, 0)
      else if (Nom = 'li') and not Cierre then
      begin
        Salto(1);
        Sb.Append('- ');
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
  // los blancos de cada linea y los huecos (la navegacion al padre ya salio:
  // EnlaceAlPadre, por su forma)
  var Lineas := Result.Split([#10]);
  var Sale := TStringBuilder.Create;
  try
    var Blancas := 0;
    for var L in Lineas do
    begin
      var T := L.TrimRight;
      if T.Trim = '' then
      begin
        Inc(Blancas);
        if Blancas > 1 then
          Continue;
      end
      else
        Blancas := 0;
      Sale.Append(T).Append(#10);
    end;
    Result := Sale.ToString.Trim;
  finally
    Sale.Free;
  end;
end;

{ La posicion (1-based) de la primera de AQue en AEn desde ADesde, sin
  distinguir mayusculas; 0 si no. }
function PosMin(const AQue, AEn: string; ADesde: Integer = 1): Integer;
begin
  Result := PosEx(AQue.ToLower, AEn.ToLower, ADesde);
end;

{ El atributo id=X (con o sin comillas) en el HTML, sin distinguir
  mayusculas: el indice enlaza "..._For_statements" y la pagina lo llama
  "..._For_Statements" (medido); 0 si no. }
function PosDeId(const AHtml, AId: string): Integer;
var
  H, Id: string;
begin
  H := AHtml.ToLower;
  Id := AId.ToLower;
  Result := Pos('id="' + Id + '"', H);
  if Result = 0 then
    Result := Pos('id=''' + Id + '''', H);
  if Result = 0 then
    Result := Pos('id=' + Id + '>', H);
  if Result = 0 then
    Result := Pos('id=' + Id + ' ', H);
end;

function TextoDeEtiqueta(const AHtml, AEtiqueta: string): string;
var
  P, Q, R: Integer;
begin
  Result := '';
  P := PosMin('<' + AEtiqueta, AHtml);
  if P = 0 then
    Exit;
  Q := PosEx('>', AHtml, P);
  R := PosMin('</' + AEtiqueta, AHtml, Q);
  if (Q = 0) or (R = 0) then
    Exit;
  Result := HtmlATexto(Copy(AHtml, Q + 1, R - Q - 1)).Replace(#10, ' ').Trim;
end;

{ El enlace al padre de una pagina de temas (en la ayuda en ingles, la linea
  'Go Up to <indice>'): se reconoce por su FORMA y no por su frase, que cambia
  con el idioma de la ayuda. La primera cursiva antes del primer titulo de
  seccion (mw-headline: la caja de contenidos lleva su propio h2), con un
  texto corto sin etiquetas, UN enlace y nada mas. Medido el 2-oct-2026 en las
  7.497 paginas de topics.chm: coge 7.282 y ninguna que no lo sea; se le
  escapa una (Services.htm, que empieza por un titulo). Sale del contenido y
  queda en AEnlace. }
function EnlaceAlPadre(var AContenido: string; out AEnlace: TEnlace): Boolean;
var
  P, Q, A, B, C, Limite: Integer;
  Interior, Antes, Texto: string;
begin
  Result := False;
  AEnlace := Default(TEnlace);
  Limite := PosMin('mw-headline', AContenido);
  if Limite = 0 then
    Limite := Length(AContenido) + 1;
  P := PosMin('<i>', AContenido);
  if (P = 0) or (P > Limite) then
    Exit;
  Q := PosMin('</i>', AContenido, P);
  if Q = 0 then
    Exit;
  Interior := Copy(AContenido, P + 3, Q - P - 3);
  A := PosMin('<a ', Interior);
  if A = 0 then
    Exit;
  Antes := Copy(Interior, 1, A - 1);
  if (Antes.IndexOf('<') >= 0) or (Length(Antes.Trim) > 30) then
    Exit;
  B := PosEx('>', Interior, A);
  C := PosMin('</a>', Interior, A);
  if (B = 0) or (C < B) or (Copy(Interior, C + 4, MaxInt).Trim <> '') then
    Exit;
  Texto := Copy(Interior, B + 1, C - B - 1);
  if Texto.IndexOf('<') >= 0 then
    Exit;
  AEnlace.Texto := DecodificaEntidades(Texto).Trim;
  AEnlace.Href := AtributoDe(Copy(Interior, A + 1, B - A - 1), 'href');
  if (AEnlace.Texto = '') or (AEnlace.Href = '') then
    Exit;
  Delete(AContenido, P, Q + 4 - P);
  Result := True;
end;

{ ---------------------------------------------- las secciones de una pagina }

type
  { Un titulo de seccion: en las paginas de la ayuda (MediaWiki) su ancla va
    en un <span class=mw-headline id=X> dentro del <hN>. }
  TTituloDoc = record
    Pos: Integer;     // el '<' de su <hN>
    Nivel: Integer;
    Ancla, Texto: string;
  end;

{ El <hN> donde esta la posicion AP: el primero hacia atras; 0 si no hay.
  Tambien el que abre el contenido (posicion 1): antes no contaba, y la
  primera seccion de una pagina que empieza por un titulo (Services.htm) "no
  estaba" (lo encontro su prueba unitaria, 4-oct-2026). }
function InicioDeTitulo(const AContenido: string; AP: Integer): Integer;
begin
  Result := AP;
  while (Result >= 1) and not ((AContenido[Result] = '<') and (Result < Length(AContenido)) and
    CharInSet(AContenido[Result + 1], ['h', 'H']) and (Result + 2 <= Length(AContenido)) and
    CharInSet(AContenido[Result + 2], ['1' .. '6'])) do
    Dec(Result);
end;

{ El primer <hN> desde ADesde (1 o mas) con N <= ANivel; 0 si no hay. ABajo
  es el contenido en minusculas. }
function SiguienteTitulo(const ABajo: string; ADesde, ANivel: Integer): Integer;
begin
  Result := PosEx('<h', ABajo, ADesde);
  while (Result > 0) and not ((Result + 2 <= Length(ABajo)) and
    CharInSet(ABajo[Result + 2], ['1' .. '6']) and
    (Ord(ABajo[Result + 2]) - Ord('0') <= ANivel)) do
    Result := PosEx('<h', ABajo, Result + 1);
end;

{ La caja de contenidos (<div id=toc>, con el h2 de su titulo, que no es una
  seccion): desde su id hasta el </ul> al que sigue su </div> - lleva listas
  dentro de listas: en el primer </ul> se quedaban 3 de 40 (medido). False si
  la pagina no tiene, o no cierra. }
function CajaDeContenidos(const AContenido, ABajo: string; out AIni, AFin: Integer): Boolean;
begin
  AIni := PosDeId(AContenido, 'toc');
  AFin := AIni;
  if AIni > 0 then
    repeat
      AFin := PosEx('</ul>', ABajo, AFin + 1);
    until (AFin = 0) or Copy(ABajo, AFin + 5, 40).TrimLeft.StartsWith('</div>');
  Result := (AIni > 0) and (AFin > 0);
end;

{ Los titulos con ancla del contenido, en orden (la caja de contenidos lleva
  su propio h2 sin ancla: no sale). Son las secciones de la pagina: las que
  lista "sections" y las que busca SeccionDe, de aqui las dos. }
function TitulosDe(const AContenido, ABajo: string): TArray<TTituloDoc>;
var
  P, A, Q, F: Integer;
  T: TTituloDoc;
begin
  Result := nil;
  P := Pos('mw-headline', ABajo);
  while P > 0 do
  begin
    T.Pos := InicioDeTitulo(AContenido, P);
    A := P;
    while (A > 1) and (AContenido[A] <> '<') do
      Dec(A);
    Q := PosEx('>', AContenido, P);
    F := PosEx('</h', ABajo, Q);
    if (T.Pos > 0) and (A > T.Pos) and (Q > 0) and (F > 0) then
    begin
      T.Nivel := Ord(AContenido[T.Pos + 2]) - Ord('0');
      T.Ancla := AtributoDe(Copy(AContenido, A + 1, Q - A - 1), 'id');
      // todo lo de dentro del titulo, como lo escribe el texto de la pagina
      // (TextoDeEtiqueta hace lo mismo; un <span> anidado no lo corta)
      T.Texto := HtmlATexto(Copy(AContenido, Q + 1, F - Q - 1)).Replace(#10, ' ').Trim;
      if T.Ancla <> '' then
        Result := Result + [T];
    end;
    P := PosEx('mw-headline', ABajo, P + 11);
  end;
end;

{ Un titulo o un ancla para compararlos como los copiaria el agente: sin
  mayusculas, '_', ' ' y el espacio duro dan igual, y sin las # de delante
  ("## Helper Syntax" tal cual sale en el texto). }
function NormalizaTitulo(const S: string): string;
begin
  Result := S.Replace('_', ' ').Replace(#$A0, ' ').Replace('`', '').Trim.TrimLeft(['#']).Trim.ToLower;
end;

{ La seccion AAncla del contenido: desde su titulo (AQ) hasta el siguiente de
  su nivel o mas alto (AR, 0 = hasta el final). Se busca por su ancla y, si no
  esta, por su titulo como se lee: el agente ve "## Helper Syntax" y el ancla
  es Helper_Syntax, y en 826 paginas de topics.chm el ancla ni siquiera es el
  titulo con '_' (Code_Insight_.28LSP.29_improvements; medido el 4-oct-2026).
  La que envuelve la pagina -ningun otro titulo de su nivel o mas alto-
  acababa al final de la pagina: en las de la API todo cuelga de Description
  (See Also, Code Examples, Exceptions...; 10.806 paginas en system.chm y
  18.571 en vcl.chm, 38 en topics.chm). Esa acaba en su primer subtitulo con
  ancla, y ASubsecciones dice las anclas de los que siguen. AAnclaReal, la de
  la pagina. ATitulos, los de TitulosDe. }
function SeccionDe(const AContenido, ABajo, AAncla: string;
  const ATitulos: TArray<TTituloDoc>; out AQ, AR: Integer;
  out AAnclaReal: string; out ASubsecciones: TArray<string>): Boolean;
var
  P, Nivel, I, CajaIni, CajaFin: Integer;
  T: TTituloDoc;
  Real: string;
  Caja, Envuelve: Boolean;
begin
  Result := False;
  AQ := 0;
  AR := 0;
  AAnclaReal := '';
  ASubsecciones := nil;
  P := PosDeId(AContenido, AAncla);
  if P > 0 then
  begin
    // contesta con el ancla de la pagina, no con la tecleada: el indice
    // escribe ..._For_statements y la pagina ..._For_Statements (revision)
    Real := AAncla;
    for T in ATitulos do
      if SameText(T.Ancla, AAncla) then
      begin
        Real := T.Ancla;
        Break;
      end;
  end
  else
    for T in ATitulos do
      if (NormalizaTitulo(T.Texto) = NormalizaTitulo(AAncla)) or
         (NormalizaTitulo(T.Ancla) = NormalizaTitulo(AAncla)) then
      begin
        P := T.Pos;
        Real := T.Ancla;
        Break;
      end;
  if P = 0 then
    Exit;
  // un ancla de antes del primer titulo no tiene titulo, y el h2 de la caja
  // de contenidos no es una seccion (pintaba la caja como texto; revision)
  Caja := CajaDeContenidos(AContenido, ABajo, CajaIni, CajaFin);
  AQ := InicioDeTitulo(AContenido, P);
  if (AQ = 0) or (Caja and (AQ >= CajaIni) and (AQ <= CajaFin)) then
  begin
    AQ := 0;
    Exit;
  end;
  Nivel := Ord(AContenido[AQ + 2]) - Ord('0');
  AR := SiguienteTitulo(ABajo, AQ + 1, Nivel);
  if AR = 0 then
  begin
    // envuelve la pagina si tampoco la precede ninguno de su nivel o mas
    // alto, con ancla o sin ella: la misma cuenta que decide donde acaba
    // (solo con los de ancla, uno sin ella delante la daba por envoltorio;
    // revision). El de la caja de contenidos no cuenta
    Envuelve := True;
    I := SiguienteTitulo(ABajo, 1, Nivel);
    while Envuelve and (I > 0) and (I < AQ) do
    begin
      if not (Caja and (I >= CajaIni) and (I <= CajaFin)) then
        Envuelve := False;
      I := SiguienteTitulo(ABajo, I + 1, Nivel);
    end;
    // corta en el primer subtitulo CON ancla: uno sin ella (1.043 en
    // topics.chm) se queda dentro, porque no se puede pedir aparte; sin
    // ninguno con ancla, la seccion entera, como antes
    if Envuelve then
      for T in ATitulos do
        if T.Pos > AQ then
        begin
          if AR = 0 then
            AR := T.Pos;
          ASubsecciones := ASubsecciones + [T.Ancla];
        end;
  end;
  AAnclaReal := Real;
  Result := True;
end;

function PaginaComoTexto(const AHtml, AAncla: string): TPaginaDoc;
var
  Contenido, Bajo: string;
  P, Q, R: Integer;
  S: TSeccion;
  E: TEnlace;
  Titulos: TArray<TTituloDoc>;
  T: TTituloDoc;
begin
  Result := Default(TPaginaDoc);
  Result.Titulo := TextoDeEtiqueta(AHtml, 'h1');
  if Result.Titulo = '' then
    Result.Titulo := TextoDeEtiqueta(AHtml, 'title');
  // la que solo redirige: su enlace, el de la marca softredirect
  P := Pos('softredirect', AHtml);
  if P > 0 then
  begin
    Q := PosMin('href=', AHtml, P);
    if Q > 0 then
      Result.Redirige := AtributoDe(Copy(AHtml, Q - 1, 400), 'href');
  end;
  // el contenido: de la caja del articulo a sus categorias (o el body)
  P := PosDeId(AHtml, 'mw-content-text');
  if P > 0 then
  begin
    P := PosEx('>', AHtml, P) + 1;
    Q := PosDeId(AHtml, 'catlinks');
    if Q > P then
      Q := LastDelimiter('<', Copy(AHtml, 1, Q))
    else
      Q := Length(AHtml) + 1;
  end
  else
  begin
    P := PosMin('<body', AHtml);
    if P > 0 then
      P := PosEx('>', AHtml, P) + 1
    else
      P := 1;
    Q := PosMin('</body', AHtml, P);
    if Q = 0 then
      Q := Length(AHtml) + 1;
  end;
  Contenido := Copy(AHtml, P, Q - P);
  // el enlace al padre, fuera del texto: el primero de Enlaces
  if EnlaceAlPadre(Contenido, E) then
    Result.Enlaces := [E];
  Bajo := Contenido.ToLower;
  // las secciones: sus titulos con ancla. Antes salian de la caja de
  // contenidos, que MediaWiki no pone con menos de cuatro titulos: una pagina
  // larga sin ella no ofrecia secciones; ahora un lector para "sections" y
  // para SeccionDe (revision de la 1.12.0)
  Titulos := TitulosDe(Contenido, Bajo);
  for T in Titulos do
  begin
    S.Ancla := T.Ancla;
    S.Titulo := T.Texto;
    Result.Secciones := Result.Secciones + [S];
  end;
  // la barra de una clase: <ul id=childlinks> con su padre y sus miembros
  P := PosDeId(Contenido, 'childlinks');
  if P > 0 then
  begin
    R := PosEx('</ul>', Bajo, P);
    P := PosEx('<a ', Bajo, P);
    while (P > 0) and ((R = 0) or (P < R)) do
    begin
      Q := PosEx('>', Contenido, P);
      E.Href := AtributoDe(Copy(Contenido, P + 1, Q - P - 1), 'href');
      E.Texto := DecodificaEntidades(Copy(Contenido, Q + 1, PosEx('<', Contenido, Q) - Q - 1)).Trim;
      if (E.Href <> '') and (E.Texto <> '') then
        Result.Enlaces := Result.Enlaces + [E];
      P := PosEx('<a ', Bajo, Q);
    end;
  end;
  // una seccion: desde su titulo hasta el siguiente de su nivel o mas alto
  // (SeccionDe: por su ancla o su titulo, y la que envuelve la pagina)
  if (AAncla <> '') and SeccionDe(Contenido, Bajo, AAncla, Titulos, Q, R,
    Result.Ancla, Result.Subsecciones) then
  begin
    if R = 0 then
      R := Length(Contenido) + 1;
    Contenido := Copy(Contenido, Q, R - Q);
    Result.AnclaEncontrada := True;
  end;
  Result.Texto := HtmlATexto(Contenido);
end;

{ ------------------------------------------------- la ayuda instalada }

function AyudasInstaladas: TArray<TAyudaInstalada>;
var
  Info: TRadStudioInfo;
  Vars: TStringList;
  A: TAyudaInstalada;
  F, Base: string;
  N: Integer;
  Hechas: TArray<TAyudaInstalada>;

  // (la lista va aparte: dentro de esta funcion, Result es su Boolean)
  function Usado(const ACorto: string): Boolean;
  begin
    for var X in Hechas do
      if X.Corto = ACorto then
        Exit(True);
    Result := False;
  end;

  function Vista(const AFichero: string): Boolean;
  begin
    for var X in Hechas do
      if SameText(X.Fichero, AFichero) then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  Hechas := nil;
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit;
  Vars := TStringList.Create;
  try
    // LA tabla de macros del IDE ($(BDS), $(BDSCOMMONDIR), el catalogo de
    // GetIt...), la de Lsp.Guard: una propia con solo $(BDS) perdia en
    // silencio la ayuda registrada con otra macro (revision de la 1.10.0)
    IdeMacroVars(Info, Vars);
    for var H in IdeHelpFiles(Info.Version) do
    begin
      F := ExpandIdeMacros(H.Fichero, Vars);
      // el mismo fichero dos veces (con $(BDS) en una rama del registro y su
      // ruta en la otra) es una ayuda, no dos
      if not TFile.Exists(F) or Vista(F) then
        Continue;
      Base := LowerCase(ChangeFileExt(ExtractFileName(F), ''));
      // dos ayudas con el mismo nombre de fichero: la segunda, con numero
      A.Corto := Base;
      N := 2;
      while Usado(A.Corto) do
      begin
        A.Corto := Base + IntToStr(N);
        Inc(N);
      end;
      A.Fichero := F;
      A.Fecha := TFile.GetLastWriteTime(F);
      Hechas := Hechas + [A];
    end;
  finally
    Vars.Free;
  end;
  Result := Hechas;
end;

type
  { Los .chm abiertos durante UNA llamada (mismo hilo), por nombre corto. }
  TAbiertos = class
  private
    FAyudas: TArray<TAyudaInstalada>;
    FChm: TObjectDictionary<string, TChm>;
  public
    constructor Create(const AAyudas: TArray<TAyudaInstalada>);
    destructor Destroy; override;
    function Chm(const ACorto: string): TChm;   // nil si no es de las instaladas
    function Ayuda(const ACorto: string; out AAyuda: TAyudaInstalada): Boolean;
    function Html(const AId: string; out AHtml: string): Boolean;
  end;

constructor TAbiertos.Create(const AAyudas: TArray<TAyudaInstalada>);
begin
  inherited Create;
  FAyudas := AAyudas;
  FChm := TObjectDictionary<string, TChm>.Create([doOwnsValues]);
end;

destructor TAbiertos.Destroy;
begin
  FChm.Free;
  inherited;
end;

function TAbiertos.Ayuda(const ACorto: string; out AAyuda: TAyudaInstalada): Boolean;
begin
  for var A in FAyudas do
    if SameText(A.Corto, ACorto) then
    begin
      AAyuda := A;
      Exit(True);
    end;
  Result := False;
end;

function TAbiertos.Chm(const ACorto: string): TChm;
var
  A: TAyudaInstalada;
begin
  if FChm.TryGetValue(ACorto.ToLower, Result) then
    Exit;
  Result := nil;
  if not Ayuda(ACorto, A) then
    Exit;
  try
    Result := TChm.Create(A.Fichero);
  except
    Result := nil; // una ayuda que Windows no abre no tumba la busqueda
  end;
  // tambien la que no abre: no se reintenta en cada candidato
  FChm.Add(ACorto.ToLower, Result);
end;

function TAbiertos.Html(const AId: string; out AHtml: string): Boolean;
var
  Corto, Pagina, Ancla: string;
  C: TChm;
  B: TArray<Byte>;
begin
  AHtml := '';
  Result := PartesDeId(AId, Corto, Pagina, Ancla);
  if not Result then
    Exit;
  C := Chm(Corto);
  Result := Assigned(C) and C.Lee(Pagina, B);
  if Result then
    AHtml := TextoDeBytes(B);
end;

{ Los mapas de una ayuda: index.hhk / index.hhc, o los que tenga con otro nombre. }
function MapasDe(AChm: TChm): TArray<TArray<Byte>>;
var
  B: TArray<Byte>;
begin
  Result := nil;
  for var N in TArray<string>.Create('index.hhk', 'index.hhc') do
    if AChm.Lee(N, B) then
      Result := Result + [B];
  if Length(Result) > 0 then
    Exit;
  for var N in AChm.Raiz do
    if EndsText('.hhk', N) or EndsText('.hhc', N) then
      if AChm.Lee(N, B) then
        Result := Result + [B];
end;

{ Cada palabra de APalabras al principio de una palabra de ATexto. }
function TodasAlPrincipio(const ATexto: string; const APalabras: TArray<string>): Boolean;
var
  K: Integer;
begin
  for var W in APalabras do
  begin
    K := ATexto.IndexOf(W);
    while (K > 0) and CharInSet(ATexto.Chars[K - 1], ['a' .. 'z', '0' .. '9', '_']) do
      K := ATexto.IndexOf(W, K + 1);
    if K < 0 then
      Exit(False);
  end;
  Result := True;
end;

function PuntosDeEntrada(const AE: TEntradaDeMapa; const AConsulta: string;
  const APalabras: TArray<string>): Integer;
var
  Nom, Base: string;
begin
  Nom := AE.Nombre.ToLower;
  Result := PuntosDePalabra(Nom, AConsulta);
  // el nombre cualificado de la pagina: System.SysUtils.FormatDateTime.htm
  Base := LowerCase(ChangeFileExt(NombreDePagina(AE.Local), ''));
  if (Base = AConsulta) or Base.EndsWith('.' + AConsulta) then
    Result := Max(Result, 110);
  // un concepto de varias palabras, por el titulo: "class helpers" en
  // "Class and Record Helpers"
  if (Length(APalabras) > 1) and TodasAlPrincipio(Nom, APalabras) then
    Result := Max(Result, 50 - Min(Max(Length(Nom) - Length(AConsulta), 0), 25));
end;

function BuscaEnLaAyuda(const AAyudas: TArray<TAyudaInstalada>;
  const AConsulta, AFramework: string; ALimite: Integer;
  out ATotal, AAbiertas: Integer): TArray<TResultadoDoc>;
var
  Q, Aguja, Fw, Html, Destino, Clase, Miembro, Base, Id, Corto, Pagina, Ancla: string;
  Palabras: TArray<string>;
  Abiertos: TAbiertos;
  Cand: TDictionary<string, Integer>;
  Paginas: TDictionary<string, Boolean>;
  Lista: TList<TResultadoDoc>;
  R: TResultadoDoc;
  C: TChm;
  B: TArray<Byte>;
  P: Integer;

  procedure Suma(const AId: string; APuntos: Integer);
  var
    Ya: Integer;
  begin
    if AId = '' then
      Exit;
    if not Cand.TryGetValue(AId, Ya) or (APuntos > Ya) then
      Cand.AddOrSetValue(AId, APuntos);
  end;

  // la pagina de un id, sin su ancla: lo que cuenta como UNA pagina
  function PaginaDe(const AId: string): string;
  var
    Co, Pa, An: string;
  begin
    if PartesDeId(AId, Co, Pa, An) then
      Result := IdDePagina(Co, Pa, '').ToLower
    else
      Result := AId.ToLower;
  end;

begin
  Result := nil;
  ATotal := 0;
  AAbiertas := 0;
  Palabras := PalabrasDeConsulta(AConsulta);
  if Length(Palabras) = 0 then
    Exit;
  Q := string.Join(' ', Palabras);
  Aguja := Palabras[0];
  for var W in Palabras do
    if Length(W) > Length(Aguja) then
      Aguja := W;
  if Length(Palabras) = 1 then
    Aguja := Q;
  Fw := AFramework.Trim.ToLower;
  Abiertos := TAbiertos.Create(AAyudas);
  Cand := TDictionary<string, Integer>.Create;
  Paginas := TDictionary<string, Boolean>.Create;
  Lista := TList<TResultadoDoc>.Create;
  try
    for var A in AAyudas do
    begin
      C := Abiertos.Chm(A.Corto);
      if C = nil then
        Continue;
      Inc(AAbiertas);
      for var Mapa in MapasDe(C) do
        for var E in EntradasQueCasan(Mapa, Aguja, Palabras) do
        begin
          P := PuntosDeEntrada(E, Q, Palabras);
          // el id, por SU compositor: hecho a mano, una entrada ms-its: o
          // con barras invertidas salia distinta de la de un enlace, o no
          // salia (revision de la 1.10.0)
          if P > 0 then
            Suma(IdDeEnlace(E.Local, A.Corto), P);
        end;
    end;
    // Clase.Miembro heredado: la lista de miembros de la clase lo enlaza
    // (TFDQuery.ExecSQL esta en TFDCustomQuery.ExecSQL; medido)
    if (Cand.Count = 0) and (Length(Palabras) = 1) and Q.Contains('.') then
    begin
      Clase := Q.Substring(0, Q.LastIndexOf('.'));
      Miembro := UltimoTrozo(Q);
      if (Clase <> '') and (Miembro <> '') then
        for var A in AAyudas do
        begin
          C := Abiertos.Chm(A.Corto);
          if C = nil then
            Continue;
          for var N in C.Raiz do
          begin
            Base := N.ToLower;
            if not (Base.EndsWith('.' + Clase + '_methods.htm') or
               Base.EndsWith('.' + Clase + '_properties.htm') or
               Base.EndsWith('.' + Clase + '_events.htm') or
               (Base = Clase + '_methods.htm') or (Base = Clase + '_properties.htm') or
               (Base = Clase + '_events.htm')) then
              Continue;
            if not C.Lee(N, B) then
              Continue;
            Html := TextoDeBytes(B);
            P := PosMin('href=', Html);
            while P > 0 do
            begin
              Destino := AtributoDe(Copy(Html, P - 1, 400), 'href');
              if EndsText('.' + Miembro + '.htm', SinAncla(Destino)) then
                Suma(IdDeEnlace(Destino, A.Corto), 90);
              P := PosMin('href=', Html, P + 5);
            end;
          end;
        end;
    end;
    // el total, en paginas: una pagina con sus anclas es una
    for var K in Cand.Keys do
      Paginas.AddOrSetValue(PaginaDe(K), True);
    ATotal := Paginas.Count;
    for var Par in Cand do
    begin
      R.Id := Par.Key;
      R.Puntos := Par.Value;
      R.Titulo := '';
      Base := '';
      if PartesDeId(R.Id, Corto, Pagina, Ancla) then
        Base := NombreDePagina(Pagina).ToLower;
      // framework=fmx|vcl: la pagina de ese, antes
      if (Fw = 'fmx') and Base.StartsWith('fmx.') or (Fw = 'vcl') and Base.StartsWith('vcl.') then
        Inc(R.Puntos, 15)
      else if (Fw = 'fmx') and Base.StartsWith('vcl.') or (Fw = 'vcl') and Base.StartsWith('fmx.') then
        Dec(R.Puntos, 15);
      // lo que es de C++ (ejemplos "(C++)", temas de C++Builder), mas abajo:
      // quien pregunta aqui escribe Delphi
      if Base.Contains('c++') then
        Dec(R.Puntos, 40);
      Lista.Add(R);
    end;
    Lista.Sort(TComparer<TResultadoDoc>.Construct(
      function(const L, R: TResultadoDoc): Integer
      begin
        Result := R.Puntos - L.Puntos;
        if Result = 0 then
          Result := Length(L.Id) - Length(R.Id);
        if Result = 0 then
          Result := CompareText(L.Id, R.Id);
      end));
    // las que solo redirigen salen como su destino, cada una con su titulo,
    // y cada pagina UNA vez: sus anclas (FMX.Objects.htm, #Types, #Classes)
    // ocupaban tres puestos de cinco (medido en la revision de la 1.10.0)
    Paginas.Clear;
    for R in Lista do
    begin
      if Length(Result) >= ALimite then
        Break;
      Id := R.Id;
      if not Abiertos.Html(Id, Html) then
        Continue;
      if Pos('softredirect', Html) > 0 then
      begin
        var Pag := PaginaComoTexto(Html, '');
        if not PartesDeId(Id, Corto, Pagina, Ancla) then
          Continue;
        Id := IdDeEnlace(Pag.Redirige, Corto);
        if (Id = '') or not Abiertos.Html(Id, Html) then
          Continue;
      end;
      if Paginas.ContainsKey(PaginaDe(Id)) then
        Continue;
      Paginas.Add(PaginaDe(Id), True);
      var Final := R;
      Final.Id := Id;
      Final.Titulo := TextoDeEtiqueta(Html, 'title');
      Result := Result + [Final];
    end;
  finally
    Lista.Free;
    Paginas.Free;
    Cand.Free;
    Abiertos.Free;
  end;
end;

function LeePaginaDeLaAyuda(const AAyudas: TArray<TAyudaInstalada>;
  var AId: string; out APagina: TPaginaDoc; out AAyuda: TAyudaInstalada): TLecturaDoc;
var
  Corto, Pagina, Ancla, AnclaPedida, Html: string;
  Abiertos: TAbiertos;
begin
  APagina := Default(TPaginaDoc);
  AAyuda := Default(TAyudaInstalada);
  if not PartesDeId(AId, Corto, Pagina, Ancla) then
    Exit(ldIdMalFormado);
  Abiertos := TAbiertos.Create(AAyudas);
  try
    if not Abiertos.Ayuda(Corto, AAyuda) then
      Exit(ldSinPagina);
    if Abiertos.Chm(Corto) = nil then
      Exit(ldNoAbre);
    if not Abiertos.Html(AId, Html) then
      Exit(ldSinPagina);
    APagina := PaginaComoTexto(Html, Ancla);
    // la que solo redirige: su destino, una vez
    if APagina.Redirige <> '' then
    begin
      AnclaPedida := Ancla;
      var Destino := IdDeEnlace(APagina.Redirige, Corto);
      var Html2: string;
      if (Destino <> '') and Abiertos.Html(Destino, Html2) then
      begin
        PartesDeId(Destino, Corto, Pagina, Ancla);
        // la seccion pedida viaja con la redireccion si el destino no trae
        // otra: topics:FormatDateTime.htm#Description daba la pagina entera,
        // sin decirlo (revision de la 1.10.0)
        if Ancla = '' then
          Ancla := AnclaPedida;
        Abiertos.Ayuda(Corto, AAyuda);
        APagina := PaginaComoTexto(Html2, Ancla);
        AId := IdDePagina(Corto, Pagina, Ancla);
      end;
    end;
    Result := ldLeida;
  finally
    Abiertos.Free;
  end;
end;

end.
