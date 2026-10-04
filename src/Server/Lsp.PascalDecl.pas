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
  hover traen la visibilidad). Lsp.DesignerBinding y la insercion de
  Lsp.Patch leen las secciones de UNA clase de un form por lineas; esto lee
  una unidad entera por tokens. }

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
  end;

  TClaseTipoPas = (ctEnumerado, ctConjunto, ctSubrango, ctAlias, ctMetodo,
    ctClase, ctRegistro, ctInterfaz, ctReferenciaClase, ctProcedimiento, ctOtro);

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
    // cuantos parametros genericos tiene (0 = ninguno) y cuantos lleva su
    // ancestro: TFoo y TFoo<T, U> son DOS tipos en la misma unidad
    // (REST.Backend.BindSource: el generico desciende del que no lo es)
    Aridad: Integer;
    AncestroAridad: Integer;
    EnImplementation: Boolean;
    // 'TCustomButton.TButtonStyle' o 'TButton': el nombre con su contenedor
    function NombreCompleto: string;
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
    constructor Create;
    destructor Destroy; override;
  end;

function LeeUnidadPascal(const ATextoActivo: string): TUnidadPas;

implementation

uses
  System.SysUtils;

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
    procedure Tokeniza;
    function Mira(AK: Integer = 0): string;
    function EsIdent(AK: Integer = 0): Boolean;
    function EsIdentEn(AIdx: Integer): Boolean;
    function AbreRecord: Boolean;
    function SaltaGenericos: Integer;
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
      AGenerica, AFuerte: Boolean; AAridad: Integer);
    procedure LeeCuerpoDeClase(ATipo: TTipoPas);
    procedure LeeCuerpoDeRegistro(ATipo: TTipoPas);
    function LeeMiembrosDeEnumerado: TArray<string>;
  public
    constructor Create(const ATexto: string; AUnidad: TUnidadPas);
    procedure Lee;
  end;

const
  RUTINAS: array [0 .. 4] of string = ('procedure', 'function', 'constructor',
    'destructor', 'operator');
  // lo que va detras del ';' de una cabecera de rutina y es suyo
  DIRECTIVAS_DE_RUTINA: array [0 .. 30] of string = ('virtual', 'override',
    'overload', 'reintroduce', 'abstract', 'dynamic', 'static', 'inline',
    'final', 'message', 'stdcall', 'cdecl', 'safecall', 'register', 'pascal',
    'winapi', 'deprecated', 'platform', 'experimental', 'library', 'dispid',
    'varargs', 'export', 'far', 'near', 'assembler', 'unsafe', 'forward',
    'external', 'local', 'noreturn');
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

{ TLectorPas }

constructor TLectorPas.Create(const ATexto: string; AUnidad: TUnidadPas);
begin
  inherited Create;
  FTxt := ATexto;
  FLow := LowerCase(ATexto);
  FUnidad := AUnidad;
  Tokeniza;
end;

function EsLetra(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (Ord(C) >= $80);
end;

function EsLetraODigito(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '0'..'9']) or (Ord(C) >= $80);
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
    if EsLetra(C) or ((C = '&') and (I < L) and EsLetra(FTxt[I + 1])) then
    begin
      var Esc := C = '&';
      if Esc then
        Inc(I); // &Type es el identificador Type
      J := I;
      while (J <= L) and EsLetraODigito(FTxt[J]) do
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
  if (S = 'of') or (S = ';') or EnLista(S, RUTINAS) or (S = 'var') or
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

// Un bloque de sentencias desde su begin/asm/try/case hasta su end
procedure TLectorPas.SaltaBloque;
var
  Prof: Integer;
  T: string;
begin
  Prof := 0;
  while not Fin do
  begin
    T := Mira;
    Toma;
    if (T = 'begin') or (T = 'try') or (T = 'case') or (T = 'asm') then
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
    else if EnLista(T, RUTINAS) then
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
  AGenerica, AFuerte: Boolean; AAridad: Integer);
var
  T: TTipoPas;
  P: string;
  Ini, Fin_, K, Prof, Puntos: Integer;
  EsNombre: Boolean;
begin
  T := TTipoPas.Create;
  T.Nombre := ANombre;
  T.Contenedor := AContenedor;
  T.Generica := AGenerica;
  T.Aridad := AAridad;
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
      else if P = 'helper' then
      begin
        Toma;
        SaltaHastaEnd;
        SaltaHastaPuntoYComa;
      end
      else
      begin
        while (Mira = 'abstract') or (Mira = 'sealed') do
          Toma;
        T.Clase := ctClase;
        if Mira = '(' then
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
          Toma // sin cuerpo: class(TX);
        else
        begin
          LeeCuerpoDeClase(T);
          SaltaHastaPuntoYComa; // 'end' ya pasado; sus directivas y el ';'
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
      FUnidad.Tipos.Add(T);
  except
    T.Free;
    raise;
  end;
end;

procedure TLectorPas.LeeCuerpoDeClase(ATipo: TTipoPas);
var
  Vis: TVisibilidadPas;
  Props: TList<TPropiedadPas>;
  T: string;
  DeClase: Boolean;

  procedure LeePropiedad;
  var
    P: TPropiedadPas;
  begin
    Toma; // 'property'
    P := Default(TPropiedadPas);
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

var
  NuevaVis: TVisibilidadPas;
begin
  Vis := vpDefecto;
  Props := TList<TPropiedadPas>.Create;
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
      if T = 'strict' then
      begin
        Toma;
        if Mira = 'private' then
          Vis := vpPrivada
        else
          Vis := vpProtegida;
        Toma;
        Continue;
      end;
      if EsVisibilidad(T, NuevaVis) and (Mira(1) <> ':') and (Mira(1) <> ',') and
         (Mira(1) <> '=') then
      begin
        Vis := NuevaVis;
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
        else if EnLista(T, RUTINAS) then
          SaltaCabeceraDeRutina
        else if (T = 'var') or (T = 'threadvar') then
          Toma;
        Continue;
      end;
      if EnLista(T, RUTINAS) then
      begin
        SaltaCabeceraDeRutina;
        Continue;
      end;
      if T = 'property' then
      begin
        LeePropiedad;
        Continue;
      end;
      if T = 'type' then
      begin
        Toma;
        LeeSeccionType(ATipo.NombreCompleto);
        Continue;
      end;
      if (T = 'const') or (T = 'resourcestring') then
      begin
        Toma;
        LeeSeccionConst(False);
        Continue;
      end;
      if (T = 'var') or (T = 'threadvar') then
      begin
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
        // un tipo anidado que sigue a otro de la misma seccion, o un campo
        if (Mira(1) = '=') or (Mira(1) = '<') then
          LeeSeccionType(ATipo.NombreCompleto)
        else
          SaltaHastaPuntoYComa;
        Continue;
      end;
      Toma; // lo que no se sabe leer
    end;
    ATipo.Propiedades := Props.ToArray;
  finally
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
  Aridad: Integer;
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
    Nombre := Toma;
    Generica := False;
    Aridad := 0;
    if Mira = '<' then
    begin
      Aridad := SaltaGenericos;
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
    LeeDefinicionDeTipo(Nombre, AContenedor, Generica, Fuerte, Aridad);
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
       (T = 'begin') or (T = 'end') then
      Exit;
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
    else if EnLista(T, RUTINAS) then
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

end.
