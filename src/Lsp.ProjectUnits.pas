unit Lsp.ProjectUnits;

{ The ONE place that registers a unit in a Delphi project - what the IDE does
  on "Add to project" / "Remove from project" / rename:

  - .dpr  : the "Name in 'path.pas' (Form)" entry in the program's uses
            clause, plus `Application.CreateForm(TForm, Form)` for forms and
            data modules (never for frames).
  - .dproj: the <DCCReference Include="path.pas"> item (with <Form>,
            <FormType>, <DesignClass> for designer units), the IDE's shape.

  delphi_create, delphi_config add-unit/remove-unit, delphi_delete and
  delphi_move all go through here, so the agent never edits the .dpr/.dproj
  by hand. Edits are curated (only the affected entry moves), encoding-
  preserving and backed up through Lsp.Patch. }

interface

uses
  System.SysUtils, System.Classes, System.JSON;

type
  { What a .pas is to the project: a plain unit or a designer unit. }
  TUnitInfo = record
    UnitName: string;    // from the `unit X;` header (dotted allowed)
    PasPath: string;     // absolute
    Designer: string;    // '' | absolute path of the .dfm/.fmx
    FormName: string;    // variable name (Form1), '' for plain units
    ClassName: string;   // TForm1
    Ancestor: string;    // TForm / TDataModule / TFrame / ...
    FormType: string;    // 'dfm' | 'fmx' | ''
    DesignClass: string; // 'TDataModule' | 'TFrame' | '' (plain form)
    function IsDesigner: Boolean;
    function NeedsCreateForm: Boolean; // forms and data modules, not frames
  end;

  TProjectUnit = record
    UnitName: string;
    Include: string;     // as written in the .dpr ('Unit1.pas', 'src\X.pas')
    FormName: string;    // from the {Form} comment, '' for plain units
    InDproj: Boolean;    // has its <DCCReference>
  end;

{ Resolves a .dpr or .dproj to the pair (both absolute). Either may be given.
  Returns '' when OK, else a refusal text. }
function ResolveProjectPair(const AProject: string; out ADpr, ADproj: string): string;

{ Inspects a .pas (header, designer pair, class/ancestor/variable). Returns ''
  when OK, else a refusal text (no header, header/file mismatch...). }
function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;

{ Adds the unit to the .dpr uses (+ CreateForm) and the .dproj. Idempotent:
  an entry already present is left alone and reported. }
function AddProjectUnit(const AProject, APasPath: string): string;

{ Takes the unit out of the .dpr (uses + CreateForm) and the .dproj. The
  file itself stays on disk. }
function RemoveProjectUnit(const AProject, APasPath: string): string;

