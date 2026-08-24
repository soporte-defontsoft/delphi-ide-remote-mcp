unit Lsp.DesignerMeta;

{ Resolves designer property paths against the GENERATED framework tables
  (tools\designer-meta-dump): classes, published properties (classic
  typinfo - the same metadata TReader streams against), enum and set
  members, and instance aliases (the class a class-typed property REALLY
  holds at runtime - TLabel.TextSettings declares TTextSettings but holds
  TLabelTextSettings, measured). The framework describes itself; the
  server hardcodes no error rules.

  Silence policy (a lint false positive would poison trust): unknown
  classes (user forms, third-party components), classes without table
  data, collection items, binary blocks and list values are NOT judged.

  Field origin (Fase 3): a hand-edited .fmx with VCL-isms packaged
  cleanly - the compiler only checks a form resource's text grammar - and
  crashed at form-load on the device, silently. Hours of blind debugging
  that these warnings turn into seconds at edit time. }

interface

uses
  System.Generics.Collections;

type
  TPropRec = record
    Kind: Char;         // c=class e=enum s=set m=method r=record o=other
    TypeName: string;
  end;

  TMetaTable = class
  public
    Classes: TDictionary<string, string>;    // lower -> original name
    Props: TDictionary<string, TPropRec>;    // 'class.prop' lower
    PropNames: TDictionary<string, string>;  // class lower -> 'A, B...' cap
    Enums: TDictionary<string, string>;      // enum lower -> ',a,b,' lower
    EnumShow: TDictionary<string, string>;   // enum lower -> 'A, B, C'
    Sets: TDictionary<string, string>;       // set lower -> ',a,b,' lower
    Alias: TDictionary<string, string>;      // 'class.prop' lower -> runtime
    PropShow: TDictionary<string, string>;   // 'class.prop' lower -> Prop original
    constructor Create(const AFacts: array of string);
    destructor Destroy; override;
  end;

function DesignerMetaLint(const AIsFmx: Boolean;
  const ALines: TArray<string>): TArray<string>;

{ The generated framework table itself - what delphi_designer asks about
  classes, published properties and enum members. Never nil. }
function MetaTable(const AIsFmx: Boolean): TMetaTable;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.RegularExpressions,
  Lsp.DesignerMeta.Fmx, Lsp.DesignerMeta.Vcl;

var
  GFmx, GVcl: TMetaTable;

function MetaTable(const AIsFmx: Boolean): TMetaTable;
begin
  if AIsFmx then
    Result := GFmx
  else
    Result := GVcl;
end;

constructor TMetaTable.Create(const AFacts: array of string);
var
  F, Names: string;
  P: TArray<string>;
  R: TPropRec;
begin
  inherited Create;
  Classes := TDictionary<string, string>.Create;
  Props := TDictionary<string, TPropRec>.Create;
  PropNames := TDictionary<string, string>.Create;
  Enums := TDictionary<string, string>.Create;
  EnumShow := TDictionary<string, string>.Create;
  Sets := TDictionary<string, string>.Create;
  Alias := TDictionary<string, string>.Create;
  PropShow := TDictionary<string, string>.Create;
  for F in AFacts do
  begin
    P := F.Split([' ']);
    if Length(P) < 2 then
      Continue;
    if (P[0] = 'C') then
      Classes.AddOrSetValue(P[1].ToLower, P[1])
    else if (P[0] = 'P') and (Length(P) >= 4) then
    begin
      R.Kind := P[3][1];
      if Length(P) >= 5 then
        R.TypeName := P[4]
      else
        R.TypeName := '?';
      Props.AddOrSetValue(P[1].ToLower + '.' + P[2].ToLower, R);
      PropShow.AddOrSetValue(P[1].ToLower + '.' + P[2].ToLower, P[2]);
      if PropNames.TryGetValue(P[1].ToLower, Names) then
      begin
        if Length(Names) < 200 then
          PropNames[P[1].ToLower] := Names + ', ' + P[2]
        else if not Names.EndsWith('...') then
          PropNames[P[1].ToLower] := Names + '...';
      end
      else
        PropNames.Add(P[1].ToLower, P[2]);
    end
    else if (P[0] = 'E') and (Length(P) >= 3) then
    begin
      Enums.AddOrSetValue(P[1].ToLower, ',' + P[2].ToLower + ',');
      EnumShow.AddOrSetValue(P[1].ToLower, P[2].Replace(',', ', '));
    end
    else if (P[0] = 'S') and (Length(P) >= 3) then
      Sets.AddOrSetValue(P[1].ToLower, ',' + P[2].ToLower + ',')
    else if (P[0] = 'A') and (Length(P) >= 3) then
      Alias.AddOrSetValue(P[1].ToLower, P[2]);
  end;
