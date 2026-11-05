unit Lsp.ClausulaUses;

{ LA CLAUSULA uses (y contains) COMO TEXTO: encontrarla (FindUses, tambien
  partida en ramas de condicionales), trocearla en entradas y leer cada una
  (LeeEntradaDeUses y sus preguntas), reescribirla quitando o anadiendo con
  sus comentarios y directivas en su sitio (ReplaceUses, EntriesWithout,
  UsesCompacta), estrenarla, y donde estan las secciones de una unit. Sin
  ficheros ni proyectos: eso lo pone Lsp.ProjectUnits, que la usa. Vivia en
  Lsp.ProjectUnits (V94 de la depuracion de la 1.23, B6 de la 1.28): se mudo
  sin cambiar una linea. }

interface

// EL escritor de una entrada del uses de un programa (o del contains de un
// paquete), como la escribe el IDE: Unidad in 'ruta', con su comentario
// {Form} o {Form: Clase} si AForm no es ''; la ruta con sus comillas
// dobladas. Su lector es LeeEntradaDeUses.
function EntradaDelUses(const AUnidad, AInclude, AForm, ADesignClass: string): string;
{ Las unidades de los uses de un fuente (AText), en el orden en que dcc las
  mira: las de interface y luego las de implementation; la ULTIMA gana cuando
  dos declaran un mismo nombre (medido con dcc, V132b de la 1.25). Con
  ASoloInterface, lo que ve el codigo del interface. De un .dpr, la suya. }
function UsesEnOrden(const AText: string; ASoloInterface: Boolean = False): TArray<string>;

{ UNA lista de nombres de unit de quien llama, cortada por ; , o blanco: adduses
  y removeuses no cortaban por el blanco y requires si (P13 del revisor). }
function NombresDeUnidades(const ALista: string): TArray<string>;

{ Donde acaba ENTERO el uses de un programa (ADpr, su texto): el indice de su
  ';' o, partido en ramas, el del condicional que las cierra. 0 si no tiene. }
function FinDelUsesDelPrograma(const ADpr: string): Integer;
{ Donde empieza (1-based) el condicional ABIERTO mas externo al final de
  ATexto - el primer IF, IFDEF, IFNDEF o IFOPT sin su ENDIF/IFEND -; 0 si no
  queda ninguno abierto. Por EL lector de directivas. La frontera de un
  insert lo pregunta: un initialization dentro de un IFDEF DEBUG metia la
  rutina DENTRO del bloque (W1 del revisor de cierre de la 1.18.2). }
function PrimerCondicionalAbierto(const ATexto: string): Integer;

{ LA regla de la seccion (interface|implementation) de una unit: la posicion
  1-based detras de su palabra en ACodigo (la vista CodigoPascal), 0 si no
  esta. La de adduses, el renombrado y la declaracion de una rutina visible. }
function FinDeSeccion(const ACodigo, ASec: string): Integer;
{ ...y la misma por LINEAS, para quien lee el fuente linea a linea
  (LineasDelTexto: el mismo salto que LineaDePosicion): la linea 0-based de
  su palabra y, en ella, la columna 1-based donde empieza (AColIni) y la de
  detras (AColFin). False si no esta. El resumen del interface de
  delphi_symbols buscaba una linea que solo dijera la palabra (revisor del
  paisaje de la 1.27, B2). }
function SeccionEnLineas(const ACodigo, ASec: string; out ALinea, AColIni, AColFin: Integer): Boolean;

type
  TUsesClause = record
    Found: Boolean;
    StartPos: Integer;  // index (1-based) of the 'u' of 'uses'
    EndPos: Integer;    // index of the closing ';'
    Entries: TArray<string>; // raw entry texts, trimmed
    Keyword: string;    // 'uses' (program/library) o 'contains' (package)
    // Partida en RAMAS ({$IFDEF X} a, b; {$ELSE} c; {$ENDIF}): su ';' cierra
    // una rama y las otras siguen detras. Se LEEN (OtrasRamas) y ningun
    // escritor la toca: no sabe en que rama va una unit (el muro del 26-sep).
    EnRamas: Boolean;
    OtrasRamas: TArray<string>;
    // donde acaba la clausula ENTERA: EndPos, o en ramas, el condicional que
    // las cierra (lo que mira el renombrado de una unit: sus entradas)
    FinRamas: Integer;
  end;

type
  // Una entrada de una clausula uses o contains, como la escribe
  // EntradaDelUses: Unidad in 'ruta' {Form: Clase}
  TEntradaDeUses = record
    Prefijo: string;     // comentarios y directivas de delante (SplitEntryPrefix)
    Nombre: string;      // la unit, con sus puntos; '' si no empieza por una
    Include: string;     // la ruta del in, con sus comillas ya sin doblar
    Form: string;        // el comentario del IDE detras de la ruta
    DesignClass: string;
    Resto: string;       // lo que va detras de todo eso
    // detras de lo suyo solo hay comentarios, directivas o blancos. Una
    // comilla sin cerrar deja codigo aqui: el ';' de la clausula no era el
    // suyo, y lo de detras (begin...) caia dentro de la entrada
    Legible: Boolean;
  end;

{ Lo que Lsp.ProjectUnits usa de la clausula (cada una explicada en su cuerpo):
  encontrarla, leer y reescribir sus entradas, estrenarla, las dos clausulas
  de una unit y la linea de una posicion. Publicas desde que la clausula se
  mudo aqui (B6 de la 1.28). }
function FindUses(const Dpr: string; AFrom: Integer = 0; const APalabra: string = ''): TUsesClause;
function ClausulaQueNoSeReescribe(const U: TUsesClause; const AFichero: string): string;
function ComentarioTrasElCierre(const ATexto: string; AFin: Integer; AUnaLinea: Boolean;
  out AIni, ALargo: Integer): Boolean;
function EntradaReescrita(const AEntrada, ANueva: string): string;
function EntriesWithout(const AEntries: TArray<string>; const AUnitName: string): TArray<string>;
function EntryFormName(const Entry: string): string;
function EntryInclude(const Entry: string): string;
function EntryUnitName(const Entry: string): string;
procedure EstrenaClausula(var AText: string; APos: Integer; const AEntradas: string;
  AEnLinea: Boolean = False);
function EstrenaUsesTrasCabecera(var AText: string; const AEntradas: string): Boolean;
function InicioDeLaLinea(const ATexto: string; APos: Integer): Integer;
function LeeEntradaDeUses(const AEntrada: string): TEntradaDeUses;
function NegativaDeEntradaIlegible(const AKeyword, AFichero, AEntrada: string): string;
function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
function UsesDeLaOtraSeccion(const AText, ABlank, ASec: string; out AOtra: string): TUsesClause;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.RegularExpressions,
  System.Character,
  Lsp.Texts,
  Lsp.Pascal,
  Lsp.Lineas;

{ Splits the clause body on top-level commas (outside quotes, comments and
  directives; those stay glued to the entry they precede or follow). }
function SplitEntries(const Body: string): TArray<string>;
var
  I, N: Integer;
  Cur: string;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    Cur := '';
    I := 1;
    while I <= Length(Body) do
    begin
      N := CommentLen(Body, I);
      if N = 0 then
        N := QuoteLen(Body, I);
      if N > 0 then
      begin
        Cur := Cur + Copy(Body, I, N);
        Inc(I, N);
        Continue;
      end;
      if Body[I] = ',' then
      begin
        if Cur.Trim <> '' then
          L.Add(Cur.Trim);
        Cur := '';
      end
      else
        Cur := Cur + Body[I];
      Inc(I);
    end;
    if Cur.Trim <> '' then
      L.Add(Cur.Trim);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

{ La clausula de units del proyecto: `uses` tras `program X;` (o `library`),
  y `contains` tras `package X;` - en un paquete la `requires` que va antes
  se salta entera. Nunca una dentro de un comentario; cerrada por el primer
  `;` fuera de comillas y comentarios. }
