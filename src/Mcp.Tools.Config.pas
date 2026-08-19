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
  public
    [SchemaDescription('Absolute path of the project .dproj')]
    property Project: string read FProject write FProject;
    [SchemaDescription('view (default: list configurations and platforms) | add-platform (enable a platform in the project)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('add-platform: the platform to enable (Win64, Linux64, OSX64, OSXARM64, Android64, iOSDevice64...)')]
    property Platform: string read FPlatform write FPlatform;
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
    'the .dproj (a curated edit of the <Platforms> block only). To BUILD a ' +
    'specific combination use delphi_build with platform+config.';
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

function AddPlatform(const ADproj, APlatform: string): string;
var
  Info: TDprojInfo;
  Reason, Enc, Xml, Indent, NewLine: string;
  P: TDprojPlatform;
  ClosePos, OpenPos, LineStart: Integer;
begin
  if APlatform.Trim = '' then
    Exit('error: add-platform necesita "platform" (Win64, Linux64, OSX64...)');
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
    Result := AddPlatform(Params.Project, Params.Platform.Trim)
  else
    Result := 'error: command debe ser view | add-platform';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_config',
    function: IMCPTool begin Result := TDelphiConfigTool.Create; end);

end.
