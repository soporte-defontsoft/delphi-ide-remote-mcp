unit Lsp.Styles;

// FMX style files (.style) for delphi_styles: the TEXT form ("object
// TStyleContainer" ... ) that the Bitmap Style Designer exports and a style
// pipeline keeps as source of truth.
//
// - A tolerant parser of the DFM-like text: objects, their StyleName, line
// ranges and nesting (collections <item...end> and binary {...} blocks are
// skipped as opaque).
// - Operations by StyleName, never by line: view, get, set (a property of a
// style or of one of its parts), clone (a new style from an existing one).
// - lint: duplicated StyleNames; StyleLookup values used by the project's
// .fmx files that no project style (nor the platform default style)
// defines; design tokens missing in one theme.
// - build: text -> binary (.bin.style) through the DelphiStyleConvert helper
// shipped next to the server, then the .rc -> .res with brcc32.
//
// Binary styles (FMX_STYLE signature / $FF) are never edited: they are the
// product of build, and a text<->binary round trip is what build is for.
// Edits go through Lsp.Patch (encoding kept, __delphi-patch copy).

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections;

type
  TStyleObj = class
    ClassName_: string;   // TLayout, TRectangle...
    ObjName: string;      // the name before ':' when present
    StyleName: string;    // '' when the object has none
    StartLine: Integer;   // 1-based, the 'object' line
    EndLine: Integer;     // 1-based, the matching 'end'
    Depth: Integer;       // 0 = TStyleContainer, 1 = a style, 2+ = parts
    Parent: TStyleObj;
    Children: TObjectList<TStyleObj>;
    constructor Create;
    destructor Destroy; override;
    { The part named AName (StyleName or object name), direct child. }
    function Child(const AName: string): TStyleObj;
  end;

  TStyleDoc = class
  private
    FLines: TArray<string>;
    FRoot: TStyleObj;
    FEnc: string;
    FPath: string;
    FEol: string;
    procedure Parse;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
    property Root: TStyleObj read FRoot;
    property Lines: TArray<string> read FLines;
    property Path: string read FPath;
    { Top-level styles (children of the container) - the ones StyleLookup
      resolves. }
    function Styles: TArray<TStyleObj>;
    function FindStyle(const AStyleName: string): TStyleObj;
    { Resolves 'style' then an optional 'a/b/c' path of parts. }
    function Resolve(const AStyleName, AChildPath: string; out AErr: string): TStyleObj;
    function BlockText(AObj: TStyleObj): string;
    { Sets (or adds) a property line of AObj. AValue is written verbatim, as
      it would appear in the file. Returns the resulting line. }
    function SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string;
    { Removes a property line of AObj; False when absent. }
    function DeleteProp(AObj: TStyleObj; const AProp: string): Boolean;
    { Copies ASrc right after itself with the new StyleName. }
    procedure CloneStyle(ASrc: TStyleObj; const ANewName: string);
    procedure Save;
    { Re-parses after an edit (line numbers moved). }
    procedure Reload;
  end;

{ True for the binary forms (FMX_STYLE signature or the $FF wrapper). }
function IsBinaryStyle(const APath: string): Boolean;

{ The text .style files of a folder (binary ones and *.bin.style excluded). }
function TextStylesIn(const ADir: string): TArray<string>;

{ Path of the DelphiStyleConvert helper next to the server exe ('' if absent). }
function StyleConverterExe: string;

{ StyleNames of the Windows platform default style, extracted once through the
  helper and cached under LOCALAPPDATA. Empty when the helper is missing. }
function PlatformDefaultStyleNames: TArray<string>;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions,
  Lsp.Patch, Lsp.BuildRunner;

{ TStyleObj }

constructor TStyleObj.Create;
begin
  inherited;
  Children := TObjectList<TStyleObj>.Create(True);
end;

destructor TStyleObj.Destroy;
begin
  Children.Free;
  inherited;
end;

function TStyleObj.Child(const AName: string): TStyleObj;
var
  C: TStyleObj;
begin
  for C in Children do
    if SameText(C.StyleName, AName) or (SameText(C.ObjName, AName) and (C.ObjName <> '')) then
      Exit(C);
  Result := nil;
end;

{ TStyleDoc }

constructor TStyleDoc.Create(const APath: string);
begin
  inherited Create;
  FPath := TPath.GetFullPath(APath);
  Reload;
end;

destructor TStyleDoc.Destroy;
begin
  FRoot.Free;
  inherited;
end;

procedure TStyleDoc.Reload;
var
  Text: string;