const
  // las combinaciones de ramas que ListaEnCadaRama recorre como mucho
  MAX_COMBINACIONES_DE_RAMAS = 256;

// EL paseo por los condicionales de ATexto (los que abren y los que cierran,
// por CondicionalDe), por EL lector de directivas: AAbiertos, los que
// quedan abiertos al final (negativo con un cierre de mas), y APrimero, donde
// empieza el abierto mas EXTERNO (0 si no queda ninguno)
procedure RecorreCondicionales(const ATexto: string; out AAbiertos, APrimero: Integer);
var
  Pila: TArray<Integer>;
begin
  AAbiertos := 0;
  Pila := [];
  for var D in DirectivasPascal(ATexto) do
    if CondicionalDe(D.Nombre) = cdAbre then
    begin
      Inc(AAbiertos);
      Pila := Pila + [D.Inicio];
    end
    else if CondicionalDe(D.Nombre) = cdCierra then
    begin
      Dec(AAbiertos);
      if Length(Pila) > 0 then
        SetLength(Pila, Length(Pila) - 1);
    end;
  APrimero := 0;
  if Length(Pila) > 0 then
    APrimero := Pila[0];
end;

// Los condicionales que quedan ABIERTOS al final de ATexto.
function CondicionalesAbiertos(const ATexto: string): Integer;
var
  Primero: Integer;
begin
  RecorreCondicionales(ATexto, Result, Primero);
end;

function PrimerCondicionalAbierto(const ATexto: string): Integer;
var
  Abiertos: Integer;
begin
  RecorreCondicionales(ATexto, Abiertos, Result);
end;

// True si ATexto lleva alguna directiva condicional (abre, cambia de rama o
// cierra): entre una coma y el nombre de su entrada, las pone en regiones
// distintas (EntriesWithout)
function LlevaCondicional(const ATexto: string): Boolean;
begin
  for var D in DirectivasPascal(ATexto) do
    if CondicionalDe(D.Nombre) <> cdNinguno then
      Exit(True);
  Result := False;
end;

// LA COMPROBACION DE UN USES CON CONDICIONALES, la unica gramatica propia de
// esta unidad para ellos: no hay juez, dcc solo compila la rama de los
// simbolos que tiene. En CADA combinacion de ramas, lo activo tiene que ser
// una lista - entradas separadas por comas, sin coma al principio, al final
// ni dos seguidas, y al menos una entrada. Dos trozos de entrada seguidos
// con solo una directiva en medio cuentan como una entrada partida, no como
// dos. 1 = alguna rama la rompe; 0 = todas bien; -1 = no se puede juzgar (un
// condicional que abre o cierra fuera de la clausula, o mas de
// MAX_COMBINACIONES_DE_RAMAS): quien pregunta no niega por eso. ACuerpo, la
// clausula sin su palabra (uses / contains), con o sin su ';'. Revisor de
// version de la 1.18.0: removeuses dejaba una coma fuera de su condicional.
function ListaEnCadaRama(const ACuerpo: string): Integer;
type
  TEvento = record
    Clase: Integer; // 0 un trozo de entrada, 1 una coma, 2 abre, 3 rama, 4 cierra
    Bloque: Integer;
  end;
var
  Eventos: TArray<TEvento>;
  Ramas: TArray<Integer>;     // las ramas de cada bloque
  ConElse: TArray<Boolean>;   // ...y si una de ellas es un ELSE (si no, cabe "ninguna")
  Pila: TArray<Integer>;

  procedure Anota(AClase, ABloque: Integer);
  var
    Ev: TEvento;
  begin
    Ev.Clase := AClase;
    Ev.Bloque := ABloque;
    Eventos := Eventos + [Ev];
  end;

