unit Mcp.Tools.Designer;

{ delphi_designer, phase 1 (READ + LINT): structured answers about forms and
  components, so an agent never guesses what a .dfm/.fmx may contain.

    info  <class>            what the framework really publishes for a class
                             (properties with kind and type, events apart) -
                             straight from the tables the designer lint
                             already uses, read from the active Delphi's own
                             source (Lsp.DesignerMetaGen: the framework
                             describing itself, nothing hand-written).
    prop  <class> <prop>     one property in detail: type, kind, and the
                             legal members when it is an enum or a set.
    tree  <file>             the component tree of a TEXT .dfm/.fmx
                             (name, class, line, children).
    get   <file> <component> one component's block, verbatim.
    lint  <file>             the designer lint on demand: unknown classes,
                             properties the class does not publish, enum
                             values that do not exist.
    preview <file>           a PNG of what the IDE designer shows, drawn by
                             the form renderers of src\Render (Lsp.FormRender)
                             in a process of their own (RenderForm, 1.17.0).

  A binary .dfm is READ on the fly as text (Lsp.DesignerBin, the IDE's own
  conversion) and every answer says so; to-text / to-binary convert it on
  disk, backup first (David, 2026-09-24, after a legacy form left an agent
  blind). Editing commands (set-property, add-component, bind-event) are
  phase 2, and will go through delphi_changeset. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiDesignerParams = class
  private
    FCommand: string;
    FPath: string;
    FClass_: string;
    FProp: string;
    FComponent: string;
    FUnit_: string;
    FFramework: string;
    FFilter: string;
    FMaxDepth: Integer;
    FState: string;
    FStyle: string;
    FNonVisual: Boolean;
    FInline: Boolean;
    FMaxWidth: Integer;
    FOut: string;
    FParent: string;
    FValue: string;
    FProps: string;
    FBefore: string;
    FAfter: string;
    FIndex: Integer;
  public
    // inline es Boolean en el esquema y vale true si no llega (6.5 de la
    // 1.18.0): el serializador crea los params con T.Create, que llama a este
    // constructor (medido); 'true'/'false' como texto los sigue leyendo
    constructor Create;
    [SchemaDescription(SP_DESIGNER_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_DESIGNER_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_DESIGNER_CLASS)]
    property ClassName_: string read FClass_ write FClass_;
    [SchemaDescription(SP_DESIGNER_PROP)]
    property Prop: string read FProp write FProp;
    [SchemaDescription(SP_DESIGNER_COMPONENT)]
    property Component: string read FComponent write FComponent;
    [SchemaDescription(SP_DESIGNER_UNIT)]
    property Unit_: string read FUnit_ write FUnit_;
    [SchemaDescription(SP_DESIGNER_FRAMEWORK)]
    property Framework: string read FFramework write FFramework;
    [SchemaDescription(SP_DESIGNER_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_DESIGNER_MAXDEPTH)]
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    [SchemaDescription(SP_DESIGNER_STATE)]
    [Contenido] // el disenador expande cada valor (PonEnMemoria y el state de preview)
    property State: string read FState write FState;
    // un fichero .vsf/.style del servidor, o el NOMBRE de una plataforma del
    // designer (android, none...): la tool explica un valor relativo
    [SchemaDescription(SP_DESIGNER_STYLE)]
    [RutaDelServidor]
    [RutaRelativa]
    property Style: string read FStyle write FStyle;
    [SchemaDescription(SP_DESIGNER_NONVISUAL)]
    property NonVisual: Boolean read FNonVisual write FNonVisual;
    [SchemaDescription(SP_CAPTURE_INLINE)]
    property Inline_: Boolean read FInline write FInline;
    [SchemaDescription(SP_CAPTURE_MAXWIDTH)]
    property MaxWidth: Integer read FMaxWidth write FMaxWidth;
    [SchemaDescription(SP_DESIGNER_OUT)]
    [RutaDelServidor]
    property Out_: string read FOut write FOut;
    [SchemaDescription(SP_DESIGNER_PARENT)]
    property Parent: string read FParent write FParent;
    [SchemaDescription(SP_DESIGNER_VALUE)]
    [Contenido]
    property Value: string read FValue write FValue;
    [SchemaDescription(SP_DESIGNER_PROPS)]
    [Contenido]
    property Props: string read FProps write FProps;
    [SchemaDescription(SP_DESIGNER_BEFORE)]
    property Before: string read FBefore write FBefore;
    [SchemaDescription(SP_DESIGNER_AFTER)]
    property After: string read FAfter write FAfter;
    [SchemaDescription(SP_DESIGNER_INDEX)]
    property Index: Integer read FIndex write FIndex;
  end;

  TDelphiDesignerTool = class(TMCPToolBase<TDelphiDesignerParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDesignerParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.RegularExpressions,
  System.Generics.Collections,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.Codificacion, // DecodeBytes y TEncKind: el form ya leido, en su codificacion
  Lsp.Styles,
  Lsp.DesignerMeta,
  Lsp.DesignerBin,
  Lsp.DesignerForma, // DesignerShapeOf: la forma del fichero
  Lsp.DesignerBinding,
  Lsp.DesignerMetaGen,
  Lsp.Pascal,
  Lsp.Discovery,     // DiscoverRadStudio: la version del Delphi del servidor
  Lsp.FormRender,    // preview: el renderizador y su protocolo
  Lsp.Imagen,        // RecortaPng: el recorte al componente, en el servidor
  Lsp.InlineImages,  // DeliverCapture: como se entrega una captura
  Lsp.DesignerEdit,  // insert / set / delete: el form y su unidad, como el IDE
  Lsp.Json,          // ObjetoJson: la respuesta de layout, para el aviso de fuera del padre
  Lsp.Rutas,
  Lsp.Mascara;

const
  MAX_PROPS = 400;

function KindWord(K: Char): string;
begin
  case K of
    'c': Result := 'class';
    'e': Result := 'enum';
    's': Result := 'set';
    'm': Result := 'event';
    'r': Result := 'record';
    '?': Result := 'unknown'; // un tipo que el fuente no deja leer
  else
    Result := 'simple';
  end;
end;

{ vcl | fmx from the explicit param or the file extension; '' = undecidable. }
function ResolveFramework(const AParam, APath: string): string;
begin
  Result := AParam.Trim.ToLower;
  if MatchText(Result, ['vcl', 'fmx']) then
    Exit;
  if Result <> '' then
    Exit('?');
  if EsDesignerFmx(APath) then
    Exit('fmx');
  if APath.EndsWith('.dfm', True) then
    Exit('vcl');
  Result := '';
end;

// (ClaseQueNoEsta vive en Lsp.DesignerMeta desde la 1.17.0: el insert de
// Lsp.DesignerEdit dice lo mismo de una clase que no esta)

function MetaClassInfo(const AFramework, AClass, AFilter: string): string;
var
  M: TMetaTable;
  Ret, PObj: TJSONObject;
  PArr, EArr: TJSONArray;
  Key, Cls, ClsId, PName: string;
  Falta: TFaltaTabla;
  R: TPropRec;
  Names: TStringList;
  N, Shown: Integer;
begin
  M := MetaTable(AFramework = 'fmx', Falta);
  if M = nil then
    Exit(Falta.Negativa); // sin fuente, generandose o fallida: lo dice ella
  // por su nombre o por su identidad con la unidad (dos unidades pueden
  // tener una clase con el mismo nombre)
  if not M.ClaseDeNombre(AClass, ClsId) then
    Exit(ClaseQueNoEsta(M, AClass, AFramework));
  Cls := M.Classes[ClsId];
  Ret := TJSONObject.Create;
  Names := TStringList.Create;
  try
    Ret.AddPair('class', Cls);
    if EsIdDeTipo(ClsId) then
      Ret.AddPair('unit', UnidadDeIdDeTipo(M.IdEscrito[ClsId]));
    Ret.AddPair('framework', UpperCase(AFramework));
    PArr := TJSONArray.Create;
    EArr := TJSONArray.Create;
    Ret.AddPair('properties', PArr);
    Ret.AddPair('events', EArr);
    for Key in M.Props.Keys do
      if Key.StartsWith(ClaveProp(ClsId, '')) then
        Names.Add(Key);
    Names.Sort;
    N := 0;
    Shown := 0;
    for Key in Names do
    begin
      R := M.Props[Key];
      PName := R.Name;
      if (AFilter <> '') and not ContainsText(PName, AFilter) then
        Continue;
      Inc(N);
      if Shown >= MAX_PROPS then
        Continue;
      Inc(Shown);
      if R.Kind = 'm' then
        EArr.Add(PName + ': ' + R.TypeName)
      else
      begin
        PObj := TJSONObject.Create;
        PArr.AddElement(PObj);
        PObj.AddPair('name', PName);
        PObj.AddPair('kind', KindWord(R.Kind));
        PObj.AddPair('type', R.TypeName);
      end;
    end;
    Ret.AddPair('total', TJSONNumber.Create(N));
    // lo que guarda por codigo (DefineProperties) tambien va al form, sin
    // publicarse: Left/Top de un no visual, los Explicit*, TextHeight...
    var Def := M.DefinidasDeLaCadena(ClsId);
    if Length(Def) > 0 then
    begin
      var DArr := TJSONArray.Create;
      for var D in Def do
        DArr.Add(D);
      Ret.AddPair('definedByCode', DArr);
    end;
    // una clase que no publica nada pero tiene descendientes (TTextSettings):
    // la instancia de una propiedad de ese tipo es una descendiente que elige
    // el codigo, y lo que hay que escribir es lo que publican ellas (sin esto
    // el agente leia "0 propiedades, no escribas nada": revision de la 1.12.0)
    if (Names.Count = 0) and M.Hijas.ContainsKey(ClsId) then
    begin
      Ret.AddPair('descendantsPublish', M.PublicadasDeLaFamilia(ClsId));
      Ret.AddPair('descendantsNote', MsgFmt(SN_DESIGNER_INFO_FAMILIA_FMT, [Cls]));
    end;
    // un filtro sin resultado lo dice (DSGN-048): total:0 a secas se leia
    // como un fallo de RTTI (Hermes, 28-sep-2026)
    if (AFilter <> '') and (N = 0) then
    begin
      var Pista := MsgFmt(SN_DESIGNER_INFO_FILTRO_VACIO_FMT, [Cls, AFilter, Names.Count]);
      if (AFramework = 'fmx') and ContainsText(AFilter, 'font') then
        Pista := Pista + MsgText(SF_DESIGNER_FUENTE_FMX);
      Ret.AddPair('hint', Pista);
    end;
    if N > Shown then
    begin
      Ret.AddPair('truncated', TJSONBool.Create(True));
      Ret.AddPair('hint', MsgText(SN_DESIGNER_INFO_TRUNCATED));
    end;
    Ret.AddPair('note', MsgText(SN_DESIGNER_INFO_NOTE));
    Result := Ret.ToJSON;
  finally
    Names.Free;
    Ret.Free;
  end;
end;

function PropInfo(const AFramework, AClass, AProp: string): string;
var
  M: TMetaTable;
  R: TPropRec;
  Ret: TJSONObject;
  Cls, ClsId, Members: string;
  Falta: TFaltaTabla;
begin
  M := MetaTable(AFramework = 'fmx', Falta);
  if M = nil then
    Exit(Falta.Negativa);
  if not M.ClaseDeNombre(AClass, ClsId) then
    Exit(ClaseQueNoEsta(M, AClass, AFramework));
  Cls := M.Classes[ClsId];
  if not M.Props.TryGetValue(ClaveProp(ClsId, AProp.Trim), R) then
    Exit(MsgFmt(SR_DESIGNER_PROP_FMT, [AProp, Cls]));
  Ret := TJSONObject.Create;
  try
    Ret.AddPair('class', Cls);
    Ret.AddPair('property', AProp.Trim);
    Ret.AddPair('kind', KindWord(R.Kind));
    Ret.AddPair('type', R.TypeName);
    // Enums had their members; SETS did not, though the description promised
    // "the legal members when it is an enum/set" and lint could already name
    // them (field round 8).
    if M.EnumShow.TryGetValue(ClaveDeIdentificador(R.TypeId), Members) or
       M.SetShow.TryGetValue(ClaveDeIdentificador(R.TypeId), Members) then
      Ret.AddPair('members', Members);
    if R.Kind = 's' then
      Ret.AddPair('membersNote', MsgText(SN_DESIGNER_SET_NOTE));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

function IsBinaryDesigner(const APath: string): Boolean;
begin
  // El nombrador de la forma vive en Lsp.DesignerBin (antes, cuatro copias de
  // la regla de los bytes: aqui, Lsp.Patch, Lsp.ProjectUnits y upload).
  Result := IsBinaryDesignerFile(APath);
end;

function LoadDoc(const APath: string; out ADoc: TStyleDoc): string;
begin
  Result := ReadPathDenied(APath); // looking at a form is reading
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_NO_EXISTE_FMT, [APath])));
  if not EsRutaDeDesigner(APath) then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  // Un binario se lee al vuelo (TStyleDoc lo convierte); solo uno danado
  // sigue siendo un rechazo, con el motivo de la RTL.
  try
    ADoc := TStyleDoc.Create(APath);
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_DESIGNER_ILEGIBLE_FMT, E.Message, [APath, E.Message]));
  end;
