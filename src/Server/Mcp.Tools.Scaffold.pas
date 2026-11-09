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
    FAncestor: string;
    FContent: string;
    FEol: string;
    FAutoCreate: string;
  public
    [SchemaDescription(SP_CREATE_KIND)]
    [Required]
    property Kind: string read FKind write FKind;
    [SchemaDescription(SP_CREATE_DIR)]
    [RutaDelServidor]
    [RutaRelativa] // dentro de un proyecto, una subcarpeta suya (relativa)
    property Dir: string read FDir write FDir;
    [SchemaDescription(SP_CREATE_NAME)]
    [Required]
    property Name: string read FName write FName;
    [SchemaDescription(SP_CREATE_PROJECT)]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_CREATE_FORMNAME)]
    property FormName: string read FFormName write FFormName;
    [SchemaDescription(SP_CREATE_ANCESTOR)]
    property Ancestor: string read FAncestor write FAncestor;
    [SchemaDescription(SP_CREATE_CONTENT)]
    [Contenido]
    property Content: string read FContent write FContent;
    [SchemaDescription(SP_CREATE_EOL)]
    property Eol: string read FEol write FEol;
    [SchemaDescription(SP_CREATE_AUTOCREATE)]
    property AutoCreate: string read FAutoCreate write FAutoCreate;
  end;

  TDelphiCreateTool = class(TMCPToolBase<TDelphiCreateParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiCreateParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,     // ParametroQueNoVa: lo que no va con el kind se dice
  Lsp.Puertas,   // EnterFileEdit / LeaveFileEdit: el cerrojo de escritura
  Lsp.Pascal,    // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Settings,  // LeeSiNo: LA gramatica del si/no
  Lsp.Scaffold;

constructor TDelphiCreateTool.Create;
begin
  inherited;
  FName := 'delphi_create';
  FDescription := SD_CREATE_CREATE;
end;

function CrearNucleo(const Params: TDelphiCreateParams): string; forward;

function TDelphiCreateTool.ExecuteWithParams(const Params: TDelphiCreateParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  EnterFileEdit;
  try
    Result := CrearNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function CrearNucleo(const Params: TDelphiCreateParams): string;
const
  // lo que lee cada kind, ademas de kind y name: los kinds de verdad, que la
  // negativa nombra con los que SI lo llevan (decia "goes with: form", un
  // kind que no existe: Opus en Hermes, 1.22.2). name, el de todos, en la
  // lista de cada uno: pegado delante de la lista compuesta, un kind sin otros
  // diria "takes name no parameters" (el delete del changeset lo decia: Hermes,
  // dirigido 1.29b)
  KINDS: array [0 .. 25] of string = (
    'project-console', 'name dir', 'project-vcl', 'name dir', 'project-fmx', 'name dir',
    'project-package', 'name dir', 'project-test', 'name dir', 'project-library', 'name dir',
    'form-vcl', 'name project formname dir ancestor autocreate',
    'form-fmx', 'name project formname dir ancestor autocreate',
    'frame-vcl', 'name project formname dir ancestor', 'frame-fmx', 'name project formname dir ancestor',
    'datamodule', 'name project formname dir autocreate',
    'unit', 'name project content dir eol',
    'include', 'name project content dir eol');
var
  K, Suyos, Sobra, VaCon: string;
  AutoCrea: Boolean;
begin
  K := SinMayusculas(Params.Kind.Trim);
  // lo que no es de este kind se dice (Lsp.Guard.ParametroQueNoVa): content
  // con un proyecto o un form, formname con una unit, se ignoraban y
  // contestaba CREATED con el esqueleto de siempre (septima revision)
  // solo los kinds que EXISTEN: uno que no, lo dice su negativa (CREATE-034),
  // no una tabla que lo daba por bueno (octava revision)
  Sobra := ParametroQueNoVa(K, KINDS,
    ['dir', Params.Dir, '', 'project', Params.Project, '',
     'formname', Params.FormName, '', 'content', Params.Content, '',
     'ancestor', Params.Ancestor, '', 'eol', Params.Eol, '',
     'autocreate', Params.AutoCreate, ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_CREATE_NO_VA_CON_KIND_FMT, [Sobra, Params.Kind.Trim,
      Params.Kind.Trim, Suyos]) + VaCon);
  // sin decirlo, como el IDE: el proyecto lo crea al arrancar
  AutoCrea := True;
  if (Params.AutoCreate.Trim <> '') and not LeeSiNo(Params.AutoCreate, AutoCrea) then
    Exit(MsgFmt(SR_CREATE_AUTOCREATE_NO_ES_SINO_FMT, [Params.AutoCreate.Trim]));
  if K.StartsWith('project-') then
    Result := CreateDelphiProject(Params.Dir, Params.Name, K.Substring(8))
  else if K.StartsWith('form-') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName,
      K.Substring(5), Params.Dir, Params.Ancestor, AutoCrea)
  else if K.StartsWith('frame-') or (K = 'datamodule') then
    Result := CreateDelphiForm(Params.Project, Params.Name, Params.FormName, K,
      Params.Dir, Params.Ancestor, AutoCrea)
  else if K = 'unit' then
    Result := CreateDelphiUnit(Params.Project, Params.Name, Params.Content,
      Params.Dir, Params.Eol)
  else if K = 'include' then
    Result := CreateDelphiInclude(Params.Project, Params.Name, Params.Content,
      Params.Dir, Params.Eol)
  else
    Result := MsgText(SR_CREATE_KIND_DEBE_SER_ALL);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_create',
    function: IMCPTool begin Result := TDelphiCreateTool.Create; end);

end.