begin
  Eventos := [];
  Ramas := [];
  ConElse := [];
  Pila := [];
  var Clases := ClasesPascal(ACuerpo);
  var Ds := DirectivasPascal(ACuerpo);
  var DI := 0;
  var EnEntrada := False;
  var I := 1;
  while I <= Length(ACuerpo) do
  begin
    if (DI <= High(Ds)) and (Ds[DI].Inicio = I) then
    begin
      var Clase := CondicionalDe(Ds[DI].Nombre);
      if Clase = cdAbre then
      begin
        Ramas := Ramas + [1];
        ConElse := ConElse + [False];
        Pila := Pila + [High(Ramas)];
        Anota(2, High(Ramas));
      end
      else if Clase in [cdRama, cdSiNo] then
      begin
        if Length(Pila) = 0 then
          Exit(-1);
        Inc(Ramas[Pila[High(Pila)]]);
        if Clase = cdSiNo then
          ConElse[Pila[High(Pila)]] := True;
        Anota(3, Pila[High(Pila)]);
      end
      else if Clase = cdCierra then
      begin
        if Length(Pila) = 0 then
          Exit(-1);
        Anota(4, Pila[High(Pila)]);
        SetLength(Pila, Length(Pila) - 1);
      end;
      EnEntrada := False;
      I := Ds[DI].Inicio + Ds[DI].Largo;
      Inc(DI);
      Continue;
    end;
    if Clases[I] in [cpCodigo, cpCadena] then
    begin
      if (Clases[I] = cpCodigo) and (ACuerpo[I] = ';') then
        Break;
      if (Clases[I] = cpCodigo) and (ACuerpo[I] = ',') then
      begin
        Anota(1, -1);
        EnEntrada := False;
      end
      else if not CharInSet(ACuerpo[I], [' ', #9, #10, #13]) then
      begin
        if not EnEntrada then
          Anota(0, -1);
        EnEntrada := True;
      end;
    end;
    Inc(I);
  end;
  if Length(Pila) > 0 then
    Exit(-1);
  // cada bloque elige una de sus ramas, o ninguna si no tiene ELSE
  var Opciones: TArray<Integer>;
  SetLength(Opciones, Length(Ramas));
  var Total := 1;
  for var B := 0 to High(Ramas) do
  begin
    Opciones[B] := Ramas[B] + (if ConElse[B] then 0 else 1);
    Total := Total * Opciones[B];
    if Total > MAX_COMBINACIONES_DE_RAMAS then
      Exit(-1);
  end;
  var Elegida, Actual: TArray<Integer>;
  SetLength(Elegida, Length(Ramas));
  SetLength(Actual, Length(Ramas));
  for var Combo := 0 to Total - 1 do
  begin
    var R := Combo;
    for var B := 0 to High(Ramas) do
    begin
      Elegida[B] := R mod Opciones[B];
      R := R div Opciones[B];
    end;
    var Abiertos: TArray<Integer> := [];
    var Estado := 0; // 0 nada todavia, 1 tras una entrada, 2 tras una coma
    for var Ev in Eventos do
      case Ev.Clase of
        2:
          begin
            Actual[Ev.Bloque] := 0;
            Abiertos := Abiertos + [Ev.Bloque];
          end;
        3:
          Inc(Actual[Ev.Bloque]);
        4:
          SetLength(Abiertos, Length(Abiertos) - 1);
      else
        begin
          var Activo := True;
          for var B in Abiertos do
            if Actual[B] <> Elegida[B] then
              Activo := False;
          if Activo then
            if Ev.Clase = 0 then
              Estado := 1
            else if Estado <> 1 then
              Exit(1) // una coma al principio o dos seguidas
            else
              Estado := 2;
        end;
      end;
    if Estado <> 1 then
      Exit(1); // una coma al final, o ninguna entrada en esta rama
  end;
  Result := 0;
end;

{ Las entradas de las OTRAS ramas de una clausula partida: de ADesde (tras el
  ';' de la primera) al condicional que la cierra. Cada rama acaba en su ';':
  se leen como una lista mas, sin las que solo son directivas. }
function EntradasDeOtrasRamas(const ATexto: string; ADesde, AAbiertos: Integer;
  out AFin: Integer): TArray<string>;
var
  Prof, Fin: Integer;
begin
  Prof := AAbiertos;
  Fin := Length(ATexto) + 1;
  for var D in DirectivasPascal(Copy(ATexto, ADesde, MaxInt)) do
  begin
    if CondicionalDe(D.Nombre) = cdAbre then
      Inc(Prof)
    else if CondicionalDe(D.Nombre) = cdCierra then
      Dec(Prof);
    if Prof <= 0 then
    begin
      Fin := ADesde + D.Inicio - 1;
      Break;
    end;
  end;
  AFin := Fin;
  Result := [];
  for var E in SplitEntries(Copy(ATexto, ADesde, Fin - ADesde).Replace(';', ',')) do
    if BlankComments(E).Trim <> '' then
      Result := Result + [E];
end;

function SinBlancosAlFinalDeLinea(const ATexto: string): string;
begin
  Result := TRegEx.Replace(ATexto, '[ \t]+(\r?\n)', '$1');
end;

{ La sangria de la primera entrada de una clausula; dos blancos si no tiene }
function SangriaDeClausula(const AClausula: string): string;
begin
  var M := TRegEx.Match(AClausula, '\n([ \t]+)\S');
  Result := (if M.Success then M.Groups[1].Value else '  ');
end;

// APalabra: otra clausula que la de la unidad, del programa o del paquete -
// 'requires', la de un paquete: la leia una regex sobre el codigo con las
// directivas en blanco, y add-requires la reescribia sin ellas (18-oct-2026)
function FindUses(const Dpr: string; AFrom: Integer = 0; const APalabra: string = ''): TUsesClause;
var
  I, N, Start, K: Integer;
  Token: string;
begin
  Result := Default(TUsesClause);
  Result.Keyword := 'uses';
  I := 1;
  if AFrom > 0 then
    // Una SECCION de un .pas (adduses, 2026-09-23): se busca desde justo
    // despues de interface/implementation, y otro token antes de la clausula
    // (type, const, procedure, la seccion siguiente...) = no hay uses ahi.
    I := AFrom
  else
  begin
    // en la vista del codigo: un 'program viejo; uses X;' dentro de un
    // comentario de arriba era la cabecera, y add-unit escribia en el uses
    // COMENTADO diciendo que lo habia hecho (sonda del lexico, 2-oct-2026)
    // EL lector de la cabecera (Lsp.Pascal): desde detras de su ';'
    var Cab: TCabeceraFuente;
    if CabeceraDeFuente(CodigoPascal(Dpr), Cab) and (Cab.Palabra <> 'unit') then
    begin
      I := Cab.Fin;
      if Cab.Palabra = 'package' then
        Result.Keyword := 'contains';
    end;
  end;
  if APalabra <> '' then
    Result.Keyword := APalabra;
  K := Length(Result.Keyword);
  Start := 0;
  while I <= Length(Dpr) do
  begin
    N := CommentLen(Dpr, I);
    if N = 0 then
      N := QuoteLen(Dpr, I);
    if N > 0 then
    begin
      Inc(I, N);
      Continue;
    end;
    if Start = 0 then
    begin
      if ((I = 1) or not EsCaracterDeIdent(Dpr[I - 1])) and (I + K - 1 <= Length(Dpr)) and
         SameText(Copy(Dpr, I, K), Result.Keyword) and
         ((I + K > Length(Dpr)) or not EsCaracterDeIdent(Dpr[I + K])) then
      begin
        Start := I;
        Inc(I, K);
        Continue;
      end;
      if EsCaracterDeIdent(Dpr[I]) then
      begin
        // another token before the clause (const, type, begin...): no clause.
        // Except `requires ...;` in a package, which comes BEFORE contains
        // and is skipped whole.
        Token := '';
        while (I <= Length(Dpr)) and EsCaracterDeIdent(Dpr[I]) do
        begin
          Token := Token + Dpr[I];
          Inc(I);
        end;
        if SameText(Token, 'requires') then
        begin
          while (I <= Length(Dpr)) and (Dpr[I] <> ';') do
          begin
            N := CommentLen(Dpr, I);
            if N = 0 then
              N := QuoteLen(Dpr, I);
            if N > 0 then
              Inc(I, N)
            else
              Inc(I);
          end;
          Inc(I); // the ';' of requires
          Continue;
        end;
        if not SameText(Token, Result.Keyword) then
          Exit;
        Start := I - K;
      end
      else
        Inc(I);
      Continue;
    end;
    if Dpr[I] = ';' then
    begin
      Result.StartPos := Start;
      Result.EndPos := I;
      Result.Found := True;
      Result.Entries := SplitEntries(Copy(Dpr, Start + K, I - (Start + K)));
      Result.FinRamas := I;
      // Un ';' DENTRO de un condicional abierto cierra una rama, no la
      // clausula: las otras ramas van detras (el uses del nodo de escritorio,
      // Windows y Linux). Se leia solo la primera.
      var Abiertos := CondicionalesAbiertos(Copy(Dpr, Start, I - Start));
      if Abiertos > 0 then
      begin
        Result.EnRamas := True;
        Result.OtrasRamas := EntradasDeOtrasRamas(Dpr, I + 1, Abiertos, Result.FinRamas);
      end;
      Exit;
    end;
    Inc(I);
  end;
end;

function FinDelUsesDelPrograma(const ADpr: string): Integer;
begin
  var U := FindUses(ADpr);
  Result := 0;
  if U.Found then
    Result := U.FinRamas;
end;

// Leading comments/directives of an entry (kept when the entry is dropped so
// a conditional directive around it stays balanced) and the bare entry text.
procedure SplitEntryPrefix(const Entry: string; out APrefix, ACore: string);
var
  I, N: Integer;
begin
  I := 1;
  while I <= Length(Entry) do
  begin
    N := CommentLen(Entry, I);
    if N > 0 then
      Inc(I, N)
    else if Entry[I].IsWhiteSpace then
      Inc(I)
    else
      Break;
  end;
  APrefix := Copy(Entry, 1, I - 1).Trim;
  ACore := Copy(Entry, I, MaxInt).Trim;
end;

{ EL lector de una entrada, el inverso de EntradaDelUses. Eran cuatro regex
  (EntryUnitName, EntryInclude, EntryFormName y la de EntradaReescrita), y
  '[^'']+' cortaba la ruta en su primera comilla: la de 'David''s units'
  salia 'David', y remove-unit dejaba su DCCReference en el .dproj (medido
  el 25-oct-2026). La cadena la mide el lexico de la casa (QuoteLen: dos
  comillas son una suya, y una sin cerrar acaba en su linea). }
function LeeEntradaDeUses(const AEntrada: string): TEntradaDeUses;
var
  Core: string;
  I, J, N: Integer;
  M: TMatch;
begin
  Result := Default(TEntradaDeUses);
  SplitEntryPrefix(AEntrada, Result.Prefijo, Core);
  I := 1;
  M := TRegEx.Match(Core, '^' + PATRON_IDENT_PUNTOS);
  if M.Success then
  begin
    Result.Nombre := M.Value;
    I := M.Length + 1;
    J := I;
    while (J <= Length(Core)) and Core[J].IsWhiteSpace do
      Inc(J);
    if SameText(Copy(Core, J, 2), 'in') and
       ((J + 2 > Length(Core)) or not EsCaracterDeIdent(Core[J + 2])) then
    begin
      Inc(J, 2);
      while (J <= Length(Core)) and Core[J].IsWhiteSpace do
        Inc(J);
      N := QuoteLen(Core, J);
      if (N >= 2) and (Core[J + N - 1] = '''') then
      begin
        Result.Include := Copy(Core, J + 1, N - 2).Replace('''''', '''');
        I := J + N;
        M := TRegEx.Match(Copy(Core, I, MaxInt), '^\s*\{\s*(' + PATRON_IDENT + ')\s*(?::\s*(' +
          PATRON_IDENT_PUNTOS + ')\s*)?\}');
        if M.Success then
        begin
          Result.Form := M.Groups[1].Value;
          if (M.Groups.Count > 2) and M.Groups[2].Success then
            Result.DesignClass := M.Groups[2].Value;
          Inc(I, M.Length);
        end;
      end;
    end;
  end;
  Result.Resto := Copy(Core, I, MaxInt);
  Result.Legible := CodigoPascal(Result.Resto).Trim = '';
end;

function EntryUnitName(const Entry: string): string;
begin
  var E := LeeEntradaDeUses(Entry);
  Result := IfThen(E.Nombre <> '', E.Nombre, E.Resto);
end;

function EntryInclude(const Entry: string): string;
begin
  Result := LeeEntradaDeUses(Entry).Include;
end;

function EntryFormName(const Entry: string): string;
begin
  Result := LeeEntradaDeUses(Entry).Form;
end;

function EntradaDelUses(const AUnidad, AInclude, AForm, ADesignClass: string): string;
begin
  // la ruta con sus comillas dobladas, como el lexico la lee: sin doblar,
  // 'David's units\UFicha.pas' no compilaba (E2052) y add-unit decia ADDED
  // (medido el 25-oct-2026)
  Result := AUnidad + ' in ' + QuotedStr(AInclude);
  if AForm <> '' then
  begin
    if ADesignClass <> '' then
      Result := Result + ' {' + AForm + ': ' + ADesignClass + '}'
    else
      Result := Result + ' {' + AForm + '}';
  end;
end;

// '' o USES-026 para la entrada AEntrada de la clausula AKeyword de AFichero:
// la de quien la reescribe y la de la puerta del build (LecturasDelIn)
function NegativaDeEntradaIlegible(const AKeyword, AFichero, AEntrada: string): string;
var
  Prefijo, Core: string;
begin
  Result := '';
  if LeeEntradaDeUses(AEntrada).Legible then
    Exit;
  SplitEntryPrefix(AEntrada, Prefijo, Core);
  Result := MsgFmt(SR_USES_ENTRADA_ILEGIBLE_FMT, [AKeyword, AFichero, SplitToLines(Core)[0].Trim]);
end;

{ Lo que impide reescribir la clausula U de AFichero, o '': partida en ramas
  (la unit caeria en la que no toca) o con algo que no se lee como una
  entrada (LeeEntradaDeUses: una comilla sin cerrar deja el ';' de la
  clausula mas abajo, y reescribirla se llevaba el codigo de detras -
  remove-unit borro el begin de un .dpr diciendo REMOVED, medido el
  25-oct-2026 -). UNA pregunta: los llamadores la hacen con su fichero y el
  escritor (ReplaceUses) otra vez, la segunda barrera. }
function ClausulaQueNoSeReescribe(const U: TUsesClause; const AFichero: string): string;
begin
  Result := '';
  if U.EnRamas then
    Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, AFichero]));
  for var E in U.Entries do
  begin
    Result := NegativaDeEntradaIlegible(U.Keyword, AFichero, E);
    if Result <> '' then
      Exit;
  end;
