unit Lsp.PascalDecl;

{ Las DECLARACIONES de una unidad Pascal, leidas del texto que ve el
  compilador (Lsp.Preproceso.TextoActivo: solo codigo, las ramas inactivas y
  los comentarios ya en blanco): su nombre, sus uses, sus tipos - clases con
  sus propiedades y la visibilidad de cada una, enumerados, conjuntos,
  alias, subrangos, tipos de metodo -, los de las clases (anidados) y los
  del implementation, y las constantes simples del interface.

  No resuelve nombres ni compila nada: lo que pone es lo que esta ESCRITO
  ('TCaption', 'System.UITypes.TColor', 'property Caption;' sin tipo). Que
  tipo es cada nombre lo decide quien lo usa con el alcance de cada unidad
  (Lsp.DesignerMetaGen). Lo que no sabe leer lo salta hasta el ';' que lo
  cierra: una declaracion rara no se lleva por delante la siguiente.

  Por que una unidad: el disenador necesita lo PUBLICADO de cada clase y eso
  solo lo dice la seccion del fuente donde se declara (el LSP no lo da:
  medido el 3-oct-2026 en crudo contra DelphiLSP, ni el completado ni el
  hover traen la visibilidad).

  Es tambien EL lector de clases de los que trabajan por lineas (check-binding,
  insert=metodo, references, add-unit, el resumen de symbols): LeeFuentePascal
  les da cada tipo con la linea de su nombre y la de su 'end', y cada clase
  con sus secciones, sus campos y sus rutinas. Cada uno leia las clases con su
  propia regex y decidia a su manera donde acababa una (el primer 'end;', o
  contando profundidad): un record anidado, una clase sin cuerpo o una de una
  linea los enganaban, y la regla de 'abre bloque' estaba escrita dos veces
  (censo del 4-oct-2026). }

interface

uses
  System.Generics.Collections;

type
  TVisibilidadPas = (vpDefecto, vpPrivada, vpProtegida, vpPublica,
    vpPublicada, vpAutomatizada);

  TPropiedadPas = record
    Nombre: string;
    // tal como va escrito, sin argumentos genericos; '' = redeclarada sin
    // tipo (property Caption;): el tipo es el del ancestro
    Tipo: string;
    Visibilidad: TVisibilidadPas;
    ConIndices: Boolean; // property X[I: Integer]: nunca va a un form
    DeClase: Boolean;    // class property: tampoco
    Linea: Integer;      // 0-based, la de su nombre
  end;

  // una palabra de visibilidad del cuerpo de una clase, donde empieza su seccion
  TSeccionPas = record
    Visibilidad: TVisibilidadPas;
    Palabra: string; // en minusculas, como va: 'public', 'strict private'
    Linea: Integer;  // 0-based, la de la palabra ('strict' si la lleva)
  end;

  // un campo o una rutina declarados en una clase
  TMiembroPas = record
    Nombre: string;
    // campo: su tipo cuando es un nombre (Vcl.StdCtrls.TButton), sin <...>;
    // '' si es otra cosa (array, record, procedure...). Rutina: ''
    Tipo: string;
    Generico: Boolean; // el tipo lleva argumentos genericos (TList<X>)
    Rutina: string;    // 'procedure', 'function', 'constructor'...; '' = campo
    DeClase: Boolean;  // class procedure, class var
    Visibilidad: TVisibilidadPas;
    Linea: Integer;    // 0-based, la de su nombre
  end;

  // ctAyudante: un 'class helper for TX' (Base = TX). Sus metodos se leen como
  // los de una clase (insert=metodo, el dueno de un miembro), pero no es una
  // clase de un form ni de las tablas del disenador
  TClaseTipoPas = (ctEnumerado, ctConjunto, ctSubrango, ctAlias, ctMetodo,
    ctClase, ctRegistro, ctInterfaz, ctReferenciaClase, ctProcedimiento, ctOtro,
    ctAyudante);
  TClasesTipoPas = set of TClaseTipoPas;

  TTipoPas = class
  public
    Nombre: string;            // el simple: 'TButtonStyle'
    Contenedor: string;        // la clase donde se declara ('TCustomButton'; con
                               // puntos si va anidada en otra); '' = de la unidad
    Clase: TClaseTipoPas;
    Fuerte: Boolean;           // 'X = type Y': un tipo con su propia informacion
    Miembros: TArray<string>;  // enumerado; conjunto de un enumerado en linea
    Base: string;              // alias: el destino; conjunto: su base; subrango: el bajo
    Alto: string;              // subrango: el alto
    Ancestro: string;          // clase: el primero de su lista, sin <...>; '' = TObject
    Propiedades: TArray<TPropiedadPas>;
    Generica: Boolean;
    // los nombres de sus parametros genericos, como van escritos: TFoo<K, V:
    // class> = ['K', 'V'] (las restricciones no); [] si no es generico
    ParametrosGenericos: TArray<string>;
    // cuantos parametros genericos tiene (0 = ninguno) y cuantos lleva su
    // ancestro: TFoo y TFoo<T, U> son DOS tipos en la misma unidad
    // (REST.Backend.BindSource: el generico desciende del que no lo es)
    Aridad: Integer;
    AncestroAridad: Integer;
    EnImplementation: Boolean;
    // donde esta, en lineas del texto leido (0-based): la de su nombre y la de
    // su 'end' (clase, record, interfaz, object con cuerpo; -1 si su bloque no
    // se cierra: un fuente a medio escribir) o la de su ';'
    Linea: Integer;
    LineaFin: Integer;
    SinCuerpo: Boolean; // una clase declarada sin bloque: 'EMio = class(Exception);'
    // las de una clase con cuerpo, en orden; las de sus tipos anidados van en
    // los suyos
    Secciones: TArray<TSeccionPas>;
    Campos: TArray<TMiembroPas>;
    Rutinas: TArray<TMiembroPas>;
    // 'TCustomButton.TButtonStyle' o 'TButton': el nombre con su contenedor
    function NombreCompleto: string;
    // ALinea esta dentro: entre la linea de su nombre y la de su fin
    function Contiene(ALinea: Integer): Boolean;
  end;

  TUnidadPas = class
  public
    Nombre: string;                 // '' = el texto no es una unidad
    UsesInterface: TArray<string>;
    UsesImplementation: TArray<string>;
    Tipos: TObjectList<TTipoPas>;   // todos: interface, implementation, anidados
    // las del interface con un valor simple (un numero, True, False): las
    // que puede preguntar un IF de otra unidad (RTLVersion131 = True)
    Constantes: TDictionary<string, string>;
    // un programa o una biblioteca: su nombre (Nombre se queda en '': no es
    // una unidad); sus tipos se leen igual
    Programa: string;
    constructor Create;
    destructor Destroy; override;
    // LA clase llamada ANombre: por su nombre completo (TOuter.TInner) o por el
    // simple, la de la unidad antes que una anidada; las declaraciones
    // adelantadas no estan. nil si no hay. AClases: de que clases de tipo
    // (insert=metodo tambien toma un class helper)
    function Clase(const ANombre: string;
      AClases: TClasesTipoPas = [ctClase]): TTipoPas;
    // ATipo y los tipos que lo contienen, del de fuera al suyo
    function Niveles(ATipo: TTipoPas): TArray<TTipoPas>;
    // como se cualifica en el implementation un metodo de ATipo: cada nivel
    // con sus parametros genericos (TOuter<T>.TInner). Y la regex que lo lee,
    // con otros nombres de parametro o espacios: su inversa
    function NombreDeImplementacion(ATipo: TTipoPas): string;
    function PatronDeImplementacion(ATipo: TTipoPas): string;
    // el tipo mas de dentro de los de AClases que contiene ALinea; nil si
    // ninguno. ASinCabecera: la linea del nombre de un tipo no es suya, es de
    // donde se declara (el dueno de una declaracion)
    function TipoEnLinea(ALinea: Integer; AClases: TClasesTipoPas;
      ASinCabecera: Boolean = False): TTipoPas;
    // el tipo cuyo nombre se declara en ALinea (con bloque antes que sin el:
    // dos en una linea); nil si ninguno. Que una linea es la cabecera de un
    // tipo lo sabe el lector: TFoo<T: class> = class no lo veia una regex
    function TipoQueEmpiezaEn(ALinea: Integer): TTipoPas;
  end;