begin
  FreeAndNil(FRoot);
  Text := PatchLoadText(FPath, FEnc);
  FEol := IfThen(Text.Contains(#13#10), #13#10, #10);
  FLines := Text.Replace(#13#10, #10).Split([#10]);
  Parse;
end;

procedure TStyleDoc.Parse;
var
  I, Depth, CollDepth: Integer;
  L, T: string;
  Cur, O: TStyleObj;
  InBinary: Boolean;
  M: TMatch;
begin
  FRoot := nil;
  Cur := nil;
  Depth := -1;
  CollDepth := 0;
  InBinary := False;
  for I := 0 to High(FLines) do
  begin
    L := FLines[I];
    T := L.Trim;
    if InBinary then
    begin
      if T.EndsWith('}') then
        InBinary := False;
      Continue;
    end;
    if T = '' then
      Continue;
    // a binary block (brace-delimited, may close on the same line)
    if T.EndsWith('= {') or (T.Contains('= {') and not T.EndsWith('}')) then
    begin
      InBinary := True;
      Continue;
    end;
    // collections: Prop = <  item ... end  ... >
    if T.EndsWith('= <') or (T = '<') then
    begin
      Inc(CollDepth);
      Continue;
    end;
    if CollDepth > 0 then
    begin
      if T.EndsWith('>') then
        Dec(CollDepth);
      Continue; // item / end / props inside a collection are opaque here
    end;
    M := TRegEx.Match(T, '^(object|inherited|inline)\s+(?:(\w+)\s*:\s*)?(\w+)', [roIgnoreCase]);
    if M.Success then
    begin
      O := TStyleObj.Create;
      O.ObjName := M.Groups[2].Value;
      O.ClassName_ := M.Groups[3].Value;
      O.StartLine := I + 1;
      O.EndLine := I + 1;
      O.Parent := Cur;
      Inc(Depth);
      O.Depth := Depth;
      if Cur = nil then
        FRoot := O
      else
        Cur.Children.Add(O);
      Cur := O;
      Continue;
    end;
    if SameText(T, 'end') then
    begin
      if Cur <> nil then
      begin
        Cur.EndLine := I + 1;
        Cur := Cur.Parent;
        Dec(Depth);
      end;
      Continue;
    end;
    if (Cur <> nil) and (Cur.StyleName = '') then
    begin
      M := TRegEx.Match(T, '^StyleName\s*=\s*''([^'']*)''', [roIgnoreCase]);
      if M.Success then
        Cur.StyleName := M.Groups[1].Value;
    end;
  end;
  if FRoot = nil then
  begin
    FRoot := TStyleObj.Create;
    FRoot.ClassName_ := '';
  end;
end;

function TStyleDoc.Styles: TArray<TStyleObj>;
begin
  Result := FRoot.Children.ToArray;
end;

function TStyleDoc.FindStyle(const AStyleName: string): TStyleObj;
var
  O: TStyleObj;
begin
  for O in FRoot.Children do
    if SameText(O.StyleName, AStyleName) then
      Exit(O);
  Result := nil;
end;

function TStyleDoc.Resolve(const AStyleName, AChildPath: string; out AErr: string): TStyleObj;
var
  Seg: string;
begin
  AErr := '';
  Result := FindStyle(AStyleName);
  if Result = nil then
  begin
    AErr := Format('No hay ningun estilo con StyleName ''%s'' en %s. Mira los ' +
      'nombres con command=view.', [AStyleName, TPath.GetFileName(FPath)]);
    Exit;
  end;
  for Seg in AChildPath.Replace('\', '/').Split(['/'], TStringSplitOptions.ExcludeEmpty) do
  begin
    Result := Result.Child(Seg.Trim);
    if Result = nil then
    begin
      AErr := Format('El estilo ''%s'' no tiene una parte ''%s'' (child=%s). ' +
        'command=get lo muestra entero.', [AStyleName, Seg.Trim, AChildPath]);
      Exit;
    end;
  end;
end;

function TStyleDoc.BlockText(AObj: TStyleObj): string;
var
  I: Integer;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    for I := AObj.StartLine - 1 to AObj.EndLine - 1 do
      L.Add(FLines[I]);
    Result := string.Join(#10, L.ToStringArray);
  finally
    L.Free;
  end;
end;

{ The line index (0-based) of AProp at AObj's own level, or -1. Own level =
  the lines after the header and before the first child object. }
function OwnPropLine(AObj: TStyleObj; const ALines: TArray<string>; const AProp: string): Integer;
var
  I, Stop: Integer;
  T: string;
begin
  Stop := AObj.EndLine - 1;
  if AObj.Children.Count > 0 then
    Stop := AObj.Children[0].StartLine - 1;
  for I := AObj.StartLine to Stop - 1 do
  begin
    T := ALines[I].TrimLeft;
    if T.StartsWith(AProp + ' =', True) or T.StartsWith(AProp + '=', True) then
      Exit(I);
  end;
  Result := -1;
end;

function TStyleDoc.SetProp(AObj: TStyleObj; const AProp, AValue: string; out AWasThere: Boolean): string;
var
  Idx, InsertAt, I: Integer;
  Indent: string;
  L: TList<string>;
begin
  Indent := StringOfChar(' ', (AObj.Depth + 1) * 2);
  Result := Indent + AProp + ' = ' + AValue;
  Idx := OwnPropLine(AObj, FLines, AProp);
  AWasThere := Idx >= 0;
  if AWasThere then
  begin
    // keep the file's own indentation of that line
    Indent := Copy(FLines[Idx], 1, Length(FLines[Idx]) - Length(FLines[Idx].TrimLeft));
    Result := Indent + AProp + ' = ' + AValue;
    FLines[Idx] := Result;
    Exit;
  end;
  // after the StyleName line when there is one, else right after the header
  InsertAt := AObj.StartLine; // 0-based index of the line AFTER the header
  for I := AObj.StartLine to AObj.EndLine - 2 do
    if FLines[I].TrimLeft.StartsWith('StyleName', True) then
    begin
      InsertAt := I + 1;
      Break;
    end;
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    L.Insert(InsertAt, Result);
    FLines := L.ToArray;
  finally
    L.Free;
  end;
end;

function TStyleDoc.DeleteProp(AObj: TStyleObj; const AProp: string): Boolean;
var
  Idx: Integer;
  L: TList<string>;
begin
  Idx := OwnPropLine(AObj, FLines, AProp);
  Result := Idx >= 0;
  if not Result then
    Exit;
  L := TList<string>.Create;
  try
    L.AddRange(FLines);
    L.Delete(Idx);
    FLines := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TStyleDoc.CloneStyle(ASrc: TStyleObj; const ANewName: string);
var
  Block: TList<string>;
  I: Integer;
  Renamed: Boolean;
  L: TList<string>;
  T: string;
begin
  Block := TList<string>.Create;
  L := TList<string>.Create;
  try
    Renamed := False;
    for I := ASrc.StartLine - 1 to ASrc.EndLine - 1 do
    begin
      T := FLines[I];
      if not Renamed and T.TrimLeft.StartsWith('StyleName', True) then
      begin
        T := Copy(T, 1, Length(T) - Length(T.TrimLeft)) + 'StyleName = ''' + ANewName + '''';
        Renamed := True;
      end;
      Block.Add(T);
    end;
    if not Renamed then
      Block.Insert(1, StringOfChar(' ', (ASrc.Depth + 1) * 2) + 'StyleName = ''' + ANewName + '''');
    L.AddRange(FLines);
    L.InsertRange(ASrc.EndLine, Block); // right after the source block
    FLines := L.ToArray;
  finally
    L.Free;
    Block.Free;
  end;
end;

procedure TStyleDoc.Save;
begin
  PatchSaveText(FPath, string.Join(FEol, FLines), FEnc);
  Reload;
end;

{ ---- files ---- }

function IsBinaryStyle(const APath: string): Boolean;
var
  B: TBytes;
  S: TFileStream;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, 9);
    if S.Size < 9 then
      Exit;
    S.ReadBuffer(B[0], 9);
  finally
    S.Free;
  end;
  Result := (B[0] = $FF) or (TEncoding.ANSI.GetString(B).StartsWith('FMX_STYLE'));
end;

function TextStylesIn(const ADir: string): TArray<string>;
var
  F: string;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    if TDirectory.Exists(ADir) then
      for F in TDirectory.GetFiles(ADir, '*.style') do
        if not F.ToLower.EndsWith('.bin.style') and not IsBinaryStyle(F) then
          L.Add(F);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function StyleConverterExe: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'DelphiStyleConvert.exe');
  if not TFile.Exists(Result) then
    Result := '';
end;

function PlatformDefaultStyleNames: TArray<string>;
var
  Cache, Exe, Enc: string;
  Code: Cardinal;
  M: TMatch;
  L: TList<string>;
begin
  Result := [];
  Cache := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'DelphiLspMcp\win10-default.style');
  if not TFile.Exists(Cache) then
  begin
    Exe := StyleConverterExe;
    if Exe = '' then
      Exit;
    TDirectory.CreateDirectory(TPath.GetDirectoryName(Cache));
    RunCaptured('"' + Exe + '" defaults "' + Cache + '"', 60000, Code);
    if (Code <> 0) or not TFile.Exists(Cache) then
      Exit;
  end;
  L := TList<string>.Create;
  try
    for M in TRegEx.Matches(PatchLoadText(Cache, Enc), 'StyleName\s*=\s*''([^'']+)''', [roIgnoreCase]) do
      L.Add(M.Groups[1].Value.ToLower);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
