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
  MCPServer.Types;

type
  TDelphiConfigParams = class
  private
    FProject: string;
    FCommand: string;
    FPlatform: string;
    FOutput: string;
  public
    [SchemaDescription('Absolute path of the project .dproj')]
    property Project: string read FProject write FProject;
    [SchemaDescription('view (default: list configurations and platforms) | add-platform (enable a platform) | remove-platform (disable it again) | set-output (put every binary under one folder, e.g. Compiled)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('add/remove-platform: the platform, from the fixed set Win32|Win64|Win64x|WinARM64EC|OSX64|OSXARM64|Linux64|Android|Android64|iOSDevice64|iOSSimARM64 (anything else is refused)')]
    property Platform: string read FPlatform write FPlatform;
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
  MCPServer.Registration,
  Lsp.Guard,
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
    'To BUILD a specific combination use delphi_build with platform+config.';
end;

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
  else
    Result := 'error: command debe ser view | add-platform | remove-platform | set-output';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_config',
    function: IMCPTool begin Result := TDelphiConfigTool.Create; end);

end.
