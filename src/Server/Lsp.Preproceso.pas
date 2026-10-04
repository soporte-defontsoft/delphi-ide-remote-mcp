unit Lsp.Preproceso;

{ EL PREPROCESADOR de la casa: el texto Pascal tal como lo ve el COMPILADOR
  con unos simbolos dados. Las ramas de IFDEF/IFNDEF/IF/ELSEIF/ELSE que no se
  toman, en blanco; un $I fichero sustituido por lo que el compilador leeria
  de el; DEFINE/UNDEF aplicados en su sitio. Y en blanco tambien los
  comentarios, las cadenas y las directivas: lo que queda es CODIGO, con los
  saltos de linea en su sitio.

  Encima de EL lexico (Lsp.Pascal): que es una directiva lo decide
  DirectivasPascal, y una directiva dentro de un comentario o de una cadena
  no lo es.

  Los simbolos se DERIVAN de la version del compilador y de la plataforma
  (SimbolosDeDelphi): la 37.0 es VER370 y CompilerVersion 37.0, sin una
  lista por version (David, 3-oct-2026: "no podemos depender de un pas
  hardcodeado a una version concreta"). Lo que pregunta el fuente de verdad
  en un IF, medido el 3-oct-2026 en los 4.125 .pas/.inc que alcanza el IDE
  de la 37.0 (Browsing Path y Library Search Path): Defined() 10.780 veces,
  CompilerVersion 515, Declared() 273, SizeOf() 173, RTLVersion 28. Un
  identificador que no se conoce vale 0, como un simbolo sin definir: la
  rama que lo pregunta no se toma. }

interface

uses
  System.Generics.Collections;

type
  { Lo que el compilador tiene definido mientras lee: los simbolos de IFDEF
    (los cambian DEFINE/UNDEF), las constantes que mira un IF
    (CompilerVersion, RTLVersion y las que se le den: las de System) y el
    tamano de los tipos del compilador para SizeOf(). Las claves no
    distinguen mayusculas, como Pascal. }
  TSimbolosPascal = class
  private
    FDefines: TDictionary<string, Boolean>;
    FConstantes: TDictionary<string, Double>;
    FTamanos: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Define(const ANombre: string);
    procedure Quita(const ANombre: string);
    function Definido(const ANombre: string): Boolean;
    procedure PonConstante(const ANombre: string; AValor: Double);
    function Constante(const ANombre: string; out AValor: Double): Boolean;
    procedure PonTamano(const ATipo: string; ABytes: Integer);
    // 0 = no se sabe
    function Tamano(const ATipo: string): Integer;
    // Una copia: lo que una unidad define no se lo lleva la siguiente, que el
    // compilador empieza cada una con los simbolos del proyecto
    function Copia: TSimbolosPascal;
  end;

  { Quien busca el texto de un $I: ANombre tal como va en la directiva, sin
    comillas; '' si no esta. }
  TBuscaInclude = reference to function(const ANombre: string): string;

{ Los simbolos del compilador de ESA version ('37.0', la de CompilerVersion)
  para ESA plataforma ('Win32'/'Win64'): VER370, los de Windows y de la CPU,
  CompilerVersion = RTLVersion = 37.0 y los tamanos de sus tipos. Derivados,
  nunca de una lista por version. }
function SimbolosDeDelphi(const AVersionCompilador, APlataforma: string): TSimbolosPascal;

{ El texto que ve el compilador (ver la cabecera). ASimbolos cambia con los
  DEFINE/UNDEF activos, tambien los de un include. Un $I que AIncluye no
  encuentra se queda en blanco. AConCadenas: las cadenas se quedan, para
  quien busca un literal (los nombres de Filer.DefineProperty). }
function TextoActivo(const ATexto: string; ASimbolos: TSimbolosPascal;
  const AIncluye: TBuscaInclude = nil; AConCadenas: Boolean = False): string;

{ El valor de la expresion de un IF/ELSEIF: Defined(X), Declared(X),
  SizeOf(T), constantes, numeros, = <> < > <= >=, + - * / div mod, and or
  xor not y parentesis. Lo que no se entiende vale 0 (falso). }
function EvaluaCondicion(const AExpresion: string; ASimbolos: TSimbolosPascal): Boolean;

implementation

uses
  System.SysUtils,
  System.Math,
  Lsp.Pascal;

const
  // Un include que se incluye a si mismo (o un ciclo) no cuelga el lector
  MAX_INCLUDES = 16;

{ TSimbolosPascal }

constructor TSimbolosPascal.Create;
begin
  inherited Create;
  FDefines := TDictionary<string, Boolean>.Create;
  FConstantes := TDictionary<string, Double>.Create;
  FTamanos := TDictionary<string, Integer>.Create;
end;

destructor TSimbolosPascal.Destroy;
begin
  FTamanos.Free;
  FConstantes.Free;
  FDefines.Free;
  inherited;
end;

procedure TSimbolosPascal.Define(const ANombre: string);
begin
  if ANombre <> '' then
    FDefines.AddOrSetValue(ClaveDeIdentificador(ANombre), True);
end;

procedure TSimbolosPascal.Quita(const ANombre: string);
begin
  FDefines.Remove(ClaveDeIdentificador(ANombre));
end;

function TSimbolosPascal.Definido(const ANombre: string): Boolean;
begin
  Result := FDefines.ContainsKey(ClaveDeIdentificador(ANombre));
end;

procedure TSimbolosPascal.PonConstante(const ANombre: string; AValor: Double);
begin
  if ANombre <> '' then
    FConstantes.AddOrSetValue(ClaveDeIdentificador(ANombre), AValor);
end;

function TSimbolosPascal.Constante(const ANombre: string; out AValor: Double): Boolean;
begin
  Result := FConstantes.TryGetValue(ClaveDeIdentificador(ANombre), AValor);
end;

procedure TSimbolosPascal.PonTamano(const ATipo: string; ABytes: Integer);
begin
  FTamanos.AddOrSetValue(ClaveDeIdentificador(ATipo), ABytes);
end;

function TSimbolosPascal.Tamano(const ATipo: string): Integer;
begin
  if not FTamanos.TryGetValue(ClaveDeIdentificador(ATipo), Result) then
    Result := 0;
end;

function TSimbolosPascal.Copia: TSimbolosPascal;
begin
  Result := TSimbolosPascal.Create;
  for var D in FDefines do
    Result.FDefines.Add(D.Key, D.Value);
  for var C in FConstantes do
    Result.FConstantes.Add(C.Key, C.Value);
  for var T in FTamanos do
    Result.FTamanos.Add(T.Key, T.Value);
end;

function SimbolosDeDelphi(const AVersionCompilador, APlataforma: string): TSimbolosPascal;
var
  V: Double;
  Puntero, Extendido, Variante: Integer;
begin
  Result := TSimbolosPascal.Create;
  V := StrToFloatDef(AVersionCompilador, 0, TFormatSettings.Invariant);
  // VER<n>: la version del compilador por diez (37.0 -> VER370, 36.0 -> VER360)
  if V > 0 then
    Result.Define('VER' + IntToStr(Round(V * 10)));
  Result.PonConstante('CompilerVersion', V);
  Result.PonConstante('RTLVersion', V);
  // Los que el compilador de Windows define siempre (Predefined Conditionals)
  for var S in ['DCC', 'CONDITIONALEXPRESSIONS', 'NATIVECODE', 'UNICODE',
    'MSWINDOWS', 'ASSEMBLER'] do
    Result.Define(S);
  if SameText(APlataforma, 'Win64') then
  begin
    for var S in ['WIN64', 'CPUX64', 'CPU64BITS'] do
      Result.Define(S);
    Puntero := 8;
    Extendido := 8; // en Win64 Extended es un Double
    Variante := 24;
  end
  else
  begin
    for var S in ['WIN32', 'CPUX86', 'CPU32BITS', 'UNDERSCOREIMPORTNAME'] do
      Result.Define(S);
    Puntero := 4;
    Extendido := 10;
    Variante := 16;
  end;
  // SizeOf() de los tipos del compilador en esa plataforma (son del
  // lenguaje, no de una version). Tambien son lo que Declared() sabe que esta
  // declarado de System: el fuente pregunta Declared(AnsiChar),
  // Declared(UTF8Char), Declared(TBytes)... y dcc dice que si en Windows
  for var T in ['Pointer', 'NativeInt', 'NativeUInt', 'string', 'UnicodeString',
    'AnsiString', 'WideString', 'RawByteString', 'UTF8String', 'TObject',
    'IInterface', 'PChar', 'PAnsiChar', 'PWideChar', 'PUTF8Char', 'PByte',
    'TBytes'] do
    Result.PonTamano(T, Puntero);
  for var T in ['Byte', 'ShortInt', 'Int8', 'UInt8', 'AnsiChar', 'UTF8Char',
    'Boolean', 'ByteBool'] do
    Result.PonTamano(T, 1);
  for var T in ['Word', 'SmallInt', 'Int16', 'UInt16', 'Char', 'WideChar',
    'WordBool'] do
    Result.PonTamano(T, 2);
  for var T in ['Integer', 'Cardinal', 'LongInt', 'LongWord', 'Int32', 'UInt32',
    'FixedInt', 'FixedUInt', 'Single', 'Float32', 'LongBool'] do
    Result.PonTamano(T, 4);
  for var T in ['Int64', 'UInt64', 'Double', 'Float64', 'Real', 'Currency',
    'Comp', 'TDateTime'] do
    Result.PonTamano(T, 8);
  Result.PonTamano('ShortString', 256);
  Result.PonTamano('Extended', Extendido);
  Result.PonTamano('Variant', Variante);
  Result.PonTamano('OleVariant', Variante);
end;

{ ---- la expresion de un IF ---- }

type
  TEvaluador = class
  private
    FToks: TArray<string>;
    FP: Integer;
    FSim: TSimbolosPascal;
    function Mira: string;
    function Toma: string;
    function Nombre: string;
    function Argumento: string;
    function Primario: Double;
    function Unario: Double;
    function Producto: Double;
    function Suma: Double;
    function Relacion: Double;
    function Negacion: Double;
    function Conjuncion: Double;
    function Disyuncion: Double;
  public
    constructor Create(const AExpresion: string; ASim: TSimbolosPascal);
    function Valor: Double;
  end;

function Bool(A: Boolean): Double;
begin
  if A then
    Result := 1
  else
    Result := 0;
end;

constructor TEvaluador.Create(const AExpresion: string; ASim: TSimbolosPascal);
var
  I, J: Integer;
  C: Char;
  Lista: TList<string>;
begin
  inherited Create;
  FSim := ASim;
  Lista := TList<string>.Create;
  try
    I := 1;
    while I <= Length(AExpresion) do
    begin
      C := AExpresion[I];
      if CharInSet(C, [' ', #9, #10, #13]) then
        Inc(I)
      else if EsLetraDeIdent(C) then // EL identificador (Lsp.Pascal)
      begin
        J := I;
        while (J <= Length(AExpresion)) and EsCaracterDeIdent(AExpresion[J]) do
          Inc(J);
        Lista.Add(Copy(AExpresion, I, J - I));
        I := J;
      end
      else if CharInSet(C, ['0'..'9']) then
      begin
        J := I;
        while (J <= Length(AExpresion)) and (CharInSet(AExpresion[J], ['0'..'9']) or
              ((AExpresion[J] = '.') and (J < Length(AExpresion)) and
               CharInSet(AExpresion[J + 1], ['0'..'9']))) do
          Inc(J);
        Lista.Add(Copy(AExpresion, I, J - I));
        I := J;
      end
      else if C = '$' then
      begin
        J := I + 1;
        while (J <= Length(AExpresion)) and
              CharInSet(AExpresion[J], ['0'..'9', 'A'..'F', 'a'..'f']) do
          Inc(J);
        Lista.Add(IntToStr(StrToInt64Def('$' + Copy(AExpresion, I + 1, J - I - 1), 0)));
        I := J;
      end
      else if CharInSet(C, ['<', '>']) and (I < Length(AExpresion)) and
              CharInSet(AExpresion[I + 1], ['=', '>']) and
              not ((C = '>') and (AExpresion[I + 1] = '>')) then
      begin
        Lista.Add(Copy(AExpresion, I, 2));
        Inc(I, 2);
      end
      else
      begin
        Lista.Add(C);
        Inc(I);
      end;
    end;
    FToks := Lista.ToArray;
  finally
    Lista.Free;
  end;
  FP := 0;
end;

function TEvaluador.Mira: string;
begin
  if FP <= High(FToks) then
    Result := FToks[FP]
  else
    Result := '';
end;

function TEvaluador.Toma: string;
begin
  Result := Mira;
  Inc(FP);
end;

// Un nombre con sus puntos (System.Embedded): lo que viene, unido
function TEvaluador.Nombre: string;
begin
  Result := Toma;
  while (Mira = '.') and (FP < High(FToks)) do
  begin
    Toma;
    Result := Result + '.' + Toma;
  end;
end;

// Lo de dentro de unos parentesis que ya se abrieron, hasta el que cierra
function TEvaluador.Argumento: string;
var
  Prof: Integer;
  T: string;
begin
  Result := '';
  Prof := 1;
  while FP <= High(FToks) do
  begin
    T := Toma;
    if T = '(' then
      Inc(Prof)
    else if T = ')' then
    begin
      Dec(Prof);
      if Prof = 0 then
        Exit;
    end;
    Result := Result + T;
  end;
end;

function TEvaluador.Primario: Double;
var
  T, L, Arg: string;
  V: Double;
begin
  Result := 0;
  T := Mira;
  if T = '' then
    Exit;
  if T = '(' then
  begin
    Toma;
    Result := Disyuncion;
    if Mira = ')' then
      Toma;
    Exit;
  end;
  if CharInSet(T[1], ['0'..'9']) then
  begin
    Toma;
    Exit(StrToFloatDef(T, 0, TFormatSettings.Invariant));
  end;
  if not EsLetraDeIdent(T[1]) then
  begin
    Toma; // un simbolo suelto: no vale nada
    Exit;
  end;
  L := LowerCase(T);
  if L = 'true' then
  begin
    Toma;
    Exit(1);
  end;
  if L = 'false' then
  begin
    Toma;
    Exit(0);
  end;
  T := Nombre;
  L := LowerCase(T);
  if Mira = '(' then
  begin
    Toma;
    Arg := Argumento;
    if L = 'defined' then
      Result := Bool(FSim.Definido(Arg))
    else if L = 'declared' then
      // declarado = una constante que se conoce (las de System se le dan al
      // lector: System.Embedded no lo esta en Windows, RTLVersion131 si) o un
      // tipo del compilador. Los tipos de otras unidades (socklen_t,
      // _OUTLINETEXTMETRICW) no: harian falta sus declaraciones leidas en el
      // orden del uses, y ninguno cambia lo publicado
      Result := Bool(FSim.Constante(Arg, V) or FSim.Constante(UltimoTrozo(Arg), V)
        or (FSim.Tamano(UltimoTrozo(Arg)) > 0))
    else if L = 'sizeof' then
      Result := FSim.Tamano(UltimoTrozo(Arg));
    // otra funcion (Ord, Length...): 0
    Exit;
  end;
  if FSim.Constante(T, V) or FSim.Constante(UltimoTrozo(T), V) then
    Result := V;
end;

function TEvaluador.Unario: Double;
begin
  if Mira = '-' then
  begin
    Toma;
    Result := -Unario;
  end
  else if Mira = '+' then
  begin
    Toma;
    Result := Unario;
  end
  else
    Result := Primario;
end;

function TEvaluador.Producto: Double;
var
  Op: string;
  B: Double;
begin
  Result := Unario;
  repeat
    Op := LowerCase(Mira);
    if (Op <> '*') and (Op <> '/') and (Op <> 'div') and (Op <> 'mod') then
      Exit;
    Toma;
    B := Unario;
    if Op = '*' then
      Result := Result * B
    else if B = 0 then
      Result := 0 // ni el compilador divide por cero: la rama no se toma
    else if Op = '/' then
      Result := Result / B
    else if Op = 'div' then
      Result := Trunc(Result) div Trunc(B)
    else
      Result := Trunc(Result) mod Trunc(B);
  until False;
end;

function TEvaluador.Suma: Double;
var
  Op: string;
begin
  Result := Producto;
  repeat
    Op := Mira;
    if (Op <> '+') and (Op <> '-') then
      Exit;
    Toma;
    if Op = '+' then
      Result := Result + Producto
    else
      Result := Result - Producto;
  until False;
end;

function TEvaluador.Relacion: Double;
var
  Op: string;
  A, B: Double;
begin
  A := Suma;
  Op := Mira;
  if (Op = '=') or (Op = '<>') or (Op = '<') or (Op = '>') or (Op = '<=') or (Op = '>=') then
  begin
    Toma;
    B := Suma;
    if Op = '=' then
      Exit(Bool(SameValue(A, B)))
    else if Op = '<>' then
      Exit(Bool(not SameValue(A, B)))
    else if Op = '<' then
      Exit(Bool((A < B) and not SameValue(A, B)))
    else if Op = '>' then
      Exit(Bool((A > B) and not SameValue(A, B)))
    else if Op = '<=' then
      Exit(Bool((A < B) or SameValue(A, B)))
    else
      Exit(Bool((A > B) or SameValue(A, B)));
  end;
  Result := A;
end;

// not liga mas que and/or y menos que una comparacion: 'not A >= 3' es
// not (A >= 3), lo que quiere decir quien lo escribe sin parentesis
function TEvaluador.Negacion: Double;
begin
  if SameText(Mira, 'not') then
  begin
    Toma;
    Result := Bool(Negacion = 0);
  end
  else
    Result := Relacion;
end;

function TEvaluador.Conjuncion: Double;
var
  B: Double;
begin
  Result := Negacion;
  while SameText(Mira, 'and') do
  begin
    Toma;
    B := Negacion;
    Result := Bool((Result <> 0) and (B <> 0));
  end;
end;

function TEvaluador.Disyuncion: Double;
var
  Op: string;
  B: Double;
begin
  Result := Conjuncion;
  repeat
    Op := LowerCase(Mira);
    if (Op <> 'or') and (Op <> 'xor') then
      Exit;
    Toma;
    B := Conjuncion;
    if Op = 'or' then
      Result := Bool((Result <> 0) or (B <> 0))
    else
      Result := Bool((Result <> 0) <> (B <> 0));
  until False;
end;

function TEvaluador.Valor: Double;
begin
  Result := Disyuncion;
end;

function EvaluaCondicion(const AExpresion: string; ASimbolos: TSimbolosPascal): Boolean;
var
  E: TEvaluador;
begin
  E := TEvaluador.Create(AExpresion, ASimbolos);
  try
    Result := E.Valor <> 0;
  finally
    E.Free;
  end;
end;

{ ---- el texto activo ---- }

function PrimeraPalabra(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and EsCaracterDeIdent(S[I]) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

// El fichero de un $I/$INCLUDE: lo de detras, sin comillas. '' si es el
// interruptor de E/S ($I+ / $I-) o una macro de FPC ($I %DATE%)
function NombreDeInclude(const AArgumento: string): string;
begin
  Result := AArgumento.Trim;
  if (Result = '') or (Result = '+') or (Result = '-') or Result.StartsWith('%') then
    Exit('');
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

type
  TRama = record
    PadreActivo: Boolean; // estaba activo lo de fuera
    Tomada: Boolean;      // ya se tomo una rama (o no se puede tomar ninguna)
  end;

function TextoActivoEn(const ATexto: string; ASimbolos: TSimbolosPascal;
  const AIncluye: TBuscaInclude; AProfundidad: Integer; AConCadenas: Boolean): string;
var
  Clases: TArray<TClasePascal>;
  Dirs: TArray<TDirectivaPascal>;
  Sb: TStringBuilder;
  Pila: TList<TRama>;
  Desde: Integer;
  Activo, Cond: Boolean;
  Arg, Inc_, Txt: string;
  R: TRama;

  procedure Copia(AHasta: Integer);
  var
    K: Integer;
    C: Char;
  begin
    for K := Desde to AHasta - 1 do
    begin
      C := ATexto[K];
      if (C = #10) or (C = #13) then
        Sb.Append(C)
      else if Activo and ((Clases[K] = cpCodigo) or
              (AConCadenas and (Clases[K] = cpCadena))) then
        Sb.Append(C)
      else
        Sb.Append(' ');
    end;
  end;

begin
  Clases := ClasesPascal(ATexto);
  Dirs := DirectivasPascal(ATexto);
  Sb := TStringBuilder.Create(Length(ATexto) + 16);
  Pila := TList<TRama>.Create;
  try
    Desde := 1;
    Activo := True;
    for var D in Dirs do
    begin
      Copia(D.Inicio);
      Desde := D.Inicio + D.Largo;
      Sb.Append(' '); // la directiva separa lo de antes de lo de despues
      Arg := D.Argumento.Trim;
      if (D.Nombre = 'IFDEF') or (D.Nombre = 'IFNDEF') or (D.Nombre = 'IF') or
         (D.Nombre = 'IFOPT') then
      begin
        Cond := False;
        if Activo then
        begin
          if D.Nombre = 'IFDEF' then
            Cond := ASimbolos.Definido(PrimeraPalabra(Arg))
          else if D.Nombre = 'IFNDEF' then
            Cond := not ASimbolos.Definido(PrimeraPalabra(Arg))
          else if D.Nombre = 'IF' then
            Cond := EvaluaCondicion(Arg, ASimbolos);
          // IFOPT pregunta por un interruptor del compilador: no se sigue
        end;
        R.PadreActivo := Activo;
        R.Tomada := Cond or not Activo;
        Pila.Add(R);
        Activo := Activo and Cond;
      end
      else if D.Nombre = 'ELSEIF' then
      begin
        if Pila.Count > 0 then
        begin
          R := Pila.Last;
          Activo := False;
          if R.PadreActivo and not R.Tomada then
          begin
            Activo := EvaluaCondicion(Arg, ASimbolos);
            R.Tomada := Activo;
          end;
          Pila[Pila.Count - 1] := R;
        end;
      end
      else if D.Nombre = 'ELSE' then
      begin
        if Pila.Count > 0 then
        begin
          R := Pila.Last;
          Activo := R.PadreActivo and not R.Tomada;
          R.Tomada := True;
          Pila[Pila.Count - 1] := R;
        end;
      end
      else if (D.Nombre = 'ENDIF') or (D.Nombre = 'IFEND') then
      begin
        if Pila.Count > 0 then
        begin
          Activo := Pila.Last.PadreActivo;
          Pila.Delete(Pila.Count - 1);
        end;
      end
      else if not Activo then
        Continue
      else if D.Nombre = 'DEFINE' then
        ASimbolos.Define(PrimeraPalabra(Arg))
      else if D.Nombre = 'UNDEF' then
        ASimbolos.Quita(PrimeraPalabra(Arg))
      else if (D.Nombre = 'I') or (D.Nombre = 'INCLUDE') then
      begin
        Inc_ := NombreDeInclude(Arg);
        if (Inc_ <> '') and Assigned(AIncluye) and (AProfundidad < MAX_INCLUDES) then
        begin
          Txt := AIncluye(Inc_);
          if Txt <> '' then
            Sb.Append(TextoActivoEn(Txt, ASimbolos, AIncluye, AProfundidad + 1, AConCadenas));
        end;
      end;
    end;
    Copia(Length(ATexto) + 1);
    Result := Sb.ToString;
  finally
    Pila.Free;
    Sb.Free;
  end;
end;

function TextoActivo(const ATexto: string; ASimbolos: TSimbolosPascal;
  const AIncluye: TBuscaInclude; AConCadenas: Boolean): string;
begin
  Result := TextoActivoEn(ATexto, ASimbolos, AIncluye, 0, AConCadenas);
end;

end.
