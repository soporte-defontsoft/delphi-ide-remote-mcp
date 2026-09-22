unit Lsp.Rename;

{ Semantic rename, PREVIEW ONLY in this version - deliberately. DelphiLSP 37
  does not implement textDocument/rename, so the rename is built from the
  pieces this server already trusts: definition() anchors the symbol,
  FindDelphiReferences separates CONFIRMED occurrences (each one re-resolved
  against the same definition) from UNVERIFIED candidates, and the designer
  and string scans look for what a text rename would silently break.

  The rule that decides everything (adopted 2026-08-24): a rename is
  APPLICABLE only when the evidence is complete -

    - ZERO unverified references (one single unconfirmed candidate = no);
    - the symbol's definition lives inside the workspace roots (renaming
      the RTL or an installed component is refused);
    - no designer file (.dfm/.fmx) mentions the identifier: a published
      member rename breaks the form binding and the IDE repairs it only
      interactively;
    - no string literal mentions it (FindComponent('X'), RTTI by name,
      StyleLookup - a text occurrence the compiler never checks);
    - the new name is a legal Delphi identifier, not a reserved word, and
      does not already occur (as a word) in any affected file.

  Anything less returns applicable=false with the reasons, and apply (when
  it exists, over delphi_changeset) will refuse. Preview never writes. }

interface

uses
  System.JSON;

{ ATodas: sin el tope de 100 filas en "changes" - lo que apply necesita, que
  edita cada aparicion y no puede quedarse con las cien primeras. El tope
  protege el transporte de un agente pequeno; apply lo vuelve a poner en la
  RESPUESTA, no en el trabajo. }
function RenamePreview(const AFilePath: string; ALine, ACharacter: Integer;
  const ANewName: string; ATodas: Boolean = False): TJSONObject;

{ El rename APLICADO (1.0.17): el mismo preview, y si es aplicable, sus
  cambios apilados y confirmados por el motor de changeset - una edicion por
  linea tocada, preview, commit: huellas, copias en __delphi-patch y todo o
  nada, exactamente lo que un agente hacia a mano con la lista. La respuesta
  es la del preview mas "applied" y el resultado del commit; si no es
  aplicable no se escribe nada y los blockers dicen por que. }
function RenameApply(const AFilePath: string; ALine, ACharacter: Integer;
  const ANewName: string): TJSONObject;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Lsp.References,
  Lsp.ProjectUnits,
  Lsp.Patch,
  Lsp.Changeset,
  Lsp.Guard,
  Lsp.Session,
  Lsp.Texts;

const
  RESERVED: array [0 .. 64] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto',
    'else', 'end', 'except', 'exports', 'file', 'finalization', 'finally',
    'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library',
    'mod', 'nil', 'not', 'object', 'of', 'or', 'out', 'packed', 'procedure',
    'program', 'property', 'raise', 'record', 'repeat', 'resourcestring',
    'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type',
    'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');

function IsValidIdent_(const S: string): Boolean;
begin
  Result := TRegEx.IsMatch(S, '^[A-Za-z_][A-Za-z0-9_]*$');
end;

{ Occurrences of AIdent as a whole word INSIDE string literals of AText.
  LINEAR scan, never a regex over the whole text: the obvious '(...|'')*'
  pattern backtracks catastrophically on big files - measured 2026-08-24,
  a 1 MB RTL unit blew the stack. }
function StringLiteralHits(const AText, AIdent: string): Integer;
var
  I, J: Integer;
  Lit: string;
