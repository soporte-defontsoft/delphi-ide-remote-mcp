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
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

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
    [SchemaDescription(SP_STYLE_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_STYLES_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_STYLE_PROJECT)]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_STYLE_STYLE)]
    property Style: string read FStyle write FStyle;
    [SchemaDescription(SP_STYLE_CHILD)]
    property Child: string read FChild write FChild;
    [SchemaDescription(SP_STYLE_PROP)]
    property Prop: string read FProp write FProp;
    [SchemaDescription(SP_STYLE_VALUE)]
    property Value: string read FValue write FValue;
    [SchemaDescription(SP_STYLE_NAME)]
    property Name: string read FName write FName;
    [SchemaDescription(SP_STYLE_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_STYLE_DELETE)]
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
  Lsp.References,   // SkipIdeArtifacts: el filtro compartido de artefactos
  Lsp.Listas,       // AgrupaPorFichero: los avisos por carpeta y fichero
  Lsp.Styles,
  Lsp.DesignerBin,  // el literal de cadena: su lector y su compositor
  Lsp.Pascal,
  Lsp.Mascara;

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
      Ret.AddPair('file', MaskDriveText('', Doc.Path));
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
      Ret.AddPair('note', MsgText(SN_STYLES_VIEW_NOTE));
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
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    Result := MsgFmt(SF_STYLE_BLOQUE_LINEAS_FMT,
      [IfThen(O.StyleName <> '', O.StyleName, O.ObjName), O.ClassName_, O.StartLine,
       O.EndLine, TPath.GetFileName(Doc.Path), Doc.BlockText(O)]);
  finally
    Doc.Free;
  end;
end;

{ ---- set / clone ---- }

// (ValidStyleValue, la gramatica de un valor de un DFM de texto, vive en
// Lsp.Styles desde la 1.17.0: delphi_designer set es su segundo usuario)
{ EL juez del nombre de un estilo, el de clone y el del renombrado de set:
  una letra (de cualquier alfabeto, como EL identificador de Lsp.Pascal) o
  '_', y detras tambien puntos y guiones. El renombrado no juzgaba nada y
  quitaba comillas a mano (revision de la 1.17.0). }
function NombreDeEstiloQueNoVale(const ANombre: string): string;
begin
  Result := '';
  if not TRegEx.IsMatch(ANombre, '\A' + PATRON_LETRA_IDENT + '(?:' + PATRON_CAR_IDENT + '|[.\-])*\z') then
    Result := MsgFmt(SR_STYLES_NAME_CHARS_FMT, [ANombre]);
end;

function SetStyleProp(const APath, AStyle, AChild, AProp, AValue: string; ADelete: Boolean): string;
var
  Doc: TStyleDoc;
  O: TStyleObj;
  Err, Line, NewName: string;
  WasThere: Boolean;
