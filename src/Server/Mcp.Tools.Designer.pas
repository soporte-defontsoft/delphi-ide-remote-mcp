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
    [SchemaDescription(SP_DESIGNER_INLINE)]
    property Inline_: Boolean read FInline write FInline;
    [SchemaDescription(SP_DESIGNER_MAXWIDTH)]
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
  Lsp.Imagen,        // RecortaPngBytes: el recorte al componente, en el servidor
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
  Result := SinMayusculas(AParam.Trim);
  if MatchText(Result, ['vcl', 'fmx']) then
    Exit;
  if Result <> '' then
    Exit('?');
  if EsDesignerFmx(APath) then
    Exit('fmx');
  if EsDesignerVcl(APath) then
    Exit('vcl');
  Result := '';
end;

// (ClaseQueNoEsta vive en Lsp.DesignerMeta desde la 1.17.0: el insert de
// Lsp.DesignerEdit dice lo mismo de una clase que no esta)

{ Con filtro, las sub-propiedades que casan un nivel por dentro de las
  propiedades OBJETO de la clase (TextSettings, Font; nunca una referencia
  como PopupMenu: EsObjetoPropio), con punto como las escribe set, y en ARecs
  su registro. La instancia de una propiedad objeto puede ser de una
  descendiente del tipo declarado (TLabelTextSettings): cuenta su familia,
  como en el juez. Y de AClase, si no publica nada pero tiene descendientes
  (TTextSettings), lo que publica su familia, sin punto, como
  descendantsPublish. Ordenadas por nombre. }
function PorDentroQueCasan(M: TMetaTable; const AClase: string; APropias: TStringList;
  const AFilter: string; ARecs: TDictionary<string, TPropRec>): TStringList;
var
  Duenas: TDictionary<string, string>;
  R: TPropRec;
  Duena, Ya: string;
begin
  Result := TStringList.Create;
  Duenas := TDictionary<string, string>.Create;
  try
    // cada clase de la familia del tipo -> las propiedades que la guardan,
    // separadas por #9 (Margins y Padding son las dos un TBounds)
    for var Key in APropias do
    begin
      R := M.Props[Key];
      if (R.Kind <> 'c') or not M.EsObjetoPropio(R.TypeId) then
        Continue;
      Duena := R.Name;
      M.RecorreFamilia(R.TypeId,
        function(const C: string): Boolean
        begin
          if Duenas.TryGetValue(C, Ya) then
            Duenas[C] := Ya + #9 + Duena
          else
            Duenas.Add(C, Duena);
          Result := False;
        end);
    end;
    // la clase que no publica nada: su familia, con duena '' (sin punto). El
    // filtro decia "the class simply has no such member" junto a un
    // descendantsPublish que lo traia, y DSGN-155 manda ahi (Flash, la
    // validacion previa de la 1.20)
    if APropias.Count = 0 then
      M.RecorreFamilia(AClase,
        function(const C: string): Boolean
        begin
          if not Duenas.ContainsKey(C) then
            Duenas.Add(C, '');
          Result := False;
        end);
    if Duenas.Count = 0 then
      Exit;
    for var Key in M.Props.Keys do
    begin
      if not Duenas.TryGetValue(ClaseDeClaveProp(Key), Ya) then
        Continue;
      R := M.Props[Key];
      if (R.Kind = 'm') or not ContainsText(R.Name, AFilter) then
        Continue;
      var Duenos := Ya.Split([#9]);
      if Length(Duenos) = 0 then
        Duenos := [''];
      for var D in Duenos do
      begin
        var Nombre := IfThen(D = '', R.Name, D + '.' + R.Name);
        if not ARecs.ContainsKey(Nombre) then
        begin
          ARecs.Add(Nombre, R);
          Result.Add(Nombre);
        end;
      end;
    end;
    Result.Sort;
  finally
    Duenas.Free;
  end;
end;

function MetaClassInfo(const AFramework, AClass, AFilter: string): string;
var
  M: TMetaTable;
  Ret: TJSONObject;
  PArr, EArr: TJSONArray;
  Key, Cls, ClsId, PName: string;
  Falta: TFaltaTabla;
  R: TPropRec;
  Names: TStringList;
  N, Shown: Integer;

  // una en la lista, con su tipo: las de la clase y las de por dentro
  procedure Pon(const ANombre: string; const AR: TPropRec);
  begin
    Inc(N);
    if Shown >= MAX_PROPS then
      Exit;
    Inc(Shown);
    if AR.Kind = 'm' then
      EArr.Add(ANombre + ': ' + AR.TypeName)
    else
    begin
      var O := TJSONObject.Create;
      PArr.AddElement(O);
      O.AddPair('name', ANombre);
      O.AddPair('kind', KindWord(AR.Kind));
      O.AddPair('type', AR.TypeName);
    end;
  end;

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
      if (AFilter <> '') and not ContainsText(R.Name, AFilter) then
        Continue;
      Pon(R.Name, R);
    end;
    // con filtro, tambien un nivel por dentro de las propiedades objeto, con
    // punto: filter=Horz decia "no such member" de un TLabel FMX cuyo
    // TextSettings.HorzAlign existe (el 27B de Hermes, 1.20), y una pista a
    // mano ("FMX lleva la fuente en TextSettings") lo suplia en un caso
    if AFilter <> '' then
    begin
      var Recs := TDictionary<string, TPropRec>.Create;
      var Dentro := PorDentroQueCasan(M, ClsId, Names, AFilter, Recs);
      try
        for PName in Dentro do
          Pon(PName, Recs[PName]);
      finally
        Dentro.Free;
        Recs.Free;
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
      Ret.AddPair('hint', MsgFmt(SN_DESIGNER_INFO_FILTRO_VACIO_FMT, [Cls, AFilter, Names.Count]));
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
  Cls, ClsId, Members, Juicio: string;
  Falta: TFaltaTabla;
  HayHoja: Boolean;
begin
  M := MetaTable(AFramework = 'fmx', Falta);
  if M = nil then
    Exit(Falta.Negativa);
  if not M.ClaseDeNombre(AClass, ClsId) then
    Exit(ClaseQueNoEsta(M, AClass, AFramework));
  Cls := M.Classes[ClsId];
  // la ruta la recorre EL juez de set (JuzgaPropiedad): con punto
  // (TextSettings.HorzAlign, Font.Size) baja por la propiedad objeto, y por
  // la descendiente que guarda la instancia. Aqui se miraba solo el primer
  // nivel y prop negaba lo que set escribe: el agente que preguntaba antes
  // de escribir salia peor parado que el que no (el 27B de Hermes, 1.20)
  Juicio := JuzgaPropiedad(M, ClsId, AProp.Trim, '', R, HayHoja);
  if not HayHoja then
  begin
    // lo que no existe, con las palabras del juez (y la pista del otro
    // marco); lo que el juez calla - lo guardado por codigo, una clase sin
    // datos -, como antes
    if Juicio <> '' then
      Juicio := ': ' + Juicio;
    Exit(MsgFmt(SR_DESIGNER_PROP_FMT, [AProp.Trim, Cls, Juicio]));
  end;
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
    // un entero con constantes (TColor, TAlphaColor, TCursor): lo que toma,
    // con EL texto del juez de set (LoQueToma). Decia solo el tipo y Flash
    // tuvo que provocar un DSGN-093 para saberlo (1.20.1)
    var Toma := LoQueToma(M, R);
    if Toma <> '' then
      Ret.AddPair('takes', Toma);
    // una propiedad objeto: lo suyo lo publica SU clase, y se pregunta a ella
    // (el enlace de la ayuda de Delphi; David, 1.20). Sin equivalencias. Una
    // REFERENCIA a un componente (PopupMenu) no: toma un Name, no lleva punto
    if (R.Kind = 'c') and M.EsObjetoPropio(R.TypeId) then
      Ret.AddPair('note', MsgFmt(SN_DESIGNER_PROP_CLASE_FMT, [R.TypeName, AFramework, AProp.Trim]));
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
  Result := EntradaDeFormDenegada(APath, False); // looking at a form is reading
  if Result <> '' then
    Exit;
  // Un binario se lee al vuelo (TStyleDoc lo convierte); solo uno danado
  // sigue siendo un rechazo, con el motivo de la RTL. Y uno que el parser del
  // IDE no lee por lineas como este lector, tampoco: tree, get y layout
  // darian otras lineas (DSGN-160, 3b del censo de jueces)
  try
    Result := TStyleDoc.Lee(APath, ADoc);
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_DESIGNER_ILEGIBLE_FMT, E.Message, [APath, E.Message]));
  end;
end;