begin
  Result := 0;
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = '''' then
    begin
      // find the closing quote ('' escapes)
      J := I + 1;
      while J <= Length(AText) do
      begin
        if AText[J] = '''' then
        begin
          if (J < Length(AText)) and (AText[J + 1] = '''') then
            Inc(J, 2)
          else
            Break;
        end
        else if CharInSet(AText[J], [#10, #13]) then
          Break // unterminated on this line: not a literal
        else
          Inc(J);
      end;
      if (J <= Length(AText)) and (AText[J] = '''') then
      begin
        Lit := Copy(AText, I, J - I + 1);
        if TRegEx.IsMatch(Lit, '(?i)\b' + TRegEx.Escape(AIdent) + '\b') then
          Inc(Result);
        I := J + 1;
      end
      else
        I := J;
    end
    else
      Inc(I);
  end;
end;

function RenamePreview(const AFilePath: string; ALine, ACharacter: Integer;
  const ANewName: string; ATodas: Boolean): TJSONObject;
var
  Refs, DefObj: TJSONObject;
  Blockers, Warnings, Changes, UnvArr, RejArr: TJSONArray;
  Ident, DefPath, EncName, Text, P, Root: string;
  Arr: TJSONArray;
  I, N, Files, DefLine: Integer;
  HasDef: Boolean;
  Lines: TArray<string>;
  Touched: TList<string>;
  Item, Chg: TJSONObject;
  DesignerHits, StringHits: Integer;
  DsgList: TStringList;
begin
  Result := TJSONObject.Create;
  Blockers := TJSONArray.Create;
  Warnings := TJSONArray.Create;
  Changes := TJSONArray.Create;
  Touched := TList<string>.Create;
  try
    // 1. the new name must be legal before any work
    if not IsValidIdent_(ANewName) then
    begin
      Blockers.Add(Format(SR_RENAME_BAD_IDENT_FMT, [ANewName]));
      Result.AddPair('applicable', TJSONBool.Create(False));
      Result.AddPair('blockers', Blockers);
      Blockers := nil;
      Exit;
    end;
    if MatchText(ANewName, RESERVED) then
    begin
      Blockers.Add(Format(SR_RENAME_RESERVED_FMT, [ANewName]));
      Result.AddPair('applicable', TJSONBool.Create(False));
      Result.AddPair('blockers', Blockers);
      Blockers := nil;
      Exit;
    end;

    // 2. the references engine does the semantic work
    Refs := FindDelphiReferences(AFilePath, ALine, ACharacter);
    try
      Ident := Refs.GetValue('identifier').Value;
      Result.AddPair('symbol', Ident);
      Result.AddPair('newName', ANewName);
      if SameText(Ident, ANewName) then
        Blockers.Add(SR_RENAME_SAME_NAME);
      DefObj := Refs.GetValue('definition') as TJSONObject;
      DefPath := DefObj.GetValue('path').Value;
      DefLine := DefObj.GetValue('line').GetValue<Integer>;
      // Same two conventions as "changes", and for the same reason: the
      // number a reader compares them by has to mean the same thing in both.
      var DefOut := TJSONObject(DefObj.Clone);
      if DefOut.GetValue('line') <> nil then
      begin
        DefOut.RemovePair('line').Free;
        DefOut.AddPair('line', TJSONNumber.Create(DefLine + 1));
        DefOut.AddPair('line0', TJSONNumber.Create(DefLine));
      end;
      Result.AddPair('definition', DefOut);
      // the definition must be OURS to rename - and a definition outside
      // the jail (an RTL unit can be 1 MB) is NEVER scanned further
      if PathDenied(DefPath) <> '' then
        Blockers.Add(SR_RENAME_LIBRARY)
      else if not Touched.Contains(DefPath) then
        Touched.Add(DefPath);

      // confirmed occurrences become the change list
      Arr := Refs.GetValue('confirmed') as TJSONArray;
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        P := Item.GetValue('path').Value;
        if not Touched.Contains(P) then
          Touched.Add(P);
        // the change list is capped: a symbol with hundreds of uses must
        // not flood a small client's context (measured 2026-08-24). The
        // caps protect the transport; occurrences/files carry the truth.
        if (I >= 100) and not ATodas then
          Continue;
        Chg := TJSONObject.Create;
        Changes.AddElement(Chg);
        Chg.AddPair('path', P);
        // BOTH conventions, spelled out. "line" used to be the language
        // server's 0-based number while the note told the reader to feed it
        // to delphi_changeset, whose atline is 1-based: a guaranteed
        // off-by-one, and worst exactly where an anchor repeats (a method's
        // declaration and its implementation). delphi_search already answers
        // like this; now so does rename.
        Chg.AddPair('line', TJSONNumber.Create(
          Item.GetValue('line').GetValue<Integer> + 1));
        Chg.AddPair('line0', TJSONNumber.Create(
          Item.GetValue('line').GetValue<Integer>));
        Chg.AddPair('text', Item.GetValue('text').Value);
        if Item.GetValue('anchor') <> nil then
          Chg.AddPair('anchor', Item.GetValue('anchor').Value);
        // Two occurrences on ONE line came out as two identical entries with
        // no column, and "one edit per line" then staged the same line twice
        // (measured 2026-08-25). The column tells them apart, and the count
        // says a single edit has to replace both.
        if Item.GetValue('character') <> nil then
          Chg.AddPair('character', TJSONNumber.Create(
            Item.GetValue('character').GetValue<Integer>));
      end;
      // "occurrences" cuenta REFERENCIAS; "changes" puede llevar una fila mas,
      // la de la propia definicion, que no es una referencia pero si hay que
      // editarla. Decir las dos cifras evita que el que las compare crea que
      // ha encontrado un duplicado.
      Result.AddPair('occurrences', TJSONNumber.Create(Arr.Count));
      if (Arr.Count > 100) and not ATodas then
        Result.AddPair('changesTruncated', TJSONBool.Create(True));

      // The DEFINITION line itself is not a "reference", so it never came in
      // the confirmed list - and changes IS the contract an agent stages.
      // Measured 2026-08-25 by an agent that did exactly what the note said:
      // renaming everything listed left the implementation header untouched
      // and the unit stopped compiling (E2065 Unsatisfied forward). Add it.
      if (DefLine >= 0) and (PathDenied(DefPath) = '') and TFile.Exists(DefPath) then
      begin
        HasDef := False;
        for I := 0 to Changes.Count - 1 do
        begin
          Item := Changes.Items[I] as TJSONObject;
          // POR line0, que es la 0-based - igual que DefLine. Esta linea
          // comparaba "line", que se escribe arriba en base 1, contra DefLine
          // en base 0: nunca casaba, asi que la fila de la definicion se
          // anadia SIEMPRE y todo rename de rutina salia con una fila
          // duplicada y "applicable": true (medido 2026-09-20 por un agente
          // auditor: 13 apariciones reales, 14 filas en "changes"). Y al
          // reves: una aparicion confirmada en la linea justo ANTERIOR a la
          // definicion casaba por accidente y entonces la fila NO se anadia -
          // que es exactamente el E2065 que el comentario de arriba dice
          // haber arreglado. Un off-by-one que fallaba en los dos sentidos.
          if SameText(Item.GetValue('path').Value, DefPath) and
             (Item.GetValue('line0').GetValue<Integer> = DefLine) then
          begin
            HasDef := True;
            Break;
          end;
        end;
        if not HasDef then
        begin
          Lines := PatchLoadText(DefPath, EncName).Replace(#13#10, #10).Split([#10]);
          if (DefLine >= 0) and (DefLine < Length(Lines)) then
          begin
            Chg := TJSONObject.Create;
            Changes.AddElement(Chg);
            Chg.AddPair('path', DefPath);
            Chg.AddPair('line', TJSONNumber.Create(DefLine + 1));
            Chg.AddPair('line0', TJSONNumber.Create(DefLine));
            Chg.AddPair('text', Lines[DefLine].Trim);
            // ...and the anchor, which is the line as it IS. Giving it for
            // every occurrence except the definition meant one last trip to
            // delphi_read for no reason (field round 11).
            Chg.AddPair('anchor', Lines[DefLine].TrimRight([#13, #10]));
            Chg.AddPair('kind', 'definition');
            // a qualified implementation header (TClass.Method) must keep the
            // class part: say it instead of letting the agent replace the lot
            if TRegEx.IsMatch(Lines[DefLine],
              '(?i)\b\w+\.' + TRegEx.Escape(Ident) + '\b') then
              Warnings.Add(Format(SN_RENAME_QUALIFIED_FMT, [Lines[DefLine].Trim]));
          end;
        end;
      end;

      // Cuantas filas lleva "changes" DE VERDAD: es lo que el agente va a
      // estadiar, y puede ser una mas que "occurrences" porque la definicion
      // no es una referencia pero si hay que editarla. Sin esta cifra, quien
      // compare las dos cree que sobra una fila.
      Result.AddPair('changesCount', TJSONNumber.Create(Changes.Count));

      // Las MENCIONES (el nombre escrito en un comentario o en una cadena)
      // llegaban aqui dentro de "unverified" y tumbaban el rename: una linea
      // de documentacion bastaba para que la tool dijera que no se puede.
      // Ya vienen separadas de origen; aqui son un aviso, porque el nombre
      // viejo SI se queda escrito ahi y eso hay que repasarlo a mano.
      if Refs.GetValue('mentionsCount') <> nil then
      begin
        var Menciones := Refs.GetValue('mentionsCount').GetValue<Integer>;
        Result.AddPair('mentions', TJSONNumber.Create(Menciones));
        if Menciones > 0 then
          Warnings.Add(Format(SN_RENAME_MENTIONS_FMT, [Menciones]));
      end;

      // one unverified candidate = not applicable, the adopted rule
      Arr := Refs.GetValue('unverified') as TJSONArray;
      if Arr.Count > 0 then
        Blockers.Add(Format(SR_RENAME_UNVERIFIED_FMT, [Arr.Count]));
      Result.AddPair('unverified', TJSONNumber.Create(Arr.Count));
      // A "homonym" the engine resolved somewhere else may be the real thing
      // seen through another project's settings - which is exactly how a
      // rename came back applicable and broke a sibling's build (measured
      // 2026-08-25). We cannot tell the two apart from here, so they are
      // BLOCKERS with their location: the caller looks and decides.
      if Refs.GetValue('rejected') <> nil then
      begin
        RejArr := Refs.GetValue('rejected') as TJSONArray;
        if RejArr.Count > 0 then
        begin
          Blockers.Add(Format(SR_RENAME_HOMONYMS_FMT, [RejArr.Count]));
          Result.AddPair('lookalikes', TJSONArray(RejArr.Clone));
        end;
      end;
      if Refs.GetValue('scope') <> nil then
        Result.AddPair('scope', TJSONArray(Refs.GetValue('scope').Clone));
      // A COUNT of unverified references blocks the rename and tells you
      // nothing about which ones they are, so there is no way to go and look
      // (measured 2026-08-25). Name them - that is the whole point of a
      // blocker: it has to be actionable.
      if Arr.Count > 0 then
      begin
        UnvArr := TJSONArray.Create;
        Result.AddPair('unverifiedRefs', UnvArr);
        for I := 0 to Arr.Count - 1 do
        begin
          if I >= 50 then
            Break;
          Item := Arr.Items[I] as TJSONObject;
          Chg := TJSONObject.Create;
          UnvArr.AddElement(Chg);
          Chg.AddPair('path', Item.GetValue('path').Value);
          if Item.GetValue('line') <> nil then
          begin
            Chg.AddPair('line', TJSONNumber.Create(
              Item.GetValue('line').GetValue<Integer> + 1));
            Chg.AddPair('line0', TJSONNumber.Create(
              Item.GetValue('line').GetValue<Integer>));
          end;
          if Item.GetValue('text') <> nil then
            Chg.AddPair('text', Item.GetValue('text').Value);
          if Item.GetValue('why') <> nil then
            Chg.AddPair('why', Item.GetValue('why').Value);
        end;
      end;
      Result.AddPair('filesScanned', Refs.GetValue('filesScanned').Clone as TJSONNumber);
    finally
      Refs.Free;
    end;

    // 3. what a text rename would silently break
    DesignerHits := 0;
    StringHits := 0;
    DsgList := TStringList.Create;
    try
      TLspSession.Instance.ResolveSettings(TPath.GetFullPath(AFilePath), Root);
      for P in Touched do
      begin
        // string literals in the code files themselves
        Text := PatchLoadText(P, EncName);
        Inc(StringHits, StringLiteralHits(Text, Ident));
        // the sibling designer of each touched unit
        for var Ext in TArray<string>.Create('.dfm', '.fmx') do
        begin
          var D := TPath.ChangeExtension(P, Ext);
          if TFile.Exists(D) and (DsgList.IndexOf(D) < 0) then
            DsgList.Add(D);
        end;
      end;
      if (Root <> '') and TDirectory.Exists(Root) then
        for var Ext in TArray<string>.Create('*.dfm', '*.fmx') do
          for var D in TDirectory.GetFiles(Root, Ext, TSearchOption.soAllDirectories) do
            if not SkipIdeArtifacts(D) and (DsgList.IndexOf(D) < 0) then
              DsgList.Add(D);
      for P in DsgList do
      begin
        Text := PatchLoadText(P, EncName);
        N := TRegEx.Matches(Text, '(?i)\b' + TRegEx.Escape(Ident) + '\b').Count;
        if N > 0 then
        begin
          Inc(DesignerHits, N);
          Warnings.Add(Format(SN_RENAME_DESIGNER_HIT_FMT, [N, P]));
        end;
      end;
    finally
      DsgList.Free;
    end;
    if DesignerHits > 0 then
      Blockers.Add(Format(SR_RENAME_DESIGNER_FMT, [DesignerHits]));
    if StringHits > 0 then
      Blockers.Add(Format(SR_RENAME_STRINGS_FMT, [StringHits]));

    // 4. collision: the new name already lives in an affected file
    N := 0;
    for P in Touched do
    begin
      Text := PatchLoadText(P, EncName);
      Inc(N, TRegEx.Matches(Text, '(?i)\b' + TRegEx.Escape(ANewName) + '\b').Count);
    end;
    if N > 0 then
      Blockers.Add(Format(SR_RENAME_COLLISION_FMT, [ANewName, N]));

    Files := Touched.Count;
    Result.AddPair('files', TJSONNumber.Create(Files));
    Result.AddPair('changes', Changes);
    Changes := nil;
    Result.AddPair('applicable', TJSONBool.Create(Blockers.Count = 0));
    Result.AddPair('blockers', Blockers);
    Blockers := nil;
    Result.AddPair('warnings', Warnings);
    Warnings := nil;
    Result.AddPair('note', SN_RENAME_PREVIEW_NOTE);
  finally
    Touched.Free;
    Changes.Free;
    Warnings.Free;
    Blockers.Free;
  end;
end;

function RenameApply(const AFilePath: string; ALine, ACharacter: Integer;
  const ANewName: string): TJSONObject;
var
  Changes: TJSONArray;
  Chg: TJSONObject;
  Ident, Id, R, P, EncName, Vieja, Nueva: string;
  Hechas: TStringList;          // path|line0 ya apiladas: dos apariciones en una linea = UNA edicion
  Textos: TDictionary<string, TArray<string>>; // lineas de cada fichero, leidas una vez
  I, L0, Apiladas: Integer;
  Lineas: TArray<string>;

  procedure PonResultado(const AClave: string; AValor: TJSONValue);
  begin
    if Result.GetValue(AClave) <> nil then
      Result.RemovePair(AClave).Free;
    Result.AddPair(AClave, AValor);
  end;

  procedure Fallo(const AMotivo: string);
  begin
    if Id <> '' then
      ChangesetExecute('rollback', Id, '', '', '', '', '', '', 0);
    Id := '';
    PonResultado('applied', TJSONBool.Create(False));
    PonResultado('note', TJSONString.Create(Format(SR_RENAME_APPLY_FAILED_FMT, [AMotivo])));
  end;

begin
  Id := '';
  Result := RenamePreview(AFilePath, ALine, ACharacter, ANewName, True);
  if not ((Result.GetValue('applicable') is TJSONBool) and
          TJSONBool(Result.GetValue('applicable')).AsBoolean) then
  begin
    PonResultado('applied', TJSONBool.Create(False));
    PonResultado('note', TJSONString.Create(SR_RENAME_NOT_APPLICABLE));
    Exit;
  end;
  Changes := Result.GetValue('changes') as TJSONArray;
  Ident := Result.GetValue('symbol').Value;
  Hechas := TStringList.Create;
  Textos := TDictionary<string, TArray<string>>.Create;
  try
    Hechas.CaseSensitive := False;
    Id := ChangesetBegin;
    if Id = '' then
    begin
      Fallo(SR_CHANGESET_TOO_MANY);
      Exit;
    end;
    Apiladas := 0;
    for I := 0 to Changes.Count - 1 do
    begin
      Chg := Changes.Items[I] as TJSONObject;
      P := TPath.GetFullPath(Chg.GetValue('path').Value);
      L0 := Chg.GetValue('line0').GetValue<Integer>;
      if Hechas.IndexOf(P + '|' + IntToStr(L0)) >= 0 then
        Continue;
      Hechas.Add(P + '|' + IntToStr(L0));
      if not Textos.TryGetValue(P.ToLower, Lineas) then
      begin
        Lineas := PatchLoadText(P, EncName).Replace(#13#10, #10).Split([#10]);
        Textos.Add(P.ToLower, Lineas);
      end;
      if (L0 < 0) or (L0 >= Length(Lineas)) then
      begin
        Fallo(Format(SR_RENAME_LINE_GONE_FMT, [L0 + 1, P]));
        Exit;
      end;
      { La linea entera, con el identificador cambiado como PALABRA: la
        cabecera cualificada (TClase.Metodo) conserva la clase, y una
        aparicion doble en la misma linea se cambia de una vez. Todo lo
        que hay en esa linea con ese nombre es el simbolo, porque una sola
        referencia sin confirmar ya ha hecho el rename no aplicable. }
      Vieja := Lineas[L0];
      Nueva := TRegEx.Replace(Vieja, '(?i)\b' + TRegEx.Escape(Ident) + '\b', ANewName);
      if Nueva = Vieja then
        Continue; // una fila que no lleva el nombre (no deberia pasar): nada que apilar
      R := ChangesetExecute('stage', Id, 'edit', P, '', Vieja, Nueva, '', L0 + 1);
      if not ChangesetRespondio(R, SN_CHANGESET_STAGED_FMT) then
      begin
        Fallo(R);
        Exit;
      end;
      Inc(Apiladas);
    end;
    if Apiladas = 0 then
    begin
      Fallo(SR_RENAME_NOTHING_TO_STAGE);
      Exit;
    end;
    R := ChangesetExecute('preview', Id, '', '', '', '', '', '', 0);
    var Prev := TJSONObject.ParseJSONValue(R);
    try
      if not (Prev is TJSONObject) or
         (TJSONObject(Prev).GetValue('unresolved') = nil) or
         (TJSONObject(Prev).GetValue('unresolved').GetValue<Integer> <> 0) then
      begin
        Fallo(R);
        Exit;
      end;
    finally
      Prev.Free;
    end;
    R := ChangesetExecute('commit', Id, '', '', '', '', '', '', 0);
    Id := ''; // commit consume el changeset, haya ido bien o mal
    if not ChangesetRespondio(R, SN_CHANGESET_COMMITTED_FMT) then
    begin
      Fallo(R);
      Exit;
    end;
    PonResultado('applied', TJSONBool.Create(True));
    PonResultado('editsApplied', TJSONNumber.Create(Apiladas));
    PonResultado('commit', TJSONString.Create(R));
    PonResultado('note', TJSONString.Create(SN_RENAME_APPLIED_NOTE));
    { El tope de 100 filas vuelve a la RESPUESTA: lo aplicado esta en el
      disco, y un simbolo con cientos de usos no tiene que inundar el
      contexto de un cliente pequeno. }
    if Changes.Count > 100 then
    begin
      while Changes.Count > 100 do
        Changes.Remove(Changes.Count - 1).Free;
      PonResultado('changesTruncated', TJSONBool.Create(True));
    end;
  finally
    Textos.Free;
    Hechas.Free;
  end;
end;

end.
