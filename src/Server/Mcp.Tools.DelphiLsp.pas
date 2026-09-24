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
    [SchemaDescription('Zero-based line number of the identifier')]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription('Zero-based character (column) inside the identifier')]
    [Required]
    property Character: Integer read FCharacter write FCharacter;
  end;

  TDelphiCompletionParams = class(TDelphiPositionParams)
  private
    FTrigger: string;
  public
    [SchemaDescription('Optional trigger character, e.g. "." (empty = manual invocation)')]
    property Trigger: string read FTrigger write FTrigger;
  end;

  TDelphiDefinitionParams = class(TDelphiPositionParams)
  private
    FKind: string;
  public
    [SchemaDescription('Optional: definition (default) | declaration (jump to the interface declaration) | implementation (jump to the method body)')]
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
  Lsp.Patch;

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
  Lines := L.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  L := Lines[ALine];
  M := TRegEx.Match(L, '^\s*(?:procedure|function|constructor|destructor|property)\s+(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)', [roIgnoreCase]);
  if M.Success then
    Result := M.Groups[1].Index - 1 // TMatch is 1-based; LSP columns 0-based
  else
  begin
    M := TRegEx.Match(L, '[A-Za-z_]\w*');
    if M.Success then
      Result := M.Groups[0].Index - 1;
  end;
end;

{ Shared helpers }

function NoSettingsNote(const ASettings: string): string;
begin
  if ASettings = '' then
    Result := ' [warning: no .delphilsp.json project settings found for this ' +
      'file - semantic answers may be null. Generate one in the IDE ' +
      '(Code Insight > Generate LSP config + Reload LSP Server).]'
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
        if L <> nil then
          Obj.AddPair('line1', TJSONNumber.Create(L.GetValue<Integer> + 1));
      end;
    end;
  end;
  for Pair in Obj do
    DecorateLocations(Pair.JsonValue);
end;

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
      Exit('LSP error: ' + Err.ToJSON + ANote);
    V := AResp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit(SN_LSP_NULL_NOTE + ANote);
    DecorateLocations(V);
    Result := V.ToJSON + ANote;
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
function StatementAt(const ALines: TArray<string>; ADesde: Integer;
  out AHasta: Integer): string;

  // Cuantos '(' quedan abiertos en AText.
  function Unbalanced(const AText: string): Integer;
  var
    C: Char;
  begin
    Result := 0;
    for C in AText do
      if C = '(' then
        Inc(Result)
      else if C = ')' then
        Dec(Result);
    if Result < 0 then
      Result := 0;
  end;

var
  K: Integer;
begin
  AHasta := ADesde;
  if (ADesde < 0) or (ADesde > High(ALines)) then
    Exit('');
  Result := ALines[ADesde].Trim;
  K := ADesde;
  // Una cabecera de class/record/interface ABRE un bloque; no es una
  // sentencia a medias, y unirle lo que viene detras pegaba el primer campo
  // a la linea de la clase.
  if TRegEx.IsMatch(Result,
    '(?i)^[A-Za-z_]\w*[ ]*=[ ]*(packed[ ]+)?(class|record|interface)\b') and
     not Result.EndsWith(';') then
    Exit;
  // Un ';' DENTRO de la lista de parametros es un separador, no el final de
  // nada: "function Alta(const A, B: string; C: Integer;" parece terminada y
  // no lo esta, asi que se perdian el tipo de retorno y el valor por defecto.
  while (K < High(ALines)) and (K - ADesde < 8) and
        (not Result.EndsWith(';') or (Unbalanced(Result) > 0)) and
        not Result.EndsWith('=') do
  begin
    Inc(K);
    if ALines[K].Trim = '' then
      Break;
    // Una linea que es SOLO comentario o directiva se salta al unir: una
    // property partida en tres con una nota en medio volvia como
    // "property Cosa: string read FCosa { la nota } write FCosa;". No es
    // falso, pero es ruido dentro de lo unico que el lector va a copiar.
    // Solo la linea ENTERA: quitar comentarios por dentro tocaria literales.
    if ALines[K].TrimLeft.StartsWith('//') or
       ALines[K].TrimLeft.StartsWith('{') then
      Continue;
    Result := Result + ' ' + ALines[K].Trim;
  end;
  AHasta := K;
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
  ' (+N dentro)', a uses clause collapses to 'uses (12 units) @1'. }
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
    Result := Result + Format(' (+%d dentro)', [Ch.Count]);
