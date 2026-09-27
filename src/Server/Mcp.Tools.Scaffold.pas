unit Mcp.Tools.Scaffold;

{ delphi_create: scaffold NEW projects (console/VCL/FMX/package/test) and NEW
  forms (VCL/FMX) remotely. Engine in Lsp.Scaffold. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Attributes,
  Lsp.Texts;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

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
    [SchemaDescription(SP_CREATE_KIND)]
    [Required]
    property Kind: string read FKind write FKind;
    [SchemaDescription(SP_CREATE_DIR)]
    [RutaDelServidor]
    property Dir: string read FDir write FDir;
    [SchemaDescription(SP_CREATE_NAME)]
    [Required]
    property Name: string read FName write FName;
    [SchemaDescription(SP_CREATE_PROJECT)]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_CREATE_FORMNAME)]
    property FormName: string read FFormName write FFormName;
    [SchemaDescription(SP_CREATE_CONTENT)]
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
  FDescription := SD_CREATE_CREATE;
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
    Result := MsgText(SR_CREATE_KIND_DEBE_SER_ALL);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_create',
    function: IMCPTool begin Result := TDelphiCreateTool.Create; end);

end.
