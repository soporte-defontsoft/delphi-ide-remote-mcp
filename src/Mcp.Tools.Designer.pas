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
  else if MatchText(Cmd, ['tree', 'get', 'lint', 'check-binding', 'binding']) then
  begin
    if Params.Path.Trim = '' then
      Exit(SR_DESIGNER_NEED_PATH);
    if MatchText(Cmd, ['check-binding', 'binding']) then
      Result := CheckBinding(Params.Path, Params.Unit_)
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