function LeeUnidadPascal(const ATextoActivo: string): TUnidadPas;

{ Un fuente TAL CUAL (el de un fichero, el de un editor): sus comentarios,
  cadenas y directivas no cuentan, y las dos ramas de un IFDEF se leen, como
  las ve quien lo edita. Las lineas de lo que devuelve son las de AFuente (un
  CR suelto, un LF o un CRLF, un salto). Es el de los que trabajan por lineas. }
function LeeFuentePascal(const AFuente: string): TUnidadPas;

{ Las clases de AUnidad y su ancestro como esta escrito ('' = TObject), por
  ClaveDeIdentificador de su nombre simple: el mapa de CadenaDeAncestros. Se
  puede llenar con varias unidades; una clase de la unidad gana a una anidada
  del mismo nombre. }
procedure AnotaAncestros(const AUnidad: TUnidadPas; AMapa: TDictionary<string, string>);

{ LA cadena de ancestros: AClase, su ancestro, el de este... por AMapa. Para en
  una clase sin ancestro escrito (desciende de TObject), en un ciclo o a los
  ATope eslabones; y en el primero que AMapa no tiene, que va el ultimo y deja
  ASale = True: es por donde la cadena sale de lo leido. Un ancestro
  cualificado (Vcl.Forms.TForm) se busca por su ultimo trozo y va en la cadena
  como esta escrito; si su nombre es el de una ya vista, es otra clase (la de
  fuera de una interpuesta) y la cadena sale por ella. Habia tres recorridos,
  cada uno con sus topes y sus raices (check-binding, add-unit, references). }
function CadenaDeAncestros(const AMapa: TDictionary<string, string>;
  const AClase: string; out ASale: Boolean; ATope: Integer = 32): TArray<string>;

{ La clase de la cabecera de un metodo en el implementation, por su nombre
  simple ('procedure TOuter<T>.TInner.Pinta;' -> 'TInner'); '' si ALinea no
  es ARutina cualificada. El lector de lo que escribe
  TUnidadPas.NombreDeImplementacion, para un tipo cualquiera: con UN
  identificador delante del punto, references no veia la clase de un metodo
  de una generica ni de una anidada, y la llamada a un override suyo salia
  como un homonimo (medido el 4-oct-2026). }
function ClaseDeImplementacion(const ALinea, ARutina: string): string;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Lsp.Pascal;

type
  // ttIdentEsc: un identificador escrito con & (&Object, &End): nunca es la
  // palabra reservada que deletrea
  TClaseTok = (ttIdent, ttIdentEsc, ttNumero, ttSimbolo);

  TLectorPas = class
  private
    FTxt, FLow: string;
    FIni, FLen: TArray<Integer>;
    FKind: TArray<TClaseTok>;
    FN, FI: Integer;
    FUnidad: TUnidadPas;
    FEnImpl: Boolean;
    FUltimaAridad: Integer; // la de los <...> del ultimo LeeNombreDeTipo
    // donde empieza cada linea de FTxt (1-based): la linea de un token
    FLineas: TArray<Integer>;
    procedure Tokeniza;
    function LineaDeTok(AIdx: Integer): Integer;
    function FinDeBloque: Integer;
    function Mira(AK: Integer = 0): string;
    function EsIdent(AK: Integer = 0): Boolean;
    function EsIdentEn(AIdx: Integer): Boolean;
    function AbreRecord: Boolean;
    function SaltaGenericos: Integer;
    function LeeParametrosGenericos: TArray<string>;
    function Texto(AIdx: Integer): string;
    function Toma: string;
    function Fin: Boolean;
    procedure SaltaBalanceado(const AAbre, ACierra: string);
    procedure SaltaHastaPuntoYComa;
    procedure SaltaHastaEnd;
    function EsAperturaDeClase(AIdx: Integer): Boolean;
    function LeeNombreDeTipo: string;
    function LeeUses: TArray<string>;
    function SaltaCabeceraDeRutina: Boolean;
    function SaltaDirectivas: Boolean;
    procedure SaltaRutina;
    procedure SaltaBloque;
    procedure LeeDeclaraciones(AInterface: Boolean);
    procedure LeeSeccionType(const AContenedor: string);
    procedure LeeSeccionConst(AGuarda: Boolean);
    procedure SaltaSeccionVar;
    procedure LeeDefinicionDeTipo(const ANombre, AContenedor: string;
      AGenerica, AFuerte: Boolean; const AParametros: TArray<string>; ALinea: Integer);
    function LeeCuerpoDeClase(ATipo: TTipoPas): Boolean;
    procedure LeeCuerpoDeRegistro(ATipo: TTipoPas);
    function LeeMiembrosDeEnumerado: TArray<string>;
  public
    constructor Create(const ATexto: string; AUnidad: TUnidadPas);
    procedure Lee;
  end;

const
  // las palabras de una cabecera de rutina y sus directivas: PALABRAS_DE_RUTINA
  // y DIRECTIVAS_DE_RUTINA, del lexico (Lsp.Pascal)
  DIRECTIVAS_DE_TIPO: array [0 .. 3] of string = ('deprecated', 'platform',
    'experimental', 'library');
  CONVENCIONES: array [0 .. 5] of string = ('stdcall', 'cdecl', 'safecall',
    'register', 'pascal', 'winapi');

function EnLista(const S: string; const ALista: array of string): Boolean;
begin
  for var X in ALista do
    if S = X then
      Exit(True);
  Result := False;
end;

{ TTipoPas }

function TTipoPas.NombreCompleto: string;
begin
  if Contenedor = '' then
    Result := Nombre
  else
    Result := Contenedor + '.' + Nombre;
end;

function TTipoPas.Contiene(ALinea: Integer): Boolean;
begin
  Result := (ALinea >= Linea) and (ALinea <= LineaFin);
end;

{ TUnidadPas }

constructor TUnidadPas.Create;
begin
  inherited Create;
  Tipos := TObjectList<TTipoPas>.Create(True);
  Constantes := TDictionary<string, string>.Create;
end;

destructor TUnidadPas.Destroy;
begin
  Constantes.Free;
  Tipos.Free;
  inherited;
end;

function TUnidadPas.Clase(const ANombre: string; AClases: TClasesTipoPas): TTipoPas;
var
  T: TTipoPas;
begin
  Result := nil;
  for T in Tipos do
    if (T.Clase in AClases) and (MismoIdentificador(T.NombreCompleto, ANombre) or
       MismoIdentificador(T.Nombre, ANombre)) then
    begin
      if (T.Contenedor = '') or MismoIdentificador(T.NombreCompleto, ANombre) then
        Exit(T);
      if Result = nil then
        Result := T; // una anidada, si no hay otra
    end;
end;

function TUnidadPas.TipoQueEmpiezaEn(ALinea: Integer): TTipoPas;
begin
  Result := nil;
  for var T in Tipos do
    if (T.Linea = ALinea) and ((Result = nil) or (T.LineaFin > Result.LineaFin)) then
      Result := T;
end;

function TUnidadPas.Niveles(ATipo: TTipoPas): TArray<TTipoPas>;
var
  Cur, Padre: TTipoPas;
begin
  Result := [ATipo];
  Cur := ATipo;
  while Cur.Contenedor <> '' do
  begin
    // el que se llama como su contenedor y lo contiene (dos del mismo nombre,
    // las ramas de un IFDEF: el suyo)
    Padre := nil;
    for var T in Tipos do
      if (T <> Cur) and MismoIdentificador(T.NombreCompleto, Cur.Contenedor) and
         T.Contiene(Cur.Linea) then
      begin
        Padre := T;
        Break;
      end;
    if Padre = nil then
      Break;
    Result := [Padre] + Result;
    Cur := Padre;
  end;
end;

function TUnidadPas.NombreDeImplementacion(ATipo: TTipoPas): string;
var
  N: TArray<TTipoPas>;
