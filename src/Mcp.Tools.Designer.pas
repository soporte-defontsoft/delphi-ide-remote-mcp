unit Mcp.Tools.Designer;

{ delphi_designer, phase 1 (READ + LINT): structured answers about forms and
  components, so an agent never guesses what a .dfm/.fmx may contain.

    info  <class>            what the framework really publishes for a class
                             (properties with kind and type, events apart) -
                             straight from the GENERATED RTTI tables the
                             designer lint already uses (tools/
                             designer-meta-dump: the framework describing
                             itself, nothing hand-written).
    prop  <class> <prop>     one property in detail: type, kind, and the
                             legal members when it is an enum or a set.
    tree  <file>             the component tree of a TEXT .dfm/.fmx
                             (name, class, line, children).
    get   <file> <component> one component's block, verbatim.
    lint  <file>             the designer lint on demand: unknown classes,
                             properties the class does not publish, enum
                             values that do not exist.

  Binary designer files (TPF0) are refused, as everywhere else in this
  server. Editing commands (set-property, add-component, bind-event) are
  phase 2, and will go through delphi_changeset. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

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
  public
    [SchemaDescription(SP_DESIGNER_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_DESIGNER_PATH)]
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
  Lsp.Styles,
  Lsp.DesignerMeta;

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
  if APath.EndsWith('.fmx', True) then
    Exit('fmx');
  if APath.EndsWith('.dfm', True) then
    Exit('vcl');
  Result := '';
end;

function MetaClassInfo(const AFramework, AClass, AFilter: string): string;
var
  M: TMetaTable;
  Ret, PObj: TJSONObject;
  PArr, EArr: TJSONArray;
  Key, Cls, PName: string;
  R: TPropRec;
  Names: TStringList;
  N, Shown: Integer;
begin
  M := MetaTable(AFramework = 'fmx');
  if not M.Classes.TryGetValue(AClass.Trim.ToLower, Cls) then
    Exit(Format(SR_DESIGNER_CLASS_FMT, [AClass, UpperCase(AFramework)]));
  Ret := TJSONObject.Create;
  Names := TStringList.Create;
  try
    Ret.AddPair('class', Cls);
    Ret.AddPair('framework', UpperCase(AFramework));
    PArr := TJSONArray.Create;
    EArr := TJSONArray.Create;
    Ret.AddPair('properties', PArr);
    Ret.AddPair('events', EArr);
    for Key in M.Props.Keys do
      if Key.StartsWith(AClass.Trim.ToLower + '.') then
        Names.Add(Key);
    Names.Sort;
    N := 0;
    Shown := 0;
    for Key in Names do
    begin
      R := M.Props[Key];
      if not M.PropShow.TryGetValue(Key, PName) then
        PName := Copy(Key, Pos('.', Key) + 1, MaxInt);
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
    if N > Shown then
    begin
      Ret.AddPair('truncated', TJSONBool.Create(True));
      Ret.AddPair('hint', 'usa filter=<texto> para acotar');
    end;
    Ret.AddPair('note', SN_DESIGNER_INFO_NOTE);
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
  Cls, Members, Runtime: string;
begin
  M := MetaTable(AFramework = 'fmx');
  if not M.Classes.TryGetValue(AClass.Trim.ToLower, Cls) then
    Exit(Format(SR_DESIGNER_CLASS_FMT, [AClass, UpperCase(AFramework)]));
  if not M.Props.TryGetValue(AClass.Trim.ToLower + '.' + AProp.Trim.ToLower, R) then
    Exit(Format(SR_DESIGNER_PROP_FMT, [AProp, Cls]));
  Ret := TJSONObject.Create;
  try
    Ret.AddPair('class', Cls);
    Ret.AddPair('property', AProp.Trim);
    Ret.AddPair('kind', KindWord(R.Kind));
    Ret.AddPair('type', R.TypeName);
    // Enums had their members; SETS did not, though the description promised
    // "the legal members when it is an enum/set" and lint could already name
    // them (field round 8).
    if M.EnumShow.TryGetValue(R.TypeName.ToLower, Members) or
       M.SetShow.TryGetValue(R.TypeName.ToLower, Members) then
      Ret.AddPair('members', Members);
    if R.Kind = 's' then
      Ret.AddPair('membersNote', SN_DESIGNER_SET_NOTE);
    if M.Alias.TryGetValue(AClass.Trim.ToLower + '.' + AProp.Trim.ToLower, Runtime) then
      Ret.AddPair('runtimeClass', Runtime);
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

function IsBinaryDesigner(const APath: string): Boolean;
var
  B: TBytes;
  S: TFileStream;
begin
  Result := False;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < 4 then
      Exit;
    SetLength(B, 4);
    S.ReadBuffer(B[0], 4);
    // Two binary shapes, same as the write layer in Lsp.Patch: a raw stream
    // starts 'TPF0', but the REAL on-disk binary .dfm/.fmx wraps it in a
    // resource header whose first byte is $FF. Checking only TPF0 let the
    // commonest binary form through as if it were text - and lint answering
    // about garbage is worse than lint refusing. A text form always begins
    // with object/inherited/inline, never $FF.
    Result := ((B[0] = $54) and (B[1] = $50) and (B[2] = $46) and (B[3] = $30))
      or (B[0] = $FF);
  finally
    S.Free;
  end;
end;

function LoadDoc(const APath: string; out ADoc: TStyleDoc): string;
begin
  Result := ReadPathDenied(APath); // looking at a form is reading
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit('RECHAZADO: no existe ' + APath);
  if not MatchText(TPath.GetExtension(APath), ['.dfm', '.fmx']) then
    Exit(SR_DESIGNER_NOT_FORM);
  if IsBinaryDesigner(APath) then
    Exit(SR_DESIGNER_BINARY);
  ADoc := TStyleDoc.Create(APath);
end;

function TreeOf(const APath: string): string;
var
  Doc: TStyleDoc;
  Ret: TJSONObject;

  function NodeJson(O: TStyleObj): TJSONObject;
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
      Kids := TJSONArray.Create;
      Result.AddPair('children', Kids);
      for K in O.Children do
        Kids.AddElement(NodeJson(K));
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
      if Doc.Root <> nil then
        Ret.AddPair('root', NodeJson(Doc.Root))
      else
        Ret.AddPair('root', TJSONNull.Create);
      Ret.AddPair('note', SN_DESIGNER_TREE_NOTE);
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function FindByName(O: TStyleObj; const AName: string): TStyleObj;
var
  K: TStyleObj;
begin
  if SameText(O.ObjName, AName) then
    Exit(O);
  for K in O.Children do
  begin
    Result := FindByName(K, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

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
      Exit(SR_DESIGNER_EMPTY);
    O := FindByName(Doc.Root, AName.Trim);
    if O = nil then
      Exit(Format(SR_DESIGNER_COMPONENT_FMT, [AName]));
    Result := Format('%s (%s) lineas %d-%d de %s:'#13#10'%s',
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
var
  DfmTxt, PasTxt, Enc, L, Nm, Cl2, Ev, Handler, RootClass, Pas, Chain: string;
  DfmLines, PasLines: TArray<string>;
  Ret: TJSONObject;
  Miss, MissEv, NotPub, Extra, Dups, Empty: TJSONArray;
  Fields, PubMethods, AnyMethods, Seen: TStringList;
  M: TMatch;
  I, Depth, SkipBelow: Integer;
  AncestorOutside, ClassFound, Complete: Boolean;

  { Every class block in the unit: name=ancestor, remembering where it starts. }
  procedure ScanClassHeaders(AHeaders: TStringList);
  var
    J: Integer;
    Mt: TMatch;
  begin
    for J := 0 to High(PasLines) do
    begin
      Mt := TRegEx.Match(PasLines[J].Trim, '(?i)^([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?class\b(?!\s*;)(?:\s*\(\s*([\w.]*))?');
      if Mt.Success then
        AHeaders.AddObject(Mt.Groups[1].Value + '=' + Mt.Groups[2].Value,
          TObject(NativeInt(J)));
    end;
  end;

  { Published fields and methods of ONE class block. Members before any
    visibility keyword are published in a $M+ class - that is exactly where
    the IDE writes the designer's fields. }
  procedure ScanClassBody(AFrom: Integer);
  var
    J, Vis: Integer;
    Line, Names, Ty, One: string;
    Mt: TMatch;
  begin
    Vis := 1; // 1 = published area
    for J := AFrom + 1 to High(PasLines) do
    begin
      Line := PasLines[J].Trim;
      if TRegEx.IsMatch(Line, '(?i)^end;') then
        Break;
      if TRegEx.IsMatch(Line, '(?i)^published\b') then
      begin
        Vis := 1;
        Continue;
      end;
      if TRegEx.IsMatch(Line, '(?i)^(strict\s+)?(private|protected|public)\b') then
      begin
        Vis := 0;
        Continue;
      end;
      Mt := TRegEx.Match(Line, '(?i)^(procedure|function)\s+([A-Za-z_]\w*)');
      if Mt.Success then
      begin
        AnyMethods.Add(Mt.Groups[2].Value);
        if Vis = 1 then
          PubMethods.Add(Mt.Groups[2].Value);
        Continue;
      end;
      if Vis <> 1 then
        Continue;
      // "A, B: TButton;" is one declaration of two components, and the type
      // may be qualified ("Vcl.StdCtrls.TButton"). Either shape used to make
      // the whole line unreadable, so every name on it was called missing.
      Mt := TRegEx.Match(Line, '^([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*([A-Za-z_][\w.]*)\s*;');
      if not Mt.Success then
        Continue;
      Names := Mt.Groups[1].Value;
      Ty := Mt.Groups[2].Value;
      if Ty.Contains('.') then
        Ty := Copy(Ty, Ty.LastDelimiter('.') + 2, MaxInt);
      for One in Names.Split([',']) do
        if One.Trim <> '' then
          Fields.Values[One.Trim] := Ty;
    end;
  end;

  { Walk the class and its ancestors AS FAR AS THIS UNIT GOES. A form whose
    ancestor lives in another unit inherits components this file cannot see:
    calling them missing would be a lie, so we stop and say so instead. }
  procedure CollectClass(const AName: string);
  var
    Headers: TStringList;
    Cur, Anc: string;
    Idx, Guard: Integer;
  begin
    Headers := TStringList.Create;
    try
      ScanClassHeaders(Headers);
      Cur := AName;
      Guard := 0;
      while (Cur <> '') and (Guard < 32) do
      begin
        Inc(Guard);
        Idx := Headers.IndexOfName(Cur);
        if Idx < 0 then
        begin
          if SameText(Cur, AName) then
            ClassFound := False
          else
          begin
            AncestorOutside := True;
            if Chain <> '' then
              Chain := Chain + ' -> ';
            Chain := Chain + Cur;
          end;
          Exit;
        end;
        ScanClassBody(Integer(NativeInt(Headers.Objects[Idx])));
        Anc := Headers.ValueFromIndex[Idx].Trim;
        if Chain <> '' then
          Chain := Chain + ' -> ';
        Chain := Chain + Cur;
        // The RTL roots: their own members are not the programmer's and never
        // show up in a .dfm as objects.
        if (Anc = '') or MatchText(Anc, ['TForm', 'TFrame', 'TDataModule',
          'TCustomForm', 'TComponent', 'TObject']) then
          Exit;
        Cur := Anc;
      end;
    finally
      Headers.Free;
    end;
  end;

begin
  Pas := APas;
  if not MatchText(TPath.GetExtension(ADfm), ['.dfm', '.fmx']) then
    Exit(SR_DESIGNER_BINDING_NOT_FORM);
  if not TFile.Exists(ADfm) then
    Exit(Format(SR_DESIGNER_NO_FORM_FMT, [ADfm]));
  // Binary BEFORE the unit check: on a binary form "I cannot find the unit"
  // sends the caller hunting for a file that was never the problem.
  if IsBinaryDesigner(ADfm) then
    Exit(SR_DESIGNER_BINARY);
  if Pas = '' then
    Pas := TPath.ChangeExtension(ADfm, '.pas')
  else
  begin
    // "path" went through the jail; this one did not, so "unit" read any .pas
    // on the machine - and answered whether a file existed even where it could
    // not read. A second path is a second door.
    Result := ReadPathDenied(Pas);
    if Result <> '' then
      Exit;
    if not MatchText(TPath.GetExtension(Pas), ['.pas']) then
      Exit(SR_DESIGNER_BINDING_UNIT_EXT);
  end;
  if not TFile.Exists(Pas) then
    Exit(Format(SR_DESIGNER_NO_UNIT_FMT, [Pas]));
  DfmTxt := PatchLoadText(ADfm, Enc);
  PasTxt := PatchLoadText(Pas, Enc);
  DfmLines := DfmTxt.Replace(#13#10, #10).Split([#10]);
  PasLines := PasTxt.Replace(#13#10, #10).Split([#10]);

  Fields := TStringList.Create;
  PubMethods := TStringList.Create;
  AnyMethods := TStringList.Create;
  Seen := TStringList.Create;
  Ret := TJSONObject.Create;
  try
    Fields.CaseSensitive := False;
    PubMethods.CaseSensitive := False;
    AnyMethods.CaseSensitive := False;
    Seen.CaseSensitive := False;

    // the root object of the .dfm names the class this form really is
    RootClass := '';
    for I := 0 to High(DfmLines) do
    begin
      M := TRegEx.Match(DfmLines[I].Trim, '(?i)^(object|inherited|inline)\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)');
      if M.Success then
      begin
        Ret.AddPair('form', M.Groups[2].Value);
        Ret.AddPair('class', M.Groups[3].Value);
        RootClass := M.Groups[3].Value;
        Break;
      end;
    end;
    if RootClass = '' then
      Exit(SR_DESIGNER_BINDING_NO_ROOT);

    ClassFound := True;
    AncestorOutside := False;
    Chain := '';
    CollectClass(RootClass);
    Ret.AddPair('inheritanceChain', Chain);

    Miss := TJSONArray.Create;
    Ret.AddPair('componentsWithoutField', Miss);
    MissEv := TJSONArray.Create;
    Ret.AddPair('eventsWithoutMethod', MissEv);
    NotPub := TJSONArray.Create;
    Ret.AddPair('eventsWithMethodNotPublished', NotPub);
    Extra := TJSONArray.Create;
    Ret.AddPair('fieldsWithoutComponent', Extra);
    Dups := TJSONArray.Create;
    Ret.AddPair('duplicateNames', Dups);
    Empty := TJSONArray.Create;
    Ret.AddPair('eventsWithNoHandler', Empty);

    // Anything the class could not be read from makes the two "missing" lists
    // unsafe: what looks absent may simply live where we cannot see.
    Complete := ClassFound and not AncestorOutside;

    Depth := 0;
    SkipBelow := -1;
    for I := 0 to High(DfmLines) do
    begin
      L := DfmLines[I].Trim;
      M := TRegEx.Match(L, '(?i)^(object|inherited|inline)\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)');
      if M.Success then
      begin
        Nm := M.Groups[2].Value;
        Cl2 := M.Groups[3].Value;
        Inc(Depth);
        if Depth = 1 then
          Continue; // the form itself
        // Inside an inline FRAME the objects belong to the frame's own class,
        // not to this form: checking them here called every one missing.
        if (SkipBelow >= 0) and (Depth > SkipBelow) then
          Continue;
        if Seen.IndexOf(Nm) >= 0 then
          Dups.Add(Format('%s (linea %d del .dfm) repite un nombre ya usado en este form: al cargarlo salta EComponentError', [Nm, I + 1]))
        else
          Seen.Add(Nm);
        if Complete and (Fields.IndexOfName(Nm) < 0) then
          Miss.Add(Format('%s: %s (linea %d del .dfm) no tiene campo publicado en la clase', [Nm, Cl2, I + 1]));
        if SameText(M.Groups[1].Value, 'inline') then
          SkipBelow := Depth;
        Continue;
      end;
      if TRegEx.IsMatch(L, '(?i)^end\s*$') then
      begin
        if (SkipBelow >= 0) and (Depth <= SkipBelow) then
          SkipBelow := -1;
        Dec(Depth);
        Continue;
      end;
      if (SkipBelow >= 0) and (Depth > SkipBelow) then
        Continue;
      if TRegEx.IsMatch(L, '^(On[A-Za-z_]\w*)\s*=\s*$') then
      begin
        Empty.Add(Format('"%s" (linea %d del .dfm) se ha quedado sin valor: el .dfm no es valido y el enlazador lo rechaza sin decirte que linea', [L, I + 1]));
        Continue;
      end;
      M := TRegEx.Match(L, '^(On[A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$');
      if M.Success then
      begin
        Ev := M.Groups[1].Value;
        Handler := M.Groups[2].Value;
        if PubMethods.IndexOf(Handler) >= 0 then
          Continue;
        // Declared, but not where the form loader can find it: the one case
        // the compiler and the first version of this tool both waved through.
        if AnyMethods.IndexOf(Handler) >= 0 then
          NotPub.Add(Format('%s = %s (linea %d del .dfm): %s existe pero NO esta en published; el cargador del form solo ve metodos publicados, asi que esto revienta con EReadError al crear la ventana', [Ev, Handler, I + 1, Handler]))
        else if Complete then
          MissEv.Add(Format('%s = %s (linea %d del .dfm): el metodo %s no esta declarado', [Ev, Handler, I + 1, Handler]));
      end;
    end;

    // a published field with no component is the other half of the same slip
    if Complete then
      for I := 0 to Fields.Count - 1 do
        if not TRegEx.IsMatch(DfmTxt,
          '(?im)^\s*(?:object|inherited|inline)\s+' + TRegEx.Escape(Fields.Names[I]) + '\s*:') then
          Extra.Add(Fields.Names[I]);

    Ret.AddPair('ok', TJSONBool.Create(ClassFound and (Miss.Count = 0) and
      (MissEv.Count = 0) and (NotPub.Count = 0) and (Extra.Count = 0) and
      (Dups.Count = 0) and (Empty.Count = 0)));
    if not ClassFound then
      Ret.AddPair('note', Format(SN_DESIGNER_BINDING_NOCLASS_FMT,
        [RootClass, TPath.GetFileName(Pas)]))
    else
    begin
      if not Complete then
        Ret.AddPair('partialNote', Format(SN_DESIGNER_BINDING_PARTIAL_FMT,
          [Chain]));
      Ret.AddPair('note', IfThen((Miss.Count = 0) and (MissEv.Count = 0) and
        (NotPub.Count = 0) and (Extra.Count = 0) and (Dups.Count = 0) and
        (Empty.Count = 0), SN_DESIGNER_BINDING_OK, SN_DESIGNER_BINDING_BAD));
    end;
    Result := Ret.ToJSON;
  finally
    Ret.Free;
    Seen.Free;
    AnyMethods.Free;
    PubMethods.Free;
    Fields.Free;
  end;
end;

{ One property of ONE object, ignoring the properties of its children. }
function PropRaw(ADoc: TStyleDoc; AObj: TStyleObj; const AName: string;
  out AFound: Boolean): string;
var
  I, J: Integer;
  Line: string;
  Mt: TMatch;
  Skip: Boolean;
begin
  Result := '';
  AFound := False;
  for I := AObj.StartLine + 1 to AObj.EndLine - 1 do
  begin
    if (I < 1) or (I > Length(ADoc.Lines)) then
      Continue;
    Skip := False;
    for J := 0 to AObj.Children.Count - 1 do
      if (I >= AObj.Children[J].StartLine) and (I <= AObj.Children[J].EndLine) then
        Skip := True;
    if Skip then
      Continue;
    Line := ADoc.Lines[I - 1].Trim;
    Mt := TRegEx.Match(Line, '^([A-Za-z_][\w.]*)\s*=\s*(.*)$');
    if Mt.Success and SameText(Mt.Groups[1].Value, AName) then
    begin
      AFound := True;
      Exit(Mt.Groups[2].Value.Trim);
    end;
  end;
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

  This resolves Align exactly the way TWinControl.AlignControls does - each
  aligned child eats its band off the remaining rectangle, in .dfm order - with
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
  govern RESIZE - are not what this measures. VCL only; .fmx geometry (Size.X,
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
  L: string;

  function Vis(AObj: TStyleObj): Boolean;
  var
    V: string;
    F2: Boolean;
  begin
    V := PropRaw(Doc, AObj, 'Visible', F2);
    Result := not (F2 and SameText(V.Trim, 'False'));
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
      not SameText(DefaultAlign(AObj.ClassName_), 'alNone');
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
      IsInh := (Kid.StartLine >= 1) and (Kid.StartLine <= Length(Doc.Lines)) and
        TRegEx.IsMatch(Doc.Lines[Kid.StartLine - 1].Trim, '(?i)^inherited\b');
      InhUnknown := IsInh and
        (PropRaw(Doc, Kid, 'Align', Found) = '') and not (HasW and HasH);

      NeedW := MatchText(Align, ['alNone', 'alLeft', 'alRight', 'alCustom']);
      NeedH := MatchText(Align, ['alNone', 'alTop', 'alBottom', 'alCustom']);
      if not InhUnknown then
      begin
        if (HasW and (W = 0)) or (HasH and (H = 0)) then
          Zero.Add(Format('%s: %s (linea %d) mide %s x %s: con un lado a cero no ' +
            'se ve, aunque el form cargue', [Nm, Cls, Kid.StartLine,
            IfThen(HasW, IntToStr(W), '?'), IfThen(HasH, IntToStr(H), '?')]));
        if (NeedW and not HasW) or (NeedH and not HasH) then
          Unknown.Add(Format('%s: %s (linea %d) no lleva %s en el .dfm; con ' +
            'align %s hace falta para saber donde acaba', [Nm, Cls, Kid.StartLine,
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
          NoRoom.Add(Format('%s (linea %d) no cabe entero en "%s": de %d px de ' +
            'alto solo se ven %d, el resto queda fuera', [Nm, Kid.StartLine,
            AWhere, H, Max(0, RB - RT - MgnT)]));
        RT := Min(RB, RT + MgnT + H + MgnB);
      end
      else if SameText(Align, 'alBottom') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := Max(RT, RB - MgnB - H);
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RB - MgnB - H - MgnT < RT) then
          NoRoom.Add(Format('%s (linea %d) no cabe entero en "%s": de %d px de ' +
            'alto solo se ven %d', [Nm, Kid.StartLine, AWhere, H, Max(0, RB - RT - MgnB)]));
        RB := Max(RT, RB - MgnB - H - MgnT);
      end
      else if SameText(Align, 'alLeft') then
      begin
        Kids[Cnt].X1 := RL + MgnL; Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RL + MgnL + W; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RL + MgnL + W + MgnR > RR) then
          NoRoom.Add(Format('%s (linea %d) no cabe entero en "%s": de %d px de ' +
            'ancho solo se ven %d', [Nm, Kid.StartLine, AWhere, W, Max(0, RR - RL - MgnL)]));
        RL := Min(RR, RL + MgnL + W + MgnR);
      end
      else if SameText(Align, 'alRight') then
      begin
        Kids[Cnt].X1 := Max(RL, RR - MgnR - W); Kids[Cnt].Y1 := RT + MgnT;
        Kids[Cnt].X2 := RR - MgnR; Kids[Cnt].Y2 := RB - MgnB;
        if AKnown and (RR - MgnR - W - MgnL < RL) then
          NoRoom.Add(Format('%s (linea %d) no cabe entero en "%s": de %d px de ' +
            'ancho solo se ven %d', [Nm, Kid.StartLine, AWhere, W, Max(0, RR - RL - MgnR)]));
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
          Outside.Add(Format('%s: %s (linea %d) ocupa de (%d,%d) a (%d,%d), y ' +
            '"%s" solo mide %d x %d: se sale y esa parte no se ve', [Nm, Cls,
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
                Overlap.Add(Format('%s (linea %d) y %s (linea %d) son ambos ' +
                  'alClient en "%s": la VCL les da el rectangulo ENTERO a los ' +
                  'dos, asi que se tapan al 100%%', [Kids[K].Nm, Kids[K].Line,
                  Kids[J].Nm, Kids[J].Line, AWhere]))
              else
                Overlap.Add(Format('%s (linea %d) y %s (linea %d) se solapan en ' +
                  '"%s": comparten de (%d,%d) a (%d,%d), uno tapa al otro',
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
      Exit(SR_DESIGNER_LAYOUT_FMX);
    Exit(SR_DESIGNER_NOT_FORM);
  end;
  Result := LoadDoc(APath, Doc);
  if Result <> '' then Exit;
  try
    if Doc.Root = nil then Exit(SR_DESIGNER_BINDING_NO_ROOT);
    // a truncated .dfm parses into something; only openers left unclosed betray
    // it. Collection items add opener-less "end"s, so we flag ONLY opens>closes,
    // which they can never cause - no false alarm on a form full of collections.
    Opens := 0; Closes := 0;
    for I := 0 to High(Doc.Lines) do
    begin
      L := Doc.Lines[I].Trim;
      if TRegEx.IsMatch(L, '(?i)^(object|inherited|inline)\s') then Inc(Opens);
      if TRegEx.IsMatch(L, '(?i)^end\b') then Inc(Closes);
    end;

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
        Ret.AddPair('truncatedNote', SR_DESIGNER_LAYOUT_TRUNC);

      if (RootW <= 0) or (RootH <= 0) then
        NoRoom.Add(Format('%s no dice cuanto mide (%d x %d): sin el tamano del ' +
          'form no puedo situar nada', [Doc.Root.ObjName, RootW, RootH]))
      else
        Walk(Doc.Root, RootW, RootH, 0, 0, Doc.Root.ObjName, not Estimated, False);

      Ret.AddPair('ok', TJSONBool.Create((Zero.Count = 0) and (Outside.Count = 0)
        and (Overlap.Count = 0) and (NoRoom.Count = 0)));
      if Estimated then
        Ret.AddPair('estimatedNote', SN_DESIGNER_LAYOUT_ESTIMATED);
      Ret.AddPair('note', IfThen((Zero.Count = 0) and (Outside.Count = 0) and
        (Overlap.Count = 0) and (NoRoom.Count = 0), SN_DESIGNER_LAYOUT_OK,
        SN_DESIGNER_LAYOUT_BAD));
      Ret.AddPair('howMeasured', SN_DESIGNER_LAYOUT_HOW);
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
  IsFmx: Boolean;
begin
  Denied := ReadPathDenied(APath);
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(APath) then
    Exit('RECHAZADO: no existe ' + APath);
  if not MatchText(TPath.GetExtension(APath), ['.dfm', '.fmx']) then
    Exit(SR_DESIGNER_NOT_FORM);
  if IsBinaryDesigner(APath) then
    Exit(SR_DESIGNER_BINARY);
  IsFmx := APath.EndsWith('.fmx', True);
  Text := PatchLoadText(APath, EncName);
  Warns := DesignerMetaLint(IsFmx, Text.Replace(#13#10, #10).Split([#10]));
  if Length(Warns) = 0 then
    Result := Format(SN_DESIGNER_LINT_OK_FMT, [TPath.GetFileName(APath)])
  else
    Result := Format(SN_DESIGNER_LINT_BAD_FMT,
      [Length(Warns), TPath.GetFileName(APath)]) + #13#10 +
      string.Join(#13#10, Warns);
end;

{ TDelphiDesignerTool }

constructor TDelphiDesignerTool.Create;
begin
  inherited;
  FName := 'delphi_designer';
  FDescription := SD_DESIGNER;
end;

function TDelphiDesignerTool.ExecuteWithParams(const Params: TDelphiDesignerParams): string;
var
  Cmd, Fw: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'info';
  if MatchText(Cmd, ['info', 'prop']) then
  begin
    Fw := ResolveFramework(Params.Framework, Params.Path);
    if Fw = '?' then
      Exit(SR_DESIGNER_FRAMEWORK);
    if Fw = '' then
      Fw := 'vcl';
    if Params.ClassName_.Trim = '' then
      Exit(SR_DESIGNER_NEED_CLASS);
    if Cmd = 'info' then
      Result := MetaClassInfo(Fw, Params.ClassName_, Params.Filter.Trim)
    else if Params.Prop.Trim = '' then
      Result := SR_DESIGNER_NEED_PROP
    else
      Result := PropInfo(Fw, Params.ClassName_, Params.Prop);
  end
  else if MatchText(Cmd, ['tree', 'get', 'lint', 'check-binding', 'binding',
    'layout']) then
  begin
    if Params.Path.Trim = '' then
      Exit(SR_DESIGNER_NEED_PATH);
    if MatchText(Cmd, ['check-binding', 'binding']) then
      Result := CheckBinding(Params.Path, Params.Unit_)
    else if Cmd = 'layout' then
      Result := LayoutOf(Params.Path)
    else if Cmd = 'tree' then
      Result := TreeOf(Params.Path)
    else if Cmd = 'lint' then
      Result := LintForm(Params.Path)
    else if Params.Component.Trim = '' then
      Result := SR_DESIGNER_NEED_COMPONENT
    else
      Result := GetComponent(Params.Path, Params.Component);
  end
  else
    Result := SR_DESIGNER_CMD;
  Result := MaskDriveText('delphi_designer', Result);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_designer',
    function: IMCPTool begin Result := TDelphiDesignerTool.Create; end);

end.
