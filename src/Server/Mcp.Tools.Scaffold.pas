unit Mcp.Tools.Scaffold;

{ delphi_create: scaffold NEW projects (console/VCL/FMX/package/test) and NEW
  forms (VCL/FMX) remotely. Engine in Lsp.Scaffold. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiCreateParams = class
  private
    FKind: string;
    FDir: string;
    FName: string;
    FProject: string;
    FFormName: string;
    FContent: string;
  public
    [SchemaDescription('What to create: project-console | project-vcl | project-fmx | project-package (a runtime package: .dpk + .dproj, requires rtl; its units go in with kind=unit or add-unit, into the contains clause; it is built to BPL+DCP in its own folder and never installed in the IDE) | project-test (a DUnitX console runner plus its first fixture, green at birth - what delphi_test discovers and runs; DUnitX ships with RAD Studio) | form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule | unit (a plain .pas) | include (a .inc with its content; never registered, used with {$I}). Everything but projects and includes is registered in the project given - except a unit with NO project and an ABSOLUTE dir, created standalone')]
    [Required]
    property Kind: string read FKind write FKind;
    [SchemaDescription('Projects: ABSOLUTE target directory (created if missing). Everything else (unit, form, frame, data module): optional SUBFOLDER of the project, RELATIVE to it and as deep as you like (Dominio\Modelos\Dto) - created if missing, and the unit is registered with that relative path. The folder layout is yours to decide. No absolute paths, no drive, no "..": what you create in a project hangs from that project. Empty = next to the .dpr. kind=unit or include WITHOUT project: the ABSOLUTE folder where the standalone file is created')]
    [RutaDelServidor]
    property Dir: string read FDir write FDir;
    [SchemaDescription('Projects: project name. Forms, frames, data modules and units: unit name (e.g. UClientes)')]
    [Required]
    property Name: string read FName write FName;
    [SchemaDescription('Everything but projects: absolute path of the project .dpr, .dpk or .dproj to register the new unit in (uses of a program, contains of a package). kind=unit may go without it, with an ABSOLUTE dir: the unit is created standalone, listed by no project yet (for a uses split in {$IFDEF} branches, add it to its branch with delphi_edit). kind=include: optional, and dir is then relative to it')]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription('Forms/frames/data modules optional: instance name without the T (default: Form+unit, Frame+unit, DM+unit)')]
    property FormName: string read FFormName write FFormName;
    [SchemaDescription('kind=unit optional: the FULL source of the unit. It is written as it comes (CRLF) and registered in the project in the same call - no need to create an empty skeleton and then rewrite it. Its `unit X;` must match "name", and it must end in `end.`. Without this, a standard empty skeleton is written. kind=include: REQUIRED, the text of the .inc')]
    property Content: string read FContent write FContent;
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
    'buildable .dproj + main form; a runtime PACKAGE: .dpk + .dproj, ' +
    'built to BPL+DCP in its folder, never installed; or a TEST project: a DUnitX ' +
    'console runner with its first fixture, what delphi_test runs) or a NEW form, frame or data module ' +
    '(VCL/FMX: .pas + .dfm/.fmx pair, registered in the .dpr uses - with ' +
    'Application.CreateForm for forms and data modules - and in the .dproj). ' +
    'IDE-equivalent skeletons, CRLF, source encoding follows the IDE''s ' +
    'configured default (UTF-8/ANSI), never overwrites anything. kind=unit ' +
    'creates a plain .pas and registers it in the project (uses of the .dpr ' +
    '+ DCCReference of the .dproj); forms get their Application.CreateForm ' +
    'too. An EXISTING .pas joins a project with delphi_config command=add-unit. ' +
    'kind=unit with NO project and an ABSOLUTE dir creates it STANDALONE (no ' +
    'project lists it yet); kind=include creates a .inc with its content. A ' +
    'uses clause split in {$IFDEF} branches (each ending in its own ";") is ' +
    'never rewritten by add-unit, remove-unit or a rename - it would land in ' +
    'the wrong branch: edit the branch with delphi_edit.';
end;

function TDelphiCreateTool.ExecuteWithParams(const Params: TDelphiCreateParams): string;
var
  K: string;
begin
  K := Params.Kind.Trim.ToLower;
  if K.StartsWith('project-') then
    Result := CreateDelphiProject(Params.Dir, Params.Name, K.Substring(8))
  else if K.StartsWith('form-') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName,
      K.Substring(5), Params.Dir)
  else if K.StartsWith('frame-') or (K = 'datamodule') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName, K,
      Params.Dir)
  else if K = 'unit' then
    Result := CreateDelphiUnit(Params.Project, Params.Name, Params.Content,
      Params.Dir)
  else if K = 'include' then
    Result := CreateDelphiInclude(Params.Project, Params.Name, Params.Content,
      Params.Dir)
  else
    Result := 'RECHAZADO: kind debe ser project-console | project-vcl | project-fmx | project-package | project-test | ' +
      'form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule | unit | include.';
end;

initialization
  TMCPRegistry.RegisterTool('delphi_create',
    function: IMCPTool begin Result := TDelphiCreateTool.Create; end);

end.
