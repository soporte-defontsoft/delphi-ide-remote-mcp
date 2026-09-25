unit Lsp.DesignerBinding;

{ El form contra su clase: lo que el compilador NO comprueba. Cada objeto del
  .dfm/.fmx con su campo publicado, cada evento (OnX = Metodo) apuntando a un
  metodo que existe Y esta en published - lo unico que ve MethodAddress al
  hacer streaming -, nombres repetidos, eventos sin valor.

  Vivia dentro de la tool delphi_designer (check-binding) y solo lo veia quien
  lo pedia: hermes cableo un OnClick a un metodo que insert=metodo habia
  dejado en public, el build paso y el form murio en Zorin con "Invalid
  property value" (25-sep-2026). Ahora es motor y lo usan check-binding, el
  lint del designer, la ESCRITURA de un designer (delphi_edit avisa al momento)
  e insert=metodo, que pone en published lo que el designer pareja cablea. }

interface

{ El informe JSON de check-binding. APas vacio = el .pas del mismo nombre. La
  jaula del segundo path es de la tool, no de aqui. }
function DesignerBindingJson(const ADfm, APas: string): string;

{ Lo mismo, como lineas de aviso para el lint, sobre las lineas del designer
  que se le dan (las de DESPUES de escribir). Vacio = cuadra, o no hay .pas
  pareja contra el que comparar. }
function DesignerBindingWarnings(const ADfm: string;
  const ADfmLines: TArray<string>): TArray<string>;

{ El designer (texto o binario) cablea AMethod como evento (OnX = AMethod). }
function DesignerWiresMethodFile(const ADfm, AMethod: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.RegularExpressions,
  Lsp.Texts,
  Lsp.Patch,
  Lsp.DesignerBin;

const
  // UNA expresion para "evento cableado por nombre": la lee el informe y la
  // consulta insert=metodo. Nadie la vuelve a escribir.
  EVENT_LINE_RE = '^(On[A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$';

function BindingReport(const DfmLines, PasLines: TArray<string>; const Pas: string): string;
var
  DfmTxt, L, Nm, Cl2, Ev, Handler, RootClass, Chain: string;
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
  DfmTxt := string.Join(#10, DfmLines);

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
      M := TRegEx.Match(L, EVENT_LINE_RE);
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

function DesignerBindingJson(const ADfm, APas: string): string;
var
  Pas, Enc, DfmTxt: string;
begin
  Pas := APas;
  if not MatchText(TPath.GetExtension(ADfm), ['.dfm', '.fmx']) then
    Exit(SR_DESIGNER_BINDING_NOT_FORM);
  if not TFile.Exists(ADfm) then
    Exit(Format(SR_DESIGNER_NO_FORM_FMT, [ADfm]));
  // Un binario DANADO antes de buscar la unit: "no encuentro la unit" sobre
  // un form ilegible manda a buscar un fichero que nunca fue el problema.
  if IsBinaryDesignerFile(ADfm) and (DesignerFileToText(ADfm, Enc) <> '') then
    Exit(Format(SR_DESIGNER_BINARY_FMT, [Enc]));
  if Pas = '' then
    Pas := TPath.ChangeExtension(ADfm, '.pas');
  if not TFile.Exists(Pas) then
    Exit(Format(SR_DESIGNER_NO_UNIT_FMT, [Pas]));
  if IsBinaryDesignerFile(ADfm) then
    DesignerFileToText(ADfm, DfmTxt) // sano: comprobado arriba
  else
    DfmTxt := PatchLoadText(ADfm, Enc);
  Result := BindingReport(DfmTxt.Replace(#13#10, #10).Split([#10]),
    PatchLoadText(Pas, Enc).Replace(#13#10, #10).Split([#10]), Pas);
end;

function DesignerBindingWarnings(const ADfm: string;
  const ADfmLines: TArray<string>): TArray<string>;
var
  Pas, Enc, S, Nombre: string;
  J: TJSONValue;
  O: TJSONObject;
  Arr: TJSONArray;
  Res: TStringList;
  I: Integer;
begin
  Result := [];
  Pas := TPath.ChangeExtension(ADfm, '.pas');
  if not TFile.Exists(Pas) then
    Exit;
  S := BindingReport(ADfmLines, PatchLoadText(Pas, Enc).Replace(#13#10, #10).Split([#10]), Pas);
  J := TJSONObject.ParseJSONValue(S);
  if not (J is TJSONObject) then
  begin
    J.Free;
    Exit;
  end;
  O := TJSONObject(J);
  Res := TStringList.Create;
  try
    for Nombre in ['eventsWithMethodNotPublished', 'eventsWithoutMethod',
                   'eventsWithNoHandler', 'componentsWithoutField', 'duplicateNames'] do
      if O.TryGetValue<TJSONArray>(Nombre, Arr) then
        for I := 0 to Arr.Count - 1 do
          Res.Add('  ' + Arr.Items[I].Value);
    if O.TryGetValue<TJSONArray>('fieldsWithoutComponent', Arr) then
      for I := 0 to Arr.Count - 1 do
        Res.Add('  campo publicado sin objeto en el designer: ' + Arr.Items[I].Value);
    if (Res.Count = 0) and not O.GetValue<Boolean>('ok', True) and
       O.TryGetValue<string>('note', S) then
      Res.Add('  ' + S);
    Result := Res.ToStringArray;
  finally
    Res.Free;
    O.Free;
  end;
end;

function DesignerWiresMethodFile(const ADfm, AMethod: string): Boolean;
var
  Txt, Enc: string;
  M: TMatch;
begin
  Result := False;
  if not TFile.Exists(ADfm) then
    Exit;
  if IsBinaryDesignerFile(ADfm) then
  begin
    if DesignerFileToText(ADfm, Txt) <> '' then
      Exit;
  end
  else
    Txt := PatchLoadText(ADfm, Enc);
  // La misma expresion que el informe, y como la aplica el informe: sobre
  // cada linea RECORTADA (empieza por ^On, sin sangria).
  for var Linea in Txt.Replace(#13#10, #10).Split([#10]) do
  begin
    M := TRegEx.Match(Linea.Trim, EVENT_LINE_RE);
    if M.Success and SameText(M.Groups[2].Value, AMethod) then
      Exit(True);
  end;
end;

end.
