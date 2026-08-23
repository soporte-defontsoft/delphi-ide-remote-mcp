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
function ProjectUnits(const AProject: string): TArray<TProjectUnit>; overload;
{ ANeedDproj=False skips the .dproj read (InDproj is then True): for callers
  that only need the .dpr's list. }
function ProjectUnits(const AProject: string; ANeedDproj: Boolean): TArray<TProjectUnit>; overload;

{ Adds a "units" array to AReturn (for delphi_config view). }
procedure AddUnitsView(const ADproj: string; AReturn: TJSONObject);

{ Projects (.dproj paths) in ADir and its parent that list APasPath. For the
  file tools: delete/move a unit keeps the projects that use it consistent. }
function ProjectsUsingUnit(const APasPath: string): TArray<string>;

// The Pascal text with every comment (brace, paren-star, slash-slash) and
// compiler directive replaced by spaces - same length, same line breaks, so
// positions and line numbers survive. String literals are left intact. For
// scanners that must not read commented-out code (field 2026-08-23: a
// StyleLookup mentioned in a comment became a lint "finding").
function BlankComments(const S: string): string;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions,
  System.Generics.Collections, System.Character,
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
  else if SameText(TPath.GetPathRoot(Full), TPath.GetPathRoot(Base)) then
    Result := ExtractRelativePath(Base, Full) // ..\..\shared\X.pas, the IDE's form
  else
    Result := Full; // another drive: no relative form exists
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

{ The IDE's DesignClass for an ancestor: TFrame / TDataModule (unit-qualified
  accepted), a class declared in the same unit is followed up the chain, and
  a custom base living elsewhere is classified by its NAME SUFFIX only
  (TBaseFrame -> frame, TDMBase -> form: the form side is the safe default
  because a spurious CreateForm on a frame breaks the build, a missing
  DesignClass on a data module only changes the IDE's icon). }
function DesignClassOf(const ASrc, AAncestor: string): string;
var
  Name: string;
  M: TMatch;
  Hops: Integer;
begin
  Result := '';
  Name := AAncestor;
  Hops := 0;
  while (Name <> '') and (Hops < 8) do
  begin
    if Name.Contains('.') then
      Name := Name.Substring(Name.LastIndexOf('.') + 1);
    if SameText(Name, 'TFrame') or SameText(Name, 'TCustomFrame') then
      Exit('TFrame');
    if SameText(Name, 'TDataModule') then
      Exit('TDataModule');
    if SameText(Name, 'TForm') or SameText(Name, 'TCustomForm') or SameText(Name, 'TForm3D') then
      Exit('');
    // declared in this unit? follow its ancestor
    M := TRegEx.Match(ASrc, '\b' + TRegEx.Escape(Name) + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
    if not M.Success then
      Break;
    Name := M.Groups[1].Value;
    Inc(Hops);
  end;
  if Name.EndsWith('Frame', True) then
    Result := 'TFrame'
  else if Name.EndsWith('DataModule', True) then
    Result := 'TDataModule';
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
    M := TRegEx.Match(Src, '\b' + TRegEx.Escape(DClass) + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
  end
  else
  begin
    // binary designer: the first designer class in the .pas, then its variable
    M := TRegEx.Match(Src, '\b(T\w+)\s*=\s*class\s*\(\s*((?:\w+\.)*T(?:Form|DataModule|Frame)\w*)', [roIgnoreCase]);
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
  AInfo.DesignClass := DesignClassOf(Src, AInfo.Ancestor);
end;

{ ---- .dpr uses clause ---- }

type
  TUsesClause = record
    Found: Boolean;
    StartPos: Integer;  // index (1-based) of the 'u' of 'uses'
    EndPos: Integer;    // index of the closing ';'
    Entries: TArray<string>; // raw entry texts, trimmed
  end;

// Length of the comment or directive starting at S[I] (0 when none): the
// slash-slash line comment, the paren-star block and the brace block
// (compiler directives included - the compiler treats them as comments
// inside a uses clause).
function CommentLen(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if I > Length(S) then
    Exit;
  if (S[I] = '/') and (I < Length(S)) and (S[I + 1] = '/') then
  begin
    J := I;
    while (J <= Length(S)) and (S[J] <> #10) and (S[J] <> #13) do
      Inc(J);
    Exit(J - I);
  end;
  if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = '*') then
  begin
    J := Pos('*)', S, I + 2);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 2 - I);
  end;
  if S[I] = '{' then
  begin
    J := Pos('}', S, I + 1);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 1 - I);
  end;
end;

{ Length of the quoted string starting at S[I] ('' escapes), 0 when none. }
function QuoteLen(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if (I > Length(S)) or (S[I] <> '''') then
    Exit;
  J := I + 1;
  while J <= Length(S) do
  begin
    if S[J] = '''' then
    begin
      if (J < Length(S)) and (S[J + 1] = '''') then
        Inc(J, 2)
      else
        Exit(J + 1 - I);
    end
    else
      Inc(J);
  end;
  Result := Length(S) - I + 1;
end;

function BlankComments(const S: string): string;
var
  I, N, K: Integer;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create(Length(S));
  try
    I := 1;
    while I <= Length(S) do
    begin
      N := QuoteLen(S, I);
      if N > 0 then
      begin
        Sb.Append(S, I - 1, N);
        Inc(I, N);
        Continue;
      end;
      N := CommentLen(S, I);
      if N > 0 then
      begin
        for K := I to I + N - 1 do
          if CharInSet(S[K], [#10, #13]) then
            Sb.Append(S[K])
          else
            Sb.Append(' ');
        Inc(I, N);
        Continue;
      end;
      Sb.Append(S[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ Splits the clause body on top-level commas (outside quotes, comments and
  directives; those stay glued to the entry they precede or follow). }
function SplitEntries(const Body: string): TArray<string>;
var
  I, N: Integer;
  Cur: string;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    Cur := '';
    I := 1;
    while I <= Length(Body) do
    begin
      N := CommentLen(Body, I);
      if N = 0 then
        N := QuoteLen(Body, I);
      if N > 0 then
      begin
        Cur := Cur + Copy(Body, I, N);
        Inc(I, N);
        Continue;
      end;
      if Body[I] = ',' then
      begin
        if Cur.Trim <> '' then
          L.Add(Cur.Trim);
        Cur := '';
      end
      else
        Cur := Cur + Body[I];
      Inc(I);
    end;
    if Cur.Trim <> '' then
      L.Add(Cur.Trim);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_');
end;

{ The program's uses clause: the `uses` keyword after `program X;` (never
  one inside a comment), closed by the first `;` outside quotes/comments. }
function FindUses(const Dpr: string): TUsesClause;
var
  I, N, Start: Integer;
  M: TMatch;
  SeenProgram: Boolean;
begin
  Result := Default(TUsesClause);
  M := TRegEx.Match(Dpr, '^\s*program\b', [roIgnoreCase, roMultiline]);
  I := 1;
  if M.Success then
    I := M.Index + M.Length;
  SeenProgram := not M.Success;
  Start := 0;
  while I <= Length(Dpr) do
  begin
    N := CommentLen(Dpr, I);
    if N = 0 then
      N := QuoteLen(Dpr, I);
    if N > 0 then
    begin
      Inc(I, N);
      Continue;
    end;
    if not SeenProgram then
    begin
      if Dpr[I] = ';' then
        SeenProgram := True; // end of `program X;`
      Inc(I);
      Continue;
    end;
    if Start = 0 then
    begin
      if ((I = 1) or not IsIdentChar(Dpr[I - 1])) and (I + 3 <= Length(Dpr)) and
         SameText(Copy(Dpr, I, 4), 'uses') and
         ((I + 4 > Length(Dpr)) or not IsIdentChar(Dpr[I + 4])) then
      begin
        Start := I;
        Inc(I, 4);
        Continue;
      end;
      if IsIdentChar(Dpr[I]) then
      begin
        // another token before `uses` (const, type, begin...): no clause
        while (I <= Length(Dpr)) and IsIdentChar(Dpr[I]) do
          Inc(I);
        if not SameText(Copy(Dpr, I - 4, 4), 'uses') then
          Exit;
        Start := I - 4;
      end
      else
        Inc(I);
      Continue;
    end;
    if Dpr[I] = ';' then
    begin
      Result.StartPos := Start;
      Result.EndPos := I;
      Result.Found := True;
      Result.Entries := SplitEntries(Copy(Dpr, Start + 4, I - (Start + 4)));
      Exit;
    end;
    Inc(I);
  end;
end;

// Leading comments/directives of an entry (kept when the entry is dropped so
// a conditional directive around it stays balanced) and the bare entry text.
procedure SplitEntryPrefix(const Entry: string; out APrefix, ACore: string);
var
  I, N: Integer;
begin
  I := 1;
  while I <= Length(Entry) do
  begin
    N := CommentLen(Entry, I);
    if N > 0 then
      Inc(I, N)
    else if Entry[I].IsWhiteSpace then
      Inc(I)
    else
      Break;
  end;
  APrefix := Copy(Entry, 1, I - 1).Trim;
  ACore := Copy(Entry, I, MaxInt).Trim;
end;

function EntryUnitName(const Entry: string): string;
var
  M: TMatch;
  Prefix, Core: string;
begin
  SplitEntryPrefix(Entry, Prefix, Core);
  M := TRegEx.Match(Core, '^([A-Za-z_][\w.]*)');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := Core;
end;

function EntryInclude(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '^\s*[A-Za-z_][\w.]*\s+in\s*''([^'']+)''', [roIgnoreCase]);
  if not M.Success then
  begin
    var Prefix, Core: string;
    SplitEntryPrefix(Entry, Prefix, Core);
    M := TRegEx.Match(Core, '^[A-Za-z_][\w.]*\s+in\s*''([^'']+)''', [roIgnoreCase]);
  end;
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

function EntryFormName(const Entry: string): string;
var
  M: TMatch;
  Prefix, Core: string;
begin
  SplitEntryPrefix(Entry, Prefix, Core);
  M := TRegEx.Match(Core, '''\s*\{\s*(\w+)');
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
  Entries go one per line with the indent the clause already used (the IDE's
  two spaces when it had none). Measured 2026-08-23: the indent was applied
  TWICE (join + a second replace) and every add/remove-unit re-indented the
  whole clause to four spaces - a 40-line cosmetic diff on a real project. }
function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
var
  Body, NL, Indent, Clause, E: string;
  M: TMatch;
  Parts: TArray<string>;
  I: Integer;
begin
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  // the indent of the first entry line of the existing clause
  Clause := Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1);
  M := TRegEx.Match(Clause, '\n([ \t]+)\S');
  if M.Success then
    Indent := M.Groups[1].Value
  else
    Indent := '  ';
  SetLength(Parts, Length(AEntries));
  for I := 0 to High(AEntries) do
  begin
    // a multi-line entry (directives around it) keeps its lines indented too
    E := AEntries[I].Replace(#13#10, #10).Replace(#10, NL + Indent);
    Parts[I] := Indent + E;
  end;
  Body := 'uses' + NL + string.Join(',' + NL, Parts) + ';';
  Body := TRegEx.Replace(Body, '[ \t]+(\r?\n)', '$1'); // no trailing blanks
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
    // right before Application.Run, like the IDE: a CreateForm placed after
    // the last one could land inside that one's conditional block
    if RunAt <> -1 then
    begin
      Indent := Copy(Lines[RunAt], 1, Length(Lines[RunAt]) - Length(Lines[RunAt].TrimLeft));
      L.Insert(RunAt, Indent + CreateFormLine(AInfo));
    end
    else
    begin
      Indent := Copy(Lines[Last], 1, Length(Lines[Last]) - Length(Lines[Last].TrimLeft));
      L.Insert(Last + 1, Indent + CreateFormLine(AInfo));
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
  if AClassName <> '' then
    Pat := '^\s*Application\.CreateForm\s*\(\s*' + TRegEx.Escape(AClassName) + '\s*,'
  else if AFormName <> '' then
    Pat := '^\s*Application\.CreateForm\s*\(\s*\w+\s*,\s*' + TRegEx.Escape(AFormName) + '\s*\)'
  else
    Exit;
  L := TStringList.Create;
  try
    for I := 0 to High(Lines) do
      if TRegEx.IsMatch(Lines[I], Pat, [roIgnoreCase]) then
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
    begin
      Present := True;
      if EntryInclude(E) <> '' then
        Include := EntryInclude(E); // the .dproj element follows the .dpr entry
    end;
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
  Carry, Prefix, Core: string;
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
    Carry := '';
    for E in U.Entries do
      if not SameText(EntryUnitName(E), UnitName) then
      begin
        if Carry <> '' then
          Entries := Entries + [Carry + #10 + E]
        else
          Entries := Entries + [E];
        Carry := '';
      end
      else
      begin
        SplitEntryPrefix(E, Prefix, Core);
        Carry := Prefix; // its directive/comment stays, glued to the next entry
      end;
    if (Carry <> '') and (Length(Entries) > 0) then
      Entries[High(Entries)] := Entries[High(Entries)] + #10 + Carry;
    Text := ReplaceUses(Text, U, Entries);
    // the .pas gone: only the {Form} variable is known, match on it
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
  Dpr, Dproj, Enc, Text, OldName, OldInclude, Entry, NewInclude, Prefix, Core: string;
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
    begin
      SplitEntryPrefix(Entries[I], Prefix, Core);
      Entries[I] := BuildEntry(Info, NewInclude);
      if Prefix <> '' then
        Entries[I] := Prefix + #10 + Entries[I];
    end;
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

function ProjectUnits(const AProject: string; ANeedDproj: Boolean): TArray<TProjectUnit>;
var
  Dpr, Dproj, Enc, Text, E: string;
  U: TUsesClause;
  P: TProjectUnit;
  Includes: TDictionary<string, Boolean>;
  M: TMatch;
begin
  Result := [];
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit;
  Includes := TDictionary<string, Boolean>.Create;
  try
    try
      Text := PatchLoadText(Dpr, Enc);
      U := FindUses(Text);
      if not U.Found then
        Exit;
      if ANeedDproj and TFile.Exists(Dproj) then
        // one sweep of the .dproj, then O(1) per entry
        for M in TRegEx.Matches(PatchLoadText(Dproj, Enc), '<DCCReference\s+Include="([^"]*)"', [roIgnoreCase]) do
          Includes.AddOrSetValue(M.Groups[1].Value.Replace('/', '\').ToLower, True);
      for E in U.Entries do
      begin
        P.Include := EntryInclude(E);
        if P.Include = '' then
          Continue; // library units (no `in`) are not project files
        P.UnitName := EntryUnitName(E);
        P.FormName := EntryFormName(E);
        P.InDproj := (not ANeedDproj) or Includes.ContainsKey(P.Include.Replace('/', '\').ToLower);
        Result := Result + [P];
      end;
    except
      Result := [];
    end;
  finally
    Includes.Free;
  end;
end;

function ProjectUnits(const AProject: string): TArray<TProjectUnit>;
begin
  Result := ProjectUnits(AProject, True);
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
      for P in ProjectUnits(F, False) do // the .dpr decides; no .dproj read
        if SameText(P.UnitName, Stem) and
          (NormPath(TPath.Combine(TPath.GetDirectoryName(F), P.Include)) = NormPath(APasPath)) then
        begin
          Result := Result + [F];
          Break;
        end;
  end;
end;

end.