end;

// La entrada AEntrada reescrita con ANueva (renombrada; completada con su
// in): conserva lo que la precede (su comentario o su directiva) y lo que
// lleva DETRAS de lo suyo - el nombre, el in y el comentario del form, que
// ANueva trae -: una directiva o un comentario. Los dos escritores la
// rehacian con lo de delante solo, y renombrar "Unit1 in 'Unit1.pas'
// {$IFDEF DEBUG}," perdia el IFDEF: el .dpr no compilaba y la tool decia
// que si (revision de la 1.10.0, medido con delphi_move y con add-unit)
function EntradaReescrita(const AEntrada, ANueva: string): string;
begin
  // lo de detras de lo suyo, por EL lector de la entrada (antes una regex
  // propia, la cuarta)
  var E := LeeEntradaDeUses(AEntrada);
  Result := ANueva + E.Resto;
  if E.Prefijo <> '' then
    Result := E.Prefijo + #10 + Result;
end;

{ Rewrites the clause with AEntries, keeping the text before/after intact.
  Entries go one per line with the indent the clause already used (the IDE's
  two spaces when it had none). Measured 2026-08-23: the indent was applied
  TWICE (join + a second replace) and every add/remove-unit re-indented the
  whole clause to four spaces - a 40-line cosmetic diff on a real project. }
// Una entrada envuelta ENTERA en su condicional, en lineas suyas: la primera
// abre (IFDEF X, IFNDEF X, IF ..., IFOPT ...), la ultima cierra (ENDIF /
// IFEND) y en medio esta la unit. Lo dice EL lector de directivas: con su
// propia regex no veia la forma parentesis-asterisco ni un // detras de la
// directiva, y quitar la entrada de detras dejaba 'UA, ;' sin DEBUG
// (revision de la 1.10.0, medido)
function EsEnvuelta(const AEntrada: string): Boolean;
var
  L: TArray<string>;

  // la linea es UNA directiva de esa clase y nada de codigo (un comentario si)
  function SoloDirectiva(const ALinea: string; AClase: TCondicional): Boolean;
  var
    Ds: TArray<TDirectivaPascal>;
  begin
    Ds := DirectivasPascal(ALinea);
    Result := (Length(Ds) = 1) and (CondicionalDe(Ds[0].Nombre) = AClase) and
      (CodigoPascal(ALinea).Trim = '');
  end;

begin
  L := Recortados(SplitToLines(AEntrada));
  Result := (Length(L) >= 3) and SoloDirectiva(L[0], cdAbre) and
    SoloDirectiva(L[High(L)], cdCierra);
end;

// Que entrada NUEVA es cada una de la clausula ORIGINAL (-1: se quito). Los
// escritores la cambian de tres maneras: anaden al final, cambian una entrada
// EN SU SITIO (completarla; renombrarla, con otro nombre) o quitan por el
// nombre, y entonces la lista se acorta. Se casan por el nombre; sin quitar
// ninguna, la que no casa es la misma en su sitio con otro nombre. Iba solo
// por el nombre, y el rename acertaba porque su lista ES la de la clausula
// (un array dinamico se asigna por referencia), no por metodo (revision de
// la 1.10.0)
function EntradaNuevaDe(const AOriginal, ANuevas: TArray<string>): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Length(AOriginal));
  I := 0;
  for var K := 0 to High(AOriginal) do
  begin
    Result[K] := -1;
    if (I <= High(ANuevas)) and
       (MismoIdentificador(EntryUnitName(AOriginal[K]), EntryUnitName(ANuevas[I])) or
        (Length(ANuevas) >= Length(AOriginal))) then
    begin
      Result[K] := I;
      Inc(I);
    end;
  end;
end;