end;

{ Las propiedades que el lector se salto en un preview, como objetos que
  guian: el componente, la propiedad, el motivo de TReader y su linea en el
  form - la localiza el servidor, que el renderizador no sabe lineas (en un
  binario, la del texto que ensenan delphi_read y get) -. Una que no esta en
  este fichero (de un ancestro, de un frame) va sin linea; lo que no casa con
  la forma de TReader, como texto (David, 7-oct-2026). }
function IgnoradasConLinea(const ARuta: string; const AIgnoradas: TArray<TIgnorada>): TJSONArray;
var
  Doc: TStyleDoc;
  Obj: TStyleObj;
  Ini, Fin: Integer;
begin
  Result := TJSONArray.Create;
  if LoadDoc(ARuta, Doc) <> '' then
    Doc := nil;
  try
    for var I in AIgnoradas do
    begin
      var Uno := TJSONObject.Create;
      Result.Add(Uno);
      if I.Componente = '' then
      begin
        Uno.AddPair('text', I.Texto);
        Continue;
      end;
      Uno.AddPair('component', I.Componente);
      Uno.AddPair('property', I.Propiedad);
      Uno.AddPair('reason', I.Motivo);
      if Doc = nil then
        Continue;
      Obj := Doc.ObjetoDeNombre(I.Componente);
      if (Obj <> nil) and Doc.PropLines(Obj, I.Propiedad, Ini, Fin) then
        Uno.AddPair('line', TJSONNumber.Create(Ini + 1));
    end;
  finally
    Doc.Free;
  end;
end;

{ AMaxDepth: los niveles que se ensenan (1 = solo el form; 0 = todos); un
  objeto del ultimo nivel dice cuantos hijos tiene en vez de ensenarlos }
function TreeOf(const APath: string; AMaxDepth: Integer): string;
var
  Doc: TStyleDoc;
  Ret: TJSONObject;
  Cortados: Integer;

  function NodeJson(O: TStyleObj; ANivel: Integer): TJSONObject;
  var
    Kids: TJSONArray;
    K: TStyleObj;
  begin
    Result := TJSONObject.Create;
    if O.ObjName <> '' then
      Result.AddPair('name', O.ObjName);
    Result.AddPair('class', O.ClassName_);
    Result.AddPair('line', TJSONNumber.Create(O.StartLine));
    if O.Children.Count > 0 then
    begin
      if (AMaxDepth > 0) and (ANivel >= AMaxDepth) then
      begin
        Result.AddPair('childrenCount', TJSONNumber.Create(O.Children.Count));
        Inc(Cortados);
        Exit;
      end;
      Kids := TJSONArray.Create;
      Result.AddPair('children', Kids);
      for K in O.Children do
        Kids.AddElement(NodeJson(K, ANivel + 1));
    end;
  end;

begin
  Doc := nil;
  Result := LoadDoc(APath, Doc);
  if Result <> '' then
    Exit;
  try
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('file', APath);
      Cortados := 0;
      if Doc.Root <> nil then
        Ret.AddPair('root', NodeJson(Doc.Root, 1))
      else
        Ret.AddPair('root', TJSONNull.Create);
      Ret.AddPair('note', MsgText(SN_DESIGNER_TREE_NOTE));
      if Cortados > 0 then
        Ret.AddPair('maxDepthNote', MsgFmt(SN_DESIGNER_TREE_MAXDEPTH_FMT, [AMaxDepth, Cortados]));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    Doc.Free;
  end;
end;

// (FindByName es TStyleDoc.ObjetoDeNombre desde la 1.17.0: insert, set y
// delete de Lsp.DesignerEdit buscan igual)

function GetComponent(const APath, AName: string): string;
var
  Doc: TStyleDoc;
  O: TStyleObj;
begin
  Doc := nil;
  Result := LoadDoc(APath, Doc);
  if Result <> '' then
    Exit;
  try
    if Doc.Root = nil then
      Exit(MsgText(SR_DESIGNER_EMPTY));
    O := Doc.ObjetoDeNombre(AName.Trim);
    if O = nil then
      Exit(MsgFmt(SR_DESIGNER_COMPONENT_FMT, [AName]));
    Result := MsgFmt(SF_DSGN_BLOQUE_LINEAS_FMT,
      [O.ObjName, O.ClassName_, O.StartLine, O.EndLine,
       TPath.GetFileName(APath), Doc.BlockText(O)]);
  finally
    Doc.Free;
  end;
end;

