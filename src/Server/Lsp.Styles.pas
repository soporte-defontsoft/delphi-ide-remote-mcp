unit Lsp.Styles;

// FMX style files (.style) for delphi_styles: the TEXT form ("object
// TStyleContainer" ... ) that the Bitmap Style Designer exports and a style
// pipeline keeps as source of truth.
//
// - A tolerant parser of the DFM-like text: objects, their StyleName, line
// ranges and nesting (collections <item...end> and binary {...} blocks are
// skipped as opaque).
// - Operations by StyleName, never by line: view, get, set (a property of a
// style or of one of its parts), clone (a new style from an existing one).
// - lint: duplicated StyleNames; StyleLookup values used by the project's
// .fmx files that no project style (nor the platform default style)
// defines; design tokens missing in one theme.
// - build: text -> binary (.bin.style) through the DelphiStyleConvert helper
// shipped next to the server, then the .rc -> .res with brcc32.
//
// Binary styles (FMX_STYLE signature / $FF) are never edited: they are the
// product of build, and a text<->binary round trip is what build is for.
// Edits go through Lsp.Patch (encoding kept, __delphi-patch copy).

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  Lsp.DesignerBin; // EL lector de las lineas de un designer de texto (LineasDeForm)

type
  TStyleObj = class
    ClassName_: string;   // TLayout, TRectangle...
    ObjName: string;      // the name before ':' when present
    Clave: string;        // object | inherited | inline (Lsp.DesignerForma.LineaDeObjeto)
    StyleName: string;    // '' when the object has none
    StartLine: Integer;   // 1-based, the 'object' line
    EndLine: Integer;     // 1-based, the matching 'end'
    Depth: Integer;       // 0 = TStyleContainer, 1 = a style, 2+ = parts
    Parent: TStyleObj;
    Children: TObjectList<TStyleObj>;
    constructor Create;
    destructor Destroy; override;
    { The part named AName (StyleName or object name), direct child. }
    function Child(const AName: string): TStyleObj;
  end;

  TStyleDoc = class
  private
    FLines: TArray<string>;
    FRoot: TStyleObj;
    FEnc: string;
    FPath: string;
    FEol: string;
    FBinaryOnDisk: Boolean;
    // que es cada linea (Lsp.DesignerBin.LineasDeForm), de las FLines que
    // FFormDe es por identidad: cada edicion pone un array nuevo
    FForm: TArray<TLineaForm>;
    FFormDe: TArray<string>;
    // las lineas como se leyeron (Reload): Guarda dice con ellas si el
    // fichero ya no se leia ANTES del cambio
    FLeidas: TArray<string>;
    function Clasificadas: TArray<TLineaForm>;
    procedure Parse;
    constructor CreateVacio;
  public
    constructor Create(const APath: string);
    { A document from a TEXT with no file behind it (the DUnitX tests of
      Lsp.DesignerEdit): it reads like any other; Guarda has nowhere to go. }
    class function DeTexto(const AText: string): TStyleDoc;
    { EL abridor de quien lee o escribe un fichero por sus lineas: el
      documento de APath, como Create, SOLO si el parser del IDE lee sus
      lineas como las lee este (FormaDistinta); si no, ADoc nil y la
      negativa DSGN-160. Lanza, como Create, si no se puede leer. Lo usan
      delphi_designer (tree, get, layout, set, insert, delete) y
      delphi_styles (view, get, set, clone, delete). }
    class function Lee(const APath: string; out ADoc: TStyleDoc): string;
    { '' si EL parser del IDE lee las lineas leidas (Leidas) como las lee
      este documento (Lsp.DesignerBin.LineasDeForm); si no, la negativa
      DSGN-160 con la primera linea en que no. Un set sobre un form con el
      '>' de una coleccion en su propia linea, que el IDE carga, escribia
      un Left nuevo en vez de cambiar el que habia (3b del censo de
      jueces, 1.20.2). }
    function FormaDistinta: string;
    destructor Destroy; override;
    property Root: TStyleObj read FRoot;
    property Lines: TArray<string> read FLines;
    { Las lineas como se leyeron del disco (Reload), sin las ediciones en
      memoria: con ellas se pregunta a un juez como estaba el fichero ANTES
      del cambio (Guarda al parser; CargaLoPuesto de Lsp.DesignerEdit al
      lector del IDE). }
    property Leidas: TArray<string> read FLeidas;
    property Path: string read FPath;
    { True si el fichero en disco es un .dfm BINARIO leido al vuelo como texto
      (Lsp.DesignerBin): se lee entero, no se guarda (ver Guarda). }
    property BinaryOnDisk: Boolean read FBinaryOnDisk;
    { Top-level styles (children of the container) - the ones StyleLookup
      resolves. }
    function Styles: TArray<TStyleObj>;
    function FindStyle(const AStyleName: string): TStyleObj;
    { Resolves 'style' then an optional 'a/b/c' path of parts. }
    function Resolve(const AStyleName, AChildPath: string; out AErr: string): TStyleObj;
    { Las lineas de AObj, cada una numerada como las numera delphi_read
      (Lsp.Mascara.CitaDeLinea): el get de delphi_designer y el de delphi_styles }
    function BlockText(AObj: TStyleObj): string;
    { Sets (or adds) a property line of AObj. AValue is written verbatim, as
      it would appear in the file. Returns the resulting line. }
    function SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string;
    { The same with a value in pieces, as the IDE writes a long string
      (Lsp.DesignerBin.TrozosDeLiteral): one piece on the property's line,
      several below it. Returns the property's line. Con su nombre y no como
      sobrecarga de SetProp: dos de igual aridad que solo difieren en
      TArray<string> frente a string tumban a DelphiLSP con una copia suelta
      de esta unidad (-32603, medido el 9-oct-2026; test_paisaje). }
    function SetPropTrozos(AObj: TStyleObj; const AProp: string; const ATrozos: TArray<string>;
      out AWasThere: Boolean): string;
    { Removes a property line of AObj; False when absent. }
    function DeleteProp(AObj: TStyleObj; const AProp: string): Boolean;
    { Copies ASrc right after itself with the new StyleName. }
    procedure CloneStyle(ASrc: TStyleObj; const ANewName: string);
    { The lines AProp's value takes at AObj's own level (0-based, AIni..AFin:
      a list, a binary block, a collection or a string split with '+' run
      over several); False when absent. Si esta mas de una vez (una clase
      con DefineProperties del mismo nombre, ImageIndex de una accion FMX),
      la ULTIMA, la que guarda el lector del IDE; SetProp y DeleteProp
      cambian todas (RangosDePropiedad). }
    function PropLines(AObj: TStyleObj; const AProp: string; out AIni, AFin: Integer): Boolean;
    { El VALOR de AProp en el nivel propio de AObj, entero (una cadena partida,
      sus trozos en uno: ValorEnteroDe; de una lista o un bloque, su primera
      linea); '' y AFound False si no esta. EL lector del valor de una
      propiedad: Mcp.Tools.Designer (PropRaw) lo leia con su propia regex
      (2.2 de la 1.18.0). }
    function ValorDe(AObj: TStyleObj; const AProp: string; out AFound: Boolean): string;
    { ...y el TEXTO del literal que es ese valor ('' si no esta o no es un
      literal): lo que ya habia, para la cuenta por valor de los sustitutos
      sueltos (Lsp.DesignerBin.SueltoEnLiteral) de designer set y styles set. }
    function LiteralDe(AObj: TStyleObj; const AProp: string): string;
    { The object named AName at any depth (a form's component, by its Name;
      the same identifier as dcc sees it); nil when there is none. }
    function ObjetoDeNombre(const AName: string): TStyleObj;
    { The file text these lines would make, with the file's own line break:
      what Guarda writes. A caller that writes several files at once
      (delphi_designer insert/delete: the form and its unit, all or
      nothing) composes with it and writes with PatchSaveText + Encoding. }
    function TextoDe(const ALines: TArray<string>): string;
    { Replaces every line (an edit composed outside); Guarda or TextoDe next. }
    procedure SetLines(const ALines: TArray<string>);
    property Encoding: string read FEnc;
    { Removes a whole object, its block object..end: a top-level style, or a
      component of a form with everything inside it. }
    procedure DeleteStyle(AObj: TStyleObj);
    { Writes the document, ONLY if THE IDE's form parser reads the result
      (Lsp.DesignerBin.ParserDeForm, with the file's own encoding): '' when
      written; if not, nothing is written and the refusal says the parser's
      message and line - DSGN-124 when this change breaks it, DSGN-125 when
      the file was already unreadable before. Era Save, que escribia lo que
      una gramatica propia daba por bueno (9.B de la 1.18.0): EL guardado de
      delphi_designer y de delphi_styles, sin otra puerta. }
    function Guarda: string;
    { EL juicio de Guarda sobre el TEXTO que se va a escribir (TextoDe: con el
      salto de linea del fichero): '' si el parser del IDE lo lee; si no,
      DSGN-124 o DSGN-125. Lo pregunta tambien quien escribe el form junto a
      su unidad (Lsp.DesignerEdit, EscribeFormYUnidad: insert, delete,
      rename), que no pasa por Guarda. }
    function JuicioDelParser(const ATexto: string): string;
    { Re-parses after an edit (line numbers moved). }
    procedure Reload;
    { Re-reads the TREE from the lines as they are now, without the disk:
      SetProp, SetPropTrozos and DeleteProp move lines and do not touch the
      line numbers of the objects, so a second edit composed in memory on
      the same document needs this first - and an object read before it is
      gone: look it up again by name (3.10 de la 1.18.0: set de varias
      propiedades, insert con propiedades). }
    procedure Reparsea;
  end;

{ Does this look like a value a text DFM (.style, .dfm, .fmx) can hold? The
  streaming grammar: number, $hex, 'string', identifier, [set], and the
  block forms. Measured field round 8: `Fill.Color = no soy un color` was
  written happily and only surfaced later as `EParserError` from build. It
  lived in delphi_styles; delphi_designer set is its second caller. }
function ValidStyleValue(const AValue: string): Boolean;

{ True for the binary forms (FMX_STYLE signature or the $FF wrapper). }
function IsBinaryStyle(const APath: string): Boolean;

{ The text .style files of a folder (binary ones and *.bin.style excluded). }
function TextStylesIn(const ADir: string): TArray<string>;

{ Path of the DelphiStyleConvert helper next to the server exe ('' if absent). }
function StyleConverterExe: string;

{ LA llamada al conversor: "<AExe>" <AArgs> en ADir ('' = el de siempre),
  con su salida y su codigo. La usan los nombres por defecto de la plataforma
  (defaults) y el build de estilos (tobin): cada uno componia la orden a mano
  (lo encontro test_paisaje en su primera pasada, 1.16.0). }
function CorreStyleConvert(const AExe, AArgs, ADir: string; ATimeoutMs: Integer;
  out ACode: Cardinal): string;

{ Lo que el cargador de estilos de FMX IGNORA de un .style de texto: su
  lector se traga cada error - una propiedad que la clase no publica, un valor
  que no lee, una clase que no conoce con todo lo de dentro - y el estilo carga
  sin ello, en la app y en el .bin.style de build (medido el 17-oct-2026: un
  Fill.Color en un TLayout salia del binario con ok:true; Hermes, completo de
  la 1.20.1). Lo dice el conversor (check: la misma lectura, apuntando), con
  el mensaje del RTL - "Error reading TLayout.Fill.Color: Property Fill.Color
  does not exist" -, en el orden en que FMX los encuentra. AFichero: el .style
  tal cual esta. False si no hay conversor o no contesto: no se sabe, y
  AIgnorado viene vacio. ANoCarga: el error con el que FMX NO PUDO cargarlo
  (el conversor corrio y su lectura lanzo: 'EReadError: Invalid property
  value' de un TextSettings.FontColor = $FFFF0000), '' si cargo. Es el juicio
  mas fuerte y se tomaba por "no se sabe": set lo escribia, lint decia clean
  y solo build lo negaba (Hermes, test completo de la 1.21.0). }
function IgnoradoPorFmx(const AFichero: string; out AIgnorado: TArray<string>;
  out ANoCarga: string): Boolean;
{ ...de un texto que aun no esta en disco (lo que set va a escribir), con la
  codificacion AEnc de su fichero: la copia que se pregunta va a la temporal
  del servidor, no a la jaula. }
function IgnoradoPorFmxDeTexto(const ATexto, AEnc: string; out AIgnorado: TArray<string>;
  out ANoCarga: string): Boolean;

{ StyleNames of the Windows platform default style, extracted once through the
  helper and cached under LOCALAPPDATA. Empty when the helper is missing.
  Ya como claves (ClaveDeEstilo). }
function PlatformDefaultStyleNames: TArray<string>;

{ LA clave del nombre de un estilo, la de FMX: su TStyleIndexer
  (FMX.Types) indexa StyleName.ToLowerInvariant, asi que 'BOTON' y 'Boton'
  con su acento son el MISMO estilo para quien lo busca. FindStyle y Child
  comparaban con SameText (solo pliega ASCII) y el lint con ToLower (el del
  idioma): con 'Boton' acentuado en el fichero, clone aceptaba la version
  en mayusculas como nueva (P7 de la segunda revision de la 1.17.0). }
function ClaveDeEstilo(const ANombre: string): string;

type
  TClaseRc = (crRecurso, crInclude);
  { Lo que un .rc hace leer a brcc32: un recurso NOMBRE TIPO [banderas]
    FICHERO, o un #include / RCINCLUDE (Tipo dice cual). Linea, 1-based;
    Fichero tal cual lo escribe el .rc, sin comillas. PorMacro: el fichero
    de un recurso es el nombre de un #define de antes (X RCDATA F), que
    brcc32 expande y esta lectura no: no se sabe que fichero es. }
  TEntradaRc = record
    Clase: TClaseRc;
    Linea: Integer;
    Nombre, Tipo, Fichero: string;
    PorMacro: Boolean;
  end;
  TLecturaRc = record
    Entradas: TArray<TEntradaRc>;
    { todo lo que podria nombrar un fichero: el de cada entrada, y cada
      cadena o palabra con forma de ruta - la puerta de leer no apuesta por
      la gramatica: la de brcc32 es mas rica que esta }
    Rutas: TArray<string>;
  end;

{ LA lectura de un .rc: la de la segunda barrera de delphi_styles build
  (RcPathsDenied) y la del lint de estilos. La puerta es brcc32 en su
  contenedor (CompilaRcEnContenedor): esto es una gramatica nuestra, porque
  brcc32 no dice que va a leer. La suya, medida el 18-oct-2026: lee por
  TOKENS - el fichero puede ir en otra linea, con banderas de memoria delante
  (PRELOAD LOADONCALL FIXED MOVEABLE DISCARDABLE PURE IMPURE; SHARED y
  NONSHARED las toma por fichero), dos recursos en una linea, RCINCLUDE con y
  sin comillas -, los comentarios // y /* */ no lo son dentro de una cadena,
  no decodifica escapes, y tiene preprocesador (#define, ##...), que esta
  lectura no sigue (lo que nombra una directiva si va a Rutas). Eran dos
  regex de linea, una por lector: 'LOGO RCDATA
  DISCARDABLE "falta.png"' no lo veia ninguna (3c del censo de jueces). }
function LeeRc(const ATexto: string): TLecturaRc;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  Lsp.Patch,
  Lsp.BuildRunner,
  Lsp.Guard,
  Lsp.Pascal, // EL identificador: ValidStyleValue
  Lsp.DesignerForma, // DesignerShapeOf: la forma en disco de un designer, y de un .style
  Lsp.Texts,
  Lsp.Casa,
  Lsp.Mascara,
  Lsp.Codificacion,
  Lsp.Args; // PrimerTrozo: el nombre de una macro del .rc

{ TStyleObj }

constructor TStyleObj.Create;
begin
  inherited;
  Children := TObjectList<TStyleObj>.Create(True);
end;

destructor TStyleObj.Destroy;
begin
  Children.Free;
  inherited;
end;

function TStyleObj.Child(const AName: string): TStyleObj;
var
  C: TStyleObj;
begin
  for C in Children do
    if (ClaveDeEstilo(C.StyleName) = ClaveDeEstilo(AName)) or
       ((C.ObjName <> '') and MismoIdentificador(C.ObjName, AName)) then
      Exit(C);
  Result := nil;
end;

{ TStyleDoc }

constructor TStyleDoc.Create(const APath: string);
begin
  inherited Create;
  FPath := TPath.GetFullPath(APath);
  Reload;
end;

constructor TStyleDoc.CreateVacio;
begin
  inherited Create;
end;

class function TStyleDoc.DeTexto(const AText: string): TStyleDoc;
begin
  Result := TStyleDoc.CreateVacio;
  Result.FPath := '';
  Result.FEnc := 'utf8';
  Result.FEol := SaltoDominante(AText);
  Result.FLines := SplitToLines(AText);
  Result.FLeidas := Copy(Result.FLines);
  Result.Parse;
end;

class function TStyleDoc.Lee(const APath: string; out ADoc: TStyleDoc): string;
begin
  ADoc := nil;
  ADoc := TStyleDoc.Create(APath);
  try
    Result := ADoc.FormaDistinta;
  except
    FreeAndNil(ADoc);
    raise;
  end;
  if Result <> '' then
    FreeAndNil(ADoc);
end;

function TStyleDoc.FormaDistinta: string;
begin
  Result := FormaDistintaDeLineas(FLeidas, TPath.GetFileName(FPath));
end;

destructor TStyleDoc.Destroy;
begin
  FRoot.Free;
  inherited;
end;

procedure TStyleDoc.Reparsea;
begin
  FreeAndNil(FRoot);
  Parse;
end;

procedure TStyleDoc.Reload;
var
  Text, Err: string;
begin
  FreeAndNil(FRoot);
  // Un .dfm BINARIO se lee al vuelo como texto (la conversion del IDE) y se
  // recuerda: Guarda lo rechaza, que guardar texto sobre un binario sin decirlo
  // es cambiarle el formato a escondidas; to-text lo hace a la vista.
  FBinaryOnDisk := IsBinaryDesignerFile(FPath);
  // por EL lector de designers (Lsp.Patch.TextoDeDesigner): binario o texto
  Err := TextoDeDesigner(FPath, Text, FEnc);
  if Err <> '' then
    raise Exception.Create(Err);
  if FBinaryOnDisk then
    FEnc := 'binario';
  FEol := SaltoDominante(Text);
  FLines := SplitToLines(Text); // el troceador de todos: un CR suelto es salto
  FLeidas := Copy(FLines); // copia: un array dinamico se comparte, no se copia al escribir
  Parse;
end;

function TStyleDoc.Clasificadas: TArray<TLineaForm>;
begin
  if (FLines = nil) or (Pointer(FFormDe) <> Pointer(FLines)) then
  begin
    FForm := LineasDeForm(FLines);
    FFormDe := FLines;
  end;
  Result := FForm;
end;

procedure TStyleDoc.Parse;
var
  I, Depth: Integer;
  Cur, O: TStyleObj;
  Form: TArray<TLineaForm>;
  Estilo: string;
begin
  FRoot := nil;
  Cur := nil;
  Depth := -1;
  // EL lector de las lineas: lo de dentro de un valor - una coleccion con sus
  // items, una cadena partida, una lista, un bloque binario - no abre ni
  // cierra objetos. Aqui se cerraba una coleccion con cualquier linea acabada
  // en '>' y un '= {' dentro de una cadena abria un bloque binario hasta el
  // final (revision de la 1.17.0, medido en vivo)
  Form := Clasificadas;
  for I := 0 to High(FLines) do
    case Form[I].Clase of
      clfObjeto:
        begin
          // un segundo objeto de fuera: no es un fichero de una raiz, y lo de
          // detras no se lee (se reasignaba la raiz y la anterior se perdia)
          if (Cur = nil) and (FRoot <> nil) then
            Break;
          O := TStyleObj.Create;
          O.ObjName := Form[I].Nombre;
          O.ClassName_ := Form[I].ClaseObj;
          O.Clave := Form[I].Clave;
          O.StartLine := I + 1;
          O.EndLine := I + 1;
          O.Parent := Cur;
          Inc(Depth);
          O.Depth := Depth;
          if Cur = nil then
            FRoot := O
          else
            Cur.Children.Add(O);
          Cur := O;
        end;
      clfFin:
        if Cur <> nil then
        begin
          Cur.EndLine := I + 1;
          Cur := Cur.Parent;
          Dec(Depth);
        end;
      clfPropiedad:
        if (Cur <> nil) and (Cur.StyleName = '') and (Form[I].Coleccion = 0) and
           SameText(Form[I].Prop, 'StyleName') and
           // el valor ENTERO: uno largo va en trozos en las lineas de debajo,
           // como lo escribe el IDE y set/clone (segunda revision de la 1.17.0)
           LeeLiteralDeForm(ValorEnteroDe(FLines, Form, I), Estilo) then
          Cur.StyleName := Estilo;
    end;
  if FRoot = nil then
  begin
    FRoot := TStyleObj.Create;
    FRoot.ClassName_ := '';
  end;
end;

function TStyleDoc.Styles: TArray<TStyleObj>;
begin
  Result := FRoot.Children.ToArray;
end;

function TStyleDoc.FindStyle(const AStyleName: string): TStyleObj;
var
  O: TStyleObj;
begin
  for O in FRoot.Children do
    if ClaveDeEstilo(O.StyleName) = ClaveDeEstilo(AStyleName) then
      Exit(O);
  Result := nil;
end;

function TStyleDoc.Resolve(const AStyleName, AChildPath: string; out AErr: string): TStyleObj;
var
  Seg: string;
begin
  AErr := '';
  Result := FindStyle(AStyleName);
  if Result = nil then
  begin
    // un objeto con ESE nombre y sin StyleName: FMX tira el nombre al cargar
    // un estilo (TStyleReader.SetName, medido en su fuente) y su indice solo
    // mira StyleName, asi que nadie lo encuentra; se dice, en vez de "no hay"
    // (informe de Hermes, 1.18.2: entradas 'inherited cardstyle: TLayout')
    for var O in FRoot.Children do
      if (O.StyleName = '') and (O.ObjName <> '') and SameText(O.ObjName, AStyleName) then
      begin
        AErr := MsgFmt(SR_STYLE_SOLO_NOMBRE_FMT, [AStyleName, TPath.GetFileName(FPath), O.ObjName,
          O.StartLine, O.EndLine, O.ObjName]);
        Exit;
      end;
    AErr := MsgFmt(SR_STYLE_NINGUN_ESTILO_STYLENAME_FMT, [AStyleName, TPath.GetFileName(FPath)]);
    Exit;
  end;
  for Seg in AChildPath.Replace('\', '/').Split(['/'], TStringSplitOptions.ExcludeEmpty) do
  begin
    Result := Result.Child(Seg.Trim);
    if Result = nil then
    begin
      AErr := MsgFmt(SR_STYLE_NO_TIENE_UNA_PARTE_FMT, [AStyleName, Seg.Trim, AChildPath]);
      Exit;
    end;
  end;
end;

function TStyleDoc.BlockText(AObj: TStyleObj): string;
var
  I: Integer;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    // cada linea con su numero, como delphi_read (CitaDeLinea): es lo que se
    // copia para un ancla, y el filtro la deja tal cual. Salia sin numero y
    // enmascarada: una ruta de un valor (Picture.FileName) salia srvd: y el
    // ancla no casaba con el disco (revision de la 1.13.0; David: el get de
    // delphi_designer como delphi_read - y el de delphi_styles, su gemelo)
    for I := AObj.StartLine - 1 to AObj.EndLine - 1 do
      L.Add(CitaDeLinea(I + 1, FLines[I]));
    Result := string.Join(#10, L.ToStringArray);
  finally
    L.Free;
  end;
end;

{ La propiedad AProp del nivel PROPIO de AObj - las lineas tras su cabecera
  y antes de su primer hijo, fuera de sus colecciones - y las lineas que
  ocupa su valor, AIni y AFin (0-based), por EL lector de las lineas
  (AForm): una lista, un bloque binario, una coleccion o una cadena partida
  ocupan varias, y lo de dentro de un valor no es del nivel propio (el
  'Caption =' de un item pasaba por el del objeto, y un set dejaba debajo el
  resto de un valor partido: delphi_designer set, 1.17.0). False si no esta. }
type
  TRangoDeLineas = record
    Ini, Fin: Integer;
  end;

{ ...cada vez que esta: dos, cuando su clase la define con DefineProperties
  ademas de publicarla - ImageIndex de una accion FMX (FMX.ActnList), Left y
  Top de un form FMX: 14 forms de los Samples, medido el 18-oct-2026 - o
  cuando se escribio a mano. El lector del IDE las lee todas en orden y se
  queda con la ULTIMA: set cambiaba la primera y contestaba ok sin efecto. }
function RangosDePropiedad(AObj: TStyleObj; const AForm: TArray<TLineaForm>;
  const AProp: string): TArray<TRangoDeLineas>;
var
  I, Stop: Integer;
  R: TRangoDeLineas;
begin
  Result := [];
  Stop := AObj.EndLine - 1;
  if AObj.Children.Count > 0 then
    Stop := AObj.Children[0].StartLine - 1;
  for I := AObj.StartLine to Min(Stop, Length(AForm)) - 1 do
    if (AForm[I].Clase = clfPropiedad) and (AForm[I].Coleccion = 0) and
       SameText(AForm[I].Prop, AProp) then
    begin
      R.Ini := I;
      R.Fin := AForm[I].Fin;
      Result := Result + [R];
    end;
end;

// la que cuenta, si esta mas de una vez: la ultima, la que guarda el lector
function RangoDePropiedad(AObj: TStyleObj; const AForm: TArray<TLineaForm>;
  const AProp: string; out AIni, AFin: Integer): Boolean;
var
  Rangos: TArray<TRangoDeLineas>;
begin
  Rangos := RangosDePropiedad(AObj, AForm, AProp);
  Result := Length(Rangos) > 0;
  AIni := -1;
  AFin := -1;
  if Result then
  begin
    AIni := Rangos[High(Rangos)].Ini;
    AFin := Rangos[High(Rangos)].Fin;
  end;
end;

function TStyleDoc.SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string;
begin
  Result := SetPropTrozos(AObj, AProp, [AValue], AWasThere);
end;

function TStyleDoc.SetPropTrozos(AObj: TStyleObj; const AProp: string; const ATrozos: TArray<string>;
  out AWasThere: Boolean): string;
var
  Ini, Fin, InsertAt, K: Integer;
  Sangria: string;
  Nuevas: TArray<string>;
  L: TList<string>;
  Rangos: TArray<TRangoDeLineas>;
begin
  Rangos := RangosDePropiedad(AObj, Clasificadas, AProp);
  AWasThere := Length(Rangos) > 0;
  // la sangria de la casa de esa linea (Lsp.Patch); la del nivel si es nueva
  if AWasThere then
    Sangria := LeadingWhite(FLines[Rangos[High(Rangos)].Ini])
  else
    Sangria := SangriaDeNivel(AObj.Depth + 1);
  Nuevas := LineasDePropiedad(Sangria, AProp, ATrozos);
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    if AWasThere then
      // el valor entero fuera, el nuevo con sus lineas; en CADA una si esta
      // mas de una vez (el lector se queda con la ultima, y el IDE las
      // guarda iguales), de abajo arriba: las de arriba no se mueven
      for K := High(Rangos) downto 0 do
      begin
        L.DeleteRange(Rangos[K].Ini, Rangos[K].Fin - Rangos[K].Ini + 1);
        L.InsertRange(Rangos[K].Ini, Nuevas);
      end
    else
    begin
      // detras de su StyleName si lo tiene (el SUYO: se buscaba en todo el
      // bloque, hijos incluidos), si no justo detras de la cabecera
      InsertAt := AObj.StartLine; // 0-based: la linea DETRAS de la cabecera
      if RangoDePropiedad(AObj, Clasificadas, 'StyleName', Ini, Fin) then
        InsertAt := Fin + 1;
      L.InsertRange(InsertAt, Nuevas);
    end;
    FLines := L.ToArray;
  finally
    L.Free;
  end;
  Result := Nuevas[0];
end;

function TStyleDoc.DeleteProp(AObj: TStyleObj; const AProp: string): Boolean;
var
  K: Integer;
  L: TList<string>;
  Rangos: TArray<TRangoDeLineas>;
begin
  // todas las veces que esta (RangosDePropiedad), de abajo arriba
  Rangos := RangosDePropiedad(AObj, Clasificadas, AProp);
  Result := Length(Rangos) > 0;
  if not Result then
    Exit;
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    for K := High(Rangos) downto 0 do
      L.DeleteRange(Rangos[K].Ini, Rangos[K].Fin - Rangos[K].Ini + 1);
    FLines := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TStyleDoc.CloneStyle(ASrc: TStyleObj; const ANewName: string);
var
  Block: TList<string>;
  I, Ini, Fin: Integer;
  L: TList<string>;
  Nuevas: TArray<string>;
begin
  Block := TList<string>.Create;
  L := TList<string>.Create;
  try
    // su StyleName, el SUYO y entero (uno largo va en trozos), por los
    // compositores de la casa: se escribia a mano entre comillas, sin #N ni
    // trozos, y se tomaba la primera linea StyleName del bloque aunque fuera
    // la de un hijo (revision de la 1.17.0)
    Nuevas := LineasDePropiedad(SangriaDeNivel(ASrc.Depth + 1), 'StyleName',
      TrozosDeLiteral(ANewName));
    if RangoDePropiedad(ASrc, Clasificadas, 'StyleName', Ini, Fin) then
      Nuevas := LineasDePropiedad(LeadingWhite(FLines[Ini]), 'StyleName', TrozosDeLiteral(ANewName))
    else
    begin
      Ini := -1;
      Fin := -1;
    end;
    for I := ASrc.StartLine - 1 to ASrc.EndLine - 1 do
      if I = Ini then
        Block.AddRange(Nuevas)
      else if (Ini < 0) or (I < Ini) or (I > Fin) then
        Block.Add(FLines[I]);
    if Ini < 0 then
      Block.InsertRange(1, Nuevas);
    L.AddRange(FLines);
    L.InsertRange(ASrc.EndLine, Block); // right after the source block
    FLines := L.ToArray;
  finally
    L.Free;
    Block.Free;
  end;
end;

function TStyleDoc.ObjetoDeNombre(const AName: string): TStyleObj;

  function Busca(O: TStyleObj): TStyleObj;
  begin
    if (O.ObjName <> '') and MismoIdentificador(O.ObjName, AName) then
      Exit(O);
    for var K in O.Children do
    begin
      Result := Busca(K);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
  end;

begin
  Result := nil;
  if (FRoot <> nil) and (AName <> '') then
    Result := Busca(FRoot);
end;

function TStyleDoc.TextoDe(const ALines: TArray<string>): string;
begin
  Result := string.Join(FEol, ALines);
end;

procedure TStyleDoc.SetLines(const ALines: TArray<string>);
begin
  FLines := Copy(ALines);
end;

function TStyleDoc.PropLines(AObj: TStyleObj; const AProp: string; out AIni, AFin: Integer): Boolean;
begin
  Result := RangoDePropiedad(AObj, Clasificadas, AProp, AIni, AFin);
end;

function TStyleDoc.ValorDe(AObj: TStyleObj; const AProp: string; out AFound: Boolean): string;
var
  Ini, Fin: Integer;
begin
  Result := '';
  AFound := PropLines(AObj, AProp, Ini, Fin);
  if AFound then
    Result := ValorEnteroDe(FLines, Clasificadas, Ini);
end;

function TStyleDoc.LiteralDe(AObj: TStyleObj; const AProp: string): string;
var
  Hay: Boolean;
begin
  if not LeeLiteralDeForm(ValorDe(AObj, AProp, Hay), Result) then
    Result := '';
end;

procedure TStyleDoc.DeleteStyle(AObj: TStyleObj);
var
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    L.DeleteRange(AObj.StartLine - 1, AObj.EndLine - AObj.StartLine + 1);
    FLines := L.ToArray;
  finally
    L.Free;
  end;
end;

function TStyleDoc.Guarda: string;
begin
  if FBinaryOnDisk then
    Exit(MsgFmt(SR_STYLE_BINARIO_NO_SE_GUARDA_FMT, [TPath.GetFileName(FPath)]));
  // los bytes que se juzgan son los que se escriben
  var Texto := TextoDe(FLines);
  Result := JuicioDelParser(Texto);
  if Result <> '' then
    Exit;
  PatchSaveText(FPath, Texto, FEnc);
  Reload;
end;

function TStyleDoc.JuicioDelParser(const ATexto: string): string;
var
  Linea, LineaAntes: Integer;
  Cita, CitaAntes, Error, Antes: string;
begin
  // lo LEIDO, por lineas como lo lee el parser del IDE: si no, lo que se va
  // a escribir se compuso sobre otras lineas (DSGN-160). La segunda barrera
  // de quien abre con Lee, y la de quien no
  Result := FormaDistinta;
  if Result <> '' then
    Exit;
  Error := ParserDeForm(ATexto, FEnc, Linea, Cita);
  if Error <> '' then
  begin
    // como estaba ANTES: si ya no se leia, se dice asi (el arreglo es otro)
    Antes := ParserDeForm(TextoDe(FLeidas), FEnc, LineaAntes, CitaAntes);
    if Antes <> '' then
      Exit(MsgFmt(SR_DSGN_PARSER_YA_ROTO_FMT, [TPath.GetFileName(FPath), Antes, LineaAntes, CitaAntes]));
    Exit(MsgFmt(SR_DSGN_PARSER_NO_ESCRIBE_FMT, [TPath.GetFileName(FPath), Error, Linea, Cita]));
  end;
end;

{ ---- files ---- }

function ValidStyleValue(const AValue: string): Boolean;
var
  V: string;
begin
  V := AValue.Trim;
  Result := (V <> '') and (
    // LA gramatica del numero y LA de la cadena (Lsp.DesignerBin): aqui un
    // 1e3 no era numero y un 'abc sin cerrar era cadena (revision de la 1.17.0)
    EsNumeroDeForm(V) or                                       // 12  -3.5  1e3  $FF00FF00
    EsIdentificador(V, True) or                                // claRed  True  TAlignLayout.Top
    TRegEx.IsMatch(V, '^\[.*\]$') or                           // [a, b]
    TRegEx.IsMatch(V, '^<.*>$') or                             // inline collection
    EsLiteralDeForm(V) or                                      // 'text'  #13#10  'a' + 'b'
    // un bloque binario o una lista, CERRADOS: '(a, b' o '{ 0102' dejaban el
    // .style sin abrir (E10, 2.2 de la 1.18.0)
    ((V[1] = '{') and V.EndsWith('}')) or ((V[1] = '(') and V.EndsWith(')')));
end;

function IsBinaryStyle(const APath: string): Boolean;
var
  B: TBytes;
  S: TFileStream;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, 9);
    if S.Size < 9 then
      Exit;
    S.ReadBuffer(B[0], 9);
  finally
    S.Free;
  end;
  // La forma la dice DesignerShapeOf (la cabecera de recurso FF 0A 00, el
  // flujo TPF0): solo $FF tomaba por binario un .style de TEXTO guardado en
  // UTF-16 (FF FE), y un TPF0 a pelo por texto (2.2 de la 1.18.0). FMX_STYLE
  // es la firma propia de un estilo FMX compilado: nueve bytes ASCII, que no
  // piden ninguna pagina ANSI (aqui habia otra definicion, TEncoding.ANSI; r5
  // de la 1.18.0).
  Result := (DesignerShapeOf(B) <> dsText) or (TEncoding.ASCII.GetString(B) = 'FMX_STYLE');
end;

function TextStylesIn(const ADir: string): TArray<string>;
var
  F: string;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    if TDirectory.Exists(ADir) then
      for F in TDirectory.GetFiles(ADir, '*.style') do
        if not F.ToLower.EndsWith('.bin.style') and not IsBinaryStyle(F) then
          L.Add(F);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function CorreStyleConvert(const AExe, AArgs, ADir: string; ATimeoutMs: Integer;
  out ACode: Cardinal): string;
begin
  Result := RunCapturedIn('"' + AExe + '" ' + AArgs, ADir, ATimeoutMs, ACode);
end;

const
  { la temporal del servidor donde se le pregunta al conversor por un texto }
  ESTILOS_CHECK_SUB = 'styles-check';

function IgnoradoPorFmx(const AFichero: string; out AIgnorado: TArray<string>;
  out ANoCarga: string): Boolean;
const
  // lo que escribe el conversor cuando la lectura lanza (DelphiStyleConvert.dpr:
  // 'ERROR: <clase>: <mensaje>' y codigo 1); otro codigo es que no se pudo
  // preguntar (el uso, el plazo)
  ERROR_DEL_CONVERSOR = 'ERROR: ';
var
  Exe, Salida: string;
  Code: Cardinal;
  L: TList<string>;
begin
  AIgnorado := [];
  ANoCarga := '';
  Exe := StyleConverterExe;
  if Exe = '' then
    Exit(False);
  Salida := CorreStyleConvert(Exe, 'check "' + AFichero + '"', '', 60000, Code);
  if Code <> 0 then
  begin
    if Code = 1 then
      for var Linea in SplitToLines(Salida) do
        if Linea.StartsWith(ERROR_DEL_CONVERSOR) then
          ANoCarga := Linea.Substring(Length(ERROR_DEL_CONVERSOR)).Trim;
    Exit(ANoCarga <> '');
  end;
  L := TList<string>.Create;
  try
    for var Linea in SplitToLines(Salida) do
      if Linea.StartsWith('IGNORED'#9) then
        L.Add(Linea.Substring(Length('IGNORED'#9)).Trim);
    AIgnorado := L.ToArray;
  finally
    L.Free;
  end;
  Result := True;
end;

function IgnoradoPorFmxDeTexto(const ATexto, AEnc: string; out AIgnorado: TArray<string>;
  out ANoCarga: string): Boolean;
var
  Dir: string;
begin
  AIgnorado := [];
  ANoCarga := '';
  if StyleConverterExe = '' then
    Exit(False);
  // la copia que se le PREGUNTA, en una carpeta de ESTA llamada del temporal
  // del servidor, como la propuesta del renderizador (Lsp.FormRender): no es
  // un entregable del agente ni se escribe en la jaula
  Dir := NuevaCarpetaDescarga(ServerTempDir(ESTILOS_CHECK_SUB));
  try
    try
      CrearCarpeta(Dir);
      var Cand := TPath.Combine(Dir, 'c.style');
      EscribeTexto(Cand, ATexto, ltTemporal, EncKindOf(AEnc), False);
      Result := IgnoradoPorFmx(Cand, AIgnorado, ANoCarga);
    except
      Result := False; // sin la pregunta no se sabe: quien llama sigue como antes
    end;
  finally
    try
      BorraArbol(Dir); // SIEMPRE, sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta: la purga del arranque se la lleva
    end;
  end;
end;

function StyleConverterExe: string;
begin
  Result := ServerDir('DelphiStyleConvert.exe');
  if not TFile.Exists(Result) then
    Result := '';
end;

function PlatformDefaultStyleNames: TArray<string>;
var
  Cache, Exe: string;
  Code: Cardinal;
  L: TList<string>;
begin
  Result := [];
  Cache := ServerCacheDir('win10-default.style');
  if not TFile.Exists(Cache) then
  begin
    Exe := StyleConverterExe;
    if Exe = '' then
      Exit;
    CrearCarpeta(TPath.GetDirectoryName(Cache));
    CorreStyleConvert(Exe, 'defaults "' + Cache + '"', '', 60000, Code);
    if (Code <> 0) or not TFile.Exists(Cache) then
      Exit;
  end;
  L := TList<string>.Create;
  try
    // EL lector de una linea de propiedad y EL de un literal de form (#N y
    // trozos incluidos): la regex de antes no leia ni lo uno ni lo otro (2.2
    // de la 1.18.0)
    for var Linea in SplitToLines(LeeTexto(Cache, [ltCasa])) do
    begin
      var Prop, Valor, Texto: string;
      if LineaDePropiedad(Linea, Prop, Valor) and SameText(Prop, 'StyleName') and
         LeeLiteralDeForm(Valor, Texto) then
        L.Add(ClaveDeEstilo(Texto));
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function ClaveDeEstilo(const ANombre: string): string;
begin
  Result := ANombre.ToLowerInvariant;
end;

const
  // las banderas de memoria que brcc32 toma por banderas (SHARED y
  // NONSHARED no: las toma por el fichero; medido el 18-oct-2026)
  BANDERAS_RC: array[0..6] of string =
    ('PRELOAD', 'LOADONCALL', 'FIXED', 'MOVEABLE', 'DISCARDABLE', 'PURE', 'IMPURE');
  // los tipos que no nombran un fichero: su bloque, con lo de antes de su BEGIN
  TIPOS_DE_BLOQUE_RC: array[0..9] of string =
    ('DIALOG', 'DIALOGEX', 'MENU', 'MENUEX', 'ACCELERATORS', 'VERSIONINFO', 'TEXTINCLUDE',
     'DLGINIT', 'TOOLBAR', 'STRINGTABLE');

type
  TClaseTokRc = (ctrCadena, ctrPalabra, ctrSigno, ctrDirectiva);
  TTokRc = record
    Clase: TClaseTokRc;
    Texto: string;
    Linea: Integer;
  end;

(* Los tokens de un .rc como los separa brcc32: cadenas entre comillas (""
  dentro es una comilla; sin escapes), palabras hasta un blanco, una coma,
  una llave o un comentario, los signos , { } y cada directiva # entera, la
  de su linea. Los comentarios fuera de una cadena no son tokens. *)
function TokensDeRc(const ATexto: string): TArray<TTokRc>;
var
  I, N, Linea, Ini, LineaIni: Integer;
  AlEmpezar: Boolean;
  C: Char;
  S: string;
  L: TList<TTokRc>;

  procedure Pon(AClase: TClaseTokRc; const AToken: string; ALinea: Integer);
  var
    T: TTokRc;
  begin
    T.Clase := AClase;
    T.Texto := AToken;
    T.Linea := ALinea;
    L.Add(T);
  end;

  function Comentario(K: Integer): Boolean;
  begin
    Result := (ATexto[K] = '/') and (K < N) and CharInSet(ATexto[K + 1], ['/', '*']);
  end;

begin
  L := TList<TTokRc>.Create;
  try
    I := 1;
    N := Length(ATexto);
    Linea := 1;
    AlEmpezar := True; // al principio de una linea: una # ahi es una directiva
    while I <= N do
    begin
      C := ATexto[I];
      if C = #10 then
      begin
        Inc(Linea);
        AlEmpezar := True;
        Inc(I);
        Continue;
      end;
      if CharInSet(C, [#9, #11, #12, #13, ' ']) then
      begin
        Inc(I);
        Continue;
      end;
      if Comentario(I) then
      begin
        if ATexto[I + 1] = '/' then
          while (I <= N) and (ATexto[I] <> #10) do
            Inc(I)
        else
        begin
          Inc(I, 2);
          while (I <= N) and not ((ATexto[I] = '*') and (I < N) and (ATexto[I + 1] = '/')) do
          begin
            if ATexto[I] = #10 then
            begin
              Inc(Linea);
              AlEmpezar := True;
            end;
            Inc(I);
          end;
          Inc(I, 2);
        end;
        Continue;
      end;
      if (C = '#') and AlEmpezar then
      begin
        Ini := I;
        while (I <= N) and not CharInSet(ATexto[I], [#10, #13]) do
          Inc(I);
        Pon(ctrDirectiva, Copy(ATexto, Ini, I - Ini).Trim, Linea);
        Continue;
      end;
      AlEmpezar := False;
      if C = '"' then
      begin
        LineaIni := Linea;
        S := '';
        Inc(I);
        while I <= N do
        begin
          if ATexto[I] = '"' then
          begin
            if (I < N) and (ATexto[I + 1] = '"') then
            begin
              S := S + '"';
              Inc(I, 2);
              Continue;
            end;
            Break;
          end;
          if ATexto[I] = #10 then
            Inc(Linea);
          S := S + ATexto[I];
          Inc(I);
        end;
        Inc(I); // su comilla de cierre
        Pon(ctrCadena, S, LineaIni);
        Continue;
      end;
      if CharInSet(C, [',', '{', '}']) then
      begin
        Pon(ctrSigno, C, Linea);
        Inc(I);
        Continue;
      end;
      Ini := I;
      while (I <= N) and not CharInSet(ATexto[I], [#9, #10, #11, #12, #13, ' ', ',', '{', '}', '"']) and
        not Comentario(I) do
        Inc(I);
      Pon(ctrPalabra, Copy(ATexto, Ini, I - Ini), Linea);
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

// lo que tiene forma de ruta: con una barra, una unidad o una extension
function PareceRutaDeRc(const AToken: string): Boolean;
var
  Punto: Integer;
begin
  if AToken.Contains('\') or AToken.Contains('/') or ((AToken.Length > 1) and (AToken[2] = ':')) then
    Exit(True);
  Punto := AToken.LastIndexOf('.');
  Result := not AToken.Contains(' ') and (Punto > 0) and (Punto < AToken.Length - 1);
end;

function LeeRc(const ATexto: string): TLecturaRc;
var
  T: TArray<TTokRc>;
  I, J: Integer;
  Lectura: TLecturaRc;
  Macros: TArray<string>;

  function Es(K: Integer; const APalabra: string): Boolean;
  begin
    Result := (K <= High(T)) and (T[K].Clase = ctrPalabra) and SameText(T[K].Texto, APalabra);
  end;

  function Signo(K: Integer; const ASigno: string): Boolean;
  begin
    Result := (K <= High(T)) and (T[K].Clase = ctrSigno) and (T[K].Texto = ASigno);
  end;

  function Abre(K: Integer): Boolean;
  begin
    Result := Es(K, 'BEGIN') or Signo(K, '{');
  end;

  // desde K, lo de antes de su BEGIN y el bloque entero, con los de dentro:
  // la K de detras de su END
  function SaltaBloque(K: Integer): Integer;
  var
    Nivel: Integer;
  begin
    while (K <= High(T)) and not Abre(K) do
      Inc(K);
    Nivel := 0;
    while K <= High(T) do
    begin
      if Abre(K) then
        Inc(Nivel)
      else if Es(K, 'END') or Signo(K, '}') then
        Dec(Nivel);
      Inc(K);
      if Nivel <= 0 then
        Break;
    end;
    Result := K;
  end;

  procedure Entrada(AClase: TClaseRc; ALinea: Integer; const ANombre, ATipo, AFichero: string;
    APorMacro: Boolean = False);
  var
    E: TEntradaRc;
  begin
    E.Clase := AClase;
    E.Linea := ALinea;
    E.Nombre := ANombre;
    E.Tipo := ATipo;
    E.Fichero := AFichero;
    E.PorMacro := APorMacro;
    Lectura.Entradas := Lectura.Entradas + [E];
  end;

begin
  Lectura := Default(TLecturaRc);
  T := TokensDeRc(ATexto);
  I := 0;
  while I <= High(T) do
  begin
    if T[I].Clase = ctrDirectiva then
    begin
      // '#include "x"', '#include <x>' (con -x, de su carpeta), '# include'; lo
      // demas del preprocesador (#define, #if, #pragma) no se sigue aqui, pero
      // lo que nombra (#define F "C:\...") lo juzga la puerta igual (H1 de la
      // 1.20.2). brcc32 expande una macro en el fichero de un recurso
      // (X RCDATA F), no en un #include ni en un RCINCLUDE (medido)
      var D := T[I].Texto.Substring(1).TrimLeft;
      if D.StartsWith('include', True) then
      begin
        // el fichero, por los tokens: una cadena sin sus comillas, un <x> sin
        // los picos, y un comentario detras no es parte de el ('#include "x"
        // // c' se negaba con STYLE-025; revisor de la 1.20.2)
        var Toks := TokensDeRc(D.Substring(7));
        var F := '';
        if Length(Toks) > 0 then
          F := Toks[0].Texto;
        if (F.Length >= 2) and (F[1] = '<') and F.EndsWith('>') then
          F := Copy(F, 2, F.Length - 2);
        Entrada(crInclude, T[I].Linea, '', '#include', F);
      end
      else
      begin
        var Toks := TokensDeRc(D);
        for var Tok in Toks do
          if (Tok.Clase <> ctrSigno) and PareceRutaDeRc(Tok.Texto) then
            Lectura.Rutas := Lectura.Rutas + [Tok.Texto];
        if (Length(Toks) > 1) and SameText(Toks[0].Texto, 'define') then
          Macros := Macros + [PrimerTrozo(Toks[1].Texto, ['('])]; // F de F(a, b)
      end;
      Inc(I);
      Continue;
    end;
    if T[I].Clase = ctrSigno then
    begin
      // un bloque suelto, o la coma de un LANGUAGE x, y
      if Abre(I) then
        I := SaltaBloque(I)
      else
        Inc(I);
      Continue;
    end;
    if Es(I, 'RCINCLUDE') then
    begin
      if I < High(T) then
        Entrada(crInclude, T[I].Linea, '', 'RCINCLUDE', T[I + 1].Texto);
      Inc(I, 2);
      Continue;
    end;
    // los que no nombran ningun fichero: LANGUAGE p, s; VERSION n;
    // CHARACTERISTICS n; STRINGTABLE [banderas] y su bloque
    if Es(I, 'LANGUAGE') then
    begin
      Inc(I, 2);
      while Signo(I, ',') do
        Inc(I, 2);
      Continue;
    end;
    if Es(I, 'VERSION') or Es(I, 'CHARACTERISTICS') then
    begin
      Inc(I, 2);
      Continue;
    end;
    if Es(I, 'STRINGTABLE') then
    begin
      I := SaltaBloque(I + 1);
      Continue;
    end;
    // NOMBRE TIPO [banderas] FICHERO, o un recurso de bloque
    if I = High(T) then
      Break;
    J := I + 2;
    while (J <= High(T)) and (T[J].Clase = ctrPalabra) and MatchText(T[J].Texto, BANDERAS_RC) do
      Inc(J);
    if MatchText(T[I + 1].Texto, TIPOS_DE_BLOQUE_RC) or Abre(J) then
    begin
      I := SaltaBloque(J);
      Continue;
    end;
    if J > High(T) then
      Break;
    Entrada(crRecurso, T[I].Linea, T[I].Texto, T[I + 1].Texto, T[J].Texto,
      (T[J].Clase = ctrPalabra) and (IndexStr(T[J].Texto, Macros) >= 0));
    I := J + 1;
  end;
  for var E in Lectura.Entradas do
    Lectura.Rutas := Lectura.Rutas + [E.Fichero];
  for var K := 0 to High(T) do
    if (T[K].Clase in [ctrCadena, ctrPalabra]) and PareceRutaDeRc(T[K].Texto) then
      Lectura.Rutas := Lectura.Rutas + [T[K].Texto];
  Result := Lectura;
end;

end.