{ Las propiedades que el lector se salto en un preview, como objetos que
  guian: el componente, la propiedad, el motivo de TReader y su linea - la
  localiza el servidor, que el renderizador no sabe lineas (en un binario, la
  del texto que ensenan delphi_read y get) -. Una escrita en otro fichero que el
  form carga (un frame en linea, un ancestro) lleva ese fichero, y su linea alli
  (Hermes, dirigido de la 1.26: iba sin linea y sin decir donde); lo que no casa
  con la forma de TReader, como texto, con su fichero si no es el form (David,
  7-oct-2026). }
function IgnoradasConLinea(AFicheros: TFicherosDelForm; const AIgnoradas: TArray<TIgnorada>): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var I in AIgnoradas do
  begin
    var Uno := TJSONObject.Create;
    Result.Add(Uno);
    // EL localizador (Lsp.FormRender), el de lo que no carga
    var D: TStyleDoc;
    var Otro: string;
    var Linea := LineaDeLoLeido(AFicheros, I, D, Otro);
    if I.Componente = '' then
    begin
      Uno.AddPair('text', I.Texto);
      if Otro <> '' then
        Uno.AddPair('file', Otro);
      Continue;
    end;
    Uno.AddPair('component', I.Componente);
    Uno.AddPair('property', I.Propiedad);
    Uno.AddPair('reason', I.Motivo);
    if Otro <> '' then
      Uno.AddPair('file', Otro);
    if Linea > 0 then
      Uno.AddPair('line', TJSONNumber.Create(Linea));
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
    begin
      // uno que llega del ancestro sin bloque aqui: lo que es, como lo carga
      // el IDE (decia que no estaba: A16-G1 de la 1.23)
      Result := HeredadoParaGet(Doc, APath, AName);
      if Result <> '' then
        Exit;
      // LA negativa de los comandos que escriben, con los nombres del form
      // (ComponenteQueNoEsta): get decia otra, DSGN-017 (A16 de la 1.23)
      Exit(ComponenteQueNoEsta(Doc, AName, TPath.GetFileName(APath)));
    end;
    // por su ruta si es de un frame en linea, la que se le dio (decia el Name
    // a secas: rondas de Opus de la 1.22.2)
    Result := MsgFmt(SF_DSGN_BLOQUE_LINEAS_FMT,
      [O.Ruta, O.ClassName_, O.StartLine, O.EndLine,
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
    if not TieneExtension(APas, ['.pas']) then
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

{ ACls es una de AClases ('Unidad:TClase') o desciende de una, por la tabla del
  marco M (Desciende): tambien la de un tercero. Sin tabla, o con una clase que
  la tabla no tiene, por su nombre. }
function EsDeAlguna(M: TMetaTable; const ACls: string; const AClases: TArray<string>): Boolean;
var
  Id: string;
begin
  var EnTabla := (M <> nil) and M.ClaseDeNombre(ACls, Id);
  for var C in AClases do
    if (EnTabla and M.Desciende(Id, C)) or
       (not EnTabla and SameText(ACls, C.Substring(C.IndexOf(':') + 1))) then
      Exit(True);
  Result := False;
end;

{ El Align que una clase de la VCL no escribe en el .dfm porque es el suyo: el que
  redeclara con default en su fuente (property Align default alTop; medido el
  2-nov-2026, y test_capacidades_126 R8 lo compara con el fuente: TCoolBar y
  TControlBar no lo redeclaran, y sin Align escrito son alNone), y el que pone a
  sus hijos el contenedor que los coloca (una pagina llena su TPageControl, un
  TCategoryPanel se apila en su grupo). Sin esto, un trio TStatusBar/TToolBar/
  TMemo era una pila y no tres bandas. }
function DefaultAlign(M: TMetaTable; const ACls: string): string;
begin
  if EsDeAlguna(M, ACls, ['Vcl.ComCtrls:TStatusBar']) then Exit('alBottom');
  if EsDeAlguna(M, ACls, ['Vcl.ComCtrls:TToolBar', 'Vcl.ComCtrls:TCustomHeaderControl',
    'Vcl.ComCtrls:THeaderControl', 'Vcl.ActnCtrls:TActionToolBar', 'Vcl.ActnMenus:TActionMainMenuBar',
    'Vcl.FormTabsBar:TCustomFormTabsBar', 'Vcl.FormTabsBar:TFormTabsBar']) then Exit('alTop');
  if EsDeAlguna(M, ACls, ['Vcl.ExtCtrls:TSplitter', 'Vcl.ExtCtrls:TCategoryPanelGroup']) then Exit('alLeft');
  if EsDeAlguna(M, ACls, ['Vcl.ComCtrls:TTabSheet']) then Exit('alClient');
  if EsDeAlguna(M, ACls, ['Vcl.ExtCtrls:TCategoryPanel']) then Exit('alTop');
  Result := 'alNone';
end;

type
  { Lo que un contenedor hace con sus hijos, para no juzgarlos como sueltos: los
    desplaza (lo que sobresale se alcanza: fcScroll), los pone en paginas, en
    celdas (sus hijos llevan alClient: "llena tu celda") o por sus reglas (fluyen,
    se colocan por relaciones), y el adorno, un marco ALREDEDOR de un grupo o un
    fondo detras, que no tapa a nadie }
  TFamiliaDeClase = (fcScroll, fcPaginas, fcCeldas, fcReglas, fcAdorno);

{ Las clases que DEFINEN cada familia, por marco: lo es la que desciende de una
  (EsDeAlguna). Eran listas de nombres que mezclaban los dos marcos -el
  TTabControl de la VCL, de UNA area, se tomaba por uno de paginas como el de FMX,
  y dos botones solapados en el no se decian- y dejaban fuera a los descendientes:
  TListBox, TMemo, TGrid, TPresentedVertScrollBox, TGridPanelLayout (forma 8 del
  revisor del paisaje de la 1.26). Con una base Custom va la clase de la paleta:
  sin tabla, una clase se reconoce por su nombre. }
function ClasesDeFamilia(AFamilia: TFamiliaDeClase; AFmx: Boolean): TArray<string>;
begin
  Result := nil;
  case AFamilia of
    fcScroll:
      if AFmx then
        Result := ['FMX.Layouts:TCustomScrollBox', 'FMX.Layouts:TScrollBox', 'FMX.Layouts:TVertScrollBox',
          'FMX.Layouts:THorzScrollBox', 'FMX.Layouts:TFramedScrollBox',
          'FMX.ScrollBox:TCustomPresentedScrollBox', 'FMX.ScrollBox:TPresentedScrollBox']
      else
        Result := ['Vcl.Forms:TScrollBox', 'Vcl.ComCtrls:TPageScroller'];
    fcPaginas:
      if AFmx then
        Result := ['FMX.TabControl:TTabControl']
      else
        Result := ['Vcl.ComCtrls:TPageControl'];
    fcCeldas:
      if AFmx then
        Result := ['FMX.Layouts:TGridPanelLayout']
      else
        Result := ['Vcl.ExtCtrls:TCustomGridPanel', 'Vcl.ExtCtrls:TGridPanel'];
    fcReglas:
      if AFmx then
        Result := ['FMX.Layouts:TFlowLayout', 'FMX.Layouts:TGridLayout']
      else
        Result := ['Vcl.ExtCtrls:TCustomFlowPanel', 'Vcl.ExtCtrls:TFlowPanel',
          'Vcl.WinXCtrls:TCustomRelativePanel', 'Vcl.WinXCtrls:TRelativePanel'];
    fcAdorno:
      if not AFmx then
        Result := ['Vcl.ExtCtrls:TBevel', 'Vcl.ExtCtrls:TShape', 'Vcl.ExtCtrls:TImage', 'Vcl.ExtCtrls:TPaintBox'];
  end;
end;

function EsDeFamilia(M: TMetaTable; const ACls: string; AFamilia: TFamiliaDeClase; AFmx: Boolean): Boolean;
begin
  Result := EsDeAlguna(M, ACls, ClasesDeFamilia(AFamilia, AFmx));
end;

{ Un contenedor que coloca a sus hijos el mismo (paginas, celdas, reglas): lo que
  dicen su Left/Top y que se solapen no significa nada }
function ColocaASusHijos(M: TMetaTable; const ACls: string; AFmx: Boolean): Boolean;
begin
  Result := EsDeFamilia(M, ACls, fcPaginas, AFmx) or EsDeFamilia(M, ACls, fcCeldas, AFmx) or
    EsDeFamilia(M, ACls, fcReglas, AFmx);
end;

const
  // 45 s: el ayudante tiene 30 para el form y sus paquetes (VigiaDelAyudante). Con
  // 30 le quedaban 15, y cargar los 110 paquetes de diseno de esta maquina, ya
  // revisados por el antivirus, eran 12,6 de sus 13,2 s (medido el 2-nov-2026 con un
  // form del NAS; C14 del revisor del paisaje del cierre de la 1.26)
  LAYOUT_PLAZO_MS = 45000;

{ Lo que dice el renderizador de donde queda cada control de APath: el juez de un
  layout (V74 y V24 de la 1.24). Fallo en R.Fallo, por ejemplo sin renderizador.
  APlazoMs, si hay otra respuesta que dar sin el. }
function CajasDelRender(const APath: string; APlazoMs: Integer = 0): TRespuestaRender;
begin
  var Pet := PeticionDeRender(APath, '');
  Pet.Cajas := True;
  Pet.PlazoMs := APlazoMs;
  Result := CorreRender(Pet);
end;

{ UNA caja de "boxes", con la misma forma para sus tres fuentes (el texto de un form
  VCL, el renderizador en FMX y lo que el renderizador anade al texto VCL): align
  solo cuando se sabe (el texto), visible solo cuando lo dijo el renderizador. }
function CajaJson(const ANombre, AClase, AAlign: string; AConAlign: Boolean; const APadre: string;
  AX, AY, AW, AH, ALinea, AVisible: Integer; const AFichero: string = ''): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ANombre);
  Result.AddPair('class', AClase);
  if AConAlign then
    Result.AddPair('align', AAlign);
  Result.AddPair('parent', APadre);
  Result.AddPair('x', TJSONNumber.Create(AX));
  Result.AddPair('y', TJSONNumber.Create(AY));
  Result.AddPair('w', TJSONNumber.Create(AW));
  Result.AddPair('h', TJSONNumber.Create(AH));
  if AVisible >= 0 then
    Result.AddPair('visible', TJSONBool.Create(AVisible = 1));
  // la linea es de ese fichero, si no es el form (LineaDeCaja)
  if AFichero <> '' then
    Result.AddPair('file', AFichero);
  Result.AddPair('line', TJSONNumber.Create(ALinea));
end;

{ La linea en el form del componente de ARuta (la del renderizador: Edit1, o
  Frame11.Edit1 dentro de un frame en linea, su inherited si el form lo
  sobrescribe); 0 si el form no lo escribe. Por EL buscador del documento: el
  recorrido propio de aqui daba, para el Edit1 del form, el del frame que iba
  antes (revisor del paisaje de la 1.26) }
function LineaEnElForm(ADoc: TStyleDoc; const ARuta: string): Integer;
begin
  var O := ADoc.ObjetoDeNombre(ARuta);
  Result := (if O <> nil then O.StartLine else 0);
end;

{ La linea de la caja C: la del form si el form la escribe (su inherited, si lo
  sobrescribe; AFichero ''), y si no, la del fichero que la escribe - un frame en
  linea, un ancestro: lo dice el renderizador (BOX=) -, con ese fichero en
  AFichero; 0 y '' si no se sabe (Hermes, dirigido de la 1.26: salia line=0 sin
  decir donde estaba) }
function LineaDeCaja(AFicheros: TFicherosDelForm; const C: TCajaDeRender; out AFichero: string): Integer;
var
  Form, Otro: string;
begin
  AFichero := '';
  Result := LineaEnElForm(AFicheros.Doc('', Form), C.Ruta);
  if (Result > 0) or (C.Fichero = '') then
    Exit;
  var D := AFicheros.Doc(C.Fichero, Otro);
  if (D = nil) or (Otro = '') then
    Exit;
  Result := LineaEnElForm(D, C.EnFichero);
  if Result > 0 then
    AFichero := Otro;
end;

{ Donde esta escrito un control, para un aviso de layout: su linea en el form, o su
  linea y el fichero que lo escribe (LineaDeCaja). Los avisos de un control de un
  frame en linea decian "line 0" mientras su caja ya decia el fichero (C9 del
  revisor del paisaje del cierre de la 1.26) }
function DondeDeCaja(ALinea: Integer; const AFichero: string): string;
begin
  if AFichero = '' then
    Result := MsgFmt(SF_DSGN_EN_LINEA_FMT, [ALinea])
  else
    Result := MsgFmt(SF_DSGN_EN_LINEA_DE_FMT, [ALinea, AFichero]);
end;

{ Las cajas medidas por la clave de su ruta (ClaveDeIdentificador, como compara
  nombres el compilador): EL emparejador de un nombre con su caja medida - el del
  padre de una caja y el de la caja del texto VCL. Eran tres cruces con dos reglas
  (SameText y la clave; A2 del revisor del paisaje de la 1.27) }
function CajasPorClave(const ACajas: TArray<TCajaDeRender>): TDictionary<string, TCajaDeRender>;
begin
  Result := TDictionary<string, TCajaDeRender>.Create;
  for var C in ACajas do
    Result.AddOrSetValue(ClaveDeIdentificador(C.Ruta), C);
end;

{ El padre medido de ACaja (en ACajaDe, CajasPorClave) y el rectangulo donde esta
  de verdad, en coordenadas del form: el contenido si no es el padre (el de un
  TTabItem o un TTabSheet, EnContenido). Sin padre medido, el area cliente del
  form, con el nombre ARaiz }
procedure PadreMedido(ACajaDe: TDictionary<string, TCajaDeRender>; const AMedido: TRespuestaRender;
  const ARaiz: string; const ACaja: TCajaDeRender; out APadre: TCajaDeRender; out PX, PY, PW, PH: Integer);
begin
  if (ACaja.Padre = '') or not ACajaDe.TryGetValue(ClaveDeIdentificador(ACaja.Padre), APadre) then
  begin
    APadre := Default(TCajaDeRender);
    APadre.Ruta := ARaiz;
    APadre.W := AMedido.Ancho;
    APadre.H := AMedido.Alto;
    APadre.Visible := True;
  end;
  PX := (if ACaja.EnContenido then ACaja.CX else APadre.X);
  PY := (if ACaja.EnContenido then ACaja.CY else APadre.Y);
  PW := (if ACaja.EnContenido then ACaja.CW else APadre.W);
  PH := (if ACaja.EnContenido then ACaja.CH else APadre.H);
end;

{ EL juez de un layout sobre las cajas que midio el renderizador, el de los dos
  marcos: LayoutFmx y el de LayoutOf eran dos copias que ya divergian - la VCL
  daba las coordenadas de un aviso relativas al padre y FMX absolutas, con el
  mismo texto, y FMX no eximia de "fuera del padre" al que coloca a sus hijos (A2
  del revisor del paisaje de la 1.27). Un control o un padre oculto no se juzga.
  Se dice un lado a cero; lo que se sale de su padre, salvo si el padre coloca a
  sus hijos (ColocaASusHijos) o se desplaza (fcScroll); y dos hermanos que
  comparten area, salvo lo que coloca su padre, el adorno y alCustom. Las
  coordenadas de un aviso, relativas al padre que nombra (el texto dice "y P mide
  W x H"); boxes sigue en las del form. ATexto, la VCL: sus cajas del texto por
  la clave (CajasPorClave), con el Align ESCRITO - o el de su clase, DefaultAlign -,
  que solo nombra el aviso (una banda sin sitio va a ANoRoom, dos alClient lo
  dicen); FMX, nil: su Align no nombra avisos y ANoRoom puede ser nil. AFicheros,
  donde se escribe cada caja. ACajaDe, el indice de AMedido (CajasPorClave): lo hace
  quien llama, que con el mismo nombra el padre de cada caja que lista. }
procedure JuzgaCajas(const AMedido: TRespuestaRender; ACajaDe: TDictionary<string, TCajaDeRender>;
  ATabla: TMetaTable; AFmx: Boolean; const ARaiz: string; AFicheros: TFicherosDelForm;
  ATexto: TDictionary<string, TJSONObject>; AZero, AOutside, AOverlap, ANoRoom: TJSONArray;
  var AFuera: TArray<string>);

  function AlignDe(const ACaja: TCajaDeRender): string;
  var
    Bx: TJSONObject;
    Al: string;
  begin
    if ATexto = nil then
      Exit('');
    if ATexto.TryGetValue(ClaveDeIdentificador(ACaja.Ruta), Bx) and Bx.TryGetValue<string>('align', Al) and
       (Al <> '') then
      Exit(Al);
    Result := DefaultAlign(ATabla, ACaja.Clase);
  end;

  function Donde(const ACaja: TCajaDeRender): string;
  var
    Fichero: string;
  begin
    var Linea := LineaDeCaja(AFicheros, ACaja, Fichero);
    Result := DondeDeCaja(Linea, Fichero);
  end;

begin
  for var I := 0 to High(AMedido.Cajas) do
  begin
    var C := AMedido.Cajas[I];
    if not C.Visible then
      Continue;
    var Padre: TCajaDeRender;
    var PX, PY, PW, PH: Integer;
    PadreMedido(ACajaDe, AMedido, ARaiz, C, Padre, PX, PY, PW, PH);
    if not Padre.Visible then
      Continue;
    var Al := AlignDe(C);
    if (C.W = 0) or (C.H = 0) then
      AZero.Add(MsgFmt(SF_DSGN_LADO_A_CERO_FMT, [C.Ruta, C.Clase, Donde(C), IntToStr(C.W), IntToStr(C.H)]));
    // que coloca a sus hijos (paginas, celdas, flujo) o se desplaza: no se juzga
    var Coloca := (Padre.Clase <> '') and ColocaASusHijos(ATabla, Padre.Clase, AFmx);
    var Desplaza := (Padre.Clase <> '') and EsDeFamilia(ATabla, Padre.Clase, fcScroll, AFmx);
    if not Coloca and not Desplaza and (C.W > 0) and (C.H > 0) and
       ((C.X < PX) or (C.Y < PY) or (C.X + C.W > PX + PW) or (C.Y + C.H > PY + PH)) then
    begin
      if SameText(Al, 'alTop') then
        ANoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FUERA_FMT, [C.Ruta, Donde(C), Padre.Ruta, C.H,
          Max(0, PY + PH - C.Y)]))
      else if SameText(Al, 'alBottom') then
        ANoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FMT, [C.Ruta, Donde(C), Padre.Ruta, C.H,
          Max(0, C.Y + C.H - PY)]))
      else if SameText(Al, 'alLeft') then
        ANoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [C.Ruta, Donde(C), Padre.Ruta, C.W,
          Max(0, PX + PW - C.X)]))
      else if SameText(Al, 'alRight') then
        ANoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [C.Ruta, Donde(C), Padre.Ruta, C.W,
          Max(0, C.X + C.W - PX)]))
      else if not SameText(Al, 'alCustom') then
      begin
        AOutside.Add(MsgFmt(SF_DSGN_OCUPA_SE_SALE_FMT, [C.Ruta, C.Clase, Donde(C), C.X - PX, C.Y - PY,
          C.X - PX + C.W, C.Y - PY + C.H, Padre.Ruta, PW, PH]));
        AFuera := AFuera + [C.Ruta];
      end;
    end;
    // dos hermanos que comparten area, salvo adorno, alCustom y lo que coloca su padre
    if Coloca or (C.W = 0) or (C.H = 0) or SameText(Al, 'alCustom') or
       EsDeFamilia(ATabla, C.Clase, fcAdorno, AFmx) then
      Continue;
    for var J := I + 1 to High(AMedido.Cajas) do
    begin
      var O := AMedido.Cajas[J];
      var AlO := AlignDe(O);
      if O.Visible and MismoIdentificador(O.Padre, C.Padre) and (O.W > 0) and (O.H > 0) and
         not SameText(AlO, 'alCustom') and not EsDeFamilia(ATabla, O.Clase, fcAdorno, AFmx) and
         (C.X < O.X + O.W) and (O.X < C.X + C.W) and (C.Y < O.Y + O.H) and (O.Y < C.Y + C.H) then
      begin
        if SameText(Al, 'alClient') and SameText(AlO, 'alClient') then
          AOverlap.Add(MsgFmt(SF_DSGN_AMBOS_ALCLIENT_FMT, [C.Ruta, Donde(C), O.Ruta, Donde(O), Padre.Ruta]))
        else
          AOverlap.Add(MsgFmt(SF_DSGN_SE_SOLAPAN_FMT, [C.Ruta, Donde(C), O.Ruta, Donde(O), Padre.Ruta,
            Max(C.X, O.X) - PX, Max(C.Y, O.Y) - PY, Min(C.X + C.W, O.X + O.W) - PX,
            Min(C.Y + C.H, O.Y + O.H) - PY]));
      end;
    end;
  end;