begin
  N := Niveles(ATipo);
  // un contenedor que no se encontro: como esta escrito
  if N[0].Contenedor <> '' then
    Result := N[0].Contenedor + '.'
  else
    Result := '';
  for var K := 0 to High(N) do
  begin
    if K > 0 then
      Result := Result + '.';
    Result := Result + N[K].Nombre;
    if Length(N[K].ParametrosGenericos) > 0 then
      Result := Result + '<' + string.Join(', ', N[K].ParametrosGenericos) + '>';
  end;
end;

function TUnidadPas.PatronDeImplementacion(ATipo: TTipoPas): string;
var
  N: TArray<TTipoPas>;
begin
  N := Niveles(ATipo);
  Result := '';
  if N[0].Contenedor <> '' then
    for var Trozo in N[0].Contenedor.Split(['.']) do
      Result := Result + PatronIdentEntero(Trozo) + '\s*\.\s*';
  for var K := 0 to High(N) do
  begin
    if K > 0 then
      Result := Result + '\s*\.\s*';
    Result := Result + PatronIdentEntero(N[K].Nombre);
    // tantos parametros como tiene, se llamen como se llamen; uno sin ellos
    // no lleva '<' (TFoo y TFoo<T> son dos tipos)
    if Length(N[K].ParametrosGenericos) > 0 then
    begin
      Result := Result + '\s*<\s*' + PATRON_IDENT;
      for var J := 2 to Length(N[K].ParametrosGenericos) do
        Result := Result + '\s*,\s*' + PATRON_IDENT;
      Result := Result + '\s*>';
    end
    else
      Result := Result + '(?!\s*<)';
  end;
end;

function TUnidadPas.TipoEnLinea(ALinea: Integer; AClases: TClasesTipoPas;
  ASinCabecera: Boolean): TTipoPas;
var
  T: TTipoPas;
begin
  Result := nil;
  // el de mas dentro empieza despues que los que lo contienen
  for T in Tipos do
    if (T.Clase in AClases) and T.Contiene(ALinea) and
       (not ASinCabecera or (ALinea > T.Linea)) and
       ((Result = nil) or (T.Linea > Result.Linea) or
        ((T.Linea = Result.Linea) and (T.LineaFin < Result.LineaFin))) then
      Result := T;
end;

{ TLectorPas }

