unit Mcp.Tools.Config;

{ delphi_config: see and manage a project's build configurations and target
  platforms - the "which configuration do I want to build" question.

  - view (read-only): framework (VCL/FMX/console), configurations (Debug,
    Release, custom), and every platform with whether it is enabled, whether
    THIS project can target it (VCL is Windows-only), and whether it needs a
    remote PAServer profile.
  - add-platform (read-write): enable a platform in the .dproj <Platforms>
    block - a CURATED edit that touches only that block, never the rest of the
    MSBuild structure. Refuses a platform the framework cannot target.

  Reads the .dproj through the shared Lsp.Dproj parser (no second parser) and
  writes it through Lsp.Patch (encoding-preserving, atomic, auto-backup). }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiConfigParams = class
  private
    FProject: string;
    FCommand: string;
    FPlatform: string;
    FOutput: string;
    FPath: string;
  public
    [SchemaDescription('Absolute path of the project .dproj')]
    property Project: string read FProject write FProject;
    [SchemaDescription('view (default: list configurations, platforms and search paths) | add-platform (enable a platform) | remove-platform (disable it again) | set-output (put every binary under one folder, e.g. Compiled) | add-searchpath (add a unit search path for one platform, or for all) | remove-searchpath (take it out again)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('add/remove-platform: the platform, from the fixed set Win32|Win64|Win64x|WinARM64EC|OSX64|OSXARM64|Linux64|Android|Android64|iOSDevice64|iOSSimARM64 (anything else is refused). add/remove-searchpath: the platform whose search path changes; empty = the base group (every platform)')]
    property Platform: string read FPlatform write FPlatform;
    [SchemaDescription(SP_CONFIG_PATH)]
    property Path: string read FPath write FPath;
    [SchemaDescription('set-output: the output folder for binaries, a simple relative name like Compiled (default). The .exe goes to <folder>\$(Platform)\$(Config) and .dcu to <folder>\Dcu\$(Platform)\$(Config). Use "default" to restore the RAD Studio layout. No absolute paths, no "..".')]
    property Output: string read FOutput write FOutput;
  end;

  TDelphiConfigTool = class(TMCPToolBase<TDelphiConfigParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiConfigParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.Dproj,
  Lsp.Patch;

constructor TDelphiConfigTool.Create;
begin
  inherited;
  FName := 'delphi_config';
  FDescription := 'See and manage a project''s build configurations and ' +
    'target PLATFORMS. command=view (read-only) reports the framework ' +
    '(VCL is Windows-only; FMX and console cross platforms), the build ' +
    'configurations (Debug/Release/custom) and every platform with whether ' +
    'it is enabled, whether THIS project can target it, and whether it needs ' +
    'a remote PAServer profile. command=add-platform enables a platform in ' +
    'the .dproj (a curated edit of the <Platforms> block only); ' +
    'remove-platform disables it again. command=set-output puts every binary ' +
    'under one folder (output=Compiled by default): a curated edit that sets ' +
    'DCC_ExeOutput/DCC_DcuOutput, keeping the per-platform/config subfolders. ' +
    'command=add-searchpath adds a unit search path (where the compiler looks ' +
    'for .pas/.dcu, e.g. the Source folder of an installed component) to ONE ' +
    'platform - the IDE''s Project Options > Search path - creating the ' +
    'platform''s property groups exactly as the IDE would; a platform added ' +
    'to a project inherits NO search paths from the others, which is the usual ' +
    'reason a unit is "not found" on the new platform only. remove-searchpath ' +
    'takes it out again. To BUILD a specific combination use delphi_build ' +
    'with platform+config.';
end;

procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject); forward;

function PlatformNeedsProfile(const APlatform: string): Boolean;
begin
  Result := not IsLocalPlatform(APlatform);
end;

function ViewConfig(const ADproj: string): string;
var
  Info: TDprojInfo;
  Return: TJSONObject;
  Cfgs, Plats: TJSONArray;
  C, Reason: string;
  P: TDprojPlatform;
  Obj: TJSONObject;
begin
  Info := ReadDproj(ADproj);
  Return := TJSONObject.Create;
  try
    Return.AddPair('project', ADproj);
    Return.AddPair('frameworkType', Info.FrameworkType);
    Return.AddPair('appType', Info.AppType);
    if SameText(Info.FrameworkType, 'VCL') then
      Return.AddPair('crossPlatform', 'no (VCL = Windows only; use FMX or a ' +
        'console app to target Linux/macOS/mobile)')
    else
      Return.AddPair('crossPlatform', 'yes (FMX/console can target other platforms)');
    Cfgs := TJSONArray.Create;
    Return.AddPair('configurations', Cfgs);
    for C in Info.Configs do
      Cfgs.Add(C);
    Plats := TJSONArray.Create;
    Return.AddPair('platforms', Plats);
    for P in Info.Platforms do
    begin
      Obj := TJSONObject.Create;
      Plats.AddElement(Obj);
      Obj.AddPair('name', P.Name);
      Obj.AddPair('enabled', TJSONBool.Create(P.Enabled));
      Obj.AddPair('canTarget', TJSONBool.Create(Info.CanTarget(P.Name, Reason)));
      if not Info.CanTarget(P.Name, Reason) then
        Obj.AddPair('reason', Reason);
      Obj.AddPair('needsRemoteProfile', TJSONBool.Create(PlatformNeedsProfile(P.Name)));
    end;
    AddSearchPathsView(TFile.ReadAllText(ADproj), Return);
    Return.AddPair('note', 'To build: delphi_build {project, platform, ' +
      'config}. Platforms with needsRemoteProfile=true also need a PAServer ' +
      'profile - see delphi_paserver.');
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

function AddPlatform(const ADproj, ARawPlatform: string): string;
var
  Info: TDprojInfo;
  Reason, Enc, Xml, Indent, NewLine, APlatform: string;
  P: TDprojPlatform;
  ClosePos, OpenPos, LineStart: Integer;
begin
  if ARawPlatform.Trim = '' then
    Exit('error: add-platform necesita "platform" (Win64, Linux64, OSX64...)');
  // WHITELIST: a platform name is a fixed, known token. Rejecting anything
  // else makes it impossible to inject XML into the .dproj through this
  // parameter (measured RCE via a crafted <Import> - field round 5, R5-B).
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(Format('RECHAZADO: "%s" no es una plataforma Delphi valida. ' +
      'Validas: Win32, Win64, Win64x, WinARM64EC, OSX64, OSXARM64, Linux64, ' +
      'Android, Android64, iOSDevice64, iOSSimARM64.', [ARawPlatform.Trim]));
  Info := ReadDproj(ADproj);
  if Info.FrameworkType = '' then
    Exit('error: no puedo leer el framework del .dproj; revisa la ruta.');
  if not Info.CanTarget(APlatform, Reason) then
    Exit(Format('RECHAZADO: %s', [Reason]));
  for P in Info.Platforms do
    if SameText(P.Name, APlatform) then
    begin
      if P.Enabled then
        Exit(Format('La plataforma %s ya esta habilitada en el proyecto. ' +
          'Compila con delphi_build {platform:"%s"}.', [APlatform, APlatform]));
      Break;
    end;

  Xml := PatchLoadText(ADproj, Enc);
  // Enable an existing-but-disabled platform: flip its value to True.
  var Tag := Format('<Platform value="%s">', [APlatform]);
  var TagPos := Pos(LowerCase(Tag), LowerCase(Xml));
  if TagPos > 0 then
  begin
    var ValStart := TagPos + Length(Tag);
    var ValEnd := Pos('<', Xml, ValStart);
    if ValEnd > 0 then
    begin
      Xml := Copy(Xml, 1, ValStart - 1) + 'True' + Copy(Xml, ValEnd, MaxInt);
      PatchSaveText(ADproj, Xml, Enc);
      Exit(Format('HABILITADA la plataforma %s (estaba declarada, desactivada). ' +
        'El IDE la enriquecera al abrir el proyecto; MSBuild ya la compila. ' +
        'Si necesita PAServer, prepara el perfil con delphi_paserver.', [APlatform]));
    end;
  end;

  // Insert a new <Platform value="X">True</Platform> before </Platforms>,
  // copying the indentation of the existing entries.
  ClosePos := Pos('</Platforms>', Xml);
  OpenPos := Pos('<Platforms>', Xml);
  if (ClosePos = 0) or (OpenPos = 0) or (ClosePos < OpenPos) then
    Exit('error: no encuentro un bloque <Platforms>...</Platforms> en el .dproj.');
  // indentation = whitespace before </Platforms>
  LineStart := ClosePos;
  while (LineStart > 1) and not CharInSet(Xml[LineStart - 1], [#10, #13]) do
    Dec(LineStart);
  Indent := Copy(Xml, LineStart, ClosePos - LineStart);
  NewLine := Indent + '    ' + Format('<Platform value="%s">True</Platform>', [APlatform]) + sLineBreak;
  Xml := Copy(Xml, 1, LineStart - 1) + NewLine + Copy(Xml, LineStart, MaxInt);
  PatchSaveText(ADproj, Xml, Enc);
  Result := Format('ANADIDA la plataforma %s al .dproj (bloque <Platforms>). ' +
    'El IDE completara sus PropertyGroups al abrir el proyecto; para un ' +
    'proyecto sencillo MSBuild ya la compila. Verifica con delphi_build ' +
    '{platform:"%s"}. Si necesita PAServer, prepara el perfil con ' +
    'delphi_paserver.', [APlatform, APlatform]);
end;

{ Disable a platform (flip its <Platform value="X">True</Platform> to False).
  Reversible and non-destructive - the safe inverse of add-platform. }
function RemovePlatform(const ADproj, ARawPlatform: string): string;
var
  Enc, Xml, APlatform: string;
begin
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(Format('RECHAZADO: "%s" no es una plataforma Delphi valida.', [ARawPlatform.Trim]));
  Xml := PatchLoadText(ADproj, Enc);
  var Tag := Format('<Platform value="%s">', [APlatform]);
  var TagPos := Pos(LowerCase(Tag), LowerCase(Xml));
  if TagPos = 0 then
    Exit(Format('La plataforma %s no esta declarada en el proyecto.', [APlatform]));
  var ValStart := TagPos + Length(Tag);
  var ValEnd := Pos('<', Xml, ValStart);
  if ValEnd = 0 then
    Exit('error: el <Platform> del .dproj tiene una forma inesperada.');
  Xml := Copy(Xml, 1, ValStart - 1) + 'False' + Copy(Xml, ValEnd, MaxInt);
  PatchSaveText(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := Format('DESHABILITADA la plataforma %s (queda declarada pero ' +
    'desactivada; add-platform la reactiva). Copia previa en __delphi-patch.', [APlatform]);
end;

{ A binary output folder must be a SIMPLE relative name (Compiled, or
  bin\out): no XML metacharacters (so nothing can be injected into the .dproj
  the way R5-B did), no drive/absolute path, no ".." escape. Returns the
  cleaned token in AClean. }
function ValidOutputFolder(const AFolder: string; out AClean: string): Boolean;
var
  C: Char;
  Seg: string;
begin
  Result := False;
  AClean := AFolder.Trim.Trim(['"']).Trim;
  AClean := AClean.Replace('/', '\');
  while AClean.StartsWith('\') do AClean := AClean.Substring(1);
  while AClean.EndsWith('\') do AClean := AClean.Substring(0, AClean.Length - 1);
  if AClean = '' then Exit;
  if AClean.Contains('..') or AClean.Contains(':') then Exit; // no escape, no drive
  for C in AClean do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ', '\']) then
      Exit;
  for Seg in AClean.Split(['\']) do
    if Seg.Trim = '' then Exit; // no empty segments (\\ , trailing, etc.)
  Result := True;
end;

{ Inner text currently between <ATag>..</ATag> ('' if the tag is absent). }
function TagInner(const AXml, ATag: string): string;
var
  Low: string;
  OpenPos, InnerStart, ClosePos: Integer;
begin
  Result := '';
  Low := LowerCase(AXml);
  OpenPos := Pos('<' + LowerCase(ATag) + '>', Low);
  if OpenPos = 0 then Exit;
  InnerStart := OpenPos + Length(ATag) + 2;
  ClosePos := Pos('</' + LowerCase(ATag) + '>', Low, InnerStart);
  if ClosePos = 0 then Exit;
  Result := Copy(AXml, InnerStart, ClosePos - InnerStart);
end;

{ Replace the inner text of an existing <ATag>..</ATag>. True if it existed. }
function SetTagInner(var AXml: string; const ATag, ANewInner: string): Boolean;
var
  Low: string;
  OpenPos, InnerStart, ClosePos: Integer;
begin
  Result := False;
  Low := LowerCase(AXml);
  OpenPos := Pos('<' + LowerCase(ATag) + '>', Low);
  if OpenPos = 0 then Exit;
  InnerStart := OpenPos + Length(ATag) + 2;
  ClosePos := Pos('</' + LowerCase(ATag) + '>', Low, InnerStart);
  if ClosePos = 0 then Exit;
  AXml := Copy(AXml, 1, InnerStart - 1) + ANewInner + Copy(AXml, ClosePos, MaxInt);
  Result := True;
end;

{ Put every build artifact of the project under one folder (default Compiled),
  matching the common RAD Studio convention:
    DCC_ExeOutput = .\<folder>\$(Platform)\$(Config)
    DCC_DcuOutput = .\<folder>\Dcu\$(Platform)\$(Config)
  A curated edit of the base PropertyGroup only; the .dproj is backed up. }
function SetOutput(const ADproj, ARawFolder: string): string;
var
  Enc, Xml, Clean, ExeInner, DcuInner, OldExe, OldDcu: string;
  BasePos, InsertAt: Integer;
  Restore: Boolean;
begin
  Restore := SameText(ARawFolder.Trim, 'default') or SameText(ARawFolder.Trim, 'reset');
  if Restore then
  begin
    Clean := '(RAD Studio default)';
    ExeInner := '.\$(Platform)\$(Config)';
    DcuInner := '.\$(Platform)\$(Config)\dcu';
  end
  else
  begin
    if ARawFolder.Trim = '' then
      Clean := 'Compiled' // sensible default
    else if not ValidOutputFolder(ARawFolder, Clean) then
      Exit(Format('RECHAZADO: "%s" no es una carpeta de salida valida. Usa un ' +
        'nombre relativo simple como Compiled (sin ruta absoluta, sin "..", ' +
        'sin caracteres especiales).', [ARawFolder.Trim]));
    ExeInner := '.\' + Clean + '\$(Platform)\$(Config)';
    DcuInner := '.\' + Clean + '\Dcu\$(Platform)\$(Config)';
  end;

  Xml := PatchLoadText(ADproj, Enc);
  OldExe := TagInner(Xml, 'DCC_ExeOutput');
  OldDcu := TagInner(Xml, 'DCC_DcuOutput');

  // Replace existing tags in place (both real projects have them).
  SetTagInner(Xml, 'DCC_ExeOutput', ExeInner);
  SetTagInner(Xml, 'DCC_DcuOutput', DcuInner);

  // If either tag was missing, insert it into the base PropertyGroup.
  if (OldExe = '') or (OldDcu = '') then
  begin
    BasePos := Pos(LowerCase('<PropertyGroup Condition="''$(Base)''!=''''">'),
                   LowerCase(Xml));
    if BasePos = 0 then
      Exit('error: no encuentro el PropertyGroup base ("$(Base)") del .dproj; ' +
        'abre el proyecto una vez en el IDE y reintenta.');
    InsertAt := Pos('>', Xml, BasePos) + 1;
    if OldDcu = '' then
      Xml := Copy(Xml, 1, InsertAt - 1) + sLineBreak +
        '        <DCC_DcuOutput>' + DcuInner + '</DCC_DcuOutput>' +
        Copy(Xml, InsertAt, MaxInt);
    if OldExe = '' then
      Xml := Copy(Xml, 1, InsertAt - 1) + sLineBreak +
        '        <DCC_ExeOutput>' + ExeInner + '</DCC_ExeOutput>' +
        Copy(Xml, InsertAt, MaxInt);
  end;

  PatchSaveText(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := Format('Salida de binarios fijada en "%s". Ahora:%s' +
    '  DCC_ExeOutput = %s (antes: %s)%s' +
    '  DCC_DcuOutput = %s (antes: %s)%s' +
    'Copia previa en __delphi-patch. Verifica con delphi_build; el IDE lo ' +
    'respeta al abrir el proyecto.',
    [Clean, sLineBreak, ExeInner, IfThen(OldExe = '', '(sin definir)', OldExe),
     sLineBreak, DcuInner, IfThen(OldDcu = '', '(sin definir)', OldDcu), sLineBreak]);
end;

{ ---- unit search paths ---------------------------------------------------
  The IDE's Project Options > Search path, per platform. Field 2026-08-21: a
  real FMX app (41 units) built for Linux64 except ONE unit - the installed
  component's folder was registered in the IDE's library path for Win/Android
  only, and a platform added to a project inherits no search path from the
  others. The .dproj had NO DCC_UnitSearchPath and NO Base_Linux64 groups at
  all (add-platform only touches <Platforms>), so the edit must create the
  platform's property groups exactly as the IDE lays them out:

    <PropertyGroup Condition="('$(Platform)'=='X' and '$(Base)'=='true') or '$(Base_X)'!=''">
        <Base_X>true</Base_X>   <CfgParent>Base</CfgParent>   <Base>true</Base>
    </PropertyGroup>                                 (the DEFINER, after its siblings)
    <PropertyGroup Condition="'$(Base_X)'!=''">
        <DCC_UnitSearchPath>path;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>                                 (the VALUES, after the Base values)

  MSBuild evaluates property groups in order, which is why the definer sits
  before the values and the values after the base values (so the macro
  $(DCC_UnitSearchPath) picks up the base list). Paths are vetted like any
  read: they must resolve (macros expanded with the IDE's own environment
  table) inside the workspace roots or the read-only library zone, and exist. }

function GroupCondition(const APlatform: string): string;
begin
  if APlatform = '' then
    Result := '''$(Base)''!='''''
  else
    Result := '''$(Base_' + APlatform + ')''!=''''';
end;

function DefinerCondition(const APlatform: string): string;
begin
  Result := '(''$(Platform)''==''' + APlatform + ''' and ''$(Base)''==''true'') or ' +
    '''$(Base_' + APlatform + ')''!=''''';
end;

{ <PropertyGroup Condition="ACondition"> ... </PropertyGroup>: AOpen = start of
  the open tag, AInner = first char after it, AClose = start of the close tag.
  False when the group does not exist. Conditions are matched verbatim. }
function FindGroup(const AXml, ACondition: string; out AOpen, AInner, AClose: Integer): Boolean;
var
  Low, Tag: string;
begin
  Result := False;
  Tag := LowerCase('<PropertyGroup Condition="' + ACondition + '">');
  Low := LowerCase(AXml);
  AOpen := Pos(Tag, Low);
  if AOpen = 0 then
    Exit;
  AInner := AOpen + Length(Tag);
  AClose := Pos('</propertygroup>', Low, AInner);
  Result := AClose > 0;
end;

{ Creates the definer and values groups of a platform when the .dproj lacks
  them (the IDE writes both the first time a platform option is touched). }
procedure EnsurePlatformGroups(var AXml: string; const APlatform: string);
var
  O, I, C, LastDef, At: Integer;
  Low, Needle: string;
begin
  if not FindGroup(AXml, DefinerCondition(APlatform), O, I, C) then
  begin
    // after the last platform definer (any platform), else after the Base one
    Low := LowerCase(AXml);
    Needle := LowerCase(' or ''$(Base_');
    LastDef := 0;
    At := Pos(Needle, Low);
    while At > 0 do
    begin
      LastDef := At;
      At := Pos(Needle, Low, At + 1);
    end;
    if LastDef = 0 then
      LastDef := Pos(LowerCase('<PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">'), Low);
    if LastDef = 0 then
      raise Exception.Create('no encuentro los PropertyGroup de configuracion base del .dproj; ' +
        'abre el proyecto una vez en el IDE y reintenta.');
    At := Pos('</propertygroup>', Low, LastDef);
    At := At + Length('</PropertyGroup>');
    AXml := Copy(AXml, 1, At - 1) + sLineBreak +
      '    <PropertyGroup Condition="' + DefinerCondition(APlatform) + '">' + sLineBreak +
      '        <Base_' + APlatform + '>true</Base_' + APlatform + '>' + sLineBreak +
      '        <CfgParent>Base</CfgParent>' + sLineBreak +
      '        <Base>true</Base>' + sLineBreak +
      '    </PropertyGroup>' + Copy(AXml, At, MaxInt);
  end;
  if not FindGroup(AXml, GroupCondition(APlatform), O, I, C) then
  begin
    if not FindGroup(AXml, GroupCondition(''), O, I, C) then
      raise Exception.Create('no encuentro el PropertyGroup base ("$(Base)") del .dproj; ' +
        'abre el proyecto una vez en el IDE y reintenta.');
    At := C + Length('</PropertyGroup>');
    AXml := Copy(AXml, 1, At - 1) + sLineBreak +
      '    <PropertyGroup Condition="' + GroupCondition(APlatform) + '">' + sLineBreak +
      '    </PropertyGroup>' + Copy(AXml, At, MaxInt);
  end;
end;

{ The <DCC_UnitSearchPath> element INSIDE one group: positions of the value
  (AValStart..AValEnd-1) and of the whole element (AElStart..AElEnd-1). }
function FindSearchTag(const AXml: string; AInner, AClose: Integer;
  out AElStart, AValStart, AValEnd, AElEnd: Integer): Boolean;
const
  OpenTag = '<DCC_UnitSearchPath>';
  CloseTag = '</DCC_UnitSearchPath>';
var
  Low: string;
begin
  Result := False;
  Low := LowerCase(AXml);
  AElStart := Pos(LowerCase(OpenTag), Low, AInner);
  if (AElStart = 0) or (AElStart > AClose) then
    Exit;
  AValStart := AElStart + Length(OpenTag);
  AValEnd := Pos(LowerCase(CloseTag), Low, AValStart);
  if (AValEnd = 0) or (AValEnd > AClose) then
    Exit;
  AElEnd := AValEnd + Length(CloseTag);
  Result := True;
end;

function SplitPaths(const AList: string): TArray<string>;
var
  L: TList<string>;
  P: string;
begin
  L := TList<string>.Create;
  try
    for P in AList.Split([';']) do
      if P.Trim <> '' then
        L.Add(P.Trim);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Vets a search path the way every read is vetted: expand the IDE's macros,
  resolve relative to the project, then the read jail (roots + library zone)
  and existence. Returns '' when fine, else the refusal. AShow is the
  resolved path for messages. }
function SearchPathDenied(const ADproj, ARaw: string; out AShow: string): string;
var
  Info: TRadStudioInfo;
  Vars: TStringList;
  Expanded: string;
  C: Char;
begin
  AShow := '';
  if ARaw.Trim = '' then
    Exit(SR_CONFIG_NEED_PATH);
  if Length(ARaw) > 400 then
    Exit(SR_CONFIG_PATH_CHARS);
  for C in ARaw do
    if (Ord(C) < 32) or CharInSet(C, ['<', '>', '"', ';', '&', '|']) then
      Exit(SR_CONFIG_PATH_CHARS);
  Expanded := ARaw.Trim;
  if Expanded.Contains('$(') then
  begin
    Info := DiscoverRadStudio;
    Vars := TStringList.Create;
    try
      if Info.Found then
        IdeEnvironmentVars(Info.Version, Vars);
      Expanded := ExpandIdeMacros(Expanded, Vars);
    finally
      Vars.Free;
    end;
    if Expanded.Contains('$(') then
      Exit(Format(SR_CONFIG_PATH_MACRO_FMT, [ARaw.Trim]));
  end;
  if not TPath.IsPathRooted(Expanded) then
    Expanded := TPath.Combine(TPath.GetDirectoryName(ADproj), Expanded);
  try
    Expanded := TPath.GetFullPath(Expanded);
  except
    on E: Exception do
      Exit(Format(SR_CONFIG_PATH_MACRO_FMT, [ARaw.Trim]));
  end;
  AShow := Expanded;
  Result := ReadPathDenied(Expanded);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Expanded) then
    Exit(Format(SR_CONFIG_PATH_MISSING_FMT, [Expanded]));
end;

function AddSearchPath(const ADproj, ARawPlatform, ARawPath: string): string;
var
  Enc, Xml, Plat, Show, Path, NewInner, P: string;
  O, I, C, ElS, VS, VE, ElE: Integer;
begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(Format('RECHAZADO: "%s" no es una plataforma Delphi valida. ' +
        'Validas: Win32, Win64, Win64x, WinARM64EC, OSX64, OSXARM64, Linux64, ' +
        'Android, Android64, iOSDevice64, iOSSimARM64 (o vacia = todas).', [ARawPlatform.Trim]));
  end;
  Result := SearchPathDenied(ADproj, ARawPath, Show);
  if Result <> '' then
    Exit;
  Path := ARawPath.Trim;

  Xml := PatchLoadText(ADproj, Enc);
  try
    if Plat <> '' then
      EnsurePlatformGroups(Xml, Plat);
  except
    on E: Exception do
      Exit('error: ' + E.Message);
  end;
  if not FindGroup(Xml, GroupCondition(Plat), O, I, C) then
    Exit('error: no encuentro el PropertyGroup ' + GroupCondition(Plat) + ' del .dproj.');
  if FindSearchTag(Xml, I, C, ElS, VS, VE, ElE) then
  begin
    for P in SplitPaths(Copy(Xml, VS, VE - VS)) do
      if SameText(P, Path) then
        Exit(Format(SN_CONFIG_PATH_PRESENT_FMT,
          [Path, IfThen(Plat = '', 'todas las plataformas (grupo base)', Plat)]));
    NewInner := Path + ';' + Copy(Xml, VS, VE - VS);
    Xml := Copy(Xml, 1, VS - 1) + NewInner + Copy(Xml, VE, MaxInt);
  end
  else
    Xml := Copy(Xml, 1, I - 1) + sLineBreak +
      '        <DCC_UnitSearchPath>' + Path + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
      Copy(Xml, I, MaxInt);
  PatchSaveText(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := Format(SN_CONFIG_PATH_ADDED_FMT,
    [Path, IfThen(Plat = '', 'todas las plataformas (grupo base)', Plat), Show,
     IfThen(Plat = '', 'Win64', Plat)]);
end;

function RemoveSearchPath(const ADproj, ARawPlatform, ARawPath: string): string;
var
  Enc, Xml, Plat, Path, Rest, P: string;
  O, I, C, ElS, VS, VE, ElE, LineStart: Integer;
  Found: Boolean;
  Keep: TList<string>;
begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(Format('RECHAZADO: "%s" no es una plataforma Delphi valida.', [ARawPlatform.Trim]));
  end;
  Path := ARawPath.Trim;
  if Path = '' then
    Exit(SR_CONFIG_NEED_PATH);
  Xml := PatchLoadText(ADproj, Enc);
  if not FindGroup(Xml, GroupCondition(Plat), O, I, C) or
     not FindSearchTag(Xml, I, C, ElS, VS, VE, ElE) then
    Exit(Format(SN_CONFIG_PATH_ABSENT_FMT,
      [Path, IfThen(Plat = '', 'el grupo base', Plat)]));
  Found := False;
  Keep := TList<string>.Create;
  try
    for P in SplitPaths(Copy(Xml, VS, VE - VS)) do
      if SameText(P, Path) then
        Found := True
      else
        Keep.Add(P);
    if not Found then
      Exit(Format(SN_CONFIG_PATH_ABSENT_FMT,
        [Path, IfThen(Plat = '', 'el grupo base', Plat)]));
    Rest := string.Join(';', Keep.ToArray);
  finally
    Keep.Free;
  end;
  if (Rest = '') or SameText(Rest, '$(DCC_UnitSearchPath)') then
  begin
    // nothing of ours left: drop the whole element, its line included
    LineStart := ElS;
    while (LineStart > 1) and not CharInSet(Xml[LineStart - 1], [#10, #13]) do
      Dec(LineStart);
    if Copy(Xml, LineStart, ElS - LineStart).Trim = '' then
    begin
      if (LineStart > 1) and (Xml[LineStart - 1] = #10) then
        Dec(LineStart);
      if (LineStart > 1) and (Xml[LineStart - 1] = #13) then
        Dec(LineStart);
      Xml := Copy(Xml, 1, LineStart - 1) + Copy(Xml, ElE, MaxInt);
    end
    else
      Xml := Copy(Xml, 1, ElS - 1) + Copy(Xml, ElE, MaxInt);
  end
  else
    Xml := Copy(Xml, 1, VS - 1) + Rest + Copy(Xml, VE, MaxInt);
  PatchSaveText(ADproj, Xml, Enc);
  Result := Format(SN_CONFIG_PATH_REMOVED_FMT,
    [Path, IfThen(Plat = '', 'todas las plataformas (grupo base)', Plat)]);
end;

{ view: the search paths per group, as the .dproj states them (macros kept). }
procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  M, TagM: TMatch;
  Name, P: string;
  Any: Boolean;
begin
  Obj := TJSONObject.Create;
  Any := False;
  for M in TRegEx.Matches(AXml,
    '<PropertyGroup Condition="''\$\((Base(?:_(\w+))?)\)''!=''''">(.*?)</PropertyGroup>',
    [roIgnoreCase, roSingleLine]) do
  begin
    TagM := TRegEx.Match(M.Groups[3].Value,
      '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>', [roIgnoreCase, roSingleLine]);
    if not TagM.Success then
      Continue;
    if M.Groups[2].Success and (M.Groups[2].Value <> '') then
      Name := M.Groups[2].Value
    else
      Name := 'base';
    Arr := TJSONArray.Create;
    for P in SplitPaths(XmlUnescape(TagM.Groups[1].Value)) do
      Arr.Add(P);
    Obj.AddPair(Name, Arr);
    Any := True;
  end;
  AReturn.AddPair('searchPaths', Obj);
  if not Any then
    AReturn.AddPair('searchPathsNote', SN_CONFIG_NO_PATHS);
end;

function TDelphiConfigTool.ExecuteWithParams(const Params: TDelphiConfigParams): string;
var
  Cmd: string;
begin
  if Params.Project.Trim = '' then
    Exit('error: delphi_config necesita "project" (ruta del .dproj)');
  Result := PathDenied(Params.Project);
  if Result <> '' then
    Exit;
  if not TFile.Exists(Params.Project) then
    Exit('error: no existe el .dproj ' + Params.Project);
  Cmd := Params.Command.Trim.ToLower;
  if (Cmd = '') or (Cmd = 'view') then
    Result := ViewConfig(Params.Project)
  else if Cmd = 'add-platform' then
    Result := AddPlatform(Params.Project, Params.Platform)
  else if Cmd = 'remove-platform' then
    Result := RemovePlatform(Params.Project, Params.Platform)
  else if Cmd = 'set-output' then
    Result := SetOutput(Params.Project, Params.Output)
  else if Cmd = 'add-searchpath' then
    Result := AddSearchPath(Params.Project, Params.Platform, Params.Path)
  else if Cmd = 'remove-searchpath' then
    Result := RemoveSearchPath(Params.Project, Params.Platform, Params.Path)
  else
    Result := 'error: command debe ser view | add-platform | remove-platform | ' +
      'set-output | add-searchpath | remove-searchpath';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_config',
    function: IMCPTool begin Result := TDelphiConfigTool.Create; end);

end.
