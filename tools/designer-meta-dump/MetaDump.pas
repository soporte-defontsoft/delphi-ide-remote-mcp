unit MetaDump;

{ The shared heart of the designer-metadata dumpers: walks every LINKED
  TPersistent class via RTTI and writes a generated .pas table the server's
  designer lint resolves against - the framework describing itself, nothing
  hand-written. Run at RELEASE time by us, never by the server.

  Emitted lines (compact, one fact per line):
    C <ClassName>                      streaming-relevant class
    P <ClassName> <Prop> <k> <Type>    published property (inherited incl.)
                                       k: c=class e=enum s=set m=method
                                          r=record o=other
    E <EnumType> <v1,v2,...>           enum members
    S <SetType> <e1,e2,...>            set element names
    A <ClassName>.<Prop> <RuntimeCls>  the INSTANCE class a class-typed
                                       property really holds (streaming
                                       resolves sub-properties against it,
                                       not the declared type - measured:
                                       TLabel.TextSettings declares
                                       TTextSettings, public props only,
                                       but holds a descendant that
                                       re-publishes them). Discovered by
                                       INSTANTIATING each component here,
                                       in this offline tool - never in the
                                       server.

  The host .dpr must set STRONGLINKTYPES ON: without it the smart linker
  strips unreferenced classes and they vanish from RTTI (measured concern -
  the whole point is covering classes no code references). }

interface

procedure DumpMeta(const AUnitName, AOutPasPath: string);

implementation

uses
  System.SysUtils, System.Classes, System.Rtti, System.TypInfo,
  System.Generics.Collections;

procedure DumpMeta(const AUnitName, AOutPasPath: string);
var
  Ctx: TRttiContext;
  T: TRttiType;
  P: TRttiProperty;
  Facts: TStringList;
  ClassesDone, TypesDone: TDictionary<string, Boolean>;
  Skipped: Integer;

  { A member list only makes sense for a HUMAN-sized enum; exotic types
    (huge or negative ranges - the FMX dump died with EIntOverflow on one)
    are skipped: the lint simply won't value-check them. }
  function EnumMembers(ATI: PTypeInfo): string;
  var
    I: Integer;
    TD: PTypeData;
  begin
    Result := '';
    TD := GetTypeData(ATI);
    if (TD.MinValue < 0) or (TD.MaxValue < TD.MinValue) or
       (Int64(TD.MaxValue) - Int64(TD.MinValue) > 256) then
      Exit;
    for I := TD.MinValue to TD.MaxValue do
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + GetEnumName(ATI, I);
    end;
  end;

  procedure EmitEnum(ATI: PTypeInfo);
  var
    S: string;
  begin
    if (ATI = nil) or (ATI.Kind <> tkEnumeration) then
      Exit;
    if TypesDone.ContainsKey(string(ATI.Name)) then
      Exit;
    TypesDone.Add(string(ATI.Name), True);
    try
      S := EnumMembers(ATI);
    except
      S := '';
    end;
    if S <> '' then
      Facts.Add('E ' + string(ATI.Name) + ' ' + S)
    else
      Inc(Skipped);
  end;

  procedure EmitSet(ATI: PTypeInfo);
  var
    S: string;
    Comp: PTypeInfo;
  begin
    if (ATI = nil) or (ATI.Kind <> tkSet) then
      Exit;
    if TypesDone.ContainsKey(string(ATI.Name)) then
      Exit;
    TypesDone.Add(string(ATI.Name), True);
    if GetTypeData(ATI).CompType = nil then
      Exit;
    Comp := GetTypeData(ATI).CompType^;
    if (Comp = nil) or (Comp.Kind <> tkEnumeration) then
      Exit;
    try
      S := EnumMembers(Comp);
    except
      S := '';
    end;
    if S <> '' then
      Facts.Add('S ' + string(ATI.Name) + ' ' + S)
    else
      Inc(Skipped);
  end;

  function KindOf(ATI: PTypeInfo): Char;
  begin
    if ATI = nil then
      Exit('o');
    case ATI.Kind of
      tkClass: Result := 'c';
      tkEnumeration: Result := 'e';
      tkSet: Result := 's';
      tkMethod: Result := 'm';
      tkRecord, tkMRecord: Result := 'r';
    else
      Result := 'o';
    end;
  end;

var
  IT: TRttiInstanceType;
  Pas: TStringList;
  I: Integer;

  { Dump one class's published surface (classic typinfo - what TReader
    streams against). Returns False if it was already dumped. }
  function DumpClass(const ACls: TClass): Boolean;
  var
    L: PPropList;
    N, X: Integer;
    Pr: PPropInfo;
    Ti: PTypeInfo;
    Kc: Char;
  begin
    if ClassesDone.ContainsKey(ACls.ClassName) then
      Exit(False);
    ClassesDone.Add(ACls.ClassName, True);
    Facts.Add('C ' + ACls.ClassName);
    N := GetPropList(ACls.ClassInfo, L);
    if N > 0 then
    try
      for X := 0 to N - 1 do
      begin
        Pr := L^[X];
        Ti := Pr.PropType^;
        Kc := KindOf(Ti);
        if Kc = 'e' then
          EmitEnum(Ti)
        else if Kc = 's' then
          EmitSet(Ti);
        if Ti <> nil then
          Facts.Add('P ' + ACls.ClassName + ' ' + string(Pr.Name) + ' ' +
            Kc + ' ' + string(Ti.Name))
        else
          Facts.Add('P ' + ACls.ClassName + ' ' + string(Pr.Name) + ' o ?');
      end;
    finally
      FreeMem(L);
    end;
    Result := True;
  end;

  { The streaming truth pass: INSTANTIATE each component (this offline tool
    may - the server never does) and record, for every class-typed published
    property, the class the instance REALLY holds, dumping its surface too.
    That is what TReader resolves sub-properties against. }
  procedure DumpInstanceAliases(const ACls: TClass);
  var
    Inst: TComponent;
    L: PPropList;
    N, X: Integer;
    Pr: PPropInfo;
    O: TObject;
  begin
    if not ACls.InheritsFrom(TComponent) then
      Exit;
    try
      Inst := TComponentClass(ACls).Create(nil);
    except
      Inc(Skipped);
      Exit;
    end;
    try
      N := GetPropList(ACls.ClassInfo, L);
      if N > 0 then
      try
        for X := 0 to N - 1 do
        begin
          Pr := L^[X];
          if (Pr.PropType = nil) or (Pr.PropType^.Kind <> tkClass) then
            Continue;
          try
            O := GetObjectProp(Inst, Pr);
          except
            Continue;
          end;
          if O = nil then
            Continue;
          DumpClass(O.ClassType);
          Facts.Add('A ' + ACls.ClassName + '.' + string(Pr.Name) + ' ' +
            O.ClassType.ClassName);
        end;
      finally
        FreeMem(L);
      end;
    finally
      try
        Inst.Free;
      except
        // a component that cannot free cleanly outside its framework
        // context stays leaked in this short-lived offline tool - fine
      end;
    end;
  end;