end;

{ layout de un form FMX: lo que FMX resuelve, medido; no hay un modelo que imitar
  (Size, Position, Align, Margins, Padding, los estilos). Un control oculto no se
  juzga. Lo que se solapa se dice, y no quita clean: en FMX un control sobre otro es
  como se compone un form, con un TRectangle de fondo y un TText encima. Sin
  renderizador se dice, nunca clean:true (DSGN-027). AFuera: los nombres de lo que
  se sale de su padre, en el orden de outsideParent (ConFueraDelPadre). APlazoMs,
  el de CajasDelRender (LayoutOf). }
function LayoutFmx(const APath: string; out AFuera: TArray<string>; APlazoMs: Integer): string;
var
  Doc: TStyleDoc;
begin
  AFuera := nil;
  Doc := nil;
  Result := LoadDoc(APath, Doc);
  if Result <> '' then
    Exit;
  try
    if Doc.Root = nil then
      Exit(MsgText(SR_DESIGNER_BINDING_NO_ROOT));
    // lo que hace cada contenedor con sus hijos, por su herencia (ClasesDeFamilia):
    // la tabla FMX si ya esta, como la VCL en LayoutOf
    var FaltaFmx: TFaltaTabla;
    var TablaFmx := MetaTable(True, FaltaFmx, 0);
    var R := CajasDelRender(APath, APlazoMs);
    if R.Fallo <> '' then
      Exit(MsgFmt(SR_DESIGNER_LAYOUT_FMX_FMT, [R.Fallo]));
    var Ret := TJSONObject.Create;
    // y los ficheros que escriben lo que no esta en el form (frames, ancestros)
    var Ficheros := TFicherosDelForm.Create(Doc, APath);
    try
      Ret.AddPair('form', Doc.Root.ObjName);
      Ret.AddPair('class', Doc.Root.ClassName_);
      Ret.AddPair('clientWidth', TJSONNumber.Create(R.Ancho));
      Ret.AddPair('clientHeight', TJSONNumber.Create(R.Alto));
      var Zero := TJSONArray.Create;
      Ret.AddPair('zeroSize', Zero);
      var Outside := TJSONArray.Create;
      Ret.AddPair('outsideParent', Outside);
      var Overlap := TJSONArray.Create;
      Ret.AddPair('overlapping', Overlap);
      var Boxes := TJSONArray.Create;
      Ret.AddPair('boxes', Boxes);
      // cada caja con el nombre de su padre (PadreMedido, el del juez; sin padre medido, el form)
      var CajaDe := CajasPorClave(R.Cajas);
      try
        for var C in R.Cajas do
        begin
          var FicheroCaja: string;
          var LineaCaja := LineaDeCaja(Ficheros, C, FicheroCaja);
          var Padre: TCajaDeRender;
          var PX, PY, PW, PH: Integer;
          PadreMedido(CajaDe, R, Doc.Root.ObjName, C, Padre, PX, PY, PW, PH);
          Boxes.AddElement(CajaJson(C.Ruta, C.Clase, '', False, Padre.Ruta, C.X, C.Y, C.W, C.H, LineaCaja,
            Ord(C.Visible), FicheroCaja));
        end;
        // y lo que se juzga, por EL juez de las cajas medidas, el mismo de la VCL (A2 de la 1.27)
        JuzgaCajas(R, CajaDe, TablaFmx, True, Doc.Root.ObjName, Ficheros, nil, Zero, Outside, Overlap, nil, AFuera);
      finally
        CajaDe.Free;
      end;
      if Length(R.Sustituidas) + Length(R.SinLeer) > 0 then
        Ret.AddPair('partialNote', MsgFmt(SN_DESIGNER_LAYOUT_A_MEDIAS_FMT, [string.Join(', ', R.Sustituidas + R.SinLeer)]));
      Ret.AddPair('clean', TJSONBool.Create((Zero.Count = 0) and (Outside.Count = 0)));
      Ret.AddPair('howMeasured', MsgText(SN_DESIGNER_LAYOUT_FMX_HOW));
      Result := Ret.ToJSON;
    finally
      Ficheros.Free;
      Ret.Free;
    end;
  finally
    Doc.Free;
  end;
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
  govern RESIZE - are not what this measures. Con renderizador, las cajas Y lo que se
  juzga salen de lo que resuelve la VCL (V24 de la 1.24: la banda de pestanas de un
  TPageControl no la descontaba; R8 de la 1.27: lo juzgado seguia saliendo de este
  texto; JuzgaCajas, el juez de los dos marcos); este texto, cuando no lo hay. FMX, LayoutFmx. AConOtraRespuesta: la
  llamada ya tiene su respuesta (insert, set parent=), y el renderizador FMX espera lo
  que el de la VCL, LAYOUT_PLAZO_MS (C9 del revisor del paisaje del cierre de la 1.26). }