{ Re-points an existing entry to a new path/name (the file was already moved
  or renamed by the caller; the new file's header decides the unit name). }
function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;

{ The units a project lists (from the .dpr uses, cross-checked with the
  .dproj). Never raises; empty on unreadable input. }
function ProjectUnits(const AProject: string): TArray<TProjectUnit>;

{ Adds a "units" array to AReturn (for delphi_config view). }
procedure AddUnitsView(const ADproj: string; AReturn: TJSONObject);

{ Projects (.dproj paths) in ADir and its parent that list APasPath. For the
  file tools: delete/move a unit keeps the projects that use it consistent. }
function ProjectsUsingUnit(const APasPath: string): TArray<string>;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions,
  Lsp.Patch, Lsp.Texts;

{ TUnitInfo }

function TUnitInfo.IsDesigner: Boolean;
begin
  Result := Designer <> '';
end;

function TUnitInfo.NeedsCreateForm: Boolean;
begin
  Result := IsDesigner and (FormName <> '') and (DesignClass <> 'TFrame');
end;

{ ---- paths ---- }

function NormPath(const P: string): string;
begin
  Result := TPath.GetFullPath(P).Replace('/', '\').ToLower;
end;

function ResolveProjectPair(const AProject: string; out ADpr, ADproj: string): string;
var
  Ext, Stem: string;
begin
  Result := '';
  ADpr := '';
  ADproj := '';
  if AProject.Trim = '' then
    Exit(SR_UNIT_NEED_PROJECT);
  Ext := TPath.GetExtension(AProject).ToLower;
  Stem := TPath.Combine(TPath.GetDirectoryName(TPath.GetFullPath(AProject)),
    TPath.GetFileNameWithoutExtension(AProject));
  if (Ext <> '.dpr') and (Ext <> '.dproj') then
    Exit(Format(SR_UNIT_PROJECT_EXT_FMT, [TPath.GetFileName(AProject)]));
  ADpr := Stem + '.dpr';
  ADproj := Stem + '.dproj';
  if not TFile.Exists(ADpr) then
    Exit(Format(SR_UNIT_NO_DPR_FMT, [ADpr]));
  // a missing .dproj is tolerated: the .dpr alone still builds with dcc, and
  // the IDE regenerates a .dproj on open. The dproj edits are then skipped.
end;

{ Relative path from the .dpr folder to APas, with backslashes - the form the
  IDE writes in both files. Outside the tree: absolute (the IDE does the same
  for ..\ up to a point; absolute is unambiguous). }
function IncludeFor(const ADpr, APas: string): string;
var
  Base, Full: string;
begin
  Base := IncludeTrailingPathDelimiter(TPath.GetDirectoryName(TPath.GetFullPath(ADpr)));
  Full := TPath.GetFullPath(APas);
  if Full.ToLower.StartsWith(Base.ToLower) then
    Result := Full.Substring(Length(Base))
  else
    Result := Full;
end;

{ ---- unit inspection ---- }

function DesignerHeaderName(const ADesigner: string; out AName, AClass: string): Boolean;
var
  B: TBytes;
  Enc, Line: string;
  Lines: TArray<string>;
  M: TMatch;
begin
  Result := False;
  AName := '';
  AClass := '';
  B := TFile.ReadAllBytes(ADesigner);
  if Length(B) < 4 then
    Exit;
  // binary designer (TPF0 stream or $FF resource wrapper): no text header
  if (B[0] = $FF) or ((B[0] = $54) and (B[1] = $50) and (B[2] = $46) and (B[3] = $30)) then
    Exit;
  Lines := PatchLoadText(ADesigner, Enc).Replace(#13#10, #10).Split([#10]);
  for Line in Lines do
  begin
    M := TRegEx.Match(Line, '^\s*(object|inherited)\s+(\w+)\s*:\s*(\w+)', [roIgnoreCase]);
    if M.Success then
    begin
      AName := M.Groups[2].Value;
      AClass := M.Groups[3].Value;
      Exit(True);
    end;
    if Line.Trim <> '' then
      Break; // the first non-blank line is the root object
  end;
end;

function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;
var
  Enc, Src, Stem, DName, DClass: string;
  M: TMatch;
begin
  Result := '';
  AInfo := Default(TUnitInfo);
  if not TFile.Exists(APasPath) then
    Exit(Format(SR_UNIT_PAS_MISSING_FMT, [APasPath]));
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
    Exit(Format(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  AInfo.PasPath := TPath.GetFullPath(APasPath);
  Src := PatchLoadText(AInfo.PasPath, Enc);
  M := TRegEx.Match(Src, '^\s*unit\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;', [roIgnoreCase, roMultiline]);
  if not M.Success then
    Exit(Format(SR_UNIT_NO_HEADER_FMT, [TPath.GetFileName(APasPath)]));
  AInfo.UnitName := M.Groups[1].Value;
  Stem := TPath.GetFileNameWithoutExtension(AInfo.PasPath);
  if not SameText(Stem, AInfo.UnitName) then
    Exit(Format(SR_UNIT_HEADER_MISMATCH_FMT, [AInfo.UnitName, TPath.GetFileName(APasPath)]));

  // designer pair?
  if TFile.Exists(ChangeFileExt(AInfo.PasPath, '.dfm')) then
  begin
    AInfo.Designer := ChangeFileExt(AInfo.PasPath, '.dfm');
    AInfo.FormType := 'dfm';
  end
  else if TFile.Exists(ChangeFileExt(AInfo.PasPath, '.fmx')) then
  begin
    AInfo.Designer := ChangeFileExt(AInfo.PasPath, '.fmx');
    AInfo.FormType := 'fmx';
  end;
  if AInfo.Designer = '' then
    Exit;

  // the designer's root object names the form; the .pas gives the ancestor
  if DesignerHeaderName(AInfo.Designer, DName, DClass) then
  begin
    AInfo.FormName := DName;
    AInfo.ClassName := DClass;
    M := TRegEx.Match(Src, '\b' + TRegEx.Escape(DClass) + '\s*=\s*class\s*\(\s*(\w+)', [roIgnoreCase]);
  end
  else
  begin
    // binary designer: the first designer class in the .pas, then its variable
    M := TRegEx.Match(Src, '\b(T\w+)\s*=\s*class\s*\(\s*(T(?:Form|DataModule|Frame)\w*)', [roIgnoreCase]);
    if M.Success then
    begin
      AInfo.ClassName := M.Groups[1].Value;
      var V := TRegEx.Match(Src, '^\s*(\w+)\s*:\s*' + TRegEx.Escape(AInfo.ClassName) + '\s*;',
        [roIgnoreCase, roMultiline]);
      if V.Success then
        AInfo.FormName := V.Groups[1].Value;
    end;
  end;
  if M.Success then
    AInfo.Ancestor := M.Groups[M.Groups.Count - 1].Value;
  if SameText(AInfo.Ancestor, 'TDataModule') or AInfo.Ancestor.ToLower.Contains('datamodule') then
    AInfo.DesignClass := 'TDataModule'
  else if SameText(AInfo.Ancestor, 'TFrame') or AInfo.Ancestor.ToLower.Contains('frame') then
    AInfo.DesignClass := 'TFrame';
end;

{ ---- .dpr uses clause ---- }

type
  TUsesClause = record
    Found: Boolean;
    StartPos: Integer;  // index (1-based) of the 'u' of 'uses'
    EndPos: Integer;    // index of the closing ';'
    Entries: TArray<string>; // raw entry texts, trimmed
  end;

{ Splits the clause body on top-level commas (outside quotes and braces). }
function SplitEntries(const Body: string): TArray<string>;
var
  I, Depth: Integer;
  InQ: Boolean;
  Cur: string;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    InQ := False;
    Depth := 0;
    Cur := '';
    for I := 1 to Length(Body) do
    begin
      case Body[I] of
        '''': InQ := not InQ;
        '{': if not InQ then Inc(Depth);
        '}': if not InQ and (Depth > 0) then Dec(Depth);
      end;
      if (Body[I] = ',') and not InQ and (Depth = 0) then
      begin
        if Cur.Trim <> '' then
          L.Add(Cur.Trim);
        Cur := '';
      end
      else
        Cur := Cur + Body[I];
    end;
    if Cur.Trim <> '' then
      L.Add(Cur.Trim);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function FindUses(const Dpr: string): TUsesClause;
var
  M: TMatch;
  I, Depth: Integer;
  InQ: Boolean;
begin
  Result := Default(TUsesClause);
  // the program's uses: first 'uses' keyword at line start after 'program'
  M := TRegEx.Match(Dpr, '^\s*uses\b', [roIgnoreCase, roMultiline]);
  if not M.Success then
    Exit;
  Result.StartPos := M.Index + (Length(M.Value) - Length(M.Value.TrimLeft));
  InQ := False;
  Depth := 0;
  for I := M.Index + M.Length to Length(Dpr) do
  begin
    case Dpr[I] of
      '''': InQ := not InQ;
      '{': if not InQ then Inc(Depth);
      '}': if not InQ and (Depth > 0) then Dec(Depth);
      ';': if not InQ and (Depth = 0) then
        begin
          Result.EndPos := I;
          Result.Found := True;
          Result.Entries := SplitEntries(Copy(Dpr, M.Index + M.Length, I - (M.Index + M.Length)));
          Exit;
        end;
    end;
  end;
end;

function EntryUnitName(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '^([A-Za-z_][\w.]*)');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := Entry;
end;

function EntryInclude(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '\bin\s*''([^'']+)''', [roIgnoreCase]);
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

function EntryFormName(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '\{\s*(\w+)');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

function BuildEntry(const AInfo: TUnitInfo; const AInclude: string): string;
begin
  Result := AInfo.UnitName + ' in ''' + AInclude + '''';
  if AInfo.IsDesigner and (AInfo.FormName <> '') then
  begin
    if AInfo.DesignClass <> '' then
      Result := Result + ' {' + AInfo.FormName + ': ' + AInfo.DesignClass + '}'
    else
      Result := Result + ' {' + AInfo.FormName + '}';
  end;
end;

{ Rewrites the clause with AEntries, keeping the text before/after intact.
  Entries go one per line, two-space indent, like the IDE. }
function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
var
  Body, NL: string;
begin
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  Body := 'uses' + NL + '  ' + string.Join(',' + NL + '  ', AEntries) + ';';
  Result := Copy(Dpr, 1, U.StartPos - 1) + Body + Copy(Dpr, U.EndPos + 1, MaxInt);
end;

function CreateFormLine(const AInfo: TUnitInfo): string;
begin
  Result := 'Application.CreateForm(' + AInfo.ClassName + ', ' + AInfo.FormName + ');';
end;

{ Inserts the CreateForm after the last existing CreateForm, else right
  before Application.Run. Returns False when neither anchor exists. }
function InsertCreateForm(var Dpr: string; const AInfo: TUnitInfo): Boolean;
var
  Lines: TArray<string>;
  I, Last, RunAt: Integer;
  NL, Indent: string;
  L: TStringList;
begin
  Result := False;
  if TRegEx.IsMatch(Dpr, '\bCreateForm\s*\(\s*' + TRegEx.Escape(AInfo.ClassName) + '\s*,', [roIgnoreCase]) then
    Exit(True); // already there
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  Lines := Dpr.Replace(#13#10, #10).Split([#10]);
  Last := -1;
  RunAt := -1;
  for I := 0 to High(Lines) do
  begin
    if TRegEx.IsMatch(Lines[I], '^\s*Application\.CreateForm\s*\(', [roIgnoreCase]) then
      Last := I;
    if (RunAt = -1) and TRegEx.IsMatch(Lines[I], '^\s*Application\.Run\b', [roIgnoreCase]) then
      RunAt := I;
  end;
  if (Last = -1) and (RunAt = -1) then
    Exit;
  L := TStringList.Create;
  try
    L.AddStrings(Lines);
    if Last <> -1 then
    begin
      Indent := Copy(Lines[Last], 1, Length(Lines[Last]) - Length(Lines[Last].TrimLeft));
      L.Insert(Last + 1, Indent + CreateFormLine(AInfo));
    end
    else
    begin
      Indent := Copy(Lines[RunAt], 1, Length(Lines[RunAt]) - Length(Lines[RunAt].TrimLeft));
      L.Insert(RunAt, Indent + CreateFormLine(AInfo));
    end;
    Dpr := string.Join(NL, L.ToStringArray);
  finally
    L.Free;
  end;
  Result := True;
end;

{ Drops every Application.CreateForm line naming AClass or AVar. }
function RemoveCreateForm(var Dpr: string; const AClassName, AFormName: string): Integer;
var
  Lines: TArray<string>;
  I: Integer;
  NL: string;
  L: TStringList;
  Pat: string;
begin
  Result := 0;
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  Lines := Dpr.Replace(#13#10, #10).Split([#10]);
  Pat := '^\s*Application\.CreateForm\s*\(\s*(' + TRegEx.Escape(AClassName) + '\s*,|\w+\s*,\s*' +
    TRegEx.Escape(AFormName) + '\s*\))';
  L := TStringList.Create;
  try
    for I := 0 to High(Lines) do
      if (AClassName <> '') and TRegEx.IsMatch(Lines[I], Pat, [roIgnoreCase]) then
        Inc(Result)
      else
        L.Add(Lines[I]);
    if Result > 0 then
      Dpr := string.Join(NL, L.ToStringArray);
  finally
    L.Free;
  end;
end;

{ ---- .dproj DCCReference ---- }

function DccRefXml(const AInfo: TUnitInfo; const AInclude: string): string;
const
  CRLF = #13#10;
begin
  if AInfo.IsDesigner and (AInfo.FormName <> '') then
  begin
    Result := '        <DCCReference Include="' + AInclude + '">' + CRLF +
      '            <Form>' + AInfo.FormName + '</Form>' + CRLF;
    if AInfo.FormType <> '' then
      Result := Result + '            <FormType>' + AInfo.FormType + '</FormType>' + CRLF;
    if AInfo.DesignClass <> '' then
      Result := Result + '            <DesignClass>' + AInfo.DesignClass + '</DesignClass>' + CRLF;
    Result := Result + '        </DCCReference>' + CRLF;
  end
  else
    Result := '        <DCCReference Include="' + AInclude + '"/>' + CRLF;
end;

{ Finds the element for AInclude (path compared case-insensitively with / and
  \ unified). Returns its [Start, Len) in Xml including the trailing newline. }
function FindDccRef(const Xml, AInclude: string; out AStart, ALen: Integer): Boolean;
var
  M: TMatch;
  Want, Got: string;
begin
  Result := False;
  Want := AInclude.Replace('/', '\').ToLower;
  for M in TRegEx.Matches(Xml, '[ \t]*<DCCReference\s+Include="([^"]*)"\s*(/>|>.*?</DCCReference>)\s*?(\r?\n|$)',
    [roIgnoreCase, roSingleline]) do
  begin
    Got := M.Groups[1].Value.Replace('/', '\').ToLower;
    if Got = Want then
    begin
      AStart := M.Index;
      ALen := M.Length;
      Exit(True);
    end;
  end;
end;

{ Inserts the element after the last DCCReference; else after </DelphiCompile>;
  else before the first <BuildConfiguration; else before the first </ItemGroup>. }
function InsertDccRef(const Xml, AElement: string): string;
var
  M: TMatch;
  At: Integer;
begin
  At := 0;
  for M in TRegEx.Matches(Xml, '[ \t]*<DCCReference\s[^>]*?(/>|>.*?</DCCReference>)[ \t]*\r?\n', [roIgnoreCase, roSingleline]) do
    At := M.Index + M.Length;
  if At = 0 then
  begin
    M := TRegEx.Match(Xml, '</DelphiCompile>[ \t]*\r?\n', [roIgnoreCase]);
    if M.Success then
      At := M.Index + M.Length
    else
    begin
      M := TRegEx.Match(Xml, '[ \t]*<BuildConfiguration\s', [roIgnoreCase]);
      if not M.Success then
        M := TRegEx.Match(Xml, '[ \t]*</ItemGroup>', [roIgnoreCase]);
      if not M.Success then
        Exit(Xml); // no ItemGroup at all: the caller reports "not in .dproj"
      At := M.Index;
    end;
  end;
  Result := Copy(Xml, 1, At - 1) + AElement + Copy(Xml, At, MaxInt);
end;

{ ---- public operations ---- }

function AddProjectUnit(const AProject, APasPath: string): string;
var
  Dpr, Dproj, Enc, Text, Include, Entry, Note: string;
  Info: TUnitInfo;
  U: TUsesClause;
  E: string;
  Present: Boolean;
  Entries: TArray<string>;
  S, L: Integer;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Result := InspectUnit(APasPath, Info);
  if Result <> '' then
    Exit;
  Include := IncludeFor(Dpr, Info.PasPath);

  // .dpr
  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(Format(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  Present := False;
  for E in U.Entries do
    if SameText(EntryUnitName(E), Info.UnitName) then
      Present := True;
  Note := '';
  if not Present then
  begin
    Entries := U.Entries;
    Entries := Entries + [BuildEntry(Info, Include)];
    Text := ReplaceUses(Text, U, Entries);
  end;
  if Info.NeedsCreateForm then
  begin
    if not InsertCreateForm(Text, Info) then
      Note := SN_UNIT_NO_RUN_ANCHOR;
  end;
  PatchSaveText(Dpr, Text, Enc);

  // .dproj
  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, Include, S, L) then
    begin
      // refresh the element (a plain unit that gained a form, for instance)
      Text := Copy(Text, 1, S - 1) + DccRefXml(Info, Include) + Copy(Text, S + L, MaxInt);
    end
    else
    begin
      Entry := InsertDccRef(Text, DccRefXml(Info, Include));
      if Entry = Text then
        Note := Note + IfThen(Note <> '', ' ', '') + SN_UNIT_NO_ITEMGROUP
      else
        Text := Entry;
    end;
    PatchSaveText(Dproj, Text, Enc);
  end
  else
    Note := Note + IfThen(Note <> '', ' ', '') + SN_UNIT_NO_DPROJ;

  if Present then
    Result := Format(SN_UNIT_PRESENT_FMT, [Info.UnitName, TPath.GetFileName(Dpr)])
  else if Info.IsDesigner then
    Result := Format(SN_UNIT_ADDED_FORM_FMT, [Info.UnitName, Include, Info.FormName,
      Info.ClassName, TPath.GetFileName(Dpr), IfThen(Info.NeedsCreateForm, SN_UNIT_CREATEFORM, '')])
  else
    Result := Format(SN_UNIT_ADDED_FMT, [Info.UnitName, Include, TPath.GetFileName(Dpr)]);
  if Note <> '' then
    Result := Result + #10 + Note;
end;

{ The entry and the .dproj include for a unit, by unit name or by file stem
  (the .pas may already be gone when delete calls us). }
function LocateEntry(const U: TUsesClause; const AUnitName: string; out AEntry: string): Boolean;
var
  E: string;
begin
  for E in U.Entries do
    if SameText(EntryUnitName(E), AUnitName) then
    begin
      AEntry := E;
      Exit(True);
    end;
  Result := False;
end;

function RemoveProjectUnit(const AProject, APasPath: string): string;
var
  Dpr, Dproj, Enc, Text, UnitName, Entry, Include, FormName, ClassName: string;
  U: TUsesClause;
  Entries: TArray<string>;
  E: string;
  S, L, N: Integer;
  Info: TUnitInfo;
  InDpr, InDproj: Boolean;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
    Exit(Format(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  UnitName := TPath.GetFileNameWithoutExtension(APasPath);
  ClassName := '';
  FormName := '';
  if InspectUnit(APasPath, Info) = '' then
  begin
    UnitName := Info.UnitName;
    ClassName := Info.ClassName;
    FormName := Info.FormName;
  end;

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(Format(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  InDpr := LocateEntry(U, UnitName, Entry);
  Include := IncludeFor(Dpr, TPath.GetFullPath(APasPath));
  if InDpr then
  begin
    if EntryInclude(Entry) <> '' then
      Include := EntryInclude(Entry);
    if FormName = '' then
      FormName := EntryFormName(Entry);
    Entries := [];
    for E in U.Entries do
      if not SameText(EntryUnitName(E), UnitName) then
        Entries := Entries + [E];
    Text := ReplaceUses(Text, U, Entries);
    if (ClassName = '') and (FormName <> '') then
      ClassName := 'T' + FormName; // the usual pairing when the .pas is gone
    N := RemoveCreateForm(Text, ClassName, FormName);
    PatchSaveText(Dpr, Text, Enc);
  end
  else
    N := 0;

  InDproj := False;
  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, Include, S, L) then
    begin
      Text := Copy(Text, 1, S - 1) + Copy(Text, S + L, MaxInt);
      PatchSaveText(Dproj, Text, Enc);
      InDproj := True;
    end;
  end;

  if not (InDpr or InDproj) then
    Exit(Format(SN_UNIT_ABSENT_FMT, [UnitName, TPath.GetFileName(Dpr)]));
  Result := Format(SN_UNIT_REMOVED_FMT, [UnitName, TPath.GetFileName(Dpr),
    IfThen(InDpr, 'uses', '-'), IfThen(N > 0, ' + CreateForm', ''),
    IfThen(InDproj, ', DCCReference del .dproj', ''), TPath.GetFileName(APasPath)]);
end;

function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;
var
  Dpr, Dproj, Enc, Text, OldName, OldInclude, Entry, NewInclude: string;
  U: TUsesClause;
  Entries: TArray<string>;
  E: string;
  Info: TUnitInfo;
  S, L, I: Integer;
  Found: Boolean;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Result := InspectUnit(ANewPasPath, Info);
  if Result <> '' then
    Exit;
  OldName := TPath.GetFileNameWithoutExtension(AOldPasPath);
  NewInclude := IncludeFor(Dpr, Info.PasPath);

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(Format(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  Found := LocateEntry(U, OldName, Entry);
  if not Found then
    Exit(Format(SN_UNIT_ABSENT_FMT, [OldName, TPath.GetFileName(Dpr)]));
  OldInclude := EntryInclude(Entry);
  if OldInclude = '' then
    OldInclude := IncludeFor(Dpr, TPath.GetFullPath(AOldPasPath));
  Entries := U.Entries;
  for I := 0 to High(Entries) do
    if SameText(EntryUnitName(Entries[I]), OldName) then
      Entries[I] := BuildEntry(Info, NewInclude);
  Text := ReplaceUses(Text, U, Entries);
  PatchSaveText(Dpr, Text, Enc);

  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, OldInclude, S, L) then
      Text := Copy(Text, 1, S - 1) + DccRefXml(Info, NewInclude) + Copy(Text, S + L, MaxInt)
    else
    begin
      E := InsertDccRef(Text, DccRefXml(Info, NewInclude));
      Text := E;
    end;
    PatchSaveText(Dproj, Text, Enc);
  end;
  Result := Format(SN_UNIT_RENAMED_FMT, [OldName, OldInclude, Info.UnitName, NewInclude,
    TPath.GetFileName(Dpr)]);
end;

function ProjectUnits(const AProject: string): TArray<TProjectUnit>;
var
  Dpr, Dproj, Enc, Text, Xml, E: string;
  U: TUsesClause;
  P: TProjectUnit;
  S, L: Integer;
begin
  Result := [];
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit;
  try
    Text := PatchLoadText(Dpr, Enc);
    U := FindUses(Text);
    if not U.Found then
      Exit;
    Xml := '';
    if TFile.Exists(Dproj) then
      Xml := PatchLoadText(Dproj, Enc);
    for E in U.Entries do
    begin
      P.Include := EntryInclude(E);
      if P.Include = '' then
        Continue; // library units (no `in`) are not project files
      P.UnitName := EntryUnitName(E);
      P.FormName := EntryFormName(E);
      P.InDproj := (Xml <> '') and FindDccRef(Xml, P.Include, S, L);
      Result := Result + [P];
    end;
  except
    Result := [];
  end;
end;

procedure AddUnitsView(const ADproj: string; AReturn: TJSONObject);
var
  Arr: TJSONArray;
  O: TJSONObject;
  P: TProjectUnit;
begin
  Arr := TJSONArray.Create;
  for P in ProjectUnits(ADproj) do
  begin
    O := TJSONObject.Create;
    O.AddPair('unit', P.UnitName);
    O.AddPair('file', P.Include);
    if P.FormName <> '' then
      O.AddPair('form', P.FormName);
    if not P.InDproj then
      O.AddPair('dproj', TJSONBool.Create(False));
    Arr.AddElement(O);
  end;
  AReturn.AddPair('units', Arr);
end;

function ProjectsUsingUnit(const APasPath: string): TArray<string>;
var
  Dir, Parent, D, F, Stem: string;
  Dirs: TArray<string>;
  P: TProjectUnit;
begin
  Result := [];
  Stem := TPath.GetFileNameWithoutExtension(APasPath);
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(APasPath));
  Parent := TPath.GetDirectoryName(Dir);
  Dirs := [Dir];
  if (Parent <> '') and (Parent <> Dir) then
    Dirs := Dirs + [Parent];
  for D in Dirs do
  begin
    if not TDirectory.Exists(D) then
      Continue;
    for F in TDirectory.GetFiles(D, '*.dpr') do
      for P in ProjectUnits(F) do
        if SameText(P.UnitName, Stem) and
          (NormPath(TPath.Combine(TPath.GetDirectoryName(F), P.Include)) = NormPath(APasPath)) then
        begin
          Result := Result + [F];
          Break;
        end;
  end;
end;

end.
