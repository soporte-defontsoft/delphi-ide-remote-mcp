unit Mcp.Tools.DelphiLsp;

{ MCP tools backed by DelphiLSP: delphi_symbols, delphi_definition,
  delphi_hover, delphi_completion. All positions are 0-based (LSP style).
  Property names surface lowercased in the JSON schema (path, line, ...). }

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts: attributes live in the interface
  Lsp.Attributes,  // [RutaDelServidor]: que parametro es una ruta NUESTRA
  Lsp.Client,
  Lsp.Session;

type
  { El "path" de las tools de POSICION. Llevaba la descripcion de
    delphi_symbols porque symbols heredaba de esta misma clase, asi que las
    SEIS anunciaban que aceptan una CARPETA y ninguna la acepta. Compartir la
    clase base hizo compartir una descripcion que solo era verdad en una de
    ellas; por eso symbols ya no hereda de aqui: su "path" es OTRO parametro,
    acepta fichero o carpeta, y decirlo una vez para las siete era decirlo mal
    en seis. }
  TDelphiFileParams = class
  private
    FPath: string;
  public
    [SchemaDescription(SP_LSP_FILE_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
  end;

  TDelphiSymbolsParams = class
  private
    FPath: string;
    FMode: string;
    FFilter: string;
  public
    [SchemaDescription(SP_SYMBOLS_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_SYMBOLS_MODE)]
    property Mode: string read FMode write FMode;
    [SchemaDescription(SP_SYMBOLS_FILTER)]
    property Filter: string read FFilter write FFilter;
  end;

  TDelphiPositionParams = class(TDelphiFileParams)
  private
    FLine: Integer;
    FCharacter: Integer;
  public
    [SchemaDescription(SP_LSP_LINE)]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription(SP_LSP_CHARACTER)]
    [Required]
    property Character: Integer read FCharacter write FCharacter;
  end;

  TDelphiCompletionParams = class(TDelphiPositionParams)
  private
    FTrigger: string;
  public
    [SchemaDescription(SP_LSP_TRIGGER)]
    property Trigger: string read FTrigger write FTrigger;
  end;

  TDelphiDefinitionParams = class(TDelphiPositionParams)
  private
    FKind: string;
  public
    [SchemaDescription(SP_LSP_KIND)]
    property Kind: string read FKind write FKind;
  end;

  TDelphiSymbolsTool = class(TMCPToolBase<TDelphiSymbolsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiSymbolsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiDefinitionTool = class(TMCPToolBase<TDelphiDefinitionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDefinitionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiSignatureTool = class(TMCPToolBase<TDelphiPositionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPositionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiHoverTool = class(TMCPToolBase<TDelphiPositionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPositionParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiCompletionTool = class(TMCPToolBase<TDelphiCompletionParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiCompletionParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Math,
  System.RegularExpressions,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Defaults,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.References,
  Lsp.Listas, // AgrupaPorCarpeta: las unidades de una carpeta, por carpeta
  Lsp.Patch,
  Lsp.NetDrives,
  Lsp.Pascal,
  Lsp.PascalDecl, // EL lector de clases: de quien es cada declaracion
  Lsp.Mascara;

const
  MAX_COMPLETION_ITEMS = 50;

type
  TLoc = record
    Uri: string;
    Line, Ch: Integer;
  end;

{ Pulls the first Location (or LocationLink) out of a textDocument/* result,
  which DelphiLSP returns either as a single object OR as a one-item array
  (measured: definition answers a bare object). False = nothing usable. }
function ParseLoc(AResult: TJSONValue; out ALoc: TLoc): Boolean;
var
  Obj, Rng, St: TJSONValue;
begin
  ALoc.Uri := '';
  ALoc.Line := -1;
  ALoc.Ch := 0;
  Result := False;
  Obj := AResult;
  if Obj is TJSONArray then
  begin
    if TJSONArray(Obj).Count = 0 then
      Exit;
    Obj := TJSONArray(Obj).Items[0];
  end;
  if not (Obj is TJSONObject) then
    Exit;
  if not TJSONObject(Obj).TryGetValue<string>('uri', ALoc.Uri) then
    TJSONObject(Obj).TryGetValue<string>('targetUri', ALoc.Uri);
  Rng := TJSONObject(Obj).GetValue('range');
  if Rng = nil then
    Rng := TJSONObject(Obj).GetValue('targetSelectionRange');
  if Rng = nil then
    Rng := TJSONObject(Obj).GetValue('targetRange');
  if Rng is TJSONObject then
  begin
    St := TJSONObject(Rng).GetValue('start');
    if St is TJSONObject then
    begin
      TJSONObject(St).TryGetValue<Integer>('line', ALoc.Line);
      TJSONObject(St).TryGetValue<Integer>('character', ALoc.Ch);
    end;
  end;
  Result := (ALoc.Uri <> '') and (ALoc.Line >= 0);
end;

{ 0-based column of the routine name on a header line ("procedure
  TClass.Name(...)" -> the column of Name). DelphiLSP's definition range
  starts at column 0 (the keyword), so to chain a second lookup we must aim
  at the identifier ourselves. Falls back to the first identifier. }
function RoutineIdentCol(const APath: string; ALine: Integer): Integer;
var
  Enc, L: string;
  Lines: TArray<string>;
  M: TMatch;
begin
  Result := 0;
  try
    L := PatchLoadText(APath, Enc);
  except
    Exit;
  end;
  // las del LSP (CR, LF y CRLF son saltos), en el CODIGO: con '{ x }
  // procedure TFoo.Bar;' la columna caia dentro del comentario (revision de
  // la 1.10.0); la vista guarda las columnas
  Lines := LineasDelTexto(CodigoPascal(L));
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  L := Lines[ALine];
  // los nombres, con EL identificador (Lsp.Pascal): con [A-Za-z_]\w* la
  // columna de un nombre con enye caia en su primer trozo
  M := TRegEx.Match(L, '^\s*(?:' + PatronPalabraDeRutina + '|property)\s+(?:' + PATRON_IDENT +
    '\.)*(' + PATRON_IDENT + ')', [roIgnoreCase]);
  if M.Success then
    Result := M.Groups[1].Index - 1 // TMatch is 1-based; LSP columns 0-based
  else
  begin
    M := TRegEx.Match(L, PATRON_IDENT);
    if M.Success then
      Result := M.Groups[0].Index - 1;
  end;
end;

{ Shared helpers }

function NoSettingsNote(const ASettings: string): string;
begin
  if ASettings = '' then
    Result := MsgText(SN_LSP_NO_SETTINGS_WARNING)
  else
    Result := '';
end;

{ Every object carrying a "uri" also gets the path in the format the rest of
  this server speaks, and the 1-based line next to the LSP 0-based one.
  Field 2026-08-25: definition was the ONE tool answering
  file:///srvd%3A/... with forward slashes, so an agent had to un-escape and
  re-slash by hand before it could chain the next call; and hover printed
  1-based lines while definition printed 0-based ones, in the same session. }
procedure DecorateLocations(V: TJSONValue);
var
  Obj: TJSONObject;
  Pair: TJSONPair;
  Item: TJSONValue;
  Rng, Start: TJSONObject;
  L: TJSONValue;
begin
  if V is TJSONArray then
  begin
    for Item in TJSONArray(V) do
      DecorateLocations(Item);
    Exit;
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  if (Obj.GetValue('uri') <> nil) and (Obj.GetValue('path') = nil) then
  begin
    Obj.AddPair('path', TLspClient.UriToPath(Obj.GetValue('uri').Value));
    Rng := Obj.GetValue('range') as TJSONObject;
    if Rng <> nil then
    begin
      Start := Rng.GetValue('start') as TJSONObject;
      if Start <> nil then
      begin
        L := Start.GetValue('line');
        // 'line', la 1-based de toda la casa (era 'line1': las tools del
        // motor y las de ficheros contaban con nombres distintos, 1.15.0)
        if L <> nil then
        begin
          Obj.AddPair('line', TJSONNumber.Create(L.GetValue<Integer> + 1));
          // ...y las 0-based que toman las tools del motor, con el nombre de
          // los aciertos de search/references: se encadena sin hacer cuentas
          // (revisor de contrato de la 1.15.0)
          Obj.AddPair('line0', TJSONNumber.Create(L.GetValue<Integer>));
          var C := Start.GetValue('character');
          if C <> nil then
            Obj.AddPair('character0', TJSONNumber.Create(C.GetValue<Integer>));
        end;
      end;
    end;
    // ...y el uri se va: es la MISMA ruta (file:///srvd%3A/...), que ninguna
    // tool acepta como argumento; iba dos veces en cada ubicacion (1.15.0)
    Obj.RemovePair('uri').Free;
  end;
  for Pair in Obj do
    DecorateLocations(Pair.JsonValue);
end;

const
  // los campos de una respuesta del motor que son TEXTO del fuente (la firma de
  // signature, las etiquetas de completion, el markdown de hover): van tal
  // cual (Lsp.Mascara.EnmascaraJsonSalvo), y una constante con una ruta salia
  // con la letra virtual; uri, path y lo demas, enmascarados
  CONTENIDO_DEL_MOTOR: array [0 .. 8] of string = ('label', 'detail',
    'documentation', 'value', 'insertText', 'filterText', 'sortText', 'newText',
    'name');
  // ...y los de symbols: la declaracion leida del fuente, sus etiquetas del
  // resumen y los uses del digest
  CONTENIDO_DE_SYMBOLS: array [0 .. 5] of string = ('decl', 'name', 'detail',
    'ident', 'symbols', 'uses');

{ Extracts "result" from a full JSON-RPC response and renders it, adding a
  filesystem path next to any "uri" for agent convenience. Frees AResp. }
function RenderResult(AResp: TJSONObject; const ANote: string): string;
var
  V: TJSONValue;
  Err: TJSONValue;
begin
  try
    Err := AResp.GetValue('error');
    if Err <> nil then
      Exit(MsgFmt(SR_LSP_ERROR_FMT, [Err.ToJSON]) + ANote);
    V := AResp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit(MsgText(SN_LSP_NULL_NOTE) + ANote);
    DecorateLocations(V);
    Result := EnmascaraJsonSalvo(V.ToJSON, CONTENIDO_DEL_MOTOR, ANote);
  finally
    AResp.Free;
  end;
end;

const
  // LSP SymbolKind 1..26, as short lower-case labels
  SYMBOL_KIND_NAMES: array[1..26] of string = (
    'file', 'module', 'namespace', 'package', 'class', 'method', 'property',
    'field', 'constructor', 'enum', 'interface', 'function', 'variable',
    'constant', 'string', 'number', 'boolean', 'array', 'object', 'key',
    'null', 'enum-member', 'struct', 'event', 'operator', 'type-param');

function SymKindName(const ANode: TJSONObject): string;
var
  K: Integer;
begin
  K := ANode.GetValue<Integer>('kind', 0);
  if (K >= Low(SYMBOL_KIND_NAMES)) and (K <= High(SYMBOL_KIND_NAMES)) then
    Result := SYMBOL_KIND_NAMES[K]
  else
    Result := 'symbol';
end;

{ La declaracion REAL, leida del FUENTE, que empieza en la linea 0-based
  ADesde; AHasta devuelve la ultima linea usada. Une las lineas siguientes
  mientras la sentencia no ha terminado -un ';' con todos los parentesis
  cerrados-, porque una firma partida en varias lineas no dice nada leida a
  medias.

  Por que vive suelta y no dentro del digest de carpeta, que es donde nacio:
  la necesitan DOS caminos. El digest lee el fuente y acierta; el camino de UN
  fichero se fiaba del "name" que da DelphiLSP, que NO es un nombre sino una
  FIRMA RENDERIZADA, y pierde cosas. Medido el 2026-09-20 con una unidad
  sonda:

    fuente:   function Alta(const A: string; B: Integer = 0): Boolean;
    DelphiLSP: Alta(const A: string; B: Integer): Boolean
    fuente:   FBuffer: array [0 .. 7] of Byte;
    DelphiLSP: FBuffer: Byte

  Un parametro opcional pasa por obligatorio y un array desaparece. Un agente
  que respeta esa firma escribe una llamada que no compila, y lo peor que
  puede hacer una tool de lectura es contestar algo FALSO con seguridad. El
  arbol, los kinds y las lineas siguen siendo del LSP: lo unico que se deja de
  creer es su forma de escribir una declaracion. }
function StatementAt(const ALines, AVista: TArray<string>; AUnidad: TUnidadPas;
  ADesde: Integer; out AHasta: Integer): string;

  // Cuantos '(' quedan abiertos en AText (la vista: sin comentarios), fuera
  // de sus cadenas: el '(' de una cadena no abre nada
  function Unbalanced(const AText: string): Integer;
  var
    I, N: Integer;
  begin
    Result := 0;
    I := 1;
    while I <= Length(AText) do
    begin
      N := QuoteLen(AText, I);
      if N > 0 then
      begin
        Inc(I, N);
        Continue;
      end;
      if AText[I] = '(' then
        Inc(Result)
      else if AText[I] = ')' then
        Dec(Result);
      Inc(I);
    end;
    if Result < 0 then
      Result := 0;
  end;

var
  K, J: Integer;
  Vista: string;
  Ventana: TArray<string>;      // las lineas que se pueden unir, desde ADesde
  Clases: TArray<TClasePascal>; // las de la ventana unida con #10
  Ini: TArray<Integer>;         // donde empieza cada linea de la ventana
  Incluida: TArray<Boolean>;
  Partes: TArray<Integer>;      // las lineas que van, en orden

  // la linea J de la ventana empieza dentro de un comentario (o de una cadena
  // de varias lineas) que viene de la de antes
  function EmpiezaDentro(AJ: Integer): Boolean;
  begin
    Result := (AJ > 0) and (Clases[Ini[AJ] - 1] <> cpCodigo);
  end;

  // lo que se une de la linea J: el fuente, sin el resto de un comentario
  // que no va (el de una linea saltada) y sin su // si detras va otra (unido
  // en una linea, el // comentaba lo que siguiera: medido en la revision de
  // la 1.10.0, 'function Baz(X: Integer; // la x Y: Integer)...')
  function Pieza(AJ: Integer; AUltima: Boolean): string;
  var
    Desde, Hasta: Integer;
  begin
    Desde := 1;
    Hasta := Length(Ventana[AJ]);
    if EmpiezaDentro(AJ) and not Incluida[AJ - 1] then
      while (Desde <= Hasta) and (Clases[Ini[AJ] + Desde - 1] <> cpCodigo) do
        Inc(Desde);
    if not AUltima then
      for var C := Desde to Hasta do
        if Clases[Ini[AJ] + C - 1] = cpLinea then
        begin
          Hasta := C - 1;
          Break;
        end;
    Result := Copy(Ventana[AJ], Desde, Hasta - Desde + 1).Trim;
  end;

begin
  AHasta := ADesde;
  if (ADesde < 0) or (ADesde > High(ALines)) then
    Exit('');
  // las lineas que la union puede tocar (ADesde y ocho mas), leidas por EL
  // lexico con el estado que traen: que linea sigue dentro de un comentario
  Ventana := Copy(ALines, ADesde, Min(High(ALines), ADesde + 8) - ADesde + 1);
  Clases := ClasesPascal(string.Join(#10, Ventana));
  SetLength(Ini, Length(Ventana));
  SetLength(Incluida, Length(Ventana));
  Ini[0] := 1;
  for J := 1 to High(Ventana) do
    Ini[J] := Ini[J - 1] + Length(Ventana[J - 1]) + 1;
  Incluida[0] := True;
  Partes := [0];
  // lo que se DEVUELVE es el fuente tal cual (ALines); lo que DECIDE es su
  // vista sin comentarios (AVista: BlankComments, alineada con ALines). Un
  // '// la nota' detras de una firma la dejaba sin su ';' final y se pegaba
  // la declaracion de la linea siguiente, que desaparecia del digest
  // (medido con la sonda del lexico, 2-oct-2026)
  Result := ALines[ADesde].Trim;
  Vista := AVista[ADesde].Trim;
  K := ADesde;
  // Una cabecera de class/record/interface ABRE un bloque; no es una
  // sentencia a medias, y unirle lo que viene detras pegaba el primer campo
  // a la linea de la clase. Cual lo es lo dice EL lector de clases: con una
  // regex, la de un generico (TFoo<T: class> = class) no lo era y se pegaba
  // (revision de la 1.13.0, medido en vendor\src\Resources)
  var Tipo := AUnidad.TipoQueEmpiezaEn(ADesde);
  if (Tipo <> nil) and (Tipo.Clase in [ctClase, ctRegistro, ctInterfaz, ctAyudante]) and
     not Tipo.SinCuerpo and not Vista.EndsWith(';') then
    Exit;
  // Un ';' DENTRO de la lista de parametros es un separador, no el final de
  // nada: "function Alta(const A, B: string; C: Integer;" parece terminada y
  // no lo esta, asi que se perdian el tipo de retorno y el valor por defecto.
  while (K < High(ALines)) and (K - ADesde < 8) and
        (not Vista.EndsWith(';') or (Unbalanced(Vista) > 0)) and
        not Vista.EndsWith('=') do
  begin
    Inc(K);
    if ALines[K].Trim = '' then
      Break;
    // Una linea que es SOLO comentario o directiva se salta al unir: una
    // property partida en tres con una nota en medio volvia como
    // "property Cosa: string read FCosa { la nota } write FCosa;". No es
    // falso, pero es ruido dentro de lo unico que el lector va a copiar.
    // Solo la linea ENTERA (la que en la vista queda en blanco): los
    // comentarios de dentro se quedan, que lo que se devuelve es el fuente.
    // Y la que CIERRA un comentario abierto en una linea que si va, va: se
    // saltaba, y 'function Tres(A: Integer { the a' salia sin su cierre
    // (revision de la 1.10.0, medido)
    J := K - ADesde;
    Incluida[J] := (AVista[K].Trim <> '') or (EmpiezaDentro(J) and Incluida[J - 1]);
    if not Incluida[J] then
      Continue;
    Partes := Partes + [J];
    Vista := Vista + ' ' + AVista[K].Trim;
  end;
  AHasta := K;
  Result := '';
  for J := 0 to High(Partes) do
    Result := Result + IfThen(J > 0, ' ', '') + Pieza(Partes[J], J = High(Partes));
end;

{ El identificador, sacado del "name" del LSP: lo que hay antes del primer
  '(' o ':'. Filtrar sobre el nombre entero era filtrar sobre una firma
  renderizada - filter="string" casaba con todo lo que DEVUELVE un string, en
  una tool cuyo parametro se llama "busca por nombre". }
function IdentOf(const AName: string): string;
var
  I: Integer;
begin
  Result := AName.Trim;
  I := Result.IndexOfAny(['(', ':']);
  if I >= 0 then
    Result := Result.Substring(0, I).Trim;
end;

function SymChildren(const ANode: TJSONObject): TJSONArray;
var
  C: TJSONValue;
begin
  C := ANode.GetValue('children');
  if C is TJSONArray then
    Result := TJSONArray(C)
  else
    Result := nil;
end;

{ La linea del simbolo EN BASE 1, que es como cuenta delphi_read y como
  cuenta el campo "line" de delphi_search. El motor LSP las da en base 0 y
  este digest las publicaba tal cual en modo FICHERO ("@30" para la linea 31)
  mientras el modo CARPETA publicaba base 1 - misma tool, mismo nombre de
  campo, dos convenios, y nada que lo dijera. Un agente que llevara una linea
  del digest a delphi_read o a un ancla caia una linea desplazada (medido
  2026-09-20). Se unifican en base 1 y el 0 viaja aparte en "line0", que es
  el convenio que ya usa delphi_search para las tools de LSP. }
function SymLine(const ANode: TJSONObject): Integer;
var
  R, S: TJSONValue;
begin
  Result := -1;
  R := ANode.GetValue('selectionRange');
  if R = nil then
    R := ANode.GetValue('range');
  if R is TJSONObject then
  begin
    S := TJSONObject(R).GetValue('start');
    if S is TJSONObject then
      Result := TJSONObject(S).GetValue<Integer>('line', -1);
  end;
end;

function SymLine1(const ANode: TJSONObject): Integer;
begin
  Result := SymLine(ANode);
  if Result >= 0 then
    Inc(Result);
end;

function SymCountDeep(const AArr: TJSONArray): Integer;
var
  V: TJSONValue;
begin
  Result := 0;
  if AArr = nil then
    Exit;
  for V in AArr do
    if V is TJSONObject then
      Result := Result + 1 + SymCountDeep(SymChildren(TJSONObject(V)));
end;

{ 'function PathDenied(const APath: string): string @40', containers add
  ' (+N inside)', a uses clause collapses to 'uses (12 units) @1'. }
function SymLabel(const ANode: TJSONObject): string;
var
  Ch: TJSONArray;
  Nm: string;
begin
  Nm := ANode.GetValue<string>('name', '?');
  Ch := SymChildren(ANode);
  if SameText(Nm, 'uses') and (Ch <> nil) then
    Exit(Format('uses (%d units) @%d', [Ch.Count, SymLine1(ANode)]));
  // La declaracion del FUENTE manda sobre la firma renderizada del LSP, y
  // ademas ya dice ella sola si es function, procedure o property: poner
  // delante la palabra del kind sobraba, y encima mentia - DelphiLSP marca
  // como "method" una rutina GLOBAL, porque para el kind 6 es cualquier
  // rutina. Cuando no hay declaracion legible se vuelve a lo de antes.
  var Decl := ANode.GetValue<string>('decl', '');
  if Decl <> '' then
  begin
    // El resumen existe para ser BARATO: decir la verdad cuesta (una firma
    // real es mas larga que la que renderiza el LSP, que se come la mitad),
    // y eso esta bien pagado, pero sin tope una firma monstruosa se lleva el
    // ahorro por delante. El ';' final tampoco aporta nada aqui. Quien
    // necesite la firma COMPLETA tiene filter="nombre" y mode="full", que es
    // exactamente para lo que estan.
    if Decl.EndsWith(';') then
      Decl := Decl.Substring(0, Decl.Length - 1);
    if Decl.Length > 110 then
      Decl := Decl.Substring(0, 110) + '...';
    Result := Format('%s @%d', [Decl, SymLine1(ANode)]);
  end
  else
    Result := Format('%s %s @%d', [SymKindName(ANode), Nm, SymLine1(ANode)]);
  if (Ch <> nil) and (Ch.Count > 0) then
    Result := Result + MsgFmt(SF_SYMBOLS_DENTRO_FMT, [Ch.Count]);
end;

{ Le pone a cada simbolo del arbol su declaracion REAL y su identificador
  limpio, en UNA pasada de la que comen los tres modos (full, summary y
  filter). Si cada modo lo sacase por su cuenta acabarian diciendo cosas
  distintas del mismo simbolo, que es como nacieron los gemelos de este mes.

  Solo los kinds que SON una declaracion: en la clausula uses cada unit es un
  simbolo de kind "file" y unir desde su linea se tragaria la clausula entera. }
procedure DecorateSymbolDecls(V: TJSONValue; const ALines, AVista: TArray<string>;
  AUnidad: TUnidadPas);
const
  DECLARAN = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 22, 23];
var
  Obj: TJSONObject;
  Item: TJSONValue;
  Ln, Fin: Integer;
  Nm, Decl: string;
begin
  if V is TJSONArray then
  begin
    for Item in TJSONArray(V) do
      DecorateSymbolDecls(Item, ALines, AVista, AUnidad);
    Exit;
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  Nm := Obj.GetValue<string>('name', '');
  if (Nm <> '') and (Obj.GetValue('range') <> nil) then
  begin
    if Obj.GetValue('ident') = nil then
      Obj.AddPair('ident', IdentOf(Nm));
    Ln := SymLine(Obj);
    if (Obj.GetValue<Integer>('kind', 0) in DECLARAN) and (Ln >= 0) and
       (Obj.GetValue('decl') = nil) then
    begin
      Decl := StatementAt(ALines, AVista, AUnidad, Ln, Fin);
      if Decl <> '' then
        Obj.AddPair('decl', Decl);
    end;
  end;
  DecorateSymbolDecls(SymChildren(Obj), ALines, AVista, AUnidad);
end;

{ El arbol de un fichero tal como sale (mode=full, o el automatico de uno
  pequeno): lo que el motor repite sin decir nada se quita - el
  selectionRange igual al range (DelphiLSP los da iguales; SymLine cae al
  range), los children vacios y el detail vacio (revisor de tokens,
  4-oct-2026: casi la mitad del arbol). }
procedure AdelgazaArbol(V: TJSONValue);
var
  Obj: TJSONObject;
  C: TJSONArray;
begin
  if V is TJSONArray then
  begin
    for var Item in TJSONArray(V) do
      AdelgazaArbol(Item);
    Exit;
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  if (Obj.GetValue('selectionRange') <> nil) and (Obj.GetValue('range') <> nil) and
     (Obj.GetValue('selectionRange').ToJSON = Obj.GetValue('range').ToJSON) then
    Obj.RemovePair('selectionRange').Free;
  C := SymChildren(Obj);
  if (C <> nil) and (C.Count = 0) then
    Obj.RemovePair('children').Free
  else if C <> nil then
    AdelgazaArbol(C);
  if (Obj.GetValue('detail') <> nil) and (Obj.GetValue<string>('detail', '') = '') then
    Obj.RemovePair('detail').Free;
end;

{ The compact skeleton: each top-level section with its direct members as
  one-line labels; grandchildren stay as counts. }
function SummaryOfSymbols(const AArr: TJSONArray; AFullLen: Integer;
  AAuto: Boolean): string;
var
  Ret, SecObj: TJSONObject;
  Sections, Syms: TJSONArray;
  V, CV: TJSONValue;
  N: TJSONObject;
begin
  Ret := TJSONObject.Create;
  try
    Ret.AddPair('mode', 'summary');
    Sections := TJSONArray.Create;
    Ret.AddPair('sections', Sections);
    // Un .dpr no tiene secciones: DelphiLSP devuelve el arbol PLANO, cada
    // rutina en la raiz y sin hijos. Tratar la raiz como "secciones" sacaba
    // trece secciones con "symbols": [] - que se lee como "esta rutina no
    // tiene nada dentro", justo lo contrario de la verdad (medido el
    // 2026-09-20 sobre DelphiLspMcp.dpr). Lo que no tiene hijos no es una
    // seccion: es un simbolo de primer nivel.
    var Sueltos := TJSONArray.Create;
    Ret.AddPair('symbols', Sueltos);
    for V in AArr do
    begin
      if not (V is TJSONObject) then
        Continue;
      N := TJSONObject(V);
      if (SymChildren(N) = nil) or (SymChildren(N).Count = 0) then
      begin
        Sueltos.Add(SymLabel(N));
        Continue;
      end;
      SecObj := TJSONObject.Create;
      Sections.AddElement(SecObj);
      SecObj.AddPair('section', N.GetValue<string>('name', '?'));
      SecObj.AddPair('line', TJSONNumber.Create(SymLine1(N)));
      SecObj.AddPair('line0', TJSONNumber.Create(SymLine(N)));
      Syms := TJSONArray.Create;
      SecObj.AddPair('symbols', Syms);
      if SymChildren(N) <> nil then
        for CV in SymChildren(N) do
          if CV is TJSONObject then
            Syms.Add(SymLabel(TJSONObject(CV)));
    end;
    if Sections.Count = 0 then
      Ret.RemovePair('sections').Free;
    if Sueltos.Count = 0 then
      Ret.RemovePair('symbols').Free;
    Ret.AddPair('totalSymbols', TJSONNumber.Create(SymCountDeep(AArr)));
    if AAuto then
      Ret.AddPair('autoNote', MsgFmt(SN_SYMBOLS_AUTO_FMT, [AFullLen]));
    Ret.AddPair('note', MsgText(SN_SYMBOLS_SUMMARY_NOTE));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ Name search inside the tree: only what matches, with kind, line and the
  container it lives in. AFilter arrives lower-case. }
function FilterSymbols(const AArr: TJSONArray; const AFilter: string): string;
var
  Ret: TJSONObject;
  Hits: TJSONArray;
  Total: Integer;

  procedure Walk(const Arr: TJSONArray; const APath: string);
  var
    V: TJSONValue;
    N, H: TJSONObject;
    Nm, Sub: string;
    Ch: TJSONArray;
  begin
    if Arr = nil then
      Exit;
    for V in Arr do
    begin
      if not (V is TJSONObject) then
        Continue;
      N := TJSONObject(V);
      Nm := N.GetValue<string>('name', '');
      Ch := SymChildren(N);
      // Se busca por NOMBRE, que es lo que promete el parametro. Antes se
      // buscaba dentro del "name" del LSP, que es una FIRMA renderizada: con
      // filter="string" casaba todo lo que devuelve un string o recibe uno.
      var Id := N.GetValue<string>('ident', '');
      if Id = '' then
        Id := IdentOf(Nm);
      if Id.ToLower.Contains(AFilter) then
      begin
        Inc(Total);
        if Hits.Count < 100 then
        begin
          H := TJSONObject.Create;
          Hits.AddElement(H);
          H.AddPair('name', Id);
          // Y la declaracion, tal y como esta escrita en el fuente.
          var D := N.GetValue<string>('decl', '');
          if D = '' then
            D := Nm;
          H.AddPair('decl', D);
          H.AddPair('kind', SymKindName(N));
          H.AddPair('line', TJSONNumber.Create(SymLine1(N)));
          H.AddPair('line0', TJSONNumber.Create(SymLine(N)));
          if APath <> '' then
            H.AddPair('in', APath);
          if (Ch <> nil) and (Ch.Count > 0) then
            H.AddPair('members', TJSONNumber.Create(Ch.Count));
        end;
      end;
      if APath = '' then
        Sub := Id
      else
        Sub := APath + ' > ' + Id;
      Walk(Ch, Sub);
    end;
  end;

begin
  Total := 0;
  Ret := TJSONObject.Create;
  try
    Hits := TJSONArray.Create;
    Ret.AddPair('filter', AFilter);
    Ret.AddPair('matches', Hits);
    Walk(AArr, '');
    Ret.AddPair('total', TJSONNumber.Create(Total));
    if Total > Hits.Count then
      Ret.AddPair('truncated', TJSONBool.Create(True));
    if Total = 0 then
      Ret.AddPair('note', MsgText(SN_SYMBOLS_FILTER_NONE));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ TDelphiSymbolsTool }

constructor TDelphiSymbolsTool.Create;
begin
  inherited;
  FName := 'delphi_symbols';
  FDescription := SD_LSP_SYMBOLS;
end;

// PositionOutOfRange vivia AQUI, en la implementation, o sea invisible para
// las otras unidades - y por eso cuatro tools validaban la posicion y dos no.
// Se mudo a Lsp.Patch, que es donde ya miran todas. Ver alli el porque.

{ Whether this is a file DelphiLSP can say anything about at all. Answering
  `[]` for a .txt reads as "this unit has no symbols" (measured 2026-08-25). }
function NotDelphiSource(const APath: string): string;
begin
  // la guarda PRIMERO: sin ruta decia "() no es un fuente Delphi"; ahora
  // GUARD-018 (falta la ruta), y fuera de la jaula su negativa de siempre
  Result := ReadPathDenied(APath);
  if Result <> '' then
    Exit;
  // la regla de las siete (Lsp.Patch): carpeta, no esta, no es Pascal
  Result := NoEsFuenteDelphi(APath);
end;

{ What a unit OFFERS, from its interface section alone: the declarations a
  caller can use, without a single body. Read as text, no language server
  involved - it has to stay cheap enough to run over a whole folder.

  Why: orienting yourself in somebody else's code cost one delphi_read per
  file, and 90% of what you need is in the interface sections (measured
  2026-08-25, a maintenance job on another agent's project: 12 calls to get
  the picture, 7 of them reads). }
function InterfaceDigest(const APath: string): TJSONObject;
var
  Text, Enc, L, Cur: string;
  Lines, Vista: TArray<string>;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, J, Kept: Integer;
  U: TUnidadPas;
  Dueno: TTipoPas;

  // Una declaracion puede ocupar varias lineas y quien lee la necesita
  // ENTERA. El como vive ahora en StatementAt, ahi arriba, porque el camino
  // de UN fichero tambien lo necesita: el digest de carpeta acertaba con las
  // firmas y el otro camino las daba mal, leyendo lo MISMO de sitios
  // distintos (medido 2026-09-20).
  function WholeStatement(var AIdx: Integer): string;
  var
    Fin: Integer;
  begin
    Result := StatementAt(Lines, Vista, U, AIdx, Fin);
    AIdx := Fin;
  end;

begin
  Result := TJSONObject.Create;
  Result.AddPair('unit', TPath.GetFileNameWithoutExtension(APath));
  Result.AddPair('path', APath);
  try
    Text := PatchLoadText(APath, Enc);
  except
    Result.AddPair('error', MsgText(SN_LSP_NO_SE_PUEDE_LEER));
    Exit;
  end;
  Lines := LineasDelTexto(Text); // las del LSP: CR, LF y CRLF son saltos
  // la estructura (interface, uses, la clase, su end;, cada declaracion) se
  // lee en la vista sin comentarios, alineada con Lines: un 'procedure
  // Vieja;' dentro de un comentario de llave salia como declaracion (medido
  // con la sonda del lexico, 2-oct-2026)
  Vista := LineasDelTexto(BlankComments(Text));
  // de quien es cada declaracion: EL lector de clases (Lsp.PascalDecl), con
  // la linea donde empieza y acaba cada tipo. Aqui se abria con una regex y
  // se cerraba en el primer 'end;': un record anidado cerraba la clase y lo
  // de detras quedaba sin dueno (censo del 4-oct-2026)
  try
    U := LeeFuentePascal(Text);
  except
    Result.Free;
    raise;
  end;
  try
  Arr := TJSONArray.Create;
  Result.AddPair('declares', Arr);
  Cur := '';
  Kept := 0;
  I := 0;
  while I <= High(Lines) do
  begin
    L := Vista[I].Trim;
    if TRegEx.IsMatch(L, '(?i)^interface[ ]*$') then
    begin
      Cur := 'interface';
      Inc(I);
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^implementation[ ]*$') then
      Break;
    if Cur <> 'interface' then
    begin
      Inc(I);
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^uses\b') then
    begin
      J := I;
      Result.AddPair('uses', WholeStatement(J).Substring(4).Replace(';', '').Trim);
      I := J + 1;
      Continue;
    end;
    if TRegEx.IsMatch(L, '(?i)^(type|const|var|resourcestring)[ ]*$') then
    begin
      Inc(I);
      Continue;
    end;
    // which type we are inside: a flat list left the reader guessing which
    // member belonged to which class, and hid the private fields entirely -
    // one of them being the subject of a refactor. (La linea del nombre de un
    // tipo es de donde se declara; un helper es un tipo con bloque tambien)
    Dueno := U.TipoEnLinea(I, [ctClase, ctRegistro, ctInterfaz, ctAyudante, ctOtro], True);
    J := I;
    // la cabecera de un tipo, del lector: la de un generico (TFoo<T: class,
    // constructor> = class) no casaba con las regex y no salia
    if (U.TipoQueEmpiezaEn(I) <> nil) or
       TRegEx.IsMatch(L, '(?i)^(class[ ]+)?(?:' + PatronPalabraDeRutina + '|property)\b') or
       TRegEx.IsMatch(L, '^' + PATRON_IDENT + '[ ]*=[ ]*(class|record|interface|packed|\()') or
       TRegEx.IsMatch(L, '(?i)^' + PATRON_IDENT + '[ ]*=[ ]*') or
       ((Dueno <> nil) and TRegEx.IsMatch(L, '^' + PATRON_IDENT + '[ ]*:[ ]*' + PATRON_IDENT)) then
    begin
      Inc(Kept);
      if Arr.Count < 300 then
      begin
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('decl', WholeStatement(J));
        if Dueno <> nil then
          Obj.AddPair('of', Dueno.NombreCompleto);
        Obj.AddPair('line', TJSONNumber.Create(I + 1));
        Obj.AddPair('line0', TJSONNumber.Create(I));
      end
      else
        J := I;
    end;
    if J > I then
      I := J;
    Inc(I);
  end;
  Result.AddPair('total', TJSONNumber.Create(Kept));
  if Kept > Arr.Count then
    Result.AddPair('truncated', TJSONBool.Create(True));
  finally
    U.Free;
  end;
end;

const
  // el resumen de una carpeta, por TAMANO (~6K tokens) y no por numero de
  // unidades: con 60 unidades src\Server daba 40K (revisor de tokens,
  // 4-oct-2026); lo que no entra se NOMBRA, hasta tantos nombres
  TOPE_DIGEST_CARPETA = 24000;
  MAX_NOMBRES_FUERA = 200;

function TDelphiSymbolsTool.ExecuteWithParams(const Params: TDelphiSymbolsParams): string;
var
  Client: TLspClient;
  Settings, Folder: string;
begin
  // A FOLDER means "what is in here", answered from the interface sections of
  // every unit at once: the question somebody arriving at unfamiliar code
  // actually has, and it used to cost one call per file.
  // "...\dev4\" is the same folder as "...\dev4": answering "no es un fuente
  // Delphi ()" - with an empty extension - for a trailing separator cost a
  // call and read as "folders are not supported", which is the opposite of
  // what this now does (field round 12).
  Folder := SinBarraFinal(Params.Path.Trim);
  if TDirectory.Exists(Folder) then
  begin
    Result := ReadPathDenied(Folder);
    if Result <> '' then
      Exit;
    var Ret := TJSONObject.Create;
    try
      var Units := TJSONArray.Create;
      Ret.AddPair('folder', Folder);
      Ret.AddPair('units', Units);
      var Fuera := TJSONArray.Create;
      Ret.AddPair('notShown', Fuera);
      var N := 0;
      var Peso := 0;
      for var F in WalkFiles(Folder, '*.pas') do
      begin
        if SkipIdeArtifacts(F) then
          Continue;
        Inc(N);
        // en orden y hasta el tope (la primera entra siempre); a partir de la
        // primera que no cabe, solo su nombre, relativo a la carpeta
        if Fuera.Count = 0 then
        begin
          var D := InterfaceDigest(F);
          var Largo := D.ToJSON.Length;
          if (Units.Count = 0) or (Peso + Largo <= TOPE_DIGEST_CARPETA) then
          begin
            Units.AddElement(D);
            Inc(Peso, Largo);
            Continue;
          end;
          D.Free;
        end;
        if Fuera.Count < MAX_NOMBRES_FUERA then
          Fuera.Add(Copy(F, Length(IncludeTrailingPathDelimiter(Folder)) + 1, MaxInt));
      end;
      Ret.AddPair('total', TJSONNumber.Create(N));
      if N > Units.Count then
        Ret.AddPair('notShownNote', MsgFmt(SN_SYMBOLS_DIGEST_FUERA_FMT,
          [TOPE_DIGEST_CARPETA, N - Units.Count, Fuera.Count]))
      else
        Ret.RemovePair('notShown').Free;
      Ret.AddPair('note', MsgText(SN_SYMBOLS_DIGEST_NOTE));
      // las unidades por carpeta (el organizador): la ruta de cada una
      // repetia la carpeta (6-oct-2026)
      AgrupaPorCarpeta(Ret, 'units');
      Exit(EnmascaraJsonSalvo(Ret.ToJSON, CONTENIDO_DE_SYMBOLS));
    finally
      Ret.Free;
    end;
  end;
  // The JAIL first, and the same refusal whether the file is there or not.
  // Checking existence first told a caller which Delphi files exist anywhere
  // on the disk: "outside the workspaces" for one that is there, "does not
  // exist" for one that is not - a map of the machine, one call at a time
  // (measured 2026-08-25). delphi_read has always answered the same either
  // way; this now does too.
  Result := ReadPathDenied(Params.Path);
  if Result = '' then
    Result := NotDelphiSource(Params.Path);
  if (Result = '') and not TFile.Exists(Params.Path) then
    Result := MsgFmt(SR_LSP_NO_FILE_FMT, [Params.Path]);
  if Result <> '' then
    Exit;
  var Mode := Params.Mode.Trim.ToLower;
  if (Mode <> '') and (Mode <> 'summary') and (Mode <> 'full') then
    Exit(MsgText(SR_LSP_MODE_DEBE_SER_SUMMARY));
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  var Resp := Client.DocumentSymbols(TLspClient.PathToUri(Params.Path));
  var Note := NoSettingsNote(Settings);
  // The full tree of a real unit measured 37.5k chars (hermes, release audit
  // 2026-08-26): the ranges are the fat, the names are the value. Big trees
  // now answer with the skeleton unless full is asked for by name.
  try
    var Err := Resp.GetValue('error');
    if Err <> nil then
      Exit(MsgFmt(SR_LSP_ERROR_FMT, [Err.ToJSON]) + Note);
    var V := Resp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit(MsgText(SN_LSP_NULL_NOTE) + Note);
    DecorateLocations(V);
    // La VERDAD de cada declaracion, leida del fuente, UNA vez y para los
    // tres modos. DelphiLSP renderiza las firmas perdiendo los valores por
    // defecto y los rangos de los arrays; el arbol, los kinds y las lineas
    // siguen siendo suyos, pero como se escribe una declaracion lo dice el
    // fichero. Si no se puede leer, no se decora nada y todo sigue como
    // antes: esto anade verdad, no la sustituye.
    try
      var EncSim: string;
      var TextoSim := PatchLoadText(Params.Path, EncSim);
      var USim := LeeFuentePascal(TextoSim);
      try
        DecorateSymbolDecls(V, LineasDelTexto(TextoSim), LineasDelTexto(BlankComments(TextoSim)), USim);
      finally
        USim.Free;
      end;
    except
      // un fichero que el LSP si pudo abrir y nosotros no: mejor el arbol
      // pelado que ningun arbol
    end;
    // la declaracion de cada simbolo es TEXTO del fuente: tal cual
    // (EnmascaraJsonSalvo); las rutas, enmascaradas
    if not (V is TJSONArray) then
      Exit(EnmascaraJsonSalvo(V.ToJSON, CONTENIDO_DE_SYMBOLS, Note));
    var Filt := Params.Filter.Trim.ToLower;
    if Filt <> '' then
      Exit(EnmascaraJsonSalvo(FilterSymbols(TJSONArray(V), Filt), CONTENIDO_DE_SYMBOLS, Note));
    AdelgazaArbol(V);
    var Full := V.ToJSON;
    if (Mode = 'full') or ((Mode = '') and (Length(Full) <= 6000)) then
      Exit(EnmascaraJsonSalvo(Full, CONTENIDO_DE_SYMBOLS, Note));
    Result := EnmascaraJsonSalvo(SummaryOfSymbols(TJSONArray(V), Length(Full), Mode = ''),
      CONTENIDO_DE_SYMBOLS, Note);
  finally
    Resp.Free;
  end;
end;

{ TDelphiDefinitionTool }

constructor TDelphiDefinitionTool.Create;
begin
  inherited;
  FName := 'delphi_definition';
  FDescription := SD_LSP_DEFINITION;
end;

function TDelphiDefinitionTool.ExecuteWithParams(const Params: TDelphiDefinitionParams): string;
var
  Client: TLspClient;
  Settings, Kind: string;
  Resp: TJSONObject;
begin
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Kind := Params.Kind.Trim.ToLower;
  if (Kind <> '') and (Kind <> 'definition') and (Kind <> 'declaration') and
     (Kind <> 'implementation') then
    Exit(MsgText(SR_LSP_KIND_DEBE_SER_DEFINITION));
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  if Kind = 'declaration' then
  begin
    // Measured (field rounds 2-3, B5): declaration straight on a CALL SITE
    // answers with the ENCLOSING method's declaration, not the target's, and
    // definition answers a bare Location object with column 0. Chain: run
    // definition (correct at a call site) to reach the body, then declaration
    // AT the body's identifier column to reach the interface declaration.
    var Pending: Boolean;
    var DefResp := Client.DefinitionResolved(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character, Pending);
    var DefLoc: TLoc;
    if ParseLoc(DefResp.GetValue('result'), DefLoc) then
    begin
      var TgtPath := TLspClient.UriToPath(DefLoc.Uri);
      var Col := RoutineIdentCol(TgtPath, DefLoc.Line);
      // al MISMO motor, que es el que ha llevado hasta ahi (Lsp.Session.AbreEn):
      // con AcquireFor, una unidad de la RTL o de otro proyecto arrancaba su
      // propio motor y pisaba Settings con el suyo (una nota LSP-021 falsa).
      // El gemelo del arreglo de references (revision de la 1.13.0)
      TLspSession.Instance.AbreEn(Client, TgtPath);
      var DeclResp := Client.Declaration(DefLoc.Uri, DefLoc.Line, Col);
      var DeclLoc: TLoc;
      if ParseLoc(DeclResp.GetValue('result'), DeclLoc) and
         not ((DeclLoc.Line = DefLoc.Line) and SameText(DeclLoc.Uri, DefLoc.Uri)) then
      begin
        // declaration moved elsewhere = the interface declaration we want
        DefResp.Free;
        Resp := DeclResp;
      end
      else
      begin
        // declaration stayed on the body (or failed): return the body - far
        // more useful than the enclosing-scope answer of a direct call
        DeclResp.Free;
        Resp := DefResp;
      end;
    end
    else if Pending then
    begin
      // hover knows the symbol, definition is not indexed yet: say "not yet",
      // never the enclosing routine (measured by Hermes, 2026-09-22)
      DefResp.Free;
      Exit(MsgText(SR_LSP_WARMING) + NoSettingsNote(Settings));
    end
    else
    begin
      // no definition to chain from: fall back to a direct declaration, and
      // SAY that on a call site this is the enclosing routine's
      DefResp.Free;
      Resp := Client.Declaration(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
      Exit(RenderResult(Resp, MsgText(SN_DEF_DECL_FALLBACK) + NoSettingsNote(Settings)));
    end;
  end
  else if Kind = 'implementation' then
    Resp := Client.Implementation_(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character)
  else
  begin
    var Pending: Boolean;
    Resp := Client.DefinitionResolved(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character, Pending);
    if Pending then
    begin
      Resp.Free;
      Exit(MsgText(SR_LSP_WARMING) + NoSettingsNote(Settings));
    end;
  end;
  Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiSignatureTool }

constructor TDelphiSignatureTool.Create;
begin
  inherited;
  FName := 'delphi_signature';
  FDescription := SD_LSP_SIGNATURE;
end;

function TDelphiSignatureTool.ExecuteWithParams(const Params: TDelphiPositionParams): string;
var
  Client: TLspClient;
  Settings: string;
  Resp: TJSONObject;
  V: TJSONValue;
begin
  // Validar la posicion ANTES de preguntarle al motor, igual que hacen
  // delphi_definition y delphi_hover. Sin esto, line=9999 sobre un fichero de
  // 519 lineas contestaba el hint de "pon el cursor dentro de los parentesis"
  // - un diagnostico FALSO: el problema no era el parentesis, era que la
  // linea no existe. Medido 2026-09-20 por un agente auditor.
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Resp := Client.SignatureHelp(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
  V := Resp.GetValue('result');
  if (V = nil) or (V is TJSONNull) then
    Result := RenderResult(Resp, NoSettingsNote(Settings) +
      MsgText(SN_LSP_HINT_INSIDE_CALL))
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiHoverTool }

constructor TDelphiHoverTool.Create;
begin
  inherited;
  FName := 'delphi_hover';
  FDescription := SD_LSP_HOVER;
end;

function TDelphiHoverTool.ExecuteWithParams(const Params: TDelphiPositionParams): string;
var
  Client: TLspClient;
  Settings: string;
  Resp: TJSONObject;
  V: TJSONValue;
begin
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  Resp := Client.Hover(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
  // Prefer the markdown payload alone: it is what an agent wants to read.
  V := Resp.FindValue('result.contents.value');
  if V <> nil then
  begin
    // la declaracion, entre ```, es TEXTO del fuente: tal cual; el enlace y
    // la nota, enmascarados (Lsp.Mascara.EnmascaraSalvoCodigo)
    Result := EnmascaraSalvoCodigo(V.Value + NoSettingsNote(Settings));
    Resp.Free;
  end
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings) +
      MsgText(SN_LSP_HINT_HOVER_USAGES));
end;

{ TDelphiCompletionTool }

constructor TDelphiCompletionTool.Create;
begin
  inherited;
  FName := 'delphi_completion';
  FDescription := SD_LSP_COMPLETION;
end;

function TDelphiCompletionTool.ExecuteWithParams(const Params: TDelphiCompletionParams): string;
var
  Client: TLspClient;
  Settings, AdjNote: string;
  Resp, Return, ItemObj: TJSONObject;
  Items, OutItems: TJSONArray;
  I, EffChar: Integer;
begin
  // Lo mismo aqui, y era lo mas enganoso de todo: delphi_completion no
  // validaba nada y contestaba ok:true a posiciones imposibles. line=9999
  // sobre un fichero de 519 lineas devolvia dos items (nil, not), y
  // character=-5 devolvia DIECISEIS MIL candidatos - respuestas verosimiles
  // para posiciones que no existen. Un agente que calcula mal una linea (por
  // ejemplo dandole el numero 1-based de delphi_read a una tool 0-based)
  // recibia una lista con pinta de buena en vez del error que le habria
  // dicho donde se equivoco. Medido 2026-09-20 por un agente auditor.
  Result := NotDelphiSource(Params.Path);
  if Result = '' then
    Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);

  // Member completion happens AFTER the dot, and "after ServicioEventos." is
  // the column past the dot, not the last letter of the name. An agent that
  // cannot see the cursor lands a column or two short and gets the whole global
  // scope (5157 symbols) with no hint it aimed at the wrong place - measured
  // 2026-08-25 by a frontier agent dogfooding a real FMX form. When the caller
  // says trigger='.', snap the position to just past the nearest dot and say so.
  EffChar := Params.Character;
  AdjNote := '';
  if Params.Trigger = '.' then
  begin
    var Enc: string;
    var Lines := LineasDelTexto(PatchLoadText(Params.Path, Enc));
    if (Params.Line >= 0) and (Params.Line <= High(Lines)) then
    begin
      var LineTxt := Lines[Params.Line];
      // already just after a dot? (char before the 0-based cursor is '.')
      var AfterDot := (EffChar >= 1) and (EffChar <= Length(LineTxt)) and
        (LineTxt[EffChar] = '.');
      if not AfterDot then
      begin
        var Best := -1;
        for var K := Max(1, EffChar - 3) to Min(Length(LineTxt), EffChar + 2) do
          if (LineTxt[K] = '.') and
             ((Best < 0) or (Abs(K - EffChar) < Abs(Best - EffChar))) then
            Best := K;
        if (Best >= 1) and (Best <> EffChar) then
        begin
          AdjNote := MsgFmt(SN_COMPLETION_SNAPPED_FMT, [Params.Character, Best]);
          EffChar := Best; // 0-based col past the dot = 1-based index of the dot
        end;
      end;
    end;
  end;

  Resp := Client.Completion(TLspClient.PathToUri(Params.Path), Params.Line,
    EffChar, Params.Trigger);
  try
    Items := Resp.FindValue('result.items') as TJSONArray;
    if Items = nil then
      Exit(RenderResult(Resp.Clone as TJSONObject, NoSettingsNote(Settings)));

    // Order by the LSP sortText (then label): DelphiLSP marks the relevant
    // candidates to sort first, and slicing the top 50 in raw order buried them.
    var Order := TList<Integer>.Create;
    try
      for I := 0 to Items.Count - 1 do Order.Add(I);
      Order.Sort(TComparer<Integer>.Construct(
        function(const L, R: Integer): Integer
        var LO, RO: TJSONObject; LS, RS: TJSONValue; LK, RK: string;
        begin
          LO := Items.Items[L] as TJSONObject; RO := Items.Items[R] as TJSONObject;
          LS := LO.GetValue('sortText'); if LS = nil then LS := LO.GetValue('label');
          RS := RO.GetValue('sortText'); if RS = nil then RS := RO.GetValue('label');
          LK := ''; if LS <> nil then LK := LS.Value;
          RK := ''; if RS <> nil then RK := RS.Value;
          Result := CompareStr(LK, RK);
          if Result = 0 then Result := CompareText(
            LO.GetValue('label').Value, RO.GetValue('label').Value);
        end));

    Return := TJSONObject.Create;
    try
      Return.AddPair('total', TJSONNumber.Create(Items.Count));
      if AdjNote <> '' then
        Return.AddPair('positionNote', AdjNote);
      OutItems := TJSONArray.Create;
      Return.AddPair('items', OutItems);
      for I := 0 to Items.Count - 1 do
      begin
        if I >= MAX_COMPLETION_ITEMS then
          Break;
        var Src := Items.Items[Order[I]] as TJSONObject;
        // El motor devuelve el TOKEN que se esta escribiendo como candidato,
        // con tipo "<error>" porque aun no resuelve ({label:'C', kind:6,
        // detail:': <error>;'}): ruido, no un simbolo. Fuera (Hermes,
        // bateria 1.2 caso C.14, 2026-09-23).
        var DetErr := Src.GetValue('detail');
        if (DetErr <> nil) and DetErr.Value.Contains('<error>') then
          Continue;
        ItemObj := TJSONObject.Create;
        OutItems.Add(ItemObj);
        ItemObj.AddPair('label', Src.GetValue('label').Value);
        var Kind := Src.GetValue('kind');
        if Kind <> nil then
          ItemObj.AddPair('kind', Kind.Clone as TJSONValue);
        var Detail := Src.GetValue('detail');
        if (Detail <> nil) and (Detail.Value <> '') then
          ItemObj.AddPair('detail', Detail.Value);
      end;
      Result := EnmascaraJsonSalvo(Return.ToJSON, CONTENIDO_DEL_MOTOR, NoSettingsNote(Settings));
    finally
      Return.Free;
    end;
    finally
      Order.Free;
    end;
  finally
    Resp.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_symbols',
    function: IMCPTool begin Result := TDelphiSymbolsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_definition',
    function: IMCPTool begin Result := TDelphiDefinitionTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_hover',
    function: IMCPTool begin Result := TDelphiHoverTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_completion',
    function: IMCPTool begin Result := TDelphiCompletionTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_signature',
    function: IMCPTool begin Result := TDelphiSignatureTool.Create; end);

end.