end;

{ Le pone a cada simbolo del arbol su declaracion REAL y su identificador
  limpio, en UNA pasada de la que comen los tres modos (full, summary y
  filter). Si cada modo lo sacase por su cuenta acabarian diciendo cosas
  distintas del mismo simbolo, que es como nacieron los gemelos de este mes.

  Solo los kinds que SON una declaracion: en la clausula uses cada unit es un
  simbolo de kind "file" y unir desde su linea se tragaria la clausula entera. }
procedure DecorateSymbolDecls(V: TJSONValue; const ALines: TArray<string>);
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
      DecorateSymbolDecls(Item, ALines);
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
      Decl := StatementAt(ALines, Ln, Fin);
      if Decl <> '' then
        Obj.AddPair('decl', Decl);
    end;
  end;
  DecorateSymbolDecls(SymChildren(Obj), ALines);
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
      Ret.AddPair('autoNote', Format(SN_SYMBOLS_AUTO_FMT, [AFullLen]));
    Ret.AddPair('note', SN_SYMBOLS_SUMMARY_NOTE);
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
      Ret.AddPair('note', SN_SYMBOLS_FILTER_NONE);
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
  FDescription := 'Document symbol tree of a Delphi unit (classes, methods, ' +
    'properties, sections) with 0-based ranges, straight from the official ' +
    'DelphiLSP engine. Works even without project settings. Big trees come ' +
    'back as a compact summary by default (mode/filter control it); a ' +
    'FOLDER answers with the interface digest of every unit inside. The ' +
    'engine parses as the COMPILER would for Windows: code inside an ' +
    'inactive {$IFDEF} (LINUX, ANDROID, MACOS...) is not in the tree, and ' +
    'nothing says so - for those blocks use delphi_search or delphi_read.';
end;

// PositionOutOfRange vivia AQUI, en la implementation, o sea invisible para
// las otras unidades - y por eso cuatro tools validaban la posicion y dos no.
// Se mudo a Lsp.Patch, que es donde ya miran todas. Ver alli el porque.

{ Whether this is a file DelphiLSP can say anything about at all. Answering
  `[]` for a .txt reads as "this unit has no symbols" (measured 2026-08-25). }
function NotDelphiSource(const APath: string): string;
begin
  Result := '';
  if not MatchText(TPath.GetExtension(APath), ['.pas', '.dpr', '.dpk', '.inc']) then
    Result := Format(SR_LSP_NOT_SOURCE_FMT,
      [TPath.GetFileName(APath), TPath.GetExtension(APath)]);
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
  Text, Enc, L, Cur, Owner: string;
  Lines: TArray<string>;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, J, Kept, Depth: Integer;

  // Una declaracion puede ocupar varias lineas y quien lee la necesita
  // ENTERA. El como vive ahora en StatementAt, ahi arriba, porque el camino
  // de UN fichero tambien lo necesita: el digest de carpeta acertaba con las
  // firmas y el otro camino las daba mal, leyendo lo MISMO de sitios
  // distintos (medido 2026-09-20).
  function WholeStatement(var AIdx: Integer): string;
  var
    Fin: Integer;
  begin
    Result := StatementAt(Lines, AIdx, Fin);
    AIdx := Fin;
  end;