// Does the FORM agree with its CLASS? The compiler never asks: a component in
// the .dfm with no published field, or an event naming a method that is not
// published, builds perfectly and then throws at form-load, on a machine where
// nobody can see it.
//
// Rewritten 2026-08-25 after a probe agent built a real VCL form (nested
// panels, a grid, a status bar, a popup menu, an inline frame, ten handlers)
// and took the first version apart: it read the whole .pas instead of the
// form's own class, so a second class in the same unit silently vouched for
// components that did not exist; it accepted a handler declared private, which
// is the exact runtime failure it promises to catch (TReader.FindMethod goes
// through MethodAddress, and that only sees PUBLISHED methods); it called
// every inherited member of a form whose ancestor lives in another unit
// missing; and it read whatever the "unit" parameter pointed at, jail or no
// jail.
//
// Read as text on purpose: it has to work on a form that does not compile yet,
// which is exactly when you need it.
function CheckBinding(const ADfm, APas: string): string;
begin
  // El informe vive en el motor (Lsp.DesignerBinding) desde el 25-sep-2026:
  // lo comparten check-binding, el lint y la escritura de un designer.
  // Aqui solo la jaula del SEGUNDO path: "path" ya paso por ella y este no,
  // asi que "unit" leia cualquier .pas de la maquina. Una segunda ruta es
  // una segunda puerta.
  if APas <> '' then
  begin
    Result := ReadPathDenied(APas);
    if Result <> '' then
      Exit;
    if not MatchText(TPath.GetExtension(APas), ['.pas']) then
      Exit(MsgText(SR_DESIGNER_BINDING_UNIT_EXT));
  end;
  Result := DesignerBindingJson(ADfm, APas);
end;

{ One property of ONE object, ignoring the properties of its children: EL
  lector del valor (TStyleDoc.ValorDe, Lsp.Styles). Hasta la 1.18.0 lo leia
  aqui una regex propia, que tomaba por propiedad del objeto el 'Caption =' de
  un item de coleccion y daba solo la primera linea de una cadena partida. }
function PropRaw(ADoc: TStyleDoc; AObj: TStyleObj; const AName: string;
  out AFound: Boolean): string;
begin
  Result := ADoc.ValorDe(AObj, AName, AFound);
end;

function PropInt(ADoc: TStyleDoc; AObj: TStyleObj; const AName: string;
  ADefault: Integer; out AFound: Boolean): Integer;
var
  S: string;
begin
  S := PropRaw(ADoc, AObj, AName, AFound);
  if not AFound or not TryStrToInt(S, Result) then
  begin
    Result := ADefault;
    if not TryStrToInt(S, ADefault) then
      AFound := AFound and False;
  end;
end;

{ Well-known VCL controls whose Align is not written in the .dfm because it is
  their default. Getting a form right "blind" is exactly the case that fails
  without this: a TStatusBar/TToolBar/TMemo trio is three disjoint bands, not a
  pile. }
function DefaultAlign(const ACls: string): string;
begin
  if MatchText(ACls, ['TStatusBar']) then Exit('alBottom');
  if MatchText(ACls, ['TToolBar', 'TCoolBar', 'TControlBar', 'THeaderControl']) then
    Exit('alTop');
  if MatchText(ACls, ['TSplitter']) then Exit('alLeft');
  if MatchText(ACls, ['TTabSheet']) then Exit('alClient');
  if MatchText(ACls, ['TCategoryPanel']) then Exit('alTop');
  Result := 'alNone';
end;

{ Graphic, non-focusable decoration: a TBevel frame AROUND a group, a TShape or
  TImage behind it. Overlapping one is normal design, not "one hides the other". }
function IsDecoration(const ACls: string): Boolean;
begin
  Result := MatchText(ACls, ['TBevel', 'TShape', 'TImage', 'TPaintBox']);
end;

{ Containers whose children are MEANT to be larger than the visible area: what
  spills is reached by scrolling, not clipped. }
function IsScrollBox(const ACls: string): Boolean;
begin
  Result := MatchText(ACls, ['TScrollBox', 'TFramedScrollBox']);
end;

{ Grid containers place each child in a CELL by its ControlCollection, so every
  child carries Align=alClient meaning "fill your cell". Without the collection
  we cannot compute cells, so we do not judge alignment or overlap among them. }
function IsGridPanel(const ACls: string): Boolean;
begin
  Result := MatchText(ACls, ['TGridPanel', 'TGridLayout']);
end;

{ Containers that arrange their children by rules at runtime, ignoring the
  Left/Top written at design time: a TFlowPanel reflows into rows, a
  TRelativePanel places by constraints. Judging their children by design
  coordinates is a guaranteed false positive. }
function IsAutoLayout(const ACls: string): Boolean;
begin
  Result := MatchText(ACls, ['TFlowPanel', 'TRelativePanel', 'TGridLayout',
    'TFlowLayout']);
end;

{ Page containers keep every page as an alClient child and show one at a time:
  the pages "overlap 100%" by design, which is not a defect. }
function IsPageContainer(const ACls: string): Boolean;
begin
  Result := MatchText(ACls, ['TPageControl', 'TTabControl', 'TPageScroller']);
end;