begin
  if AProp.Trim = '' then
    Exit(MsgText(SR_STYLES_NEED_PROP));
  if not EsIdentificador(AProp.Trim, True) then
    Exit(MsgFmt(SR_STYLES_PROP_CHARS_FMT, [AProp]));
  if (not ADelete) and (AValue.Trim = '') then
    Exit(MsgText(SR_STYLES_NEED_VALUE));
  if AValue.Contains(#10) or AValue.Contains(#13) then
    Exit(MsgText(SR_STYLES_VALUE_LINE));
  // el StyleName lo juzga el juez del NOMBRE (sin comillas tambien vale, como
  // lo lee el arbol): la gramatica de un valor negaba my-style (revision de
  // la 1.17.0)
  if (not ADelete) and not SameText(AProp.Trim, 'StyleName') and not ValidStyleValue(AValue) then
    Exit(MsgFmt(SR_STYLES_VALUE_GRAMMAR_FMT, [AValue.Trim]));
  Doc := TStyleDoc.Create(APath);
  try
    O := Doc.Resolve(AStyle, AChild, Err);
    if O = nil then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Err));
    // StyleName is not a property like the others: writing it RENAMES the
    // style. Done blind it produced two styles with the same name in one
    // file, and after that `delete` silently took the first of the two
    // (field round 8). A rename that collides is refused; a clean one is
    // allowed and says what it really did.
    if (not ADelete) and SameText(AProp.Trim, 'StyleName') then
    begin
      // el nombre como lo lee el arbol (LeeLiteralDeForm): 'Bot'#243'n' es
      // Boton con su acento; sin comillas, tal cual
      if not LeeLiteralDeForm(AValue.Trim, NewName) then
        NewName := AValue.Trim;
      if NewName = '' then
        Exit(MsgText(SR_STYLES_RENAME_EMPTY));
      Err := NombreDeEstiloQueNoVale(NewName);
      if Err <> '' then
        Exit(Err);
      if Doc.FindStyle(NewName) <> nil then
        Exit(MsgFmt(SR_STYLES_RENAME_DUP_FMT, [NewName]));
      // escrito por el compositor de la casa: #N y trozos como el IDE
      Line := Doc.SetProp(O, AProp.Trim, TrozosDeLiteral(NewName), WasThere);
      Doc.Save;
      Exit(MsgFmt(SN_STYLES_RENAMED_FMT,
        [AStyle, NewName, TPath.GetFileName(Doc.Path)]));
    end;
    if ADelete then
    begin
      if not Doc.DeleteProp(O, AProp.Trim) then
        Exit(MsgFmt(SN_STYLES_PROP_ABSENT_FMT, [AProp, AStyle, AChild]));
      Doc.Save;
      Exit(MsgFmt(SN_STYLES_PROP_DELETED_FMT, [AProp, AStyle, IfThen(AChild <> '', '/' + AChild, ''),
        TPath.GetFileName(Doc.Path)]));
    end;
    Line := Doc.SetProp(O, AProp.Trim, AValue.Trim, WasThere);
    Doc.Save;
    Result := MsgFmt(SN_STYLES_PROP_SET_FMT, [IfThen(WasThere, MsgText(SF_STYLE_CAMBIADA), MsgText(SF_STYLE_ANADIDA)), Line.Trim,
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
    Exit(MsgText(SR_STYLES_NEED_NAME));
  Result := NombreDeEstiloQueNoVale(ANew.Trim);
  if Result <> '' then
    Exit;
  Doc := TStyleDoc.Create(APath);
  try
    Src := Doc.FindStyle(AStyle);
    if Src = nil then
      Exit(MsgFmt(SR_STYLE_HAY_NINGUN_ESTILO_COMMAND_FMT,
        [AStyle, TPath.GetFileName(Doc.Path)]));
    if Doc.FindStyle(ANew.Trim) <> nil then
      Exit(MsgFmt(SR_STYLES_NAME_TAKEN_FMT, [ANew]));
    Doc.CloneStyle(Src, ANew.Trim);
    Doc.Save;
    Src := Doc.FindStyle(ANew.Trim);
    Result := MsgFmt(SN_STYLES_CLONED_FMT, [ANew.Trim, AStyle, Src.StartLine, Src.EndLine,
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
      Exit(MsgFmt(SR_STYLE_HAY_NINGUN_ESTILO_COMMAND_FMT,
        [AStyle, TPath.GetFileName(Doc.Path)]));
    First := Src.StartLine;
    Last := Src.EndLine;
    N := Length(Doc.Styles);
    Doc.DeleteStyle(Src);
    Doc.Save;
    Result := MsgFmt(SN_STYLES_DELETED_FMT, [AStyle, First, Last,
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
    Exit(MsgFmt(SR_STYLES_NO_TEXT_FMT, [Dir]));
  if AProject.Trim <> '' then
  begin
    // uno que no esta es NOT_FOUND, y lo que se recorre pasa por la puerta de
    // LEER: se recorria otra carpeta (o la del proceso) contestando ok:true
    // (quinta revision)
    if not TDirectory.Exists(AProject) and not TFile.Exists(AProject) then
      Exit(MsgFmt(SR_STYLES_PROJECT_NO_EXISTE_FMT, [AProject]));
    if TDirectory.Exists(AProject) then
      ProjDir := TPath.GetFullPath(AProject)
    else
      ProjDir := TPath.GetDirectoryName(TPath.GetFullPath(AProject));
    Result := ReadPathDenied(ProjDir);
    if Result <> '' then
      Exit;
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
            Issue.AddPair('lines', MsgFmt(SF_STYLE_LINEAS_Y_FMT, [Seen[N], O.StartLine]));
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
        // El filtro COMPARTIDO, no una lista propia: esta era el tercer
        // emisor de "que carpetas se saltan" y no conocia __delphi-temp ni
        // las carpetas de compilacion (auditoria 2026-09-21).
        if SkipIdeArtifacts(F) then
          Continue;
        if ReadPathDenied(F) <> '' then
          Continue;
        // El lector de la CASA, con el encoding REAL. Leia como UTF-8
        // estricto "porque los lookups son ASCII" - pero el FICHERO no lo es:
        // un solo .pas en CP1252 con un acento tumbaba el lint entero con
        // "No mapping for the Unicode character" (medido en vivo 2026-09-21).
        var EncF: string;
        Text := PatchLoadText(F, EncF);
        if F.EndsWith('.pas', True) then
          Text := BlankComments(Text); // a lookup in a comment is not a lookup
        Lines := SplitToLines(Text); // las lineas como las numera delphi_read
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
          // la ruta, para agruparlos por carpeta y fichero al final (el
          // organizador enmascara la carpeta)
          Issue.AddPair('path', F);
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
    Ret.AddPair('stylesDir', MaskDriveText('', Dir));
    Ret.AddPair('projectDir', MaskDriveText('', ProjDir));
    Ret.AddPair('styleFiles', TJSONNumber.Create(Length(Files)));
    Ret.AddPair('styleNames', TJSONNumber.Create(Names.Count));
    Ret.AddPair('lookupsUsed', TJSONNumber.Create(Used));
    Ret.AddPair('lookupsStandard', TJSONNumber.Create(Standard));
    Ret.AddPair('duplicatedStyleNames', Dups);
    Ret.AddPair('lookupsWithoutStyle', Missing);
    Ret.AddPair('tokensMissing', Tokens);
    Ret.AddPair('rcMissingFiles', Rc);
    // clean = sin hallazgos; ok es "la llamada fue bien" (novena revision)
    Ret.AddPair('clean', TJSONBool.Create((Dups.Count = 0) and (Missing.Count = 0) and
      (Tokens.Count = 0) and (Rc.Count = 0)));
    if Length(PlatformDefaultStyleNames) = 0 then
      Ret.AddPair('note', MsgText(SN_STYLES_NO_DEFAULTS))
    else
      Ret.AddPair('note', MsgText(SN_STYLES_LINT_NOTE));
    // por carpeta y fichero, y DESPUES de 'clean': el par libera la lista
    // plana (Missing) al quedarse la agrupada
    AgrupaPorFichero(Ret, 'lookupsWithoutStyle');
    Result := Ret.ToJSON;
  finally
    Ret.Free; // owns Dups/Missing/Tokens/Rc once added
    Names.Free;
    Defaults.Free;
    Seen.Free;
  end;
end;

{ ---- build ---- }

function RcPathsDenied(const ARc: string): string; forward;

function BuildStyles(const APath: string): string;
var
  Dir, Exe, F, Bin, Out, Rc, Res, Brcc, RcDenied: string;
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
    Exit(MsgText(SR_STYLES_NO_CONVERTER));
  Files := TextStylesIn(Dir);
  if TFile.Exists(APath) and not IsBinaryStyle(APath) then
    Files := [TPath.GetFullPath(APath)];
  if Length(Files) = 0 then
    Exit(MsgFmt(SR_STYLES_NO_TEXT_FMT, [Dir]));
  Ret := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    AllOk := True;
    for F in Files do
    begin
      Bin := TPath.Combine(Dir, TPath.GetFileNameWithoutExtension(F) + '.bin.style');
      Out := CorreStyleConvert(Exe, 'tobin "' + F + '" "' + Bin + '"', Dir, 120000, Code);
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
    Ret.AddPair('stylesDir', MaskDriveText('', Dir));
    Ret.AddPair('converted', Arr);
    // Un estilo que no convirtio es un FALLO: salia exito con ok:false y una
    // nota que mandaba recompilar, y el .rc metia los .bin.style de antes
    // (tercera revision, 27-sep-2026)
    if not AllOk then
    begin
      var Malos := 0;
      for var It in Arr do
        if not TJSONObject(It).GetValue<Boolean>('ok', True) then
          Inc(Malos);
      Ret.AddPair('error', MsgFmt(SR_STYLES_BUILD_CONVERT_FMT, [Malos, Arr.Count]));
      Ret.AddPair('ok', TJSONBool.Create(False));
      Exit(Ret.ToJSON);
    end;
    // the .rc -> .res, with the product's resource compiler
    for Rc in TDirectory.GetFiles(Dir, '*.rc') do
    begin
      Info := DiscoverRadStudio;
      Brcc := TPath.Combine(Info.RootDir, 'bin\brcc32.exe');
      if not TFile.Exists(Brcc) then
      begin
        Ret.AddPair('rc', TPath.GetFileName(Rc));
        Ret.AddPair('error', MsgFmt(SR_STYLE_BRCC_NO_ENCONTRADO_FMT, [Brcc]));
        AllOk := False;
        Break;
      end;
      // Every file this .rc pulls in, checked against the same jail that
      // delphi_read applies. brcc32 has no idea where it may look.
      RcDenied := RcPathsDenied(Rc);
      if RcDenied <> '' then
      begin
        Ret.AddPair('rc', TPath.GetFileName(Rc));
        Ret.AddPair('error', RcDenied);
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
        Ret.AddPair('error', MsgFmt(SR_STYLES_BUILD_RC_FMT, [TPath.GetFileName(Rc), Out.Trim]));
        AllOk := False;
      end;
      Break; // one manifest per styles folder
    end;
    Ret.AddPair('ok', TJSONBool.Create(AllOk));
    // "recompila el proyecto" solo cuando hay un .res nuevo que meter
    if AllOk then
      Ret.AddPair('note', MsgText(SN_STYLES_BUILD_NOTE));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

{ Every path a .rc refers to, checked against the read jail before the
  resource compiler is allowed anywhere near it.

  A .rc line is `NAME TYPE "file"` (or with the file unquoted), plus
  #include. brcc32 resolves those with the SERVER's file access: an absolute
  path outside the workspace opens fine and its bytes end up inside the .res,
  which delphi_fetch will happily hand over. Measured 2026-08-25: win.ini,
  and then the server's own settings.ini with the token in it. '' = clean. }
function RcPathsDenied(const ARc: string): string;
var
  Seen: TStringList;

  // One file of the closure. Recurses through #include, because a .rc whose
  // own lines are all legal can still pull in a second file that is not -
  // and that is exactly how the guard was walked around the day after it was
  // written (measured 2026-08-25: settings.ini, with the token, embedded in a
  // downloadable .res through an #include of a .txt).
  function Walk(const AFile: string; ADepth: Integer): string;
  var
    Txt, Enc, Cand, Base, Raw: string;
    M: TMatch;
  begin
    Result := '';
    if ADepth > 8 then
      Exit(MsgText(SR_STYLES_RC_DEEP));
    if Seen.IndexOf(AFile.ToLower) >= 0 then
      Exit; // already checked (and it stops an include cycle dead)
    Seen.Add(AFile.ToLower);
    if ReadPathDenied(AFile) <> '' then
      Exit(MsgFmt(SR_STYLES_RC_OUTSIDE_FMT,
        [TPath.GetFileName(AFile), TPath.GetFileName(ARc)]));
    try
      Txt := PatchLoadText(AFile, Enc);
    except
      Exit(MsgFmt(SR_STYLES_RC_UNREADABLE_FMT, [TPath.GetFileName(AFile)]));
    end;
    Base := TPath.GetDirectoryName(TPath.GetFullPath(AFile));
    for M in TRegEx.Matches(Txt, '(?im)^\s*(?:#include\s+|[A-Za-z_]\w*\s+[A-Za-z_]\w*\s+)("[^"]+"|\S+)\s*$') do
    begin
      Raw := M.Groups[1].Value.Trim;
      Cand := Raw.Trim(['''', '"']);
      if Cand = '' then
        Continue;
      if not (Cand.Contains('.') or Cand.Contains('\') or Cand.Contains('/')) then
        Continue;
      if not TPath.IsPathRooted(Cand) then
        Cand := TPath.Combine(Base, Cand);
      try
        Cand := TPath.GetFullPath(Cand);
      except
        Exit(MsgFmt(SR_STYLES_RC_BADPATH_FMT, [Raw]));
      end;
      if ReadPathDenied(Cand) <> '' then
        Exit(MsgFmt(SR_STYLES_RC_OUTSIDE_FMT, [Raw, TPath.GetFileName(AFile)]));
      // an #include brings a whole new file's worth of references with it
      if M.Value.TrimLeft.ToLower.StartsWith('#include') and TFile.Exists(Cand) then
      begin
        Result := Walk(Cand, ADepth + 1);
        if Result <> '' then
          Exit;
      end;
    end;
  end;

begin
  Seen := TStringList.Create;
  try
    Result := Walk(TPath.GetFullPath(ARc), 0);
  finally
    Seen.Free;
  end;
end;

{ ---- dispatcher ---- }

{ El gesto; ExecuteWithParams envuelve los que ESCRIBEN en el cerrojo. }
function GestoDeEstilos(const Params: TDelphiStylesParams): string;
var
  Cmd, Denied: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'view';
  if Params.Path.Trim = '' then
    Exit(MsgText(SR_STYLES_NEED_PATH));
  // lo que no va con el comando se dice (Lsp.Guard.ParametroQueNoVa): delete
  // con child/prop borraba el estilo ENTERO pidiendo una parte, y delete es a
  // la vez un comando y un booleano de set (octava revision)
  var Suyos: string;
  var Sobra := ParametroQueNoVa(Cmd, [
      'view', 'filter',
      'get', 'style child',
      'set', 'style child prop value delete',
      'clone', 'style name',
      'delete', 'style',
      'lint', 'project',
      'build', ''],
    ['project', Params.Project, '', 'style', Params.Style, '',
     'child', Params.Child, '', 'prop', Params.Prop, '', 'value', Params.Value, '',
     'name', Params.Name, '', 'filter', Params.Filter, '',
     'delete', IfThen(Params.Delete, 'true'), ''], Suyos);
  if Sobra <> '' then
    Exit(MsgFmt(SR_STYLES_NO_VA_CON_COMANDO_FMT, [Sobra, Cmd, Cmd, ONinguno(Suyos)]));
  if MatchText(Cmd, ['set', 'clone', 'delete', 'build']) then
    Denied := WriteTargetDenied(Params.Path)
  else
    Denied := ReadPathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit(MsgFmt(SR_STYLES_MISSING_FMT, [Params.Path]));
  if MatchText(Cmd, ['view', 'get', 'set', 'clone', 'delete']) then
  begin
    if TDirectory.Exists(Params.Path) or
       not SameText(TPath.GetExtension(Params.Path), '.style') then
      Exit(MsgText(SR_STYLES_NEED_FILE)); // un .txt daba un view vacio "correcto"
    if IsBinaryStyle(Params.Path) then
      Exit(MsgFmt(SR_STYLES_BINARY_FMT, [TPath.GetFileName(Params.Path)]));
  end;
  // lint/build con un FICHERO: su carpeta, como en la 1.6.2, y DICHO (se
  // hacia en silencio; un rechazo rompia un contrato documentado)
  var Ruta := Params.Path;
  var NotaCarpeta := '';
  if MatchText(Cmd, ['lint', 'build']) and TFile.Exists(Params.Path) then
  begin
    Ruta := TPath.GetDirectoryName(TPath.GetFullPath(Params.Path));
    NotaCarpeta := MsgFmt(SN_STYLES_CARPETA_DEL_FICHERO_FMT,
      [TPath.GetFileName(Params.Path), Ruta]);
    // build ESCRIBE en la carpeta: su puerta, sobre la carpeta
    if Cmd = 'build' then
    begin
      Denied := WriteTargetDenied(Ruta);
      if Denied <> '' then
        Exit(Denied);
    end;
  end;
  if MatchText(Cmd, ['get', 'set', 'clone', 'delete']) and (Params.Style.Trim = '') then
    Exit(MsgText(SR_STYLES_NEED_STYLE));
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
      Result := LintStyles(Ruta, Params.Project.Trim)
    else if Cmd = 'build' then
      Result := BuildStyles(Ruta)
    else
      Result := MsgText(SR_STYLE_COMMAND_DEBE_SER);
  except
    on E: Exception do
      Result := MsgExcepcion(E.ClassName, E.Message);
  end;
  if (NotaCarpeta <> '') and not EsFallo(Result) then
    Result := ConNota(Result, 'folderNote', NotaCarpeta);
  // (lo enmascara el filtro de salida, Lsp.Host; una segunda pasada con el
  // nombre de la tool gastaba lo que la llamada dejo anotado)
end;

function TDelphiStylesTool.ExecuteWithParams(const Params: TDelphiStylesParams): string;
begin
  // set/clone/delete reescriben el .dfm leyendolo entero: cerrojo, como
  // cualquier otra edicion. build NO entra - lanza el conversor externo y
  // puede tardar segundos; tener ahi dentro el cerrojo de TODAS las escrituras
  // del servidor seria peor que la carrera que evita.
  if not MatchText(Params.Command.Trim.ToLower, ['set', 'clone', 'delete']) then
    Exit(GestoDeEstilos(Params));
  EnterFileEdit;
  try
    Result := GestoDeEstilos(Params);
  finally
    LeaveFileEdit;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_styles',
    function: IMCPTool begin Result := TDelphiStylesTool.Create; end);

end.