begin
  Result := TJSONObject.Create;
  Result.AddPair('unit', TPath.GetFileNameWithoutExtension(APath));
  Result.AddPair('path', APath);
  try
    Text := PatchLoadText(APath, Enc);
  except
    Result.AddPair('error', 'no se puede leer');
    Exit;
  end;
  Lines := Text.Replace(#13#10, #10).Split([#10]);
  Arr := TJSONArray.Create;
  Result.AddPair('declares', Arr);
  Cur := '';
  Owner := '';
  Depth := 0;
  Kept := 0;
  I := 0;
  while I <= High(Lines) do
  begin
    L := Lines[I].Trim;
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
    // which class we are inside, and where it ends: a flat list left the
    // reader guessing which member belonged to which class, and hid the
    // private fields entirely - one of them being the subject of a refactor.
    if TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*=[ ]*(class|record|interface)\b') then
    begin
      Owner := L.Split(['='])[0].Trim;
      Depth := 1;
    end
    else if (Owner <> '') and TRegEx.IsMatch(L, '(?i)^end;') then
    begin
      Owner := '';
      Depth := 0;
    end;
    J := I;
    if TRegEx.IsMatch(L, '(?i)^(class[ ]+)?(function|procedure|constructor|destructor|property)\b') or
       TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*=[ ]*(class|record|interface|packed|\()') or
       TRegEx.IsMatch(L, '(?i)^[A-Za-z_]\w*[ ]*=[ ]*') or
       ((Depth > 0) and TRegEx.IsMatch(L, '^[A-Za-z_]\w*[ ]*:[ ]*[A-Za-z_]')) then
    begin
      Inc(Kept);
      if Arr.Count < 300 then
      begin
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('decl', WholeStatement(J));
        if (Owner <> '') and not L.StartsWith(Owner) then
          Obj.AddPair('of', Owner);
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
end;

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
  Folder := ExcludeTrailingPathDelimiter(Params.Path.Trim);
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
      var N := 0;
      for var F in TDirectory.GetFiles(Folder, '*.pas',
        TSearchOption.soAllDirectories) do
      begin
        if SkipIdeArtifacts(F) then
          Continue;
        Inc(N);
        if Units.Count < 60 then
          Units.AddElement(InterfaceDigest(F));
      end;
      Ret.AddPair('total', TJSONNumber.Create(N));
      if N > Units.Count then
        Ret.AddPair('truncated', TJSONBool.Create(True));
      Ret.AddPair('note', SN_SYMBOLS_DIGEST_NOTE);
      Exit(Ret.ToJSON);
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
    Result := Format(SR_LSP_NO_FILE_FMT, [Params.Path]);
  if Result <> '' then
    Exit;
  var Mode := Params.Mode.Trim.ToLower;
  if (Mode <> '') and (Mode <> 'summary') and (Mode <> 'full') then
    Exit('error: mode debe ser "summary", "full" o vacio (automatico).');
  Client := TLspSession.Instance.AcquireFor(Params.Path, Settings);
  var Resp := Client.DocumentSymbols(TLspClient.PathToUri(Params.Path));
  var Note := NoSettingsNote(Settings);
  // The full tree of a real unit measured 37.5k chars (hermes, release audit
  // 2026-08-26): the ranges are the fat, the names are the value. Big trees
  // now answer with the skeleton unless full is asked for by name.
  try
    var Err := Resp.GetValue('error');
    if Err <> nil then
      Exit('LSP error: ' + Err.ToJSON + Note);
    var V := Resp.GetValue('result');
    if (V = nil) or (V is TJSONNull) then
      Exit(SN_LSP_NULL_NOTE + Note);
    DecorateLocations(V);
    // La VERDAD de cada declaracion, leida del fuente, UNA vez y para los
    // tres modos. DelphiLSP renderiza las firmas perdiendo los valores por
    // defecto y los rangos de los arrays; el arbol, los kinds y las lineas
    // siguen siendo suyos, pero como se escribe una declaracion lo dice el
    // fichero. Si no se puede leer, no se decora nada y todo sigue como
    // antes: esto anade verdad, no la sustituye.
    try
      var EncSim: string;
      DecorateSymbolDecls(V, PatchLoadText(Params.Path, EncSim)
        .Replace(#13#10, #10).Split([#10]));
    except
      // un fichero que el LSP si pudo abrir y nosotros no: mejor el arbol
      // pelado que ningun arbol
    end;
    if not (V is TJSONArray) then
      Exit(V.ToJSON + Note);
    var Filt := Params.Filter.Trim.ToLower;
    if Filt <> '' then
      Exit(FilterSymbols(TJSONArray(V), Filt) + Note);
    var Full := V.ToJSON;
    if (Mode = 'full') or ((Mode = '') and (Length(Full) <= 6000)) then
      Exit(Full + Note);
    Result := SummaryOfSymbols(TJSONArray(V), Length(Full), Mode = '') + Note;
  finally
    Resp.Free;
  end;
end;

{ TDelphiDefinitionTool }

constructor TDelphiDefinitionTool.Create;
begin
  inherited;
  FName := 'delphi_definition';
  FDescription := 'Resolve the identifier at a 0-based line:character ' +
    'position in a Delphi source file, using the official DelphiLSP engine ' +
    '(compiler-grade, cross-unit, including RTL/VCL sources). Point INSIDE ' +
    'the identifier. kind selects the half of the unit (a Delphi method ' +
    'exists in BOTH): definition (default) = the BODY in the ' +
    'implementation section; declaration = the interface declaration OF THE ' +
    'TARGET SYMBOL (on a call site the tool chains definition->declaration, ' +
    'so you get the callee, never the enclosing method). ' +
    '(kind=implementation is accepted but DelphiLSP answers it like ' +
    'declaration - measured.) Requires project settings for full answers.';
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
    Exit('RECHAZADO: kind debe ser definition | declaration | implementation.');
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
      var C2 := TLspSession.Instance.AcquireFor(TgtPath, Settings);
      var DeclResp := C2.Declaration(DefLoc.Uri, DefLoc.Line, Col);
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
      Exit(SN_LSP_WARMING + NoSettingsNote(Settings));
    end
    else
    begin
      // no definition to chain from: fall back to a direct declaration, and
      // SAY that on a call site this is the enclosing routine's
      DefResp.Free;
      Resp := Client.Declaration(TLspClient.PathToUri(Params.Path), Params.Line, Params.Character);
      Exit(RenderResult(Resp, SN_DEF_DECL_FALLBACK + NoSettingsNote(Settings)));
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
      Exit(SN_LSP_WARMING + NoSettingsNote(Settings));
    end;
  end;
  Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiSignatureTool }

constructor TDelphiSignatureTool.Create;
begin
  inherited;
  FName := 'delphi_signature';
  FDescription := 'Signature help (parameter completion) for the call under ' +
    'a 0-based line:character position: the routine signatures with their ' +
    'parameter list, from the official DelphiLSP engine - the IDE''s ' +
    'Ctrl+Shift+Space. Point INSIDE the parentheses of the call (right ' +
    'after "(" or a ","). Requires project settings for full answers.';
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
      ' [hint: the position must be INSIDE the call parentheses, right after ( or ,]')
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings));
end;

