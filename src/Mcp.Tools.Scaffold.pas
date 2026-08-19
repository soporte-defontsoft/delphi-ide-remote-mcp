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
    [SchemaDescription('What to create: project-console | project-vcl | project-fmx | form-vcl | form-fmx')]
    property Kind: string read FKind write FKind;
    [SchemaDescription('Projects: target directory (created if missing)')]
    property Dir: string read FDir write FDir;
    [SchemaDescription('Projects: project name. Forms: unit name (e.g. UClientes)')]
    property Name: string read FName write FName;
    [SchemaDescription('Forms: absolute path of the project .dpr to register the form in')]
    property Project: string read FProject write FProject;
    [SchemaDescription('Forms optional: form name without the T (default: Form+unit name)')]
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
    'buildable .dproj + main form) or a NEW form (VCL/FMX: .pas + .dfm/.fmx ' +
    'pair, registered in the .dpr uses and Application.CreateForm). ' +
    'IDE-equivalent skeletons, UTF-8 with BOM + CRLF, never overwrites ' +
    'anything. For plain units use delphi_edit with createunit=true.';
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
  else
    Result := 'RECHAZADO: kind debe ser project-console | project-vcl | project-fmx | form-vcl | form-fmx.';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_create',
    function: IMCPTool begin Result := TDelphiCreateTool.Create; end);

end.
