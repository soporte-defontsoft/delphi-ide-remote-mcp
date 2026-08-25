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
// there, builds perfectly and then throws at form-load, on a machine where
// nobody can see it. Measured 2026-08-25 by an agent building a VCL form
// through MCP: thirteen fields and seven handlers written twice, by hand, in
// two files, with nothing checking they matched - "el hueco entre compila y
// funciona", in its words.
//
// Read as text on purpose: it has to work on a form that does not compile yet,
// which is exactly when you need it.
function CheckBinding(const ADfm, APas: string): string;
var
  DfmTxt, PasTxt, Enc, L, Cls, Nm, Cl2, Ev, Handler: string;
  DfmLines, PasLines: TArray<string>;
  Ret: TJSONObject;
  Miss, MissEv, Extra: TJSONArray;
  Fields, Methods: TStringList;
  M: TMatch;
  I, InClass: Integer;
  Pas: string;
begin
  Pas := APas;
  if Pas = '' then
    Pas := TPath.ChangeExtension(ADfm, '.pas');
  if not TFile.Exists(ADfm) then
    Exit(Format(SR_DESIGNER_NO_FORM_FMT, [ADfm]));
  // Binary BEFORE the unit check: on a binary form "I cannot find the unit"
  // sends the caller hunting for a file that was never the problem.
  if IsBinaryDesigner(ADfm) then
    Exit(SR_DESIGNER_BINARY);
  if not TFile.Exists(Pas) then
    Exit(Format(SR_DESIGNER_NO_UNIT_FMT, [Pas]));
  DfmTxt := PatchLoadText(ADfm, Enc);
  PasTxt := PatchLoadText(Pas, Enc);
  DfmLines := DfmTxt.Replace(#13#10, #10).Split([#10]);
  PasLines := PasTxt.Replace(#13#10, #10).Split([#10]);

  Fields := TStringList.Create;
  Methods := TStringList.Create;
  Ret := TJSONObject.Create;
  try
    Fields.CaseSensitive := False;
    Methods.CaseSensitive := False;
    // what the class declares: published fields (Name: TClass;) and methods
    InClass := 0;
    for I := 0 to High(PasLines) do
    begin
      L := PasLines[I].Trim;
      if TRegEx.IsMatch(L, '(?i)^[A-Za-z_]\w*\s*=\s*class\b') then
        InClass := 1
      else if (InClass = 1) and TRegEx.IsMatch(L, '(?i)^end;') then
        InClass := 0
      // Only the PUBLISHED area holds components. A form's fields before
      // any visibility keyword are published - that is where the IDE
      // writes them - while everything after `private` is the
      // programmer's own. Counting those as missing components gave two
      // false positives on the first real form this ran against.
      else if (InClass = 1) and TRegEx.IsMatch(L,
         '(?i)^(strict\s+)?(private|protected|public)\b') then
        InClass := 2
      else if (InClass >= 1) and TRegEx.IsMatch(L, '(?i)^published\b') then
        InClass := 1;
      if InClass = 1 then
      begin
        M := TRegEx.Match(L, '^([A-Za-z_]\w*)\s*:\s*T[A-Za-z_]\w*\s*;');
        if M.Success then
          Fields.Add(M.Groups[1].Value);
      end;
      M := TRegEx.Match(L, '(?i)^(procedure|function)\s+(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)');
      if M.Success then
        Methods.Add(M.Groups[2].Value);
    end;

    Miss := TJSONArray.Create;
    Ret.AddPair('componentsWithoutField', Miss);
    MissEv := TJSONArray.Create;
    Ret.AddPair('eventsWithoutMethod', MissEv);
    Extra := TJSONArray.Create;
    Ret.AddPair('fieldsWithoutComponent', Extra);

    Cls := '';
    for I := 0 to High(DfmLines) do
    begin
      L := DfmLines[I].Trim;
      M := TRegEx.Match(L, '^(object|inherited|inline)\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)');
      if M.Success then
      begin
        Nm := M.Groups[2].Value;
        Cl2 := M.Groups[3].Value;
        if Cls = '' then
        begin
          // the first object IS the form: its class is what we check against
          Cls := Cl2;
          Ret.AddPair('form', Nm);
          Ret.AddPair('class', Cl2);
          Continue;
        end;
        if Fields.IndexOf(Nm) < 0 then
          Miss.Add(Format('%s: %s (linea %d del .dfm) no tiene campo publicado en la clase', [Nm, Cl2, I + 1]));
        Continue;
      end;
      M := TRegEx.Match(L, '^(On[A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$');
      if M.Success then
      begin
        Ev := M.Groups[1].Value;
        Handler := M.Groups[2].Value;
        if Methods.IndexOf(Handler) < 0 then
          MissEv.Add(Format('%s = %s (linea %d del .dfm): el metodo %s no esta declarado', [Ev, Handler, I + 1, Handler]));
      end;
    end;

    // a published field with no component is the other half of the same slip
    for I := 0 to Fields.Count - 1 do
      if not TRegEx.IsMatch(DfmTxt,
        '(?im)^\s*(?:object|inherited|inline)\s+' + TRegEx.Escape(Fields[I]) + '\s*:') then
        Extra.Add(Fields[I]);

    Ret.AddPair('ok', TJSONBool.Create(
      (Miss.Count = 0) and (MissEv.Count = 0) and (Extra.Count = 0)));
    Ret.AddPair('note', IfThen((Miss.Count = 0) and (MissEv.Count = 0) and
      (Extra.Count = 0), SN_DESIGNER_BINDING_OK, SN_DESIGNER_BINDING_BAD));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
    Methods.Free;
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