{ WHERE things actually end up, which is the one thing an agent building a form
  cannot see. It has the numbers - it wrote them - but not the arithmetic that
  turns Left/Top/Width/Height plus Align into a screen, and a form that binds
  perfectly can still be a stack of controls on top of each other, a button of
  size zero, or a panel hanging off the edge of the window.

  This resolves Align close to the way TWinControl.AlignControls does - each
  aligned child eats its band off the remaining rectangle, in .dfm order (the
  VCL orders children of the same Align by their position: two alTop panels
  reordered in the file stay where their Top puts them, measured 10-oct-2026;
  the judge would be the renderer's rectangles, a proposal in the 1.18.0 list) - with
  the one subtlety a probe agent measured on 2026-08-25: alClient does NOT
  shrink the remaining rectangle, so several alClient siblings all get the WHOLE
  space and lie on top of each other (the IDE writes them with identical
  coordinates). Invisible controls are skipped, because the VCL neither lays out
  nor draws them. Grid children fill cells and are left alone. A TBevel/TShape/
  TImage is decoration and does not "cover" anyone. And the resolved rectangle
  of every control is returned in `boxes`, in form coordinates - that is the
  "where things end up" the name promises, and what lets an agent place the next
  control without seeing the screen.

  Approximate, and it says how: a container's client area is its Width/Height
  (bevels and borders shave a few pixels), a form given only Width/Height (no
  ClientWidth) has its window frame estimated at 96 dpi, and Anchors - which
  govern RESIZE - are not what this measures. VCL only; .fmx geometry (Size.Width,
  Position.Y) is a different model and is refused rather than answered wrongly. }
function LayoutOf(const APath: string): string;
type
  TBox = record
    Nm, Cls, Align: string;
    X1, Y1, X2, Y2, Line: Integer;
    HasW, HasH, Free_, Deco, Client: Boolean;
  end;
var
  Doc: TStyleDoc;
  Ret: TJSONObject;
  Zero, Outside, Overlap, NoRoom, Unknown, Boxes: TJSONArray;
  RootW, RootH, Opens, Closes, I: Integer;
  Found, Estimated: Boolean;
  TablaVcl: TMetaTable;
  FaltaVcl: TFaltaTabla;

  function Vis(AObj: TStyleObj): Boolean;
  var
    V: string;
    F2: Boolean;
  begin
    V := PropRaw(Doc, AObj, 'Visible', F2);
    Result := not (F2 and SameText(V.Trim, 'False'));
  end;

  // un control segun la tabla de la VCL (si ya esta: layout no la espera): uno
  // sin Width/Height tiene el tamano de su constructor, y se saltaba como si
  // fuera un TTimer (David, 4-oct-2026: lo que deja el insert)
  function EsControl(AObj: TStyleObj): Boolean;
  var
    Id: string;
  begin
    Result := (TablaVcl <> nil) and TablaVcl.ClaseDeNombre(AObj.ClassName_, Id) and
      TablaVcl.Desciende(Id, ID_VCL_CONTROL);
  end;

  function IsVisual(AObj: TStyleObj): Boolean;
  var
    HasW, HasH: Boolean;
  begin
    PropRaw(Doc, AObj, 'Width', HasW);
    PropRaw(Doc, AObj, 'Height', HasH);
    // A TTimer/TPopupMenu/TDataSource carries only the designer icon's Left/Top
    // and no size: not on screen, nothing to check. But a container that fills
    // its parent writes no Width/Height either (a TTabSheet fills the page, a
    // TCategoryPanel takes the group's width) - it is very much on screen, and
    // skipping it hid everything inside it. Children, or a non-alNone class
    // default, give it away.
    Result := HasW or HasH or (AObj.Children.Count > 0) or
      not SameText(DefaultAlign(AObj.ClassName_), 'alNone') or EsControl(AObj);
  end;

  procedure Walk(AParent: TStyleObj; AClientW, AClientH, AAbsX, AAbsY: Integer;
    const AWhere: string; AKnown, AScroll: Boolean);
  var
    Kids: array of TBox;
    Cnt, K, J, RL, RT, RR, RB, W, H, X, Y, ClientN: Integer;
    MgnL, MgnT, MgnR, MgnB: Integer;
    Kid: TStyleObj;
    Align, Nm, Cls: string;
    HasW, HasH, HasL, HasT, AWM, IsInh, InhUnknown: Boolean;
    Grid, Managed, NeedW, NeedH: Boolean;
    ix, iy: Integer;
  begin
    Grid := IsGridPanel(AParent.ClassName_);
    // "managed" = the parent places its children itself (grid cells, flow
    // reflow, relative rules, page tabs): design Left/Top and sibling overlap
    // mean nothing there, so we do not judge them.
    Managed := Grid or IsAutoLayout(AParent.ClassName_) or
      IsPageContainer(AParent.ClassName_);
    RL := 0; RT := 0; RR := AClientW; RB := AClientH;
    ClientN := 0;
    SetLength(Kids, AParent.Children.Count);
    Cnt := 0;
    for K := 0 to AParent.Children.Count - 1 do
    begin
      Kid := AParent.Children[K];
      if not IsVisual(Kid) then Continue;
      if not Vis(Kid) then Continue;      // the VCL does not lay out the hidden
      Nm := Kid.ObjName; if Nm = '' then Nm := Kid.ClassName_;
      Cls := Kid.ClassName_;
      Align := PropRaw(Doc, Kid, 'Align', Found);
      if not Found then Align := DefaultAlign(Cls);
      W := PropInt(Doc, Kid, 'Width', -1, HasW);
      H := PropInt(Doc, Kid, 'Height', -1, HasH);
      X := PropInt(Doc, Kid, 'Left', 0, HasL);
      Y := PropInt(Doc, Kid, 'Top', 0, HasT);
      // AlignWithMargins insets an aligned control inside its band; without it
      // the resolved rectangle is off by the margin width, exactly for the
      // "place the next one" case.
      AWM := SameText(PropRaw(Doc, Kid, 'AlignWithMargins', Found).Trim, 'True');
      MgnL := 0; MgnT := 0; MgnR := 0; MgnB := 0;
      if AWM then
      begin
        MgnL := PropInt(Doc, Kid, 'Margins.Left', 3, Found);
        MgnT := PropInt(Doc, Kid, 'Margins.Top', 3, Found);
        MgnR := PropInt(Doc, Kid, 'Margins.Right', 3, Found);
        MgnB := PropInt(Doc, Kid, 'Margins.Bottom', 3, Found);
      end;
      // An inherited control takes its Align and size from the ANCESTOR form,
      // which lives in another .dfm we do not merge. If the child overrides
      // neither Align nor a full size, we cannot know where it lands - so we say
      // so once and do not invent an alNone/zero-height box for it.
      IsInh := SameText(Kid.Clave, 'inherited'); // la palabra de LineaDeObjeto
      InhUnknown := IsInh and
        (PropRaw(Doc, Kid, 'Align', Found) = '') and not (HasW and HasH);

      NeedW := MatchText(Align, ['alNone', 'alLeft', 'alRight', 'alCustom']);
      NeedH := MatchText(Align, ['alNone', 'alTop', 'alBottom', 'alCustom']);
      if not InhUnknown then
      begin
        if (HasW and (W = 0)) or (HasH and (H = 0)) then
          Zero.Add(MsgFmt(SF_DSGN_LADO_A_CERO_FMT, [Nm, Cls, Kid.StartLine,
            IfThen(HasW, IntToStr(W), '?'), IfThen(HasH, IntToStr(H), '?')]));
        if (NeedW and not HasW) or (NeedH and not HasH) then
          // un control sin tamano en el .dfm tiene el de su constructor: lo
          // que deja el insert de delphi_designer, como el IDE
          if not HasW and not HasH and SameText(Align, 'alNone') and EsControl(Kid) then
            Unknown.Add(MsgFmt(SF_DSGN_TAMANO_DEL_CONSTRUCTOR_FMT, [Nm, Cls, Kid.StartLine]))
          else
            Unknown.Add(MsgFmt(SF_DSGN_NO_LLEVA_EN_DFM_FMT, [Nm, Cls, Kid.StartLine,
              IfThen(NeedW and not HasW, 'Width', 'Height'), Align]));
      end;
      if W < 0 then W := 0;
      if H < 0 then H := 0;

      Kids[Cnt].Nm := Nm; Kids[Cnt].Cls := Cls; Kids[Cnt].Align := Align;
      Kids[Cnt].Line := Kid.StartLine; Kids[Cnt].HasW := HasW; Kids[Cnt].HasH := HasH;
      // decoration, alCustom (runtime position), and an unresolved inherited
      // control are all left OUT of overlap: none of them is "one hides another".
      Kids[Cnt].Deco := IsDecoration(Cls) or SameText(Align, 'alCustom') or InhUnknown;
      Kids[Cnt].Free_ := False;
      Kids[Cnt].Client := False;
      if InhUnknown then
        Kids[Cnt].Align := 'inherited?';

      if Grid or Managed and not (SameText(Align, 'alTop') or
        SameText(Align, 'alBottom') or SameText(Align, 'alLeft') or
        SameText(Align, 'alRight') or SameText(Align, 'alClient')) then
      begin
        // the parent places it; we record the parent rect as a placeholder and
        // do not judge it.
        Kids[Cnt].X1 := RL; Kids[Cnt].Y1 := RT; Kids[Cnt].X2 := RR; Kids[Cnt].Y2 := RB;
      end
      else if SameText(Align, 'alTop') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RT + MgnT + H;
        if AKnown and (RT + MgnT + H + MgnB > RB) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FUERA_FMT, [Nm, Kid.StartLine,
            AWhere, H, Max(0, RB - RT - MgnT)]));
        RT := Min(RB, RT + MgnT + H + MgnB);
      end
      else if SameText(Align, 'alBottom') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := Max(RT, RB - MgnB - H);
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RB - MgnB - H - MgnT < RT) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FMT, [Nm, Kid.StartLine, AWhere, H, Max(0, RB - RT - MgnB)]));
        RB := Max(RT, RB - MgnB - H - MgnT);
      end
      else if SameText(Align, 'alLeft') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RL + MgnL + W; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RL + MgnL + W + MgnR > RR) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [Nm, Kid.StartLine, AWhere, W, Max(0, RR - RL - MgnL)]));
        RL := Min(RR, RL + MgnL + W + MgnR);
      end
      else if SameText(Align, 'alRight') then
      begin
        Kids[Cnt].X1 := Max(RL, RR - MgnR - W); Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RR - MgnR - W - MgnL < RL) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [Nm, Kid.StartLine, AWhere, W, Max(0, RR - RL - MgnR)]));
        RR := Max(RL, RR - MgnR - W - MgnL);
      end
      else if SameText(Align, 'alClient') then
      begin
        // alClient does NOT consume the remaining rect: it takes ALL of it (less
        // its own margins), and so does the next alClient - two overlap 100%.
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        Kids[Cnt].Client := True;
        Inc(ClientN);
      end
      else
      begin
        // alNone / alCustom: placed by its own Left/Top.
        Kids[Cnt].X1 := X; Kids[Cnt].Y1 := Y; Kids[Cnt].X2 := X + W; Kids[Cnt].Y2 := Y + H;
        Kids[Cnt].Free_ := True;
        if AKnown and not AScroll and not Managed and not InhUnknown and
           SameText(Align, 'alNone') and
           ((X < 0) or (Y < 0) or (X + W > AClientW) or (Y + H > AClientH)) then
          Outside.Add(MsgFmt(SF_DSGN_OCUPA_SE_SALE_FMT, [Nm, Cls,
            Kid.StartLine, X, Y, X + W, Y + H, AWhere, AClientW, AClientH]));
      end;

      Inc(Cnt);
    end;

    // alClient is resolved LAST, whatever order the .dfm lists it in: it gets
    // the rectangle left after every band, not the one that happened to remain
    // when it was declared. Placing it inline made an alClient grid "overlap"
    // an alBottom panel that came after it (a false positive on a real form).
    for K := 0 to Cnt - 1 do
      if Kids[K].Client then
      begin
        Kids[K].X1 := RL; Kids[K].Y1 := RT; Kids[K].X2 := RR; Kids[K].Y2 := RB;
      end;

    // the resolved rectangle of every control, in FORM coordinates: this is the
    // "where things end up" the tool promises, and what lets an agent place the
    // next control without seeing the screen.
    for K := 0 to Cnt - 1 do
    begin
      var Bx := TJSONObject.Create;
      Bx.AddPair('name', Kids[K].Nm);
      Bx.AddPair('class', Kids[K].Cls);
      Bx.AddPair('align', Kids[K].Align);
      Bx.AddPair('parent', AWhere);
      Bx.AddPair('x', TJSONNumber.Create(AAbsX + Kids[K].X1));
      Bx.AddPair('y', TJSONNumber.Create(AAbsY + Kids[K].Y1));
      Bx.AddPair('w', TJSONNumber.Create(Kids[K].X2 - Kids[K].X1));
      Bx.AddPair('h', TJSONNumber.Create(Kids[K].Y2 - Kids[K].Y1));
      Bx.AddPair('line', TJSONNumber.Create(Kids[K].Line));
      Boxes.AddElement(Bx);
    end;

    // overlap: any two whose rectangles share area, decoration/alCustom/
    // inherited excluded. A parent that manages its own children (grid, flow,
    // relative, page tabs) is skipped whole. Adjacent aligned bands share only
    // an edge (area 0) and never trip this.
    if not Managed then
      for K := 0 to Cnt - 1 do
        if not Kids[K].Deco then
          for J := K + 1 to Cnt - 1 do
            if not Kids[J].Deco and
               (Kids[K].X1 < Kids[J].X2) and (Kids[J].X1 < Kids[K].X2) and
               (Kids[K].Y1 < Kids[J].Y2) and (Kids[J].Y1 < Kids[K].Y2) then
            begin
              if Kids[K].Client and Kids[J].Client then
                Overlap.Add(MsgFmt(SF_DSGN_AMBOS_ALCLIENT_FMT, [Kids[K].Nm, Kids[K].Line,
                  Kids[J].Nm, Kids[J].Line, AWhere]))
              else
                Overlap.Add(MsgFmt(SF_DSGN_SE_SOLAPAN_FMT,
                  [Kids[K].Nm, Kids[K].Line, Kids[J].Nm, Kids[J].Line, AWhere,
                   Max(Kids[K].X1, Kids[J].X1), Max(Kids[K].Y1, Kids[J].Y1),
                   Min(Kids[K].X2, Kids[J].X2), Min(Kids[K].Y2, Kids[J].Y2)]));
            end;

    // recurse into containers, each with its OWN resolved rect as client area
    K := 0;
    for J := 0 to AParent.Children.Count - 1 do
    begin
      Kid := AParent.Children[J];
      if not IsVisual(Kid) then Continue;
      if not Vis(Kid) then Continue;
      if Kid.Children.Count > 0 then
      begin
        W := Kids[K].X2 - Kids[K].X1;
        H := Kids[K].Y2 - Kids[K].Y1;
        ix := AAbsX + Kids[K].X1; iy := AAbsY + Kids[K].Y1;
        // a container squeezed to nothing is already reported; do not cascade a
        // zero/negative client size into its children.
        if (W > 0) and (H > 0) then
          Walk(Kid, W, H, ix, iy, Kids[K].Nm,
            AKnown and Kids[K].HasW and Kids[K].HasH or
              MatchText(Kids[K].Align, ['alClient', 'alTop', 'alBottom', 'alLeft', 'alRight']),
            IsScrollBox(Kids[K].Cls));
      end;
      Inc(K);
    end;
  end;