begin
  Skipped := 0;
  Ctx := TRttiContext.Create;
  Facts := TStringList.Create;
  ClassesDone := TDictionary<string, Boolean>.Create;
  TypesDone := TDictionary<string, Boolean>.Create;
  try
    for T in Ctx.GetTypes do
    begin
      if not (T is TRttiInstanceType) then
        Continue;
      IT := TRttiInstanceType(T);
      // one exotic type must not kill the whole dump
      try
        if not IT.MetaclassType.InheritsFrom(TPersistent) then
          Continue;
        // classic published typinfo (GetPropList) - the SAME metadata
        // TReader streams against; System.Rtti hides properties when a
        // unit compiles with restricted $RTTI (measured: TTextSettings
        // came out empty via Rtti while real .fmx files stream
        // TextSettings.HorzAlign happily)
        if DumpClass(IT.MetaclassType) then
          DumpInstanceAliases(IT.MetaclassType);
      except
        on E: Exception do
        begin
          Inc(Skipped);
          Writeln('  (saltado ' + IT.MetaclassType.ClassName + ': ' +
            E.ClassName + ')');
        end;
      end;
    end;

    Pas := TStringList.Create;
    try
      Pas.Add('unit ' + AUnitName + ';');
      Pas.Add('');
      Pas.Add('{ GENERATED by tools\designer-meta-dump - DO NOT EDIT.');
      Pas.Add('  The framework''s own RTTI (classes, published properties,');
      Pas.Add('  enum and set members) for the designer lint. Regenerate');
      Pas.Add('  after a RAD Studio upgrade: build the dumpers and run them');
      Pas.Add('  (see the .dpr headers). }');
      Pas.Add('');
      Pas.Add('interface');
      Pas.Add('');
      Pas.Add('const');
      Pas.Add(Format('  META_COUNT = %d;', [Facts.Count]));
      Pas.Add(Format('  META: array [0 .. %d] of string = (', [Facts.Count - 1]));
      for I := 0 to Facts.Count - 1 do
        if I < Facts.Count - 1 then
          Pas.Add('    ''' + Facts[I] + ''',')
        else
          Pas.Add('    ''' + Facts[I] + '''');
      Pas.Add('  );');
      Pas.Add('');
      Pas.Add('implementation');
      Pas.Add('');
      Pas.Add('end.');
      Pas.SaveToFile(AOutPasPath, TEncoding.UTF8);
      Writeln(Format('%s: %d hechos (%d clases, %d tipos saltados) -> %s',
        [AUnitName, Facts.Count, ClassesDone.Count, Skipped, AOutPasPath]));
    finally
      Pas.Free;
    end;
  finally
    TypesDone.Free;
    ClassesDone.Free;
    Facts.Free;
    Ctx.Free;
  end;
end;

end.
