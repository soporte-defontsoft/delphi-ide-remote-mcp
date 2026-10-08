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
    Clave: string;        // object | inherited | inline (Lsp.DesignerBin.LineaDeObjeto)
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
    function Clasificadas: TArray<TLineaForm>;
    procedure Parse;
    constructor CreateVacio;
  public
    constructor Create(const APath: string);
    { A document from a TEXT with no file behind it (the DUnitX tests of
      Lsp.DesignerEdit): it reads like any other; Save has nowhere to go. }
    class function DeTexto(const AText: string): TStyleDoc;
    destructor Destroy; override;
    property Root: TStyleObj read FRoot;
    property Lines: TArray<string> read FLines;
    property Path: string read FPath;
    { True si el fichero en disco es un .dfm BINARIO leido al vuelo como texto
      (Lsp.DesignerBin): se lee entero, no se guarda (ver Save). }
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
    function SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string; overload;
    { The same with a value in pieces, as the IDE writes a long string
      (Lsp.DesignerBin.TrozosDeLiteral): one piece on the property's line,
      several below it. Returns the property's line. }
    function SetProp(AObj: TStyleObj; const AProp: string; const ATrozos: TArray<string>;
      out AWasThere: Boolean): string; overload;
    { Removes a property line of AObj; False when absent. }
    function DeleteProp(AObj: TStyleObj; const AProp: string): Boolean;
    { Copies ASrc right after itself with the new StyleName. }
    procedure CloneStyle(ASrc: TStyleObj; const ANewName: string);
    { The lines AProp's value takes at AObj's own level (0-based, AIni..AFin:
      a list, a binary block, a collection or a string split with '+' run
      over several); False when absent. What SetProp and DeleteProp replace. }
    function PropLines(AObj: TStyleObj; const AProp: string; out AIni, AFin: Integer): Boolean;
    { The object named AName at any depth (a form's component, by its Name;
      the same identifier as dcc sees it); nil when there is none. }
    function ObjetoDeNombre(const AName: string): TStyleObj;
    { The file text these lines would make, with the file's own line break:
      what Save writes. A caller that writes several files at once
      (delphi_designer insert/delete: the form and its unit, all or
      nothing) composes with it and writes with PatchSaveText + Encoding. }
    function TextoDe(const ALines: TArray<string>): string;
    { Replaces every line (an edit composed outside); Save or TextoDe next. }
    procedure SetLines(const ALines: TArray<string>);
    property Encoding: string read FEnc;
    { Removes a whole object, its block object..end: a top-level style, or a
      component of a form with everything inside it. }
    procedure DeleteStyle(AObj: TStyleObj);
    procedure Save;
    { Re-parses after an edit (line numbers moved). }
    procedure Reload;
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

{ StyleNames of the Windows platform default style, extracted once through the
  helper and cached under LOCALAPPDATA. Empty when the helper is missing. }
function PlatformDefaultStyleNames: TArray<string>;

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
  Lsp.Texts,
  Lsp.Casa,
  Lsp.Mascara;

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
    if SameText(C.StyleName, AName) or (SameText(C.ObjName, AName) and (C.ObjName <> '')) then
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
  Result.Parse;
end;

destructor TStyleDoc.Destroy;
begin
  FRoot.Free;
  inherited;
end;

procedure TStyleDoc.Reload;
var
  Text, Err: string;
begin
  FreeAndNil(FRoot);
  // Un .dfm BINARIO se lee al vuelo como texto (la conversion del IDE) y se
  // recuerda: Save lo rechaza, que guardar texto sobre un binario sin decirlo
  // es cambiarle el formato a escondidas; to-text lo hace a la vista.
  FBinaryOnDisk := IsBinaryDesignerFile(FPath);
  if FBinaryOnDisk then
  begin
    Err := DesignerFileToText(FPath, Text);
    if Err <> '' then
      raise Exception.Create(Err);
    FEnc := 'binario';
  end
  else
    Text := PatchLoadText(FPath, FEnc);
  FEol := SaltoDominante(Text);
  FLines := SplitToLines(Text); // el troceador de todos: un CR suelto es salto
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
    if SameText(O.StyleName, AStyleName) then
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
function RangoDePropiedad(AObj: TStyleObj; const AForm: TArray<TLineaForm>;
  const AProp: string; out AIni, AFin: Integer): Boolean;
var
  I, Stop: Integer;
begin
  Result := False;
  AIni := -1;
  AFin := -1;
  Stop := AObj.EndLine - 1;
  if AObj.Children.Count > 0 then
    Stop := AObj.Children[0].StartLine - 1;
  for I := AObj.StartLine to Min(Stop, Length(AForm)) - 1 do
    if (AForm[I].Clase = clfPropiedad) and (AForm[I].Coleccion = 0) and
       SameText(AForm[I].Prop, AProp) then
    begin
      AIni := I;
      AFin := AForm[I].Fin;
      Exit(True);
    end;
end;

function TStyleDoc.SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string;
begin
  Result := SetProp(AObj, AProp, [AValue], AWasThere);
end;

function TStyleDoc.SetProp(AObj: TStyleObj; const AProp: string; const ATrozos: TArray<string>;
  out AWasThere: Boolean): string;
var
  Ini, Fin, InsertAt: Integer;
  Sangria: string;
  Nuevas: TArray<string>;
  L: TList<string>;
begin
  AWasThere := RangoDePropiedad(AObj, Clasificadas, AProp, Ini, Fin);
  // la sangria de la casa de esa linea (Lsp.Patch); la del nivel si es nueva
  if AWasThere then
    Sangria := LeadingWhite(FLines[Ini])
  else
    Sangria := StringOfChar(' ', (AObj.Depth + 1) * 2);
  Nuevas := LineasDePropiedad(Sangria, AProp, ATrozos);
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    if AWasThere then
    begin
      // el valor entero fuera, el nuevo con sus lineas
      L.DeleteRange(Ini, Fin - Ini + 1);
      L.InsertRange(Ini, Nuevas);
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
  Ini, Fin: Integer;
  L: TList<string>;
begin
  Result := RangoDePropiedad(AObj, Clasificadas, AProp, Ini, Fin);
  if not Result then
    Exit;
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    L.DeleteRange(Ini, Fin - Ini + 1);
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
    Nuevas := LineasDePropiedad(StringOfChar(' ', (ASrc.Depth + 1) * 2), 'StyleName',
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

procedure TStyleDoc.Save;
begin
  if FBinaryOnDisk then
    raise Exception.Create(MsgFmt(SR_STYLE_BINARIO_NO_SE_GUARDA_FMT, [TPath.GetFileName(FPath)]));
  PatchSaveText(FPath, TextoDe(FLines), FEnc);
  Reload;
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
    CharInSet(V[1], ['{', '(']));                              // binary / list block
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
  Result := (B[0] = $FF) or (TEncoding.ANSI.GetString(B).StartsWith('FMX_STYLE'));
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

function StyleConverterExe: string;
begin
  Result := ServerDir('DelphiStyleConvert.exe');
  if not TFile.Exists(Result) then
    Result := '';
end;

function PlatformDefaultStyleNames: TArray<string>;
var
  Cache, Exe, Enc: string;
  Code: Cardinal;
  M: TMatch;
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
    for M in TRegEx.Matches(PatchLoadText(Cache, Enc), 'StyleName\s*=\s*''([^'']+)''', [roIgnoreCase]) do
      L.Add(M.Groups[1].Value.ToLower);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