begin
  Doc := nil;
  if not MatchText(TPath.GetExtension(APath), ['.dfm']) then
  begin
    if MatchText(TPath.GetExtension(APath), ['.fmx']) then
      Exit(MsgText(SR_DESIGNER_LAYOUT_FMX));
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  end;
  Result := LoadDoc(APath, Doc);
  if Result <> '' then Exit;
  TablaVcl := MetaTable(False, FaltaVcl, 0);
  try
    if Doc.Root = nil then Exit(MsgText(SR_DESIGNER_BINDING_NO_ROOT));
    // a truncated .dfm parses into something; only openers left unclosed betray
    // it. THE reader of the lines (Lsp.DesignerBin.LineasDeForm) tells the end
    // of a collection item from the end of an object; we still flag ONLY
    // opens>closes
    Opens := 0; Closes := 0;
    var Form := LineasDeForm(Doc.Lines);
    for I := 0 to High(Form) do
      if Form[I].Clase = clfObjeto then
        Inc(Opens)
      else if Form[I].Clase = clfFin then
        Inc(Closes);

    Ret := TJSONObject.Create;
    try
      Ret.AddPair('form', Doc.Root.ObjName);
      Ret.AddPair('class', Doc.Root.ClassName_);
      Estimated := False;
      RootW := PropInt(Doc, Doc.Root, 'ClientWidth', -1, Found);
      if not Found then
      begin
        RootW := PropInt(Doc, Doc.Root, 'Width', -1, Found);
        if Found then begin RootW := RootW - 16; Estimated := True; end;
      end;
      RootH := PropInt(Doc, Doc.Root, 'ClientHeight', -1, Found);
      if not Found then
      begin
        RootH := PropInt(Doc, Doc.Root, 'Height', -1, Found);
        if Found then begin RootH := RootH - 38; Estimated := True; end;
      end;
      Ret.AddPair('clientWidth', TJSONNumber.Create(RootW));
      Ret.AddPair('clientHeight', TJSONNumber.Create(RootH));
      if Estimated then
        Ret.AddPair('clientEstimated', TJSONBool.Create(True));

      Zero := TJSONArray.Create; Ret.AddPair('zeroSize', Zero);
      Outside := TJSONArray.Create; Ret.AddPair('outsideParent', Outside);
      Overlap := TJSONArray.Create; Ret.AddPair('overlapping', Overlap);
      NoRoom := TJSONArray.Create; Ret.AddPair('clipped', NoRoom);
      Unknown := TJSONArray.Create; Ret.AddPair('sizeNotWritten', Unknown);
      Boxes := TJSONArray.Create; Ret.AddPair('boxes', Boxes);

      if Opens > Closes then
        Ret.AddPair('truncatedNote', MsgText(SN_DESIGNER_LAYOUT_TRUNC));

      if (RootW <= 0) or (RootH <= 0) then
        NoRoom.Add(MsgFmt(SF_DSGN_NO_DICE_CUANTO_MIDE_FMT, [Doc.Root.ObjName, RootW, RootH]))
      else
        Walk(Doc.Root, RootW, RootH, 0, 0, Doc.Root.ObjName, not Estimated, False);

      // clean = sin problemas de layout; ok es "la llamada fue bien" (novena)
      Ret.AddPair('clean', TJSONBool.Create((Zero.Count = 0) and (Outside.Count = 0)
        and (Overlap.Count = 0) and (NoRoom.Count = 0)));
      if Estimated then
        Ret.AddPair('estimatedNote', MsgText(SN_DESIGNER_LAYOUT_ESTIMATED));
      Ret.AddPair('note', IfThen((Zero.Count = 0) and (Outside.Count = 0) and
        (Overlap.Count = 0) and (NoRoom.Count = 0), MsgText(SN_DESIGNER_LAYOUT_OK),
        MsgText(SN_DESIGNER_LAYOUT_BAD)));
      Ret.AddPair('howMeasured', MsgText(SN_DESIGNER_LAYOUT_HOW));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function LintForm(const APath: string): string;
var
  Denied, EncName, Text: string;
  Warns: TArray<string>;