constructor TLectorPas.Create(const ATexto: string; AUnidad: TUnidadPas);
begin
  inherited Create;
  FTxt := ATexto;
  FLow := LowerCase(ATexto);
  FUnidad := AUnidad;
  // las lineas como las cuentan los que leen por lineas: CRLF, LF o un CR
  // suelto, un salto
  var N := 1;
  SetLength(FLineas, 64);
  FLineas[0] := 1;
  var I := 1;
  while I <= Length(FTxt) do
  begin
    if (FTxt[I] = #13) or (FTxt[I] = #10) then
    begin
      if (FTxt[I] = #13) and (I < Length(FTxt)) and (FTxt[I + 1] = #10) then
        Inc(I);
      if N = Length(FLineas) then
        SetLength(FLineas, N * 2);
      FLineas[N] := I + 1;
      Inc(N);
    end;
    Inc(I);
  end;
  SetLength(FLineas, N);
  Tokeniza;
end;

procedure TLectorPas.Tokeniza;
var
  I, J, L, Cap: Integer;
  C: Char;

  procedure Pon(AIni, ALen: Integer; AKind: TClaseTok);
  begin
    if FN = Cap then
    begin
      Cap := Cap * 2 + 64;
      SetLength(FIni, Cap);
      SetLength(FLen, Cap);
      SetLength(FKind, Cap);
    end;
    FIni[FN] := AIni;
    FLen[FN] := ALen;
    FKind[FN] := AKind;
    Inc(FN);
  end;

begin
  FN := 0;
  Cap := 0;
  L := Length(FTxt);
  I := 1;
  while I <= L do
  begin
    C := FTxt[I];
    if C <= ' ' then
    begin
      Inc(I);
      Continue;
    end;
    // EL identificador (Lsp.Pascal): aqui ya contaba como letra cualquier
    // caracter no ASCII, y es lo que hace dcc (medido el 4-oct-2026: un euro o
    // un espacio duro dentro de un nombre compilan); habia tres clasificadores
    // de caracter en el servidor, cada uno con su regla
    if EsLetraDeIdent(C) or ((C = '&') and (I < L) and EsLetraDeIdent(FTxt[I + 1])) then
    begin
      var Esc := C = '&';
      if Esc then
        Inc(I); // &Type es el identificador Type
      J := I;
      while (J <= L) and EsCaracterDeIdent(FTxt[J]) do
        Inc(J);
      if Esc then
        Pon(I, J - I, ttIdentEsc)
      else
        Pon(I, J - I, ttIdent);
      I := J;
    end
    else if CharInSet(C, ['0'..'9']) then
    begin
      J := I;
      while (J <= L) and (CharInSet(FTxt[J], ['0'..'9', 'A'..'Z', 'a'..'z', '_']) or
            ((FTxt[J] = '.') and (J < L) and CharInSet(FTxt[J + 1], ['0'..'9']))) do
        Inc(J);
      Pon(I, J - I, ttNumero);
      I := J;
    end
    else if CharInSet(C, ['$', '#', '%']) then
    begin
      J := I + 1;
      while (J <= L) and CharInSet(FTxt[J], ['0'..'9', 'A'..'F', 'a'..'f', '$']) do
        Inc(J);
      Pon(I, J - I, ttNumero);
      I := J;
    end
    else
    begin
      // los de dos caracteres que importan aqui; el resto, de uno. '>=' no:
      // en TFoo<T>=class es el cierre de los genericos y un '=' (Steema,
      // Tee.GridData.Rtti), y una comparacion no se lee en una declaracion
      if (I < L) and ((Copy(FTxt, I, 2) = '..') or (Copy(FTxt, I, 2) = ':=') or
         (Copy(FTxt, I, 2) = '<=') or (Copy(FTxt, I, 2) = '<>')) then
      begin
        Pon(I, 2, ttSimbolo);
        Inc(I, 2);
      end
      else
      begin
        Pon(I, 1, ttSimbolo);
        Inc(I);
      end;
    end;
  end;
  FI := 0;
end;

// Recien leido un bloque hasta su 'end' (consumido): la linea de ese 'end';
// -1 si el texto se acabo sin el
function TLectorPas.FinDeBloque: Integer;
begin
  if (FI > 0) and (FKind[FI - 1] = ttIdent) and SameText(Texto(FI - 1), 'end') then
    Result := LineaDeTok(FI - 1)
  else
    Result := -1;
end;

// La linea (0-based) del token AIdx; la del ultimo si AIdx se pasa
function TLectorPas.LineaDeTok(AIdx: Integer): Integer;
var
  Lo, Hi, Mid, P: Integer;
begin
  if AIdx >= FN then
    AIdx := FN - 1;
  if AIdx < 0 then
    Exit(0);
  P := FIni[AIdx];
  Lo := 0;
  Hi := High(FLineas);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if FLineas[Mid] <= P then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := Lo;
end;

function TLectorPas.Mira(AK: Integer): string;
var
  K: Integer;
begin
  K := FI + AK;
  if (K < 0) or (K >= FN) then
    Exit('');
  Result := Copy(FLow, FIni[K], FLen[K]);
  // &Object no es la palabra object: un campo &Object de un record cortaba
  // la unidad (uMakerAi.Chat.Mistral; revision de la 1.12.0)
  if FKind[K] = ttIdentEsc then
    Result := '&' + Result;
end;

function TLectorPas.EsIdent(AK: Integer): Boolean;
begin
  Result := EsIdentEn(FI + AK);
end;

function TLectorPas.EsIdentEn(AIdx: Integer): Boolean;
begin
  Result := (AIdx >= 0) and (AIdx < FN) and (FKind[AIdx] in [ttIdent, ttIdentEsc]);
end;

{ 'record' aqui abre un record (con su end), y no es la restriccion de un
  generico (<T: record> o <T: record, IFoo>), que no tiene end. }
function TLectorPas.AbreRecord: Boolean;
begin
  Result := (Mira = 'record') and (Mira(1) <> '>') and (Mira(1) <> ',');
end;

{ Desde un '<' hasta su '>' (consumido): cuantos argumentos o parametros
  genericos hay a su nivel (TFoo<A, B> = 2). }
function TLectorPas.SaltaGenericos: Integer;
var
  Prof: Integer;
  T: string;
begin
  Result := 0;
  Prof := 0;
  while not Fin do
  begin
    T := Mira;
    Toma;
    if T = '<' then
    begin
      Inc(Prof);
      if (Prof = 1) and (Result = 0) then
        Result := 1;
    end
    else if T = '>' then
    begin
      Dec(Prof);
      if Prof <= 0 then
        Exit;
    end
    else if (T = ',') and (Prof = 1) then
      Inc(Result);
  end;
end;

{ Desde el '<' de la cabecera de un tipo generico hasta su '>' (consumido):
  los nombres de sus parametros. En TFoo<K, V: class; T: constructor> son K,
  V y T: detras de ':' las comas separan restricciones, no parametros, y el
  ';' empieza otro grupo. Contadas como SaltaGenericos (que es para los
  ARGUMENTOS: TList<A, B>), TFoo<T: class, constructor> tenia dos y su
  descendiente class(TFoo<X>) buscaba otro (revision de la 1.13.0). }
function TLectorPas.LeeParametrosGenericos: TArray<string>;
var
  Prof: Integer;
  EnRestriccion: Boolean;
  T: string;
begin
  Result := [];
  Prof := 0;
  EnRestriccion := False;
  while not Fin do
  begin
    if (Prof = 1) and not EnRestriccion and EsIdent then
      Result := Result + [Texto(FI)];
    T := Mira;
    Toma;
    if T = '<' then
      Inc(Prof)
    else if T = '>' then
    begin
      Dec(Prof);
      if Prof <= 0 then
        Exit;
    end
    else if (Prof = 1) and (T = ':') then
      EnRestriccion := True
    else if (Prof = 1) and (T = ';') then
      EnRestriccion := False
    else if (Prof = 1) and (T = '[') then
      SaltaBalanceado('[', ']'); // un atributo del parametro
  end;
end;

function TLectorPas.Texto(AIdx: Integer): string;
begin
  if (AIdx < 0) or (AIdx >= FN) then
    Exit('');
  Result := Copy(FTxt, FIni[AIdx], FLen[AIdx]);
end;

function TLectorPas.Toma: string;
begin
  Result := Texto(FI);
  if FI < FN then
    Inc(FI);
end;

function TLectorPas.Fin: Boolean;
begin
  Result := FI >= FN;
end;

// Desde un AAbre, hasta su ACierra (consumido), contando los de dentro
procedure TLectorPas.SaltaBalanceado(const AAbre, ACierra: string);
var
  Prof: Integer;
  T: string;
begin
  Prof := 0;
  while not Fin do
  begin
    T := Mira;
    Toma;
    if T = AAbre then
      Inc(Prof)
    else if T = ACierra then
    begin
      Dec(Prof);
      if Prof <= 0 then
        Exit;
    end;
  end;
end;

{ Hasta el ';' que cierra lo que empieza aqui (consumido), a profundidad 0
  de parentesis, corchetes y records. Un 'end' a profundidad 0 lo cierra
  tambien SIN consumirlo: el ultimo campo de un record o de una clase puede
  ir sin ';'. }
procedure TLectorPas.SaltaHastaPuntoYComa;
var
  Prof: Integer;
  T: string;
begin
  Prof := 0;
  while not Fin do
  begin
    T := Mira;
    if (T = '(') or (T = '[') or AbreRecord then
      Inc(Prof)
    else if (T = ')') or (T = ']') then
      Dec(Prof)
    else if T = 'end' then
    begin
      if Prof <= 0 then
        Exit;
      Dec(Prof);
    end
    else if (T = ';') and (Prof <= 0) then
    begin
      Toma;
      Exit;
    end;
    Toma;
  end;
end;

{ 'class' en AIdx abre un bloque con su 'end' (la declaracion de una clase
  con cuerpo), y no es 'class of', 'class;', 'class function', 'class var',
  ni 'class(TX);' sin cuerpo. }
function TLectorPas.EsAperturaDeClase(AIdx: Integer): Boolean;
var
  K, Prof: Integer;
  S: string;
begin
  K := AIdx + 1;
  S := LowerCase(Texto(K));
  // ni 'class>' / 'class,': la restriccion de un generico (<T: class>)
  if (S = 'of') or (S = ';') or EnLista(S, PALABRAS_DE_RUTINA) or (S = 'var') or
     (S = 'threadvar') or (S = 'property') or (S = '>') or (S = ',') then
    Exit(False);
  while (S = 'abstract') or (S = 'sealed') do
  begin
    Inc(K);
    S := LowerCase(Texto(K));
  end;
  if S = '(' then
  begin
    Prof := 0;
    while K < FN do
    begin
      S := Texto(K);
      if S = '(' then
        Inc(Prof)
      else if S = ')' then
      begin
        Dec(Prof);
        if Prof = 0 then
          Break;
      end;
      Inc(K);
    end;
    Exit(Texto(K + 1) <> ';');
  end;
  Result := True;
end;

{ Desde justo detras de lo que abre un record, una interfaz, un object o un
  helper, hasta su 'end' (consumido), contando los bloques de dentro. }
procedure TLectorPas.SaltaHastaEnd;
var
  Prof: Integer;
  T, Ant: string;
begin
  Prof := 1;
  Ant := '';
  while not Fin do
  begin
    T := Mira;
    if AbreRecord or ((T = 'object') and (Ant <> 'of')) or
       (T = 'dispinterface') or
       ((T = 'interface') and (Mira(1) <> ';')) or
       ((T = 'class') and EsAperturaDeClase(FI)) then
      Inc(Prof)
    else if T = 'end' then
    begin
      Dec(Prof);
      if Prof = 0 then
      begin
        Toma;
        Exit;
      end;
    end;
    Ant := T;
    Toma;
  end;
end;

// Un nombre de tipo: Ident(.Ident)*, sin sus argumentos genericos
function TLectorPas.LeeNombreDeTipo: string;
begin
  Result := '';
  if not EsIdent then
    Exit;
  Result := Toma;
  FUltimaAridad := 0;
  if Mira = '<' then
    FUltimaAridad := SaltaGenericos;
  while (Mira = '.') and EsIdent(1) do
  begin
    Toma;
    Result := Result + '.' + Toma;
    FUltimaAridad := 0;
    if Mira = '<' then
      FUltimaAridad := SaltaGenericos;
  end;
end;

// La lista de un uses (ya pasado 'uses'), hasta su ';'
function TLectorPas.LeeUses: TArray<string>;
var
  Lista: TList<string>;
  N: string;
begin
  Lista := TList<string>.Create;
  try
    while not Fin do
    begin
      if EsIdent then
      begin
        N := Toma;
        while (Mira = '.') and EsIdent(1) do
        begin
          Toma;
          N := N + '.' + Toma;
        end;
        Lista.Add(N);
        // 'in' con su cadena (ya en blanco): hasta la coma o el ';'
        while not Fin and (Mira <> ',') and (Mira <> ';') do
          Toma;
      end;
      if Mira = ',' then
        Toma
      else
      begin
        if Mira = ';' then
          Toma;
        Break;
      end;
    end;
    Result := Lista.ToArray;
  finally
    Lista.Free;
  end;
end;

{ Lo de detras del ';' de una cabecera que es suyo (virtual; overload;
  message WM_X; external 'x' name 'y';...). True si dice que no hay cuerpo
  (forward, external). Un campo que se llama como una directiva (Message:
  string) no lo es: le sigue ':' o ','. }
function TLectorPas.SaltaDirectivas: Boolean;
var
  T: string;
begin
  Result := False;
  repeat
    T := Mira;
    if not EnLista(T, DIRECTIVAS_DE_RUTINA) or (Mira(1) = ':') or (Mira(1) = ',') then
      Exit;
    if (T = 'forward') or (T = 'external') then
      Result := True;
    SaltaHastaPuntoYComa;
  until Fin;
end;

{ Una cabecera de rutina: procedure|function|... Nombre[<T>](.Nombre)*
  [(params)] [: tipo]; y sus directivas. True si no lleva cuerpo. La
  clausula de resolucion (procedure IFoo.Bar = Baz;) tambien. }
function TLectorPas.SaltaCabeceraDeRutina: Boolean;
begin
  Toma; // la palabra de la rutina
  while EsIdent do
  begin
    Toma;
    if Mira = '<' then
      SaltaBalanceado('<', '>');
    if Mira = '.' then
      Toma
    else
      Break;
  end;
  if Mira = '=' then
  begin
    SaltaHastaPuntoYComa;
    Exit(True);
  end;
  if Mira = '(' then
    SaltaBalanceado('(', ')');
  SaltaHastaPuntoYComa; // el tipo de resultado, si lo hay, va dentro
  Result := SaltaDirectivas;
end;

{ Un bloque de sentencias desde su begin/asm/try/case hasta su end. Dentro
  de un asm no hay Pascal: lo cierra el primer end que no es una etiqueta.
  La de Vcl.Graphics y Vcl.Imaging.GIFImg en su rama de 32 bits se llama
  @@END: contada como un end, la rutina acababa ahi y las clases que venian
  detras no salian en la tabla (medido el 4-oct-2026 leyendo como Win32). }
procedure TLectorPas.SaltaBloque;
var
  Prof: Integer;
  T: string;
  EnAsm: Boolean;
begin
  Prof := 0;
  EnAsm := False;
  while not Fin do
  begin
    T := Mira;
    Toma;
    if EnAsm then
    begin
      // Mira(-2): lo que va delante del end recien tomado
      if (T = 'end') and (Mira(-2) <> '@') then
      begin
        EnAsm := False;
        Dec(Prof);
        if Prof <= 0 then
          Exit;
      end;
    end
    else if T = 'asm' then
    begin
      EnAsm := True;
      Inc(Prof);
    end
    else if (T = 'begin') or (T = 'try') or (T = 'case') then
      Inc(Prof)
    else if T = 'end' then
    begin
      Dec(Prof);
      if Prof <= 0 then
        Exit;
    end;
  end;
end;

{ Una rutina del implementation: cabecera, declaraciones locales (sus
  tipos se leen: una clase local tambien es una clase) y cuerpo. }
procedure TLectorPas.SaltaRutina;
var
  T: string;
begin
  if SaltaCabeceraDeRutina then
    Exit;
  while not Fin do
  begin
    T := Mira;
    if (T = 'begin') or (T = 'asm') then
    begin
      SaltaBloque;
      if Mira = ';' then
        Toma;
      Exit;
    end
    else if T = 'type' then
    begin
      Toma;
      LeeSeccionType('');
    end
    else if (T = 'const') or (T = 'resourcestring') then
    begin
      Toma;
      LeeSeccionConst(False);
    end
    else if (T = 'var') or (T = 'threadvar') then
    begin
      Toma;
      SaltaSeccionVar;
    end
    else if EnLista(T, PALABRAS_DE_RUTINA) then
      SaltaRutina
    else if T = 'class' then
      Toma
    else if T = 'label' then
      SaltaHastaPuntoYComa
    else
      Exit; // algo que no es de una rutina: la deja el que llamo
  end;
end;

procedure TLectorPas.SaltaSeccionVar;
begin
  while not Fin do
  begin
    if Mira = '[' then
    begin
      SaltaBalanceado('[', ']');
      Continue;
    end;
    if not EsIdent or not ((Mira(1) = ':') or (Mira(1) = ',')) then
      Exit;
    SaltaHastaPuntoYComa;
  end;
end;

procedure TLectorPas.LeeSeccionConst(AGuarda: Boolean);
var
  Nombre: string;
  Ini: Integer;
begin
  while not Fin do
  begin
    if Mira = '[' then
    begin
      SaltaBalanceado('[', ']');
      Continue;
    end;
    if not EsIdent or not ((Mira(1) = '=') or (Mira(1) = ':')) then
      Exit;
    Nombre := Toma;
    if Mira = '=' then
    begin
      Toma;
      Ini := FI;
      SaltaHastaPuntoYComa;
      // un valor simple: un token (numero, True, False) y su ';'
      if AGuarda and (FI - Ini = 2) and (Texto(FI - 1) = ';') then
        FUnidad.Constantes.AddOrSetValue(Nombre, Texto(Ini));
    end
    else
      SaltaHastaPuntoYComa; // con tipo: no es de las que mira un IF
  end;
end;

function TLectorPas.LeeMiembrosDeEnumerado: TArray<string>;
var
  Lista: TList<string>;
  Prof: Integer;
begin
  Lista := TList<string>.Create;
  try
    Toma; // '('
    while not Fin do
    begin
      if EsIdent then
        Lista.Add(Toma);
      // un valor (= expr): hasta la coma o el ')' de fuera
      Prof := 0;
      while not Fin do
      begin
        if Mira = '(' then
          Inc(Prof)
        else if Mira = ')' then
        begin
          if Prof = 0 then
            Break;
          Dec(Prof);
        end
        else if (Mira = ',') and (Prof = 0) then
          Break;
        Toma;
      end;
      if Mira = ',' then
        Toma
      else
      begin
        if Mira = ')' then
          Toma;
        Break;
      end;
    end;
    Result := Lista.ToArray;
  finally
    Lista.Free;
  end;
end;

procedure TLectorPas.LeeDefinicionDeTipo(const ANombre, AContenedor: string;
  AGenerica, AFuerte: Boolean; const AParametros: TArray<string>; ALinea: Integer);
var
  T: TTipoPas;
  P: string;
  Ini, Fin_, K, Prof, Puntos: Integer;
  EsNombre, FinLeido: Boolean;
begin
  FinLeido := False; // la linea de su 'end' (los de bloque); si no, la de su ';'
  T := TTipoPas.Create;
  T.Nombre := ANombre;
  T.Linea := ALinea;
  T.LineaFin := ALinea;
  T.Contenedor := AContenedor;
  T.Generica := AGenerica;
  T.ParametrosGenericos := AParametros;
  T.Aridad := Length(AParametros);
  T.Fuerte := AFuerte;
  T.EnImplementation := FEnImpl;
  T.Clase := ctOtro;
  try
    if Mira = 'packed' then
      Toma;
    P := Mira;
    if P = 'class' then
    begin
      Toma;
      P := Mira;
      if P = 'of' then
      begin
        Toma;
        T.Clase := ctReferenciaClase;
        T.Base := LeeNombreDeTipo;
        SaltaHastaPuntoYComa;
      end
      else if P = ';' then
      begin
        Toma; // la declaracion adelantada: el cuerpo viene despues
        FreeAndNil(T);
      end
      else
      begin
        if P = 'helper' then
        begin
          // class helper [(TOtroHelper)] for TX: su cuerpo, como el de una
          // clase. Se saltaba entero (ctOtro) e insert=metodo contestaba que
          // no encontraba la clase (revision de la 1.13.0)
          Toma;
          T.Clase := ctAyudante;
          if Mira = '(' then
            SaltaBalanceado('(', ')');
          if Mira = 'for' then
          begin
            Toma;
            T.Base := LeeNombreDeTipo;
          end;
        end
        else
          while (Mira = 'abstract') or (Mira = 'sealed') do
            Toma;
        if T.Clase <> ctAyudante then
          T.Clase := ctClase;
        if (T.Clase = ctClase) and (Mira = '(') then
        begin
          Toma;
          T.Ancestro := LeeNombreDeTipo;
          T.AncestroAridad := FUltimaAridad;
          // las interfaces de la lista, hasta el ')'
          Prof := 1;
          while not Fin do
          begin
            if Mira = '(' then
              Inc(Prof)
            else if Mira = ')' then
            begin
              Dec(Prof);
              if Prof = 0 then
              begin
                Toma;
                Break;
              end;
            end;
            Toma;
          end;
        end;
        if Mira = ';' then
        begin
          Toma; // sin cuerpo: class(TX);
          T.SinCuerpo := True;
        end
        else
        begin
          // sin su end (un fuente a medio escribir: empezo otro tipo antes),
          // LineaFin -1 y lo que sigue es de la seccion
          if LeeCuerpoDeClase(T) then
          begin
            T.LineaFin := FinDeBloque;
            SaltaHastaPuntoYComa; // 'end' ya pasado; sus directivas y el ';'
          end
          else
            T.LineaFin := -1;
          FinLeido := True;
        end;
      end;
    end
    else if P = 'record' then
    begin
      Toma;
      T.Clase := ctRegistro;
      if Mira = 'helper' then
        SaltaHastaEnd
      else
        LeeCuerpoDeRegistro(T);
      T.LineaFin := FinDeBloque;
      FinLeido := True;
      SaltaHastaPuntoYComa;
    end
    else if (P = 'interface') or (P = 'dispinterface') then
    begin
      Toma;
      if Mira = ';' then
      begin
        Toma;
        FreeAndNil(T);
      end
      else
      begin
        T.Clase := ctInterfaz;
        if Mira = '(' then
          SaltaBalanceado('(', ')');
        SaltaHastaEnd;
        T.LineaFin := FinDeBloque;
        FinLeido := True;
        SaltaHastaPuntoYComa;
      end;
    end
    else if P = 'object' then
    begin
      Toma;
      T.Clase := ctRegistro;
      if Mira = '(' then
        SaltaBalanceado('(', ')');
      SaltaHastaEnd;
      T.LineaFin := FinDeBloque;
      FinLeido := True;
      SaltaHastaPuntoYComa;
    end
    else if P = '(' then
    begin
      T.Clase := ctEnumerado;
      T.Miembros := LeeMiembrosDeEnumerado;
      SaltaHastaPuntoYComa;
    end
    else if P = 'set' then
    begin
      Toma;
      if Mira = 'of' then
        Toma;
      T.Clase := ctConjunto;
      if Mira = '(' then
        T.Miembros := LeeMiembrosDeEnumerado
      else
      begin
        Ini := FI;
        T.Base := LeeNombreDeTipo;
        if Mira = '..' then
        begin
          // set of A..B: la base es el subrango
          FI := Ini;
          T.Base := '';
          Toma;
          if Mira = '..' then
          begin
            Toma;
            T.Alto := Toma;
          end;
          T.Base := Texto(Ini) + '..' + T.Alto;
          T.Alto := '';
        end;
      end;
      SaltaHastaPuntoYComa;
    end
    else if (P = 'procedure') or (P = 'function') then
    begin
      Toma;
      if Mira = '(' then
        SaltaBalanceado('(', ')');
      T.Clase := ctProcedimiento;
      // el tipo de resultado y 'of object', hasta el ';'
      while not Fin and (Mira <> ';') do
      begin
        if (Mira = 'of') and (Mira(1) = 'object') then
        begin
          Toma;
          T.Clase := ctMetodo;
        end;
        Toma;
      end;
      if Mira = ';' then
        Toma;
      // la convencion de llamada puede ir detras del ';'
      while EnLista(Mira, CONVENCIONES) and (Mira(1) = ';') do
      begin
        Toma;
        Toma;
      end;
    end
    else if P = 'reference' then
    begin
      T.Clase := ctProcedimiento;
      SaltaHastaPuntoYComa;
    end
    else
    begin
      // una expresion hasta el ';': alias, subrango, puntero, array...
      Ini := FI;
      Prof := 0;
      Puntos := -1;
      while not Fin do
      begin
        // un record dentro (TX = array[..] of record ... end;) tambien: con
        // solo parentesis, el primer ';' del record cortaba la unidad
        // (JvProfilerForm, SynPdf; revision de la 1.12.0)
        if (Mira = '(') or (Mira = '[') or AbreRecord then
          Inc(Prof)
        else if (Mira = ')') or (Mira = ']') then
          Dec(Prof)
        else if (Mira = ';') and (Prof <= 0) then
          Break
        else if Mira = 'end' then
        begin
          if Prof <= 0 then
            Break;
          Dec(Prof);
        end
        else if (Mira = '..') and (Prof <= 0) and (Puntos < 0) then
          Puntos := FI;
        Toma;
      end;
      Fin_ := FI; // el ';' (o el end)
      // sin las directivas del final (TX = Integer deprecated;)
      while (Fin_ > Ini) and EnLista(LowerCase(Texto(Fin_ - 1)), DIRECTIVAS_DE_TIPO) do
        Dec(Fin_);
      if Puntos >= 0 then
      begin
        T.Clase := ctSubrango;
        T.Base := '';
        for K := Ini to Puntos - 1 do
          T.Base := T.Base + Texto(K);
        T.Alto := '';
        for K := Puntos + 1 to Fin_ - 1 do
          T.Alto := T.Alto + Texto(K);
      end
      else
      begin
        // Ident(.Ident)* (con sus <...> fuera) es un alias
        EsNombre := (Fin_ > Ini) and EsIdentEn(Ini) and
          (LowerCase(Texto(Ini)) <> 'array') and (LowerCase(Texto(Ini)) <> 'file');
        K := Ini + 1;
        while EsNombre and (K < Fin_) do
        begin
          if (Texto(K) = '.') and (K + 1 < Fin_) and EsIdentEn(K + 1) then
            Inc(K, 2)
          else if Texto(K) = '<' then
          begin
            // los argumentos genericos, hasta el '>' de fuera
            Prof := 0;
            while K < Fin_ do
            begin
              if Texto(K) = '<' then
                Inc(Prof)
              else if Texto(K) = '>' then
              begin
                Dec(Prof);
                if Prof = 0 then
                  Break;
              end;
              Inc(K);
            end;
            Inc(K);
          end
          else
            EsNombre := False;
        end;
        if EsNombre then
        begin
          T.Clase := ctAlias;
          T.Base := Texto(Ini);
          K := Ini + 1;
          while (K + 1 < Fin_) and (Texto(K) = '.') do
          begin
            T.Base := T.Base + '.' + Texto(K + 1);
            Inc(K, 2);
          end;
        end;
      end;
      if Mira = ';' then
        Toma;
    end;
    if T <> nil then
    begin
      if not FinLeido then
      begin
        T.LineaFin := LineaDeTok(FI - 1);
        if T.LineaFin < ALinea then
          T.LineaFin := ALinea;
      end;
      FUnidad.Tipos.Add(T);
    end;
  except
    T.Free;
    raise;
  end;
end;

{ El cuerpo de una clase (o de un class helper), desde detras de su cabecera
  hasta su 'end' (consumido): True. False si no se cierra: empieza otro tipo
  de la seccion antes (un fuente a medio escribir), que queda sin consumir. }
function TLectorPas.LeeCuerpoDeClase(ATipo: TTipoPas): Boolean;
var
  Vis: TVisibilidadPas;
  Props: TList<TPropiedadPas>;
  Secs: TList<TSeccionPas>;
  LosCampos, LasRutinas: TList<TMiembroPas>;
  T: string;
  DeClase: Boolean;
  // los campos de detras de un 'class var', hasta otra seccion o miembro
  EnClassVar: Boolean;

  procedure LeePropiedad;
  var
    P: TPropiedadPas;
  begin
    Toma; // 'property'
    P := Default(TPropiedadPas);
    P.Linea := LineaDeTok(FI);
    P.Nombre := Toma;
    P.Visibilidad := Vis;
    P.DeClase := DeClase;
    if Mira = '[' then
    begin
      P.ConIndices := True;
      SaltaBalanceado('[', ']');
    end;
    if Mira = ':' then
    begin
      Toma;
      P.Tipo := LeeNombreDeTipo;
    end;
    SaltaHastaPuntoYComa;
    // la propiedad por defecto de un array: 'default;' detras
    if (Mira = 'default') and (Mira(1) = ';') then
    begin
      Toma;
      Toma;
    end;
    while EnLista(Mira, DIRECTIVAS_DE_TIPO) and (Mira(1) <> ':') and (Mira(1) <> ',') do
      SaltaHastaPuntoYComa;
    Props.Add(P);
  end;

  function EsVisibilidad(const S: string; out AVis: TVisibilidadPas): Boolean;
  begin
    Result := True;
    if S = 'private' then
      AVis := vpPrivada
    else if S = 'protected' then
      AVis := vpProtegida
    else if S = 'public' then
      AVis := vpPublica
    else if S = 'published' then
      AVis := vpPublicada
    else if S = 'automated' then
      AVis := vpAutomatizada
    else
      Result := False;
  end;

  procedure AnotaSeccion(AVis: TVisibilidadPas; const APalabra: string; ALinea: Integer);
  var
    S: TSeccionPas;
  begin
    S.Visibilidad := AVis;
    S.Palabra := APalabra;
    S.Linea := ALinea;
    Secs.Add(S);
  end;

  // la rutina que empieza aqui (Mira = su palabra); 'procedure IFoo.Bar = Baz;'
  // (la clausula de resolucion de una interfaz) no declara ninguna
  procedure AnotaRutina;
  var
    M: TMiembroPas;
  begin
    if not EsIdent(1) or (Mira(2) = '.') then
      Exit;
    M := Default(TMiembroPas);
    M.Nombre := Texto(FI + 1);
    M.Rutina := Mira;
    M.DeClase := DeClase;
    M.Visibilidad := Vis;
    M.Linea := LineaDeTok(FI + 1);
    LasRutinas.Add(M);
  end;

  // 'A, B: TButton;': los campos de una declaracion, con su tipo si es un
  // nombre ('' si es un array, un record, un procedure...)
  procedure LeeCampos;
  var
    Nuevos: TArray<TMiembroPas>;
    M: TMiembroPas;
    Tipo: string;
    Generico: Boolean;
    Ini: Integer;
  begin
    Nuevos := [];
    while EsIdent do
    begin
      M := Default(TMiembroPas);
      M.Linea := LineaDeTok(FI);
      M.Nombre := Toma;
      M.Visibilidad := Vis;
      M.DeClase := EnClassVar;
      Nuevos := Nuevos + [M];
      if Mira = ',' then
        Toma
      else
        Break;
    end;
    if Mira <> ':' then
    begin
      SaltaHastaPuntoYComa; // no es un campo: lo que no se sabe leer
      Exit;
    end;
    Toma;
    // el tipo es un nombre si detras viene el ';' (o el end del ultimo); si
    // no, se vuelve atras: un 'record' consumido aqui desbalanceaba el salto
    Ini := FI;
    Tipo := LeeNombreDeTipo;
    Generico := FUltimaAridad > 0;
    if (Tipo = '') or ((Mira <> ';') and (Mira <> 'end')) then
    begin
      FI := Ini;
      Tipo := '';
      Generico := False;
    end;
    SaltaHastaPuntoYComa;
    for M in Nuevos do
    begin
      var C := M;
      C.Tipo := Tipo;
      C.Generico := Generico;
      LosCampos.Add(C);
    end;
  end;

var
  NuevaVis: TVisibilidadPas;
begin
  Result := True;
  Vis := vpDefecto;
  EnClassVar := False;
  Props := TList<TPropiedadPas>.Create;
  Secs := TList<TSeccionPas>.Create;
  LosCampos := TList<TMiembroPas>.Create;
  LasRutinas := TList<TMiembroPas>.Create;
  try
    while not Fin do
    begin
      T := Mira;
      DeClase := False;
      if T = 'end' then
      begin
        Toma;
        Break;
      end;
      // 'strict' delante de private/protected; un campo Strict: Boolean no
      if (T = 'strict') and ((Mira(1) = 'private') or (Mira(1) = 'protected')) then
      begin
        EnClassVar := False;
        var LineaStrict := LineaDeTok(FI);
        Toma;
        if Mira = 'private' then
          Vis := vpPrivada
        else
          Vis := vpProtegida;
        AnotaSeccion(Vis, 'strict ' + Mira, LineaStrict);
        Toma;
        Continue;
      end;
      if EsVisibilidad(T, NuevaVis) and (Mira(1) <> ':') and (Mira(1) <> ',') and
         (Mira(1) <> '=') then
      begin
        Vis := NuevaVis;
        EnClassVar := False;
        AnotaSeccion(Vis, T, LineaDeTok(FI));
        Toma;
        Continue;
      end;
      if T = '[' then
      begin
        SaltaBalanceado('[', ']');
        Continue;
      end;
      if T = 'class' then
      begin
        Toma;
        DeClase := True;
        T := Mira;
        if T = 'property' then
          LeePropiedad
        else if EnLista(T, PALABRAS_DE_RUTINA) then
        begin
          AnotaRutina;
          SaltaCabeceraDeRutina;
        end
        else if (T = 'var') or (T = 'threadvar') then
        begin
          Toma;
          EnClassVar := True;
          Continue;
        end;
        EnClassVar := False;
        Continue;
      end;
      if EnLista(T, PALABRAS_DE_RUTINA) then
      begin
        EnClassVar := False;
        AnotaRutina;
        SaltaCabeceraDeRutina;
        Continue;
      end;
      if T = 'property' then
      begin
        EnClassVar := False;
        LeePropiedad;
        Continue;
      end;
      if T = 'type' then
      begin
        EnClassVar := False;
        Toma;
        LeeSeccionType(ATipo.NombreCompleto);
        Continue;
      end;
      if (T = 'const') or (T = 'resourcestring') then
      begin
        EnClassVar := False;
        Toma;
        LeeSeccionConst(False);
        Continue;
      end;
      if (T = 'var') or (T = 'threadvar') then
      begin
        EnClassVar := False;
        Toma;
        Continue;
      end;
      if T = ';' then
      begin
        Toma;
        Continue;
      end;
      if EsIdent then
      begin
        // 'Nombre =' fuera de una seccion type no es un tipo anidado (esos van
        // detras de su 'type', y LeeSeccionType los lee todos). Con el nombre
        // de esta clase es su cabecera otra vez: la otra rama de un IFDEF
        // ({$IFDEF A} TFoo = class(TA) {$ELSE} TFoo = class(TB) {$ENDIF}),
        // que el lector de las dos ramas ve aqui; se salta y lo de detras
        // sigue siendo suyo. Con otro, la clase no se cerro: acaba aqui sin su
        // end y ese tipo es el siguiente de la seccion. Leidos como anidados,
        // todo lo de detras quedaba dentro de esta clase e insert=metodo
        // escribia TFoo.TBar.X (revision de la 1.13.0)
        if (Mira(1) = '=') or (Mira(1) = '<') then
        begin
          if not MismoIdentificador(Texto(FI), ATipo.Nombre) then
          begin
            Result := False;
            Break;
          end;
          Toma;
          if Mira = '<' then
            SaltaBalanceado('<', '>');
          if Mira = '=' then
            Toma;
          if Mira = 'packed' then
            Toma;
          if Mira = 'class' then
          begin
            Toma;
            while (Mira = 'abstract') or (Mira = 'sealed') do
              Toma;
            if Mira = '(' then
              SaltaBalanceado('(', ')');
          end;
        end
        else
          LeeCampos;
        Continue;
      end;
      Toma; // lo que no se sabe leer
    end;
    ATipo.Propiedades := Props.ToArray;
    ATipo.Secciones := Secs.ToArray;
    ATipo.Campos := LosCampos.ToArray;
    ATipo.Rutinas := LasRutinas.ToArray;
  finally
    LasRutinas.Free;
    LosCampos.Free;
    Secs.Free;
    Props.Free;
  end;
end;

{ Un record avanzado, desde detras de 'record' hasta su 'end' (consumido):
  sus campos y sus metodos se saltan, sus tipos anidados se leen
  (TArchitectures = set of TOSVersion.TArchitecture: el enumerado vive en
  un record de System.SysUtils). }
procedure TLectorPas.LeeCuerpoDeRegistro(ATipo: TTipoPas);
var
  Prof: Integer;
  T, Ant: string;
begin
  Prof := 1;
  Ant := '';
  while not Fin do
  begin
    T := Mira;
    if (Prof = 1) and (T = 'type') then
    begin
      Toma;
      LeeSeccionType(ATipo.NombreCompleto);
      Ant := '';
      Continue;
    end;
    if AbreRecord or ((T = 'object') and (Ant <> 'of')) or
       ((T = 'class') and EsAperturaDeClase(FI)) then
      Inc(Prof)
    else if T = 'end' then
    begin
      Dec(Prof);
      if Prof = 0 then
      begin
        Toma;
        Exit;
      end;
    end;
    Ant := T;
    Toma;
  end;
end;

{ Una seccion type: Nombre[<T>] = [type] definicion; hasta lo que no es una
  declaracion de tipo (otra seccion, un miembro de la clase, el end). }
procedure TLectorPas.LeeSeccionType(const AContenedor: string);
var
  Nombre: string;
  Generica, Fuerte: Boolean;
  Parametros: TArray<string>;
  LineaNombre: Integer;
begin
  while not Fin do
  begin
    if Mira = '[' then
    begin
      SaltaBalanceado('[', ']');
      Continue;
    end;
    if Mira = ';' then
    begin
      Toma;
      Continue;
    end;
    if not EsIdent or not ((Mira(1) = '=') or (Mira(1) = '<')) then
      Exit;
    LineaNombre := LineaDeTok(FI);
    Nombre := Toma;
    Generica := False;
    Parametros := [];
    if Mira = '<' then
    begin
      Parametros := LeeParametrosGenericos;
      Generica := True;
    end;
    if Mira <> '=' then
    begin
      SaltaHastaPuntoYComa;
      Continue;
    end;
    Toma;
    Fuerte := False;
    if Mira = 'type' then
    begin
      Toma;
      Fuerte := True;
    end;
    LeeDefinicionDeTipo(Nombre, AContenedor, Generica, Fuerte, Parametros, LineaNombre);
  end;
end;

procedure TLectorPas.LeeDeclaraciones(AInterface: Boolean);
var
  T: string;
begin
  while not Fin do
  begin
    T := Mira;
    if (T = 'implementation') or (T = 'initialization') or (T = 'finalization') or
       (T = 'end') or (AInterface and (T = 'begin')) then
      Exit;
    if (T = 'begin') or (T = 'asm') then
    begin
      // el bloque principal (begin..end.) o el cuerpo de una rutina otra vez:
      // la otra rama de un IFDEF ({$IFDEF PUREPASCAL} begin..end; {$ELSE}
      // asm..end; {$ENDIF}), que el lector de las dos ramas ve suelto. Si
      // detras de su end no viene el punto, era eso: se salta y se sigue.
      // Paraba aqui, y las clases del implementation que venian detras no
      // estaban (revision de la 1.13.0)
      var Ini := FI;
      SaltaBloque;
      if Fin or (Mira = '.') then
      begin
        FI := Ini;
        Exit;
      end;
      Continue;
    end;
    if T = 'uses' then
    begin
      Toma;
      if AInterface then
        FUnidad.UsesInterface := FUnidad.UsesInterface + LeeUses
      else
        FUnidad.UsesImplementation := FUnidad.UsesImplementation + LeeUses;
    end
    else if T = 'type' then
    begin
      Toma;
      LeeSeccionType('');
    end
    else if (T = 'const') or (T = 'resourcestring') then
    begin
      Toma;
      LeeSeccionConst(AInterface and (T = 'const'));
    end
    else if (T = 'var') or (T = 'threadvar') then
    begin
      Toma;
      SaltaSeccionVar;
    end
    else if EnLista(T, PALABRAS_DE_RUTINA) then
    begin
      if AInterface then
        SaltaCabeceraDeRutina
      else
        SaltaRutina;
    end
    else if T = '[' then
      SaltaBalanceado('[', ']')
    else if (T = 'exports') or (T = 'label') then
      SaltaHastaPuntoYComa
    else
      Toma; // 'class' de 'class procedure TX.Y', o lo que no se sabe leer
  end;
end;

procedure TLectorPas.Lee;
begin
  // un programa o una biblioteca: sus tipos tambien (una clase de un .dpr de
  // consola es tan clase como la de una unidad); sus rutinas llevan cuerpo
  if (Mira = 'program') or (Mira = 'library') then
  begin
    Toma;
    FUnidad.Programa := Toma;
    while (Mira = '.') and EsIdent(1) do
    begin
      Toma;
      FUnidad.Programa := FUnidad.Programa + '.' + Toma;
    end;
    SaltaHastaPuntoYComa;
    FEnImpl := True;
    LeeDeclaraciones(False);
    Exit;
  end;
  if Mira <> 'unit' then
    Exit;
  Toma;
  FUnidad.Nombre := Toma;
  while (Mira = '.') and EsIdent(1) do
  begin
    Toma;
    FUnidad.Nombre := FUnidad.Nombre + '.' + Toma;
  end;
  SaltaHastaPuntoYComa;
  if Mira = 'interface' then
    Toma;
  FEnImpl := False;
  LeeDeclaraciones(True);
  if Mira = 'implementation' then
  begin
    Toma;
    FEnImpl := True;
    LeeDeclaraciones(False);
  end;
end;

function LeeUnidadPascal(const ATextoActivo: string): TUnidadPas;
var
  L: TLectorPas;
begin
  Result := TUnidadPas.Create;
  try
    L := TLectorPas.Create(ATextoActivo, Result);
    try
      L.Lee;
    finally
      L.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function LeeFuentePascal(const AFuente: string): TUnidadPas;
begin
  // CodigoPascal: comentarios, cadenas y directivas en blanco, con el mismo
  // largo y los saltos en su sitio (las lineas del lector son las del fuente)
  Result := LeeUnidadPascal(CodigoPascal(AFuente));
end;

function ClaseDeImplementacion(const ALinea, ARutina: string): string;
const
  // un nivel: su nombre y, si es generico, sus parametros (en una cabecera
  // del implementation son nombres: TFoo<K, V>)
  NIVEL = PATRON_IDENT + '(?:\s*<[^<>()]*>)?';
var
  M: TMatch;
begin
  Result := '';
  M := TRegEx.Match(ALinea, '(?i)\b' + PatronPalabraDeRutina + '\s+(' + NIVEL +
    '(?:\s*\.\s*' + NIVEL + ')*?)\s*\.\s*' + PatronIdentEntero(ARutina));
  if not M.Success then
    Exit;
  Result := TRegEx.Replace(M.Groups[1].Value, '\s*<[^<>()]*>', '');
  Result := UltimoTrozo(TRegEx.Replace(Result, '\s', ''));
end;

procedure AnotaAncestros(const AUnidad: TUnidadPas; AMapa: TDictionary<string, string>);
var
  T: TTipoPas;
  K: string;
begin
  for T in AUnidad.Tipos do
    if T.Clase = ctClase then
    begin
      K := ClaveDeIdentificador(T.Nombre);
      if (T.Contenedor = '') or not AMapa.ContainsKey(K) then
        AMapa.AddOrSetValue(K, T.Ancestro);
    end;
end;

function CadenaDeAncestros(const AMapa: TDictionary<string, string>;
  const AClase: string; out ASale: Boolean; ATope: Integer): TArray<string>;
var
  Cur, Anc, K: string;
  Vistas: TArray<string>;
begin
  ASale := False;
  Result := [];
  Vistas := [];
  Cur := AClase;
  while (Cur <> '') and (Length(Result) < ATope) do
  begin
    K := ClaveDeIdentificador(UltimoTrozo(Cur));
    // un ciclo (un fuente a medio escribir): se para. Pero uno cualificado
    // con el nombre de una ya vista es OTRA clase, la de fuera de una
    // interpuesta (TBaseForm = class(UBase.TBaseForm)): una clase no es su
    // propio ancestro, y la cadena sale por ahi. Se tomaba por un ciclo y la
    // cadena quedaba completa: check-binding daba por sobrantes los
    // componentes heredados (revision de la 1.13.0)
    for var V in Vistas do
      if V = K then
      begin
        if Pos('.', Cur) > 0 then
        begin
          Result := Result + [Cur];
          ASale := True;
        end;
        Exit;
      end;
    Vistas := Vistas + [K];
    Result := Result + [Cur];
    if not AMapa.TryGetValue(K, Anc) then
    begin
      ASale := True;
      Exit;
    end;
    Cur := Anc;
  end;
end;

end.
