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

function RenamePreview(const AFilePath: string; ALine, ACharacter: Integer;
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
  const ANewName: string): TJSONObject;
var
  Refs, DefObj: TJSONObject;
  Blockers, Warnings, Changes: TJSONArray;
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
        if I >= 100 then
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
      end;
      Result.AddPair('occurrences', TJSONNumber.Create(Arr.Count));
      if Arr.Count > 100 then
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
          if SameText(Item.GetValue('path').Value, DefPath) and
             (Item.GetValue('line').GetValue<Integer> = DefLine) then
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
            Chg.AddPair('kind', 'definition');
            // a qualified implementation header (TClass.Method) must keep the
            // class part: say it instead of letting the agent replace the lot
            if TRegEx.IsMatch(Lines[DefLine],
              '(?i)\b\w+\.' + TRegEx.Escape(Ident) + '\b') then
              Warnings.Add(Format(SN_RENAME_QUALIFIED_FMT, [Lines[DefLine].Trim]));
          end;
        end;
      end;

      // one unverified candidate = not applicable, the adopted rule
      Arr := Refs.GetValue('unverified') as TJSONArray;
      if Arr.Count > 0 then
        Blockers.Add(Format(SR_RENAME_UNVERIFIED_FMT, [Arr.Count]));
      Result.AddPair('unverified', TJSONNumber.Create(Arr.Count));
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

end.
