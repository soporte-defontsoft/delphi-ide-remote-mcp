unit MCPServer.Registration;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  MCPServer.Tool.Base,
  MCPServer.Resource.Base,
  MCPServer.Logger;

type
  TMCPToolClass = class of TMCPToolBase;
  
  TMCPToolFactory = reference to function: IMCPTool;
  TMCPResourceFactory = reference to function: IMCPResource;

  TMCPRegistry = class
  private
    class var FTools: TDictionary<string, TMCPToolFactory>;
    class var FResources: TDictionary<string, TMCPResourceFactory>;
    
    class procedure EnsureInitialized;
  public
    class procedure RegisterTool(const Name: string; Factory: TMCPToolFactory);
    class procedure RegisterResource(const URI: string; Factory: TMCPResourceFactory);
    
    class function CreateTool(const Name: string): IMCPTool;
    class function CreateResource(const URI: string): IMCPResource;
    
    class function GetToolNames: TArray<string>;
    class function GetResourceURIs: TArray<string>;
    
    class function HasTool(const Name: string): Boolean;
    class function HasResource(const URI: string): Boolean;
  end;

implementation

uses
  MCPServer.JsonRpcProcessor, // [local change] ERecursoNoExiste: -32002
  Lsp.Texts; // [local change 2026-09-27] los textos, del catalogo

{ TMCPRegistry }

class procedure TMCPRegistry.EnsureInitialized;
begin
  if not Assigned(FTools) then
    FTools := TDictionary<string, TMCPToolFactory>.Create;

  if not Assigned(FResources) then
    FResources := TDictionary<string, TMCPResourceFactory>.Create;
end;

class procedure TMCPRegistry.RegisterTool(const Name: string; Factory: TMCPToolFactory);
begin
  EnsureInitialized;

  FTools.AddOrSetValue(Name, Factory);
  TLogger.Info('Registered tool: ' + Name);
end;

class procedure TMCPRegistry.RegisterResource(const URI: string; Factory: TMCPResourceFactory);
begin
  EnsureInitialized;

  FResources.AddOrSetValue(URI, Factory);
  TLogger.Info('Registered resource: ' + URI);
end;

class function TMCPRegistry.CreateTool(const Name: string): IMCPTool;
var
  Factory: TMCPToolFactory;
begin
  EnsureInitialized;

  if FTools.TryGetValue(Name, Factory) then
    Result := Factory()
  else
    raise Exception.Create(MsgFmt(SR_SYS_TOOL_NOT_FOUND_FMT, [Name]));
end;

class function TMCPRegistry.CreateResource(const URI: string): IMCPResource;
var
  Factory: TMCPResourceFactory;
begin
  EnsureInitialized;

  if FResources.TryGetValue(URI, Factory) then
    Result := Factory()
  else
    raise ERecursoNoExiste.Create(MsgFmt(SR_SYS_RECURSO_NO_EXISTE_FMT, [URI]));
end;

class function TMCPRegistry.GetToolNames: TArray<string>;
begin
  EnsureInitialized;

  Result := FTools.Keys.ToArray;
end;

class function TMCPRegistry.GetResourceURIs: TArray<string>;
begin
  EnsureInitialized;

  Result := FResources.Keys.ToArray;
end;

class function TMCPRegistry.HasTool(const Name: string): Boolean;
begin
  EnsureInitialized;

  Result := FTools.ContainsKey(Name);
end;

class function TMCPRegistry.HasResource(const URI: string): Boolean;
begin
  EnsureInitialized;

  Result := FResources.ContainsKey(URI);
end;

initialization

finalization
  if Assigned(TMCPRegistry.FTools) then
    TMCPRegistry.FTools.Free;
  if Assigned(TMCPRegistry.FResources) then
    TMCPRegistry.FResources.Free;

end.