{ TDelphiHoverTool }

constructor TDelphiHoverTool.Create;
begin
  inherited;
  FName := 'delphi_hover';
  FDescription := 'Type/signature information for the identifier at a 0-based ' +
    'line:character position (official DelphiLSP engine). IMPORTANT: hover ' +
    'answers on identifier USAGES (call sites, type references); hovering a ' +
    'declaration itself returns null. Requires project settings for full answers.';
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
    Result := V.Value + NoSettingsNote(Settings);
    Resp.Free;
  end
  else
    Result := RenderResult(Resp, NoSettingsNote(Settings) +
      ' [hint: hover only answers on usages, not on declarations]');
end;

{ TDelphiCompletionTool }

constructor TDelphiCompletionTool.Create;
begin
  inherited;
  FName := 'delphi_completion';
  FDescription := 'Code completion candidates at a 0-based line:character ' +
    'position (official DelphiLSP engine). Returns at most 50 items ' +
    '(label/kind/detail) plus the total count.';
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
    var Lines := PatchLoadText(Params.Path, Enc).Replace(#13#10, #10).Split([#10]);
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
          AdjNote := Format(SN_COMPLETION_SNAPPED_FMT, [Params.Character, Best]);
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
      Result := Return.ToJSON + NoSettingsNote(Settings);
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