end;

destructor TMetaTable.Destroy;
begin
  PropShow.Free;
  Alias.Free;
  Sets.Free;
  EnumShow.Free;
  Enums.Free;
  PropNames.Free;
  Props.Free;
  Classes.Free;
  inherited;
end;

function DesignerMetaLint(const AIsFmx: Boolean;
  const ALines: TArray<string>): TArray<string>;
var
  M: TMetaTable;
  Stack: TStack<string>;    // owner class per nesting level ('' = unknown)
  Warns: TStringList;
  I, SIdx, CollDepth: Integer;
  L, Lhs, Rhs, Cur, CurShow, Seg, Key, Runtime, Have, Members, V: string;
  Mt: TMatch;
  Segs: TArray<string>;
  R: TPropRec;
  InBlock: Boolean;
  BlockCh: Char;

  procedure Warn(const AMsg: string);
  begin
    Warns.Add(Format('  linea %d: %s  ->  %s',
      [I + 1, ALines[I].Trim, AMsg]));
  end;

begin
  if AIsFmx then
    M := GFmx
  else
    M := GVcl;
  Stack := TStack<string>.Create;
  Warns := TStringList.Create;
  CollDepth := 0;
  InBlock := False;
  BlockCh := ' ';
  try
    for I := 0 to High(ALines) do
    begin
      L := ALines[I].Trim;
      if InBlock then
      begin
        if ((BlockCh = '{') and L.EndsWith('}')) or
           ((BlockCh = '(') and L.EndsWith(')')) then
          InBlock := False;
        Continue;
      end;
      // collections (Prop = < item ... end>): the item classes never
      // appear in the text - silence inside
      if CollDepth > 0 then
      begin
        if L.StartsWith('end') and L.EndsWith('>') then
          Dec(CollDepth)
        else if L.EndsWith('<') then
          Inc(CollDepth);
        Continue;
      end;
      Mt := TRegEx.Match(L,
        '^(object|inherited|inline) +[A-Za-z_]\w* *: *([A-Za-z_][\w.]*)');
      if Mt.Success then
      begin
        Cur := Mt.Groups[2].Value.ToLower;
        if not M.Classes.ContainsKey(Cur) then
          Cur := '';
        Stack.Push(Cur);
        Continue;
      end;
      if L = 'end' then
      begin
        if Stack.Count > 0 then
          Stack.Pop;
        Continue;
      end;
      Mt := TRegEx.Match(L, '^([A-Za-z_][\w.]*) = (.*)$');
      if not Mt.Success then
        Continue;
      Lhs := Mt.Groups[1].Value;
      Rhs := Mt.Groups[2].Value.Trim;
      if Rhs = '<' then
      begin
        Inc(CollDepth);
        Continue;
      end;
      if (Rhs <> '') and (Rhs[1] = '{') and not Rhs.EndsWith('}') then
      begin
        InBlock := True;
        BlockCh := '{';
        Continue;
      end;
      if Rhs = '(' then
      begin
        InBlock := True;
        BlockCh := '(';
        Continue;
      end;
      // one-line binary/list values: DefineProperties land - not judged
      if (Rhs <> '') and CharInSet(Rhs[1], ['{', '(']) then
        Continue;
      if Stack.Count = 0 then
        Continue;
      Cur := Stack.Peek;
      if Cur = '' then
        Continue;
      if not M.Classes.TryGetValue(Cur, CurShow) then
        Continue;
      Segs := Lhs.Split(['.']);
      for SIdx := 0 to High(Segs) do
      begin
        Seg := Segs[SIdx].ToLower;
        Key := Cur + '.' + Seg;
        if not M.Props.TryGetValue(Key, R) then
        begin
          if not M.PropNames.TryGetValue(Cur, Have) then
            Break; // class without data: silence, never guess
          // Left/Top on a NON-VISUAL component are the designer's own
          // placement in the form editor: the IDE writes them in every
          // .dfm/.fmx carrying a TImageList or a TPopupMenu, and no class
          // publishes them. Warning about those is pure noise (field
          // report 2026-08-24: 6 of 6 warnings on a real form were these).
          if (SIdx = 0) and MatchText(Segs[SIdx], ['Left', 'Top']) then
            Break;
          Warn(Format('"%s" no existe en %s segun el framework (publica: %s)',
            [Segs[SIdx], CurShow, Have]));
          Break;
        end;
        if SIdx < High(Segs) then
        begin
          if R.Kind <> 'c' then
          begin
            Warn(Format('"%s" (%s) no tiene subpropiedades',
              [Segs[SIdx], R.TypeName]));
            Break;
          end;
          // descend where the STREAMING descends: the instance alias
          // (measured runtime class) wins over the declared type
          if M.Alias.TryGetValue(Key, Runtime) then
            Cur := Runtime.ToLower
          else
            Cur := R.TypeName.ToLower;
          if (not M.Classes.TryGetValue(Cur, CurShow)) or
             (not M.PropNames.ContainsKey(Cur)) then
            Break; // no data for the subtree: silence
        end
        else
        begin
          // leaf value checks, only where the table can KNOW
          if (R.Kind = 'e') and TRegEx.IsMatch(Rhs, '^[A-Za-z_][\w.]*$') then
          begin
            V := Rhs;
            if V.LastIndexOf('.') >= 0 then
              V := V.Substring(V.LastIndexOf('.') + 1);
            if M.Enums.TryGetValue(R.TypeName.ToLower, Members) and
               (not Members.Contains(',' + V.ToLower + ',')) then
              Warn(Format('"%s" no es un valor de %s; validos: %s',
                [Rhs, R.TypeName, M.EnumShow[R.TypeName.ToLower]]));
          end
          else if (R.Kind = 's') and TRegEx.IsMatch(Rhs, '^[A-Za-z_]\w*$') then
            Warn(Format('%s es un SET: los valores van entre corchetes, ' +
              'p.ej. [%s]', [R.TypeName, Rhs]))
          else if (R.Kind = 's') and (Rhs <> '') and (Rhs[1] = '[') and
                  Rhs.EndsWith(']') and
                  M.Sets.TryGetValue(R.TypeName.ToLower, Members) then
          begin
            for V in Rhs.Substring(1, Length(Rhs) - 2).Split([',']) do
              if (V.Trim <> '') and
                 (not Members.Contains(',' + V.Trim.ToLower + ',')) then
              begin
                Warn(Format('"%s" no es un elemento de %s',
                  [V.Trim, R.TypeName]));
                Break;
              end;
          end;
        end;
      end;
    end;
    Result := Warns.ToStringArray;
  finally
    Warns.Free;
    Stack.Free;
  end;
end;

initialization
  GFmx := TMetaTable.Create(Lsp.DesignerMeta.Fmx.META);
  GVcl := TMetaTable.Create(Lsp.DesignerMeta.Vcl.META);

finalization
  GVcl.Free;
  GFmx.Free;

end.