function LayoutOf(const APath: string; out AFuera: TArray<string>; AConOtraRespuesta: Boolean = False): string;
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
      not SameText(DefaultAlign(TablaVcl, AObj.ClassName_), 'alNone') or EsControl(AObj);
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
    Grid := EsDeFamilia(TablaVcl, AParent.ClassName_, fcCeldas, False);
    // "managed" = the parent places its children itself (grid cells, flow
    // reflow, relative rules, page tabs): design Left/Top and sibling overlap
    // mean nothing there, so we do not judge them.
    Managed := ColocaASusHijos(TablaVcl, AParent.ClassName_, False);
    RL := 0; RT := 0; RR := AClientW; RB := AClientH;
    ClientN := 0;
    SetLength(Kids, AParent.Children.Count);
    Cnt := 0;
    for K := 0 to AParent.Children.Count - 1 do
    begin
      Kid := AParent.Children[K];
      if not IsVisual(Kid) then Continue;
      if not Vis(Kid) then Continue;      // the VCL does not lay out the hidden
      // por SU ruta (Frame1.Edit1 dentro de un frame en linea), la que da el
      // renderizador y con la que se cruzan las cajas: por el nombre a secas,
      // lo sobrescrito en un frame tomaba el rectangulo de un homonimo del
      // form (revisor del paisaje de la 1.27, medido)
      Nm := Kid.Ruta; if Kid.ObjName = '' then Nm := Kid.ClassName_;
      Cls := Kid.ClassName_;
      Align := PropRaw(Doc, Kid, 'Align', Found);
      if not Found then Align := DefaultAlign(TablaVcl, Cls);
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
          Zero.Add(MsgFmt(SF_DSGN_LADO_A_CERO_FMT, [Nm, Cls, DondeDeCaja(Kid.StartLine, ''),
            IfThen(HasW, IntToStr(W), '?'), IfThen(HasH, IntToStr(H), '?')]));
        if (NeedW and not HasW) or (NeedH and not HasH) then
          // un control sin tamano en el .dfm tiene el de su constructor: lo
          // que deja el insert de delphi_designer, como el IDE
          if not HasW and not HasH and SameText(Align, 'alNone') and EsControl(Kid) then
            Unknown.Add(MsgFmt(SF_DSGN_TAMANO_DEL_CONSTRUCTOR_FMT, [Nm, Cls, DondeDeCaja(Kid.StartLine, '')]))
          else
            Unknown.Add(MsgFmt(SF_DSGN_NO_LLEVA_EN_DFM_FMT, [Nm, Cls, DondeDeCaja(Kid.StartLine, ''),
              IfThen(NeedW and not HasW, 'Width', 'Height'), Align]));
      end;
      if W < 0 then W := 0;
      if H < 0 then H := 0;

      Kids[Cnt].Nm := Nm; Kids[Cnt].Cls := Cls; Kids[Cnt].Align := Align;
      Kids[Cnt].Line := Kid.StartLine; Kids[Cnt].HasW := HasW; Kids[Cnt].HasH := HasH;
      // decoration, alCustom (runtime position), and an unresolved inherited
      // control are all left OUT of overlap: none of them is "one hides another".
      Kids[Cnt].Deco := EsDeFamilia(TablaVcl, Cls, fcAdorno, False) or SameText(Align, 'alCustom') or InhUnknown;
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
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FUERA_FMT, [Nm, DondeDeCaja(Kid.StartLine, ''),
            AWhere, H, Max(0, RB - RT - MgnT)]));
        RT := Min(RB, RT + MgnT + H + MgnB);
      end
      else if SameText(Align, 'alBottom') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := Max(RT, RB - MgnB - H);
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RB - MgnB - H - MgnT < RT) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ALTO_FMT, [Nm, DondeDeCaja(Kid.StartLine, ''), AWhere, H, Max(0, RB - RT - MgnB)]));
        RB := Max(RT, RB - MgnB - H - MgnT);
      end
      else if SameText(Align, 'alLeft') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RL + MgnL + W; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RL + MgnL + W + MgnR > RR) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [Nm, DondeDeCaja(Kid.StartLine, ''), AWhere, W, Max(0, RR - RL - MgnL)]));
        RL := Min(RR, RL + MgnL + W + MgnR);
      end
      else if SameText(Align, 'alRight') then
      begin
        Kids[Cnt].X1 := Max(RL, RR - MgnR - W); Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RR - MgnR - W - MgnL < RL) then
          NoRoom.Add(MsgFmt(SF_DSGN_NO_CABE_ANCHO_FMT, [Nm, DondeDeCaja(Kid.StartLine, ''), AWhere, W, Max(0, RR - RL - MgnR)]));
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
        begin
          Outside.Add(MsgFmt(SF_DSGN_OCUPA_SE_SALE_FMT, [Nm, Cls,
            DondeDeCaja(Kid.StartLine, ''), X, Y, X + W, Y + H, AWhere, AClientW, AClientH]));
          AFuera := AFuera + [Nm];
        end;
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
      Boxes.AddElement(CajaJson(Kids[K].Nm, Kids[K].Cls, Kids[K].Align, True, AWhere, AAbsX + Kids[K].X1,
        AAbsY + Kids[K].Y1, Kids[K].X2 - Kids[K].X1, Kids[K].Y2 - Kids[K].Y1, Kids[K].Line, -1));
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
                Overlap.Add(MsgFmt(SF_DSGN_AMBOS_ALCLIENT_FMT, [Kids[K].Nm, DondeDeCaja(Kids[K].Line, ''),
                  Kids[J].Nm, DondeDeCaja(Kids[J].Line, ''), AWhere]))
              else
                Overlap.Add(MsgFmt(SF_DSGN_SE_SOLAPAN_FMT,
                  [Kids[K].Nm, DondeDeCaja(Kids[K].Line, ''), Kids[J].Nm, DondeDeCaja(Kids[J].Line, ''), AWhere,
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
            EsDeFamilia(TablaVcl, Kids[K].Cls, fcScroll, False));
      end;
      Inc(K);
    end;
  end;

  // lo que dijo la aritmetica del texto, fuera: con las cajas medidas lo juzgado sale
  // de ellas (R8 de la 1.27), por EL juez de los dos marcos (JuzgaCajas, A2)
  procedure Vacia(AArr: TJSONArray);
  begin
    while AArr.Count > 0 do
      AArr.Remove(0).Free;
  end;

begin
  AFuera := nil;
  Doc := nil;
  // de que marco es, por EL juez (un .dfm de un modulo de datos de FMX tambien
  // es FMX): layout solo mide la VCL
  if not EsDesignerVcl(APath) then
  begin
    // sin otra respuesta, la del renderizador es la unica: el plazo de un preview
    if EsDesignerFmx(APath) then
      Exit(LayoutFmx(APath, AFuera, (if AConOtraRespuesta then LAYOUT_PLAZO_MS else 0)));
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

      // donde quedan de verdad, si el renderizador contesta: lo resuelto del texto es
      // aproximado (V24 de la 1.24)
      // con un plazo propio: aqui hay respuesta sin el, y un paquete que cuelga no
      // puede costar lo que un preview
      var Medido := CajasDelRender(APath, LAYOUT_PLAZO_MS);
      if Medido.Fallo = '' then
      begin
        // cada caja medida con la del texto por la clave de su nombre, la de CajasPorClave
        // (EL emparejador: eran tres cruces con dos reglas, A2 de la 1.27). La del texto toma
        // el rectangulo medido; lo que el texto no lista -un frame inline y lo que lleva
        // dentro- entra con lo que el renderizador midio, con la linea de su bloque, en el
        // form o en el fichero del frame (LineaDeCaja), y el nombre de su padre, el del
        // juez (PadreMedido) (dirigido de Hermes de la 1.24, punto 4; el fichero, el de la 1.26)
        var DelTexto := TDictionary<string, TJSONObject>.Create;
        var CajaDe := CajasPorClave(Medido.Cajas);
        var Ficheros := TFicherosDelForm.Create(Doc, APath);
        try
          for var B := 0 to Boxes.Count - 1 do
          begin
            var Bx := Boxes.Items[B] as TJSONObject;
            DelTexto.AddOrSetValue(ClaveDeIdentificador(Bx.GetValue<string>('name')), Bx);
          end;
          for var C in Medido.Cajas do
          begin
            var Bx: TJSONObject;
            if DelTexto.TryGetValue(ClaveDeIdentificador(C.Ruta), Bx) then
            begin
              Bx.RemovePair('x').Free;
              Bx.RemovePair('y').Free;
              Bx.RemovePair('w').Free;
              Bx.RemovePair('h').Free;
              Bx.AddPair('x', TJSONNumber.Create(C.X));
              Bx.AddPair('y', TJSONNumber.Create(C.Y));
              Bx.AddPair('w', TJSONNumber.Create(C.W));
              Bx.AddPair('h', TJSONNumber.Create(C.H));
            end
            else if C.Visible then
            begin
              var FicheroCaja: string;
              var LineaCaja := LineaDeCaja(Ficheros, C, FicheroCaja);
              var Padre: TCajaDeRender;
              var PX, PY, PW, PH: Integer;
              PadreMedido(CajaDe, Medido, Doc.Root.ObjName, C, Padre, PX, PY, PW, PH);
              Boxes.AddElement(CajaJson(C.Ruta, C.Clase, '', False, Padre.Ruta, C.X, C.Y, C.W, C.H,
                LineaCaja, -1, FicheroCaja));
            end;
          end;
          // y lo que se juzga, sobre lo medido (R8), por EL juez de los dos marcos (A2); el
          // area cliente, la que pinto
          Vacia(Zero);
          Vacia(Outside);
          Vacia(Overlap);
          Vacia(NoRoom);
          Vacia(Unknown);
          AFuera := nil;
          JuzgaCajas(Medido, CajaDe, TablaVcl, False, Doc.Root.ObjName, Ficheros, DelTexto, Zero, Outside, Overlap,
            NoRoom, AFuera);
        finally
          Ficheros.Free;
          CajaDe.Free;
          DelTexto.Free;
        end;
        if (Medido.Ancho > 0) and (Medido.Alto > 0) then
        begin
          Ret.RemovePair('clientWidth').Free;
          Ret.RemovePair('clientHeight').Free;
          Ret.RemovePair('clientEstimated').Free;
          Ret.AddPair('clientWidth', TJSONNumber.Create(Medido.Ancho));
          Ret.AddPair('clientHeight', TJSONNumber.Create(Medido.Alto));
          Estimated := False;
        end;
        Ret.AddPair('boxesFrom', 'renderer');
      end
      else
      begin
        Ret.AddPair('boxesFrom', 'text');
        Ret.AddPair('boxesNote', MsgFmt(SN_DESIGNER_LAYOUT_DEL_TEXTO_FMT, [Medido.Fallo]));
      end;

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

{ ADesde: el instante en que empezo la llamada (EmpiezaLaEspera): el lector del IDE
  tiene lo que le queda a su cliente, como tras una edicion (A3 de la 1.27); tenia el
  plazo de un preview }
function LintForm(const APath: string; ADesde: UInt64): string;
var
  Denied, EncName, Text: string;
  Warns: TArray<string>;
begin
  Denied := EntradaDeFormDenegada(APath, False);
  if Denied <> '' then
    Exit(Denied);
  // Un .dfm binario se lee al vuelo (Lsp.DesignerBin); uno danado se rechaza.
  // (por EL lector de designers, Lsp.Patch.TextoDeDesigner)
  var Motivo := TextoDeDesigner(APath, Text, EncName);
  if Motivo <> '' then
    Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Motivo));
  // EL lint de un form (Lsp.Patch.LintDeForm): tablas del framework + el
  // form contra su clase (check-binding) + EL parser del IDE con los bytes
  // del fichero, lo PRIMERO y con o sin tabla (8.10 de la 1.18.0); un
  // binario ya paso su conversion. lint = todo lo que el compilador no mira
  // ...y lo que la tabla no sabe juzgar (lo que la clase guarda por codigo),
  // el lector del IDE: CLEAN solo si carga (DSGN-061 de la 1.20)
  var L := LintDeForm(APath, Text, EncName, not IsBinaryDesigner(APath), ESPERA_TABLA_MS, True, '', ADesde);
  var Falta := L.Falta;
  var Notas := L.Notas;
  Warns := L.Propiedades + L.Lector + L.Enlace;
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
  if (Length(Warns) = 0) and (Length(Notas) = 0) and (L.SinLector = '') and (Length(L.Lookups) = 0) and
     (Length(L.Colores) = 0) and (Length(L.Literales) = 0) then
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
    // un StyleLookup que ningun estilo que el form ve define: no CLEAN, pero
    // nota, no aviso (V75 de la 1.23.1)
    if Length(L.Lookups) > 0 then
    begin
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + string.Join(#13#10, L.Lookups);
    end;
    // un color de menos de 8 cifras: no CLEAN, nota como la de arriba (V154)
    if Length(L.Colores) > 0 then
    begin
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + string.Join(#13#10, L.Colores);
    end;
    // un literal que preview niega: no CLEAN, nota como las de arriba
    if Length(L.Literales) > 0 then
    begin
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + string.Join(#13#10, L.Literales);
    end;
    // sin el lector no se dice CLEAN de lo que solo el sabe juzgar
    if L.SinLector <> '' then
    begin
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + MsgFmt(SN_DESIGNER_LINT_SIN_LECTOR_FMT, [PorQueAlLector(L), L.SinLector]);
    end;
  end;
  // lo que dice CLEAN no habla de ellos, y un agente lo leia como "lookups bien" (V156)
  if L.LookupsSinJuzgar > 0 then
    Result := Result + #13#10 + MsgFmt(SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT, [L.LookupsSinJuzgar]);
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
  K: TEncKind;
begin
  Result := EntradaDeFormDenegada(APath, True);
  if Result <> '' then
    Exit;
  Ruta := TPath.GetFullPath(APath);
  B := TFile.ReadAllBytes(Ruta);
  Forma := DesignerShapeOf(B);
  // un form de TEXTO en UTF-16 o UTF-32, que el IDE no carga (A28 de la 1.23)
  var Ancho := (Forma = dsText) and KindDeBom(B, K) and (K in ENC_ANCHAS);
  // un .fmx es texto siempre; uno ancho si se convierte, al texto que escribe
  // el IDE: es la salida que da DSGN-122, tambien para un .fmx
  if EsDesignerFmx(Ruta) and not (AToText and Ancho) then
    Exit(MsgText(SR_DESIGNER_FMX_ALWAYS_TEXT));
  if AToText then
  begin
    if (Forma = dsText) and not Ancho then
      Exit(MsgFmt(SN_DESIGNER_ALREADY_FMT, [TPath.GetFileName(Ruta), MsgText(SF_DSGN_TEXTO)]));
    // el binario, por EL conversor del IDE; el ancho, leido en UTF-8 por su
    // parser y escrito por ese mismo conversor: la salida que dice DSGN-122
    // (David, 24-oct-2026: un form asi ya no lo abre el IDE para arreglarlo)
    if Ancho then
      Err := TextoDeFormAncho(B, Texto)
    else
      Err := DesignerBinaryToText(B, Texto);
    if Err <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    // el fichero ENTERO cambia de forma: su contenido actual, sellado
    Copia := MaskDriveText('', GuardaContenidoActual(Ruta));
    // un nombre no ASCII va en UTF-8 CON BOM, como lo guarda el IDE (sin el,
    // TParser y dcc lo leen en ANSI); lo demas del texto es ASCII (#N).
    // ANuevo: el fichero ENTERO cambia de forma y lo que hay en el disco -el
    // binario, ya sellado arriba- no cuenta: la ida y vuelta de los escritores
    // lo leia como un texto ANSI y en una maquina de doble byte (932/936/949/
    // 950) o con 65001 no volvia igual y se negaba (codificacion M3 del revisor
    // de version de la 1.18.0)
    if IsAscii(Texto) then
      PatchSaveText(Ruta, Texto, EncName(ekUtf8), False, True)
    else
      PatchSaveText(Ruta, Texto, EncName(ekUtf8Bom), False, True);
    if Ancho then
    begin
      var Como := MsgText(SF_DSGN_TOTEXT_UTF8BOM);
      if IsAscii(Texto) then
        Como := MsgText(SF_DSGN_TOTEXT_ASCII);
      Exit(MsgFmt(SN_DESIGNER_TOTEXT_ANCHO_FMT, [TPath.GetFileName(Ruta), EncName(K), Como,
        Length(LineasDelTexto(Texto)), Copia]));
    end;
    Result := MsgFmt(SN_DESIGNER_TOTEXT_FMT, [TPath.GetFileName(Ruta), Length(B),
      Length(LineasDelTexto(Texto)), Copia]);
  end
  else
  begin
    if Forma <> dsText then
      Exit(MsgFmt(SN_DESIGNER_ALREADY_FMT, [TPath.GetFileName(Ruta), MsgText(SF_DSGN_BINARIO)]));
    // un form que el IDE no carga no se convierte: se convertia pasandolo antes
    // a UTF-8 o a UTF-16 (A28 de la 1.23)
    if Ancho then
    begin
      Err := FormAnchoQueNoCarga(Ruta);
      if Err <> '' then
        Exit(Err);
    end;
    // la regla de ida y vuelta de los escritores (ReescrituraDenegada): un
    // form roto -un BOM de UTF-8 con el cuerpo en CP1252- se convertiria, con
    // el lector tolerante, con U+FFFD donde estan sus acentos; con el estricto
    // de la 1.17 reventaba (SYS-006). Revisor propio de la 4.1. Los bytes ya
    // leidos, sin leer otra vez
    Err := ReescrituraDenegada(Ruta, B, K);
    if Err <> '' then
      Exit(Err);
    // los BYTES de disco, no el texto decodificado: el parser los lee como
    // el IDE y dcc (M2, punto 4 de la 1.18.2)
    Err := DesignerTextToBinary(B, Bin);
    if Err <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    Copia := MaskDriveText('', GuardaContenidoActual(Ruta));
    AtomicWrite(Ruta, Bin);
    Result := MsgFmt(SN_DESIGNER_TOBINARY_FMT, [TPath.GetFileName(Ruta), Length(Bin), Copia]);
  end;
end;

{ La nota de codificacion de un form en la respuesta de lint y en la de cada
  escritura del disenador (insert, set, delete): la de uno SIN BOM cuyos bytes
  son UTF-8 (READ-009). Un form de texto en UTF-16 o UTF-32 ya no llega aqui:
  lo niegan antes (DSGN-122, A28 de la 1.23). Una respuesta que es un fallo se
  queda como esta. }
function ConNotaDeFormAncho(const AResult, APath: string): string;
begin
  Result := AResult;
  try
    // LA nota (Lsp.Patch.NotaDeCodificacionDeForm): la del form ancho o, si
    // no, la de uno SIN BOM cuyos bytes son UTF-8 (READ-009; lint daba CLEAN,
    // medido con dcc el 13-oct); preview y el lint de delphi_edit la
    // componian por su cuenta (W9 del revisor de cierre)
    if not EsFallo(Result) then
      Result := ConNota(Result, 'encodingNote', NotaDeCodificacionDeForm(TPath.GetFullPath(APath)));
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
  dibuja SIEMPRE en un temporal nuestro y se recorta ahi (RecortaPngBytes con
  el RECT= del componente, leido y escrito por las puertas de su casa de
  entregables); con out= se lleva despues a su sitio: el
  renderizador nunca escribe en la jaula por su cuenta. }
function PreviewDeForm(const Params: TDelphiDesignerParams): string;
var
  Ruta, Fw, Estilo, Propia, Temporal, Fallo: string;
  Peticion: TPeticionRender;
  R: TRespuestaRender;
  Return, Raiz, Ms: TJSONObject;
  NoVis: TJSONArray;
  RX, RY, RW, RH, AnchoOrig, AltoOrig, OX, OY: Integer;
  Recortada: Boolean;
  Estados: TArray<string>;
  Recorte: TArray<Byte>;

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
  // un form de texto en UTF-16 o UTF-32 no lo carga el IDE (lo niega su
  // parser): se dice antes de lanzar nada, con la causa y la salida (A28 de
  // la 1.23; un UTF-16 se dibujaba convertido)
  Fallo := FormAnchoQueNoCarga(Ruta);
  if Fallo <> '' then
    Exit(Fallo);
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

  // por stdio, inline=false sin out= no tendria por donde salir: se niega
  // antes de dibujar (2ai de la 1.18.2)
  Fallo := CapturaSinSalidaDenegada(Params.Inline_, Params.Out_);
  if Fallo <> '' then
    Exit(Fallo);
  // donde cae: el out= de toda la familia de capturas (CaptureTarget). Se
  // dibuja en un temporal nuestro aunque haya out=
  var EnLaCasa: Boolean;
  Fallo := CaptureTarget(Params.Out_, CAPTURE_SUB_DESIGNER, 'designer', CAPTURE_EXT, Propia, EnLaCasa);
  if Fallo <> '' then
    Exit(Fallo);
  Temporal := Propia;
  if not EnLaCasa then // un out=: lo dice EL que lo decide (CaptureTarget)
  begin
    Fallo := CaptureTarget('', CAPTURE_SUB_DESIGNER, 'designer', CAPTURE_EXT, Temporal);
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
    // en memoria, leido y escrito por las puertas: el temporal vive en la casa
    // de los entregables (ltEntregables), que juzga su nombrador - la jaula le
    // negaria __delphi-temp a un agente confinado. Se releia y se reescribia
    // en sitio sin ninguna (1.18.2, 2b)
    try
      Fallo := RecortaPngBytes(LeeBytes(Temporal, LUGARES_DE_UNA_CAPTURA), RX, RY, RW, RH,
        AnchoOrig, AltoOrig, Recorte);
      if Fallo = '' then
        EscribeBytes(Temporal, Recorte, ltEntregables);
    except
      on E: Exception do
        Fallo := E.Message;
    end;
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
    // (una excepcion de aqui a la entrega -IgnoradasConLinea, el tamano- dejaba
    // la captura NUESTRA en la casa: se consume y se relanza; 2ai-B b de la
    // 1.18.2. El cuerpo, sin reindentar)
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
    // LA nota de codificacion, por su casa (W9 del revisor de cierre: preview
    // la componia a mano y sin READ-009)
    var NotaEnc := NotaDeCodificacionDeForm(Ruta);
    if NotaEnc <> '' then
      Return.AddPair('encodingNote', NotaEnc);
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
      // lo que publica una clase del USUARIO en la raiz no lo lee el
      // renderizador (no carga sus clases): se dice cual es, que no es un
      // error del form (1.19.2). Y lo que es de la clase de la RAIZ y no de la
      // form en la que la lee (un TQuickRep, un TForm3D, un modulo de datos
      // FMX: DSGN-157, corpus del 18-oct-2026). EL juicio, el de lo que no
      // carga: Lsp.FormRender.IgnoradaDelUsuario y DeLaRaizQueElLectorNoVe
      var Suyas := '';
      var NoVistas := '';
      var NoConfirmadas := '';
      var DelForm := 0;
      var RaizL := RaizParaElLector(Ruta, R.RaizClase, Fw = 'fmx');
      var Sustituto := ClaseDelSustituto(R.RaizTipo);
      // los documentos de lo leido: el form y el frame o el ancestro en el que esta
      // escrito lo que se salto (EL localizador: Lsp.FormRender.TFicherosDelForm)
      var DocP: TStyleDoc := nil;
      try
        if TStyleDoc.Lee(Ruta, DocP) <> '' then
          DocP := nil;
      except
        DocP := nil; // sin documento: lo saltado, sin linea
      end;
      var Ficheros := TFicherosDelForm.Create(DocP, Ruta);
      try
      Return.AddPair('ignored', IgnoradasConLinea(Ficheros, R.Ignoradas));
      // las partes de una clase del proyecto, en el documento de lo saltado (el
      // juicio es el del lint: Lsp.FormRender.PartesDeClaseNoInstalada)
      for var Ig in R.Ignoradas do
      begin
        var Suya: TPropiedadDelUsuario;
        var PropCn, ClaseCn, Otro: string;
        if IgnoradaDelUsuario(R.RaizNombre, Ig, RaizL.Propias, Suya) then
        begin
          Suyas := Suyas + IfThen(Suyas <> '', ', ') + Ig.Propiedad + ' (' + Suya.Clase + ', ' +
            TPath.GetFileName(Suya.Fichero) + ')';
          Inc(DelForm);
        end
        else if (R.RaizNombre <> '') and SameText(Ig.Componente, R.RaizNombre) and
                DeLaRaizQueElLectorNoVe(RaizL, Sustituto, Ig.Propiedad) then
          NoVistas := NoVistas + IfThen(NoVistas <> '', ', ') + Ig.Propiedad
        // una excepcion del codigo de un componente (no del lector), o bajo las
        // partes de una clase del proyecto: no es del fichero que se sepa
        else if DelCodigoDeUnComponente(Ig) or
                PartesDeClaseNoInstalada(Ficheros.Doc(Ig.Fichero, Otro), Ig, Fw = 'fmx', PropCn, ClaseCn) then
          NoConfirmadas := NoConfirmadas + IfThen(NoConfirmadas <> '', ' | ') + TextoDeIgnorada(Ig)
        // un frame que se contiene a si mismo no es una propiedad con su linea:
        // RENDER-026 ya dice su fichero y que hacer (Hermes, dirigido de la 1.26)
        else if not EsFrameCiclico(Ig) then
          Inc(DelForm);
      end;
      finally
        Ficheros.Free;
        DocP.Free;
      end;
      // leido sin un ancestro: lo saltado puede ser solo lo que el aporta, y
      // "no abrira" seria falso (una vista FMX sin su maestro, 18-oct-2026); y si todo
      // lo saltado es de la raiz que el lector no ve, tampoco
      if Length(R.SinLeer) > 0 then
        Return.AddPair('ignoredNote', MsgFmt(SN_DESIGNER_PREVIEW_IGNORADAS_PARCIAL_FMT,
          [string.Join(', ', R.SinLeer)]))
      else if DelForm > 0 then
        Return.AddPair('ignoredNote', MsgText(SN_DESIGNER_PREVIEW_IGNORADAS));
      if NoVistas <> '' then
        Return.AddPair('ignoredRootNote', MsgFmt(SN_DESIGNER_PREVIEW_RAIZ_NO_VISTA_FMT,
          [Sustituto, RaizL.Clase, Sustituto, NoVistas]));
      if NoConfirmadas <> '' then
        Return.AddPair('ignoredUnconfirmedNote', MsgFmt(SN_DESIGNER_PREVIEW_IGNORADAS_NO_CONFIRMADAS_FMT,
          [NoConfirmadas]));
      if Suyas <> '' then
        Return.AddPair('ignoredUserNote', MsgFmt(SN_DESIGNER_PREVIEW_DEL_USUARIO_FMT, [Suyas]));
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
    // ('screenshot' y su tamano los pone DeliverCapture, para toda tool que
    // capture; A20)
    // UN SOLO PASO, como toda captura: inline (y su temporal consumido) o
    // fichero + enlace. El frame lleva el origen del recorte: pixeles de la
    // imagen -> unidades de la form, sin cuentas del agente
    DeliverCapture('delphi_designer', Propia, Params.Inline_, Params.MaxWidth,
      OX, OY, 1.0, 1.0, Return, MsgText(SN_DESIGNER_INLINE_NOTE_FMT),
      MsgText(SN_DESIGNER_FRAME_NOTE));
    Result := Return.ToJSON;
    except
      if CapturaConsumible(Propia) then
        ConsumeAgentCapture(Propia);
      raise;
    end;
  finally
    Return.Free;
  end;
end;

{ insert y set parent=: si el control cae fuera del area de su padre, la
  respuesta lo dice - lo que calcula layout, aqui al lado (David, 4-oct-2026),
  tambien en FMX, que layout mide desde la 1.24. Lo suyo, por los NOMBRES que
  layout da con sus avisos: se leia el texto del aviso por su prefijo, y un .fmx
  pasaba tal cual con la razon de antes (revisor del paisaje de la 1.26, G). Un
  fallo pasa tal cual. La respuesta ya esta escrita: el renderizador, con el plazo
  de layout, no el de un preview (C9 del revisor del paisaje del cierre de la 1.26). }
function ConFueraDelPadre(const AResult, APath: string): string;
var
  Ret, Lay: TJSONObject;
  Fuera, Suyas: TJSONArray;
  Nombre: string;
  Nombres: TArray<string>;
begin
  Result := AResult;
  if EsFallo(AResult) then
    Exit;
  Ret := ObjetoJson(AResult);
  if Ret = nil then
    Exit;
  try
    if not (Ret.TryGetValue<string>('inserted', Nombre) or Ret.TryGetValue<string>('moved', Nombre)) then
      Exit;
    Lay := ObjetoJson(LayoutOf(APath.Trim, Nombres, True));
    if Lay = nil then
      Exit;
    try
      Suyas := nil;
      if Lay.TryGetValue<TJSONArray>('outsideParent', Fuera) then
        for var I := 0 to Min(Fuera.Count, Length(Nombres)) - 1 do
          if MismoIdentificador(Nombres[I], Nombre) then // como se comparan dos nombres (A2 de la 1.27)
          begin
            if Suyas = nil then
            begin
              Suyas := TJSONArray.Create;
              Ret.AddPair('outsideParent', Suyas);
            end;
            Suyas.Add(Fuera.Items[I].Value);
          end;
    finally
      Lay.Free;
    end;
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ El gesto; ExecuteWithParams lo envuelve en el cerrojo de escritura. ADesde: el
  instante en que empezo la llamada (EmpiezaLaEspera), el plazo de su cliente. }
function GestoDeDisenador(const Params: TDelphiDesignerParams; ADesde: UInt64): string;
var
  Cmd, Fw: string;
begin
  Cmd := SinMayusculas(Params.Command.Trim);
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
  var Suyos, VaCon: string;
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
     'index', IfThen(Params.Index >= 0, IntToStr(Params.Index)), ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_DESIGNER_NO_VA_CON_COMANDO_FMT, [Sobra, Modo, Modo, Suyos]) + VaCon);
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
    begin
      var Fuera: TArray<string>;
      Result := LayoutOf(Params.Path, Fuera);
    end
    else if Cmd = 'tree' then
      Result := TreeOf(Params.Path, Params.MaxDepth) // (un negativo lo niega la capa de parametros, SYS-016)
    else if Cmd = 'lint' then
    begin
      // un form que el IDE no carga, antes que nada - tras la puerta de leer:
      // fuera de ella lo dice LintForm (A28 de la 1.23)
      Result := '';
      if ReadPathDenied(TPath.GetFullPath(Params.Path)) = '' then
        Result := FormAnchoQueNoCarga(TPath.GetFullPath(Params.Path));
      if Result = '' then
        Result := ConNotaDeFormAncho(LintForm(Params.Path, ADesde), Params.Path);
    end
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
    // un form que el IDE no carga no se edita con el disenador (A28 de la
    // 1.23: se escribia, con una nota que decia que el IDE lo abria). Tras la
    // puerta de leer: fuera de ella lo dice el escritor
    if ReadPathDenied(TPath.GetFullPath(Params.Path)) = '' then
    begin
      Result := FormAnchoQueNoCarga(TPath.GetFullPath(Params.Path));
      if Result <> '' then
        Exit;
    end;
    if Cmd = 'insert' then
      Result := ConFueraDelPadre(InsertaComponente(Params.Path, Params.ClassName_,
        Params.Component, Params.Parent, Params.Props), Params.Path)
    else if Cmd = 'set' then
      Result := ConFueraDelPadre(CambiaPropiedad(Params.Path, Params.Component,
        Params.Prop, Params.Value, Params.Parent, Params.Props, Params.Before,
        Params.After, Params.Index), Params.Path)
    else
      Result := BorraComponente(Params.Path, Params.Component);
    // ...y la nota de codificacion que dice lint, tras escribir (r5-L3 de la
    // 1.18.0: solo la decian lint y preview)
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
  // la llamada empieza: lo que espera su cliente cuenta desde aqui, y viaja hasta el
  // lector del IDE del lint (A3 de la 1.27)
  var Desde := EmpiezaLaEspera;
  // to-text y to-binary reescriben el .dfm entero, e insert/set/delete el form
  // y su unidad: son ediciones como cualquier otra y van bajo el mismo
  // cerrojo. Los de LECTURA no: info, prop y lint pueden esperar a la tabla
  // del disenador mientras se genera (Lsp.DesignerMetaGen), y con el cerrojo
  // cogido paraban todas las ediciones del servidor (revision de la 1.12.0);
  // leen como delphi_read, que tampoco lo coge (lo que se escribe se escribe
  // entero o nada).
  Cmd := SinMayusculas(Params.Command.Trim);
  if not MatchText(Cmd, ['to-text', 'to-binary', 'totext', 'tobinary', 'insert', 'set', 'delete']) then
    Exit(GestoDeDisenador(Params, Desde));
  // el orden entre hermanos pregunta al renderizador (segundos con paquetes):
  // FUERA del cerrojo, que coge el mismo solo para releer y escribir; dentro
  // paraba todas las ediciones del servidor (revisor 5 de la noche, A3). Y
  // insert y set parent=, que le preguntan desde el 17f4edd donde dejar el
  // bloque (AbreFormParaJuzgar / CambioDesdeQueSeJuzgo): se quedaron dentro y
  // el juez corria con el cerrojo (revisor del 17f4edd, A1: un textedit de
  // otro fichero esperaba al insert). Y set entero desde la V173c de la
  // 1.23.1: el simple, props y Name juzgaban con el cerrojo (el ayudante del
  // IDE, el motor de la clase raiz y de los heredados), y un set de una Sample
  // con paquetes paro 87 s todas las ediciones del servidor; ahora cogen el
  // cerrojo ellos, solo para leer y para escribir (AbreFormParaJuzgar)
  if MatchText(Cmd, ['set', 'insert']) then
    Exit(GestoDeDisenador(Params, Desde));
  // la tabla que piden insert, set (parent= y Name tambien) y delete se
  // espera FUERA del cerrojo, por lo mismo: set parent= la esperaba dentro y
  // paraba todas las ediciones mientras se generaba (revision de la 1.17.0)
  if MatchText(Cmd, ['insert', 'set', 'delete']) and
     (MetaTable(EsDesignerFmx(Params.Path), Falta) = nil) and
     (Falta.Negativa <> '') then
    Exit(Falta.Negativa);
  EnterFileEdit;
  try
    Result := GestoDeDisenador(Params, Desde);
  finally
    LeaveFileEdit;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_designer',
    function: IMCPTool begin Result := TDelphiDesignerTool.Create; end);

end.
