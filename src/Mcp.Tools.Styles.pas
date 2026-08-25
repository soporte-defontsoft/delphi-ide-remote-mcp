unit Mcp.Tools.Styles;

{ delphi_styles: FMX styles as a first-class thing for a remote agent - the
  text .style files a project keeps as source of truth (Bitmap Style Designer
  export), edited BY STYLE NAME, checked against the .fmx files that use
  them, and turned into the binaries the app embeds. Engine in Lsp.Styles. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiStylesParams = class
  private
    FCommand: string;
    FPath: string;
    FProject: string;
    FStyle: string;
    FChild: string;
    FProp: string;
    FValue: string;
    FName: string;
    FFilter: string;
    FDelete: Boolean;
  public
    [SchemaDescription('view (styles of a .style file: StyleName, class, lines) | get (one style, whole text) | set (one property of a style or of one of its parts) | clone (a new style copied from an existing one) | delete (remove a whole style by StyleName; the __delphi-patch copy is the way back) | lint (duplicated StyleNames, StyleLookup values of the project''s .fmx that no style defines, design tokens missing in a theme, .rc entries without file) | build (every text .style of the folder -> .bin.style, then the .rc -> .res with brcc32)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_STYLES_PATH)]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('lint: the project .dproj (or a folder) whose .fmx/.pas files are scanned for StyleLookup. Default: the parent folder of the styles folder')]
    property Project: string read FProject write FProject;
    [SchemaDescription('get/set/clone: the StyleName of the style (top-level object of the container), e.g. buttonstyle or cardstyle')]
    property Style: string read FStyle write FStyle;
    [SchemaDescription('set optional: a part inside the style, by StyleName or object name, as a path: background or background/text')]
    property Child: string read FChild write FChild;
    [SchemaDescription('set: the property, as written in the file: Fill.Color, Size.Height, Visible, TextSettings.Font.Size...')]
    property Prop: string read FProp write FProp;
    [SchemaDescription('set: the value EXACTLY as it appears in a .style file: xFFF6ECDB (colors AARRGGBB), 44.000000000000000000 (floats), True/False, ''text'' (strings quoted), Center (enums)')]
    property Value: string read FValue write FValue;
    [SchemaDescription('clone: the StyleName of the new style')]
    property Name: string read FName write FName;
    [SchemaDescription('view optional: substring the StyleName must contain')]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription('set: true = remove the property instead of setting it')]
    property Delete: Boolean read FDelete write FDelete;
  end;

  TDelphiStylesTool = class(TMCPToolBase<TDelphiStylesParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiStylesParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.IniFiles,
  System.Generics.Collections,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.BuildRunner,
  Lsp.Patch,
  Lsp.ProjectUnits,
  Lsp.Styles;

constructor TDelphiStylesTool.Create;
begin
  inherited;
  FName := 'delphi_styles';
  FDescription := SD_STYLES;
end;

function StylesDirOf(const APath: string): string;
begin
  if TDirectory.Exists(APath) then
    Result := TPath.GetFullPath(APath)
  else
    Result := TPath.GetDirectoryName(TPath.GetFullPath(APath));
end;

{ ---- view / get ---- }

function ViewStyles(const APath, AFilter: string): string;
var
  Doc: TStyleDoc;
  O: TStyleObj;
  Ret: TJSONObject;
  Arr: TJSONArray;
  E: TJSONObject;
  N: Integer;
begin
  Doc := TStyleDoc.Create(APath);
  try
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('file', MaskDriveText('delphi_styles', Doc.Path));
      Ret.AddPair('container', Doc.Root.ClassName_);
      Arr := TJSONArray.Create;
      N := 0;
      for O in Doc.Styles do
      begin
        if (AFilter <> '') and not O.StyleName.ToLower.Contains(AFilter.ToLower) then
          Continue;
        E := TJSONObject.Create;
        E.AddPair('style', O.StyleName);
        E.AddPair('class', O.ClassName_);
        E.AddPair('lines', Format('%d-%d', [O.StartLine, O.EndLine]));
        E.AddPair('parts', TJSONNumber.Create(O.Children.Count));
        Arr.AddElement(E);
        Inc(N);
      end;
      Ret.AddPair('count', TJSONNumber.Create(N));
      Ret.AddPair('styles', Arr);
      Ret.AddPair('note', SN_STYLES_VIEW_NOTE);
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function GetStyle(const APath, AStyle, AChild: string): string;
var
  Doc: TStyleDoc;
  O: TStyleObj;
  Err: string;
begin
  Doc := TStyleDoc.Create(APath);
  try
    O := Doc.Resolve(AStyle, AChild, Err);
    if O = nil then
      Exit('RECHAZADO: ' + Err);
    Result := Format('%s (%s) lineas %d-%d de %s:'#10'%s',
      [IfThen(O.StyleName <> '', O.StyleName, O.ObjName), O.ClassName_, O.StartLine,
       O.EndLine, TPath.GetFileName(Doc.Path), Doc.BlockText(O)]);
  finally
    Doc.Free;
  end;
end;

{ ---- set / clone ---- }

function SetStyleProp(const APath, AStyle, AChild, AProp, AValue: string; ADelete: Boolean): string;
var
  Doc: TStyleDoc;
  O: TStyleObj;
  Err, Line: string;
  WasThere: Boolean;
begin
  if AProp.Trim = '' then
    Exit(SR_STYLES_NEED_PROP);
  if not TRegEx.IsMatch(AProp.Trim, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
    Exit(Format(SR_STYLES_PROP_CHARS_FMT, [AProp]));
  if (not ADelete) and (AValue.Trim = '') then
    Exit(SR_STYLES_NEED_VALUE);
  if AValue.Contains(#10) or AValue.Contains(#13) then
    Exit(SR_STYLES_VALUE_LINE);
  Doc := TStyleDoc.Create(APath);
  try
    O := Doc.Resolve(AStyle, AChild, Err);
    if O = nil then
      Exit('RECHAZADO: ' + Err);
    if ADelete then
    begin
      if not Doc.DeleteProp(O, AProp.Trim) then
        Exit(Format(SN_STYLES_PROP_ABSENT_FMT, [AProp, AStyle, AChild]));
      Doc.Save;
      Exit(Format(SN_STYLES_PROP_DELETED_FMT, [AProp, AStyle, IfThen(AChild <> '', '/' + AChild, ''),
        TPath.GetFileName(Doc.Path)]));
    end;
    Line := Doc.SetProp(O, AProp.Trim, AValue.Trim, WasThere);
    Doc.Save;
    Result := Format(SN_STYLES_PROP_SET_FMT, [IfThen(WasThere, 'CAMBIADA', 'ANADIDA'), Line.Trim,
      AStyle, IfThen(AChild <> '', '/' + AChild, ''), TPath.GetFileName(Doc.Path)]);
  finally
    Doc.Free;
  end;
end;

function CloneStyle(const APath, AStyle, ANew: string): string;
var
  Doc: TStyleDoc;
  Src: TStyleObj;
begin
  if ANew.Trim = '' then
    Exit(SR_STYLES_NEED_NAME);
  if not TRegEx.IsMatch(ANew.Trim, '^[A-Za-z_][\w.\-]*$') then
    Exit(Format(SR_STYLES_NAME_CHARS_FMT, [ANew]));
  Doc := TStyleDoc.Create(APath);
  try
    Src := Doc.FindStyle(AStyle);
    if Src = nil then
      Exit(Format('RECHAZADO: no hay ningun estilo ''%s'' en %s (command=view los lista).',
        [AStyle, TPath.GetFileName(Doc.Path)]));
    if Doc.FindStyle(ANew.Trim) <> nil then
      Exit(Format(SR_STYLES_NAME_TAKEN_FMT, [ANew]));
    Doc.CloneStyle(Src, ANew.Trim);
    Doc.Save;
    Src := Doc.FindStyle(ANew.Trim);
    Result := Format(SN_STYLES_CLONED_FMT, [ANew.Trim, AStyle, Src.StartLine, Src.EndLine,
      TPath.GetFileName(Doc.Path)]);
  finally
    Doc.Free;
  end;
end;

{ ---- delete ---- }

{ A whole style out of the file. The copy PatchSaveText leaves in
  __delphi-patch is the way back (delphi_move it over the file). Field
  2026-08-23: cleaning a test clone took delphi_delete of the .style plus a
  delphi_move of the backup - two calls and a whole-file swap for one block. }
function DeleteStyle(const APath, AStyle: string): string;
var
  Doc: TStyleDoc;
  Src: TStyleObj;
  First, Last, N: Integer;
begin
  Doc := TStyleDoc.Create(APath);
  try
    Src := Doc.FindStyle(AStyle);
    if Src = nil then
      Exit(Format('RECHAZADO: no hay ningun estilo ''%s'' en %s (command=view los lista).',
        [AStyle, TPath.GetFileName(Doc.Path)]));
    First := Src.StartLine;
    Last := Src.EndLine;
    N := Length(Doc.Styles);
    Doc.DeleteStyle(Src);
    Doc.Save;
    Result := Format(SN_STYLES_DELETED_FMT, [AStyle, First, Last,
      TPath.GetFileName(Doc.Path), N - 1]);
  finally
    Doc.Free;
  end;
end;

{ ---- lint ---- }

function LintStyles(const APath, AProject: string): string;
var
  Dir, ProjDir, F, Enc, Text, N, Sect, Key: string;
  Files: TArray<string>;
  Doc: TStyleDoc;
  O: TStyleObj;
  Names, Defaults: TDictionary<string, string>;
  Seen: TDictionary<string, Integer>;
  Ret, Issue: TJSONObject;
  Dups, Missing, Tokens, Rc: TJSONArray;
  M: TMatch;
  Lines: TArray<string>;
  I: Integer;
  Ini: TMemIniFile;
  Sections, Keys, AllKeys: TStringList;
  Standard, Used: Integer;
  D: string;
begin
  Dir := StylesDirOf(APath);
  Files := TextStylesIn(Dir);
  if TFile.Exists(APath) and not IsBinaryStyle(APath) and (Length(Files) = 0) then
    Files := [TPath.GetFullPath(APath)];
  if Length(Files) = 0 then
    Exit(Format(SR_STYLES_NO_TEXT_FMT, [Dir]));
  if AProject.Trim <> '' then
  begin
    if TDirectory.Exists(AProject) then
      ProjDir := TPath.GetFullPath(AProject)
    else
      ProjDir := TPath.GetDirectoryName(TPath.GetFullPath(AProject));
  end
  else
    ProjDir := TPath.GetDirectoryName(Dir); // the styles folder's parent
  Names := TDictionary<string, string>.Create;
  Defaults := TDictionary<string, string>.Create;
  Seen := TDictionary<string, Integer>.Create;
  Ret := TJSONObject.Create;
  Dups := TJSONArray.Create;
  Missing := TJSONArray.Create;
  Tokens := TJSONArray.Create;
  Rc := TJSONArray.Create;
  try
    // 1) style names per file + duplicates
    for F in Files do
    begin
      Doc := TStyleDoc.Create(F);
      try
        Seen.Clear;
        for O in Doc.Styles do
        begin
          if O.StyleName = '' then
            Continue;
          N := O.StyleName.ToLower;
          if Seen.ContainsKey(N) then
          begin
            Issue := TJSONObject.Create;
            Issue.AddPair('file', TPath.GetFileName(F));
            Issue.AddPair('style', O.StyleName);
            Issue.AddPair('lines', Format('%d y %d', [Seen[N], O.StartLine]));
            Dups.AddElement(Issue);
          end
          else
            Seen.Add(N, O.StartLine);
          Names.AddOrSetValue(N, TPath.GetFileName(F));
        end;
      finally
        Doc.Free;
      end;
    end;
    // 2) StyleLookup used by the project against names + platform defaults
    for D in PlatformDefaultStyleNames do
      Defaults.AddOrSetValue(D, '');
    Standard := 0;
    Used := 0;
    if TDirectory.Exists(ProjDir) then
      for F in TDirectory.GetFiles(ProjDir, '*.*', TSearchOption.soAllDirectories) do
      begin
        if not (F.EndsWith('.fmx', True) or F.EndsWith('.pas', True)) then
          Continue;
        if F.ToLower.Contains('\__delphi-patch\') or F.ToLower.Contains('\__history\') then
          Continue;
        if ReadPathDenied(F) <> '' then
          Continue;
        Text := TEncoding.UTF8.GetString(TFile.ReadAllBytes(F)); // lookups are ASCII
        if F.EndsWith('.pas', True) then
          Text := BlankComments(Text); // a lookup in a comment is not a lookup
        Lines := Text.Replace(#13#10, #10).Split([#10]);
        for I := 0 to High(Lines) do
        begin
          M := TRegEx.Match(Lines[I], 'StyleLookup\s*(?:=|:=)\s*''([^'']+)''', [roIgnoreCase]);
          if not M.Success then
            Continue;
          Inc(Used);
          N := M.Groups[1].Value.ToLower;
          if Names.ContainsKey(N) then
            Continue;
          if Defaults.ContainsKey(N) then
          begin
            Inc(Standard);
            Continue;
          end;
          Issue := TJSONObject.Create;
          Issue.AddPair('lookup', M.Groups[1].Value);
          Issue.AddPair('file', MaskDriveText('delphi_styles', F));
          Issue.AddPair('line', TJSONNumber.Create(I + 1));
          Missing.AddElement(Issue);
        end;
      end;
    // 3) design tokens: every key must exist in every theme section
    for F in TDirectory.GetFiles(Dir, '*.ini') do
    begin
      if F.ToLower.Contains('rules') or not F.ToLower.Contains('token') then
        Continue;
      Ini := TMemIniFile.Create(F, TEncoding.UTF8);
      Sections := TStringList.Create;
      Keys := TStringList.Create;
      AllKeys := TStringList.Create;
      try
        AllKeys.Sorted := True;
        AllKeys.Duplicates := dupIgnore;
        Ini.ReadSections(Sections);
        for Sect in Sections do
        begin
          Ini.ReadSection(Sect, Keys);
          for Key in Keys do
            AllKeys.Add(Key);
        end;
        for Sect in Sections do
          for Key in AllKeys do
            if not Ini.ValueExists(Sect, Key) then
            begin
              Issue := TJSONObject.Create;
              Issue.AddPair('file', TPath.GetFileName(F));
              Issue.AddPair('theme', Sect);
              Issue.AddPair('token', Key);
              Tokens.AddElement(Issue);
            end;
      finally
        AllKeys.Free;
        Keys.Free;
        Sections.Free;
        Ini.Free;
      end;
    end;
    // 4) .rc entries pointing at files that do not exist
    for F in TDirectory.GetFiles(Dir, '*.rc') do
    begin
      Text := PatchLoadText(F, Enc);
      for M in TRegEx.Matches(Text, '^\s*(\w+)\s+RCDATA\s+"([^"]+)"', [roIgnoreCase, roMultiline]) do
        if not TFile.Exists(TPath.Combine(Dir, M.Groups[2].Value)) then
        begin
          Issue := TJSONObject.Create;
          Issue.AddPair('rc', TPath.GetFileName(F));
          Issue.AddPair('resource', M.Groups[1].Value);
          Issue.AddPair('missing', M.Groups[2].Value);
          Rc.AddElement(Issue);
        end;
    end;
    Ret.AddPair('stylesDir', MaskDriveText('delphi_styles', Dir));
    Ret.AddPair('projectDir', MaskDriveText('delphi_styles', ProjDir));
    Ret.AddPair('styleFiles', TJSONNumber.Create(Length(Files)));
    Ret.AddPair('styleNames', TJSONNumber.Create(Names.Count));
    Ret.AddPair('lookupsUsed', TJSONNumber.Create(Used));
    Ret.AddPair('lookupsStandard', TJSONNumber.Create(Standard));
    Ret.AddPair('duplicatedStyleNames', Dups);
    Ret.AddPair('lookupsWithoutStyle', Missing);
    Ret.AddPair('tokensMissing', Tokens);
    Ret.AddPair('rcMissingFiles', Rc);
    Ret.AddPair('ok', TJSONBool.Create((Dups.Count = 0) and (Missing.Count = 0) and
      (Tokens.Count = 0) and (Rc.Count = 0)));
    if Length(PlatformDefaultStyleNames) = 0 then
      Ret.AddPair('note', SN_STYLES_NO_DEFAULTS)
    else
      Ret.AddPair('note', SN_STYLES_LINT_NOTE);
    Result := Ret.ToJSON;
  finally
    Ret.Free; // owns Dups/Missing/Tokens/Rc once added
    Names.Free;
    Defaults.Free;
    Seen.Free;
  end;
end;

{ ---- build ---- }

function BuildStyles(const APath: string): string;
var
  Dir, Exe, F, Bin, Out, Rc, Res, Brcc: string;
  Files: TArray<string>;
  Ret, E: TJSONObject;
  Arr: TJSONArray;
  Code: Cardinal;
  AllOk: Boolean;
  Info: TRadStudioInfo;
begin
  Dir := StylesDirOf(APath);
  Exe := StyleConverterExe;
  if Exe = '' then
    Exit(SR_STYLES_NO_CONVERTER);
  Files := TextStylesIn(Dir);
  if TFile.Exists(APath) and not IsBinaryStyle(APath) then
    Files := [TPath.GetFullPath(APath)];
  if Length(Files) = 0 then
    Exit(Format(SR_STYLES_NO_TEXT_FMT, [Dir]));
  Ret := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    AllOk := True;
    for F in Files do
    begin
      Bin := TPath.Combine(Dir, TPath.GetFileNameWithoutExtension(F) + '.bin.style');
      Out := RunCapturedIn('"' + Exe + '" tobin "' + F + '" "' + Bin + '"', Dir, 120000, Code);
      E := TJSONObject.Create;
      E.AddPair('source', TPath.GetFileName(F));
      E.AddPair('binary', TPath.GetFileName(Bin));
      E.AddPair('ok', TJSONBool.Create(Code = 0));
      if Code = 0 then
        E.AddPair('bytes', TJSONNumber.Create(TFile.GetSize(Bin)))
      else
      begin
        E.AddPair('error', Out.Trim);
        AllOk := False;
      end;
      Arr.AddElement(E);
    end;
    Ret.AddPair('stylesDir', MaskDriveText('delphi_styles', Dir));
    Ret.AddPair('converted', Arr);
    // the .rc -> .res, with the product's resource compiler
    for Rc in TDirectory.GetFiles(Dir, '*.rc') do
    begin
      Info := DiscoverRadStudio;
      Brcc := TPath.Combine(Info.RootDir, 'bin\brcc32.exe');
      if not TFile.Exists(Brcc) then
      begin
        Ret.AddPair('rc', TPath.GetFileName(Rc));
        Ret.AddPair('rcError', 'brcc32.exe no encontrado en ' + Brcc);
        AllOk := False;
        Break;
      end;
      Res := TPath.ChangeExtension(Rc, '.res');
      Out := RunCapturedIn('"' + Brcc + '" -fo"' + Res + '" "' + Rc + '"', Dir, 120000, Code);
      Ret.AddPair('rc', TPath.GetFileName(Rc));
      Ret.AddPair('res', TPath.GetFileName(Res));
      Ret.AddPair('rcOk', TJSONBool.Create((Code = 0) and TFile.Exists(Res)));
      if Code = 0 then
        Ret.AddPair('resBytes', TJSONNumber.Create(TFile.GetSize(Res)))
      else
      begin
        Ret.AddPair('rcError', Out.Trim);
        AllOk := False;
      end;
      Break; // one manifest per styles folder
    end;
    Ret.AddPair('ok', TJSONBool.Create(AllOk));
    Ret.AddPair('note', SN_STYLES_BUILD_NOTE);
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ ---- dispatcher ---- }

function TDelphiStylesTool.ExecuteWithParams(const Params: TDelphiStylesParams): string;
var
  Cmd, Denied: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'view';
  if Params.Path.Trim = '' then
    Exit(SR_STYLES_NEED_PATH);
  if MatchText(Cmd, ['set', 'clone', 'delete', 'build']) then
    Denied := PathDenied(Params.Path)
  else
    Denied := ReadPathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit(Format(SR_STYLES_MISSING_FMT, [Params.Path]));
  if MatchText(Cmd, ['view', 'get', 'set', 'clone', 'delete']) then
  begin
    if TDirectory.Exists(Params.Path) then
      Exit(SR_STYLES_NEED_FILE);
    if IsBinaryStyle(Params.Path) then
      Exit(Format(SR_STYLES_BINARY_FMT, [TPath.GetFileName(Params.Path)]));
  end;
  if MatchText(Cmd, ['get', 'set', 'clone', 'delete']) and (Params.Style.Trim = '') then
    Exit(SR_STYLES_NEED_STYLE);
  try
    if Cmd = 'view' then
      Result := ViewStyles(Params.Path, Params.Filter.Trim)
    else if Cmd = 'get' then
      Result := GetStyle(Params.Path, Params.Style.Trim, Params.Child.Trim)
    else if Cmd = 'set' then
      Result := SetStyleProp(Params.Path, Params.Style.Trim, Params.Child.Trim,
        Params.Prop, Params.Value, Params.Delete)
    else if Cmd = 'clone' then
      Result := CloneStyle(Params.Path, Params.Style.Trim, Params.Name)
    else if Cmd = 'delete' then
      Result := DeleteStyle(Params.Path, Params.Style.Trim)
    else if Cmd = 'lint' then
      Result := LintStyles(Params.Path, Params.Project.Trim)
    else if Cmd = 'build' then
      Result := BuildStyles(Params.Path)
    else
      Result := 'error: command debe ser view | get | set | clone | delete | lint | build';
  except
    on E: Exception do
      Result := 'ERROR ' + E.ClassName + ': ' + E.Message;
  end;
  Result := MaskDriveText('delphi_styles', Result);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_styles',
    function: IMCPTool begin Result := TDelphiStylesTool.Create; end);

end.
