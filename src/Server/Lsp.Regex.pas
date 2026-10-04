unit Lsp.Regex;

{ Lo que el TRegEx del RTL hace distinto de lo que uno espera, en UN sitio.

  Un grupo de captura que NO participa en la coincidencia (dentro de un
  (...)?, de un (...)* o de una rama de una alternativa) y que va detras del
  ultimo que si participo NO EXISTE: TMatch.Groups solo cuenta hasta el
  ultimo grupo que participo, y Groups[N] de uno de esos es la excepcion
  'Index out of bounds (N)'. Uno que no participo pero lleva otro detras que
  si existe: vacio, con Success = True (el Success de cada grupo es el de la
  coincidencia entera, System.RegularExpressions, TGroupCollection.Create) y
  con Index 1 y Length 0, lo mismo que un grupo vacio al principio del texto
  (medido). El RTL no deja saber si un grupo participo: solo su texto, o
  nada.

  Medido el 4-oct-2026: delphi_designer lint y check-binding caian con
  SYS-006 'Index out of bounds (2)' en un form de produccion (Hermes, en la
  VM 13.2) porque su .pas declaraba 'TTableSchemaClass = class of
  TTableSchema;': la cabecera de clase se leia con su ancestro en un grupo
  opcional, y Groups[2] no existia. Tres sitios del servidor ya se guardaban
  de esto, cada uno a su manera (Groups.Count > 4, Groups[Count - 1],
  Count > 2 y Success, que no media lo que creia); quien lee un grupo que
  puede no participar lo lee con GrupoDe. }

interface

uses
  System.RegularExpressions,
  System.RegularExpressionsAPI;

// El texto del grupo AIndice de AMatch; '' si no participo, si esta vacio o
// si AMatch no casa. Nunca cae
function GrupoDe(const AMatch: TMatch; AIndice: Integer): string;

type
  // lo que da buscar con una expresion del agente: tambien que el motor se rindio
  TResultadoBusqueda = (rbCasa, rbNoCasa, rbSeRinde);

  { Una expresion escrita por el AGENTE (delphi_search regex=true), con las
    opciones de un TRegEx [roIgnoreCase] (UTF-8, sin distinguir mayusculas,
    cualquier salto), buscada con pcre_exec a mano: TRegEx toma por "no casa"
    CUALQUIER error del motor (el fuente de la RTL: 'Result := OffsetCount >
    0'), y una expresion que agota el limite de pasos del motor (backtracking:
    (a*)*$ en una linea de treinta aes) daba cero resultados en silencio, sin
    colgarse y sin decirlo (medido el 4-oct-2026). Las del servidor son suyas
    y estan medidas; las del agente, por aqui. }
  TExprDelAgente = class
  private
    FPatron: PPCRE;
  public
    // AError <> '': no compila, con el motivo del motor y su posicion
    constructor Create(const AExpr: string; out AError: string);
    destructor Destroy; override;
    // la primera coincidencia en ATexto desde AInicio (1-based), con su
    // posicion (1-based) y su largo, en caracteres de ATexto
    function Busca(const ATexto: string; AInicio: Integer;
      out AIndice, ALongitud: Integer): TResultadoBusqueda;
  end;

implementation

uses
  System.SysUtils;

function GrupoDe(const AMatch: TMatch; AIndice: Integer): string;
begin
  if AMatch.Success and (AIndice >= 0) and (AIndice < AMatch.Groups.Count) then
    Result := AMatch.Groups[AIndice].Value
  else
    Result := '';
end;

{ TExprDelAgente }

// La RTL usa el PCRE de 16 bits en Windows (System.RegularExpressionsAPI
// define PCRE16 si MSWINDOWS): la cadena va tal cual, en UTF-16, y el motor
// cuenta en caracteres de la cadena; la opcion PCRE_UTF8 es alli PCRE_UTF16
// (el mismo bit). La primera version de esto le pasaba UTF-8 y solo casaban
// las expresiones de un caracter (medido). Fuera de Windows, UTF-8 y se
// cuenta en bytes.
constructor TExprDelAgente.Create(const AExpr: string; out AError: string);
var
  Err: MarshaledAString;
  ErrOfs: Integer;
{$IFNDEF MSWINDOWS}
  U: UTF8String;
{$ENDIF}
begin
  inherited Create;
  AError := '';
{$IFDEF MSWINDOWS}
  FPatron := pcre_compile(PCRE_STR(PChar(AExpr)), PCRE_UTF8 or PCRE_CASELESS or PCRE_NEWLINE_ANY,
    @Err, @ErrOfs, nil);
{$ELSE}
  U := UTF8String(AExpr);
  FPatron := pcre_compile(PCRE_STR(PAnsiChar(U)), PCRE_UTF8 or PCRE_CASELESS or PCRE_NEWLINE_ANY,
    @Err, @ErrOfs, nil);
{$ENDIF}
  if FPatron = nil then
    AError := Format('%s (at %d)', [string(AnsiString(Err)), ErrOfs]);
end;

destructor TExprDelAgente.Destroy;
begin
  // pcre_free en la DLL da una violacion de acceso: pcre_dispose (la RTL)
  pcre_dispose(FPatron, nil, nil);
  inherited;
end;

function TExprDelAgente.Busca(const ATexto: string; AInicio: Integer;
  out AIndice, ALongitud: Integer): TResultadoBusqueda;
var
  Ofs: array [0 .. 2] of Integer; // solo la coincidencia entera
  R: Integer;
{$IFNDEF MSWINDOWS}
  U: UTF8String;
{$ENDIF}
begin
  AIndice := 0;
  ALongitud := 0;
{$IFDEF MSWINDOWS}
  R := pcre_exec(FPatron, nil, PCRE_STR(PChar(ATexto)), Length(ATexto), AInicio - 1,
    PCRE_NO_UTF8_CHECK, @Ofs[0], 3);
{$ELSE}
  // en UTF-8 el motor cuenta en bytes: lo que ocupan los caracteres de delante
  U := UTF8String(ATexto);
  R := pcre_exec(FPatron, nil, PCRE_STR(PAnsiChar(U)), Length(U),
    Length(UTF8String(Copy(ATexto, 1, AInicio - 1))), PCRE_NO_UTF8_CHECK, @Ofs[0], 3);
{$ENDIF}
  // (0: casa, pero no caben los grupos; aqui no hacen falta)
  if R >= 0 then
  begin
{$IFDEF MSWINDOWS}
    AIndice := Ofs[0] + 1;
    ALongitud := Ofs[1] - Ofs[0];
{$ELSE}
    AIndice := Length(string(Copy(U, 1, Ofs[0]))) + 1;
    ALongitud := Length(string(Copy(U, Ofs[0] + 1, Ofs[1] - Ofs[0])));
{$ENDIF}
    Exit(rbCasa);
  end;
  if R = PCRE_ERROR_NOMATCH then
    Exit(rbNoCasa);
  Result := rbSeRinde; // el limite de pasos, el de recursion, o cualquier otro error
end;

end.