{ El comentario - no una directiva, que no es de nadie - que empieza
  detras del ';' de una clausula (AFin, su posicion en ATexto), en su misma
  linea tras blancos: su inicio y su largo. AUnaLinea: solo si acaba en esa
  linea (un // siempre; una llave puede seguir). LA pregunta de los tres que
  lo miran: la edicion en su sitio de una compacta (UsesCompacta), el
  escritor (ReplaceUses: es de la ULTIMA entrada, 11.3) y el eco
  (ClausulaReleida, B16 de la 1.28); estaba escrita dos veces. }
function ComentarioTrasElCierre(const ATexto: string; AFin: Integer; AUnaLinea: Boolean;
  out AIni, ALargo: Integer): Boolean;
begin
  AIni := AFin + 1;
  while (AIni <= Length(ATexto)) and CharInSet(ATexto[AIni], [' ', #9]) do
    Inc(AIni);
  ALargo := CommentLen(ATexto, AIni);
  Result := (ALargo > 0) and not AbreDirectiva(ATexto, AIni) and
    (not AUnaLinea or (Copy(ATexto, AIni, ALargo).IndexOfAny([#10, #13]) < 0));
end;

{ Una clausula COMPACTA - alguna linea con varias units, sin comentarios ni
  directivas, solo identificadores - editada EN SU SITIO: las que se van
  salen con su coma (y la linea que se queda vacia, con ellas) y las nuevas
  entran detras de la ultima, en su linea mientras quepa (80 columnas, o la
  linea mas larga que ya tenia), si no en una nueva con su sangria. '' si
  no es compacta o el cambio no es "quitar unas y anadir al final": entonces
  escribe ReplaceUses, una por linea, como siempre. Rehacerla una por linea
  era un diff de cuarenta lineas por una unit (adduses y removeuses en
  UTrayMain, 9-oct-2026; 3.13 de la 1.18.0). }
function UsesCompacta(const Dpr: string; const U: TUsesClause;
  const AEntries: TArray<string>): string;
var
  Ini, P, I, K, Ancho: Integer;
  Cuerpo, NL, Indent, Nuevo, Antes: string;
  Pos_: TArray<Integer>;
  Quedan: TArray<Boolean>;
  M: TMatch;
begin
  Result := '';
  if (Length(U.Entries) = 0) or (Length(AEntries) = 0) then
    Exit;
  Ini := U.StartPos + Length(U.Keyword);
  Cuerpo := Copy(Dpr, Ini, U.EndPos - Ini);
  // ni un comentario ni una directiva, y solo nombres de unit
  if CodigoPascal(Cuerpo) <> Cuerpo then
    Exit;
  for var E in U.Entries + AEntries do
    if not EsIdentificador(E, True) then
      Exit;
  // compacta: alguna linea con dos o mas
  if not TRegEx.IsMatch(Cuerpo, ',[ \t]*[^\s]') then
    Exit;
  // un comentario DETRAS del ';', en su linea, es de la ULTIMA entrada
  // original (11.3): editada en su sitio, la compacta lo dejaba tras la nueva
  // ('SysUtils, Classes; // para Format') o con otra si quitaba la suya.
  // ReplaceUses ya sabe de quien es (revisor de version de la 1.18.0, medido)
  var PC, LC: Integer;
  if ComentarioTrasElCierre(Dpr, U.EndPos, False, PC, LC) then
    Exit;
  // las que se quedan, en su orden; detras, solo nuevas
  SetLength(Quedan, Length(U.Entries));
  K := 0;
  for I := 0 to High(U.Entries) do
  begin
    Quedan[I] := (K <= High(AEntries)) and (AEntries[K] = U.Entries[I]);
    if Quedan[I] then
      Inc(K);
  end;
  if K = 0 then
    Exit;
  for I := K to High(AEntries) do
    for var E in U.Entries do
      if MismoIdentificador(AEntries[I], E) then
        Exit; // una que estaba, fuera de su orden: el camino de siempre
  // donde empieza cada una; entre dos, solo la coma y blancos
  SetLength(Pos_, Length(U.Entries));
  P := 1;
  for I := 0 to High(U.Entries) do
  begin
    var Q := PosEx(U.Entries[I], Cuerpo, P);
    if (Q = 0) or not (Copy(Cuerpo, P, Q - P).Replace(',', '').Trim = '') then
      Exit;
    Pos_[I] := Q;
    P := Q + Length(U.Entries[I]);
  end;
  // fuera las que se van: su nombre y la coma y los blancos que la siguen
  // en SU linea (el salto se queda)
  Nuevo := Cuerpo;
  for I := High(U.Entries) downto 0 do
    if not Quedan[I] then
    begin
      var Fin := Pos_[I] + Length(U.Entries[I]);
      while (Fin <= Length(Nuevo)) and CharInSet(Nuevo[Fin], [' ', #9]) do
        Inc(Fin);
      if (Fin <= Length(Nuevo)) and (Nuevo[Fin] = ',') then
        Inc(Fin);
      while (Fin <= Length(Nuevo)) and CharInSet(Nuevo[Fin], [' ', #9]) do
        Inc(Fin);
      Delete(Nuevo, Pos_[I], Fin - Pos_[I]);
    end;
  // sin coma colgando al final, sin blancos al final de linea, sin lineas
  // que se quedaron vacias
  Nuevo := TRegEx.Replace(Nuevo, '[\s,]+$', '');
  Nuevo := SinBlancosAlFinalDeLinea(Nuevo);
  repeat
    Antes := Nuevo;
    Nuevo := TRegEx.Replace(Nuevo, '\r?\n[ \t]*(?=\r?\n)', '');
  until Nuevo = Antes;
  // las nuevas, detras de la ultima
  NL := SaltoDominante(Dpr);
  Indent := SangriaDeClausula(Cuerpo);
  Ancho := 80;
  for var L in SplitToLines(Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1)) do
    if Length(L) > Ancho then
      Ancho := Length(L);
  for I := K to High(AEntries) do
  begin
    // la columna en la que acaba la ultima linea (con lo que hay delante de
    // la palabra uses, si sigue en su linea)
    var UltSalto := Nuevo.LastIndexOf(#10);
    var Col: Integer;
    if UltSalto >= 0 then
      Col := Length(Nuevo) - UltSalto - 1
    else
    begin
      var IniLinea := U.StartPos;
      while (IniLinea > 1) and not CharInSet(Dpr[IniLinea - 1], [#10, #13]) do
        Dec(IniLinea);
      Col := U.StartPos - IniLinea + Length(U.Keyword) + Length(Nuevo);
    end;
    if Col + 2 + Length(AEntries[I]) + 1 <= Ancho then
      Nuevo := Nuevo + ', ' + AEntries[I]
    else
      Nuevo := Nuevo + ',' + NL + Indent + AEntries[I];
  end;
  Result := Copy(Dpr, 1, Ini - 1) + Nuevo + Copy(Dpr, U.EndPos, MaxInt);
end;

function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
var
  Body, NL, Indent, Clause, E: string;
  M: TMatch;
  Parts: TArray<string>;
  I: Integer;
  Mapa: TArray<Integer>;
  ClasesClausula: TArray<TClasePascal>;

  // la primera linea de una entrada cuando va sola (con un salto detras)
  function PrimeraLinea(const AEntrada: string): string;
  begin
    var T := ConSalto(AEntrada, #10); // tambien el CR suelto (decima revision)
    var P := T.IndexOf(#10);
    Result := IfThen(P >= 0, Copy(T, 1, P), '').Trim;
  end;

  // si el // con el que empieza la entrada NUEVA AI iba, en la clausula
  // ORIGINAL, detras de la coma de la que ahora es la AI-1. Por si hay uno
  // asi, no por el primero con ese texto: con dos '// TODO' iguales detras
  // de dos comas, el segundo se daba a la duena del primero y bajaba a una
  // linea suya (revision de la 1.10.0, medido con adduses)
  function EsDeLaAnterior(AI: Integer; const AComentario: string): Boolean;
  begin
    for var K := 1 to High(U.Entries) do
      if (PrimeraLinea(U.Entries[K]) = AComentario) and (Mapa[K - 1] = AI - 1) then
        Exit(True);
    Result := False;
  end;

  // AEntrada sin la primera linea que es ALinea (recortada)
  function SinLinea(const AEntrada, ALinea: string): string;
  begin
    var Quedan: TArray<string> := [];
    var Quitada := False;
    for var L in SplitToLines(AEntrada) do
      if not Quitada and (L.Trim = ALinea) then
        Quitada := True
      else
        Quedan := Quedan + [L];
    Result := string.Join(#10, Quedan);
  end;

  // AEntrada sin el // AComentario de una entrada QUITADA, cuando no queda
  // ninguna detras de ella: en una linea suya o, si no la tiene, pegado
  // detras del codigo de una linea (PegaALaAnterior pega ahi la primera
  // linea que arrastra, que es de la quitada si la que queda no lleva uno
  // propio). Una linea suya primero: si la que queda lleva uno propio con el
  // mismo texto, ese es el pegado y no se toca
  function SinComentarioDeQuitada(const AEntrada, AComentario: string): string;
  begin
    var Lineas := SplitToLines(AEntrada);
    for var L := 0 to High(Lineas) do
      if Lineas[L].Trim = AComentario then
        Exit(SinLinea(AEntrada, AComentario));
    for var L := 0 to High(Lineas) do
    begin
      var T := Lineas[L].TrimRight;
      if T.EndsWith(AComentario) and (T.Trim <> AComentario) then
      begin
        Lineas[L] := Copy(T, 1, Length(T) - Length(AComentario)).TrimRight;
        Exit(string.Join(#10, Lineas));
      end;
    end;
    Result := AEntrada;
  end;

  // el hueco que habia en la clausula ORIGINAL entre un separador de ASeps y
  // el comentario //; False si ese comentario no iba detras de uno. Un
  // separador DE CODIGO y un // DE VERDAD, segun el lexico: el mismo texto
  // dentro de una llave o de una cadena no cuenta
  function HuecoTrasSeparador(const ASeps, AComentario: string; out AHueco: string): Boolean;
  begin
    AHueco := '';
    for var MM in TRegEx.Matches(Clause, '[' + ASeps + ']([ \t]*)' + TRegEx.Escape(AComentario)) do
      if (ClasesClausula[MM.Index] = cpCodigo) and
         (ClasesClausula[MM.Index + MM.Length - Length(AComentario)] = cpLinea) then
      begin
        AHueco := MM.Groups[1].Value;
        Exit(True);
      end;
    Result := False;
  end;

  // si el comentario // AComentario iba, en la clausula ORIGINAL, detras de la
  // coma de codigo numero ANumero (la que separa la entrada ANumero-1 de la
  // ANumero), en su misma linea, y con que hueco. HuecoTrasSeparador mira
  // cualquier coma: un '// TODO' de linea propia se iba con la quitada si otro
  // '// TODO' iba detras de otra coma (revisor de version de la 1.18.0, medido)
  function TrasLaComa(ANumero: Integer; const AComentario: string; out AHueco: string): Boolean;
  var
    N: Integer;
  begin
    AHueco := '';
    N := 0;
    for var J := 1 to Length(Clause) do
      if (ClasesClausula[J] = cpCodigo) and (Clause[J] = ',') then
      begin
        Inc(N);
        if N = ANumero then
        begin
          var MC := TRegEx.Match(Copy(Clause, J + 1, MaxInt), '^([ \t]*)' + TRegEx.Escape(AComentario));
          Result := MC.Success and
            (ClasesClausula[J + MC.Length - Length(AComentario) + 1] = cpLinea);
          if Result then
            AHueco := MC.Groups[1].Value;
          Exit;
        end;
      end;
    Result := False;
  end;

begin
  // EL escritor pregunta el mismo, como AtomicWrite: una clausula partida en
  // ramas no se reescribe - la unit caeria en la rama que no toca, o la
  // clausula perderia su forma -, ni una que no se lee como una lista
  // (ClausulaQueNoSeReescribe). Los llamadores lo dicen antes, con el fichero.
  var NoSe := ClausulaQueNoSeReescribe(U, MsgText(SF_USES_EL_FICHERO));
  if NoSe <> '' then
    raise Exception.Create(NoSe);
  // sin entradas no hay clausula: la palabra sola no compila, y quitar la
  // ULTIMA unit de un .dpr/.dpk la dejaba asi diciendo OK (decima revision).
  // Se va entera con los saltos que la seguian; removeuses lo hacia a mano.
  if Length(AEntries) = 0 then
  begin
    var Fin := U.EndPos + 1;
    while (Fin <= Length(Dpr)) and CharInSet(Dpr[Fin], [#10, #13]) do
      Inc(Fin);
    Exit(Copy(Dpr, 1, U.StartPos - 1) + Copy(Dpr, Fin, MaxInt));
  end;
  // una clausula compacta se edita en su sitio (UsesCompacta)
  Result := UsesCompacta(Dpr, U, AEntries);
  if Result <> '' then
    Exit;
  NL := SaltoDominante(Dpr);
  // the indent of the first entry line of the existing clause
  Clause := Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1);
  ClasesClausula := ClasesPascal(Clause);
  Indent := SangriaDeClausula(Clause);
  SetLength(Parts, Length(AEntries));
  Mapa := EntradaNuevaDe(U.Entries, AEntries);
  // un // que va detras de la coma es de la entrada de ANTES (esta en su
  // misma linea), aunque el troceo por comas lo deje al principio de la
  // siguiente: se le devuelve a su dueno, y el separador (la coma o el ;)
  // va DELANTE de el. Si no, quitar la ultima entrada dejaba el ; dentro
  // del comentario y la clausula sin cerrar, y cada reescritura bajaba el
  // comentario a una linea suya (medido 27-sep con removeuses). Y a SU
  // dueno, no a la de antes en la lista nueva: quitada la duena, se pegaba a
  // la anterior ('UA, // de UB', medido el 2-oct-2026 con remove-unit). Y si
  // su duena se QUITA, se va con ella: el comentario en la linea de una
  // entrada es suyo; el que va en una linea propia se queda (David, 10-oct-2026,
  // 11.3: regla de la casa, no hay juez; quedaba huerfano dentro del uses).
  var Entradas := Copy(AEntries);
  var Colas: TArray<string>;
  SetLength(Colas, Length(Entradas));
  for I := 1 to High(Entradas) do
  begin
    var Texto := ConSalto(Entradas[I], #10);
    var P := Texto.IndexOf(#10);
    var Primera := PrimeraLinea(Entradas[I]);
    // solo si en el original iba detras de SU coma: uno que estaba en una
    // linea suya no sube; y con el hueco que tenia (las entradas llegan
    // recortadas: el hueco sale del texto original de la clausula)
    var HC: string;
    if Primera.StartsWith('//') and HuecoTrasSeparador(',', Primera, HC) and
       EsDeLaAnterior(I, Primera) then
    begin
      Colas[I - 1] := IfThen(HC <> '', HC, ' ') + Primera;
      Entradas[I] := Copy(Texto, P + 2, MaxInt);
    end;
  end;
  // el // que iba detras de la coma de una entrada QUITADA se va con ella
  // (11.3): viajaba al principio de la siguiente, detras de lo que la
  // quitada le deja pegado (EntriesWithout: su prefijo), y se quita ahi. El
  // de CADA quitada: con varias seguidas, el de las de delante viajaba de
  // prefijo en prefijo hasta la primera que se queda, o, si se iban las
  // ultimas, detras de la ultima que queda (PegaALaAnterior), y quedaba
  // huerfano o con otra duena (B16 de la 1.28, medido el 5-nov-2026)
  var UltimaQueQueda := -1;
  for var K := 0 to High(U.Entries) do
    if Mapa[K] >= 0 then
      UltimaQueQueda := K;
  for var J := 0 to High(U.Entries) - 1 do
    if (Mapa[J] = -1) and (UltimaQueQueda >= 0) then
    begin
      // detras de SU coma, la que la sigue (la J + 1), no de cualquiera
      var Suyo := PrimeraLinea(U.Entries[J + 1]);
      var HS: string;
      if not (Suyo.StartsWith('//') and TrasLaComa(J + 1, Suyo, HS)) then
        Continue;
      if J < UltimaQueQueda then
      begin
        // en el prefijo de la primera que se queda detras
        var K := J + 1;
        while Mapa[K] = -1 do
          Inc(K);
        Entradas[Mapa[K]] := SinLinea(Entradas[Mapa[K]], Suyo);
      end
      else
        Entradas[Mapa[UltimaQueQueda]] := SinComentarioDeQuitada(Entradas[Mapa[UltimaQueQueda]], Suyo);
    end;
  // el comentario que va DETRAS del ; final, en su misma linea, es de la
  // ULTIMA entrada original, y queda fuera de la clausula: con una unit
  // anadida detras se iba a la nueva ('Lsp.NetDrives; // PrefijoSinBarra'
  // salio 'Lsp.Texts; // PrefijoSinBarra', medido el 2-oct-2026 con adduses,
  // y lo mismo add-unit en un .dpr), y quitada su entrada se pegaba a la que
  // quedaba ('// de SysUtils // de Classes'). Se queda con su entrada; si su
  // entrada se fue, se va con ella, como el de una quitada de en medio (11.3;
  // hasta el 10-oct-2026 se quedaba en una linea suya)
  var Resto := U.EndPos + 1;   // desde donde sigue el texto de detras
  var PosCom, LargoCom: Integer;
  // (una directiva no es un comentario de nadie: {$ o (*$ no viaja)
  if ComentarioTrasElCierre(Dpr, U.EndPos, True, PosCom, LargoCom) and (Length(U.Entries) > 0) then
  begin
    // la que corresponde a la ultima original, no por su texto: el de una
    // entrada lleva delante el comentario de la anterior, que quitar esa
    // anterior cambia (medido)
    var Duena := Mapa[High(U.Entries)];
    if Duena < High(Entradas) then
    begin
      var Coment := Copy(Dpr, PosCom, LargoCom);
      if Duena >= 0 then
        Colas[Duena] := Colas[Duena] + IfThen(PosCom > U.EndPos + 1,
          Copy(Dpr, U.EndPos + 1, PosCom - U.EndPos - 1), ' ') + Coment;
      Resto := PosCom + LargoCom;
    end;
  end;
  // la COLA de entradas envueltas cada una en su condicional ({$IFDEF X} /
  // la unit / {$ENDIF}) al final de la clausula: el separador de la de antes
  // tiene que ir DENTRO de cada condicional (A {$IFDEF X}, B {$ENDIF};), o
  // con X apagado queda 'A, ;' y no compila. Quitar la ultima C de 'A,
  // {$IFDEF DEBUG} DebugU, {$ENDIF} C;' lo dejaba asi (medido en la revision
  // de la 1.10.0; venia de antes)
  var InicioCola := Length(Entradas);
  while (InicioCola - 1 >= 1) and EsEnvuelta(Entradas[InicioCola - 1]) do
    Dec(InicioCola);
  for I := 0 to High(Entradas) do
  begin
    // a multi-line entry (directives around it) keeps its lines indented too:
    // cada linea se reindenta desde cero, que la que venia con su sangria
    // propia (la vecina de una entrada quitada) salia con las dos (medido
    // en vivo con removeuses, 2026-09-23)
    var Lineas := SplitToLines(Entradas[I]);
    for var J := 0 to High(Lineas) do
      Lineas[J] := Lineas[J].Trim;
    var Sep := IfThen(I < High(Entradas), ',', ';');
    if InicioCola < Length(Entradas) then
    begin
      if (I = InicioCola - 1) or ((I >= InicioCola) and (I < High(Entradas))) then
        Sep := '';
      if I >= InicioCola then
        Lineas[1] := ', ' + Lineas[1]; // la coma, dentro del condicional
    end;
    // el separador, detras de la ultima linea con codigo y delante de su //.
    // Lo que es un // lo dice el lexico, con el estado de las lineas de antes:
    // el de '{ver https://x}' no lo es, y la coma caia DENTRO de la llave
    // (adduses acababa en SYS-006, medido el 2-oct-2026)
    var Coms := ComentariosDeLinea(Lineas);
    var K := High(Lineas);
    while (K > 0) and (Coms[K] = 1) do
      Dec(K);
    var C := Coms[K];
    if C > 0 then
    begin
      var Codigo := Copy(Lineas[K], 1, C - 1);
      var Hueco := Copy(Codigo, Length(Codigo.TrimRight) + 1, MaxInt);
      // el que tenia en el original, detras de su separador. (Era un IfThen
      // con MH.Groups[1] de argumento: IfThen es una funcion, sus argumentos
      // se evaluan todos, y sin casar el grupo lanzaba 'Index out of bounds
      // (1)': el SYS-006 de la sonda)
      if (Hueco = '') and
         (not HuecoTrasSeparador(',;', Copy(Lineas[K], C, MaxInt), Hueco) or (Hueco = '')) then
        Hueco := ' ';
      Lineas[K] := Codigo.TrimRight + Sep + Hueco + Copy(Lineas[K], C, MaxInt);
    end
    else
      Lineas[K] := Lineas[K] + Sep;
    Lineas[High(Lineas)] := Lineas[High(Lineas)] + Colas[I];
    E := string.Join(NL + Indent, Lineas);
    Parts[I] := Indent + E;
  end;
  Body := IfThen(U.Keyword <> '', U.Keyword, 'uses') + NL + string.Join(NL, Parts);
  Body := SinBlancosAlFinalDeLinea(Body);
  // EL escritor pregunta si lo que deja sigue siendo una lista en cada rama de
  // sus condicionales (ListaEnCadaRama), y solo si la que habia lo era: una
  // coma fuera de su condicional no compila con unos simbolos (revisor de
  // version de la 1.18.0, medido con dcc: E2029). Se niega sin escribir
  var Palabra := IfThen(U.Keyword <> '', U.Keyword, 'uses');
  if (ListaEnCadaRama(Copy(Clause, Length(Palabra) + 1, MaxInt)) = 0) and
     (ListaEnCadaRama(Copy(Body, Length(Palabra) + 1, MaxInt)) = 1) then
    raise Exception.Create(MsgFmt(SR_USES_RAMA_SIN_LISTA_FMT, [Palabra]));
  Result := Copy(Dpr, 1, U.StartPos - 1) + Body + Copy(Dpr, Resto, MaxInt);
end;

// Donde empieza (1-based) la linea de ATexto en la que esta APos: un salto
// es CRLF, LF o un CR suelto, como en LineaDePosicion
function InicioDeLaLinea(const ATexto: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result > 1) and not CharInSet(ATexto[Result - 1], [#10, #13]) do
    Dec(Result);
end;

{ Estrena la clausula uses de AEntradas (ya escritas, sin el ';') en APos de
  AText, donde empieza el salto que sigue a la palabra de seccion o a la
  cabecera: con la MISMA separacion que habia alli, delante y detras. Asi
  removeuses, que quita la
  clausula con los saltos que la siguen (ReplaceUses), es su inversa: con dos
  saltos fijos delante, una unit compacta ('interface' y el codigo justo
  debajo) ganaba una linea en blanco tras adduses + removeuses (test completo
  de Opus de la 1.22.0); con una linea en blanco, la forma del IDE, salen los
  mismos bytes que antes. Sin salto en APos, dos delante, como antes. EL
  escritor de una clausula nueva de un .pas y de un .dpr (eran dos), y su
  forma, la del IDE ('uses', salto, dos espacios, las entradas): la componian
  a mano sus dos llamadores (forma 3 de la 1.26). AEnLinea: la de una unit de
  UNA linea ('unit X; interface implementation end.'), pegada a la palabra en
  APos y en su misma linea, que se quedo a mano junto a su llamada (C3 del
  cierre de la 1.26). }
procedure EstrenaClausula(var AText: string; APos: Integer; const AEntradas: string;
  AEnLinea: Boolean = False);
var
  Fin: Integer;
  NL, Cuerpo: string;
begin
  if AEnLinea then
  begin
    AText := Copy(AText, 1, APos - 1) + ' uses ' + AEntradas + ';' + Copy(AText, APos, MaxInt);
    Exit;
  end;
  NL := SaltoDominante(AText);
  Cuerpo := 'uses' + NL + '  ' + AEntradas + ';';
  Fin := APos;
  while (Fin <= Length(AText)) and CharInSet(AText[Fin], [#10, #13]) do
    Inc(Fin);
  if Fin = APos then
    AText := Copy(AText, 1, APos - 1) + NL + NL + Cuerpo + Copy(AText, APos, MaxInt)
  else
  begin
    var Sep := Copy(AText, APos, Fin - APos);
    AText := Copy(AText, 1, APos - 1) + Sep + Cuerpo + Sep + Copy(AText, Fin, MaxInt);
  end;
end;

{ Estrena el uses de un programa o una biblioteca justo detras de su
  cabecera (EL lector: CabeceraDeFuente) con AEntradas ya escritas, sin el
  ';'. False si AText no es un program/library. La clausula que nace la
  escriben add-unit (al programa le quitaron su ultima unit: se fue entera)
  y adduses en un .dpr: un solo escritor de ese uses. }
function EstrenaUsesTrasCabecera(var AText: string; const AEntradas: string): Boolean;
var
  Cab: TCabeceraFuente;
begin
  Result := CabeceraDeFuente(CodigoPascal(AText), Cab) and
    MatchText(Cab.Palabra, ['program', 'library']);
  if Result then
    EstrenaClausula(AText, Cab.Fin, AEntradas);
end;

{ Las entradas de una clausula SIN la unit dicha. El comentario o directiva
  que precede a la entrada quitada se queda, pegado a la siguiente (o a la
  anterior si era la ultima), para no desbalancear un IFDEF. Lo hacia
  remove-unit (.dpr/.dpk) en su sitio; ahora tambien removeuses (.pas): un
  solo sitio (2026-09-23). }
function EntriesWithout(const AEntries: TArray<string>; const AUnitName: string): TArray<string>;
var
  E, Carry, Prefix, Core, Detras: string;

  // lo que deja una entrada quitada, al FINAL de la anterior de la lista nueva
  procedure PegaALaAnterior(const ALoQueDeja: string);
  begin
    // un // en la primera linea del prefijo iba detras de la coma de la
    // anterior: vuelve a SU linea (ReplaceUses pone el ; delante de el)
    var C := ConSalto(ALoQueDeja, #10); // tambien el CR suelto (decima revision)
    var P := C.IndexOf(#10);
    var Primera := IfThen(P >= 0, Copy(C, 1, P), C);
    if Primera.TrimLeft.StartsWith('//') then
    begin
      Result[High(Result)] := Result[High(Result)] + Primera.TrimRight;
      C := IfThen(P >= 0, Copy(C, P + 2, MaxInt), '');
    end;
    if C.Trim <> '' then
      Result[High(Result)] := Result[High(Result)] + #10 + C;
  end;

begin
  Result := [];
  Carry := '';
  for E in AEntries do
    if not MismoIdentificador(EntryUnitName(E), AUnitName) then
    begin
      if Carry <> '' then
        Result := Result + [Carry + #10 + E]
      else
        Result := Result + [E];
      Carry := '';
    end
    else
    begin
      SplitEntryPrefix(E, Prefix, Core);
      // ...y las directivas que la entrada lleva DETRAS: 'DebugU{$ENDIF}'
      // perdia su ENDIF y el IFDEF de la de antes quedaba abierto (medido en
      // la revision de la 1.10.0; venia de antes). Por el lector UNICO de
      // directivas, cada una en su linea: aqui se escribio un gemelo suyo
      // (DirectivasDe) y lo encontro el censo del lexico, el mismo dia
      Detras := '';
      for var D in DirectivasPascal(Core) do
        Detras := IfThen(Detras <> '', Detras + #10, '') + Copy(Core, D.Inicio, D.Largo);
      // La coma que se va con la entrada es la de su MISMA region: sin una
      // directiva condicional entre ella y el nombre. Lo de siempre es la de
      // DETRAS, y lo que la entrada deja va al principio de la siguiente. Si
      // un condicional abre DETRAS del nombre ('B {$IFDEF X}, C{$ENDIF}'), la
      // de detras es de otra region: se va la de DELANTE y lo que deja va al
      // final de la anterior ('A {$IFDEF X}, C{$ENDIF}'); antes quedaba 'A,
      // {$IFDEF X} C{$ENDIF}', E2029 sin X (revisor de version de la 1.18.0,
      // medido con dcc). Si ninguna de las dos, lo niega ReplaceUses (USES-023)
      if (Length(Result) > 0) and LlevaCondicional(Detras) and not LlevaCondicional(Prefix) then
        PegaALaAnterior(IfThen(Prefix <> '', Prefix + #10, '') + Detras)
      else
        Carry := Prefix + IfThen((Prefix <> '') and (Detras <> ''), #10, '') + Detras;
    end;
  // la ULTIMA se fue: lo que deja, al final de la anterior
  if (Carry <> '') and (Length(Result) > 0) then
    PegaALaAnterior(Carry);
end;

{ DONDE acaba la palabra de la seccion ASec (interface|implementation) en
  ACodigo (la vista CodigoPascal): la posicion 1-based detras de ella, 0 si
  no esta. LA regla de la seccion de un uses: estaba cinco veces en tres
  funciones (inventario del 10-oct-2026). La primera vez que la palabra sale
  ENTERA en el codigo, este donde este: se buscaba a principio de linea, y
  en 'unit X; interface uses A; implementation end.' no habia seccion
  (adduses negaba, y el renombrado de una unit, que desde el 18-oct-2026 mira
  sus clausulas, la necesita). Lo que la lleva dentro de otra palabra
  (dispinterface, IInterface) no; en una unit la seccion va antes que un
  'IX = interface'. }
function FinDeSeccion(const ACodigo, ASec: string): Integer;
var
  M: TMatch;
begin
  M := TRegEx.Match(ACodigo, '(?<![\w.])' + ASec + '\b', [roIgnoreCase]);
  if M.Success then
    Result := M.Index + M.Length
  else
    Result := 0;
end;

function SeccionEnLineas(const ACodigo, ASec: string; out ALinea, AColIni, AColFin: Integer): Boolean;
begin
  ALinea := -1;
  AColIni := 0;
  AColFin := 0;
  var Fin := FinDeSeccion(ACodigo, ASec);
  Result := Fin > 0;
  if not Result then
    Exit;
  var Ini := Fin - Length(ASec);
  var IniLinea := InicioDeLaLinea(ACodigo, Ini);
  ALinea := LineaDePosicion(ACodigo, Ini) - 1;
  AColIni := Ini - IniLinea + 1;
  AColFin := Fin - IniLinea + 1;
end;

{ La OTRA seccion de ASec (interface <-> implementation) y su clausula uses
  (Found = False si no la tiene); ABlank, AText en la vista del codigo. UNA
  para adduses (una unit no va en las dos) y removeuses (lo que no esta en la
  suya y si en la otra, USES-024): estaba escrita dos veces (revisor de
  version de la 1.18.1). }
function UsesDeLaOtraSeccion(const AText, ABlank, ASec: string; out AOtra: string): TUsesClause;
var
  PosOtra: Integer;
begin
  AOtra := IfThen(SameText(ASec, 'interface'), 'implementation', 'interface');
  Result := Default(TUsesClause);
  PosOtra := FinDeSeccion(ABlank, AOtra);
  if PosOtra > 0 then
    Result := FindUses(AText, PosOtra);
end;

function UsesEnOrden(const AText: string; ASoloInterface: Boolean): TArray<string>;

  function DeLaClausula(const U: TUsesClause): TArray<string>;
  begin
    Result := nil;
    if U.Found then
      for var E in U.Entries do
        Result := Result + [EntryUnitName(E)];
  end;

begin
  var Blank := CodigoPascal(AText);
  var PosInt := FinDeSeccion(Blank, 'interface');
  if PosInt = 0 then
    Exit(DeLaClausula(FindUses(AText)));
  Result := DeLaClausula(FindUses(AText, PosInt));
  if ASoloInterface then
    Exit;
  var PosImp := FinDeSeccion(Blank, 'implementation');
  if PosImp > 0 then
    Result := Result + DeLaClausula(FindUses(AText, PosImp));
end;

function NombresDeUnidades(const ALista: string): TArray<string>;
begin
  Result := Recortados(ALista.Split([';', ',', ' ', #9]));
end;

end.