begin
  Denied := ReadPathDenied(APath);
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_NO_EXISTE_FMT, [APath])));
  if not EsRutaDeDesigner(APath) then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  // Un .dfm binario se lee al vuelo (Lsp.DesignerBin); uno danado se rechaza.
  if IsBinaryDesigner(APath) then
  begin
    EncName := DesignerFileToText(APath, Text);
    if EncName <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, EncName));
  end
  else
    Text := PatchLoadText(APath, EncName);
  // EL lint de un form (Lsp.Patch.LintDeForm): tablas del framework + el
  // form contra su clase (check-binding) + EL parser del IDE con los bytes
  // del fichero, lo PRIMERO y con o sin tabla (8.10 de la 1.18.0); un
  // binario ya paso su conversion. lint = todo lo que el compilador no mira
  var L := LintDeForm(APath, Text, EncName, not IsBinaryDesigner(APath));
  var Falta := L.Falta;
  var Notas := L.Notas;
  Warns := L.Propiedades + L.Enlace;
  if L.Parser <> '' then
    Warns := [L.Parser] + Warns;
  // sin tabla la respuesta es la negativa (DSGN-050/051/053/054), con lo del
  // form contra su clase detras: antes salia "[DSGN-038] 1 designer
  // warnings" con el motivo dentro, un exito (revision de la 1.12.0)
  if Falta.Negativa <> '' then
  begin
    Result := Falta.Negativa;
    if Length(Warns) > 0 then
      Result := Result + #13#10 + string.Join(#13#10, Warns);
    Exit;
  end;
  // lo que no se pudo comprobar va aparte y no cuenta como aviso: una clase
  // de terceros no es un error (revision de la 1.12.0)
  if (Length(Warns) = 0) and (Length(Notas) = 0) then
    Result := MsgFmt(SN_DESIGNER_LINT_OK_FMT, [TPath.GetFileName(APath)])
  else
  begin
    Result := '';
    if Length(Warns) > 0 then
      Result := MsgFmt(SN_DESIGNER_LINT_BAD_FMT,
        [Length(Warns), TPath.GetFileName(APath)]) + #13#10 +
        string.Join(#13#10, Warns);
    if Length(Notas) > 0 then
    begin
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + MsgFmt(SN_DESIGNER_LINT_NOTAS_FMT,
        [TPath.GetFileName(APath), Length(Notas)]) + #13#10 +
        string.Join(#13#10, Notas);
    end;
  end;
end;

{ TDelphiDesignerTool }

constructor TDelphiDesignerParams.Create;
begin
  inherited Create;
  FInline := True;
  // index 0 es un valor (que se contesta con su rango), no "no se pidio"
  // (revisor 4 de la noche, M6: index=0 caia en 'prop is missing')
  FIndex := -1;
end;

constructor TDelphiDesignerTool.Create;
begin
  inherited;
  FName := 'delphi_designer';
  FDescription := SD_DESIGNER;
end;

{ to-text / to-binary: el mismo fichero en el otro formato, tal como lo
  escribiria el IDE (Lsp.DesignerBin). Copia previa por el nombrador de
  siempre (BackupFile). Solo .dfm: los .fmx son texto siempre. }
function ConvertDesigner(const APath: string; AToText: Boolean): string;
var
  Ruta, Texto, Err, Copia: string;
  B, Bin: TBytes;
  Forma: TDesignerShape;
begin
  Result := WriteTargetDenied(APath);
  if Result <> '' then
    Exit;
  Ruta := TPath.GetFullPath(APath);
  if not TFile.Exists(Ruta) then
    Exit(NoEsFichero(Ruta, MsgFmt(SR_NO_EXISTE_FMT, [Ruta])));
  if not EsRutaDeDesigner(Ruta) then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  if EsDesignerFmx(Ruta) then
    Exit(MsgText(SR_DESIGNER_FMX_ALWAYS_TEXT));
  B := TFile.ReadAllBytes(Ruta);
  Forma := DesignerShapeOf(B);
  if AToText then
  begin
    if Forma = dsText then
      Exit(MsgFmt(SN_DESIGNER_ALREADY_FMT, [TPath.GetFileName(Ruta), MsgText(SF_DSGN_TEXTO)]));
    Err := DesignerBinaryToText(B, Texto);
    if Err <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    // el fichero ENTERO cambia de forma: su contenido actual, sellado
    Copia := MaskDriveText('', GuardaContenidoActual(Ruta));
    // un nombre no ASCII va en UTF-8 CON BOM, como lo guarda el IDE (sin el,
    // TParser y dcc lo leen en ANSI); lo demas del texto es ASCII (#N)
    if IsAscii(Texto) then
      PatchSaveText(Ruta, Texto, EncName(ekUtf8))
    else
      PatchSaveText(Ruta, Texto, EncName(ekUtf8Bom));
    Result := MsgFmt(SN_DESIGNER_TOTEXT_FMT, [TPath.GetFileName(Ruta), Length(B),
      Length(LineasDelTexto(Texto)), Copia]);
  end
  else
  begin
    if Forma <> dsText then
      Exit(MsgFmt(SN_DESIGNER_ALREADY_FMT, [TPath.GetFileName(Ruta), MsgText(SF_DSGN_BINARIO)]));
    // la regla de ida y vuelta de los escritores (ReescrituraDenegada): un
    // form roto -un BOM de UTF-8 con el cuerpo en CP1252- se convertiria, con
    // el lector tolerante, con U+FFFD donde estan sus acentos; con el estricto
    // de la 1.17 reventaba (SYS-006). Revisor propio de la 4.1. Los bytes ya
    // leidos, sin leer otra vez
    var K: TEncKind;
    Err := ReescrituraDenegada(Ruta, B, K);
    if Err <> '' then
      Exit(Err);
    Texto := DecodeBytes(B, K);
    Err := DesignerTextToBinary(Texto, Bin);
    if Err <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    Copia := MaskDriveText('', GuardaContenidoActual(Ruta));
    AtomicWrite(Ruta, Bin);
    Result := MsgFmt(SN_DESIGNER_TOBINARY_FMT, [TPath.GetFileName(Ruta), Length(Bin), Copia]);
  end;
end;

{ Si un form de TEXTO esta en UTF-16 o UTF-32 (AK), por EL lector del BOM
  (Lsp.Codificacion.KindDeBom): el IDE lo abre y dcc no lo compila (E2161,
  medido el 9-oct-2026; r5 de la 1.18.0), y el renderizador no lee el
  UTF-32 - su parser de forms lo tomaba por UTF-16 y fallaba con un error de
  sintaxis que no decia por que. }
function FormAncho(const APath: string; out AK: TEncKind): Boolean;
var
  S: TFileStream;
  Cabeza: TArray<Byte>;
begin
  // los cuatro primeros bytes bastan, el BOM mas largo (el de UTF-32): leer el
  // fichero entero eran dos lecturas completas en lint (revisor propio de r5)
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Cabeza, 4);
    SetLength(Cabeza, S.Read(Cabeza[0], 4));
  finally
    S.Free;
  end;
  Result := KindDeBom(Cabeza, AK) and (AK in ENC_ANCHAS);
end;

{ Lo que lint no ve en el texto y dcc si (DSGN-121): un form de texto en UTF-16
  o UTF-32 lo abre el IDE y no lo compila dcc. La nota va en la respuesta de
  lint y en la de cada escritura del disenador (insert, set, delete), que la
  conservan; una respuesta que es un fallo se queda como esta. }
function ConNotaDeFormAncho(const AResult, APath: string): string;
var
  K: TEncKind;
begin
  Result := AResult;
  try
    if not EsFallo(Result) and FormAncho(TPath.GetFullPath(APath), K) then
      Result := ConNota(Result, 'encodingNote', MsgFmt(SN_DSGN_FORM_ANCHO_FMT,
        [TPath.GetFileName(APath), EncName(K)]));
  except
    // una nota no tumba la respuesta de lo que ya se hizo
  end;
end;

{ La respuesta de un comando de lectura sobre un .dfm binario lleva la nota:
  lo que ves es fiel, pero en disco es binario. }
function ConNotaBinario(const AResult: string): string;
begin
  Result := AResult;
  // a un RECHAZO no se le pega "lo que ves es fiel": no se ha ensenado nada
  if EsFallo(AResult) then
    Exit;
  Result := ConNota(AResult, 'binaryOnDiskNote', MsgText(SN_DESIGNER_BINARY_VIEW));
end;

{ preview: un PNG de lo que ensena el designer del IDE, por el renderizador
  de su framework (Lsp.FormRender, src\Render). Lee el fichero: no coge el
  cerrojo de escritura salvo para colocar un out= (ColocaProducto). El PNG se
  dibuja SIEMPRE en un temporal nuestro y se recorta ahi (RecortaPng con el
  RECT= del componente); con out= se lleva despues a su sitio: el
  renderizador nunca escribe en la jaula por su cuenta. }
function PreviewDeForm(const Params: TDelphiDesignerParams): string;
var
  Ruta, Fw, Estilo, Propia, Temporal, Fallo: string;
  Peticion: TPeticionRender;
  R: TRespuestaRender;
  Return, Raiz, Ms: TJSONObject;
  NoVis: TJSONArray;
  RX, RY, RW, RH, AnchoOrig, AltoOrig, OX, OY: Integer;
  Recortada, Ancho: Boolean;
  KAncha: TEncKind;
  Estados: TArray<string>;

  // el temporal es nuestro: si algo falla despues del render, no se queda
  procedure TiraTemporal;
  begin
    if (Temporal <> '') and IsAgentCapture(Temporal) then
      ConsumeAgentCapture(Temporal);
  end;

  function Textos(const AValores: TArray<string>): TJSONArray;
  begin
    Result := TJSONArray.Create;
    for var V in AValores do
      Result.Add(V);
  end;

begin
  if Params.Path.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_PATH));
  Ruta := TPath.GetFullPath(Params.Path.Trim);
  Fw := ResolveFramework('', Ruta);
  if Fw = '' then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  if (Params.Framework.Trim <> '') and not SameText(Params.Framework.Trim, Fw) then
    Exit(MsgFmt(SR_DESIGNER_FW_NO_CASA_FMT, [Params.Framework.Trim, TPath.GetFileName(Ruta)]));
  // la puerta de lectura, la de siempre (la entrada ya la paso: por si la
  // tool llega por otro camino)
  Fallo := ReadPathDenied(Ruta);
  if Fallo <> '' then
    Exit(Fallo);
  if not TFile.Exists(Ruta) then
    Exit(NoEsFichero(Ruta, MsgFmt(SR_NO_EXISTE_FMT, [Ruta])));
  // un form de texto en UTF-32 no lo lee el renderizador ni lo compila dcc:
  // se dice antes de lanzar nada; uno en UTF-16 se dibuja, con la nota
  Ancho := FormAncho(Ruta, KAncha);
  if Ancho and (KAncha in [ekUtf32LE, ekUtf32BE]) then
    Exit(MsgFmt(SR_DSGN_FORM_UTF32_FMT, [TPath.GetFileName(Ruta), EncName(KAncha)]));
  // EL parser del IDE antes de lanzar nada (8.10 de la 1.18.0): un form que no
  // lee no se dibuja, y se dice la linea que nombra - DSGN-061 decia "the
  // renderer could not draw" con su "Identifier expected on line 2" y nada
  // mas, tras gastar un proceso. Un binario lo lee el renderizador entero
  if not IsBinaryDesigner(Ruta) then
  begin
    var EncP: string;
    var LinP: Integer;
    var CitaP: string;
    var ErrP := ParserDeForm(PatchLoadText(Ruta, EncP), EncP, LinP, CitaP);
    if ErrP <> '' then
      Exit(MsgFmt(SR_DSGN_PREVIEW_PARSER_FMT, [TPath.GetFileName(Ruta), ErrP, LinP, CitaP]));
  end;

  // style: none, el NOMBRE de una plataforma del designer (la lista la tiene
  // el renderizador FMX: UNA tabla) o un fichero por ruta completa
  Estilo := Params.Style.Trim;
  if SameText(Estilo, 'none') then
    Estilo := 'none'
  else if TRegEx.IsMatch(Estilo, '^[A-Za-z0-9-]+$') then
  begin
    if Fw = 'vcl' then
      Exit(MsgFmt(SR_DESIGNER_STYLE_VCL_FMT, [Estilo]));
  end
  else if Estilo <> '' then
  begin
    if not EsRutaAbsoluta(Estilo) then
      Exit(MsgFmt(SR_DESIGNER_STYLE_NOMBRE_FMT, [Estilo]));
    Estilo := TPath.GetFullPath(Estilo);
    Fallo := ReadPathDenied(Estilo);
    if Fallo <> '' then
      Exit(Fallo);
    if not TFile.Exists(Estilo) then
      Exit(NoEsFichero(Estilo, MsgFmt(SR_NO_EXISTE_FMT, [Estilo])));
  end;

  // state, por EL lector de la lista (TrozosDeEstado: un ';' en un literal no
  // parte, una comilla que no EMPIEZA el valor es una letra) y antes de
  // dibujar nada. Un valor entre comillas es un literal del form y se entrega
  // su texto: SetPropValue pintaba las comillas (revisor 2 de la noche, M-A)
  var Trozos: TArray<string>;
  Fallo := TrozosDeEstado(Params.State, Trozos);
  if Fallo <> '' then
    Exit(Fallo);
  Estados := [];
  for var E in Trozos do
  begin
    var P := Pos('=', E);
    var Texto: string;
    var Valor := Copy(E, P + 1, MaxInt).Trim;
    // y su texto con la unidad virtual de una ruta expandida: la excepcion
    // declarada de [Contenido], la de value / props (PonEnMemoria, B-9)
    if (P > 0) and (Valor.StartsWith('''') or Valor.StartsWith('#')) and
       LeeLiteralDeForm(Valor, Texto) then
      Estados := Estados + [Copy(E, 1, P - 1).Trim + '=' + ExpandDriveValue(Texto)]
    else if (P > 0) and (ExpandDriveValue(Valor) <> Valor) then
      Estados := Estados + [Copy(E, 1, P - 1).Trim + '=' + ExpandDriveValue(Valor)]
    else
      Estados := Estados + [E];
  end;

  // donde cae: el out= de toda la familia de capturas (CaptureTarget). Se
  // dibuja en un temporal nuestro aunque haya out=
  Fallo := CaptureTarget(Params.Out_, CAPTURE_SUB_DESIGNER, 'designer', '.png', Propia);
  if Fallo <> '' then
    Exit(Fallo);
  Temporal := Propia;
  if Params.Out_.Trim <> '' then
  begin
    Fallo := CaptureTarget('', CAPTURE_SUB_DESIGNER, 'designer', '.png', Temporal);
    if Fallo <> '' then
      Exit(Fallo);
  end;
  CrearCarpeta(TPath.GetDirectoryName(Temporal));

  // lo comun - framework, ruta, Delphi, form o frame por EL lector de clases -
  // en UN sitio, el del juez del orden tambien (Lsp.FormRender.PeticionDeRender)
  Peticion := PeticionDeRender(Ruta, Fw);
  Peticion.Salida := Temporal;
  Peticion.Componente := Params.Component.Trim;
  Peticion.Estilo := Estilo;
  Peticion.NoVisuales := Params.NonVisual;
  Peticion.Estados := Estados;
  R := CorreRender(Peticion);
  if R.Fallo <> '' then
  begin
    TiraTemporal;
    Exit(R.Fallo);
  end;

  // el recorte al componente, aqui y por el recortador de la casa: el
  // renderizador solo dice donde esta (RECT=)
  OX := 0;
  OY := 0;
  Recortada := False;
  AnchoOrig := R.Ancho;
  AltoOrig := R.Alto;
  if Peticion.Componente <> '' then
  begin
    if not R.HayRect then
    begin
      TiraTemporal;
      Exit(MsgFmt(SR_DESIGNER_PREVIEW_SIN_COMPONENTE_FMT, [Peticion.Componente, R.RaizNombre]));
    end;
    RX := R.RectX;
    RY := R.RectY;
    RW := R.RectW;
    RH := R.RectH;
    Fallo := RecortaPng(Temporal, RX, RY, RW, RH, AnchoOrig, AltoOrig);
    if Fallo <> '' then
    begin
      TiraTemporal;
      Exit(MsgEnvuelve(SR_DESIGNER_RECORTE_FALLO_FMT, Fallo, [TPath.GetFileName(Ruta), Peticion.Componente,
        Fallo]));
    end;
    OX := RX;
    OY := RY;
    Recortada := True;
  end;

  if Temporal <> Propia then
    try
      ColocaProducto(Temporal, Propia); // EL escritor de un producto (Lsp.Patch)
      Temporal := '';
    except
      on E: Exception do
      begin
        TiraTemporal;
        Exit(MsgExcepcion(E.ClassName, E.Message));
      end;
    end;

  Return := TJSONObject.Create;
  try
    Return.AddPair('path', Ruta);
    Return.AddPair('framework', Fw);
    Raiz := TJSONObject.Create;
    Raiz.AddPair('name', R.RaizNombre);
    Raiz.AddPair('class', R.RaizClase);
    Raiz.AddPair('kind', R.RaizTipo);
    Return.AddPair('root', Raiz);
    Return.AddPair('fidelity', R.Fidelidad);
    if R.Fidelidad = 'print' then
      Return.AddPair('fidelityNote', MsgText(SN_DESIGNER_FIDELIDAD_PRINT));
    if Ancho then
      Return.AddPair('encodingNote', MsgFmt(SN_DSGN_FORM_ANCHO_FMT,
        [TPath.GetFileName(Ruta), EncName(KAncha)]));
    Return.AddPair('style', R.Estilo);
    Return.AddPair('packages', R.Paquetes);
    Return.AddPair('components', TJSONNumber.Create(R.Componentes));
    if Length(R.Sustituidas) > 0 then
    begin
      Return.AddPair('substituted', Textos(R.Sustituidas));
      Return.AddPair('substitutedNote', MsgText(SN_DESIGNER_SUSTITUIDAS));
    end;
    if Length(R.Ignoradas) > 0 then
    begin
      Return.AddPair('ignored', IgnoradasConLinea(Ruta, R.Ignoradas));
      Return.AddPair('ignoredNote', MsgText(SN_DESIGNER_PREVIEW_IGNORADAS));
    end;
    if Length(R.Avisos) > 0 then
      Return.AddPair('warnings', Textos(R.Avisos));
    // los no visuales SIEMPRE, se dibujen o no (David, 7-oct-2026: lo que
    // el modelo necesita es saber que existen)
    NoVis := TJSONArray.Create;
    for var NV in R.NoVisuales do
    begin
      var Uno := TJSONObject.Create;
      Uno.AddPair('name', NV.Nombre);
      Uno.AddPair('class', NV.Clase);
      NoVis.AddElement(Uno);
    end;
    Return.AddPair('nonVisual', NoVis);
    // lo DIBUJADO (NONVISUAL= del ayudante), no lo pedido: decia true sin
    // haber dibujado nada (3.6 de la 1.18.0, Hermes)
    Return.AddPair('nonVisualDrawn', TJSONBool.Create(Params.NonVisual and (R.NoVisualesDibujados > 0)));
    if (Length(R.NoVisuales) > 0) and not Params.NonVisual then
      Return.AddPair('nonVisualNote', MsgText(SN_DESIGNER_NO_VISUALES_OCULTOS));
    if Recortada then
    begin
      Return.AddPair('component', Peticion.Componente);
      Return.AddPair('componentRect', Format('%d,%d,%d,%d', [R.RectX, R.RectY, R.RectW, R.RectH]));
      Return.AddPair('croppedFrom', Format('%dx%d', [AnchoOrig, AltoOrig]));
    end;
    Ms := TJSONObject.Create;
    Ms.AddPair('load', TJSONNumber.Create(R.MsCarga));
    Ms.AddPair('paint', TJSONNumber.Create(R.MsPintado));
    Ms.AddPair('total', TJSONNumber.Create(R.MsTotal));
    Return.AddPair('ms', Ms);
    Return.AddPair('screenshot', Propia);
    Return.AddPair('screenshotBytes', TJSONNumber.Create(TFile.GetSize(Propia)));
    // UN SOLO PASO, como toda captura: inline (y su temporal consumido) o
    // fichero + enlace. El frame lleva el origen del recorte: pixeles de la
    // imagen -> unidades de la form, sin cuentas del agente
    DeliverCapture('delphi_designer', Propia, Params.Inline_, Params.MaxWidth,
      OX, OY, 1.0, 1.0, Return, MsgText(SN_DESIGNER_INLINE_NOTE_FMT),
      MsgText(SN_DESIGNER_FRAME_NOTE));
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ insert y set parent= en un .dfm: si el control cae fuera del area de su
  padre, la respuesta lo dice - lo que calcula layout, aqui al lado (David,
  4-oct-2026). Un fallo, o un .fmx (layout no mide FMX), pasan tal cual. }
function ConFueraDelPadre(const AResult, APath: string): string;
var
  Ret, Lay: TJSONObject;
  Fuera, Suyas: TJSONArray;
  Nombre: string;
begin
  Result := AResult;
  if EsFallo(AResult) or not APath.Trim.EndsWith('.dfm', True) then
    Exit;
  Ret := ObjetoJson(AResult);
  if Ret = nil then
    Exit;
  try
    if not (Ret.TryGetValue<string>('inserted', Nombre) or Ret.TryGetValue<string>('moved', Nombre)) then
      Exit;
    Lay := ObjetoJson(LayoutOf(APath.Trim));
    if Lay = nil then
      Exit;
    try
      Suyas := nil;
      if Lay.TryGetValue<TJSONArray>('outsideParent', Fuera) then
        for var V in Fuera do
          if V.Value.StartsWith(Nombre + ':') then
          begin
            if Suyas = nil then
            begin
              Suyas := TJSONArray.Create;
              Ret.AddPair('outsideParent', Suyas);
            end;
            Suyas.Add(V.Value);
          end;
    finally
      Lay.Free;
    end;
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ El gesto; ExecuteWithParams lo envuelve en el cerrojo de escritura. }
function GestoDeDisenador(const Params: TDelphiDesignerParams): string;
var
  Cmd, Fw: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'info';
  // Sin guion tambien (un modelo pequeno lo pierde, y este agente dos veces
  // en un dia): la misma cortesia que 'windows' y 'binding'.
  if Cmd = 'totext' then
    Cmd := 'to-text'
  else if Cmd = 'tobinary' then
    Cmd := 'to-binary';
  // lo que no es del comando se dice (Lsp.Guard.ParametroQueNoVa): aqui se
  // ignoraba en silencio (decima revision)
  var Modo := IfThen(Cmd = 'binding', 'check-binding', Cmd);
  var Suyos: string;
  var Sobra := ParametroQueNoVa(Modo, [
      // el parametro se llama classname: la tabla decia class y DSGN-047 lo
      // ensenaba con ese nombre (Hermes, 28-sep-2026, F2)
      'info', 'classname framework filter',
      'prop', 'classname framework prop',
      'tree', 'path maxdepth', 'lint', 'path', 'layout', 'path',
      'get', 'path component',
      'check-binding', 'path unit',
      'preview', 'path component framework state style nonvisual inline maxwidth out',
      'insert', 'path classname component parent props',
      'set', 'path component prop value parent props before after index',
      'delete', 'path component',
      'to-text', 'path', 'to-binary', 'path'],
    ['path', Params.Path, '', 'classname', Params.ClassName_, '', 'prop', Params.Prop, '',
     'component', Params.Component, '', 'unit', Params.Unit_, '',
     'framework', Params.Framework, '', 'filter', Params.Filter, '',
     'maxdepth', IfThen(Params.MaxDepth <> 0, IntToStr(Params.MaxDepth)), '',
     'state', Params.State, '', 'style', Params.Style, '',
     'nonvisual', IfThen(Params.NonVisual, 'true'), '', 'inline', IfThen(Params.Inline_, 'true', 'false'), 'true',
     'maxwidth', IfThen(Params.MaxWidth <> 0, IntToStr(Params.MaxWidth)), '',
     'out', Params.Out_, '', 'parent', Params.Parent, '', 'value', Params.Value, '',
     'props', Params.Props, '', 'before', Params.Before, '', 'after', Params.After, '',
     'index', IfThen(Params.Index >= 0, IntToStr(Params.Index)), ''], Suyos);
  if Sobra <> '' then
    Exit(MsgFmt(SR_DESIGNER_NO_VA_CON_COMANDO_FMT, [Sobra, Modo, Modo, Suyos]));
  if MatchText(Cmd, ['info', 'prop']) then
  begin
    Fw := ResolveFramework(Params.Framework, Params.Path);
    if Fw = '?' then
      Exit(MsgText(SR_DESIGNER_FRAMEWORK));
    if Fw = '' then
      Fw := 'vcl';
    if Params.ClassName_.Trim = '' then
      Exit(MsgText(SR_DESIGNER_NEED_CLASS));
    if Cmd = 'info' then
      Result := MetaClassInfo(Fw, Params.ClassName_, Params.Filter.Trim)
    else if Params.Prop.Trim = '' then
      Result := MsgText(SR_DESIGNER_NEED_PROP)
    else
      Result := PropInfo(Fw, Params.ClassName_, Params.Prop);
  end
  else if MatchText(Cmd, ['tree', 'get', 'lint', 'check-binding', 'binding',
    'layout']) then
  begin
    if Params.Path.Trim = '' then
      Exit(MsgText(SR_DESIGNER_NEED_PATH));
    if MatchText(Cmd, ['check-binding', 'binding']) then
      Result := CheckBinding(Params.Path, Params.Unit_)
    else if Cmd = 'layout' then
      Result := LayoutOf(Params.Path)
    else if Cmd = 'tree' then
      Result := TreeOf(Params.Path, Params.MaxDepth) // (un negativo lo niega la capa de parametros, SYS-016)
    else if Cmd = 'lint' then
      Result := ConNotaDeFormAncho(LintForm(Params.Path), Params.Path)
    else if Params.Component.Trim = '' then
      Result := MsgText(SR_DESIGNER_NEED_COMPONENT)
    else
      Result := GetComponent(Params.Path, Params.Component);
    if IsBinaryDesigner(TPath.GetFullPath(Params.Path)) then
      Result := ConNotaBinario(Result);
  end
  else if Cmd = 'preview' then
    Result := PreviewDeForm(Params)
  else if MatchText(Cmd, ['to-text', 'to-binary']) then
  begin
    if Params.Path.Trim = '' then
      Exit(MsgText(SR_DESIGNER_NEED_PATH));
    Result := ConvertDesigner(Params.Path, Cmd = 'to-text');
  end
  else if MatchText(Cmd, ['insert', 'set', 'delete']) then
  begin
    // editar el form y su unidad como el IDE (Lsp.DesignerEdit, 1.17.0)
    if Params.Path.Trim = '' then
      Exit(MsgText(SR_DESIGNER_NEED_PATH));
    if Cmd = 'insert' then
      Result := ConFueraDelPadre(InsertaComponente(Params.Path, Params.ClassName_,
        Params.Component, Params.Parent, Params.Props), Params.Path)
    else if Cmd = 'set' then
      Result := ConFueraDelPadre(CambiaPropiedad(Params.Path, Params.Component,
        Params.Prop, Params.Value, Params.Parent, Params.Props, Params.Before,
        Params.After, Params.Index), Params.Path)
    else
      Result := BorraComponente(Params.Path, Params.Component);
    // ...y lo mismo que lint tras escribir: el form sigue en UTF-16/32, que dcc
    // no compila (r5-L3 de la 1.18.0: solo lo decian lint y preview)
    Result := ConNotaDeFormAncho(Result, Params.Path);
  end
  else
    Result := MsgText(SR_DESIGNER_CMD);
  // (lo enmascara el filtro de salida, Lsp.Host; una segunda pasada con el
  // nombre de la tool gastaba lo que la llamada dejo anotado)
end;

function TDelphiDesignerTool.ExecuteWithParams(const Params: TDelphiDesignerParams): string;
var
  Cmd: string;
  Falta: TFaltaTabla;
begin
  // to-text y to-binary reescriben el .dfm entero, e insert/set/delete el form
  // y su unidad: son ediciones como cualquier otra y van bajo el mismo
  // cerrojo. Los de LECTURA no: info, prop y lint pueden esperar a la tabla
  // del disenador mientras se genera (Lsp.DesignerMetaGen), y con el cerrojo
  // cogido paraban todas las ediciones del servidor (revision de la 1.12.0);
  // leen como delphi_read, que tampoco lo coge (lo que se escribe se escribe
  // entero o nada).
  Cmd := Params.Command.Trim.ToLower;
  if not MatchText(Cmd, ['to-text', 'to-binary', 'totext', 'tobinary', 'insert', 'set', 'delete']) then
    Exit(GestoDeDisenador(Params));
  // el orden entre hermanos pregunta al renderizador (segundos con paquetes):
  // FUERA del cerrojo, que coge el mismo solo para releer y escribir; dentro
  // paraba todas las ediciones del servidor (revisor 5 de la noche, A3). Y
  // insert y set parent=, que le preguntan desde el 17f4edd donde dejar el
  // bloque (AbreFormParaJuzgar / CambioDesdeQueSeJuzgo): se quedaron dentro y
  // el juez corria con el cerrojo (revisor del 17f4edd, A1: un textedit de
  // otro fichero esperaba al insert)
  if ((Cmd = 'set') and ((Params.Before.Trim <> '') or (Params.After.Trim <> '') or
     (Params.Index >= 0) or (Params.Parent.Trim <> ''))) or (Cmd = 'insert') then
    Exit(GestoDeDisenador(Params));
  // la tabla que piden insert, set (parent= y Name tambien) y delete se
  // espera FUERA del cerrojo, por lo mismo: set parent= la esperaba dentro y
  // paraba todas las ediciones mientras se generaba (revision de la 1.17.0)
  if MatchText(Cmd, ['insert', 'set', 'delete']) and
     (MetaTable(EsDesignerFmx(Params.Path), Falta) = nil) and
     (Falta.Negativa <> '') then
    Exit(Falta.Negativa);
  EnterFileEdit;
  try
    Result := GestoDeDisenador(Params);
  finally
    LeaveFileEdit;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_designer',
    function: IMCPTool begin Result := TDelphiDesignerTool.Create; end);

end.
