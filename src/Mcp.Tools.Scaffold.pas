unit Mcp.Tools.Scaffold;

{ delphi_create: scaffold NEW projects (console/VCL/FMX) and NEW forms
  (VCL/FMX) remotely. Engine in Lsp.Scaffold. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types;

type
  TDelphiCreateParams = class
  private
    FKind: string;
    FDir: string;
    FName: string;
    FProject: string;
    FFormName: string;
  public
    [SchemaDescription('What to create: project-console | project-vcl | project-fmx | form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule | unit (a plain .pas). Everything but projects is registered in the project given')]
    property Kind: string read FKind write FKind;
    [SchemaDescription('Projects: target directory (created if missing)')]
    property Dir: string read FDir write FDir;
    [SchemaDescription('Projects: project name. Forms, frames, data modules and units: unit name (e.g. UClientes)')]
    property Name: string read FName write FName;
    [SchemaDescription('Everything but projects: absolute path of the project .dpr (or .dproj) to register the new unit in')]
    property Project: string read FProject write FProject;
    [SchemaDescription('Forms/frames/data modules optional: instance name without the T (default: Form+unit, Frame+unit, DM+unit)')]
    property FormName: string read FFormName write FFormName;
  end;

  TDelphiCreateTool = class(TMCPToolBase<TDelphiCreateParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiCreateParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  Lsp.Scaffold;

constructor TDelphiCreateTool.Create;
begin
  inherited;
  FName := 'delphi_create';
  FDescription := 'Create a NEW Delphi project (console/VCL/FMX: .dpr + ' +
    'buildable .dproj + main form) or a NEW form, frame or data module ' +
    '(VCL/FMX: .pas + .dfm/.fmx pair, registered in the .dpr uses - with ' +
    'Application.CreateForm for forms and data modules - and in the .dproj). ' +
    'IDE-equivalent skeletons, CRLF, source encoding follows the IDE''s ' +
    'configured default (UTF-8/ANSI), never overwrites anything. kind=unit ' +
    'creates a plain .pas and registers it in the project (uses of the .dpr ' +
    '+ DCCReference of the .dproj); forms get their Application.CreateForm ' +
    'too. An EXISTING .pas joins a project with delphi_config command=add-unit.';
end;

function TDelphiCreateTool.ExecuteWithParams(const Params: TDelphiCreateParams): string;
var
  K: string;
begin
  K := Params.Kind.Trim.ToLower;
  if K.StartsWith('project-') then
    Result := CreateDelphiProject(Params.Dir, Params.Name, K.Substring(8))
  else if K.StartsWith('form-') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName, K.Substring(5))
  else if K.StartsWith('frame-') or (K = 'datamodule') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName, K)
  else if K = 'unit' then
    Result := CreateDelphiUnit(Params.Project, Params.Name)
  else
    Result := 'RECHAZADO: kind debe ser project-console | project-vcl | project-fmx | ' +
      'form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule | unit.';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_create',
    function: IMCPTool begin Result := TDelphiCreateTool.Create; end);

end.
